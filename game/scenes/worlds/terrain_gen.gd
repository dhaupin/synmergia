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
## RefCounted static helper (preloaded by the terrain streamer).
extends RefCounted

const SeedChain = preload("res://core/frame/kv/seed_chain.gd")
const Faces = preload("res://core/frame/math/icosahedral_faces.gd")

## Bump to invalidate all derived content deliberately. v2: the
## heightfield + boulders join the world (all rocks/trees re-derive).
const RULESET_VERSION: String = "terrain_v2"

## Project default world seed (dev). Shards override per-shard later.
const DEFAULT_WORLD_SEED: String = "synmergia-alpha-1"
const WORLD_SEED_SETTING: String = "synmergia/world/seed"

## Base rock size (meters) before per-rock scale. ROCK_EMBED is how
## deep the rock sphere's center sits above the base surface; the
## visible top is therefore ROCK_EMBED + ROCK_RADIUS*scale above it,
## which the walk-over cap height matches exactly.
const ROCK_RADIUS: float = 1.2
const ROCK_EMBED: float = 0.3

## -- Terrain arc constants (planet-scale law; all heights in meters) --
## Hard ceiling on the ground law: nothing grows above this.
const TERRAIN_MAX: float = 42.0
## The sea line above the base surface. Per-seed in a narrow band so
## shorelines shift between worlds but the shelf law holds.
const SEA_LEVEL_MIN: float = 4.0
const SEA_LEVEL_SPAN: float = 3.0
## Ocean floor depth range below the sea line (the swimmable shelf).
const OCEAN_DEPTH_MIN: float = 9.0
const OCEAN_DEPTH_SPAN: float = 6.0
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
const ISLAND_CENTER: Vector3 = Vector3(0.0, 0.866, 0.5)
const ISLAND_ANGULAR_REACH: float = 0.012
const ISLAND_PLATEAU: float = 20.0
## The spawn shore: guaranteed land + a flattened build/walk plaza.
const SPAWN_CENTER: Vector3 = Vector3(1.0, 0.0, 0.0)
const SPAWN_FLAT_ANG: float = 0.0015 # ~30 m at planet scale
const SPAWN_HEIGHT: float = 9.0
## No rock, boulder, or tree may center within this angle of spawn
## (at 20 km that is ~240 m of clear shore; at prototype scale it
## covers the old rock-cap-free spawn guarantee the probes pin).
const SPAWN_CLEAR_ANG: float = 0.012
## The homeland's angular reach: the STARTING CONTINENT's guaranteed
## land around the spawn. 2.0 rad = ~40 km at the 20 km planet scale
## -- the streamed neighborhood (faces span ~60 deg) is solid land,
## the coast is a journey, and the ocean lies beyond it. The dome is
## GATED BY LATITUDE (temperate band only), so the polar seas survive
## the big cap, and the detail noise carves the coast into bays and
## points (no circle coastline).
const HOMELAND_ANGULAR_REACH: float = 2.0
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
static func _seed_salt(world_seed: PackedByteArray, tag: String) -> int:
	var acc: int = 0
	for b in tag.to_utf8_buffer():
		acc = (acc * 131 + b) % 9007199254740991
	for b in world_seed:
		acc = (acc * 131 + b) % 9007199254740991
	return acc


## The sea line for this world (pure function of the seed).
static func sea_level(world_seed: PackedByteArray) -> float:
	return SEA_LEVEL_MIN + SEA_LEVEL_SPAN * fposmod(float(_seed_salt(world_seed, "sea")), 1000003.0) / 1000003.0


## Value-noise cell hash: integer lattice cell + salt -> [0, 1).
## Wrapping int math is the hash (deterministic everywhere).
static func _cell_hash(cell: Vector3i, salt: int) -> float:
	var h: int = salt
	h = (h * 668265263) ^ (cell.x * 374761393)
	h = (h * 1274126177) ^ (cell.y * 668265263)
	h = (h * 974634733) ^ (cell.z * 2147483647)
	h = h ^ (h >> 15)
	return float(absi(h) % 1000003) / 1000003.0


## Trilinear value noise on the direction cube (continuous everywhere;
## per-octave wavelength fits inside a lattice cell, so no seam law is
## needed at this fidelity). freq = lattice cells per radius.
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
	var noise_land: float = clampf(band * (base * 1.15 + detail * 0.45 - 0.42), 0.0, 1.0)
	var dome: float = _homeland(d)
	if dome <= 0.0:
		return noise_land
	# The dome wins, minus the bay-carving detail (floored so the
	# neighborhood always stays dry land).
	return clampf(maxf(noise_land, maxf(dome * 0.95 - detail * 0.35, dome * 0.42)), 0.0, 1.0)


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


