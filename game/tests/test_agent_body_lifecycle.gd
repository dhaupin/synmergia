## test_agent_body_lifecycle.gd - the KEYSTONE receipt: an agent is a PLAYER,
## with its own REAL body in the same world as the human, driven by its own
## input (labs/prd-agent-play.md sec 1/7).
##
##   cd game && godot --headless --path . --script res://tests/test_agent_body_lifecycle.gd
##
## Before this round "an agent is a player" held in every layer EXCEPT the
## body: the world built exactly ONE player, the driver drove it, and an
## agent's character id resolved to no live body. This receipt proves the gap
## is closed end to end:
##   1. seating an agent spawns a REAL GlobeWorldPlayer in the globe and
##      registers it with EntityService (the world's live registry).
##   2. THE TWO-INPUT LAW: the agent's body is driven by its OWN virtual input
##      via the driver's principal, and the human's body is untouched -- two
##      players in one process do not steer each other.
##   3. the agent actually MOVES under its own input.
##   4. despawn banks the body (PlayerProgress) then removes it.
##   5. the manual re-enable UX (sec 17.2): re_enable spawns a fresh body and
##      seats it again; it is refused by name while the human is AFK.
extends SceneTree

const ROSTER := "res://core/services/agent_roster.gd"

var _pass := 0
var _fail := 0
var _globe: Node = null
var _boot = null
var _roster: Node = null
var _coord: Node = null
var _driver: Node = null
var _act: Node = null
var _bodies: Node = null
var _es: Node = null
var _pp: Node = null


func _initialize() -> void:
	print("=== AGENT BODY LIFECYCLE TEST ===")
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


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + msg)
	else:
		_fail += 1
		print("  [FAIL] " + msg)


func _run() -> void:
	_roster = root.get_node_or_null("AgentRoster")
	_coord = root.get_node_or_null("AgentCoordinator")
	_driver = root.get_node_or_null("AgentDriver")
	_act = root.get_node_or_null("ActivityService")
	_bodies = root.get_node_or_null("AgentBodyService")
	_es = root.get_node_or_null("EntityService")
	_pp = root.get_node_or_null("PlayerProgress")
	_assert(_roster != null and _coord != null and _bodies != null, "roster + coordinator + body service present")
	if _roster == null or _coord == null or _bodies == null:
		return _finish()
	_driver.set_enabled(true)
	OS.set_environment("SYN_AGENT_DEV_SLOTS", "5")

	var human: Node = _globe.get("player")
	_assert(human != null and is_instance_valid(human), "the human's body is live")
	if human == null:
		return _finish()
	var human_id: String = str(human.entity_id)
	_assert(human_id != "", "the human's body carries an entity id")
	# Session: the human is this account, and active.
	var ls := root.get_node_or_null("LoginService")
	if ls != null:
		ls.set("_current_account_id", human_id)
	_act.touch(human_id)

	# ---- 1. seating spawns a REAL body -------------------------------
	var handle := "rook_%d" % Time.get_ticks_msec()
	_assert(bool(_coord.register(handle, {}).get("ok", false)), "register agent %s (no character yet)" % handle)
	_assert(bool(_roster.attach(human_id, handle).get("ok", false)), "attach the agent to the human")
	var seat: Dictionary = _roster.seat_agent(human_id, handle)
	_assert(bool(seat.get("ok", false)), "the human seats the agent")
	var agent_id: String = String(_coord.get_agent(handle).get("entity_id", ""))
	_assert(agent_id != "", "the coordinator linked the agent to a character id")
	var agent_body: Node = _bodies.body_for(handle)
	_assert(agent_body != null and is_instance_valid(agent_body), "a REAL body exists for the agent")
	_assert(agent_body != human, "the agent's body is a distinct node from the human's")
	_assert(agent_body != null and agent_body.has_method("set_virtual_input"), "the agent body is a player body (own input)")
	_assert(agent_body != null and agent_body.get_parent() == _globe, "the agent body lives in the SAME world as the human")
	_assert(_es.get_entity(agent_id) == agent_body, "the agent body is in the live entity registry")
	# observe(principal) reports the AGENT's own body, not the human's.
	var obs: Dictionary = _driver.observe(handle)
	_assert(String(obs.get("principal", "")) == handle, "observe names the principal it reports")
	_assert(String(obs.get("player", {}).get("id", "")) == agent_id, "observe reports the AGENT's own body id")
	var obs_local: Dictionary = _driver.observe("")
	_assert(String(obs_local.get("player", {}).get("id", "")) == human_id, "observe() with no principal reports the human")

	# ---- 2. THE TWO-INPUT LAW ----------------------------------------
	# Drive the AGENT by its principal. Only the agent's virtual stick moves.
	var mv: Dictionary = _driver.act("move", {"principal": handle, "forward": 1.0})
	_assert(bool(mv.get("ok", false)), "the driver moves the agent by its principal")
	_assert(bool(agent_body.has_virtual_input()), "the agent body reads its OWN virtual input")
	_assert(absf(agent_body._virtual_move.y - 1.0) < 0.001, "the agent's virtual stick is forward")
	_assert(not bool(human.has_virtual_input()), "the human's body is NOT touched by the agent's move")
	# A move with NO principal drives the human's seat (the global Input
	# path), never the agent's virtual stick.
	_driver.act("move", {"forward": 1.0})
	_assert(absf(agent_body._virtual_move.y - 1.0) < 0.001, "a principal-less move does not disturb the agent")
	_driver.act("stop", {"principal": handle})

	# ---- 3. the agent MOVES under its own input ----------------------
	_driver.act("move", {"principal": handle, "forward": 1.0})
	var before: Vector3 = agent_body.global_position
	await create_timer(0.7).timeout
	var after: Vector3 = agent_body.global_position
	_assert(before.distance_to(after) > 0.05, "the agent walked under its own input (moved %.3f m)" % before.distance_to(after))
	_driver.act("stop", {"principal": handle})

	# ---- 4. despawn banks + removes ----------------------------------
	var despawn: Dictionary = _roster.despawn_agent(handle)
	_assert(bool(despawn.get("ok", false)), "the agent body despawns")
	_assert(_pp.has_progress(agent_id), "the body was banked before it left")
	_assert(_es.get_entity(agent_id) == null, "the body left the entity registry")
	_assert(_bodies.body_for(handle) == null, "the body service dropped the body")

	# ---- 5. the manual re-enable UX (sec 17.2) -----------------------
	_act.touch(human_id)
	var re: Dictionary = _roster.re_enable(human_id, handle)
	_assert(bool(re.get("ok", false)), "the human re-enables the agent")
	var body2: Node = _bodies.body_for(handle)
	_assert(body2 != null and is_instance_valid(body2), "re-enable spawned a fresh body")
	_assert(body2 != agent_body, "the fresh body is a new node (the old one was freed)")
	var agent_id2: String = String(_coord.get_agent(handle).get("entity_id", ""))
	_assert(_es.get_entity(agent_id2) == body2, "the fresh body is registered too")
	# AFK -> re-enable refused by name (agents do NOT auto-respawn).
	_act.set_timeout("agent", 1.0)
	_act.touch(human_id)
	await create_timer(1.2).timeout
	var afk: Dictionary = _roster.re_enable(human_id, handle)
	_assert(not bool(afk.get("ok", true)) and String(afk.get("reason", "")).length() > 0, "re-enable is refused by name while the human is AFK")
	_act.set_timeout("agent", 900.0)

	_finish()


func _finish() -> void:
	print("--- AGENT BODY LIFECYCLE TEST: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
