## Test the in-memory persistence store. Covers the SQL
## subset the in-memory adapter supports and the round-trip
## behaviour services depend on.
##
## Run with:
##   tools/godot --headless --path synmergia --script res://tests/adapters/test_persistence_store.gd
extends SceneTree

const MemoryPersistenceStore = preload("res://adapters/persistence/memory_persistence_store.gd")

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	print("--- PERSISTENCE STORE TEST ---")

	var store = MemoryPersistenceStore.new()
	var rc := store.connect({})
	if rc != 0:
		_fail("connect returned %d" % rc)
		_finish()
		return
	_ok("connect returned 0")

	_test_insert_and_select(store)
	_test_select_with_where(store)
	_test_update(store)
	_test_delete(store)
	_test_transactions(store)
	_test_insert_many(store)
	_test_query_one(store)
	_test_healthy(store)

	_finish()


func _test_insert_and_select(store: MemoryPersistenceStore) -> void:
	store.reset()
	store.seed("accounts", [])
	var rc := store.execute(
		"INSERT INTO accounts (id, name) VALUES ($1, $2)",
		["acc_1", "alice"]
	)
	if rc != 1:
		_fail("insert returned %d" % rc)
		return
	_ok("INSERT inserts one row")

	var rows := store.query("SELECT * FROM accounts")
	if rows.size() != 1:
		_fail("expected 1 row, got %d" % rows.size())
		return
	if rows[0].get("id") != "acc_1" or rows[0].get("name") != "alice":
		_fail("row content wrong: %s" % str(rows[0]))
		return
	_ok("SELECT returns inserted row")


func _test_select_with_where(store: MemoryPersistenceStore) -> void:
	store.reset()
	store.seed("accounts", [
		{"id": "acc_1", "name": "alice"},
		{"id": "acc_2", "name": "bob"},
		{"id": "acc_3", "name": "carol"},
	])
	var rows := store.query(
		"SELECT * FROM accounts WHERE id = $1",
		["acc_2"]
	)
	if rows.size() != 1:
		_fail("expected 1 row, got %d" % rows.size())
		return
	if rows[0].get("name") != "bob":
		_fail("expected bob, got %s" % rows[0].get("name"))
		return
	_ok("SELECT WHERE returns matching row")

	var multi := store.query(
		"SELECT * FROM accounts WHERE name = $1 AND id = $2",
		["carol", "acc_3"]
	)
	if multi.size() != 1 or multi[0].get("id") != "acc_3":
		_fail("AND clause failed: %s" % str(multi))
		return
	_ok("SELECT WHERE col = $1 AND col2 = $2 works")


func _test_update(store: MemoryPersistenceStore) -> void:
	store.reset()
	store.seed("accounts", [
		{"id": "acc_1", "name": "alice", "level": 1},
		{"id": "acc_2", "name": "bob", "level": 1},
	])
	var rc := store.execute(
		"UPDATE accounts SET level = $1 WHERE id = $2",
		[5, "acc_1"]
	)
	if rc != 1:
		_fail("update returned %d (expected 1)" % rc)
		return
	_ok("UPDATE modifies one row")

	var row: Dictionary = store.query_one(
		"SELECT * FROM accounts WHERE id = $1",
		["acc_1"]
	)
	if row.get("level") != 5:
		_fail("expected level=5, got %s" % str(row))
		return
	_ok("UPDATE persisted through SELECT")


func _test_delete(store: MemoryPersistenceStore) -> void:
	store.reset()
	store.seed("accounts", [
		{"id": "acc_1", "name": "alice"},
		{"id": "acc_2", "name": "bob"},
	])
	var rc := store.execute(
		"DELETE FROM accounts WHERE id = $1",
		["acc_1"]
	)
	if rc != 1:
		_fail("delete returned %d (expected 1)" % rc)
		return
	_ok("DELETE removes one row")

	var rows := store.query("SELECT * FROM accounts")
	if rows.size() != 1 or rows[0].get("id") != "acc_2":
		_fail("after delete, expected only acc_2: %s" % str(rows))
		return
	_ok("DELETE removed row from table")


func _test_transactions(store: MemoryPersistenceStore) -> void:
	store.reset()
	store.seed("accounts", [{"id": "acc_1", "name": "alice"}])
	var tx := store.begin()
	if tx < 1:
		_fail("begin returned %d (expected positive)" % tx)
		return
	store.execute(
		"UPDATE accounts SET name = $1 WHERE id = $2",
		["changed", "acc_1"]
	)
	# Pre-commit check
	var pre: Dictionary = store.query_one("SELECT * FROM accounts WHERE id = $1", ["acc_1"])
	if pre.get("name") != "changed":
		_fail("update inside tx not visible: %s" % str(pre))
		return
	# Rollback
	var rrc := store.rollback(tx)
	if rrc != 0:
		_fail("rollback returned %d" % rrc)
		return
	var post: Dictionary = store.query_one("SELECT * FROM accounts WHERE id = $1", ["acc_1"])
	if post.get("name") != "alice":
		_fail("rollback did not revert: %s" % str(post))
		return
	_ok("tx + rollback reverts changes")

	# Commit
	var tx2 := store.begin()
	store.execute("UPDATE accounts SET name = $1 WHERE id = $2", ["committed", "acc_1"])
	if store.commit(tx2) != 0:
		_fail("commit returned non-zero")
		return
	var after: Dictionary = store.query_one("SELECT * FROM accounts WHERE id = $1", ["acc_1"])
	if after.get("name") != "committed":
		_fail("commit did not persist: %s" % str(after))
		return
	_ok("tx + commit persists changes")


func _test_insert_many(store: MemoryPersistenceStore) -> void:
	store.reset()
	store.seed("items", [])
	var rc := store.insert_many("items", [
		["itm_1", "sword"],
		["itm_2", "shield"],
		["itm_3", "potion"],
	], ["id", "name"])
	if rc != 3:
		_fail("insert_many returned %d" % rc)
		return
	_ok("insert_many inserts 3 rows")

	var rows := store.query("SELECT * FROM items")
	if rows.size() != 3:
		_fail("expected 3 rows, got %d" % rows.size())
		return
	var sword = rows[0]
	if sword.get("id") != "itm_1" or sword.get("name") != "sword":
		_fail("row content wrong: %s" % str(sword))
		return
	_ok("insert_many rows have correct column mapping")


func _test_query_one(store: MemoryPersistenceStore) -> void:
	store.reset()
	store.seed("accounts", [{"id": "acc_1", "name": "alice"}])

	var found: Dictionary = store.query_one(
		"SELECT * FROM accounts WHERE id = $1", ["acc_1"]
	)
	if found.is_empty() or found.get("name") != "alice":
		_fail("query_one returned wrong row: %s" % str(found))
		return
	_ok("query_one returns matching row")

	var missing: Dictionary = store.query_one(
		"SELECT * FROM accounts WHERE id = $1", ["acc_404"]
	)
	if not missing.is_empty():
		_fail("query_one on miss should be {}, got %s" % str(missing))
		return
	_ok("query_one on miss returns empty dict")


func _test_healthy(store: MemoryPersistenceStore) -> void:
	if not store.healthy():
		_fail("healthy() returned false on memory store")
		return
	_ok("memory store is healthy")


func _ok(msg: String) -> void:
	_passed += 1
	print("  [PASS] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
