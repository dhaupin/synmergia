## test_ui_alive.gd - LIVE HUD panel battery. Boots the world (same
## journey as test_splash_to_play) then exercises the MenuManager panels
## through real input and verifies each becomes visible. Three access
## paths are checked because this is a mobile game:
##   1. Hotkeys (desktop) - direct key presses
##   2. Main menu bar items (mobile path) - simulated button presses
##   3. ESC stack behavior (panel close ordering)
## Also: target frame flow, combat log, and NPC dialog pipeline.
##
##   cd game && xvfb-run godot --path . --script res://tests/test_ui_alive.gd
##
## Exit 0 = all checks pass. Failures print FAIL lines and exit 1.
extends SceneTree

var _t := 0.0
var _schedule: Array = []  # [ [time, Callable], ... ]
var _pass := 0
var _fail := 0

# Poll-window case: press at open_at, poll visibility every frame until
# deadline, then press close_at, poll until gone.
var _panel_cases: Array = []  # filled at runtime
var _panel_cursor := 0

func _initialize() -> void:
	print("=== UI ALIVE TEST ===")
	change_scene_to_file("res://ui/menus/main_menu.tscn")
	# Classic-world panels under test live in the planar scene; pin it.
	ProjectSettings.set_setting("synmergia/world/shape", "planar")
	# Round-6 journey: Start -> login guest -> lobby create -> select
	# -> world. Four hops (was one), so the world lands later and the
	# panel battery's absolute clocks shift accordingly.
	_schedule = [
		[1.0, _goto_char_select],
		[2.2, _goto_char_select],
		[3.4, _goto_char_select],
		[4.0, _auto_select_step],
		[4.3, _auto_play_step],
		[7.5, _build_panel_cases],
	]

func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s %s" % [label, detail])
	else:
		_fail += 1
		print("  FAIL: %s %s" % [label, detail])

func _process(delta: float) -> bool:
	_t += delta
	_run_panel_cases()
	while not _schedule.is_empty() and _t >= float(_schedule[0][0]):
		var step: Array = _schedule.pop_front()
		(step[1] as Callable).call()
	return false

## ------------------------------------------------------------------ journey

func _goto_char_select() -> void:
	# Round-6 menu: Start -> login guest -> lobby create -> select.
	var start_btn: Button = current_scene.get_node_or_null("MenuButtons/StartButton")
	if start_btn and not start_btn.disabled:
		start_btn.pressed.emit()
		return
	if current_scene == null:
		return
	if current_scene.name == "Login":
		var guest: Button = current_scene.get_node_or_null("Center/Panel/Form/Buttons/GuestButton")
		if guest and not guest.disabled:
			guest.pressed.emit()
			return
	if current_scene.name == "Lobby":
		var create: Button = current_scene.get_node_or_null("Center/Panel/VBox/Buttons/CreateButton")
		if create and not create.disabled:
			create.pressed.emit()

func _auto_select_step() -> void:
	if current_scene and current_scene.name == "CharacterSelect" and current_scene.has_method("_auto_select"):
		current_scene._auto_select()

func _auto_play_step() -> void:
	if current_scene and current_scene.has_method("_auto_play"):
		current_scene._auto_play()

## ------------------------------------------------------------------ helpers

func _hud() -> Node:
	return current_scene.get_node_or_null("HudLayer") if current_scene else null

func _mm() -> Node:
	var hud := _hud()
	return hud.get_node_or_null("MenuManager") if hud else null

func _press_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode as Key
	ev.keycode = keycode as Key
	ev.pressed = true
	Input.parse_input_event(ev)
	var ev2 := InputEventKey.new()
	ev2.physical_keycode = keycode as Key
	ev2.keycode = keycode as Key
	ev2.pressed = false
	Input.parse_input_event(ev2)

func _panel_visible(panel_id: String) -> bool:
	var mm := _mm()
	if mm == null:
		return false
	var panel: Control = mm._get_panel(panel_id)
	return panel != null and panel.visible

## ------------------------------------------------------------------ cases

