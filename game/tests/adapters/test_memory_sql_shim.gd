## Regression test: MemoryPersistenceStore SQL shim + DictStore decode.
## Converted from the round-23 audit probe. Pins the defects fixed there:
##   1. Operator scan must match the EARLIEST operator and must not match
##      "=" inside ">=" / "<=" / "!=".
##   2. Both IN spellings parse ("IN (" and "IN("), with parameter lists.
##   3. ORDER BY / GROUP BY / LIMIT parse without a WHERE clause.
##   4. DictStore.get_many decodes values identically to get_value
##      (plain strings must survive, not decode to null).
## Run with:
##   sh ./scripts/godot_test_runner.sh adapters/test_memory_sql_shim
extends SceneTree

const MemoryPersistenceStore = preload("res://adapters/persistence/memory_persistence_store.gd")

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	print("--- MEMORY SQL SHIM TEST ---")

	var store = MemoryPersistenceStore.new()
	var rc := store.open({})
	if rc != 0:
		_fail("connect returned %d" % rc)
		_finish()
		return

	store.execute("CREATE TABLE accounts (id TEXT, name TEXT, level INT)")
	store.execute("INSERT INTO accounts (id, name, level) VALUES ($1, $2, $3)", ["acc_1", "alice", 5])
	store.execute("INSERT INTO accounts (id, name, level) VALUES ($1, $2, $3)", ["acc_2", "bob", 12])
	store.execute("INSERT INTO accounts (id, name, level) VALUES ($1, $2, $3)", ["acc_3", "carol", 30])
	var rows: Array = store.query("SELECT * FROM accounts")
	_ok("seed 3 rows", rows.size() == 3, "(got %d)" % rows.size())

	# Operator scan: earliest match wins; compound ops never degrade to "=".
	rows = store.query("SELECT * FROM accounts WHERE id = $1", ["acc_2"])
	_ok("WHERE =", rows.size() == 1 and rows[0].get("name") == "bob")
	rows = store.query("SELECT * FROM accounts WHERE level > $1", [5])
	_ok("WHERE >", rows.size() == 2)
	rows = store.query("SELECT * FROM accounts WHERE level >= $1", [5])
	_ok("WHERE >= (no '= inside >=')", rows.size() == 3)
	rows = store.query("SELECT * FROM accounts WHERE level < $1", [30])
	_ok("WHERE <", rows.size() == 2)
	rows = store.query("SELECT * FROM accounts WHERE level <= $1", [12])
	_ok("WHERE <= (no '= inside <=')", rows.size() == 2)
	rows = store.query("SELECT * FROM accounts WHERE id != $1", ["acc_1"])
	_ok("WHERE != (no '= inside !=')", rows.size() == 2)

	# AND chains both conditions.
	rows = store.query("SELECT * FROM accounts WHERE level > $1 AND id != $2", [5, "acc_3"])
	_ok("WHERE AND", rows.size() == 1 and rows[0].get("name") == "bob")

	# IN: both spellings, params and literals.
	rows = store.query("SELECT * FROM accounts WHERE id IN ($1, $2)", ["acc_1", "acc_3"])
	_ok("WHERE IN params", rows.size() == 2, "(got %d)" % rows.size())
	rows = store.query("SELECT * FROM accounts WHERE id IN('acc_1', 'acc_3')", [])
	_ok("WHERE IN( literals", rows.size() == 2)
	rows = store.query("SELECT * FROM accounts WHERE id IN ('acc_1', 'acc_3')", [])
	_ok("WHERE IN ( literals", rows.size() == 2)

	# LIKE.
	rows = store.query("SELECT * FROM accounts WHERE name LIKE $1", ["%o%"])
	_ok("WHERE LIKE", rows.size() == 2)

	# ORDER BY: with and without WHERE.
	rows = store.query("SELECT * FROM accounts WHERE level > $1 ORDER BY level DESC", [0])
	_ok("ORDER BY DESC + WHERE", rows.size() == 3 and rows[0].get("name") == "carol")
	rows = store.query("SELECT * FROM accounts ORDER BY level ASC", [])
	_ok("ORDER BY no WHERE", rows.size() == 3 and rows[0].get("name") == "alice" and rows[2].get("name") == "carol")

	# LIMIT: with and without WHERE, combined with ORDER BY.
	rows = store.query("SELECT * FROM accounts LIMIT 2", [])
	_ok("LIMIT no WHERE", rows.size() == 2)
	rows = store.query("SELECT * FROM accounts WHERE level > $1 ORDER BY level ASC LIMIT 2", [0])
	_ok("WHERE + ORDER + LIMIT", rows.size() == 2 and rows[0].get("name") == "alice")

	# UPDATE / DELETE with parameterised WHERE.
	var rc2: int = store.execute("UPDATE accounts SET name = $1 WHERE id = $2", ["alicia", "acc_1"])
	rows = store.query("SELECT * FROM accounts WHERE id = $1", ["acc_1"])
	_ok("UPDATE SET+WHERE", rc2 == 1 and rows.size() == 1 and rows[0].get("name") == "alicia")
	rc2 = store.execute("DELETE FROM accounts WHERE id = $1", ["acc_3"])
	rows = store.query("SELECT * FROM accounts WHERE id = $1", ["acc_3"])
	_ok("DELETE WHERE", rc2 == 1 and rows.is_empty())

	# KV round-trips (DictStore rests on these).
	store.set_value("k_dict", {"hp": 10, "name": "sword"})
	store.set_value("k_str", "hello")
	store.set_value("k_int", 7)
	store.set_value("k_bool", true)
	_ok("kv dict round-trip", store.get_value("k_dict") is Dictionary and store.get_value("k_dict").get("hp") == 10)
	_ok("kv str round-trip", store.get_value("k_str") == "hello")
	_ok("kv int round-trip", store.get_value("k_int") == 7)
	_ok("kv bool round-trip", store.get_value("k_bool") == true)

	# DictStore.get_many decode contract (must match get_value).
	var ds = MemoryPersistenceStore.new()
	ds.open({})
	ds.set_value("d_dict", {"hp": 10})
	ds.set_value("d_str", "hello")
	ds.set_value("d_int", 7)
	var many: Dictionary = ds.get_many(["d_dict", "d_str", "d_int"])
	_ok("get_many dict", many.get("d_dict") is Dictionary and many.get("d_dict").get("hp") == 10, "(got %s)" % str(many.get("d_dict")))
	_ok("get_many str (no double-decode)", many.get("d_str") == "hello", "(got %s)" % str(many.get("d_str")))
	_ok("get_many int", many.get("d_int") == 7)
	_ok("get_many==get_value str", ds.get_value("d_str") == many.get("d_str"))

	_finish()


func _finish() -> void:
	print("--- MEMORY SQL SHIM: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  PASS: %s %s" % [label, detail])
	else:
		_failed += 1
		print("  FAIL: %s %s" % [label, detail])


func _fail(label: String) -> void:
	_failed += 1
	print("  FAIL: %s" % label)
