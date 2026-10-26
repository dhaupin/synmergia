## deck_ride_probe - the S14.6 standing-carry receipt:
##   1) the PansRunner carries PIECE colliders (the deck panel is
##      standable: its PropBody top is the deck surface itself);
##   2) a body standing in the deck box is CARRIED by place()'s
##      old->new transform -- the rigid receipt: rider delta ==
##      hull delta (same transform, never two truths);
##   3) the carried rider holds the "deck_rides" anchor and the
##      roster CLEARS it the tick after a step-off.
## Run headless: godot --headless --path . --script res://dev_temp/probes/deck_ride_probe.gd
## (the vessel law loads AFTER boot: a parse-time preload is poisoned
## by the --script-mode noise classes -- the test_load lesson)
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING := "synmergia/world/planet_radius"
const RADIUS := 20000.0

var _globe: Node
var _warped: Array = []

func _on_warped(player_id, vehicle_id, gateway_id) -> void:
	_warped.append(str(gateway_id))

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
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
	var runner = wr.get_node_or_null("PansRunner")
	if runner == null:
		print("RIDE-MISS no PansRunner under WorldRoot")
		quit(1)
		return
	# Take the tick law offline: the probe drives place() itself.
	for n in _globe.get_children():
		if n is Timer:
			n.stop()
	# 1) THE PIECE LAW: the deck panel exists and carries a standable
	#    body (the old one-belt attach left the deck unreachable).
	var deck_panel = runner.get_node_or_null("DeckPanel")
	if deck_panel == null:
		print("RIDE-MISS no DeckPanel piece under the runner")
		quit(1)
		return
	var deck_body: StaticBody3D = deck_panel.get_node_or_null("PropBody")
	if deck_body == null:
		print("RIDE-MISS the deck panel carries no standable body")
		quit(1)
		return
	print("RIDE piece colliders under runner = %d" % (runner.get_meta("colliders") as Array).size())
	# 2) THE CARRY: park the boat mid-lane, stand a body on her deck.
	FV.place(runner, 0.1)
	await root.get_tree().physics_frame
	# A body CENTER above the deck top (0.94 deck top + ~0.9 center
	# height), mid-deck on the forward section.
	var seat: Vector3 = (runner.global_transform * Transform3D(Basis(), Vector3(0.0, 1.84, 2.0))).origin
	var rider := CharacterBody3D.new()
	rider.name = "Decker"
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	col.shape = cap
	rider.add_child(col)
	root.add_child(rider)
	rider.global_position = seat
	for _i in range(5):
		await root.get_tree().physics_frame
	if not FV._in_deck_box(runner, rider):
		var local: Vector3 = runner.global_transform.affine_inverse() * rider.global_position
		print("RIDE-MISS the standing rider is outside the deck box (local=%s)" % str(local))
		quit(1)
		return
	# THE RIGID RECEIPT in vessel-LOCAL terms (global deltas drift
	# with the floating origin's reroot between reads; deck-local
	# geometry is what riding means): the rider keeps its exact deck
	# spot while the hull runs the lane.
	var rider_local_before: Vector3 = runner.global_transform.affine_inverse() * rider.global_position
	var hull_before: Vector3 = runner.global_position
	FV.place(runner, 0.13)
	await root.get_tree().physics_frame
	var docked: bool = rider.has_meta("deck_rides")
	var hull_after: Vector3 = runner.global_position
	var rider_local_after: Vector3 = runner.global_transform.affine_inverse() * rider.global_position
	var hull_d: Vector3 = hull_after - hull_before
	var local_d: Vector3 = rider_local_after - rider_local_before
	print("RIDE carried=%s hull=%.3f m deck-local drift=%.4f m" % [str(docked), hull_d.length(), local_d.length()])
	if not docked:
		print("RIDE-MISS the standing rider was not carried (no anchor meta)")
		quit(1)
		return
	if hull_d.length() < 0.2:
		print("RIDE-MISS the parked boat did not move on the park step (hull=%.3f m)" % hull_d.length())
		quit(1)
		return
	if local_d.length() > 0.05:
		print("RIDE-MISS the rigid carry is off: the rider kept %.4f m of deck-local drift over %.3f m of lane" % [local_d.length(), hull_d.length()])
		quit(1)
		return
	# 3) THE STEP-OFF: leave the deck, the roster clears the anchor
	#    the tick after.
	rider.global_position = hull_after + (rider.global_basis.x.normalized() * 60.0)
	for _i in range(3):
		await root.get_tree().physics_frame
	FV.place(runner, 0.16)
	await root.get_tree().physics_frame
	var still: bool = rider.has_meta("deck_rides")
	print("RIDE anchor after step-off = %s" % str(still))
	if still:
		print("RIDE-MISS the anchor survived the step-off")
		quit(1)
		return
	rider.queue_free()
	# 4) THE DECK WAKE SEAM: the ledger pays the standing crossing (the
	#    same ride count the dock path records at arrival).
	var fs = root.get_node_or_null("/root/FerryService")
	if fs != null and fs.has_method("record_deck_wake"):
		var res: Dictionary = fs.call("record_deck_wake", "probe_deck_rider", "veh_pans_ferry", "waypoint_sun_pans")
		var rides_n: int = int(fs.call("rides_recorded", "probe_deck_rider", "veh_pans_ferry"))
		print("RIDE wake seam ok=%s rides=%d" % [str(bool(res.get("ok", false))), rides_n])
		if not bool(res.get("ok", false)) or rides_n != 1:
			print("RIDE-MISS the deck wake seam did not pay one ride")
			quit(1)
			return
		# THE DOCK-WARP TIER: the wake gates, the route names the ports,
		# unknown ports refuse. Three wakes teach the sea your name.
		fs.wake_warped.connect(_on_warped)
		var early: Dictionary = fs.call("warp_wake", "probe_warper", "veh_pans_ferry", "waypoint_sun_pans")
		if bool(early.get("ok", true)):
			print("RIDE-MISS the wake warp opened without any rides")
			quit(1)
			return
		var off_port: Dictionary = fs.call("record_deck_wake", "probe_warper", "veh_pans_ferry", "waypoint_capitol_pier")
		var _r2: Dictionary = fs.call("record_deck_wake", "probe_warper", "veh_pans_ferry", "waypoint_capitol_pier")
		var _r3: Dictionary = fs.call("record_deck_wake", "probe_warper", "veh_pans_ferry", "waypoint_capitol_pier")
		var off: Dictionary = fs.call("warp_wake", "probe_warper", "veh_pans_ferry", "waypoint_village_center")
		if bool(off.get("ok", true)):
			print("RIDE-MISS the wake warp traveled to an off-route port")
			quit(1)
			return
		var warp: Dictionary = fs.call("warp_wake", "probe_warper", "veh_pans_ferry", "waypoint_sun_pans")
		if not bool(warp.get("ok", false)) or _warped != ["waypoint_sun_pans"]:
			print("RIDE-MISS the wake warp did not fire at three wakes (res=%s warped=%s)" % [str(warp), str(_warped)])
			quit(1)
			return
		print("RIDE wake warp gate ok (refused early, refused off-route, fired at 3)")
		# THE DOCK ROW: the warp row reads the SAME ledger -- a known
		# sailor's press pines the row; a stranger reads the count.
		var DockPanel = load("res://ui/components/ferry_dock_ui.gd").new()
		root.add_child(DockPanel)
		await root.get_tree().process_frame
		DockPanel.pin_gateway_id = "waypoint_capitol_pier"
		DockPanel.vehicle_id = "veh_pans_ferry"
		DockPanel.open_for_player("probe_nowarp")
		await root.get_tree().process_frame
		var wb = DockPanel.get("_warp_btn")
		if wb == null or not wb.visible:
			print("RIDE-MISS the dock's wake-warp row is missing (btn=%s vis=%s)" % [str(wb if wb == null else wb.visible), str(wb == null)])
			quit(1)
			return
		var wb_text: String = str(wb.text)
		if not bool(wb.disabled):
			print("RIDE-MISS the stranger's warp row is pressable without wakes")
			quit(1)
			return
		if not ("0/3" in wb_text):
			print("RIDE-MISS the stranger's warp row reads the wrong count (%s)" % wb_text)
			quit(1)
			return
		DockPanel.open_for_player("probe_warper")
		await root.get_tree().process_frame
		var wb_text2: String = str(wb.text)
		if not ("Warp to waypoint_sun_pans" in wb_text2):
			print("RIDE-MISS the sailor's warp row does not name the far port (%s)" % wb_text2)
			quit(1)
			return
		DockPanel._on_warp_pressed()
		await root.get_tree().process_frame
		if _warped.size() != 2:
			print("RIDE-MISS the dock's warp press did not fire the travel (warped=%s)" % str(_warped))
			quit(1)
			return
		print("RIDE dock warp row travels at the press")
	else:
		print("RIDE wake seam absent (no FerryService) -- skipped")
	print("RIDE-OK")
	quit(0)
