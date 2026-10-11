extends SceneTree
func _init() -> void:
	call_deferred("_go")
func _go() -> void:
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	var inst = scene.instantiate()
	root.add_child(inst)
	current_scene = inst
	var p = null
	for i in range(300):
		await process_frame
		if p == null:
			p = inst.get_node_or_null("Player")
		if p != null and i == 5:
			print("EARLY pos: ", p.global_position, " respawn_point: ", p.get("respawn_point"))
		if p != null and i == 60:
			print("LATE pos: ", p.global_position, " respawn_point: ", p.get("respawn_point"), " bind: ", p.health_component.get_bind_position() if "health_component" in p else "n/a")
			quit(0)
			return
	quit(0)
