extends RefCounted
class_name DictStore

const PersistenceStore = preload("res://adapters/persistence/persistence_store.gd")
const MemoryPersistenceStore = preload("res://adapters/persistence/memory_persistence_store.gd")

var _store: PersistenceStore = null
var _expires: Dictionary = {}
## Which registry persistence store this DictStore rides. "default"
## for the vast majority; services with reload-critical ledgers name
## their own durable store (RideService -> "durable_mounts", R48).
var _store_name: String = "default"

func _init(p_store_name: String = "default") -> void:
	_store_name = p_store_name

static var _adapter_registry = null
# Shared fallback backend: all DictStore instances must see the same KV
# data when no AdapterRegistry is available (tests / pre-boot). A
# per-instance fallback silently isolated every writer.
static var _shared_fallback: PersistenceStore = null

static func set_adapter_registry(reg) -> void:
	_adapter_registry = reg

func _ensure_store() -> void:
	if _store != null:
		return
	var reg = _adapter_registry
	if reg == null:
		# Fallback to shared memory store if registry not available yet
		if _shared_fallback == null:
			_shared_fallback = MemoryPersistenceStore.new()
			_shared_fallback.open({})
		_store = _shared_fallback
		return
	if reg and reg.has_method("get_persistence"):
		_store = reg.get_persistence(_store_name)
	if _store == null:
		if _shared_fallback == null:
			_shared_fallback = MemoryPersistenceStore.new()
			_shared_fallback.open({})
		_store = _shared_fallback
		if reg and reg.has_method("register_persistence"):
			reg.register_persistence(_store_name, _store)

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
	# Memory/Postgres decode JSON inside get_many and return null for
	# missing keys; raw/legacy stores may return a JSON string. Tolerate
	# both shapes without double-decoding native Variants.
	var rows: Dictionary = _store.get_many([key])
	var raw = rows.get(key)
	if raw == null or str(raw) == "":
		return null
	if raw is String:
		var parsed = JSON.parse_string(raw)
		return parsed if parsed != null else raw
	return raw

func get_kv(key: String, default: Variant = null) -> Variant:
	var val = get_value(key)
	return val if val != null else default

func set_value(key: String, value: Variant, ttl_sec: int = 0) -> void:
	_ensure_store()
	if _store == null:
		return
	# Store through the backend's own encode path: set_value/set_kv on
	# Memory and Postgres stores persist JSON strings natively.
	if _store.has_method("set_value"):
		_store.set_value(key, value)
	elif _store.has_method("set_many"):
		_store.set_many({key: value})
	else:
		push_warning("DictStore: backend has no KV write method; drop for " + key)
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
	return _store.has_key(key) if _store.has_method("has_key") else get_value(key) != null

func has(key: String) -> bool:
	return has_key(key)

func erase(key: String) -> void:
	_ensure_store()
	if _store == null:
		return
	if _store.has_method("erase"):
		_store.erase(key)
	elif _store.has_method("delete_many"):
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
	# Memory/Postgres backends expose all_keys(); raw stores fall back
	# to the SQL shim (kv table is schema-stable).
	var keys: Array = _store.all_keys() if _store.has_method("all_keys") else _keys_via_query()
	var result: Array = []
	for k in keys:
		if k != "" and not _is_expired(k):
			result.append(k)
	return result

func _keys_via_query() -> Array:
	var keys: Array = []
	var rows = _store.query("SELECT key FROM kv", [])
	for row in rows:
		var k = row.get("key", "")
		if k != "":
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
			# get_value's contract: only decode the JSON envelope. A plain
			# String value was stored AS a JSON string ("hello"), and
			# str()-then-parse here double-decoded it to null (round 23).
			if v == null or (v is String and v == ""):
				result[key] = null
			elif v is String:
				var parsed = JSON.parse_string(v)
				result[key] = parsed if parsed != null else v
			else:
				result[key] = v
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
