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
func water_surface(dir: Vector3) -> float:
	return sea_level()


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


## The prop density for a biome, in props per square kilometre (trees).
func tree_density(_biome_id: int) -> float:
	return 0.0


## The prop density for a biome, in props per square kilometre (detail kinds).
func detail_density(_biome_id: int) -> float:
	return 0.0
