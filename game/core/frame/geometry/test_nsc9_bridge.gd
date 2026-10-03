## Cross-layer integration tests: NSC-9 -> SpatialFragmenter -> T3 bridge
extends SceneTree

const Nsc9BridgeScript = preload("res://core/frame/geometry/nsc9_bridge.gd")
const T3Script = preload("res://core/frame/kv/t3.gd")
const FragmenterScript = preload("res://core/frame/geometry/fragmenter.gd")
const Nsc9Script = preload("res://core/frame/math/nsc9.gd")

func _init() -> void:
	var ok = true

	if not _test_nsc9_to_address():
		push_error("FAIL: nsc9_to_address")
		ok = false
	if not _test_nsc9_to_t3_path():
		push_error("FAIL: nsc9_to_t3_path")
		ok = false
	if not _test_store_nsc9_state_and_query_region():
		push_error("FAIL: store_nsc9_state_and_query_region")
		ok = false
	if not _test_store_nsc9_state_deterministic():
		push_error("FAIL: store_nsc9_state_deterministic")
		ok = false
	if not _test_store_nsc9_fragmented_and_restore():
		push_error("FAIL: store_nsc9_fragmented_and_restore")
		ok = false
	if not _test_query_nsc9_vertex():
		push_error("FAIL: query_nsc9_vertex")
		ok = false
	if not _test_non_spatial_nsc9_returns_zero():
		push_error("FAIL: non_spatial_nsc9_returns_zero")
		ok = false
	if not _test_is_spatial_nsc9():
		push_error("FAIL: is_spatial_nsc9")
		ok = false
	if not _test_entity_spatial_to_vertex():
		push_error("FAIL: entity_spatial_to_vertex")
		ok = false

	quit(0 if ok else 1)


func _test_nsc9_to_address() -> bool:
	var bridge := Nsc9BridgeScript.new()
	var nsc9 := Nsc9Script.new()

	# Valid spatial axis (1-12). facility=7, axis=1 (spatial), seq=0
	var code := nsc9.encode_int(7, 1, 0)  # 9-007-001-000000
	var addr := bridge.nsc9_to_address(code)
	if addr == 0:
		return false

	# Vertex should map axis 1 -> vertex 0
	var sf := preload("res://core/frame/geometry/spatial_fragmenter.gd").new()
	if sf.get_vertex(addr) != 0:
		return false

	# Different axis -> different vertex
	var code2 := nsc9.encode_int(7, 2, 0)
	var addr2 := bridge.nsc9_to_address(code2)
	if addr2 == 0:
		return false
	if sf.get_vertex(addr2) != 1:
		return false

	# Depth parameter respected
	var addr_depth := bridge.nsc9_to_address(code, 3)
	if sf.get_depth(addr_depth) != 3:
		return false

	return true


func _test_nsc9_to_t3_path() -> bool:
	var bridge := Nsc9BridgeScript.new()
	var nsc9 := Nsc9Script.new()
	var code := nsc9.encode_int(1, 1, 0)  # facility=1, axis=1, seq=0

	var path1 := bridge.nsc9_to_t3_path(code)
	var addr := bridge.nsc9_to_address(code)
	var path2 := bridge.address_to_t3_path(addr)
	if path1 != path2:
		return false

	# Expected format "spatial/0001-0000-0000-d0-v0"
	if not path1.begins_with("spatial/"):
		return false
	return true


func _test_store_nsc9_state_and_query_region() -> bool:
	var bridge := Nsc9BridgeScript.new()
	var t3 := T3Script.new()
	var nsc9 := Nsc9Script.new()

	var code := nsc9.encode_int(5, 3, 12345)  # spatial axis 3 -> vertex 2
	var state := {"hp": 100, "mana": 50}
	var meta := {"source": "combat"}

	var hash := bridge.store_nsc9_state(t3, code, state, 0, meta)
	if hash.size() != 32:
		return false

	var results := bridge.query_nsc9_region(t3, code)
	if results.size() == 0:
		return false

	var frag := results[0]
	if frag.get("address") == 0:
		return false
	if frag.get("vertex") != 2:
		return false
	if not frag.has("metadata"):
		return false
	if frag.metadata.get("source") != "combat":
		return false

	return true


