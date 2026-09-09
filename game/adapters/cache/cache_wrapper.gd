extends RefCounted
class_name CacheWrapper

const CacheStore = preload("res://adapters/cache/cache_store.gd")
const MemoryCacheStore = preload("res://adapters/cache/memory_cache_store.gd")

var _store: CacheStore = null

func _ensure_store() -> void:
	if _store != null:
		return
	var reg = null
	if get_tree():
		reg = get_tree().root.get_node_or_null("AdapterRegistry")
	if reg and reg.has_method("get_cache"):
		_store = reg.get_cache("default")
	if _store == null:
		_store = MemoryCacheStore.new()
		_store.open({})
		if reg and reg.has_method("register_cache"):
			reg.register_cache("default", _store)

func get(key: String) -> Variant:
	_ensure_store()
	if _store == null:
		return null
	return _store.fetch(key)

func set(key: String, value: Variant, ttl_sec: int = 0) -> void:
	_ensure_store()
	if _store == null:
		return
	_store.store(key, value, ttl_sec)

func set_nx(key: String, value: Variant, ttl_sec: int = 0) -> bool:
	_ensure_store()
	if _store == null:
		return false
	return _store.set_nx(key, value, ttl_sec)

func delete(key: String) -> void:
	_ensure_store()
	if _store == null:
		return
	_store.delete(key)

func exists(key: String) -> bool:
	_ensure_store()
	if _store == null:
		return false
	return _store.exists(key)

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
