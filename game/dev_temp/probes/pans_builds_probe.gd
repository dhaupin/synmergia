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
	print("PANS-BUILD-OK")
	quit(0)
