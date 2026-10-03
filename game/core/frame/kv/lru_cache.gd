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

func _init(max_size: int = 256) -> void:
	_max_size = max(1, max_size)

## 4.7.2 strictness: get/set collide with native Object members and fail to
## parse as class members. Canonical accessors are get_value/set_value.
func get_value(key: String) -> Variant:
	if not _data.has(key):
		return null
	_move_to_front(key)
	return _data[key]

func set_value(key: String, value: Variant) -> void:
	if _data.has(key):
		_data[key] = value
		_move_to_front(key)
		return
	_data[key] = value
	_push_front(key)
	if _data.size() > _max_size:
		_evict_lru()

func has(key: String) -> bool:
	return _data.has(key)

func delete(key: String) -> bool:
	if not _data.has(key):
		return false
	_unlink(key)
	_data.erase(key)
	return true

func size() -> int:
	return _data.size()

func max_size() -> int:
	return _max_size

func clear() -> void:
	_data.clear()
	_prev.clear()
	_next.clear()
	_head = ""
	_tail = ""

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
