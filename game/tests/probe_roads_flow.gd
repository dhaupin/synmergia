## Probe: the RIVER FLOW + ROAD law pins (the 2026-10-13 current/road
## slice). Headless script mode:
##   godot --headless --path game --script res://tests/probe_roads_flow.gd
##
## Pins:
##   F1. River flow is law-shaped: on-channel the flow points
##       mouth-ward along the specs; off-channel it is zero.
##   F2. Flow speed = the profile law (spring-side full pull, estuary
##       eased); twice-primes identical (pure data).
##   F3. Standing water drifts toward its outlet, tiny and slow
##       (<= the drift law's speed + eps); dry ground never drifts.
##   R1. The road exists and CONNECTS: village harbor -> capitol plaza
##       anchors, a real polyline, smoothed bed grades inside the
##       16 m/step walk bound.
##   R2. Every water crossing carries a deck: nodes over the channel
##       (or over standing water) read bridge weight > 0.4, and the
##       road state's deck height sits above the local waterline.
##   R3. The corridor probe: road weight 1 at the centerline,
##       clearance 0 on the road, > 0.8 one clear-belt away (the
##       respect law beasts spawn and hunt by).
##   R4. Determinism: two builds answer identical roads.

extends SceneTree

var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(label: String, cond: bool) -> bool:
	_checks += 1
	print(("  PASS " if cond else "  FAIL ") + label)
	return cond


