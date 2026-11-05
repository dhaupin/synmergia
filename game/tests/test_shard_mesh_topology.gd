## Shard mesh topology receipt: the deployment topology that turns the
## mesh from one process into a coordinator + N shard processes
## (Phase 3 of labs/prd-shard-mesh.md).
##
## Legs:
##   1. MeshRole resolves a container's role from the env: coordinator
##      (START_MODE=coordinator), shard (SHARD_ID, or prod/headless/server),
##      else standalone -- an unset/unknown combo falls back safely.
##   2. MeshRole.self_id() is the mesh identity: the coordinator id for a
##      coordinator, the shard id otherwise.
##   3. MeshRole.shard_id(): an explicit SHARD_ID wins; MESH_AUTOSHARD with
##      no SHARD_ID derives a unique id from HOSTNAME (docker --scale);
##      neither -> shard_1 (the dev default, unchanged).
##   4. THE CROSS-PROCESS REGISTRY: a shard announces on the mesh topic and
##      a SEPARATE coordinator instance ingests it -- the registry spans
##      processes, not just one container's memory.
##   5. A repeat announce is idempotent (one entry, refreshed).
##   6. A departure announce removes the shard from the registry.
##   7. The coordinator role does not announce itself as a shard (no-op).
##
## Run with:
##   godot --headless --path game/ --script res://tests/test_shard_mesh_topology.gd
extends SceneTree

var _passed: int = 0
var _failed: int = 0

const MESH_ROLE_PATH := "res://core/mesh/mesh_role.gd"
const COORDINATOR_PATH := "res://core/services/coordinator_service.gd"
const SHARD_MANAGER_PATH := "res://core/services/shard_manager.gd"


func _initialize() -> void:
	print("--- SHARD MESH TOPOLOGY ---")
	await process_frame
	_test_role_resolution()
	_test_self_id()
	_test_shard_id_autoshard()
	await _test_cross_process_registration()
	await _test_idempotent_reannounce()
	await _test_departure()
	await _test_coordinator_does_not_announce()
	_clear_env()
	_finish()


func _test_role_resolution() -> void:
	_clear_env()
	var role = load(MESH_ROLE_PATH)
	_assert(role.resolve() == "standalone", "no env -> standalone")
	OS.set_environment("START_MODE", "coordinator")
	_assert(role.resolve() == "coordinator", "START_MODE=coordinator -> coordinator")
	OS.set_environment("START_MODE", "headless")
	_assert(role.resolve() == "shard", "START_MODE=headless -> shard")
	OS.set_environment("START_MODE", "")
	OS.set_environment("SHARD_ID", "shard_9")
	_assert(role.resolve() == "shard", "SHARD_ID set -> shard")
	OS.set_environment("START_MODE", "bogus")
	_assert(role.resolve() == "shard", "unknown mode with SHARD_ID -> shard (safe)")
	OS.set_environment("SHARD_ID", "")
	_assert(role.resolve() == "standalone", "unknown mode with no id -> standalone (safe)")
	_clear_env()


func _test_self_id() -> void:
	_clear_env()
	var role = load(MESH_ROLE_PATH)
	OS.set_environment("START_MODE", "coordinator")
	_assert(role.self_id() == "coordinator", "coordinator self id is the coordinator id")
	OS.set_environment("START_MODE", "headless")
	OS.set_environment("SHARD_ID", "shard_42")
	_assert(role.self_id() == "shard_42", "shard self id is its shard id")
	_clear_env()


func _test_shard_id_autoshard() -> void:
	_clear_env()
	var role = load(MESH_ROLE_PATH)
	OS.set_environment("SHARD_ID", "pinned_1")
	_assert(role.shard_id() == "pinned_1", "explicit SHARD_ID wins")
	OS.set_environment("SHARD_ID", "")
	OS.set_environment("MESH_AUTOSHARD", "true")
	OS.set_environment("HOSTNAME", "Synmergia-Shard-3")
	_assert(role.shard_id() == "synmergia_shard_3", "autoshard derives a sanitized id from HOSTNAME")
	OS.set_environment("MESH_AUTOSHARD", "")
	_assert(role.shard_id() == "shard_1", "no SHARD_ID, no autoshard -> shard_1 (dev default)")
	_clear_env()


