## CombatSystem - Manages combat interactions, skills, and hit detection
## Free-form combat system inspired by RYL2
extends Node

const Skill = preload("res://core/combat/skill.gd")
const StatusEffect = preload("res://core/entities/status_effect.gd")
signal skill_executed(caster: Entity, skill: Skill, targets: Array)
signal skill_hit(caster: Entity, target: Entity, skill: Skill, damage: int)
signal skill_missed(caster: Entity, skill: Skill)
signal damage_dealt(damager: Entity, target: Entity, amount: int, skill: Skill)
signal entity_died(victim: Entity, killer: Entity)

var registered_entities: Dictionary = {}
var active_hitboxes: Array[HitboxData] = []
var combo_trackers: Dictionary = {}  # entity_id -> ComboTracker

class HitboxData:
	var owner_id: int
	var position: Vector3
	var size: float
	var skill: Skill
	var start_time: float
	var duration: float
	var team_id: int
	var hit_entities: Array[int]  # Entity IDs already hit

func _physics_process(_delta: float) -> void:
	_process_hitboxes(_delta)
	_process_combos(_delta)

## ENTITY MANAGEMENT

func register_entity(entity: Entity) -> void:
	registered_entities[entity.entity_id] = entity
	entity.died.connect(_on_entity_died)
	combo_trackers[entity.entity_id] = ComboTracker.new()

func unregister_entity(entity: Entity) -> void:
	registered_entities.erase(entity.entity_id)
	combo_trackers.erase(entity.entity_id)
	entity.died.disconnect(_on_entity_died)

func get_entity(entity_id: String) -> Entity:
	return registered_entities.get(entity_id)

func _on_entity_died(entity: Entity, killer: Entity) -> void:
	entity_died.emit(entity, killer)

## SKILL EXECUTION

func execute_skill(caster: Node, skill: Skill, target: Node = null, ground_position: Vector3 = Vector3.ZERO) -> Dictionary:
	if not skill.can_cast(caster):
		return {"success": false, "reason": "cannot_cast"}
	
	# Execute skill
	var result := skill.execute(caster, target, ground_position)
	
	if result.success:
		skill_executed.emit(caster, skill, result.targets_hit)
		
		# Track combo
		if "entity_id" in caster and caster.entity_id in combo_trackers:
			combo_trackers[caster.entity_id].record_skill(skill)
		
		# Create hitbox if applicable
		if skill.hitbox_size > 0:
			create_hitbox(caster, skill, target, ground_position)
	
	return result

func create_hitbox(caster: Node, skill: Skill, target: Node, ground_position: Vector3) -> void:
	var hitbox := HitboxData.new()
	hitbox.owner_id = caster.entity_id if "entity_id" in caster and caster.entity_id else -1
	hitbox.skill = skill
	hitbox.team_id = caster.team_id if "team_id" in caster else 0 if "team_id" in caster else 0
	hitbox.hit_entities = []
	hitbox.start_time = Time.get_ticks_msec() / 1000.0
	hitbox.duration = skill.animation_duration * 0.5  # Hitbox active for half animation
	
	# Calculate hitbox position
	if skill.is_ground_targeted and ground_position != Vector3.ZERO:
		hitbox.position = ground_position
	elif target:
		hitbox.position = target.global_position
	else:
		# Position in front of caster
		var forward: Vector3 = -caster.global_transform.basis.z
		hitbox.position = caster.global_position + forward * skill.hitbox_offset.z + Vector3(0, skill.hitbox_offset.y, 0)
	
	hitbox.size = skill.aoe_radius if skill.aoe_radius > 0 else skill.hitbox_size
	
	active_hitboxes.append(hitbox)

func _process_hitboxes(_delta: float) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	
	for hitbox in active_hitboxes:
		# Check if hitbox expired
		if current_time - hitbox.start_time > hitbox.duration:
			active_hitboxes.erase(hitbox)
			continue
		
		# Find entities in hitbox
		var hit_entities := get_entities_in_hitbox(hitbox)
		
		for entity in hit_entities:
			# Check if already hit
			if entity.entity_id in hitbox.hit_entities:
				continue
			
			# Check team (no friendly fire)
			if entity.team_id == hitbox.team_id and hitbox.team_id != 0:
				continue
			
			# Check if already dead
			if not entity.is_alive():
				continue
			
			# Apply hit
			hitbox.hit_entities.append(entity.entity_id)
			_apply_hit(hitbox, entity)

func get_entities_in_hitbox(hitbox: HitboxData) -> Array:
	var entities_in_range: Array = []
	
	for entity_id in registered_entities:
		var entity: Entity = registered_entities[entity_id]
		
		if not is_instance_valid(entity):
			continue
		
		if entity.global_position.distance_to(hitbox.position) <= hitbox.size:
			entities_in_range.append(entity)
	
	return entities_in_range

func _apply_hit(hitbox: HitboxData, target: Entity) -> void:
	var caster := get_entity(str(hitbox.owner_id)) if hitbox.owner_id != -1 else null
	
	# Calculate and apply damage
	var damage: int = 0
	if caster:
		damage = hitbox.skill.calculate_damage(caster, target)
	
	target.take_damage(damage, caster)
	
	# Emit signals
	if caster:
		skill_hit.emit(caster, target, hitbox.skill, damage)
		damage_dealt.emit(caster, target, damage, hitbox.skill)
	
	# Apply additional effects from skill
	_apply_skill_effects(hitbox.skill, caster, target)

