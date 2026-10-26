## harbor_lights_probe - the two-end light law's receipt (S14.8):
##   1) the pier beacon stands beside the pier head (one flank step
##      off the vessel law's pier dir, the same beat the moor uses);
##   2) the moor guide stands at the pans flank; both bases ride the
##      SEA CLAMP (max(walk, sea) -- never under water);
##   3) the NIGHT LAW flips the lamp truth on the synthetic Concord
##      epoch: noon dark, dusk lit, midnight lit, dawn dark (the
##      boundary hours are honest -- dusk itself wakes, dawn itself
##      sleeps);
##   4) the boat stays berthed where she was (the lights never move
##      the lane).
## Run headless: godot --headless --path . --script res://dev_temp/probes/harbor_lights_probe.gd
## (the builders load AFTER boot -- the parse-time preload poison)
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING := "synmergia/world/planet_radius"
const RADIUS := 20000.0

var _globe: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var HL = load("res://entities/harbor_lights.gd")
	var FV = load("res://entities/ferry_vessel.gd")
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var packed: PackedScene = load(GLOBE_SCENE)
	_globe = packed.instantiate()
	root.add_child(_globe)
	for _i in range(10):
		await process_frame
	for _i in range(30):
		await root.get_tree().physics_frame
	var wr = _globe.get("world_root")
	# 1) THE BEACON
	var beacon = wr.get_node_or_null("PierBeacon")
	if beacon == null:
		print("LIGHT-MISS no PierBeacon under WorldRoot")
		quit(1)
		return
	var lane: Array = FV.lane_dirs()
	var flank_dir: Vector3 = (beacon.get_meta("dir") as Vector3)
	print("LIGHT beacon dir angle_to_pier=%.4f rad (flank law) h=%.1f" % \
		[flank_dir.angle_to(lane[0]), beacon.position.length() - RADIUS])
	if flank_dir.angle_to(lane[0]) > 0.02:
		print("LIGHT-MISS the beacon left the pier flank")
		quit(1)
		return
	if not beacon.has_meta("lamp"):
		print("LIGHT-MISS the beacon carries no lamp material")
		quit(1)
		return
	# 2) THE MOOR GUIDE
	var guide = wr.get_node_or_null("MoorGuide")
	if guide == null:
		print("LIGHT-MISS no MoorGuide under WorldRoot")
		quit(1)
		return
	var gdir: Vector3 = (guide.get_meta("dir") as Vector3)
	print("LIGHT guide dir angle_to_moor=%.4f rad h=%.1f" % \
		[gdir.angle_to(lane[1]), guide.position.length() - RADIUS])
	if gdir.angle_to(lane[1]) > 0.02:
		print("LIGHT-MISS the guide left the moor flank")
		quit(1)
		return
	# 3) THE NIGHT LAW (synthetic Concord epochs -- the hour band
	#    edges are honest: dusk itself lights, dawn itself sleeps).
	var base_day := 14000.0
	var noon: float = base_day + 0.5  # 12:00
	var dusk: float = base_day + 18.0 / 24.0
	var midnight: float = base_day + 1.0 + 0.1 / 24.0
	var dawn_check: float = base_day + 2.0 + 6.0 / 24.0
	HL.place_night(beacon, noon)
	if bool(beacon.get_meta("lamp").emission_enabled):
		print("LIGHT-MISS the noon lamp is lit (the band starts at dusk)")
		quit(1)
		return
	HL.place_night(beacon, dusk)
	if not bool(beacon.get_meta("lamp").emission_enabled):
		print("LIGHT-MISS the dusk lamp did not wake")
		quit(1)
		return
	HL.place_night(guide, midnight)
	if not bool(guide.get_meta("lamp").emission_enabled):
		print("LIGHT-MISS the midnight moor ember did not wake")
		quit(1)
		return
	HL.place_night(beacon, dawn_check)
	if beacon.get_meta("lamp").emission_enabled:
		print("LIGHT-MISS the dawn lamp did not sleep")
		quit(1)
		return
	print("LIGHT night law noon=dark dusk=lit midnight=lit dawn=dark")
	# 4) THE LANE STAYS PUT: the lights never move the boat.
	var runner = wr.get_node_or_null("PansRunner")
	if runner == null:
		print("LIGHT-MISS no PansRunner under WorldRoot")
		quit(1)
		return
	var rdir: Vector3 = (runner.position).normalized()
	print("LIGHT runner dir angle_to_pier=%.4f rad (berth held)" % rdir.angle_to(lane[0]))
	if rdir.angle_to(lane[0]) > 0.02:
		print("LIGHT-MISS the lights displaced the ferry's berth")
		quit(1)
		return
	print("LIGHT-OK")
	quit(0)
