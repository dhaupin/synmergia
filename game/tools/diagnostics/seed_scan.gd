extends SceneTree
## Full-law seed scan (turn 14, slice A): the earthlike z-asymmetry
## hash fix + candidates, scored against EXACTLY the pins the battery
## enforces: W1 land budget (20000-pt rng sweep, seed 20261013),
## W3 inland peaks, the homeland ring alpine summit sweep, the plains
## ring law, spawn/apron dry, the 4-new-band hunt, and the river
## census + downhill bound. Winner gets burned into
## DEFAULT_WORLD_SEED and faces the full probe battery after.

const CANDIDATES := [
	"synmergia-tidefall-2",
	"saltcrown-isle-4",
]

func _init() -> void:
	print("seed_scan: loaded")
	call_deferred("_run")

func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var Sph = load("res://core/frame/math/spherical.gd")
	for cand in CANDIDATES:
		ProjectSettings.set_setting("synmergia/world/seed", cand)
		var seed_b: PackedByteArray = Gen.world_seed_bytes()
		var sea: float = Gen.sea_level(seed_b)
		# --- W1 + W3 (exact probe recipe: 20000 rng cube sample) ------
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261013
		var land: int = 0
		var peaks50: int = 0
		var mirages: int = 0
		var N: int = 20000
		for i in range(N):
			var d: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var h: float = Gen.terrain_height(d, seed_b)
			if h > Gen.TERRAIN_MAX + 1.0:
				mirages += 1
			if h > sea + 0.05:
				land += 1
				if h - sea > 50.0:
					peaks50 += 1
		var area_km2: float = float(land) / float(N) * 4.0 * PI * 400.0
		var w1_ok: bool = area_km2 > 100.0 and area_km2 < 380.0
		var w3_ok: bool = peaks50 >= 8 and mirages == 0
		# --- Ring alpine summit sweep (exact probe recipe) ------------
		var ring_alpine := false
		for sign_v in [-1.0, 1.0]:
			for b in range(36):
				for rr in range(24):
					var rrr: float = 0.26 + 0.48 * (float(rr) / 23.0)
					var drr: Vector3 = Sph.spherical_to_cartesian(sign_v * rad_to_deg(rrr), 10.0 * float(b), 0.0, 1.0)
					var hrr: float = Gen.terrain_height(drr, seed_b)
					if hrr > sea + 280.0 and Gen.climate_temperature(drr, seed_b) < Gen.ALPINE_T:
						ring_alpine = true
		# --- Plains ring law -------------------------------------------
		var plains_ok := true
		for k in range(18):
			for j in range(12):
				var dp: Vector3 = Sph.spherical_to_cartesian(-20.0 + 40.0 * (float(k) / 17.0), 30.0 * float(j), 0.0, 1.0)
				if dp.angle_to(Gen.SPAWN_CENTER) >= Gen.HOMELAND_PLAINS_ANG * 0.9:
					continue
				var idp: int = Gen.climate_biome_id(dp, seed_b)
				if idp == Gen.BiomeId.JUNGLE or idp == Gen.BiomeId.SAVANNA \
						or idp == Gen.BiomeId.STEPPE or idp == Gen.BiomeId.BADLANDS \
						or idp == Gen.BiomeId.DESERT:
					plains_ok = false
		# --- Spawn + apron dry ------------------------------------------
		var spawn_id: int = Gen.climate_biome_id(Sph.spherical_to_cartesian(0.0, 0.0, 0.0, 1.0), seed_b)
		var spawn_dry: bool = spawn_id != Gen.BiomeId.OCEAN_DEEP and spawn_id != Gen.BiomeId.OCEAN_SHELF \
			and spawn_id != Gen.BiomeId.LAKE and spawn_id != Gen.BiomeId.SWAMP
		var apron_ok := true
		for i in range(24):
			var da: Vector3 = Sph.spherical_to_cartesian(0.0, Gen.SPAWN_APRON_ANG * 0.8 * float(i) / 24.0, 0.0, 1.0)
			var ida: int = Gen.climate_biome_id(da, seed_b)
			if ida == Gen.BiomeId.OCEAN_DEEP or ida == Gen.BiomeId.OCEAN_SHELF \
					or ida == Gen.BiomeId.LAKE or ida == Gen.BiomeId.SWAMP:
				apron_ok = false
		# --- The four new bands (2400-pt golden-angle hunt) ------------
		var ga: float = PI * (3.0 - sqrt(5.0))
		var counts := {Gen.BiomeId.JUNGLE: 0, Gen.BiomeId.SAVANNA: 0, Gen.BiomeId.STEPPE: 0, Gen.BiomeId.BADLANDS: 0}
		for i in range(2400):
			var y: float = 1.0 - 2.0 * (float(i) + 0.5) / 2400.0
			var r: float = sqrt(maxf(0.0, 1.0 - y * y))
			var th: float = ga * float(i)
			var d: Vector3 = Vector3(cos(th) * r, y, sin(th) * r).normalized()
			var hid: int = Gen.climate_biome_id(d, seed_b)
			if counts.has(hid):
				counts[hid] = counts[hid] + 1
		var reached: int = 0
		for kk in counts:
			if counts[kk] > 0:
				reached += 1
		# --- W2: the homeland plateau cap stays solid (exact probe) ---
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 20261013
		var cap_ok := true
		var cap_dirs: int = 0
		var cap_land: int = 0
		var plateau_ang: float = Gen.HOMELAND_ANGULAR_REACH * 0.6
		var isl_n: Vector3 = Gen.ISLAND_CENTER.normalized()
		for i in range(N):
			var d2: Vector3 = Vector3(rng2.randf_range(-1, 1), rng2.randf_range(-1, 1), rng2.randf_range(-1, 1)).normalized()
			if d2.angle_to(Gen.SPAWN_CENTER) < plateau_ang:
				cap_dirs += 1
				var h2: float = Gen.terrain_height(d2, seed_b)
				if h2 > sea:
					cap_land += 1
				elif d2.angle_to(isl_n) > Gen.ISLAND_ANGULAR_REACH and d2.angle_to(isl_n) < Gen.ISLAND_MOAT_OUTER:
					cap_land += 1
		var w2_ok: bool = cap_land == cap_dirs
		# --- Rivers -------------------------------------------------------
		var specs: Array = Gen.river_specs_cached(seed_b)
		var downhill: float = 0.0
		for spec in specs:
			downhill = maxf(downhill, Gen.river_goes_downhill(spec.path, seed_b))
		var rivers_ok: bool = specs.size() >= 3 and downhill <= 1.0
		var all_ok: bool = w1_ok and w3_ok and w2_ok and ring_alpine and plains_ok \
			and spawn_dry and apron_ok and reached == 4 and rivers_ok
		print("SEED %-22s W1=%.0f%s W3=%d/%d ring=%s plains=%s spawn=%s bands=%d/4 %s riv=%d dn=%.2f W2=%s -> %s" % [
			cand, area_km2, ("" if w1_ok else "!!"), peaks50, 8, ("y" if ring_alpine else "n"),
			("y" if plains_ok else "n"), ("y" if spawn_dry and apron_ok else "n"),
			reached, str(counts.values()), specs.size(), downhill,
			("ok" if w2_ok else "FAIL"), ("PASS" if all_ok else "fail")])
	quit(0)
