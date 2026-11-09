## test_agent_driver.gd - LIVE receipt for the agent-play control layer
## (labs/prd-agent-play.md). Boots the real globe and drives it through the
## SAME verbs an agent/companion app uses: observe() -> act() -> wait_for(),
## plus a real HTTP round-trip through the AgentDoor transport.
##
##   cd game && xvfb-run godot --path . --script res://tests/test_agent_driver.gd
##
## Legs:
##   1. observe() reports in_world + a structured player block.
##   2. movement rides the REAL input map (action_press) -- the body walks.
##   3. wait_for resolves (in_world) and honestly times out on a false pred.
##   4. act() refuses unknown verbs / missing handles by name.
##   5. the AgentDoor serves a real HTTP request (thread -> driver -> socket).
##   6. the door speaks the gamestruct wire (POST /act {id,verb,value}, /coord,
##      /see), and the generic projections (/tools, /call) are gone (gamestruct
##      owns them).
##   7. see() captures a real PNG (the eyes verb) that the agent reads itself.
##
## Exit 0 = every leg observed. Failures print FAIL lines and exit 1.
extends SceneTree

var _pass := 0
var _fail := 0

var _globe: Node = null
var _boot = null
var _player: Node = null
var _driver: Node = null
var _door: Node = null


func _initialize() -> void:
	print("=== AGENT DRIVER LIVE TEST: booting globe scene ===")
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
	_door = root.get_node_or_null("AgentDoor")
	_assert(_driver != null, "AgentDriver autoload present")
	_assert(_door != null, "AgentDoor autoload present")
	if _driver == null:
		return _finish()

	# A shipped server keeps the door closed; the test opens it.
	_driver.set_enabled(true)
	_player = _boot.player(_globe)
	_assert(_player != null, "local player present on the globe")

	_leg_observe()
	await _leg_move()
	await _leg_wait_for()
	_leg_refusals()
	_leg_handle_verbs()
	_leg_see()
	await _leg_door()
	await _leg_door_wire()

	_finish()


func _leg_observe() -> void:
	var obs: Dictionary = _driver.observe()
	_assert(bool(obs.get("ok", false)), "observe() returns ok")
	_assert(bool(obs.get("in_world", false)), "observe() reports in_world")
	var p = obs.get("player", null)
	_assert(p is Dictionary, "observe() carries a structured player block")
	if p is Dictionary:
		_assert(p.has("position") and p.has("health"), "player block has position + health")
	_assert(obs.get("actions") is Array, "observe() carries the actionable list")
	print("    [observe] scene=%s actions=%d" % [str(obs.get("scene", "")), (obs.get("actions", []) as Array).size()])


func _leg_move() -> void:
	var before: Vector3 = _player.global_position
	var r: Dictionary = _driver.act("move", {"forward": 1.0})
	_assert(bool(r.get("ok", false)), "act(move forward) accepted")
	# Walk for a few frames, then stop.
	for i in range(30):
		await process_frame
	_driver.act("stop", {})
	var after: Vector3 = _player.global_position
	var moved: float = before.distance_to(after)
	_assert(moved > 0.05, "movement rides the real input map (moved %.3f m)" % moved)
	print("    [move] travelled %.3f m" % moved)


func _leg_wait_for() -> void:
	var ok: Dictionary = await _driver.wait_for({"in_world": true}, 2000)
	_assert(bool(ok.get("ok", false)), "wait_for(in_world) resolves")
	var to: Dictionary = await _driver.wait_for({"event": "never_fires_xyz"}, 250)
	_assert(not bool(to.get("ok", true)), "wait_for times out honestly on a false predicate")
	_assert(String(to.get("reason", "")) == "timeout", "timeout carries the honest reason")


