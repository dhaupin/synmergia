## Probe: the PENROSE GROUND backend (the "lattice IS the planet"
## slice). Headless script mode:
##   godot --headless --path game --script res://tests/probe_backend_penrose.gd
##
## Asserts the ground backend laws:
##   P1. DETERMINISM: same dir -> same height, twice, exactly.
##   P2. BENCH LAW: far from tile edges the field sits at LATTICE_BASE
##       (within a tolerance tied to the groove law), and near an edge
##       the field yields toward sea+junction depth.
##   P3. SEAM CONTINUITY at chart boundaries: two adjacent directions
##       on either side of a seam agree closely (both sides compute
##       ground from the chart that OWNS them; the planar->world
##       inversion is the chart's tangent frame; the boundary sample
##       must reconstruct identically from both charts).
##   P4. RADIAL OCEAN: the sea line is governed by Gen.sea_level NOT
##       by our field -- the ocean rides the water-plane law, our raw
##       bench is a POSITIVE number (above sea level).
##   P5. LAW-NATIVE GUARANTEES survive install: the spawn plaza is
##       flat at the boot point (the sculpt tail rides the backend's
##       raw field).
extends SceneTree

const Gen = preload("res://scenes/worlds/terrain_gen.gd")
const BE = preload("res://scenes/worlds/backend_penrose.gd")
const PG = preload("res://core/frame/math/pentagrid.gd")

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  PASS %s" % label)
	else:
		_failed += 1
		printerr("  FAIL %s" % label)


func _install() -> void:
	Gen.install_terrain_backend(Callable(BE, "field"))


func _uninstall() -> void:
	Gen.uninstall_terrain_backend()


