## TerrainGen - SeedChain-driven deterministic per-face chunk content
## (prd-spherical-mvp.md S7 + the terrain arc). The world PRD's seed
## law: same seed + ruleset version = same world. Rock/boulder specs
## and terrain heights for a face derive ONLY from (world seed, face
## id, RULESET_VERSION) via SeedChain.derive_seed -- never from time,
## order, or locality.
##
## v2 TERRAIN ARC: the planet gains a seeded heightfield -- one large
## continent (the starting continent, spawn on its shore), rolling
## hills, inland mountains, a mountain lake, an offshore island
## plateau (the ferry destination), and an ocean floor below the sea
## line. Everything is a PURE FUNCTION of direction + seed:
##   terrain_height(dir, seed)  -- the ground law
##   walk_height(dir, seed, face, R, terrain_on) -- what the walker
##     rides: terrain (when on) + small-rock walk-over caps. Boulders
##     are NOT in the provider: they are big enough to block (their
##     PropCollider carries that) and the climb law's mantle raycast
##     reads their top from the collider itself.
##
## Also owns the walk-over height provider: small rock tops raise the
## player's radial snap height so colliders decorate, not block.
## v3 CLIMATE ARC (prd-terrain.md): pure climate fields on the same
## seed discipline -- temperature (latitude band + altitude lapse +
## noise), moisture (octave noise shaped by land mass), and the biome
## resolution law (discrete id + smooth blend weights for rendering).
## Hydrology (slice 3) now joins as a FIRST-CLASS height-independent
## law: standing water can sit at ANY elevation (a mountain lake is
## legal), carried by a water-table field -- not by pushing terrain
## down to one global sea shell. Rivers are carved polylines in the
## law itself (data, not nodes). RefCounted static helper (preloaded
## by the terrain streamer).
extends RefCounted

const SeedChain = preload("res://core/frame/kv/seed_chain.gd")
const Faces = preload("res://core/frame/math/icosahedral_faces.gd")
const LRU_CACHE = preload("res://core/frame/kv/lru_cache.gd")
const SECTOR_CACHE = preload("res://core/frame/kv/sector_cache.gd")

## THE CANONICAL CACHE SYSTEM (frame/kv/sector_cache.gd): all five
## statics below ride the one seeded quantized-sector primitive --
## a String key of (2048-quantized dir, seed hex) backed by an O(1)
## LRUCache, so bounds EVICT the least-recently-used sector instead
## of clearing the class wholesale (multi-world hot swaps keep the
## hot set; nothing but a reinstall flushes anything). Defaults keep
## the legacy 524288-entry law.
static var _height_cache = SECTOR_CACHE.new()
static var _water_surface_cache = SECTOR_CACHE.new()
static var _blend_cache = SECTOR_CACHE.new()
static var _skin_cache = SECTOR_CACHE.new()  # the splat class weights (skin law, same law)
static var _channel_cache = SECTOR_CACHE.new()
static var _crag_cache = SECTOR_CACHE.new()
static var _river_spec_cache = LRU_CACHE.new(8)
## LANE-H2 CARVED-HEIGHT MEMO: terrain_height_carved in its default
## mode is a pure function of (dir sector, seed) -- base field, lake
## carve, river channel, road override all read only pure per-(dir,
## seed) laws. Measured ~207k calls per level-6 build, ~24 us each;
## only the inner _terrain_height_base was memoized, so the carve /
## channel / road legs re-ran every call. This caches the FULL carved
## height. The non-default modes ("_raw", "_noroad") stay uncached
## (they are the pathing law's own read, and the road seam hashes
## them).
static var _carved_cache = SECTOR_CACHE.new()

## GROUND-SAMPLE MEMO (the fused-sample refactor, labs/prd-ground-sample.md).
## Stage 1: one GroundSample per quantized direction, built by calling the
## existing sub-laws (so it is trivially bit-identical) and memoized together.
## Stage 2 rewires the public entry points to read THIS struct instead of
## re-deriving; Stage 3 collapses the per-field caches into this one.
static var _ground_cache = SECTOR_CACHE.new()

## Bump to invalidate all derived content deliberately. v2: the
## heightfield + boulders join the world (all rocks/trees re-derive).
## v3: climate + hydrology join (biome ids/weights re-derive; the
## height law stays BIT-IDENTICAL -- see the v3 contract below).
## v4: THE VISIBILITY DENSITY RAISE (the play-day report measured
## tests/probe_prop_density.gd: the nearest prop to the boot was
## ~6.4 km over a ~251 km2 face): scatter counts now carry the face's
## real geometry (rock specs 6..10, boulders 2..3, tree site ladder
## in the streamer's _spawn_trees). Prop content re-derives; the
## height law is BIT-IDENTICAL through the v3->v4 move.
const RULESET_VERSION: String = "terrain_v7"

## Project default world seed (dev). Shards override per-shard later.
const DEFAULT_WORLD_SEED: String = "saltcrown-isle-4"
const WORLD_SEED_SETTING: String = "synmergia/world/seed"

## Base rock size (meters) before per-rock scale. ROCK_EMBED is how
## deep the rock sphere's center sits above the base surface; the
## visible top is therefore ROCK_EMBED + ROCK_RADIUS*scale above it,
## which the walk-over cap height matches exactly.
const ROCK_RADIUS: float = 1.2
const ROCK_EMBED: float = 0.3

## -- BIODIVERSITY LEG (v7) --------------------------------------------
## TREE SPECIES LAW (v7). Species codes -- NEVER renumber (sites may
## carry these into derived content). The biome at the tree SITE picks
## one via species_at(); the streamer's twin tree builders (sync node
## path + batched MultiMesh path) read the SAME code, so a promoted
## face and its far-face twin show the same tree.
class TreeSpecies:
	const BROADLEAF: int = 0   # the v4 default (trunk cylinder + canopy sphere)
	const CONIFER: int = 1     # taiga/alpine-meadow: stacked cone crown
	const ACACIA: int = 2      # savanna: flat-topped umbrella canopy
	const PALM: int = 3        # shore (warm): bare trunk + frond rosette
	const MANGROVE: int = 4    # swamp: dark mass on stilted root
	const DEAD_SNAG: int = 5   # badlands/tundra/steppe: bare gray snag
	const BAOBAB: int = 6      # savanna rare: fat bottle trunk

## The species pick (PURE, cached on the sector primitive -- one read
## per tree site). Biome -> species ladder with a seeded twist so two
## trees in the same biome still vary (savanna's acacia/baobab mix).
static var _species_cache = SECTOR_CACHE.new()
static func tree_species_at(dir: Vector3, world_seed: PackedByteArray) -> int:
	var cached = _species_cache.get_value(dir, world_seed)
	if cached != null:
		return int(cached)
	var bid: int = climate_biome_id(dir, world_seed)
	var t: float = climate_temperature(dir, world_seed)
	var salt: int = _seed_salt(world_seed, "tree_species")
	var acc: int = salt
	var q: Vector3i = Vector3i(int(dir.x * 4096.0), int(dir.y * 4096.0), int(dir.z * 4096.0))
	acc = (acc * 131 + absi(q.x) + absi(q.y) * 7 + absi(q.z) * 13) % 9007199254740991
	var roll: float = float(acc % 1000) / 1000.0
	var sp: int = TreeSpecies.BROADLEAF
	match bid:
		BiomeId.TAIGA:
			sp = TreeSpecies.CONIFER
		BiomeId.ALPINE_MEADOW:
			sp = TreeSpecies.CONIFER if roll < 0.7 else TreeSpecies.BROADLEAF
		BiomeId.SAVANNA:
			sp = TreeSpecies.ACACIA if roll < 0.8 else TreeSpecies.BAOBAB
		BiomeId.SHORE:
			sp = TreeSpecies.PALM if t > 0.55 else TreeSpecies.BROADLEAF
		BiomeId.SWAMP:
			sp = TreeSpecies.MANGROVE if roll < 0.75 else TreeSpecies.BROADLEAF
		BiomeId.BADLANDS, BiomeId.TUNDRA, BiomeId.STEPPE:
			sp = TreeSpecies.DEAD_SNAG if roll < 0.5 else TreeSpecies.BROADLEAF
		_:
			sp = TreeSpecies.BROADLEAF
	_species_cache.set_value(dir, world_seed, sp)
	return sp

## -- Terrain arc constants (planet-scale law; all heights in meters) --
## Hard ceiling on the ground law: nothing grows above this.
## THE RANGE RETUNE + SNOW-CAP BUMP: MOUNTAIN_AMP feeds BOTH mountain
## streams (the seed-anisotropic far chain below + the HOME-ANCHORED
## ring range, sampled in the SPAWN frame). The ~520 m climb through
## the ring ramp keeps ~3.5 m/law-step (under the 4 m continuity
## bound); TERRAIN_MAX 560 roofs the bump (snow-line summits legal at
## ~380+ m on the equator).
const MOUNTAIN_AMP: float = 1000.0
const RING_R0: float = 0.26
const RING_R1: float = 0.46
const RING_R2: float = 0.74
const RING_T_LO: float = 0.35
const RING_T_HI: float = 0.55
## THE HOMELAND PLAINS LAW: inside this angle of the boot the hot
## dry/tropical bands yield to GRASSLAND (temperate coastal starter
## plains by the town; water/shore/swamp laws outrank as always).
## v4 VISIBILITY EXTENSION (the density raise, the play-day report
## measured by tests/bench_site_deriv.gd + tests/probe_prop_density.gd):
## at 0.12 rad (2.4 km) the "starter plains" belt was SMALLER than the
## boot's own face corner -- the ground 3-10 km out resolved by raw
## latitude heat (desert/steppe/savanna bands), so the site-level
## species law drew no tree far or near and the plains read bare.
## 0.30 rad = ~6 km keeps the belt a real starter plains (the village,
## the boot, and the visible meadow country), while the dome edge
## (0.70 rad) still carries the authored variety bands.
const HOMELAND_PLAINS_ANG: float = 0.30
## Hard ceiling on the ground law: nothing grows above this.
const TERRAIN_MAX: float = 560.0
## The sea line above the base surface. Per-seed in a narrow band so
## shorelines shift between worlds but the shelf law holds.
const SEA_LEVEL_MIN: float = 4.0
const SEA_LEVEL_SPAN: float = 3.0
## Ocean floor depth range below the sea line (the swimmable shelf).
const OCEAN_DEPTH_MIN: float = 9.0
const OCEAN_DEPTH_SPAN: float = 6.0
## THE POLAR CAPS (v12, the "real planet" law): two authored ice/snow
## landmasses at the top and bottom of the sphere, like a real planet.
## The natural land band (`_land_mass`'s latitude gate) zeroes land above
## ~45 deg, so the poles resolve as open sea; this cap overrides that with
## a plateau-then-coast dome around each pole, paying the SAME max-law the
## homeland dome and the Sun Pans atoll pay (noise still carves the coast,
## the skirt floor keeps the ring dry). The temperature law already reads
## the poles as the coldest place on the sphere (lat 90 -> t = 0), so the
## cap resolves the freeze ladder (TUNDRA / ALPINE) and the vertex snowline
## tints it white -- ice/snow land with no new biome id. Symmetric across
## both poles (absf(d.y)), so the north/south compass + map law is
## untouched (the poles were "TBA" only because an early polar treatment
## broke the map's lat sign -- fixed since by the shared lat_lon_to_uv law).
## POLAR_CAP_ANG 0.34 rad ~ 6.8 km cap radius at the 20 km planet scale.
const POLAR_CAP_ANG: float = 0.34
## THE POLAR RELIEF: a masked mountain stream on the caps so the ice
## reads as broken country (ridges + peaks), not a flat white pancake.
## Lower than MOUNTAIN_AMP (1000) -- these are ice sheets, not the home
## range; the snowline already tints the whole cap white.
const POLAR_RELIEF_AMP: float = 420.0
## The mountain lake: direction (unit), angular radius, and how far
## its surface sits below the sea line (mountain bowls drain low).
const LAKE_CENTER: Vector3 = Vector3(0.28, 0.26, 0.92)
const LAKE_RADIUS_ANG: float = 0.055
const LAKE_DROP: float = 7.5
## The island: direction (unit) and plateau height. It rises from the
## ocean floor as a steep-sided volcanic plateau -- the ferry's
## destination. Placed OFFSHORE: lat 60, lon 90 = 1.57 rad from the
## spawn, beyond the continent plateau (1.2 rad) out on the coastal
## shelf -- an island in the sea, with the moat (below) cutting the
## channel the ferry owns. Angular reach 0.012 rad = a 240 m-radius
## island at the 20 km planet scale.
## THE AUTHORED STRAIT (turn 14, the starter-vista proto): the ferry
## island moved INTO the homeland's sea front - yes at the coast
## within the dome's falloff, so the moat law deliberately cuts the
## crossing between the village harbor and the island.
const ISLAND_CENTER: Vector3 = Vector3(0.866, 0.0, 0.5)
const ISLAND_ANGULAR_REACH: float = 0.012
const ISLAND_PLATEAU: float = 20.0
## THE BOOT COVE (2026-10-14, the owner's vista law: "grass hillside,
## the capitol city + coastline ~1 km out; mountains way off behind").
## An authored sea notch + shelf-city strand cut INTO the homeland's
## own plain, on the south bearing (COVE_BEARING_DEG in the spawn
## tangent frame):
##   - the CAPITOL CITY FLAT: grassland turf at sea + 22 m riding the
##     flat ring 0.86..1.1 km from the boot - the city basin clears
##     the boot's low-eye horizon (~654 m on the flats), so the
##     monolith + city skyline are VISIBLE from the spawn plaza over
##     the water;
##   - the COVE SEA: from the flat's outer rim out to the homeland
##     reach, the water cut opens - the coastline reads ~1.1 km off;
##   - the boot plaza + dry apron keep their own ground outside the
##     bearing window, so the W4 boot-dry law survives untouched;
##   - the ring range lives untouched all around at 5.2..14.8 km, so
##     the turn-around vista reads the mountain band kilometers off.
## The ferry island + strait moat law is untouched: the island keeps
## its own sea front and bearing.
const COVE_BEARING_DEG: float = 90.0
const COVE_HALF_WIDTH: float = 0.15
const CAPITOL_FLAT_IN_ANG: float = 0.043
const CAPITOL_FLAT_OUT_ANG: float = 0.055
const CAPITOL_BASE_LIFT: float = 22.0
const COVE_FLOOR_DROP: float = 8.0
## The strand's fixed color-noise salt: authored features do not roll
## with the world seed (the cove is one authored coast, not biome).
const COVE_SALT: int = 733
## THE VILLAGE HILLSIDE (the owner's overlook read): the boot plaza
## benches up so the starter village reads "grassy hillside
## overlooking the capitol + coast" -- the plaza at 28 m sits above
## the capitol bench (sea+22) and the cove water, with the ring
## range 5+ km behind it. The plaza-flat + apron laws ride the same
## constant (ramps relaw), so the boot ground stays exact under the
## taller bench.
const VILLAGE_HILLSIDE_LIFT: float = 19.0  # plaza = VILLAGE..+SPAWN height

## THE CAPITOL PLAZA ANCHOR: the cove's far rim, 1.03 km from the
## boot on the same strand read. THIS is the Novo Concord city
## bearing (the "one of those is the Novo Concord Federation city",
## 2026-10-14); the plaza laws below turf it flat for the build.
## The spawn shore: guaranteed land + a flattened build/walk plaza.
const SPAWN_CENTER: Vector3 = Vector3(1.0, 0.0, 0.0)
## THE COVE AXIS (AUTHORED STAND UNIT): the strand's center bearing,
## tangent-plane placed at the capitol flat's mid ring (0.049 rad =
## ~980 m). Pure function of the spawn plaza's boot frame.
static func cove_axis() -> Vector3:
	var east: Vector3 = Vector3(0, 1, 0).cross(SPAWN_CENTER).normalized()
	var north: Vector3 = SPAWN_CENTER.cross(east).normalized()
	var rad: float = deg_to_rad(COVE_BEARING_DEG)
	var mid: float = 0.5 * (CAPITOL_FLAT_IN_ANG + CAPITOL_FLAT_OUT_ANG)
	var dir: Vector3 = (SPAWN_CENTER + east * (mid * cos(rad)) \
		+ north * (mid * sin(rad))).normalized()
	return dir.normalized()

## THE SUN PANS (v11, the authored desert atoll): the water law never
## co-locates hot+dry on this seed (the globe scan measured ZERO
## desert bands), so the desert rides an AUTHORED feature: a small
## volcanic atoll on the face-12 bearing (the scan's warmest deep-
## ocean face: t=0.65, m=0.62, barely any land). The land dome + the
## climate pocket resolve DESERT at the core; the fade rings out
## through the dry ladder to the wetter coast -- desert -> savanna ->
## shore, all riding the existing dressing laws (straw tints, shells,
## wrack, ore). Pure functions of the direction: mesh, walk, biome,
## and dressing all read the same law. GM discovery: far-side ocean
## bearing, glide-reachable from the homeland islands.
const SUN_PANS_HEAT: float = 0.08   # the volcanic lift over face-12's base heat
const SUN_PANS_DRY: float = 0.48    # the pans wring the air out
const SUN_PANS_ANG: float = 0.028   # ~560 m island radius at the planet scale

static func sun_pans_dir() -> Vector3:
	return preload("res://core/frame/math/icosahedral_faces.gd").face_center(12).normalized()

## The pans' climate factor (0..1): 1 on the pan core, smoothstep
## falloff to the beach rim.
static func sun_pans_factor(d: Vector3) -> float:
	var ang: float = d.normalized().angle_to(sun_pans_dir())
	if ang >= SUN_PANS_ANG:
		return 0.0
	var t: float = 1.0 - ang / SUN_PANS_ANG
	return 1.0 if t >= 0.7 else smoothstep(0.0, 0.7, t)

## The pans' LAND dome (0..1): the same plateau-then-coast law the
## homeland dome uses, so the noise carve keeps a coast and the skirt
## floor keeps the ring dry.
static func _sun_pans_island(d: Vector3) -> float:
	var ang: float = d.normalized().angle_to(sun_pans_dir())
	if ang >= SUN_PANS_ANG:
		return 0.0
	var t: float = ang / SUN_PANS_ANG
	return 1.0 if t <= 0.55 else smoothstep(1.0, 0.55, t)

