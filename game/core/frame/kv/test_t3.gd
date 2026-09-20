## T3 substrate smoke tests.
extends SceneTree

const T3_SCRIPT = preload("res://core/frame/kv/t3.gd")

var _passed := 0
var _failed := 0


func _init() -> void:
	_test_empty_tree()
	_test_insert_get_and_normalize()
	_test_hash_determinism()
	_test_subtree_hashes()
	_test_delete()
	_test_diff()
	_test_apply_diff()
	_test_walk()
	_test_invalid_callback()
	quit(0 if _failed == 0 else 1)


func _test_empty_tree() -> void:
	var tree = _new_tree()
	var empty_hash: PackedByteArray = tree.hash_subtree("/")
	_assert(empty_hash.size() == 32, "empty root hash has 32 bytes")
	_assert(tree.hash_subtree("/missing/") == empty_hash, "missing subtree hashes empty bytes")
	_assert(tree.get_at("missing") == null, "missing value returns null")
	_assert(not tree.delete("missing"), "missing delete returns false")


func _test_insert_get_and_normalize() -> void:
	var tree = _new_tree()
	var schema := Resource.new()
	var hash: PackedByteArray = tree.insert("//alpha///beta//", {"count": 3}, schema)
	_assert(hash.size() == 32, "insert returns a 32-byte hash")
	_assert(tree.get_at("alpha/beta") == {"count": 3}, "inserted value is retrievable")
	_assert(tree.get_at("/alpha/beta/") == {"count": 3}, "path normalization is symmetric")
	_assert(tree.get_at("alpha/beta///") == {"count": 3}, "trailing slashes normalize")
	_assert(tree.insert("alpha/beta", {"count": 3}, schema) == hash, "idempotent insert returns same hash")


func _test_hash_determinism() -> void:
	var tree = _new_tree()
	var schema := Resource.new()
	var first: PackedByteArray = tree.insert("deterministic", [1, 2, 3], schema)
	var second: PackedByteArray = tree.insert("/deterministic/", [1, 2, 3], schema)
	_assert(first == second, "same path value and schema produce same hash")
	var changed: PackedByteArray = tree.insert("deterministic", [1, 2, 4], schema)
	_assert(changed != first, "different value produces different hash")
	# Schema identity is deterministic (script path / native class), so
	# distinct hashes require semantically distinct schemas.
	var other_type_schema: Resource = load("res://core/frame/kv/definition_schema.gd").new()
	var schema_changed: PackedByteArray = tree.insert("schema", 1, other_type_schema)
	_assert(schema_changed == tree.insert("schema", 1, other_type_schema), "same schema is idempotent")
	var base_hash: PackedByteArray = tree.insert("schema_native", 1, Resource.new())
	_assert(base_hash != tree.insert("schema_native", 1, other_type_schema), "different schema changes hash")


func _test_subtree_hashes() -> void:
	var tree = _new_tree()
	var schema := Resource.new()
	var parent_hash: PackedByteArray = tree.insert("parent", "parent-value", schema)
	_assert(tree.hash_subtree("parent") == parent_hash, "leaf subtree hash equals node hash")
	var root_before: PackedByteArray = tree.hash_subtree("/")
	var child_hash: PackedByteArray = tree.insert("parent/child", "child-value", schema)
	_assert(child_hash.size() == 32, "child hash has 32 bytes")
	_assert(tree.hash_subtree("/") != root_before, "root changes after child insert")
	_assert(tree.hash_subtree("parent") != parent_hash, "parent subtree changes after child insert")
	_assert(tree.hash_subtree("parent/child") == child_hash, "child subtree remains its node hash")


