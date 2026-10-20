## FerryDockUI - the dock front-end (S16.10, prd-ocean-depths sec 9).
##
## Mirrors MountUI's island shape (extends UIPanel; content built into
## the panel's Main in the _setup_content override). The dock invents
## nothing: the schedule chart is FerryService.route_status (the same
## primitive the almanac's sailing page reads -- chart and dock cannot
## disagree), the boards/sailings wake the ride book, and every press
## rides the SAME gate chain the headless probe already rode
## (board_ferry within the window, charter_skiff with the ticket law).
##
## Opening context:
##   open_for_player(pid)  -- Brack's fence at the moor pin.
##
## WAKE LAW surfaced honestly: a player with no recorded ride sees the
## skiff row refused IN the panel (the sea makes you row it once),
## not a hidden failure.
extends "res://ui/components/ui_panel.gd"

class_name FerryDockUI

## Runtime autoload lookups (script-mode-safe; the bare identifier
## fails compile when autoloads are absent -- test_islands).
func _ferry_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("FerryService")) if tree and tree.root else null

func _glog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

func _local_player_id() -> String:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var pm = (ml as SceneTree).root.get_node_or_null("PlayerManager")
		if pm != null and pm.has_method("get_local_player_id"):
			return str(pm.get_local_player_id())
	return ""

var _status_label: Label
var _route_row: Label
var _clock_row: Label
var _wake_row: Label
var _board_btn: Button
var _skiff_btn: Button
var _cycle_btn: Button
## The vessel THIS dock calls at (set by the caller; empty = the first
## scheduled ferry or, with a pin set, the pin's first caller). A
## dock is tied to a shoreline, so the moor-side dock names the
## barque -- not "whatever dict order says".
var vehicle_id: String = ""
## THE PIN LAW (the callers-at-this-harbor law): the gateway pin the
## dock was opened for. A harbor pin can front MANY lines (the
## capitol pier carries the Haven Ferry AND the Pans Runner) -- the
## callers resolve from the VEHICLES' own route data (no pin table
## to drift), and the current/p:set cycle button fronts each in turn.
var pin_gateway_id: String = ""
var _picked_caller: int = 0
var _pin_last: String = ""

var _ferry_service = null

func _ready() -> void:
	# Resolve BEFORE super._ready(): the base chain calls _setup_content().
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		_ferry_service = (ml as SceneTree).root.get_node_or_null("FerryService")
	super._ready()
	set_title("Ferry Dock")
	set_panel_size(Vector2(440, 330))

func open_for_player(player_id: String) -> void:
	if not _is_open:
		open(player_id)
	else:
		_player_id = player_id
		refresh()


## The harbor's callers: every scheduled ferry whose ROUTE names this
## dock's pin (the vehicles' own data truth; an unpinned dock keeps
## the empty list).
func _pin_callers() -> Array:
	if _ferry_service == null or pin_gateway_id.is_empty() \
			or _ferry_service._ferries.is_empty():
		return []
	if _pin_last != pin_gateway_id:
		_pin_last = pin_gateway_id
		_picked_caller = 0
	var out: Array = []
	var ferries: Dictionary = _ferry_service._ferries
	for vid in ferries.keys():
		var v = ferries[vid]
		if v != null and v.route_gateways != null \
				and pin_gateway_id in v.route_gateways:
			out.append(str(vid))
	return out


## The vessel the dock fronts right now: an explicit vehicle_id wins
## (back-compat), then the pin's picked caller, then the first
## scheduled ferry (the v0 default).
func _active_vid() -> String:
	if vehicle_id != "" and _ferry_service != null \
			and _ferry_service._ferries.has(vehicle_id):
		return vehicle_id
	var callers := _pin_callers()
	if not callers.is_empty():
		return str(callers[_picked_caller % callers.size()])
	if _ferry_service != null and not _ferry_service._ferries.is_empty():
		return str(_ferry_service._ferries.keys()[0])
	return ""


## The line switch: the picked caller steps to the next one and the
## panel re-reads (schedule, wake ledger, boarding window -- every
## row is that line's own truth).
func _on_cycle_pressed() -> void:
	var callers := _pin_callers()
	if callers.size() > 1:
		_picked_caller = (_picked_caller + 1) % callers.size()
		refresh()

func _setup_content() -> void:
	var panel := get_panel()
	if panel == null:
		return
	var main: VBoxContainer = panel.get_node_or_null("Main")
	if main == null:
		return
	_route_row = Label.new()
	_route_row.name = "RouteRow"
	_route_row.text = "The tide table is blank."
	main.add_child(_route_row)
	_clock_row = Label.new()
	_clock_row.name = "ClockRow"
	_clock_row.text = "The dock is dark."
	main.add_child(_clock_row)
	_wake_row = Label.new()
	_wake_row.name = "WakeRow"
	_wake_row.text = "The sea keeps count of your crossings."
	main.add_child(_wake_row)
	_board_btn = Button.new()
	_board_btn.name = "BoardButton"
	_board_btn.text = "Board the Ferry"
	_board_btn.pressed.connect(_on_board_pressed)
	main.add_child(_board_btn)
	_cycle_btn = Button.new()
	_cycle_btn.name = "CycleButton"
	_cycle_btn.text = "Also calling here"
	_cycle_btn.pressed.connect(_on_cycle_pressed)
	main.add_child(_cycle_btn)
	_skiff_btn = Button.new()
	_skiff_btn.name = "SkiffButton"
	_skiff_btn.text = "Charter the Skiff"
	_skiff_btn.pressed.connect(_on_skiff_pressed)
	main.add_child(_skiff_btn)
	_status_label = Label.new()
	_status_label.name = "StatusRow"
	_status_label.text = ""
	main.add_child(_status_label)
	refresh()

