## Runtime audit: which HUD panels built their UI vs silently bailed.
extends SceneTree
func _initialize() -> void:
	await process_frame
	var hud: Node = (load("res://ui/hud/hud_layer.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	var names := ["ActionBar", "QuickAccessBar", "DialogUI", "SettingsPanel", "LoadingUI",
		"ActionMenu", "FactionUI", "AchievementUI", "ShopUI", "QuestUI", "TitleUI",
		"WorldMap", "Minimap", "TargetFrame", "BuffBar", "CombatLog", "BossHealthBar", "TooltipManager"]
	print("--- PANEL BUILD AUDIT ---")
	for n in names:
		var p: Node = hud.get_node_or_null(n)
		if p == null:
			print("ABSENT   ", n)
			continue
		var s = p.get_script()
		var sp: String = s.resource_path if s else ""
		var has_panel: bool = p.has_node("Panel")
		var child_count: int = p.get_child_count()
		print("node=%-18s panel=%s children=%d script=%s" % [n, str(has_panel), child_count, sp.get_file()])
	quit(0)
