extends SceneTree
func _init() -> void:
	call_deferred("_go")
func _go() -> void:
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	var inst = scene.instantiate()
	root.add_child(inst)
	current_scene = inst
	var p = null
	var last: Vector3 = Vector3.ZERO
	for i in range(600):
		await process_frame
		if p == null:
			p = inst.get_node_or_null("Player")
			if p != null:
				last = p.global_position
				print("FIRST pos: ", last)
		if p != null:
			if p.global_position.distance_to(last) > 50.0:
				print("JUMP at frame %d: %s -> %s" % [i, last, p.global_position])
				print("respawn_point now: ", p.get("respawn_point"))
				var hc = p.get("health_component")
				if hc != null:
					print("bind now: ", hc.get_bind_position())
				quit(0)
				return
			last = p.global_position
	print("NO JUMP in 600 frames; final ", last)
	quit(0)
