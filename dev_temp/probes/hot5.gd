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
	print("H5 walked, now NODE ACCESS with validity")
	var st = globe.get("streamer")
	for f in st.active_faces():
		var arr: Array = st._patch_boulders.get(f, [])
		for b in arr:
			if not is_instance_valid(b):
				print("H5 face=", f, " boulder FREED (stale ref)")
				continue
			var body = b.get_node_or_null("PropBody")
			print("H5 face=", f, " boulder valid, body_valid=", body != null and is_instance_valid(body))
	print("H5 node access done")
	await process_frame
	globe.queue_free()
	await process_frame
	print("H5 freed clean")
	quit(0)
