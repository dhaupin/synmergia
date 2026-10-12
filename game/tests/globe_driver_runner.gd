## GlobeDriverRunner - the node-based flow runner for the globe driver.
## WHY THIS EXISTS: the SceneTree-script coroutine in globe_driver.gd
## strands the moment StarterKitService's deferred `await
## create_timer(0.5)` fires inside the world boot (signal emission
## stack). Node-based awaits keep resuming after suspended signal
## handlers; SceneTree-script awaits do not (Godot 4.7.2). So the flow
## stages live here, in a plain Node added to the tree root, and
## globe_driver.gd merely delegates -- this node prints the verdict
## and quits with the right exit code.
##
## Run (from globe_driver wrapper):
##   GODOT_PROBE_XVFB=1 xvfb-run -a godot --path game --script res://tests/globe_driver.gd
## Shots: /tmp/play/globe_flow_*.png
extends Node

## Scene name -> stage-gates below use get_tree().current_scene.
var _fail: String = ""
var _ticks := 0

## Call from the driver's _initialize (via call_deferred so the
## autoloads are live).
func _ready() -> void:
	run()

func run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("/tmp/play")

	# --- Stage 1: main menu (real boot scene) ------------------------
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")
	if not await _wait_scene("MainMenu", 4.0):
		_fail += "menu; "
	await _settle(0.6)
	_shot("globe_flow_1_menu")

	# --- Stage 2: Start -> guest -> lobby(create) -> select ----------
	var start_btn := get_tree().current_scene.get_node_or_null("MenuButtons/StartButton")
	if start_btn != null:
		start_btn.grab_focus()
	await _settle(0.3)
	_key(KEY_ENTER)
	if not await _wait_scene("Login", 8.0):
		_fail += "login_route; "
	await _settle(0.4)
	var guest_btn := _scene_or_null("Center/Panel/Form/Buttons/GuestButton")
	if guest_btn != null:
		guest_btn.grab_focus()
	await _settle(0.2)
	_key(KEY_ENTER)
	if not await _wait_scene("Lobby", 8.0):
		_fail += "lobby_route; "
	await _settle(0.4)
	var create_btn := _scene_or_null("Center/Panel/VBox/Buttons/CreateButton")
	if create_btn != null:
		create_btn.grab_focus()
	await _settle(0.2)
	_key(KEY_ENTER)
	if not await _wait_scene("CharacterSelect", 8.0):
		_fail += "char_select_route; "
	await _settle(0.8)
	_shot("globe_flow_2_select")

	# --- Stage 3: pick species + class via real handlers -------------
	var sel := get_tree().current_scene
	if sel != null and sel.has_method("_on_species_card_selected"):
		sel.call("_on_species_card_selected", "human")
	await _settle(0.4)
	if sel != null and sel.has_method("_on_class_selected"):
		sel.call("_on_class_selected", "human_warrior")
	await _settle(0.4)
	_shot("globe_flow_3_selected")

	# --- Stage 4: Play -> spherical world ----------------------------
	if sel != null and sel.has_method("_on_play_pressed"):
		sel.call("_on_play_pressed")
	var world_ok: bool = await _wait_scene_any(["GlobeWorld", "WorldPlayable"], 40.0)
	if not world_ok:
		_fail += "world_route; "
	if not world_ok:
		_fail += "world_route; "
	print("[drv] stage4 wait done ok=%s scene=%s" % [str(world_ok), str(get_tree().current_scene.name if get_tree().current_scene else "null")])
	await _settle(2.0)
	print("[drv] settled post-spawn")
	if get_tree().current_scene != null and get_tree().current_scene.name != "GlobeWorld":
		_fail += "wrong_world_" + (get_tree().current_scene.name if get_tree().current_scene else "null") + "; "
	await _settle(2.0)
	_shot("globe_flow_4_globe_spawn")

	# --- Stage 5: walk the sphere (real input map) -------------------
	await _walk_for(6.0)
	await _settle(0.5)
	_shot("globe_flow_5_globe_walked")

	# Ground truth: player exists and rides the sphere.
	var globe := get_tree().current_scene
	var player = globe.get("player") if globe != null else null
	if player == null:
		_fail += "no_player; "
	else:
		# ride height, not an absolute radius pin: the shipped config is
		# a 20 km planet (project.godot planet_radius) while the S5b
		# probe family pins the 100 m prototype explicitly. The old
		# absolute |r - 101| check penalized the shipped world (a
		# "63.67 m" error that was just 20000 + normal surface lift).
		# The LAW the driver pins: the body sits ABOVE the base shell by
		# the walk-surface lift at its position -- read the tolerance
		# from the globe itself (player.planet_distance vs planet_radius
		# stays within ~3 m of the boot walk surface 9.0 m).
		var pr: float = float(globe.get("planet_radius"))
		var lift: float = absf(player.planet_distance() - pr)
		if lift > 12.0:
			_fail += "off_shell_%.2f; " % lift
		print("globe driver: player surface lift %.2f m (planet r %.1f), path %.1f m" % [lift, pr, player.path_walked])

	# --- Stage 6: HUD panel over the globe (real hotkey) -------------
	_key(KEY_I)
	await _settle(0.8)
	_shot("globe_flow_6_panel")
	_key(KEY_ESCAPE)
	await _settle(0.3)

	print("GLOBEDRIVER done fail_flags=", _fail)
	await get_tree().process_frame
	get_tree().quit(0 if _fail == "" else 1)


func _scene_or_null(path: String) -> Node:
	var cs := get_tree().current_scene
	return cs.get_node_or_null(path) if cs != null else null


func _wait_scene_any(names: Array, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs != null and cs.name in names:
			return true
	return false


func _wait_scene(sname: String, timeout: float) -> bool:
	return await _wait_scene_any([sname], timeout)


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)


## WALL-CLOCK waits, not frame loops: under xvfb + llvmpipe the globe
## world renders at ~1-2 fps, so a 60-frame walk is a MINUTE of wall. A
## frame-counted settle was misread as a coroutine strand in earlier
## runs -- it was just time dilation. Hold-down uses one timer tick per
## action with the press kept alive by re-firing each timer timeout.
func _walk_for(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		var ev := InputEventAction.new()
		ev.action = "move_forward"
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().create_timer(0.25).timeout
		var up := InputEventAction.new()
		up.action = "move_forward"
		up.pressed = false
		Input.parse_input_event(up)
		t += 0.25


func _settle(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(stage_name: String) -> void:
	if OS.get_environment("GODOT_PROBE_XVFB") == "":
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("no screenshot for %s" % stage_name)
		return
	img.save_png("/tmp/play/%s.png" % stage_name)
	print("  shot: /tmp/play/%s.png" % stage_name)
