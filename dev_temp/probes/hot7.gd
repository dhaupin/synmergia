extends SceneTree
var globe = null
func _initialize() -> void:
	ProjectSettings.set_setting("synmergia/world/planet_radius", 20000.0)
	var packed = load("res://scenes/worlds/globe_world.tscn")
	globe = packed.instantiate()
	root.add_child(globe)
	_run2.call_deferred()
func _run2() -> void:
	await process_frame
	var player = globe.get("player")
	player.auto_walk = true
	for i in range(150):
		await physics_frame
	player.auto_walk = false
	print("H7 walked")
	var st = globe.get("streamer")
	var live := 0
	for f in st.active_faces():
		var arr: Array = st._patch_boulders.get(f, [])
		for b in arr:
			if is_instance_valid(b):
				var body = b.get_node_or_null("PropBody")
				if body != null and is_instance_valid(body):
					live += 1
	print("H7 audit done, live=", live)
	for i in range(5):
		await process_frame
		await physics_frame
	print("H7 5 idle frames done")
	ProjectSettings.set_setting("synmergia/world/planet_radius", 100.0)
	await process_frame
	print("H7 radius reset")
	globe.queue_free()
	await process_frame
	await process_frame
	await physics_frame
	print("H7 freed clean")
	quit(0)
