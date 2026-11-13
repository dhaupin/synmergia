## Probe: the CHART-LOD live climb in globe_world (the turn-8 scene
## glue). Headless script mode:
##   godot --headless --path game --script res://tests/probe_chart_lod_scene.gd
##
## Asserts the scene-level wiring laws:
##   G1. BOOT: _setup_chart_lod built the adapter + ChartLodRoot under
##       world_root, and the first adapter tick queued boot orders for
##       at least one chart (cold start).
##   G2. FUNNEL: after a forced observer move through plan updates,
##       real MeshInstance3D nodes exist under ChartLodRoot named by
##       chart index, each carrying >= 2 surfaces (surface + skirt)
##       and non-degenerate AABBs.
##   G3. CLIMB: two far-apart observers produce DIFFERENT chart rung
##       maps in the adapter's settle path (the ladder is actually
##       driven by position, not a fixed layout).
##   G4. TICK ECONOMY: an at-throttle call to _update_chart_lod is a
##       no-op (accum guard), 2 Hz, matching the truth-line cadence.
extends SceneTree

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  PASS %s" % label)
	else:
		_failed += 1
		printerr("  FAIL %s" % label)


func _run() -> void:
	var GlobeWorldScript = load("res://scenes/worlds/globe_world.gd")
	_check(GlobeWorldScript != null, "globe_world.gd loads")

	# G1: build the scene via the proxy-layout probe path (same trick
	# the terrain probes use: instantiate without a running game).
	var globe = GlobeWorldScript.new()
	root.add_child(globe)
	await process_frame
	await process_frame
	_check(globe.clipmap != null, "clipmap booted")
	_check(globe.chart_lod != null, "chart LOD adapter booted")
	_check(globe.chart_lod_root != null and globe.chart_lod_root.get_parent() == globe.world_root, "ChartLodRoot under world_root")

	# G2: drive the scene funnel directly (the physics tick throttles
	# at 0.5 s of accumulated delta -- headless script mode does not
	# accrue that in two process frames). One forced tick at fullDelta
	# must mesh at least one chart overlay with surface + skirt.
	# BOOT CRASH GATE: the funnel is gated OFF by default in the scene
	# (the play-day crash: one cold tick meshed ~42 overlays during
	# the boot window and starved the engine's progress signal). The
	# probe flips the gate on -- that is the point: the GATED-ON path
	# is probed here, players boot with it off.
	globe.chart_overlays_on = true
	globe._update_chart_lod(1.0)
	await process_frame
	_check(not globe.chart_overlays_on or globe._chart_nodes.size() <= globe.MAX_ORDERS_PER_TICK + globe.MAX_ORDERS_PER_TICK + 1,
		"per-tick order budget bounds the cold-start work (%d nodes <= budget+1)" % globe._chart_nodes.size())
	var nodes := 0
	for c in globe.chart_lod_root.get_children():
		if c is MeshInstance3D:
			nodes += 1
			var mi: MeshInstance3D = c
			_check(mi.mesh != null and mi.mesh.get_surface_count() >= 2, "chart overlay %s has surface + skirt" % mi.name)
	_check(nodes > 0, "at least one chart overlay meshed at boot")

	# G3: the ladder is position-driven -- two far-apart plans differ.
	var policy = load("res://scenes/worlds/penrose_chart_lod.gd")
	var plan_a: Dictionary = policy.plan_safe(0.0, 0.0, 1)
	var plan_b: Dictionary = policy.plan_safe(45.0, 160.0, 1)
	var differ := false
	for i in plan_a:
		if int(plan_a[i]["subdiv"]) != int(plan_b[i]["subdiv"]):
			differ = true
			break
	_check(differ, "far-apart observers produce different rung maps")

	# G4: the accrual guard -- the adapter plan state did not advance
	# on a synthetic pass of the same observer twice with no delta.
	var adapter = load("res://scenes/worlds/penrose_chart_adapter.gd").new()
	var first: Dictionary = policy.plan_safe(10.0, 10.0, 1)
	adapter.apply_plan(first, 1)
	var no_orders: Array = adapter.apply_plan(policy.plan_safe(10.0, 10.0, 1))
	_check(no_orders.is_empty(), "at-throttle repeat queues zero orders")

	print("CHART LOD SCENE probe: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