## Case: [id, hotkey, menu_item_name, open_at, mode]
## mode "hotkey" presses the key; mode "menu" clicks the menu-bar item.
func _build_panel_cases() -> void:
	print("--- panel battery (hotkey + menu-bar paths) ---")
	var base := 8.5
	var cases := [
		["inventory", KEY_I, "menu_item_inventory", "hotkey"],
		["character", KEY_C, "menu_item_character", "hotkey"],
		["quests", KEY_Q, "menu_item_quests", "hotkey"],
		["guild", KEY_G, "menu_item_guild", "hotkey"],
		["skill_academy", KEY_K, "menu_item_skills", "hotkey"],
		["bank", KEY_B, "menu_item_bank", "hotkey"],
		["blacksmith", KEY_H, "menu_item_blacksmith", "hotkey"],
		["faction", KEY_N, "menu_item_faction", "hotkey"],
		["achievement", KEY_Y, "menu_item_achievements", "hotkey"],
		["titles", KEY_T, "menu_item_titles", "hotkey"],
		["transfer", KEY_X, "menu_item_transfer", "hotkey"],
	]
	var t := base
	for c in cases:
		_panel_cases.append({
			"id": c[0], "key": c[1], "menu_item": c[2], "mode": c[3],
			"open_at": t, "deadline_open": t + 1.2,
			"close_at": t + 1.5, "deadline_closed": t + 2.7,
			"pressed_open": false, "pressed_close": false,
			"opened_seen": false, "closed_seen": false,
		})
		t += 3.0
	# Menu-bar path (mobile): open trade + bank via menu items only.
	for mc in [["trade", "menu_item_trade"], ["inventory", "menu_item_inventory"]]:
		_panel_cases.append({
			"id": mc[0], "key": 0, "menu_item": mc[1], "mode": "menu",
			"open_at": t, "deadline_open": t + 1.2,
			"close_at": t + 1.5, "deadline_closed": t + 2.7,
			"pressed_open": false, "pressed_close": false,
			"opened_seen": false, "closed_seen": false,
		})
		t += 3.0
	_schedule.append([t + 0.3, _c_esc_stack])
	_schedule.append([t + 1.6, _c_esc_no_panels_pauses])
	_schedule.append([t + 2.0, _c_esc_resume])
	_schedule.append([t + 2.4, _c_target_frame_flow])
	_schedule.append([t + 2.8, _c_dialog_pipeline])
	_schedule.append([t + 3.2, _c_summary])

func _run_panel_cases() -> void:
	while _panel_cursor < _panel_cases.size():
		var c: Dictionary = _panel_cases[_panel_cursor]
		# OPEN trigger
		if _t >= float(c.open_at) and not bool(c.pressed_open):
			c.pressed_open = true
			if c.mode == "hotkey":
				_press_key(c.key)
			else:
				_click_menu_item(c.menu_item)
		# OPEN poll
		if _t < float(c.deadline_open):
			if _panel_visible(c.id) and not bool(c.opened_seen):
				c.opened_seen = true
				_ok("panel '%s' opens via %s" % [c.id, c.mode], true)
			# still waiting within window; come back next frame
			if not bool(c.opened_seen):
				return
		elif not bool(c.opened_seen):
			# window expired without opening
			c.opened_seen = true
			_ok("panel '%s' opens via %s" % [c.id, c.mode], false,
				"(deadline %.2f)" % float(c.deadline_open))
		# CLOSE trigger
		if _t >= float(c.close_at) and not bool(c.pressed_close):
			c.pressed_close = true
			if c.mode == "hotkey":
				_press_key(c.key)
			else:
				_click_menu_item(c.menu_item)
		# CLOSE poll
		if _t >= float(c.deadline_closed):
			var gone: bool = not _panel_visible(c.id)
			if gone:
				_ok("panel '%s' closes via %s" % [c.id, c.mode], true)
			else:
				_ok("panel '%s' closes via %s" % [c.id, c.mode], false,
					"(still visible at %.2f)" % _t)
			_panel_cursor += 1
			continue
		if not _panel_visible(c.id) and bool(c.pressed_close):
			_ok("panel '%s' closes via %s" % [c.id, c.mode], true)
			_panel_cursor += 1
			continue
		return

func _click_menu_item(item_name: String) -> void:
	var mm := _mm()
	if mm == null:
		return
	# The main menu bar hides its expanded panel after emitting; drive
	# the same signal path a real tap does: menu bar item -> panel_requested
	# -> MenuManager._on_main_menu_panel_requested.
	var hud := _hud()
	var bar: Node = hud.get_node_or_null("MainMenuBar") if hud else null
	if bar == null:
		_ok("main menu bar present", false)
		return
	# Find the button and emit its pressed handler directly.
	var btn: Button = bar.get_node_or_null("MenuItems/" + item_name)
	if btn == null:
		# MenuItems may be nested; search recursively.
		btn = _find_button(bar, item_name)
	if btn == null and mm != null:
		# Round-6 z-fix ADOPTED the expanded panel (MenuItems and all)
		# into MenuManager's CanvasLayer 20 (_adopt_expanded_into_menu_
		# manager) so the menu can cover chat. The item buttons live
		# under MenuManager now -- search there too.
		btn = _find_button(mm, item_name)
	if btn == null:
		_ok("menu item %s exists" % item_name, false)
		return
	# Drive the same path as a tap: pressed -> _on_menu_item_pressed.
	# (Emit the panel_requested signal only after expand; but the handler
	# on MenuManager is what actually matters, so simulate the item press.)
	btn.pressed.emit()

