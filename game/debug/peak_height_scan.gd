extends SceneTree
## Throwaway measurement (dev_temp law): how tall are the mountains
## this seed actually grows? Coarse direction lattice -> terrain_height,
## reporting the top decile. Not a contract probe; deleted-comparand OK.
## NOTE: spherical_to_cartesian takes DEGREES for lat/lon; a lattice
## built in radians fed direct made this scan sample a pole patch (the
## 10.7 m "max" round was pole junk, not the real range).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var sea: float = Gen.sea_level(seed_b)
	var best: Array = []  # top heights with directions
	var hmin := 1e9
	var hmax := -1e9
	var n := 0
	# Degrees, full sphere: lat -85..85, lon -180..180.
	for i in range(0, 68):
		for j in range(0, 180):
			var lat_deg := -85.0 + 170.0 * (float(i) / 67.0)
			var lon_deg := -180.0 + 360.0 * (float(j) / 179.0)
			var Sph = load("res://core/frame/math/spherical.gd")
			var dir: Vector3 = Sph.spherical_to_cartesian(lat_deg, lon_deg, 0.0, 1.0)
			var h: float = Gen.terrain_height(dir, seed_b)
			n += 1
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
			best.append([h, lat_deg, lon_deg])
	best.sort_custom(func(a, b): return a[0] > b[0])
	print("sea_line=", sea, " n_samples=", n, " hmin=", hmin, " hmax=", hmax)
	print("TOP 12 peaks (lat deg, lon deg, height m):")
	for k in range(12):
		var e: Array = best[k]
		print("  lat=%.1f lon=%.1f  h=%.1f  (over sea %.1f)" % [e[1], e[2], e[0], e[0] - sea])
	var heights: Array = []
	for e in best:
		heights.append(e[0])
	heights.sort()
	if heights.size() > 0:
		print("p99=", heights[int(heights.size() * 0.99) - 1], " p90=", heights[int(heights.size() * 0.90) - 1])
	quit(0)
