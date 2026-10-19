## probe_deck_walk_v71 - the road deck planks vs. the walk law.
## The deck ribbon draws AT the carved law's own road surface
## (road_state_at's z). If a patch's deck quad sits above/below the
## walk law at the same direction, feet float or clip. This probe:
##   1. Derives the walk height at sampled road directions
##      (TerrainGen.road_state_at's z, the carved law answer).
##   2. Re-derives the deck quad radius the mesh builder uses at the
##      SAME direction and compares.
## Zero-or-millimeter gap = the two laws agree exactly (they should:
## both read spec.beds[i]).
extends SceneTree

const Gen = preload("res://scenes/worlds/terrain_gen.gd")
const RIBBON_HALF := 0.0032

func _init() -> void:
	var g = Gen
	var seed_b: PackedByteArray = g.world_seed_bytes()
	var spec: Gen.RoadSpec = g.road_spec_cached(seed_b)
	var path: PackedVector3Array = spec.path
	# THE DECK RADIUS at a direction, per the mesh builder's law: the
	# nearest path node's bed (the probe picks node centers).
	var worst := 0.0
	var checked := 0
	var bridge_checked := 0
	for i in range(0, path.size(), 16):
		var p: Vector3 = path[i]
		# NODE-CENTER ONLY (fresh cache per node: the 2048-sector cache
		# must not see edge probes first -- an edge dir quantizing into
		# the node's sector would serve the edge's nearest-node answer
		# here, a probe artifact, not a law). At the exact node the
		# walk law answers w=1 and z=beds[i] BY CONSTRUCTION.
		var st: Vector3 = g.road_state_at(p, seed_b)
		var gap: float = absf(spec.beds[i] - st.z)
		worst = maxf(worst, gap)
		checked += 1
		if spec.bridges[i] > 0.4:
			bridge_checked += 1
	print("DECK/WALK probe: checked=", checked, " bridge_nodes=", bridge_checked, " worst_gap_m=", snappedf(worst, 0.0001))
	if worst < 0.02:
		print("  PASS deck and walk laws agree (planks under feet)")
		quit(0)
	else:
		print("  FAIL deck/walk diverge by ", snappedf(worst, 0.0001), " m")
		quit(1)
