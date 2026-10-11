extends SceneTree
func _initialize() -> void:
	await process_frame
	var hud: Node = (load("res://ui/hud/hud_layer.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	var panel: Node = hud.get_node_or_null("SettingsPanel")
	if panel and panel.has_method("open"):
		panel.open("local")
	elif panel:
		panel.visible = true
	await process_frame
	await process_frame
	print("controls_count=", panel._setting_controls.size())
	print("has_camera_mode=", panel._setting_controls.has("camera_mode"))
	print("has_language=", panel._setting_controls.has("language"))
	quit(0)
