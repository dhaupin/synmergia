## Entity - Base class for all game entities
## Characters, NPCs, enemies all inherit from this
class_name SynmergiaEntity
extends Node

signal health_changed(current: int, maximum: int)
signal died(killer)  # Entity type omitted to avoid circular reference during parsing
signal stat_changed(stat: String, value: int)
signal state_changed(new_state: String)

enum EntityType {
	NONE = 0,
	PLAYER = 1,
	ENEMY = 2,
	NPC = 4,
	DESTRUCTIBLE = 8,
	OBJECT = 16,
	TELEPORT = 32,
	LOOT = 64,
	ALL = 0xFFFFFFFF
}

enum Relation {
	NEUTRAL,
	FRIENDLY,
	HOSTILE
}

enum ControllerType {
	HUMAN,      # Real human player
	AGENT,      # AI agent
	NPC,        # Scripted NPC
	HOSTILE_AI  # Enemy AI
}

@export var entity_id: String = ""
@export var display_name: String = "Entity"
@export var level: int = 1
@export var entity_type: EntityType = EntityType.NPC
@export var relation: Relation = Relation.NEUTRAL

# Controller type - for fairness system (HUMAN and AGENT are equals)
@export var controller_type: ControllerType = ControllerType.NPC
@export var connector_id: String = ""  # Which connector controls this (for agents)

# Stats stored as dictionary
var stats: Dictionary = {
	"strength": 10,
	"agility": 10,
	"intelligence": 10,
	"vitality": 10,
	"endurance": 10,
	"wisdom": 10,
	"damage_multiplier": 1.0,
	"defense_multiplier": 1.0,
	"armor_multiplier": 1.0,
	"movement_speed_multiplier": 1.0
}

# Resources
var max_health: int = 100
var current_health: int = 100
var max_mana: int = 100
var current_mana: int = 100
var max_stamina: float = 100.0
var current_stamina: float = 100.0

# Status effects (using Array to avoid circular dependency with StatusEffect)
var status_effects: Array = []
var is_dead: bool = false

# Team (for friendly fire)
var team_id: int = 0

# Respawn state
var respawn_point: Vector3 = Vector3.ZERO  # Last bound position
var respawn_ankh_id: String = ""           # Bound ankh ID
var pending_respawn: bool = false         # Waiting to respawn

# Faction
var faction_id: String = ""

# Species (using untyped var to avoid circular dependency with Species schema)
var species_id: String = ""
var species = null

func _ready() -> void:
	_calculate_max_resources()
	current_health = max_health
	current_mana = max_mana
	health_changed.emit(current_health, max_health)

func _calculate_max_resources() -> void:
	max_health = 100 + (stats.vitality * 10)
	max_mana = 100 + (stats.intelligence * 8)
	max_stamina = 100.0 + (stats.endurance * 5)

## STATS

func get_stat(stat_name: String) -> int:
	return stats.get(stat_name, 0)

func set_stat(stat_name: String, value: int) -> void:
	stats[stat_name] = value
	stat_changed.emit(stat_name, value)
	if stat_name == "vitality":
		_calculate_max_resources()

func add_stat(stat_name: String, amount: int) -> void:
	set_stat(stat_name, get_stat(stat_name) + amount)

## SPECIES

func apply_species(new_species) -> void:
	if new_species == null:
		return
	
	species = new_species
	species_id = new_species.id
	
	# Apply stat modifiers
	for stat in new_species.stat_modifiers:
		var modifier := new_species.stat_modifiers[stat] as int
		stats[stat] = stats.get(stat, 10) + modifier
	
	# Apply resource modifiers
	max_health = int(max_health * new_species.health_modifier)
	max_mana = int(max_mana * new_species.mana_modifier)
	max_stamina = max_stamina * new_species.stamina_modifier
	
	# Apply movement speed modifier
	stats["movement_speed_multiplier"] = new_species.speed_modifier
	
	_calculate_max_resources()
	
	# GameLogger.debug("Entity: Applied species %s to %s" % [species_id, display_name])

## HEALTH

