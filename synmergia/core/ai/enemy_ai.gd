## EnemyAI - AI state machine for enemies
## Handles IDLE, PATROL, CHASE, COMBAT, FLEE, RETURN states
class_name EnemyAI
extends Node

enum AIState {
	IDLE,
	PATROL,
	CHASE,
	COMBAT,
	FLEE,
	RETURN
}

signal state_changed(from: AIState, to: AIState)
signal target_acquired(target: SynmergiaEntity)
signal target_lost()

@export var state: AIState = AIState.IDLE
@export var aggro_range: float = 15.0
@export var chase_range: float = 25.0
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.5
@export var patrol_speed: float = 2.0
@export var chase_speed: float = 5.0

var _target: SynmergiaEntity = null
var _spawn_position: Vector3 = Vector3.ZERO
var _patrol_target: Vector3 = Vector3.ZERO
var _patrol_wait_time: float = 0.0
var _attack_timer: float = 0.0
var _aggro_timer: float = 0.0

func _ready() -> void:
	var entity: SynmergiaEntity = get_parent()
	if entity:
		_spawn_position = entity.global_position

func _physics_process(delta: float) -> void:
	match state:
		AIState.IDLE:
			_update_idle(delta)
		AIState.PATROL:
			_update_patrol(delta)
		AIState.CHASE:
			_update_chase(delta)
		AIState.COMBAT:
			_update_combat(delta)
		AIState.FLEE:
			_update_flee(delta)
		AIState.RETURN:
			_update_return(delta)

## Check for nearby targets (aggro detection)
func _check_for_targets() -> SynmergiaEntity:
	var entity: SynmergiaEntity = get_parent()
	if not entity:
		return null
	
	var nearby := EntityService.get_entities_in_radius(
		entity.global_position,
		aggro_range,
		SynmergiaEntity.EntityType.PLAYER
	)
	
	for target in nearby:
		if _is_valid_target(target):
			return target
	
	return null

func _is_valid_target(target: SynmergiaEntity) -> bool:
	# Check if dead
	if target.health_component and target.health_component.is_dead():
		return false
	
	# Check if can see (stealth check)
		# Stealth detection
		if target.status_handler:
			var stealth_effect = target.status_handler.get_effect_by_type(StatusEffectData.EffectType.BUFF, "stealth")
			if stealth_effect and stealth_effect.is_active():
				# Check if this enemy can see stealth
				var entity: SynmergiaEntity = get_parent()
				if entity and entity.enemy_data:
					if not entity.enemy_data.see_stealth:
						return false  # Can't see stealthed targets
				else:
					return false  # No enemy_data, assume can't see stealth
	
	# Check faction/enemy status
	if EntityService.is_enemy(get_parent(), target):
		return true
	
	return false

## Set state
func set_state(new_state: AIState) -> void:
	if state == new_state:
		return
	
	var old_state := state
	state = new_state
	state_changed.emit(old_state, new_state)
	
	_match_state_behavior()

func _match_state_behavior() -> void:
	var entity: SynmergiaEntity = get_parent()
	if not entity:
		return
	
	match state:
		AIState.IDLE:
			entity.move_speed = 0
		AIState.PATROL:
			entity.move_speed = patrol_speed
			_patrol_wait_time = 0
		AIState.CHASE:
			entity.move_speed = chase_speed
		AIState.COMBAT:
			entity.move_speed = 0
		AIState.FLEE:
			entity.move_speed = chase_speed * 1.2
		AIState.RETURN:
			entity.move_speed = patrol_speed

## IDLE: Wait and look for targets
func _update_idle(delta: float) -> void:
	var entity: SynmergiaEntity = get_parent()
	if not entity:
		return
	
	# Look for targets
	var target: Variant = _check_for_targets()
	if target:
		_set_target(target)
		set_state(AIState.CHASE)
		return
	
	# Occasionally start patrolling
	if randf() < 0.01:  # 1% chance per frame... adjust for real use
		_start_patrol()

## PATROL: Wander around spawn point
func _update_patrol(delta: float) -> void:
	var entity: SynmergiaEntity = get_parent()
	if not entity:
		return
	
	# Check for targets first
	var target: Variant = _check_for_targets()
	if target:
		_set_target(target)
		set_state(AIState.CHASE)
		return
	
	# Wait at patrol point
	if _patrol_wait_time > 0:
		_patrol_wait_time -= delta
		return
	
	# Move to patrol target
	var dir := (_patrol_target - entity.global_position).normalized()
	var dist: float = entity.global_position.distance_to(_patrol_target)
	
	if dist < 1.0:
		# Reached patrol point, wait
		_patrol_wait_time = randf_range(2.0, 5.0)
		_set_new_patrol_target()
	else:
		entity.move_direction = dir