## THE CAPITOL PLAZA DIRECTION: the city strand anchor ON the flat
## ring (the monolith + city props ride it).
static func capitol_dir() -> Vector3:
	return cove_axis()

## MESH-RESOLUTION LAW (web play-test round 15): at the v1 planet
## scale the streamed terrain mesh samples the heightfield only every
## ~330 m (icosahedral face edge ~21 km / 2^6 subdivisions). A 30 m
## plaza is smaller than ONE tile, so the mesh never saw it: the boot
## sat at SPAWN_HEIGHT (9 m) while the rendered ground stayed at the
## natural ~30 m peak. The camera ended up INSIDE the hillside, the
## backface-culled terrain vanished, and the water shell was the only
## surface left -- "I spawned on the ocean layer, land above me". The
## plaza must span several tiles to exist in the mesh at all.
## 0.04 rad = 800 m (~2.4 tiles), full-flat within 0.024 rad = 480 m,
## past the ~360 m boot horizon (so the whole visible ground is plaza).
const SPAWN_FLAT_ANG: float = 0.04
const SPAWN_HEIGHT: float = 9.0 + VILLAGE_HILLSIDE_LIFT
## No rock, boulder, or tree may center within this angle of spawn
## (at 20 km that is ~240 m of clear shore; at prototype scale it
## covers the old rock-cap-free spawn guarantee the probes pin).
const SPAWN_CLEAR_ANG: float = 0.012
## SPAWN SHORE APRON (play-test round 8): a guaranteed-dry ring around
## the plaza. The detail noise carved the coast right up to the plaza
## edge, so the boot view was half ocean and every report read
## "spawned in the ocean" while the truth line showed dry ground 3 m
## above the sea line. From the plaza edge out to this angle the land
## floors to (sea + margin), blending down from the plaza height so
## the ramp-continuity law still holds (no cliffs).
## Round 15: pushed out with SPAWN_FLAT_ANG -- the apron is the tier
## OUTSIDE the plaza, so its inner edge must never sit inside it.
const SPAWN_APRON_ANG: float = 0.06 # ~1200 m at the 20 km planet scale
const SPAWN_APRON_SEA_MARGIN: float = 0.25
## Tier 2 (play-test round 9): the 80 m apron was smaller than the
## boot horizon (~360 m from a 3 m eye height), so the screenshot
## still showed the sea beyond it and the report repeated. The shore
## floor is now HELD out to this angle -- the coast starts past the
## horizon, and the dome carve makes the first bays a journey away.
const SPAWN_APRON_OUTER_ANG: float = 0.09 # ~1800 m at the 20 km scale
## The homeland's angular reach: the STARTING CONTINENT's guaranteed
## land around the spawn. 2.0 rad = ~40 km at the 20 km planet scale
## -- the streamed neighborhood (faces span ~60 deg) is solid land,
## the coast is a journey, and the ocean lies beyond it. The dome is
## GATED BY LATITUDE (temperate band only), so the polar seas survive
## the big cap, and the detail noise carves the coast into bays and
## points (no circle coastline).
## The homeland's angular reach: the STARTING CONTINENT around the
## spawn. 0.70 rad = ~14 km at the 20 km planet scale - the recorded
## home continent (to ~12.6 km from boot, 159-251 km2); beyond it the
## detail noise carves the coast into bays and points, and the ocean
## lies beyond. The dome is shaped by the plateau falloff, and the
## ring range lives on its hinterland.
const HOMELAND_ANGULAR_REACH: float = 0.70
## The island moat: a deep channel ringing the island from
## ISLAND_ANGULAR_REACH out to this angle (the crossing the ferry
## owns -- even where the continent reaches, the channel cuts).
const ISLAND_MOAT_OUTER: float = 0.03
const ISLAND_MOAT_DEPTH: float = 5.0


## The world seed as bytes (from the project setting).
static func world_seed_bytes() -> PackedByteArray:
	var raw: String = str(ProjectSettings.get_setting(WORLD_SEED_SETTING, DEFAULT_WORLD_SEED))
	return raw.to_utf8_buffer()


## Deterministic 32-byte seed for one face's content.
static func face_seed_bytes(world_seed: PackedByteArray, face: int) -> PackedByteArray:
	return SeedChain.derive_seed([world_seed], "terrain/%s/face/%d" % [RULESET_VERSION, face])


## One rock's placement spec (all fields derived, nothing random here).
class RockSpec:
	var dir: Vector3
	var scale: float
	var yaw: float


## One boulder's placement spec. Boulders are the big climbable rocks:
## several meters across, embedded deep, collider-carried (they block
## -- walk around or climb). The mantle raycast reads their top off
## the collider, so no walk-over cap exists for them.
class BoulderSpec:
	var dir: Vector3
	var radius: float
	var yaw: float


## Per-seed scalar in [0, 1) from the seed bytes (stream salt).
## LANE-H2 SEED-CONSTANT MEMO: _seed_salt is a pure function of
## (world_seed, tag) -- no direction, no state. Measured: ~958k calls
## per level-6 patch build, each walking the whole seed + tag bytes
## through a modulo chain, always returning the same integer for the
## same (seed, tag). The memo answers the SAME integer from a per-seed
## tag table (pure law, zero behavior change). Mutex-guarded because
## the mesh derive runs on worker lanes (the same discipline the
## SectorCache statics already follow).
static var _salt_mutex := Mutex.new()
static var _salt_seed: PackedByteArray = PackedByteArray()
static var _salt_table: Dictionary = {}

static func _seed_salt(world_seed: PackedByteArray, tag: String) -> int:
	_salt_mutex.lock()
	if world_seed == _salt_seed and _salt_table.has(tag):
		var hit: int = _salt_table[tag]
		_salt_mutex.unlock()
		return hit
	_salt_mutex.unlock()
	var acc: int = 0
	for b in tag.to_utf8_buffer():
		acc = (acc * 131 + b) % 9007199254740991
	for b in world_seed:
		acc = (acc * 131 + b) % 9007199254740991
	_salt_mutex.lock()
	if world_seed != _salt_seed:
		_salt_seed = world_seed
		_salt_table = {}
	_salt_table[tag] = acc
	_salt_mutex.unlock()
	return acc


## The sea line for this world (pure function of the seed).
## LANE-H2: the sea line is a pure scalar per seed, yet it was
## re-derived ~353k times per level-6 build (every climate/hydro
## corner reads it). Memoized under the same seed-guarded table.
static var _sea_seed: PackedByteArray = PackedByteArray()
static var _sea_valid: bool = false
static var _sea_val: float = 0.0

static func sea_level(world_seed: PackedByteArray) -> float:
	_salt_mutex.lock()
	if _sea_valid and world_seed == _sea_seed:
		var hit: float = _sea_val
		_salt_mutex.unlock()
		return hit
	_salt_mutex.unlock()
	var v: float = SEA_LEVEL_MIN + SEA_LEVEL_SPAN * fposmod(float(_seed_salt(world_seed, "sea")), 1000003.0) / 1000003.0
	_salt_mutex.lock()
	_sea_seed = world_seed
	_sea_val = v
	_sea_valid = true
	_salt_mutex.unlock()
	return v


## Value-noise cell hash: integer lattice cell + salt -> [0, 1).
## Wrapping int math is the hash (deterministic everywhere).
static func _cell_hash(cell: Vector3i, salt: int) -> float:
	var h: int = salt
	h = (h * 668265263) ^ (cell.x * 374761393)
	h = (h * 1274126177) ^ (cell.y * 668265263)
	# THE MIRROR-TWIN FIX: the raw z term dominated the XOR fold and
	# left the field z-mirror symmetric (measured p50 height-delta
	# 0.0 m over 2000 mirror pairs - every landmass spawned a
	# lon-mirrored twin across the boot meridian). A one-way folded
	# z term: mirror cells now hash differently (post-fix measured
	# p50 1.4-2.0 m, p90 7.6-20.8 m - no structural pairing).
	var zterm: int = cell.z * 2147483647 + 7919
	h = (h * 974634733) ^ (zterm ^ (zterm >> 13))
	h = h ^ (h >> 15)
	h = h ^ (h >> 33)  # second avalanche: flattens the folded bits' skew
	return float(absi(h) % 1000003) / 1000003.0


## Trilinear value noise on the direction cube (continuous everywhere;
## per-octave wavelength fits inside a lattice cell, so no seam law is
## needed at this fidelity). freq = lattice cells per radius.
## THE WILDFLOWER DRIFT (the meadow's patch law): a pure signal in
## [0, 1] on the site direction -- two value-noise octaves at a meadow
## patch scale (~50 m cells at the planet scale), sharpened so only the
## strong cells form drifts and a high fraction of sites inside them
## bloom. THE MEADOW LAW readers (the streamer's rng-for-rng twins)
## raise the bloom draw gate by this member and weight the palette to
## the drift band -- a patch reads as ONE wildflower kind, then hands
## off to the next: real fields of wildflowers, not sprinkles. Pure
## reads, no stamping, no rng draw (the twin laws' draw counts stay
## untouched), and the field is of the LAND: seed-deterministic, like
## the pans' own name.
const FLDRIFT_SALT: int = 2879
static func wildflower_drift(d: Vector3) -> float:
	var base: float = _vnoise(d, FLDRIFT_SALT, 2600.0)
	var fine: float = _vnoise(d, FLDRIFT_SALT + 1, 6800.0)
	var n: float = base * 0.62 + fine * 0.38
	return clampf((n - 0.42) / 0.28, 0.0, 1.0)


static func _vnoise(d: Vector3, salt: int, freq: float) -> float:
	var p: Vector3 = d * freq
	var c: Vector3i = Vector3i(floori(p.x), floori(p.y), floori(p.z))
	var f: Vector3 = p - Vector3(c)
	var u: Vector3 = f * f * (Vector3(3.0, 3.0, 3.0) - 2.0 * f)
	var v000: float = _cell_hash(c + Vector3i(0, 0, 0), salt)
	var v100: float = _cell_hash(c + Vector3i(1, 0, 0), salt)
	var v010: float = _cell_hash(c + Vector3i(0, 1, 0), salt)
	var v110: float = _cell_hash(c + Vector3i(1, 1, 0), salt)
	var v001: float = _cell_hash(c + Vector3i(0, 0, 1), salt)
	var v101: float = _cell_hash(c + Vector3i(1, 0, 1), salt)
	var v011: float = _cell_hash(c + Vector3i(0, 1, 1), salt)
	var v111: float = _cell_hash(c + Vector3i(1, 1, 1), salt)
	var x00: float = lerpf(v000, v100, u.x)
	var x10: float = lerpf(v010, v110, u.x)
	var x01: float = lerpf(v001, v101, u.x)
	var x11: float = lerpf(v011, v111, u.x)
	return lerpf(lerpf(x00, x10, u.y), lerpf(x01, x11, u.y), u.z)


## Land mass in [0, 1]: latitude band gate (the polar caps are sea --
## the Concord maps show white at the top of the world, ice later) x
## seeded continental noise, with the STARTING CONTINENT guaranteed
## around the spawn. Above ~0.18 is solid land. Near the homeland's
## edge the detail noise carves the guaranteed dome into bays and
## points -- the coast is organic, never a circle.
static func _land_mass(d: Vector3, salt: int) -> float:
	var lat: float = 90.0 - rad_to_deg(acos(clampf(d.y, -1.0, 1.0)))
	var band: float = cos(deg_to_rad(minf(absf(lat), 45.0) * (90.0 / 45.0)))
	band = clampf(band, 0.0, 1.0)
	var base: float = _vnoise(d, salt, 2.0)
	var detail: float = 0.65 * _vnoise(d, salt + 1, 5.0) + 0.35 * _vnoise(d, salt + 2, 11.0)
	var noise_land: float = clampf(band * (base * 1.15 + detail * 0.45 - 0.68), 0.0, 1.0)
	var dome: float = _homeland(d)
	if dome > 0.0:
		return clampf(maxf(noise_land, maxf(dome * 0.95 - detail * 0.35, dome * 0.42)), 0.0, 1.0)
	# THE SUN PANS ISLAND (v11): the authored desert atoll pays the
	# same max-law the homeland dome pays (noise still carves the
	# coast, the skirt floor keeps the ring dry).
	var pans: float = _sun_pans_island(d)
	if pans > 0.0:
		return clampf(maxf(noise_land, maxf(pans * 0.95 - detail * 0.35, pans * 0.42)), 0.0, 1.0)
	# THE POLAR CAPS (v12): the ice/snow landmasses at the poles pay the
	# same max-law (the natural latitude band zeroed land there). The cap
	# floor is HIGHER than the homeland's (0.72 vs 0.42): the cap has no
	# spawn/plains override to raise it, so its interior must sit solidly
	# above the sea line on its own (measured: the 0.42 floor left the
	# pole at -3.4 m -- noise tipped it under the sea).
	var cap: float = _polar_cap(d)
	if cap > 0.0:
		return clampf(maxf(noise_land, maxf(cap * 1.02 - detail * 0.25, cap * 0.72)), 0.0, 1.0)
	return noise_land


## THE SEA BIAS NOTE (the oceanify calibration): the world's land
## share lives inside the W1 budget band (100..380 km2); the recorded
## rolls measured 214 km2 on the winner seed up to 437 km2 on a
## moonstruck candidate. See the seed scans in game/debug for the
## calibration history.


## The spawn-shore homeland dome: guarantees land around the spawn
## direction regardless of the continental roll of the dice. PLATEAU
## shape: full strength within 60% of the reach, then a smoothstep
## falloff to the coast -- the streamed neighborhood rides the
## plateau, and the detail noise carves the coast into bays.
static func _homeland(d: Vector3) -> float:
	var ang: float = d.angle_to(SPAWN_CENTER)
	if ang >= HOMELAND_ANGULAR_REACH:
		return 0.0
	var t: float = ang / HOMELAND_ANGULAR_REACH
	return 1.0 if t <= 0.6 else smoothstep(1.0, 0.6, t)


## THE POLAR CAP shape (0..1): a plateau-then-coast dome around BOTH
## poles, symmetric in |d.y| (so north and south pay the same law and
## the map/compass lat sign is untouched). Angle from the pole axis
## (0,+1,0); full strength inside 60% of POLAR_CAP_ANG, then a
## smoothstep falloff to the polar sea -- the SAME plateau dialect the
## homeland dome uses, so the detail noise carves the ice coast into
## bays and points. Pure function of the direction (mesh, walk, biome,
## and dressing all read it).
static func _polar_cap(d: Vector3) -> float:
	var ang: float = acos(clampf(absf(d.y), -1.0, 1.0))
	if ang >= POLAR_CAP_ANG:
		return 0.0
	var t: float = ang / POLAR_CAP_ANG
	return 1.0 if t <= 0.6 else smoothstep(1.0, 0.6, t)


## Mountain bowl factor (0..1) for the lake direction.
static func _lake_bowl(d: Vector3) -> float:
	var ang: float = d.angle_to(LAKE_CENTER)
	if ang >= LAKE_RADIUS_ANG:
		return 0.0
	return smoothstep(0.0, 1.0, 1.0 - ang / LAKE_RADIUS_ANG)


## Island plateau shape (0 at the shore, 1 on the top).
static func _island_shape(d: Vector3) -> float:
	var ang: float = d.angle_to(ISLAND_CENTER)
	if ang >= ISLAND_ANGULAR_REACH:
		return 0.0
	var t: float = 1.0 - ang / ISLAND_ANGULAR_REACH
	return smoothstep(0.0, 1.0, clampf(t * 1.8, 0.0, 1.0))


## THE BOOT COVE WINDOW (0..1): angular proximity to the authored
## strand bearing, cone shaped around the cove axis with a wide
## smoothstep falloff -- the bay's land walls are the window's rim
## where the weight dies. Pure; sampled in the spawn tangent frame.
## THE COVE WINDOW (0..1): BEARING deviation from the authored stand
## axis, measured in the spawn tangent frame -- never a 3D cone (a
## cone at ring radii swallows the dry apron ring at other bearings).
## Full strength ON the axis bearing, dead past the half width.
static func _cove_window(d: Vector3) -> float:
	var east: Vector3 = Vector3(0, 1, 0).cross(SPAWN_CENTER).normalized()
	var north: Vector3 = SPAWN_CENTER.cross(east).normalized()
	var axis: Vector3 = cove_axis()
	var qa: Vector3 = axis - SPAWN_CENTER * SPAWN_CENTER.dot(axis)
	qa = qa.normalized()
	var q: Vector3 = d - SPAWN_CENTER * SPAWN_CENTER.dot(d)
	var qlen: float = q.length()
	if qlen < 1e-9:
		return 1.0
	q = q / qlen
	var dev: float = absf(atan2(q.dot(north), q.dot(east)) \
		- atan2(qa.dot(north), qa.dot(east)))
	if dev > PI:
		dev = TAU - dev
	# THE REACH GATE (v12): the bearing window ALONE wraps the WHOLE
	# planet along the cove's great circle -- harmless while the poles
	# were open ocean, but it cut a phantom sea notch into the new polar
	# land (the north pole sits ON the cove bearing at 1.57 rad, so the
	# window read 1.0 there and the sea cut pressed the pole to -3.4 m).
	# The authored cove is a HOMELAND feature: full window out to the
	# homeland reach, fading to nothing just beyond it, so the coast is
	# unchanged near the boot and nothing wraps.
	var ang_spawn: float = d.angle_to(SPAWN_CENTER)
	var reach: float = 1.0 - smoothstep(HOMELAND_ANGULAR_REACH - 0.04, \
		HOMELAND_ANGULAR_REACH, ang_spawn)
	return (1.0 - smoothstep(COVE_HALF_WIDTH, COVE_HALF_WIDTH * 2.0, dev)) * reach


## THE GROUND LAW (v2 core, renamed at v3). Height (meters) of the
## walkable terrain above the base surface at world direction `dir`
## BEFORE hydrology carving. Continuous everywhere (smoothstep blends;
## max/lerp of continuous fields). Bands: ocean floor -> continental
## shelf -> beach -> plains -> hills -> mountains -> snowline ceiling;
## the lake and island override their bowls; the spawn plaza flattens
## last (guaranteed flat ground under the boot). The PUBLIC
## terrain_height() now wraps this with the hydrology carve (lakes +
## river channels, prd-terrain.md) and delegates -- spawn carving
## stays LAST so the apron stays dry.
## PERFORMANCE LAW (v3, measured): the mesh pass now samples slopes
## too, so quantized-direction memoization lives HERE (the law is
## pure per direction; read-cache law as per the header block). world_seed
## keys the cache so multi-world callers never cross-contaminate.


