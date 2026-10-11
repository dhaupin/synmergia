extends SceneTree

# S14.7 Sundered Sea probe: the authored backend (backend_sundered.gd)
# composes over TerrainGen._natural_raw through the external seam.
# All site sampling runs the backend's own tangent-plane CHART (exact
# orthogonal through/cross coordinates), so the checks read the law
# where it was authored. Checks:
#   1. Chart round-trip: from_chart(x, y) -> _chart() recovers (x, y).
#   2. Channel cut: chart(0, 0) and mid-run are below the sea line.
#   3. Headlands stand: flank bands rise above the sea.
#   4. Shoal ford: crest above the off-shoal floor, still wet.
#   5. Estuary widening: a sea-mouth river's mouth is fatter than its
#      spring (the independent S14.7 estuary law in terrain_gen).
#   6. Spawn guarantee under the backend: plaza + dry apron untouched.
#   7. Island + moat survive (law-native sculpt over the backend).
#   8. Determinism + uninstall identity (bit-natural restore).

const Gen = preload("res://scenes/worlds/terrain_gen.gd")
const Sundered = preload("res://scenes/worlds/backend_sundered.gd")

var checks := 0
var fails := 0


func _check(label: String, cond: bool) -> void:
	checks += 1
	if cond:
		print("  PASS ", label)
	else:
		fails += 1
		print("  FAIL ", label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var seed_bytes: PackedByteArray = Gen.world_seed_bytes()
	var sea: float = Gen.sea_level(seed_bytes)
	var c0: Vector3 = Sundered.STRAIT_CENTER.normalized()
	var run_hi: float = Sundered.RUN_LO + Sundered.RUN_LEN
	var w: float = Sundered.STRAIT_HALF_ANG
	var flank: float = Sundered.HEADLAND_HALF_ANG

	# --- Natural law baseline (uninstalled). ---
	var natural_center: float = Gen.terrain_height(c0, seed_bytes)
	var natural_mid: float = Gen.terrain_height(
		Sundered.from_chart(lerpf(Sundered.RUN_LO, run_hi, 0.5), 0.0), seed_bytes)

	# --- Install the Sundered backend. ---
	Sundered.install()

	# --- 1. Chart round-trip (the probe's own rigor). ---
	var round_ok := true
	for p in [[0.0, 0.0], [0.05, 0.0], [0.05, 0.006], \
		[run_hi * 0.9, -0.009], [run_hi * 0.5, w + flank * 0.5]]:
		var d: Vector3 = Sundered.from_chart(p[0], p[1])
		var back: Vector2 = Sundered._chart(d)
		if absf(back.x - p[0]) > 2e-4 or absf(back.y - p[1]) > 2e-4:
			round_ok = false
			print("    chart-roundtrip off at ", p, " -> ", back)
	var probe_d: Vector3 = Sundered.from_chart(0.05, 0.006)
	var probe_ch: Vector2 = Sundered._chart(probe_d)
	print("    seen: probe_d ", probe_d, " chart ", probe_ch)
	_check("chart round-trip (from_chart -> _chart exact ~2e-4)", round_ok)

	# --- 2. The strait cut exists and is wet. ---
	var center_h: float = Gen.terrain_height(c0, seed_bytes)
	# NB: the center itself is NOT inside the run band (RUN_LO > 0);
	# measure the channel at mid-run.
	var mid_a: float = lerpf(Sundered.RUN_LO, run_hi, 0.5)
	var cut_h: float = Gen.terrain_height(Sundered.from_chart(mid_a, 0.0), seed_bytes)
	_check("strait channel cut below sea line (%.2f < %.2f)" % [cut_h, sea],
		cut_h < sea)

	# --- 3. Headlands stand. ---
	var head_a: float = mid_a  # same x, flank y
	var head_l_h: float = Gen.terrain_height(Sundered.from_chart(head_a, w + flank * 0.5), seed_bytes)
	var head_r_h: float = Gen.terrain_height(Sundered.from_chart(head_a, -(w + flank * 0.5)), seed_bytes)
	_check("headlands rise above the sea (L %.2f, R %.2f)" % [head_l_h, head_r_h],
		head_l_h > sea + 1.0 and head_r_h > sea + 1.0)

	# --- 4. Shoal ford: crest above the floor, still wet. ---
	var x_shoal: float = lerpf(Sundered.RUN_LO, run_hi, Sundered.SHOAL_AT)
	var crest_h: float = Gen.terrain_height(Sundered.from_chart(x_shoal, 0.0), seed_bytes)
	var floor_h: float = Gen.terrain_height(Sundered.from_chart(x_shoal + 3.0 * Sundered.SHOAL_WIDTH, 0.0), seed_bytes)
	_check("shoal rises above the channel floor (+%.2f m)" % [crest_h - floor_h],
		crest_h > floor_h + 3.0)
	_check("shoal stays wet (still below sea)", crest_h < sea)

	# --- 5. Estuary widening: mouth cross-section wider than source.
	var width_ok: bool = false
	var est_ratio: float = 0.0
	for spec in Gen.river_specs_cached(seed_bytes):
		var n: int = spec.path.size()
		if n < 3:
			continue
		# Sea-terminating river only (the estuary law's own gate).
		var end_h: float = Gen._terrain_height_base(spec.path[n - 1], seed_bytes)
		if end_h > sea:
			continue
		var w0: float = _half_width(spec.path[0], seed_bytes)
		var w1: float = _half_width(spec.path[n - 1], seed_bytes)
		if w0 > 0.0 and w1 > w0 * 1.5:
			width_ok = true
			est_ratio = w1 / w0
			break
	var est_msg: String = "estuary widens sea-mouth rivers"
	if width_ok:
		est_msg += " (%.1fx)" % est_ratio
	_check(est_msg, width_ok)

	# --- 6. Spawn guarantee under the backend. ---
	var plaza: float = Gen.terrain_height(Gen.SPAWN_CENTER.normalized(), seed_bytes)
	_check("plaza still flats to SPAWN_HEIGHT",
		absf(plaza - Gen.SPAWN_HEIGHT) < 0.01)
	var apron_dir: Vector3 = Gen.SPAWN_CENTER.rotated(Vector3(0, 0, 1),
		Gen.SPAWN_APRON_ANG * 0.5)
	var apron: float = Gen.terrain_height(apron_dir.normalized(), seed_bytes)
	_check("dry apron holds above sea", apron >= sea + Gen.SPAWN_APRON_SEA_MARGIN - 0.01)

	# --- 7. Island + moat survive the strait. ---
	var isl_top: float = Gen.terrain_height(Gen.ISLAND_CENTER.normalized(), seed_bytes)
	_check("island plateau stands over the strait backend", isl_top > sea + 12.0)
	# The moat ring mid-point along the island->strait line: the same
	# general bearing the run follows; build it from the site frame.
	var moat_ang: float = (Gen.ISLAND_ANGULAR_REACH + Gen.ISLAND_MOAT_OUTER) * 0.5
	var island_c: Vector3 = Gen.ISLAND_CENTER.normalized()
	var to_strait: Vector3 = island_c.cross(c0).normalized()
	var moat_dir: Vector3 = island_c.rotated(to_strait, moat_ang)
	var moat_h: float = Gen.terrain_height(moat_dir, seed_bytes)
	_check("moat channel cut", moat_h < sea - Gen.ISLAND_MOAT_DEPTH + 0.01)

	# --- 8. Determinism + uninstall identity. ---
	var mid_h: float = Gen.terrain_height(Sundered.from_chart(mid_a, 0.0), seed_bytes)
	var mid_again: float = Gen.terrain_height(Sundered.from_chart(mid_a, 0.0), seed_bytes)
	_check("backend answer deterministic", absf(mid_h - mid_again) < 1e-9)
	Gen.uninstall_terrain_backend()
	var back_c: float = Gen.terrain_height(c0, seed_bytes)
	_check("uninstall returns the natural law (center)",
		absf(back_c - natural_center) < 0.001)
	var back_m: float = Gen.terrain_height(
		Sundered.from_chart(mid_a, 0.0), seed_bytes)
	_check("uninstall identity at the mid-run sample",
		absf(back_m - natural_mid) < 0.001)

	print("--- RESULTS: %d passed, %d failed ---" % [checks - fails, fails])
	quit(0 if fails == 0 else 1)


## River-channel half-width (radians) at a direction: binary-scan along
## a small circle through `dir` until the river_channel field halves.
## Returns 0 if the field is not > 0.5 AT the site (no channel).
func _half_width(dir: Vector3, seed_bytes: PackedByteArray) -> float:
	var c: float = Gen.river_channel(dir, seed_bytes)
	if c < 0.5:
		return 0.0
	var axis: Vector3 = dir.cross(Vector3(0, 1, 0)) if dir.dot(Vector3(0, 1, 0)) < 0.9 else dir.cross(Vector3(1, 0, 0))
	axis = axis.normalized()
	var lo: float = 0.0
	var hi: float = 0.06  # generous
	for _it in range(24):
		var mid_ang: float = (lo + hi) * 0.5
		if Gen.river_channel(dir.rotated(axis, mid_ang), seed_bytes) >= c * 0.5 - 0.001:
			lo = mid_ang
		else:
			hi = mid_ang
	return (lo + hi) * 0.5
