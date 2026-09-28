## Tests for IcosahedralFaces (prd-spherical-mvp.md S5a)
## Loads by path (fresh class_name is invisible to script mode until
## an editor import pass - GuardData lesson).
extends SceneTree

func _init() -> void:
	var ok := true
	if not _test_counts_and_degree():
		push_error("FAIL: counts_and_degree")
		ok = false
	if not _test_adjacency():
		push_error("FAIL: adjacency")
		ok = false
	if not _test_edge_sharing_symmetry():
		push_error("FAIL: edge_sharing_symmetry")
		ok = false
	if not _test_face_for_direction():
		push_error("FAIL: face_for_direction")
		ok = false
	if not _test_partition():
		push_error("FAIL: partition")
		ok = false
	if not _test_vertex_coverage():
		push_error("FAIL: vertex_coverage")
		ok = false
	quit(0 if ok else 1)

func _faces() -> GDScript:
	return load("res://core/frame/math/icosahedral_faces.gd")

func _icos() -> GDScript:
	return load("res://core/frame/math/icosahedral.gd")

func _test_counts_and_degree() -> bool:
	var F = _faces()
	assert(F.face_count() == 20)
	var total_edge_slots := 0
	for f in range(20):
		assert(F.face_vertices(f).size() == 3)
		assert(F.neighbors(f).size() == 3)
		var center: Vector3 = F.face_center(f)
		assert(abs(center.length() - 1.0) < 0.001)
		total_edge_slots += F.face_vertices(f).size()
	assert(total_edge_slots == 60)
	return true

func _test_adjacency() -> bool:
	var F = _faces()
	for f in range(20):
		for n in F.neighbors(f):
			# Symmetry: every neighbor lists us back.
			assert(F.neighbors(n).has(f))
			# Distance sanity: neighbors touch, so their centers are
			# closer than opposite faces (dot > 0 for all pairs here).
			assert(F.face_center(f).dot(F.face_center(n)) > 0.0)
	return true

func _test_edge_sharing_symmetry() -> bool:
	# Every one of the 30 edges appears in exactly 2 faces.
	var edge_count := {}
	for f in range(20):
		var fv: PackedInt32Array = _faces().face_vertices(f)
		for pair in [[fv[0], fv[1]], [fv[1], fv[2]], [fv[2], fv[0]]]:
			var key: String = "%d-%d" % [mini(pair[0], pair[1]), maxi(pair[0], pair[1])]
			edge_count[key] = edge_count.get(key, 0) + 1
	assert(edge_count.size() == 30)
	for key in edge_count:
		assert(edge_count[key] == 2)
	return true

func _test_face_for_direction() -> bool:
	var F = _faces()
	# Every face center resolves to its own face.
	for f in range(20):
		assert(F.face_for_direction(F.face_center(f)) == f)
	# Vertex directions sit on 5-face boundaries; must resolve to one
	# of those 5 (never an unrelated face).
	var verts: PackedVector3Array = _icos().VERTICES
	for v in verts:
		var f: int = F.face_for_direction(v.normalized())
		var fv: PackedInt32Array = F.face_vertices(f)
		assert(fv.has(verts.find(v)) or F.face_center(f).distance_to(v.normalized()) < 0.8)
	return true

func _test_partition() -> bool:
	# 2,000 quasi-random directions each land in exactly one face and
	# in the face whose center is nearest (Voronoi consistency).
	var rng := RandomNumberGenerator.new()
	rng.seed = 20
	var F = _faces()
	var counts := {}
	for i in range(2000):
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if d.length() < 0.01:
			continue
		var f: int = F.face_for_direction(d)
		assert(f >= 0 and f < 20)
		counts[f] = counts.get(f, 0) + 1
		# Voronoi consistency: no other center beats this one.
		var dot: float = d.normalized().dot(F.face_center(f))
		for g in range(20):
			if g != f:
				assert(dot >= d.normalized().dot(F.face_center(g)) - 0.0001)
	# Coverage: every face claimed territory (all faces are reachable).
	assert(counts.size() == 20)
	return true

func _test_vertex_coverage() -> bool:
	# All 12 vertices appear in exactly 5 faces.
	var vert_count := {}
	for f in range(20):
		for v in _faces().face_vertices(f):
			vert_count[v] = vert_count.get(v, 0) + 1
	assert(vert_count.size() == 12)
	for v in vert_count:
		assert(vert_count[v] == 5)
	return true