## -- EXTERNAL TERRAIN BACKEND (the heightfield source seam) ----------
## An installable provider REPLACES the natural analytic landfield as
## the raw ground: imported heightmaps / server continents / any other
## height source flow through the WHOLE chain -- LOD, skirts, the walk
## law, the biome fields, the hydrology carve, the props -- because
## every downstream law reads terrain_height(). The contract for a
## backend Callable: (unit_dir: Vector3, seed_bytes: PackedByteArray)
## -> float (meters above the base surface, may be negative).
##
## What a backend does NOT own (the laws that stay LAW-NATIVE on top):
##   - the sculpt laws (mountain lake bowl, ferry island plateau,
##     the island moat) -- still applied over the imported field;
##   - the spawn guarantee (plaza flatten + dry shore apron) -- the
##     boot lands dry on ANY backend;
##   - the hydrology carve (lake basins + river channels) -- rivers
##     and lakes sit on top of whatever heightfield is installed;
##   - TERRAIN_MAX (the hard ceiling) -- no backend grows a mesa wall.
## The default is UNINSTALLED (analytic law runs as before): the natural analytic law is the body of
## the law and an install is an opt-in change of behavior only.
## Uninstall clears the height cache so a re-install never serves
## stale sectors.
static var _height_backend: Callable = Callable()

## THE LAW EPOCH (perf leg): bumped on every backend install/uninstall --
## derived caches elsewhere (the streamer's warm-mesh ring) compare
## their epoch against this to invalidate THEMSELVES, so a law change
## guards every consumer seam without wiring a flush into each one.
static var LAW_EPOCH: int = 0

static func install_terrain_backend(backend: Callable) -> void:
	_height_backend = backend
	LAW_EPOCH += 1
	# The one LEGAL wholesale flush: the LAW changed, so warm sectors
	# are not stale-able but wrong. Capacity eviction (the LRU path)
	# never lands here.
	_height_cache.clear()      # fresh sectors: no stale law answers
	_carved_cache.clear()      # the carved result rides the ground law
	_channel_cache.clear()     # channel field rides the ground law
	_temperature_cache.clear() # lapse rides the ground law
	_water_table_cache.clear() # perch rides the ground law
	_river_spec_cache.clear()  # springs/pathing re-derive under the seam
	_waterfall_cache.clear()   # the seam masks ride the specs
	_crag_cache.clear()        # the color noises ride the seed law
	_ground_cache.clear()      # the fused sample rides the ground law


static func uninstall_terrain_backend() -> void:
	_height_backend = Callable()
	LAW_EPOCH += 1
	_height_cache.clear()
	_carved_cache.clear()
	_crag_cache.clear()
	_waterfall_cache.clear()
	_channel_cache.clear()
	_temperature_cache.clear()
	_water_table_cache.clear()
	_river_spec_cache.clear()
	_crag_cache.clear()
	_ground_cache.clear()


static func terrain_backend_installed() -> bool:
	return _height_backend.is_valid()


static func _terrain_height_base(dir: Vector3, world_seed: PackedByteArray) -> float:
	dir = dir.normalized()
	var cached = _height_cache.get_value(dir, world_seed)
	if cached != null:
		return float(cached)
	var h: float = _terrain_height_base_nowrap(dir, world_seed)
	if _height_cache.set_value(dir, world_seed, h):
		return h
	# Poison guard tripped (a rogue backend answer): serve the
	# honest clamped number WITHOUT caching it -- the law stays
	# total, no poisoned sector ever enters (and can't be served		# forever by a hot key).
	return clampf(h, -TERRAIN_MAX, TERRAIN_MAX)


## THE RAW v2 height body (the cache wrapper's callee). TWO FIELDS,
## ONE TAIL: the raw landfield is either the installed EXTERNAL
## BACKEND or the analytic law (the uninstalled fallback, bit-identical
## to every pre-seam world) -- then BOTH paths run the same sculpt +
## spawn tail (ferry island + moat, spawn plaza, dry apron), so the
## law-native guarantees survive ANY backend. The TERRAIN_MAX ceiling
## roofs the raw field on BOTH paths; the mountain-lake bowl stays
## analytic-only (a foreign field brings its own water).
static func _terrain_height_base_nowrap(dir: Vector3, world_seed: PackedByteArray) -> float:
	var d: Vector3 = dir.normalized()
	var sea: float = sea_level(world_seed)
	if _height_backend.is_valid():
		# Backend contract: (unit_dir, seed_bytes) -> meters (may be
		# negative). Sector memoization is owned by _terrain_height_base
		# (the same quantized cache the analytic path uses).
		var bk: float = float(_height_backend.call(d, world_seed))
		if not is_finite(bk):
			bk = 0.0  # rogue backend: the law stays total (plaza-flat fall-through)
		var bh: float = minf(bk, TERRAIN_MAX)
		# The island's lower ramp reads a shelf-floor number; under a
		# backend the analytic seafloor noise is not ours to read, so
		# the ramp blends from the flat nominal floor.
		return _sculpt_and_spawn(d, bh, sea, sea - OCEAN_DEPTH_MIN)
	var raw_h: float = _natural_raw(d, world_seed)
	# The island skirt's floor: JUST ABOVE the strait line (the ramp
	# rises from the coastal shelf, and the W2 cap sweep reads dry
	# around the moat - the minf moat carve still cuts the channel).
	return _sculpt_and_spawn(d, raw_h, sea, sea + 0.4)


## The NATURAL analytic raw field (shelf -> land -> hills -> mountains
## -> native lake bowl), WITHOUT the island/moat/spawn tail. Named and
## public so authored backends can COMPOSE over the home world
## (sundered_sea: carve the strait INTO the natural land) instead of
## reimplementing geology. Bit-identical to the pre-seam analytic
## body: same band law, same noise streams, same TERRAIN_MAX clamp.
static func _natural_raw(d: Vector3, world_seed: PackedByteArray) -> float:
	var sea: float = sea_level(world_seed)
	var salt: int = _seed_salt(world_seed, "terrain")
	var land: float = _land_mass(d, salt)
	var ocean_floor: float = sea - (OCEAN_DEPTH_MIN + OCEAN_DEPTH_SPAN * _vnoise(d, salt + 7, 6.0))
	var land_h: float = -3.0 + land * 17.0
	var inland: float = smoothstep(0.18, 0.5, land)
	land_h += inland * (_vnoise(d, salt + 4, 9.0) * 6.0 - 2.0)
	var mnoise: float = _vnoise(d, salt + 3, 3.0)
	var mask: float = smoothstep(0.62, 0.94, mnoise) * smoothstep(0.35, 0.6, land)
	# THE RANGE RETUNE: the far chain rides MOUNTAIN_AMP (the shared
	# mountain stream with the home ring) - the old inlined cap left
	# the far continents hill-sized (measured: 93 m peak on the old
	# law). The powder keeps the crest family; wider mask band keeps
	# the carve slope inside the continuity bound.
	land_h += mask * pow(mnoise, 2.2) * MOUNTAIN_AMP
	# THE HOME-ANCHORED RING RANGE: real mountains on the boot's own
	# continent - a ring band 0.26..0.74 rad around the SPAWN, sampled
	# in the spawn's polar frame (bearing phi + ring distance), so the
	# projection is continuous (no seam law) and RADIAL walks see
	# gentle slope: climb rides the ramp, crest arcs ride the bearing.
	var ang_boot: float = d.angle_to(SPAWN_CENTER)
	var ramp: float = smoothstep(RING_R0, RING_R1, ang_boot) \
		* (1.0 - smoothstep(RING_R1, RING_R2, ang_boot))
	if ramp > 0.0:
		var east: Vector3 = Vector3(0.0, 1.0, 0.0).cross(SPAWN_CENTER).normalized()
		var north: Vector3 = SPAWN_CENTER.cross(east).normalized()
		var phi: float = atan2(d.dot(north), d.dot(east))
		var pf: Vector3 = Vector3(cos(phi), sin(phi), ang_boot)  # ring-continuous coords
		var crest_noise: float = _vnoise(pf, salt + 21, 0.55)
		var crest: float = 1.0 - absf(2.0 * crest_noise - 1.0)  # zero-crossing ridge arcs
		var blobs: float = _vnoise(pf, salt + 22, 0.9)
		var chain_gate: float = smoothstep(RING_T_LO, RING_T_LO + 0.2, blobs) \
			* (1.0 - smoothstep(RING_T_HI, RING_T_HI + 0.25, blobs))
		var land_gate: float = smoothstep(0.20, 0.34, land)
		land_h += ramp * chain_gate * (0.35 + 0.65 * pow(crest, 1.6)) * land_gate * MOUNTAIN_AMP
	# THE POLAR RELIEF (v12): a masked mountain stream on the ice caps so
	# the caps read as broken country, not a flat pancake. The mask rides
	# the cap strength, so the coast still ramps gently (continuity).
	var cap_r: float = _polar_cap(d)
	if cap_r > 0.0:
		var cap_noise: float = _vnoise(d, salt + 31, 4.0)
		var cap_mask: float = smoothstep(0.55, 0.92, cap_noise) * smoothstep(0.35, 0.7, land)
		land_h += cap_r * cap_mask * pow(cap_noise, 2.0) * POLAR_RELIEF_AMP
	var h: float = minf(lerpf(ocean_floor, land_h, smoothstep(0.0, 0.18, land)), TERRAIN_MAX)
	var bowl: float = _lake_bowl(d) * smoothstep(0.1, 0.3, land)
	if bowl > 0.0:
		h = lerpf(h, sea - LAKE_DROP, bowl)
	return h


## The SHARED sculpt + spawn tail (island + moat, spawn plaza, dry
## apron): applied over whichever landfield was installed, so the ferry
## crossing and the dry boot survive ANY backend. `island_floor` is the
## number the island's lower ramp blends from (the analytic seafloor
## field on the native path, the flat nominal floor under a backend).
static func _sculpt_and_spawn(d: Vector3, h_in: float, sea: float, island_floor: float) -> float:
	d = d.normalized()
	var h: float = h_in
	# THE BOOT COVE (the authored vista law, rides over ANY backend):
	# a shelf-city strand + sea notch cut into the homeland's own
	# plain on the cove bearing, ring-shaped in the spawn frame. First
	# the CITY FLAT (lift overrides the ring-range massif where the
	# window holds -- the strand is authored, not noise), then the
	# SEA cut OUTSIDE the flat rim out to the homeland reach.
	var cove_w: float = _cove_window(d)
	if cove_w > 0.0:
		var ang_cove: float = d.angle_to(SPAWN_CENTER)
		# The city flat: between the flat rings the strand floors at
		# sea + lift (an authored bench, ramping at both rims).
		if ang_cove < CAPITOL_FLAT_OUT_ANG:
			# The city bench: full authored lift inside the flat ring,
			# ramping UP only at the inland rim (the strand keeps its
			# sea+lift height to the water -- no headland wall between
			# the city and the cove).
			var inner: float = smoothstep(0.0, CAPITOL_FLAT_IN_ANG, ang_cove)
			h = lerpf(h, sea + cove_w * CAPITOL_BASE_LIFT, \
				clampf(cove_w * inner, 0.0, 1.0))
		else:
			# The cove water: OUTSIDE the flat rim the strand ramps
			# down into the bay (a ~120 m beach; shallow shelf, not an
			# abyss), so the boot's eye reads the coastline at ~1.1 km.
			var sea_ramp: float = smoothstep(CAPITOL_FLAT_OUT_ANG, \
				CAPITOL_FLAT_OUT_ANG + 0.006, ang_cove)
			h = lerpf(h, sea - COVE_FLOOR_DROP, \
				clampf(cove_w * sea_ramp, 0.0, 1.0))
	# The island: volcanic plateau rising from the (floor) strait.
	# The tier OVERLAYS the base field (lerp, not max): the ring-range
	# crest or any other massif lives on the seat otherwise - the W5
	# law pins the top at EXACTLY sea+22 under any seed.
	var isl: float = _island_shape(d)
	if isl > 0.0:
		var top: float = sea + 2.0 + isl * ISLAND_PLATEAU
		h = lerpf(h, maxf(island_floor, lerpf(island_floor, top, isl)), isl)
	# The moat: a deep channel ringing the island (the ferry's
	# crossing, cut even where the continent reaches).
	var ang_isl: float = d.angle_to(ISLAND_CENTER)
	if ang_isl > ISLAND_ANGULAR_REACH and ang_isl < ISLAND_MOAT_OUTER:
		h = minf(h, sea - ISLAND_MOAT_DEPTH)
	# Spawn plaza: flatten last -- the boot always lands on known
	# ground (ramp reaches full flat at half the plaza radius).
	var ang_spawn: float = d.angle_to(SPAWN_CENTER)
	if ang_spawn < SPAWN_FLAT_ANG:
		var t: float = 1.0 - ang_spawn / SPAWN_FLAT_ANG
		h = lerpf(h, SPAWN_HEIGHT, smoothstep(0.0, 1.0, clampf(t * 2.5, 0.0, 1.0)))
	# Spawn shore apron (see the const block): from the plaza edge out
	# to SPAWN_APRON_ANG the land floors to just above the sea line,
	# ramping down from the plaza height. The floor meets the plaza at
	# exactly SPAWN_HEIGHT (continuous) and ends at sea + margin (the
	# worst-case step down to the natural dome terrain stays under the
	# 4 m ramp-continuity bound the probe pins).
	# THE COVE YIELD: inside the cove window beyond the city flat the
	# apron STANDS DOWN -- the authored bay is the coast there, and
	# the apron's max() would raise the cove water back to dry land.
	var ang_apron: float = d.angle_to(SPAWN_CENTER)
	var apron_skip: bool = cove_w > 0.1 and ang_apron >= CAPITOL_FLAT_OUT_ANG
	if ang_apron >= SPAWN_FLAT_ANG and ang_apron < SPAWN_APRON_OUTER_ANG and not apron_skip:
		var apron_floor: float = sea + SPAWN_APRON_SEA_MARGIN
		if ang_apron < SPAWN_APRON_ANG:
			var t_apron: float = 1.0 - (ang_apron - SPAWN_FLAT_ANG) / (SPAWN_APRON_ANG - SPAWN_FLAT_ANG)
			apron_floor = lerpf(sea + SPAWN_APRON_SEA_MARGIN, SPAWN_HEIGHT, smoothstep(0.0, 1.0, t_apron))
		h = maxf(h, apron_floor)
	return h


## Rock specs for a face. Pure function of the seed: a fresh RNG is
## seeded from the face's derived bytes every call, so any process on
## any machine derives identical content. Dirs too close to the spawn
## shore are RE-DRAWN (never dropped: the count contract 20..34 holds)
## so no walk-over cap ever covers the spawn plaza, and WATER draws
## re-roll the same way -- rocks belong on dry ground (they skipped at
## draw time put them all in the bay on wet-side faces). v4 DENSITY:
## the count carries the face's real ground footprint (~251 km2 at the
## 20 km scale) -- 2..5 rocks put the nearest stone kilometers off.
## v4 SITE COVERAGE (the corner-face fix): the old 70/30
## center/corner draws hug the cell CENTROID -- the boot sits in a
## near-face corner, and the whole visible boot arc went prop-bare
## (measured by tests/probe_prop_density). The draw is BARYCENTRIC
## now (center 0.25 + two corner verts 0.35/0.40): the sites cover
## the whole Voronoi cell evenly, boot corners included. The convex
## mix of the cell's four points cannot leave the cell, and the
## spawn-clear/water redraws below stay the guards.
## THE HOT-PATH CACHE: the walk-over provider calls this EVERY walk
## step, so the array memoizes per (world seed, face) on the
## LRU_CACHE primitive (bounds evict, capacity 64 faces -- the
## streamed set + its neighbors live well inside).
static var _rock_specs_cache = LRU_CACHE.new(64)
static func rock_specs(world_seed: PackedByteArray, face: int) -> Array:
	var ckey: String = str(world_seed) + "/" + str(face)
	var cached = _rock_specs_cache.get_value(ckey)
	if cached != null:
		return cached
	var bytes: PackedByteArray = face_seed_bytes(world_seed, face)
	# Fold the 32 seed bytes into one 64-bit RNG seed.
	var acc: int = 0
	for b in bytes:
		acc = (acc * 256 + b) % 9007199254740991
	var rng := RandomNumberGenerator.new()
	rng.seed = acc

	var count: int = rng.randi_range(20, 34)
	var center: Vector3 = Faces.face_center(face)

	var specs: Array = []
	for i in range(count):
		# Direction: BARYCENTRIC draw (v4 site coverage law -- see the
		# header block: center 0.25 + two corner verts 0.35/0.40, so
		# sites cover the whole Voronoi cell, boot corners included).
		# Spawn-adjacent draws (bounded: at most 4 redraws, then the
		# last draw stands -- deterministic on every machine).
		var verts: PackedInt32Array = Faces.face_vertices(face)
		var v: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var v2: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var dir: Vector3 = (center * 0.25 + v * 0.35 + v2 * 0.40).normalized()
		for _try in range(4):
			if dir.angle_to(SPAWN_CENTER) >= SPAWN_CLEAR_ANG:
				break
			v = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
			v2 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
			dir = (center * 0.25 + v * 0.35 + v2 * 0.40).normalized()
		# THE DRY REDRAW (v4): a rock whose draw landed underwater re-rolls
		# the same way the spawn-clear redraw does -- bounded, so on an
		# all-water roll the last draw stands (deterministic; the site
		# pass still water-skips it, but a wet-side face never loses its
		# stones to the bay).
		var sea_rock: float = sea_level(world_seed)
		for _try in range(6):
			if terrain_height(dir, world_seed) >= sea_rock - 0.6:
				break
			v = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
			v2 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
			dir = (center * 0.25 + v * 0.35 + v2 * 0.40).normalized()
		var spec := RockSpec.new()
		spec.dir = dir
		spec.scale = rng.randf_range(1.0, 2.2)
		spec.yaw = rng.randf_range(0.0, TAU)
		specs.append(spec)
	_rock_specs_cache.set_value(ckey, specs)
	return specs


