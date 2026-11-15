extends SceneTree
func _initialize() -> void:
	await process_frame
	var hud: Node = (load("res://ui/hud/hud_layer.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	var panel: Node = hud.get_node_or_null("SettingsPanel")
	print("has Panel node=", panel.has_node("Panel"))
	print("visible=", panel.visible, " _is_open=", panel._is_open)
	print("_category_containers=", panel._category_containers.size())
	print("_tab_buttons=", panel._tab_buttons.size())
	quit(0)
