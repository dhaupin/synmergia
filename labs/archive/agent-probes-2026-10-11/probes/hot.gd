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
	var f = st.current_face
	var old_lvl: int = int(st._patch_lvl.get(f))
	print("HOT face=", f, " lvl=", old_lvl)
	var rocks_before: Array = st._patch_rocks.get(f, [])
	print("HOT rocks_before=", rocks_before.size())
	# Force demote below current floor? base-1 is the min; try demote of a NEIGHBOR:
	var nb = load("res://core/frame/math/icosahedral_faces.gd").neighbors(f)
	st._load_patch(nb[0], maxi(2, old_lvl - 1))   # hot path on a demote
	print("HOT demote done; holder_valid=", is_instance_valid(st._prop_holders.get(nb[0])))
	st._load_patch(nb[0], old_lvl)                # promote back
	print("HOT promote done; rocks_after=", (st._patch_rocks.get(nb[0], []) as Array).size())
	await process_frame
	await process_frame
	print("HOT survived two frames")
	globe.queue_free()
	await process_frame
	quit(0)
