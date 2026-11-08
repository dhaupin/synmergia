## CombatSystem - Manages combat interactions, skills, and hit detection
## Free-form combat system inspired by RYL2
extends Node

const Skill = preload("res://core/combat/skill.gd")
const StatusEffect = preload("res://core/entities/status_effect.gd")
## Named collision bits (round 10): data/physics_layers/ LayerProfile.
const Layers = preload("res://core/schemas/layer_profile.gd")
# The MWo-style hit table: _apply_hit rolls it through the skill so
# miss/dodge/parry/block/crit all resolve in one place.
const CombatMath = preload("res://core/services/combat_math.gd")
# Entity is not an autoload (class_name only). The signal and
# method signatures here use `: Entity`, which requires Entity's
# class_name to be registered at parse time. Preloading it here
# guarantees that -- same idiom as the 27-call workaround before
# the autoload was removed.
const Entity = preload("res://core/entities/entity.gd")
signal skill_executed(caster: Entity, skill: Skill, targets: Array)
signal skill_hit(caster: Entity, target: Entity, skill: Skill, damage: int)
signal skill_missed(caster: Entity, skill: Skill)
signal damage_dealt(damager: Entity, target: Entity, amount: int, skill: Skill)
signal entity_died(victim: Entity, killer: Entity)

var registered_entities: Dictionary = {}
var active_hitboxes: Array[HitboxData] = []
var combo_trackers: Dictionary = {}  # entity_id -> ComboTracker

class HitboxData:
	# Entity.entity_id is a String; the old int type made every
	# create_hitbox() a runtime assignment error.
	var owner_id: String = ""
	var position: Vector3
	var size: float
	var skill: Skill
	var start_time: float
	var duration: float
	var team_id: int = 0
	var hit_entities: Array[String] = []  # Entity IDs already hit

func _physics_process(_delta: float) -> void:
	_process_hitboxes(_delta)
	_process_combos(_delta)

## ENTITY MANAGEMENT

## Registry accepts ANY combatant: Entity subclasses (Enemy, NPC) AND
## the live player (the player body, a CharacterBody3D). The old
## `entity: Entity` annotation made every player registration throw
## "not a subclass of the expected argument class" -- so the player was
## never in the hitbox sweep registry.
func register_entity(entity) -> void:
	if entity == null or not is_instance_valid(entity) or not ("entity_id" in entity):
		return
	registered_entities[entity.entity_id] = entity
	# Death hook: Entity subclasses emit died(killer); the player body
	# emits player_died(killer). Bind the victim so the re-emit carries
	# the full (victim, killer) pair either way.
	var death_signal := "died" if entity.has_signal("died") else "player_died"
	if entity.has_signal(death_signal):
		var cb := _on_entity_died.bind(entity)
		if not entity.is_connected(death_signal, cb):
			entity.connect(death_signal, cb)
	combo_trackers[entity.entity_id] = ComboTracker.new()

func unregister_entity(entity) -> void:
	if entity == null:
		return
	if "entity_id" in entity:
		registered_entities.erase(entity.entity_id)
		combo_trackers.erase(entity.entity_id)
	# Death paths can reach here after the node is already freed
	# (enemy self-unregisters in _on_died before queue_free); touching
	# a freed instance's signals segfaults, so validate first.
	if not is_instance_valid(entity):
		return
	var death_signal := "died" if entity.has_signal("died") else "player_died"
	if entity.has_signal(death_signal):
		var cb := _on_entity_died.bind(entity)
		if entity.is_connected(death_signal, cb):
			entity.disconnect(death_signal, cb)

func get_entity(entity_id: String):
	return registered_entities.get(entity_id)

## Signal arity: Entity.died / the player body's player_died emit the
## killer; the bound victim arrives second. Mismatching this used to
## break every death hook with "Method expected 2 argument(s), but
## called with 1". Untyped params: the killer may be the player body.
func _on_entity_died(killer, victim) -> void:
	entity_died.emit(victim, killer)

## SKILL EXECUTION

func execute_skill(caster: Node, skill: Skill, target: Node = null, ground_position: Vector3 = Vector3.ZERO) -> Dictionary:
	if not skill.can_cast(caster):
		return {"success": false, "reason": "cannot_cast"}

	# Execute skill. Hitbox-family casts defer target-side effects:
	# the sweep's _apply_skill_effects owns DoT/CC on LANDED hits only
	# (skill.execute applying at cast AND the sweep applying per hit
	# used to double-apply both).
	var result := skill.execute(caster, target, ground_position, skill.hitbox_size > 0)

	if result.success:
		skill_executed.emit(caster, skill, result.targets_hit)

		# Track combo
		if "entity_id" in caster and caster.entity_id in combo_trackers:
			combo_trackers[caster.entity_id].record_skill(skill)

		# Create hitbox if applicable. Seed hit_entities with the primary
		# target when skill.execute already damaged it directly -- the
		# sweep must not hit it a second time.
		if skill.hitbox_size > 0:
			create_hitbox(caster, skill, target, ground_position, result.targets_hit)

	return result

