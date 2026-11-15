extends SceneTree
func _initialize() -> void:
	var ds = root.get_node_or_null("DataService")
	if ds and ds.has_method("load_all_data"):
		ds.load_all_data()
	var ach = root.get_node_or_null("AchievementService")
	ach._load_achievement_definitions()
	var pm = root.get_node_or_null("PlayerManager")
	var pscript = load("res://entities/player/player_controller.gd")
	var pnode = pscript.new()
	pnode.entity_id = "probe_2"
	pm.set_local_player(pnode)
	var def = ach.get_achievement("slayer_10")
	print("t1: direct _grant_rewards ->")
	ach._grant_rewards("probe_2", def)
	print("gold now: ", pm.gold, " (expect 200)")
	print("t2: get_achievement returns AchievementData? ", def is AchievementData)
	print("t3: TitleService exists: ", root.get_node_or_null("TitleService") != null)
	pnode.free()
	quit(0)
