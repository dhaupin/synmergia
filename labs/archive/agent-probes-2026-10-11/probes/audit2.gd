extends SceneTree
func _initialize() -> void:
	await process_frame
	var hud: Node = (load("res://ui/hud/hud_layer.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	var names := ["ActionBar", "QuickAccessBar", "DialogUI", "SettingsPanel", "LoadingUI",
		"ActionMenu", "FactionUI", "AchievementUI", "ShopUI", "QuestUI", "TitleUI"]
	print("--- POST-FIX AUDIT ---")
	for n in names:
		var p: Node = hud.get_node_or_null(n)
		if p == null:
			print("ABSENT   ", n)
			continue
		var has_panel: bool = p.has_node("Panel")
		var panel_children: int = 0
		var has_main: bool = false
		if has_panel:
			var pn: Node = p.get_node("Panel")
			panel_children = pn.get_child_count()
			has_main = pn.has_node("Main")
		print("node=%-16s panel=%s main=%s panel_children=%d" % [n, str(has_panel), str(has_main), panel_children])
	quit(0)
