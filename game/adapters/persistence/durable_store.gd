extends "res://adapters/persistence/memory_persistence_store.gd"
class_name MemoryPersistenceStoreDurable

# A MemoryPersistenceStore that SNAPSHOT-SERIALIZES itself to a
# user:// JSON file on every write and reloads that file on open.
#
# Why: the web export's default persistence backend is
# MemoryPersistenceStore -- pure in-process RAM. The wasm heap dies on
# a page reload, so every guest account, character, wallet, and mount
# the probe bought evaporated on F5 (the R48 reload leg failed with
# "no old character listed": the account blob itself was memory).
#
# user:// in a web build is Godot's IndexedDB mount: ConfigFile /
# FileAccess writes there survive reloads. The snapshot is small (the
# game's own state, JSON), so a full-file rewrite per write is cheap
# and keeps one serialization law (prd-db.md sec 3: memory and
# Postgres stores persist JSON strings natively -- so does this).
#
# Scope law: registered ONLY for the store names that must survive a
# browser reload ("accounts", "characters", "inventories",
# "equipment", "vaults", "player_settings", "sessions",
# "durable_mounts"). Heavy session stores (chat, loot, votes) stay on
# the plain memory backend. And snapshotting itself is web-only: on
# desktop/headless the wasm-heap death does not exist, and snapshots
# would make --script tests leak state across invocations.

var _snapshot_path: String = ""
## Snapshotting is WEB-ONLY law: the reload problem is the wasm heap
## dying, which only exists in the browser. Headless --script tests
## run in a shared user:// sandbox across invocations -- snapshots
## there would leak one run's ledger into the next (the R48 QC flake:
## probe_riding's purchase chain failed on a mount the PREVIOUS run
## had bought). Web: snapshots live; everywhere else: pure memory.
var _snapshots_enabled: bool = false

func open(config: Dictionary) -> int:
	_snapshots_enabled = OS.has_feature("web")
	var name := str(config.get("store_name", "default"))
	_snapshot_path = "user://durable/%s.json" % name
	DirAccess.make_dir_recursive_absolute("user://durable")
	_load_snapshot()
	return 0


func _load_snapshot() -> void:
	if not _snapshots_enabled:
		return
	var f := FileAccess.open(_snapshot_path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for table in parsed.keys():
			var rows = parsed[table]
			if rows is Array:
				_tables[table] = rows.duplicate(true)


func _save_snapshot() -> void:
	if not _snapshots_enabled:
		return
	var f := FileAccess.open(_snapshot_path, FileAccess.WRITE)
	if f == null:
		push_error("DurableStore: cannot write snapshot %s" % _snapshot_path)
		return
	f.store_string(JSON.stringify(_tables))


func execute(sql: String, params: Array = []) -> int:
	var rc := super.execute(sql, params)
	if rc >= 0:
		_save_snapshot()
	return rc


func set_many(entries: Dictionary) -> int:
	var rc := super.set_many(entries)
	if rc == 0:
		_save_snapshot()
	return rc


func delete_many(keys: Array) -> int:
	var rc := super.delete_many(keys)
	if rc >= 0:
		_save_snapshot()
	return rc


func insert_many(table: String, rows: Array, columns: Array) -> int:
	var rc := super.insert_many(table, rows, columns)
	if rc >= 0:
		_save_snapshot()
	return rc


func reset() -> void:
	super.reset()
	if _snapshot_path != "":
		_save_snapshot()
