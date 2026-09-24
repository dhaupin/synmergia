## EnemyData - Enemy/NPC template definition
## Base schema for enemy templates
extends Resource
class_name EnemyData

const LootTableResolver = preload("res://core/schemas/loot_table_resolver.gd")

enum EnemyType {
	NORMAL,
	ELITE,
	CHAMPION,
	BOSS,
	WORLD_BOSS,
	RAID_BOSS
}

@export var id: String = ""
@export var display_name: String = "Enemy"
@export var description: String = ""

# Classification
@export var enemy_type: EnemyType = EnemyType.NORMAL
@export var level: int = 1
@export var faction: String = "hostile"
@export var species_id: String = ""  # Links to Species for faction relationships

# Stats (base values)
@export var health: int = 100
@export var mana: int = 0
@export var stamina: int = 50

@export var strength: int = 10
@export var agility: int = 10
@export var intelligence: int = 5
@export var vitality: int = 10

# Combat stats
@export var attack_power: int = 10
@export var spell_power: int = 5
@export var armor: int = 5
@export var resistance: int = 0

# Attack settings
@export var attack_range: float = 2.0
@export var attack_speed: float = 1.0  # Attacks per second
@export var move_speed: float = 4.0

# AI settings
@export var aggro_range: float = 15.0  # Detection radius
@export var chase_range: float = 25.0  # How far enemy will chase
@export var wander_range: float = 5.0  # How far from spawn point they'll wander
@export var see_stealth: bool = false  # Can detect invisible targets

# Behavior flags
@export var is_aggressive: bool = true   # Attacks on sight
@export var is_passive: bool = false     # Only attacks when hit
@export var is_dummy: bool = false       # Training dummy: no retaliation, no loot, no rewards
@export var is_elite: bool = false
@export var is_boss: bool = false
@export var is_social: bool = true       # Calls for help when attacked

# Loot
@export var loot_table_id: String = ""
@export var gold_min: int = 0
@export var gold_max: int = 10
@export var xp_reward: int = 10

# Skills
@export var skills: Array[String] = []  # Skill IDs

# Visual
@export var model_path: String = ""
@export var icon_path: String = ""
@export var scale: float = 1.0
@export var animation_set: String = ""

# Respawn
@export var respawn_time: float = 60.0  # Seconds
@export var despawn_time: float = 0.0   # 0 = never despawn

# Difficulty scaling
@export var difficulty_modifier: float = 1.0

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Get scaled stats based on level
func get_scaled_stat(base_value: int, level_override: int = -1) -> int:
	var lvl := level_override if level_override > 0 else level
	var scale_factor := 1.0 + (lvl - 1) * 0.1  # 10% increase per level
	return int(base_value * scale_factor * difficulty_modifier)

## Get scaled health
func get_scaled_health() -> int:
	return get_scaled_stat(health)

## Get scaled damage
func get_scaled_damage(lvl_override: int = -1) -> int:
	return get_scaled_stat(attack_power, lvl_override)

## Create actual stats dictionary for spawning
func get_stats_for_level(lvl_override: int = -1) -> Dictionary:
	return {
		"health": get_scaled_stat(health, lvl_override),
		"mana": get_scaled_stat(mana, lvl_override),
		"stamina": get_scaled_stat(stamina, lvl_override),
		"strength": get_scaled_stat(strength, lvl_override),
		"agility": get_scaled_stat(agility, lvl_override),
		"intelligence": get_scaled_stat(intelligence, lvl_override),
		"vitality": get_scaled_stat(vitality, lvl_override),
		"attack_power": get_scaled_damage(lvl_override),
		"spell_power": get_scaled_stat(spell_power, lvl_override),
		"armor": get_scaled_stat(armor, lvl_override),
		"resistance": get_scaled_stat(resistance, lvl_override)
	}

## Check if this is a boss
func is_boss_type() -> bool:
	return enemy_type == EnemyType.WORLD_BOSS or enemy_type == EnemyType.RAID_BOSS or is_boss

## Get loot drop
func roll_loot() -> Dictionary:
	var loot := {
		"gold": randi() % (gold_max - gold_min + 1) + gold_min,
		"xp": xp_reward,
		"items": []
	}

	# Roll against loot table if configured. loot_table_id is a bare
	# table id ("loot_slime_basic"), the same convention every consumer
	# uses; resolve it through the data directory, then tolerate a full
	# res:// path for any direct-path authoring.
	if not loot_table_id.is_empty():
		var table = LootTableResolver.load_table(loot_table_id)
		if table != null:
			var roll_result: Dictionary = table.roll_drop()
			loot["items"] = roll_result.get("items", [])
			if roll_result.get("currency"):
				loot["gold"] += roll_result["currency"].get("gold", 0)
	return loot

## Get display info for UI
func get_info() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"level": level,
		"type": EnemyType.keys()[enemy_type],
		"is_boss": is_boss_type(),
		"health": get_scaled_health()
	}
