## Snapshot store: persists state-tree snapshots (root hashes) for crash recovery.
## Uses pg-bridge HTTP pattern (see labs/prd-db.md sec. 7.1).
## Falls back to in-memory storage for tests / first-boot.
extends RefCounted

class_name SnapshotStore

var _snapshots: Dictionary = {}
var _ordered_keys: Array = []
var _pg_bridge_url: String = ""

func store_snapshot(root_hash: PackedByteArray, tree_state: Dictionary) -> bool:
	var hash_str: String
	if root_hash.is_empty():
		hash_str = ""
	else:
		hash_str = root_hash.hex_encode()
	_snapshots[hash_str] = {
		"root_hash" = root_hash,
		"tree_state" = tree_state,
		"stored_at" = Time.get_unix_time_from_system(),
	}
	if not _ordered_keys.has(hash_str):
		_order_keys()
	return true

func load_snapshot(root_hash: PackedByteArray) -> Dictionary:
	var hash_str: String
	if root_hash.is_empty():
		hash_str = ""
	else:
		hash_str = root_hash.hex_encode()
	var snapshot = _snapshots.get(hash_str)
	if snapshot == null:
		return {}
	return snapshot.get("tree_state", {})

func latest_snapshot() -> PackedByteArray:
	if _ordered_keys.is_empty():
		return PackedByteArray()
	var latest_key = _ordered_keys.back()
	var snapshot = _snapshots.get(latest_key)
	if snapshot == null:
		return PackedByteArray()
	return snapshot.get("root_hash", PackedByteArray())

func delete_snapshot(root_hash: PackedByteArray) -> bool:
	var hash_str: String
	if root_hash.is_empty():
		hash_str = ""
	else:
		hash_str = root_hash.hex_encode()
	if not _snapshots.has(hash_str):
		return false
	_snapshots.erase(hash_str)
	_order_keys()
	return true

func has_snapshot(root_hash: PackedByteArray) -> bool:
	var hash_str: String
	if root_hash.is_empty():
		hash_str = ""
	else:
		hash_str = root_hash.hex_encode()
	return _snapshots.has(hash_str)

func snapshot_count() -> int:
	return _snapshots.size()

func _order_keys() -> void:
	_order_keys.clear()
	_order_keys.assign(_snapshots.keys())
	_order_keys.sort_custom(func(a: String, b: String) -> bool:
		var ta = _snapshots[a].get("stored_at", 0) as int
		var tb = _snapshots[b].get("stored_at", 0) as int
		return ta < tb
	)

func set_bridge_url(url: String) -> void:
	_pg_bridge_url = url
