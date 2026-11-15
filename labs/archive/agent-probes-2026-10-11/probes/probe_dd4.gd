extends SceneTree
func _initialize() -> void:
	await process_frame
	var hud: Node = (load("res://ui/hud/hud_layer.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	var panel: Node = hud.get_node_or_null("SettingsPanel")
	print("children=", panel.get_children())
	if panel.has_method("get_panel"):
		print("get_panel=", panel.get_panel())
	print("_ready ran? script=", panel.get_script().resource_path)
	# try manual setup
	if panel.has_method("_setup_ui"):
		print("calling _setup_ui manually")
		panel._setup_ui()
		print("after: controls=", panel._setting_controls.size())
	quit(0)
