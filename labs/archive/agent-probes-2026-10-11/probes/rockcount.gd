extends SceneTree
func _initialize() -> void:
	# replicate the continent walk numbers for the journal
	ProjectSettings.set_setting("synmergia/world/planet_radius", 20000.0)
	var packed = load("res://scenes/worlds/globe_world.tscn")
	var g = packed.instantiate()
	root.add_child(g)
	_run2.call_deferred()
var g = null
func _run2() -> void:
	await process_frame
	var st = g.get("streamer")
	var F = load("res://core/frame/math/icosahedral_faces.gd")
	var total := 0
	for f in range(F.face_count()):
		st.update(F.face_center(f) * 20000.0)
		await physics_frame
		for fa in st.active_faces():
			total += (st._patch_rocks.get(fa, []) as Array).size()
	print("ROCKTOT total rock refs live across the 20-face walk: ", total)
	quit(0)
