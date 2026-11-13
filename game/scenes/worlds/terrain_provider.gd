## TerrainProvider -- the main world's `GroundProvider` (labs/prd-clipmap.md
## section 10). A thin adapter over `TerrainGen`'s public statics, so the
## clipmap and the prop layer read the main world through the SAME interface
## the underworld and the moon will implement. No new ground law lives here:
## every method delegates to `TerrainGen`, and the seed is captured at
## construction so the interface stays pure in `dir`.
extends "res://core/world/ground_provider.gd"

const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
const Faces = preload("res://core/frame/math/icosahedral_faces.gd")

## The canon planet radius (rock walk-over caps scale by it).
const PLANET_RADIUS: float = 20000.0

## Tree density per biome, in trees per square kilometre. Calibrated from the
## streamer's own scatter (a face is ~251 km2 at R=20 km; the ladder plants
## ~sites x planted-fraction per face) and then tuned UP ~2x for a fuller
## near view -- this is the one art knob, deliberately data so a world may
## override it. (labs/prd-clipmap.md 9.4.)
const TREE_DENSITY_KM2 := {
	TerrainGen.BiomeId.FOREST: 18.0,
	TerrainGen.BiomeId.TAIGA: 16.0,
	TerrainGen.BiomeId.JUNGLE: 18.0,
	TerrainGen.BiomeId.GRASSLAND: 9.0,
	TerrainGen.BiomeId.SWAMP: 2.0,
	TerrainGen.BiomeId.SAVANNA: 1.5,
	TerrainGen.BiomeId.SHORE: 1.2,
	# The streamer plants NO trees past the tree line (desert / steppe /
	# badlands / tundra / alpine): those bands are detail-prop country.
	TerrainGen.BiomeId.STEPPE: 0.0,
	TerrainGen.BiomeId.BADLANDS: 0.0,
	TerrainGen.BiomeId.TUNDRA: 0.0,
	TerrainGen.BiomeId.DESERT: 0.0,
	TerrainGen.BiomeId.ALPINE: 0.0,
}

## Detail-prop density per biome, in props per square kilometre. Calibrated
## from the streamer's `_DETAIL_BUDGETS` (a face is ~251 km2; grassland 700
## per face ~= 2.8/km2, scaled up for the near view).
const DETAIL_DENSITY_KM2 := {
	TerrainGen.BiomeId.GRASSLAND: 60.0,
	TerrainGen.BiomeId.SAVANNA: 34.0,
	TerrainGen.BiomeId.STEPPE: 34.0,
	TerrainGen.BiomeId.FOREST: 42.0,
	TerrainGen.BiomeId.JUNGLE: 42.0,
	TerrainGen.BiomeId.TAIGA: 34.0,
	TerrainGen.BiomeId.ALPINE_MEADOW: 28.0,
	TerrainGen.BiomeId.SWAMP: 20.0,
	TerrainGen.BiomeId.ALPINE: 16.0,
	TerrainGen.BiomeId.TUNDRA: 16.0,
	TerrainGen.BiomeId.BADLANDS: 16.0,
	TerrainGen.BiomeId.DESERT: 16.0,
	TerrainGen.BiomeId.SHORE: 13.0,
}

var _seed: PackedByteArray
var _sea: float


func _init() -> void:
	_seed = TerrainGen.world_seed_bytes()
	_sea = TerrainGen.sea_level(_seed)


func ground_height(dir: Vector3) -> float:
	return TerrainGen.terrain_height(dir, _seed)


func walk_height(dir: Vector3) -> float:
	var face: int = Faces.face_for_direction(dir)
	return TerrainGen.terrain_height(dir, _seed) + TerrainGen.rock_top_height(dir, _seed, face, PLANET_RADIUS)


func biome_id(dir: Vector3) -> int:
	return TerrainGen.climate_biome_id(dir, _seed)


func species_at(dir: Vector3) -> int:
	return TerrainGen.tree_species_at(dir, _seed)


func sea_level() -> float:
	return _sea


func water_surface(dir: Vector3) -> float:
	return TerrainGen.hydro_water_surface(dir, _seed)


## The fused draw sample (one call per clipmap vertex): the ground_sample
## memo + the splat skin, exactly what the clipmap used to inline.
func surface_sample(dir: Vector3) -> Dictionary:
	var gs = TerrainGen.ground_sample(dir, _seed)
	var skin: Dictionary = TerrainGen.splat_skin_from(gs, _seed, gs.height, 0.2)
	return {"height": gs.height, "splat": skin["splat"], "aux": skin["aux"]}


func spawn_dir() -> Vector3:
	return TerrainGen.SPAWN_CENTER


func tree_density(bid: int) -> float:
	return float(TREE_DENSITY_KM2.get(bid, 0.0))


func detail_density(bid: int) -> float:
	return float(DETAIL_DENSITY_KM2.get(bid, 0.0))


func seed_bytes() -> PackedByteArray:
	return _seed
