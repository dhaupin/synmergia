## Tests for snapshot store
extends SceneTree

func _init() -> void:
	var ok = true
	if not _test_store_load():
		push_error("FAIL: store_load")
		ok = false
	if not _test_latest():
		push_error("FAIL: latest")
		ok = false
	if not _test_delete():
		push_error("FAIL: delete")
		ok = false
	if not _test_has():
		push_error("FAIL: has")
		ok = false
	if not _test_empty_hash():
		push_error("FAIL: empty_hash")
		ok = false
	if not _test_overwrite():
		push_error("FAIL: overwrite")
		ok = false
	quit(0 if ok else 1)

func _test_store_load() -> bool:
	var store = SnapshotStore.new()
	var root = PackedByteArray([1, 2, 3, 4])
	var state = {"entities": {"player_1": {"hp": 100}}}
	store.store_snapshot(root, state)
	var loaded = store.load_snapshot(root)
	assert(loaded.has("entities"))
	assert(loaded["entities"] has "player_1")
	return true

func _test_latest() -> bool:
	var store = SnapshotStore.new()
	var root1 = PackedByteArray([0xAA])
	var root2 = PackedByteArray([0xBB])
	store.store_snapshot(root1, {"v": 1})
	store.store_snapshot(root2, {"v": 2})
	var latest = store.latest_snapshot()
	assert(latest.size() == 1)
	assert(latest[0] == 0xBB)
	return true

func _test_delete() -> bool:
	var store = SnapshotStore.new()
	var root = PackedByteArray([0xCC])
	store.store_snapshot(root, {"x": 1})
	assert(store.has_snapshot(root) == true)
	assert(store.delete_snapshot(root) == true)
	assert(store.has_snapshot(root) == false)
	assert(store.delete_snapshot(root) == false)
	return true

func _test_has() -> bool:
	var store = SnapshotStore.new()
	var root = PackedByteArray([0xDD])
	assert(store.has_snapshot(root) == false)
	store.store_snapshot(root, {})
	assert(store.has_snapshot(root) == true)
	return true

func _test_empty_hash() -> bool:
	var store = SnapshotStore.new()
	var empty = PackedByteArray()
	store.store_snapshot(empty, {"empty": true})
	assert(store.has_snapshot(empty) == true)
	var loaded = store.load_snapshot(empty)
	assert(loaded["empty"] == true)
	return true

func _test_overwrite() -> bool:
	var store = SnapshotStore.new()
	var root = PackedByteArray([0xEE])
	store.store_snapshot(root, {"v": 1})
	store.store_snapshot(root, {"v": 2})
	var loaded = store.load_snapshot(root)
	assert(loaded["v"] == 2)
	assert(store.snapshot_count() == 1)
	return true
