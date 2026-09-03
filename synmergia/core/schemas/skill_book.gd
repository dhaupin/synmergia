## SkillBook - A consumable item that upgrades a skill
## Instantiated at runtime by SkillAcademyService — not a .tres file
extends Item

class_name SkillBook
var book_skill_id: String = ""
var book_upgrade_level: int = 0  # 1 = common, 2 = rare, ..., 5 = mythic

## Create a runtime skill book instance.
## skill_id: the skill it upgrades (e.g. "human_ambush")
## upgrade_level: 1-5 (maps to tier: common/rare/epic/legendary/mythic)
## skill_display_name: used for the item's display name
static func create(skill_id: String, upgrade_level: int, skill_display_name: String) -> SkillBook:
	var tier_names := ["", "common", "rare", "epic", "legendary", "mythic"]
	var tier_roman := ["", "I", "II", "III", "IV", "V"]
	var tier: String = tier_names[upgrade_level] if upgrade_level in tier_names else "common"

	var book := SkillBook.new()
	book.book_skill_id = skill_id
	book.book_upgrade_level = upgrade_level
	book.id = "book_%s_%s" % [skill_id, tier]
	book.display_name = "Manual of %s %s" % [skill_display_name, tier_roman[upgrade_level]]
	book.description = "A weathered manual containing techniques to enhance %s. Consume 4 of the same tier to upgrade." % skill_display_name
	book.item_category = ItemCategory.SKILL_BOOK
	var rarities := [Rarity.COMMON, Rarity.COMMON, Rarity.RARE, Rarity.EPIC, Rarity.LEGENDARY, Rarity.MYTHIC]
	book.rarity = rarities[upgrade_level] if upgrade_level < rarities.size() else Rarity.COMMON
	book.soulbound = false
	book.stack_size = 1
	book.current_stack = 1
	book.sell_price = 10 * upgrade_level
	book.buy_price = 100 * upgrade_level
	book.unique = false
	book.bind_on_pickup = false
	return book
