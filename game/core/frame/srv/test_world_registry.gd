## Tests for WorldRegistry's pure statics (frame primitive, co-located).
##
## Focus: the derived Horizon math (cosmic age / observable radius) and
## the universe-seed decode. Orbits/windows are already covered by
## probe_world_lattice; this file LOCKS THE EPOCH ALIGNMENT that makes
## cosmic_age_s correct -- SignService.sky_epoch_days() is unix/86400, so
## cosmic_age_s(origin_unix, epoch_days) really is (unix_now - origin_unix).
## Audit round 19 added it precisely because that alignment is easy to
## misread as a mixed-epoch bug and "fix" into a regression.
extends SceneTree

const WR = preload("res://core/frame/srv/world_registry.gd")

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	_test_epoch_alignment()
	_test_negative_age_clamps()
	_test_observable_radius_grows_at_c()
	_test_universe_seed()
	print("WorldRegistry tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_epoch_alignment() -> void:
	# sky_epoch_days() = unix/86400, so epoch_days * 86400 = unix_now.
	var origin := 1_600_000_000.0
	var now_unix := 1_700_000_000.0
	var age: float = WR.cosmic_age_s(origin, now_unix / 86400.0)
	_assert(absf(age - (now_unix - origin)) < 1.0, "cosmic age is unix seconds since the origin")
	_assert(absf(age - 100_000_000.0) < 1.0, "cosmic age equals the elapsed unix seconds")


func _test_negative_age_clamps() -> void:
	_assert_eq(WR.cosmic_age_s(2_000_000_000.0, 1_000_000_000.0 / 86400.0), 0.0,
		"an origin in the future clamps age to 0")


func _test_observable_radius_grows_at_c() -> void:
	var c := 299_792_458.0
	var r1: float = WR.observable_radius_m(0.0, 1000.0, c)
	var r2: float = WR.observable_radius_m(0.0, 1001.0, c)
	_assert(absf((r2 - r1) - 86400.0 * c) < 1.0, "the horizon grows exactly one light-day per day")


func _test_universe_seed() -> void:
	var s1: PackedByteArray = WR.new().universe_seed()
	var s2: PackedByteArray = WR.new().universe_seed()
	_assert(s1.size() > 0, "the universe seed is non-empty")
	_assert_eq(s1.hex_encode(), WR.UNIVERSE_SEED_HEX, "the universe seed round-trips the hex constant")
	_assert(s1 == s2, "the universe seed is deterministic across instances")


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s (got %s, want %s)" % [label, str(actual), str(expected)])
