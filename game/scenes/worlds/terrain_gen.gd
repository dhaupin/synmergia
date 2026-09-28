## TerrainGen - SeedChain-driven deterministic per-face chunk content
## (prd-spherical-mvp.md S7). The world PRD's seed law: same seed +
## ruleset version = same world. Rock specs for a face derive ONLY
## from (world seed, face id, RULESET_VERSION) via
## SeedChain.derive_seed -- never from time, order, or locality.
## Also owns the walk-over height provider: rock tops raise the
## player's radial snap height so colliders decorate, not block.
## RefCounted static helper (preloaded by the terrain streamer).
extends RefCounted

const SeedChain = preload("res://core/frame/kv/seed_chain.gd")
const Faces = preload("res://core/frame/math/icosahedral_faces.gd")

## Bump to invalidate all derived content deliberately.
const RULESET_VERSION: String = "rocks_v1"

## Project default world seed (dev). Shards override per-shard later.
const DEFAULT_WORLD_SEED: String = "synmergia-alpha-1"
const WORLD_SEED_SETTING: String = "synmergia/world/seed"

## Base rock size (meters) before per-rock scale. ROCK_EMBED is how
## deep the rock sphere's center sits above the base surface; the
## visible top is therefore ROCK_EMBED + ROCK_RADIUS*scale above it,
## which the walk-over cap height matches exactly.
const ROCK_RADIUS: float = 1.2
const ROCK_EMBED: float = 0.3


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


## Rock specs for a face. Pure function of the seed: a fresh RNG is
## seeded from the face's derived bytes every call, so any process on
## any machine derives identical content.
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
		# vertex (70/30 stays well inside the Voronoi cell).
		var verts: PackedInt32Array = Faces.face_vertices(face)
		var v: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var spec := RockSpec.new()
		spec.dir = (center * 0.7 + v * 0.3).normalized()
		spec.scale = rng.randf_range(1.0, 2.2)
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
