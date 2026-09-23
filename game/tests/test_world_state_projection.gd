## test_world_state_projection.gd - world/mob state -> shared frame tree.
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_world_state_projection.gd
##
## Covers:
##   1. write_entity inserts identity + health; read_entity round-trips.
##   2. Health flush coalescing: mark_dirty + flush writes current values,
##      multiple marks in one window produce one write per entity.
##   3. remove_entity clears nodes; unknown ids return false.
##   4. Shared-tree integration: FrameService.world_root_hash() reacts to
##      both this service and PlayerProgress (one root over both halves).
##   5. Lifecycle wiring: a duck-typed mob spawned into EntityService
##      projects automatically; unregister removes its nodes.
##   6. Non-projectable entities (no enemy_data) are ignored.
##
## Exit 0 = all pass.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	await process_frame
	await _run()
	quit(0 if _fail == 0 else 1)


func _run() -> void:
	var ProjectionScript = load("res://core/services/world_state_projection.gd")
	var proj = ProjectionScript.new()
	get_root().add_child(proj)
	await process_frame

	# --- 1. Write + read round-trip --------------------------------------
	var wrote: bool = proj.write_entity("mob_1", {
		"kind": "enemy", "display_name": "Slime", "level": 2,
		"current_health": 18, "max_health": 30,
	})
	_assert(wrote, "write_entity writes identity + health")

	var read: Dictionary = proj.read_entity("mob_1")
	_assert(read.has("identity") and read.has("health"), "read_entity returns both nodes")
	_assert(str(read["identity"]["display_name"]) == "Slime" and int(read["identity"]["level"]) == 2,
			"identity payload round-trips")
	_assert(int(read["health"]["current"]) == 18 and int(read["health"]["max"]) == 30,
			"health payload round-trips")

	var tree = proj.state_tree()
	var identity_node: Dictionary = tree.get_state("/world/entities/mob_1/identity")
	_assert(str(identity_node.get("type", "")) == "other", "identity node typed other")
	var health_node: Dictionary = tree.get_state("/world/entities/mob_1/health")
	_assert(str(health_node.get("type", "")) == "health", "health node typed health")

	# --- 2. Coalesced health flush -----------------------------------------
	# flush() resolves ids through EntityService, so the stub mob is
	# registered FIRST and mob_1's later tree checks ride on it.
	var es_early = root.get_node_or_null("EntityService")
	var mob0 := _make_stub_mob("mob_0", "Coalesce Slime", 1, 30, 30)
	root.add_child(mob0)
	es_early.register_entity(mob0, null, "mob_0")

	# Three damage marks on the same mob in one window -> ONE write.
	proj.mark_dirty("mob_0")
	proj.mark_dirty("mob_0")
	proj.mark_dirty("mob_0")
	var written_count: int = proj.flush()
	_assert(written_count == 1, "three marks in one window coalesce to one write (got %d)" % written_count)

	# A stale id (entity gone from EntityService) is dropped, not written.
	proj.mark_dirty("mob_gone")
	_assert(proj.flush() == 0, "stale dirty id flushes nothing")
	_assert(proj.read_entity("mob_gone").is_empty(), "no phantom nodes from stale ids")

	# --- 3. remove_entity ----------------------------------------------------
	_assert(proj.remove_entity("mob_1"), "remove_entity clears nodes")
	_assert(proj.read_entity("mob_1").is_empty(), "mob_1 nodes gone")
	_assert(not proj.remove_entity("mob_1"), "second remove returns false")
	_assert(not proj.remove_entity(""), "empty id remove is a safe no-op")
	_assert(not proj.write_entity("", {"kind": "enemy"}), "empty id write is a safe no-op")

	# --- 4. Shared-tree integration (FrameService root hash) -----------------
	var fs = root.get_node_or_null("FrameService")
	_assert(fs != null, "FrameService present")
	if fs == null:
		return _finish()

	var hash_before: PackedByteArray = fs.world_root_hash()
	proj.write_entity("mob_2", {"kind": "enemy", "display_name": "Wolf",
			"level": 3, "current_health": 40, "max_health": 40})
	fs.touch_world_tree()
	var hash_after: PackedByteArray = fs.world_root_hash()
	_assert(hash_after.size() > 0, "world_root_hash non-empty after world write")
	_assert(hash_after != hash_before or hash_before.size() == 0,
			"world write moves the shared root hash")

	# The change signal fires on mutation.
	var signal_fired := [false]
	fs.world_state_changed.connect(func(h): signal_fired[0] = true)
	proj.write_entity("mob_3", {"kind": "enemy", "display_name": "Bat",
			"level": 1, "current_health": 5, "max_health": 5})
	_assert(signal_fired[0], "world_state_changed emitted on mutation")

	# PlayerProgress (character half) writes the SAME tree: both halves
	# visible under one root.
	var progress_script = load("res://core/services/player_progress.gd")
	var progress = progress_script.new()
	get_root().add_child(progress)
	await process_frame
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var player: Node = PlayerScript.new()
	player.display_name = "ProjHero"
	player.entity_id = "proj_char"
	get_root().add_child(player)
	await process_frame
	player.add_experience(100)
	_assert(progress.save_player(player, "proj_test"), "PlayerProgress save succeeds")
	fs.touch_world_tree()

	var player_tree = fs.get_world_state_tree()
	var char_node: Dictionary = player_tree.get_state("/player/proj_char/progress")
	_assert(not char_node.is_empty(), "character half visible in the shared world tree")
	var mob_node: Dictionary = player_tree.get_state("/world/entities/mob_2/identity")
	_assert(not mob_node.is_empty(), "mob half visible in the same tree")

	# --- 5. Lifecycle wiring via EntityService -------------------------------
	var es = root.get_node_or_null("EntityService")
	_assert(es != null, "EntityService present")
	if es == null:
		return _finish()

	var mob := _make_stub_mob("mob_lifecycle", "Gel Cube", 3, 22, 22)
	root.add_child(mob)
	var registered_id: String = es.register_entity(mob, null, "mob_lifecycle")
	_assert(registered_id == "mob_lifecycle", "stub mob registered with id override")
	await process_frame
	await process_frame

	var lifecycle_read: Dictionary = proj.read_entity("mob_lifecycle")
	_assert(not lifecycle_read.is_empty(), "spawn projected into the tree automatically")
	if not lifecycle_read.is_empty():
		_assert(str(lifecycle_read["identity"]["display_name"]) == "Gel Cube",
				"lifecycle identity from enemy_data stub")

	# Damage marks dirty; the flush window picks up current health.
	mob.health_component.current_health = 7
	proj.mark_dirty("mob_lifecycle")
	var flushed: int = proj.flush()
	_assert(flushed == 1, "flush writes the damaged mob (got %d)" % flushed)
	var hurt: Dictionary = proj.read_entity("mob_lifecycle")
	_assert(int(hurt["health"]["current"]) == 7, "health flush carries damaged value")

	# Unregister removes the projection.
	es.unregister_entity(mob)
	await process_frame
	_assert(proj.read_entity("mob_lifecycle").is_empty(), "despawn removed the projection")

	# --- 6. Non-projectable entities ignored ---------------------------------
	# A registered combatant WITHOUT enemy_data (data-less stub) must
	# produce no nodes and no crash -- projection duck-types on the
	# enemy_data surface, EntityService keeps its classification.
	var bare := _make_stub_mob("mob_bare", "Ghost", 1, 10, 10)
	bare.enemy_data = null
	root.add_child(bare)
	es.register_entity(bare, null, "mob_bare")
	await process_frame
	_assert(proj.read_entity("mob_bare").is_empty(),
			"registered entity without enemy_data produces no nodes")

	_finish()


## A minimal duck-typed mob: Node3D-ish with entity_id, display_name,
## level, enemy_data (stub Dictionary via .get()) and a health_component.
func _make_stub_mob(id: String, display: String, lvl: int, cur: int, mx: int) -> Node:
	var mob := Node3D.new()
	mob.set_script(load("res://tests/stub_mob.gd"))
	mob.name = "StubMob_" + id
	mob.entity_id = id
	mob.display_name = display
	mob.level = lvl
	mob.enemy_data = {
		"display_name": display, "level": lvl,
	}
	mob.health_component = load("res://core/components/health_component.gd").new()
	mob.health_component.current_health = cur
	mob.health_component.max_health = mx
	return mob


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)


func _finish() -> void:
	print("WorldStateProjection: %d passed, %d failed" % [_pass, _fail])