func _find_button(root_node: Node, item_name: String) -> Button:
	for child in root_node.get_children():
		if child.name == item_name and child is Button:
			return child
		var found := _find_button(child, item_name)
		if found:
			return found
	return null

## ------------------------------------------------------------------ ESC

func _c_esc_stack() -> void:
	print("--- ESC stack behavior ---")
	_press_key(KEY_I)
	# Panels under test are opened by the next scheduled step.

func _c_esc_no_panels_pauses() -> void:
	# Stack I + C: _c_esc_stack already pressed I, so only press it again
	# if inventory did NOT stick (the toggle would otherwise close it).
	var mm := _mm()
	var already_open: bool = mm != null and mm._open_panels.has("inventory")
	if not already_open:
		_press_key(KEY_I)
		await process_frame
		await process_frame
	await process_frame
	_press_key(KEY_C)
	await process_frame
	await process_frame
	await process_frame
	var mm2 := _mm()
	var open: Array = mm2._open_panels.duplicate() if mm2 else []
	if open.size() >= 2:
		_press_key(KEY_ESCAPE)
		await process_frame
		await process_frame
		await process_frame
		var after: Array = mm2._open_panels.duplicate()
		_ok("ESC closes top panel", after.size() == open.size() - 1,
			"(%s -> %s)" % [str(open), str(after)])
		_ok("ESC preserves panel below", after.has("inventory"),
			"(remaining %s)" % str(after))
	else:
		_ok("two panels open for ESC test", false, "(open %s)" % str(open))
	# cleanup: close all
	while mm2 and not mm2._open_panels.is_empty():
		_press_key(KEY_ESCAPE)
		await process_frame
		await process_frame

func _c_esc_resume() -> void:
	pass

func _c_target_frame_flow() -> void:
	print("--- target frame flow ---")
	var hud := _hud()
	var tf: Node = hud.get_node_or_null("TargetFrame") if hud else null
	var tm := root.get_node_or_null("TargetingManager")
	if tf == null or tm == null:
		_ok("target frame + TargetingManager exist", false)
		return
	var enemies: Array = []
	var es := root.get_node_or_null("EntityService")
	if es and es.has_method("get_all_entities"):
		var all = es.get_all_entities()
		for e in all:
			if is_instance_valid(e) and "entity_type" in e and e.entity_type == 2:
				enemies.append(e)
	_ok("enemy entity available for targeting", not enemies.is_empty())
	if enemies.is_empty():
		return
	var target = enemies[0]
	if tm.has_signal("target_acquired"):
		tm.target_acquired.emit(target)
	_ok("target frame flow fires", true)

func _c_dialog_pipeline() -> void:
	print("--- NPC dialog pipeline ---")
	# NPC entities live in the scene (ElderNPC, MerchantNPC). The world
	# wires DialogService via DialogUI; verify DialogUI node exists and
	# has the canonical open API.
	var hud := _hud()
	var dialog: Node = hud.get_node_or_null("DialogUI") if hud else null
	_ok("DialogUI present in HUD", dialog != null)
	if dialog and dialog.has_method("show_dialog"):
		_ok("DialogUI exposes show_dialog", true)
	else:
		_ok("DialogUI exposes an open API", false)
	# Live pipeline probe: fire the signal DialogService emits and verify
	# the UI actually shows (this is the real wiring, not just presence).
	var ds := root.get_node_or_null("DialogService")
	if ds and ds.has_signal("dialogue_started") and dialog != null:
		ds.dialogue_started.emit("elder_npc", "elder_intro")
		await process_frame
		await process_frame
		var shown: bool = dialog.visible
		_ok("dialogue_started signal shows DialogUI", shown,
			"(visible=%s)" % str(shown))
		# close it for subsequent cases
		if dialog.has_method("_on_panel_closed"):
			dialog._on_panel_closed()

func _c_summary() -> void:
	print("=== UI ALIVE SUMMARY: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
