## Item - Equipment and consumable definition
## Base schema for all items
extends Resource
class_name Item

enum ItemCategory {
	WEAPON,       # Swords, bows, staves, daggers
	ARMOR,        # Head, chest, legs, feet, gloves, shoulders
	ACCESSORY,    # Rings, necklaces, belts, cloaks
	CONSUMABLE,   # Potions, food, scrolls, reagents
	RESOURCE,     # Crafting materials, gathering
	GEM,          # Socketable gems, crafting ingredient
	EVENT,        # Limited time event items
	DWELLING,     # Housing items, furniture, decorations
	MISC,          # Everything else (quest items, vanity, garbage loot)
	SKILL_BOOK    # Skill book: consumes to upgrade a skill
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
	LEGENDARY,
	MYTHIC
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
@export var is_bound: bool = false  # Binds on pickup (runtime state)
@export var bind_on_equip: bool = false
@export var bind_on_pickup: bool = false  # Auto-bind when picked up
@export var soulbound: bool = false  # Permanently bound to account/character
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

# Durability
@export var max_durability: int = 100  # 0 = indestructible
@export var current_durability: int = 100  # Runtime value (not exported, set on init)
@export var durability_loss_rate: float = 1.0  # Durability per minute of combat at rate 1.0
@export var can_repair: bool = true

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

# Consumable effects (also used for self-rez)
@export var buff_effects: Array[Dictionary] = []  # Buffs granted by consumable

# Self-rez specific
@export var is_self_rez_item: bool = false  # This item can self-resurrect
@export var self_rez_health_percent: float = 0.5  # Health % restored on self-rez
@export var self_rez_mana_percent: float = 0.5  # Mana % restored on self-rez
@export var self_rez_cooldown: float = 300.0  # Cooldown before can use again

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")
	# Initialize durability for equipment
	if max_durability > 0 and current_durability == 0:
		current_durability = max_durability
	# Set default durability loss rate based on item type
	if durability_loss_rate == 1.0:  # Only if not explicitly set
		match item_category:
			ItemCategory.WEAPON:
				durability_loss_rate = 1.0  # Full rate
			ItemCategory.ARMOR:
				durability_loss_rate = 0.8  # Slower than weapons
			ItemCategory.ACCESSORY:
				durability_loss_rate = 0.5  # Accessories decay slowly

## Check if entity can use this item
func can_use(entity) -> bool:
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
		Rarity.MYTHIC:
			return Color(1.0, 0.0, 0.5)  # Magenta
	return Color.WHITE

## Create a copy with quantity
func create_instance(quantity: int = 1) -> Item:
	var instance := duplicate()
	instance.id = id + "_instance_%d" % [randi()]
	instance.current_stack = mini(quantity, stack_size)
	return instance

## Get display info for UI
func get_info() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"rarity": Rarity.keys()[rarity],
		"rarity_color": get_rarity_color(),
		"item_type": ItemCategory.keys()[item_category],
		"stats": get_total_stats(),
		"required_level": required_level
	}

## Get durability percentage (0.0 to 1.0)
func get_durability_percent() -> float:
	if max_durability <= 0:
		return 1.0  # Indestructible
	return float(current_durability) / float(max_durability)

## Is item broken?
func is_broken() -> bool:
	if max_durability <= 0:
		return false  # Indestructible
	return current_durability <= 0

## Get effective damage (0 if broken)
func get_effective_damage_min() -> int:
	if is_broken():
		return 0
	return weapon_damage_min

## Get effective damage (0 if broken)
func get_effective_damage_max() -> int:
	if is_broken():
		return 0
	return weapon_damage_max

## Get effective armor value (0 if broken)
func get_effective_armor_value() -> int:
	if is_broken():
		return 0
	return armor_value

## Get effective stat value (0 if broken)
func get_effective_stat(stat_name: String) -> int:
	if is_broken():
		return 0
	return stats.get(stat_name, 0)

## Get all effective stats (0 if broken)
func get_effective_stats() -> Dictionary:
	if is_broken():
		return {}
	return get_total_stats()

## Can item be equipped (not broken)?
func can_equip() -> bool:
	return equip_slot != EquipSlot.NONE and not is_broken()

## Apply durability loss from combat (returns actual amount lost)
func apply_combat_durability_loss(delta_minutes: float) -> int:
	if max_durability <= 0 or current_durability <= 0:
		return 0  # Indestructible or already broken

	var loss := int(delta_minutes * durability_loss_rate)
	if loss <= 0:
		return 0

	var old_durability := current_durability
	current_durability = maxi(0, current_durability - loss)
	return old_durability - current_durability

## Repair item to max durability
func repair() -> bool:
	if not can_repair:
		return false
	if max_durability <= 0:
		return false  # Indestructible
	current_durability = max_durability
	return true

## Repair item to specific amount
func repair_to(amount: int) -> bool:
	if not can_repair:
		return false
	if max_durability <= 0:
		return false
	current_durability = clampi(amount, 0, max_durability)
	return true