func _test_delete() -> void:
	var tree = _new_tree()
	var schema := Resource.new()
	tree.insert("parent", "parent-value", schema)
	tree.insert("parent/child", "child-value", schema)
	var parent_before: PackedByteArray = tree.hash_subtree("parent")
	var root_before: PackedByteArray = tree.hash_subtree("/")
	_assert(tree.delete("parent/child"), "existing node deletes successfully")
	_assert(not tree.delete("parent/child"), "second delete returns false")
	_assert(tree.get_at("parent/child") == null, "deleted value is unavailable")
	_assert(tree.get_at("parent") == "parent-value", "deleting child keeps parent value")
	_assert(tree.hash_subtree("parent") != parent_before, "parent hash changes after child deletion")
	_assert(tree.hash_subtree("/") != root_before, "root reflects deletion")


func _test_diff() -> void:
	var tree = _new_tree()
	var schema := Resource.new()
	var root_a: PackedByteArray = tree.hash_subtree("/")
	tree.insert("a", 1, schema)
	tree.insert("b", 2, schema)
	root_a = tree.hash_subtree("/")
	var first_diff: Array = tree.diff(root_a, root_a)
	_assert(first_diff.is_empty(), "same roots produce an empty diff")

	tree.insert("a", 10, schema)
	tree.insert("c", 3, schema)
	tree.delete("b")
	var root_b: PackedByteArray = tree.hash_subtree("/")
	var changes: Array = tree.diff(root_a, root_b)
	_assert(changes.size() == 3, "diff reports only changed paths")
	_assert(changes[0][0] == "a" and changes[1][0] == "b" and changes[2][0] == "c", "diff is path ordered")
	_assert(changes[0][1] != null and changes[0][2] != null, "updated diff has old and new hashes")
	_assert(changes[1][2] == null, "deleted diff has a null new hash")
	_assert(changes[2][1] == null and changes[2][3] != null, "inserted diff has no old hash and has value bytes")
	_assert(tree.diff(root_a, root_b) == changes, "diff is deterministic")


func _test_apply_diff() -> void:
	var tree = _new_tree()
	var schema := Resource.new()
	var root_a: PackedByteArray = tree.hash_subtree("/")
	tree.insert("a", 1, schema)
	tree.insert("b", 2, schema)
	root_a = tree.hash_subtree("/")
	tree.insert("a", 10, schema)
	tree.insert("c", 3, schema)
	tree.delete("b")
	var root_b: PackedByteArray = tree.hash_subtree("/")
	var changes: Array = tree.diff(root_a, root_b)
	_assert(tree.apply_diff(root_b, []) == root_b, "empty diff leaves root unchanged")
	_assert(tree.apply_diff(root_a, changes) == root_b, "diff roundtrip returns target root")
	_assert(tree.get_at("a") == 10 and tree.get_at("c") == 3 and tree.get_at("b") == null, "applied diff restores values")


func _test_walk() -> void:
	var tree = _new_tree()
	var schema := Resource.new()
	tree.insert("scope", "root", schema)
	tree.insert("scope/child", "child", schema)
	tree.insert("scope/child/deep", "deep", schema)
	tree.insert("scope/sibling", "sibling", schema)
	tree.insert("scope_other", "outside", schema)
	var seen: Array = []
	tree.walk("/scope/", func(path: String, hash: PackedByteArray, value: Variant) -> void:
		seen.append([path, value])
	)
	_assert(seen == [["scope", "root"], ["scope/child", "child"], ["scope/child/deep", "deep"], ["scope/sibling", "sibling"]], "walk is scoped and depth-first")

	var empty_seen: Array = []
	tree.walk("missing", func(path: String, hash: PackedByteArray, value: Variant) -> void:
		empty_seen.append(path)
	)
	_assert(empty_seen.is_empty(), "empty subtree walk invokes no callback")


func _test_invalid_callback() -> void:
	var tree = _new_tree()
	tree.insert("a", 1, Resource.new())
	var counts: Array = [0]
	tree.walk("", func(path: String, hash: PackedByteArray, value: Variant) -> void:
		counts[0] += 1
		push_error("intentional walk callback error")
	)
	_assert(counts[0] == 1, "logged callback error does not stop walk")


func _new_tree():
	return T3_SCRIPT.new()


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
