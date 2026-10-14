extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var road = Gen.road_spec_cached(seed_b)
	var n: int = road.path.size()
	for i in range(0, 60):
		var p: Vector3 = road.path[i].normalized()
		var nb: float = road.beds[i]
		var nat: float = Gen.terrain_height_carved(p, seed_b, "_noroad")
		var ch: float = Gen.river_channel(p, seed_b)
		var surf: float = Gen.hydro_water_surface(p, seed_b)
		if i > 12 and i < 24 or i < 6:
			print("node %3d bed %9.2f nat %9.2f ch %.2f surf %.1f br %.2f" % [i, nb, nat, ch, surf, road.bridges[i]])
	quit(0)
