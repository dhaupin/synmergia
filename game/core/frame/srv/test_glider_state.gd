# test_glider_state.gd - co-located test for the GliderState primitive.
# Run: godot --headless --path . --script res://core/frame/srv/test_glider_state.gd
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var GS = load("res://core/frame/srv/glider_state.gd")

	# ---- Auto deployment above the height gate --------------------------
	var g = GS.new()
	g.on_airborne()
	_check("airborne starts FALLING", g.state == GS.State.FALLING)
	var s: int = g.tick(1.0 / 60.0, 3.0)  # below the gate
	_check("low fall does not auto-deploy", s == GS.State.FALLING)
	s = g.tick(1.0 / 60.0, 12.0)  # above the gate
	_check("auto-deploy above 6 m", s == GS.State.GLIDING)

	# ---- Manual mode: jump again mid-fall -------------------------------
	var m = GS.new()
	m.deployment_mode = "manual"
	m.on_airborne()
	m.tick(1.0 / 60.0, 20.0)
	_check("manual mode never auto-deploys", m.state == GS.State.FALLING)
	m.on_deploy_pressed()
	_check("manual deploy opens the wing", m.state == GS.State.GLIDING)

	# Manual grace: too late = no deploy (the ground came first).
	var late = GS.new()
	late.deployment_mode = "manual"
	late.on_airborne()
	late.tick(5.0, 20.0)
	late.on_deploy_pressed()
	_check("manual grace window closes after 4 s", late.state == GS.State.FALLING)

	# ---- Glide model -----------------------------------------------------
	var g2 = GS.new()
	g2.on_airborne()
	g2.tick(1.0 / 60.0, 30.0)  # auto-deploy
	var sink: float = g2.glide_vertical_speed(0.0)
	var floated: float = g2.glide_vertical_speed(1.0)
	_check("glide sinks at 4.5 m/s in still air", abs(sink - 4.5) < 0.001)
	_check("thermal lift reduces the sink (never a launch)", \
		floated > -0.01 and floated < sink)
	_check("dive is faster than level flight", \
		g2.glide_forward_speed(1.0) > g2.glide_forward_speed(0.0))
	_check("dive top speed 16, level 7", \
		abs(g2.glide_forward_speed(1.0) - 16.0) < 0.001 \
		and abs(g2.glide_forward_speed(0.0) - 7.0) < 0.001)

	# ---- Landing resets; stow mid-air resumes the fall -------------------
	g2.tick(1.0 / 60.0, 0.2)
	_check("touch-down lands and resets", g2.state == GS.State.GROUNDED)
	g2.on_airborne()
	g2.tick(1.0 / 60.0, 30.0)
	g2.on_stow_pressed()
	_check("stow mid-air resumes the fall", g2.state == GS.State.STOWED_FALL)

	# ---- The mount cliff answer ------------------------------------------
	_check("mount rule: the mount bails, the rider keeps the fall", \
		GS.MOUNT_DISMOUNT_ON_FALL == true)

	# ---- Grounded tick is inert ------------------------------------------
	var g3 = GS.new()
	var s3: int = g3.tick(0.5, 100.0)
	_check("grounded state ignores altitude", s3 == GS.State.GROUNDED)

	if _fails == 0:
		print("GLIDER STATE TEST PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("GLIDER STATE TEST FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
