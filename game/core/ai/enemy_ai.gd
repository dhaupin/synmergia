## EnemyAI - AI state machine for enemies
## Handles IDLE, PATROL, CHASE, COMBAT, FLEE, RETURN states
extends Node
class_name EnemyAI

# Memory tree (frame primitive, arch sec 9): enemies remember who attacked
# them and who they lost (fled from), and bias future targeting.
const MemoryTreeScript = preload("res://core/frame/kv/memory_tree.gd")
const MemorySchemaScript = preload("res://core/frame/kv/memory_schema.gd")
# The MWo-style hit table: enemy swings run the same single roll
# (miss/dodge/parry/block/crit) as player skills.
const CombatMath = preload("res://core/services/combat_math.gd")
# Shared interest queries (round 10): one "nearby" law.
const EntityInterest = preload("res://core/services/entity_interest.gd")
# R29: data-driven skill kit. EnemyData.skills lists skill IDs; they
# materialize into combat Skills on first attack and cast through the
# enemy's CombatComponent (GCD + the live effect stack). The plain MWo
# swing stays as the no-kit / GCD-busy fallback.
const SkillScript = preload("res://core/combat/skill.gd")
const MAX_MEMORY_ENTRIES := 16


## The body's "up" under the world-shape law: on the spherical world
## that is the direction from the planet center to the body (the
## tangent-plane normal); planar keeps the classic Y up. Enemies have
## no planet_center of their own, so the player's reference is the
## shared planet frame (all bodies ride one planet).
static func _entity_up(entity: Node3D) -> Vector3:
	var tree := entity.get_tree() if is_instance_valid(entity) else null
	var pm: Node = tree.root.get_node_or_null("PlayerManager") if tree else null
	var local: Node = pm.local_player if pm != null and is_instance_valid(pm) else null
	var planet_center: Variant = (local.planet_center if local != null and "planet_center" in local and (local as Node3D).is_inside_tree() else Vector3.ZERO)
	var pc: Vector3 = planet_center if planet_center is Vector3 else Vector3.ZERO
	if pc != Vector3.ZERO:
		var rel: Vector3 = (entity as Node3D).global_position - pc
		if rel.length() > 0.001:
			return rel.normalized()
	return Vector3.UP


## Project a wished world direction onto the body's local tangent
## plane (the planet law): the vertical component would walk the body
## up/down the ground (the sideways-vertical wolf bug) -- on the
## sphere only the tangent part is a walk step.
static func _tangent(entity: Node3D, dir: Vector3) -> Vector3:
	var d := dir
	if d.length_squared() < 0.000001:
		return Vector3.ZERO
	d = d.normalized()
	var up := _entity_up(entity)
	return (d - up * d.dot(up)).normalized() if d.dot(up) != 1.0 else Vector3.ZERO


enum AIState {
	IDLE,
	PATROL,
	CHASE,
	COMBAT,
	FLEE,
	RETURN
}

signal state_changed(from: AIState, to: AIState)
signal target_acquired(target: Entity)
signal target_lost()

@export var state: AIState = AIState.IDLE
@export var aggro_range: float = 15.0
@export var chase_range: float = 25.0
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.5
@export var patrol_speed: float = 2.0
@export var chase_speed: float = 5.0

var _target = null  # untyped: may be PlayerController (CharacterBody3D)
var _spawn_position: Vector3 = Vector3.ZERO
var _patrol_target: Vector3 = Vector3.ZERO
var _patrol_wait_time: float = 0.0
var _attack_timer: float = 0.0
var _aggro_timer: float = 0.0
var _memory_tree = null  # lazy MemoryTreeScript instance
var _memory_agent_path := ""
var _known_threats: Dictionary = {}  # player_id -> weight (remembered attackers)
var _skills: Array = []          # materialized combat Skills
var _skills_loaded: bool = false

## Materialize EnemyData.skills into combat Skills once (lazy: the
## DataService catalog may still be filling during boot, and /root
## resolution keeps this file free of bare-autoload compile deps).
func _load_skills() -> void:
	if _skills_loaded:
		return
	_skills_loaded = true
	var entity: Entity = get_parent()
	if entity == null or not ("enemy_data" in entity) or entity.enemy_data == null:
		return
	var skill_ids: Array = entity.enemy_data.skills if "skills" in entity.enemy_data else []
	var ds = get_node_or_null("/root/DataService")
	for id in skill_ids:
		if ds == null or not ds.has_method("get_skill"):
			break
		var schema = ds.get_skill(str(id))
		if schema != null:
			var skill: Skill = SkillScript.from_schema(schema)
			if skill != null:
				_skills.append(skill)

