extends RefCounted
class_name DictStore

const PersistenceStore = preload("res://adapters/persistence/persistence_store.gd")
const MemoryPersistenceStore = preload("res://adapters/persistence/memory_persistence_store.gd")

var _store: PersistenceStore = null

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

func get(key: String) -> Variant:
    _ensure_store()
    if _store == null:
        return null
    var rows = _store.query("SELECT value FROM kv WHERE key = $1", [key])
    if rows.is_empty():
        return null
    var raw = rows[0].get("value", "")
    if raw == "":
        return ""
    var parsed = JSON.parse(raw)
    if parsed.error != OK:
        return raw
    return parsed.result

func set(key: String, value: Variant) -> void:
    _ensure_store()
    if _store == null:
        return
    var json = JSON.stringify(value)
    _store.execute("DELETE FROM kv WHERE key = $1", [key])
    _store.execute("INSERT INTO kv (key, value) VALUES ($1, $2)", [key, json])

func has(key: String) -> bool:
    _ensure_store()
    if _store == null:
        return false
    var rows = _store.query("SELECT 1 FROM kv WHERE key = $1", [key])
    return not rows.is_empty()

func erase(key: String) -> void:
    _ensure_store()
    if _store == null:
        return
    _store.execute("DELETE FROM kv WHERE key = $1", [key])

func all_keys() -> Array:
    _ensure_store()
    if _store == null:
        return []
    var rows = _store.query("SELECT key FROM kv", [])
    var keys: Array = []
    for row in rows:
        var k = row.get("key", "")
        if k != "":
            keys.append(k)
    return keys