func _leg_refusals() -> void:
	var unknown: Dictionary = _driver.act("fly_to_moon", {})
	_assert(not bool(unknown.get("ok", true)), "unknown verb refused")
	var missing: Dictionary = _driver.act("ui:Does/Not/Exist", {})
	_assert(not bool(missing.get("ok", true)), "missing handle refused by name")
	# A real handle, when the world offers one, activates.
	var obs: Dictionary = _driver.observe()
	var acts: Array = obs.get("actions", [])
	for a in acts:
		if String(a.get("id", "")) != "":
			var r: Dictionary = _driver.act(String(a["id"]), {})
			_assert(r.has("ok"), "act() on a real handle returns a verdict")
			print("    [act] handle %s -> ok=%s" % [str(a["id"]), str(r.get("ok", false))])
			return
	print("    [act] no actionable handle surfaced in this scene (refusal legs hold)")


## The gamestruct value write: set_value on a text control lands (and shows in
## the next observe); set_value on a non-settable control or an unknown handle
## is an HONEST refusal, never a silent success. This is the class the live
## play-test caught (set_value returned ok while the field stayed empty).
func _leg_handle_verbs() -> void:
	var obs: Dictionary = _driver.observe()
	var acts: Array = obs.get("actions", [])
	var line_handle: String = ""
	for a in acts:
		if String(a.get("kind", "")) == "lineedit" and String(a.get("id", "")) != "":
			line_handle = String(a["id"])
			break
	if line_handle == "":
		print("    [set_value] no text control in this scene (refusal legs hold)")
		return
	var w: Dictionary = _driver.act(line_handle, {"verb": "set_value", "value": "agent-typed"})
	_assert(bool(w.get("ok", false)), "set_value on a text control lands")
	var after: Dictionary = _driver.observe()
	var shown: bool = false
	for a in after.get("actions", []):
		if String(a.get("id", "")) == line_handle and String(a.get("value", "")) == "agent-typed":
			shown = true
			break
	_assert(shown, "the written value is visible in the next observe")
	# A button holds no value -> honest refusal.
	var button_handle: String = ""
	for a in acts:
		if String(a.get("kind", "")) == "button" and String(a.get("id", "")) != "":
			button_handle = String(a["id"])
			break
	if button_handle != "":
		var b: Dictionary = _driver.act(button_handle, {"verb": "set_value", "value": "x"})
		_assert(not bool(b.get("ok", true)), "set_value on a button is refused honestly")
	var ghost: Dictionary = _driver.act("ui:No/Such/Field", {"verb": "set_value", "value": "x"})
	_assert(not bool(ghost.get("ok", true)), "set_value on an unknown handle is refused")


## see() is the EYES verb: capture the current frame to a PNG the agent reads
## with its own vision. The leg proves a real image lands (a sane size + PNG
## magic), and that a blank frame would be refused (the size floor).
func _leg_see() -> void:
	var r: Dictionary = _driver.act("see", {"label": "receipt"})
	_assert(bool(r.get("ok", false)), "see() captures a frame")
	if not bool(r.get("ok", false)):
		print("    [see] refused: %s" % String(r.get("reason", "")))
		return
	var path: String = String(r.get("path", ""))
	_assert(path != "" and FileAccess.file_exists(path), "the capture file exists on disk")
	_assert(int(r.get("bytes", 0)) >= 1024, "the capture is a real image (not skeletal)")
	_assert(int(r.get("width", 0)) > 0 and int(r.get("height", 0)) > 0, "the capture reports its size")
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		var magic := f.get_buffer(8)
		f.close()
		_assert(magic == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), "the capture is a real PNG (magic bytes)")
	print("    [see] %s (%d bytes, %dx%d)" % [path.get_file(), int(r.get("bytes", 0)), int(r.get("width", 0)), int(r.get("height", 0))])


