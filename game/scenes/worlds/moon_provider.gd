## MoonProvider -- the pale stone's ground law (labs/prd-clipmap.md 10.3).
##
## The moon globe used to draw a bare SphereMesh; its declared crater pool
## (`data/oceans/ocean_lunar_crater.tres`, "The Builder's Pool") was never
## built. This provider derives a gentle regolith heightfield, carves the
## crater bowl the pool fills, and declares the water surface -- so the moon
## gets real terrain the clipmap draws and the crater becomes a real dish.
##
## Every read is a PURE function of (seed, dir). Tabs, no class_name.
extends "res://core/world/ground_provider.gd"

const SeedNoise = preload("res://core/world/seed_noise.gd")
const SeedChain = preload("res://core/frame/kv/seed_chain.gd")
const PropLayer = preload("res://core/world/prop_layer.gd")

const WORLD_ID: String = "moon"
const PLANET_RADIUS: float = 1200.0

## The crater sits at the moon's top pole, where the horizontal water-plane
## model of a LOCAL ocean volume is a good approximation (a dish carved near
## the summit of the regolith).
const CRATER_DIR: Vector3 = Vector3(0, 1, 0)
const CRATER_RADIUS_M: float = 40.0
const CRATER_FLOOR_M: float = 30.0     # bowl depth below the reference radius
const CRATER_WATER_M: float = 6.0      # water surface below the reference radius
## The landing site: just outside the crater rim, on the flat the return gate
## and the earthrise stand on. Derived so the visitor always lands level.
const LANDING_ANG_MARGIN: float = 0.075
const LANDING_AZIMUTH: float = 0.6

## Regolith relief (m) and octaves -- the pale stone is gentle.
const RELIEF_AMP: float = 2.4
const RELIEF_OCTAVES: int = 4
const SALT_TERRAIN: int = 41

## Moon biome ids (local namespace; NEVER renumber).
const BIOME_REGOLITH: int = 0
const BIOME_CRATER: int = 1
const BIOME_RIM: int = 2

const BIOME_DETAIL_KM2 := {
        BIOME_REGOLITH: 5.0,   # a sparse pebble scatter, nothing more (pristine)
        BIOME_CRATER: 0.0,
        BIOME_RIM: 8.0,
}

const BIOME_COLOR := {
        BIOME_REGOLITH: Color(0.62, 0.62, 0.64),
        BIOME_CRATER: Color(0.42, 0.43, 0.46),
        BIOME_RIM: Color(0.72, 0.72, 0.73),
}

var _seed: PackedByteArray
var _acc: int = 0
var _crater_ang: float = 0.0
var _landing_dir: Vector3 = Vector3(0, 1, 0)


func _init() -> void:
        _seed = SeedChain.derive_seed([], "worlds/moon/ground")
        _acc = SeedNoise.seed_accumulator(_seed)
        _crater_ang = CRATER_RADIUS_M / PLANET_RADIUS
        _landing_dir = _derive_landing_dir()


## -- ground law --------------------------------------------------------

func ground_height(dir: Vector3) -> float:
        var d: Vector3 = dir.normalized()
        var base: float = SeedNoise.smooth_field(d, _acc, SALT_TERRAIN, RELIEF_OCTAVES) * RELIEF_AMP
        var a: float = d.angle_to(CRATER_DIR)
        var h: float = base
        if a < _crater_ang:
                # The bowl: a parabola to the floor, with a raised rim lip.
                var t: float = a / _crater_ang
                h = -CRATER_FLOOR_M * (1.0 - t * t)
                if t > 0.8:
                        h += 2.2 * (t - 0.8) / 0.2
        elif a < _crater_ang * 1.8:
                # The ejecta apron: blend the rim back to the regolith.
                var t2: float = (a - _crater_ang) / (_crater_ang * 0.8)
                h = base + 2.2 * (1.0 - t2)
        # Flatten a small apron at the landing so the gate stands level.
        var land_ang: float = d.angle_to(_landing_dir)
        if land_ang < 0.05:
                h = base
        elif land_ang < 0.09:
                var f: float = (land_ang - 0.05) / 0.04
                h = lerpf(base, h, f)
        return h


func walk_height(dir: Vector3) -> float:
        return ground_height(dir)


func surface_sample(dir: Vector3) -> Dictionary:
        var d: Vector3 = dir.normalized()
        var bid: int = biome_id(d)
        var base: Color = BIOME_COLOR.get(bid, Color(0.62, 0.62, 0.64))
        var shade: float = 1.0 + 0.08 * clampf(ground_height(d) / RELIEF_AMP, -1.0, 1.0)
        var col := Color(base.r * shade, base.g * shade, base.b * shade)
        return {"height": ground_height(d), "splat": col, "aux": Vector2(0.0, 1.0)}


func spawn_dir() -> Vector3:
        return _landing_dir


## The crater's declared water surface (m above the reference radius); -1e9
## outside the dish. The pool data (surface_height - floor_y) is the depth law.
func water_surface(dir: Vector3) -> float:
        var d: Vector3 = dir.normalized()
        if d.angle_to(CRATER_DIR) < _crater_ang * 1.05:
                return -CRATER_WATER_M
        return -1.0e9


func sea_level() -> float:
        return -1.0e9


## -- biome law ---------------------------------------------------------

func biome_id(dir: Vector3) -> int:
        var d: Vector3 = dir.normalized()
        var a: float = d.angle_to(CRATER_DIR)
        if a < _crater_ang:
                return BIOME_CRATER
        if a < _crater_ang * 1.4:
                return BIOME_RIM
        return BIOME_REGOLITH


## -- props -------------------------------------------------------------

func tree_density(_bid: int) -> float:
        return 0.0


func detail_density(bid: int) -> float:
        return float(BIOME_DETAIL_KM2.get(bid, 0.0))


func detail_kind(bid: int, _rng: RandomNumberGenerator) -> int:
        match bid:
                BIOME_REGOLITH:
                        return PropLayer.KIND_ORE
                BIOME_RIM:
                        return PropLayer.KIND_ORE
        return -1   # the crater interior is bare regolith (a clean workshop)


func rock_specs(_face: int) -> Array:
        return []


func boulder_specs(_face: int) -> Array:
        return []


func seed_bytes() -> PackedByteArray:
        return _seed


## -- crater / landing geometry (public reads for the globe) ------------

func crater_dir() -> Vector3:
        return CRATER_DIR


func crater_angular_radius() -> float:
        return _crater_ang


func landing_dir() -> Vector3:
        return _landing_dir


## The crater's water surface, in world_root-local planet coords (the moon is
## conjured at origin, so local == planet coords). Matches the declared
## `surface_height` the ocean volume reads.
func crater_water_y() -> float:
        return PLANET_RADIUS - CRATER_WATER_M


func _derive_landing_dir() -> Vector3:
        # A direction at (crater rim + margin) from the pole, at a derived
        # azimuth -- level ground just outside the dish.
        var ang: float = _crater_ang + LANDING_ANG_MARGIN
        var east: Vector3 = Vector3(1, 0, 0)
        var north: Vector3 = Vector3(0, 0, 1)
        var tangent: Vector3 = (east * cos(LANDING_AZIMUTH) + north * sin(LANDING_AZIMUTH)).normalized()
        return (CRATER_DIR * cos(ang) + tangent * sin(ang)).normalized()
