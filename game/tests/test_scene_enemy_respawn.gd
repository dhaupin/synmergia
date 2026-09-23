## test_scene_enemy_respawn.gd - scene-placed enemy respawn cycle test.
## Run in RENDERING mode:
##
##   cd game && xvfb-run godot --path . --script res://tests/test_scene_enemy_respawn.gd
##
## Chain exercised:
##   _capture_scene_spawns snapshots every scene enemy (pos, data, level)
##     -> kill a slime via the real take_damage path
##     -> EventHub.entity_died -> WorldPlayable schedules a rebuild
##     -> fresh Enemy at the original spawn point, real data/level/HP,
##        registered with EntityService
##     -> second kill also respawns (record re-pointed at the new entity)
##
## The scene has MULTIPLE slimes and every slime's AI starts wandering
## immediately, so position matching is inherently racy. Identity is
## matched by entity-id sets instead: snapshot all slime ids before the
## kill; after death the living set must lose exactly the target; the
## respawn is any living slime id not in the pre-kill snapshot. The
## captured spawn point is cross-checked as a soft diagnostic (printed,
## not asserted) because wander can move the fresh mob within seconds.
##
## The scene slime's EnemyData.respawn_time is 30s; the captured record is
## patched to 2s so the test runs in seconds, not minutes.
##
## Exit 0 = all hops observed.
extends SceneTree

var _pass := 0
var _fail := 0
var _armed := false
var _finished := false
var _frames := 0

var _target: Node = null
var _target_id := ""
var _spawn_pos: Vector3 = Vector3.ZERO
var _known_ids: Dictionary = {}  # pre-kill slime id -> true
var _phase := 0  # 1 waiting death, 2 waiting respawn 1, 3 waiting respawn 2
var _deadline := 0

var got_entity_died := false


func _initialize() -> void:
	print("=== SCENE ENEMY RESPAWN TEST: booting playable scene ===")
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	if scene == null:
		print("  FAIL: could not load world_playable.tscn")
		quit(1)
		return
	var inst := scene.instantiate()
	root.add_child(inst)
	current_scene = inst


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 90 and not _armed:
		_run()
	elif _armed and not _finished and _frames % 15 == 0:
		_tick()
	return false


func _run() -> void:
	_armed = true

	var hub := root.get_node_or_null("EventHub")
	var es := root.get_node_or_null("EntityService")
	_assert(hub != null and es != null, "autoloads present (EventHub/EntityService)")
	if hub == null:
		_finish()
		return

	var slime := _any_living_slime()
	_assert(slime != null, "living slime found in scene")
	if slime == null:
		_finish()
		return

	_target = slime
	_target_id = str(slime.entity_id)
	_spawn_pos = Vector3.INF
	print("    slime '%s' (%s) at %s" % [slime.display_name, _target_id, str(slime.global_position)])

	# Pre-kill identity snapshot + spawn-point lookup + delay patch.
	var world := current_scene
	var record_found := false
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_dead and str(e.display_name) == "Slime":
			_known_ids[str(e.entity_id)] = true
	if world != null and "_scene_spawns" in world:
		for record in world._scene_spawns:
			if record.entity_id == _target_id:
				record.respawn_time = 2.0
				_spawn_pos = record.spawn_position
				record_found = true
				break
	_assert(record_found, "captured record exists for the slime")
	print("    captured spawn point: %s; known slime ids: %s" % [str(_spawn_pos), str(_known_ids.keys())])

	hub.entity_died.connect(func(_e, _k, _m): got_entity_died = true)

	# Kill through the real damage path.
	var dealt: int = slime.take_damage(99999, null)
	_assert(dealt > 0, "lethal damage applied")
	_phase = 1
	_deadline = _frames + 300


func _tick() -> void:
	match _phase:
		1:
			# The TARGET must be gone/dead (other slimes still live).
			var gone: bool = not is_instance_valid(_target) or _target.is_dead
			if got_entity_died and gone:
				_phase = 2
				_deadline = _frames + 420  # 2s delay + margin at 60fps
				print("    [hop] slime died; waiting for respawn")
			elif _frames > _deadline:
				_assert(got_entity_died, "entity_died observed for the slime")
				_assert(gone, "target slime removed after death")
				_finish()
		2:
			if _frames > _deadline:
				_assert(false, "slime respawned within the patched 2s window")
				_finish()
				return
			# Respawn = any living slime id NOT in the pre-kill snapshot.
			var fresh := _find_new_slime()
			if fresh != null:
				print("    [hop] fresh slime %s at %s (captured spawn: %s)" % [
					str(fresh.entity_id), str(fresh.global_position), str(_spawn_pos)])
				_verify_first(fresh)
		3:
			if _frames > _deadline:
				_assert(false, "second kill also respawned within the window")
				_finish()
				return
			var fresh2 := _find_new_slime()
			if fresh2 != null:
				_assert(true, "second kill also respawns (record re-pointed)")
				_finish()


## Any living slime.
func _any_living_slime() -> Node:
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_dead and str(e.display_name) == "Slime":
			return e
	return null


## A living slime whose id was NOT in the pre-kill snapshot.
func _find_new_slime() -> Node:
	for e in get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if e.is_dead or str(e.display_name) != "Slime":
			continue
		if _known_ids.has(str(e.entity_id)):
			continue
		return e
	return null


## Shorten a captured record's delay by entity id (used for the second
## kill). Returns false when no record matches (re-point broken).
func _patch_respawn_time(id: String, value: float) -> bool:
	var world := current_scene
	if world == null or not ("_scene_spawns" in world):
		return false
	for record in world._scene_spawns:
		if record.entity_id == id:
			record.respawn_time = value
			return true
	return false


func _verify_first(fresh: Node) -> void:
	_phase = 0
	_assert(got_entity_died, "entity_died fired for the slime")
	# Soft diagnostic: expected at the captured spawn point, but wander
	# can move the fresh mob before the next poll, so never assert this.
	if _spawn_pos != Vector3.INF \
			and fresh.global_position.distance_to(_spawn_pos) > 5.0:
		print("    INFO: fresh slime already wandered (%.1fm from spawn point)" % fresh.global_position.distance_to(_spawn_pos))
	_assert(fresh.health_component != null
			and fresh.health_component.current_health == fresh.health_component.max_health,
			"fresh slime has full health")
	_assert("attach_ai" in fresh, "fresh slime has AI surface")

	var es := root.get_node_or_null("EntityService")
	var registered: bool = es != null and es.get_entity(str(fresh.entity_id)) != null
	_assert(registered, "fresh slime registered with EntityService")

	# Second kill: the record must have been re-pointed.
	_target = fresh
	_target_id = str(fresh.entity_id)
	_known_ids[str(fresh.entity_id)] = true  # it's known now; next fresh wins
	if not _patch_respawn_time(_target_id, 2.0):
		# Record not re-pointed: the second kill would not respawn.
		_assert(false, "record re-pointed at the new entity")
		_finish()
		return
	fresh.take_damage(99999, null)
	_phase = 3
	_deadline = _frames + 420


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("SceneEnemyRespawn: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
