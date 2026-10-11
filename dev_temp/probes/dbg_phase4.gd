extends SceneTree
func _initialize() -> void:
	await process_frame
	var tick = root.get_node_or_null("TickService")
	var zm = root.get_node_or_null("ZoneManager")
	var es = root.get_node_or_null("EntityService")
	var pm = root.get_node_or_null("PlayerManager")
	var fs = root.get_node_or_null("FrameService")
	if tick._tick_timer != null:
		tick._tick_timer.stop()
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var player: Node = PlayerScript.new()
	player.display_name = "AoiHero"
	player.entity_id = "aoi_char"
	root.add_child(player)
	await process_frame
	es.register_entity(player, null, "aoi_char")
	pm.set_local_player(player)
	var ZoneDataScript = load("res://core/schemas/zone_data.gd")
	var zone_a = ZoneDataScript.new()
	zone_a.id = "aoi_zone"
	zone_a.zone_center = Vector3(0, 0, 0)
	zone_a.zone_radius = 100.0
	zm.register_zone(zone_a)
	var tree = fs.get_world_state_tree()
	print("DBG tick._state_tree == fs tree: ", tick._state_tree == tree)
	var prev: PackedByteArray = tree.root_hash()
	tree.insert_state("/world/zones/aoi_zone/entities/horde_1/health", "horde_1", "health", {"current": 10, "max": 10})
	tree.insert_state("/player/aoi_char/progress", "aoi_char", "health", {"current": 100, "max": 200})
	var cur: PackedByteArray = tree.root_hash()
	print("DBG prev==cur: ", prev == cur)
	var full: Array = tree.diff_states(prev, cur)
	print("DBG full_diff size: ", full.size())
	for e in full:
		print("DBG entry path: ", str(e[0]) if e is Array and e.size() > 0 else "??")
	tick._previous_root_hash = prev
	tick._current_root_hash = cur
	var aoi: Dictionary = tick._compute_aoi_diff(1)
	print("DBG aoi keys: ", aoi.keys())
	for k in aoi.keys():
		print("DBG aoi[", k, "] size: ", aoi[k].size())
	quit(0)
