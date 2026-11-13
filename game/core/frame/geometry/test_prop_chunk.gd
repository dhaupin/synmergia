## Tests for PropChunk addressing (the prop layer's stable grid).
## Run: godot --headless --path . --script res://core/frame/geometry/test_prop_chunk.gd
extends SceneTree

const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")
const Faces = preload("res://core/frame/math/icosahedral_faces.gd")


func _init() -> void:
	var ok := true
	if not _test_determinism():
		push_error("FAIL: determinism")
		ok = false
	if not _test_partition():
		push_error("FAIL: partition")
		ok = false
	if not _test_center_in_cell():
		push_error("FAIL: center_in_cell")
		ok = false
	if not _test_key_roundtrip():
		push_error("FAIL: key_roundtrip")
		ok = false
	if not _test_radius():
		push_error("FAIL: radius")
		ok = false
	print("[prop_chunk] %s" % ("ALL PASS" if ok else "FAILURES"))
	quit(0 if ok else 1)


func _test_determinism() -> bool:
	# The same direction yields the same chunk, twice, at several depths.
	var dirs: Array = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0.3, 0.5, 0.8).normalized(),
			Vector3(-0.2, 0.9, 0.1).normalized()]
	for d in dirs:
		for depth in [0, 3, 6, 9]:
			var k1: int = PropChunk.chunk_for_dir(d, depth)
			var k2: int = PropChunk.chunk_for_dir(d, depth)
			if k1 != k2:
				return false
	# Nearby directions (within a fine cell) land in the same chunk.
	var a: Vector3 = Vector3(0.5, 0.5, 0.7).normalized()
	var b: Vector3 = (a + Vector3(0.0001, 0, 0)).normalized()
	if PropChunk.chunk_for_dir(a, 4) != PropChunk.chunk_for_dir(b, 4):
		return false
	return true


func _test_partition() -> bool:
	# Every direction maps to a cell inside [0, n-1] with i + j <= n-1,
	# across a fibonacci sweep at depth 6.
	var n: int = PropChunk.cells_per_edge(6)
	var n_pts: int = 2000
	var ga: float = PI * (3.0 - sqrt(5.0))
	for p in range(n_pts):
		var y: float = 1.0 - 2.0 * (float(p) + 0.5) / float(n_pts)
		var r: float = sqrt(maxf(0.0, 1.0 - y * y))
		var th: float = ga * float(p)
		var d: Vector3 = Vector3(cos(th) * r, y, sin(th) * r)
		var key: int = PropChunk.chunk_for_dir(d, 6)
		var cell: Vector2i = PropChunk.cell_of(key)
		if cell.x < 0 or cell.x >= n or cell.y < 0 or cell.y >= n:
			return false
		if cell.x + cell.y > n - 1:
			return false
		if PropChunk.face_of(key) < 0 or PropChunk.face_of(key) >= Faces.face_count():
			return false
	return true


func _test_center_in_cell() -> bool:
	# The center direction of a chunk must fall back into that same chunk.
	for depth in [2, 5, 7]:
		var n: int = PropChunk.cells_per_edge(depth)
		for face in range(Faces.face_count()):
			for i in range(0, n, maxi(1, n / 5)):
				for j in range(0, n, maxi(1, n / 5)):
					if i + j > n - 1:
						continue
					var key: int = PropChunk.make_key(face, i, j)
					var cd: Vector3 = PropChunk.chunk_center_dir(key, depth)
					if PropChunk.chunk_for_dir(cd, depth) != key:
						return false
	return true


func _test_key_roundtrip() -> bool:
	for face in range(Faces.face_count()):
		for i in [0, 7, 63]:
			for j in [0, 12, 63]:
				var key: int = PropChunk.make_key(face, i, j)
				if PropChunk.face_of(key) != face:
					return false
				if PropChunk.cell_of(key) != Vector2i(i, j):
					return false
	return true


func _test_radius() -> bool:
	# A radius query must include the center's own chunk, and every returned
	# chunk must be a valid key. A zero radius still returns at least one.
	var cd: Vector3 = Vector3(1, 0, 0)
	var hits: Array = PropChunk.chunks_in_radius(cd, 0.02, 6)
	if hits.is_empty():
		return false
	if not hits.has(PropChunk.chunk_for_dir(cd, 6)):
		return false
	for k in hits:
		if PropChunk.face_of(k) < 0 or PropChunk.face_of(k) >= Faces.face_count():
			return false
	# A wider radius returns at least as many chunks.
	var wide: Array = PropChunk.chunks_in_radius(cd, 0.08, 6)
	if wide.size() < hits.size():
		return false
	# The windowed scan must match a brute-force scan exactly (correctness).
	for r in [0.02, 0.05, 0.1]:
		var got: Array = PropChunk.chunks_in_radius(cd, r, 6)
		var want: Array = _brute_radius(cd, r, 6)
		got.sort()
		want.sort()
		if got != want:
			push_error("radius mismatch at r=%f: got %d want %d" % [r, got.size(), want.size()])
			return false
	return true


func _brute_radius(cd: Vector3, ang: float, depth: int) -> Array:
	var out: Array = []
	var n: int = PropChunk.cells_per_edge(depth)
	var cell_r: float = PropChunk.chunk_angular_radius(depth)
	for face in range(Faces.face_count()):
		for i in range(n):
			for j in range(n):
				if i + j > n - 1:
					continue
				var key: int = PropChunk.make_key(face, i, j)
				if cd.angle_to(PropChunk.chunk_center_dir(key, depth)) <= ang + cell_r:
					out.append(key)
	return out