func _test_store_nsc9_state_deterministic() -> bool:
	var bridge := Nsc9BridgeScript.new()
	var t3_a := T3Script.new()
	var t3_b := T3Script.new()
	var nsc9 := Nsc9Script.new()

	var code := nsc9.encode_int(10, 5, 999)
	var meta := {"tick": 42}

	var hash_a := bridge.store_nsc9_state(t3_a, code, {}, 0, meta)
	var hash_b := bridge.store_nsc9_state(t3_b, code, {}, 0, meta)
	if hash_a != hash_b:
		return false

	return true


func _test_store_nsc9_fragmented_and_restore() -> bool:
	var bridge := Nsc9BridgeScript.new()
	var t3 := T3Script.new()
	var fragmenter := FragmenterScript.new()
	var nsc9 := Nsc9Script.new()

	var code := nsc9.encode_int(2, 4, 0)  # spatial axis 4 -> vertex 3
	var original_state := {"items": ["sword", "shield"], "gold": 250}

	var root_hash := bridge.store_nsc9_fragmented(t3, code, original_state, fragmenter)
	if root_hash.size() != 32:
		return false

	var restored := bridge.restore_nsc9_fragmented(t3, code, fragmenter)
	# JSON round-trip reorders dictionary keys; compare structurally.
	return restored.size() == original_state.size() and restored.has("items") and restored.has("gold") and restored.items.size() == 2 and restored.gold == 250


func _test_query_nsc9_vertex() -> bool:
	var bridge := Nsc9BridgeScript.new()
	var t3 := T3Script.new()
	var nsc9 := Nsc9Script.new()

	# Store two codes on different vertices
	var code_a := nsc9.encode_int(1, 1, 0)  # vertex 0
	var code_b := nsc9.encode_int(2, 2, 0)  # vertex 1
	bridge.store_nsc9_state(t3, code_a, {}, 0, {"id": "A"})
	bridge.store_nsc9_state(t3, code_b, {}, 0, {"id": "B"})

	var vertex0_results := bridge.query_nsc9_vertex(t3, code_a)
	var vertex1_results := bridge.query_nsc9_vertex(t3, code_b)

	if vertex0_results.size() != 1:
		return false
	if vertex1_results.size() != 1:
		return false
	if vertex0_results[0].metadata.get("id") != "A":
		return false
	if vertex1_results[0].metadata.get("id") != "B":
		return false

	# Query with a code that maps to vertex 0 should not return vertex 1 fragments
	var vertex0_again := bridge.query_nsc9_vertex(t3, nsc9.encode_int(99, 1, 0))
	if vertex0_again.size() != 1:
		return false

	return true


func _test_non_spatial_nsc9_returns_zero() -> bool:
	var bridge := Nsc9BridgeScript.new()
	var nsc9 := Nsc9Script.new()

	# Axis 100 is factional (non-spatial)
	var code := nsc9.encode_int(7, 100, 123)
	var addr := bridge.nsc9_to_address(code)
	if addr != 0:
		return false

	var path := bridge.nsc9_to_t3_path(code)
	if path != "":
		return false

	return true


func _test_is_spatial_nsc9() -> bool:
	var bridge := Nsc9BridgeScript.new()
	var nsc9 := Nsc9Script.new()

	var spatial_code := nsc9.encode_int(1, 5, 0)
	if not bridge.is_spatial_nsc9(spatial_code):
		return false

	var non_spatial := nsc9.encode_int(1, 200, 0)  # temporal axis
	if bridge.is_spatial_nsc9(non_spatial):
		return false

	return true


func _test_entity_spatial_to_vertex() -> bool:
	var bridge := Nsc9BridgeScript.new()
	var nsc9 := Nsc9Script.new()

	# vertex 0 -> axis 1 -> vertex 0
	if bridge.entity_spatial_to_vertex(42, 0) != 0:
		return false
	# vertex 11 -> axis 12 -> vertex 11
	if bridge.entity_spatial_to_vertex(42, 11) != 11:
		return false
	# Out of range vertex -> -1
	if bridge.entity_spatial_to_vertex(42, 12) != -1:
		return false

	return true
