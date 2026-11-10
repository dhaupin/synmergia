## AgentRosterUI - the agent roster panel (MenuManager "agents").
##
## The human-facing surface for their agents' BODIES (labs/prd-agent-play.md
## sec 12, 17.2). An agent is a real player with its own body now; this panel
## is where the human sees that body's live state and re-enables an agent
## that left play (agents do NOT auto-respawn -- the human brings them back).
##
## Rows read AgentRoster.board(account): one row per attached agent, the
## handle, the seat state (seated / away / no body), and a "Re-enable"
## button that calls AgentRoster.re_enable. Refresh rides the roster's OWN
## signals -- no private polling re-read.
##
## Shell law: builds inside UIPanel's standard "Panel/Main" content box with
## an idempotent synchronous build (the ContainerUI lesson), the same shell
## the IgnoreBookUI / PremiumShopUI ride. The panel is SELF-CONTAINED on the
## visibility edge: the static MenuManager.open_menu() facade only flips
## visible (it never calls open()), so a lazily-built panel must build when
## it becomes visible -- _notification handles that, and _on_open covers the
## toggle/open() path.

extends "res://ui/components/ui_panel.gd"

class_name AgentRosterUI

const NotifKindScript = preload("res://core/notifications/notification_kind.gd")

## Fires whenever the panel re-renders its rows (receipt/HUD logging).
signal roster_shown(count: int)

## Build-once content refs (inside the base Panel/Main shell).
var _status_label: Label
var _rows_box: VBoxContainer
var _hint_label: Label

## Guard against double-connections (the shell can re-_ready the same
## instance when the funnel re-opens it).
var _signals_bound: bool = false

func _setup_panel() -> void:
	set_panel_size(Vector2(440, 500))
	set_title("Agent Roster")

func _setup_content() -> void:
	# Deliberate no-op: content builds lazily in _ensure_content (the
	# ContainerUI law -- the shell is deferred behind _ready, so a
	# synchronous open right after add_child would hit a half-built panel).
	pass

## The static MenuManager.open_menu() facade only flips visible; it never
## calls open(). Build + refresh the moment the panel becomes visible so a
## panel opened through that path is never an empty shell.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_on_open()

func _ensure_content() -> void:
	if _rows_box != null:
		return
	if not has_node("Panel/Main"):
		_setup_base_panel()
	var main := get_node("Panel/Main") as VBoxContainer
	if main.get_node_or_null("AgentRows") == null:
		_build_ui(main)
	else:
		_status_label = main.get_node_or_null("Status") as Label
		_rows_box = main.get_node_or_null("AgentRows") as VBoxContainer
		_hint_label = main.get_node_or_null("Hint") as Label
	_bind_roster_signals()

func _build_ui(shell: VBoxContainer) -> void:
	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shell.add_child(_status_label)

	_rows_box = VBoxContainer.new()
	_rows_box.name = "AgentRows"
	shell.add_child(_rows_box)

	var all_row := HBoxContainer.new()
	all_row.name = "AllRow"
	shell.add_child(all_row)
	var all_btn := Button.new()
	all_btn.name = "ReEnableAllButton"
	all_btn.text = "Re-enable all"
	all_btn.pressed.connect(_on_re_enable_all_pressed)
	all_row.add_child(all_btn)

	_hint_label = Label.new()
	_hint_label.name = "Hint"
	_hint_label.text = "Agents do not respawn on their own. Re-enable one to send its body back into the world."
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shell.add_child(_hint_label)

## Refresh rides the roster's own state signals (no private polling re-read).
func _bind_roster_signals() -> void:
	if _signals_bound:
		return
	var roster := _roster()
	if roster == null:
		return
	for sig in ["agent_attached", "agent_detached", "agent_seated", "agent_unseated",
			"agent_despawned", "agent_despawn_refused"]:
		if roster.has_signal(sig) and not roster.is_connected(sig, _on_roster_changed):
			roster.connect(sig, _on_roster_changed)
	_signals_bound = true

func _on_roster_changed(_a = null, _b = null, _c = null) -> void:
	_refresh()

## UIPanel open path (menu_manager's _open_panel calls open(pid)).
func _on_open() -> void:
	_ensure_content()
	_refresh()

func _refresh() -> void:
	if _rows_box == null:
		return
	# Remove synchronously (queue_free alone is deferred): two refreshes in
	# one frame would otherwise leave a stale row holding the "Row_<handle>"
	# name, and Godot would auto-rename the fresh row -- the receipt then
	# reads the wrong node. remove_child clears the name immediately; the
	# node still frees safely behind queue_free.
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()

	var roster := _roster()
	if roster == null or not roster.has_method("board"):
		if _status_label:
			_status_label.text = "The roster is closed (service unavailable)."
		return

	var account := _account_id()
	var board: Dictionary = roster.board(account)
	var agents: Array = board.get("agents", [])
	if _status_label:
		_status_label.text = "Agents: %d / %d slots  -  %d free" % [
			int(board.get("used_slots", 0)),
			int(board.get("effective_slots", 0)),
			int(board.get("available_slots", 0)),
		]
	if agents.is_empty():
		var empty := Label.new()
		empty.name = "EmptyLabel"
		empty.text = "(no agents attached to this account)"
		_rows_box.add_child(empty)
		roster_shown.emit(0)
		return
	for handle in agents:
		_add_row(String(handle))
	roster_shown.emit(agents.size())

