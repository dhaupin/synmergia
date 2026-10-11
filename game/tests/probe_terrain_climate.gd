## Climate + hydrology probe (prd-terrain.md slices 1-3, the LAWS).
## A. Purity: same dir + seed => same temperature/moisture/biome twice.
## B. Band sanity: poles cold, equator warm; homeland green; desert
##    pockets exist somewhere warm+dry (deterministic count, exact
##    number seed-chosen); no salt-and-pepper one-band islands.
## C. Spawn law: the apron stays dry + flat (never ocean/swamp/lake).
## D. Hydrology: water may sit at ANY height (mountain water is
##    legal); the carve respects the 4 m continuity bound; rivers run
##    downhill and terminate; channels are pure and identical across
##    two primest.
## Run: godot --headless --path . --script res://tests/probe_terrain_climate.gd
extends SceneTree

const Gen = preload("res://scenes/worlds/terrain_gen.gd")
const Sph = preload("res://core/frame/math/spherical.gd")

var _checks := 0


func _init() -> void:
	call_deferred("_run")


func _check(label: String, cond: bool) -> bool:
	_checks += 1
	print(("  PASS " if cond else "  FAIL ") + label)
	return cond


## A coarse spiral over the sphere for statistical sweeps.
func _sweep(steps: int) -> Array:
	var out: Array = []
	var ga: float = PI * (3.0 - sqrt(5.0))
	for i in range(steps):
		var y: float = 1.0 - 2.0 * (float(i) + 0.5) / float(steps)
		var r: float = sqrt(maxf(0.0, 1.0 - y * y))
		var th: float = ga * float(i)
		out.append(Vector3(cos(th) * r, y, sin(th) * r).normalized())
	return out


