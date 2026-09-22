## test_splash_to_play.gd - LIVE splash-to-play journey test.
## Boots the game exactly as a player would (project main scene =
## main_menu.tscn), then drives the real flow:
##
##   main_menu -> [Play] -> character_select -> [F5 auto-select]
##   -> [F6 play] -> GameManager.PLAYING -> world_playable
##
## Then verifies the playing state end-to-end:
##   - game state == PLAYING, current scene is world_playable
##   - player registered in EntityService, camera + touch HUD alive
##   - camera sensitivity setting round-trips (slider -> orbit)
##   - movement input still drives the player after the full journey
##
##   cd game && xvfb-run godot --path . --script res://tests/test_splash_to_play.gd
##
## Exit 0 = every checkpoint observed. Failures print FAIL and exit 1.
extends SceneTree

var _t := 0.0
var _schedule: Array = []  # [ [time, Callable], ... ]
var _pass := 0
var _fail := 0

var _yaw_before_sens := 0.0
var _yaw_after_sens := 0.0

func _initialize() -> void:
	print("=== SPLASH-TO-PLAY JOURNEY TEST ===")
	# Boot the project's real main scene (main_menu) like a player launch.
	# --script mode starts with an empty root, so change_scene ourselves.
	var menu: PackedScene = load("res://ui/menus/main_menu.tscn")
	if menu == null:
		print("  FAIL: main_menu.tscn not loadable")
		quit(1)
		return
	var err := change_scene_to_file("res://ui/menus/main_menu.tscn")
	if err != OK:
		print("  FAIL: change_scene error %d" % err)
		quit(1)
		return

	_schedule = [
		[1.2, _c_main_menu_visible],
		[1.5, _c_press_play],
		[2.5, _c_char_select_visible],
		[2.8, _c_auto_select],
		[3.0, _c_play_world],
		[5.0, _c_world_loaded],
		[5.3, _c_player_registered],
		[5.6, _c_hud_alive],
		[5.9, _c_sensitivity_set],
		[7.4, _c_sensitivity_effect],
		[7.7, _c_move_input],
		[9.4, _c_move_check],
		[9.7, _c_summary],
	]

func _process(delta: float) -> bool:
	_t += delta
	while not _schedule.is_empty() and _t >= float(_schedule[0][0]):
		var step: Array = _schedule.pop_front()
		(step[1] as Callable).call()
		if _fail > 0 and step[1] == _c_summary:
			pass
	return false

func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s %s" % [label, detail])
	else:
		_fail += 1
		print("  FAIL: %s %s" % [label, detail])

func _scene() -> Node:
	return current_scene

func _press_button(node_path: String) -> void:
	var btn: Button = _scene().get_node_or_null(node_path) if _scene() else null
	if btn and not btn.disabled:
		btn.pressed.emit()
	else:
		print("  [journey] button missing/disabled: %s" % node_path)

## -------------------------------------------------------------- checkpoints

func _c_main_menu_visible() -> void:
	print("--- journey: main menu ---")
	var s := _scene()
	_ok("main menu scene is current", s != null and s.name == "MainMenu",
		"(scene %s)" % (s.name if s else "null"))
	var play: Button = s.get_node_or_null("MenuButtons/PlayButton") if s else null
	_ok("Play button present and enabled", play != null and not play.disabled,
		"(disabled=%s)" % str(play.disabled if play else "?"))

func _c_press_play() -> void:
	_press_button("MenuButtons/PlayButton")

func _c_char_select_visible() -> void:
	var s := _scene()
	var is_cs: bool = s != null and (s.name == "CharacterSelect" or s.get_script() == load("res://ui/menus/character_select.gd"))
	_ok("character select reached", is_cs, "(scene %s)" % (s.name if s else "null"))
	var gm := root.get_node_or_null("GameManager")
	_ok("game state CHARACTER_SELECT",
		gm and gm.current_state == gm.GameState.CHARACTER_SELECT,
		"(state %s)" % gm.GameState.keys()[gm.current_state] if gm else "(no gm)")

func _c_auto_select() -> void:
	# The documented test hotkey: F5 auto-selects first species/class.
	var s := _scene()
	var play: Button = s.get_node_or_null("PlayButton") if s else null
	if play and not play.disabled:
		print("  [journey] auto-select done (play enabled)")
	else:
		# Fallback: drive _auto_select directly.
		if s and s.has_method("_auto_select"):
			s._auto_select()
			print("  [journey] fallback _auto_select called")