## THE GROUND LAW. Height (meters) of the walkable terrain above the
## base surface at world direction `dir`. Continuous everywhere
## (smoothstep blends; max/lerp of continuous fields). Bands: ocean
## floor -> continental shelf -> beach -> plains -> hills -> mountains
## -> snowline ceiling; the lake and island override their bowls; the
## spawn plaza flattens last (guaranteed flat ground under the boot).
static func terrain_height(dir: Vector3, world_seed: PackedByteArray) -> float:
	var d: Vector3 = dir.normalized()
	var salt: int = _seed_salt(world_seed, "terrain")
	var sea: float = sea_level(world_seed)

	# The homeland dome is folded into _land_mass (bays and points
	# carved by the same detail noise), so one land law reads it.
	var land: float = _land_mass(d, salt)

	# Continental shelf: ocean floor blends into the land level across
	# the near-shore band (no coast kink -- the sea floor is a beach
	# in slow motion).
	var ocean_floor: float = sea - (OCEAN_DEPTH_MIN + OCEAN_DEPTH_SPAN * _vnoise(d, salt + 7, 6.0))
	var land_h: float = -3.0 + land * 17.0
	# Rolling hills (inland only; the shelf stays smooth for wading).
	var inland: float = smoothstep(0.18, 0.5, land)
	land_h += inland * (_vnoise(d, salt + 4, 9.0) * 6.0 - 2.0)
	# Mountains: rare deep-inland noise cells grow peaks (amplitude
	# and mask tuned so peaks stay under TERRAIN_MAX naturally -- a
	# clipped ceiling reads as an artificial mesa wall).
	var mnoise: float = _vnoise(d, salt + 3, 3.0)
	var mask: float = smoothstep(0.62, 0.9, mnoise) * smoothstep(0.35, 0.6, land)
	land_h += mask * pow(mnoise, 2.5) * 20.0
	var h: float = lerpf(ocean_floor, land_h, smoothstep(0.0, 0.18, land))
	h = minf(h, TERRAIN_MAX)

	# The mountain lake: a bowl pressed to LAKE_DROP below the sea
	# line (only where there is land to hold it).
	var bowl: float = _lake_bowl(d) * smoothstep(0.1, 0.3, land)
	if bowl > 0.0:
		h = lerpf(h, sea - LAKE_DROP, bowl)

	# The island: volcanic plateau rising from the ocean floor.
	var isl: float = _island_shape(d)
	if isl > 0.0:
		var top: float = sea + 2.0 + isl * ISLAND_PLATEAU
		h = maxf(h, lerpf(ocean_floor, top, isl))
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
	return h


## Rock specs for a face. Pure function of the seed: a fresh RNG is
## seeded from the face's derived bytes every call, so any process on
## any machine derives identical content. Dirs too close to the spawn
## shore are RE-DRAWN (never dropped: the count contract 2..5 holds)
## so no walk-over cap ever covers the spawn plaza.
static func rock_specs(world_seed: PackedByteArray, face: int) -> Array:
	var bytes: PackedByteArray = face_seed_bytes(world_seed, face)
	# Fold the 32 seed bytes into one 64-bit RNG seed.
	var acc: int = 0
	for b in bytes:
		acc = (acc * 256 + b) % 9007199254740991
	var rng := RandomNumberGenerator.new()
	rng.seed = acc

	var count: int = rng.randi_range(2, 5)
	var center: Vector3 = Faces.face_center(face)

	var specs: Array = []
	for i in range(count):
		# Direction: jitter from the face center toward a random corner
		# vertex (70/30 stays well inside the Voronoi cell). Re-draw
		# spawn-adjacent draws (bounded: at most 4 redraws, then the
		# last draw stands -- deterministic on every machine).
		var verts: PackedInt32Array = Faces.face_vertices(face)
		var v: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var dir: Vector3 = (center * 0.7 + v * 0.3).normalized()
		for _try in range(4):
			if dir.angle_to(SPAWN_CENTER) >= SPAWN_CLEAR_ANG:
				break
			v = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
			dir = (center * 0.7 + v * 0.3).normalized()
		var spec := RockSpec.new()
		spec.dir = dir
		spec.scale = rng.randf_range(1.0, 2.2)
		spec.yaw = rng.randf_range(0.0, TAU)
		specs.append(spec)
	return specs


## Boulder specs: 1-2 per face -- the VARIETY LAW is universal: any
## streamed set (a face + its 3 neighbors) always carries climbing
## content, so the guarantee is every face, not a lucky subset. A
## 10 km face with one or two big rocks is sparse. Same seed
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

	var count: int = 1 + rng.randi_range(0, 1)
	var center: Vector3 = Faces.face_center(face)
	var specs: Array = []
	for i in range(count):
		var verts: PackedInt32Array = Faces.face_vertices(face)
		var v: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var dir: Vector3 = (center * 0.6 + v * 0.4).normalized()
		for _try in range(4):
			if dir.angle_to(SPAWN_CENTER) >= SPAWN_CLEAR_ANG:
				break
			v = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
			dir = (center * 0.6 + v * 0.4).normalized()
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
