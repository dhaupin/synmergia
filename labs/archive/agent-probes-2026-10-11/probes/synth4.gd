extends SceneTree
var clicks := {"n": 0}
func _init() -> void:
	await process_frame
	var svc = root.get_node_or_null("A11yService")
	var panel := PanelContainer.new()
	panel.name = "ProbePanel"
	root.add_child(panel)
	var btn_a := Button.new(); btn_a.name = "StartButton"; btn_a.text = "Start"; panel.add_child(btn_a)
	var loading_layer := CanvasLayer.new(); loading_layer.name = "BootLoadingLayer"; root.add_child(loading_layer)
	var hidden_btn := Button.new(); hidden_btn.text = "Hidden"; loading_layer.add_child(hidden_btn)
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
	slot.gui_input.connect(_on_slot_gui)
	var s2: Array = svc.snapshot()
	var slot_idx := -1
	for i in range(s2.size()):
		if String(s2[i]["action"]) == "Cast Fireball":
			slot_idx = i
			print("snap rect=", s2[i]["rect"], " real rect=", slot.get_global_rect())
	slot.grab_focus()
	await process_frame
	print("after focus rect=", slot.get_global_rect(), " visible=", slot.is_visible_in_tree())
		# Layer hijack test: hide the loading layer entirely, then activate.
	loading_layer.visible = false
	await process_frame
	var ok: bool = svc.activate(slot_idx)
	print("activate=", ok, " clicks=", clicks["n"])
	quit(0)
func _on_slot_gui(ev) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		clicks["n"] += 1
		print("  gui event at pos=", ev.position, " pressed=", ev.pressed)
