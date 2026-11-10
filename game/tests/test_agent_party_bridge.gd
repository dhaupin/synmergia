## test_agent_party_bridge.gd - receipt for the AgentRoster -> PartyService
## seating bridge, gated by presence (labs/prd-agent-play.md sec 12, 17).
##
##   cd game && godot --headless --path . --script res://tests/test_agent_party_bridge.gd
##
## Legs:
##   1. PartyService.add_member: leader-gated, full/double-join refused by
##      name, and a real join emits the standard signals.
##   2. the presence gate: can_play fails closed with no clock; opens when
##      the human is active; closes when the human is AFK.
##   3. seating: a gated-closed seat is refused; an active human seats the
##      agent into the human's party as a distinct member.
##   4. unseat: the agent leaves; a second unseat is honestly false.
##   5. the idle leg: when the human goes idle, seat_all'd agents leave.
extends SceneTree

const ROSTER := "res://core/services/agent_roster.gd"
const ACTIVITY := "res://core/services/activity_service.gd"

var _pass := 0
var _fail := 0
var _roster: Node = null
var _coord: Node = null
var _party: Node = null
var _act: Node = null


func _initialize() -> void:
	print("=== AGENT PARTY BRIDGE TEST ===")
	call_deferred("_run")


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + msg)
	else:
		_fail += 1
		print("  [FAIL] " + msg)


