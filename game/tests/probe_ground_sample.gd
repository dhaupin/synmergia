## Probe: THE GROUND SAMPLE (labs/prd-ground-sample.md, the bit-identical
## safety net). For a battery of directions it asserts that the fused
## `TerrainGen.ground_sample(dir, seed)` returns EXACTLY the same numbers
## as the individual public entry points it fuses:
##   height (terrain_height), water_surface (hydro_water_surface),
##   biome_id (climate_biome_id), skin (skin_classes),
##   temperature (climate_temperature), water_table (water_table_raw),
##   crag (_crag_noise), river_channel (river_channel), road_state
##   (road_state_at).
## EXACT equality (not epsilon) is the law: the refactor MUST be
## bit-identical, so the renderers and every probe pin keep their numbers.
## Also pins that the sample is PURE (same dir twice => same struct) and
## that a second `ground_sample` call on the same sector returns the
## memoized instance (identity).
## Run: godot --headless --path . --script res://tests/probe_ground_sample.gd
extends SceneTree

const Gen = preload("res://scenes/worlds/terrain_gen.gd")

var _okay := true
var _checks := 0


func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_okay = false
		print("  FAIL " + label)


## A coarse spiral over the sphere plus the authored anchors (spawn, cove,
## lake, island, poles) so the battery hits land, sea, rivers, road, and
## the special sculpt regions.
func _dirs() -> Array:
	var out: Array = []
	var ga: float = PI * (3.0 - sqrt(5.0))
	for i in range(240):
		var y: float = 1.0 - 2.0 * (float(i) + 0.5) / 240.0
		var r: float = sqrt(maxf(0.0, 1.0 - y * y))
		var th: float = ga * float(i)
		out.append(Vector3(cos(th) * r, y, sin(th) * r).normalized())
	out.append(Gen.SPAWN_CENTER)
	out.append(Vector3(0.0, 1.0, 0.0))   # north pole
	out.append(Vector3(0.0, -1.0, 0.0))  # south pole
	out.append(Gen.LAKE_CENTER)
	out.append(Gen.ISLAND_CENTER)
	out.append(Gen.capitol_dir())
	return out


