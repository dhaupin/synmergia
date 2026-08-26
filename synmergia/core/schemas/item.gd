## Item - Equipment and consumable definition
## Base schema for all items
class_name Item
extends Resource

enum ItemCategory {
	WEAPON,       # Swords, bows, staves, daggers
	ARMOR,        # Head, chest, legs, feet, gloves, shoulders
	ACCESSORY,    # Rings, necklaces, belts, cloaks
	CONSUMABLE,   # Potions, food, scrolls, reagents
	RESOURCE,     # Crafting materials, gathering
	GEM,          # Socketable gems, crafting ingredient
	EVENT,        # Limited time event items
	DWELLING,     # Housing items, furniture, decorations
	MISC          # Everything else (quest items, vanity, garbage loot)
}

enum WeaponType {
	NONE,
	SWORD,
	AXE,
	MACE,
	DAGGER,
	BOW,
	CROSSBOW,
	STAFF,
	WAND,
	SPEAR,
	SHIELD
}

enum ArmorType {
	NONE,
	CLOTH,
	LEATHER,
	MAIL,
	PLATE
}

enum AccessoryType {
	NONE,
	RING,
	NECKLACE,
	BRACELET,
	CLOAK,
	BELT
}

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY
}

enum EquipSlot {
	NONE,
	HEAD,
	CHEST,
	LEGS,
	FEET,
	GLOVES,
	SHOULDERS,
	MAIN_HAND,
	OFF_HAND,
	RING_1,
	RING_2,
	NECKLACE,
	CLOAK
}

@export var id: String = ""
@export var display_name: String = "Item"
@export var description: String = ""
@export var icon_path: String = ""

# Classification
@export var item_category: ItemCategory = ItemCategory.MISC
@export var rarity: Rarity = Rarity.COMMON
@export var equip_slot: EquipSlot = EquipSlot.NONE

# Subcategory (for organization)
@export var weapon_type: WeaponType = WeaponType.NONE
@export var armor_type: ArmorType = ArmorType.NONE
@export var accessory_type: AccessoryType = AccessoryType.NONE

# Stack & Trade
@export var stack_size: int = 1
@export var current_stack: int = 1  # Runtime quantity (for stacked items)
@export var is_bound: bool = false  # Binds on pickup
@export var bind_on_equip: bool = false
@export var unique: bool = false  # Only one can be owned

# Weight & Encumbrance
@export var weight: float = 0.0  # Weight per unit (ores heavier than leather)

# Economy
@export var sell_price: int = 0
@export var buy_price: int = 0
@export var item_level: int = 1

# Requirements
@export var required_level: int = 1
@export var required_class: String = ""  # Empty = all classes
@export var required_strength: int = 0
@export var required_agility: int = 0
@export var required_intelligence: int = 0

# Stats (for equipment)
@export var stats: Dictionary = {
	# "strength": 10,
	# "agility": 5,
	# "health": 100,
	# "mana": 50
}

# Primary stats (main benefit)
@export var primary_stats: Dictionary = {}

# Secondary stats (bonus effects)
@export var secondary_stats: Dictionary = {}

# Equipment-specific
@export var weapon_damage_min: int = 0
@export var weapon_damage_max: int = 0
@export var attack_speed: float = 1.0  # Attacks per second
@export var armor_value: int = 0

# Consumable-specific
@export var use_skill_id: String = ""  # Skill to execute on use
@export var cooldown: float = 0.0
@export var duration: float = 0.0  # For buffs that consume item

# Cosmetic
@export var model_path: String = ""
@export var color: Color = Color.WHITE

# Dwelling/Housing specific
@export var dwelling_category: String = ""  # furniture, decoration, lighting, storage, etc.
@export var dwelling_size: Vector3 = Vector3.ONE  # Size in housing grid units
@export var is_placeable: bool = false
@export var placement_zones: Array[String] = []  # Where it can be placed

# Event specific
@export var event_id: String = ""  # Links to event_system event
@export var event_expires: bool = false
@export var event_end_date: String = ""  # ISO date when item expires

# Consumable specific
@export var use_skill_id: String = ""  # Skill to execute on use
@export var cooldown: float = 0.0
@export var duration: float = 0.0  # For buffs that consume item
@export var buff_effects: Array[Dictionary] = []  # Buffs granted by consumable

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Check if entity can use this item
func can_use(entity: Entity) -> bool:
	if entity.level < required_level:
		return false
	if required_class != "" and entity.character_class != required_class:
		return false
	if required_strength > 0 and entity.strength < required_strength:
		return false
	if required_agility > 0 and entity.agility < required_agility:
		return false
	if required_intelligence > 0 and entity.intelligence < required_intelligence:
		return false
	return true

## Can this item be equipped?
func can_equip() -> bool:
	return equip_slot != EquipSlot.NONE

## Get total stat contribution
func get_total_stats() -> Dictionary:
	var total: Dictionary = {}
	for key in stats:
		total[key] = stats[key]
	for key in primary_stats:
		if total.has(key):
			total[key] += primary_stats[key]
		else:
			total[key] = primary_stats[key]
	return total

## Get total weight for this stack
func get_total_weight() -> float:
	return weight * current_stack

## Get rarity color for UI
func get_rarity_color() -> Color:
	match rarity:
		Rarity.COMMON:
			return Color.WHITE
		Rarity.UNCOMMON:
			return Color.GREEN
		Rarity.RARE:
			return Color.BLUE
		Rarity.EPIC:
			return Color(0.8, 0.2, 1.0)  # Purple
		Rarity.LEGENDARY:
			return Color(1.0, 0.6, 0.0)  # Orange
	return Color.WHITE

## Create a copy with quantity
func create_instance(quantity: int = 1) -> Item:
	var instance := duplicate()
	instance.id = id + "_instance_%d" % [randi()]
	instance.set("stack_size", mini(quantity, stack_size))
	return instance

## Get display info for UI
func get_info() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"rarity": Rarity.keys()[rarity],
		"rarity_color": get_rarity_color(),
		"item_type": ItemType.keys()[item_type],
		"stats": get_total_stats(),
		"required_level": required_level
	}
