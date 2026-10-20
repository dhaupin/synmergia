## pans_builds_probe - the pans art trio's receipt:
##   1) the PansMonolith stands in the booted world (WorldRoot child),
##   2) the PansRunner vessel holds a berth position on the pier<->pans
##      lane (the ride law placed it),
##   3) the almanac's sailing page lists EVERY scheduled ferry (the
##      Haven Ferry AND the Pans Runner -- the ferries[0] lesson).
## Run headless: godot --headless --path . --script res://dev_temp/probes/pans_builds_probe.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING := "synmergia/world/planet_radius"
const RADIUS := 20000.0
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")

var _globe: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var packed: PackedScene = load(GLOBE_SCENE)
	_globe = packed.instantiate()
	root.add_child(_globe)
	for _i in range(10):
		await process_frame
	for _i in range(30):
		await root.get_tree().physics_frame
	# 1) THE MONOLITH
	var wr = _globe.get("world_root")
	var mono = wr.get_node_or_null("PansMonolith")
	if mono == null:
		print("PANS-BUILD-MISS no PansMonolith under WorldRoot")
		quit(1)
		return
	var mono_lord: Vector3 = (mono.position).normalized()
	var pans: Vector3 = TerrainGen.sun_pans_dir()
	print("PANS-BUILD monolith pos angle_to_pans=%.4f rad label=%s" % [mono_lord.angle_to(pans), mono.name])
	if mono_lord.angle_to(pans) > 0.02:
		print("PANS-BUILD-MISS monolith off the pans bearing")
		quit(1)
		return
	# 2) THE RUNNER
	var runner = wr.get_node_or_null("PansRunner")
	if runner == null:
		print("PANS-BUILD-MISS no PansRunner under WorldRoot")
		quit(1)
		return
	var rdir: Vector3 = (runner.position).normalized()
	var pier_lane: Array = preload("res://entities/ferry_vessel.gd").lane_dirs()
	var pier_dir: Vector3 = pier_lane[0]
	print("PANS-BUILD runner pos angle_to_pier=%.4f rad h=%.1f" % [rdir.angle_to(pier_dir), runner.position.length() - RADIUS])
	if rdir.angle_to(pier_dir) > 0.05:
		print("PANS-BUILD-MISS runner not berthed at the pier end")
		quit(1)
		return
	# 3) THE SAILING PAGE (must carry BOTH ferries)
	var Almanac = load("res://ui/components/sky_almanac_ui.gd")
	var panel: Control = Almanac.new()
	root.add_child(panel)
	await root.get_tree().process_frame
	await root.get_tree().process_frame
	var sail_rows = panel.get("_sail_rows")
	if sail_rows == null:
		print("PANS-BUILD-MISS almanac sail rows absent")
		quit(1)
		return
	var had_haven: bool = false
	var had_pans: bool = false
	var lines := 0
	for lbl in sail_rows.get_children():
		if lbl is Label and not String(lbl.text).is_empty():
			lines += 1
			if "Haven Ferry" in lbl.text:
				had_haven = true
			if "Pans Runner" in lbl.text:
				had_pans = true
	print("PANS-BUILD sailing rows=%d haven=%s pans=%s" % [lines, str(had_haven), str(had_pans)])
	if not had_pans:
		print("PANS-BUILD-MISS the Pans Runner is invisible on the sailing page")
		quit(1)
		return
	# 4) THE HARBOR CALLERS LAW: a dock opened for the capitol pier
	#    pin fronts BOTH lines -- the Haven Ferry by scan order, and
	#    after a switch press, the Pans Runner (the pin's second
	#    caller). Broad failures are misses; missing cycles are a
	#    miss too.
	var DockPanel = load("res://ui/components/ferry_dock_ui.gd").new()
	root.add_child(DockPanel)
	await root.get_tree().process_frame
	DockPanel.pin_gateway_id = "waypoint_capitol_pier"
	DockPanel.open_for_player("probe_pier")
	await root.get_tree().process_frame
	var first_route: String = str(DockPanel._route_row.text)
	print("PANS-BUILD dock first caller=", first_route)
	if not ("Haven Ferry" in first_route):
		print("PANS-BUILD-MISS the pier's first caller is not the Haven Ferry")
		quit(1)
		return
	DockPanel._on_cycle_pressed()
	await root.get_tree().process_frame
	var second_route: String = str(DockPanel._route_row.text)
	print("PANS-BUILD dock second caller=", second_route)
	if not ("Pans Runner" in second_route):
		print("PANS-BUILD-MISS the Pans Runner is unboardable at the pier")
		quit(1)
		return
	# 5) THE BERTH-CLEARANCE TUNE (the numeric clip receipt): the
	#    berthed keel bottoms at the berth origin - 0.55 (the 1.1 m
	#    belly box); the pier head's deck top rides at walk + 1.125
	#    (head origin 0.85 + plate at +0.15 + half-plate 0.125). The
	#    clearance is a LIVE-MODEL number: the constants must leave
	#    at least 0.2 m of air over the boards.
	var FV = load("res://entities/ferry_vessel.gd")
	var keel_clear: float = float(FV.PIER_BERTH_LIFT) - 0.55 - 1.125
	print("PANS-BUILD keel clearance over pier boards=%.2f m" % keel_clear)
	if keel_clear < 0.2:
		print("PANS-BUILD-MISS the berthed hull clips the pier head")
		quit(1)
		return
	# 6) THE BERTH ALTERNATION (the pure schedule timeline): the
	#    vessel_t law at synthetic Concord epochs -- pre-dawn her at
	#    the pier (t=0, first cast-off even), mid leg-1 she is mid-lane
	#    (t=0.5), arrived at the pans moor before the 19.5 leg (t=1),
	#    mid leg-2 mirrored (t=0.5), and the overnight sleep leaves her
	#    at the pier for dawn (t=0). One derivation, the boot's tick
	#    and any future deck law read the same numbers.
	var Sched = preload("res://core/frame/srv/ferry_schedule.gd")
	var base_day := 12000.0
	var t_pre: float = Sched.vessel_t(2, 7.5, 3.0, base_day + 5.0 / 24.0)
	var t_mid1: float = Sched.vessel_t(2, 7.5, 3.0, base_day + 9.0 / 24.0)
	var t_moor: float = Sched.vessel_t(2, 7.5, 3.0, base_day + 15.0 / 24.0)
	var t_mid2: float = Sched.vessel_t(2, 7.5, 3.0, base_day + 21.0 / 24.0)
	var t_dawn: float = Sched.vessel_t(2, 7.5, 3.0, base_day + 1.0 + 2.0 / 24.0)
	print("PANS-BUILD berths pre=%.2f mid1=%.2f moor=%.2f mid2=%.2f dawn=%.2f" % [t_pre, t_mid1, t_moor, t_mid2, t_dawn])
	if absf(t_pre) > 0.01 or absf(t_moor - 1.0) > 0.01 \
			or absf(t_mid1 - 0.5) > 0.02 or absf(t_mid2 - 0.5) > 0.02 \
			or absf(t_dawn) > 0.01:
		print("PANS-BUILD-MISS the berth alternation law is off its timeline")
		quit(1)
		return
	print("PANS-BUILD-OK")
	quit(0)
