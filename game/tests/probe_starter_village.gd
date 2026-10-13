## Probe: the STARTER VILLAGE PROTO (the ledger's parked build).
## Headless script mode:
##   godot --headless --path game --script res://tests/probe_starter_village.gd
##
## The village rides the plaza's own laws, so the probe pins BOTH
## layers:
##   LAW (no scene): every authored structure direction lands on the
##     plaza's exact flat ground (== SPAWN_HEIGHT), stays dry above
##     the sea line, and reads a CLEAN cartway corridor (the road bend
##     and the apron rank keep the cartway out of the village).
##   SCENE (the globe boot): the village node exists under world_root
##     with the THREE authored structures, each carrying the one-law
##     PropBody collider (climbable group), and each sitting at
##     planet_radius + lift + the walk law's plaza height.
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"

var _fails: int = 0


func _check(label: String, cond: bool) -> bool:
	if cond:
		print("PASS: " + label)
	else:
		_fails += 1
		printerr("FAIL: " + label)
	return cond


func _dir_for(V, spawn: Vector3, east: Vector3, north: Vector3, bearing: float, reach: float) -> Vector3:
	var rad: float = deg_to_rad(float(bearing))
	return (spawn + east * (float(reach) * cos(rad)) \
		+ north * (float(reach) * sin(rad))).normalized()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var TGen = load("res://scenes/worlds/terrain_gen.gd")
	var SV = load("res://entities/starter_village.gd")
	var seed_b: PackedByteArray = TGen.world_seed_bytes()
	var sea: float = TGen.sea_level(seed_b)
	var spawn: Vector3 = TGen.SPAWN_CENTER
	var east: Vector3 = Vector3(0, 1, 0).cross(spawn).normalized()
	var north: Vector3 = spawn.cross(east).normalized()

	var layout: Array = [
		["VillageHall", SV.HALL_BEARING_DEG, SV.HALL_REACH],
		["ForgeStall", SV.FORGE_BEARING_DEG, SV.FORGE_REACH],
		["WaySignpost", SV.SIGN_BEARING_DEG, SV.SIGN_REACH],
	]

	# LAW layer: plaza-flat ground, dry, clean corridor.
	for entry in layout:
		var dir: Vector3 = _dir_for(SV, spawn, east, north, float(entry[1]), float(entry[2]))
		var h: float = TGen.terrain_height(dir, seed_b)
		_check("%s foot is plaza-flat (h %.3f == spawn %.1f)" % [entry[0], h, TGen.SPAWN_HEIGHT],
			absf(h - TGen.SPAWN_HEIGHT) < 0.01)
		_check("%s foot is dry above the sea line" % entry[0], h > sea + 1.0)
		# The cartway law's action, not its raw reach: the bend keeps
		# the route out of the apron and the rank bars the corridor
		# from carving OR tinting inside it -- the village foot keeps
		# its exact ground even when the path passes nearby.
		var st: Vector3 = TGen.road_state_at(dir, seed_b)
		var h_road: float = TGen.road_height_override(dir, seed_b, h)
		_check("%s foot keeps its ground under the cartway law (w %.2f, no regrade)" % [entry[0], st.x],
			absf(h_road - h) < 0.001)
		_check("%s sits inside the plaza flat ring" % entry[0],
			dir.angle_to(spawn) < TGen.SPAWN_FLAT_ANG)

	# SCENE layer: the globe boots the village with colliders.
	ProjectSettings.set_setting("synmergia/world/planet_radius", 100.0)
	var packed: PackedScene = load(GLOBE_SCENE)
	var globe = packed.instantiate()
	root.add_child(globe)
	await process_frame
	await process_frame

	var world_root: Node = globe.get("world_root")
	var village: Node3D = world_root.get_node_or_null("StarterVillage")
	if not _check("the village boots into the world", village != null):
		quit(1)
		return
	_check("the village carries exactly the 3 authored structures",
		village.get_child_count() == 3)
	var expected: Array = ["VillageHall", "ForgeStall", "WaySignpost"]
	var names_ok := true
	for child in village.get_children():
		if not (child.name in expected):
			names_ok = false
	_check("structure names match the authored layout", names_ok)
	for child in village.get_children():
		var body: Node = child.get_node_or_null("PropBody")
		_check("%s carries the one-law PropBody" % child.name, body != null)
		if body != null:
			var body3d := body as StaticBody3D
			_check("%s PropBody joins the climbable group" % child.name,
				body3d.is_in_group("climbable"))
		# Position law: |pos| == planet_radius + lift + walk height.
		var pl: float = globe.get("planet_radius")
		var walker: Callable = Callable(globe.get("streamer"), "walk_surface_h")
		var dir_s: Vector3 = child.position.normalized()
		var expected_r: float = pl + 0.52 + float(walker.call(dir_s))
		_check("%s rides the walk law's lift (r %.2f ~ %.2f)" % [child.name, child.position.length(), expected_r],
			absf(child.position.length() - expected_r) < 0.5)

	print("probe_starter_village: %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	quit(0 if _fails == 0 else 1)
