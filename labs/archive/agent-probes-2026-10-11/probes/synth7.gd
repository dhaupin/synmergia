extends SceneTree
func _init() -> void:
	await process_frame
	var svc = root.get_node_or_null("A11yService")
	# full R36 prefix: first panel + loading layer + plain label etc.
	var panel := PanelContainer.new()
	panel.name = "ProbePanel"
	root.add_child(panel)
	var btn_a := Button.new(); btn_a.name = "StartButton"; btn_a.text = "Start"; panel.add_child(btn_a)
	var field := LineEdit.new(); field.name = "UsernameField"; field.placeholder_text = "username"; panel.add_child(field)
	var plain := Label.new(); plain.name = "NotActionable"; plain.text = "Just a label"; panel.add_child(plain)
	var loading_layer := CanvasLayer.new(); loading_layer.name = "BootLoadingLayer"; root.add_child(loading_layer)
	var hidden_btn := Button.new(); hidden_btn.text = "Invisible Action"; loading_layer.add_child(hidden_btn)
	await process_frame; await process_frame
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
	var w = slot.get_viewport().gui_get_hovered_control()
	print("hovered=", w)
	print("layer visible=", loading_layer.visible, " hidden_btn.visible in tree=", hidden_btn.is_visible_in_tree())
	var s2: Array = svc.snapshot()
	var slot_idx := -1
	for i in range(s2.size()):
		if String(s2[i]["action"]) == "Cast Fireball":
			slot_idx = i
	var ok: bool = svc.activate(slot_idx)
	await process_frame; await process_frame
	print("activate=", ok, " clicks=", clicks["n"])
	quit(0)
