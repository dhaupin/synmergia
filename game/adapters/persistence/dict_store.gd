extends RefCounted
class_name DictStore

const PersistenceStore = preload("res://adapters/persistence/persistence_store.gd")
const MemoryPersistenceStore = preload("res://adapters/persistence/memory_persistence_store.gd")

var _store: PersistenceStore = null
var _expires: Dictionary = {}  # key -> unix timestamp (0 = no expiry)

func _ensure_store() -> void:
	if _store != null:
		return
	var reg = null
	if get_tree():
		reg = get_tree().root.get_node_or_null("AdapterRegistry")
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

func get(key: String) -> Dictionary:
	_ensure_store()
	if _store == null:
		return {}
	if _is_expired(key):
		erase(key)
		return {}
	var rows = _store.query("SELECT value FROM kv WHERE key = $1", [key])
	if rows.is_empty():
		return {}
	var raw = rows[0].get("value", "")
	if raw == "":
		return {}
	var parsed = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}

func set(key: String, value: Dictionary, ttl_sec: int = 0) -> void:
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

func has(key: String) -> bool:
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
			set(key, value)
		else:
			erase(key)

func get_many(keys: Array) -> Dictionary:
	_ensure_store()
	if _store == null:
		return {}
	var result: Dictionary = {}
	for key in keys:
		result[key] = get(key)
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
