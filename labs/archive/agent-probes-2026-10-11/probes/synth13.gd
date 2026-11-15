# the suite fixture minus everything except the SECOND-surface clicks:
# does the presence of ANOTHER surface awaiting with process_frame
# matter? iterate: add hud_panel, await, add slot, apply, await, connect,
# snapshot, activate -- identical to suite. Then add 3 frames.
extends SceneTree
func _init() -> void:
	await process_frame
	var svc = root.get_node_or_null("A11yService")
	var hud_panel := PanelContainer.new()
	hud_panel.name = "HudProbePanel"
	root.add_child(hud_panel)
	await process_frame
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(52, 52)
	hud_panel.add_child(slot)
	var US = load("res://ui/components/ui_styles.gd")
	US.apply_accessibility(slot, "Cast Fireball", "12 mana. Key 1.")
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
	print("A clicks=", clicks["n"])
	quit(0)
