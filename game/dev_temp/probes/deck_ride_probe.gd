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
	print("RIDE-OK")
	quit(0)
