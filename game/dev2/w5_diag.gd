extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var G = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = G.world_seed_bytes()
	var sea: float = G.sea_level(seed_b)
	var isl: Vector3 = G.ISLAND_CENTER
	var top: float = G.terrain_height(isl, seed_b)
	print("sea=", sea, " ISLAND_PLATEAU=", G.ISLAND_PLATEAU, " expected_top=", sea + 2.0 + G.ISLAND_PLATEAU, " actual_top=", top)
	# walk small rings around the island center: where does 70 come from?
	var axis: Vector3 = Vector3(0, 1, 0).cross(isl).normalized()
	for k in range(6):
		var ang: float = 0.002 * float(k)
		var d: Vector3 = isl.rotated(axis, ang)
		print("k=", k, " ang=", ang, " h=", G.terrain_height(d, seed_b), " ang_spawn=", d.angle_to(G.SPAWN_CENTER), " ang_isl_reach=", G.ISLAND_ANGULAR_REACH)
	quit(0)
