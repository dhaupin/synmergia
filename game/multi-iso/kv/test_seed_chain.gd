## Seed chain derivation tests. Spec: labs/prd-t3-substrate.md, world-building-arch.md В§7
extends SceneTree

const T3Script = preload("res://labs/kv/t3.gd")
const SeedChainScript = preload("res://labs/kv/seed_chain.gd")
const SeedSchemaScript = preload("res://data/roots/seed_schema.gd")

var _passed := 0
var _failed := 0


func _init() -> void:
	_test_derive_seed_basic()
	_test_derive_seed_deterministic()
	_test_derive_seed_different_paths()
	_test_derive_seed_different_stacks()
	_test_derive_seed_empty_path()
	_test_derive_seed_bottom_up_order()
	_test_build_seed_tree_basic()
	_test_build_seed_tree_nested()
	_test_build_seed_tree_seed_types()
	_test_seed_hash_hex()
	_test_derive_seed_uses_sha256()
	print("SeedChain tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_derive_seed_basic() -> void:
	var stack := [_make_bytes("player"), _make_bytes("shard"), _make_bytes("world")]
	var hash := SeedChainScript.derive_seed(stack, "/test/path")
	_assert(hash.size() == 32, "derive_seed returns 32 bytes")


func _test_derive_seed_deterministic() -> void:
	var stack := [_make_bytes("player"), _make_bytes("shard"), _make_bytes("world")]
	var first := SeedChainScript.derive_seed(stack, "/zone/5")
	var second := SeedChainScript.derive_seed(stack, "/zone/5")
	_assert_eq(first, second, "same stack + path produces same seed")


func _test_derive_seed_different_paths() -> void:
	var stack := [_make_bytes("player"), _make_bytes("shard"), _make_bytes("world")]
	var a := SeedChainScript.derive_seed(stack, "/zone/1")
	var b := SeedChainScript.derive_seed(stack, "/zone/2")
	_assert(a != b, "different paths produce different seeds")


func _test_derive_seed_different_stacks() -> void:
	var stack_a := [_make_bytes("player"), _make_bytes("shard"), _make_bytes("world")]
	var stack_b := [_make_bytes("player"), _make_bytes("shard"), _make_bytes("different_world")]
	var a := SeedChainScript.derive_seed(stack_a, "/zone/1")
	var b := SeedChainScript.derive_seed(stack_b, "/zone/1")
	_assert(a != b, "different stacks produce different seeds")


func _test_derive_seed_empty_path() -> void:
	var stack := [_make_bytes("player"), _make_bytes("shard"), _make_bytes("world")]
	var hash := SeedChainScript.derive_seed(stack, "")
	_assert(hash.size() == 32, "empty path still produces a 32-byte seed")


func _test_derive_seed_bottom_up_order() -> void:
	var player_seed := _make_bytes("p")
	var shard_seed := _make_bytes("s")
	var world_seed := _make_bytes("w")
	var stack := [player_seed, shard_seed, world_seed]
	var path := "/test"
	var acc := path.to_utf8_buffer()
	acc = _sha256(world_seed + acc)
	acc = _sha256(shard_seed + acc)
	acc = _sha256(player_seed + acc)
	var expected := acc
	var actual := SeedChainScript.derive_seed(stack, path)
	_assert_eq(actual, expected, "bottom-up order: world first, shard second, player last")


func _test_build_seed_tree_basic() -> void:
	var t3 := T3Script.new()
	var chain := SeedChainScript.new()
	var stack := [_make_bytes("player"), _make_bytes("shard"), _make_bytes("world")]
	var world_root := {
		"root_node": {
			"seed_type": "locked",
			"visibility_scope": "world",
			"path": "/root",
			"parameters": {"zone": 1},
			"children": {}
		}
	}
	var root_hash := chain.build_seed_tree(t3, stack, world_root)
	_assert(root_hash.size() == 32, "build_seed_tree returns 32-byte root hash")
	var value := t3.get("root_node")
	_assert(value != null, "root_node was inserted into T3")
	if value:
		_assert_eq(value["seed_type"], "locked", "seed_type is preserved")


func _test_build_seed_tree_nested() -> void:
	var t3 := T3Script.new()
	var chain := SeedChainScript.new()
	var stack := [_make_bytes("p"), _make_bytes("s"), _make_bytes("w")]
	var world_root := {
		"world": {
			"seed_type": "locked",
			"visibility_scope": "world",
			"path": "/world",
			"parameters": {},
			"children": {
				"shard_1": {
					"seed_type": "open",
					"visibility_scope": "shard",
					"path": "/world/shard_1",
					"parameters": {"inst": "abc"},
					"children": {
						"inst_a": {
							"seed_type": "frame",
							"visibility_scope": "instance",
							"path": "/world/shard_1/inst_a",
							"parameters": {"players": 3},
							"children": {}
						}
					}
				}
			}
		}
	}
	var root_hash := chain.build_seed_tree(t3, stack, world_root)
	_assert(root_hash.size() == 32, "nested tree root hash is 32 bytes")
	_assert(t3.get("world") != null, "world node inserted")
	_assert(t3.get("world/shard_1") != null, "shard child inserted")
	_assert(t3.get("world/shard_1/inst_a") != null, "instance grandchild inserted")


func _test_build_seed_tree_seed_types() -> void:
	var t3 := T3Script.new()
	var chain := SeedChainScript.new()
	var stack := [_make_bytes("p"), _make_bytes("s"), _make_bytes("w")]
	var world_root := {
		"locked_node": {"seed_type": "locked", "visibility_scope": "world", "path": "/locked", "parameters": {}, "children": {}},
		"open_node": {"seed_type": "open", "visibility_scope": "instance", "path": "/open", "parameters": {}, "children": {}},
		"frame_node": {"seed_type": "frame", "visibility_scope": "player", "path": "/frame", "parameters": {}, "children": {}}
	}
	chain.build_seed_tree(t3, stack, world_root)
	var locked_val = t3.get("locked_node")
	var open_val = t3.get("open_node")
	var frame_val = t3.get("frame_node")
	_assert_eq(locked_val["seed_type"], "locked", "locked seed type preserved")
	_assert_eq(open_val["seed_type"], "open", "open seed type preserved")
	_assert_eq(frame_val["seed_type"], "frame", "frame seed type preserved")


func _test_seed_hash_hex() -> void:
	var seed := PackedByteArray([1, 2, 3, 4, 5])
	var hex := SeedChainScript.seed_hash(seed)
	_assert_eq(hex, "0102030405", "seed_hash returns hex-encoded string")
	_assert_eq(hex.length(), 10, "hex string has 2 chars per byte")


func _test_derive_seed_uses_sha256() -> void:
	var stack: Array[PackedByteArray] = []
	var hash := SeedChainScript.derive_seed(stack, "/empty")
	_assert(hash.size() == 32, "empty stack still produces 32-byte SHA-256")
	var hash2 := SeedChainScript.derive_seed(stack, "/empty")
	_assert_eq(hash, hash2, "SHA-256 is deterministic")


func _make_bytes(input: String) -> PackedByteArray:
	return input.to_utf8_buffer()


func _sha256(data: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	if not data.is_empty():
		context.update(data)
	return context.finish()


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
