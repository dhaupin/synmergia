extends SceneTree

## Julia prop-scatter parity receipt (tests/test_julia_prop_batch.gd):
## the GDScript frame's rock/boulder scatter (TerrainGen.rock_specs /
## boulder_specs) vs the Julia pre-solve mirror (srv/julia-bridge/propmath.jl)
## for the same world seed.
##
## The frame's prop scatter is a pure function of (world_seed, face): a
## fresh PCG32 RNG (now mirrored bit-exact in pcg32.jl) seeded from the
## face's SeedChain bytes, then a bounded barycentric draw per site. The
## Julia batch (prop_batch.jl --parity) derives the same 20 faces and emits
## one record each; this receipt re-derives the frame's records and asserts
## equality. The embedded anchors are the recorded parity values so CI
## without Julia still passes.
##
## Run:
##   godot --headless --path . --script res://tests/test_julia_prop_batch.gd
##
## The live leg (actually invoking Julia) runs only when `julia` is on PATH.

const SEED_HEX := "73616c7463726f776e2d69736c652d34"
const TOL := 1.0e-4  # frame float32 vs Julia float64; measured err ~1e-6

## The 12 raw icosahedron vertices (Icosahedral.VERTICES) -- drift guard.
const VERTS := [
        Vector3(0.000000, 1.000000, 1.618034),
        Vector3(0.000000, -1.000000, 1.618034),
        Vector3(0.000000, 1.000000, -1.618034),
        Vector3(0.000000, -1.000000, -1.618034),
        Vector3(1.000000, 1.618034, 0.000000),
        Vector3(-1.000000, 1.618034, 0.000000),
        Vector3(1.000000, -1.618034, 0.000000),
        Vector3(-1.000000, -1.618034, 0.000000),
        Vector3(1.618034, 0.000000, 1.000000),
        Vector3(-1.618034, 0.000000, 1.000000),
        Vector3(1.618034, 0.000000, -1.000000),
        Vector3(-1.618034, 0.000000, -1.000000),
]

## The 20 faces: unit center + 3 outward-wound vertex indices (IcosahedralFaces).
const FACES := [
        [Vector3(0.356822, 0.000000, 0.934172), 0, 1, 8],
        [Vector3(-0.356822, 0.000000, 0.934172), 0, 9, 1],
        [Vector3(0.000000, 0.934172, 0.356822), 0, 4, 5],
        [Vector3(0.577350, 0.577350, 0.577350), 0, 8, 4],
        [Vector3(-0.577350, 0.577350, 0.577350), 0, 5, 9],
        [Vector3(0.000000, -0.934172, 0.356822), 1, 7, 6],
        [Vector3(0.577350, -0.577350, 0.577350), 1, 6, 8],
        [Vector3(-0.577350, -0.577350, 0.577350), 1, 9, 7],
        [Vector3(0.356822, 0.000000, -0.934172), 2, 10, 3],
        [Vector3(-0.356822, 0.000000, -0.934172), 2, 3, 11],
        [Vector3(0.000000, 0.934172, -0.356822), 2, 5, 4],
        [Vector3(0.577350, 0.577350, -0.577350), 2, 4, 10],
        [Vector3(-0.577350, 0.577350, -0.577350), 2, 11, 5],
        [Vector3(0.000000, -0.934172, -0.356822), 3, 6, 7],
        [Vector3(0.577350, -0.577350, -0.577350), 3, 10, 6],
        [Vector3(-0.577350, -0.577350, -0.577350), 3, 7, 11],
        [Vector3(0.934172, 0.356822, 0.000000), 4, 8, 10],
        [Vector3(-0.934172, 0.356822, 0.000000), 5, 11, 9],
        [Vector3(0.934172, -0.356822, 0.000000), 6, 10, 8],
        [Vector3(-0.934172, -0.356822, 0.000000), 7, 9, 11],
]

