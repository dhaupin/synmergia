extends SceneTree
## Throwaway measurement (dev_temp law): how tall are the mountains
## this seed actually grows? Coarse direction lattice -> terrain_height,
## reporting the top decile. Not a contract probe; deleted-comparand OK.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var Sph = load("res://core/frame/math/spherical.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var sea: float = Gen.sea_level(seed_b)
	var best: Array = []  # top heights with directions
	var hmin := 1e9
	var hmax := -1e9
	var n := 0
	for i in range(0, 60):
		for j in range(0, 120):
			var lat := -1.45 + 2.9 * (float(i) / 59.0)
			var lon := -3.14 + 6.28 * (float(j) / 119.0)
			var d: Vector3 = Sph.spherical_to_cartesian(0.0, lat, lon, 1.0)
			var h: float = Gen.terrain_height(d, seed_b)
			n += 1
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
			best.append([h, lat, lon])
	best.sort_custom(func(a, b): return a[0] > b[0])
	print("sea_line=", sea, " n_samples=", n, " hmin=", hmin, " hmax=", hmax)
	print("TOP 12 peaks (lat deg, lon deg, height m above base):")
	for k in range(12):
		var e: Array = best[k]
		print("  lat=%.2f deg lon=%.2f deg  h=%.1f  (over sea %.1f)" % [
			[rad_to_deg(e[1]), rad_to_deg(e[2]), e[0], e[0] - sea][0],
			[rad_to_deg(e[1]), rad_to_deg(e[2]), e[0], e[0] - sea][1],
			[rad_to_deg(e[1]), rad_to_deg(e[2]), e[0], e[0] - sea][2],
			[rad_to_deg(e[1]), rad_to_deg(e[2]), e[0], e[0] - sea][3]])
	# Percentiles for the tall-ish band
	var heights: Array = []
	for e in best:
		heights.append(e[0])
	heights.sort()
	if heights.size() > 0:
		var p99: float = heights[int(heights.size() * 0.99) - 1]
		var p98: float = heights[int(heights.size() * 0.98) - 1]
		var p90: float = heights[int(heights.size() * 0.90) - 1]
		print("p99=", p99, " p98=", p98, " p90=", p90)
	quit(0)
