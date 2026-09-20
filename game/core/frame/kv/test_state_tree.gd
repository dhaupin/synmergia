## StateTree wrapper tests. Spec: labs/prd-state-schema.md, world-building-arch.md S8
extends SceneTree

const T3Script = preload("res://core/frame/kv/t3.gd")
const StateTreeScript = preload("res://core/frame/kv/state_tree.gd")
const StateSchemaScript = preload("res://data/roots/state_schema.gd")

var _passed := 0
var _failed := 0


func _init() -> void:
	_test_init_default()
	_test_init_with_t3()
	_test_insert_get_position()
	_test_insert_get_health()
	_test_insert_get_inventory()
	_test_update_state()
	_test_root_hash_thirty_two_bytes()
	_test_diff_same_roots()
	_test_diff_different_roots()
	_test_apply_diff_roundtrip()
	_test_apply_diff_empty()
	_test_hash_determinism()
	_test_missing_path_returns_empty_dict()
	_test_multiple_entities()
	_test_type_agnostic_nine_types()
	_test_diff_reports_correct_path()
	print("StateTree tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_init_default() -> void:
	var tree := StateTreeScript.new()
	_assert(tree != null, "init default creates StateTree")
	_assert(tree.root_hash().size() == 32, "default tree has 32-byte root hash")


func _test_init_with_t3() -> void:
	var t3 := T3Script.new()
	var tree := StateTreeScript.new(t3)
	_assert(tree != null, "init with T3 creates StateTree")
	_assert(tree.root_hash().size() == 32, "wrapped T3 tree has 32-byte root hash")


func _test_insert_get_position() -> void:
	var tree := StateTreeScript.new()
	var hash := tree.insert_state("entities/player_1", "player_1", "position", {"x": 10.0, "y": 0.0, "z": -5.0})
	_assert(hash.size() == 32, "insert_state returns 32-byte hash")
	var state := tree.get_state("entities/player_1")
	_assert(state.get("type") == "position", "retrieved state has correct type")
	_assert(state.get("entity_id") == "player_1", "retrieved state has correct entity_id")
	_assert(state.get("payload").get("x") == 10.0, "retrieved payload has correct x")
	_assert(state.get("payload").get("y") == 0.0, "retrieved payload has correct y")
	_assert(state.get("payload").get("z") == -5.0, "retrieved payload has correct z")


func _test_insert_get_health() -> void:
	var tree := StateTreeScript.new()
	var hash := tree.insert_state("entities/enemy_1", "enemy_1", "health", {"current": 50, "max": 100})
	_assert(hash.size() == 32, "insert_state returns 32-byte hash")
	var state := tree.get_state("entities/enemy_1")
	_assert(state.get("type") == "health", "retrieved state has correct type")
	_assert(state.get("entity_id") == "enemy_1", "retrieved state has correct entity_id")
	_assert(state.get("payload").get("current") == 50, "retrieved payload has correct current")
	_assert(state.get("payload").get("max") == 100, "retrieved payload has correct max")


func _test_insert_get_inventory() -> void:
	var tree := StateTreeScript.new()
	var hash := tree.insert_state("entities/player_1", "player_1", "inventory", {"items": ["sword", "shield", "potion"]})
	_assert(hash.size() == 32, "insert_state returns 32-byte hash")
	var state := tree.get_state("entities/player_1")
	_assert(state.get("type") == "inventory", "retrieved state has correct type")
	_assert(state.get("entity_id") == "player_1", "retrieved state has correct entity_id")
	_assert(state.get("payload").get("items").size() == 3, "retrieved payload has correct item count")


func _test_update_state() -> void:
	var tree := StateTreeScript.new()
	tree.insert_state("entities/player_1", "player_1", "health", {"current": 50, "max": 100})
	var hash1 := tree.root_hash()
	var hash2 := tree.update_state("entities/player_1", "player_1", "health", {"current": 75, "max": 100})
	_assert(hash2.size() == 32, "update_state returns 32-byte hash")
	_assert(hash2 != hash1, "root hash changes after update")
	var state := tree.get_state("entities/player_1")
	_assert(state.get("payload").get("current") == 75, "payload updated to new value")


func _test_root_hash_thirty_two_bytes() -> void:
	var tree := StateTreeScript.new()
	var hash := tree.root_hash()
	_assert(hash.size() == 32, "root_hash returns 32 bytes")
	tree.insert_state("a", "a", "position", {"x": 0, "y": 0, "z": 0})
	var hash2 := tree.root_hash()
	_assert(hash2.size() == 32, "root_hash still 32 bytes after insert")
	_assert(hash2 != hash, "root hash changes after insert")


func _test_diff_same_roots() -> void:
	var tree := StateTreeScript.new()
	var root := tree.root_hash()
	var diff := tree.diff_states(root, root)
	_assert(diff.is_empty(), "diff of same roots is empty")


func _test_diff_different_roots() -> void:
	var tree := StateTreeScript.new()
	var root_a := tree.root_hash()
	tree.insert_state("entities/player_1", "player_1", "position", {"x": 1, "y": 2, "z": 3})
	tree.insert_state("entities/enemy_1", "enemy_1", "health", {"current": 10, "max": 10})
	var root_b := tree.root_hash()
	var diff := tree.diff_states(root_a, root_b)
	_assert(diff.size() == 2, "diff reports two changed paths")
	var paths := []
	for entry in diff:
		paths.append(entry[0])
	paths.sort()
	_assert(paths == ["entities/enemy_1", "entities/player_1"], "diff paths are correct and ordered")


func _test_apply_diff_roundtrip() -> void:
	var tree := StateTreeScript.new()
	var root_a := tree.root_hash()
	tree.insert_state("entities/player_1", "player_1", "position", {"x": 1, "y": 2, "z": 3})
	tree.insert_state("entities/enemy_1", "enemy_1", "health", {"current": 10, "max": 10})
	var root_b := tree.root_hash()
	var diff := tree.diff_states(root_a, root_b)
	var tree2 := StateTreeScript.new()
	var applied_root := tree2.apply_diff(root_a, diff)
	_assert(applied_root == root_b, "apply_diff roundtrip returns target root")
	var state1 := tree2.get_state("entities/player_1")
	var state2 := tree2.get_state("entities/enemy_1")
	_assert(state1.get("type") == "position" and state1.get("payload").get("x") == 1, "player state restored")
	_assert(state2.get("type") == "health" and state2.get("payload").get("current") == 10, "enemy state restored")


func _test_apply_diff_empty() -> void:
	var tree := StateTreeScript.new()
	var root := tree.root_hash()
	var result_root := tree.apply_diff(root, [])
	_assert(result_root == root, "empty diff leaves root unchanged")


func _test_hash_determinism() -> void:
	var tree1 := StateTreeScript.new()
	var tree2 := StateTreeScript.new()
	tree1.insert_state("entities/player_1", "player_1", "position", {"x": 10.0, "y": 0.0, "z": -5.0})
	tree2.insert_state("entities/player_1", "player_1", "position", {"x": 10.0, "y": 0.0, "z": -5.0})
	_assert(tree1.root_hash() == tree2.root_hash(), "same inserts produce same root hash")


func _test_missing_path_returns_empty_dict() -> void:
	var tree := StateTreeScript.new()
	var state := tree.get_state("entities/missing")
	_assert(state == {}, "missing path returns empty dict")


func _test_multiple_entities() -> void:
	var tree := StateTreeScript.new()
	tree.insert_state("entities/player_1", "player_1", "position", {"x": 1, "y": 2, "z": 3})
	tree.insert_state("entities/player_2", "player_2", "health", {"current": 100, "max": 100})
	tree.insert_state("entities/enemy_1", "enemy_1", "inventory", {"items": ["gold"]})
	tree.insert_state("entities/npc_1", "npc_1", "faction", {"faction_id": "guild_a", "standing": 0.8})
	_assert(tree.root_hash().size() == 32, "root hash is 32 bytes with multiple entities")
	_assert(tree.get_state("entities/player_1").get("type") == "position", "player_1 state correct")
	_assert(tree.get_state("entities/player_2").get("type") == "health", "player_2 state correct")
	_assert(tree.get_state("entities/enemy_1").get("type") == "inventory", "enemy_1 state correct")
	_assert(tree.get_state("entities/npc_1").get("type") == "faction", "npc_1 state correct")


func _test_type_agnostic_nine_types() -> void:
	var tree := StateTreeScript.new()
	var types := ["position", "inventory", "health", "faction", "status", "quest", "social", "behavior_state", "other"]
	for i in range(types.size()):
		var type_name: String = types[i]
		var path := "entities/entity_%d" % i
		var payload := {}
		match type_name:
			"position": payload = {"x": 0, "y": 0, "z": 0}
			"health": payload = {"current": 10, "max": 10}
			"inventory": payload = {"items": []}
			"faction": payload = {"faction_id": "a", "standing": 0.0}
			"status": payload = {"effects": []}
			"quest": payload = {"quest_id": "q", "progress": 0}
			"social": payload = {"relations": {}}
			"behavior_state": payload = {"current_state": "idle", "ai_tick_state": {}}
			"other": payload = {}
		var hash := tree.insert_state(path, "entity_%d" % i, type_name, payload)
		_assert(hash.size() == 32, "type %s insert returns 32-byte hash" % type_name)
		var state := tree.get_state(path)
		_assert(state.get("type") == type_name, "type %s retrieved correctly" % type_name)


func _test_diff_reports_correct_path() -> void:
	var tree := StateTreeScript.new()
	var root_a := tree.root_hash()
	tree.insert_state("entities/player_1", "player_1", "position", {"x": 1, "y": 2, "z": 3})
	var root_b := tree.root_hash()
	var diff := tree.diff_states(root_a, root_b)
	_assert(diff.size() == 1, "diff reports exactly one changed path")
	_assert(diff[0][0] == "entities/player_1", "diff path matches inserted path")
	_assert(diff[0][1] == null, "diff old hash is null for new insert")
	_assert(diff[0][2] != null, "diff new hash is not null")
	_assert(diff[0][3] != null, "diff includes value bytes")


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)