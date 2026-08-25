## Entity - Base class for all game entities
## Characters, NPCs, enemies all inherit from this
class_name Entity
extends Node3D

signal health_changed(current: int, maximum: int)
signal died(killer: Entity)
signal stat_changed(stat: String, value: int)
signal state_changed(new_state: String)

@export var entity_id: String = ""
@export var display_name: String = "Entity"
@export var level: int = 1

# Stats stored as dictionary
var stats: Dictionary = {
	"strength": 10,
	"agility": 10,
	"intelligence": 10,
	"vitality": 10,
	"endurance": 10,
	"wisdom": 10
}

# Resources
var max_health: int = 100
var current_health: int = 100
var max_mana: int = 100
var current_mana: int = 100
var max_stamina: float = 100.0
var current_stamina: float = 100.0

# Status effects
var status_effects: Array[StatusEffect] = []
var is_dead: bool = false

# Team (for friendly fire)
var team_id: int = 0

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

## HEALTH

func take_damage(amount: int, source: Entity = null) -> int:
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

func apply_status_effect(effect: StatusEffect) -> void:
	if effect.is_expired():
		return
	status_effects.append(effect)
	effect.apply(self)
	effect.effect_expired.connect(_on_status_effect_expired)

func _on_status_effect_expired(effect: StatusEffect) -> void:
	status_effects.erase(effect)

func remove_status_effect(effect: StatusEffect) -> void:
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

func die(killer: Entity = null) -> void:
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

func is_in_range(target: Entity, range: float) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return global_position.distance_to(target.global_position) <= range

func can_attack(target: Entity) -> bool:
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
