extends SceneTree
## Throwaway diagnostic for the variety slice: band census on a bigger
## sweep, and the failing color-law probe re-printed with terms.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var Sph = load("res://core/frame/math/spherical.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	# Erosion histogram on dry-warm land (badlands habitat).
	var ga: float = PI * (3.0 - sqrt(5.0))
	var evals := []
	for i in range(2400):
		var y: float = 1.0 - 2.0 * (float(i) + 0.5) / 2400.0
		var r: float = sqrt(maxf(0.0, 1.0 - y * y))
		var th: float = ga * float(i)
		var d: Vector3 = Vector3(cos(th) * r, y, sin(th) * r).normalized()
		var t: float = Gen.climate_temperature(d, seed_b)
		var m: float = Gen.climate_moisture(d, seed_b)
		if m < 0.45 and t > 0.5:
			evals.append(Gen.erosion_field(d, seed_b))
	evals.sort()
	print("dry-warm n=", evals.size())
	for frac in [0.50, 0.60, 0.70, 0.80, 0.85, 0.90, 0.95, 0.99]:
		var idx: int = clampi(int(evals.size() * frac), 0, evals.size() - 1)
		print("erosion p%v = %v" % [frac * 100.0, evals[idx]])
	var keep := []
	for i in range(2400):
		var y2: float = 1.0 - 2.0 * (float(i) + 0.5) / 2400.0
		var r2: float = sqrt(maxf(0.0, 1.0 - y2 * y2))
		var th2: float = ga * float(i)
		var d2: Vector3 = Vector3(cos(th2) * r2, y2, sin(th2) * r2).normalized()
		var t2: float = Gen.climate_temperature(d2, seed_b)
		var m2: float = Gen.climate_moisture(d2, seed_b)
		var e2: float = Gen.erosion_field(d2, seed_b)
		if m2 < 0.45 and t2 > 0.5 and e2 > 0.55:
			keep.append([t2, m2, e2, int(Gen.climate_biome_id(d2, seed_b))])
	print("badlands habitat at 0.55 gate: ", keep.size(), " sample: ", keep.slice(0, 6))
	# The color-law regression: re-print the failing check's terms.
	var d_home: Vector3 = Sph.spherical_to_cartesian(0.0, 3.0, 0.0, 1.0)
	var weights: Dictionary = Gen.climate_biome_weights(d_home, seed_b)
	var c_forest: Color = Gen.vertex_color(d_home, seed_b, 10.0, 0.0)
	var c_cliff: Color = Gen.vertex_color(d_home, seed_b, 15.0, 1.0)
	var t_home: float = Gen.climate_temperature(d_home, seed_b)
	var m_home: float = Gen.climate_moisture(d_home, seed_b)
	print("d_home t=%.3f m=%.3f weights=%s" % [t_home, m_home, weights])
	print("c_forest=", c_forest, " c_cliff=", c_cliff, " cliff.r>forest.r: ", c_cliff.r > c_forest.r)
	quit(0)
