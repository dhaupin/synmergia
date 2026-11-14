## GroundProvider -- the per-world ground-law interface the renderers and
## the prop layer read (labs/prd-clipmap.md section 10).
##
## The clipmap used to hardcode `TerrainGen` (the main world's ground law),
## which is why it could only draw one globe. A `GroundProvider` is the small
## set of reads every consumer needs; each world supplies its own. `TerrainGen`
## backs the main world via `TerrainProvider`; the underworld and the moon
## supply their own.
##
## This base class documents the contract and fails LOUD if a method is not
## overridden -- a silent zero here would draw a flat world. (No class_name:
## instantiated by path, the world_content_builder pattern.)
extends RefCounted


## The world's raw ground height (meters above the sphere) at a unit direction.
func ground_height(_dir: Vector3) -> float:
	push_error("GroundProvider.ground_height not overridden")
	return 0.0


## The walk-surface height (ground + walk-over caps: small rocks etc.).
func walk_height(dir: Vector3) -> float:
	return ground_height(dir)


## The biome id at a direction (a `TerrainGen.BiomeId` value, or a world's own).
func biome_id(_dir: Vector3) -> int:
	return 0


## The tree species id at a direction (a `TerrainGen.TreeSpecies` value).
func species_at(_dir: Vector3) -> int:
	return 0


## The sea level (meters above the sphere); -1e9 if the world has no sea.
func sea_level() -> float:
	return -1.0e9


## The water surface height at a direction (lake/river/pool); -1e9 if none.
## Distinct from `sea_level()`: the sea is a global shell the renderer floods
## once, while standing water is a per-direction table the renderer draws as a
## sheet wherever it clears the ground (rivers, high ponds). The default is the
## sea line (a world with a sea reports its sea here too, so the sheet law
## simply never fires above it).
func water_surface(dir: Vector3) -> float:
	return sea_level()


## The tint of a standing-water sheet at `dir` for a given water depth (meters
## above the bed). The default is the depth-only law (shallow film -> deep
## blue); a world with a climate may override (freeze band, marsh murk).
func water_tint(_dir: Vector3, depth: float) -> Color:
	var wcol: Color = Color(0.72, 0.82, 0.86).lerp(Color(0.42, 0.62, 0.68), clampf(depth / 2.0, 0.0, 1.0))
	if depth > 2.0:
		wcol = wcol.lerp(Color(0.30, 0.44, 0.55), clampf((depth - 2.0) / 4.0, 0.0, 1.0))
	return wcol


## The world's authored road (a `TerrainGen.RoadSpec`-shaped value: `path`,
## `beds`, `bridges`) the renderer draws as a raised deck ribbon, or null if the
## world has no road. Default = none.
func road_spec():
	return null


## The vertex surface sample the renderer draws: a fused read returning the
## draw height + splat colour + aux, so a renderer makes ONE provider call
## per vertex (the ground_sample pattern). The default is a flat, unskinned
## shell so a provider that has no colour law still draws.
func surface_sample(dir: Vector3) -> Dictionary:
	return {"height": ground_height(dir), "splat": Color(0.42, 0.55, 0.30), "aux": Vector2(0.0, 1.0)}


## The world's authored spawn/seat direction (the renderer's boot fallback
## when it has no player position yet). Default = the north pole; a world
## with a camp declares its own.
func spawn_dir() -> Vector3:
	return Vector3(0, 1, 0)


## The per-face fixed rock specs (labs/prd-clipmap.md 9.6): an array of
## {dir, scale, yaw}. Default = none, so a world that scatters no per-face
## stones never inherits another world's.
func rock_specs(_face: int) -> Array:
	return []


## The per-face fixed boulder specs: an array of {dir, radius, yaw}.
## Default = none.
func boulder_specs(_face: int) -> Array:
	return []


## The prop density for a biome, in props per square kilometre (trees).
func tree_density(_biome_id: int) -> float:
	return 0.0


## The prop density for a biome, in props per square kilometre (detail kinds).
func detail_density(_biome_id: int) -> float:
	return 0.0


## The grass-blade density for a biome, in blades per square kilometre. This
## is the DENSE ground-cover field (drawn as a MultiMesh per chunk), separate
## from `detail_density` so a world can carpet a meadow without also flooding
## the discrete detail kinds. Default = 0 (no grass; the world stays bare).
func grass_density(_biome_id: int) -> float:
	return 0.0


## The authored deep-water beds (the Sundered Sea's kelp/pearl gardens): an
## array of {dir: Vector3, kind: int, bed: int}. Default = none, so only the
## world that authored beds grows them (the retired retired streamer's DEEP_BEDS, now a
## provider read so the prop layer -- not the renderer -- owns the garden).
func deep_beds() -> Array:
	return []


## The zone id a prop site's direction belongs to (the harvest registration's
## zone law). Default = "" so a world that does not resolve zones registers no
## land harvestables (its flora is paint only).
func zone_for_dir(_dir: Vector3) -> String:
	return ""
