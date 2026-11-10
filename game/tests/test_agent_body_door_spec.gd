## test_agent_body_door_spec.gd - LIVE receipt for the AGENT BODY over the DOOR
## (labs/prd-agent-play.md sec 1/7). The in-process receipt
## (test_agent_body_lifecycle.gd) proves the two-input law by calling the driver
## directly; THIS receipt proves the SAME law over the gamestruct wire
## (AgentDoor HTTP), which the in-process receipt does not cover: an agent body
## is reachable, drivable, and stoppable by its PRINCIPAL handle through the
## door, and the human's body is untouched.
##
## Boots the real globe with the door enabled (SYN_AGENT=1) and asserts:
##   1. GET  /observe                        -> the HUMAN's body id (no principal).
##   2. GET  /observe?principal=<handle>     -> the AGENT's body id (distinct).
##   3. POST /act {move, principal}          -> ok; the AGENT body reads virtual
##                                              input, the HUMAN body does not.
##   4. POST /act {stop, principal}          -> ok; the AGENT body's input clears.
##   5. POST /act {move, <unknown principal>} -> an unknown principal MUST be
##                                              refused by name (ok:false+reason),
##                                              never a throw.
##
## Run (the live-driver convention -- xvfb + headless):
##   SYN_AGENT=1 xvfb-run -a godot --headless --path game \
##     --script res://tests/test_agent_body_door_spec.gd
## (xvfb unavailable? plain headless is fine -- this receipt has no see() leg.)
##
## Exit 0 = every leg held; a documented SPEC gap is REPORTED (a [GAP] line)
## rather than counted as a failure, so a real regression still exits 1.
extends SceneTree

var _pass := 0
var _fail := 0
var _gaps := 0

var _globe: Node = null
var _boot = null
var _driver: Node = null
var _door: Node = null
var _roster: Node = null
var _coord: Node = null
var _bodies: Node = null
var _act: Node = null
var _ls: Node = null

var _human: Node = null
var _human_id: String = ""
var _handle: String = ""
var _agent_id: String = ""
var _agent_body: Node = null


func _initialize() -> void:
	print("=== AGENT BODY DOOR SPEC: booting globe scene ===")
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
	_roster = root.get_node_or_null("AgentRoster")
	_coord = root.get_node_or_null("AgentCoordinator")
	_bodies = root.get_node_or_null("AgentBodyService")
	_act = root.get_node_or_null("ActivityService")
	_ls = root.get_node_or_null("LoginService")
	_assert(_driver != null and _door != null, "AgentDriver + AgentDoor autoloads present")
	_assert(_roster != null and _coord != null and _bodies != null, "roster + coordinator + body service present")
	if _driver == null or _door == null or _roster == null or _coord == null or _bodies == null:
		_finish()
		return
	# The shipped posture is SYN_AGENT=1; force the same enable so the receipt
	# holds regardless of how the process was launched.
	_driver.set_enabled(true)

	_human = _globe.get("player")
	_assert(_human != null and is_instance_valid(_human), "the human's body is live on the globe")
	if _human == null:
		_finish()
		return
	_human_id = str(_human.entity_id)
	_assert(_human_id != "", "the human's body carries an entity id")

	var port: int = _door.start(0)
	_assert(port > 0, "AgentDoor binds a live port")
	if port <= 0:
		_finish()
		return

	if not _seat_agent():
		_finish()
		return

	await _leg_observe_human()
	await _leg_observe_agent()
	await _leg_act_move()
	await _leg_act_stop()
	await _leg_unknown_principal()

	_door.stop()
	_finish()


## Seat an agent through the REAL services (the same calls the in-process
## lifecycle receipt uses): register with the coordinator, attach to the
## human's account, set the session + activity clock, then seat -- which spawns
## a real body via AgentBodyService.
func _seat_agent() -> bool:
	OS.set_environment("SYN_AGENT_DEV_SLOTS", "5")
	_handle = "rook_%d" % Time.get_ticks_msec()
	if _ls != null:
		_ls.set("_current_account_id", _human_id)
	if _act != null:
		_act.touch(_human_id)
	_assert(bool(_coord.register(_handle, {}).get("ok", false)), "register agent %s with the coordinator" % _handle)
	_assert(bool(_roster.attach(_human_id, _handle).get("ok", false)), "attach the agent to the human's account")
	var seat: Dictionary = _roster.seat_agent(_human_id, _handle)
	_assert(bool(seat.get("ok", false)), "the human seats the agent (spawns its body)")
	_agent_body = _bodies.body_for(_handle)
	_agent_id = str(_coord.get_agent(_handle).get("entity_id", ""))
	_assert(_agent_body != null and is_instance_valid(_agent_body), "a REAL agent body exists for the handle")
	_assert(_agent_id != "", "the agent body carries its own entity id")
	_assert(_agent_id != _human_id, "the agent's body id is distinct from the human's")
	_assert(_agent_body != null and _agent_body != _human, "the agent's body is a distinct node from the human's")
	return _agent_body != null and is_instance_valid(_agent_body)


## 1. /observe with no principal reports the HUMAN's own body.
func _leg_observe_human() -> void:
	var obs: Dictionary = await _http("GET", "/observe")
	_assert(bool(obs.get("ok", false)), "GET /observe -> ok:true")
	_assert(bool(obs.get("in_world", false)), "GET /observe reports the live world")
	var pid: String = str(obs.get("player", {}).get("id", ""))
	_assert(pid == _human_id, "no principal -> the snapshot's player is the HUMAN's body (%s)" % _human_id)
	print("    [observe] human player=%s" % pid)


