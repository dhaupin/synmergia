## Julia orchestrator LIVE receipt (tests/test_julia_orchestrator_live.gd).
##
## labs/prd-perf-bridges.md: MultiIsoService is an autoload that mirrors
## the entity roster into the Julia multi-iso orchestrator, but until now
## the orchestrator sidecar could never boot in dev/CI (server.jl needs
## HTTP.jl + JSON.jl, whose pkgimages segfault on this Julia build), so
## the "live" path was never exercised end to end. This receipt boots the
## STDLIB-ONLY sibling (`srv/julia-bridge/server_lite.jl`) on a private
## port and drives the REAL MultiIsoService through a register -> query ->
## unregister cycle, asserting the results.
##
## The sidecar is spawned here so the leg is self-contained. If julia or
## server_lite.jl is unavailable the live legs SKIP honestly (the contract
## legs still run).
##
## Legs:
##   0. The MULTI_ISO_URL env seam sets the server URL at boot.
##   1. server_lite.jl boots and answers /health on a private port.
##   2. A fresh MultiIsoService pointed at it reports healthy.
##   3. register_entity -> query_spatial finds it at the vertex.
##   4. query_intersect (spatial x faction x social) finds it.
##   5. query_faction finds it; a foreign faction does not.
##   6. unregister_entity removes it from every axis.
##   7. Disabled service never egresses (contract leg, always runs).
##   8. The REAL EntityService hook buckets a positioned body at the
##      vertex its world position implies (the spatial axis is truthful).
##   9. The canonical clipmap CHUNK axis: register with a PropChunk key ->
##      query_chunk finds it in that exact cell and not a neighbour; the
##      chunk x faction intersection resolves; the REAL hook buckets a
##      positioned body at its canonical chunk (the clipmap tie-in).
##
## Run:
##   godot --headless --path . --script res://tests/test_julia_orchestrator_live.gd
extends SceneTree

const SVC_PATH := "res://core/services/multi_iso_service.gd"
const SERVER := "/workspace/project/synmergia/srv/julia-bridge/server_lite.jl"
const PROJECT := "/workspace/project/synmergia/srv/julia-bridge"
const ICOSA := "res://core/frame/math/icosahedral.gd"
const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")

const PORT := 8092
const URL := "http://127.0.0.1:8092"

var _passed: int = 0
var _failed: int = 0
var _pid: int = -1
var _svc: Node = null


## A minimal world body: the real fields the entity hooks duck-read.
class FakeBody:
	extends Node3D
	var entity_id: String = ""
	var planet_center: Vector3 = Vector3.ZERO
	var team_id: int = 0
	var faction_id: String = ""


func _initialize() -> void:
	print("--- JULIA ORCHESTRATOR LIVE ---")
	await process_frame
	await _test_env_override_contract()
	_test_disabled_contract()
	var live: bool = _boot_sidecar()
	if live:
		await _test_live_cycle()
	else:
		print("[SKIP] server_lite.jl unavailable; live legs skipped")
	_kill_sidecar()
	_finish()


func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] ", msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] ", msg)


## Contract leg (always runs): the MULTI_ISO_URL env seam sets the server
## URL at boot, so a container can point the service at the sidecar's port.
func _test_env_override_contract() -> void:
	var script: GDScript = load(SVC_PATH)
	OS.set_environment("MULTI_ISO_URL", "http://127.0.0.1:65535")
	var svc: Node = script.new()
	root.add_child(svc)
	await process_frame
	if svc.local_server_url == "http://127.0.0.1:65535" and svc.julia_server_url == "http://127.0.0.1:65535":
		_ok("MULTI_ISO_URL env override sets the server URL at boot")
	else:
		_fail("env override ignored: local=%s" % svc.local_server_url)
	root.remove_child(svc)
	svc.free()
	OS.set_environment("MULTI_ISO_URL", "")


## Contract leg (always runs): a disabled service never touches the net.
func _test_disabled_contract() -> void:
	var script: GDScript = load(SVC_PATH)
	if script == null or not script.can_instantiate():
		_fail("multi_iso_service.gd did not load")
		return
	var svc: Node = script.new()
	svc.enabled = false
	root.add_child(svc)
	await process_frame
	var off: Array = await svc.query_spatial(3)
	if off.is_empty():
		_ok("disabled service degrades to empty (no egress)")
	else:
		_fail("disabled service returned data: %s" % str(off))
	root.remove_child(svc)
	svc.free()


func _which(exe: String) -> String:
	var out: Array = []
	if OS.execute("which", [exe], out, true) != 0:
		return ""
	return str(out[0]).strip_edges() if not out.is_empty() else ""


func _boot_sidecar() -> bool:
	var julia := _which("julia")
	if julia.is_empty():
		print("  julia not on PATH")
		return false
	if not FileAccess.file_exists(SERVER):
		print("  server_lite.jl not found at %s" % SERVER)
		return false
	# --compile=min is REQUIRED on this Julia build (its default
	# optimizer miscompiles the request loop to a segfault).
	_pid = OS.create_process(julia, [
		"--startup-file=no", "--compile=min", "--project=" + PROJECT,
		SERVER, "--port", str(PORT)], false)
	if _pid <= 0:
		return false
	for _i in range(80):
		if _health(URL):
			print("  server_lite.jl up on %s (pid %d)" % [URL, _pid])
			return true
		OS.delay_msec(250)
	print("  server_lite.jl did not become healthy")
	return false


func _health(url: String) -> bool:
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


