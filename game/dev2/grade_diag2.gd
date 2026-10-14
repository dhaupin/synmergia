extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var road = Gen.road_spec_cached(seed_b)
	var beds: PackedFloat32Array = PackedFloat32Array(road.beds)
	var n: int = beds.size()
	# Manual clamp (identical to the law's loop).
	for p in range(10):
		var worst: float = 0.0
		for i in range(n - 1):
			var gap: float = beds[i + 1] - beds[i]
			if absf(gap) > 15.0:
				worst = maxf(worst, absf(gap))
				var fix: float = (absf(gap) - 15.0) * 0.5
				if gap > 0.0:
					beds[i + 1] -= fix
					beds[i] += fix
				else:
					beds[i] -= fix
					beds[i + 1] += fix
		print("pass ", p, " worst ", "%.2f" % worst)
		if worst == 0.0:
			break
	var worst_after: float = 0.0
	for i in range(n - 1):
		worst_after = maxf(worst_after, absf(beds[i + 1] - beds[i]) - 15.0)
	print("manual clamp worst overshoot %.2f" % worst_after)
	quit(0)