func _add_row(handle: String) -> void:
	var state := _row_state(handle)
	var row := HBoxContainer.new()
	row.name = "Row_%s" % handle
	_rows_box.add_child(row)

	var name_label := Label.new()
	name_label.name = "RowHandle"
	name_label.text = handle
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var state_label := Label.new()
	state_label.name = "RowState"
	state_label.text = String(state.get("label", "no body"))
	state_label.add_theme_color_override("font_color", _state_color(String(state.get("label", ""))))
	row.add_child(state_label)

	var re_btn := Button.new()
	re_btn.name = "RowButton"
	re_btn.text = "Re-enable"
	re_btn.pressed.connect(_on_re_enable_pressed.bind(handle))
	row.add_child(re_btn)

## The live state of one attached agent, read from the world's own truth:
##   seated  - a live body AND in the human's party
##   away    - a live body, but not in the party
##   no body - attached, but no live body (needs a re-enable)
func _row_state(handle: String) -> Dictionary:
	var bodies := _svc("AgentBodyService")
	var has_body: bool = bodies != null and bodies.has_method("body_for") and bodies.body_for(handle) != null
	var seated := false
	if has_body:
		var eid := _agent_entity(handle)
		var ps := _svc("PartyService")
		if eid != "" and ps != null and ps.has_method("get_player_party"):
			seated = not (ps.get_player_party(eid) as Dictionary).is_empty()
	var label := "no body"
	if has_body and seated:
		label = "seated"
	elif has_body:
		label = "away"
	return {"has_body": has_body, "seated": seated, "label": label}

func _state_color(label: String) -> Color:
	match label:
		"seated":
			return UIStyles.COLORS.success
		"away":
			return UIStyles.COLORS.warning
		_:
			return UIStyles.COLORS.text_secondary

## Receipt convenience: is a row present for this handle? Old rows linger a
## frame (queue_free is deferred), so read the LAST matching row -- the
## freshest one.
func shows_entry(handle: String) -> bool:
	return row_state_for(handle) != ""

## Receipt convenience: the freshest row's state text for a handle, or "".
func row_state_for(handle: String) -> String:
	if _rows_box == null:
		return ""
	var children := _rows_box.get_children()
	for i in range(children.size() - 1, -1, -1):
		var row := children[i]
		if row is HBoxContainer and str(row.name) == "Row_%s" % handle:
			var st := row.get_node_or_null("RowState") as Label
			if st != null:
				return str(st.text)
	return ""

## Receipt convenience: the freshest row's Re-enable button for a handle.
func button_for(handle: String) -> Button:
	if _rows_box == null:
		return null
	var children := _rows_box.get_children()
	for i in range(children.size() - 1, -1, -1):
		var row := children[i]
		if row is HBoxContainer and str(row.name) == "Row_%s" % handle:
			return row.get_node_or_null("RowButton") as Button
	return null

func _on_re_enable_pressed(handle: String) -> void:
	var roster := _roster()
	if roster == null or not roster.has_method("re_enable"):
		return
	var result: Dictionary = roster.re_enable(_account_id(), handle)
	_notify_re_enable(handle, result)
	_refresh()

func _on_re_enable_all_pressed() -> void:
	var roster := _roster()
	if roster == null or not roster.has_method("re_enable_all"):
		return
	var result: Dictionary = roster.re_enable_all(_account_id())
	var back: int = (result.get("re_enabled", []) as Array).size()
	var refused: int = (result.get("refused", []) as Array).size()
	_toast("Brought %d agent(s) back into the world (%d refused)." % [back, refused])
	_refresh()

func _notify_re_enable(handle: String, result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		if bool(result.get("already", false)):
			_toast("%s is already in the world." % handle)
		else:
			_toast("%s is back in the world." % handle)
	else:
		_toast("%s: %s" % [handle, str(result.get("reason", "could not re-enable"))])

func _toast(message: String) -> void:
	var ns := _svc("NotificationService")
	if ns == null or not ns.has_method("notify"):
		return
	# The dedupe key carries the MESSAGE, not a fixed name: a fixed key lets
	# the 5s window swallow the next honest answer.
	ns.notify(
		NotifKindScript.NotifKind.CUSTOM,
		message,
		"AgentRosterUI",
		"agent_roster_%s" % message.hash(),
		{},
		_account_id()
	)

func _agent_entity(handle: String) -> String:
	var coord := _svc("AgentCoordinator")
	if coord == null or not coord.has_method("get_agent"):
		return ""
	var rec: Dictionary = coord.get_agent(handle)
	return String(rec.get("entity_id", ""))

## The human's account (the panel's owner). "" degrades to an empty roster.
func _account_id() -> String:
	var ls := _svc("LoginService")
	if ls != null and ls.has_method("get_current_account_id"):
		return str(ls.get_current_account_id())
	return ""

func _roster() -> Node:
	return _svc("AgentRoster")

## Runtime service resolution (the parse-law: a parse-time preload of a game
## script fights the autoload registration order in script-mode receipts).
func _svc(name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(name))
