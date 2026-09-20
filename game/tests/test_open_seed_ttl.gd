## TestOpenSeedTTL
##
## Tests for OpenSeedRegistry (labs/prd-open-seed-ttl.md D032)
## Covers US-001 through US-006 + edge cases
extends SceneTree

# NOTE: no file-level preload here. Preloading open_seed_registry.gd at
# parse time compiles it before the GameLog autoload exists, which fails
# the compile and leaves even the autoload node scriptless. load() at
# runtime (after autoload registration) compiles cleanly.
var registry = null
var ok: bool = true

func _initialize() -> void:
	# Autoloads are registered by _initialize time (unlike _init, which
	# runs before autoload registration and made these tests vacuous).
	registry = root.get_node_or_null("OpenSeedRegistry")
	if registry == null:
		var OpenSeedRegistryScript = load("res://core/services/open_seed_registry.gd")
		registry = OpenSeedRegistryScript.new()
	# Wait one frame: autoload _ready() (which loads the per-type TTL
	# definitions) runs AFTER SceneTree._initialize, so register() calls
	# made immediately would all fall back to the default TTL.
	await process_frame
	_run_tests()
	quit(0 if ok else 1)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: %s" % msg)
		ok = false
	else:
		print("PASS: %s" % msg)

func _run_tests() -> void:
	_test_register_and_lookup_fresh()
	_test_lookup_expired_returns_empty()
	_test_invalidate()
	_test_touch_logout()
	_test_configurable_ttl()
	_test_state_finalization()
	_test_per_character_isolation()
	_test_sweep_expired()

