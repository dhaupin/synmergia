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
	print("H4 walked")
	var st = globe.get("streamer")
	for f in st.active_faces():
		print("H4 face=", f, " boulders=", (st._patch_boulders.get(f, []) as Array).size(), " lvl=", st._patch_lvl.get(f))
	print("H4 no node access")
	await physics_frame
	print("H4 physics frame ok")
	await process_frame
	print("H4 process frame ok")
	quit(0)