## First off-cooldown, castable skill from the kit (null = plain swing).
func _next_ready_skill(entity: Entity) -> Skill:
	_load_skills()
	for skill in _skills:
		if skill != null and skill.remaining_cooldown <= 0.0 and skill.can_cast(entity):
			return skill
	return null

func _ready() -> void:
	var entity: Entity = get_parent()
	if entity:
		_spawn_position = entity.global_position
		_memory_agent_path = "memory/enemies/%s" % entity.entity_id
		_restore_memory()
		# Persist periodically so grudges survive restarts (mirrors the
		# frame snapshot_store durability story; in-memory tree + durable KV).
		_persist_timer = Timer.new()
		_persist_timer.wait_time = PERSIST_INTERVAL_SEC
		_persist_timer.one_shot = false
		_persist_timer.timeout.connect(_persist_memory)
		add_child(_persist_timer)
		_persist_timer.start()
	tree_exiting.connect(_persist_memory)

const PERSIST_INTERVAL_SEC := 30.0
const MEMORY_KV_KEY := "frame:enemy_memory:%s"
var _persist_timer: Timer = null

## Serialize the agent's memory subtree into a plain dictionary.
func _memory_snapshot() -> Dictionary:
	var tree = _get_memory_tree()
	if tree == null or _memory_agent_path == "":
		return {}
	var snap: Dictionary = {}
	for p in tree.list_memories(_memory_agent_path):
		var mem: Dictionary = tree.get_memory(str(p))
		snap[str(p)] = {"kind": mem.get("kind", "event"), "content": mem.get("content", {}), "weight": mem.get("weight", 1.0)}
	return snap

## Restore a previously persisted memory snapshot into the tree.
func _restore_memory() -> void:
	var tree = _get_memory_tree()
	if tree == null or _memory_agent_path == "":
		return
	var store = _kv_store()
	if store == null:
		return
	var key := MEMORY_KV_KEY % _memory_agent_path
	if not store.has_key(key):
		return
	var snap: Variant = store.get_kv(key)
	if snap is String:
		snap = JSON.parse_string(str(snap))
	if not snap is Dictionary:
		return
	var entries: Dictionary = snap
	for path in entries.keys():
		var e: Dictionary = entries[path]
		tree.insert_memory(str(path), str(e.get("kind", "event")), e.get("content", {}), float(e.get("weight", 1.0)))
	_update_known_threats(tree)

## Write the current memory snapshot to the durable KV store.
func _persist_memory() -> void:
	var tree = _get_memory_tree()
	if tree == null or _memory_agent_path == "":
		return
	var store = _kv_store()
	if store == null:
		return
	var snap := _memory_snapshot()
	var key := MEMORY_KV_KEY % _memory_agent_path
	if snap.is_empty():
		if store.has_key(key):
			store.erase(key)
		return
	store.set_kv(key, snap)

func _kv_store():
	if _kv_store_ref != null:
		return _kv_store_ref
	if DictStoreScript:
		_kv_store_ref = DictStoreScript.new()
	return _kv_store_ref

const DictStoreScript = preload("res://adapters/persistence/dict_store.gd")
var _kv_store_ref = null

func _get_memory_tree():
	if _memory_tree != null:
		return _memory_tree
	if MemoryTreeScript:
		_memory_tree = MemoryTreeScript.new()
	return _memory_tree

## Record an event in this enemy's memory tree (observation kind, weighted).
func remember(event_key: String, content: Dictionary, weight: float) -> void:
	var tree = _get_memory_tree()
	if tree == null or _memory_agent_path == "":
		return
	tree.insert_memory(_memory_agent_path + "/events/" + event_key, "event", content, weight)
	_update_known_threats(tree)

## Load the remembered attacker weights into _known_threats (id -> weight).
func _update_known_threats(tree) -> void:
	_known_threats.clear()
	var paths: Array = tree.list_by_kind(_memory_agent_path, "event")
	var entries: Array = []
	for p in paths:
		var mem: Dictionary = tree.get_memory(str(p))
		var content: Dictionary = mem.get("content", {})
		var pid: String = str(content.get("player_id", ""))
		if pid != "":
			entries.append({"id": pid, "weight": float(mem.get("weight", 0.0)), "time": float(content.get("time", 0.0)), "path": str(p)})
	# Keep only the most recent MAX_MEMORY_ENTRIES threat memories.
	entries.sort_custom(func(a, b): return float(a["time"]) > float(b["time"]))
	for i in range(mini(entries.size(), MAX_MEMORY_ENTRIES)):
		_known_threats[entries[i]["id"]] = entries[i]["weight"]

