extends SceneTree
func _initialize() -> void:
	await process_frame
	var hud: Node = (load("res://ui/hud/hud_layer.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	var panel: Node = hud.get_node_or_null("SettingsPanel")
	print("panel=", panel)
	if panel:
		print("controls_count=", panel._setting_controls.size())
		print("keys_has_camera_mode=", panel._setting_controls.has("camera_mode"))
		print("keys_has_language=", panel._setting_controls.has("language"))
		var info = panel._setting_controls.get("camera_mode", {})
		print("camera_mode info=", info)
		var ctrl = info.get("control")
		print("ctrl=", ctrl, " selected=", ctrl.selected if ctrl else "nil")
	quit(0)
