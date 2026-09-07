extends RefCounted
class_name MemoryStore

# Process-local runtime state. Thin wrapper over Godot's Dictionary.
# Use for: active cooldowns, AOI sets, current-tick follow targets.
#
# NO cross-process visibility, NO persistence, NO TTL.
# Anything that needs those belongs in CacheStore or PersistenceStore.
#
# Mirrors a subset of CacheStore (KV + hash + set) for parity.


var _data: Dictionary = {}


func get(key: String) -> Variant:
	return _data.get(key, null)


func set(key: String, value: Variant) -> void:
	_data[key] = value


func delete(key: String) -> int:
	if _data.has(key):
		_data.erase(key)
		return 1
	return 0


func exists(key: String) -> bool:
	return _data.has(key)


func keys() -> Array:
	return _data.keys()


# --- Hashes ---

func hset(key: String, field: String, value: Variant) -> int:
	if not _data.has(key):
		_data[key] = {}
	if typeof(_data[key]) != TYPE_DICTIONARY:
		_data[key] = {}
	(_data[key] as Dictionary)[field] = value
	return 1


func hget(key: String, field: String) -> Variant:
	if not _data.has(key) or typeof(_data[key]) != TYPE_DICTIONARY:
		return null
	return (_data[key] as Dictionary).get(field, null)


func hget_all(key: String) -> Dictionary:
	if not _data.has(key) or typeof(_data[key]) != TYPE_DICTIONARY:
		return {}
	return (_data[key] as Dictionary).duplicate()


func hdel(key: String, field: String) -> int:
	if not _data.has(key) or typeof(_data[key]) != TYPE_DICTIONARY:
		return 0
	var h: Dictionary = _data[key]
	if h.has(field):
		h.erase(field)
		return 1
	return 0


# --- Sets ---

func sadd(key: String, member: String) -> int:
	if not _data.has(key):
		_data[key] = []
	if typeof(_data[key]) != TYPE_ARRAY:
		_data[key] = []
	var s: Array = _data[key]
	if not s.has(member):
		s.append(member)
		return 1
	return 0


func srem(key: String, member: String) -> int:
	if not _data.has(key) or typeof(_data[key]) != TYPE_ARRAY:
		return 0
	var s: Array = _data[key]
	var idx := s.find(member)
	if idx >= 0:
		s.remove_at(idx)
		return 1
	return 0


func smembers(key: String) -> Array:
	if not _data.has(key) or typeof(_data[key]) != TYPE_ARRAY:
		return []
	var s: Array = _data[key]
	return s.duplicate()


func sismember(key: String, member: String) -> bool:
	if not _data.has(key) or typeof(_data[key]) != TYPE_ARRAY:
		return false
	var s: Array = _data[key]
	return s.has(member)