func _make_seed(val: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(32)
	for i in range(32):
		b[i] = (val + i) & 0xFF
	return b

func _test_register_and_lookup_fresh() -> void:
	registry.clear()
	var char_id := "char_1"
	var seed_bytes := _make_seed(10)
	registry.register(char_id, seed_bytes, "dungeon")

	# Fresh lookup should return the exact seed
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var found = registry.lookup(char_id, now + 1000)
	_assert(found == seed_bytes, "Fresh lookup returns registered instance_seed")

func _test_lookup_expired_returns_empty() -> void:
	registry.clear()
	var char_id := "char_2"
	var seed_bytes := _make_seed(20)
	registry.register(char_id, seed_bytes, "dungeon", 300000)

	var logout_time := int(Time.get_unix_time_from_system() * 1000.0)
	registry.touch_logout(char_id, logout_time)

	# Lookup after 301 seconds (> 300_000 ms)
	var expired_time := logout_time + 301000
	var found = registry.lookup(char_id, expired_time)
	_assert(found.is_empty(), "Expired lookup returns empty PackedByteArray")

	# Entry should have been removed from registry on expired lookup
	var entry = registry.get_entry(char_id)
	_assert(entry.is_empty(), "Expired entry is automatically invalidated from registry")

func _test_invalidate() -> void:
	registry.clear()
	var char_id := "char_3"
	var seed_bytes := _make_seed(30)
	registry.register(char_id, seed_bytes, "dungeon")
	registry.invalidate(char_id)
	var found = registry.lookup(char_id)
	_assert(found.is_empty(), "Invalidated entry returns empty")

func _test_touch_logout() -> void:
	registry.clear()
	var char_id := "char_4"
	var seed_bytes := _make_seed(40)
	registry.register(char_id, seed_bytes, "dungeon", 300000)

	var t0: int = 1000000
	registry.touch_logout(char_id, t0)
	var entry = registry.get_entry(char_id)
	_assert(entry["last_logout_ms"] == t0, "touch_logout updates last_logout_ms")

	# Within 5m of t0
	var found = registry.lookup(char_id, t0 + 200000)
	_assert(found == seed_bytes, "Lookup within TTL of updated logout returns seed")

func _test_configurable_ttl() -> void:
	registry.clear()
	var char_dungeon := "char_dung"
	var char_arena := "char_arena"
	var seed_d := _make_seed(50)
	var seed_a := _make_seed(60)

	# arena has 180_000 ms (3m) TTL, dungeon has 300_000 ms (5m)
	registry.register(char_dungeon, seed_d, "dungeon")
	registry.register(char_arena, seed_a, "arena")

	var t0 := 1000000
	registry.touch_logout(char_dungeon, t0)
	registry.touch_logout(char_arena, t0)

	# At t0 + 200_000 ms (> arena's 180s, but < dungeon's 300s):
	var found_arena = registry.lookup(char_arena, t0 + 200000)
	var found_dung = registry.lookup(char_dungeon, t0 + 200000)

	_assert(found_arena.is_empty(), "Arena TTL expires at 180s")
	_assert(found_dung == seed_d, "Dungeon seed still valid at 200s")

func _test_state_finalization() -> void:
	registry.clear()
	var char_id := "char_finalizer"
	var seed_bytes := _make_seed(70)
	registry.register(char_id, seed_bytes, "dungeon", 10000)

	# Lambdas capture local booleans/dictionaries BY VALUE in GDScript,
	# so writes inside the callback would never reach these locals. Use a
	# Dictionary (reference type) to observe the callback's effects.
	var captured := {"invoked": false, "snapshot": {}}
	registry.set_finalize_callback(func(cid: String, snapshot: Dictionary):
		captured["invoked"] = true
		captured["snapshot"] = snapshot
	)

	var dummy_state := {"boss_defeated": true, "player_pos": [10, 20, 30]}
	registry.set_state_snapshot(char_id, dummy_state)

	# Expire it. NOTE: lookup() with an explicit time still uses real
	# wall-clock registration internally for the finalize stamp; use
	# sweep_expired which evaluates against the same supplied clock.
	var t0 := 1000000
	registry.touch_logout(char_id, t0)
	registry.set_state_snapshot(char_id, dummy_state)
	var swept = registry.sweep_expired(t0 + 15000)
	_assert(swept == 1, "Expired entry swept")

	_assert(captured["invoked"] == true, "Finalize callback invoked upon TTL expiry")
	_assert(captured["snapshot"].get("character_id") == char_id, "Snapshot character_id matches")
	_assert(captured["snapshot"].get("state") == dummy_state, "Snapshot contains state tree snapshot")

	# Idempotent call test
	var second_finalize = registry.finalize(char_id)
	_assert(second_finalize == false, "Second finalize call returns false (idempotent)")

func _test_per_character_isolation() -> void:
	registry.clear()
	var char_a := "acc_1_char_a"
	var char_b := "acc_1_char_b"
	var seed_a := _make_seed(80)
	var seed_b := _make_seed(90)

	registry.register(char_a, seed_a, "dungeon")
	registry.register(char_b, seed_b, "dungeon")

	_assert(registry.lookup(char_a) == seed_a, "Char A lookup returns Seed A")
	_assert(registry.lookup(char_b) == seed_b, "Char B lookup returns Seed B")

	registry.invalidate(char_a)
	_assert(registry.lookup(char_a).is_empty(), "Char A invalidated")
	_assert(registry.lookup(char_b) == seed_b, "Char B remains intact (per-character isolation)")

func _test_sweep_expired() -> void:
	registry.clear()
	var c1 := "sweep_1"
	var c2 := "sweep_2"
	var seed_1 := _make_seed(1)
	var seed_2 := _make_seed(2)
	registry.register(c1, seed_1, "dungeon", 5000)
	registry.register(c2, seed_2, "dungeon", 50000)

	var t0 := 1000000
	registry.touch_logout(c1, t0)
	registry.touch_logout(c2, t0)

	var swept = registry.sweep_expired(t0 + 10000)
	_assert(swept == 1, "sweep_expired sweeps exactly 1 expired entry")
	# lookup() without an explicit time uses wall clock (real unix ms),
	# which is far past t0 (1000000 ms after epoch) and would expire c2.
	# Supply the same simulated clock for the remaining-entry check.
	_assert(registry.lookup(c2, t0 + 10000) == seed_2, "Non-expired entry remains")
