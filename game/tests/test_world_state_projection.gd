## test_world_state_projection.gd - world/mob + player live state -> shared frame tree.
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_world_state_projection.gd
##
## Covers:
##   1. Zone-scoped write/read: identity + health under /world/zones/<z>/entities/<id>/
##   2. Coalesced health flush: three marks in one window -> one write; sig suppression.
##   3. remove_entity clears nodes; empty ids are safe no-ops.
##   4. Tick-routed writes: buffered flush defers tree visibility to the next
##      tick's atomic Phase-2 batch (production cadence proof).
##   5. Player live-state half: register_player -> /world/zones/<z>/players/<id>/live
##      with hp + quantized position; position change rewrites; drift teardown.
##   6. Per-zone snapshot pruning: snapshot_for_zone returns only that zone's nodes.
##   7. Lifecycle wiring: registered stub mob projects automatically; unregister removes.
##   8. Non-projectable entities (no enemy_data) are ignored.
##   9. Cross-half: character (PlayerProgress bridge) + zone nodes share one root.
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

	var tree = proj.state_tree()

	# --- 1. Zone-scoped write + read round-trip ---------------------------
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

	# Zone-scoped paths (stub not tracked by ZoneManager -> "unzoned").
	var identity_node: Dictionary = tree.get_state("/world/zones/unzoned/entities/mob_1/identity")
	_assert(str(identity_node.get("type", "")) == "other", "identity node typed other under zone scope")
	var health_node: Dictionary = tree.get_state("/world/zones/unzoned/entities/mob_1/health")
	_assert(str(health_node.get("type", "")) == "health", "health node typed health under zone scope")

	# --- 2. Coalesced health flush (immediate mode) -----------------------
	var es_early = root.get_node_or_null("EntityService")
	var mob0 := _make_stub_mob("mob_0", "Coalesce Slime", 1, 30, 30)
	root.add_child(mob0)
	es_early.register_entity(mob0, null, "mob_0")

	# Registration queues identity + initial health; drain both first.
	var initial: int = proj.flush(true)
	_assert(initial == 2, "registration drain writes identity + health (got %d)" % initial)

	# Three damage marks on the same mob in one window -> ONE write.
	mob0.health_component.current_health = 17
	proj.mark_dirty("mob_0")
	proj.mark_dirty("mob_0")
	proj.mark_dirty("mob_0")
	var written_count: int = proj.flush(true)
	_assert(written_count == 1, "three marks in one window coalesce to one write (got %d)" % written_count)

	# Signature suppression: unchanged health -> no write.
	_assert(proj.flush(true) == 0, "unchanged health signature suppresses rewrite")

	# A stale id (entity gone from EntityService) is dropped, not written.
	proj.mark_dirty("mob_gone")
	_assert(proj.flush(true) == 0, "stale dirty id flushes nothing")
	_assert(proj.read_entity("mob_gone").is_empty(), "no phantom nodes from stale ids")

	# --- 3. remove_entity --------------------------------------------------
	_assert(proj.remove_entity("mob_1"), "remove_entity clears nodes")
	_assert(proj.read_entity("mob_1").is_empty(), "mob_1 nodes gone")
	_assert(not proj.remove_entity("mob_1"), "second remove returns false")
	_assert(not proj.remove_entity(""), "empty id remove is a safe no-op")
	_assert(not proj.write_entity("", {"kind": "enemy"}), "empty id write is a safe no-op")

	# --- 4. Tick-routed writes (production cadence) ------------------------
	# Registered mob, damaged, drained through the BUFFERED path: the tree
	# must NOT change until the next tick's Phase-2 batch applies it.
	var mob_t := _make_stub_mob("mob_tick", "Tick Slime", 2, 20, 20)
	root.add_child(mob_t)
	es_early.register_entity(mob_t, null, "mob_tick")
	proj.flush(true)  # identity immediate

	mob_t.health_component.current_health = 13
	proj.mark_dirty("mob_tick")
	var before_hash: PackedByteArray = tree.root_hash()
	proj.flush()  # buffered: queues into TickService's command buffer
	var now_hash: PackedByteArray = tree.root_hash()
	_assert(now_hash == before_hash, "buffered flush defers tree mutation (atomic batch pending)")
	var still_old: Dictionary = tree.get_state("/world/zones/unzoned/entities/mob_tick/health")
	if not still_old.is_empty():
		_assert(int(still_old["payload"]["current"]) == 20, "tree still carries pre-damage health")
	# Tick boundary: drain gates on the coalesce window, next tick applies.
	await create_timer(1.5).timeout
	var applied: Dictionary = tree.get_state("/world/zones/unzoned/entities/mob_tick/health")
	_assert(not applied.is_empty() and int(applied["payload"]["current"]) == 13,
			"tick pipeline applied the buffered health write")

	# --- 5. Player live-state half -----------------------------------------
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var player: Node = PlayerScript.new()
	player.display_name = "ProjHero"
	player.entity_id = "proj_char"
	get_root().add_child(player)
	await process_frame
	# Players are EntityService-registered in production; flush resolves
	# ids through it (an unregistered player is treated as gone).
	es_early.register_entity(player, null, "proj_char")

	proj.register_player(player)
	_assert(proj.flush(true) >= 1, "register_player projects live state")

	var pnode: Dictionary = tree.get_state("/world/zones/unzoned/players/proj_char/live")
	_assert(not pnode.is_empty(), "player live node under zone scope")
	if not pnode.is_empty():
		var pl: Dictionary = pnode["payload"]
		_assert(pl.has("pos_x") and pl.has("pos_y") and pl.has("pos_z"), "live payload carries position")
		_assert(float(pl["pos_x"]) == 0.0, "quantized position (origin)")

	# Position change -> next flush rewrites with the new grid coords.
	player.global_position = Vector3(1.2567, 0.0, 2.8911)
	_assert(proj.flush(true) >= 1, "position change flushes")
	var pnode2: Dictionary = tree.get_state("/world/zones/unzoned/players/proj_char/live")
	_assert(not pnode2.is_empty() and is_equal_approx(float(pnode2["payload"]["pos_x"]), 1.26),
			"position quantized to 0.01m grid (1.2567 -> 1.26)")

	# Zone drift (white-box): recorded zone differs from live zone ->
	# stale node deleted in the same batch, live node rewritten.
	proj._projected_player_zone["proj_char"] = "old_zone"
	tree.insert_state("/world/zones/old_zone/players/proj_char/live", "proj_char", "other",
			{"hp_cur": 1, "hp_max": 1, "pos_x": 9.0, "pos_y": 9.0, "pos_z": 9.0})
	player.global_position = Vector3(4.0, 0.0, 4.0)
	proj.flush(true)
	_assert(tree.get_state("/world/zones/old_zone/players/proj_char/live").is_empty(),
			"zone drift tears down the stale scope node")
	_assert(not tree.get_state("/world/zones/unzoned/players/proj_char/live").is_empty(),
			"zone drift rewrites into the live zone")

	# --- 6. Per-zone snapshot pruning ---------------------------------------
	# Two mobs in two zones (white-box zone hints on the health path;
	# identity rides the current zone, hints apply after that drain).
	var mob_a := _make_stub_mob("mob_a", "Zone A Slime", 1, 10, 10)
	var mob_b := _make_stub_mob("mob_b", "Zone B Slime", 1, 10, 10)
	root.add_child(mob_a)
	root.add_child(mob_b)
	es_early.register_entity(mob_a, null, "mob_a")
	es_early.register_entity(mob_b, null, "mob_b")
	proj.flush(true)  # drain registration identity under current zone
	proj._projected_zone["mob_a"] = "zone_a"
	proj._projected_zone["mob_b"] = "zone_b"
	mob_a.health_component.current_health = 9
	mob_b.health_component.current_health = 8
	proj.mark_dirty("mob_a")
	proj.mark_dirty("mob_b")
	var zoned_written: int = proj.flush(true)
	_assert(zoned_written == 2, "two zoned mobs flush one health write each (got %d)" % zoned_written)

	var snap_a: Array = proj.snapshot_for_zone("zone_a")
	var snap_b: Array = proj.snapshot_for_zone("zone_b")
	_assert(snap_a.size() == 1, "zone_a snapshot holds exactly its own node (got %d)" % snap_a.size())
	_assert(snap_b.size() == 1, "zone_b snapshot holds exactly its own node (got %d)" % snap_b.size())
	var a_has_b := false
	for entry in snap_a:
		if str(entry[0]).begins_with("/world/zones/zone_b"):
			a_has_b = true
	_assert(not a_has_b, "zone_a snapshot contains no zone_b nodes (pruning holds)")

	# --- 7. Lifecycle wiring via EntityService ------------------------------
	var es = root.get_node_or_null("EntityService")
	_assert(es != null, "EntityService present")
	if es == null:
		return _finish()

	var mob := _make_stub_mob("mob_lifecycle", "Gel Cube", 3, 22, 22)
	root.add_child(mob)
	var registered_id: String = es.register_entity(mob, null, "mob_lifecycle")
	_assert(registered_id == "mob_lifecycle", "stub mob registered with id override")
	proj.flush(true)

	var lifecycle_read: Dictionary = proj.read_entity("mob_lifecycle")
	_assert(not lifecycle_read.is_empty(), "spawn projected into the tree automatically")
	if not lifecycle_read.is_empty():
		_assert(str(lifecycle_read["identity"]["display_name"]) == "Gel Cube",
				"lifecycle identity from enemy_data stub")

	# Damage marks dirty; the flush picks up current health.
	mob.health_component.current_health = 7
	proj.mark_dirty("mob_lifecycle")
	var flushed: int = proj.flush(true)
	_assert(flushed == 1, "flush writes the damaged mob (got %d)" % flushed)
	var hurt: Dictionary = proj.read_entity("mob_lifecycle")
	_assert(int(hurt["health"]["current"]) == 7, "health flush carries damaged value")

	# Unregister removes the projection.
	es.unregister_entity(mob)
	await process_frame
	proj.flush(true)
	_assert(proj.read_entity("mob_lifecycle").is_empty(), "despawn removed the projection")

	# --- 8. Non-projectable entities ignored --------------------------------
	var bare := _make_stub_mob("mob_bare", "Ghost", 1, 10, 10)
	bare.enemy_data = null
	root.add_child(bare)
	es.register_entity(bare, null, "mob_bare")
	await process_frame
	_assert(proj.read_entity("mob_bare").is_empty(),
			"registered entity without enemy_data produces no nodes")

	# --- 9. Cross-half: one root over character + zone projections ----------
	var fs = root.get_node_or_null("FrameService")
	_assert(fs != null, "FrameService present")
	if fs == null:
		return _finish()

	var progress_script = load("res://core/services/player_progress.gd")
	var progress = progress_script.new()
	get_root().add_child(progress)
	await process_frame
	_assert(progress.save_player(player, "proj_test"), "PlayerProgress save succeeds")

	var shared_tree = fs.get_world_state_tree()
	var char_node: Dictionary = shared_tree.get_state("/player/proj_char/progress")
	_assert(not char_node.is_empty(), "character half visible in the shared world tree")
	var mob_half: Dictionary = shared_tree.get_state("/world/zones/unzoned/entities/mob_a/health")
	_assert(not mob_half.is_empty(), "zone-projected mob half visible in the same tree")
	fs.touch_world_tree()
	_assert(fs.world_root_hash().size() > 0, "world_root_hash non-empty over both halves")

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