func _test_cross_process_registration() -> void:
	_clear_env()
	var coord = root.get_node_or_null("CoordinatorService")
	if coord == null:
		_fail("CoordinatorService autoload missing")
		return

	# A second instance stands in for a SEPARATE coordinator process; the
	# autoload stands in for the shard process. Distinct bus self ids on the
	# shared in-process store (the receipt's stand-in for a real cross-process
	# transport; RedisShardBus is the same contract over the bridge).
	var shard_side = load(COORDINATOR_PATH).new()
	root.add_child(shard_side)
	await process_frame
	await process_frame

	_set_bus_self_id(coord, "coordinator")
	_set_bus_self_id(shard_side, "shard_9")

	coord.clear_processed_events()

	shard_side.announce_self_to_mesh("shard_9", {"name": "Nine", "is_primary": false, "world_name": "Synmergia", "max_players": 5000})

	var ids: Array = coord.get_all_shard_ids()
	_assert(ids.has("shard_9"), "a separate coordinator ingests the announced shard")
	var info: Dictionary = coord.get_shard_info("shard_9")
	_assert(info.get("name", "") == "Nine", "the ingested shard carries its name")
	_assert(info.get("remote", false) == true, "the ingested entry is marked remote")

	shard_side.queue_free()


func _test_idempotent_reannounce() -> void:
	_clear_env()
	var coord = root.get_node_or_null("CoordinatorService")
	if coord == null:
		_fail("CoordinatorService autoload missing")
		return
	var shard_side = load(COORDINATOR_PATH).new()
	root.add_child(shard_side)
	await process_frame
	await process_frame
	_set_bus_self_id(coord, "coordinator")
	_set_bus_self_id(shard_side, "shard_dup")

	shard_side.announce_self_to_mesh("shard_dup", {"name": "One"})
	var _x: Array = coord.get_all_shard_ids()
	shard_side.announce_self_to_mesh("shard_dup", {"name": "One"})
	var ids: Array = coord.get_all_shard_ids()
	var count := 0
	for sid in ids:
		if sid == "shard_dup":
			count += 1
	_assert(count == 1, "a repeat announce is idempotent (one entry)")

	shard_side.queue_free()


func _test_departure() -> void:
	_clear_env()
	var coord = root.get_node_or_null("CoordinatorService")
	if coord == null:
		_fail("CoordinatorService autoload missing")
		return
	var shard_side = load(COORDINATOR_PATH).new()
	root.add_child(shard_side)
	await process_frame
	await process_frame
	_set_bus_self_id(coord, "coordinator")
	_set_bus_self_id(shard_side, "shard_bye")

	shard_side.announce_self_to_mesh("shard_bye", {"name": "Bye"})
	_assert(coord.get_all_shard_ids().has("shard_bye"), "the shard is registered before departure")
	shard_side.announce_unregister_to_mesh("shard_bye")
	_assert(not coord.get_all_shard_ids().has("shard_bye"), "the departure removes the shard from the registry")

	shard_side.queue_free()


func _test_coordinator_does_not_announce() -> void:
	_clear_env()
	# With START_MODE=coordinator, announce_self_to_mesh must be a no-op --
	# the coordinator is not a shard and never registers as one.
	OS.set_environment("START_MODE", "coordinator")
	var coord = root.get_node_or_null("CoordinatorService")
	if coord == null:
		_fail("CoordinatorService autoload missing")
		return
	var peer = load(COORDINATOR_PATH).new()
	root.add_child(peer)
	await process_frame
	await process_frame
	_set_bus_self_id(coord, "coordinator")
	_set_bus_self_id(peer, "coordinator_peer")

	coord.announce_self_to_mesh("coordinator", {"name": "Nope"})
	var ids: Array = peer.get_all_shard_ids()
	_assert(not ids.has("coordinator"), "the coordinator does not register as a shard")

	peer.queue_free()
	_clear_env()


func _set_bus_self_id(coord, id: String) -> void:
	var b = coord.bus()
	if b == null:
		return
	b.unsubscribe(coord.BUS_TOPIC)
	b.unsubscribe(coord.MESH_TOPIC)
	b.set_self_id(id)
	b.subscribe(coord.BUS_TOPIC)
	b.subscribe(coord.MESH_TOPIC)


func _clear_env() -> void:
	OS.set_environment("START_MODE", "")
	OS.set_environment("SHARD_ID", "")
	OS.set_environment("MESH_AUTOSHARD", "")
	OS.set_environment("HOSTNAME", "")


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