## Forgiveness: after a leash return completes, decay every remembered
## grudge by GRUDGE_DECAY_FACTOR (weights below GRUDGE_FORGET_THRESHOLD
## are forgotten entirely). Attackers who keep re-offending keep their
## grudge hot because newer memories are written at full weight.
const GRUDGE_DECAY_FACTOR := 0.5
const GRUDGE_FORGET_THRESHOLD := 0.25

func _decay_grudges() -> void:
	var tree = _get_memory_tree()
	if tree == null or _memory_agent_path == "":
		return
	var paths: Array = tree.list_by_kind(_memory_agent_path, "event")
	for p in paths:
		var mem: Dictionary = tree.get_memory(str(p))
		var weight: float = float(mem.get("weight", 0.0))
		var decayed: float = weight * GRUDGE_DECAY_FACTOR
		if decayed < GRUDGE_FORGET_THRESHOLD:
			tree.delete_memory(str(p))
		else:
			var content: Dictionary = mem.get("content", {})
			tree.update_memory(str(p), "event", content, decayed)
	_update_known_threats(tree)

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
func _check_for_targets():
	var entity: Entity = get_parent()
	if not entity:
		return null

	var nearby: Array = EntityInterest.query_players(
		entity.global_position,
		aggro_range
	)

	# Memory bias: prefer remembered attackers (grudge) -- highest weight first.
	var best_target = null
	var best_weight: float = 0.0
	for target in nearby:
		if not _is_valid_target(target):
			continue
		var weight: float = float(_known_threats.get(target.entity_id, 0.0))
		if weight > best_weight:
			best_weight = weight
			best_target = target
	if best_target != null:
		return best_target

	for target in nearby:
		if _is_valid_target(target):
			return target

	return null

func _is_valid_target(target) -> bool:
	# Check if dead
	if target.health_component and target.health_component.is_dead():
		return false

	# Stealth check: a stealthed target is invisible unless this enemy
	# can see stealth (enemy_data.see_stealth). Duck-typed: PlayerController
	# has no status_handler, which simply means "not stealthed".
	if "status_handler" in target and target.status_handler != null:
		var stealth_effect = target.status_handler.get_effect_by_type(StatusEffectData.EffectType.STEALTH, "stealth")
		if stealth_effect and stealth_effect.is_active():
			var parent_entity = get_parent()
			var see_stealth: bool = false
			if parent_entity and "enemy_data" in parent_entity and parent_entity.enemy_data:
				see_stealth = true if ("see_stealth" in parent_entity.enemy_data and parent_entity.enemy_data.see_stealth) else false
			if not see_stealth:
				return false

	# Spawn sanctuary: a fresh target loitering near a zone spawn/bind
	# point cannot be aggroed. Grudged targets (they damaged us first)
	# are exempt so players cannot use spawn as a combat shield.
	var has_grudge: bool = float(_known_threats.get(target.entity_id, 0.0)) > 0.0
	if not has_grudge and _is_target_in_spawn_sanctuary(target):
		return false

	# Check faction/enemy status
	if EntityService.is_enemy(get_parent(), target):
		return true

	return false

## True when the target stands within SPAWN_SANCTUARY_RADIUS of any
## registered spawn point (or bind point) of the zone it is in. Duck-
## typed throughout: ZoneManager may be absent (script-mode tests) and
## the zone data may not be registered yet -- both mean "no sanctuary".
## Radius must exceed the largest aggro_range in enemy data (10.0).
const SPAWN_SANCTUARY_RADIUS := 12.0

func _is_target_in_spawn_sanctuary(target) -> bool:
	var zm = get_node_or_null("/root/ZoneManager")
	if zm == null or not zm.has_method("get_entity_zone"):
		return false
	var zone = zm.get_entity_zone(target)
	if zone == null:
		return false
	var anchors: Array = []
	if "spawn_points" in zone:
		anchors = zone.spawn_points
	if "bind_point" in zone:
		anchors.append(zone.bind_point)
	for anchor in anchors:
		if target.global_position.distance_to(anchor) <= SPAWN_SANCTUARY_RADIUS:
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
	var entity: Entity = get_parent()
	if not entity:
		return

	# Enemies steer via move_direction; move_speed is only meaningful on
	# controllers that read it (PlayerController). Set it if present so
	# future movement code can consult it without crashing on Enemy.
	if "move_speed" in entity:
		_match_state_speed(entity)

	match state:
		AIState.PATROL:
			_patrol_wait_time = 0