func _start_patrol() -> void:
	_set_new_patrol_target()
	set_state(AIState.PATROL)

func _set_new_patrol_target() -> void:
	var entity: SynmergiaEntity = get_parent()
	if not entity:
		return
	
	# Random point within patrol radius
	var angle := randf() * TAU
	var dist: float = randf() * 10.0 + 5.0
	_patrol_target = _spawn_position + Vector3(cos(angle), 0, sin(angle)) * dist

## CHASE: Move toward target
func _update_chase(delta: float) -> void:
	var entity: SynmergiaEntity = get_parent()
	if not entity or not _target:
		set_state(AIState.RETURN)
		return
	
	# Check if target is still valid
	if not is_instance_valid(_target):
		_clear_target()
		set_state(AIState.RETURN)
		return
	
	var dist: float = entity.global_position.distance_to(_target.global_position)
	
	# In attack range? Start combat
	if dist <= attack_range:
		set_state(AIState.COMBAT)
		return
	
	# Target out of chase range? Give up
	if dist > chase_range:
		_clear_target()
		set_state(AIState.RETURN)
		return
	
	# Move toward target
	var dir := (_target.global_position - entity.global_position).normalized()
	entity.move_direction = dir

## COMBAT: Attack target
func _update_combat(delta: float) -> void:
	var entity: SynmergiaEntity = get_parent()
	if not entity or not _target:
		set_state(AIState.RETURN)
		return
	
	# Check if target is dead or invalid
	if not is_instance_valid(_target) or (entity.health_component and entity.health_component.is_dead()):
		_clear_target()
		set_state(AIState.RETURN)
		return
	
	var dist: float = entity.global_position.distance_to(_target.global_position)
	
	# Target out of range? Chase again
	if dist > attack_range:
		set_state(AIState.CHASE)
		return
	
	# Face target
	entity.look_at(_target.global_position, Vector3.UP)
	
	# Attack
	_attack_timer -= delta
	if _attack_timer <= 0:
		_perform_attack()
		_attack_timer = attack_cooldown

func _perform_attack() -> void:
	if not _target or not is_instance_valid(_target):
		return
	
	var entity: SynmergiaEntity = get_parent()
	if not entity:
		return
	
	# Add threat
	if entity.aggro_component and _target.aggro_component:
		_target.aggro_component.add_threat(entity, 100)
	
	# Deal damage
	var damage := entity.attack_power
	_target.health_component.take_damage(damage, entity)

## FLEE: Run away from target
func _update_flee(delta: float) -> void:
	var entity: SynmergiaEntity = get_parent()
	if not entity or not _target:
		set_state(AIState.RETURN)
		return
	
	# Run away from target
	var dir := (entity.global_position - _target.global_position).normalized()
	entity.move_direction = dir
	
	# Stop fleeing when far enough
	var dist: float = entity.global_position.distance_to(_target.global_position)
	if dist > chase_range:
		_clear_target()
		set_state(AIState.RETURN)

## RETURN: Go back to spawn
func _update_return(delta: float) -> void:
	var entity: SynmergiaEntity = get_parent()
	if not entity:
		return
	
	var dist: float = entity.global_position.distance_to(_spawn_position)
	
	# Back at spawn?
	if dist < 1.0:
		set_state(AIState.IDLE)
		return
	
	# Move toward spawn
	var dir := (_spawn_position - entity.global_position).normalized()
	entity.move_direction = dir

## Set target
func _set_target(new_target: SynmergiaEntity) -> void:
	if _target == new_target:
		return
	
	_target = new_target
	
	if new_target:
		target_acquired.emit(new_target)
	else:
		target_lost.emit()

func _clear_target() -> void:
	_target = null
	target_lost.emit()

## Force engage target (called by EventBus when aggro'd)
func engage_target(target: SynmergiaEntity) -> void:
	if _is_valid_target(target):
		_set_target(target)
		set_state(AIState.CHASE)

## Handle being damaged
func on_damaged(source: SynmergiaEntity) -> void:
	if state == AIState.IDLE or state == AIState.PATROL:
		# Become aware
		engage_target(source)

## Handle target death
func on_target_death() -> void:
	_clear_target()
	set_state(AIState.RETURN)
