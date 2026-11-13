## diag_law_limbs - cold cost of each ground-law limb (fresh sectors).
## Run: godot --headless --path game --script res://tests/diag_law_limbs.gd
extends SceneTree

const TerrainGen := preload("res://scenes/worlds/terrain_gen.gd")


func _init() -> void:
	call_deferred("_run")


func _fresh(i: int) -> Vector3:
	var ga: float = PI * (3.0 - sqrt(5.0))
	var y: float = 1.0 - 2.0 * (float(i) + 0.5) / 20000.0
	var r: float = sqrt(maxf(0.0, 1.0 - y * y))
	var th: float = ga * float(i)
	return (Vector3(cos(th) * r, y, sin(th) * r) + Vector3(0.137, 0.211, 0.093) * float(i)).normalized()


func _seed() -> PackedByteArray:
	var s := PackedByteArray()
	for i in range(8):
		s.append((i * 37 + 11) & 0xFF)
	return s


var _leg: int = 0

func _time(label: String, n: int, seed_b: PackedByteArray, fn: Callable) -> void:
	# A DISTINCT dir set per leg (rotated) so no cross-leg warming.
	_leg += 1
	var rot := Vector3(0.137, 0.211, 0.093) * float(_leg) + Vector3(0.31, 0.17, 0.29) * float(_leg * _leg)
	var t0: int = Time.get_ticks_usec()
	for i in range(n):
		var ga: float = PI * (3.0 - sqrt(5.0))
		var y: float = 1.0 - 2.0 * (float(i) + 0.5) / 20000.0
		var r: float = sqrt(maxf(0.0, 1.0 - y * y))
		var th: float = ga * float(i)
		fn.call((Vector3(cos(th) * r, y, sin(th) * r) + rot).normalized(), seed_b)
	var us: float = float(Time.get_ticks_usec() - t0) / float(n)
	print("  %-26s %8.1f us" % [label, us])


func _run() -> void:
	var seed_b: PackedByteArray = _seed()
	var n: int = 400
	print("DIAG_LAW_LIMBS (cold, fresh sector per call):")
	_time("sea_level", n, seed_b, func(d, s): TerrainGen.sea_level(s))
	_time("_terrain_height_base", n, seed_b, func(d, s): TerrainGen._terrain_height_base(d, s))
	_time("_natural_raw", n, seed_b, func(d, s): TerrainGen._natural_raw(d, s))
	_time("terrain_height (carved)", n, seed_b, func(d, s): TerrainGen.terrain_height(d, s))
	_time("_hydro_gates", n, seed_b, func(d, s): TerrainGen._hydro_gates(d, s))
	_time("hydro_lake_carve", n, seed_b, func(d, s): TerrainGen.hydro_lake_carve(d, s, 20.0))
	_time("road_height_override", n, seed_b, func(d, s): TerrainGen.road_height_override(d, s, 20.0))
	_time("_island_shape", n, seed_b, func(d, s): TerrainGen._island_shape(d))
	_time("_sculpt_and_spawn", n, seed_b, func(d, s): TerrainGen._sculpt_and_spawn(d, 20.0, TerrainGen.sea_level(s), 0.0))
	_time("water_table_raw", n, seed_b, func(d, s): TerrainGen.water_table_raw(d, s))
	_time("hydro_water_surface", n, seed_b, func(d, s): TerrainGen.hydro_water_surface(d, s))
	_time("climate_temperature", n, seed_b, func(d, s): TerrainGen.climate_temperature(d, s))
	_time("climate_moisture", n, seed_b, func(d, s): TerrainGen.climate_moisture(d, s))
	_time("_crag_noise", n, seed_b, func(d, s): TerrainGen._crag_noise(d, s))
	_time("river_channel", n, seed_b, func(d, s): TerrainGen.river_channel(d, s))
	_time("road_state_at", n, seed_b, func(d, s): TerrainGen.road_state_at(d, s))
	_time("waterfall_seam_at", n, seed_b, func(d, s): TerrainGen.waterfall_seam_at(d, s))
	_time("ground_sample (fused)", n, seed_b, func(d, s): TerrainGen.ground_sample(d, s))
	_time("splat_skin", n, seed_b, func(d, s): TerrainGen.splat_skin(d, s, 10.0, 0.2))
	quit(0)
