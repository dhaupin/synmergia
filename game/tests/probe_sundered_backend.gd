## Probe: THE SUNDERED STRAIT BACKEND (Lane M -- re-verify + install).
## Headless: godot --headless --path game --script res://tests/probe_sundered_backend.gd
##
## backend_sundered.gd (TerrainBackendSundered) AUTHORS the Sundered
## Strait over the home world's natural geology: a navigable channel
## from the ferry moat ring out to open water, two headlands, a
## wreck-shoal ford. It COMPOSES over TerrainGen._natural_raw -- the
## home continent and the polar caps must NOT move.
##
## This probe installs the backend through the REAL seam (the exact
## lines globe_world._install_world_backend runs: read world_main's
## terrain_backend_id, resolve res://scenes/worlds/backend_<id>.gd,
## Gen.install_terrain_backend(Callable(script, "field"))) and checks:
##   0. The declaration + the seam resolve (world_main declares the
##      backend; the script exists; the Callable installs).
##   1. The field is FINITE everywhere (fibonacci sphere sweep) and
##      respects the TERRAIN_MAX ceiling.
##   2. The corridor CARVES: the channel floor is below the sea line
##      (navigable) the whole run, at the centerline.
##   3. The headlands STAND: the flank bands are dry (above sea).
##   4. The shoal is a WET FORD: crest above the off-shoal floor,
##      still below the sea line.
##   5. THE COMPOSE LAW: the spawn dome (plaza + apron) and the polar
##      caps read IDENTICAL to the natural law -- a far strait must not
##      move the home continent or the poles.
##   6. Determinism + clean uninstall (bit-natural restore).
##
## Exit 0 = pass.

extends SceneTree

const Gen = preload("res://scenes/worlds/terrain_gen.gd")
const Sundered = preload("res://scenes/worlds/backend_sundered.gd")

var _checks := 0
var _fails := 0

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS ", label)
	else:
		_fails += 1
		print("  FAIL ", label)


func _init() -> void:
	# Script-mode boot law: _init runs before autoload globals register,
	# so the pass defers to the queued call (the probe_terrain_backend
	# pattern).
	call_deferred("_run")


## The real seam: the id the world declares (empty when dormant).
func _declared_backend_id() -> String:
	var wd: Resource = load("res://data/worlds/world_main.tres")
	if wd == null or not ("terrain_backend_id" in wd):
		return ""
	return str(wd.terrain_backend_id)


## Fibonacci sphere direction (even coverage of the whole sphere).
func _fib_dir(i: int, n: int) -> Vector3:
	var ga: float = PI * (3.0 - sqrt(5.0))
	var y: float = 1.0 - 2.0 * (float(i) + 0.5) / float(n)
	var r: float = sqrt(maxf(0.0, 1.0 - y * y))
	var th: float = ga * float(i)
	return Vector3(cos(th) * r, y, sin(th) * r)