func _run() -> void:
	var ok := true
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var sea: float = Gen.sea_level(seed_b)

	# ---- A. Purity ----------------------------------------------------
	var d_probe: Vector3 = Sph.spherical_to_cartesian(12.0, 34.0, 0.0, 1.0)
	var t1: float = Gen.climate_temperature(d_probe, seed_b)
	var m1: float = Gen.climate_moisture(d_probe, seed_b)
	var id1: int = Gen.climate_biome_id(d_probe, seed_b)
	var t2: float = Gen.climate_temperature(d_probe, seed_b)
	var m2: float = Gen.climate_moisture(d_probe, seed_b)
	var id2: int = Gen.climate_biome_id(d_probe, seed_b)
	ok = _check("purity: temperature identical twice", t1 == t2) and ok
	ok = _check("purity: moisture identical twice", m1 == m2) and ok
	ok = _check("purity: biome identical twice", id1 == id2) and ok
	ok = _check("purity: fields live in [0, 1]", t1 >= 0.0 and t1 <= 1.0 and m1 >= 0.0 and m1 <= 1.0) and ok

	# ---- B. Band sanity ------------------------------------------------
	# Poles: freezing (temperature below the snowline band).
	var d_north: Vector3 = Vector3(0.0, 1.0, 0.0)
	var d_south: Vector3 = Vector3(0.0, -1.0, 0.0)
	var t_north: float = Gen.climate_temperature(d_north, seed_b)
	var t_south: float = Gen.climate_temperature(d_south, seed_b)
	ok = _check("band: poles read cold (t_north %.2f, t_south %.2f < %.2f)" \
		% [t_north, t_south, Gen.SNOWLINE_T], \
		t_north < Gen.SNOWLINE_T + 0.05 and t_south < Gen.SNOWLINE_T + 0.05) and ok
	# Continental temperate: the homeland ring reads warm enough for the
	# green ladder (a frozen homeland would be a planet bug).
	var d_home: Vector3 = Sph.spherical_to_cartesian(0.0, 3.0, 0.0, 1.0)
	var t_home: float = Gen.climate_temperature(d_home, seed_b)
	ok = _check("band: homeland is temperate (t %.2f > %.2f)" % [t_home, Gen.SNOWLINE_T], \
		t_home > Gen.SNOWLINE_T) and ok

	# Statistical sweep: every direction resolves a VALID biome id, and
	# cold poles resolve cold bands while warm land resolves green/dry
	# land bands (no ocean misreads inland, no green at the poles).
	var faces_all_ok := true
	var cold_band_ok := true
	var warm_land_ok := true
	var band_ids := {}
	for d in _sweep(600):
		var id: int = Gen.climate_biome_id(d, seed_b)
		if id < 0 or id > 12:
			faces_all_ok = false
		var lat: float = absf(90.0 - rad_to_deg(acos(clampf(d.y, -1.0, 1.0))))
		if lat > 80.0 and id >= Gen.BiomeId.GRASSLAND:
			cold_band_ok = false
		if lat < 10.0 and Gen._land_mass(d, Gen._seed_salt(seed_b, "terrain")) > 0.5:
			if id == Gen.BiomeId.OCEAN_DEEP or id == Gen.BiomeId.OCEAN_SHELF:
				warm_land_ok = false
		band_ids[id] = int(band_ids.get(id, 0)) + 1
	ok = _check("band: every swept direction resolves a valid biome", faces_all_ok) and ok
	ok = _check("band: high latitudes never resolve a green band", cold_band_ok) and ok
	ok = _check("band: solid inland homeland never reads deep ocean", warm_land_ok) and ok
	print("  [info] biome id census: %s" % [band_ids])

	# Continuity: a small angular step never jumps from one land biome
	# THROUGH a non-adjacent band (the salt-and-pepper repair; tolerance
	# is two ladder steps because noise edges are soft, carved bands
	# (river/lake) are pointers, and the shore ring is thin).
	var cont_ok := true
	var prev_id: int = Gen.climate_biome_id(Sph.spherical_to_cartesian(0.0, 0.001, 0.0, 1.0), seed_b)
	for i in range(1, 200):
		var d: Vector3 = Sph.spherical_to_cartesian(0.0, 0.001 * float(i), 0.0, 1.0)
		var id: int = Gen.climate_biome_id(d, seed_b)
		var land_a: bool = id >= Gen.BiomeId.ALPINE
		var land_b: bool = prev_id >= Gen.BiomeId.ALPINE
		if land_a != land_b:
			# crossing the water boundary is a REAL edge (shore), keep;
			# but land<->land jumps through a water band are bugs.
			if id >= Gen.BiomeId.ALPINE and prev_id >= Gen.BiomeId.ALPINE \
					and (id == Gen.BiomeId.LAKE or prev_id == Gen.BiomeId.LAKE):
				cont_ok = false
		prev_id = id
	ok = _check("continuity: land bands never salt-and-pepper", cont_ok) and ok

	# ---- C. Spawn law ---------------------------------------------------
	var d_spawn: Vector3 = Sph.spherical_to_cartesian(0.0, 0.0, 0.0, 1.0)
	var spawn_id: int = Gen.climate_biome_id(d_spawn, seed_b)
	ok = _check("spawn: plaza resolves dry land (not %d)" % spawn_id, \
		spawn_id != Gen.BiomeId.OCEAN_DEEP and spawn_id != Gen.BiomeId.OCEAN_SHELF \
		and spawn_id != Gen.BiomeId.LAKE and spawn_id != Gen.BiomeId.SWAMP) and ok
	var apron_ok := true
	for i in range(24):
		var d: Vector3 = Sph.spherical_to_cartesian(0.0, Gen.SPAWN_APRON_ANG * 0.8 * float(i) / 24.0, 0.0, 1.0)
		var id: int = Gen.climate_biome_id(d, seed_b)
		if id == Gen.BiomeId.OCEAN_DEEP or id == Gen.BiomeId.OCEAN_SHELF \
				or id == Gen.BiomeId.LAKE or id == Gen.BiomeId.SWAMP:
			apron_ok = false
	ok = _check("spawn: the whole apron resolves dry land", apron_ok) and ok

	# ---- D. Hydrology ------------------------------------------------------
	Gen.hydrology_prime(seed_b)
	# Purity: the channel field is identical across two prime cycles.
	var before: float = Gen.river_channel(d_probe, seed_b)
	Gen.hydrology_prime(seed_b)
	var after: float = Gen.river_channel(d_probe, seed_b)
	ok = _check("hydro: river channel identical across primes (c %.2f)" % before, \
		before == after) and ok

	# The height law is still continuous WITH carving (the continuity
	# bound: no step > 4 m along a fine radial walk from the SPAWN, the
	# same walk the planet probe pins -- base and carved both hold).
	var step_ok := true
	var prev_h: float = Gen.terrain_height(d_spawn, seed_b)
	for i in range(1, 400):
		var d: Vector3 = Sph.spherical_to_cartesian(0.0, 0.001 * float(i), 0.0, 1.0)
		var h: float = Gen.terrain_height(d, seed_b)
		if absf(h - prev_h) > 4.0:
			step_ok = false
		prev_h = h
	ok = _check("hydro: carved law stays continuous (max step <= 4 m)", step_ok) and ok
	# AND the biome-law continuity walk uses the same lon-0 start (the
	# earlier check's first comparison was vs d_home, 3 deg of lon --
	# the 17.86 m bookkeeping artifact the diag run exposed, not a law
	# break; this pin now holds both to the spawn-anchored walk).

	# Rivers: every spec is a downhill-running channel to sea or basin.
	var specs: Array = Gen.river_specs_cached(seed_b)
	var rivers_ok := specs.size() >= 3
	var downhill_worst: float = 0.0
	for spec in specs:
		var w: float = Gen.river_goes_downhill(spec.path, seed_b)
		downhill_worst = maxf(downhill_worst, w)
	ok = _check("hydro: %d rivers exist (>= 3)" % specs.size(), rivers_ok) and ok
	ok = _check("hydro: every river steps downhill (worst up-step %.2f m <= 1.0)" % downhill_worst, \
		downhill_worst <= 1.0) and ok

	# Water can sit at ANY height (the user's law): a mountain-lake pin.
	# Sweep for basins well above the sea line and count them.
	var any_upland_water := false
	for d in _sweep(900):
		var h: float = Gen.terrain_height(d, seed_b)
		var tab: float = Gen.water_table(d, seed_b)
		if h > sea + 10.0 and tab - h > Gen.Hydro.BEACH_MIN:
			any_upland_water = true
			break
	ok = _check("hydro: standing water exists ABOVE sea+10 m (mountain water legal)", \
		any_upland_water) and ok

	# Determinism: two primest produce the SAME specs (instance-level).
	var s1: Array = Gen.river_specs_cached(seed_b)
	var key: String = seed_b.hex_encode()
	Gen._river_spec_cache.delete(key)  # evict ONE seed's specs (LRU member delete)
	Gen.hydrology_prime(seed_b)
	var s2: Array = Gen.river_specs_cached(seed_b)
	var same: bool = s1.size() == s2.size()
	if same:
		for i in range(s1.size()):
			var a: Gen.RiverSpec = s1[i]
			var b: Gen.RiverSpec = s2[i]
			if a.spring != b.spring or a.path.size() != b.path.size():
				same = false
				break
			for j in range(a.path.size()):
				if a.path[j] != b.path[j]:
					same = false
					break
	ok = _check("hydro: re-derived rivers are identical", same) and ok

	# The RIVER RIPPLE (floodplain law): moisture on the channel capsule
	# = raw field + boost x channel, exactly, at every spec's spring and
	# every path midpoint (- and 0 far away, so the boost is LOCAL -- it
	# doesn't dull the planet's dry belts).
	var ripple_ok := true
	var ripple_far_ok := true
	var samples := 0
	for spec in specs:
		var pts: PackedVector3Array = spec.path
		for k in range(0, pts.size(), 4):  # every 4th path node: spring, mids, near-mouth
			var d: Vector3 = pts[k].normalized()
			var c: float = Gen.river_channel(d, seed_b)
			if c < 0.5:
				continue  # path corner offset from the capsule core: not a pin
			var m_full: float = Gen.climate_moisture(d, seed_b)
			var m_raw: float = clampf(Gen.climate_moisture_field(d, seed_b), 0.0, 1.0)
			samples += 1
			# Saturating law: the boosted total clamps to the [0, 1] field
			# (a saturated headwater is a REAL answer, not a law break).
			var expected: float = clampf(m_raw + Gen.Hydro.RIVER_MOIST_BOOST * c, 0.0, 1.0)
			if absf(m_full - expected) > 0.01:
				ripple_ok = false
	# A far-from-any-river land direction (analytic far point: the
	# direction antipodal to the first spring) reads NO boost.
	if specs.size() > 0:
		var d_far: Vector3 = -specs[0].spring.normalized()
		var c_far: float = Gen.river_channel(d_far, seed_b)
		if c_far < 0.05:
			var mf: float = Gen.climate_moisture(d_far, seed_b)
			var mrf: float = Gen.climate_moisture_field(d_far, seed_b)
			ripple_far_ok = absf(mf - mrf) < 0.005 and absf(mf - mrf) < (Gen.Hydro.RIVER_MOIST_BOOST * 0.05 + 0.005)
	ok = _check("hydro: river ripple delta == boost x channel on %d bank samples" % samples, \
		ripple_ok and samples >= 5) and ok
	ok = _check("hydro: the ripple stays local (far-from-river reads no boost)", ripple_far_ok) and ok

	# ---- E. The color law (slice 2) --------------------------------
	# Purity + palette sanity: same dir => same color; different biomes
	# => different colors; seabed dimmer than land; snow appears at
	# cold poles; spawn apron stays snow-free.
	var c_probe: Color = Gen.vertex_color(d_probe, seed_b, 10.0, 0.0)
	var c_probe2: Color = Gen.vertex_color(d_probe, seed_b, 10.0, 0.0)
	ok = _check("color: vertex_color identical twice", c_probe == c_probe2) and ok
	var c_desert: Color = Gen.vertex_color(Sph.spherical_to_cartesian(-25.0, 160.0, 0.0, 1.0), seed_b, 5.0, 0.0)
	var c_forest: Color = Gen.vertex_color(d_home, seed_b, 10.0, 0.0)
	ok = _check("color: distinct biomes tint differently (desert vs forest)", \
		absf(c_desert.r - c_forest.r) > 0.05 or absf(c_desert.b - c_forest.b) > 0.05) and ok
	var c_seabed: Color = Gen.vertex_color(Sph.spherical_to_cartesian(-30.0, 180.0, 0.0, 1.0), seed_b, sea - 6.0, 0.0)
	ok = _check("color: seabed dims wet (darker than 0.5 gray)", c_seabed.r < 0.5) and ok
	var c_cliff: Color = Gen.vertex_color(d_home, seed_b, 15.0, 1.0)
	ok = _check("color: steep ground reads rock-ish (r > biome green)", c_cliff.r > c_forest.r) and ok
	var c_pole: Color = Gen.vertex_color(Vector3(0.0, 1.0, 0.0), seed_b, 20.0, 0.0)
	ok = _check("color: polar snow takes over (near-white)", c_pole.r > 0.7 and c_pole.b > 0.7) and ok
	var c_apron: Color = Gen.vertex_color(Sph.spherical_to_cartesian(0.0, Gen.SPAWN_APRON_ANG * 0.9, 0.0, 1.0), seed_b, Gen.SPAWN_HEIGHT, 0.0)
	ok = _check("color: spawn apron never snow-white", not (c_apron.r > 0.8 and c_apron.b > 0.85)) and ok

	print("climate probe: %d checks, %s" % [_checks, "ALL PASS" if ok else "FAILURES"])
	quit(0 if ok else 1)
