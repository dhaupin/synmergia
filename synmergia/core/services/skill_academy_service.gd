## SkillAcademyService - Skill book upgrades and Skill Academy NPC hub
##
## Procedurally generates skill book items at startup from loaded skills.
## No .tres files needed for skill books — they are runtime items.
## Players spend skill points + consume 4 matching-tier books to upgrade skills.
class_name SkillAcademyService
extends Node

# Singleton
static var instance: SkillAcademyService

## Tier names in display order
const TIER_NAMES: Array = ["common", "rare", "epic", "legendary", "mythic"]

## Tier → upgrade level mapping
const TIER_TO_LEVEL: Dictionary = {
	"common": 1, "rare": 2, "epic": 3, "legendary": 4, "mythic": 5
}

## Books required per upgrade level
const BOOKS_PER_UPGRADE: int = 4

## Gold price for a common-tier skill book at the academy vendor
const COMMON_BOOK_PRICE: int = 100

## In-memory catalog: skill_id → catalog entry
var _catalog: Dictionary = {}

## Runtime player data: player_id → { spent_pts, upgrades }
var _player_data: Dictionary = {}

signal upgrade_applied(player_id: String, skill_id: String, new_level: int)
signal respec_completed(player_id: String, points_refunded: int)

func _ready() -> void:
	instance = self
	_generate_catalog()
	GameLog.info("SkillAcademyService: Catalog generated with %d skills" % _catalog.size())

static func get_instance() -> SkillAcademyService:
	return instance

## Build the skill book catalog from all loaded skills in DataService.
## Called once at startup. No .tres files are created.
func _generate_catalog() -> void:
	_catalog.clear()
	if not DataService:
		GameLog.warn("SkillAcademyService: DataService not available at startup")
		return

	var all_skills: Dictionary = DataService.get_all_skills()
	for skill_id in all_skills:
		var skill_schema: SkillSchema = all_skills[skill_id]
		if not skill_schema is SkillSchema:
			continue
		if not skill_schema.upgradable:
			continue
		_catalog[skill_id] = {
			"schema": skill_schema,
			"display_name": skill_schema.display_name,
			"tiers": TIER_NAMES.duplicate()
		}

## Get all catalog skill IDs
func get_catalog_skill_ids() -> Array:
	return _catalog.keys()

## Get catalog entry for a skill
func get_catalog_entry(skill_id: String) -> Dictionary:
	return _catalog.get(skill_id, {})

## Get the SkillSchema for a skill ID
func get_skill_schema(skill_id: String) -> SkillSchema:
	var entry: Dictionary = _catalog.get(skill_id, {})
	return entry.get("schema", null) as SkillSchema

## Create a runtime SkillBook item for the given skill and tier.
## Used by both the shop (common only) and LootService (any tier).
func create_book(skill_id: String, tier: String) -> SkillBook:
	var entry: Dictionary = _catalog.get(skill_id, {})
	if entry.is_empty():
		GameLog.warn("SkillAcademyService: Unknown skill_id for book: " + skill_id)
		return null

	var schema: SkillSchema = entry.get("schema")
	var display_name: String = entry.get("display_name", "Unknown Skill")
	var upgrade_level: int = TIER_TO_LEVEL.get(tier.to_lower(), 1)

	return SkillBook.create(skill_id, upgrade_level, display_name)

## Create a mythic-tier book for a boss loot drop.
func create_mythic_book(skill_id: String) -> SkillBook:
	return create_book(skill_id, "mythic")

## Purchase a common-tier book from the academy vendor.
## Deducts gold, returns the book item (caller should add to inventory).
func purchase_book(player_id: String, skill_id: String, gold: int) -> Dictionary:
	if gold < COMMON_BOOK_PRICE:
		return {"success": false, "reason": "Not enough gold"}
	if not _catalog.has(skill_id):
		return {"success": false, "reason": "Unknown skill"}
	if not "schema" in _catalog[skill_id]:
		return {"success": false, "reason": "Skill not upgradable"}

	var book: SkillBook = create_book(skill_id, "common")
	if not book:
		return {"success": false, "reason": "Book generation failed"}

	return {
		"success": true,
		"book": book,
		"cost": COMMON_BOOK_PRICE
	}

