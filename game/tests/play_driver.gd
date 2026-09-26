## Play driver (batch 15): walks the REAL player flow -- menu, character
## select, world entry, HUD panels -- injecting authentic input events
## and following the game's own state machine (no manual scene swaps:
## after the Enter press we poll for whatever scene the game itself
## loads next). Dumps one screenshot per stage to /tmp/play/ for pixel
## analysis. Windowed run under xvfb, like a player at a dusty desk:
##   cd game && xvfb-run -a godot --path . --script res://tests/play_driver.gd
extends SceneTree

var _fail := ""

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/play")
	_run()

func _run() -> void:
	await process_frame
	await process_frame

	# --- Stage 1: main menu (project boot scene) ---------------------
	change_scene_to_file("res://ui/menus/main_menu.tscn")
	if not await _wait_scene("MainMenu", 4.0):
		_fail += "menu; "
	await _settle(0.6)
	_shot("1_menu")

	# Focus-walk like a keyboard player: focus Play explicitly (a mouse
	# click also focuses; TAB-counting across a 3-button menu is how you
	# accidentally quit) then press Enter.
	var play_btn := current_scene.get_node_or_null("MenuButtons/PlayButton")
	if play_btn != null:
		play_btn.grab_focus()
	await _settle(0.3)
	_key(KEY_ENTER)
	# The menu routes through GameManager -> character select. Follow it.
	if not await _wait_scene("CharacterSelect", 6.0):
		_fail += "char_select_route; "
		# Recovery so later stages still run: load it ourselves.
		change_scene_to_file("res://ui/menus/character_select.tscn")
		await _wait_scene("CharacterSelect", 4.0)
	await _settle(0.8)
	_shot("2_char_select")

	# --- Stage 2: pick species + class via the real card handlers ----
	var sel := current_scene
	if sel != null and sel.has_method("_on_species_card_selected"):
		sel.call("_on_species_card_selected", "human")
	await _settle(0.4)
	if sel != null and sel.has_method("_on_class_selected"):
		sel.call("_on_class_selected", "human_warrior")
	await _settle(0.4)
	_shot("3_selected")
	if sel != null and sel.has_method("_on_play_pressed"):
		sel.call("_on_play_pressed")
	# PLAYING state shows a loading screen then the world. Follow it.
	if not await _wait_scene("WorldPlayable", 10.0):
		_fail += "world_route; "

	# --- Stage 3: the world, HUD included ----------------------------
	await _settle(2.0)
	_shot("4_world_spawn")
	_walk_ticks(30)
	await _settle(0.4)
	_shot("5_world_walked")

	# --- Stage 4: HUD panels over the live world (real hotkeys) ------
	for row in [[KEY_V, "almanac"], [KEY_J, "chronicle"], [KEY_I, "inventory"], [KEY_Q, "quests"]]:
		_key(row[0])
		await _settle(0.8)
		_shot("6_panel_" + row[1])
		_key(KEY_ESCAPE)
		await _settle(0.4)

	print("PLAYDRIVER done fail_flags=", _fail)
	quit(0 if _fail == "" else 1)


func _wait_scene(sname: String, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		await process_frame
		t += 1.0 / 60.0
		if current_scene != null and current_scene.name == sname:
			return true
	return false


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
	# Real movement input through the input map, held over N frames.
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


func _settle(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		t += 1.0 / 60.0


func _shot(stage_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("/tmp/play/%s.png" % stage_name)
