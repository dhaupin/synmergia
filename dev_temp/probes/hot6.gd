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
	print("H6 walked")
	var st = globe.get("streamer")
	var live := 0
	var freed := 0
	for f in st.active_faces():
		var arr: Array = st._patch_boulders.get(f, [])
		live += arr.size()
		for b in arr:
			if not is_instance_valid(b):
				freed += 1
				continue
			var body = b.get_node_or_null("PropBody")
			var g_ok = body != null and is_instance_valid(body) and body.is_in_group("climbable")
			print("H6 face=", f, " climbable=", g_ok, " body_name=", (body.name if body != null else "?"), " body_type=", ("StaticBody3D" if body is StaticBody3D else "NOT-BODY"))
	print("H6 audit live=", live, " freed_refs=", freed)
	await process_frame
	await physics_frame
	print("H6 idle frames ok")
	await process_frame
	globe.queue_free()
	await process_frame
	print("H6 freed clean")
	quit(0)
