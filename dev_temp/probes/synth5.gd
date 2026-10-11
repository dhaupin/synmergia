extends SceneTree
func _init() -> void:
	await process_frame
	var panel := PanelContainer.new()
	panel.name = "ProbePanel"
	root.add_child(panel)
	var btn_a := Button.new(); btn_a.name = "StartButton"; btn_a.text = "Start"; panel.add_child(btn_a)
	var hud_panel := PanelContainer.new()
	hud_panel.name = "HudProbePanel"
	root.add_child(hud_panel)
	var slot := PanelContainer.new()
	slot.name = "Slot_0"
	slot.custom_minimum_size = Vector2(52, 52)
	hud_panel.add_child(slot)
	await process_frame; await process_frame
	var clicks := {"n": 0}
	slot.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			clicks["n"] += 1)
	var c: Vector2 = Vector2(26, 26)
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = c
	down.global_position = c
	var up: InputEventMouseButton = down.duplicate()
	up.pressed = false
	var vp := root.get_viewport()
	print("pre: clicks=", clicks["n"])
	vp.push_input(down, true)
	print("post-down: clicks=", clicks["n"])
	vp.push_input(up, true)
	await process_frame
	print("post-up: clicks=", clicks["n"], " center=", c)
	quit(0)
