## probe_polar_caps.gd -- the v12 polar-cap law receipt.
## Verifies the two ice/snow landmasses: both poles resolve as LAND
## (height above the sea line), resolve a COLD biome, carry relief
## (not a flat pancake), and leave the spawn dome untouched.
## Exit 0 = pass.
extends SceneTree

const Gen = preload("res://scenes/worlds/terrain_gen.gd")

# BiomeId values (see BAND_NAMES in diag_biome_map.gd)
const BIOME_ALPINE := 3
const BIOME_TUNDRA := 4
const BIOME_ALPINE_MEADOW := 10

var _seed: PackedByteArray


func _init() -> void:
	_seed = Gen.world_seed_bytes()
	var ok := true
	ok = _test_poles_are_land() and ok
	ok = _test_poles_are_cold() and ok
	ok = _test_cap_has_relief() and ok
	ok = _test_spawn_untouched() and ok
	print("POLAR-CAPS %s" % ("ALL PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _sea() -> float:
	return Gen.sea_level(_seed)


func _test_poles_are_land() -> bool:
	var sea: float = _sea()
	var ok := true
	for pole in [Vector3(0, 1, 0), Vector3(0, -1, 0)]:
		var h: float = Gen.terrain_height(pole, _seed)
		var good: bool = h > sea + 3.0
		print("  pole %v height=%.2f sea=%.2f -> %s" \
			% [pole, h, sea, "LAND" if good else "FAIL"])
		ok = ok and good
	var land_n := 0
	var n := 24
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		var d := Vector3(sin(0.10) * cos(a), cos(0.10), sin(0.10) * sin(a))
		if Gen.terrain_height(d, _seed) > sea + 3.0:
			land_n += 1
	var ring_ok: bool = land_n >= int(n * 0.75)
	print("  cap interior ring: %d/%d land -> %s" % [land_n, n, "OK" if ring_ok else "FAIL"])
	return ok and ring_ok


func _test_poles_are_cold() -> bool:
	var ok := true
	var cold: Array = [BIOME_ALPINE, BIOME_TUNDRA, BIOME_ALPINE_MEADOW]
	for pole in [Vector3(0, 1, 0), Vector3(0, -1, 0)]:
		var b: int = Gen.climate_biome_id(pole, _seed)
		var good: bool = cold.has(b)
		print("  pole %v biome=%d -> %s" % [pole, b, "COLD" if good else "FAIL"])
		ok = ok and good
	return ok


func _test_cap_has_relief() -> bool:
	var lo := 1e9
	var hi := -1e9
	for i in range(64):
		var a: float = TAU * float(i) / 64.0
		var d := Vector3(sin(0.08) * cos(a), cos(0.08), sin(0.08) * sin(a))
		var h: float = Gen.terrain_height(d, _seed)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	var spread: float = hi - lo
	var good: bool = spread > 12.0
	print("  cap relief spread=%.1f m -> %s" % [spread, "OK" if good else "FAIL"])
	return good


func _test_spawn_untouched() -> bool:
	var spawn_h: float = Gen.terrain_height(Vector3(1, 0, 0), _seed)
	var ok: bool = spawn_h > 20.0 and spawn_h < 40.0
	print("  spawn height=%.2f -> %s" % [spawn_h, "OK" if ok else "FAIL"])
	return ok
