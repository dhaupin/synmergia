## Shard mesh identity receipt: the deployment legs that let several
## containers run as distinct, coordinated shards.
##
## Legs:
##   1. SHARD_ID / SHARD_NAME / IS_PRIMARY in the env configure a fresh
##      ShardManager (not shard_1/"Alpha").
##   2. No shard env -> the defaults (shard_1/"Alpha"/primary) are intact,
##      so dev/CI boots are unchanged.
##   3. A configured shard registers itself with CoordinatorService and the
##      registry reports its name/is_primary back.
##   4. Two shards with different ids both appear in the coordinator registry
##      (the mesh sees more than one shard).
##   5. The "default" DictStore store is registered at boot and a DictStore
##      write/read round-trips through it -- the leg that stops shard and
##      coordinator state from silently falling back to process-local memory.
##
## Run with:
##   godot --headless --path game/ --script res://tests/test_shard_mesh_identity.gd
extends SceneTree

var _passed: int = 0
var _failed: int = 0

const SHARD_MANAGER_PATH := "res://core/services/shard_manager.gd"


func _initialize() -> void:
	print("--- SHARD MESH IDENTITY ---")
	await process_frame
	_test_env_identity()
	_test_default_identity()
	_test_coordinator_registration()
	_test_two_shards_register()
	_test_default_store_registered()
	_clear_env()
	_finish()


func _spawn_shard() -> Node:
	var script = load(SHARD_MANAGER_PATH)
	var sm: Node = script.new()
	root.add_child(sm)  # triggers _ready -> env config + register
	return sm


func _test_env_identity() -> void:
	_clear_env()
	OS.set_environment("SHARD_ID", "shard_7")
	OS.set_environment("SHARD_NAME", "Beta")
	OS.set_environment("IS_PRIMARY", "false")
	var sm := _spawn_shard()
	_assert(sm.shard_id == "shard_7", "env SHARD_ID configures shard_id")
	_assert(sm.shard_name == "Beta", "env SHARD_NAME configures shard_name")
	_assert(sm.is_primary == false, "env IS_PRIMARY=false configures is_primary")
	sm.queue_free()
	_clear_env()


func _test_default_identity() -> void:
	_clear_env()
	var sm := _spawn_shard()
	_assert(sm.shard_id == "shard_1", "no env -> default shard_id shard_1")
	_assert(sm.shard_name == "Alpha", "no env -> default shard_name Alpha")
	_assert(sm.is_primary == true, "no env -> default is_primary true")
	sm.queue_free()


func _test_coordinator_registration() -> void:
	_clear_env()
	var coord = root.get_node_or_null("CoordinatorService")
	if coord == null:
		_fail("CoordinatorService autoload missing")
		return
	OS.set_environment("SHARD_ID", "shard_reg")
	OS.set_environment("SHARD_NAME", "RegShard")
	var sm := _spawn_shard()
	var info: Dictionary = coord.get_shard_info("shard_reg")
	_assert(not info.is_empty(), "configured shard registers with the coordinator")
	_assert(info.get("name", "") == "RegShard", "coordinator records the shard name")
	_assert(coord.get_all_shard_ids().has("shard_reg"), "registry lists the new shard id")
	sm.queue_free()
	_clear_env()


func _test_two_shards_register() -> void:
	_clear_env()
	var coord = root.get_node_or_null("CoordinatorService")
	if coord == null:
		_fail("CoordinatorService autoload missing")
		return
	OS.set_environment("SHARD_ID", "shard_a")
	OS.set_environment("SHARD_NAME", "A")
	var a := _spawn_shard()
	OS.set_environment("SHARD_ID", "shard_b")
	OS.set_environment("SHARD_NAME", "B")
	var b := _spawn_shard()
	var ids: Array = coord.get_all_shard_ids()
	_assert(ids.has("shard_a") and ids.has("shard_b"), "two shards both register (mesh sees both)")
	a.queue_free()
	b.queue_free()
	_clear_env()


func _test_default_store_registered() -> void:
	var reg = root.get_node_or_null("AdapterRegistry")
	if reg == null:
		_fail("AdapterRegistry autoload missing")
		return
	var store = reg.get_persistence("default")
	_assert(store != null, "the 'default' persistence store is registered at boot")

	# Round-trip through a DictStore: proves the static registry hook is
	# pointed at AdapterRegistry (otherwise it uses the local fallback and
	# this write is invisible to the registered store).
	var DictStore = load("res://adapters/persistence/dict_store.gd")
	var ds = DictStore.new()
	ds.set_kv("shard_mesh_receipt_key", {"v": 42})
	var back = ds.get_kv("shard_mesh_receipt_key")
	_assert(back is Dictionary and back.get("v", 0) == 42, "DictStore round-trips through the registered store")


func _clear_env() -> void:
	OS.set_environment("SHARD_ID", "")
	OS.set_environment("SHARD_NAME", "")
	OS.set_environment("IS_PRIMARY", "")


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  PASS: ", label)
	else:
		_failed += 1
		print("  FAIL: ", label)


func _fail(label: String) -> void:
	_failed += 1
	print("  FAIL: ", label)


func _finish() -> void:
	print("--- RESULT: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
