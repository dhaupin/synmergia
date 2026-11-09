## test_agent_coordinator.gd - LIVE receipt for the multi-agent roster + the
## door's remote posture (labs/prd-agent-play.md sec 8-9).
##
##   cd game && xvfb-run godot --path . --script res://tests/test_agent_coordinator.gd
##
## Legs:
##   1. roster: register / list / get / pause / resume / terminate.
##   2. delegate -> step -> poll: a real move runs on the local seat.
##   3. the sign-off gate: a gated verb parks, approve runs it, reject buries it.
##   4. round-robin: two agents each get exactly one turn.
##   5. door auth: fail-closed when SYN_AGENT_TOKEN is set (no header dies).
##   6. door /coord: the multi-agent wire the door serves (the generic MCP
##      projection now lives in gamestruct, so POST /call is GONE).
extends SceneTree

var _pass := 0
var _fail := 0
var _globe: Node = null
var _boot = null
var _player: Node = null
var _driver: Node = null
var _coord: Node = null
var _door: Node = null


func _initialize() -> void:
	print("=== AGENT COORDINATOR LIVE TEST ===")
	_boot = load("res://tests/support/globe_boot.gd")
	_boot_globe.call_deferred()


func _boot_globe() -> void:
	_globe = await _boot.boot(self)
	if _globe == null:
		print("  FAIL: could not load globe_world.tscn")
		quit(1)
		return
	current_scene = _globe
	_run.call_deferred()


func _run() -> void:
	_driver = root.get_node_or_null("AgentDriver")
	_coord = root.get_node_or_null("AgentCoordinator")
	_door = root.get_node_or_null("AgentDoor")
	_assert(_coord != null, "AgentCoordinator autoload present")
	if _coord == null:
		return _finish()
	_driver.set_enabled(true)
	_player = _boot.player(_globe)

	_leg_roster()
	await _leg_delegate_move()
	_leg_gate()
	await _leg_round_robin()
	_leg_door_auth()
	await _leg_door_coord()
	_finish()


func _leg_roster() -> void:
	var r: Dictionary = _coord.register("alpha", {"name": "Alpha", "role": "scout"})
	_assert(bool(r.get("ok", false)), "register alpha")
	var dup: Dictionary = _coord.register("alpha", {})
	_assert(not bool(dup.get("ok", true)), "duplicate handle refused")
	var list: Array = _coord.list_agents()
	_assert(list.size() == 1 and String(list[0]["handle"]) == "alpha", "roster lists alpha")
	_assert(bool(_coord.pause("alpha")), "pause alpha")
	_assert(String(_coord.get_agent("alpha")["state"]) == "paused", "paused state holds")
	_assert(bool(_coord.resume("alpha")), "resume alpha")
	_assert(String(_coord.get_agent("alpha")["state"]) == "idle", "resumed to idle")


func _leg_delegate_move() -> void:
	var before: Vector3 = _player.global_position
	var d: Dictionary = _coord.delegate("alpha", {"verb": "move", "args": {"forward": 1.0}})
	_assert(bool(d.get("ok", false)) and not bool(d.get("gated", true)), "delegate move is queued (not gated)")
	var s: Dictionary = _coord.step()
	_assert(bool(s.get("ok", false)) and String(s.get("handle", "")) == "alpha", "step ran alpha's turn")
	for i in range(30):
		await process_frame
	_driver.act("stop", {})
	var moved: float = before.distance_to(_player.global_position)
	_assert(moved > 0.05, "delegated move rode the real input map (%.3f m)" % moved)
	var poll: Dictionary = _coord.poll_work("alpha")
	_assert(bool(poll.get("ok", false)), "poll_work returns the finished item")
	print("    [delegate] moved %.3f m" % moved)


func _leg_gate() -> void:
	# A name-gated verb parks before it can run.
	var d: Dictionary = _coord.delegate("alpha", {"verb": "spend", "args": {"amount": 5}})
	_assert(bool(d.get("ok", false)) and bool(d.get("gated", false)), "gated verb parks for approval")
	var wid: int = int(d.get("work_id", 0))
	var s: Dictionary = _coord.step()
	_assert(not bool(s.get("ok", true)), "step runs nothing while work awaits approval")
	var q: Array = _coord.queue_of("alpha")
	var parked: bool = false
	for it in q:
		if int(it["work_id"]) == wid and String(it["state"]) == "pending_approval":
			parked = true
	_assert(parked, "queue shows the item pending_approval")
	_assert(bool(_coord.approve("alpha", wid).get("ok", false)), "approve moves it to queued")
	var s2: Dictionary = _coord.step()
	_assert(bool(s2.get("ok", false)), "step runs the approved item")
	# A requires_approval flag gates a normally-open verb.
	var d2: Dictionary = _coord.delegate("alpha", {"verb": "move", "args": {"forward": 1.0}, "requires_approval": true})
	_assert(bool(d2.get("gated", false)), "requires_approval flag also gates")
	var rej: Dictionary = _coord.reject("alpha", int(d2.get("work_id", 0)), "no")
	_assert(bool(rej.get("ok", false)), "reject buries the gated item")