func _apply_skill_effects(skill: Skill, caster: Entity, target: Entity) -> void:
	# Apply DoT if skill has duration
	if skill.is_dot:
		_apply_dot(caster, target, skill)
	
	# Apply CC effects
	if skill.crowd_control_type != "":
		_apply_cc(skill, caster, target)
	
	# Apply movement effects
	if skill.teleport_distance > 0:
		_apply_teleport(caster, target, skill)

func _apply_dot(caster: Entity, target: Entity, skill: Skill) -> void:
	# Create and apply DoT effect
	var effect := DoTEffect.new()
	effect.damage_per_tick = skill.damage / int(skill.dot_duration / skill.dot_tick_rate)
	effect.tick_rate = skill.dot_tick_rate
	effect.total_duration = skill.dot_duration
	effect.source = caster
	
	target.apply_status_effect(effect)

func _apply_cc(skill: Skill, caster: Entity, target: Entity) -> void:
	var effect := skill.create_slow_effect(caster) if skill.crowd_control_type == "slow" else \
		skill.create_stun_effect(caster) if skill.crowd_control_type == "stun" else \
		skill.create_root_effect(caster)
	
	target.apply_status_effect(effect)

func _apply_teleport(caster: Entity, _target: Entity, skill: Skill) -> void:
	var forward: Vector3 = -caster.global_transform.basis.z
	forward.y = 0
	caster.global_position += forward * skill.teleport_distance

## COMBO SYSTEM

func _process_combos(_delta: float) -> void:
	for entity_id in combo_trackers:
		var tracker: Node = combo_trackers[entity_id]
		tracker._physics_process(_delta)

func get_combo_count(entity_id: String) -> int:
	if entity_id in combo_trackers:
		return combo_trackers[entity_id].combo_count
	return 0

func can_combo(entity_id: String, skill: Skill) -> bool:
	if entity_id in combo_trackers:
		return combo_trackers[entity_id].can_combo(skill)
	return true

## GROUND TARGETING

func get_ground_target_position(caster: Node, direction: Vector2, max_range: float) -> Vector3:
	# Raycast to ground
	var from: Vector3 = caster.global_position + Vector3.UP * 2
	var to: Vector3 = caster.global_position + Vector3(direction.x, 0, direction.y) * max_range
	
	var space_state: PhysicsDirectSpaceState3D = caster.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collision_mask = 0b0000111  # World layers
	
	var result: Dictionary = space_state.intersect_ray(query)
	
	if result:
		return result.position
	
	# Fallback if no ground hit
	return caster.global_position + Vector3(direction.x, 0, direction.y) * max_range

## UTILITY

func calculate_damage_output(attacker: Entity, skill: Skill) -> int:
	if not skill:
		return 0
	return skill.calculate_damage(attacker, null)

## ComboTracker - Tracks skill combos
class ComboTracker:
	var combo_count: int = 0
	var last_skill_time: float = 0.0
	var last_skill: Skill = null
	var combo_history: Array[String] = []
	
	const COMBO_WINDOW: float = 2.0  # Seconds to chain combo
	
	func record_skill(skill: Skill) -> void:
		var current_time := Time.get_ticks_msec() / 1000.0
		
		# Check if within combo window
		if current_time - last_skill_time < COMBO_WINDOW and last_skill != null:
			# Check if skill can chain
			if skill.skill_id in last_skill.combo_chain:
				combo_count += 1
			else:
				combo_count = 1  # Reset combo
		else:
			combo_count = 1
		
		last_skill = skill
		last_skill_time = current_time
		
		# Track history (keep last 5)
		combo_history.append(skill.skill_id)
		if combo_history.size() > 5:
			combo_history.pop_at(0)
	
	func can_combo(skill: Skill) -> bool:
		if last_skill == null:
			return true
		return skill.skill_id in last_skill.combo_chain
	
	func _physics_process(_delta: float) -> void:
		var current_time := Time.get_ticks_msec() / 1000.0
		if current_time - last_skill_time > COMBO_WINDOW:
			combo_count = 0

## DoTEffect - Damage over time effect
class DoTEffect:
	extends StatusEffect
	
	var damage_per_tick: int = 0
	var tick_rate: float = 1.0
	var total_duration: float = 0.0
	var ticks_remaining: int = 0
	var tick_timer: float = 0.0
	
	func _init() -> void:
		effect_type = EffectType.DEBUFF
	
	func apply(target_entity: Node) -> bool:
		ticks_remaining = int(total_duration / tick_rate)
		if target_entity.damage_dealt.connect(_on_target_take_damage) == OK:
			pass
		return true
	
	func remove(target_entity: Node) -> void:
		target_entity.damage_dealt.disconnect(_on_target_take_damage)
	
	func _physics_process(delta: float) -> void:
		tick_timer += delta
		if tick_timer >= tick_rate and ticks_remaining > 0:
			tick_timer = 0.0
			# Damage applied via signal
			ticks_remaining -= 1
	
	func _on_target_take_damage(_damager: Entity, _target: Entity, _amount: int) -> void:
		pass  # Could modify damage or apply effects
