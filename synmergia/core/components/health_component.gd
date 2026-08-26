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
	
	# Check for interrupt (before applying damage)
	var entity: Entity = get_parent()
	if entity.combat_component:
		entity.combat_component.on_damage_taken(amount, source, damage_type)
	
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
	
	# Stop all combat state
	var entity: Entity = get_parent()
	if entity.combat_component:
		entity.combat_component.interrupt()
	
	# Create corpse
	_create_corpse(killer)
	
	health_depleted.emit()
	EventBus.entity_died.emit(entity, killer)
	
	# Start respawn timer
	_start_respawn()

## Create corpse entity
var _corpse: Node3D = null

func _create_corpse(killer: Entity) -> void:
	var entity: Entity = get_parent()
	
	# TODO: Load corpse scene
	# _corpse = load("res://scenes/corpse.tscn").instantiate()
	# _corpse.global_position = entity.global_position
	# _corpse.setup(entity, killer)
	# get_tree().root.add_child(_corpse)
	
	# Enable corpse looting
	# Corpse loot should be: dropped items + portion of carried gold

## Remove corpse
func _remove_corpse() -> void:
	if _corpse:
		_corpse.queue_free()
		_corpse = null

## Set respawn location options
enum RespawnLocation {
	BIND_POINT,      # Last bound location
	NEAR_CORPSE,     # Near death location
	NEAR_PARTY,      # Near party members
	CUSTOM           # Specific location
}

@export var default_respawn_location: RespawnLocation = RespawnLocation.BIND_POINT
@export var respawn_location: Vector3 = Vector3.ZERO  # For CUSTOM

## Get available respawn locations
func get_respawn_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var entity: Entity = get_parent()
	
	# Always available: Bind point
	options.append({
		"location": RespawnLocation.BIND_POINT,
		"name": "Bind Point",
		"position": _bind_position,
		"delay": 0
	})
	
	# Always available: Near corpse (if corpse exists)
	if _corpse:
		options.append({
			"location": RespawnLocation.NEAR_CORPSE,
			"name": "Near Corpse",
			"position": entity.global_position,
			"delay": _respawn_time * 0.5  # Faster respawn
		})
	
	return options

## Respawn at specific location
func respawn_at(location: RespawnLocation, custom_position: Vector3 = Vector3.ZERO) -> void:
	match location:
		RespawnLocation.BIND_POINT:
			_do_respawn_at(_bind_position)
		RespawnLocation.NEAR_CORPSE:
			var entity: Entity = get_parent()
			_do_respawn_at(entity.global_position)
		RespawnLocation.CUSTOM:
			_do_respawn_at(custom_position)
		_:
			_do_respawn_at(_bind_position)

func _do_respawn_at(position: Vector3) -> void:
	_remove_corpse()
	_is_dead = false
	current_health = max_health
	
	var entity: Entity = get_parent()
	entity.global_position = position
	
	respawned.emit()
	EventBus.entity_spawned.emit(entity)

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