func _leg_round_robin() -> void:
	_coord.register("beta", {"name": "Beta"})
	_coord.delegate("alpha", {"verb": "move", "args": {"forward": 1.0}})
	_coord.delegate("beta", {"verb": "move", "args": {"forward": 1.0}})
	var s1: Dictionary = _coord.step()
	var s2: Dictionary = _coord.step()
	var h1: String = String(s1.get("handle", ""))
	var h2: String = String(s2.get("handle", ""))
	_assert(h1 != "" and h2 != "" and h1 != h2, "round-robin gave each agent one turn (%s, %s)" % [h1, h2])
	for i in range(10):
		await process_frame
	_driver.act("stop", {})


func _leg_door_auth() -> void:
	# The auth gate is a pure function; test it directly (never _route on the
	# main thread -- _route blocks on the driver, which only the main thread
	# drains, so calling it here would deadlock).
	OS.set_environment("SYN_AGENT_TOKEN", "")
	_assert(_door._authorized({}), "no-token door is open (loopback dev posture)")
	OS.set_environment("SYN_AGENT_TOKEN", "s3cret")
	_assert(not _door._authorized({}), "missing bearer is refused (fail closed)")
	_assert(_door._authorized({"authorization": "Bearer s3cret"}), "correct bearer is allowed")
	_assert(_door._authorized({"x-api-key": "s3cret"}), "x-api-key is accepted too")
	_assert(not _door._authorized({"authorization": "Bearer nope"}), "wrong bearer is refused")
	OS.set_environment("SYN_AGENT_TOKEN", "")


func _leg_door_coord() -> void:
	var port: int = _door.start(0)
	_assert(port > 0, "door binds an ephemeral port")
	if port <= 0:
		return
	# the multi-agent wire: POST /coord {op, ...}
	var reg := await _http_post(port, "/coord", {"op": "register", "handle": "gamma", "opts": {"name": "Gamma"}})
	_assert(bool(reg.get("ok", false)), "POST /coord {op:register} lands on the roster")
	var has_gamma: bool = false
	for a in _coord.list_agents():
		if String(a["handle"]) == "gamma":
			has_gamma = true
	_assert(has_gamma, "door-registered agent lands on the roster")
	# the generic MCP projection is GONE from the door (gamestruct owns it now)
	var call := await _http_post(port, "/call", {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
	_assert(not bool(call.get("ok", true)), "POST /call is GONE (MCP projection lives in gamestruct)")
	var tools := await _http_get(port, "/tools")
	_assert(not bool(tools.get("ok", true)), "GET /tools is GONE (tool catalog lives in gamestruct)")
	_door.stop()


func _http_get(port: int, path: String) -> Dictionary:
	return await _request(port, "GET", path, "")

func _http_post(port: int, path: String, body: Dictionary) -> Dictionary:
	return await _request(port, "POST", path, JSON.stringify(body))

func _request(port: int, method: String, path: String, payload: String) -> Dictionary:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", port) != OK:
		return {}
	var deadline: int = Time.get_ticks_msec() + 5000
	while peer.get_status() != StreamPeerTCP.STATUS_CONNECTED and Time.get_ticks_msec() < deadline:
		await process_frame
		peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return {}
	var req: String = (
		"%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\n" % [method, path]
		+ "Content-Type: application/json\r\n"
		+ "Content-Length: %d\r\n" % payload.to_utf8_buffer().size()
		+ "Connection: keep-alive\r\n\r\n" + payload
	)
	peer.put_data(req.to_utf8_buffer())
	var raw := PackedByteArray()
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		peer.poll()
		var avail: int = peer.get_available_bytes()
		if avail > 0:
			var chunk: Array = peer.get_partial_data(avail)
			if chunk[0] == OK:
				raw.append_array(chunk[1])
		var text: String = raw.get_string_from_utf8()
		var sep: int = text.find("\r\n\r\n")
		if sep >= 0 and text.substr(sep + 4).strip_edges() != "":
			var parsed = JSON.parse_string(text.substr(sep + 4))
			peer.disconnect_from_host()
			return parsed if parsed is Dictionary else {}
	peer.disconnect_from_host()
	return {}


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] %s" % label)
	else:
		_fail += 1
		print("  [FAIL] %s" % label)


func _finish() -> void:
	print("=== AGENT COORDINATOR: %d passed / %d failed ===" % [_pass, _fail])
	if _globe != null and is_instance_valid(_globe):
		_globe.free()
	quit(0 if _fail == 0 else 1)
