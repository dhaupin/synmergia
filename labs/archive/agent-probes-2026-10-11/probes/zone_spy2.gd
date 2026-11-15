extends SceneTree
var t := 0.0
func _init() -> void:
	call_deferred("_boot")
func _boot() -> void:
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	var inst = scene.instantiate()
	root.add_child(inst)
	current_scene = inst
	# replicate schedule: the transition happens ~1 frame after '5 scene spawns' (~t=0.5-1s?)
	var seen_transition := false
	while t < 8.0:
		await process_frame
		t += 1.0 / 60.0
		var zm = root.get_node_or_null("ZoneManager")
		var p = current_scene.get_node_or_null("Player")
		if p == null:
			continue
		if not seen_transition and zm != null and str(zm.get_entity_zone_id(p)) == "zone_deep_root_camp":
			seen_transition = true
			print("IN DEEP ROOT at t=%.2f pos=%s" % [t, p.global_position])
			var z = zm.get_zone("zone_deep_root_camp")
			print("zone center: ", z.zone_center, " contained: ", z.contains_position(p.global_position))
			quit(0)
			return
	print("never entered; final ", current_scene.get_node_or_null("Player").global_position)
	quit(0)
