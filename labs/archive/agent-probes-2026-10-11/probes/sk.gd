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
		var mi = st._patches.get(f)
		print("SKIRT face=", f, " skirt_tris=", st._patch_skirt_tris.get(f), " surfaces=", (mi.mesh.get_surface_count() if mi and mi.mesh else -1))
	quit(0)