## Apply an upgrade to a skill for a player.
## Requires: 4 books of the correct tier in inventory + 1 available skill point.
## Books are consumed. Skill point is spent.
func apply_upgrade(
	player_id: String,
	skill_id: String,
	skill_data: CharacterData,
	inventory_books: Array
) -> Dictionary:
	var schema: SkillSchema = get_skill_schema(skill_id)
	if schema == null:
		return {"success": false, "reason": "Skill not found in catalog"}

	var current_level: int = skill_data.get_skill_upgrade_level(skill_id)
	if current_level >= 5:
		return {"success": false, "reason": "Skill already at max upgrade level"}

	var next_level: int = current_level + 1
	var tier: Dictionary = schema.get_upgrade_tier(next_level)
	if tier.is_empty():
		return {"success": false, "reason": "No upgrade tier defined for level %d" % next_level}

	var tier_name: String = tier.get("tier", "common")

	# Check: does player have enough skill points?
	if skill_data.get_available_skill_points() < 1:
		return {"success": false, "reason": "No skill points available"}

	# Count matching books in inventory
	var required_count: int = BOOKS_PER_UPGRADE
	var found_books: Array = []
	var remaining_books: Array = []

	for book in inventory_books:
		if book is SkillBook and book.book_skill_id == skill_id and book.book_upgrade_level == next_level:
			if found_books.size() < required_count:
				found_books.append(book)
			else:
				remaining_books.append(book)
		else:
			remaining_books.append(book)

	if found_books.size() < required_count:
		return {
			"success": false,
			"reason": "Need %d %s books, have %d" % [required_count, tier_name.capitalize(), found_books.size()]
		}

	# Apply upgrade
	var new_upgrades: Dictionary = skill_data.skill_upgrades.duplicate()
	new_upgrades[skill_id] = next_level
	skill_data.skill_upgrades = new_upgrades
	skill_data.spent_skill_points += 1

	upgrade_applied.emit(player_id, skill_id, next_level)

	return {
		"success": true,
		"skill_id": skill_id,
		"new_level": next_level,
		"books_consumed": found_books.size(),
		"remaining_books": remaining_books,
		"skill_points_remaining": skill_data.get_available_skill_points()
	}

## Preview what an upgrade to the next level would look like.
func get_upgrade_preview(skill_id: String, current_level: int) -> Dictionary:
	var schema: SkillSchema = get_skill_schema(skill_id)
	if schema == null:
		return {}

	var next_level: int = current_level + 1
	if next_level > 5:
		return {"maxed": true}

	var tier: Dictionary = schema.get_upgrade_tier(next_level)
	var deltas: Dictionary = tier.get("delta", {})
	var tier_name: String = tier.get("tier", "common")
	var books_required: int = tier.get("books_required", 4)

	return {
		"next_level": next_level,
		"tier": tier_name,
		"books_required": books_required,
		"deltas": deltas,
		"cumulative": schema.get_upgrade_deltas(next_level)
	}

## Full respec for a player.
## WARNING: Clears ALL skill upgrades and refunds skill points.
## Books are consumed and NOT returned. This is intentional.
func respec(player_id: String, skill_data: CharacterData) -> Dictionary:
	if skill_data.skill_upgrades.is_empty():
		return {"success": false, "reason": "No upgrades to reset"}

	var refunded: int = skill_data.spent_skill_points
	skill_data.skill_upgrades.clear()
	skill_data.spent_skill_points = 0

	respec_completed.emit(player_id, refunded)

	return {
		"success": true,
		"points_refunded": refunded,
		"message": "All upgrades reset. Collect your books again to rebuild."
	}

## Load persisted upgrade data for a player (called on login).
func load_player_data(player_id: String, spent_pts: int, upgrades: Dictionary) -> void:
	_player_data[player_id] = {
		"spent_pts": spent_pts,
		"upgrades": upgrades
	}

## Check if the respec warning has been shown (UI-level concern, tracked here for convenience).
func get_player_summary(player_id: String, skill_data: CharacterData) -> Dictionary:
	return {
		"total_upgrade_levels": skill_data.get_total_upgrade_levels(),
		"skill_points_earned": skill_data.get_earned_skill_points(),
		"skill_points_spent": skill_data.spent_skill_points,
		"skill_points_available": skill_data.get_available_skill_points(),
		"upgrades": skill_data.skill_upgrades.duplicate()
	}

## Get all known upgradable skills with their current upgrade level.
func get_skill_upgrade_states(skill_data: CharacterData) -> Dictionary:
	var result: Dictionary = {}
	for skill_id in _catalog:
		var level: int = skill_data.get_skill_upgrade_level(skill_id)
		result[skill_id] = {
			"display_name": _catalog[skill_id].get("display_name", skill_id),
			"current_level": level,
			"maxed": level >= 5,
			"upgradable": level < 5
		}
	return result

## Get the next required tier name for upgrading a skill.
func get_next_tier_name(skill_id: String, current_level: int) -> String:
	var schema: SkillSchema = get_skill_schema(skill_id)
	if schema == null:
		return ""
	var tier: Dictionary = schema.get_upgrade_tier(current_level + 1)
	return tier.get("tier", "")
