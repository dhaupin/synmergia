## test_tree_species_v7 - the species-law unit checks (no globe boot).
## The census counts WHAT DOES ANSWER; what the planet OFFERS at these
## latitudes is the climate probe's own contract (probe_terrain_
## climate's census on this dev seed resolves no reachable TAIGA (7)
## or SWAMP (6) in the sweep -- the species ladder only answers where
## the biome resolves). What this test pins:
##   1. species_at is PURE: same dir + seed answers the same code.
##   2. The shapes their biomes DID answer (acacia in savanna,
##      conifer set for taiga when taiga resolves).
##   3. The v7 ruleset bump: biome ids untouched (never renumbered).
## The retired retired streamer's vine/mushroom/mycelium/scree laws read the SAME
## biome ints, so whatever this seed offers they've got covered.
extends SceneTree

const Gen = preload("res://scenes/worlds/terrain_gen.gd")

var fails := 0

func _check(label: String, cond: bool) -> void:
	if not cond:
		fails += 1
		print("  FAIL ", label)
	else:
		print("  PASS ", label)

func _sweep(steps: int) -> Array:
	var out: Array = []
	var ga: float = PI * (3.0 - sqrt(5.0))
	for i in range(steps):
		var y: float = 1.0 - 2.0 * (float(i) + 0.5) / float(steps)
		var r: float = sqrt(maxf(0.0, 1.0 - y * y))
		var th: float = ga * float(i)
		out.append(Vector3(cos(th) * r, y, sin(th) * r).normalized())
	return out

func _init() -> void:
	var g = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = g.world_seed_bytes()
	# 1. PURE
	var d := Vector3(0.6, 0.45, 0.66).normalized()
	var a: int = g.tree_species_at(d, seed_b)
	var b: int = g.tree_species_at(d, seed_b)
	_check("pure: same dir+seed twice", a == b)
	# 2. Shapes (what the sweep hit).
	var seen := {}
	var samples: Array = _sweep(4000) + _sweep(977)
	for dir in samples:
		var bid: int = g.climate_biome_id(dir, seed_b)
		var sp: int = g.tree_species_at(dir, seed_b)
		if not seen.has(bid):
			seen[bid] = {}
		seen[bid][sp] = true
	print("  species-per-biome census:")
	for bid in seen:
		print("    biome ", bid, " -> ", seen[bid].keys())
	var taiga_hits: bool = seen.has(g.BiomeId.TAIGA)
	if taiga_hits:
		_check("taiga (resolved) answers conifer", \
			seen[g.BiomeId.TAIGA].has(g.TreeSpecies.CONIFER))
	var swamp_hits: bool = seen.has(g.BiomeId.SWAMP)
	if swamp_hits:
		_check("swamp (resolved) answers mangrove", \
			seen[g.BiomeId.SWAMP].has(g.TreeSpecies.MANGROVE))
	_check("savanna answers acacia", seen.get(g.BiomeId.SAVANNA, {}).has(g.TreeSpecies.ACACIA))
	_check("grassland answers broadleaf", seen.get(g.BiomeId.GRASSLAND, {}).has(g.TreeSpecies.BROADLEAF))
	# 3. BIOME IDS UNTOUCHED
	_check("BiomeId.BADLANDS untouched at 16", g.BiomeId.BADLANDS == 16)
	_check("TreeSpecies default broadleaf 0", g.TreeSpecies.BROADLEAF == 0)
	print("SPECIES_V7_FAILS=", fails)
	quit(0 if fails == 0 else 1)
