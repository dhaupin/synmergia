extends SceneTree
func _init() -> void:
	await process_frame
	var svc = root.get_node_or_null("A11yService")
	var panel := PanelContainer.new()
	root.add_child(panel)
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(52, 52)
	panel.add_child(slot)
	var US = load("res://ui/components/ui_styles.gd")
	US.apply_accessibility(slot, "Cast Probe", "synth")
	await process_frame
	await process_frame
	var clicks := {"n": 0}
	slot.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			clicks["n"] += 1)
	var snap: Array = svc.snapshot()
	var idx := -1
	for i in range(snap.size()):
		if String(snap[i]["action"]) == "Cast Probe":
			idx = i
	print("idx=", idx, " rect=", slot.get_global_rect())
	var ok: bool = svc.activate(idx)
	await process_frame
	await process_frame
	print("activate=", ok, " clicks=", clicks["n"], " focused=", slot.has_focus())
	quit(0)
