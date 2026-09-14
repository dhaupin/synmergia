## SkillAcademyService - Skill book upgrades and Skill Academy NPC hub
##
## Procedurally generates skill book items at startup from loaded skills.
## No .tres files needed for skill books -- they are runtime items.
## Players spend skill points + consume 4 matching-tier books to upgrade skills.
extends Node

const SkillBook = preload("res://core/schemas/skill_book.gd")
const CharacterData = preload("res://core/schemas/character_data.gd")
const SkillSchema = preload("res://core/schemas/skill.gd")
const DictStore = preload("res://adapters/persistence/dict_store.gd")
# Singleton
static var instance: SkillAcademyService

## Tier names in display order
const TIER_NAMES: Array = ["common", "rare", "epic", "legendary", "mythic"]

## Tier -> upgrade level mapping
const TIER_TO_LEVEL: Dictionary = {
	"common": 1, "rare": 2, "epic": 3, "legendary": 4, "mythic": 5
}

## Books required per upgrade level
const BOOKS_PER_UPGRADE: int = 4

## Gold price for a common-tier skill book at the academy vendor
const COMMON_BOOK_PRICE: int = 100

## Respec cost: base gold + gold per skill point being refunded
const RESPEC_BASE_COST: int = 500
const RESPEC_GOLD_PER_POINT: int = 20

## In-memory catalog: skill_id -> catalog entry
var _catalog: Dictionary = {}

## Runtime player data: player_id -> { spent_pts, upgrades }
var _player_data: Dictionary = {}

signal upgrade_applied(player_id: String, skill_id: String, new_level: int)
signal respec_completed(player_id: String, points_refunded: int)
signal signature_selected(player_id: String, signature_id: String, is_free: bool)

func _ready() -> void:
	instance = self
	_generate_catalog()
	GameLog.info("SkillAcademyService: Catalog generated with %d skills" % _catalog.size())

static func singleton() -> SkillAcademyService:
	return instance

