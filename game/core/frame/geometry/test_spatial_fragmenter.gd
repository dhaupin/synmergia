## Tests for Spatial Geometry Fragmenter
## Covers: deterministic subdivision, parent linkage, ancestor checks,
## bounding boxes, common ancestor, address key encoding, depth limits,
## face isolation, and round-trip consistency.
extends SceneTree

func _init() -> void:
	var ok = true
	if not _test_subdivide_count():
		push_error("FAIL: subdivide_count")
		ok = false
	if not _test_parent_linkage():
		push_error("FAIL: parent_linkage")
		ok = false
	if not _test_ancestor_checks():
		push_error("FAIL: ancestor_checks")
		ok = false
	if not _test_depth_tracking():
		push_error("FAIL: depth_tracking")
		ok = false
	if not _test_max_depth_limit():
		push_error("FAIL: max_depth_limit")
		ok = false
	if not _test_face_isolation():
		push_error("FAIL: face_isolation")
		ok = false
	if not _test_bounding_box():
		push_error("FAIL: bounding_box")
		ok = false
	if not _test_common_ancestor():
		push_error("FAIL: common_ancestor")
		ok = false
	if not _test_address_key_uniqueness():
		push_error("FAIL: address_key_uniqueness")
		ok = false
	if not _test_round_trip():
		push_error("FAIL: round_trip")
		ok = false
	if not _test_deterministic():
		push_error("FAIL: deterministic")
		ok = false
	quit(0 if ok else 1)


func _test_subdivide_count() -> bool:
	var sf: SpatialFragmenter = SpatialFragmenter.new()
	var addr: int = sf.make_address(0, 0, 0, 0, 9)
	var children: Array[int] = sf.subdivide(addr, 1)
	return children.size() == 8 and sf.get_depth(children[0]) == 1


func _test_parent_linkage() -> bool:
	var sf: SpatialFragmenter = SpatialFragmenter.new()
	var parent: int = sf.make_address(0, 0, 0, 0, 9)
	var children: Array[int] = sf.subdivide(parent, 1)
	for child in children:
		if sf.get_parent(child) != parent:
			return false
	return true


func _test_ancestor_checks() -> bool:
	var sf: SpatialFragmenter = SpatialFragmenter.new()
	var root: int = sf.make_address(0, 0, 0, 0, 9)
	var child: int = sf.subdivide(root, 1)[0]
	var grandchild: int = sf.subdivide(child, 1)[0]
	if not sf.is_ancestor(root, child):
		return false
	if not sf.is_ancestor(root, grandchild):
		return false
	if not sf.is_ancestor(child, grandchild):
		return false
	if sf.is_ancestor(grandchild, root):
		return false
	if sf.is_ancestor(child, root):
		return false
	var other_face: int = sf.make_address(0, 0, 0, 0, 3)
	if sf.is_ancestor(other_face, grandchild):
		return false
	return true


func _test_depth_tracking() -> bool:
	var sf: SpatialFragmenter = SpatialFragmenter.new()
	var addr: int = sf.make_address(0, 0, 0, 0, 0)
	if sf.get_depth(addr) != 0:
		return false
	var child: int = sf.subdivide(addr, 3)[0]
	if sf.get_depth(child) != 3:
		return false
	return true


func _test_max_depth_limit() -> bool:
	var sf: SpatialFragmenter = SpatialFragmenter.new()
	var addr: int = sf.make_address(0, 0, 0, 24, 0)
	var children: Array[int] = sf.subdivide(addr, 1)
	return children.size() == 1 and sf.get_depth(children[0]) == 24


func _test_face_isolation() -> bool:
	var sf: SpatialFragmenter = SpatialFragmenter.new()
	var face0: int = sf.make_address(0, 0, 0, 0, 0)
	var face1: int = sf.make_address(0, 0, 0, 0, 1)
	var c0: Array[int] = sf.subdivide(face0, 1)
	var c1: Array[int] = sf.subdivide(face1, 1)
	for child in c0:
		if sf.get_face(child) != 0:
			return false
	for child in c1:
		if sf.get_face(child) != 1:
			return false
	return true


func _test_bounding_box() -> bool:
	var sf: SpatialFragmenter = SpatialFragmenter.new()
	var addr: int = sf.make_address(1, 1, 1, 0, 0)
	var bb: Dictionary = sf.get_bounding_box(addr)
	if bb.min_x >= bb.max_x:
		return false
	if bb.min_x != 1 << sf.MAX_DEPTH:
		return false
	var child: int = sf.subdivide(addr, 1)[0]
	var child_bb: Dictionary = sf.get_bounding_box(child)
	if child_bb.min_x >= child_bb.max_x:
		return false
	return true


func _test_common_ancestor() -> bool:
	var sf: SpatialFragmenter = SpatialFragmenter.new()
	var root: int = sf.make_address(100, 200, 50, 0, 5)
	var children: Array[int] = sf.subdivide(root, 2)
	var ancestor: int = sf.find_common_ancestor(children)
	if not sf.is_ancestor(ancestor, children[0]):
		return false
	if not sf.is_ancestor(ancestor, children[7]):
		return false
	var across_faces: Array[int] = [sf.make_address(0, 0, 0, 0, 0), sf.make_address(0, 0, 0, 0, 1)]
	if sf.find_common_ancestor(across_faces) != 0:
		return false
	return true


func _test_address_key_uniqueness() -> bool:
	var sf: SpatialFragmenter = SpatialFragmenter.new()
	var keys: Dictionary = {}
	var addresses: Array[int] = []
	for depth in range(4):
		for face in range(3):
			var addr: int = sf.make_address(0, 0, 0, depth, face)
			addresses.append(addr)
			var key: String = sf.generate_key(addr)
			if keys.has(key):
				return false
			keys[key] = addr

	# Fixed-width formatting means distinct addresses never collide
	var addr1: int = sf.make_address(1, 12, 0, 1, 0)
	var addr2: int = sf.make_address(11, 2, 0, 1, 0)
	if sf.generate_key(addr1) != sf.generate_key(addr2):
		return true
	else:
		return addr1 == addr2


func _test_round_trip() -> bool:
	var sf: SpatialFragmenter = SpatialFragmenter.new()
	var root: int = sf.make_address(50, 75, 25, 0, 9)
	var children: Array[int] = sf.subdivide(root, 2)
	for child in children:
		var parent: int = sf.get_parent(child)
		if sf.get_depth(parent) != sf.get_depth(child) - 1:
			return false
		var grandparents: Array[int] = sf.subdivide(parent, 1)
		if not grandparents.has(child):
			return false
	return true


func _test_deterministic() -> bool:
	var sf: SpatialFragmenter = SpatialFragmenter.new()
	var addr: int = sf.make_address(42, 99, 7, 3, 2)
	var c1: Array[int] = sf.subdivide(addr, 2)
	var c2: Array[int] = sf.subdivide(addr, 2)
	return c1 == c2