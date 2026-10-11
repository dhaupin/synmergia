extends SceneTree
# Hypothesis: by this point in the real test, the FIRST probe panel
# (from section 1) is still in the tree and being freed via
# queue_free, or the Extra late button from the debounce test exists.
# The labeled first test surface's tree may affect focus grabbing:
# activate() first grabs focus on the slot; the earlier default focus
# grab may consume the click position. Reproduce the FULL R36 prefix.
func _init() -> void:
	await process_frame
	var svc = root.get_node_or_null("A11yService")
	# section-1 fixture, exactly as in the suite
	var panel := PanelContainer.new()
	panel.name = "ProbePanel"
	root.add_child(panel)
	var btn_a := Button.new(); btn_a.name = "StartButton"; btn_a.text = "Start"; panel.add_child(btn_a)
	var btn_b := Button.new(); btn_b.name = "GuestButton"; btn_b.text = "Play as Guest"; panel.add_child(btn_b)
	var field := LineEdit.new(); field.name = "UsernameField"; field.placeholder_text = "username"; panel.add_child(field)
	var disabled := Button.new(); disabled.name = "LockedButton"; disabled.text = "Locked"; disabled.disabled = true; panel.add_child(disabled)
	var plain := Label.new(); plain.name = "NotActionable"; plain.text = "Just a label"; panel.add_child(plain)
	var loading_layer := CanvasLayer.new(); loading_layer.name = "BootLoadingLayer"; root.add_child(loading_layer)
	var hidden_btn := Button.new(); hidden_btn.name = "HiddenDuringBoot"; hidden_btn.text = "Invisible Action"; loading_layer.add_child(hidden_btn)
	await process_frame; await process_frame
	# R36 fixture
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
	print("idx=", slot_idx, " snapSize=", s2.size())
	var ok: bool = svc.activate(slot_idx)
	await process_frame; await process_frame
	print("activate=", ok, " clicks=", clicks["n"])
	quit(0)
