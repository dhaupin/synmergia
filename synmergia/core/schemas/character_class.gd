## CharacterClass - Player class definition
## Defines class-specific stats, skills, and resource types
class_name CharacterClass
extends Resource

enum ResourceType {
	MANA,        # Standard mana pool
	ENERGY,      # Fast regen, no max (like Rogue)
	RAGE,        # Builds from damage, decays out of combat
	RUNIC_POWER, # WoW DK style
	CHI          # Monk style
}

enum Role {
	GM = 0,         ## Reserved. Never assigned via .tres. Guarded at login.
	TANK = 1,       ## Guardian, Bulwark, Warden
	DPS_MELEE = 2,  ## Stalker, Ranger, Infiltrator (ranged physical)
	DPS_RANGED = 3, ## Runesmith, Enchanter, Operative (ranged caster)
	SUPPORT = 4    ## Cleric, Shaman, Seer, Temporalist, Conduit, Overclocker
}

@export var id: String = ""
@export var display_name: String = "Warrior"
@export var description: String = ""
@export var icon_path: String = ""

# Classification
@export var role: Role = Role.DPS_MELEE
@export var resource_type: ResourceType = ResourceType.MANA

# Base stats (these are added on top of species modifiers)
@export var base_stats: Dictionary = {
	"strength": 12,
	"agility": 10,
	"intelligence": 8,
	"vitality": 10,
	"endurance": 10,
	"wisdom": 8
}

# Stat growth per level
@export var stat_growth: Dictionary = {
	"strength": 2,
	"agility": 1,
	"intelligence": 1,
	"vitality": 2,
	"endurance": 1,
	"wisdom": 1
}

# Resource settings
@export var base_resource: int = 100  # Starting mana/energy/rage
@export var resource_per_level: int = 10  # How much resource gained per level
@export var resource_regen_per_second: float = 5.0  # Out of combat regen
@export var resource_regen_combat: float = 1.0  # In combat regen (often lower)

# Combat settings
@export var base_attack_power: int = 10
@export var attack_power_per_level: int = 2
@export var base_spell_power: int = 5
@export var spell_power_per_level: int = 1

# Starting skills
@export var starting_skills: Array[String] = []
@export var skill_tree_unlocks: Dictionary = {
	# "level": ["skill_id1", "skill_id2"]
}

# Respec (skill reset) cost in gold at the Skill Academy
@export var respec_cost_gold: int = 500

# Equipment restrictions
@export var can_use_melee_weapons: bool = true
@export var can_use_ranged_weapons: bool = true
@export var can_use_staves: bool = false
@export var can_use_armor: Dictionary = {
	"cloth": true,
	"leather": true,
	"mail": true,
	"plate": false
}

# Visual
@export var model_override: String = ""  # Override species model
@export var default_weapon_path: String = ""
@export var class_specific_animation_set: String = ""

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Calculate stat at given level
func calculate_stat(stat: String, level: int) -> int:
	var base: int = int(base_stats.get(stat, 10))
	var growth: float = float(stat_growth.get(stat, 1))
	return base + (growth * (level - 1))

## Calculate resource at given level
func calculate_resource(level: int) -> int:
	return base_resource + (resource_per_level * (level - 1))

## Get resource regen based on in_combat status
func get_resource_regen(in_combat: bool) -> float:
	if in_combat:
		return resource_regen_combat
	return resource_regen_per_second

## Get skills unlocked at level
func get_skills_for_level(level: int) -> Array[String]:
	var skills: Array[String] = []
	
	# Add starting skills
	for skill_id in starting_skills:
		skills.append(skill_id)
	
	# Add skills from skill tree
	for unlock_level in skill_tree_unlocks.keys():
		if level >= unlock_level as int:
			for skill_id in skill_tree_unlocks[unlock_level]:
				if not skills.has(skill_id):
					skills.append(skill_id)
	
	return skills

## Check if class can equip item
func can_equip_item(item) -> bool:
	if not item.can_equip():
		return true  # Non-equippable items are fine
	
	# Weapon check
	if item.equip_slot == "main_hand" or item.equip_slot == "off_hand":
		if item.item_category == "weapon":
			match item.equip_slot:
				"main_hand":
					var weapon_type = item.get("weapon_type", "sword")
					if weapon_type == "staff" and not can_use_staves:
						return false
					if not can_use_melee_weapons and weapon_type in ["sword", "axe", "mace"]:
						return false
					if not can_use_ranged_weapons and weapon_type in ["bow", "crossbow", "gun"]:
						return false
	
	# Armor check
	if item.equip_slot in ["head", "chest", "legs", "feet", "gloves", "shoulders"]:
		var armor_type = item.get("armor_type", "leather")
		if not can_use_armor.get(armor_type, false):
			return false
	
	return true

## Get display info for UI
func get_info() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"role": Role.keys()[role],
		"resource_type": ResourceType.keys()[resource_type],
		"base_stats": base_stats,
		"starting_skills": starting_skills
	}