## State-dependent speed, applied only when the parent exposes move_speed.
func _match_state_speed(entity) -> void:
	match state:
		AIState.IDLE:
			entity.move_speed = 0
		AIState.PATROL:
			entity.move_speed = patrol_speed
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
	var entity: Entity = get_parent()
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
	var entity: Entity = get_parent()
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

	# Move to patrol target (tangent plane: walk the ground, not the
	# planet's radial).
	var dist: float = entity.global_position.distance_to(_patrol_target)

	if dist < 1.0:
		# Reached patrol point, wait
		_patrol_wait_time = randf_range(2.0, 5.0)
		_set_new_patrol_target()
	else:
		var dir := (_patrol_target - entity.global_position).normalized()
		entity.move_direction = _tangent(entity, dir)

func _start_patrol() -> void:
	_set_new_patrol_target()
	set_state(AIState.PATROL)

func _set_new_patrol_target() -> void:
	var entity: Entity = get_parent()
	if not entity:
		return

	# Random point within patrol radius
	var angle := randf() * TAU
	var dist: float = randf() * 10.0 + 5.0
	_patrol_target = _spawn_position + Vector3(cos(angle), 0, sin(angle)) * dist

## CHASE: Move toward target
func _update_chase(delta: float) -> void:
	var entity: Entity = get_parent()
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

	# Move toward target (tangent plane under the world-shape law).
	var dir: Vector3 = (_target.global_position - entity.global_position).normalized()
	entity.move_direction = _tangent(entity, dir)

## COMBAT: Attack target
func _update_combat(delta: float) -> void:
	var entity: Entity = get_parent()
	if not entity or not _target:
		set_state(AIState.RETURN)
		return

	# Check if target is dead or invalid (test the TARGET's health, not
	# ours; health_component is duck-typed -- bare Entity targets carry
	# no such field).
	var target_dead: bool = false
	if is_instance_valid(_target) and "health_component" in _target and _target.health_component != null:
		target_dead = _target.health_component.is_dead()
	if not is_instance_valid(_target) or target_dead:
		on_target_death()
		return

	# Threat-based switching: while in combat, whoever sits on top of the
	# threat table becomes the target (damage, heals, taunts all feed it).
	# Taunts force-lock the table so the tank holds the enemy.
	if entity.aggro_component:
		var threat_target = entity.aggro_component.get_highest_threat_target()
		if threat_target != null and threat_target != _target and is_instance_valid(threat_target):
			if threat_target.entity_type == Entity.EntityType.PLAYER or _is_valid_target(threat_target):
				_set_target(threat_target)

	var dist: float = entity.global_position.distance_to(_target.global_position)

	# Target out of range? Chase again
	if dist > attack_range:
		set_state(AIState.CHASE)
		return

	# Face target (planet law: on the spherical world "up" is the own
	# radial; Vector3.UP would roll the body sideways/vertical).
	entity.look_at(_target.global_position, _entity_up(entity))

	# Attack
	_attack_timer -= delta
	if _attack_timer <= 0:
		_perform_attack()
		_attack_timer = attack_cooldown

