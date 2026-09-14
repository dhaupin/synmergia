extends RefCounted
class_name DictStore

const PersistenceStore = preload("res://adapters/persistence/persistence_store.gd")
const MemoryPersistenceStore = preload("res://adapters/persistence/memory_persistence_store.gd")

var _store: PersistenceStore = null
var _expires: Dictionary = {}

static var _adapter_registry = null

static func set_adapter_registry(reg) -> void:
	_adapter_registry = reg

func _ensure_store() -> void:
	if _store != null:
		return
	var reg = _adapter_registry
	if reg == null:
		# Fallback to memory store if registry not available yet
		_store = MemoryPersistenceStore.new()
		_store.open({})
		return
	if reg and reg.has_method("get_persistence"):
		_store = reg.get_persistence("default")
	if _store == null:
		_store = MemoryPersistenceStore.new()
		_store.open({})
		if reg and reg.has_method("register_persistence"):
			reg.register_persistence("default", _store)

func _is_expired(key: String) -> bool:
	if not _expires.has(key):
		return false
	var exp: float = _expires[key]
	if exp <= 0:
		return false
	return Time.get_unix_time_from_system() >= exp

func get_value(key: String) -> Variant:
	_ensure_store()
	if _store == null:
		return null
	if _is_expired(key):
		erase(key)
		return null
	var rows = _store.query("SELECT value FROM kv WHERE key = $1", [key])
	if rows.is_empty():
		return null
	var raw = rows[0].get("value", "")
	if raw == "":
		return null
	var parsed = JSON.parse_string(raw)
	return parsed

func set_value(key: String, value: Dictionary, ttl_sec: int = 0) -> void:
	_ensure_store()
	if _store == null:
		return
	var json = JSON.stringify(value)
	_store.execute("DELETE FROM kv WHERE key = $1", [key])
	_store.execute("INSERT INTO kv (key, value) VALUES ($1, $2)", [key, json])
	if ttl_sec > 0:
		_expires[key] = Time.get_unix_time_from_system() + ttl_sec
	else:
		_expires[key] = 0

func has_key(key: String) -> bool:
	_ensure_store()
	if _store == null:
		return false
	if _is_expired(key):
		erase(key)
		return false
	var rows = _store.query("SELECT 1 FROM kv WHERE key = $1", [key])
	return not rows.is_empty()

func erase(key: String) -> void:
	_ensure_store()
	if _store == null:
		return
	_store.execute("DELETE FROM kv WHERE key = $1", [key])
	_expires.erase(key)

func all_keys() -> Array:
	_ensure_store()
	if _store == null:
		return []
	var rows = _store.query("SELECT key FROM kv", [])
	var keys: Array = []
	for row in rows:
		var k = row.get("key", "")
		if k != "" and not _is_expired(k):
			keys.append(k)
	return keys

func set_batch(entries: Dictionary) -> void:
	_ensure_store()
	if _store == null:
		return
	for key in entries.keys():
		var value = entries[key]
		if value is Dictionary and not value.is_empty():
			set_value(key, value)
		else:
			erase(key)

func get_many(keys: Array) -> Dictionary:
	_ensure_store()
	if _store == null:
		return {}
	var result: Dictionary = {}
	for key in keys:
		result[key] = get_value(key)
	return result

func erase_batch(keys: Array) -> void:
	_ensure_store()
	if _store == null:
		return
	for key in keys:
		erase(key)

func sweep_expired() -> int:
	var now := Time.get_unix_time_from_system()
	var removed := 0
	for key in _expires.keys():
		var exp: float = _expires[key]
		if exp > 0 and now >= exp:
			erase(key)
			removed += 1
	return removed