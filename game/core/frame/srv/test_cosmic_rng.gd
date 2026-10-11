## Tests for CosmicRng — the master RNG service (co-located per frame
## conventions).
##
## Covers: scoped stream determinism (same pool+scope -> same roll),
## scope isolation (different scopes differ), stirring changes output,
## cosmic flywheel integration, replay mode, unit/randi_in helpers,
## snapshot/restore round-trip, and the audit ring.
extends SceneTree

const RngScript = preload("res://core/frame/srv/cosmic_rng.gd")
const CosmicScript = preload("res://core/frame/srv/cosmic_entropy.gd")

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	_test_scoped_stream_deterministic()
	_test_scope_isolation()
	_test_stir_changes_output()
	_test_cosmic_integration()
	_test_replay_mode()
	_test_helpers()
	_test_snapshot_restore()
	_test_audit_ring()
	print("CosmicRng tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_scoped_stream_deterministic() -> void:
	var a = RngScript.new(true)
	var b = RngScript.new(true)
	var ra: float = a.stream_for("loot/daily_crate").randf()
	var rb: float = b.stream_for("loot/daily_crate").randf()
	_check("same pool + scope -> same roll", is_equal_approx(ra, rb))


func _test_scope_isolation() -> void:
	var a = RngScript.new(true)
	var loot: float = a.stream_for("loot/daily_crate").randf()
	var spawn: float = a.stream_for("spawn/wolf_42").randf()
	_check("different scopes -> different rolls", not is_equal_approx(loot, spawn))


func _test_stir_changes_output() -> void:
	var a = RngScript.new(true)
	var before: float = a.stream_for("loot/daily_crate").randf()
	a.stir("spark", 12345)
	var after: float = a.stream_for("loot/daily_crate").randf()
	_check("stirring the pool changes derived streams", not is_equal_approx(before, after))


func _test_cosmic_integration() -> void:
	var cosmic = CosmicScript.new()
	cosmic.feed_kp(5.67)
	var a = RngScript.new(true)
	a.stir_from_cosmic(cosmic)
	var b = RngScript.new(true)
	b.stir("kp", 5.67 * 100.0)
	b.stir("chaos", int(cosmic.total_chaos))
	var ra: float = a.stream_for("loot/daily_crate").randf()
	var rb: float = b.stream_for("loot/daily_crate").randf()
	_check("stir_from_cosmic mixes kp + total chaos", is_equal_approx(ra, rb))
	# A quiet sky vs a storm must yield different pools.
	var quiet = CosmicScript.new()
	quiet.feed_kp(0.33)
	var aq = RngScript.new(true)
	aq.stir_from_cosmic(quiet)
	_check("storm pool differs from calm pool", not is_equal_approx(
		a.stream_for("loot/daily_crate").randf(),
		aq.stream_for("loot/daily_crate").randf()))


func _test_replay_mode() -> void:
	# Replay: snapshot the pool, stir on, restore, same stream returns.
	var a = RngScript.new(true)
	a.stir("kp", 567.0)
	var snap: Dictionary = a.snapshot()
	var roll_before: float = a.stream_for("loot/daily_crate").randf()
	var b = RngScript.new(true)
	b.restore(snap)
	var roll_after: float = b.stream_for("loot/daily_crate").randf()
	_check("restore replays the exact stream", is_equal_approx(roll_before, roll_after))


func _test_helpers() -> void:
	var a = RngScript.new(true)
	var u1: float = a.unit("q1")
	var u2: float = a.unit("q1")
	var u3: float = a.unit("q2")
	_check("unit() in [0,1)", u1 >= 0.0 and u1 < 1.0)
	_check("unit() is scoped", not is_equal_approx(u1, u3))
	var i1: int = a.randi_in("dice", 1, 6)
	_check("randi_in() in range", i1 >= 1 and i1 <= 6)


func _test_snapshot_restore() -> void:
	var a = RngScript.new(true)
	a.stir("hand", 42)
	var snap: Dictionary = a.snapshot()
	var b = RngScript.new(true)
	b.restore(snap)
	_check("pool round-trips", b.snapshot()["pool"] == snap["pool"])
	_check("stir count round-trips", b.snapshot()["stir_count"] == snap["stir_count"])


func _test_audit_ring() -> void:
	var a = RngScript.new(true)
	for i in range(100):
		a.stir("hand", i)
	var tail: Array[Dictionary] = a.audit_tail(4)
	_check("audit ring bounded", tail.size() == 4)
	_check("audit tail is the most recent stirs", tail[3]["detail"] == 99)


func _check(label: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  PASS %s" % label)
	else:
		_failed += 1
		print("  FAIL %s" % label)
