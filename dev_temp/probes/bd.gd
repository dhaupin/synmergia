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
	await process_frame
	var st = globe.get("streamer")
	for f in st.active_faces():
		var arr: Array = st._patch_boulders.get(f, [])
		for b in arr:
			var body = b.get_node_or_null("PropBody")
			print("BOULDAUD face=", f, " boulder_valid=", is_instance_valid(b), " body=", body != null)
	print("BOULDAUD done")
	globe.queue_free()
	await process_frame
	await process_frame
	quit(0)
