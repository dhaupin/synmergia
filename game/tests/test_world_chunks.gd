## test_world_chunks.gd - WorldService.generate_chunk: deterministic
## seed-derived chunk content, in-session and reboot dedup, record
## shape and bounds.
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_world_chunks.gd
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
	var ws = root.get_node_or_null("WorldService")
	_assert(ws != null, "WorldService present")
	if ws == null:
		return _finish()

	ws.world_seed = 4242

	# --- 1. Generate + in-session dedup --------------------------------------
	var a1: Dictionary = ws.generate_chunk("31_-7")
	var a2: Dictionary = ws.generate_chunk("31_-7")
	_assert(not a1.is_empty(), "chunk generates for a valid key")
	_assert(a1 == a2, "same chunk key returns the same record in-session")
	_assert(ws.is_chunk_generated("31_-7"), "is_chunk_generated agrees")
	_assert(ws.generated_chunk_count() >= 1, "count tracks generated chunks")
	_assert(not ws.get_chunk("31_-7").is_empty(), "get_chunk returns the generated record")

	# --- 2. Record shape + bounds ---------------------------------------------
	_assert(a1.has("biome") and a1.has("elevation") and a1.has("seed"), "record carries biome/elevation/seed")
	_assert(a1.get("cx") == 31 and a1.get("cz") == -7, "record carries chunk coords")
	_assert(a1.get("world_seed") == 4242, "record echoes the world seed")
	var res: Array = a1.get("resources", [])
	_assert(res.size() <= 4, "resource count bounded 0..4")
	var res_ok := true
	for r in res:
		if not (r is Dictionary) or not r.has("kind") or not r.has("x") or not r.has("z"):
			res_ok = false
		elif float(r["x"]) < 3100.0 or float(r["x"]) >= 3200.0:
			res_ok = false
		elif float(r["z"]) < -700.0 or float(r["z"]) >= -600.0:
			res_ok = false
	_assert(res_ok, "resource nodes carry kind + in-chunk world positions")
	var hints: Array = a1.get("spawn_hints", [])
	_assert(hints.size() <= 2, "spawn hint count bounded 0..2")

	# --- 3. Determinism across instances (reboot dedup path) ------------------
	# A fresh instance with the same seed loads the persisted record from
	# the kv store instead of regenerating -- both paths must agree.
	var WSScript = load("res://core/services/world_service.gd")
	var ws2 = WSScript.new()
	ws2.world_seed = 4242
	var a3: Dictionary = ws2.generate_chunk("31_-7")
	_assert(a3 == a1, "fresh instance returns the identical record (reboot dedup)")
	ws2.free()

	# --- 4. Seed law: content derives from seed + coords ----------------------
	var s_a: String = str(ws._chunk_seed_bytes(31, -7))
	ws.world_seed = 999
	var s_b: String = str(ws._chunk_seed_bytes(31, -7))
	ws.world_seed = 4242
	var s_c: String = str(ws._chunk_seed_bytes(31, -8))
	_assert(s_a != s_b, "different world seeds derive different chunk seeds")
	_assert(s_a != s_c, "different coords derive different chunk seeds")

	# --- 5. Garbage keys generate nothing -------------------------------------
	_assert(ws.generate_chunk("not_a_chunk").is_empty(), "non-chunk key generates nothing")
	_assert(ws.generate_chunk("1_2_3").is_empty(), "three-part key generates nothing")
	_assert(ws.generate_chunk("x_y").is_empty(), "non-numeric key generates nothing")

	_finish()

func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)

func _finish() -> void:
	print("WorldChunks: %d passed, %d failed" % [_pass, _fail])