## Per-face [face, rock_count, rock_sum, boulder_count, boulder_sum] from
## the Julia batch (prop_batch.jl --parity). The frame must reproduce these.
const FACE_SUMS := [
        [0, 20, 109.4401534021, 2, 15.5821699857],
        [1, 21, 100.5118518795, 2, 17.7731060832],
        [2, 31, 185.7459140750, 3, 26.0209400792],
        [3, 20, 136.4934210040, 3, 25.7164015318],
        [4, 30, 159.7202951408, 3, 21.1323517538],
        [5, 22, 67.4001731397, 2, 15.7246877520],
        [6, 30, 168.9965441175, 2, 18.7590695453],
        [7, 21, 84.5651138548, 3, 23.5182739348],
        [8, 28, 99.4487140088, 2, 11.6690221624],
        [9, 25, 76.3117549049, 2, 12.8333288292],
        [10, 21, 119.5368416065, 2, 17.6742658605],
        [11, 33, 172.6345800197, 2, 15.1483011420],
        [12, 24, 108.4798276242, 2, 14.3665829522],
        [13, 33, 120.5022904288, 2, 12.7881242535],
        [14, 26, 104.8563874904, 3, 22.4908610703],
        [15, 27, 87.8035714925, 2, 13.8533694373],
        [16, 23, 150.3512396752, 3, 20.1061992282],
        [17, 33, 122.8795099143, 2, 17.3659933775],
        [18, 26, 142.4970313888, 3, 29.4611940327],
        [19, 26, 91.2504511735, 2, 14.8690486411],
]

## First rock per face [face, dir, scale, yaw] -- a per-spec anchor so a
## drift inside a face (not just its sum) is caught.
const ROCK_ANCHORS := [
        [0, Vector3(0.101777, 0.029991, 0.994355), 1.682078, 3.401626],
        [1, Vector3(-0.489990, -0.209938, 0.846071), 2.150042, 4.333059],
        [2, Vector3(0.029991, 0.994355, 0.101777), 1.700526, 5.088758],
        [3, Vector3(0.744294, 0.552892, 0.374617), 1.092666, 0.869207],
        [4, Vector3(-0.814306, 0.150238, 0.560655), 1.749799, 1.094618],
        [5, Vector3(-0.029991, -0.994355, 0.101777), 1.260510, 3.457549],
        [6, Vector3(0.560655, -0.814306, 0.150238), 2.129474, 6.281994],
        [7, Vector3(-0.762829, -0.504365, 0.404608), 1.262693, 2.892931],
        [8, Vector3(0.489990, -0.209938, -0.846071), 1.685871, 0.259156],
        [9, Vector3(-0.101777, -0.029991, -0.994355), 1.320414, 1.580098],
        [10, Vector3(-0.410417, 0.907158, -0.092852), 1.844335, 0.369403],
        [11, Vector3(0.560655, 0.814306, -0.150238), 2.086203, 2.047329],
        [12, Vector3(-0.404608, 0.762829, -0.504365), 1.882449, 3.923252],
        [13, Vector3(0.029991, -0.994355, -0.101777), 1.725263, 0.790728],
        [14, Vector3(0.744294, -0.552892, -0.374617), 1.013688, 5.365663],
        [15, Vector3(-0.374617, -0.744294, -0.552892), 1.309784, 4.023092],
        [16, Vector3(0.864606, 0.441463, -0.239929), 1.114220, 2.622545],
        [17, Vector3(-0.994355, 0.101777, 0.029991), 2.038484, 6.048841],
        [18, Vector3(0.864606, -0.441463, -0.239929), 1.020336, 5.679047],
        [19, Vector3(-0.994355, -0.101777, 0.029991), 1.744917, 2.969384],
]

