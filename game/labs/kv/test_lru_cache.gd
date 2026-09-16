## Tests for LRU cache
extends SceneTree

var LRUCacheScript

func _init() -> void:
	LRUCacheScript = load("res://labs/kv/lru_cache.gd")
	var ok = true
	if not _test_basic_get_set():
		push_error("FAIL: basic_get_set")
		ok = false
	if not _test_lru_eviction():
		push_error("FAIL: lru_eviction")
		ok = false
	if not _test_get_promotes():
		push_error("FAIL: get_promotes")
		ok = false
	if not _test_delete():
		push_error("FAIL: delete")
		ok = false
	if not _test_has():
		push_error("FAIL: has")
		ok = false
	if not _test_clear():
		push_error("FAIL: clear")
		ok = false
	quit(0 if ok else 1)

func _test_basic_get_set() -> bool:
	var lru = LRUCacheScript.new(3)
	lru.set("a", 1)
	lru.set("b", 2)
	assert(lru.get("a") == 1)
	assert(lru.get("b") == 2)
	assert(lru.get("missing") == null)
	assert(lru.size() == 2)
	return true

func _test_lru_eviction() -> bool:
	var lru = LRUCacheScript.new(3)
	lru.set("a", 1)
	lru.set("b", 2)
	lru.set("c", 3)
	lru.set("d", 4)
	assert(lru.get("a") == null)
	assert(lru.get("b") == 2)
	assert(lru.get("c") == 3)
	assert(lru.get("d") == 4)
	assert(lru.size() == 3)
	return true

func _test_get_promotes() -> bool:
	var lru = LRUCacheScript.new(2)
	lru.set("a", 1)
	lru.set("b", 2)
	lru.get("a")
	lru.set("c", 3)
	assert(lru.get("a") == 1)
	assert(lru.get("b") == null)
	assert(lru.get("c") == 3)
	return true

func _test_delete() -> bool:
	var lru = LRUCacheScript.new(5)
	lru.set("x", 99)
	assert(lru.delete("x") == true)
	assert(lru.get("x") == null)
	assert(lru.delete("missing") == false)
	return true

func _test_has() -> bool:
	var lru = LRUCacheScript.new(5)
	lru.set("k", 42)
	assert(lru.has("k") == true)
	assert(lru.has("nope") == false)
	return true

func _test_clear() -> bool:
	var lru = LRUCacheScript.new(5)
	lru.set("a", 1)
	lru.set("b", 2)
	lru.clear()
	assert(lru.size() == 0)
	assert(lru.get("a") == null)
	return true