func create_hitbox(caster: Node, skill: Skill, target: Node, ground_position: Vector3, already_hit: Array = []) -> void:
	var hitbox := HitboxData.new()
	hitbox.owner_id = str(caster.entity_id) if "entity_id" in caster and caster.entity_id else ""
	hitbox.skill = skill
	hitbox.team_id = caster.team_id if "team_id" in caster else 0
	hitbox.hit_entities = []
	for node in already_hit:
		if node != null and is_instance_valid(node) and "entity_id" in node and node.entity_id != "":
			hitbox.hit_entities.append(str(node.entity_id))
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

			# The caster must never be hit by their own hitbox.
			if hitbox.owner_id != "" and entity.entity_id == hitbox.owner_id:
				continue

			# Check team (no friendly fire)
			if entity.team_id == hitbox.team_id and hitbox.team_id != 0:
				continue

			# Check if already dead
			if not _is_alive(entity):
				continue

			# Apply hit
			hitbox.hit_entities.append(entity.entity_id)
			_apply_hit(hitbox, entity)

func get_entities_in_hitbox(hitbox: HitboxData) -> Array:
	var entities_in_range: Array = []

	for entity_id in registered_entities:
		var entity = registered_entities[entity_id]

		if not is_instance_valid(entity):
			continue
		# Entities torn out of the tree (scene-change race) have no valid
		# transform: skip them instead of throwing every physics tick.
		if entity is Node3D and not entity.is_inside_tree():
			continue

		if entity.global_position.distance_to(hitbox.position) <= hitbox.size:
			entities_in_range.append(entity)

	return entities_in_range

## Alive check across the two combatant families: Entity subclasses
## expose is_alive(); the player body (CharacterBody3D) exposes
## is_dead(). The old direct is_alive() call threw on the player.
func _is_alive(node) -> bool:
	if node.has_method("is_alive"):
		return node.is_alive()
	if node.has_method("is_dead"):
		return not node.is_dead()
	return is_instance_valid(node)

func _apply_hit(hitbox: HitboxData, target) -> void:
	var caster = get_entity(str(hitbox.owner_id)) if hitbox.owner_id != "" else null

	# Calculate and apply damage through the hit table. calculate_damage
	# runs the MWo roll (miss/dodge/parry/block/crit) and returns 0 on
	# miss-family outcomes.
	var damage: int = 0
	var outcome: Dictionary = {}
	if caster:
		damage = hitbox.skill.calculate_damage(caster, target)
		outcome = hitbox.skill._last_hit_result

	var is_whiff := CombatMath.is_whiff(int(outcome.get("hit_result", CombatMath.HitResult.HIT)))

	if not is_whiff:
		# Crit flag rides with the hit: Enemy/Entity.take_damage forwards it
		# onto EventHub.damage_dealt so the HUD can style the number. The
		# skill's damage_type picks armor vs resist on the target.
		target.take_damage(damage, caster, hitbox.skill.damage_type, hitbox.skill._last_was_crit)

	# The HUD bridge turns whiffs into Miss/Dodge/Parry floats and landed
	# blocks into partial-damage floats. Emitted for both outcomes.
	EventHub.hit_resolved.emit(caster, target, outcome, hitbox.skill, damage)

	# Emit signals (the landed-hit path only; the miss leg now gets
	# its own announcement -- skill_missed had zero emitters for the
	# whole scaffolding era while CombatLog.log_miss sat waiting).
	if caster and not is_whiff:
		skill_hit.emit(caster, target, hitbox.skill, damage)
		damage_dealt.emit(caster, target, damage, hitbox.skill)
	elif caster:
		skill_missed.emit(caster, hitbox.skill)

	# Apply additional effects from skill (landed hits only: a stunned
	# target should not eat CC off a dodged swing)
	if not is_whiff:
		_apply_skill_effects(hitbox.skill, caster, target)

## Untyped caster/target: the player body (CharacterBody3D) is a valid
## caster/target family; Entity annotations threw on every real swing.
## DoT/CC application routes through the skill's own appliers (the
## same construction skill.execute uses) so both paths stay identical.
func _apply_skill_effects(skill: Skill, caster, target) -> void:
	if target == null or not target.has_method("apply_status_effect"):
		return
	# Apply DoT if skill has duration
	if skill.is_dot:
		skill.applyDoT(caster, target)

	# Apply CC effects
	if skill.crowd_control_type != "":
		skill.applyCrowdControl(caster, target, Vector3.ZERO)

	# Apply movement effects (caster-side)
	if skill.teleport_distance > 0:
		_apply_teleport(caster, target, skill)

func _apply_teleport(caster, _target, skill: Skill) -> void:
	var forward: Vector3 = -caster.global_transform.basis.z
	forward.y = 0
	caster.global_position += forward * skill.teleport_distance

## COMBO SYSTEM

func _process_combos(_delta: float) -> void:
	for entity_id in combo_trackers:
		# ComboTracker is a RefCounted inner class, NOT a Node; the old
		# `Node` annotation failed every physics frame with
		# "Trying to assign value of type 'RefCounted' to a variable of type 'Node'".
		var tracker: ComboTracker = combo_trackers[entity_id]
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
	query.collision_mask = Layers.group_mask("world")  # World layers

	var result: Dictionary = space_state.intersect_ray(query)

	if result:
		return result.position

	# Fallback if no ground hit
	return caster.global_position + Vector3(direction.x, 0, direction.y) * max_range

## UTILITY

func calculate_damage_output(attacker, skill: Skill) -> int:
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