func _run() -> void:
	_coord = root.get_node_or_null("AgentCoordinator")
	_party = root.get_node_or_null("PartyService")
	_act = root.get_node_or_null("ActivityService")
	_roster = root.get_node_or_null("AgentRoster")
	if _roster == null:
		_roster = load(ROSTER).new()
		root.add_child(_roster)
	if _coord == null:
		_coord = load("res://core/services/agent_coordinator.gd").new()
		root.add_child(_coord)
	if _party == null:
		_party = load("res://core/services/party_service.gd").new()
		root.add_child(_party)
	if _act == null:
		_act = load(ACTIVITY).new()
		root.add_child(_act)
	await process_frame
	_assert(_roster != null and _party != null, "roster + party present")
	# Ensure the gate/logout wiring is bound (idempotent).
	_roster._bind_presence_gate()

	var human := "human_%d" % Time.get_ticks_msec()
	var human_body := "char_human_%d" % Time.get_ticks_msec()
	var agent_body := "char_agent_%d" % Time.get_ticks_msec()

	# 1. add_member is leader-gated + honest.
	var pid: String = _party.create_party(human_body)
	_assert(pid != "", "the human opened a party")
	var not_leader: Dictionary = _party.add_member(pid, "someone", "not_the_leader")
	_assert(not bool(not_leader.get("ok", true)) and String(not_leader.get("reason", "")).contains("leader"), "a non-leader add is refused by name")
	var joined: Dictionary = _party.add_member(pid, agent_body, human_body)
	_assert(bool(joined.get("ok", false)), "the leader seats a member programmatically")
	var again: Dictionary = _party.add_member(pid, agent_body, human_body)
	_assert(not bool(again.get("ok", true)) and String(again.get("reason", "")).contains("already in a party"), "a double join is refused by name")
	_assert(_party.get_party_size(pid) == 2, "the party holds the human + the member")

	# 2. the presence gate.
	OS.set_environment("SYN_AGENT_DEV_SLOTS", "5")
	# Unknown account -> inactive -> gate closed.
	var gate_closed: Dictionary = _roster.can_play("acct_unknown_%d" % Time.get_ticks_msec())
	_assert(not bool(gate_closed.get("ok", true)) and String(gate_closed.get("reason", "")).contains("offline or AFK"), "the gate fails closed for an unknown account")
	# Active human -> gate open.
	_act.touch(human)
	_assert(bool(_roster.can_play(human).get("ok", false)), "the gate opens for an active human")
	# AFK human -> gate closed (a 1 s timeout + a wait).
	_act.set_timeout("agent", 1.0)
	_act.touch(human)
	await create_timer(1.2).timeout
	_assert(not bool(_roster.can_play(human).get("ok", true)), "the gate closes when the human is AFK")

	# 3. seating: register an agent handle with a character, attach it, seat.
	#    The human's live body must be resolvable: this receipt fakes the
	#    session by wiring a tiny local-player + login stand-in.
	_mount_fake_session(human, human_body)
	var handle := "rook_%d" % Time.get_ticks_msec()
	_assert(bool(_coord.register(handle, {"entity_id": agent_body}).get("ok", false)), "register agent %s with a character" % handle)
	_assert(bool(_roster.attach(human, handle).get("ok", false)), "attach the agent to the human")
	# The agent was already seated by the party leg above; leave so the seat
	# leg starts clean.
	_party.leave_party(agent_body)
	var closed_seat: Dictionary = _roster.seat_agent(human, handle)
	_assert(not bool(closed_seat.get("ok", true)), "seating is refused while the human is AFK")
	# Make the human active again, then seat.
	_act.set_timeout("agent", 900.0)
	_act.touch(human)
	var seated: Dictionary = _roster.seat_agent(human, handle)
	_assert(bool(seated.get("ok", false)), "the active human seats the agent")
	_assert(_party.get_player_party(agent_body).get("id", "") == pid, "the agent is a member of the human's party")
	_assert(_party.get_party_size(pid) == 2, "the party holds the human + the seated agent")

	# 4. unseat.
	_assert(_roster.unseat_agent(handle), "the agent leaves the party")
	_assert(_party.get_player_party(agent_body).is_empty(), "the agent is no longer in a party")
	_assert(not _roster.unseat_agent(handle), "a second unseat is honestly false")

	# 5. the idle leg: seat again, then go idle -> the agent leaves.
	_act.touch(human)
	_assert(bool(_roster.seat_agent(human, handle).get("ok", false)), "re-seated for the idle leg")
	_act.set_timeout("agent", 1.0)
	_act.touch(human)
	await create_timer(1.2).timeout
	_act._sweep()
	_assert(_party.get_player_party(agent_body).is_empty(), "the idle human's agent left the party")

	# 6. the logout leg: seat, then log out -> the agent leaves + the clock drops.
	_act.set_timeout("agent", 900.0)
	_act.touch(human)
	_assert(bool(_roster.seat_agent(human, handle).get("ok", false)), "re-seated for the logout leg")
	_roster._on_login(human)
	var ls := root.get_node_or_null("LoginService")
	if ls != null and ls.has_signal("logged_out"):
		ls.logged_out.emit()
		_assert(_party.get_player_party(agent_body).is_empty(), "the logged-out human's agent left the party")
		_assert(not _act.is_active(human, "agent"), "the clock was dropped on logout")

	_finish()


## Mount a minimal session stand-in so the bridge can resolve the human's
## live body. The real autoloads are mounted in this boot, so we set their
## state directly (the private field + the local-player slot) rather than
## replacing them -- the bridge reads exactly those.
func _mount_fake_session(account_id: String, entity_id: String) -> void:
	var ls := root.get_node_or_null("LoginService")
	if ls != null:
		ls.set("_current_account_id", account_id)
	var pm := root.get_node_or_null("PlayerManager")
	if pm == null:
		pm = Node.new()
		pm.name = "PlayerManager"
		root.add_child(pm)
	# A tiny Node3D body carrying entity_id (the honest field the bridge
	# reads; Node3D so any consumer reading global_position is safe).
	var body := Node3D.new()
	body.name = "FakeHumanBody"
	body.set_script(_body_script())
	body.set("entity_id", entity_id)
	root.add_child(body)
	pm.set("local_player", body)


func _body_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar entity_id: String = \"\"\n"
	s.reload()
	return s


func _finish() -> void:
	print("--- AGENT PARTY BRIDGE TEST: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
