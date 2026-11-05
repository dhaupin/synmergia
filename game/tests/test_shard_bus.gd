## Shard bus receipt: the cross-shard transport seam (Phase 1 of
## labs/prd-shard-mesh.md).
##
## The coordinator's cross-shard events used to fan out into a
## process-local array -- no other shard could ever see them. This
## receipt proves the transport seam: a swappable ShardBus behind a
## registry, the in-process round-trip, and a real cross-instance
## delivery through the coordinator's own emit/get_pending_events path.
##
## Legs:
##   1. The registry seeds MemoryShardBus as the default bus.
##   2. THE SWAP LAW: re-registering an id replaces the bus and
##      make_default re-points the board.
##   3. Memory round-trip: A publishes, B (a different self id) drains it;
##      A does NOT receive its own fan-out (the no-echo law).
##   4. Coordinator cross-instance: an event emitted on one coordinator
##      instance arrives in a SECOND instance's get_pending_events.
##   5. Env fallback: SHARD_BUS_BACKEND=redis with no reachable bridge
##      falls back to the memory bus (dev/CI unchanged).
##   6. The redis bus fails honestly (non-zero open, unhealthy) when the
##      bridge is unreachable.
##
## Run with:
##   godot --headless --path game/ --script res://tests/test_shard_bus.gd
extends SceneTree

var _passed: int = 0
var _failed: int = 0

const BUS_PATH := "res://core/mesh/shard_bus.gd"
const MEMORY_BUS_PATH := "res://core/mesh/memory_shard_bus.gd"
const REDIS_BUS_PATH := "res://core/mesh/redis_shard_bus.gd"
const REGISTRY_PATH := "res://core/mesh/shard_bus_registry.gd"
const COORDINATOR_PATH := "res://core/services/coordinator_service.gd"


func _initialize() -> void:
	print("--- SHARD BUS ---")
	await process_frame
	_test_registry_default()
	_test_swap_law()
	await _test_memory_round_trip()
	await _test_coordinator_cross_instance()
	await _test_env_fallback()
	_test_redis_honest_failure()
	_clear_env()
	_finish()


func _test_registry_default() -> void:
	var reg = load(REGISTRY_PATH).new()
	var bus = reg.get_default_bus()
	_assert(bus != null, "registry seeds a default bus")
	_assert(reg.get_default_bus_id() == "memory", "the default bus is the memory bus")
	_assert(bus.get_id() == "memory", "the memory bus reports id 'memory'")
	_assert(reg.list_buses().size() >= 1, "the board lists its buses")


func _test_swap_law() -> void:
	var reg = load(REGISTRY_PATH).new()
	var base = load(BUS_PATH).new()   # the unwired base, id "base"
	reg.register(base, false)
	_assert(reg.get_bus("base") == base, "register adds a bus by id")
	# Re-register a fresh base with make_default -> replaces + re-points.
	var base2 = load(BUS_PATH).new()
	reg.register(base2, true)
	_assert(reg.get_bus("base") == base2, "re-registering an id REPLACES the bus")
	_assert(reg.get_default_bus_id() == "base", "make_default re-points the board")


func _test_memory_round_trip() -> void:
	var a = load(MEMORY_BUS_PATH).new()
	a.open({})
	a.set_self_id("shard_a")
	a.subscribe("t")
	var b = load(MEMORY_BUS_PATH).new()
	b.open({})
	b.set_self_id("shard_b")
	b.subscribe("t")

	var delivered: int = a.publish("t", {"n": 1})
	_assert(delivered == 1, "publish reaches the one OTHER subscriber (not self)")
	var got: Array = b.poll("t")
	_assert(got.size() == 1 and got[0].get("n", 0) == 1, "the peer drains the published message")
	_assert(a.poll("t").is_empty(), "the publisher does NOT receive its own fan-out (no echo)")
	_assert(b.poll("t").is_empty(), "a drained inbox stays drained")


func _test_coordinator_cross_instance() -> void:
	var coord = root.get_node_or_null("CoordinatorService")
	if coord == null:
		_fail("CoordinatorService autoload missing")
		return

	# A second coordinator instance, sharing the process-wide memory store.
	var peer = load(COORDINATOR_PATH).new()
	root.add_child(peer)
	await process_frame
	await process_frame

	# Give the two instances distinct self ids on the shared bus.
	var a_bus = coord.bus()
	a_bus.unsubscribe(coord.BUS_TOPIC)
	a_bus.set_self_id("shard_alpha")
	a_bus.subscribe(coord.BUS_TOPIC)
	var b_bus = peer.bus()
	b_bus.unsubscribe(peer.BUS_TOPIC)
	b_bus.set_self_id("shard_beta")
	b_bus.subscribe(peer.BUS_TOPIC)

	coord.clear_processed_events()
	peer.clear_processed_events()

	coord.emit_cross_shard_event_auto("test_ping", "shard_alpha", {"k": 7})

	var remote: Array = peer.get_pending_events()
	var found := false
	for ev in remote:
		if ev.get("event_type", "") == "test_ping" and ev.get("payload", {}).get("k", 0) == 7:
			found = true
	_assert(found, "a second coordinator instance receives the emitted event")

	var local: Array = coord.get_pending_events()
	var local_found := false
	for ev in local:
		if ev.get("event_type", "") == "test_ping":
			local_found = true
	_assert(local_found, "the emitting coordinator keeps its own event (exactly once)")

	peer.queue_free()
	coord.clear_processed_events()


func _test_env_fallback() -> void:
	# Point at an unreachable bridge and force the redis bus; the bind must
	# fall back to the memory bus rather than fail the boot.
	OS.set_environment("SHARD_BUS_BACKEND", "redis")
	OS.set_environment("REDIS_BRIDGE_URL", "http://127.0.0.1:1")
	var coord = load(COORDINATOR_PATH).new()
	root.add_child(coord)
	await process_frame
	await process_frame
	_assert(coord.bus().get_id() == "memory", "unreachable redis bus falls back to memory")
	coord.queue_free()
	_clear_env()


func _test_redis_honest_failure() -> void:
	var rb = load(REDIS_BUS_PATH).new()
	var rc: int = rb.open({"bridge_url": "http://127.0.0.1:1"})
	_assert(rc != 0, "redis bus open() fails honestly with no bridge")
	_assert(not rb.healthy(), "a failed redis bus reports unhealthy")
	_assert(rb.poll("t").is_empty(), "a failed redis bus polls empty")


func _clear_env() -> void:
	OS.set_environment("SHARD_BUS_BACKEND", "")
	OS.set_environment("REDIS_BRIDGE_URL", "")


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
