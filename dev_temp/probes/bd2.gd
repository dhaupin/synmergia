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
	print("STEP1 streamer boot ok")
	# Force a HOT RELOAD: demote + promote face 16 by hand through the
	# public path and see if the swap itself crashes.
	globe.queue_free()
	await process_frame
	print("STEP2 globe freed")
	quit(0)
