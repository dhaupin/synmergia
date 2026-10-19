## bench_hotcorner_v8 - the corner-derivation MONEY SHOT (the perf leg).
## For one level-7 face's corner set, times each per-direction law the
## mesh pass calls COLD, so the dominant cost is measured, not guessed:
##   A) terrain_height           (the base field, sector-cached)
##   B) vertex_color             (the biome tint stack)
##   C) road_state_at            (the corridor probe -- suspect: walks
##                                the whole 320-node path per fresh dir)
##   D) river_channel            (the hydro channel probe)
##   E) hydro_water_surface      (the gated water table)
## Prints calls/s + us/dir per law, plus the implied per-patch cost
## (49k corners incl. the 3 slope-neighbor reads each).
extends SceneTree

const Gen = preload("res://scenes/worlds/terrain_gen.gd")

func _bench(label: String, f: Callable, dirs: Array) -> float:
	var t0 := Time.get_ticks_usec()
	var sink := 0.0
	for d in dirs:
		var r = f.call(d, _seed)
		sink += float(str(r).hash())
	var us := float(Time.get_ticks_usec() - t0)
	var per_dir := us / float(dirs.size())
	print("%-22s %8.0f us/dir  (%.0f dirs/s)  sink=%.6f" % [label, per_dir, 1e6 / per_dir, sink])
	return per_dir

var _seed: PackedByteArray

func _corners_for_face(face: int, level: int) -> Array:
	# Rebuild the subdivision corner set (the same law _build_mesh uses).
	var fv = load("res://core/frame/math/icosahedral_faces.gd").face_vertices(face)
	var tile_r := 20000.0 + 2.0
	var center := Faces2.face_center(face) * tile_r
	var x := load("res://core/frame/math/icosahedral.gd")
	var a: Vector3 = x.VERTICES[fv[0]].normalized() * tile_r - center
	var b: Vector3 = x.VERTICES[fv[2]].normalized() * tile_r - center
	var c: Vector3 = x.VERTICES[fv[1]].normalized() * tile_r - center
	var out: Array = []
	_sub(a, b, c, level, out)
	var dirs: Array = []
	for tri in out:
		for i in range(3):
			dirs.append(((tri[i] + center).normalized()))
	return dirs

func _sub(a: Vector3, b: Vector3, c: Vector3, d: int, out: Array) -> void:
	if d <= 0:
		out.append([a, b, c])
		return
	var mab: Vector3 = (a + b).normalized() * ((a.length() + b.length()) * 0.5)
	var mbc: Vector3 = (b + c).normalized() * ((b.length() + c.length()) * 0.5)
	var mca: Vector3 = (c + a).normalized() * ((c.length() + a.length()) * 0.5)
	_sub(a, mab, mca, d - 1, out)
	_sub(mab, b, mbc, d - 1, out)
	_sub(mca, mbc, c, d - 1, out)
	_sub(mab, mbc, mca, d - 1, out)

class Faces2:
	static func face_center(face: int) -> Vector3:
		return load("res://core/frame/math/icosahedral_faces.gd").face_center(face)

func _init() -> void:
	_seed = Gen.world_seed_bytes()
	# One face's corner dirs at level 7 (the real population: 16384 tris,
	# 49k corners; dedup to the UNIQUE quantized set the height cache sees).
	var all: Array = _corners_for_face(1, 7)
	var uniq := {}
	for dvec in all:
		var key: Vector3 = (dvec * 4096.0).floor()
		if not uniq.has(key):
			uniq[key] = dvec
	var dirs: Array = uniq.values()
	print("UNIQUE_CORNER_DIRS(level7,face1)=", dirs.size(), " raw=", all.size())
	print("== A) terrain_height ==")
	_bench("terrain_height", Callable(Gen, "terrain_height"), dirs)
	print("== B) vertex_color ==")
	_bench("vertex_color", Callable(Gen, "vertex_color"), dirs)
	print("== C) road probes ==")
	_bench("road_state_at", Callable(Gen, "road_state_at"), dirs)
	_bench("road_clearance_at", Callable(Gen, "road_clearance_at"), dirs)
	print("== D) hydrology ==")
	_bench("river_channel", Callable(Gen, "river_channel"), dirs)
	_bench("hydro_water_surface", Callable(Gen, "hydro_water_surface"), dirs)
	print("== E) climate stack ==")
	_bench("climate_temperature", Callable(Gen, "climate_temperature"), dirs)
	_bench("climate_moisture", Callable(Gen, "climate_moisture"), dirs)
	_bench("climate_biome_id", Callable(Gen, "climate_biome_id"), dirs)
	quit(0)
