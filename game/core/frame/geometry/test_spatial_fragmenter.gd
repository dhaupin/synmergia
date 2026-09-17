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
	if not _test_nsc9_bridge():
		push_error("FAIL: nsc9_bridge")
		ok = false
	if not _test_t3_integration():
		push_error("FAIL: t3_integration")
		ok = false
	if not _test_path_for_address():
		push_error("FAIL: path_for_address")
		ok = false
	if not _test_integration_determinism():
		push_error("FAIL: integration_determinism")
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


func _test_nsc9_bridge() -> bool:
	var sf: SpatialFragmenter = SpatialFragmenter.new()
	# Test nsc9_axis_to_face
	if sf.nsc9_axis_to_face(1) != 0:
		return false
	if sf.nsc9_axis_to_face(12) != 11:
		return false
	if sf.nsc9_axis_to_face(0) != -1:
		return false
	if sf.nsc9_axis_to_face(13) != -1:
		return false
	# Test nsc9_code_to_face with valid NSC-9 codes
	if sf.nsc9_code_to_face(9_000_000_000_000 + 1_000_000_000 + 1_000_000) != 0:
		return false
	if sf.nsc9_code_to_face(9_000_000_000_000 + 1_000_000_000 + 12_000_000) != 11:
		return false
	if sf.nsc9_code_to_face(-1) != -1:
		return false
	# Test to_spatial_address
	var addr: int = sf.to_spatial_address(9_000_000_000_000 + 1_000_000_000 + 1_000_000, 100, 200, 50)
	if addr < 0:
		return false
	var test_addr: int = sf.make_address(100, 200, 50, 0, 0)
	if addr != test_addr:
		return false
	return true


func _test_t3_integration() -> bool:
	var T3Script = preload("res://core/frame/kv/t3.gd")
	var t3: Variant = T3Script.new()
	var sf: SpatialFragmenter = SpatialFragmenter.new()

	# Store a fragment
	var address: int = sf.make_address(1, 2, 3, 0, 4)
	var path: String = sf.path_for_address(address)
	var hash: PackedByteArray = sf.store_fragment_in_t3(t3, path, address)
	if hash.size() == 0:
		return false

	# Query the fragment
	var results: Array[Dictionary] = sf.query_spatial_tree(t3, path)
	if results.size() == 0:
		return false

	var fragment: Dictionary = results[0]
	if not fragment.has("address") or fragment["address"] != address:
		return false
	if not fragment.has("x") or fragment["x"] != 1:
		return false
	if not fragment.has("y") or fragment["y"] != 2:
		return false
	if not fragment.has("z") or fragment["z"] != 3:
		return false
	if not fragment.has("depth") or fragment["depth"] != 0:
		return false
	if not fragment.has("face") or fragment["face"] != 4:
		return false
	if not fragment.has("key") or fragment["key"] != "0001-0002-0003-d0-f4":
		return false
	if not fragment.has("bbox") or not fragment["bbox"].has("min_x"):
		return false
	if not fragment.has("metadata"):
		return false

	# Test with null T3
	var empty_hash: PackedByteArray = sf.store_fragment_in_t3(null, "test/path", address)
	if empty_hash.size() != 0:
		return false

	var empty_results: Array[Dictionary] = sf.query_spatial_tree(null, "test/path")
	if empty_results.size() != 0:
		return false

	return true


func _test_path_for_address() -> bool:
	var sf: SpatialFragmenter = SpatialFragmenter.new()
	# Test path_for_address with known address
	var addr1: int = sf.make_address(1, 2, 3, 0, 4)
	if sf.path_for_address(addr1) != "spatial/0001-0002-0003-d0-f4":
		return false

	var addr2: int = sf.make_address(16, 32, 48, 1, 0)
	if sf.path_for_address(addr2) != "spatial/0010-0020-0030-d1-f0":
		return false

	var addr3: int = sf.make_address(0, 0, 0, 0, 0)
	if sf.path_for_address(addr3) != "spatial/0000-0000-0000-d0-f0":
		return false

	return true


func _test_integration_determinism() -> bool:
	var T3Script = preload("res://core/frame/kv/t3.gd")
	var t3_1: Variant = T3Script.new()
	var t3_2: Variant = T3Script.new()
	var sf: SpatialFragmenter = SpatialFragmenter.new()

	var address: int = sf.make_address(5, 10, 15, 2, 3)
	var path: String = sf.path_for_address(address)

	var hash1: PackedByteArray = sf.store_fragment_in_t3(t3_1, path, address)
	var hash2: PackedByteArray = sf.store_fragment_in_t3(t3_2, path, address)

	if hash1.size() != hash2.size():
		return false
	for i in range(min(hash1.size(), hash2.size())):
		if hash1[i] != hash2[i]:
			return false

	var results1: Array[Dictionary] = sf.query_spatial_tree(t3_1, path)
	var results2: Array[Dictionary] = sf.query_spatial_tree(t3_2, path)

	if results1.size() != results2.size():
		return false
	if results1.size() > 0:
		var r1: Dictionary = results1[0]
		var r2: Dictionary = results2[0]
		if r1.size() != r2.size():
			return false
		for key in r1.keys():
			if not r2.has(key) or r1[key] != r2[key]:
				return false

	return true