extends SceneTree
## Landmass inventory + mirror-symmetry diagnostic (turn 14, slice A).
## 2-deg grid (islets resolvable at the 20 km scale), flood fill wraps
## in lon, clamps in lat. Every component checked against a lon-mirror
## twin, then the RAW land field scored over random z-mirror pairs so
## the twin mechanism is measured, not inferred.

var _land: Array = []
var _lat_n: int = 90
var _lon_n: int = 180


func _lat_of(li: int) -> float:
	return -90.0 + (float(li) + 0.5) * 2.0


func _lon_of(lj: int) -> float:
	return -180.0 + (float(lj) + 0.5) * 2.0


func _idx(lat_i: int, lon_i: int) -> int:
	var lon_w: int = (lon_i % _lon_n + _lon_n) % _lon_n
	return lat_i * _lon_n + lon_w


func _init() -> void:
	print("land_scan: script loaded, deferring scan")
	call_deferred("_run")


func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var override: String = OS.get_environment("SYNMERGIA_SCAN_SEED")
	if not override.is_empty():
		ProjectSettings.set_setting("synmergia/world/seed", override)
		print("scan seed override: ", override)
	var Sph = load("res://core/frame/math/spherical.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var sea: float = Gen.sea_level(seed_b)
	print("SEA=%.2f scanning %d cells (2-deg grid)..." % [sea, _lat_n * _lon_n])

	_land.resize(_lat_n * _lon_n)
	_land.fill(false)
	for i in range(_lat_n):
		for j in range(_lon_n):
			var d: Vector3 = Sph.spherical_to_cartesian(_lat_of(i), _lon_of(j), 0.0, 1.0)
			_land[_idx(i, j)] = Gen.terrain_height(d, seed_b) > sea

	# Flood fill (8-neighbor.
	var seen: Array = []
	seen.resize(_lat_n * _lon_n)
	seen.fill(false)
	var comps: Array = []
	for i in range(_lat_n * _lon_n):
		if _land[i] and not seen[i]:
			var stack: Array = [i]
			seen[i] = true
			var cells: Array = []
			var lat_sum: float = 0.0
			var lon_sum_x: float = 0.0
			var lon_sum_z: float = 0.0
			var lat_min: float = 999.0
			var lat_max: float = -999.0
			while not stack.is_empty():
				var k: int = stack.pop_back()
				cells.append(k)
				var li: int = k / _lon_n
				var lj: int = k % _lon_n
				lat_sum += _lat_of(li)
				var lon_c: float = deg_to_rad(_lon_of(lj))
				lon_sum_x += cos(deg_to_rad(_lat_of(li))) * cos(lon_c)
				lon_sum_z += cos(deg_to_rad(_lat_of(li))) * sin(lon_c)
				lat_min = minf(lat_min, _lat_of(li))
				lat_max = maxf(lat_max, _lat_of(li))
				for dj in range(-1, 2):
					for di in range(-1, 2):
						if di == 0 and dj == 0:
							continue
						var ni: int = li + di
						if ni < 0 or ni >= _lat_n:
							continue
						var nk: int = _idx(ni, lj + dj)
						if _land[nk] and not seen[nk]:
							seen[nk] = true
							stack.append(nk)
			var lat_c: float = lat_sum / float(cells.size())
			var lon_c2: float = rad_to_deg(atan2(lon_sum_z, lon_sum_x))
			comps.append({
				"cells": cells.size(),
				"lat": lat_c,
				"lon": lon_c2,
				"lat_min": lat_min,
				"lat_max": lat_max,
			})
	comps.sort_custom(func(a, b): return a["cells"] > b["cells"])
	print("COMPONENTS=%d" % comps.size())
	for idx in range(comps.size()):
		var c: Dictionary = comps[idx]
		var area_km2: float = float(c["cells"]) * 0.49  # ~698 m x ~698 m per 2-deg cell at 20 km
		var twin := ""
		for jdx in range(comps.size()):
			if jdx == idx:
				continue
			var o: Dictionary = comps[jdx]
			if absf(o["lat"] - c["lat"]) < 6.0 and (o["lon"] < 0.0) != (c["lon"] < 0.0):
				var dlon: float = absf(absf(o["lon"]) - absf(c["lon"]))
				if dlon < 20.0:
					twin = "TWIN of #%d (%.1f, %.1f, %d cells)" % [jdx, o["lat"], o["lon"], o["cells"]]
					break
		print("#%d cells=%d area~%.1f km2 lat=%.1f lon=%.1f (lat %.1f..%.1f) %s" % [
			idx, c["cells"], area_km2, c["lat"], c["lon"], c["lat_min"], c["lat_max"], twin])

	# RAW mirror score over random z-mirror pairs.
	var pairs: int = 2000
	var agree: int = 0
	var diffs: Array = []
	for i in range(pairs):
		var th: float = 2.0 * PI * float(randi() % 100000) / 100000.0
		var ph: float = acos(2.0 * float(randi() % 100000) / 100000.0 - 1.0)
		var d: Vector3 = Vector3(sin(ph) * cos(th), cos(ph), sin(ph) * sin(th))
		var dm: Vector3 = Vector3(d.x, d.y, -d.z)
		var ha: float = Gen.terrain_height(d, seed_b)
		var hb: float = Gen.terrain_height(dm, seed_b)
		if (ha > sea) == (hb > sea):
			agree += 1
		diffs.append(absf(ha - hb))
	diffs.sort()
	print("Z-MIRROR land agreement: %d/%d (%.1f%%), height-delta p50=%.1f p90=%.1f m" % [
		agree, pairs, 100.0 * float(agree) / float(pairs),
		diffs[pairs / 2], diffs[int(pairs * 0.9)]])
	quit(0)
