## Chunk-query gameplay consumer receipt (the /nearby reader).
##
## labs/prd-perf-bridges.md Facet 5 landed the multi-iso index's canonical
## chunk axis but only receipts + the admin /chunk command read it; the
## documented "next multi-round item" is wiring the chunk query into a
## gameplay consumer. This receipt proves ChunkInterest + the player-facing
## /nearby command:
##   1. ChunkInterest.canonical_chunk_of derives the EXACT PropChunk key a
##      positioned body's planet-radial direction implies (the canonical
##      layer tie-in).
##   2. local_players_in_cell finds a nearby player through the physics
##      truth (EntityInterest), scoped to the cell's angular radius.
##   3. /nearby is PLAYER-FACING (no admin gate) and reports the canonical
##      cell (key + face + cell).
##   4. The local line names the nearby player.
##   5. The index line reflects the live orchestrator (a body registered at
##      that chunk is counted) -- SKIPS honestly without the sidecar.
##   6. The index line degrades honestly when the index is unavailable.
##
## Run: cd game && godot --headless --path . --script res://tests/test_chunk_nearby.gd
extends SceneTree

const SERVER := "/workspace/project/synmergia/srv/julia-bridge/server_lite.jl"
const PROJECT := "/workspace/project/synmergia/srv/julia-bridge"
const ICOSA := "res://core/frame/math/icosahedral.gd"
const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")
const ChunkInterest = preload("res://core/services/chunk_interest.gd")

const PORT := 8094
const URL := "http://127.0.0.1:8094"

var _cs: Node
var _ns: Node
var _es: Node
var _svc: Node = null
var _pid: int = -1
var _fired: Array = []
var _fails := 0
var _passes := 0


class FakeBody:
	extends Node3D
	var entity_id: String = ""
	var entity_type: int = 1        # Entity.EntityType.PLAYER
	var display_name: String = "NearbyProbe"
	var level: int = 1
	var planet_center: Vector3 = Vector3.ZERO
	var team_id: int = 0
	var faction_id: String = "faction_human"