## Boulder specs: 2-3 per face (v4 density: 1-2 left the homelands
## with one climbable boulder per hundreds of km2 at the planet
## scale) -- the VARIETY LAW is universal: any
## streamed set (a face + its 3 neighbors) always carries climbing
## content, so the guarantee is every face, not a lucky subset. Same seed
## discipline as rocks (independent derived stream, so adding
## boulders never reshuffles the rocks). Spawn-adjacent draws are
## re-rolled.
static func boulder_specs(world_seed: PackedByteArray, face: int) -> Array:
	var bytes: PackedByteArray = SeedChain.derive_seed(
		[world_seed], "terrain/%s/boulders/%d" % [RULESET_VERSION, face])
	var acc: int = 0
	for b in bytes:
		acc = (acc * 256 + b) % 9007199254740991
	var rng := RandomNumberGenerator.new()
	rng.seed = acc

	var count: int = 2 + rng.randi_range(0, 1)
	var center: Vector3 = Faces.face_center(face)
	var specs: Array = []
	for i in range(count):
		var verts: PackedInt32Array = Faces.face_vertices(face)
		var v: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var v2b: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var dir: Vector3 = (center * 0.25 + v * 0.35 + v2b * 0.40).normalized()
		for _try in range(4):
			if dir.angle_to(SPAWN_CENTER) >= SPAWN_CLEAR_ANG:
				break
			v = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
			v2b = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
			dir = (center * 0.25 + v * 0.35 + v2b * 0.40).normalized()
		# THE DRY REDRAW (v4, same bounded law as the rocks): a boulder
		# draw landing in the water keeps its climbable count on dry
		# ground wherever the face holds any.
		var sea_b: float = sea_level(world_seed)
		for _try in range(6):
			if terrain_height(dir, world_seed) >= sea_b - 0.6:
				break
			v = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
			v2b = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
			dir = (center * 0.25 + v * 0.35 + v2b * 0.40).normalized()

		var spec := BoulderSpec.new()
		spec.dir = dir
		spec.radius = rng.randf_range(3.5, 6.5)
		spec.yaw = rng.randf_range(0.0, TAU)
		specs.append(spec)
	return specs


## Stable fingerprint of a face's content (probe/determinism aid).
static func fingerprint(world_seed: PackedByteArray, face: int) -> String:
	var specs: Array = rock_specs(world_seed, face)
	var parts: PackedStringArray = PackedStringArray()
	for s in specs:
		parts.append("%s|%.4f|%.4f" % [s.dir, s.scale, s.yaw])
	return "%d rocks: %s" % [specs.size(), "; ".join(parts)]


# -- v3 CLIMATE ARC (prd-terrain.md slice 1) ---------------------------

## Stable biome integer codes (inner-class pattern like RockSpec).
## NEVER rennumber -- saves/worlds derive content from these.
class BiomeId:
	const OCEAN_DEEP: int = 0
	const OCEAN_SHELF: int = 1
	const SHORE: int = 2
	const ALPINE: int = 3
	const TUNDRA: int = 4
	const DESERT: int = 5
	const SWAMP: int = 6
	const TAIGA: int = 7
	const FOREST: int = 8
	const GRASSLAND: int = 9
	const ALPINE_MEADOW: int = 10
	const LAKE: int = 11
	const RIVER: int = 12
	# THE VARIETY LAW (appended 13..16; NEVER renumber - the old ids
	# untouched - saves/worlds derive content from these).
	const JUNGLE: int = 13
	const SAVANNA: int = 14
	const STEPPE: int = 15
	const BADLANDS: int = 16
	const LAST: int = BADLANDS


## Land boundary for the ocean bands (same _land_mass the height law
## reads: below this the heightfield is underwater).
const OCEAN_LAND_LINE: float = 0.18

## Temperature law bands (fractions, pure in [0,1]).
## THE RANGE-ERA LAPSE: the alpine line sits ~286 m and the snow line
## ~353 m at the subtropical base heat - foothills temperate, summits
## stone. The old 26 m ceiling put the alpine line at ~25 m (home
## plateaus read stone).
const TEMP_LAPSE_CEIL: float = 420.0  # meters of height over which heat falls off
const TEMP_LAPSE_RATE: float = 0.75  # fraction lost over the ceiling

## Moisture cells (wavelength inside a lattice cell; no seam law needed
## at this fidelity -- the noise family's own law).
const MOIST_FREQ_COARSE: float = 3.0
const MOIST_FREQ_FINE: float = 7.0

## Biome resolution thresholds (documented, pinned by probe).
const SNOWLINE_T: float = 0.22   # temperature below this freezes
const ALPINE_T: float = 0.34     # freeze-adjacent stone band
const DRY_T: float = 0.32        # moisture below this in warmth = desert
const SWAMP_T: float = 0.68      # moisture above this + low = swamp
## THE VARIETY LAW bands (every threshold MEASURED on the live seed;
## each new band pins its OWN axis - the probe membership law
## re-states these so a threshold move that leaks into the wrong band
## is caught, not just "similar").
const JUNGLE_T: float = 0.72     # the tree band above forest heat
const SAVANNA_M: float = 0.55    # hot dry-mid (between dry and green)
const STEPPE_M: float = 0.50     # the reachable semi-arid cut (mild belt)
const BADLANDS_M: float = 0.45   # dry-warm broken country
const BADLANDS_T: float = 0.5
const EROSION_T: float = 0.55    # the badlands' own erosion-stream gate


## Possessive classes, named for the probes: what a climate reading
## resolves to at ONE direction.
class ClimateSample:
	var temperature: float
	var moisture: float
	var land: float
	var height: float
	var biome: int
	var wetness: float  # blend weight toward the biome palette (slice 2)


## TEMPERATURE: latitude in [0, 1] heat (1 at the equator, 0 at the
## poles, smoothstep), plus altitude lapse, plus seeded noise jitter.
## PERF: sector-memoized (the canonical quantized law -- the mesh pass
## asks temperature at every vertex corner through biome weights).
static var _temperature_cache = SECTOR_CACHE.new()
static func climate_temperature(d: Vector3, world_seed: PackedByteArray) -> float:
	d = d.normalized()
	var cached = _temperature_cache.get_value(d, world_seed)
	if cached != null:
		return float(cached)
	var lat: float = absf(90.0 - rad_to_deg(acos(clampf(d.y, -1.0, 1.0))))
	var t: float = 1.0 - smoothstep(0.0, 90.0, lat)
	var salt: int = _seed_salt(world_seed, "climate_temp")
	var jitter: float = (_vnoise(d, salt, 4.0) - 0.5) * 0.18
	var h: float = terrain_height(d, world_seed)
	# THE SUN PANS HEAT (v11): the atoll's volcanic lift PLUS the lapse
	# exemption -- the base latitude heat at the pans' ocean already
	# clears the desert line (the scan measured t=0.65 at the face),
	# and the pocket keeps ~85% of its ground-level heat at the crest,
	# so the salt pans read DESERT and the skirt keeps the ring.
	var pans_f: float = sun_pans_factor(d)
	var lapse: float = clampf(h, 0.0, TEMP_LAPSE_CEIL) / TEMP_LAPSE_CEIL \
		* TEMP_LAPSE_RATE * (1.0 - 0.85 * pans_f)
	var out: float = clampf(t + jitter - lapse + SUN_PANS_HEAT * pans_f, 0.0, 1.0)
	_temperature_cache.set_value(d, world_seed, out)
	# Note: by construction the output is clamped finite, so the
	# poison guard can never trip here; set_value's bool is ignored.
	return out


## MOISTURE: two octave noises shaped by land (interiors hold more;
## nothing reads below the shore line where sea spray owns the air).
static func climate_moisture(d: Vector3, world_seed: PackedByteArray) -> float:
	d = d.normalized()
	# RIVER RIPPLE (prd-terrain.md: rivers make downstream biome edges
	# real): the channel capsule lifts the moisture FIELD continuously,
	# so banks run wetter than their dry cell -- floodplain green on
	# rivers and a natural swamp tendency at their mouths. Pure: the
	# channel law reads only the carved specs (no moisture reads). The
	# RAW field stays exposed for probes (the boost is an exact,
	# checkable delta on top of it).
	var m_raw: float = clampf(climate_moisture_field(d, world_seed), 0.0, 1.0)
	var c: float = river_channel(d, world_seed)
	return clampf(m_raw + Hydro.RIVER_MOIST_BOOST * c, 0.0, 1.0)


## The moisture FIELD law (the raw, ripple-free body the ripple law
## rides: two-octave noise shaped by land; sea air stays moist). The
## ripple lives in climate_moisture; probes pin the boost as the exact
## delta between the two calls at the same direction.
static func climate_moisture_field(d: Vector3, world_seed: PackedByteArray) -> float:
	d = d.normalized()
	var salt: int = _seed_salt(world_seed, "climate_moist")
	var m: float = 0.62 * _vnoise(d, salt, MOIST_FREQ_COARSE) + 0.38 * _vnoise(d, salt + 1, MOIST_FREQ_FINE)
	# THE SUN PANS DRY (v11): the atoll wrings the air out -- the pans
	# resolve DESERT at the core, the fade rings out through the dry
	# ladder to the wetter coast.
	m -= SUN_PANS_DRY * sun_pans_factor(d)
	var land: float = _land_mass(d, _seed_salt(world_seed, "terrain"))
	if land <= OCEAN_LAND_LINE:
		return clampf(m * 0.4 + 0.5, 0.0, 1.0)  # sea air is moist
	return clampf(m + land * 0.1, 0.0, 1.0)


## THE EROSION FIELD (the variety law's badlands gate): its OWN seed
## salt ("erosion", freq 2.0) on the independent-stream discipline:
## adding the gate never reshuffles the other fields. Range [0, 1].
static func erosion_field(d: Vector3, world_seed: PackedByteArray) -> float:
	d = d.normalized()
	var salt: int = _seed_salt(world_seed, "erosion")
	return _vnoise(d, salt, 2.0)


## THE BIOME RESOLUTION LAW. Discrete id at one direction. Order
## reads: ocean bands (the land law carries them), then the river
## channel (running water crosses every other band), then standing
## water at ANY height (the LAKE law: the GATED water surface -- the
## same basin+spawn gate the carve uses -- over the carved bed), then
## the damp shore ring, then the freeze ladder, swamp, desert, and
## the green ladder. `height`/`surface` are pre-read by the
## hydrology-aware caller; the plain path reads them itself.
static func climate_biome_at(d: Vector3, world_seed: PackedByteArray, height: float, surface: float) -> int:
	var t: float = climate_temperature(d, world_seed)
	var m: float = climate_moisture(d, world_seed)
	var land: float = _land_mass(d, _seed_salt(world_seed, "terrain"))
	# THE ROAD BRIDGE: a deck crossing reads as LAND (the deck stands
	# above the water line and the road tint paints it - no water band
	# under a solid cartway). Sector-cached, one read per direction.
	var bridge: float = road_state_at(d, world_seed).y
	# Ocean bands by the land law (deep vs shelf by depth).
	if land < OCEAN_LAND_LINE:
		if height < sea_level(world_seed) - OCEAN_DEPTH_MIN * 0.5:
			return BiomeId.OCEAN_DEEP
		return BiomeId.OCEAN_SHELF
	# River channel: running water above every other land band (the
	# bridge deck outranks it - see the road bridge law above).
	if river_channel(d, world_seed) > 0.55 and bridge <= 0.4:
		return BiomeId.RIVER
	# Standing water at ANY elevation (the lake law). The surface is
	# the GATED one (basin + spawn), so this fires only where a real
	# carved bed holds real water -- height here is the CARVED height.
	if surface - height > Hydro.BEACH_MIN and bridge <= 0.4:
		return BiomeId.LAKE
	# Damp shore ring above the waterline.
	if height < sea_level(world_seed) + 1.0:
		return BiomeId.SHORE
	# Freeze ladder (temperature bands, altitude-aware via the lapse
	# already inside temperature).
	if t < SNOWLINE_T:
		return BiomeId.ALPINE if m > 0.45 else BiomeId.TUNDRA
	if t < ALPINE_T:
		return BiomeId.ALPINE_MEADOW if m > 0.5 else BiomeId.TUNDRA
	# Wet hollows: the marsh ring -- gated-adjacent ground near the
	# water surface (the hydrology law carries the gate; see
	# climate_swamp_wetness). Bridge decks outrank the marsh too.
	if m > SWAMP_T and bridge <= 0.4 and climate_swamp_wetness(d, world_seed, height, surface) > 0.5:
		return BiomeId.SWAMP
	# THE HOMELAND PLAINS LAW (v4 extension): the boot's belt yields
	# to GRASSLAND outright once the water/freezes/swamp outrankers
	# have had their say (they returned above). The old placement
	# AFTER the green ladder only rescued jungle/savanna splits -- the
	# dry ladder (badlands/desert/steppe) resolved bare starter
	# country INSIDE the belt, so the plains read bare no matter how
	# the density asked (measured: tests/bench_site_deriv, face 18).
	if d.angle_to(SPAWN_CENTER) < HOMELAND_PLAINS_ANG:
		return BiomeId.GRASSLAND
	# THE SWING LADDER (variety): broken country -> desert -> steppe.
	# Badlands first: dry-warm rare broken country on its OWN erosion
	# gate (independent-stream discipline - adding the gate never
	# reshuffles the other fields). Then the dry warmth desert, then
	# the mild semi-arid steppe (mild + below the reachable cut).
	# THE SUN PANS CORE (v11): the atoll's pan floors resolve DESERT
	# outright -- the erosion gate keeps its hold only on the skirt,
	# so the island reads true salt pans inside a broken-country ring.
	if m < BADLANDS_M and t > BADLANDS_T and erosion_field(d, world_seed) >= EROSION_T \
			and sun_pans_factor(d) < 0.55:
		return BiomeId.BADLANDS
	if m < DRY_T and t > 0.55:
		return BiomeId.DESERT
	if m < STEPPE_M and t <= 0.55:
		return BiomeId.STEPPE  # the t-bound keeps the hot dry-mid in savanna
	# THE GREEN LADDER: jungle -> savanna -> forest/taiga -> grassland
	# (jungle = the tree band ABOVE forest heat; tropical coasts ride
	# the temperature split, not an unreachable saturation cut). The
	# savanna holds the HOT DRY-MID band only (m below its own cap -
	# the membership pin caught the m-over edge firing savanna where
	# the ladder had already crossed the jungle side).
	var warm_id: int = BiomeId.GRASSLAND
	if t > JUNGLE_T and m > SAVANNA_M:
		warm_id = BiomeId.JUNGLE
	elif t >= 0.55 and m >= DRY_T and m < SAVANNA_M:
		warm_id = BiomeId.SAVANNA
	elif m > 0.55:
		warm_id = BiomeId.FOREST if t > ALPINE_T else BiomeId.TAIGA
	# (the homeland plains yield fires ABOVE the dry ladder now: the
	# boot belt is grassland once water/freezes/swamp have had their
	# say, so no redundant rescue sits here anymore).
	return warm_id


## The SWAMP WETNESS law: the marsh RING around gated water (a band
## of waterlogged ground straddling the surface line, at ANY height,
## where the basin gate stands). Pure; the probe pins its rim law.
static func climate_swamp_wetness(d: Vector3, world_seed: PackedByteArray, height: float, surface: float) -> float:
	if surface < -1e8:
		return 0.0  # no basin support here: bone dry swampwise
	var near_shore: float = clampf(1.0 - absf(surface - height) / 1.5, 0.0, 1.0)
	return near_shore * clampf(1.0 - (height - sea_level(world_seed)) / 12.0, 0.0, 1.0)


## Convenience: the discrete biome at one direction (the plain path).
static func climate_biome_id(d: Vector3, world_seed: PackedByteArray) -> int:
	# GROUND-SAMPLE FUSION (stage 2): the biome id is a field on the fused
	# sample (the builder calls climate_biome_at with the same pre-read
	# height + surface), so this is bit-identical to the old recompute.
	return ground_sample(d.normalized(), world_seed).biome_id


## THE GATED WATER SURFACE: where standing water actually IS. The raw
## table filtered by the shared gates, with the surface FADED to the
## bed at the fill window's rim (so it joins the ground continuously
## with the carve: the biome law and the mesh layer never disagree).
## -1e9 = no standing water here.
## PERFORMANCE LAW: per-direction results cache on the QUANTIZED
## direction (same law as the height cache) -- the mesh pass asks
## this once per corner, and each call re-runs the whole water-table
## law (noise + perch + height); without the cache a level-6 patch
## re-did the work for every triangle that shares the corner. Same
## answer per quantized sector, so the law stays pure-reading.
static func hydro_water_surface(d: Vector3, world_seed: PackedByteArray) -> float:
	d = d.normalized()
	var cached = _water_surface_cache.get_value(d, world_seed)
	if cached != null:
		return float(cached)
	var gates: Vector2 = _hydro_gates(d, world_seed)
	var out: float = -1e9
	# THE DRY LAW (the rewiring): the surface SINKS into the ground by
	# max(suppress, 1 - gate) - the old guard read suppress BACKWARDS
	# (it treated suppress > 0 as "water allowed"; standing water was
	# legal ONLY inside a spawn-hugging halo). The full-dry branch
	# keeps the swamp sentinel law: outside real basin support the
	# surface reports NO water, so the marsh ring fires only inside
	# real basin support (same law, right direction).
	var dry: float = maxf(gates.y, 1.0 - gates.x)
	if dry < 0.995:
		var table: float = water_table_raw(d, world_seed)
		# THE PRE-ROAD DISCIPLINE (the stack cycle the perf-budget probe
		# cornered at 20 km): _road_build reads THIS surface to place
		# its water crossings, and this used to read the PUBLIC height
		# -- which includes the road override -- so the spec build
		# recursed through its own corridor forever. Standing water is
		# a product of the LAND, not of the cart: the read rides the
		# pre-road field (the same _noroad mode the river pathing law
		# already uses).
		var h: float = terrain_height_carved(d, world_seed, "_noroad")
		var window: float = smoothstep(0.0, Hydro.LAKE_CARVE_MAX, h - (table - Hydro.LAKE_BEDDROP))
		var surface: float = lerpf(table, h, window)
		out = lerpf(surface, h, dry)  # gate fades it into the ground
	_water_surface_cache.set_value(d, world_seed, out)  # bounds evict, never clear
	return out


