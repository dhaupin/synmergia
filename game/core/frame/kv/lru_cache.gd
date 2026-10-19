## Generic LRU cache for hot queries.
## Ported from vant axolotl lib/cache.js (LRU portion).
## O(1) get/set/delete/evict using a Dictionary payload plus an
## intrusive doubly-linked recency order (_prev/_next, MRU at _head,
## LRU at _tail). The prior version kept an Array and called erase()
## on every promote, which is O(n) per get/set despite the O(1) claim
## (audit round 17).
extends RefCounted

class_name LRUCache

var _max_size: int
var _data: Dictionary = {}
var _prev: Dictionary = {}   # key -> predecessor key ("" marks the head)
var _next: Dictionary = {}   # key -> successor key ("" marks the tail)
var _head: String = ""       # most-recently-used
var _tail: String = ""       # least-recently-used
## THE THREAD LAW (v5): prop derivation now runs on a background
## thread while the main thread streams mesh -- both write THIS cache
## via the terrain law. One coarse lock on every accessor keeps the
## intrusive list intact (Godot Dictionary/Array mutation is not
## thread-safe). Uncontended fast path, so the cost is tiny at the
## mesh pass's hit rate; contention only happens while a derive job
## is in flight, which is exactly the situation the lock exists for.

func _init(max_size: int = 256) -> void:
	_max_size = max(1, max_size)

var _lock := Mutex.new()

## 4.7.2 strictness: get/set collide with native Object members and fail to
## parse as class members. Canonical accessors are get_value/set_value.
func get_value(key: String) -> Variant:
	_lock.lock()
	var out: Variant = null
	if _data.has(key):
		_move_to_front(key)
		out = _data[key]
	_lock.unlock()
	return out

func set_value(key: String, value: Variant) -> void:
	_lock.lock()
	if _data.has(key):
		_data[key] = value
		_move_to_front(key)
		_lock.unlock()
		return
	_data[key] = value
	_push_front(key)
	if _data.size() > _max_size:
		_evict_lru()
	_lock.unlock()

func has(key: String) -> bool:
	_lock.lock()
	var out: bool = _data.has(key)
	_lock.unlock()
	return out

func delete(key: String) -> bool:
	if not _data.has(key):
		return false
	_unlink(key)
	_data.erase(key)
	return true

func size() -> int:
	_lock.lock()
	var out: int = _data.size()
	_lock.unlock()
	return out

func max_size() -> int:
	return _max_size

func clear() -> void:
	_lock.lock()
	_data.clear()
	_prev.clear()
	_next.clear()
	_head = ""
	_tail = ""
	_lock.unlock()

## Emptiness test that does not depend on key values (a "" key is legal):
## every linked key has an entry in BOTH _prev and _next, so if either
## dictionary is non-empty the list is non-empty.
func _list_empty() -> bool:
	return _prev.is_empty() and _next.is_empty()

## Insert key at the MRU end. O(1).
func _push_front(key: String) -> void:
	if _list_empty():
		_prev[key] = ""
		_next[key] = ""
		_head = key
		_tail = key
		return
	_prev[key] = ""
	_next[key] = _head
	_prev[_head] = key
	_head = key

## Detach key from the recency order. O(1).
func _unlink(key: String) -> void:
	var prev: String = _prev.get(key, "")
	var next: String = _next.get(key, "")
	if prev == "":
		_head = next
	else:
		_next[prev] = next
	if next == "":
		_tail = prev
	else:
		_prev[next] = prev
	_prev.erase(key)
	_next.erase(key)

func _move_to_front(key: String) -> void:
	_unlink(key)
	_push_front(key)

func _evict_lru() -> void:
	if _list_empty():
		return
	var lru: String = _tail
	_unlink(lru)
	_data.erase(lru)
