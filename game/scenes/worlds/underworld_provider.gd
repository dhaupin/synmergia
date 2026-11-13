## UnderworldProvider -- the Deep Root's ground law (labs/prd-clipmap.md 10.3).
##
## The underworld globe used to draw a bare SphereMesh (a flat ball: no
## heightfield, no biomes, no props) while its five `BiomeBand` declarations
## sat unread (the builders hardcoded band ids and never read `.family`).
## This provider makes those declarations the real data law: it derives a
## seed-smooth heightfield, partitions the surface into the bands' BIOMES,
## and owns the biome->prop-kind dispatch the prop layer calls.
##
## Every read is a PURE function of (seed, dir) -- no RNG state, no
## accumulation -- so the Deep Root re-derives byte-identical every boot.
## Tabs, no class_name; instantiated by path (the terrain_provider pattern).
extends "res://core/world/ground_provider.gd"

const SeedNoise = preload("res://core/world/seed_noise.gd")
const SeedChain = preload("res://core/frame/kv/seed_chain.gd")
const ResourceScan = preload("res://core/frame/srv/resource_scan.gd")
const PropLayer = preload("res://core/world/prop_layer.gd")

const WORLD_ID: String = "underworld"
const PLANET_RADIUS: float = 2000.0
## The camp seat (world_root-local planet coords): the arrival shelf, which
## the heightfield flattens so the camp, cistern, and gates sit on level
## ground. Mirrors globe_underworld.CAMP_HEAD_POS.
const CAMP_HEAD: Vector3 = Vector3(0, 2000.0, 0)
const CAMP_DIR: Vector3 = Vector3(0, 1, 0)

## Underworld biome ids (a local namespace; NEVER renumber -- content
## derives from these).
const BIOME_CAMP: int = 0
const BIOME_CRAG: int = 1
const BIOME_GROVE: int = 2
const BIOME_MYCELIUM: int = 3
const BIOME_STALAGMITE: int = 4
const BIOME_GRASSES: int = 5

## Independent noise streams (salts).
const SALT_TERRAIN: int = 11
const SALT_BIOME: int = 23

## Heightfield relief amplitude (m) and octaves. Small -- the Deep Root is a
## shelf, not a mountain range; the noise is what lifts it off the flat ball.
const RELIEF_AMP: float = 3.2
const RELIEF_OCTAVES: int = 5
## The camp's BIOME zone (a small disc around the arrival seat). Distinct
## from the relief apron below: the biome zone is small so the five bands
## (16-70 m out) keep their own biomes, while the relief apron is wide so
## every authored structure (camp, cistern, wilds) lands on level ground.
const CAMP_BIOME_ANG: float = 0.006
## The relief apron: within RELIEF_FLAT_ANG the heightfield is level (the
## authored geometry rides the base shell); it fades to full relief by
## RELIEF_FADE_ANG. The Deep Root's own stones/camp are placed at
## planet_radius, so this keeps the drawn ground under them honest.
const RELIEF_FLAT_ANG: float = 0.045
const RELIEF_FADE_ANG: float = 0.07

## Band id -> biome (the declaration's own id is the key).
const BAND_BIOME := {
        "biome_underworld_crag_ring": BIOME_CRAG,
        "biome_underworld_dead_grove": BIOME_GROVE,
        "biome_underworld_mycelium_field": BIOME_MYCELIUM,
        "biome_underworld_stalagmite_runs": BIOME_STALAGMITE,
        "biome_underworld_odd_grasses": BIOME_GRASSES,
}

## Biome -> the prop-layer detail kind (BiomeBand.family is the dispatch
## key; the family enum maps onto the prop kinds). -1 = nothing, -2 = defer
## to the prop layer's built-in ladder.
const BIOME_KIND := {
        BIOME_CAMP: -2,
        BIOME_CRAG: PropLayer.KIND_ORE,
        BIOME_GROVE: PropLayer.KIND_MUSHROOM,
        BIOME_MYCELIUM: PropLayer.KIND_MYCELIUM,
        BIOME_STALAGMITE: PropLayer.KIND_ORE,
        BIOME_GRASSES: PropLayer.KIND_TUFT,
}

## Biome -> detail density (props per square kilometre). The glow meadow is
## the dense band; the stone bands carry a sparse stone/ore sprinkle.
const BIOME_DETAIL_KM2 := {
        BIOME_CAMP: 0.0,
        BIOME_CRAG: 18.0,
        BIOME_GROVE: 30.0,
        BIOME_MYCELIUM: 46.0,
        BIOME_STALAGMITE: 34.0,
        BIOME_GRASSES: 130.0,
}

## Biome -> the drawn ground albedo (the dusk-read palette: the Deep Root's
## stone is dark; the glow bands carry a faint green).
const BIOME_COLOR := {
        BIOME_CAMP: Color(0.17, 0.15, 0.19),
        BIOME_CRAG: Color(0.14, 0.12, 0.16),
        BIOME_GROVE: Color(0.16, 0.13, 0.11),
        BIOME_MYCELIUM: Color(0.20, 0.30, 0.24),
        BIOME_STALAGMITE: Color(0.30, 0.28, 0.26),
        BIOME_GRASSES: Color(0.22, 0.34, 0.24),
}

var _seed: PackedByteArray
var _acc: int = 0
var _bands: Array = []   # ordered band records (loaded once)


func _init() -> void:
        _seed = SeedChain.derive_seed([], "worlds/underworld/ground")
        _acc = SeedNoise.seed_accumulator(_seed)
        # Preload the band declarations on the MAIN thread: the clipmap's
        # cold build derives on worker threads, so no lazy member mutation or
        # resource load may happen on the derive path (the thread-safety law).
        _load_bands()


