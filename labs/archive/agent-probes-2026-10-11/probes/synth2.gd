extends SceneTree
func _init() -> void:
	await process_frame
	var svc = root.get_node_or_null("A11yService")
	# EXACT test reproduction, timings included:
	var hud_panel := PanelContainer.new()
	hud_panel.name = "HudProbePanel"
	root.add_child(hud_panel)
	await process_frame
	var slot := PanelContainer.new()
	slot.name = "Slot_0"
	slot.custom_minimum_size = Vector2(52, 52)
	hud_panel.add_child(slot)
	var US = load("res://ui/components/ui_styles.gd")
	US.apply_accessibility(slot, "Cast Fireball", "12 mana.")
	await process_frame
	var clicks := {"n": 0}
	slot.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			clicks["n"] += 1)
	var s2: Array = svc.snapshot()
	var slot_idx := -1
	for i in range(s2.size()):
		if String(s2[i]["action"]) == "Cast Fireball":
			slot_idx = i
	print("idx=", slot_idx, " size=", s2.size())
	var ok: bool = svc.activate(slot_idx)
	await process_frame
	await process_frame
	print("activate=", ok, " clicks=", clicks["n"])
	quit(0)