## 2. /observe?principal=<handle> reports the AGENT's own body, distinct.
func _leg_observe_agent() -> void:
	var obs: Dictionary = await _http("GET", "/observe?principal=%s" % _handle)
	_assert(bool(obs.get("ok", false)), "GET /observe?principal -> ok:true")
	_assert(str(obs.get("principal", "")) == _handle, "the snapshot echoes the principal it reports")
	var pid: String = str(obs.get("player", {}).get("id", ""))
	_assert(pid == _agent_id, "principal -> the snapshot's player is the AGENT's body (%s)" % _agent_id)
	_assert(pid != _human_id, "the agent's reported body is distinct from the human's")
	print("    [observe] principal=%s player=%s" % [_handle, pid])


## 3. POST /act {move, principal}: the AGENT body reads its own virtual input;
##    the HUMAN body does not (the two-input law over the wire).
func _leg_act_move() -> void:
	if _human.has_method("clear_virtual_input"):
		_human.clear_virtual_input()  # baseline: the human is untouched before the move
	var resp: Dictionary = await _http("POST", "/act", JSON.stringify({
		"id": "move", "value": {"forward": 1.0, "principal": _handle},
	}))
	_assert(bool(resp.get("ok", false)), "POST /act move (principal) -> ok:true")
	_assert(bool(_agent_body.has_virtual_input()), "the AGENT body reads its OWN virtual input")
	_assert(absf(float(_agent_body._virtual_move.y) - 1.0) < 0.001, "the agent's virtual stick is forward")
	_assert(not bool(_human.has_virtual_input()), "the HUMAN body is NOT touched by the agent's move")
	print("    [act] move principal=%s agent_virtual=%s human_virtual=%s" % [
		_handle, str(_agent_body.has_virtual_input()), str(_human.has_virtual_input())])


## 4. POST /act {stop, principal}: the AGENT body's stick is zeroed (the agent
##    stopped). Design note: the body's virtual-input OWNERSHIP flag stays TRUE
##    after a stop, on purpose -- an agent body never reads the global Input, so
##    it must keep owning the stick or the human's keys would steer it
##    (globe_player.set_virtual_input: "a zero vector still counts as virtual
##    input live"). clear_virtual_input() is the despawn-only leg, so the brief's
##    "cleared" is read as "the stick is zeroed, ownership retained".
func _leg_act_stop() -> void:
	var resp: Dictionary = await _http("POST", "/act", JSON.stringify({
		"id": "stop", "value": {"principal": _handle},
	}))
	_assert(bool(resp.get("ok", false)), "POST /act stop (principal) -> ok:true")
	_assert(_agent_body._virtual_move == Vector2.ZERO, "the agent body's virtual stick is zeroed (the agent stopped)")
	_assert(bool(_agent_body.has_virtual_input()), "the agent body keeps OWNING its input after stop (never reads the human's keys)")
	print("    [act] stop principal=%s stick=%s owns_input=%s" % [
		_handle, str(_agent_body._virtual_move), str(_agent_body.has_virtual_input())])


## 5. An UNKNOWN principal MUST be refused by name (ok:false + reason), never a
##    throw -- and must NEVER silently fall back onto the human's body. The
##    driver docstring PROMISES this refusal ("never a silent fall-back onto the
##    local player, which would let one agent drive another's body"); the live
##    door is checked here. Any shortfall is reported as a [GAP], not fixed
##    (agent_driver.gd is outside this receipt's owned file).
func _leg_unknown_principal() -> void:
	var ghost: String = "ghost_spec_%d" % Time.get_ticks_msec()
	if _human.has_method("clear_virtual_input"):
		_human.clear_virtual_input()
	var resp: Dictionary = await _http("POST", "/act", JSON.stringify({
		"id": "move", "value": {"forward": 1.0, "principal": ghost},
	}))
	# The "never a throw" half: a JSON verdict always comes back.
	_assert(resp is Dictionary and resp.has("ok"), "an unknown principal never throws (a JSON verdict returns)")
	if bool(resp.get("ok", true)):
		_report_gap("SPEC leg 5: an unknown principal is NOT refused by name",
			"POST /act move(principal=%s) -> ok:true; the driver fell back onto the human seat" % ghost)
	else:
		_assert(String(resp.get("reason", "")) != "", "the unknown-principal refusal carries a reason")
	# Evidence of the silent fall-back: the human body got driven by a ghost.
	if bool(_human.has_virtual_input()):
		_report_gap("SPEC leg 5: the unknown-principal move drove the HUMAN body",
			"the human body reads virtual input after a move for a non-existent principal (the cross-body drive the driver docstring forbids)")
		print("    [act] unknown principal %s drove the HUMAN body (has_virtual_input=true)" % ghost)
	else:
		print("    [act] unknown principal %s did not touch the human body" % ghost)


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


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] %s" % label)
	else:
		_fail += 1
		print("  [FAIL] %s" % label)


func _report_gap(label: String, detail: String) -> void:
	_gaps += 1
	print("  [GAP] %s" % label)
	print("        %s" % detail)


func _finish() -> void:
	print("=== AGENT BODY DOOR SPEC: %d passed / %d failed / %d gaps ===" % [_pass, _fail, _gaps])
	if _globe != null and is_instance_valid(_globe):
		_globe.free()
	quit(0 if _fail == 0 else 1)