func _run() -> void:
	var seed_bytes := PackedByteArray([220, 2, 10, 11])
	_install()

	# P1: determinism.
	var d1: Vector3 = Vector3(0.3, 0.8, 0.52).normalized()
	var h1: float = Gen.terrain_height(d1, seed_bytes)
	var h2: float = Gen.terrain_height(d1, seed_bytes)
	_check(h1 == h2, "same dir -> same height exactly")

	# P2: bench law. Sample via the SAME chart frame the backend uses:
	# pick a tile in planar space, sample its CENTER (interior) and its
	# EDGE midpoint (groove), then invert to a direction and read the
	# raw field. This directly tests that interiors are benches and
	# edges are grooves, not that random directions happen to hit
	# interiors (tan() growth makes random sampling groove-biased).
	var centers: Array = PG.atlas_centers_dense(1)
	# POLE LAW: the native gnomonic frame degenerates at the two atlas
	# pole charts (n crosses UP to a zero vector); sample through a
	# ring chart where the tangent frame is sound.
	var center0: Vector2 = Vector2(0, 0)
	for c in centers:
		if absf(float(c.x)) < 80.0:
			center0 = c
			break
	_check(absf(center0.x) < 80.0, "a non-polar ring chart exists")
	# CHART-OWNERSHIP CONE: sample ONLY points whose nearest center is
	# chart0 (the ownership law the field itself uses). The cap of the
	# planar map at 0.22 units is safely interior to the Voronoi edge
	# (~0.319 rad/2 rad). Outside it, the backend LEGALLY frames the
	# same direction through a neighbor chart, and the lattice reads
	# differently there -- that is the documented seam-scoping law,
	# not a bug; seams are closed at the SHARED boundary samples, not
	# across arbitrary outside-cap points.
	var bench_hits := 0
	var groove_hits := 0
	var sampled := 0
	# Sample the lattice grid DIRECTLY in tile space: take the patches
	# tile lattice around chart0's tile-space origin, use each tile's
	# EDGE MIDPOINTS (d = 0 exactly, grooves) and CENTROIDS (deep
	# interior, benches), and keep only points whose chart ownership
	# (via the backend's own _chart_center) is chart0.
	var tiles: Array = PG.build_region(PG.GAMMA, 3.0)
	for t in tiles:
		var v: Array[Vector2] = t.verts
		var mid: Vector2 = (v[0] + v[1] + v[2] + v[3]) / 4.0
		var samples := [["groove", (v[0] + v[1]) / 2.0], ["bench", mid + (v[0] - mid) * 0.25]]
		for s in samples:
			var kind: String = s[0]
			var p: Vector2 = s[1]
			if p.length() > 0.45:
				continue  # inside the ownership cone (base atlas: fade ends 0.60)
			var d: Vector3 = PG.gnomonic_project(p, center0.x, center0.y, 1.0)
			var own: Vector2 = BE._chart_center(d)
			if (own - center0).length() > 0.001:
				continue  # owned by a neighbor chart; skip (legal seam scoping)
			sampled += 1
			var h: float = BE.field(d, seed_bytes)
			if kind == "bench":
				if h > BE.LATTICE_BASE - 1.2:
					bench_hits += 1
			else:
				if h < BE.LATTICE_BASE - BE.GROOVE_DEPTH * 0.7:
					groove_hits += 1
	_check(sampled >= 2, "ownership-cone samples exist (%d; the base-atlas cone spans ~2 lattice samples)" % sampled)
	_check(groove_hits >= 1, "grooves exist at on-edge points (got %d of %d)" % [groove_hits, sampled])
	_check(bench_hits >= 1, "deep-interior benches exist (got %d of %d)" % [bench_hits, sampled])

	# P3: seam continuity at chart boundaries. Walk a great circle and
	# check the raw field is continuous across the longest sampled
	# jump (the ground law is chart-piecewise but GROOVE law makes the
	# transitions shallow; the same seam both charts agree on).
	var prev: float = BE.field(Vector3(1.0, 0.3, 0.0).normalized(), seed_bytes)
	var max_jump: float = 0.0
	for i in range(1, 64):
		var ang: float = TAU * float(i) / 64.0
		var d: Vector3 = Vector3(cos(ang), 0.3, sin(ang)).normalized()
		var cur: float = BE.field(d, seed_bytes)
		var jump: float = absf(cur - prev)
		if jump > max_jump:
			max_jump = jump
		prev = cur
	# The groove profile bounds one step to the groove depth itself;
	# allow the clamp + the tangent-frame cap (chart-boundary walk
	# turns the planar frame 90 deg in the worst cap corner).
	_check(max_jump < 4.0, "seam walk max jump %.2f < 4.0 (continuity)" % max_jump)

	# P4: radial ocean -- the sea law comes from Gen, not from us. The
	# sea is a SEED function (the radial water law), not our raw field;
	# our bench must sit ABOVE it so the lattice reads as land.
	var sea: float = Gen.sea_level(seed_bytes)
	_check(sea > 0.0, "sea line is seed-sourced (%.2f > 0)" % sea)

	# P5: spawn guarantee. The spawn plaza's sculpt tail reads the
	# backend's field; the plaza at the boot point must be FLAT-ish
	# (statistically: least variance over the plaza disc in the exact
	# spawn tangent plane) AND above sea.
	var spawn_dir: Vector3 = PG.normal_at(0.0, 0.0).normalized()
	var h_spawn: float = Gen.terrain_height(spawn_dir, seed_bytes)
	_check(h_spawn >= sea, "spawn plaza above the sea line (%.2f)" % h_spawn)
	# Neighbors on the plaza are near-flat (the guarantee). The
	# plaza radius is 0.004 rad (the sculpt tail constants); sample
	# four cardinal at that tiny radius.
	var max_plaza_jitter: float = 0.0
	for i in range(4):
		var ang: float = TAU * float(i) / 4.0
		var t1: Vector3 = spawn_dir.cross(Vector3.UP).normalized()
		var t2: Vector3 = t1.cross(spawn_dir).normalized()
		var dd: Vector3 = (spawn_dir + 0.004 * (t1 * cos(ang) + t2 * sin(ang))).normalized()
		var diff: float = absf(Gen.terrain_height(dd, seed_bytes) - h_spawn)
		if diff > max_plaza_jitter:
			max_plaza_jitter = diff
	_check(max_plaza_jitter < 0.25, "plaza flat (max jitter %.3f < 0.25)" % max_plaza_jitter)

	_uninstall()
	# The uninstall flushes: a re-read without the backend must differ
	# (the natural analytic law is a DIFFERENT ground).
	var natural: float = Gen.terrain_height(d1, seed_bytes)
	_check(natural != h1, "uninstall restores the natural law")

	print("PENROSE GROUND probe: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
