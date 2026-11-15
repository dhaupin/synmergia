# Add the FIRST surface (panel + 4 controls + queue_free'd LATER) before
# the hud surface -- queue_free of panel happens at end (not before):
# the free'd-tree state at activate time is the difference.
extends SceneTree
func _init() -> void:
	await process_frame
	var svc = root.get_node_or_null("A11yService")
	var panel := PanelContainer.new(); panel.name = "ProbePanel"; root.add_child(panel)
	var btn_a := Button.new(); btn_a.text = "Start"; panel.add_child(btn_a)
	var btn_b := Button.new(); btn_b.text = "Play as Guest"; panel.add_child(btn_b)
	var field := LineEdit.new(); field.placeholder_text = "username"; panel.add_child(field)
	var disabled := Button.new(); disabled.text = "Locked"; disabled.disabled = true; panel.add_child(disabled)
	await process_frame; await process_frame
	var hud_panel := PanelContainer.new(); hud_panel.name = "HudProbePanel"; root.add_child(hud_panel)
	await process_frame
	var slot := PanelContainer.new(); slot.custom_minimum_size = Vector2(52, 52); hud_panel.add_child(slot)
	var US = load("res://ui/components/ui_styles.gd")
	US.apply_accessibility(slot, "Cast Fireball", "12 mana.")
	await process_frame
	var clicks := {"n": 0}
	slot.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			clicks["n"] += 1)
	var snap: Array = svc.snapshot()
	var slot_idx := -1
	for i in range(snap.size()):
		if String(snap[i]["action"]) == "Cast Fireball":
			slot_idx = i
	svc.activate(slot_idx)
	for i in range(3):
		await process_frame
	print("B clicks=", clicks["n"])
	quit(0)