## -- ground law --------------------------------------------------------

func ground_height(dir: Vector3) -> float:
        var d: Vector3 = dir.normalized()
        var relief: float = SeedNoise.smooth_field(d, _acc, SALT_TERRAIN, RELIEF_OCTAVES) * RELIEF_AMP
        # Fade the relief to zero across the authored apron so every
        # structure the globe places at the base shell lands level.
        var camp_ang: float = d.angle_to(CAMP_DIR)
        if camp_ang < RELIEF_FLAT_ANG:
                relief = 0.0
        elif camp_ang < RELIEF_FADE_ANG:
                relief *= (camp_ang - RELIEF_FLAT_ANG) / (RELIEF_FADE_ANG - RELIEF_FLAT_ANG)
        return relief


func walk_height(dir: Vector3) -> float:
        return ground_height(dir)


func surface_sample(dir: Vector3) -> Dictionary:
        var d: Vector3 = dir.normalized()
        var bid: int = biome_id(d)
        var base: Color = BIOME_COLOR.get(bid, Color(0.16, 0.14, 0.18))
        # A faint height shading so rolling ground reads even in the dark.
        var shade: float = 1.0 + 0.10 * clampf(ground_height(d) / RELIEF_AMP, -1.0, 1.0)
        var col := Color(base.r * shade, base.g * shade, base.b * shade)
        return {"height": ground_height(d), "splat": col, "aux": Vector2(0.0, 1.0)}


func spawn_dir() -> Vector3:
        return CAMP_DIR


func sea_level() -> float:
        return -1.0e9


func water_surface(dir: Vector3) -> float:
        return sea_level()


## -- biome law (BiomeBand dispatch) ------------------------------------

func biome_id(dir: Vector3) -> int:
        var d: Vector3 = dir.normalized()
        if d.angle_to(CAMP_DIR) < CAMP_BIOME_ANG:
                return BIOME_CAMP
        var bands: Array = _load_bands()
        if bands.is_empty():
                return BIOME_GRASSES
        # The band whose nearest seat SPOKE is angularly closest, among the
        # bands whose radial span holds this point. A deterministic
        # Voronoi-like partition of (radius, angle); ties break by band order.
        var r: float = d.angle_to(CAMP_DIR) * PLANET_RADIUS
        var best: int = BIOME_GRASSES
        var best_score: float = 1.0e18
        var best_out: float = 1.0e18
        var best_out_biome: int = BIOME_GRASSES
        for b in bands:
                var radial_gap: float = 0.0
                if r < float(b["inner"]):
                        radial_gap = float(b["inner"]) - r
                elif r > float(b["outer"]):
                        radial_gap = r - float(b["outer"])
                if radial_gap < best_out:
                        best_out = radial_gap
                        best_out_biome = int(b["biome"])
                if radial_gap > 0.0:
                        continue
                var score: float = _spoke_angle(b, d)
                if score < best_score:
                        best_score = score
                        best = int(b["biome"])
        if best_score >= 1.0e17:
                return best_out_biome
        return best


## The angular distance from `d` to the nearest seat spoke of a band (rad).
func _spoke_angle(b: Dictionary, d: Vector3) -> float:
        var count: int = maxi(int(b["count"]), 1)
        var rel: float = _rel_angle(b, d)
        var spacing: float = TAU / float(count)
        var k: float = roundf((rel - float(b["offset"])) / spacing)
        var seat: float = float(b["offset"]) + k * spacing
        return absf(angle_difference(rel, seat))


## The point's azimuth around the camp up-axis (rad, in [0, TAU)).
func _rel_angle(_b: Dictionary, d: Vector3) -> float:
        var east: Vector3 = Vector3(1, 0, 0)
        var north: Vector3 = Vector3(0, 0, 1)
        return fposmod(atan2(d.dot(north), d.dot(east)), TAU)


## -- prop densities + kind dispatch ------------------------------------

func tree_density(_bid: int) -> float:
        return 0.0   # the Deep Root grows no canopy trees; its grove is authored


func detail_density(bid: int) -> float:
        return float(BIOME_DETAIL_KM2.get(bid, 0.0))


## The biome->kind dispatch the prop layer calls. Returns -2 to defer to the
## prop layer's built-in ladder.
func detail_kind(bid: int, rng: RandomNumberGenerator) -> int:
        var kind: int = int(BIOME_KIND.get(bid, -2))
        if kind == -1 or kind == -2:
                return kind
        # A little variety inside a band so the scatter is not monotone.
        if kind == PropLayer.KIND_ORE and rng.randf() < 0.35:
                return PropLayer.KIND_TUFT
        if kind == PropLayer.KIND_MYCELIUM and rng.randf() < 0.25:
                return PropLayer.KIND_MUSHROOM
        return kind


func rock_specs(_face: int) -> Array:
        return []   # the crag band is authored by the globe, not per-face


func boulder_specs(_face: int) -> Array:
        return []


func seed_bytes() -> PackedByteArray:
        return _seed


## -- band declarations (loaded once, cached) ---------------------------

func _load_bands() -> Array:
        if not _bands.is_empty():
                return _bands
        for p in ResourceScan.list_resources("res://data/biomes"):
                var b: Resource = load(p)
                if b == null or not ("world_id" in b) or not ("family" in b):
                        continue
                if str(b.world_id) != WORLD_ID:
                        continue
                var bid: String = str(b.id)
                if not BAND_BIOME.has(bid):
                        continue
                _bands.append({
                        "id": bid,
                        "biome": int(BAND_BIOME[bid]),
                        "inner": float(b.radius_inner_m),
                        "outer": float(b.radius_outer_m),
                        "offset": float(b.angular_offset),
                        "count": int(b.seat_count()),
                })
        return _bands
