## HealthComponent - HP management and death handling
## Attached to entities that have health
class_name HealthComponent
extends Node

signal health_changed(current: int, maximum: int, delta: int)
signal health_depleted()
signal died(killer: Entity)
signal resurrecting(respawn_time: float)
signal respawned()

@export var max_health: int = 100
@export var base_health: int = 100
@export var health_regen: float = 1.0  # HP per second
@export var health_regen_combat: float = 0.0  # HP per second in combat

var current_health: int
var _is_dead: bool = false
var _respawn_timer: float = 0.0
var _respawn_time: float = 10.0
var _bind_position: Vector3 = Vector3.ZERO
var _killer: Entity = null

func _ready() -> void:
	current_health = max_health

## Take damage
func take_damage(amount: int, source: Entity = null, damage_type: String = "physical") -> int:
	if _is_dead:
		return 0
	
	# Apply armor/mitigation (placeholder)
	var mitigated := 0  # TODO: Calculate from armor
	var actual_damage := max(1, amount - mitigated)
	
	current_health = max(0, current_health - actual_damage)
	health_changed.emit(current_health, max_health, -actual_damage)
	
	# Emit combat events
	EventBus.damage_dealt.emit(source, get_parent(), actual_damage, damage_type)
	
	if current_health <= 0:
		die(source)
	
	return actual_damage

## Heal
func heal(amount: int, source: Entity = null) -> int:
	if _is_dead:
		return 0
	
	var actual_heal := min(amount, max_health - current_health)
	current_health += actual_heal
	health_changed.emit(current_health, max_health, actual_heal)
	
	return actual_heal

## Get percentage health
func get_health_percent() -> float:
	if max_health <= 0:
		return 0.0
	return float(current_health) / float(max_health)

## Is entity dead?
func is_dead() -> bool:
	return _is_dead

## Die
func die(killer: Entity = null) -> void:
	if _is_dead:
		return
	
	_is_dead = true
	_killer = killer
	current_health = 0
	
	health_depleted.emit()
	EventBus.entity_died.emit(get_parent(), killer)
	
	# Start respawn timer
	_start_respawn()

## Start respawn process
func _start_respawn() -> void:
	_respawn_timer = _respawn_time
	resurrecting.emit(_respawn_time)

## Set respawn position
func set_bind_position(position: Vector3) -> void:
	_bind_position = position

## Get bind position
func get_bind_position() -> Vector3:
	return _bind_position

## Respawn immediately (admin/quest)
func force_respawn() -> void:
	_do_respawn()

func _process(delta: float) -> void:
	if _is_dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0:
			_do_respawn()
	else:
		# Health regen
		var regen := health_regen
		# TODO: Check in_combat and use combat regen
		
		if regen > 0 and current_health < max_health:
			var heal_amount := int(regen * delta)
			if heal_amount > 0:
				heal(heal_amount)

func _do_respawn() -> void:
	_is_dead = false
	current_health = max_health
	_respawn_timer = 0.0
	
	# Move to respawn position
	var entity: Entity = get_parent()
	entity.global_position = _bind_position
	
	respawned.emit()
	EventBus.entity_spawned.emit(entity)

## Set max health
func set_max_health(new_max: int) -> void:
	var old_max := max_health
	max_health = new_max
	
	# Scale current health proportionally
	if old_max > 0:
		current_health = int(float(current_health) / old_max * max_health)
	
	health_changed.emit(current_health, max_health, 0)
