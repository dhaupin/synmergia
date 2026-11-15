extends SceneTree
func _initialize() -> void:
	var ds = root.get_node_or_null("DataService")
	if ds and ds.has_method("load_all_data"):
		ds.load_all_data()
	var ach = root.get_node_or_null("AchievementService")
	ach._load_achievement_definitions()
	var pid := "probe3_%d" % Time.get_ticks_msec()
	# Step 4 replica: first kill BEFORE local player exists
	ach.track(pid, "enemy", 1)
	var pm = root.get_node_or_null("PlayerManager")
	var pscript = load("res://entities/player/player_controller.gd")
	var pnode = pscript.new()
	pnode.entity_id = pid
	pm.set_local_player(pnode)
	var gold_before: int = pm.gold
	ach.track(pid, "enemy", 9)
	print("unlocked: ", ach.has_unlocked(pid, "slayer_10"))
	print("gold_before=", gold_before, " gold_after=", pm.gold, " delta=", pm.gold - gold_before)
	print("gold_reward of slayer_10: ", ach.get_achievement("slayer_10").gold_reward)
	pnode.free()
	quit(0)
