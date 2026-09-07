## Test the in-process memory store. No TTL, no cross-process,
## just Godot Dict/Array. Used for runtime state like cooldowns,
## active locks, etc.
##
## Run with:
##   tools/godot --headless --path synmergia --script res://tests/adapters/test_memory_store.gd
extends SceneTree

const MemoryStore = preload("res://adapters/memory_layer/memory_store.gd")

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	print("--- MEMORY STORE TEST ---")
	var mem = MemoryStore.new()
	_test_basic_kv(mem)
	_test_hashes(mem)
	_test_sets(mem)
	_finish()


func _test_basic_kv(mem: MemoryStore) -> void:
	mem.set("k1", "v1")
	if mem.get("k1") != "v1":
		_fail("get returned wrong value")
		return
	if mem.exists("k1") != true:
		_fail("exists should be true")
		return
	if mem.delete("k1") != 1:
		_fail("delete should return 1")
		return
	if mem.exists("k1") != false:
		_fail("exists should be false after delete")
		return
	_ok("basic KV")


func _test_hashes(mem: MemoryStore) -> void:
	mem.hset("user:1", "name", "alice")
	mem.hset("user:1", "level", 5)
	if mem.hget("user:1", "name") != "alice":
		_fail("hget wrong value")
		return
	if mem.hget("user:1", "level") != 5:
		_fail("hget int wrong value")
		return
	var all: Dictionary = mem.hget_all("user:1")
	if all.size() != 2:
		_fail("hget_all should return 2 fields, got %d" % all.size())
		return
	_ok("hashes: hset / hget / hget_all")

	if mem.hdel("user:1", "level") != 1:
		_fail("hdel should return 1")
		return
	if mem.hget("user:1", "level") != null:
		_fail("hdel did not remove field")
		return
	_ok("hdel removes field")


func _test_sets(mem: MemoryStore) -> void:
	mem.sadd("fruits", "apple")
	mem.sadd("fruits", "banana")
	mem.sadd("fruits", "apple")  # duplicate
	if mem.smembers("fruits").size() != 2:
		_fail("set should have 2 unique members")
		return
	if not mem.sismember("fruits", "apple"):
		_fail("apple should be a member")
		return
	_ok("sets: sadd / smembers / sismember")

	if mem.srem("fruits", "banana") != 1:
		_fail("srem should return 1")
		return
	if mem.sismember("fruits", "banana"):
		_fail("banana should be removed")
		return
	_ok("srem removes member")


func _ok(msg: String) -> void:
	_passed += 1
	print("  [PASS] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
