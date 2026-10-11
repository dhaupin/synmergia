extends SceneTree
func _init() -> void:
	await process_frame
	var panel := PanelContainer.new()
	root.add_child(panel)
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(52, 52)
	panel.add_child(slot)
	await process_frame
	await process_frame
	print("visible=", slot.is_visible_in_tree(), " rect=", slot.get_global_rect(), " mouse_filter=", slot.mouse_filter)
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
	var up: InputEventMouseButton = down.duplicate()
	up.pressed = false
	var vp := root.get_viewport()
	print("vp=", vp)
	vp.push_input(down, true)
	vp.push_input(up, true)
	await process_frame
	await process_frame
	print("clicks after viewport.push_input(in_gui): ", clicks["n"])
	quit(0)