func _leg_door() -> void:
	var port: int = _door.start(0)
	_assert(port > 0, "AgentDoor binds an ephemeral port")
	if port <= 0:
		return
	var peer := StreamPeerTCP.new()
	var err: int = peer.connect_to_host("127.0.0.1", port)
	if err != OK:
		_assert(false, "door client connects")
		return
	# Wait for the TCP handshake.
	var deadline: int = Time.get_ticks_msec() + 5000
	while peer.get_status() != StreamPeerTCP.STATUS_CONNECTED and Time.get_ticks_msec() < deadline:
		await process_frame
		peer.poll()
	_assert(peer.get_status() == StreamPeerTCP.STATUS_CONNECTED, "door client connected")
	var req: String = "GET /observe HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: keep-alive\r\n\r\n"
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
		if raw.size() > 0 and raw.get_string_from_utf8().find("\r\n\r\n") >= 0:
			var text: String = raw.get_string_from_utf8()
			var sep: int = text.find("\r\n\r\n")
			var body: String = text.substr(sep + 4)
			if body.strip_edges() != "":
				break
	var body_text: String = ""
	var full: String = raw.get_string_from_utf8()
	var s: int = full.find("\r\n\r\n")
	if s >= 0:
		body_text = full.substr(s + 4)
	var parsed = JSON.parse_string(body_text)
	_assert(parsed is Dictionary, "door /observe returns JSON")
	if parsed is Dictionary:
		_assert(bool(parsed.get("in_world", false)), "door /observe reports the live world")
		print("    [door] HTTP /observe in_world=%s actions=%d" % [
			str(parsed.get("in_world", false)), (parsed.get("actions", []) as Array).size()])
	peer.disconnect_from_host()
	_door.stop()


## A one-shot HTTP round-trip against the door (raw TCP, no client lib).
func _http(method: String, path: String, body: String = "") -> Dictionary:
	var peer := StreamPeerTCP.new()
	var err: int = peer.connect_to_host("127.0.0.1", _door.get_port())
	if err != OK:
		return {}
	var deadline: int = Time.get_ticks_msec() + 5000
	while peer.get_status() != StreamPeerTCP.STATUS_CONNECTED and Time.get_ticks_msec() < deadline:
		await process_frame
		peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return {}
	var req: String = "%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: keep-alive\r\n\r\n%s" % [
		method, path, body.to_utf8_buffer().size(), body]
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
		if raw.size() > 0:
			var t: String = raw.get_string_from_utf8()
			var sp: int = t.find("\r\n\r\n")
			if sp >= 0 and t.substr(sp + 4).strip_edges() != "":
				break
	peer.disconnect_from_host()
	var full: String = raw.get_string_from_utf8()
	var sep: int = full.find("\r\n\r\n")
	if sep < 0:
		return {}
	var parsed = JSON.parse_string(full.substr(sep + 4))
	return parsed if parsed is Dictionary else {}


## The gamestruct wire: POST /act takes {id, verb, value}; /coord is the
## multi-agent extension; the generic projections (/tools, /call) are REMOVED
## (gamestruct owns them). This is the debloat receipt.
func _leg_door_wire() -> void:
	var port: int = _door.start(0)
	_assert(port > 0, "door re-binds for the wire leg")
	if port <= 0:
		return
	var moved: Dictionary = await _http("POST", "/act", JSON.stringify({"id": "move", "verb": "move", "value": {"forward": 1.0}}))
	_assert(moved.has("ok"), "POST /act {id,verb,value} answered on the gamestruct wire")
	_driver.act("stop", {})
	var coord: Dictionary = await _http("POST", "/coord", JSON.stringify({"op": "status"}))
	_assert(coord.has("ok"), "POST /coord answered (the multi-agent extension)")
	var seen: Dictionary = await _http("POST", "/see", JSON.stringify({"label": "wire"}))
	_assert(bool(seen.get("ok", false)) and String(seen.get("path", "")) != "", "POST /see captures a frame over the wire")
	var tools: Dictionary = await _http("GET", "/tools")
	_assert(not bool(tools.get("ok", true)) and String(tools.get("error", "")).begins_with("unknown route"), "GET /tools is GONE (projection lives in gamestruct)")
	var call: Dictionary = await _http("POST", "/call", "{}")
	_assert(not bool(call.get("ok", true)), "POST /call is GONE (MCP projection lives in gamestruct)")
	_door.stop()


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] %s" % label)
	else:
		_fail += 1
		print("  [FAIL] %s" % label)


func _finish() -> void:
	print("=== AGENT DRIVER: %d passed / %d failed ===" % [_pass, _fail])
	if _globe != null and is_instance_valid(_globe):
		_globe.free()
	quit(0 if _fail == 0 else 1)
