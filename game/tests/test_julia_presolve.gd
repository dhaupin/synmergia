extends SceneTree

## Julia presolve receipt (tests/test_julia_presolve.gd):
## the GDScript frame's own world-lattice derivations vs the Julia
## presolve artifact (srv/julia-bridge/world_batch.jl) for the same
## epochs. This is the Facet 2 consumer: the frame re-derives a sample
## of the batch output and asserts equality, so the pre-solve tier has
## a real validating consumer (it had none).
##
## The Julia side is the float64 oracle; the frame runs float32
## (Vector3), so orbit matches to float32 precision and seeds must
## match EXACTLY (integer/byte math). The anchors below are what
## `julia --project=. world_batch.jl --epochs 3` printed.
##
## Run:
##   godot --headless --path . --script res://tests/test_julia_presolve.gd
##
## The live leg (actually invoking Julia) runs only when `julia` is on
## PATH; CI without Julia still passes on the embedded artifact.

const WorldRegistryScript = preload("res://core/frame/srv/world_registry.gd")

const SEED_MAIN := "5d8e24a05d428934c6adf4badb6cc6aa9afbaacbf4ed44c801d6a615a814603b"
const SEED_MOON := "01bcff183981449b1dbaa44bd1aee3eb3bf81e3e10dc0c44ff0aa1e7a71931dd"
const SEED_UNDERWORLD := "a2d86dfda69638f0168c6711b638e2f0c9e19ec7b02aeed589b0b26290015d53"

## The Julia oracle artifact (world_batch.jl, sky days 0/1/2).
const ORACLE_ORBIT_MOON := [
	Vector3(68835.79685560397, -6940.864918240803, 57562.63949334462),
	Vector3(7676.496176429477, -10734.835603501087, 89027.15715453947),
	Vector3(-57979.5918513922, -8240.485182076005, 68340.77357412603),
]
const ORACLE_FAV_MAIN := [0.22281692032865347, 0.47281692032865347, 0.7228169203286535]

const ORBIT_REL_TOL := 1e-5
const FAV_ABS_TOL := 1e-5

var _failures: int = 0

func _ok(msg: String) -> void:
	print("[OK] ", msg)

func _fail(msg: String) -> void:
	_failures += 1
	printerr("[FAIL] ", msg)

func _init() -> void:
	_run()

func _run() -> void:
	print("--- Julia presolve artifact ---")
	var reg = WorldRegistryScript.new()
	reg.load_worlds()

	for pair in [["main", SEED_MAIN], ["moon", SEED_MOON], ["underworld", SEED_UNDERWORLD]]:
		var got: String = reg.world_seed_hex(pair[0])
		if got != pair[1]:
			_fail("seed(%s) drifted: %s" % [pair[0], got])
		else:
			_ok("seed(%s) matches the Julia artifact" % pair[0])

	var main_w = reg.get_world("main")
	var moon = reg.get_world("moon")

	# Re-derive the sample the artifact carries (sky days 0/1/2).
	var worst_orbit: float = 0.0
	for i in ORACLE_ORBIT_MOON.size():
		var sky: float = float(i)
		var want: Vector3 = ORACLE_ORBIT_MOON[i]
		var got: Vector3 = reg.orbit_position(moon, sky)
		var err: float = (got - want).length() / maxf(want.length(), 1.0)
		worst_orbit = maxf(worst_orbit, err)
		if err > ORBIT_REL_TOL:
			_fail("orbit(day %d) = %s (expect %s)" % [i, str(got), str(want)])
	if worst_orbit <= ORBIT_REL_TOL:
		_ok("moon orbit matches the artifact on 3 epochs (max rel %.8f)" % worst_orbit)

	var worst_fav: float = 0.0
	for i in ORACLE_FAV_MAIN.size():
		var sky: float = float(i)
		var got: float = reg.window_favorability(main_w, moon, sky)
		var err: float = absf(got - ORACLE_FAV_MAIN[i])
		worst_fav = maxf(worst_fav, err)
		if err > FAV_ABS_TOL:
			_fail("favorability(day %d) = %.9f (expect %.9f)" % [i, got, ORACLE_FAV_MAIN[i]])
	if worst_fav <= FAV_ABS_TOL:
		_ok("window favorability matches the artifact on 3 epochs (max abs %.8f)" % worst_fav)

	# Live leg: consume the real batch and validate a sample of it.
	var julia: String = _which_julia()
	if julia == "":
		print("[SKIP] julia not on PATH; embedded artifact only (wire contract pinned)")
	else:
		_live_leg(julia, reg, moon)

	print("JULIA PRESOLVE RECEIPT %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)

func _which_julia() -> String:
	for p in ["/usr/local/bin/julia", "/usr/bin/julia"]:
		if FileAccess.file_exists(p):
			return p
	return ""

## Run world_batch.jl and validate every EPOCH row it emits against the
## frame's own derivation -- the artifact the frame now consumes.
func _live_leg(julia: String, reg, moon) -> void:
	var out: Array = []
	var code: int = OS.execute(julia, [
		"--project=/workspace/project/synmergia/srv/julia-bridge",
		"/workspace/project/synmergia/srv/julia-bridge/world_batch.jl",
		"--epochs", "3",
	], out, true)
	if code != 0:
		_fail("julia world_batch.jl exited %d" % code)
		return
	# OS.execute joins all stdout into one element on this engine
	# build; split it back into lines before parsing.
	var lines: PackedStringArray = "\n".join(out).split("\n")
	var rows: int = 0
	var bad: int = 0
	for raw in lines:
		var line: String = raw.strip_edges()
		if not line.begins_with("EPOCH "):
			continue
		var f: PackedStringArray = line.split(" ")
		# EPOCH <world> <t> <day> <sky> <window> <x> <y> <z> <fav>
		var world: String = f[1]
		var sky: float = f[4].to_float()
		var want_orbit := Vector3(f[6].to_float(), f[7].to_float(), f[8].to_float())
		var want_fav: float = f[9].to_float()
		var w = reg.get_world(world)
		var got_orbit: Vector3 = reg.orbit_position(w, sky)
		var got_fav: float = reg.window_favorability(w, moon, sky)
		rows += 1
		if (got_orbit - want_orbit).length() / maxf(want_orbit.length(), 1.0) > ORBIT_REL_TOL:
			bad += 1
			_fail("live orbit(%s, day %s) drifted" % [world, f[3]])
		if absf(got_fav - want_fav) > FAV_ABS_TOL:
			bad += 1
			_fail("live favorability(%s, day %s) drifted" % [world, f[3]])
	if rows == 0:
		_fail("julia world_batch.jl produced no EPOCH rows")
	elif bad == 0:
		_ok("live Julia batch consumed + validated: %d epochs, all match" % rows)
