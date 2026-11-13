extends SceneTree

## Julia terrain parity receipt (tests/test_julia_terrain.gd):
## the GDScript frame's analytic heightfield (TerrainGen._natural_raw)
## vs the Julia pre-solve mirror (srv/julia-bridge/terrainmath.jl) for
## the same directions + seed.
##
## The Julia side is the float64 oracle; GDScript's frame math runs in
## float32 (Vector3), so heights match within float32 precision (the
## recorded max error is ~1.2e-5 m). The anchor values below are what
## `julia --project=. terrain_batch.jl` and the dev_temp probe produced.
##
## Run:
##   godot --headless --path . --script res://tests/test_julia_terrain.gd
##
## The live leg (actually invoking Julia) runs only when `julia` is on
## PATH; CI without Julia still passes on the embedded anchors.

const SEED_HEX := "73616c7463726f776e2d69736c652d34"
const SEA_EXPECTED := 4.565249304
const TOL := 1.0e-3  # meters; measured max err is ~1.2e-5, headroom for float32

## dir -> expected natural_raw (from the frame, cross-checked in Julia).
const ANCHORS := [
	[Vector3(1.0, 0.0, 0.0), 92.189549544],
	[Vector3(0.0, 1.0, 0.0), 527.169085761],
	[Vector3(0.0, 0.0, 1.0), 1.720050975],
	[Vector3(0.57735025882720947, 0.57735025882720947, 0.57735025882720947), -7.504462024],
	[Vector3(-0.57735025882720947, 0.57735025882720947, -0.57735025882720947), 122.035082620],
	[Vector3(0.35682210326194763, 0.0, 0.93417233228683472), -8.821273722],
	[Vector3(0.28, 0.26, 0.92), -6.484093118],
	[Vector3(0.1, 0.2, 0.97), 1.428447624],
]

var _failures: int = 0

func _ok(msg: String) -> void:
	print("[OK] ", msg)

func _fail(msg: String) -> void:
	_failures += 1
	printerr("[FAIL] ", msg)

func _init() -> void:
	_run()

func _run() -> void:
	print("--- Julia terrain parity ---")
	var G = load("res://scenes/worlds/terrain_gen.gd")
	if G == null:
		_fail("terrain_gen.gd did not load")
		quit(1)
		return
	var seed: PackedByteArray = G.world_seed_bytes()
	if seed.hex_encode() != SEED_HEX:
		_fail("world seed drifted: %s (expect %s)" % [seed.hex_encode(), SEED_HEX])
	else:
		_ok("world seed matches the terrain anchor")

	var sea: float = G.sea_level(seed)
	if absf(sea - SEA_EXPECTED) > TOL:
		_fail("sea_level drifted: %.9f (expect %.9f)" % [sea, SEA_EXPECTED])
	else:
		_ok("sea_level matches the Julia oracle (%.6f)" % sea)

	var worst: float = 0.0
	var bad: int = 0
	for row in ANCHORS:
		var d: Vector3 = row[0]
		var want: float = row[1]
		var got: float = G._natural_raw(d.normalized(), seed)
		var err: float = absf(got - want)
		worst = maxf(worst, err)
		if err > TOL:
			bad += 1
			_fail("natural_raw(%s) = %.6f (expect %.6f, err %.6f)" % [str(d), got, want, err])
	if bad == 0:
		_ok("natural_raw matches on all %d anchors (max err %.6f m)" % [ANCHORS.size(), worst])
	# Live leg: actually invoke Julia when it is on PATH.
	var julia: String = _which_julia()
	if julia == "":
		print("[SKIP] julia not on PATH; embedded anchors only (wire contract pinned)")
	else:
		_live_leg(julia, seed)

	print("JULIA TERRAIN RECEIPT %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)

func _which_julia() -> String:
	for p in ["/usr/local/bin/julia", "/usr/bin/julia"]:
		if FileAccess.file_exists(p):
			return p
	return ""

func _live_leg(julia: String, seed: PackedByteArray) -> void:
	var out: Array = []
	var code: int = OS.execute(julia, [
		"--project=/workspace/project/synmergia/srv/julia-bridge",
		"/workspace/project/synmergia/srv/julia-bridge/terrain_batch.jl",
		"--n", "2000",
	], out, true)
	if code != 0:
		_fail("julia terrain_batch.jl exited %d" % code)
		return
	var line: String = ""
	for l in out:
		if l.begins_with("JULIA_TERRAIN_USEC"):
			line = l
	if line == "":
		_fail("julia terrain_batch.jl produced no timing line")
		return
	_ok("live Julia batch ran: %s" % line.strip_edges())