## First boulder per face [face, dir, radius, yaw].
const BOULDER_ANCHORS := [
        [0, Vector3(0.092852, -0.410417, 0.907158), 6.430825, 1.000847],
        [1, Vector3(-0.092852, 0.410417, 0.907158), 4.906195, 1.737633],
        [2, Vector3(0.029991, 0.994355, 0.101777), 5.773818, 1.539035],
        [3, Vector3(0.552892, 0.374617, 0.744294), 5.142511, 1.947035],
        [4, Vector3(-0.404608, 0.762829, 0.504365), 4.486177, 1.247253],
        [5, Vector3(0.029991, -0.994355, 0.101777), 6.092762, 0.671303],
        [6, Vector3(0.744294, -0.552892, 0.374617), 6.447649, 4.401872],
        [7, Vector3(-0.404608, -0.762829, 0.504365), 6.266168, 5.559841],
        [8, Vector3(0.489990, -0.209938, -0.846071), 4.761526, 0.058724],
        [9, Vector3(-0.101777, 0.029991, -0.994355), 4.818998, 3.506850],
        [10, Vector3(-0.029991, 0.994355, -0.101777), 5.301357, 1.058222],
        [11, Vector3(0.560655, 0.814306, -0.150238), 5.443658, 1.467865],
        [12, Vector3(-0.552892, 0.374617, -0.744294), 4.429109, 3.044747],
        [13, Vector3(-0.029991, -0.994355, -0.101777), 5.255707, 2.527845],
        [14, Vector3(0.744294, -0.552892, -0.374617), 6.029186, 3.273227],
        [15, Vector3(-0.814306, -0.150238, -0.560655), 5.930941, 2.562016],
        [16, Vector3(0.864606, 0.441463, -0.239929), 3.786222, 1.740110],
        [17, Vector3(-0.994355, 0.101777, 0.029991), 4.363407, 2.517184],
        [18, Vector3(0.864606, -0.441463, -0.239929), 5.579350, 4.908845],
        [19, Vector3(-0.994355, -0.101777, 0.029991), 4.971485, 1.310564],
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
	print("--- Julia prop-scatter parity ---")
	var G = load("res://scenes/worlds/terrain_gen.gd")
	var Faces = load("res://core/frame/math/icosahedral_faces.gd")
	var Ico = load("res://core/frame/math/icosahedral.gd")
	if G == null or Faces == null or Ico == null:
		_fail("frame scripts did not load")
		quit(1)
		return
	var seed: PackedByteArray = G.world_seed_bytes()
	if seed.hex_encode() != SEED_HEX:
		_fail("world seed drifted: %s" % seed.hex_encode())
	else:
		_ok("world seed matches the prop anchor")

	# --- icosahedral table drift guard --------------------------------
	var vbad: int = 0
	for i in range(12):
		if Ico.VERTICES[i].distance_to(VERTS[i]) > 1.0e-5:
			vbad += 1
	if vbad == 0:
		_ok("the 12 icosahedron vertices match the Julia tables")
	else:
		_fail("%d icosahedron vertices drifted from the Julia tables" % vbad)

	var fbad: int = 0
	for f in range(20):
		if Faces.face_center(f).distance_to(FACES[f][0]) > 1.0e-5:
			fbad += 1
			continue
		var fv: PackedInt32Array = Faces.face_vertices(f)
		if fv[0] != FACES[f][1] or fv[1] != FACES[f][2] or fv[2] != FACES[f][3]:
			fbad += 1
	if fbad == 0:
		_ok("the 20 face centers + vertex orders match the Julia tables")
	else:
		_fail("%d faces drifted from the Julia tables" % fbad)

	# --- spec derivation vs the recorded Julia parity -----------------
	var worst: float = 0.0
	var mismatch: int = 0
	for row in FACE_SUMS:
		var f: int = row[0]
		var rn: int = 0
		var rs: float = 0.0
		for s in G.rock_specs(seed, f):
			rn += 1
			rs += s.dir.x + s.dir.y + s.dir.z + s.scale + s.yaw
		var bn: int = 0
		var bs: float = 0.0
		for b in G.boulder_specs(seed, f):
			bn += 1
			bs += b.dir.x + b.dir.y + b.dir.z + b.radius + b.yaw
		if rn != row[1] or bn != row[3]:
			mismatch += 1
			_fail("face %d count: rocks %d/%d boulders %d/%d" % [f, rn, row[1], bn, row[3]])
			continue
		var e1: float = absf(rs - row[2])
		var e2: float = absf(bs - row[4])
		worst = maxf(worst, maxf(e1, e2))
		if e1 > TOL or e2 > TOL:
			mismatch += 1
			_fail("face %d sum drifted: rocks %.6f/%.6f boulders %.6f/%.6f" % [f, rs, row[2], bs, row[4]])
	if mismatch == 0:
		_ok("all 20 faces match the Julia spec sums (max err %.8f)" % worst)

	# --- per-spec anchors ---------------------------------------------
	var abad: int = 0
	for row in ROCK_ANCHORS:
		var f: int = row[0]
		var specs: Array = G.rock_specs(seed, f)
		if specs.is_empty():
			abad += 1
			continue
		var s = specs[0]
		if s.dir.distance_to(row[1]) > 1.0e-4 or absf(s.scale - row[2]) > 1.0e-4 or absf(s.yaw - row[3]) > 1.0e-4:
			abad += 1
	for row in BOULDER_ANCHORS:
		var f: int = row[0]
		var specs: Array = G.boulder_specs(seed, f)
		if specs.is_empty():
			abad += 1
			continue
		var b = specs[0]
		if b.dir.distance_to(row[1]) > 1.0e-4 or absf(b.radius - row[2]) > 1.0e-4 or absf(b.yaw - row[3]) > 1.0e-4:
			abad += 1
	if abad == 0:
		_ok("the first rock + boulder of every face match the Julia anchors")
	else:
		_fail("%d per-spec anchors drifted" % abad)

	# Live leg: actually invoke Julia when it is on PATH.
	var julia: String = _which_julia()
	if julia == "":
		print("[SKIP] julia not on PATH; embedded anchors only (wire contract pinned)")
	else:
		_live_leg(julia)

	print("JULIA PROP RECEIPT %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)

func _which_julia() -> String:
	for p in ["/usr/local/bin/julia", "/usr/bin/julia"]:
		if FileAccess.file_exists(p):
			return p
	return ""

func _live_leg(julia: String) -> void:
	# OS.execute truncates captured output at the first newline in this
	# Godot build, so run Julia through a file redirect and read it back.
	var tmp: String = "user://julia_prop_parity.txt"
	var abs_tmp: String = ProjectSettings.globalize_path(tmp)
	var cmd: String = "%s --startup-file=no %s --parity > %s 2>/dev/null" % [
		julia, "/workspace/project/synmergia/srv/julia-bridge/prop_batch.jl", abs_tmp]
	var code: int = OS.execute("sh", ["-c", cmd])
	if code != 0:
		_fail("julia prop_batch.jl exited %d" % code)
		return
	var f := FileAccess.open(tmp, FileAccess.READ)
	if f == null:
		_fail("julia prop_batch.jl produced no readable output")
		return
	var seen: int = 0
	var bad: int = 0
	while not f.eof_reached():
		var s: String = f.get_line().strip_edges()
		if not s.begins_with("P "):
			continue
		var p: PackedStringArray = s.split(" ")
		if p.size() < 6:
			continue
		seen += 1
		var fidx: int = int(p[1])
		if fidx < 0 or fidx >= FACE_SUMS.size():
			bad += 1
			continue
		var row: Array = FACE_SUMS[fidx]
		if int(p[2]) != row[1] or int(p[4]) != row[3]:
			bad += 1
			continue
		if absf(float(p[3]) - row[2]) > TOL or absf(float(p[5]) - row[4]) > TOL:
			bad += 1
	f.close()
	if seen == 20 and bad == 0:
		_ok("live Julia prop batch agrees on all 20 faces")
	else:
		_fail("live Julia prop batch: %d faces seen, %d mismatched" % [seen, bad])
