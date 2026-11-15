extends SceneTree
func _init() -> void:
	await process_frame
	# isolate: full panel + sorted subtree, click manually after grab_focus
	var panel := PanelContainer.new()
	panel.name = "ProbePanel"
	root.add_child(panel)
	var btn_a := Button.new(); btn_a.name = "StartButton"; btn_a.text = "Start"; panel.add_child(btn_a)
	var loader := CanvasLayer.new(); loader.name = "BootLoadingLayer"; root.add_child(loader)
	var hb := Button.new(); hb.text = "Invisible Action"; loader.add_child(hb)
	await process_frame
	var hud_panel := PanelContainer.new()
	hud_panel.name = "HudProbePanel"
	root.add_child(hud_panel)
	await process_frame
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(52, 52)
	hud_panel.add_child(slot)
	await process_frame; await process_frame
	var clicks := {"n": 0}
	slot.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			clicks["n"] += 1)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	var c: Vector2 = slot.get_global_rect().get_center()
	down.position = c
	down.global_position = c
	var up = down.duplicate()
	up.pressed = false
	var vp = root.get_viewport()
	vp.push_input(down, true)
	vp.push_input(up, true)
	await process_frame
	print("manual: clicks=", clicks["n"])
	# now with loader hidden
	loader.visible = false
	await process_frame
	vp.push_input(down, true)
	vp.push_input(up, true)
	await process_frame
	print("manual+loaderhidden: clicks=", clicks["n"])
	quit(0)
