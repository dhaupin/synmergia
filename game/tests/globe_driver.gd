## Globe driver - the full real-flow pass on the spherical world
## (prd-spherical-mvp.md, part 2). Boots the actual menu flow like a
## player, with the shape knob flipped so the spherical world loads,
## then walks the globe and HUD-panels on it.
##
## Run rendered (real 3D flow; headless skips the world scene):
##   GODOT_PROBE_XVFB=1 xvfb-run -a godot --path game --script res://tests/globe_driver.gd
## Shots: /tmp/play/globe_flow_*.png
extends SceneTree

var _fail: String = ""


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/play")
	_run()


func _run() -> void:
	await process_frame
	await process_frame

	# Rendered-only: GameManager skips world scene loads in headless
	# mode (no render context), so the flow cannot be exercised here.
	# Self-skip honestly instead of failing.
	if DisplayServer.get_name() == "headless":
		print("GLOBEDRIVER SKIP: rendered-only test (xvfb-run / full godot)")
		quit(0)
		return

	# Spherical world on (the S2 knob; GameManager branches on it).
	ProjectSettings.set_setting("synmergia/world/shape", "spherical")

	# --- Stage 1: main menu (real boot scene) ------------------------
	change_scene_to_file("res://ui/menus/main_menu.tscn")
	if not await _wait_scene("MainMenu", 4.0):
		_fail += "menu; "
	await _settle(0.6)
	_shot("globe_flow_1_menu")

	# --- Stage 2: Start -> login(guest) -> lobby(create) -> select ---
	# (round-6 menu: one Start button, one flow)
	var start_btn := current_scene.get_node_or_null("MenuButtons/StartButton")
	if start_btn != null:
		start_btn.grab_focus()
	await _settle(0.3)
	_key(KEY_ENTER)
	if not await _wait_scene("Login", 6.0):
		_fail += "login_route; "
	await _settle(0.4)
	var guest_btn := current_scene.get_node_or_null("Center/Panel/Form/Buttons/GuestButton")
	if guest_btn != null:
		guest_btn.grab_focus()
	await _settle(0.2)
	_key(KEY_ENTER)
	if not await _wait_scene("Lobby", 6.0):
		_fail += "lobby_route; "
	await _settle(0.4)
	var create_btn := current_scene.get_node_or_null("Center/Panel/VBox/Buttons/CreateButton")
	if create_btn != null:
		create_btn.grab_focus()
	await _settle(0.2)
	_key(KEY_ENTER)
	if not await _wait_scene("CharacterSelect", 6.0):
		_fail += "char_select_route; "
	await _settle(0.8)
	_shot("globe_flow_2_select")

	# --- Stage 3: pick species + class via real handlers -------------
	var sel := current_scene
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
	var world_ok: bool = await _wait_scene_any(["GlobeWorld", "WorldPlayable"], 12.0)
	if not world_ok:
		_fail += "world_route; "
	if current_scene != null and current_scene.name != "GlobeWorld":
		_fail += "wrong_world_" + (current_scene.name if current_scene else "null") + "; "
	await _settle(2.0)
	_shot("globe_flow_4_globe_spawn")

	# --- Stage 5: walk the sphere (real input map) -------------------
	_walk_ticks(60)
	await _settle(0.5)
	_shot("globe_flow_5_globe_walked")

	# Ground truth: player exists and rides the sphere.
	var globe := current_scene
	var player = globe.get("player") if globe != null else null
	if player == null:
		_fail += "no_player; "
	else:
		var r: float = player.global_position.length()
		var err: float = abs(r - (100.0 + 1.0))
		if err > 0.5:
			_fail += "off_shell_%.2f; " % err
		print("globe driver: player radial err %.3f m, path %.1f m" % [err, player.path_walked])

	# --- Stage 6: HUD panel over the globe (real hotkey) -------------
	_key(KEY_I)
	await _settle(0.8)
	_shot("globe_flow_6_panel")
	_key(KEY_ESCAPE)
	await _settle(0.3)

	print("GLOBEDRIVER done fail_flags=", _fail)
	quit(0 if _fail == "" else 1)


func _wait_scene_any(names: Array, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		await process_frame
		t += 1.0 / 60.0
		if current_scene != null and current_scene.name in names:
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


func _walk_ticks(n: int) -> void:
	for i in n:
		var ev := InputEventAction.new()
		ev.action = "move_forward"
		ev.pressed = true
		Input.parse_input_event(ev)
		await process_frame
		var up := InputEventAction.new()
		up.action = "move_forward"
		up.pressed = false
		Input.parse_input_event(up)
		await process_frame


func _settle(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		t += 1.0 / 60.0


func _shot(stage_name: String) -> void:
	if OS.get_environment("GODOT_PROBE_XVFB") == "":
		return
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("no screenshot for %s" % stage_name)
		return
	img.save_png("/tmp/play/%s.png" % stage_name)
	print("  shot: /tmp/play/%s.png" % stage_name)
