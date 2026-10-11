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
	print("H3 walked")
	var st = globe.get("streamer")
	var audit_n := 0
	for f in st.active_faces():
		var arr: Array = st._patch_boulders.get(f, [])
		for b in arr:
			var body = b.get_node_or_null("PropBody")
			if is_instance_valid(b) and is_instance_valid(body) and body.is_in_group("climbable"):
				audit_n += 1
	print("H3 audit n=", audit_n)
	globe.queue_free()
	await process_frame
	await physics_frame
	print("H3 freed+physics flushed")
	quit(0)
