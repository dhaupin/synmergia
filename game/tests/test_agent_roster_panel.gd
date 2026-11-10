## test_agent_roster_panel.gd - the agent roster PANEL receipt.
##
##   cd game && godot --headless --path . --script res://tests/test_agent_roster_panel.gd
##
## The human-facing surface for their agents' bodies (labs/prd-agent-play.md
## sec 12, 17.2). Boots the REAL globe (a live world, so agent bodies spawn),
## fakes a session (LoginService account + an active clock + a live human
## body), attaches an agent, and drives the panel through MenuManager:
##   1. MenuManager.open_menu("agents") builds the panel (the lazily-built
##      content is forced on the visibility edge) and shows a row for the
##      attached agent.
##   2. the row state follows the LIVE truth: no body -> seated -> away,
##      refreshed by the roster's OWN signals (no private polling re-read).
##   3. pressing the row's Re-enable button calls AgentRoster.re_enable and
##      the row state follows (a fresh body returns, seated again).
##   4. an AFK human is refused by name; the row state stays honest.
##   5. the shell law: close() emits panel_closed (MenuManager's row).
extends SceneTree

const ROSTER := "res://core/services/agent_roster.gd"

var _pass := 0
var _fail := 0
var _globe: Node = null
var _boot = null
var _roster: Node = null
var _coord: Node = null
var _bodies: Node = null
var _act: Node = null
var _mm: Node = null
var _panel: Node = null


func _initialize() -> void:
	print("=== AGENT ROSTER PANEL TEST ===")
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
	_bodies = root.get_node_or_null("AgentBodyService")
	_act = root.get_node_or_null("ActivityService")
	_assert(_roster != null and _coord != null and _bodies != null, "roster + coordinator + body service present")
	if _roster == null or _coord == null or _bodies == null:
		return _finish()

	var human: Node = _globe.get("player")
	_assert(human != null and is_instance_valid(human), "the human's body is live")
	if human == null:
		return _finish()
	var human_id: String = str(human.entity_id)
	var account := "acct_panel_%d" % Time.get_ticks_msec()

	# Fake the session: the human is this account, in-world and active.
	var ls := root.get_node_or_null("LoginService")
	if ls != null:
		ls.set("_current_account_id", account)
	_act.touch(account)
	OS.set_environment("SYN_AGENT_DEV_SLOTS", "5")

	# The MenuManager that owns the panels (hud_layer.tscn's child).
	var hud: Node = _globe.get("hud")
	_mm = hud.get_node_or_null("MenuManager") if hud != null else null
	_assert(_mm != null, "MenuManager present in the globe HUD")
	if _mm == null:
		return _finish()

	# ---- 1. open through the MenuManager facade; the panel builds --------
	var MM = load("res://ui/components/menu_manager.gd")
	MM.open_menu("agents")
	await process_frame
	await process_frame
	_panel = _mm._get_panel("agents")
	_assert(_panel != null, "the roster panel is registered with MenuManager")
	if _panel == null:
		return _finish()
	_assert(_panel.visible, "open_menu showed the roster panel")
	_assert(_panel.has_node("Panel/Main/AgentRows"), "the panel built its content shell on open (no empty panel)")

	# Attach an agent; the row appears through the roster's own signal.
	var handle := "rook_%d" % Time.get_ticks_msec()
	_assert(bool(_coord.register(handle, {}).get("ok", false)), "register agent %s" % handle)
	_assert(bool(_roster.attach(account, handle).get("ok", false)), "attach the agent to the account")
	await process_frame
	_assert(_panel.shows_entry(handle), "the panel shows a row for the attached agent")
	_assert(_panel.row_state_for(handle) == "no body", "the fresh agent reads 'no body' (attached, not yet in the world)")

	# ---- 2. the row state follows the live truth ------------------------
	# Seat: a body spawns -> the row flips to 'seated' via agent_seated.
	var seat: Dictionary = _roster.seat_agent(account, handle)
	_assert(bool(seat.get("ok", false)), "the human seats the agent (a body spawns)")
	await process_frame
	_assert(_bodies.body_for(handle) != null, "the agent's body is live in the world")
	_assert(_panel.row_state_for(handle) == "seated", "the row reads 'seated' after the body spawns (signal-driven refresh)")

	# Unseat: the body stays, but the party seat drops -> 'away'.
	_assert(_roster.unseat_agent(handle), "the agent leaves the party (body remains)")
	await process_frame
	_assert(_panel.row_state_for(handle) == "away", "the row reads 'away' when the body is up but unseated")

	# ---- 3. press the row's Re-enable button (the real pressed signal) ---
	# Despawn the body first so the re-enable has real work to do.
	_act.touch(account)
	var despawn: Dictionary = _roster.despawn_agent(handle)
	_assert(bool(despawn.get("ok", false)), "the agent's body is banked + despawned")
	await process_frame
	_assert(_bodies.body_for(handle) == null, "the body is gone before the re-enable")
	_assert(_panel.row_state_for(handle) == "no body", "the row reads 'no body' after the despawn (agent_despawned refresh)")

	# Count agent_seated emissions to prove the button reached re_enable.
	var seated_hits: Array = []
	_roster.agent_seated.connect(func(a, h, _p): seated_hits.append(h))
	var btn: Button = _panel.button_for(handle)
	_assert(btn != null, "the row carries a Re-enable button")
	if btn != null:
		btn.pressed.emit()
	await process_frame
	await process_frame
	_assert(seated_hits.has(handle), "pressing Re-enable called AgentRoster.re_enable (agent_seated fired)")
	_assert(_bodies.body_for(handle) != null, "re-enable spawned a fresh body back into the world")
	_assert(_panel.row_state_for(handle) == "seated", "the row follows to 'seated' after the re-enable")

	# ---- 4. an AFK human is refused by name -----------------------------
	_act.set_timeout("agent", 1.0)
	_act.touch(account)
	await create_timer(1.2).timeout
	var afk: Dictionary = _roster.re_enable(account, handle)
	_assert(not bool(afk.get("ok", true)) and String(afk.get("reason", "")).contains("offline or AFK"), "re-enable is refused by name while the human is AFK")
	_act.set_timeout("agent", 900.0)
	_act.touch(account)

	# ---- 5. the shell law: close() emits panel_closed -------------------
	var closed: Array = []
	_panel.panel_closed.connect(func(): closed.append(true))
	_panel.close()
	await process_frame
	_assert(closed.size() == 1, "the panel emits panel_closed on close (MenuManager's row contract)")
	_assert(not _panel.visible, "the panel hides on close")

	_finish()


func _finish() -> void:
	print("--- AGENT ROSTER PANEL TEST: %d/%d ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