func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"description": description,
		"icon_path": icon_path,
		"item_category": item_category,
		"rarity": rarity,
		"equip_slot": equip_slot,
		"weapon_type": weapon_type,
		"armor_type": armor_type,
		"accessory_type": accessory_type,
		"stack_size": stack_size,
		"current_stack": current_stack,
		"is_bound": is_bound,
		"bind_on_equip": bind_on_equip,
		"bind_on_pickup": bind_on_pickup,
		"soulbound": soulbound,
		"unique": unique,
		"weight": weight,
		"sell_price": sell_price,
		"buy_price": buy_price,
		"item_level": item_level,
		"required_level": required_level,
		"required_class": required_class,
		"required_strength": required_strength,
		"required_agility": required_agility,
		"required_intelligence": required_intelligence,
		"stats": stats,
		"primary_stats": primary_stats,
		"secondary_stats": secondary_stats,
		"weapon_damage_min": weapon_damage_min,
		"weapon_damage_max": weapon_damage_max,
		"attack_speed": attack_speed,
		"armor_value": armor_value,
		"max_durability": max_durability,
		"current_durability": current_durability,
		"durability_loss_rate": durability_loss_rate,
		"can_repair": can_repair,
		"use_skill_id": use_skill_id,
		"cooldown": cooldown,
		"duration": duration,
		"model_path": model_path,
		"color": color,
		"dwelling_category": dwelling_category,
		"dwelling_size": dwelling_size,
		"is_placeable": is_placeable,
		"placement_zones": placement_zones,
		"event_id": event_id,
		"event_expires": event_expires,
		"event_end_date": event_end_date,
		"buff_effects": buff_effects,
		"is_self_rez_item": is_self_rez_item,
		"self_rez_health_percent": self_rez_health_percent,
		"self_rez_mana_percent": self_rez_mana_percent,
		"self_rez_cooldown": self_rez_cooldown
	}

static func from_dict(data: Dictionary) -> Item:
	var item := Item.new()
	item.id = data.get("id", "")
	item.display_name = data.get("display_name", "Item")
	item.description = data.get("description", "")
	item.icon_path = data.get("icon_path", "")
	item.item_category = data.get("item_category", ItemCategory.MISC)
	item.rarity = data.get("rarity", Rarity.COMMON)
	item.equip_slot = data.get("equip_slot", EquipSlot.NONE)
	item.weapon_type = data.get("weapon_type", WeaponType.NONE)
	item.armor_type = data.get("armor_type", ArmorType.NONE)
	item.accessory_type = data.get("accessory_type", AccessoryType.NONE)
	item.stack_size = int(data.get("stack_size", 1))
	item.current_stack = int(data.get("current_stack", 1))
	item.is_bound = data.get("is_bound", false)
	item.bind_on_equip = data.get("bind_on_equip", false)
	item.bind_on_pickup = data.get("bind_on_pickup", false)
	item.soulbound = data.get("soulbound", false)
	item.unique = data.get("unique", false)
	item.weight = float(data.get("weight", 0.0))
	item.sell_price = int(data.get("sell_price", 0))
	item.buy_price = int(data.get("buy_price", 0))
	item.item_level = int(data.get("item_level", 1))
	item.required_level = int(data.get("required_level", 1))
	item.required_class = data.get("required_class", "")
	item.required_strength = int(data.get("required_strength", 0))
	item.required_agility = int(data.get("required_agility", 0))
	item.required_intelligence = int(data.get("required_intelligence", 0))
	item.stats = data.get("stats", {})
	item.primary_stats = data.get("primary_stats", {})
	item.secondary_stats = data.get("secondary_stats", {})
	item.weapon_damage_min = int(data.get("weapon_damage_min", 0))
	item.weapon_damage_max = int(data.get("weapon_damage_max", 0))
	item.attack_speed = float(data.get("attack_speed", 1.0))
	item.armor_value = int(data.get("armor_value", 0))
	item.max_durability = int(data.get("max_durability", 100))
	item.current_durability = int(data.get("current_durability", 100))
	item.durability_loss_rate = float(data.get("durability_loss_rate", 1.0))
	item.can_repair = data.get("can_repair", true)
	item.use_skill_id = data.get("use_skill_id", "")
	item.cooldown = float(data.get("cooldown", 0.0))
	item.duration = float(data.get("duration", 0.0))
	item.model_path = data.get("model_path", "")
	item.color = data.get("color", Color.WHITE)
	item.dwelling_category = data.get("dwelling_category", "")
	item.dwelling_size = data.get("dwelling_size", Vector3.ONE)
	item.is_placeable = data.get("is_placeable", false)
	item.placement_zones = data.get("placement_zones", [])
	item.event_id = data.get("event_id", "")
	item.event_expires = data.get("event_expires", false)
	item.event_end_date = data.get("event_end_date", "")
	item.buff_effects = data.get("buff_effects", [])
	item.is_self_rez_item = data.get("is_self_rez_item", false)
	item.self_rez_health_percent = float(data.get("self_rez_health_percent", 0.5))
	item.self_rez_mana_percent = float(data.get("self_rez_mana_percent", 0.5))
	item.self_rez_cooldown = float(data.get("self_rez_cooldown", 300.0))
	return item
