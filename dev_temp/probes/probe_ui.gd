extends SceneTree
func _initialize() -> void:
	var ui_script = load("res://ui/components/sky_almanac_ui.gd")
	var panel = ui_script.new()
	root.add_child(panel)
	await process_frame
	await process_frame
	print("rows=", panel._rows)
	print("rowcount=", panel._rows.get_child_count() if panel._rows != null else -1)
	print("day_label=", panel._day_label.text if panel._day_label != null else "null")
	print("door=", panel._door_label.text.substr(0, 40) if panel._door_label != null else "null")
	panel.free()
	quit(0)