func refresh() -> void:
	if _route_row == null:
		return
	_ferry_service = _ferry_svc()
	var player_id: String = _player_id if not _player_id.is_empty() else _local_player_id()
	if _ferry_service == null:
		_route_row.text = "No ferry runs this shore."
		_clock_row.text = ""
		if _board_btn != null:
			_board_btn.visible = false
		if _skiff_btn != null:
			_skiff_btn.visible = false
		return
	var ferries: Dictionary = _ferry_service._ferries
	var vessel_ids: Array = ferries.keys()
	if vessel_ids.is_empty():
		_route_row.text = "No scheduled vessel calls at this dock."
		if _board_btn != null:
			_board_btn.visible = false
		if _skiff_btn != null:
			_skiff_btn.visible = false
		if _cycle_btn != null:
			_cycle_btn.visible = false
		return
	# The dock fronts its data-truth vessel (see _active_vid). The
	# cycle button fronts the shared-harbor lines (a pin with more
	# than one caller shows every line's own schedule in turn).
	var vid: String = _active_vid()
	if vid.is_empty():
		vid = str(vessel_ids[0])
	var callers: Array = _pin_callers()
	if _cycle_btn != null:
		if callers.size() > 1:
			var nxt: String = str(callers[(_picked_caller + 1) % callers.size()])
			var nv = ferries.get(nxt)
			if nv != null:
				_cycle_btn.text = "Also calling: %s -- switch line" % str(nv.display_name)
				_cycle_btn.visible = true
			else:
				_cycle_btn.visible = false
		else:
			_cycle_btn.visible = false
	var v = ferries[vid]
	_route_row.text = "%s: %s -> %s (%d cast-offs a day)" % [
		str(v.display_name), str(v.route_gateways[0]), str(v.route_gateways[1]),
		int(v.ferries_per_day)]
	var st: Dictionary = _ferry_service.route_status(vid)
	var wake: int = _ferry_service.rides_recorded(player_id, vid) if _ferry_service.has_method("rides_recorded") else 0
	if _wake_row != null:
		_wake_row.text = "Your crossings: %d" % wake
	match str(st.get("status", "in_port")):
		"boarding":
			if _clock_row != null:
				_clock_row.text = "The gates are open -- casting off now."
			if _board_btn != null:
				_board_btn.visible = true
				_board_btn.text = "Board the %s (free)" % str(v.display_name)
		"at_sea":
			if _clock_row != null:
				_clock_row.text = "She is at sea. The skiff can run."
			if _board_btn != null:
				_board_btn.visible = false
		_:
			if _clock_row != null:
				var dep: Dictionary = st.get("dep", {})
				var in_h: float = float(dep.get("in_h", 0.0))
				_clock_row.text = "Next cast-off in %.1f h." % in_h
			if _board_btn != null:
				_board_btn.visible = false
	if _skiff_btn != null:
		_skiff_btn.visible = true
		_skiff_btn.text = "Charter the Skiff (ticket, else %d gold)" % int(_ferry_service.DEFAULT_SKIFF_TICKET)

func _on_board_pressed() -> void:
	_ferry_service = _ferry_svc()
	if _ferry_service == null:
		return
	var player_id: String = _player_id if not _player_id.is_empty() else _local_player_id()
	if player_id.is_empty():
		return
	var vid: String = _active_vid()
	if vid.is_empty():
		return
	var answer: Dictionary = _ferry_service.board_ferry(player_id, vid)
	if not bool(answer.get("ok", false)):
		_speak_refusal(str(answer.get("reason", "refused")))
	else:
		_speak_ok("Boards are taken. The deck is yours until cast-off.")
	refresh()

## The charter press rides the SAME charted seam the probe rode: the
## service answers {ok, reason} or {ok, skiff}; a refusal is spoken,
## never swallowed (a short purse must say so; the wake law is).
func _on_skiff_pressed() -> void:
	_ferry_service = _ferry_svc()
	if _ferry_service == null:
		return
	var player_id: String = _player_id if not _player_id.is_empty() else _local_player_id()
	if player_id.is_empty():
		return
	var vid: String = _active_vid()
	if vid.is_empty():
		return
	var answer: Dictionary = _ferry_service.charter_skiff(player_id, vid)
	if bool(answer.get("ok", false)) and bool(answer.get("skiff", false)):
		_speak_ok("The skiff is yours -- 2.5x the crossing.")
	else:
		_speak_refusal(str(answer.get("reason", "refused")))
	refresh()

func _speak_ok(msg: String) -> void:
	if _status_label != null:
		_status_label.text = msg
	var gl := _glog()
	if gl:
		gl.info("FerryDockUI: %s" % msg)

func _speak_refusal(reason: String) -> void:
	if _status_label != null:
		_status_label.text = reason
	var gl := _glog()
	if gl:
		gl.info("FerryDockUI: refused -- %s" % reason)