## THE BIOME PALETTE (slice 2, prd-terrain.md): the albedo law. One
## color per biome id, consumed by the streamer's vertex-tint pass via
## climate_biome_weights (band edges blend, no hard rings).
static func biome_color(id: int, world_seed: PackedByteArray, d: Vector3) -> Color:
	var c: Color
	match id:
		BiomeId.OCEAN_DEEP:
			c = Color(0.16, 0.26, 0.32)
		BiomeId.OCEAN_SHELF:
			c = Color(0.30, 0.44, 0.46)
		BiomeId.SHORE:
			c = Color(0.72, 0.64, 0.45)
		BiomeId.ALPINE:
			c = Color(0.55, 0.53, 0.50)
		BiomeId.TUNDRA:
			c = Color(0.70, 0.70, 0.62)
		BiomeId.DESERT:
			c = Color(0.80, 0.68, 0.42)
		BiomeId.SWAMP:
			c = Color(0.38, 0.40, 0.24)
		BiomeId.TAIGA:
			c = Color(0.26, 0.42, 0.32)
		BiomeId.FOREST:
			c = Color(0.22, 0.45, 0.24)
		BiomeId.GRASSLAND:
			c = Color(0.40, 0.56, 0.30)
		BiomeId.ALPINE_MEADOW:
			c = Color(0.48, 0.58, 0.40)
		BiomeId.LAKE:
			c = Color(0.28, 0.37, 0.46)
		BiomeId.RIVER:
			c = Color(0.30, 0.40, 0.45)
		# THE VARIETY LAW palettes: measured band colors (deep saturated
		# green jungle, golden savanna, olive steppe, rust badlands).
		BiomeId.JUNGLE:
			c = Color(0.14, 0.38, 0.18)
		BiomeId.SAVANNA:
			c = Color(0.62, 0.55, 0.26)
		BiomeId.STEPPE:
			c = Color(0.52, 0.52, 0.32)
		BiomeId.BADLANDS:
			c = Color(0.55, 0.34, 0.26)
		_:
			c = Color(0.42, 0.42, 0.40)
	# Per-direction variation: a gentle seeded lightness wobble so
	# tiles do not read as flat paint (deterministic, no order deps).
	var salt: int = _seed_salt(world_seed, "tint_wobble")
	var w: float = (_vnoise(d.normalized(), salt, 8.0) - 0.5) * 0.10
	return Color(clampf(c.r + w, 0.0, 1.0), clampf(c.g + w, 0.0, 1.0), clampf(c.b + w, 0.0, 1.0))


## THE VERTEX COLOR LAW (slice 2 entry point for the streamer): blended
## biome palette + the slope/snow physics. `steep` is [0, 1] slope
## factor (the streamer computes it from the local height gradient);
## steep ground blends toward rock gray. The snowline rides temperature
## (not a fixed lift) EXCEPT the spawn apron (dry boot ground). Below
## the waterline everything dims (the shell paints depth through it).
## PERFORMANCE LAW: the biome BLEND (weights x palette x wobble) is
## pure per direction, so it memoizes on the quantized direction +
## seed (same law as the height cache). `steep`/`lift` stay OUT of
## the cache -- the slope rock, snowline, and wet dim blend on top of
## the memoized base, so every vertex keeps its own physics dollar.
## THE CRAG NOISE BUNDLE read: the four per-color terrain noises
## (macro tone polish, crag streak, strata wobble, fracture chatter)
## memoized per quantized direction + seed (the SectorCache law).
## Recompute 4 _vnoise calls per vertex dominated the mesh pass after
## the crag slice; the memo brings the build back inside the budget.
static func _crag_noise(d: Vector3, world_seed: PackedByteArray) -> Vector4:
	var cached = _crag_cache.get_value(d, world_seed)
	if cached is Vector4:
		return cached
	var polish_salt: int = _seed_salt(world_seed, "polish")
	var strata_salt: int = _seed_salt(world_seed, "strata")
	var out := Vector4(
		_vnoise(d, polish_salt, 2.2),
		_vnoise(d, polish_salt + 1, 7.0),
		_vnoise(d, strata_salt, 3.0),
		_vnoise(d, strata_salt + 1, 14.0))
	_crag_cache.set_value(d, world_seed, out)
	return out


static func vertex_color(d: Vector3, world_seed: PackedByteArray, lift: float, steep: float) -> Color:
	d = d.normalized()
	var gs: GroundSample = ground_sample(d, world_seed)
	# GROUND-SAMPLE FUSION (stage 2): one fused read replaces the
	# individual biome/temperature/surface/height/road/crag calls.
	# Bit-identical: the same laws, read once and reused.
	var base_c = _blend_cache.get_value(d, world_seed)
	var base: Color
	if base_c is Color:
		base = base_c
	else:
		var c0: Color = Color(0, 0, 0)
		var weights: Dictionary = gs.biome_weights
		for id in weights:
			var bc: Color = biome_color(int(id), world_seed, d)
			var w: float = float(weights[id])
			c0 = Color(c0.r + bc.r * w, c0.g + bc.g * w, c0.b + bc.b * w)
		base = c0
		_blend_cache.set_value(d, world_seed, base)  # bounds evict, never clear
	var sea: float = gs.sea
	var c: Color = base
	# THE CRAG NOISE BUNDLE (the perf-budget catch): the four per-color
	# terrain noises are pure per (direction, seed), so they share ONE
	# quantized-direction memo (the same probability the height cache
	# rides). Uncached, they cost ~3.5 ms per vertex (~4 s per level-6
	# patch build); cached, the budget pin holds. Values:
	# x = macro tone noise, y = crag streak, z = strata wobble,
	# w = fracture chatter.
	var cn: Vector4 = gs.crag
	# THE BAND READ (one per vertex): the corner's biome drives the
	# crag streaks AND the grass expression below -- one cached read
	# instead of two passes through the climate law.
	var id_check: int = gs.biome_id
	# Slope physics: steep ground reads rock (bands: shallow slopes keep
	# their biome; cliffs gray out).
	c = c.lerp(Color(0.46, 0.42, 0.38), clampf(steep * 0.75, 0.0, 1.0))
	# THE CRAG LAW (the parked style slice, finished): a steep face is
	# no longer flat paint. Two roughness signals ride the slope so
	# cliffs read craggy in EVERY biome, not only badlands/alpine:
	#   STRATA -- horizontal sediment bands: the face's lift lands in
	#   wavelength bands, jittered by low-frequency field noise so the
	#   band edges wander like real bedding planes read.
	#   FRACTURE chatter -- high-frequency tone splits along ledges:
	#   dark cracks on the roughest cuts (deep steep), light dusting
	#   near the gentler ledge bands.
	if steep > 0.05:
		# The bundle read (see _crag_noise): fume + chatter come cached.
		var fume: float = cn.z
		var band: float = absf(fposmod(lift / 3.5 + fume, 1.0) * 2.0 - 1.0)
		var strata: float = pow(band, 2.0) * smoothstep(0.05, 0.45, steep)
		c = Color(c.r * (1.0 - strata * 0.20), c.g * (1.0 - strata * 0.24), c.b * (1.0 - strata * 0.20))
		var fracture: float = smoothstep(0.62, 0.9, cn.w) * smoothstep(0.3, 0.75, steep)
		c = c.darkened(fracture * 0.30)
	# Snowline via temperature: below the freeze band, snow takes over
	# (spawn apron excepted -- the boot stays dry-green).
	var t: float = gs.temperature
	if t < SNOWLINE_T + 0.04:
		var ang_spawn: float = d.normalized().angle_to(SPAWN_CENTER)
		if ang_spawn > SPAWN_APRON_OUTER_ANG:
			var snow: float = clampf((SNOWLINE_T + 0.04 - t) / 0.08, 0.0, 1.0)
			c = c.lerp(Color(0.88, 0.90, 0.93), snow * 0.85)
	# Wet dimming below the waterline (the ocean shell paints the water
	# body; the dimmed ground reads as depth through it).
	if lift < sea - 0.2:
		c = c.darkened(0.45)
	# THE WET RING (visual polish slice 1): the ground within 1.5 m
	# UNDER any gated standing-water surface (lake rims, river banks,
	# pond edges - not just the sea ring) reads moist-darkened, fade
	# proportional. Sits AFTER the memoized blend (per-corner physics
	# stay out of the cache).
	var surf: float = gs.water_surface
	var under_g: float = surf - gs.height
	if under_g > 0.0 and under_g < 1.5:
		c = c.darkened((1.0 - under_g / 1.5) * 0.5)
	# THE SHORE FOAM + WAVE LINE (the owner's polish order): the last
	# hand-span of wet ground -- under EITHER the gated sheets (lakes,
	# rivers, ponds) or the ocean line itself -- reads a pale wash
	# band whose edge WAVES. The mask reuses the bundle's chatter
	# noise (cn.w), so the waviness costs no extra noise reads; the
	# band rides the same under-measure the wet ring just paid.
	var under: float = maxf(under_g, sea - lift if lift < sea else 0.0)
	if under > 0.0 and under < 0.45:
		var foam: float = (1.0 - under / 0.45) * 0.85 * smoothstep(0.45, 0.72, cn.w)
		c = c.lerp(Color(0.93, 0.94, 0.92), clampf(foam, 0.0, 1.0))
	# THE WATERFALL SEAM (the owner's polish order): where a river
	# fell hard, the face below the drop reads the falling water's
	# pale seam, flickered by the bundle's chatter so the streaks
	# read real instead of a painted band.
	var seam: float = waterfall_seam_at(d, world_seed)
	if seam > 0.01:
		var seam_c: float = seam * (0.55 + 0.4 * smoothstep(0.4, 0.8, cn.w))
		c = c.lerp(Color(0.88, 0.91, 0.93), clampf(seam_c, 0.0, 1.0))
	# THE GRASS EXPRESSION (the density slice's color half): the soft
	# growth bands carry a fine sparkle of dry-tuft specks -- the
	# bundle's chatter as the high-frequency mask -- with wet corners
	# skipped (the water laws own those), so meadows read lived-in
	# ground instead of flat green paint.
	if id_check == BiomeId.GRASSLAND or id_check == BiomeId.SAVANNA \
			or id_check == BiomeId.JUNGLE or id_check == BiomeId.FOREST \
			or id_check == BiomeId.TAIGA:
		if under <= 0.01:
			var tuft: float = smoothstep(0.78, 0.94, cn.w)
			c = c.lerp(Color(0.78, 0.80, 0.40), tuft * 0.30)
	# THE ROAD LAW TINT (v1): the cartway paints its material - the
	# dirt trail reads packed earth, the bridge deck reads plank wood.
	# Per-corner physics again: the road state cache answers both.
	var road_state: Vector3 = gs.road_state
	if road_state.x > 0.0 and d.angle_to(SPAWN_CENTER) >= SPAWN_APRON_OUTER_ANG:
		var road_c: Color = Color(0.50, 0.38, 0.26).lerp(Color(0.58, 0.42, 0.30), road_state.y)
		c = c.lerp(road_c, road_state.x * 0.85)
	# THE GROUND POLISH PASS (the style slice the ledger parked): a
	# wide macro tone patch so tiles never read as flat paint, plus
	# the crag streaks on broken country (badlands/alpine ridges).
	# The bundle read again: macro tone + crag streak from the cache
	# (the whole color-noise family is pure per (dir, seed) -- one
	# memo, no fresh noise per vertex pass).
	var macro: float = (cn.x - 0.5) * 0.055
	c = Color(clampf(c.r + macro, 0.0, 1.0), clampf(c.g + macro, 0.0, 1.0), clampf(c.b + macro, 0.0, 1.0))
	if id_check == BiomeId.BADLANDS or id_check == BiomeId.ALPINE:
		var crag: float = pow(1.0 - absf(2.0 * cn.y - 1.0), 1.5)
		c = c.lerp(Color(0.52, 0.48, 0.45), crag * 0.22)
	# THE COASTAL BLUFF RIDER (the crag law's sea front): any face near
	# the waterline that steepness already flagged gets the shoreline
	# treatment -- a cut-cliff gray-brown with spray-darkened feet, so
	# the sea's edges read chiseled instead of painted slope gray.
	var bluff := smoothstep(0.5, 0.8, steep) * (1.0 - smoothstep(sea + 0.5, sea + 9.0, lift))
	if lift < sea + 9.0 and bluff > 0.01:
		c = c.lerp(Color(0.42, 0.38, 0.32), bluff)
		c = c.darkened(bluff * 0.5 * (1.0 - smoothstep(sea - 0.4, sea + 1.6, lift)))
	return c


## THE TEXTURE SKIN LAW (the spike round's splat export): the SAME
## physics vertex_color reads -- the climate weights, the slope rock,
## the snowline, the wet dim, the foam band, the waterfall seam, the
## road packed-earth, the bluff shading -- exported as SPLAT WEIGHTS
## instead of a palette color, so the terrain shader blends tileable
## texture skins UNDER our law-proven bones instead of overwriting
## them. Returns {"splat": Color(grass, dirt, rock, sand)} for the
## vertex COLOR and {"aux": Vector2(snow, bright)} for UV2, where
## bright folds every post-blend dimming into ONE faithful multiplier.
## THE LAWFUL SUBSET note (honest spike ledger): the vertex-color
## micro-tones (the tuft sparkle, the macro tone polish, the tint
## wobble salt, the crag strata/fracture dimming) stay COLOR-lane
## only -- the tileable skins carry their own grain, and the receipts
## pin exactly what moved and what did not. The color law itself is
## byte-identical: the spike adds a lane, never edits the law.
## Toggle: SPLAT_SKIN (below); the streamer's skin lane reads it.
const SPLAT_SKIN := true

static func skin_classes(d: Vector3, world_seed: PackedByteArray) -> Color:
	# GROUND-SAMPLE FUSION (stage 2): the class weights ride the fused
	# sample's biome_weights (bit-identical: the same weights law).
	var s: GroundSample = ground_sample(d.normalized(), world_seed)
	return _skin_from(s.biome_weights)


## The PURE class split (the fused builder's own entry; reads no laws).
static func _skin_from(weights: Dictionary) -> Color:
	var w_grass: float = 0.0
	var w_dirt: float = 0.0
	var w_rock: float = 0.0
	var w_sand: float = 0.0
	for id in weights:
		var w: float = float(weights[id])
		match int(id):
			BiomeId.GRASSLAND, BiomeId.ALPINE_MEADOW, BiomeId.STEPPE, \
			BiomeId.JUNGLE, BiomeId.FOREST, BiomeId.TAIGA, BiomeId.SWAMP, \
			BiomeId.TUNDRA:
				w_grass += w
			BiomeId.SAVANNA:
				w_grass += w * 0.6
				w_sand += w * 0.4
			BiomeId.ALPINE, BiomeId.BADLANDS:
				w_rock += w
			BiomeId.SHORE, BiomeId.DESERT:
				w_sand += w
			BiomeId.OCEAN_DEEP, BiomeId.OCEAN_SHELF, BiomeId.LAKE, \
			BiomeId.RIVER:
				w_sand += w  # beds read sand through the water dim
			_:
				w_dirt += w
	var out := Color(clampf(w_grass, 0.0, 1.0), clampf(w_dirt, 0.0, 1.0), clampf(w_rock, 0.0, 1.0), clampf(w_sand, 0.0, 1.0))
	return out


static func splat_skin(d: Vector3, world_seed: PackedByteArray, lift: float, steep: float) -> Dictionary:
	return splat_skin_from(ground_sample(d.normalized(), world_seed), world_seed, lift, steep)


## The PURE splat law (the fused builder's own entry): reads only the
## sample's fields + world_seed (the waterfall seam) -- no laws, no memo.
## The clipmap reads this from its fused sample so one ground_sample per
## vertex serves BOTH the height and the colour.
static func splat_skin_from(gs: GroundSample, world_seed: PackedByteArray, lift: float, steep: float) -> Dictionary:
	var d: Vector3 = gs.dir
	var cls: Color = gs.skin
	var w_grass: float = cls.r
	var w_dirt: float = cls.g
	var w_rock: float = cls.b
	var w_sand: float = cls.a
	var sea: float = gs.sea
	# THE SLOPE PHYSICS: the same rock lerp factor vertex_color rides.
	var f_rock: float = clampf(steep * 0.75, 0.0, 1.0)
	w_grass *= 1.0 - f_rock
	w_dirt *= 1.0 - f_rock
	w_sand *= 1.0 - f_rock
	w_rock = w_rock + (1.0 - w_rock) * f_rock
	var aux: Vector2 = Vector2(0.0, 1.0)
	# THE SNOWLINE (same law: temperature, spawn apron dry-green).
	var t: float = gs.temperature
	if t < SNOWLINE_T + 0.04:
		var ang_spawn: float = d.normalized().angle_to(SPAWN_CENTER)
		if ang_spawn > SPAWN_APRON_OUTER_ANG:
			aux.x = clampf((SNOWLINE_T + 0.04 - t) / 0.08, 0.0, 1.0) * 0.85
	# THE DIMMING STACK (post-blend leg), folded into aux.y:
	var cn: Vector4 = gs.crag
	if lift < sea - 0.2:
		aux.y *= 0.55  # the under-shell wet dim (darkest leg)
	var surf: float = gs.water_surface
	var under_g: float = surf - gs.height
	if under_g > 0.0 and under_g < 1.5:
		aux.y *= 1.0 - (1.0 - under_g / 1.5) * 0.5  # the wet ring
	# THE SHORE FOAM + WATERFALL SEAM: both pale-white washes ride the
	# snow slot in weight space (the color law lerps them toward the
	# same pale palette the snow phase sits on).
	var under: float = maxf(under_g, sea - lift if lift < sea else 0.0)
	if under > 0.0 and under < 0.45:
		var foam: float = (1.0 - under / 0.45) * 0.85 * smoothstep(0.45, 0.72, cn.w)
		aux.x = clampf(aux.x + foam, 0.0, 1.0)
	var seam: float = waterfall_seam_at(d, world_seed)
	if seam > 0.01:
		aux.x = clampf(aux.x + seam * (0.55 + 0.4 * smoothstep(0.4, 0.8, cn.w)), 0.0, 1.0)
	# THE ROAD LAW TINT: the cartway reads packed earth (dirt skin).
	var road_state: Vector3 = gs.road_state
	if road_state.x > 0.0 and d.angle_to(SPAWN_CENTER) >= SPAWN_APRON_OUTER_ANG:
		var f_road: float = road_state.x * 0.85
		w_grass *= 1.0 - f_road
		w_rock *= 1.0 - f_road
		w_sand *= 1.0 - f_road
		w_dirt = w_dirt + (1.0 - w_dirt) * f_road
	# THE COASTAL BLUFF RIDER: sea-cut faces darken (multiply, not mix).
	var bluff2 := smoothstep(0.5, 0.8, steep) * (1.0 - smoothstep(sea + 0.5, sea + 9.0, lift))
	if lift < sea + 9.0 and bluff2 > 0.01:
		aux.y *= 1.0 - bluff2 * 0.5 * (1.0 - smoothstep(sea - 0.4, sea + 1.6, lift))
	return {
		"splat": Color(w_grass, w_dirt, w_rock, w_sand),
		"aux": aux,
	}


