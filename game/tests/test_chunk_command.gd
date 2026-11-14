## test_chunk_command.gd - THE /chunk OPERATOR-SURFACE RECEIPT.
##
## Verifies the canonical clipmap chunk report (labs/prd-clipmap.md sec. 12
## + labs/prd-perf-bridges.md): the multi-iso index now answers "who is in
## THIS canonical chunk" and the report is the in-game reader that ties the
## index to the canonical layer.
##  * non-admins are refused,
##  * an admin's report names the EXACT PropChunk key the sender's position
##    derives (face + cell + area), the same cell a client derives,
##  * the index line reflects the live orchestrator's chunk axis (a body
##    registered at that chunk shows up),
##  * the report is READ-ONLY (no index write follows it).
##
## The sidecar is spawned here so the index leg is live. If julia or
## server_lite.jl is unavailable the index assertion SKIPS honestly.
## Run: cd game && godot --headless --path . --script res://tests/test_chunk_command.gd
extends SceneTree

const SERVER := "/workspace/project/synmergia/srv/julia-bridge/server_lite.jl"
const PROJECT := "/workspace/project/synmergia/srv/julia-bridge"
const SVC_PATH := "res://core/services/multi_iso_service.gd"
const ICOSA := "res://core/frame/math/icosahedral.gd"
const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")
const EntityScript = preload("res://core/entities/entity.gd")

const PORT := 8093
const URL := "http://127.0.0.1:8093"

var _cs: Node
var _perm: Node
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
	var display_name: String = "ChunkProbe"
	var level: int = 1
	var planet_center: Vector3 = Vector3.ZERO
	var team_id: int = 0
	var faction_id: String = "faction_human"


func _initialize() -> void:
	await process_frame
	_cs = root.get_node_or_null("ChatService")
	_perm = root.get_node_or_null("PermissionManager")
	_ns = root.get_node_or_null("NotificationService")
	_es = root.get_node_or_null("EntityService")
	if _cs == null or _perm == null or _ns == null or _es == null:
		push_error("FAIL: required autoloads missing")
		quit(1)
		return
	print("--- CHUNK COMMAND TEST ---")
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
	_perm._validation_cache["chunk_admin"] = {"time": Time.get_ticks_msec(), "level": 100}
	_perm._validation_cache["chunk_player"] = {"time": Time.get_ticks_msec(), "level": 0}

	# --- 1. non-admin refused --------------------------------------------
	_fired.clear()
	_cs._handle_command("chunk_player", 9, "chunk", "")
	await process_frame
	await process_frame
	_ok(_said("Admin permission required"), "non-admin is refused")

	# --- 2. a positioned body, indexed at its canonical chunk -------------
	var ico = load(ICOSA)
	var v0: Vector3 = ico.VERTICES[0].normalized()
	var key: int = PropChunk.chunk_for_dir(v0)
	var face: int = PropChunk.face_of(key)
	var cell: Vector2i = PropChunk.cell_of(key)

	# The sender id IS the body's entity id (the report resolves the
	# sender's own body to find their chunk).
	var body := FakeBody.new()
	body.position = v0 * 20000.0
	root.add_child(body)
	await process_frame
	var eid: String = _es.register_entity(body, null, "chunk_admin")
	await process_frame

	if live and _svc != null:
		_svc._on_entity_registered(body, null)
		for _i in range(60):
			await process_frame

	# --- 3. admin report: the exact canonical cell ------------------------
	_fired.clear()
	_cs._handle_command("chunk_admin", 9, "chunk", "")
	for _i in range(30):
		await process_frame
	_ok(_said("[chunk]"), "report header present")
	_ok(_said("key: %d" % key), "report names the exact PropChunk key")
	_ok(_said("face: %d" % face), "report names the terrain face")
	_ok(_said("cell: (%d, %d)" % [cell.x, cell.y]), "report names the barycentric cell")

	# --- 4. the index line reflects the live chunk axis -------------------
	if live and _svc != null:
		_ok(_said(eid), "the index line names the body registered at that chunk")
		# A body in a foreign chunk is not in this one.
		var foreign: Array = await _svc.query_chunk(key + 1)
		_ok(not foreign.has(eid), "the body is only in its own chunk, not a neighbour")
	else:
		print("[SKIP] index leg: no sidecar; contract legs only")

	# --- 5. READ-ONLY: the report does not mutate the index ---------------
	if live and _svc != null:
		var before: Array = await _svc.query_chunk(key)
		_fired.clear()
		_cs._handle_command("chunk_admin", 9, "chunk", "")
		for _i in range(30):
			await process_frame
		var after: Array = await _svc.query_chunk(key)
		before.sort()
		after.sort()
		_ok(before == after, "the report is read-only (chunk index unchanged)")

	if _es != null:
		_es.unregister_entity(body, "test_cleanup")
	root.remove_child(body)
	body.free()


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
	# Use the REAL autoload MultiIsoService (the node the /chunk report
	# itself reads) pointed at the sidecar, so the report's index line and
	# this receipt share one live index.
	OS.set_environment("MULTI_ISO_URL", URL)
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
	# _svc is the shared autoload -- never free it; just stop the sidecar.
	_svc = null
	if _pid > 0:
		OS.kill(_pid)
		_pid = -1