func _test_live_cycle() -> void:
	var script: GDScript = load(SVC_PATH)
	# Pin the URL through the env seam so an ambient MULTI_ISO_URL in the
	# CI container cannot redirect the receipt away from its own sidecar.
	OS.set_environment("MULTI_ISO_URL", URL)
	_svc = script.new()
	_svc.use_localhost = true
	_svc.local_server_url = URL
	_svc.enabled = true
	root.add_child(_svc)
	await process_frame
	await process_frame

	if await _svc.is_healthy():
		_ok("MultiIsoService reports the sidecar healthy")
	else:
		_fail("MultiIsoService could not reach the sidecar")

	var probe := "live_probe_%d" % Time.get_ticks_usec()
	await _svc.register_entity(probe, 3, 7, 2, 1)

	var spatial: Array = await _svc.query_spatial(3)
	if spatial.has(probe):
		_ok("register -> query_spatial finds the entity at vertex 3")
	else:
		_fail("query_spatial missed the entity: %s" % str(spatial))

	var inter: Array = await _svc.query_intersect(3, 7, 2)
	if inter.has(probe):
		_ok("query_intersect (spatial x faction x social) finds it")
	else:
		_fail("query_intersect missed the entity: %s" % str(inter))

	var fac: Array = await _svc.query_faction(7)
	var other: Array = await _svc.query_faction(9)
	if fac.has(probe) and not other.has(probe):
		_ok("query_faction finds it in faction 7, not in faction 9")
	else:
		_fail("query_faction wrong: f7=%s f9=%s" % [str(fac), str(other)])

	# The canonical clipmap chunk axis (prd-clipmap.md sec. 12): the
	# exact cell a client derives is a first-class index axis.
	var chunk: int = PropChunk.chunk_for_dir(Vector3(0, 1, 0))
	var cprobe := "chunk_probe_%d" % Time.get_ticks_usec()
	await _svc.register_entity(cprobe, 3, 7, 0, 0, 2026, chunk)
	var cin: Array = await _svc.query_chunk(chunk)
	var cout: Array = await _svc.query_chunk(chunk + 1)
	if cin.has(cprobe) and not cout.has(cprobe):
		_ok("register with a canonical chunk -> query_chunk finds it in that cell only")
	else:
		_fail("query_chunk wrong: in=%s out=%s" % [str(cin), str(cout)])
	var cinter: Array = await _svc.query_intersect(-1, 7, -1, chunk)
	if cinter.has(cprobe):
		_ok("query_intersect (chunk x faction) finds it")
	else:
		_fail("query_intersect chunk+faction missed: %s" % str(cinter))
	await _svc.unregister_entity(cprobe)
	var cafter: Array = await _svc.query_chunk(chunk)
	if not cafter.has(cprobe):
		_ok("unregister removes it from the chunk axis")
	else:
		_fail("unregistered entity still in chunk: %s" % str(cafter))

	await _svc.unregister_entity(probe)
	var after: Array = await _svc.query_spatial(3)
	if not after.has(probe):
		_ok("unregister_entity removes it from every axis")
	else:
		_fail("unregistered entity still present: %s" % str(after))

	await _test_entity_hook_leg()

	root.remove_child(_svc)
	_svc.free()
	_svc = null


## Drive the REAL EntityService hook (the live consumer): a positioned
## body registers into the vertex its world position implies, not a
## fabricated faction hash. Proves the spatial axis is truthful end to
## end (frame position -> icosahedral vertex -> orchestrator bucket).
func _test_entity_hook_leg() -> void:
	var ico = load(ICOSA)
	var v0: Vector3 = ico.VERTICES[0].normalized()
	var body := FakeBody.new()
	body.entity_id = "hook_probe_%d" % Time.get_ticks_usec()
	body.position = v0 * 20000.0
	body.faction_id = "faction_human"
	root.add_child(body)
	await process_frame

	_svc._on_entity_registered(body, null)
	# The service queues the POST; let it drain to the sidecar.
	for _i in range(60):
		await process_frame

	var hits: Array = await _svc.query_spatial(0)
	if hits.has(body.entity_id):
		_ok("entity hook registers a positioned body at its real vertex 0")
	else:
		_fail("entity hook did not bucket the body at vertex 0: %s" % str(hits))
	var chunk: int = PropChunk.chunk_for_dir(v0)
	var chin: Array = await _svc.query_chunk(chunk)
	if chin.has(body.entity_id):
		_ok("entity hook buckets the body at its canonical clipmap chunk")
	else:
		_fail("entity hook missed the canonical chunk %d: %s" % [chunk, str(chin)])

	_svc._on_entity_unregistered(body, null)
	for _i in range(60):
		await process_frame
	var gone: Array = await _svc.query_spatial(0)
	if not gone.has(body.entity_id):
		_ok("entity hook unregisters the body from the vertex")
	else:
		_fail("entity hook left the body registered: %s" % str(gone))
	var cgone: Array = await _svc.query_chunk(chunk)
	if not cgone.has(body.entity_id):
		_ok("entity hook unregisters the body from the canonical chunk")
	else:
		_fail("entity hook left the body in the chunk: %s" % str(cgone))
	root.remove_child(body)
	body.free()


func _kill_sidecar() -> void:
	if _pid > 0:
		OS.kill(_pid)
		_pid = -1


func _finish() -> void:
	if _failed == 0:
		print("JULIA ORCHESTRATOR LIVE RECEIPT PASS (%d)" % _passed)
		quit(0)
	else:
		printerr("JULIA ORCHESTRATOR LIVE RECEIPT FAIL (%d)" % _failed)
		quit(1)