## BLEND WEIGHTS for rendering (slice 2): a Dictionary of biome ->
## weight (fractions, sum: within 0.03 of 1.0). Consumed by
## vertex_color below. The WEIGHTS law: primary biome carries the
## bulk; adjacent bands carry a pinch -- colors blend across band edges.
static func climate_biome_weights(d: Vector3, world_seed: PackedByteArray) -> Dictionary:
	# GROUND-SAMPLE FUSION (stage 2): read the fused sample, then the pure
	# weight ladder (bit-identical -- the sample carries the same id/t/m/h).
	var s: GroundSample = ground_sample(d.normalized(), world_seed)
	return _biome_weights_from(s.biome_id, s.temperature, s.moisture, s.height, s.sea)


## The PURE weight ladder (the fused builder's own entry; reads no laws).
static func _biome_weights_from(id: int, t: float, m: float, h: float, sea: float) -> Dictionary:
	var weights: Dictionary = {id: 1.0}
	var pinch: float = 0.12
	if id == BiomeId.GRASSLAND:
		if m > SWAMP_T - 0.08:
			weights[BiomeId.SWAMP] = pinch
			weights[id] = 1.0 - pinch
		if t > 0.55 and m < DRY_T + 0.06:
			weights[BiomeId.DESERT] = pinch
			weights[id] = 1.0 - pinch
		if h > sea + 16.0:
			weights[BiomeId.FOREST] = pinch
			weights[id] = 1.0 - pinch
	elif id == BiomeId.FOREST or id == BiomeId.TAIGA:
		weights[BiomeId.GRASSLAND] = pinch
		weights[id] = 1.0 - pinch
	elif id == BiomeId.SHORE:
		weights[BiomeId.OCEAN_SHELF] = pinch
		weights[id] = 1.0 - pinch
	# THE VARIETY PINCHES: the weights law grew the neighbor pinches so
	# the new band edges blend, not ring.
	elif id == BiomeId.JUNGLE:
		weights[BiomeId.FOREST] = pinch
		weights[id] = 1.0 - pinch
	elif id == BiomeId.SAVANNA:
		weights[BiomeId.DESERT if t > 0.62 else BiomeId.GRASSLAND] = pinch
		weights[id] = 1.0 - pinch
	elif id == BiomeId.STEPPE:
		weights[BiomeId.TUNDRA] = pinch  # the temperature-ladder pinch
		weights[id] = 1.0 - pinch
	elif id == BiomeId.BADLANDS:
		weights[BiomeId.DESERT] = pinch
		weights[id] = 1.0 - pinch
	return weights


# -- v3 HYDROLOGY (prd-terrain.md slice 3, shipped with the climate) ----

## HYDRO constants (the height independence IS the law): standing
## water may sit at ANY height; the sea is just the water table at
## elevation zero.
class Hydro:
	const MIN_TABLE_SPAN: float = 0.5  # table field resolution (m)
	const BEACH_MIN: float = 0.35      # min water depth for a beach reading
	const CARVE_MAX: float = 4.0       # max carve step (the continuity law)
	const RIVER_STEP_ANG: float = 0.02 # river walk step (radians)
	const RIVER_MAX_STEPS: int = 64
	const RIVER_RADIUS_ANG: float = 0.018
	## ESTUARY LAW: how much a sea-terminating river's capsule widens
	## at its mouth (radius multiplier at t=1). Quadratic ramp; 1.8 =
	## an 80% wider bed at the mouth (a fordable fan, not a bay).
	const ESTUARY_WIDEN: float = 1.8
	const SWAMP_GAP: float = 0.62       # film band edge (m gap = swamp grade)
	const RIVER_BED_DEPTH: float = 1.8  # channel carve depth (m)
	const TABLE_LIFT: float = 9.0       # wet-cell table lift (m)
	const TABLE_PERCH: float = 0.6      # wet tables perch up to 60% of rel. elevation
	const BASIN_T: float = 0.6          # coarse-cell basin district band [T, T+0.35)
	const LAKE_BEDDROP: float = 0.9     # bed sits this far below the table
	const LAKE_CARVE_MAX: float = 10.0  # basin press depth (continuity is the GATE's smoothness, not this cap)
	const SUPPRESS_IN: float = 0.05     # hydrology suppress near boot...
	const SUPPRESS_OUT: float = 0.075   # ...fully ON past this angle (brackets the apron only)
	const RIVER_MOIST_BOOST: float = 0.22  # moisture lift on the channel capsule (floodplain law)
	const ISLAND_FLOW_WALL: float = 40.0  # the flow law's island wall (above any river-band relief)


## The WATER TABLE: the local standing-water surface height. Pure.
## A two-octave noise field in meters, riden by moisture (wet climate
## cells hold their table high; dry cells hold it below the shelf).
## NO cover clamp: a wet film over dry ground is NOT a lake -- the
## lake band comes only from CARVED basins (the basin gate below),
## and the swamp band reads the near-zero film gap. Returns meters.
static func water_table(d: Vector3, world_seed: PackedByteArray) -> float:
	return water_table_raw(d, world_seed)


## The RAW water table (the field the carve law and the biome law
## both read; one definition, no recursion). The MOUNTAIN LAW lives
## here: wet climates PERCH their table with the terrain (up to
## TABLE_PERCH of the local relief), so high bowls can hold standing
## water at ANY elevation -- the user's law, not a sea-only trick.
## PERF: sector-memoized (read by BOTH the water-surface law and the
## lake carve at every corner; two noise octaves + moisture + perch
## per miss is the priciest non-river corner call).
static var _water_table_cache = SECTOR_CACHE.new()
static func water_table_raw(d: Vector3, world_seed: PackedByteArray) -> float:
	d = d.normalized()
	var cached = _water_table_cache.get_value(d, world_seed)
	if cached != null:
		return float(cached)
	var salt: int = _seed_salt(world_seed, "hydro_table")
	var sea: float = sea_level(world_seed)
	var base: float = _vnoise(d, salt, 2.0)
	var fine: float = 0.6 * _vnoise(d, salt + 1, 5.0)
	var raw: float = base * 0.75 + fine * 0.25
	var moist: float = climate_moisture(d, world_seed)
	var lift: float = smoothstep(DRY_T, SWAMP_T, moist) * Hydro.TABLE_LIFT
	var perch: float = smoothstep(SWAMP_T - 0.2, SWAMP_T + 0.1, moist) \
		* Hydro.TABLE_PERCH * maxf(_terrain_height_base(d, world_seed) - sea, 0.0)
	var out: float = sea - 4.0 + raw * 14.0 + lift * moist + perch
	_water_table_cache.set_value(d, world_seed, out)
	return out



## THE HYDRO GATES (the ONE definition both the carve law and the
## water-surface law read): (gate, suppress). Gate = the basin
## DISTRICT band (a bump over the coarse cell: basins are discrete
## lake districts, not a planet-wide damp). Suppress = the spawn law
## (the boot plaza + apron stay dry). Both factors continuous.
static func _hydro_gates(d: Vector3, world_seed: PackedByteArray) -> Vector2:
	d = d.normalized()
	# THE SUN PANS EXCLUSION (v11): a desert atoll holds no basins --
	# the district gate dies over the pans, so the carve never presses
	# a lake into dry ground and the standing-water law never fills
	# the salt pans.
	if sun_pans_factor(d) > 0.0:
		return Vector2(0.0, 0.0)
	# THE POLAR EXCLUSION (v12): an ice cap holds no basins either --
	# the district gate dies over the caps, so the carve never presses a
	# lake into the polar land (measured: a stray basin pressed the north
	# pole to -3.4 m, under the sea, before this).
	if _polar_cap(d) > 0.0:
		return Vector2(0.0, 0.0)
	var salt: int = _seed_salt(world_seed, "hydro_table")
	var cell: float = _vnoise(d, salt, 2.0)
	var gate: float = smoothstep(Hydro.BASIN_T, Hydro.BASIN_T + 0.05, cell) \
		* (1.0 - smoothstep(Hydro.BASIN_T + 0.25, Hydro.BASIN_T + 0.35, cell))
	# THE ALPINE DISTRICTS (the rewiring): the coarse district field is
	# chance-blobbed per seed and its gate band never landed above sea
	# on every roll - upland basins died. A NEW independent salt
	# ("hydro_basin", freq 3.0) draws the UPLAND districts, opened only
	# ABOVE the lowland press horizon (base_h > sea + CARVE_MAX - 2,
	# smoothstepped +4) and faded by the same bump rim. Lowland
	# districts and every existing lake stay untouched.
	var basin_salt: int = _seed_salt(world_seed, "hydro_basin")
	var basin_cell: float = _vnoise(d, basin_salt, 3.0)
	var upland_gate: float = smoothstep(Hydro.BASIN_T, Hydro.BASIN_T + 0.05, basin_cell) \
		* (1.0 - smoothstep(Hydro.BASIN_T + 0.25, Hydro.BASIN_T + 0.35, basin_cell))
	if upland_gate > 0.0:
		var sea: float = sea_level(world_seed)
		var base_h: float = _terrain_height_base(d, world_seed)
		upland_gate *= smoothstep(sea + Hydro.LAKE_CARVE_MAX - 2.0, sea + Hydro.LAKE_CARVE_MAX + 2.0, base_h)
	gate = maxf(gate, upland_gate)
	# The SPAWN LAW is independent of the basin gate (a river flowing
	# through the apron still has its baseline honest): suppress = 1
	# near the boot. CONSUMERS read the COMPLEMENT (carve = press *
	# gate * (1 - suppress)) - the old raw multiply squeezed all the
	# planet's standing water into a spawn-hugging halo.
	var ang_spawn: float = d.angle_to(SPAWN_CENTER)
	var suppress: float = 1.0 - smoothstep(Hydro.SUPPRESS_IN, Hydro.SUPPRESS_OUT, ang_spawn)
	# THE BELT DRY LAW (v4, the visibility raise's hydrology half): the
	# apron's dry floor extends across the whole homeland plains belt
	# (HOMELAND_PLAINS_ANG) EXCEPT the authored cove bearing -- the
	# starter country reads meadow, not marsh. Measured
	# (tests/probe_tree_law_census): face 18's centroid + 133 of face
	# 16's plantable sites stood inside the water table's fill (LAKE
	# bands) within walking distance of the boot, so the species law
	# drew nothing -- the plaza's own suppress bracket (0.05..0.075)
	# stopped short of the belt. The cove window above stays its own
	# authored sea (the vista law outranks the belt).
	var cove_w2: float = _cove_window(d)
	if cove_w2 < 0.05:
		var belt: float = 1.0 - smoothstep(HOMELAND_PLAINS_ANG * 0.9, HOMELAND_PLAINS_ANG * 1.08, ang_spawn)
		suppress = maxf(suppress, belt)
	return Vector2(gate, suppress)


## THE RIVER CHANNEL field: how deep the river bed at a direction is
## (0 outside a channel). The channel is a capsule along each river
## segment: inside RIVER_RADIUS_ANG of the segment chord, depth falls
## off smoothly from the channel floor.
## PERFORMANCE LAW: per-direction results cache on the QUANTIZED
## direction (the same law the streamer's height cache reads) -- the
## mesh pass asks ~50k corners, each a O(rivers x steps) capsule
## sweep; without the cache a level-6 patch build hung the probe
## (measured: continent walk stalled). Same answer per quantized
## sector, so the law stays pure-reading.
## NOTE: cleared together with the height cache on any backend
## install/uninstall (the channel field and the spring/path derive
## both read the ground law; a stale cache would carve rivers with
## the OLD field's heights after a seam change).
## ESTUARY LAW (S14.7): a river's capsule radius GROWS toward its
## mouth. `mouth_factor` in [0,1]: 0 = spring end, 1 = the sea-side
## endpoint where the poly terminates against the sea line -- measured
## from the SEED (terminating height), so it is pure. Lake/hollow
## termini get 0 (no estuary on dry land). Sampled from paths the
## carve pass shares, so the channel field, bed carve, and the biome
## moisture ripple all widen together.
static func river_mouth_factor(seg_dir: Vector3, world_seed: PackedByteArray) -> float:
	var sea: float = sea_level(world_seed)
	for spec in river_specs_cached(world_seed):
		var n: int = spec.path.size()
		if n < 2:
			continue
		for i in range(n - 1):
			var p0: Vector3 = spec.path[i]
			var p1: Vector3 = spec.path[i + 1]
			var seg_len: float = p0.angle_to(p1)
			if seg_len < 1e-9:
				continue
			# Slerp position along the segment; mouth moves 0 -> 1 as
			# the terminating endpoint's BASE height approaches sea.
			var end_h: float = _terrain_height_base(spec.path[n - 1], world_seed)
			var t_l: float = clampf((end_h - sea) / 4.0, 0.0, 1.0)
			# Find the domain point's position along the whole path:
			# cheap version — the point's PROXIMITY to the mouth end
			# decides the factor (angular distance to path end,
			# normalized by the path span).
			if seg_dir.angle_to(spec.path[n - 1]) < seg_len * 4.0:
				return 1.0 - t_l
	return 0.0


## THE WATERFALL SEAM LAW (the owner's polish order): where a river
## fell HARD between two path nodes (drop >= WATERFALL_MIN_DROP),
## the face below the drop reads the falling water's pale seam.
## Value = the 0..1 paint mask (0 off-river). Geometry of the mask:
## along the chord the seam is a SHORT band centered on the drop
## segment's midpoint; across it a capsule of ~2x the river radius
## (the falling sheet is wider than the bed); vertically it covers
## the face from just under the drop TOP down past the landing.
static var _waterfall_cache = SECTOR_CACHE.new()
static var WATERFALL_MIN_DROP: float = 3.0
const WATERFALL_SEAM_SPAN_K: float = 0.6   # the along-chord band (x seg len)
const WATERFALL_SEAM_WIDTH_K: float = 2.0  # across-chord width (x river radius)
static func waterfall_seam_at(d: Vector3, world_seed: PackedByteArray) -> float:
	d = d.normalized()
	var cached = _waterfall_cache.get_value(d, world_seed)
	if cached != null:
		return float(cached)
	var best: float = 0.0
	var sea: float = sea_level(world_seed)
	for spec in river_specs_cached(world_seed):
		var n: int = spec.path.size()
		if n < 2:
			continue
		for si in range(n - 1):
			var drop: float = float(spec.drops[si])
			if drop < WATERFALL_MIN_DROP:
				continue
			var p0: Vector3 = spec.path[si]
			var p1: Vector3 = spec.path[si + 1]
			var seg_len: float = maxf(1e-6, p0.angle_to(p1))
			# The tangent-plane polyline read (same approximation the
			# channel capsule's chord law rides): project d onto the
			# segment frame, clamp along, weigh the perpendicular.
			var axis: Vector3 = (p1 - p0).normalized()
			var r: Vector3 = d - p0
			var along: float = r.dot(axis)
			var perp: float = (r - axis * along).length()
			var top_h: float = _terrain_height_base(p0, world_seed)
			var bottom_h: float = top_h - drop * 0.8
			var reach_ang: float = seg_len * WATERFALL_SEAM_SPAN_K
			var half_spread: float = (Hydro.RIVER_RADIUS_ANG if Hydro.RIVER_RADIUS_ANG > 0.0 else 0.004) * WATERFALL_SEAM_WIDTH_K
			var horiz: float = clampf(1.0 - (absf(along - seg_len * 0.5) / maxf(reach_ang, 1e-5)), 0.0, 1.0) \
					* clampf(1.0 - perp / maxf(half_spread, 1e-5), 0.0, 1.0)
			var lift: float = terrain_height(d, world_seed)
			var band: float = smoothstep(bottom_h - 1.0, bottom_h + 1.0, lift) \
					* (1.0 - smoothstep(top_h - 0.5, top_h + 0.3, lift))
			var mask: float = clampf(horiz * band, 0.0, 1.0) * smoothstep(WATERFALL_MIN_DROP, WATERFALL_MIN_DROP + 3.0, drop)
			best = maxf(best, mask)
	_waterfall_cache.set_value(d, world_seed, minf(best, 1.0))
	return minf(best, 1.0)


static func river_channel(d: Vector3, world_seed: PackedByteArray) -> float:
	d = d.normalized()
	# Seed-tagged in the shared key law: different world seeds never
	# share a bucket (the untagged key read foreign specs' channels in
	# multi-seed callers).
	var cached = _channel_cache.get_value(d, world_seed)
	if cached != null:
		return float(cached)
	var best: float = 0.0
	var d_n: Vector3 = d
	var sea: float = sea_level(world_seed)
	for spec in river_specs_cached(world_seed):
		# PHY: the river's terminating BASE height decides the estuary:
		# sea-terminating poly = widen-to-mouth, otherwise constant.
		var end_h: float = _terrain_height_base(spec.path[spec.path.size() - 1], world_seed)
		var estuary_x: float = 0.0 if end_h > sea else 1.0
		var n: int = spec.path.size()
		for i in range(spec.path.size() - 1):
			var p0: Vector3 = spec.path[i]
			var p1: Vector3 = spec.path[i + 1]
			# Capsule test: min angle from d_n to the segment chord.
			var seg_len: float = p0.angle_to(p1)
			if seg_len < 1e-9:
				var ang: float = d_n.angle_to(p0)
				if ang < Hydro.RIVER_RADIUS_ANG:
					best = maxf(best, 1.0 - ang / Hydro.RIVER_RADIUS_ANG)
				continue
			# Slerp the chord: sample a few interior directions (a capsule
			# via direction-space samples, exact enough for a soft field).
			for si in range(1, 4):
				var t: float = float(si) / 4.0
				var axis: Vector3 = p0.cross(p1)
				if axis.length() < 1e-9:
					continue
				var mid: Vector3 = p0.rotated(axis.normalized(), seg_len * t).normalized()
				# ESTUARY: the radius at this sample grows toward the
				# mouth (t goes 0 spring-side -> 1 mouth-side along the
				# segment). i/(n-1) anchors the segment near the mouth.
				var mouth_t: float = clampf((float(i) + t) / maxf(float(n - 1), 1.0), 0.0, 1.0)
				var rad: float = Hydro.RIVER_RADIUS_ANG * (1.0 + Hydro.ESTUARY_WIDEN \
					* estuary_x * mouth_t * mouth_t)
				var ang2: float = d_n.angle_to(mid)
				if ang2 < rad:
					best = maxf(best, 1.0 - ang2 / rad)
		# Endpoints matter: the spring head + the mouth also carry a
		# round channel (the chord test above reads in-between samples
		# but a capsule END needs the endpoint disk).
		for ei in [0, spec.path.size() - 1]:
			var p: Vector3 = spec.path[ei]
			var pt: float = float(ei) / maxf(float(n - 1), 1.0)
			var rad_p: float = Hydro.RIVER_RADIUS_ANG * (1.0 + Hydro.ESTUARY_WIDEN \
				* estuary_x * pt * pt)
			var ang3: float = d_n.angle_to(p)
			if ang3 < rad_p:
				best = maxf(best, 1.0 - ang3 / rad_p)
	var out: float = clampf(best, 0.0, 1.0)
	_channel_cache.set_value(d, world_seed, out)  # bounds evict, never clear
	return out## The spring/path cache: one derive per process (deterministic). The
