## SkillBook - A consumable item that upgrades a skill
##
## Extends Item (not Resource): books are real inventory items -- they
## drop from loot tables, sit in inventories, and render in UIs. The
## old `extends Resource` crashed at runtime: create() assigns id /
## display_name / item_category etc., which only exist on Item.
extends Item
class_name SkillBook

## Runtime metadata (not exported: books are runtime-generated items,
## the academy catalog + loot rolls are the only producers).
var book_skill_id: String = ""
var book_upgrade_level: int = 0


static func create(skill_id: String, upgrade_level: int, skill_display_name: String) -> SkillBook:
	var tier_names := ["", "common", "rare", "epic", "legendary", "mythic"]
	var tier_roman := ["", "I", "II", "III", "IV", "V"]
	var tier: String = tier_names[upgrade_level] if upgrade_level >= 0 and upgrade_level < tier_names.size() else "common"

	# Load the script at runtime to avoid "Identifier not found: SkillBook" at parse time
	var script := load("res://core/schemas/skill_book.gd")
	var book = script.new() as SkillBook
	if book == null:
		return null
	book.book_skill_id = skill_id
	book.book_upgrade_level = upgrade_level
	book.id = "book_%s_%s" % [skill_id, tier]
	book.display_name = "Manual of %s %s" % [skill_display_name, tier_roman[upgrade_level]]
	book.description = "A weathered manual containing techniques to enhance %s. Consume 4 of the same tier to upgrade." % skill_display_name
	book.soulbound = false
	book.stack_size = 1
	book.current_stack = 1
	book.sell_price = 10 * upgrade_level
	book.buy_price = 100 * upgrade_level
	book.unique = false
	book.bind_on_pickup = false
	book.item_category = Item.ItemCategory.SKILL_BOOK
	return book
