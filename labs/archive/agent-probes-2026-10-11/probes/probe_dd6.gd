extends SceneTree
func _initialize() -> void:
	await process_frame
	var pc = root.get_node_or_null("PlayerConfig")
	pc.set_account_setting("camera_mode", 1, true)
	await process_frame
	print("saved camera_mode=", pc.get_account_setting("camera_mode", -1))
	var hud: Node = (load("res://ui/hud/hud_layer.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	var panel: Node = hud.get_node_or_null("SettingsPanel")
	await process_frame
	print("controls=", panel._setting_controls.size())
	var info = panel._setting_controls.get("camera_mode", {})
	var ctrl = info.get("control")
	print("camera_mode selected=", ctrl.selected if ctrl else "nil")
	print("camera_mode value after=", pc.get_account_setting("camera_mode", -1))
	quit(0)
