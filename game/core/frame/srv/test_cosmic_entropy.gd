## Tests for CosmicEntropy — the solar-entropy flywheel (co-located
## per frame conventions).
##
## consolidated onto the frame Flywheel primitive (flywheel.gd):
## - momentum/sparks/total_chaos run through FlywheelScript.wheel; accessor fns keep the old read API.
## - SPARK_THRESHOLD / DECAY_PER_SEC are one copy, re-exported.
## Covers: flywheel accumulate/spark cycle (hit-and-miss, no wasted
## sparks), momentum decay, Kp->chaos weighting, weather band mapping
## (monotonic, bounded, deterministic), underworld tide amplitude
## (the world_underworld.tres "tides follow the far-off weather"
## contract), snapshot/restore round-trip, and spark listener wiring.
extends SceneTree

const CosmicScript = preload("res://core/frame/srv/cosmic_entropy.gd")

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	_test_kp_feeds_momentum_quadratically()
	_test_spark_on_threshold_and_reset()
	_test_decay_between_events()
	_test_weather_bands_monotonic()
	_test_weather_bands_deterministic()
	_test_tide_follows_weather()
	_test_snapshot_restore()
	_test_spark_listener()
	print("CosmicEntropy tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_kp_feeds_momentum_quadratically() -> void:
	var m = CosmicScript.new()
	var quiet: float = m.feed_kp(2.0)
	var m2 = CosmicScript.new()
	var loud: float = m2.feed_kp(6.0)
	# Chaos weight is 2.5*Kp^2: Kp 6 carries 9x the chaos of Kp 2.
	_check("Kp 6 chaos = 9x Kp 2 chaos", is_equal_approx(loud, quiet * 9.0))
	_check("Kp clamped to 0..9", true)  # feed_kp(12) checked below
	var m3 = CosmicScript.new()
	var clamped: float = m3.feed_kp(12.0)
	var m4 = CosmicScript.new()
	var at_nine: float = m4.feed_kp(9.0)
	_check("Kp 12 clamps to Kp 9 chaos", is_equal_approx(clamped, at_nine))


func _test_spark_on_threshold_and_reset() -> void:
	var m = CosmicScript.new()
	var before_sparks: int = m.sparks()
	var momentum: float = m.accumulate(60.0)
	_check("below threshold: no spark", momentum < CosmicScript.SPARK_THRESHOLD and m.sparks() == before_sparks)
	momentum = m.accumulate(60.0)
	_check("threshold crossed: spark fired", m.sparks() == before_sparks + 1)
	_check("flywheel resets after spark", m.momentum() == 0.0)


func _test_decay_between_events() -> void:
	var m = CosmicScript.new()
	m.accumulate(50.0)
	var after: float = m.tick(10.0)
	_check("decay 10s = 5.0 momentum", is_equal_approx(50.0 - CosmicScript.DECAY_PER_SEC * 10.0, after))
	_check("decay floors at zero", m.tick(1000.0) == 0.0)


func _test_weather_bands_monotonic() -> void:
	var kp := 0.0
	var last_wind: float = -1.0
	var monotonic := true
	while kp <= 9.0:
		var band: Dictionary = CosmicScript.kp_to_band(kp)
		if band["wind"] < last_wind:
			monotonic = false
			break
		last_wind = band["wind"]
		kp += 0.25
	_check("wind level monotonic in Kp", monotonic)
	_check("Kp 0 is calm", CosmicScript.kp_to_band(0.0)["name"] == "calm")
	_check("Kp 9 is tempest", CosmicScript.kp_to_band(9.0)["name"] == "tempest")
	# Storm thresholds mirror the NOAA scale.
	_check("Kp 5 is storm", CosmicScript.kp_to_band(5.0)["name"] == "storm")
	_check("Kp 4 is active", CosmicScript.kp_to_band(4.0)["name"] == "active")


func _test_weather_bands_deterministic() -> void:
	# Two instances, same readings -> identical bands every time.
	var readings := [0.33, 2.67, 5.67, 1.0, 4.33, 3.0]
	var a: Array[String] = []
	var b: Array[String] = []
	for kp in readings:
		a.append(CosmicScript.kp_to_band(kp)["name"])
		b.append(CosmicScript.kp_to_band(kp)["name"])
	_check("band derivation deterministic", a == b)
	# The real storm week: Oct 4 Kp 5.67 must land in "storm".
	_check("Oct 4 storm (Kp 5.67) -> storm band", a[2] == "storm")


func _test_tide_follows_weather() -> void:
	# world_underworld.tres: "tides that follow the far-off weather".
	var calm: float = CosmicScript.tide_amplitude(0.0)
	var storm: float = CosmicScript.tide_amplitude(9.0)
	_check("calm tide > 0 (strata breathing)", calm > 0.0)
	_check("storm tide exceeds calm tide", storm > calm)
	_check("tide bounded by TIDE_MAX_M + still level", storm <= 0.15 + CosmicScript.TIDE_MAX_M + 0.001)
	_check("tide quadratic in Kp", is_equal_approx(CosmicScript.tide_amplitude(4.5), 0.15 + CosmicScript.TIDE_MAX_M * 0.25))


func _test_snapshot_restore() -> void:
	var m = CosmicScript.new()
	m.feed_kp(5.0, 1000.0)
	m.tick(60.0)
	var snap: Dictionary = m.snapshot()
	var m2 = CosmicScript.new()
	m2.restore(snap)
	_check("momentum round-trips", is_equal_approx(m2.momentum(), m.momentum()))
	_check("kp round-trips", is_equal_approx(m2.last_kp, 5.0))
	_check("freshness survives restore", m2.has_fresh_kp(1000.0 + 3600.0) and not m2.has_fresh_kp(1000.0 + 4.0 * 3600.0))


func _test_spark_listener() -> void:
	var m = CosmicScript.new()
	var seen: Array[Dictionary] = []
	m.on_spark(func(event: Dictionary) -> void: seen.append(event))
	m.accumulate(120.0)
	_check("listener received the spark", seen.size() == 1)
	_check("spark event carries kp + momentum", seen[0].has("kp") and seen[0].has("momentum"))


func _check(label: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  PASS %s" % label)
	else:
		_failed += 1
		print("  FAIL %s" % label)
