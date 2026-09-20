## Generic LRU cache for hot queries.
## Ported from vant axolotl lib/cache.js (LRU portion).
## O(1) get/set/evict using Dictionary + Array ordering.
extends RefCounted

class_name LRUCache

var _max_size: int
var _data: Dictionary = {}
var _order: Array = []

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
	else:
		_data[key] = value
		_order.push_front(key)
		if _order.size() > _max_size:
			_evict_lru()

func has(key: String) -> bool:
	return _data.has(key)

func delete(key: String) -> bool:
	if not _data.has(key):
		return false
	_data.erase(key)
	_order.erase(key)
	return true

func size() -> int:
	return _data.size()

func max_size() -> int:
	return _max_size

func clear() -> void:
	_data.clear()
	_order.clear()

func _move_to_front(key: String) -> void:
	_order.erase(key)
	_order.push_front(key)

func _evict_lru() -> void:
	if _order.is_empty():
		return
	var lru = _order.pop_back()
	_data.erase(lru)
