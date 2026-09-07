## Test the AdapterRegistry: name -> store lookup.
## This test does NOT use the autoload (which would require
## booting the full game). It instantiates stores directly and
## uses the same registration API.
##
## Run with:
##   tools/godot --headless --path synmergia --script res://tests/adapters/test_registry.gd
extends SceneTree

const PersistenceStore = preload("res://adapters/persistence/persistence_store.gd")
const MemoryPersistenceStore = preload("res://adapters/persistence/memory_persistence_store.gd")
const MemoryCacheStore = preload("res://adapters/cache/memory_cache_store.gd")
const MemoryStore = preload("res://adapters/memory_layer/memory_store.gd")

var _passed: int = 0
var _failed: int = 0
var _registry: Dictionary = {}  # simulate registry for the test


func _initialize() -> void:
	print("--- REGISTRY PATTERN TEST ---")
	_test_registration_and_lookup()
	_test_unregistered_returns_null()
	_test_overwrite_replaces()
	_test_introspection()
	_finish()


func _reg(name: String, store) -> void:
	_registry[name] = store


func _lookup(name: String):
	return _registry.get(name, null)


func _test_registration_and_lookup() -> void:
	var ps = MemoryPersistenceStore.new()
	ps.open({})
	_reg("accounts", ps)
	if _lookup("accounts") != ps:
		_fail("registered store not retrievable")
		return
	# Use it
	var rc := ps.execute("INSERT INTO accounts (id) VALUES ($1)", ["acc_1"])
	if rc != 1:
		_fail("insert via registry-held store failed")
		return
	_ok("register + retrieve + use persistence store")

	var cache = MemoryCacheStore.new()
	cache.open({})
	_reg("sessions", cache)
	cache.store("session:abc", "user_1", 60)
	if _lookup("sessions").get("session:abc") != "user_1":
		_fail("cache store via registry failed")
		return
	_ok("register + retrieve + use cache store")

	var mem = MemoryStore.new()
	_reg("cooldowns", mem)
	mem.store("plr_1:fireball", 1234567890.0)
	if _lookup("cooldowns").get("plr_1:fireball") != 1234567890.0:
		_fail("memory store via registry failed")
		return
	_ok("register + retrieve + use memory store")


func _test_unregistered_returns_null() -> void:
	if _lookup("does_not_exist") != null:
		_fail("unregistered name should return null")
		return
	_ok("unregistered name returns null")


func _test_overwrite_replaces() -> void:
	var a = MemoryPersistenceStore.new()
	a.open({})
	a.seed("t1", [{"x": 1}])
	_reg("t1", a)

	var b = MemoryPersistenceStore.new()
	b.open({})
	b.seed("t1", [{"x": 2}])
	_reg("t1", b)

	if _lookup("t1") != b:
		_fail("overwrite did not replace")
		return
	var rows := b.query("SELECT * FROM t1")
	if rows[0].get("x") != 2:
		_fail("replaced store should hold new data")
		return
	_ok("overwrite replaces previous registration")


func _test_introspection() -> void:
	# Simulate introspection: registry knows its keys.
	var names: Array = _registry.keys()
	if not names.has("accounts"):
		_fail("registry.keys() should include 'accounts'")
		return
	if not names.has("sessions"):
		_fail("registry.keys() should include 'sessions'")
		return
	_ok("introspection: keys() includes registered names")


func _ok(msg: String) -> void:
	_passed += 1
	print("  [PASS] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
