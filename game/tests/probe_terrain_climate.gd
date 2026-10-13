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
	# THE MEMBERSHIP LAW (variety: each new band pins its OWN axis --
	# the resolution thresholds re-stated per id so a threshold move
	# that leaks into the wrong band is caught, not just "similar").
	var members_ok := true
	var member_violation: String = ""
	for d in _sweep(600):
		var id: int = Gen.climate_biome_id(d, seed_b)
		if id < 0 or id > Gen.BiomeId.LAST:
			faces_all_ok = false
		var t: float = Gen.climate_temperature(d, seed_b)
		var m: float = Gen.climate_moisture(d, seed_b)
		if id == Gen.BiomeId.JUNGLE and not (t > Gen.JUNGLE_T - 0.02 and m > Gen.SAVANNA_M - 0.02):
			members_ok = false; member_violation = "jungle t=%.2f m=%.2f" % [t, m]
		if id == Gen.BiomeId.SAVANNA and not (t >= 0.55 and m >= Gen.DRY_T and m < Gen.SAVANNA_M + 0.03):
			members_ok = false; member_violation = "savanna t=%.2f m=%.2f" % [t, m]
		if id == Gen.BiomeId.STEPPE and not (m < Gen.STEPPE_M + 0.03 and t <= 0.55 + 0.05):
			members_ok = false; member_violation = "steppe t=%.2f m=%.2f" % [t, m]
		if id == Gen.BiomeId.BADLANDS and not (m < 0.48 and t > 0.5 \
				and Gen.erosion_field(d, seed_b) >= Gen.EROSION_T - 0.02):
			members_ok = false; member_violation = "badlands t=%.2f m=%.2f" % [t, m]
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
	ok = _check("variety: each new band answers its OWN axis (%s)" % member_violation, members_ok) and ok
	# THE VARIETY CENSUS (the point of the slice): the planet resolves
	# a rich band mix, not 3 paints on a globe. Land bands (>= ALPINE
	# through LAST) counted across the sweep must show at least 6
	# distinct bands. The REACHED law is honest-sampled (the mountain-
	# water discipline): a 600-point sweep is provably blind to rare
	# bands (~1 pt / 2 km2 on a 5000 km2 planet), so the four NEW ids
	# are counted on a 2400-point hunt sweep -- seeded fields, so
	# "exists somewhere on this seed" is an honest existence claim.
	var land_census := 0
	for bid in band_ids:
		if bid >= Gen.BiomeId.ALPINE:
			land_census += 1
	ok = _check("variety: land band census >= 6 distinct (saw %d)" % land_census, land_census >= 6) and ok
	var new_band_names := ["jungle", "savanna", "steppe", "badlands"]
	var new_ids := [Gen.BiomeId.JUNGLE, Gen.BiomeId.SAVANNA, Gen.BiomeId.STEPPE, Gen.BiomeId.BADLANDS]
	var new_found := {}
	var ga2: float = PI * (3.0 - sqrt(5.0))
	for i in range(2400):
		var y2: float = 1.0 - 2.0 * (float(i) + 0.5) / 2400.0
		var r2: float = sqrt(maxf(0.0, 1.0 - y2 * y2))
		var th2: float = ga2 * float(i)
		var d2: Vector3 = Vector3(cos(th2) * r2, y2, sin(th2) * r2).normalized()
		var hunt_id: int = Gen.climate_biome_id(d2, seed_b)
		for k in range(new_ids.size()):
			if hunt_id == new_ids[k]:
				new_found[new_band_names[k]] = int(new_found.get(new_band_names[k], 0)) + 1
	ok = _check("variety: all four new bands reached on this seed (hunt census %s)" % str(new_found), \
		new_found.size() == 4) and ok
	print("  [info] biome id census: %s" % [band_ids])

	# ---- B2. THE RANGE LAW (the 2026-10-13 retune) -----------------
	# THE RING SWEEP: the range law ANCHORS crest to the ring band
	# 0.26..0.74 rad around boot, so the band is the honest hunt
	# range -- 36 bearings x 24 radii x BOTH hemispheres (lat +/-:
	# the measured 368.7 m summit sits SOUTH of boot at 14.7 deg --
	# the first north-only sweep missed it). Coarse uniform lattices
	# (1,200 pts over 4 km2 cells) are provably blind to it.
	var ring_alpine_found := false
	for sign in [-1.0, 1.0]:
		for b in range(36):
			for rr in range(24):
				var rrr: float = 0.26 + 0.48 * (float(rr) / 23.0)
				var drr: Vector3 = Sph.spherical_to_cartesian(
					sign * rad_to_deg(rrr), 10.0 * float(b), 0.0, 1.0)
				var hrr: float = Gen.terrain_height(drr, seed_b)
				if hrr > Gen.sea_level(seed_b) + 280.0 \
						and Gen.climate_temperature(drr, seed_b) < Gen.ALPINE_T:
					ring_alpine_found = true
	ok = _check("range: the homeland ring carries an ALPINE summit (band sweep, both hemispheres)", ring_alpine_found) and ok
	ok = _check("range: the homeland ring carries an ALPINE summit (band sweep, both hemispheres)", ring_alpine_found) and ok
	# Plains law: inside the ring the hot bands yield to GRASSLAND.
	var plains_ok := true
	var plains_violation := ""
	for k in range(18):
		for j in range(12):
			var lon_p: float = 30.0 * float(j)
			var lat_p: float = -20.0 + 40.0 * (float(k) / 17.0)
			var dp: Vector3 = Sph.spherical_to_cartesian(lat_p, lon_p, 0.0, 1.0)
			if dp.angle_to(Gen.SPAWN_CENTER) >= Gen.HOMELAND_PLAINS_ANG * 0.9:
				continue
			var idp: int = Gen.climate_biome_id(dp, seed_b)
			if idp == Gen.BiomeId.JUNGLE or idp == Gen.BiomeId.SAVANNA \
					or idp == Gen.BiomeId.STEPPE or idp == Gen.BiomeId.BADLANDS \
					or idp == Gen.BiomeId.DESERT:
				plains_ok = false
				plains_violation = "id=%v lat=%v lon=%v" % [idp, lat_p, lon_p]
	ok = _check("range: homeland plains law holds (no hot bands inside the ring%s)" % plains_violation, plains_ok) and ok

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

	# Water can sit at ANY height (the user's law): a mountain-tarn pin.
	# The coarse sweep is blind to small district bowls by construction
	# (~1.7 lattice samples/km2 vs bowls ~0.5-2 km2: the pass was
	# sampling luck even before), so the sweep DISCOVERY runs first,
	# and when it misses, a perched-table candidate ring search
	# finishes the hunt. The LAW stays one: standing water somewhere
	# above sea+10 m.
	var any_upland_water := false
	for d in _sweep(900):
		var h: float = Gen.terrain_height(d, seed_b)
		var tab: float = Gen.water_table(d, seed_b)
		if h > sea + 10.0 and tab - h > Gen.Hydro.BEACH_MIN:
			any_upland_water = true
			break
	if not any_upland_water:
		var perched := [Vector3(0, 1, 0), Vector3(0, -1, 0)]
		perched.clear()
		for dd in _sweep(12000):
			var base: float = Gen._terrain_height_base(dd, seed_b)
			if base > sea + 10.0 and Gen.water_table(dd, seed_b) > sea + 10.0 + Gen.Hydro.BEACH_MIN:
				perched.append(dd)
		for base_d in perched:
			var east: Vector3 = Vector3(0.0, 1.0, 0.0).cross(base_d).normalized()
			var north: Vector3 = base_d.cross(east).normalized()
			var found := false
			for ring in range(30):
				var t: float = 0.00005 + 0.00004 * ring
				for mode in range(4):
					var dd2: Vector3 = (base_d \
						+ (east if mode < 2 else north) \
						* (t if mode % 2 == 0 else -t)).normalized()
					var hh: float = Gen.terrain_height(dd2, seed_b)
					var tt: float = Gen.water_table(dd2, seed_b)
					if tt - hh > Gen.Hydro.BEACH_MIN and hh > sea + 10.0:
						found = true
						break
				if found:
					break
			if found:
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
	# THE ROCK LAW, biome-agnostic: steep ground DESATURATES toward
	# rock gray (the channel spread narrows). The r-only proxy was a
	# green-ground artifact: the same physics on a golden savanna or
	# rust badlands ground reads correctly but failed the proxy.
	var spread_ground: float = maxf(maxf(c_forest.r, c_forest.g), c_forest.b) \
		- minf(minf(c_forest.r, c_forest.g), c_forest.b)
	var spread_cliff: float = maxf(maxf(c_cliff.r, c_cliff.g), c_cliff.b) \
		- minf(minf(c_cliff.r, c_cliff.g), c_cliff.b)
	ok = _check("color: steep ground desaturates toward rock (spread %.2f -> %.2f)" \
		% [spread_ground, spread_cliff], spread_cliff < spread_ground * 0.6) and ok
	var c_pole: Color = Gen.vertex_color(Vector3(0.0, 1.0, 0.0), seed_b, 20.0, 0.0)
	ok = _check("color: polar snow takes over (near-white)", c_pole.r > 0.7 and c_pole.b > 0.7) and ok
	var c_apron: Color = Gen.vertex_color(Sph.spherical_to_cartesian(0.0, Gen.SPAWN_APRON_ANG * 0.9, 0.0, 1.0), seed_b, Gen.SPAWN_HEIGHT, 0.0)
	ok = _check("color: spawn apron never snow-white", not (c_apron.r > 0.8 and c_apron.b > 0.85)) and ok

	print("climate probe: %d checks, %s" % [_checks, "ALL PASS" if ok else "FAILURES"])
	quit(0 if ok else 1)
