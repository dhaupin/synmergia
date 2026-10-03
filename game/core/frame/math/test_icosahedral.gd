## Tests for icosahedral projection
extends SceneTree

func _init() -> void:
	var ok = true
	if not _test_vertex_count():
		push_error("FAIL: vertex_count")
		ok = false
	if not _test_projection():
		push_error("FAIL: projection")
		ok = false
	if not _test_to_cell():
		push_error("FAIL: to_cell")
		ok = false
	if not _test_cell_center():
		push_error("FAIL: cell_center")
		ok = false
	if not _test_neighbors():
		push_error("FAIL: neighbors")
		ok = false
	if not _test_position_to_cell():
		push_error("FAIL: position_to_cell")
		ok = false
	quit(0 if ok else 1)

func _test_vertex_count() -> bool:
	var ic = Icosahedral.new()
	var verts = ic.get_vertices()
	assert(verts.size() == 12)
	return true

func _test_projection() -> bool:
	var ic = Icosahedral.new()
	var latlon = ic.project(Vector3(1, 0, 0))
	assert(abs(latlon.x) < 0.01)
	assert(abs(latlon.y) < 0.01)
	var latlon2 = ic.project(Vector3(0, 1, 0))
	assert(abs(latlon2.x - 90.0) < 0.01)
	return true

func _test_to_cell() -> bool:
	var ic = Icosahedral.new()
	var cell = ic.to_cell(0, 0)
	assert(cell >= 0 and cell < 12)
	var cell2 = ic.to_cell(90, 0)
	assert(cell2 >= 0 and cell2 < 12)
	return true

func _test_cell_center() -> bool:
	var ic = Icosahedral.new()
	for i in range(12):
		var center = ic.cell_center(i)
		assert(center != Vector3.ZERO)
		# Audit round 16: the old assertion's trailing clause
		# `abs(len - 1.0) > 0` is true for every non-unit vector, so it
		# was a tautology that passed while cell_center returned the raw
		# 1.902-length vertex. Assert UNIT length for real.
		assert(abs(center.length() - 1.0) < 0.001)
	return true

func _test_neighbors() -> bool:
	var ic = Icosahedral.new()
	for i in range(12):
		var nbrs = ic.neighbors(i)
		assert(nbrs.size() == 5)
		assert(not nbrs.has(i))
	return true

func _test_position_to_cell() -> bool:
	var ic = Icosahedral.new()
	var cell = ic.position_to_cell(Vector3(0, 1, 0))
	assert(cell >= 0 and cell < 12)
	return true
