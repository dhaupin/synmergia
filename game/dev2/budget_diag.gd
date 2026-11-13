extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	ProjectSettings.set_setting("synmergia/world/planet_radius", 20000.0)
	var packed: PackedScene = load("res://scenes/worlds/globe_world.tscn")
	var globe = packed.instantiate()
	root.add_child(globe)
	await process_frame
	await process_frame
	var st = globe.get("streamer")
	var F = load("res://core/frame/math/icosahedral_faces.gd")
	for tgt in [19, 2]:
		var t0: int = Time.get_ticks_usec()
		st.update(F.face_center(tgt) * 20000.0)
		var dt: float = float(Time.get_ticks_usec() - t0) / 1000000.0
		print("LEG face=%d took %.2f s meshes=%d" % [tgt, dt, st.ground_meshes().size()])
	quit(0)