## Build the skill book catalog from all loaded skills in DataService.
## Called once at startup. No .tres files are created.
func _generate_catalog() -> void:
	_catalog.clear()
	if not DataService:
		GameLog.warn("SkillAcademyService: DataService not available at startup")
		return

	var all_skills: Array = DataService.get_all_skills()
	for skill_schema in all_skills:
		if not skill_schema is SkillSchema:
			continue
		if not skill_schema.upgradable:
			continue
		_catalog[skill_schema.id] = {
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

## ============================================================================
## STAT REQUIREMENT CHECKS
## ============================================================================

## Check if player meets stat requirement for an upgrade tier
func _check_stat_requirement(schema: SkillSchema, tier: Dictionary, skill_data: CharacterData) -> Dictionary:
	var required_stat: String = tier.get("min_stat", "")
	var required_value: int = tier.get("min_stat_value", 0)

	# No stat required
	if required_stat == "" or required_value == 0:
		return {"meets_requirement": true}

	# Get player's stat value (base + allocated)
	var player_stat_value: int = skill_data.get_stat_total(required_stat)

	return {
		"meets_requirement": player_stat_value >= required_value,
		"stat": required_stat,
		"required": required_value,
		"current": player_stat_value
	}

## Check all player stats for what upgrade levels are achievable
func check_available_upgrades(skill_id: String, skill_data: CharacterData) -> Dictionary:
	var schema: SkillSchema = get_skill_schema(skill_id)
	if schema == null:
		return {}

	var result := {
		"skill_id": skill_id,
		"current_level": skill_data.get_skill_upgrade_level(skill_id),
		"available_tiers": []
	}

	var current := skill_data.get_stat_total("strength")  # placeholder - get all stats
	var all_stats := skill_data.get_all_stats_with_allocated()

	# Check each tier
	for tier in schema.upgrade_tiers:
		var stat_check := _check_stat_requirement(schema, tier, skill_data)
		result["available_tiers"].append({
			"level": tier.get("level", 0),
			"tier": tier.get("tier", ""),
			"stat_requirement_met": stat_check.get("meets_requirement", true),
			"required_stat": stat_check.get("stat", ""),
			"required_value": stat_check.get("required", 0),
			"current_value": stat_check.get("current", 0)
		})

	return result

## Apply an upgrade to a skill for a player.
## Requires: 4 books of the correct tier in inventory + 1 available skill point + stat requirements.
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

	# Check: does player meet stat requirements?
	var stat_check := _check_stat_requirement(schema, tier, skill_data)
	if not stat_check.get("meets_requirement", true):
		return {
			"success": false,
			"reason": "Requires %s %d (you have %d)" % [
				stat_check.get("stat", "?").capitalize(),
				stat_check.get("required", 0),
				stat_check.get("current", 0)
			]
		}

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
## Books are consumed and NOT returned. Gold is deducted.
func respec(
	player_id: String,
	skill_data: CharacterData,
	gold: int,
	inventory: Node
) -> Dictionary:
	if skill_data.skill_upgrades.is_empty():
		return {"success": false, "reason": "No upgrades to reset"}

	var refunded: int = skill_data.spent_skill_points
	var cost: int = get_respec_cost(refunded)
	if gold < cost:
		return {"success": false, "reason": "Not enough gold (need %d)" % cost}

	if inventory and "remove_gold" in inventory:
		inventory.remove_gold(cost)
	elif inventory and inventory.inventory_component and "remove_gold" in inventory.inventory_component:
		inventory.inventory_component.remove_gold(cost)

	skill_data.skill_upgrades.clear()
	skill_data.spent_skill_points = 0

	respec_completed.emit(player_id, refunded)

	return {
		"success": true,
		"points_refunded": refunded,
		"cost": cost,
		"message": "Respec complete. %d points refunded. Collect your books again." % refunded
	}

## Load persisted upgrade data for a player (called on login).
func load_player_data(player_id: String, spent_pts: int, upgrades: Dictionary) -> void:
	_player_data[player_id] = {
		"spent_pts": spent_pts,
		"upgrades": upgrades
	}

## Check if the respec warning has been shown (UI-level concern, tracked here for convenience).
## Calculate the gold cost to respec a player with spent_points spent.
func get_respec_cost(spent_points: int) -> int:
	if spent_points <= 0:
		return 0
	return RESPEC_BASE_COST + (spent_points * RESPEC_GOLD_PER_POINT)

## ============================================================================
## STAT ALLOCATION RESPEC
## ============================================================================

## Cost to respec stats: similar to skill respec
const STAT_RESPEC_BASE_COST: int = 500
const STAT_RESPEC_GOLD_PER_POINT: int = 20

func get_stat_respec_cost(points_to_reset: int) -> int:
	if points_to_reset <= 0:
		return 0
	return STAT_RESPEC_BASE_COST + (points_to_reset * STAT_RESPEC_GOLD_PER_POINT)

## Preview stat respec - check what skill upgrades would be affected
func preview_stat_respec(skill_data: CharacterData) -> Dictionary:
	var current_stats := skill_data.get_all_stats_with_allocated()
	var affected_skills := []
	var total_points := skill_data.get_total_allocated_points()

	# Check all upgradable skills
	for skill_id in _catalog.keys():
		var schema: SkillSchema = get_skill_schema(skill_id)
		if schema == null:
			continue

		var current_level: int = skill_data.get_skill_upgrade_level(skill_id)
		if current_level <= 0:
			continue

		# Check if reducing stats would downgrade this skill
		for tier in schema.upgrade_tiers:
			var tier_level: int = tier.get("level", 0)
			if tier_level > current_level:
				continue  # Not currently at this tier

			var required_stat: String = tier.get("min_stat", "")
			var required_value: int = tier.get("min_stat_value", 0)

			if required_stat == "" or required_value == 0:
				continue

			# If we reset all allocated points, what's the base stat?
			var base_stat := skill_data.get_stat_total(required_stat) - skill_data.get_allocated_points(required_stat)
			if base_stat < required_value:
				affected_skills.append({
					"skill_id": skill_id,
					"display_name": schema.display_name,
					"current_level": current_level,
					"downgrade_to": tier_level - 1,
					"required_stat": required_stat,
					"required_value": required_value,
					"new_value_after_respec": base_stat
				})
				break  # Only report highest affected tier

	return {
		"total_allocated_points": total_points,
		"estimated_cost": get_stat_respec_cost(total_points),
		"affected_skills": affected_skills,
		"has_warnings": not affected_skills.is_empty()
	}

## Execute stat respec - reset all allocated stat points
func execute_stat_respec(
	player_id: String,
	skill_data: CharacterData,
	inventory,
	gold: int
) -> Dictionary:
	var total_points := skill_data.get_total_allocated_points()
	if total_points <= 0:
		return {"success": false, "reason": "No stat points to reset"}

	var cost := get_stat_respec_cost(total_points)
	if gold < cost:
		return {"success": false, "reason": "Not enough gold (need %d)" % cost}

	# Check for skill downgrade warnings
	var preview: Dictionary = preview_stat_respec(skill_data)
	var downgrades: Array = preview.get("affected_skills", [])

	# Apply gold cost
	if inventory and "remove_gold" in inventory:
		inventory.remove_gold(cost)
	elif inventory and inventory.inventory_component and "remove_gold" in inventory.inventory_component:
		inventory.inventory_component.remove_gold(cost)

	# Reset allocated stats
	for stat in skill_data.allocated_stats.keys():
		skill_data.allocated_stats[stat] = 0

	# Apply skill downgrades
	var downgraded_skills := []
	for downgrade in downgrades:
		var skill_id: String = downgrade.get("skill_id", "")
		var new_level: int = downgrade.get("downgrade_to", 0)
		if new_level < 0:
			new_level = 0
		skill_data.skill_upgrades[skill_id] = new_level
		downgraded_skills.append({
			"skill_id": skill_id,
			"new_level": new_level
		})

	skill_data.total_stat_respecs += 1

	return {
		"success": true,
		"points_reset": total_points,
		"cost": cost,
		"downgraded_skills": downgraded_skills,
		"message": "Stat respec complete. %d points refunded. %d skills downgraded." % [total_points, downgraded_skills.size()]
	}

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

## Signature Selection ================================================================

## Get all 3 signature skill IDs for a class
func get_class_signatures(class_id: String) -> Array[String]:
	var signatures: Array[String] = []
	var all_skills: Array = DataService.get_all_skills()
	for skill_schema in all_skills:
		if not skill_schema is SkillSchema:
			continue
		if skill_schema.required_class == class_id and not skill_schema.upgradable:
			signatures.append(skill_schema.id)
	return signatures

## Get signature schema by ID
func get_signature_schema(skill_id: String) -> SkillSchema:
	var entry: Dictionary = _catalog.get(skill_id, {})
	return entry.get("schema", null) as SkillSchema

## Change player's active signature
func change_signature(
	player_id: String,
	skill_data: CharacterData,
	new_signature_id: String,
	player_level: int,
	gold: int,
	inventory: Node
) -> Dictionary:
	# Validate level requirement
	if player_level < 10:
		return {"success": false, "reason": "Must be level 10+ to select a signature"}

	# Validate the signature belongs to the player's class
	var class_signatures: Array[String] = get_class_signatures(skill_data.class_id)
	if not class_signatures.has(new_signature_id):
		return {"success": false, "reason": "Invalid signature for your class"}

	# Check if already selected
	if skill_data.active_signature == new_signature_id:
		return {"success": false, "reason": "Signature already active"}

	# Check gold cost
	var cost: int = skill_data.get_signature_change_cost()
	if gold < cost:
		return {"success": false, "reason": "Not enough gold (need %d)" % cost}

	# Deduct gold
	if inventory and "remove_gold" in inventory:
		inventory.remove_gold(cost)
	elif inventory and inventory.inventory_component and "remove_gold" in inventory.inventory_component:
		inventory.inventory_component.remove_gold(cost)

	# Update character data
	var old_signature: String = skill_data.active_signature
	skill_data.active_signature = new_signature_id
	skill_data.signature_switches += 1

	signature_selected.emit(player_id, new_signature_id, skill_data.signature_switches == 1)

	return {
		"success": true,
		"old_signature": old_signature,
		"new_signature": new_signature_id,
		"cost": cost,
		"is_free": skill_data.signature_switches == 1,
		"message": "Signature changed to %s!" % new_signature_id
	}

## Get player's signature info
func get_signature_info(skill_data: CharacterData, player_level: int) -> Dictionary:
	var class_sigs: Array[String] = get_class_signatures(skill_data.class_id)
	var available_sigs: Array[Dictionary] = []

	for sig_id in class_sigs:
		var schema: SkillSchema = get_signature_schema(sig_id)
		if schema:
			available_sigs.append({
				"skill_id": sig_id,
				"display_name": schema.display_name,
				"description": schema.description,
				"is_active": skill_data.active_signature == sig_id,
				"is_locked": player_level < 10
			})

	return {
		"class_id": skill_data.class_id,
		"active_signature": skill_data.active_signature,
		"available_signatures": available_sigs,
		"signature_switches": skill_data.signature_switches,
		"change_cost": skill_data.get_signature_change_cost(),
		"is_free": skill_data.signature_switches == 0,
		"can_change": player_level >= 10 and skill_data.active_signature != "",
		"must_select": player_level >= 10 and skill_data.active_signature == ""
	}

## == Persistence ============================================================

const _KV_PREFIX: String = "skill_academy:"

func _load_state() -> void:
	var store := DictStore.new()
	_player_data = {}
	for key in store.all_keys():
		if key.begins_with(_KV_PREFIX):
			var player_id = key.substr(_KV_PREFIX.length())
			_player_data[player_id] = store.get_value(key)

func _persist_player_data(player_id: String) -> void:
	var store := DictStore.new()
	if _player_data.has(player_id):
		store.set_value(_KV_PREFIX + player_id, _player_data[player_id])
	else:
		store.erase(_KV_PREFIX + player_id)