func take_damage(amount: int, source = null) -> int:
	if is_dead:
		return 0
	
	var damage := _calculate_damage_received(amount)
	current_health = max(0, current_health - damage)
	health_changed.emit(current_health, max_health)
	
	if current_health <= 0:
		die(source)
	
	return damage

func heal(amount: int) -> void:
	if is_dead:
		return
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

func heal_percentage(percent: float) -> void:
	heal(int(max_health * percent))

func is_alive() -> bool:
	return not is_dead and current_health > 0

func _calculate_damage_received(amount: int) -> int:
	var defense := get_defense()
	var reduction := float(defense) / (defense + 100.0)
	return int(amount * (1.0 - reduction))

## MANA

func use_mana(amount: int) -> bool:
	if current_mana >= amount:
		current_mana -= amount
		return true
	return false

func restore_mana(amount: int) -> void:
	current_mana = min(max_mana, current_mana + amount)

## STAMINA

func use_stamina(amount: float) -> bool:
	if current_stamina >= amount:
		current_stamina -= amount
		return true
	return false

func restore_stamina(amount: float) -> void:
	current_stamina = min(max_stamina, current_stamina + amount)

## DEFENSE & OFFENSE

func get_defense() -> int:
	return stats.vitality * 2

func get_magic_resistance() -> int:
	return stats.wisdom * 2

func get_attack_power() -> int:
	return stats.strength * 2

func get_spell_power() -> int:
	return stats.intelligence * 2

func get_attack_speed() -> float:
	return 1.0 + (stats.agility * 0.01)

func get_crit_chance() -> float:
	return 0.05 + (stats.agility * 0.003)

func get_crit_multiplier() -> float:
	return 1.5

## STATUS EFFECTS

func apply_status_effect(effect) -> void:
	if effect.is_expired():
		return
	status_effects.append(effect)
	effect.apply(self)
	effect.effect_expired.connect(_on_status_effect_expired)

func _on_status_effect_expired(effect) -> void:
	status_effects.erase(effect)

func remove_status_effect(effect) -> void:
	if status_effects.has(effect):
		effect.remove(self)
		status_effects.erase(effect)

func has_status_effect(effect_type: String) -> bool:
	for effect in status_effects:
		if effect.effect_type == effect_type:
			return true
	return false

func clear_all_status_effects() -> void:
	for effect in status_effects:
		effect.remove(self)
	status_effects.clear()

## DEATH

func die(killer = null) -> void:
	if is_dead:
		return
	is_dead = true
	clear_all_status_effects()
	died.emit(killer)

func resurrect(health_percent: float = 0.5) -> void:
	is_dead = false
	current_health = int(max_health * health_percent)
	current_mana = int(max_mana * health_percent)
	health_changed.emit(current_health, max_health)

## UTILITY

func is_in_range(target, range: float) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return global_position.distance_to(target.global_position) <= range

func can_attack(target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if is_dead or target.is_dead:
		return false
	if team_id != 0 and team_id == target.team_id:
		return false  # Same team, no friendly fire
	return true

## SERIALIZATION

func get_entity_data() -> Dictionary:
	return {
		"entity_id": entity_id,
		"display_name": display_name,
		"level": level,
		"stats": stats,
		"health": current_health,
		"mana": current_mana,
		"faction_id": faction_id,
		"species_id": species_id,
		"position": {
			"x": global_position.x,
			"y": global_position.y,
			"z": global_position.z
		},
		"rotation": rotation.y
	}

func load_entity_data(data: Dictionary) -> void:
	entity_id = data.get("entity_id", entity_id)
	display_name = data.get("display_name", display_name)
	level = data.get("level", level)
	stats = data.get("stats", stats)
	faction_id = data.get("faction_id", faction_id)
	species_id = data.get("species_id", species_id)
	_calculate_max_resources()
	
	current_health = data.get("health", max_health)
	current_mana = data.get("mana", max_mana)
	
	var pos_data = data.get("position", {})
	if not pos_data.is_empty():
		global_position = Vector3(
			pos_data.get("x", 0),
			pos_data.get("y", 0),
			pos_data.get("z", 0)
		)
	
	rotation.y = data.get("rotation", 0)
