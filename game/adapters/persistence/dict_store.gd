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
	# Route through the KV batch API, not the SQL shim: the SQL path
	# depends on per-backend dialect support (parameterized WHERE on the
	# kv table), while set_many/get_many is the portable interface.
	var rows: Dictionary = _store.get_many([key])
	var raw = rows.get(key)
	if raw == null or str(raw) == "":
		return null
	var parsed = JSON.parse_string(str(raw))
	return parsed

func get_kv(key: String, default: Variant = null) -> Variant:
	var val = get_value(key)
	return val if val != null else default

func set_value(key: String, value: Variant, ttl_sec: int = 0) -> void:
	_ensure_store()
	if _store == null:
		return
	var json = JSON.stringify(value)
	# Use set_many for single key (still uses batch endpoint)
	var entries: Dictionary = {key: json}
	_store.set_many(entries)
	if ttl_sec > 0:
		_expires[key] = Time.get_unix_time_from_system() + ttl_sec
	else:
		_expires[key] = 0

func set_kv(key: String, value: Variant, ttl_sec: int = 0) -> void:
	set_value(key, value, ttl_sec)

func _set(property: StringName, value: Variant) -> bool:
	set_value(String(property), value)
	return true

func _get(property: StringName) -> Variant:
	return get_value(String(property))

func has_key(key: String) -> bool:
	_ensure_store()
	if _store == null:
		return false
	if _is_expired(key):
		erase(key)
		return false
	var rows: Dictionary = _store.get_many([key])
	return rows.get(key) != null

func has(key: String) -> bool:
	return has_key(key)

func erase(key: String) -> void:
	_ensure_store()
	if _store == null:
		return
	_store.delete_many([key])
	_expires.erase(key)

func delete(key: String) -> void:
	erase(key)

func size() -> int:
	return all_keys().size()

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
	# Serialize exactly like set_value so every backend receives JSON
	# strings and reads parse back uniformly.
	var encoded: Dictionary = {}
	for key in entries.keys():
		var value = entries[key]
		if value is Dictionary and not value.is_empty():
			encoded[key] = JSON.stringify(value)
			_expires[key] = 0
	if _store.has_method("set_many"):
		_store.set_many(encoded)
	else:
		for key in encoded.keys():
			set_value(key, JSON.parse_string(encoded[key]))
	# Empty or non-dictionary values erase the key (set_batch contract).
	for key in entries.keys():
		if not encoded.has(key):
			erase(key)


func get_many(keys: Array) -> Dictionary:
	_ensure_store()
	if _store == null:
		return {}
	var result: Dictionary = {}
	if _store.has_method("get_many"):
		var raw: Dictionary = _store.get_many(keys)
		for key in keys:
			var v = raw.get(key)
			result[key] = JSON.parse_string(str(v)) if v != null and str(v) != "" else null
	else:
		for key in keys:
			result[key] = get_value(key)
	return result


func erase_batch(keys: Array) -> void:
	_ensure_store()
	if _store == null:
		return
	# Use underlying store's delete_many if available
	if _store.has_method("delete_many"):
		_store.delete_many(keys)
	else:
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