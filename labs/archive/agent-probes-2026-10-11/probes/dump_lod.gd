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
	var F = load("res://core/frame/math/icosahedral_faces.gd")
	var d1: Vector3 = Vector3(1.0, 0.0, 0.0)
	var lvl: int = st._level_for_edge()
	print("DUMPL2 base=", lvl, " lvls=", str(st.lod_levels()), " tris=", st.triangle_count())
	print("DUMPL2 face((1,0,0))=", F.face_for_direction(d1))
	for f in [16, 18]:
		print("DUMPL2 face ", f, " reach=", st._face_reach(f), " ang=", F.angular_distance_to_center(d1, f))
		# face vertices
		var fv: PackedInt32Array = F.face_vertices(f)
		for vi in fv:
			print("DUMPL2   vert ", vi, "=", load("res://core/frame/math/icosahedral.gd").VERTICES[vi])
	quit(0)