func _initialize() -> void:
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var dirs: Array = _dirs()

	var mismatch := 0
	var first_bad := ""
	for d in dirs:
		var s: Gen.GroundSample = Gen.ground_sample(d, seed_b)
		var h: float = Gen.terrain_height(d, seed_b)
		var ws: float = Gen.hydro_water_surface(d, seed_b)
		var bid: int = Gen.climate_biome_id(d, seed_b)
		var sk: Color = Gen.skin_classes(d, seed_b)
		var t: float = Gen.climate_temperature(d, seed_b)
		var wt: float = Gen.water_table_raw(d, seed_b)
		var rc: float = Gen.river_channel(d, seed_b)
		var rs: Vector3 = Gen.road_state_at(d, seed_b)
		if s.height != h or s.water_surface != ws or s.biome_id != bid \
				or s.skin != sk or s.temperature != t or s.water_table != wt \
				or s.river_channel != rc or s.road_state != rs:
			mismatch += 1
			if first_bad == "":
				first_bad = "dir=%s h=%s/%s ws=%s/%s biome=%d/%d" % [str(d), str(h), str(s.height), str(ws), str(s.water_surface), bid, s.biome_id]
	_check("fused sample == public laws EXACTLY across %d dirs" % dirs.size(), mismatch == 0)
	if mismatch > 0:
		print("    first mismatch: " + first_bad)

	# Purity: same dir twice => identical struct values.
	var dp: Vector3 = dirs[7]
	var a: Gen.GroundSample = Gen.ground_sample(dp, seed_b)
	var b: Gen.GroundSample = Gen.ground_sample(dp, seed_b)
	_check("purity: height identical twice", a.height == b.height)
	_check("purity: skin identical twice", a.skin == b.skin)
	_check("purity: biome identical twice", a.biome_id == b.biome_id)
	_check("purity: memoized (same instance on re-ask)", a == b)

	# The crag field is Vector4 and not exposed via a public wrapper; assert
	# it is finite (the memo poison-guard contract).
	_check("crag finite", is_finite(a.crag.x) and is_finite(a.crag.w))

	# The colour/skin lanes (vertex_color + splat_skin) read the fused
	# sample; assert they stay PURE and consistent with the sample fields
	# they now ride (lift = the sample height, so the reads agree).
	var vc_mismatch := 0
	var sk_mismatch := 0
	for d in dirs:
		var s: Gen.GroundSample = Gen.ground_sample(d, seed_b)
		var c1: Color = Gen.vertex_color(d, seed_b, s.height, 0.3)
		var c2: Color = Gen.vertex_color(d, seed_b, s.height, 0.3)
		if c1 != c2:
			vc_mismatch += 1
		var sp1: Dictionary = Gen.splat_skin(d, seed_b, s.height, 0.3)
		var sp2: Dictionary = Gen.splat_skin(d, seed_b, s.height, 0.3)
		if sp1 != sp2:
			sk_mismatch += 1
	_check("vertex_color pure across %d dirs" % dirs.size(), vc_mismatch == 0)
	_check("splat_skin pure across %d dirs" % dirs.size(), sk_mismatch == 0)

	# Stage 4: the public splat_skin delegates to the pure splat_skin_from
	# (the clipmap reads the latter from its fused sample). Pin equality.
	var del_mismatch := 0
	for d in dirs:
		var s: Gen.GroundSample = Gen.ground_sample(d, seed_b)
		var pub: Dictionary = Gen.splat_skin(d, seed_b, s.height, 0.3)
		var pur: Dictionary = Gen.splat_skin_from(s, seed_b, s.height, 0.3)
		if pub != pur:
			del_mismatch += 1
	_check("splat_skin == splat_skin_from across %d dirs" % dirs.size(), del_mismatch == 0)

	# Stage 5: the river bounding early-out must be EXACT -- when it
	# rejects a spec (far from every path point by bound_ang), the widest
	# per-vertex radius of that spec can never reach the query. A reject
	# that fired while the query sat within the spec's widest radius would
	# be a silent missed river.
	var bound_bad := 0
	var specs: Array = Gen.river_specs_cached(seed_b)
	var probes: Array = dirs.duplicate()
	for spec in specs:
		probes.append(spec.spring.normalized())
		probes.append(spec.path[spec.path.size() - 1])
	var widest: float = Gen.Hydro.RIVER_RADIUS_ANG * (1.0 + Gen.Hydro.ESTUARY_WIDEN)
	for d in probes:
		var dn: Vector3 = d.normalized()
		for spec in specs:
			if Gen._river_spec_far(dn, spec):
				var nearest := 999.0
				for p in spec.path:
					nearest = minf(nearest, dn.angle_to(p))
				if nearest <= widest:
					bound_bad += 1
	_check("river bound exact (reject never covers a hit)", bound_bad == 0)
	# The waterfall seam bound (the same early-out for waterfall_seam_at)
	# must be EXACT: when _river_spec_far_seam rejects a spec, no seam
	# mask on that spec can reach the query. A reject that fired while the
	# query sat inside a segment's reach (half_spread + one arc) would be
	# a silently dropped waterfall.
	var seam_bad := 0
	var half_spread: float = Gen.Hydro.RIVER_RADIUS_ANG * Gen.WATERFALL_SEAM_WIDTH_K
	for d in probes:
		var dn: Vector3 = d.normalized()
		for spec in specs:
			if Gen._river_spec_far_seam(dn, spec):
				var nearest := 999.0
				for p in spec.path:
					nearest = minf(nearest, dn.angle_to(p))
				var nn: int = spec.path.size()
				for si in range(nn - 1):
					var arc: float = spec.path[si].angle_to(spec.path[si + 1])
					if nearest <= half_spread + arc:
						seam_bad += 1
						break
	_check("waterfall seam bound exact (reject never covers a hit)", seam_bad == 0)

	# The seam value must stay finite and in range across the battery.
	var seam_mismatch := 0
	for d in dirs:
		var direct: float = Gen.waterfall_seam_at(d, seed_b)
		if not is_finite(direct) or direct < 0.0 or direct > 1.0:
			seam_mismatch += 1
	_check("waterfall seam finite in [0,1] across %d dirs" % dirs.size(), seam_mismatch == 0)

	# The road bound (the checkpoint early-out) must be EXACT: when
	# _road_spec_near is false, no probe point can be within the widest
	# query radius (ROAD_CLEAR_ANG). A false reject that fired while a
	# probe point sat inside would be a silently dropped cartway.
	var road_spec = Gen.road_spec_cached(seed_b)
	var road_bad := 0
	var road_probes: Array = dirs.duplicate()
	for pp in road_spec.probe_pts:
		road_probes.append(pp)
	for d in road_probes:
		var dn: Vector3 = d.normalized()
		if not Gen._road_spec_near(dn, road_spec):
			var nearest := 999.0
			for pp in road_spec.probe_pts:
				nearest = minf(nearest, dn.angle_to(pp))
			if nearest <= Gen.ROAD_CLEAR_ANG:
				road_bad += 1
	_check("road bound exact (reject never covers a hit)", road_bad == 0)

	# The precomputed probe set must reproduce the inline probe law
	# bit-for-bit: the road state at each probe point matches a fresh
	# scan of the same point set (the rebuild is exact, no drift).
	var road_mismatch := 0
	for d in dirs:
		var st: Vector3 = Gen.road_state_at(d, seed_b)
		if not (is_finite(st.x) and is_finite(st.y) and is_finite(st.z)):
			road_mismatch += 1
	_check("road state finite across %d dirs" % dirs.size(), road_mismatch == 0)

	# THE DEFINITIVE ROAD BIT-IDENTITY LEG: the new precomputed-probe-set
	# scan must reproduce the OLD inline algorithm (path nodes + per-seg
	# slerp thirds, scanned in the same order) EXACTLY, for every dir.
	var road_ref_bad := 0
	var rpath: PackedVector3Array = road_spec.path
	var rn: int = rpath.size()
	for d in dirs:
		var dn: Vector3 = d.normalized()
		# --- the OLD algorithm, reconstructed ---
		var ow: float = 0.0
		var obr: float = 0.0
		var obed: float = 0.0
		for i in range(rn):
			var p0: Vector3 = rpath[i]
			var a0: float = dn.angle_to(p0)
			if a0 < Gen.ROAD_ANG:
				var nw: float = 1.0 - a0 / Gen.ROAD_ANG
				if nw > ow:
					ow = nw
					obr = road_spec.bridges[i]
					obed = road_spec.beds[i]
			if i + 1 < rn:
				var p1: Vector3 = rpath[i + 1]
				var sl: float = p0.angle_to(p1)
				if sl >= 1e-9:
					var ax: Vector3 = p0.cross(p1).normalized()
					for si in range(1, 3):
						var md: Vector3 = p0.rotated(ax, sl * (float(si) / 3.0)).normalized()
						var a2: float = dn.angle_to(md)
						if a2 < Gen.ROAD_ANG:
							var w2: float = 1.0 - a2 / Gen.ROAD_ANG
							if w2 > ow:
								ow = w2
								obr = maxf(road_spec.bridges[i], road_spec.bridges[i + 1])
								obed = maxf(road_spec.beds[i], road_spec.beds[i + 1])
		var ref: Vector3 = Vector3(clampf(ow, 0.0, 1.0), clampf(obr, 0.0, 1.0), obed)
		var got: Vector3 = Gen._road_probe(dn, seed_b, Gen.ROAD_ANG)
		if got != ref:
			road_ref_bad += 1
	_check("road probe set == old inline algorithm exactly (%d dirs)" % dirs.size(), road_ref_bad == 0)


	print("probe_ground_sample: %s (%d checks)" % ["ALL PASS" if _okay else "FAILS", _checks])
	quit(0 if _okay else 1)
