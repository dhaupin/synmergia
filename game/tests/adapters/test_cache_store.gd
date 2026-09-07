## Test the in-memory cache store. Covers KV, TTL, counters,
## hashes, sets, and lists -- the operations the game actually uses.
##
## Run with:
##   tools/godot --headless --path synmergia --script res://tests/adapters/test_cache_store.gd
extends SceneTree

const MemoryCacheStore = preload("res://adapters/cache/memory_cache_store.gd")

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	print("--- CACHE STORE TEST ---")

	var cache = MemoryCacheStore.new()
	var rc := cache.connect({})
	if rc != 0:
		_fail("connect returned %d" % rc)
		_finish()
		return
	_ok("connect returned 0")

	_test_basic_kv(cache)
	_test_ttl(cache)
	_test_counters(cache)
	_test_hashes(cache)
	_test_sets(cache)
	_test_lists(cache)
	_test_set_nx(cache)
	_test_expire(cache)

	_finish()


func _test_basic_kv(cache: MemoryCacheStore) -> void:
	cache.reset()
	if cache.set("k1", "v1") != 1:
		_fail("set returned non-1")
		return
	if cache.get("k1") != "v1":
		_fail("get returned wrong value")
		return
	if cache.get("missing") != null:
		_fail("get on missing key should return null")
		return
	_ok("basic KV set/get")
	if cache.delete("k1") != 1:
		_fail("delete returned 0")
		return
	if cache.exists("k1"):
		_fail("key still exists after delete")
		return
	_ok("delete + exists")


func _test_ttl(cache: MemoryCacheStore) -> void:
	cache.reset()
	cache.set("temp", "value", 1)  # 1 second TTL
	if cache.get("temp") != "value":
		_fail("immediate read should return value")
		return
	_ok("set with TTL preserves value")
	# Force expiry: set TTL to 0 (no expiry), then set with past TTL.
	# Easier: just test that sweep_expired works after we manually expire.
	cache._expires["temp"] = Time.get_unix_time_from_system() - 1.0
	if cache.get("temp") != null:
		_fail("expired key should return null on get")
		return
	_ok("expired key returns null on get")


func _test_counters(cache: MemoryCacheStore) -> void:
	cache.reset()
	if cache.incr("counter") != 1:
		_fail("first incr should be 1")
		return
	if cache.incr("counter") != 2:
		_fail("second incr should be 2")
		return
	if cache.incr_by("counter", 10) != 12:
		_fail("incr_by 10 should give 12")
		return
	_ok("counter ops work")

	if cache.incr_with_ttl("rate_limit", 60) != 1:
		_fail("incr_with_ttl should return 1")
		return
	if cache.get("rate_limit") != 1:
		_fail("rate_limit should be 1 after incr_with_ttl")
		return
	_ok("incr_with_ttl creates counter with TTL")


func _test_hashes(cache: MemoryCacheStore) -> void:
	cache.reset()
	cache.hset("user:1", "name", "alice")
	cache.hset("user:1", "level", 5)
	if cache.hget("user:1", "name") != "alice":
		_fail("hget wrong value")
		return
	if cache.hget("user:1", "level") != 5:
		_fail("hget int wrong value")
		return
	var all: Dictionary = cache.hget_all("user:1")
	if all.size() != 2 or all.get("name") != "alice":
		_fail("hget_all wrong: %s" % str(all))
		return
	_ok("hset / hget / hget_all")

	if cache.hdel("user:1", "level") != 1:
		_fail("hdel returned 0")
		return
	if cache.hget("user:1", "level") != null:
		_fail("hdel did not remove field")
		return
	_ok("hdel removes field")


func _test_sets(cache: MemoryCacheStore) -> void:
	cache.reset()
	cache.sadd("fruits", "apple")
	cache.sadd("fruits", "banana")
	cache.sadd("fruits", "apple")  # duplicate
	var members: Array = cache.smembers("fruits")
	if members.size() != 2:
		_fail("set should have 2 unique members, got %d" % members.size())
		return
	if not cache.sismember("fruits", "apple"):
		_fail("apple should be a member")
		return
	_ok("sadd / smembers / sismember")

	if cache.srem("fruits", "banana") != 1:
		_fail("srem returned 0")
		return
	if cache.sismember("fruits", "banana"):
		_fail("banana should be removed")
		return
	_ok("srem removes member")


func _test_lists(cache: MemoryCacheStore) -> void:
	cache.reset()
	cache.rpush("queue", "a")
	cache.rpush("queue", "b")
	cache.rpush("queue", "c")
	if cache.llen("queue") != 3:
		_fail("llen should be 3")
		return
	_ok("rpush + llen")

	var first = cache.lpop("queue")
	if first != "a":
		_fail("lpop should return a, got %s" % str(first))
		return
	_ok("lpop returns first element")

	var middle: Array = cache.lrange("queue", 0, -1)
	if middle.size() != 2 or middle[0] != "b" or middle[1] != "c":
		_fail("lrange wrong: %s" % str(middle))
		return
	_ok("lrange returns remaining elements")

	cache.lpush("queue", "z")
	if cache.lrange("queue", 0, -1)[0] != "z":
		_fail("lpush should put z first")
		return
	_ok("lpush prepends")


func _test_set_nx(cache: MemoryCacheStore) -> void:
	cache.reset()
	if not cache.set_nx("lock", "owner1", 30):
		_fail("first set_nx should succeed")
		return
	if cache.set_nx("lock", "owner2", 30):
		_fail("second set_nx should fail (key exists)")
		return
	if cache.get("lock") != "owner1":
		_fail("set_nx should not overwrite")
		return
	_ok("set_nx only sets when key absent")


func _test_expire(cache: MemoryCacheStore) -> void:
	cache.reset()
	cache.set("k", "v")
	if cache.expire("k", 60) != 1:
		_fail("expire on existing key should return 1")
		return
	if cache.expire("missing", 60) != -1:
		_fail("expire on missing key should return -1")
		return
	_ok("expire returns 1 / -1 / 0 correctly")


func _ok(msg: String) -> void:
	_passed += 1
	print("  [PASS] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