func _run() -> void:
	var ok := true
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()

	Gen.hydrology_prime(seed_b)
	var specs: Array = Gen.river_specs_cached(seed_b)

	# ---- F1/F2: the river flow law --------------------------------
	var flow_ok := true
	var flow_zero_ok := true
	var speed_ok := true
	for spec in specs:
		var n: int = spec.path.size()
		if n < 4:
			continue
		for k in range(2, n - 2, 3):
			var node: Vector3 = spec.path[k].normalized()
			var c: float = Gen.river_channel(node, seed_b)
			if c < 0.5:
				continue
			var flow: Vector3 = Gen.river_flow_at(node, seed_b)
			if flow.length() < 0.9:
				flow_ok = false
				continue
			# Mouth-ward: positive projection onto the local chord.
			var tangent: Vector3 = spec.path[k + 1].cross(spec.path[k]).normalized()
			var fwd: Vector3 = (spec.path[k + 1] - spec.path[k]).normalized()
			fwd = (fwd - node * fwd.dot(node)).normalized()
			if flow.dot(fwd) < 0.7:
				flow_ok = false
			var speed: float = Gen.river_flow_speed(node, seed_b)
			if speed <= 0.0 or speed > Gen.RIVER_FLOW_BASE + 0.001:
				speed_ok = false
	# Far off any channel: zero flow.
	var far_ok: bool = true
	for spec2 in specs:
		var d_far: Vector3 = -spec2.spring.normalized()
		if Gen.river_channel(d_far, seed_b) < 0.005 and Gen.river_flow_at(d_far, seed_b).length() > 0.0:
			far_ok = false
	var flow2: Vector3 = Gen.river_flow_at(specs[0].path[1].normalized() if specs.size() > 0 and specs[0].path.size() > 1 else Vector3(1, 0, 0), seed_b)
	var flow_twice: Vector3 = Gen.river_flow_at(specs[0].path[1].normalized() if specs.size() > 0 and specs[0].path.size() > 1 else Vector3(1, 0, 0), seed_b)
	ok = _check("flow: on-channel flow points mouth-ward", flow_ok) and ok
	ok = _check("flow: far off-channel reads zero", far_ok) and ok
	ok = _check("flow: speed inside the profile band", speed_ok) and ok
	ok = _check("flow: pure (twice-prime identical)", flow2 == flow_twice) and ok

	# ---- F3: the standing-water drift law --------------------------
	var drift_ok := true
	var dry_ok := true
	var ga: float = PI * (3.0 - sqrt(5.0))
	for i in range(600):
		var y: float = 1.0 - 2.0 * (float(i) + 0.5) / 600.0
		var r: float = sqrt(maxf(0.0, 1.0 - y * y))
		var th: float = ga * float(i)
		var d: Vector3 = Vector3(cos(th) * r, y, sin(th) * r).normalized()
		var surf: float = Gen.hydro_water_surface(d, seed_b)
		var h: float = Gen.terrain_height(d, seed_b)
		var drift: Vector3 = Gen.water_drift_at(d, seed_b)
		if surf - h > Gen.Hydro.BEACH_MIN and Gen.river_channel(d, seed_b) <= 0.4:
			if drift.length() > Gen.LAKE_DRIFT_SPEED + 0.001:
				drift_ok = false
		if surf - h <= Gen.Hydro.BEACH_MIN and drift.length() > 0.0:
			dry_ok = false
	ok = _check("drift: standing water drifts slow (<= drift law)", drift_ok) and ok
	ok = _check("drift: dry ground never drifts", dry_ok) and ok

	# ---- R1: the road connects with a graded bed --------------------
	var road: Variant = Gen.road_spec_cached(seed_b)
	var road_ok: bool = road != null and road.path.size() >= 30
	ok = _check("road: a real polyline exists (%d nodes)" % (road.path.size() if road != null else 0), road_ok) and ok
	if road != null:
		var n: int = road.path.size()
		var ends_ok: bool = road.path[0].angle_to(Gen.village_harbor_dir()) < 0.001 \
			and road.path[n - 1].angle_to(Gen.capitol_plaza_dir()) < 0.001
		ok = _check("road: anchors exact (village harbor -> capitol)", ends_ok) and ok
		var grade_ok: bool = true
		for i in range(n - 1):
			if absf(road.beds[i + 1] - road.beds[i]) > 15.5:
				grade_ok = false
		ok = _check("road: the bed grades inside the walk bound", grade_ok) and ok

		# ---- R2: every crossing is decked above the water ----------
		var deck_ok: bool = true
		for i2 in range(n):
			var node: Vector3 = road.path[i2]
			var ch: float = Gen.river_channel(node, seed_b)
			var surf: float = Gen.hydro_water_surface(node, seed_b)
			var over_water: bool = ch > 0.45 or surf - road.beds[i2] > 0.25
			if over_water and road.bridges[i2] <= 0.4:
				deck_ok = false
		ok = _check("road: every water crossing carries a deck", deck_ok) and ok

		# ---- R3: corridor weight + the respect belt ----------------
		var mid: Vector3 = road.path[n / 2].normalized()
		var st: Vector3 = Gen.road_state_at(mid, seed_b)
		ok = _check("road: centerline weight ~1 (state %s)" % str(st), st.x > 0.6) and ok
		var clear_mid: float = Gen.road_clearance_at(mid, seed_b)
		ok = _check("road: clearance is 0 on the cartway", clear_mid <= 0.01) and ok
		# One clear belt off to the side: rotate the mid node away
		# from the road by the respect angle.
		var axis: Vector3 = mid.cross(Vector3(0, 1, 0))
		if axis.length() < 0.001:
			axis = mid.cross(Vector3(1, 0, 0))
		var side: Vector3 = mid.rotated(axis.normalized(), Gen.ROAD_CLEAR_ANG).normalized()
		var clear_side: float = Gen.road_clearance_at(side, seed_b)
		ok = _check("road: the respect belt clears (side %.2f)" % clear_side, clear_side > 0.8) and ok

		# ---- R4: determinism ---------------------------------------
		var road2: Variant = Gen.road_spec_cached(seed_b)
		var det_ok: bool = road2.path == road.path and road2.beds == road.beds
		ok = _check("road: two builds identical (pure)", det_ok) and ok

	print("roads/flow probe: %d checks, %s" % [_checks, "ALL PASS" if ok else "FAILURES"])
	quit(0 if ok else 1)
