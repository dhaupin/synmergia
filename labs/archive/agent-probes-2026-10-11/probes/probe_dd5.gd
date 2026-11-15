extends SceneTree
func _initialize() -> void:
	await process_frame
	var hud: Node = (load("res://ui/hud/hud_layer.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	var panel: Node = hud.get_node_or_null("SettingsPanel")
	# settings_panel._ready: super._ready() -> UIPanel._ready -> _setup_panel (stub) ...
	# Does SettingsPanel override _setup_panel? No. So get_panel() == null forever.
	# Manual: build the base Panel exactly like shop_ui's new override, then re-run.
	var panel_node := PanelContainer.new()
	panel_node.set_anchors_preset(Control.PRESET_CENTER)
	panel_node.custom_minimum_size = Vector2(700, 550)
	panel_node.name = "Panel"
	panel.add_child(panel_node)
	panel._setup_ui()
	print("controls=", panel._setting_controls.size())
	print("has_camera_mode=", panel._setting_controls.has("camera_mode"))
	var info = panel._setting_controls.get("camera_mode", {})
	var ctrl = info.get("control")
	print("camera_mode selected=", ctrl.selected if ctrl else "nil")
	quit(0)
