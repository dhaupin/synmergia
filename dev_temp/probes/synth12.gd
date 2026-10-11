extends SceneTree
func _init() -> void:
	await process_frame
	var svc = root.get_node_or_null("A11yService")
	var panel := PanelContainer.new(); panel.name = "ProbePanel"; root.add_child(panel)
	var btn_a := Button.new(); btn_a.name = "StartButton"; btn_a.text = "Start"; panel.add_child(btn_a)
	var btn_b := Button.new(); btn_b.name = "GuestButton"; btn_b.text = "Play as Guest"; panel.add_child(btn_b)
	var field := LineEdit.new(); field.name = "UsernameField"; field.placeholder_text = "username"; panel.add_child(field)
	var disabled := Button.new(); disabled.name = "LockedButton"; disabled.text = "Locked"; disabled.disabled = true; panel.add_child(disabled)
	var plain := Label.new(); plain.name = "NotActionable"; plain.text = "Just a label"; panel.add_child(plain)
	var loading_layer := CanvasLayer.new(); loading_layer.name = "BootLoadingLayer"; root.add_child(loading_layer)
	var hidden_btn := Button.new(); hidden_btn.visible = false; hidden_btn.text = "Invisible Action"; loading_layer.add_child(hidden_btn)
	await process_frame; await process_frame
	var extra := Button.new(); extra.name = "LateButton"; extra.text = "Late Arrival"; extra.position = Vector2(0, 120); panel.add_child(extra)
	await create_timer(2.5).timeout
	var hud_panel := PanelContainer.new(); hud_panel.name = "HudProbePanel"; root.add_child(hud_panel)
	await process_frame
	var slot := PanelContainer.new(); slot.name = "Slot_0"; slot.custom_minimum_size = Vector2(52, 52); hud_panel.add_child(slot)
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
			print("rect=", snap[i]["rect"])
	var wp = slot.get_global_rect().get_center()
	var winner = root.get_viewport().gui_get_hovered_control()
	print("center=", wp, " hovered=", winner)
	svc.activate(slot_idx)
	for i in range(3):
		await process_frame
	print("clicks=", clicks["n"])
	quit(0)