func _initialize() -> void:
	await process_frame
	_cs = root.get_node_or_null("ChatService")
	_ns = root.get_node_or_null("NotificationService")
	_es = root.get_node_or_null("EntityService")
	if _cs == null or _ns == null or _es == null:
		push_error("FAIL: required autoloads missing")
		quit(1)
		return
	print("--- CHUNK NEARBY TEST ---")
	_ns.notification_sent.connect(func(_pid2, n):
		_fired.append(str(n.get("message", "") if n is Dictionary else n)))
	var live: bool = await _boot_sidecar()
	await _run(live)
	_kill_sidecar()
	print("--- RESULT: %d passed, %d failed ---" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("PASS: ", label)
	else:
		_fails += 1
		push_error("FAIL: %s" % label)


func _said(needle: String) -> bool:
	for m in _fired:
		if m.find(needle) != -1:
			return true
	return false


func _run(live: bool) -> void:
	var ico = load(ICOSA)
	var v0: Vector3 = ico.VERTICES[0].normalized()
	var key: int = PropChunk.chunk_for_dir(v0)
	var face: int = PropChunk.face_of(key)
	var cell: Vector2i = PropChunk.cell_of(key)

	# Two bodies sharing the canonical cell: the sender + a nearby player.
	var me := FakeBody.new()
	me.position = v0 * 20000.0
	me.entity_id = "nearby_me"
	root.add_child(me)
	var peer := FakeBody.new()
	peer.position = v0 * 20000.0
	peer.entity_id = "nearby_peer"
	peer.display_name = "NearbyPeer"
	root.add_child(peer)
	await process_frame
	_es.register_entity(me, null, "nearby_me")
	_es.register_entity(peer, null, "nearby_peer")
	await process_frame

	# 1. The canonical layer tie-in: the derived key is the exact PropChunk cell.
	_ok(ChunkInterest.canonical_chunk_of(me) == key,
		"canonical_chunk_of derives the exact PropChunk key")

	# 2. The local physics-truth read finds the nearby player.
	var local: Array = ChunkInterest.local_players_in_cell(me)
	var local_ids: Array = []
	for p in local:
		if is_instance_valid(p) and "entity_id" in p:
			local_ids.append(str(p.entity_id))
	_ok(local_ids.has("nearby_peer"), "local_players_in_cell finds the nearby player")
	_ok(not local_ids.has("nearby_me"), "the sender is excluded from its own local read")

	if live and _svc != null:
		_svc._on_entity_registered(me, null)
		for _i in range(60):
			await process_frame

	# 3. /nearby is player-facing (no admin gate) and names the canonical cell.
	_fired.clear()
	_cs._handle_command("nearby_me", 9, "nearby", "")
	for _i in range(30):
		await process_frame
	_ok(_said("[nearby]"), "player-facing /nearby report header present")
	_ok(_said("Admin permission required") == false, "/nearby has no admin gate")
	_ok(_said("canonical cell %d" % key), "report names the exact canonical cell")
	_ok(_said("face %d" % face), "report names the terrain face")

	# 4. The local line names the nearby player.
	_ok(_said("nearby_peer"), "the local line names the nearby player")

	# 5. The index line reflects the live orchestrator's chunk axis.
	if live and _svc != null:
		_ok(_said("index: 1 entity in this cell") or _said("index: 2 entities in this cell"),
			"the index line counts the body registered at that chunk")
	else:
		print("[SKIP] index leg: no sidecar; contract legs only")

	# 6. The index read degrades honestly when the service is unavailable.
	var off := ChunkInterest.new()
	var saved_enabled: bool = _svc.enabled if _svc != null else false
	if _svc != null:
		_svc.enabled = false
	var unavailable: Dictionary = await ChunkInterest.query_index_cell(key)
	if _svc != null:
		_svc.enabled = saved_enabled
	_ok(bool(unavailable.get("available", true)) == false or _svc == null,
		"query_index_cell reports unavailable rather than fabricating (disabled leg)")
	_ok((unavailable.get("ids", []) as Array).is_empty(),
		"an unavailable index returns no ids")

	if _es != null:
		_es.unregister_entity(me, "test_cleanup")
		_es.unregister_entity(peer, "test_cleanup")
	root.remove_child(me)
	me.free()
	root.remove_child(peer)
	peer.free()


func _which(exe: String) -> String:
	var out: Array = []
	if OS.execute("which", [exe], out, true) != 0:
		return ""
	return str(out[0]).strip_edges() if not out.is_empty() else ""


func _boot_sidecar() -> bool:
	var julia := _which("julia")
	if julia.is_empty() or not FileAccess.file_exists(SERVER):
		print("  (no julia sidecar; index leg will skip)")
		return false
	_pid = OS.create_process(julia, [
		"--startup-file=no", "--compile=min", "--project=" + PROJECT,
		SERVER, "--port", str(PORT)], false)
	if _pid <= 0:
		return false
	for _i in range(80):
		if _health():
			print("  server_lite.jl up on %s (pid %d)" % [URL, _pid])
			break
		OS.delay_msec(250)
	_svc = root.get_node_or_null("MultiIsoService")
	if _svc == null:
		print("  (no MultiIsoService autoload; index leg will skip)")
		return false
	_svc.use_localhost = true
	_svc.local_server_url = URL
	_svc.enabled = true
	await process_frame
	await process_frame
	return true


func _health() -> bool:
	var c := HTTPClient.new()
	if c.connect_to_host("127.0.0.1", PORT) != OK:
		return false
	var deadline := Time.get_ticks_msec() + 1500
	while c.get_status() == HTTPClient.STATUS_CONNECTING or c.get_status() == HTTPClient.STATUS_RESOLVING:
		if Time.get_ticks_msec() > deadline:
			return false
		c.poll()
		OS.delay_msec(20)
	if c.get_status() != HTTPClient.STATUS_CONNECTED:
		return false
	if c.request(HTTPClient.METHOD_GET, "/health", PackedStringArray(["Accept: application/json"]), "") != OK:
		return false
	var dl2 := Time.get_ticks_msec() + 1500
	while c.get_status() == HTTPClient.STATUS_REQUESTING:
		if Time.get_ticks_msec() > dl2:
			return false
		c.poll()
		OS.delay_msec(20)
	var ok := c.has_response() and c.get_response_code() == 200
	c.close()
	return ok


func _kill_sidecar() -> void:
	_svc = null
	if _pid > 0:
		OS.kill(_pid)
		_pid = -1
