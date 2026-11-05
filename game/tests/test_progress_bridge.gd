## test_progress_bridge.gd - PlayerProgress -> StateSchema state tree bridge.
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_progress_bridge.gd
##
## Covers:
##   1. Pure mapping: snapshot -> typed payloads (health/position/inventory)
##      with the XP curve mirroring PlayerProgress.restore_player.
##   2. Quantization: off-grid floats land on the 0.01m grid, then validate.
##   3. write_progress inserts all nodes; root hash reacts (D027 sees diffs).
##   4. Bad input degrades to no-write (empty id / empty snapshot).
##   5. clear_progress removes every node for a character.
##   6. Integration: PlayerProgress.save_player updates the projection;
##      clear_progress wipes store AND tree.
##
## Exit 0 = all pass.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	await process_frame
	# _run awaits internally (integration section needs a frame); without
	# the await here, quit() fires before the coroutine finishes.
	await _run()
	quit(0 if _fail == 0 else 1)


func _run() -> void:
	var BridgeScript = load("res://core/frame/bridge/progress_bridge.gd")
	var bridge = BridgeScript.new()

	# --- 1. Pure mapping -------------------------------------------------
	var snap := {
		"experience": 200, "gold": 250, "level": 2,
		"position": {"x": 1.234, "y": 0.5, "z": -3.0},
	}
	var payloads: Dictionary = BridgeScript.snapshot_to_payloads(snap)
	_assert(payloads.has("health"), "mapping produces health payload")
	_assert(int(payloads["health"]["current"]) == 200, "health.current = experience")
	_assert(int(payloads["health"]["max"]) == 1500,
			"health.max = xp to next (1000*1.5 for level 2, got %d)" % int(payloads["health"]["max"]))
	_assert(payloads.has("inventory"), "mapping produces inventory payload")
	var items: Array = payloads["inventory"]["items"]
	_assert(items.size() == 1 and str(items[0]["id"]) == "gold" and int(items[0]["quantity"]) == 250,
			"inventory carries the gold coin entry")
	_assert(BridgeScript.xp_to_next(1) == 1000, "xp curve level 1 = 1000")
	_assert(BridgeScript.xp_to_next(3) == 2250, "xp curve level 3 = 2250")

	# ---- THE PAST-BAND LAW IS THE CURVE'S, NOT THE OLD 1.5^n (#54) --------
	# The shipped old pin (1000 / 2250) is band-byte-equal under BOTH laws;
	# these legs keep the bridge pinned to LevelCurve past the band, where
	# the breathing ratio diverges from the old 1.5^n explosion.
	var CurveLaw = load("res://core/progression/level_curve.gd")
	var band_top: int = int(float(1000) * pow(1.5, 9))
	_assert(BridgeScript.xp_to_next(11) == CurveLaw.level_cost(11),
			"past-band cost = the breathing band law (band_top x 1.03)")
	_assert(BridgeScript.xp_to_next(11) == int(float(band_top) * pow(1.03, 1)),
			"level 11 = anchored breathing ratio, not 1.5^n (%d)" % BridgeScript.xp_to_next(11))
	_assert(BridgeScript.xp_to_next(12) == int(float(band_top) * pow(1.03, 2)),
			"level 12 compounds the ratio, not the old 1.5")
	_assert(BridgeScript.xp_to_next(12) < int(float(1000) * pow(1.5, 11)),
			"the bridge no longer explodes past the band (curve < old 1.5^n)")

	# No-usable-fields snapshot maps to nothing.
	_assert(BridgeScript.snapshot_to_payloads({}).is_empty(), "empty snapshot maps to {}")
	_assert(BridgeScript.snapshot_to_payloads({"reason": "kill"}).is_empty(),
			"checkpoint-only snapshot maps to {}")

	# --- 2. Quantization + validation --------------------------------------
	var schema = load("res://core/frame/schemas/state_schema.gd").new()
	var q = BridgeScript.quantize_coordinate(1.234567)
	_assert(q != null and absf(float(q) - 1.23) < 0.0001, "off-grid float quantizes to 0.01m")
	_assert(schema._validate({"type": "position", "entity_id": "e",
			"payload": {"x": q, "y": 0.5, "z": -3.0}}) == true,
			"quantized position validates against StateSchema")
	_assert(schema._validate({"type": "position", "entity_id": "e",
			"payload": {"x": 1.234567, "y": 0.5, "z": -3.0}}) == false,
			"raw off-grid float is rejected by StateSchema")
	_assert(BridgeScript.quantize_coordinate("bad") == null, "non-numeric coordinate -> null")

	# --- 3. Tree writes + root-hash reaction --------------------------------
	var hash_a: PackedByteArray = bridge.write_progress("char_b1", snap)
	_assert(hash_a.size() > 0, "write_progress returns a root hash")

	var progress_node: Dictionary = bridge.read_node("char_b1", "progress")
	_assert(not progress_node.is_empty(), "progress node present in tree")
	_assert(str(progress_node.get("type", "")) == "health", "progress node typed health")
	var read_payload: Dictionary = progress_node.get("payload", {})
	_assert(int(read_payload.get("current", -1)) == 200, "tree payload carries xp")

	var pos_node: Dictionary = bridge.read_node("char_b1", "position")
	_assert(str(pos_node.get("type", "")) == "position", "position node typed position")
	var pos_payload: Dictionary = pos_node.get("payload", {})
	_assert(absf(float(pos_payload.get("x", 0.0)) - 1.23) < 0.0001,
			"tree position is on the 0.01m grid")

	var inv_node: Dictionary = bridge.read_node("char_b1", "inventory")
	_assert(str(inv_node.get("type", "")) == "inventory", "inventory node typed inventory")

	var typed: Dictionary = bridge.read_progress("char_b1")
	_assert(typed.size() == 3, "read_progress returns all three typed payloads")

	# A changed value MUST move the root hash (this is the D027 contract).
	var snap_b := snap.duplicate(true)
	snap_b["experience"] = 900
	var hash_b: PackedByteArray = bridge.write_progress("char_b1", snap_b)
	_assert(hash_b != hash_a, "progress change moves the tree root hash (D027 visible)")
	_assert(int(bridge.read_node("char_b1", "progress")["payload"]["current"]) == 900,
			"tree reflects the new xp after rewrite")

	# Per-character isolation in the tree.
	bridge.write_progress("char_b2", {"experience": 5, "gold": 1, "level": 1})
	_assert(int(bridge.read_node("char_b2", "progress")["payload"]["current"]) == 5,
			"second character writes its own nodes")
	_assert(int(bridge.read_node("char_b1", "progress")["payload"]["current"]) == 900,
			"second character does not clobber the first")

	# --- 4. Bad input degrades to no-write ----------------------------------
	_assert(bridge.write_progress("", snap).size() == 0, "empty id writes nothing")
	_assert(bridge.write_progress("char_b3", {}).size() == 0, "empty snapshot writes nothing")
	_assert(bridge.read_node("char_b3", "progress").is_empty(), "no phantom nodes for bad input")

	# --- 5. clear_progress ---------------------------------------------------
	_assert(bridge.clear_progress("char_b1"), "clear_progress removes nodes")
	_assert(bridge.read_node("char_b1", "progress").is_empty(), "progress node gone")
	_assert(bridge.read_node("char_b1", "position").is_empty(), "position node gone")
	_assert(bridge.read_node("char_b1", "inventory").is_empty(), "inventory node gone")
	_assert(not bridge.clear_progress("char_b1"), "second clear returns false (nothing left)")
	_assert(not bridge.read_node("char_b2", "progress").is_empty(),
			"other character's nodes survive the clear")

	# --- 6. Integration with PlayerProgress ---------------------------------
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var progress_script = load("res://core/services/player_progress.gd")
	var progress = progress_script.new()
	get_root().add_child(progress)
	await process_frame

	var player: Node = PlayerScript.new()
	player.display_name = "BridgeHero"
	player.entity_id = "bridge_char"
	get_root().add_child(player)
	await process_frame
	player.add_experience(300)
	player.add_gold(75)

	_assert(progress.save_player(player, "bridge_test"), "save_player succeeds")
	var pbridge = progress.state_tree_bridge()
	_assert(pbridge != null, "PlayerProgress exposes the bridge")
	var proj: Dictionary = pbridge.read_progress("bridge_char")
	_assert(proj.has("health"), "checkpoint projected into the state tree")
	_assert(int(proj["health"]["current"]) == 300, "projection carries saved xp")
	_assert(proj.has("position"), "in-tree player projects a position node")
	_assert(proj.has("inventory"), "projection carries the inventory node")

	progress.clear_progress("bridge_char")
	_assert(pbridge.read_progress("bridge_char").is_empty(),
			"PlayerProgress.clear_progress wipes the tree projection too")

	_finish()


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)


func _finish() -> void:
	print("ProgressBridge: %d passed, %d failed" % [_pass, _fail])
