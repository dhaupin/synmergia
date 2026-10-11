extends SceneTree
const GLOBE_SCENE := "res://scenes/worlds/globe_island.tscn"
const PLANET_RADIUS_20KM := 20000.0
var _globe: Node3D = Node3D.new()
func _init() -> void:
	set_planet_radius(PLANET_RADIUS_20KM)
	if not _build_globe():
		quit(1)
		return
	await root.get_tree().physics_frame
	await root.get_tree().physics_frame
	var player: Node3D = _globe.get("player")
	print("spawned radius: " + str(player.global_position.length()) + " m")
	print("start time: " + str(Time.get_unix_time_from_system()))
	player.begin_loop()
	player.auto_walk = true
	var t0 := 0.0
	while player.path_walked < 5.0 and t0 < 10.0:
		await root.get_tree().physics_frame
		t0 += 1.0 / 60.0
	player.auto_walk = false
	print("walked: " + str(player.path_walked) + " m in " + str(t0) + "s")
	print("end time: " + str(Time.get_unix_time_from_system()))
	quit(0)
func set_planet_radius(r: float) -> void:
	ProjectSettings.set_setting("synmergia/world/planet_radius", r)
func _build_globe() -> bool:
	var packed := load(GLOBE_SCENE)
	if packed == null or not packed.can_instantiate():
		push_error("FAIL: globe scene did not load")
		return false
	_globe = packed.instantiate()
	root.add_child(_globe)
	var player: Node3D = _globe.get("player")
	if player == null or player.get_script() == null:
		push_error("FAIL: player missing")
		return false
	return true
