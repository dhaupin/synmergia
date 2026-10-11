extends SceneTree
func _initialize() -> void:
	var ds = root.get_node_or_null("DataService")
	if ds and ds.has_method("load_all_data"):
		ds.load_all_data()
	var ach = root.get_node_or_null("AchievementService")
	ach._load_achievement_definitions()
	var pid := "probe4_%d" % Time.get_ticks_msec()
	ach.track(pid, "enemy", 1)  # kill before local player exists
	var pm = root.get_node_or_null("PlayerManager")
	var pscript = load("res://entities/player/player_controller.gd")
	var pnode = pscript.new()
	pnode.entity_id = pid
	pm.set_local_player(pnode)
	# manual grant of slayer_10 (unlocked=false here, so no guard issue)
	var def = ach.get_achievement("slayer_10")
	ach._grant_rewards(pid, def)
	print("A: after manual grant, gold=", pm.gold, " (expect 200)")
	pm.gold = 0
	# now track to trigger the real unlock path
	ach.track(pid, "enemy", 9)
	print("B: unlocked=", ach.has_unlocked(pid, "slayer_10"), " gold=", pm.gold, " (expect 200 via _do_unlock)")
	print("C: local_player=", pm.get("local_player"), " eid=", pnode.entity_id)
	pnode.free()
	quit(0)
