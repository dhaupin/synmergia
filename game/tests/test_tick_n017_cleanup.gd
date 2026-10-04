## test_tick_n017_cleanup.gd - TickService N017 boot policy: orphan
## per-tick root keys from previous sessions are removed on cleanup;
## live pointers and lookalike keys survive.
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_tick_n017_cleanup.gd
##
## Exit 0 = all pass.
extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	quit(0 if _fail == 0 else 1)

func _run() -> void:
	var tick = root.get_node_or_null("TickService")
	var ar = root.get_node_or_null("AdapterRegistry")
	_assert(tick != null, "TickService present")
	_assert(ar != null, "AdapterRegistry present")
	if tick == null or ar == null:
		return _finish()

	# Freeze the live tick loop: Phase 5 writes tick:N:root keys every
	# tick and would race the seeded-orphan assertions below.
	if tick._tick_timer != null:
		tick._tick_timer.stop()

	var store = ar.get_persistence("world_state")
	_assert(store != null, "world_state persistence store present")
	if store == null:
		return _finish()

	# Seed orphans exactly as a previous session would have left them.
	store.set_kv("tick:0:root", {"root_hash": "aa", "tick": 0})
	store.set_kv("tick:7:root", {"root_hash": "bb", "tick": 7})
	store.set_kv("tick:999999:root", {"root_hash": "cc", "tick": 999999})
	# A lookalike that must survive (tick:-prefixed, but not a root key).
	store.set_kv("tick:cache:root_x", "keep me")
	# Live pointers must survive.
	store.set_kv("world_state:latest_tick", 7)
	store.set_kv("world_state:latest_root", "bb")

	tick._cleanup_orphan_root_keys()

	_assert(typeof(store.get_kv("tick:0:root")) == TYPE_NIL, "orphan tick:0:root removed")
	_assert(typeof(store.get_kv("tick:7:root")) == TYPE_NIL, "orphan tick:7:root removed")
	_assert(typeof(store.get_kv("tick:999999:root")) == TYPE_NIL, "orphan tick:999999:root removed")
	_assert(typeof(store.get_kv("tick:cache:root_x")) != TYPE_NIL, "lookalike non-root key survives")
	_assert(typeof(store.get_kv("world_state:latest_tick")) != TYPE_NIL, "live latest_tick pointer survives")
	_assert(typeof(store.get_kv("world_state:latest_root")) != TYPE_NIL, "live latest_root pointer survives")

	_finish()

func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)

func _finish() -> void:
	print("N017Cleanup: %d passed, %d failed" % [_pass, _fail])
