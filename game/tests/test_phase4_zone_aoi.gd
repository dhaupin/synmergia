## test_phase4_zone_aoi.gd - TickService Phase 4 zone-aware AOI + LOD.
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_phase4_zone_aoi.gd
##
## Covers:
##   1. Peer resolution works again (PlayerManager.get_local_player_id);
##      the dead get_player_info() probe is gone.
##   2. Zone-scoped diff entries reach a client whose AOI overlaps the
##      zone's spatial box (horde state reaches nearby clients).
##   3. Entries from a distant zone are EXCLUDED (no cross-zone leaks).
##   4. Non-spatial entries (character progress) always reach the client.
##   5. LOD L1 strips /world/zones/ payload bytes, keeps structure;
##      L0 passes everything through.
##   6. _phase4_diff_emit runs without a network peer (no crash).
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
	var tick = root.get_node_or_null("TickService")
	var zm = root.get_node_or_null("ZoneManager")
	var es = root.get_node_or_null("EntityService")
	var pm = root.get_node_or_null("PlayerManager")
	var fs = root.get_node_or_null("FrameService")
	_assert(tick != null, "TickService present")
	_assert(zm != null, "ZoneManager present")
	_assert(es != null, "EntityService present")
	_assert(pm != null, "PlayerManager present")
	if tick == null or zm == null or es == null or pm == null:
		return _finish()
	# Freeze the live tick loop: Phase 3 re-roots every tick and would
	# race the manual prev/cur hash window below. This suite drives the
	# AOI functions directly with its own hash pairs.
	if tick._tick_timer != null:
		tick._tick_timer.stop()

	# --- 1. Peer -> player resolution --------------------------------------
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var player: Node = PlayerScript.new()
	player.display_name = "AoiHero"
	player.entity_id = "aoi_char"
	root.add_child(player)
	await process_frame
	es.register_entity(player, null, "aoi_char")
	pm.set_local_player(player)
	await process_frame

	_assert(tick._get_player_id_from_peer(1) == "aoi_char",
			"peer 1 resolves to the local player entity id")

	# --- Test zone near the player ------------------------------------------
	var ZoneDataScript = load("res://core/schemas/zone_data.gd")
	var zone_a = ZoneDataScript.new()
	zone_a.id = "aoi_zone"
	zone_a.zone_center = Vector3(0, 0, 0)
	zone_a.zone_radius = 100.0
	zm.register_zone(zone_a)

	# --- Distant zone -------------------------------------------------------
	var zone_b = ZoneDataScript.new()
	zone_b.id = "far_zone"
	zone_b.zone_center = Vector3(20000, 0, 20000)
	zone_b.zone_radius = 100.0
	zm.register_zone(zone_b)

	var tree = fs.get_world_state_tree()
	_assert(tree != null, "shared world tree available")
	if tree == null:
		return _finish()

	# --- 2+3+4. Diff routing -------------------------------------------------
	# Baseline hash, then three changes: near-zone horde node, far-zone
	# node, and a non-spatial character node.
	var prev: PackedByteArray = tree.root_hash()
	tree.insert_state("/world/zones/aoi_zone/entities/horde_1/health",
			"horde_1", "health", {"current": 10, "max": 10})
	tree.insert_state("/world/zones/far_zone/entities/mob_x/health",
			"mob_x", "health", {"current": 5, "max": 5})
	tree.insert_state("/player/aoi_char/progress", "aoi_char", "health",
			{"current": 100, "max": 200})
	var cur: PackedByteArray = tree.root_hash()
	_assert(cur != prev, "tree root hash moved after inserts")

	tick._previous_root_hash = prev
	tick._current_root_hash = cur
	var aoi: Dictionary = tick._compute_aoi_diff(1)

	var seen: Array = []
	for chunk_key in aoi.keys():
		for entry in aoi[chunk_key]:
			if entry is Array and entry.size() >= 4:
				# Diff entries carry raw (slash-less) paths; normalize.
				var p: String = str(entry[0])
				seen.append(p if p.begins_with("/") else "/" + p)

	var has_near := false
	var has_far := false
	var has_progress := false
	for p in seen:
		if p.begins_with("/world/zones/aoi_zone/"):
			has_near = true
		if p.begins_with("/world/zones/far_zone/"):
			has_far = true
		if p.begins_with("/player/aoi_char/"):
			has_progress = true
	_assert(has_near, "near-zone horde entry reaches the client")
	_assert(not has_far, "far-zone entry is excluded (no cross-zone leak)")
	_assert(has_progress, "character progress entry reaches its owner")

	# --- 5. LOD tiers --------------------------------------------------------
	# L0 (default momentum): everything passes through untouched.
	var synthetic := {
		"0_0": [
			["/world/zones/aoi_zone/entities/horde_1/health", PackedByteArray(), PackedByteArray([1, 2]), PackedByteArray([9])],
			["/player/aoi_char/progress", PackedByteArray(), PackedByteArray([3, 4]), PackedByteArray([8])],
		],
	}
	var l0: Dictionary = tick._apply_lod(1, synthetic)
	var l0_zone_bytes: int = l0["0_0"][0][3].size()
	var l0_other_bytes: int = l0["0_0"][1][3].size()
	_assert(l0_zone_bytes == 1 and l0_other_bytes == 1, "L0 keeps full payloads")

	# Force high load: L1 strips live-half bytes, keeps structure.
	tick._flywheel_momentum = tick.FLYWHEEL_HIGH_THRESHOLD
	_assert(tick._get_client_lod_level(1) == 1, "high load downgrades client to L1")
	var l1: Dictionary = tick._apply_lod(1, synthetic)
	var l1_zone_bytes: int = l1["0_0"][0][3].size()
	var l1_other_bytes: int = l1["0_0"][1][3].size()
	var l1_zone_path := str(l1["0_0"][0][0])
	_assert(l1_zone_path == "/world/zones/aoi_zone/entities/horde_1/health", "L1 keeps entry structure (path)")
	_assert(l1_zone_bytes == 0, "L1 strips zone-half payload bytes")
	_assert(l1_other_bytes == 1, "L1 keeps character-half payload bytes")
	tick._flywheel_momentum = 0.0
	_assert(tick._get_client_lod_level(1) == 0, "load clears -> clients return to L0")

	# --- 6. Phase 4 without a network peer -----------------------------------
	var result: Dictionary = tick._phase4_diff_emit()
	_assert(result.has("clients_emit"), "phase 4 emit runs headless without crashing")

	_finish()

func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)

func _finish() -> void:
	print("Phase4ZoneAoi: %d passed, %d failed" % [_pass, _fail])
