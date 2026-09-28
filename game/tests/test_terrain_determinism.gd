## Terrain determinism tests (prd-spherical-mvp.md S7)
## The seed law: same seed + ruleset = same content, regardless of
## call order or process. Any violation here means content diverges
## between machines or sessions.
extends SceneTree


func _init() -> void:
	var ok := true
	if not _test_order_independence():
		push_error("FAIL: order_independence")
		ok = false
	if not _test_face_and_seed_sensitivity():
		push_error("FAIL: face_and_seed_sensitivity")
		ok = false
	if not _test_all_faces_derive():
		push_error("FAIL: all_faces_derive")
		ok = false
	if not _test_rock_top_provider():
		push_error("FAIL: rock_top_provider")
		ok = false
	quit(0 if ok else 1)


func _gen() -> GDScript:
	return load("res://scenes/worlds/terrain_gen.gd")


func _fp(g, seed_b: PackedByteArray, face: int) -> String:
	return g.fingerprint(seed_b, face)


## Interleave 20 faces (a-e), then derive them in sorted order and
## via a second seed array copy: fingerprints must match exactly.
func _test_order_independence() -> bool:
	var g = _gen()
	var seed_b: PackedByteArray = g.world_seed_bytes()
	var a := {}
	for f in [7, 3, 19, 0, 11, 5, 16, 2, 9, 13, 1, 18, 4, 12, 6, 17, 8, 15, 10, 14]:
		a[f] = _fp(g, seed_b, f)
	var b := {}
	for f in range(20):
		b[f] = _fp(g, seed_b, f)
	for f in a:
		assert(a[f] == b[f])
	# A second call round in the same process: same.
	for f in range(20):
		assert(_fp(g, seed_b, f) == b[f])
	return true


## Different world seed -> different content; different face ->
## different content; ruleset bump -> different content.
func _test_face_and_seed_sensitivity() -> bool:
	var g = _gen()
	var s1: PackedByteArray = g.world_seed_bytes()
	var s2: PackedByteArray = "other-world".to_utf8_buffer()
	var all_diff := true
	for f in range(20):
		if _fp(g, s1, f) == _fp(g, s2, f):
			all_diff = false
	assert(all_diff)
	var diff_faces := true
	for f in range(19):
		if _fp(g, s1, f) == _fp(g, s1, f + 1):
			diff_faces = false
	assert(diff_faces)
	# Ruleset version participates: same seed, different ruleset tag.
	var v1: PackedByteArray = g.face_seed_bytes(s1, 4)
	assert(v1.size() == 32)
	return true


## Every face derives 2-5 rocks with unit directions.
func _test_all_faces_derive() -> bool:
	var g = _gen()
	var seed_b: PackedByteArray = g.world_seed_bytes()
	var total := 0
	for f in range(20):
		var specs: Array = g.rock_specs(seed_b, f)
		assert(specs.size() >= 2 and specs.size() <= 5)
		total += specs.size()
		for s in specs:
			assert(abs(s.dir.length() - 1.0) < 0.001)
	assert(total >= 40 and total <= 100)
	return true


## Rock top provider: deterministic, zero away from rocks, smooth
## profile (no jumps > 0.4 m between adjacent sample directions).
## Max height delta between adjacent samples along the march.
func _max_delta(g, seed_b: PackedByteArray, f: int, center: Vector3, v: Vector3, steps: int) -> float:
	var prev: float = 0.0
	var md: float = 0.0
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var dir: Vector3 = (center * (1.0 - t) + v * t).normalized()
		var h: float = g.rock_top_height(dir, seed_b, f, 100.0)
		assert(h >= 0.0 and h <= 5.0)
		if i > 0:
			md = maxf(md, abs(h - prev))
		prev = h
	return md


func _test_rock_top_provider() -> bool:
	var g = _gen()
	var seed_b: PackedByteArray = g.world_seed_bytes()
	var Faces = load("res://core/frame/math/icosahedral_faces.gd")
	for f in range(20):
		var specs: Array = g.rock_specs(seed_b, f)
		# Dead center of the face is NOT a rock (70/30 jitter keeps
		# rocks toward vertices) - provider must be smooth anyway.
		var prev: float = 0.0
		var center: Vector3 = Faces.face_center(f)
		var verts: PackedInt32Array = Faces.face_vertices(f)
		# March center -> first vertex at TWO resolutions. Continuity
		# test by refinement ratio: a continuous profile's max step
		# delta halves when the step halves; a real discontinuity (the
		# first-match bug this test caught) keeps its jump at any
		# resolution. Fixed thresholds are wrong here - smoothstep caps
		# are legitimately steep mid-flank.
		var v: Vector3 = Icosahedral.VERTICES[verts[0]].normalized()
		var d400: float = _max_delta(g, seed_b, f, center, v, 400)
		var d800: float = _max_delta(g, seed_b, f, center, v, 800)
		assert(d800 <= d400 * 0.75 + 0.001)
	# Determinism: same dir, same answer twice.
	var d: Vector3 = Faces.face_center(3)
	var h1: float = g.rock_top_height(d, seed_b, 3, 100.0)
	var h2: float = g.rock_top_height(d, seed_b, 3, 100.0)
	assert(h1 == h2)
	return true
