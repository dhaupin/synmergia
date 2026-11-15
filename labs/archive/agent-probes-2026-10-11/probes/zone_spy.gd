extends SceneTree
func _init() -> void:
	call_deferred("_boot")
func _boot() -> void:
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	var inst = scene.instantiate()
	root.add_child(inst)
	current_scene = inst
	for i in range(400):
		await process_frame
		var zm = root.get_node_or_null("ZoneManager")
		if zm != null and zm.get_zone("zone_deep_root_camp") != null:
			var z = zm.get_zone("zone_deep_root_camp")
			print("ZONE center=%s radius=%s bounds=%s" % [z.zone_center, z.zone_radius, z.bounds])
			var p = current_scene.get_node_or_null("Player")
			print("player pos: ", p.global_position if p else null)
			print("contained: ", z.contains_position(p.global_position) if p else "?")
			quit(0)
			return
	quit(0)
