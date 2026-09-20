## MemoryTree tests. Spec: labs/world-building-arch.md §9
extends SceneTree

const T3Script = preload("res://core/frame/kv/t3.gd")
const MemoryTreeScript = preload("res://core/frame/kv/memory_tree.gd")
const MemorySchemaScript = preload("res://core/frame/kv/memory_schema.gd")

var _passed := 0
var _failed := 0


func _init() -> void:
	_test_init()
	_test_insert_get()
	_test_update()
	_test_delete()
	_test_list()
	_test_list_by_kind()
	_test_agent_root_hash()
	_test_diff_same()
	_test_diff_different()
	_test_apply_diff_roundtrip()
	_test_determinism()
	print("MemoryTree tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_init() -> void:
	var tree := MemoryTreeScript.new()
	_assert(tree != null, "init creates MemoryTree")
	var schema := MemorySchemaScript.new()
	_assert(schema != null, "MemorySchema creates instance")
	var hash := tree.agent_root_hash("/memory/agent_1")
	_assert(hash.size() == 32, "empty subtree has 32-byte root hash")


func _test_insert_get() -> void:
	var tree := MemoryTreeScript.new()
	var hash := tree.insert_memory("/memory/npc_blacksmith", "observation", {"player": "alice", "action": "bought sword"}, 0.8)
	_assert(hash.size() == 32, "insert_memory returns 32-byte hash")
	var mem := tree.get_memory("/memory/npc_blacksmith")
	_assert(mem.get("kind") == "observation", "retrieved memory has kind")
	_assert(mem.get("content").get("player") == "alice", "retrieved content has player")
	_assert(absf(float(mem.get("weight")) - 0.8) < 0.001, "retrieved memory has weight")


func _test_update() -> void:
	var tree := MemoryTreeScript.new()
	tree.insert_memory("/memory/npc_g", "goal", {"want": "protect_village"}, 1.0)
	var h1 := tree.get_memory("/memory/npc_g")
	_assert(h1.get("content").get("want") == "protect_village", "initial goal present")
	tree.update_memory("/memory/npc_g", "goal", {"want": "defend_gate"}, 1.0)
	var mem := tree.get_memory("/memory/npc_g")
	_assert(mem.get("content").get("want") == "defend_gate", "update replaces content")


func _test_delete() -> void:
	var tree := MemoryTreeScript.new()
	tree.insert_memory("/memory/npc_x/m1", "fact", {"k": "v"}, 1.0)
	_assert(tree.delete_memory("/memory/npc_x/m1"), "delete returns true for existing")
	_assert(not tree.delete_memory("/memory/npc_x/m1"), "delete returns false for missing")
	_assert(tree.get_memory("/memory/npc_x/m1").is_empty(), "deleted memory gone")


func _test_list() -> void:
	var tree := MemoryTreeScript.new()
	tree.insert_memory("/memory/npc_a/obs1", "observation", {"a": 1}, 1.0)
	tree.insert_memory("/memory/npc_a/obs2", "event", {"b": 2}, 0.5)
	tree.insert_memory("/memory/npc_a/obs3", "observation", {"c": 3}, 1.0)
	var all := tree.list_memories("/memory/npc_a")
	_assert(all.size() == 3, "list_memories returns all 3")


func _test_list_by_kind() -> void:
	var tree := MemoryTreeScript.new()
	tree.insert_memory("/memory/npc_b/obs1", "observation", {"a": 1}, 1.0)
	tree.insert_memory("/memory/npc_b/obs2", "event", {"b": 2}, 0.5)
	tree.insert_memory("/memory/npc_b/obs3", "observation", {"c": 3}, 1.0)
	var obs := tree.list_by_kind("/memory/npc_b", "observation")
	_assert(obs.size() == 2, "list_by_kind returns only observations")
	var events := tree.list_by_kind("/memory/npc_b", "event")
	_assert(events.size() == 1, "list_by_kind returns only events")


func _test_agent_root_hash() -> void:
	var tree := MemoryTreeScript.new()
	tree.insert_memory("/memory/npc_c/m1", "fact", {"k": "v"}, 1.0)
	var h1 := tree.agent_root_hash("/memory/npc_c")
	_assert(h1.size() == 32, "agent subtree hash is 32 bytes")
	tree.insert_memory("/memory/npc_c/m2", "fact", {"k2": "v2"}, 1.0)
	var h2 := tree.agent_root_hash("/memory/npc_c")
	_assert(h1 != h2, "adding memory changes subtree hash")


func _test_diff_same() -> void:
	var tree := MemoryTreeScript.new()
	var r_empty := tree.root_hash()
	tree.insert_memory("/memory/npc_d/m1", "fact", {"k": "v"}, 1.0)
	var diffs := tree.diff_memories(r_empty, tree.root_hash())
	_assert(diffs.size() == 1, "diff of empty->one memory reports one changed path")


func _test_diff_different() -> void:
	var tree := MemoryTreeScript.new()
	var r1 := tree.root_hash()
	tree.insert_memory("/memory/npc_e/m1", "fact", {"k": "v1"}, 1.0)
	var r2 := tree.root_hash()
	var diffs := tree.diff_memories(r1, r2)
	_assert(diffs.size() == 1, "diff between two snapshots reports one changed path")
	_assert(str(diffs[0][0]) == "memory/npc_e/m1", "diff path is the inserted memory (normalized, no leading slash)")


func _test_apply_diff_roundtrip() -> void:
	var tree := MemoryTreeScript.new()
	var r1 := tree.root_hash()
	tree.insert_memory("/memory/npc_f/m1", "fact", {"k": "v2"}, 1.0)
	tree.insert_memory("/memory/npc_f/m2", "goal", {"g": 1}, 0.9)
	var r2 := tree.root_hash()
	var diffs := tree.diff_memories(r1, r2)
	var other := MemoryTreeScript.new()
	var applied := other.apply_diff(r1, diffs)
	_assert(applied == r2, "apply_diff roundtrips to source root")
	var mem := other.get_memory("/memory/npc_f/m1")
	_assert(mem.get("content").get("k") == "v2", "applied memory content restored")
	var goal := other.get_memory("/memory/npc_f/m2")
	_assert(goal.get("kind") == "goal", "applied goal kind restored")


func _test_determinism() -> void:
	var t1 := MemoryTreeScript.new()
	t1.insert_memory("/memory/npc_h/m1", "event", {"a": 1, "b": [1, 2]}, 0.7)
	var t2 := MemoryTreeScript.new()
	t2.insert_memory("/memory/npc_h/m1", "event", {"a": 1, "b": [1, 2]}, 0.7)
	_assert(t1.root_hash() == t2.root_hash(), "same inserts in same order produce same root hash")


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % msg)
