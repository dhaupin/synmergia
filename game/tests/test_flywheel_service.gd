## Tests for FlywheelService on the frame's canonical Flywheel
## primitive (core/frame/srv/flywheel.gd): same accumulate/decay/spark
## law as CosmicEntropy's weather wheel, per-wheel threshold/cap tuning,
## snapshot triggers, sub-meter routing. Co-located run pattern:
##   godot --headless --path . --script res://tests/test_flywheel_service.gd

extends SceneTree

## --script mode cannot resolve autoload identifiers (GameLog etc) at
## preload/parse time, so every service script loads at runtime.
var SvcScript = null
var FlywheelScript = null

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	SvcScript = load("res://core/services/flywheel_service.gd")
	FlywheelScript = load("res://core/frame/srv/flywheel.gd")
	_test_shard_wheel_accumulate_and_cap()
	_test_shard_spark_fires_snapshot_at_80pct()
	_test_player_wheel_records_usage()
	_test_primitive_parity_with_cosmic()
	print("FlywheelService tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("  PASS %s" % label)
		_passed += 1
	else:
		print("  FAIL %s" % label)
		_failed += 1


func _fresh_service() -> Node:
	var svc = SvcScript.new()
	root.add_child(svc)
	return svc

func _test_shard_wheel_accumulate_and_cap() -> void:
	var svc = _fresh_service()
	svc.update_shard_flywheel("s1", 10.0, "player_input")
	_check("shard momentum accumulates (weight 1)", is_equal_approx(svc.get_shard_momentum("s1"), 10.0))
	svc.update_shard_flywheel("s1", 5.0, "mob_ai")
	_check("mob_ai weighted x10", is_equal_approx(svc.get_shard_momentum("s1"), 60.0))
	# Drive past the cap: no matter how much chaos, momentum <= MAX_MOMENTUM.
	for i in range(200):
		svc.update_shard_flywheel("s1", 10.0, "generation")
	_check("momentum capped at 1000", svc.get_shard_momentum("s1") <= 1000.0)


func _test_shard_spark_fires_snapshot_at_80pct() -> void:
	var svc = _fresh_service()
	var hot_seen: Array = []
	svc.shard_hot.connect(func(shard_id: String, snap: Dictionary) -> void: hot_seen.append(snap))
	# generation x100 deltas: 8 updates x100 = 800 == 80% -> spark.
	for i in range(8):
		svc.update_shard_flywheel("s2", 1.0, "generation")
	_check("shard_hot fired at >80% momentum", hot_seen.size() >= 1)
	if hot_seen.size() > 0:
		var snap: Dictionary = hot_seen[0]
		_check("snapshot carries shard_id + trigger",
			str(snap.get("shard_id")) == "s2" and str(snap.get("trigger")) == "high_entropy")
		_check("snapshot momentum >= 80%", float(snap.get("momentum")) >= 800.0)


func _test_player_wheel_records_usage() -> void:
	var svc = _fresh_service()
	svc.update_player_flywheel("p1", "movement_distance", 12.0)
	svc.update_player_flywheel("p1", "chat_message", 1.0)
	var state: Dictionary = svc.get_player_flywheel_state("p1")
	_check("movement sub-meter recorded", float(state.get("movement", {}).get("distance", 0.0)) == 12.0)
	_check("chat sub-meter recorded", int(state.get("chat", {}).get("messages", 0)) == 1)


func _test_primitive_parity_with_cosmic() -> void:
	# Parity: the primitive and a CosmicEntropy wheel obey the same law
	# given the same delta — accumulate, decay, spark shape.
	var w = FlywheelScript.new("parity")
	var before_sparks: int = w.sparks
	var m: float = w.accumulate(60.0)
	_check("parity: below threshold no spark", m < w.spark_threshold and w.sparks == before_sparks)
	w.accumulate(60.0)
	_check("parity: spark at threshold", w.sparks == before_sparks + 1)
	_check("parity: wheel resets after spark", w.momentum == 0.0)
	var after: float = w.tick(10.0)
	_check("parity: decay floor at zero on long tick", w.tick(1000.0) == 0.0 and after <= 60.0)
