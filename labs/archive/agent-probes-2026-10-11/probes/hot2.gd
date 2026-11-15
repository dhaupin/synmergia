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
	print("SWEEP begin")
	# full walk: cross every face boundary like the lattice probe.
	var F = load("res://core/frame/math/icosahedral_faces.gd")
	for f in range(F.face_count()):
		var stats: Dictionary = st.update(F.face_center(f) * 20000.0)
		print("SWEEP face=", st.current_face, " loaded=", stats["loaded"], " unloaded=", stats["unloaded"])
		await process_frame
	print("SWEEP all faces done")
	# now free the whole globe
	globe.queue_free()
	await process_frame
	await process_frame
	print("SWEEP freed clean")
	quit(0)
