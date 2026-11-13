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
	TerrainGen.BiomeId.FOREST: 46.0,
	TerrainGen.BiomeId.TAIGA: 42.0,
	TerrainGen.BiomeId.JUNGLE: 50.0,
	TerrainGen.BiomeId.GRASSLAND: 15.0,
	TerrainGen.BiomeId.SWAMP: 9.0,
	TerrainGen.BiomeId.SAVANNA: 5.0,
	TerrainGen.BiomeId.SHORE: 3.0,
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
## per face ~= 2.8/km2) then tuned UP ~3x for the AAA near view -- the
## discrete mushrooms/ore/bushes/flowers that read as ground furniture.
const DETAIL_DENSITY_KM2 := {
	TerrainGen.BiomeId.GRASSLAND: 165.0,
	TerrainGen.BiomeId.SAVANNA: 95.0,
	TerrainGen.BiomeId.STEPPE: 95.0,
	TerrainGen.BiomeId.FOREST: 120.0,
	TerrainGen.BiomeId.JUNGLE: 120.0,
	TerrainGen.BiomeId.TAIGA: 95.0,
	TerrainGen.BiomeId.ALPINE_MEADOW: 80.0,
	TerrainGen.BiomeId.SWAMP: 58.0,
	TerrainGen.BiomeId.ALPINE: 45.0,
	TerrainGen.BiomeId.TUNDRA: 45.0,
	TerrainGen.BiomeId.BADLANDS: 45.0,
	TerrainGen.BiomeId.DESERT: 40.0,
	TerrainGen.BiomeId.SHORE: 40.0,
}

## Grass-blade density per biome, in blades per square kilometre. The DENSE
## ground-cover carpet (one MultiMesh per chunk), separate from the discrete
## detail kinds so a meadow can be thick without flooding the prop tree. The
## grass-family bands carry the carpet; dry/frozen bands a thin straggle;
## deep water grows none (the sea skip in the derive pass handles the rest).
const GRASS_DENSITY_KM2 := {
	TerrainGen.BiomeId.GRASSLAND: 2600.0,
	TerrainGen.BiomeId.SAVANNA: 1500.0,
	TerrainGen.BiomeId.STEPPE: 1500.0,
	TerrainGen.BiomeId.FOREST: 1900.0,
	TerrainGen.BiomeId.JUNGLE: 2100.0,
	TerrainGen.BiomeId.TAIGA: 1300.0,
	TerrainGen.BiomeId.ALPINE_MEADOW: 1700.0,
	TerrainGen.BiomeId.SWAMP: 1000.0,
	TerrainGen.BiomeId.ALPINE: 320.0,
	TerrainGen.BiomeId.TUNDRA: 320.0,
	TerrainGen.BiomeId.BADLANDS: 420.0,
	TerrainGen.BiomeId.DESERT: 160.0,
	TerrainGen.BiomeId.SHORE: 260.0,
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


## The standing-water tint (the streamer's climate law): depth band, then a
## frozen sheet near the snowline, then the marsh murk in a swamp basin.
func water_tint(dir: Vector3, depth: float) -> Color:
	var wcol: Color = Color(0.72, 0.82, 0.86).lerp(Color(0.42, 0.62, 0.68), clampf(depth / 2.0, 0.0, 1.0))
	if depth > 2.0:
		wcol = wcol.lerp(Color(0.30, 0.44, 0.55), clampf((depth - 2.0) / 4.0, 0.0, 1.0))
	if TerrainGen.climate_temperature(dir, _seed) < TerrainGen.SNOWLINE_T:
		wcol = wcol.lerp(Color(0.86, 0.90, 0.94), 0.8)
	elif TerrainGen.climate_biome_id(dir, _seed) == TerrainGen.BiomeId.SWAMP:
		wcol = wcol.lerp(Color(0.42, 0.46, 0.30), 0.7)
	return wcol


## The main world's authored cartway (the streamer's road spec, now a provider
## read so the renderer draws the deck). Cached in TerrainGen.
func road_spec():
	return TerrainGen.road_spec_cached(_seed)


## The fused draw sample (one call per clipmap vertex): the ground_sample
## memo + the splat skin, exactly what the clipmap used to inline.
func surface_sample(dir: Vector3) -> Dictionary:
	var gs = TerrainGen.ground_sample(dir, _seed)
	var skin: Dictionary = TerrainGen.splat_skin_from(gs, _seed, gs.height, 0.2)
	return {"height": gs.height, "splat": skin["splat"], "aux": skin["aux"]}


func spawn_dir() -> Vector3:
	return TerrainGen.SPAWN_CENTER


func rock_specs(face: int) -> Array:
	return TerrainGen.rock_specs(_seed, face)


func boulder_specs(face: int) -> Array:
	return TerrainGen.boulder_specs(_seed, face)


func tree_density(bid: int) -> float:
	return float(TREE_DENSITY_KM2.get(bid, 0.0))


func detail_density(bid: int) -> float:
	return float(DETAIL_DENSITY_KM2.get(bid, 0.0))


func grass_density(bid: int) -> float:
	return float(GRASS_DENSITY_KM2.get(bid, 0.0))


func seed_bytes() -> PackedByteArray:
	return _seed


## The land-harvest zone for a prop site: the main world's homeland biome
## cluster is the starter plains (the streamer's hardcoded zone), everything
## else is paint only (the sea/atoll/deep-root keep their own gather laws).
func zone_for_dir(dir: Vector3) -> String:
	var bid: int = TerrainGen.climate_biome_id(dir, _seed)
	match bid:
		TerrainGen.BiomeId.GRASSLAND, TerrainGen.BiomeId.SAVANNA, \
		TerrainGen.BiomeId.STEPPE, TerrainGen.BiomeId.FOREST, \
		TerrainGen.BiomeId.JUNGLE, TerrainGen.BiomeId.TAIGA, \
		TerrainGen.BiomeId.SWAMP, TerrainGen.BiomeId.RIVER, \
		TerrainGen.BiomeId.ALPINE_MEADOW:
			return "zone_starter_plains"
	return ""


## The Sundered Sea's authored beds (the streamer's DEEP_BEDS): chart
## coordinates -> a world direction, owned by the world's own face. Kept
## here so the prop layer grows the gardens; the renderer no longer owns
## them.
const DEEP_BED_CHART: Array = [
	[0.40, -0.07, 1], [0.45, 0.00, 1], [0.50, 0.07, 1],
	[0.58, -0.04, 2], [0.64, 0.00, 2], [0.70, 0.04, 2],
]


func deep_beds() -> Array:
	var chart = load("res://core/services/strait_chart.gd")
	if chart == null:
		return []
	var out: Array = []
	for i in range(DEEP_BED_CHART.size()):
		var bed: Array = DEEP_BED_CHART[i]
		var d: Vector3 = chart.dir_from_chart(float(bed[0]), float(bed[1]))
		out.append({"dir": d, "kind": int(bed[2]), "bed": i})
	return out
