extends RefCounted
class_name MemoryWrapper

const MemoryStore = preload("res://adapters/memory_layer/memory_store.gd")

var _store: MemoryStore = null

func _ensure_store() -> void:
	if _store != null:
		return
	var reg = null
	if get_tree():
		reg = get_tree().root.get_node_or_null("AdapterRegistry")
	if reg and reg.has_method("get_memory"):
		_store = reg.get_memory("default")
	if _store == null:
		_store = MemoryStore.new()
		_store.open({})
		if reg and reg.has_method("register_memory"):
			reg.register_memory("default", _store)

func get(key: String) -> Variant:
	_ensure_store()
	if _store == null:
		return null
	return _store.fetch(key)

func set(key: String, value: Variant) -> void:
	_ensure_store()
	if _store == null:
		return
	_store.store(key, value, 0)

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
