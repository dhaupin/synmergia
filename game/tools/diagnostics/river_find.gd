extends SceneTree
## Deep-dive: follow ONE spring's flow step by step, printing base +
## press + dip at each node, plus the 8 candidates' base/press at the
## step where the flow stops, so the starvation mechanism is read
## from data instead of inferred.

func _init() -> void:
	print("river_dive: loaded")
	call_deferred("_run")

func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var sea: float = Gen.sea_level(seed_b)
	var spring: Vector3 = Vector3(0.961, 0.130, -0.245).normalized()
	var springs_first: Array = Gen.river_springs(seed_b)
	print("FIRST river_springs=%d" % springs_first.size())
	var specs: Array = Gen.river_specs_cached(seed_b)
	print("RIVER_SPECS=%d" % specs.size())
	var springs: Array = Gen.river_springs(seed_b)
	print("AFTER cache river_springs=%d" % springs.size())
	for s_ in springs:
		print("  LAW spring dir=%s base=%.1f" % [str(s_.spring), Gen._terrain_height_base(s_.spring, seed_b) - sea])
	# Gate census over the 24 draws (same rng stream as the law): how
	# many landed water (< sea), how many low-land (< 0.3), how many
	# land-legal; per land-legal, the river_path it now produces.
	var s_i: int = 0
	var land_ok: int = 0
	for i in range(24):
		var acc: int = Gen._seed_salt(seed_b, "hydro_springs")
		acc = (acc * 131 + i) % 9007199254740991
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = acc
		for _try2 in range(8):
			var d2: Vector3 = Vector3(rng2.randf() * 2.0 - 1.0, rng2.randf() * 2.0 - 1.0, rng2.randf() * 2.0 - 1.0)
			if d2.length() < 0.001:
				continue
			d2 = d2.normalized()
			s_i += 1
			var lb: float = Gen._land_mass(d2, Gen._seed_salt(seed_b, "terrain"))
			var hb: float = Gen._terrain_height_base(d2, seed_b)
			if lb < 0.3:
				continue
			if hb < sea:
				continue
			land_ok += 1
			var pv: PackedVector3Array = Gen.river_path(d2, seed_b)
			print("draw %d land_ok=%d base=%.1f path_len=%d carved_end=%.1f" % [
				s_i, land_ok, hb - sea, pv.size(), (Gen.terrain_height(pv[pv.size() - 1], seed_b) - sea)])
			break
	for s_ in springs:
		var pd: Vector3 = s_.path[s_.path.size() - 1]
		var base_s: float = Gen._terrain_height_base(s_.spring, seed_b)
		var base_e: float = Gen._terrain_height_base(pd, seed_b)
		print("  spring base=%.1f end base=%.1f len=%d" % [base_s, base_e, s_.path.size()])
	var path: PackedVector3Array = specs[0].path if specs.size() > 0 else PackedVector3Array()
	for i in range(path.size()):
		var d: Vector3 = path[i]
		var base_h: float = Gen._terrain_height_base(d, seed_b)
		var carved: float = Gen.terrain_height(d, seed_b)
		var dip: float = base_h - Gen.hydro_lake_carve(d, seed_b, base_h)
		print("node %d base=%.2f carved=%.2f dip=%.2f (sea %.2f)" % [i, base_h - sea, carved - sea, dip, sea])
	# The 8 candidates at the LAST node:
	if path.size() > 0:
		var cur: Vector3 = path[path.size() - 1]
		var hint: Vector3 = Vector3(0, 1, 0) if absf(cur.dot(Vector3(0, 1, 0))) < 0.9 else Vector3(1, 0, 0)
		var t1: Vector3 = cur.cross(hint).normalized()
		var t2: Vector3 = cur.cross(t1).normalized()
		for k in range(8):
			var ang: float = TAU * float(k) / 8.0
			var tangent: Vector3 = t1 * cos(ang) + t2 * sin(ang)
			var rot_axis: Vector3 = tangent.cross(cur)
			var cand: Vector3 = cur.rotated(rot_axis.normalized(), Gen.Hydro.RIVER_STEP_ANG).normalized()
			var bb: float = Gen._terrain_height_base(cand, seed_b)
			var cc: float = Gen.terrain_height(cand, seed_b)
			print("cand %d base=%.2f carved=%.2f (sea %.2f)" % [k, bb - sea, cc - sea, sea])
	quit(0)
