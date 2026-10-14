extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var road = Gen.road_spec_cached(seed_b)
	var n: int = road.path.size()
	var worst: Array = []
	for i in range(n - 1):
		var gap: float = absf(road.beds[i + 1] - road.beds[i])
		if gap > 15.0:
			worst.append([i, "%.1f" % gap, road.bridges[i], road.bridges[i + 1]])
	worst = worst if worst.size() <= 8 else worst.slice(0, 8)
	print("violations=", worst)
	print("n=", n, " beds sample mid=", road.beds[n / 2])
	quit(0)
