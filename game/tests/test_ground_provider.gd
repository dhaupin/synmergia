## Tests for GroundProvider / TerrainProvider (the multi-world ground seam).
## Run: godot --headless --path . --script res://tests/test_ground_provider.gd
extends SceneTree

const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
const Provider = preload("res://scenes/worlds/terrain_provider.gd")


func _init() -> void:
	var ok := true
	if not _test_equivalence():
		push_error("FAIL: equivalence")
		ok = false
	if not _test_density():
		push_error("FAIL: density")
		ok = false
	print("[ground_provider] %s" % ("ALL PASS" if ok else "FAILURES"))
	quit(0 if ok else 1)


func _test_equivalence() -> bool:
	var p = Provider.new()
	var seed: PackedByteArray = TerrainGen.world_seed_bytes()
	var dirs: Array = [Vector3(1, 0, 0), Vector3(0.3, 0.5, 0.8).normalized(),
			Vector3(-0.2, 0.9, 0.1).normalized(), Vector3(0, -1, 0)]
	for d in dirs:
		if absf(p.ground_height(d) - TerrainGen.terrain_height(d, seed)) > 1e-9:
			return false
		if p.biome_id(d) != TerrainGen.climate_biome_id(d, seed):
			return false
		if p.species_at(d) != TerrainGen.tree_species_at(d, seed):
			return false
	if absf(p.sea_level() - TerrainGen.sea_level(seed)) > 1e-9:
		return false
	return true


func _test_density() -> bool:
	var p = Provider.new()
	# Forest must be denser than desert; densities are non-negative.
	if p.tree_density(TerrainGen.BiomeId.FOREST) <= p.tree_density(TerrainGen.BiomeId.DESERT):
		return false
	if p.detail_density(TerrainGen.BiomeId.GRASSLAND) <= 0.0:
		return false
	return true