## carve and the channel field both read ONLY this cache.


static func river_specs_cached(world_seed: PackedByteArray) -> Array:
	var key: String = world_seed.hex_encode()
	var cached = _river_spec_cache.get_value(key)
	if cached != null:
		return cached
	var specs: Array = river_specs(world_seed)
	_river_spec_cache.set_value(key, specs)
	return specs


## PRIME seam: the boot must call this ONCE before any terrain height
## read (the hydrology carve reads springs/paths). Cheap (24 springs,
## 64 steps each). Returns the prime count for probes.
static func hydrology_prime(world_seed: PackedByteArray) -> int:
	var springs: Array = river_springs(world_seed)
	var key: String = world_seed.hex_encode()
	var filtered: Array = springs.filter(func(s): return s.path.size() >= 2)
	_river_spec_cache.set_value(key, filtered)
	return springs.size()


## Carved height law: terrain, then lakes/basins, then river channels.
## mode "_raw" = river carving ONLY (the flow law reads no lakes to
## avoid recursion); plain mode = full v3 law (lakes + channels).
static func terrain_height_carved(d: Vector3, world_seed: PackedByteArray, mode: String = "") -> float:
	# LANE-H2: the default mode is a pure per-(dir sector, seed) law, so
	# the whole carved result memoizes (not just the base field). Non-
	# default modes keep the original uncached path below.
	if mode == "":
		var ckey_dir: Vector3 = d.normalized()
		var cchit = _carved_cache.get_value(ckey_dir, world_seed)
		if cchit != null:
			return float(cchit)
		var ch: float = _terrain_height_carved_uncached(ckey_dir, world_seed, mode)
		_carved_cache.set_value(ckey_dir, world_seed, ch)
		return ch
	return _terrain_height_carved_uncached(d, world_seed, mode)


static func _terrain_height_carved_uncached(d: Vector3, world_seed: PackedByteArray, mode: String) -> float:
	var h: float = _terrain_height_base(d, world_seed)
	if mode != "_raw":
		h = hydro_lake_carve(d, world_seed, h)
	var channel: float = river_channel(d, world_seed)
	if channel > 0.0:
		var bed: float = minf(h - Hydro.RIVER_BED_DEPTH * channel, water_table_raw(d, world_seed) - 0.3)
		h = lerpf(h, bed, channel)
	# THE ROAD LAW (v1): the cart path owns its corridor - a smoothed
	# walk bed on land, a solid bridge deck over every water crossing
	# (the deck stands ABOVE the water line, never submerged). The
	# corridor fade keeps the 4 m walk-bound honest. "_noroad" serves
	# the pre-road field (the pathing law reads it - no cycle);
	# "_raw" is unchanged (river carving only).
	if mode != "_raw" and mode != "_noroad":
		h = road_height_override(d, world_seed, h)
	return h


## The basin-carrying height component of standing water: press the
## bed toward (table - LAKE_BEDDROP). All gates live in the ONE shared
## definition (_hydro_gates) - the private pre-gate was removed (its
## smoothstep early-exit BEFORE reading the shared gates violated the
## one-definition law and starved every upland basin dry).
## THE BOWL LAW: the press COMPLETES the bowl - press = min(gap,
## reach); the reach scales with max(perched table, terrain altitude)
## (alpine bowls dig to their own scale; flatlands keep the flat
## pair). Continuity is the gate's smoothstep fades, never the cap -
## the 4 m walk-bound check still passes.
## THE SPAWN DIRECTION: the carve reads the COMPLEMENT of the
## suppress factor (the old raw multiply was the backwards halo).
## THE ISLAND SHIELD: seed-dependent carves yield to the island
## volcanic tier, faded across the ramp edge - the island top is
## exact under ANY seed (W5), banks/probe channels unaffected.
static func hydro_lake_carve(d: Vector3, world_seed: PackedByteArray, h: float) -> float:
	d = d.normalized()
	var gates: Vector2 = _hydro_gates(d, world_seed)
	if gates.x <= 0.0:
		return h
	var table: float = water_table_raw(d, world_seed)
	var bed_target: float = table - Hydro.LAKE_BEDDROP
	var gap: float = h - bed_target
	if gap <= 0.0:
		return h
	var sea: float = sea_level(world_seed)
	var perched: float = maxf(table - sea, 0.0)
	var reach: float = maxf(Hydro.LAKE_CARVE_MAX, maxf(perched, h - sea))
	var press: float = minf(gap, reach)
	var carve: float = press * gates.x * (1.0 - gates.y) * (1.0 - _island_shape(d))
	return h - carve


## The v2 height law, kept bit-identical as _terrain_height_base.
static func terrain_height(dir: Vector3, world_seed: PackedByteArray) -> float:
	return terrain_height_carved(dir, world_seed, "")


## A river's spec: one carved polyline per spring.
class RiverSpec:
	var spring: Vector3
	var path: PackedVector3Array  # unit dirs, spring -> sea/lake
	## THE DROP TRACKING (the waterfall seam law): per segment's base
	## height fall (meters, positive downhill). Zero = a gentle reach;
	## a DROP (>= WATERFALL_MIN_DROP) marks a waterfall seam.
	var drops: PackedFloat32Array = PackedFloat32Array()


## SPRINGS: seed-derived river sources. One per land noise cell (the
## coarse moisture grid). Pure: same seed, same springs everywhere.
## IMPORTANT: springs/pathing read the BASE heightfield only (the
## carve law reads THEM -- no cycle back).
static func river_springs(world_seed: PackedByteArray) -> Array:
	var salt: int = _seed_salt(world_seed, "hydro_springs")
	var out: Array = []
	for i in range(24):
		var acc: int = salt
		acc = (acc * 131 + i) % 9007199254740991
		var rng := RandomNumberGenerator.new()
		rng.seed = acc
		# A random unit direction per spring (deterministic stream).
		var d: Vector3 = Vector3(rng.randf() * 2.0 - 1.0, rng.randf() * 2.0 - 1.0, rng.randf() * 2.0 - 1.0)
		if d.length() < 0.001:
			continue
		d = d.normalized()
		# Springs are LAND law only: air-starts die here.
		# THE SPRING REDRAW: a blind draw starves thin-land seeds (the
		# census fell to 1 river on the recalibrated ocean planet), so
		# sea/air draws RE-DRAW the same bounded way the rock specs
		# re-draw spawn-adjacent dirs. Deterministic (one rng stream):
		# same seed, same redraws on every machine. At most 8 redraws,
		# then this spring dies as before.
		var sea: float = sea_level(world_seed)
		var land: float = _land_mass(d, _seed_salt(world_seed, "terrain"))
		var h: float = _terrain_height_base(d, world_seed)
		for _try in range(8):
			if land >= 0.3 and h > sea:
				break
			var d_new: Vector3 = Vector3(rng.randf() * 2.0 - 1.0, rng.randf() * 2.0 - 1.0, rng.randf() * 2.0 - 1.0)
			if d_new.length() < 0.001:
				continue
			d = d_new.normalized()
			land = _land_mass(d, _seed_salt(world_seed, "terrain"))
			h = _terrain_height_base(d, world_seed)
		if land < 0.3 or h < sea:
			continue
		var spec := RiverSpec.new()
		spec.spring = d
		spec.path = river_path(d, world_seed)
		# THE DROP TRACKING: per segment's base fall, measured from the
		# path itself (the river law's own read). Computed at spec
		# build so every waterfall scan pays O(segments) dict reads,
		# not the full base-height re-derivation per corner.
		var nn: int = spec.path.size()
		spec.drops.resize(nn - 1)
		for si in range(nn - 1):
			spec.drops[si] = _terrain_height_base(spec.path[si], world_seed) \
				- _terrain_height_base(spec.path[si + 1], world_seed)
		out.append(spec)
	return out


## THE RIVER FLOW LAW: greedy steepest descent (deterministic ties by
## spring direction's own axes), max RIVER_MAX_STEPS steps of
## RIVER_STEP_ANG, until the sea or a deep table basin. Pure.
static func river_path(spring: Vector3, world_seed: PackedByteArray) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array([spring.normalized()])
	var cur: Vector3 = spring.normalized()
	var sea: float = sea_level(world_seed)
	for _step in range(Hydro.RIVER_MAX_STEPS):
		var best_dir: Vector3 = Vector3.ZERO
		var best_h: float = 1e9
		# Tangent frame around cur (deterministic: built from cur).
		var hint: Vector3 = Vector3(0, 1, 0) if absf(cur.dot(Vector3(0, 1, 0))) < 0.9 else Vector3(1, 0, 0)
		var t1: Vector3 = cur.cross(hint).normalized()
		var t2: Vector3 = cur.cross(t1).normalized()
		for k in range(8):
			var ang: float = TAU * float(k) / 8.0
			# Tangent ring around cur at RIVER_STEP_ANG: candidates sit
			# along the LOCAL surface tangent (great-circle sense), so the
			# ring is real directions on the sphere, not stretched chords
			# of (cur + tan) sums.
			var tangent: Vector3 = t1 * cos(ang) + t2 * sin(ang)
			var rot_axis: Vector3 = tangent.cross(cur)
			if rot_axis.length() <= 1e-9:
				rot_axis = t1
			var cand: Vector3 = cur.rotated(rot_axis.normalized(), Hydro.RIVER_STEP_ANG).normalized()
			# THE ISLAND SHIELD (pathing side): the volcanic island is a
			# WALL to the flow law - each candidate's cost carries the
			# tier's relief so greedy rivers ROUTE around it instead of
			# biting the plateau top under any seed. Banks/probe
			# channels are unaffected (the shield is island-local).
			var cand_raw: float = _terrain_height_base(cand, world_seed)
			var hh: float = cand_raw + Hydro.ISLAND_FLOW_WALL * _island_shape(cand)
			if hh < best_h:
				best_h = hh
				best_dir = cand
		# Kill: reached the sea.
		if best_h <= sea + 0.2 or best_dir.is_zero_approx():
			if not best_dir.is_zero_approx():
				out.append(best_dir)
			return out
		# HOLLOW LAW: no downhill step left => the river ENDS here (it
		# feeds a hollow -- a pond, a marsh, a basin lake). Greedy rivers
		# never climb: taking an uphill best-candidate was the bug the
		# probe caught (a 1.17 m up-step on a ridge crest).
		if best_h >= _terrain_height_base(cur, world_seed) - 0.05:
			return out
		cur = best_dir
		out.append(cur)
	return out


## The CLEARANCE law (probe-pin helper): does a river REALLY run
## downhill, step by step, and terminate? Strict L1 check. Reads the
## PRE-ROAD field (_noroad): the hydraulic truth is the river's own
## carve - a road deck or a graded bank landing on the channel is a
## structure OVER the water, not the water's law.
static func river_goes_downhill(path: PackedVector3Array, world_seed: PackedByteArray) -> float:
	var worst: float = 0.0
	for i in range(path.size() - 1):
		var h0: float = terrain_height_carved(path[i], world_seed, "_noroad")
		var h1: float = terrain_height_carved(path[i + 1], world_seed, "_noroad")
		worst = maxf(worst, h1 - h0)  # punish any up-step
	return worst  # <= ~0 means strictly downhill (within noise)


## Rivers that exist (specs with path length >= 2, land-legal).
## The streamer carves the bed + raises the local table by these in
## slice 3's render pass; the LAW already carries them as data.
static func river_specs(world_seed: PackedByteArray) -> Array:
	var out: Array = []
	for spec in river_springs(world_seed):
		if spec.path.size() >= 2:
			out.append(spec)
	return out


## Height (meters above the base surface) of the rock cap at world
## direction `dir`, or 0.0 when no rock sits there. Smoothstep cap
## (zero slope at edge and top), MAX across overlapping caps -- max of
## continuous functions is continuous; a first-match return would
## jump where two caps overlap (test-caught lesson).
static func rock_top_height(dir: Vector3, world_seed: PackedByteArray, face: int, base_radius: float) -> float:
	var specs: Array = rock_specs(world_seed, face)
	var d: Vector3 = dir.normalized()
	var best: float = 0.0
	for s in specs:
		var angular_radius: float = (ROCK_RADIUS * s.scale * 0.9) / base_radius
		var ang: float = d.angle_to(s.dir)
		if ang < angular_radius:
			var frac: float = 1.0 - pow(ang / angular_radius, 2.0)
			var h: float = (ROCK_EMBED + ROCK_RADIUS * s.scale) * smoothstep(0.0, 1.0, frac)
			if h > best:
				best = h
	return best


## THE WALK LAW: the height the radial snap rides. Terrain (when the
## heightfield is on -- planet scale) plus small-rock walk-over caps.
## Boulders are deliberately absent: they block (colliders), and the
## climb law's mantle raycast reads their tops from the colliders.
static func walk_height(dir: Vector3, world_seed: PackedByteArray, face: int, base_radius: float, terrain_on: bool) -> float:
	var h: float = 0.0
	if terrain_on:
		h = terrain_height(dir, world_seed)
	return h + rock_top_height(dir, world_seed, face, base_radius)


# -- THE RIVER FLOW LAW (the current slice, v1) -------------------------

## Rivers RUN: water moves spring -> mouth through every channel
## capsule, and standing water (lakes, ponds) drifts toward its
## outlet. The flow is PURE derived data riding the carved river
## specs (no per-tick state); the movement laws (the wade band, the
## swim driver, the water mounts) apply it as positional drift or a
## speed tax per their own profile. All heights/turns stay in the
## planar-tangent frame (no radial component - the water stays in
## its bed).

## The flow profile: full channel pull on the spring side, eased in
## the estuary (the mouth fans wide - the current dies there).
const RIVER_FLOW_BASE: float = 2.4      # m/s channel cruise
const RIVER_FLOW_MOUTH_EASE: float = 0.6
const LAKE_DRIFT_SPEED: float = 0.35    # m/s standing-water drift

static var _flow_cache = SECTOR_CACHE.new()
static var _drift_cache = SECTOR_CACHE.new()


## THE LOCAL FLOW DIRECTION (unit tangent, mouth-ward) at a
## direction. Zero vector off every channel.
static func river_flow_at(d: Vector3, world_seed: PackedByteArray) -> Vector3:
	d = d.normalized()
	var cached = _flow_cache.get_value(d, world_seed)
	if cached != null:
		return cached
	var best: float = 0.0
	var flow: Vector3 = Vector3.ZERO
	for spec in river_specs_cached(world_seed):
		var n: int = spec.path.size()
		for i in range(n - 1):
			var p0: Vector3 = spec.path[i]
			var p1: Vector3 = spec.path[i + 1]
			var seg_len: float = p0.angle_to(p1)
			if seg_len < 1e-9:
				continue
			var axis: Vector3 = p0.cross(p1).normalized()
			for si in range(1, 4):
				var t: float = float(si) / 4.0
				var mid: Vector3 = p0.rotated(axis, seg_len * t).normalized()
				var ang: float = d.angle_to(mid)
				if ang < Hydro.RIVER_RADIUS_ANG:
					var w: float = 1.0 - ang / Hydro.RIVER_RADIUS_ANG
					if w > best:
						best = w
						# The rotation derivative along p0 -> p1: the
						# tangent poised mouth-ward (axis x mid).
						flow = axis.cross(mid).normalized()
		# The spring head: no upstream segment sits there, so the head
		# disk carries the FIRST segment's tangent.
		if n > 1:
			var head: Vector3 = spec.path[0]
			var ang_head: float = d.angle_to(head)
			if ang_head < Hydro.RIVER_RADIUS_ANG \
					and 1.0 - ang_head / Hydro.RIVER_RADIUS_ANG > best:
				best = 1.0 - ang_head / Hydro.RIVER_RADIUS_ANG
				flow = head.cross(spec.path[1]).normalized()
	_flow_cache.set_value(d, world_seed, flow)  # bounds evict, never clear
	return flow


## THE FLOW SPEED (m/s) at a direction: the channel's pull, eased in
## the estuary. Zero off-channel.
static func river_flow_speed(d: Vector3, world_seed: PackedByteArray) -> float:
	d = d.normalized()
	var c: float = river_channel(d, world_seed)
	if c <= 0.0:
		return 0.0
	var mouth: float = river_mouth_factor(d, world_seed)
	return RIVER_FLOW_BASE * (1.0 - RIVER_FLOW_MOUTH_EASE * mouth)