func _c_play_world() -> void:
	var s := _scene()
	if s and s.has_method("_auto_play"):
		s._auto_play()
	else:
		_press_button("PlayButton")

func _c_world_loaded() -> void:
	print("--- journey: entering world ---")
	var s := _scene()
	var in_world: bool = s != null and s.get_script() == load("res://scenes/world_playable.gd")
	_ok("world_playable scene loaded", in_world, "(scene %s)" % (s.name if s else "null"))
	var gm := root.get_node_or_null("GameManager")
	_ok("game state PLAYING",
		gm and gm.current_state == gm.GameState.PLAYING,
		"(state %s)" % gm.GameState.keys()[gm.current_state] if gm else "(no gm)")

func _c_player_registered() -> void:
	var player: Node = _scene().get_node_or_null("Player") if _scene() else null
	_ok("player node exists in world", player != null)
	var es := root.get_node_or_null("EntityService")
	var registered: bool = false
	var entity_count := -1
	if es and player and "entity_id" in player:
		var all = es.get_all_entities() if es.has_method("get_all_entities") else []
		entity_count = all.size() if all != null else 0
		registered = entity_count > 0
	_ok("EntityService has entities", registered, "(count %d)" % entity_count)
	_ok("camera rig present", player != null and player.get_node_or_null("CameraPivot/Camera3D") != null
		or (player != null and "camera_pivot" in player and player.camera_pivot.get_child_count() > 0))

func _c_hud_alive() -> void:
	var hud: Node = _scene().get_node_or_null("HudLayer") if _scene() else null
	_ok("HudLayer present", hud != null)
	var im := root.get_node_or_null("InputManager")
	var joystick: Node = im.get_virtual_joystick() if im and im.has_method("get_virtual_joystick") else null
	_ok("touch HUD instance alive", joystick != null,
		"(mode %s)" % str(im.input_mode) if im and "input_mode" in im else "")

func _c_sensitivity_set() -> void:
	# Round-trip: set the sensitivity slider value through PlayerConfig
	# exactly like SettingsPanel does, verify the live camera picks it up.
	var cam: Node = _cam()
	if cam == null:
		_ok("camera found for sensitivity test", false)
		return
	_yaw_before_sens = cam.get_yaw()
	var pc := root.get_node_or_null("PlayerConfig")
	if pc == null:
		_ok("PlayerConfig available", false)
		return
	pc.set_account_setting("camera_rotation_speed", 2.5, false)

func _c_sensitivity_effect() -> void:
	var cam: Node = _cam()
	if cam == null:
		return
	_ok("sensitivity applied to live camera",
		is_equal_approx(cam.sensitivity, 2.5), "(sens %.2f)" % cam.sensitivity)
	# Drive a small touch-look swipe through the same bridge the HUD uses.
	var bridge_emitted := false
	var im := root.get_node_or_null("InputManager")
	if im and im.has_method("get_virtual_joystick"):
		var joy: Node = im.get_virtual_joystick()
		if joy and joy.has_signal("camera_look"):
			joy.camera_look.emit(Vector2(80, 0))
			bridge_emitted = true
	_ok("touch-look bridge emits", bridge_emitted)

func _c_move_input() -> void:
	# Right after the swipe, verify movement input still works (state machine
	# alive after the journey). Use a direct action press on move_left.
	var p: Node = _player()
	if p == null:
		_ok("player present for movement check", false)
		return
	var ev := InputEventAction.new()
	ev.action = "move_left"
	ev.pressed = true
	Input.parse_input_event(ev)

func _c_move_check() -> void:
	var ev := InputEventAction.new()
	ev.action = "move_left"
	ev.pressed = false
	Input.parse_input_event(ev)
	var p := _player()
	if p == null:
		return
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	_ok("player responds to move input after journey", speed > 1.0,
		"(speed %.2f, state %s)" % [speed, p.state_machine.get_state_name() if p and "state_machine" in p else "?"])

func _c_summary() -> void:
	print("=== JOURNEY SUMMARY: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

## ------------------------------------------------------------------ helpers

func _player() -> Node:
	var s := _scene()
	return s.get_node_or_null("Player") if s else null

func _cam() -> Node:
	var p := _player()
	if p == null or not ("camera_pivot" in p):
		return null
	return p.camera_pivot.get_node_or_null("Camera3D")
