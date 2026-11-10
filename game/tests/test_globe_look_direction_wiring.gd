## test_globe_look_direction_wiring - THE MINIMAP ARROW TURNS ON THE GLOBE.
##
## THE GAP: hud_integrator._process feeds the minimap arrow heading from
## `player.get_look_direction()` (the "doesn't turn" fix). The retired planar
## controller declared that method; the globe body (GlobeWorldPlayer) did not,
## so `has_method("get_look_direction")` was false and the arrow FROZE at spawn
## heading on the world the player actually plays -- the same class of wiring
## drift as the "players" group miss (test_globe_player_players_group.gd).
##
## This receipt boots the REAL globe, proves the consumer's resolution seam
## (PlayerManager.local_player) finds the globe body, proves the body answers
## the method, and drives the integrator's OWN heading leg through the real
## Minimap to show the arrow rotation moves off the frozen spawn value.
##
## Run: godot --headless --path game --script res://tests/test_globe_look_direction_wiring.gd
extends SceneTree

var _passed := 0
var _failed := 0


func _ok(msg: String) -> void:
	_passed += 1
	print("   PASS  %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	print("   FAIL  %s" % msg)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok(msg)
	else:
		_fail(msg)


func _initialize() -> void:
	print("--- GLOBE LOOK-DIRECTION WIRING RECEIPT ---")
	_run.call_deferred()


func _finish() -> void:
	print("=== GLOBE LOOK-DIRECTION WIRING: %d passed, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("GLOBE LOOK-DIRECTION WIRING RECEIPT PASSED")
		quit(0)
	else:
		print("GLOBE LOOK-DIRECTION WIRING RECEIPT FAILED")
		quit(1)


func _run() -> void:
	var boot = load("res://tests/support/globe_boot.gd")
	var globe = await boot.boot(self)
	if globe == null:
		_fail("globe_world.tscn failed to boot")
		_finish()
		return
	current_scene = globe
	var player = boot.player(globe)
	var pm := root.get_node_or_null("PlayerManager")
	var tm := root.get_node_or_null("TargetingManager")
	_check(player != null, "globe body present")
	_check(pm != null, "PlayerManager up")
	_check(tm != null, "TargetingManager up")
	if player == null or pm == null or tm == null:
		await boot.teardown(globe, self)
		_finish()
		return

	# 1. The consumer's resolution seam finds the globe body (not a stale plana
	#    body, not null).
	var local: Variant = pm.get("local_player")
	_check(local != null and is_instance_valid(local) and local == player,
		"PlayerManager.local_player resolves the globe body (the HUD's seam)")

	# 2. The body answers the method the consumer gates on. THIS is the gap:
	#    before the fix has_method("get_look_direction") was false on the globe.
	_check(player.has_method("get_look_direction"),
		"globe body answers get_look_direction() (the consumer's has_method gate)")

	# 3. The live HUD carries the consumer + the Minimap it drives.
	var hud: Node = globe.get_node_or_null("HudLayer")
	var integ: Node = null
	var minimap: Node = null
	if hud != null:
		integ = hud.get_node_or_null("HudIntegrator")
		minimap = hud.get_node_or_null("Minimap")
	_check(integ != null, "HudLayer carries the HudIntegrator")
	_check(minimap != null and minimap.has_method("set_player_rotation"),
		"Minimap is live and exposes set_player_rotation")

	# If the method is missing the rest of the receipt is meaningless: report
	# the gap cleanly (a method call on a missing method aborts the coroutine,
	# which would otherwise hang the run instead of failing it).
	if not player.has_method("get_look_direction"):
		_fail("the rest of the receipt needs get_look_direction -- skipping")
		await boot.teardown(globe, self)
		_finish()
		return

	# 4. Untargeted: the direction is the camera pivot's forward (the planar law).
	var pivot: Node3D = player.get_node_or_null("CameraPivot")
	var expected_forward: Vector3 = -pivot.global_transform.basis.z if pivot != null else Vector3.ZERO
	var look: Vector3 = player.get_look_direction()
	_check(pivot != null and look.distance_to(expected_forward) < 0.01,
		"untargeted look direction == camera pivot forward")

	# 5. THE CONSUMER LEG: rotate the camera, let the engine tick the integrator,
	#    and prove the minimap arrow heading moved OFF the frozen spawn value.
	var rot_before: float = float(minimap.get("_player_rotation")) if minimap != null else 0.0
	player.orbit_camera(1.0, 0.0)  # swing the view ~1 rad
	for _i in range(30):
		await physics_frame
		await process_frame
	var look_after: Vector3 = player.get_look_direction()
	var rot_after: float = float(minimap.get("_player_rotation")) if minimap != null else 0.0
	var yaw_expected: float = atan2(look_after.x, look_after.z)
	_check(absf(rot_after - rot_before) > 0.001,
		"the minimap arrow heading MOVED after the camera turned (not frozen)")
	# The integrator stores atan2(look.x, look.z); the damped value converges
	# to it. Allow the lerp's residual.
	var yaw_err: float = absf(angle_difference(rot_after, yaw_expected))
	_check(yaw_err < 0.2,
		"the minimap heading matches the body's look direction (err %.3f rad)" % yaw_err)

	# 6. Targeted: the look direction faces the live target (the planar law's
	#    first branch), driven through the real TargetingManager pool. The
	#    "enemy" schema id resolves to the real target_enemy.tres (no phantom
	#    schema load).
	var dummy := Node3D.new()
	globe.add_child(dummy)
	dummy.global_position = player.global_position + Vector3(0, 0, 3.0)
	tm.set_target("look_receipt_target", "enemy", "LookDummy", dummy.global_position, dummy, 2, {})
	player.is_targeting = true
	var toward: Vector3 = (dummy.global_position - player.global_position).normalized()
	var targeted_look: Vector3 = player.get_look_direction()
	_check(targeted_look.distance_to(toward) < 0.01,
		"targeted look direction faces the live target")
	player.is_targeting = false
	player.clear_target()
	if is_instance_valid(dummy):
		dummy.queue_free()

	await boot.teardown(globe, self)
	_finish()