## THE STANDING-WATER DRIFT: lakes and ponds drift TOWARD their
## outlet - the deepest rim direction of a small ring walk, applied
## at a slow stroll. Zero on dry ground and in the channel core (the
## river's own pull owns the river there).
static func water_drift_at(d: Vector3, world_seed: PackedByteArray) -> Vector3:
	d = d.normalized()
	var cached = _drift_cache.get_value(d, world_seed)
	if cached != null:
		return cached
	var out: Vector3 = Vector3.ZERO
	var surface: float = hydro_water_surface(d, world_seed)
	var h: float = terrain_height(d, world_seed)
	if surface - h > Hydro.BEACH_MIN:
		var c: float = river_channel(d, world_seed)
		if c > 0.4:
			out = river_flow_at(d, world_seed) * river_flow_speed(d, world_seed)
		else:
			# A small tangent-plane ring walk: the deepest neighbor
			# decides the outlet direction (the drift follows it).
			var frame: Vector3 = Vector3(0, 1, 0) if absf(d.dot(Vector3(0, 1, 0))) < 0.9 else Vector3(1, 0, 0)
			var t1: Vector3 = d.cross(frame).normalized()
			var t2: Vector3 = d.cross(t1).normalized()
			var deep: Vector3 = Vector3.ZERO
			var deep_h: float = h
			for k in range(4):
				var ang: float = TAU * float(k) / 4.0
				var rot_axis: Vector3 = t1 * cos(ang) + t2 * sin(ang)
				var cand: Vector3 = d.rotated(rot_axis, 0.003).normalized()
				var ch: float = terrain_height(cand, world_seed)
				if ch < deep_h:
					deep_h = ch
					deep = cand
			if not deep.is_zero_approx():
				var tangent: Vector3 = deep - d
				tangent = (tangent - d * tangent.dot(d)).normalized()
				out = tangent * LAKE_DRIFT_SPEED
	_drift_cache.set_value(d, world_seed, out)  # bounds evict, never clear
	return out


# -- THE ROAD LAW (v1: the village -> capitol cart path) ----------------

## An auto-generated cart road from the village harbor to the capitol
## plaza: a seeded cross-country meander that prefers flat land and
## river/lake crossings (every crossing gets a solid bridge deck),
## carving a smooth walkable bed through its corridor. Same seed
## discipline as every other law: pure, deterministic, data-first.

## The road kind ids (the RoadData schema carries the data-driven
## materials; the law carries the built-in palette defaults).
class RoadKind:
	const TRAIL: int = 0         # packed earth trail
	const COBBLE: int = 1        # cobblestone highway

const ROAD_STEP_ANG: float = 0.004        # 80 m segments at the 20 km planet
const ROAD_ANG: float = 0.010             # the corridor half-width (~200 m)
const ROAD_CLEAR_ANG: float = 0.030       # the respect belt (~600 m: spawns/aggro keep off)
const ROAD_BRIDGE_DECK: float = 1.2       # deck sits this far above the local waterline
const ROAD_CUT_MAX: float = 12.0          # max bed cut below the natural terrain
const ROAD_MAX_STEPS: int = 320
const ROAD_TURN_SPAN: int = 9             # aim-cone breadth (odd)

static var _road_spec_cache = LRU_CACHE.new(4)
# TWO state caches: the corridor probe and the respect belt probe ask
# DIFFERENT radii over the same keys - one shared cache would serve
# whichever radius ran first (a law break, caught at design time).
static var _road_state_cache = SECTOR_CACHE.new()
static var _road_clear_cache = SECTOR_CACHE.new()


## A built road: the meander polyline + per-node walk surface
## (bed or deck) + per-node deck weight (0 = open road bed, 1 = bridge).
class RoadSpec:
	var kind: int = RoadKind.TRAIL
	var path: PackedVector3Array
	var beds: PackedFloat32Array   # meters above the base surface, per node
	var bridges: PackedFloat32Array


## THE VILLAGE HARBOR: the mainland rim of the authored strait (the
## settlement that owns the ferry crossing). Sits on the boot side of
## the moat band, at the island's bearing.
static func village_harbor_dir() -> Vector3:
	var isl: Vector3 = ISLAND_CENTER.normalized()
	return isl.rotated(Vector3(0, 1, 0), -(ISLAND_MOAT_OUTER + ISLAND_ANGULAR_REACH + 0.004)).normalized()


## THE CAPITOL PLAZA: the opposite bearing at the same range - the
## far coast of the starter continent (a real cart journey across
## the homeland, up to the road law to route it).
static func capitol_plaza_dir() -> Vector3:
	return capitol_dir()


static func road_spec_cached(world_seed: PackedByteArray) -> RoadSpec:
	var key: String = world_seed.hex_encode()
	var cached = _road_spec_cache.get_value(key)
	if cached != null:
		return cached
	var spec: RoadSpec = _road_build(world_seed)
	_road_spec_cache.set_value(key, spec)
	return spec


## THE ROAD PATH LAW: greedy aim-cone walk on the pre-road field,
## costed by water (bridges cost; sea is impossible for a cart), by
## slope (roads bend for passes), by a seeded meander (organic
## curves), and by turn economy (no zigzag). Two rotational
## smoothing passes follow, then the bed/deck law grades each node.
static func _road_build(world_seed: PackedByteArray) -> RoadSpec:
	var sea: float = sea_level(world_seed)
	var meadow_salt: int = _seed_salt(world_seed, "road_meadow")
	var village: Vector3 = village_harbor_dir()
	var capitol: Vector3 = capitol_plaza_dir()
	var path: PackedVector3Array = PackedVector3Array([village])
	var cur: Vector3 = village
	var prev_ang: float = 0.0
	for step in range(ROAD_MAX_STEPS):
		if cur.angle_to(capitol) < ROAD_STEP_ANG * 1.4:
			break
		# The aim cone: the capitol bearing plus span/2 offsets.
		var aim_axis: Vector3 = cur.cross(capitol)
		if aim_axis.length() < 1e-9:
			aim_axis = Vector3(0, 1, 0)
		aim_axis = aim_axis.normalized()
		var prev_h: float = _terrain_height_base(cur, world_seed)
		var best_cost: float = 1e18
		var best_dir: Vector3 = Vector3.ZERO
		var best_ang: float = 0.0
		var mid: float = float(ROAD_TURN_SPAN - 1) / 2.0
		for jj in range(ROAD_TURN_SPAN):
			var ang: float = (float(jj) - mid) * ROAD_STEP_ANG * 0.45
			var cand: Vector3 = cur.rotated(aim_axis.rotated(cur, ang).normalized(), ROAD_STEP_ANG).normalized()
			var ch: float = _terrain_height_base(cand, world_seed)
			var cost: float = absf(ang - prev_ang) * 4.0
			cost += absf(ch - prev_h) * 1.5
			cost += river_channel(cand, world_seed) * 22.0
			var surf: float = hydro_water_surface(cand, world_seed)
			if surf - ch > 0.4:
				cost += 26.0
			if ch < sea - 0.5:
				cost += 4000.0  # a cart road never fords the sea (the ferry owns it)
			# THE BOOT RING: the road bends around the spawn plaza ring
		# (the plaza + apron laws outrank the cartway; traveling lands
		# right past it either way).
			if cand.angle_to(SPAWN_CENTER) < SPAWN_APRON_OUTER_ANG:
				cost += 220.0
			cost += _vnoise(cand, meadow_salt, 9.0) * 2.2
			if cost < best_cost:
				best_cost = cost
				best_dir = cand
				best_ang = ang
		if best_dir.is_zero_approx():
			break
		cur = best_dir
		prev_ang = best_ang
		path.append(cur)
	path.append(capitol)

	# Rotational smoothing: two passes of geodesic midpoints (no zigzag).
	for _pass in range(2):
		var smooth_path: PackedVector3Array = PackedVector3Array([path[0]])
		for i in range(1, path.size() - 1):
			var m: Vector3 = (path[i - 1] + path[i + 1]).normalized()
			smooth_path.append(m.normalized())
		smooth_path.append(path[path.size() - 1])
		path = smooth_path

	# THE BED LAW: per-node walk surface graded under the continuity
	# bound (80 m step law: 16 m/step cap at the 0.2 m/m ramp grade).
	var spec := RoadSpec.new()
	spec.path = path
	var n: int = path.size()
	var beds := PackedFloat32Array()
	for i in range(n):
		var raw: float = terrain_height_carved(path[i], world_seed, "_noroad")
		beds.append(raw)
	for _pass in range(3):
		for i in range(1, n - 1):
			beds[i] = (beds[i - 1] + beds[i] * 2.0 + beds[i + 1]) / 4.0
	# THE CUT LAW first: the bed never trenches deeper than
	# ROAD_CUT_MAX under the natural terrain (the road bends for
	# passes instead of cutting canyons).
	# THE CAUSEWAY FLOOR: a wet node (came through a coastal dip) sits
	# dry above the waterline - the embankment law washes away the
	# flood of a greedy wander (should be rare: the sea cost bends the
	# path for the mountain pass instead).
	for i in range(n):
		var natural: float = terrain_height_carved(path[i], world_seed, "_noroad")
		beds[i] = maxf(beds[i], natural - ROAD_CUT_MAX)
		if natural < sea - 0.2:
			beds[i] = maxf(beds[i], sea + 0.4)
	# THE DECK LAW before the final grade: bridges stand above the
	# waterline; their approach ramps ride the graded bank heights.
	var bridges := PackedFloat32Array()
	var deck_pins := PackedFloat32Array()
	for i in range(n):
		var node_bed: float = beds[i]
		var channel_w: float = river_channel(path[i], world_seed)
		var surf: float = hydro_water_surface(path[i], world_seed)
		var bridge: float = maxf(smoothstep(0.15, 0.45, channel_w), smoothstep(0.15, 0.5, surf - node_bed))
		if bridge > 0.0:
			var riverline: float = node_bed + Hydro.RIVER_BED_DEPTH
			if surf > -1e8:
				riverline = surf
			var deck: float = maxf(node_bed, riverline - 0.3 + ROAD_BRIDGE_DECK)
			node_bed = lerpf(node_bed, deck, bridge)
		beds[i] = node_bed
		deck_pins.append(bridge)
	# THE GRADE CLAMP (final): pull overshoots back onto the walk
	# bound. Deck-pinned nodes never get pulled DOWN below their deck
	# (the walk law pins the plank above the waterline) - the approach
	# banks do the yielding toward the deck there. Running the clamp
	# after the cut AND deck laws is the order the probe caught: the
	# earlier orders re-introduced the breaks they had ironed out.
	for _pass in range(64):
		var worst: float = 0.0
		for i in range(n - 1):
			var gap: float = beds[i + 1] - beds[i]
			if absf(gap) > 15.0:
				worst = maxf(worst, absf(gap))
				var fix: float = absf(gap) - 15.0
				if gap > 0.0:
					# beds[i+1] is the high side: lower it unless pinned
					if deck_pins[i + 1] <= 0.4:
						beds[i + 1] -= fix
						beds[i] += fix
					else:
						beds[i] += fix
				else:
					if deck_pins[i] <= 0.4:
						beds[i] -= fix
						beds[i + 1] += fix
					else:
						beds[i + 1] += fix
		if worst == 0.0:
			break
	spec.beds = beds
	spec.bridges = deck_pins
	spec.path = path
	return spec


## The corridor probe: (road weight, deck weight, walk surface) at a
## direction from a membership radius. Cached per quantized sector.
static func _road_probe(d: Vector3, world_seed: PackedByteArray, ang_radius: float) -> Vector3:
	d = d.normalized()
	var cache = _road_state_cache if ang_radius == ROAD_ANG else _road_clear_cache
	var cached = cache.get_value(d, world_seed)
	if cached != null:
		return cached
	var spec: RoadSpec = road_spec_cached(world_seed)
	var w: float = 0.0
	var br: float = 0.0
	var bed: float = 0.0
	var n: int = spec.path.size()
	for i in range(n):
		var p: Vector3 = spec.path[i]
		var ang: float = d.angle_to(p)
		if ang < ang_radius:
			var node_w: float = 1.0 - ang / ang_radius
			if node_w > w:
				w = node_w
				br = spec.bridges[i]
				bed = spec.beds[i]
		if i + 1 < n:
			var p1: Vector3 = spec.path[i + 1]
			var seg_len: float = p.angle_to(p1)
			if seg_len >= 1e-9:
				var axis: Vector3 = p.cross(p1).normalized()
				for si in range(1, 3):
					var mid: Vector3 = p.rotated(axis, seg_len * (float(si) / 3.0)).normalized()
					var ang2: float = d.angle_to(mid)
					if ang2 < ang_radius:
						var w2: float = 1.0 - ang2 / ang_radius
						if w2 > w:
							w = w2
							br = maxf(spec.bridges[i], spec.bridges[i + 1])
							bed = maxf(spec.beds[i], spec.beds[i + 1])
	var st: Vector3 = Vector3(clampf(w, 0.0, 1.0), clampf(br, 0.0, 1.0), bed)
	cache.set_value(d, world_seed, st)
	return st


## THE ROAD STATE at a direction: (corridor weight, deck weight, the
## walk surface - bed or deck height). Zero/zero/0 outside the road.
static func road_state_at(d: Vector3, world_seed: PackedByteArray) -> Vector3:
	var st: Vector3 = _road_probe(d, world_seed, ROAD_ANG)
	if st.x > 0.0:
		# THE ISLAND SHIELD (the W5 law): the volcanic tier outranks
		# the cartway -- the corridor weight fades across the seat's
		# ramp edge, so the island top reads EXACTLY sea+2+ISLAND_
		# PLATEAU under any seed. The same complement law the hydro
		# carve's shield uses; a road brushing the ring-band country
		# behind the seat never regrades the ferry plateau.
		st.x *= 1.0 - _island_shape(d)
	return st


## THE ROAD HEIGHT: the carved law's corridor override (bed on land,
## deck over water). Called by terrain_height_carved.
static func road_height_override(d: Vector3, world_seed: PackedByteArray, h: float) -> float:
	var st: Vector3 = road_state_at(d, world_seed)
	if st.x <= 0.0:
		return h
	# THE SPAWN LAWS OUTRANK THE CARTWAY: the boot plaza is EXACTLY
	# SPAWN_HEIGHT and the apron holds its dry floor - the road never
	# regrades ground inside the apron ring (the path law bends
	# around it; this guard is the defensive belt).
	if d.angle_to(SPAWN_CENTER) < SPAWN_APRON_OUTER_ANG:
		return h
	return lerpf(h, st.z, st.x)


## THE ROAD RESPECT (the enemy law): 1 far from the road, 0 on it,
## smoothly across the respect belt - beasts spawn and hunt OUTSIDE
## the cartway (the spawn placement law and the aggro gate read it).
static func road_clearance_at(d: Vector3, world_seed: PackedByteArray) -> float:
	var w: float = _road_probe(d, world_seed, ROAD_CLEAR_ANG).x
	return clampf(1.0 - w * 2.0, 0.0, 1.0)


## THE ROAD WALK DIRECTION at a direction (for the auto-follow law):
## the tangent of the nearest corridor segment pointing toward the
## capitol. Zero vector off the road.
static func road_walk_dir(d: Vector3, world_seed: PackedByteArray) -> Vector3:
	d = d.normalized()
	var spec: RoadSpec = road_spec_cached(world_seed)
	var best: float = 0.0
	var walk: Vector3 = Vector3.ZERO
	var n: int = spec.path.size()
	for i in range(n - 1):
		var p0: Vector3 = spec.path[i]
		var p1: Vector3 = spec.path[i + 1]
		var seg_len: float = p0.angle_to(p1)
		if seg_len >= 1e-9:
			var axis: Vector3 = p0.cross(p1).normalized()
			for si in range(1, 3):
				var mid: Vector3 = p0.rotated(axis, seg_len * (float(si) / 3.0)).normalized()
				var ang: float = d.angle_to(mid)
				if ang < ROAD_ANG and 1.0 - ang / ROAD_ANG > best:
					best = 1.0 - ang / ROAD_ANG
					walk = axis.cross(mid).normalized()
	return walk


# -- THE GROUND SAMPLE (the fused-sample refactor, stage 1) -------------
#
# One value object holding every per-direction quantity the renderer, the
# walk law, and the biome law need. Built ONCE per quantized direction and
# memoized together (labs/prd-ground-sample.md). Stage 1 computes it by
# calling the existing sub-laws, so it is trivially bit-identical to the
# individual entry points; stage 2 rewires those entry points to read this
# struct, stage 3 collapses the per-field caches into _ground_cache.
#
# The `primary` flag marks a sector as "used as a ground sample" so
# _ground_cache can hold both fused samples (primary=true) and the bare
# raw samples stage 2 reads internally (primary=false) without a
# self-referential builder recursion.
class GroundSample:
	var dir: Vector3
	var height: float          # terrain_height (carved, default mode)
	var height_base: float     # _terrain_height_base
	var water_table: float     # water_table_raw
	var water_surface: float   # hydro_water_surface (-1e9 = no standing water)
	var temperature: float
	var moisture: float
	var biome_id: int
	var biome_weights: Dictionary
	var skin: Color            # skin_classes
	var crag: Vector4          # _crag_noise
	var river_channel: float
	var road_state: Vector3
	var sea: float
	var primary: bool = false


## Build the fused sample for a direction (no memo). All fields are read
## from the existing sub-laws, so the numbers are bit-identical to the
## public entry points.
static func _build_ground_sample(dir: Vector3, world_seed: PackedByteArray) -> GroundSample:
	var d: Vector3 = dir.normalized()
	var s := GroundSample.new()
	s.dir = d
	s.sea = sea_level(world_seed)
	s.height = terrain_height(d, world_seed)
	s.height_base = _terrain_height_base(d, world_seed)
	s.water_table = water_table_raw(d, world_seed)
	s.water_surface = hydro_water_surface(d, world_seed)
	s.temperature = climate_temperature(d, world_seed)
	s.moisture = climate_moisture(d, world_seed)
	s.biome_id = climate_biome_at(d, world_seed, s.height, s.water_surface)
	s.biome_weights = _biome_weights_from(s.biome_id, s.temperature, s.moisture, s.height, s.sea)
	s.skin = _skin_from(s.biome_weights)
	s.crag = _crag_noise(d, world_seed)
	s.river_channel = river_channel(d, world_seed)
	s.road_state = road_state_at(d, world_seed)
	return s


## The fused ground sample at a direction, memoized together on the
## quantized sector. This is the ONE call a renderer needs per vertex.
static func ground_sample(dir: Vector3, world_seed: PackedByteArray) -> GroundSample:
	var d: Vector3 = dir.normalized()
	var cached = _ground_cache.get_value(d, world_seed)
	if cached is GroundSample and cached.primary:
		return cached
	var s: GroundSample = _build_ground_sample(d, world_seed)
	s.primary = true
	_ground_cache.set_value(d, world_seed, s)
	return s
