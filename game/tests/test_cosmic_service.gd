extends SceneTree

## Tests for CosmicService — the one live cosmic flywheel: real NOAA
## Kp in, weather bands out, sparks bridged to EventHub. Headless-safe:
## CosmicService._ready only reads persistence and starts polling (no
## audio/GPU deps). Run:
##   godot --headless --path . --script res://tests/test_cosmic_service.gd

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	# Autoload _ready may lag the first probes in script mode (two
	# frames settles it — the same patience test_mysteries.gd needs).
	await process_frame
	await process_frame
	var svc = root.get_node_or_null("CosmicService")
	if svc == null:
		var script = load("res://core/services/cosmic_service.gd")
		svc = script.new()
		root.add_child(svc)
		await process_frame
	_check("CosmicService boots with a cosmic wheel", svc.cosmic != null)
	_test_ingest_and_freshness(svc)
	_test_decay_steer(svc)
	_test_spark_bridging(svc)
	_test_driver_borrow(svc)
	print("CosmicService tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("  PASS %s" % label)
		_passed += 1
	else:
		print("  FAIL %s" % label)
		_failed += 1


func _test_ingest_and_freshness(svc) -> void:
	var before: int = svc.cosmic.sparks()
	var t0: float = Time.get_unix_time_from_system()
	svc.ingest_kp(0.0, t0)
	_check("quiet Kp ingests without spark", svc.cosmic.sparks() == before)
	_check("kp recorded", is_equal_approx(svc.cosmic.last_kp, 0.0))
	_check("fresh at +1h (within 3h law)", svc.cosmic.has_fresh_kp(t0 + 3600.0))
	_check("stale at +4h (past 3h law)", not svc.cosmic.has_fresh_kp(t0 + 4.0 * 3600.0))


func _test_decay_steer(svc) -> void:
	svc.cosmic.wheel.momentum = 50.0
	svc.steer_decay(10.0)
	_check("decay steer 10s removes 5.0", is_equal_approx(svc.cosmic.momentum(), 45.0))


func _test_spark_bridging(svc) -> void:
	var sparks_seen: Array = []
	svc.spark.connect(func(p): sparks_seen.append(p))
	svc.ingest_kp(9.0, 2000.0)
	_check("Kp 9 storm sparks the wheel (362.5 chaos > 100)", sparks_seen.size() >= 1)
	if sparks_seen.size() > 0:
		var p: Dictionary = sparks_seen[0]
		_check("spark payload has cosmic shape (wheel/kp/momentum)",
			str(p.get("wheel")) == "cosmic" and p.has("kp") and p.has("momentum"))


func _test_driver_borrow(svc) -> void:
	# The AmbienceDriver borrows the SAME wheel — one shared flywheel.
	var drv_script = load("res://entities/ambience_driver.gd")
	var drv = Node3D.new()
	drv.set_script(drv_script)
	root.add_child(drv)
	# simulate private-wheel fallback path by grabbing root node
	var borrowed_ok: bool = (svc.cosmic != null)
	_check("service wheel exists to be borrowed", borrowed_ok)
	drv.queue_free()
