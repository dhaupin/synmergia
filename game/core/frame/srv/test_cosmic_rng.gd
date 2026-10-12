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
const PenroseScript = preload("res://core/frame/math/penrose.gd")

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
	_test_penrose_point_seam()
	_test_penrose_replay()
	_test_pentagrid_seam()
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

func _test_penrose_point_seam() -> void:
	var a = RngScript.new(true)
	var p := Vector2(0.3, 0.4)
	var r1: float = a.penrose_unit(p)
	var r2: float = a.penrose_unit(p)
	_check("penrose_unit deterministic at same point", r1 == r2)
	var q := Vector2(0.7, 0.2)
	_check("penrose_unit differs across windows", a.penrose_unit(q) != r1)
	var ri: int = a.penrose_randi(p, 1, 6)
	_check("penrose_randi in range", ri >= 1 and ri <= 6)
	var ri2: int = a.penrose_randi(p, 1, 6)
	_check("penrose_randi deterministic", ri == ri2)


func _test_penrose_replay() -> void:
	# Replay contract: (snapshot, window scope) alone reproduces rolls.
	var a = RngScript.new(true)
	a.stir("hand", 7)
	var snap: Dictionary = a.snapshot()
	var p := Vector2(0.45, 0.55)
	var roll_a: float = a.penrose_unit(p)
	var b = RngScript.new(true)
	b.restore(snap)
	var roll_b: float = b.penrose_unit(p)
	_check("penrose replay from snapshot matches", roll_a == roll_b)


func _test_pentagrid_seam() -> void:
	# Global tiling-space seam: any point on the whole plane resolves
	# to a stable rhombus scope; same point -> same roll, differing
	# points differ, foreign scopes stay distinct, replay holds.
	var a = RngScript.new(true)
	var p1 := Vector2(12.3, -7.7)
	var s1: String = a.pentagrid_scope(p1)
	_check("pentagrid scope is a global tile key", s1.begins_with("pentagrid."))
	_check("pentagrid scope deterministic", s1 == a.pentagrid_scope(p1))
	var r1: float = a.pentagrid_unit(p1)
	_check("pentagrid_unit deterministic at a point", r1 == a.pentagrid_unit(p1))
	var p2 := Vector2(-99.4, 55.1)
	var s2: String = a.pentagrid_scope(p2)
	_check("distant points scope to different rhombi", s1 != s2 and a.pentagrid_unit(p2) != r1)
	_check("pentagrid and penrose rivers stay separate", a.unit(s1) != 0.0 and s1 != PenroseScript.scope_for_point(p1))
	var ri: int = a.pentagrid_randi(p1, 1, 20)
	_check("pentagrid_randi deterministic and ranged", ri >= 1 and ri <= 20 and ri == a.pentagrid_randi(p1, 1, 20))
	# Replay: (snapshot, plane position) alone reproduces the roll.
	a.stir("hand", 99)
	var snap: Dictionary = a.snapshot()
	var roll_a: float = a.pentagrid_unit(p1)
	var b = RngScript.new(true)
	b.restore(snap)
	_check("pentagrid replay from snapshot matches", b.pentagrid_unit(p1) == roll_a)


func _check(label: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  PASS %s" % label)
	else:
		_failed += 1
		print("  FAIL %s" % label)
