extends RefCounted
class_name CacheWrapper

const CacheStore = preload("res://adapters/cache/cache_store.gd")
const MemoryCacheStore = preload("res://adapters/cache/memory_cache_store.gd")

var _store: CacheStore = null

static var _adapter_registry = null

static func set_adapter_registry(reg) -> void:
	_adapter_registry = reg

# Resolve the AdapterRegistry to use; see DictStore._resolve_registry for
# why the static hook alone is not enough in --script mode.
func _resolve_registry():
	if _adapter_registry != null:
		return _adapter_registry
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		return loop.get_root().get_node_or_null("AdapterRegistry")
	return null

func _ensure_store() -> void:
	if _store != null:
		return
	var reg = _resolve_registry()
	if reg == null:
		# Fallback to memory store if registry not available yet
		_store = MemoryCacheStore.new()
		_store.open({})
		return
	if reg and reg.has_method("get_cache"):
		_store = reg.get_cache("default")
	if _store == null:
		_store = MemoryCacheStore.new()
		_store.open({})
		if reg and reg.has_method("register_cache"):
			reg.register_cache("default", _store)

func get_value(key: String) -> Variant:
	_ensure_store()
	if _store == null:
		return null
	return _store.fetch(key)

func get_kv(key: String, default: Variant = null) -> Variant:
	var val = get_value(key)
	return val if val != null else default

func set_value(key: String, value: Variant, ttl_sec: int = 0) -> void:
	_ensure_store()
	if _store == null:
		return
	_store.store(key, value, ttl_sec)

func set_kv(key: String, value: Variant, ttl_sec: int = 0) -> void:
	set_value(key, value, ttl_sec)

func _set(property: StringName, value: Variant) -> bool:
	set_value(String(property), value)
	return true

func _get(property: StringName) -> Variant:
	return get_value(String(property))

func set_nx(key: String, value: Variant, ttl_sec: int = 0) -> bool:
	_ensure_store()
	if _store == null:
		return false
	return _store.set_nx(key, value, ttl_sec)

func remove(key: String) -> void:
	_ensure_store()
	if _store == null:
		return
	_store.delete(key)

func delete(key: String) -> void:
	remove(key)

func erase(key: String) -> void:
	remove(key)

func exists(key: String) -> bool:
	_ensure_store()
	if _store == null:
		return false
	return _store.exists(key)

func has(key: String) -> bool:
	return exists(key)

func has_key(key: String) -> bool:
	return exists(key)

func all_keys() -> Array:
	_ensure_store()
	if _store == null:
		return []
	if _store.has_method("keys"):
		return _store.keys()
	return []

func expire(key: String, ttl_sec: int) -> void:
	_ensure_store()
	if _store == null:
		return
	_store.expire(key, ttl_sec)

func incr(key: String) -> int:
	_ensure_store()
	if _store == null:
		return 0
	return _store.incr(key)

func incr_by(key: String, delta: int) -> int:
	_ensure_store()
	if _store == null:
		return 0
	return _store.incr_by(key, delta)

func incr_with_ttl(key: String, ttl_sec: int) -> int:
	_ensure_store()
	if _store == null:
		return 0
	return _store.incr_with_ttl(key, ttl_sec)

func hset(key: String, field: String, value: Variant) -> int:
	_ensure_store()
	if _store == null:
		return 0
	return _store.hset(key, field, value)

func hget(key: String, field: String) -> Variant:
	_ensure_store()
	if _store == null:
		return null
	return _store.hget(key, field)

func hget_all(key: String) -> Dictionary:
	_ensure_store()
	if _store == null:
		return {}
	return _store.hget_all(key)

func hdel(key: String, field: String) -> int:
	_ensure_store()
	if _store == null:
		return 0
	return _store.hdel(key, field)

func sadd(key: String, member: String) -> int:
	_ensure_store()
	if _store == null:
		return 0
	return _store.sadd(key, member)

func srem(key: String, member: String) -> int:
	_ensure_store()
	if _store == null:
		return 0
	return _store.srem(key, member)

func smembers(key: String) -> Array:
	_ensure_store()
	if _store == null:
		return []
	return _store.smembers(key)

func sismember(key: String, member: String) -> bool:
	_ensure_store()
	if _store == null:
		return false
	return _store.sismember(key, member)

func lpush(key: String, value: Variant) -> int:
	_ensure_store()
	if _store == null:
		return 0
	return _store.lpush(key, value)

func rpush(key: String, value: Variant) -> int:
	_ensure_store()
	if _store == null:
		return 0
	return _store.rpush(key, value)

func lpop(key: String) -> Variant:
	_ensure_store()
	if _store == null:
		return null
	return _store.lpop(key)

func lrange(key: String, start: int, stop: int) -> Array:
	_ensure_store()
	if _store == null:
		return []
	return _store.lrange(key, start, stop)

func llen(key: String) -> int:
	_ensure_store()
	if _store == null:
		return 0
	return _store.llen(key)