func _run() -> void:
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var sea: float = Gen.sea_level(seed_b)
	var run_hi: float = Sundered.RUN_LO + Sundered.RUN_LEN
	var w: float = Sundered.STRAIT_HALF_ANG
	var flank: float = Sundered.HEADLAND_HALF_ANG
	print("seed_ok=%s sea=%.2f TERRAIN_MAX=%.1f" % [str(seed_b.size() > 0), sea, Gen.TERRAIN_MAX])

	# ---- 0. The declaration + the real seam -------------------------
	var declared: String = _declared_backend_id()
	_check("world_main declares terrain_backend_id = 'sundered' (got '%s')" % declared,
		declared == "sundered")
	var backend_id: String = declared if not declared.is_empty() else "sundered"
	var script_path: String = "res://scenes/worlds/backend_%s.gd" % backend_id
	_check("backend script resolves at %s" % script_path,
		ResourceLoader.exists(script_path))
	if not ResourceLoader.exists(script_path):
		print("--- RESULTS: %d passed, %d failed ---" % [_checks - _fails, _fails])
		quit(1)
		return
	var backend_script = load(script_path)

	# ---- Natural baselines (BEFORE install) -------------------------
	# Spawn dome + polar cap samples must survive the install untouched.
	var spawn_samples: Array = [Gen.SPAWN_CENTER.normalized()]
	for a in [0.01, 0.03, 0.05, 0.07, 0.088]:
		for b in range(8):
			var az: float = TAU * float(b) / 8.0
			var axis: Vector3 = Vector3(cos(az), 0.0, sin(az)).normalized()
			spawn_samples.append(Gen.SPAWN_CENTER.normalized().rotated(axis, a))
	var polar_samples: Array = [Vector3(0, 1, 0), Vector3(0, -1, 0)]
	for pole in [Vector3(0, 1, 0), Vector3(0, -1, 0)]:
		for a in [0.05, 0.15, 0.25, 0.33]:
			for b in range(6):
				var az2: float = TAU * float(b) / 6.0
				var ax2: Vector3 = Vector3(cos(az2), 0.0, sin(az2)).normalized()
				polar_samples.append(pole.rotated(ax2, a).normalized())
	var home_samples: Array = []
	for i in range(60):
		var d: Vector3 = _fib_dir(i, 200)
		if d.angle_to(Gen.SPAWN_CENTER) < 0.68 and d.angle_to(Gen.ISLAND_CENTER.normalized()) > 0.05:
			home_samples.append(d)

	var nat_spawn: Array = []
	for d in spawn_samples:
		nat_spawn.append(Gen.terrain_height(d, seed_b))
	var nat_polar: Array = []
	for d in polar_samples:
		nat_polar.append(Gen.terrain_height(d, seed_b))
	var nat_home: Array = []
	for d in home_samples:
		nat_home.append(Gen.terrain_height(d, seed_b))

	# ---- Install through the REAL seam ------------------------------
	Gen.install_terrain_backend(Callable(backend_script, "field"))
	_check("backend installs through the seam (terrain_backend_installed)",
		Gen.terrain_backend_installed())

	# ---- 1. Finiteness over the whole sphere ------------------------
	var finite_ok := true
	var ceiling_ok := true
	var n_sweep := 3000
	var worst: float = -INF
	for i in range(n_sweep):
		var d: Vector3 = _fib_dir(i, n_sweep)
		var h: float = Gen.terrain_height(d, seed_b)
		if not is_finite(h):
			finite_ok = false
			print("    non-finite at ", d)
			break
		if h > Gen.TERRAIN_MAX + 1e-3:
			ceiling_ok = false
			print("    over-ceiling at ", d, " h=", h)
			break
		worst = maxf(worst, h)
	_check("field finite over the whole sphere (%d fibonacci samples)" % n_sweep, finite_ok)
	_check("field respects the TERRAIN_MAX ceiling (worst %.1f <= %.1f)" % [worst, Gen.TERRAIN_MAX],
		ceiling_ok)

	# ---- 2. The corridor carves (navigable channel) -----------------
	var corridor_ok := true
	var corridor_lo := INF
	var corridor_hi := -INF
	for i in range(21):
		var x: float = lerpf(Sundered.RUN_LO + 0.002, run_hi - 0.002, float(i) / 20.0)
		var h: float = Gen.terrain_height(Sundered.from_chart(x, 0.0), seed_b)
		corridor_lo = minf(corridor_lo, h)
		corridor_hi = maxf(corridor_hi, h)
		if h >= sea:
			corridor_ok = false
			print("    corridor dry at x=%.3f h=%.2f (sea %.2f)" % [x, h, sea])
	_check("corridor is navigable the whole run (floor %.2f..%.2f < sea %.2f)"
		% [corridor_lo, corridor_hi, sea], corridor_ok)

	# ---- 3. The headlands stand (dry) -------------------------------
	# Sampled across the run INTERIOR (a small inset): the corridor is
	# a finite authored RECTANGLE, and a sample authored EXACTLY on the
	# x = RUN_LO edge round-trips through from_chart/_chart with a ~2e-8
	# rad float error that can land a hair OUTSIDE the rectangle, where
	# the backend correctly serves the natural field. That knife-edge is
	# a measurement artifact, not a compose failure; the mouth-edge
	# behavior is measured and printed separately below.
	var head_ok := true
	var head_min := INF
	var inset: float = 0.002
	for i in range(21):
		var x: float = lerpf(Sundered.RUN_LO + inset, run_hi - inset, float(i) / 20.0)
		for sgn in [1.0, -1.0]:
			var h: float = Gen.terrain_height(Sundered.from_chart(x, sgn * (w + flank * 0.5)), seed_b)
			head_min = minf(head_min, h)
			if h <= sea + 1.0:
				head_ok = false
				print("    headland wet at x=%.3f y=%+.4f h=%.2f" % [x, sgn * (w + flank * 0.5), h])
	_check("headlands stand dry across the run interior (min %.2f > sea %.2f + 1)" % [head_min, sea], head_ok)
	# The corridor floor across the same interior (the navigable read).
	var corr_hi := -INF
	for i in range(21):
		var x: float = lerpf(Sundered.RUN_LO + inset, run_hi - inset, float(i) / 20.0)
		corr_hi = maxf(corr_hi, Gen.terrain_height(Sundered.from_chart(x, 0.0), seed_b))
	_check("corridor floor stays navigable across the interior (max %.2f < sea %.2f)" % [corr_hi, sea],
		corr_hi < sea)
	# The authored rectangle EDGE (measured note, not a gate): a sample
	# exactly at x = RUN_LO reads the natural field when the chart
	# round-trip lands a hair outside -- by design, the site is finite.
	var edge_d: Vector3 = Sundered.from_chart(Sundered.RUN_LO, -(w + flank * 0.5))
	var edge_ch: Vector2 = Sundered._chart(edge_d)
	print("    mouth-edge note: from_chart(RUN_LO, -%.5f) round-trips to x=%.8f (< RUN_LO=%s) -- the site boundary"
		% [w + flank * 0.5, edge_ch.x, str(edge_ch.x < Sundered.RUN_LO)])

	# ---- 4. The shoal is a wet ford ---------------------------------
	var x_shoal: float = lerpf(Sundered.RUN_LO, run_hi, Sundered.SHOAL_AT)
	var crest: float = Gen.terrain_height(Sundered.from_chart(x_shoal, 0.0), seed_b)
	var floor_h: float = Gen.terrain_height(
		Sundered.from_chart(x_shoal + 3.0 * Sundered.SHOAL_WIDTH, 0.0), seed_b)
	_check("shoal crest rises above the channel floor (%.2f > %.2f + 3)" % [crest, floor_h],
		crest > floor_h + 3.0)
	_check("shoal stays a WET ford (crest %.2f < sea %.2f)" % [crest, sea], crest < sea)

	# ---- 5. THE COMPOSE LAW: spawn dome + poles unchanged -----------
	var spawn_ok := true
	var spawn_worst := 0.0
	for k in range(spawn_samples.size()):
		var got: float = Gen.terrain_height(spawn_samples[k], seed_b)
		var dlt: float = absf(got - float(nat_spawn[k]))
		spawn_worst = maxf(spawn_worst, dlt)
		if dlt > 1e-4:
			spawn_ok = false
			print("    spawn moved at ", spawn_samples[k], " nat=", nat_spawn[k], " bk=", got)
	_check("spawn dome UNCHANGED by the backend (%d samples, worst delta %.6f m)"
		% [spawn_samples.size(), spawn_worst], spawn_ok)
	var polar_ok := true
	var polar_worst := 0.0
	for k in range(polar_samples.size()):
		var got2: float = Gen.terrain_height(polar_samples[k], seed_b)
		var dlt2: float = absf(got2 - float(nat_polar[k]))
		polar_worst = maxf(polar_worst, dlt2)
		if dlt2 > 1e-4:
			polar_ok = false
			print("    pole moved at ", polar_samples[k], " nat=", nat_polar[k], " bk=", got2)
	_check("polar caps UNCHANGED by the backend (%d samples, worst delta %.6f m)"
		% [polar_samples.size(), polar_worst], polar_ok)
	var home_ok := true
	var home_worst := 0.0
	for k in range(home_samples.size()):
		var got3: float = Gen.terrain_height(home_samples[k], seed_b)
		var dlt3: float = absf(got3 - float(nat_home[k]))
		home_worst = maxf(home_worst, dlt3)
		if dlt3 > 1e-4:
			home_ok = false
			print("    homeland moved at ", home_samples[k], " nat=", nat_home[k], " bk=", got3)
	_check("home continent UNCHANGED by the backend (%d samples, worst delta %.6f m)"
		% [home_samples.size(), home_worst], home_ok)
	var plaza: float = Gen.terrain_height(Gen.SPAWN_CENTER.normalized(), seed_b)
	_check("spawn plaza still flats to SPAWN_HEIGHT (%.2f)" % plaza,
		absf(plaza - Gen.SPAWN_HEIGHT) < 0.01)

	# ---- 6. Determinism + clean uninstall ---------------------------
	var mid: Vector3 = Sundered.from_chart(lerpf(Sundered.RUN_LO, run_hi, 0.5), 0.0)
	var mid_a: float = Gen.terrain_height(mid, seed_b)
	var mid_b: float = Gen.terrain_height(mid, seed_b)
	_check("backend answer deterministic", absf(mid_a - mid_b) < 1e-9)
	Gen.uninstall_terrain_backend()
	_check("uninstall clears the seam", not Gen.terrain_backend_installed())
	var nat_after: float = Gen.terrain_height(mid, seed_b)
	var nat_mid: float = Gen._natural_raw(mid.normalized(), seed_b)
	# The mid-run corridor site has no sculpt tail, so the natural law
	# there is the raw field exactly.
	_check("uninstall restores the natural law (mid-run %.3f == raw %.3f)" % [nat_after, nat_mid],
		absf(nat_after - nat_mid) < 0.01)

	print("--- RESULTS: %d passed, %d failed ---" % [_checks - _fails, _fails])
	quit(0 if _fails == 0 else 1)
