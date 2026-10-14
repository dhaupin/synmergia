extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	ProjectSettings.set_setting("synmergia/world/planet_radius", 100.0)
	var packed: PackedScene = load("res://scenes/worlds/globe_world.tscn")
	var globe = packed.instantiate()
	root.add_child(globe)
	await process_frame
	await process_frame
	var player = globe.get("player")
	var n: Vector3 = player.get_surface_normal()
	var p: Vector3 = player.global_position
	print("NORM n=", n, " pos=", p, " posdir=", p.normalized(), " delta=", (n - p.normalized()).length())
	var cap = root.get_node_or_null("GlobeWorld/WorldRoot/CapitolMonolith")
	if cap == null:
		for child in root.get_children():
			print("CHILD ", child.name)
	quit(0)
