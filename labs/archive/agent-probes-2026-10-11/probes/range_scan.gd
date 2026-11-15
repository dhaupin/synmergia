extends SceneTree
## Throwaway scan for the range-law retune: peak heights, ridge chain
## geometry, the new alpine/snowline heights, the homeland plains
## gate, and the continuity bound under the sharpened crest.

func _init() -> void:
	call_deferred("_run")

func _peak_scan() -> Array:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var Sph = load("res://core/frame/math/spherical.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var best: Array = []
	for i in range(0, 120):
		for j in range(0, 240):
			var lat := -83.0 + 166.0 * (float(i) / 119.0)
			var lon := -179.0 + 358.0 * (float(j) / 239.0)
			var d: Vector3 = Sph.spherical_to_cartesian(lat, lon, 0.0, 1.0)
			var h: float = Gen.terrain_height(d, seed_b)
			best.append([h, lat, lon, d])
	best.sort_custom(func(a, b): return a[0] > b[0])
	print("TOP PEAKS: ", best.slice(0, 6).map(func(e): return ["h=%.1f" % e[0], "lat=%.1f" % e[1], "lon=%.1f" % e[2]]))
	# Alpine / snowline heights ON the tallest summit neighborhood.
	var summit: Vector3 = best[0][3]
	var t_max: float = Gen.climate_temperature(summit, seed_b)
	print("summit: h=", best[0][0], " t=", t_max, " (snowline_t=", Gen.SNOWLINE_T, " alpine_t=", Gen.ALPINE_T, ")")
	# Where does the alpine band begin? Walk temperature down?
	# Homelantd plains gate: the boot ring ids (16 angles, 2 radii).
	var gate_ok := true
	var ring_ids := {}
	for r_mult in [0.3, 0.7, 1.05]:
		for i in range(16):
			var ang: float = Gen.HOMELAND_PLAINS_ANG * r_mult * float(i) / 16.0
			var d: Vector3 = Sph.spherical_to_cartesian(0.0, rad_to_deg(ang), 0.0, 1.0)
			var id: int = Gen.climate_biome_id(d, seed_b)
			ring_ids[String(r_mult)] = int(ring_ids.get(String(r_mult), 0)) + 1
			if i == 0:
				ring_ids[String(r_mult)] = 0
			if id != Gen.BiomeId.GRASSLAND and ang < Gen.HOMELAND_PLAINS_ANG * 0.95 \
					and not (id == Gen.BiomeId.OCEAN_DEEP or id == Gen.BiomeId.OCEAN_SHELF \
					or id == Gen.BiomeId.SHORE or id == Gen.BiomeId.RIVER or id == Gen.BiomeId.LAKE \
					or id == Gen.BiomeId.SWAMP):
				gate_ok = false
	print("plains-gate ring ok=", gate_ok, " (ring census keys=", ring_ids.keys(), ")")
	var d_spawn: Vector3 = Sph.spherical_to_cartesian(0.0, 0.0, 0.0, 1.0)
	print("spawn id=", Gen.climate_biome_id(d_spawn, seed_b))
	return best

func _continuity(Gen, Sph, seed_b) -> void:
	var worst: float = 0.0
	var worst_at := ""
	# Radial walks on 8 azimuths toward and away from the range.
	for k in range(8):
		var lon0: float = 45.0 * float(k)
		var prev: float = Gen.terrain_height(Sph.spherical_to_cartesian(0.0, 0.001, lon0, 1.0), seed_b)
		for i in range(1, 1600):
			var d: Vector3 = Sph.spherical_to_cartesian(0.0, 0.001 * float(i), lon0, 1.0)
			var h: float = Gen.terrain_height(d, seed_b)
			if absf(h - prev) > worst:
				worst = absf(h - prev)
				worst_at = "az=%v step=%v" % [lon0, i]
			prev = h
	print("continuity worst step: ", worst, " at ", worst_at)

func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var Sph = load("res://core/frame/math/spherical.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var best: Array = _peak_scan()
	# Range visibility from the boot: distance to the nearest >250 m peak.
	var Sph2 = Sph
	for e in best:
			pass
	var near := []
	for i in range(0, 120, 1):
		for j in range(0, 240, 1):
			pass
	# Straight-line: the top peaks' distance from spawn.
	for e in best.slice(0, 6):
		var d: Vector3 = Sph2.spherical_to_cartesian(e[1], e[2], 0.0, 1.0)
		var dist: float = d.angle_to(Vector3(1.0, 0.0, 0.0))
		print("peak d_spawn=%.1f rad (%.1f km)" % [dist, dist * 20.0])
	_continuity(Gen, Sph, seed_b)
	quit(0)