func _perform_attack() -> void:
	if not _target or not is_instance_valid(_target):
		return

	var entity: Entity = get_parent()
	if not entity:
		return

	# R29: cast a kit skill through the enemy's CombatComponent when one
	# is ready (GCD-gated; effects land through the live stack). The
	# plain swing below remains the no-kit / GCD-busy fallback.
	var kit_skill: Skill = _next_ready_skill(entity)
	if kit_skill != null and entity.combat_component != null:
		if entity.combat_component.execute_skill(kit_skill, _target):
			# Threat mirrors the swing path: our table tracks the target,
			# theirs tracks us. Nominal weight (the roll happens inside
			# CombatSystem; relative threat is what drives switching).
			if entity.aggro_component:
				entity.aggro_component.add_damage_threat(_target, maxi(1, int(kit_skill.damage)))
			if "aggro_component" in _target and _target.aggro_component != null:
				_target.aggro_component.add_damage_threat(entity, maxi(1, int(kit_skill.damage)))
			return
		# Rejected (GCD busy / not castable right now): fall through.

	# MWo-style single-roll hit table for enemy swings too: one randf()
	# splits into miss/dodge/parry/block/crit/hit against the TARGET's
	# stats. calculate_damage applies crit multipliers and block
	# reduction and returns 0 on miss-family outcomes.
	var outcome := CombatMath.calculate_hit(entity, _target)
	var damage := CombatMath.calculate_damage(entity.get_attack_power(), outcome)

	if CombatMath.is_whiff(int(outcome.get("hit_result", CombatMath.HitResult.HIT))):
		# Nothing landed: no damage, no threat, no on-hit. The HUD bridge
		# turns this into a defender-side Miss/Dodge/Parry float + toast.
		EventHub.hit_resolved.emit(entity, _target, outcome, null, 0)
		return

	var is_crit: bool = bool(outcome.get("is_crit", false))

	# Duck-typed landing with arity safety: Entity subclasses (Enemy,
	# Guard) take a 4th is_crit param; PlayerController and bare
	# health_component take 3. Calling a 3-param method with 4 args is a
	# runtime error, so the arity is read off the method list.
	if _target.has_method("take_damage"):
		if _take_damage_arity(_target) >= 4:
			_target.take_damage(damage, entity, "physical", is_crit)
		else:
			_target.take_damage(damage, entity, "physical")
	elif _target.health_component != null:
		_target.health_component.take_damage(damage, entity, "physical")

	# The HUD bridge emits defender toasts + landed-hit floats from this.
	EventHub.hit_resolved.emit(entity, _target, outcome, null, damage)

	# Damage threat onto OUR OWN table (drives target switching), and the
	# target's table records damage taken from us (player threat meters).
	# Whiffs build no threat.
	if entity.aggro_component:
		entity.aggro_component.add_damage_threat(_target, int(damage))
	if "aggro_component" in _target and _target.aggro_component != null:
		_target.aggro_component.add_damage_threat(entity, int(damage))

func _take_damage_arity(node) -> int:
	for m in node.get_method_list():
		if m.get("name", "") == "take_damage":
			return (m.get("args", []) as Array).size()
	return 3

## FLEE: Run away from target
func _update_flee(delta: float) -> void:
	var entity: Entity = get_parent()
	if not entity or not _target:
		set_state(AIState.RETURN)
		return

	# Run away from target (tangent plane law).
	var dir: Vector3 = (entity.global_position - _target.global_position).normalized()
	entity.move_direction = _tangent(entity, dir)

	# Stop fleeing when far enough
	var dist: float = entity.global_position.distance_to(_target.global_position)
	if dist > chase_range:
		_clear_target()
		set_state(AIState.RETURN)

## RETURN: Go back to spawn
func _update_return(delta: float) -> void:
	var entity: Entity = get_parent()
	if not entity:
		return

	var dist: float = entity.global_position.distance_to(_spawn_position)

	# Back at spawn?
	if dist < 1.0:
		_decay_grudges()
		set_state(AIState.IDLE)
		return

	# Move toward spawn (tangent plane law).
	var dir := (_spawn_position - entity.global_position).normalized()
	entity.move_direction = _tangent(entity, dir)

## Set target
func _set_target(new_target) -> void:
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
func engage_target(target) -> void:
	if _is_valid_target(target):
		_set_target(target)
		set_state(AIState.CHASE)

## Handle being damaged. Untyped source: the live player is a
## PlayerController (CharacterBody3D), not an Entity subclass -- a typed
## `source: Entity` param throws on every real player hit and silently
## kills threat + grudge recording.
func on_damaged(source) -> void:
	# Remember who hurt us BEFORE engaging: engage_target runs the
	# _is_valid_target gate, which exempts grudged targets from the
	# spawn-sanctuary rule. Recording first means a player who attacks
	# us while standing in spawn still gets chased (no combat shield).
	if source and source.entity_type == Entity.EntityType.PLAYER:
		remember("hit_%s_%d" % [source.entity_id, Time.get_ticks_msec()], {
			"player_id": source.entity_id,
			"player_name": source.display_name,
			"action": "attacked",
			"time": Time.get_unix_time_from_system(),
		}, 1.0)
	if state == AIState.IDLE or state == AIState.PATROL:
		# Become aware
		engage_target(source)

## Handle target death
func on_target_death() -> void:
	# Record the kill in memory before releasing the target.
	if _target and _target.entity_type == Entity.EntityType.PLAYER:
		remember("kill_%s_%d" % [_target.entity_id, Time.get_ticks_msec()], {
			"player_id": _target.entity_id,
			"player_name": _target.display_name,
			"action": "killed",
			"time": Time.get_unix_time_from_system(),
		}, 1.5)
	_clear_target()
	set_state(AIState.RETURN)
