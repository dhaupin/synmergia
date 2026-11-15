## Globe island probe (prd-spherical-mvp.md S3)
## Run headless:   godot --headless --path . --script res://tests/probe_globe_island.gd
## Run rendered:   GODOT_PROBE_XVFB=1 xvfb-run -a godot --path . --script res://tests/probe_globe_island.gd
##   -> writes /tmp/play/globe_stage{1,2,3}.png
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_island.tscn"
const WALK_SECONDS: float = 30.0
const WALK_DISTANCE_METERS: float = 250.0
const CELLS_TO_SAMPLE: int = 20

var _globe: Node3D
var _shots := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	# Running mode: real physics frames drive _physics_process. The
	# waiting-in-_init script-mode trap (engine would sleep forever) is
	# avoided by constructing physics nodes without SceneTree auto-advance.
	var packed: PackedScene = load(GLOBE_SCENE)
	if packed == null or not packed.can_instantiate():
		push_error("FAIL: globe scene did not load")
		quit(1)
		return
	_globe = packed.instantiate()
	root.add_child(_globe)

	# get() returns null instead of aborting on a scriptless root
	# (a parse error upstream must end in quit(1), not a hung tree).
	var player = _globe.get("player")
	if player == null or player.get_script() == null:
		push_error("FAIL: globe script missing or player missing (parse error upstream?)")
		quit(1)
		return

	# Let one physics tick run so the controller's first normal update
	# lands (pre-tick the surface normal still holds its default).
	await root.get_tree().physics_frame
	await root.get_tree().physics_frame

	# Stage 1: spawn sanity.
	ok = _check("spawned glued to shell", player.is_glued(0.2)) and ok
	ok = _check("initial surface normal == radial", \
		(player.get_surface_normal() - player.global_position.normalized()).length() < 0.01) and ok
	_shoot("globe_stage1")

	# Stage 2: walk ~250 m along the equator (real physics ticks).
	player.begin_loop()
	player.auto_walk = true
	var elapsed: float = 0.0
	var dt: float = 1.0 / 60.0
	while player.path_walked < WALK_DISTANCE_METERS and elapsed < WALK_SECONDS * 4.2:
		await root.get_tree().physics_frame
		elapsed += dt
	player.auto_walk = false
	var walked: float = player.path_walked
	ok = _check("walked ~250 m (got %.1f)" % walked, abs(walked - WALK_DISTANCE_METERS) < 30.0) and ok

	# Still on the shell, normal still radial, no escape velocity.
	ok = _check("glued after walk", player.is_glued(0.5)) and ok
	ok = _check("normal radial after walk", \
		(player.get_surface_normal() - player.global_position.normalized()).length() < 0.01) and ok
	var radial_speed: float = player.velocity.dot(player.global_position.normalized())
	ok = _check("no radial drift (|v_rad|=%.2f)" % radial_speed, abs(radial_speed) < 1.5) and ok

	# Curvature signature: 250 m of arc on the ~101 m walking shell is
	# theta = 2.475 rad (141.8 deg); chord = 2*R*sin(theta/2) = 191 m,
	# so the true ratio is 250/191 = 1.31. Flat walking gives 1.0.
	# Threshold 1.2 keeps margin without asserting wrong arithmetic.
	var ratio: float = player.walked_curvature_ratio()
	ok = _check("curvature ratio > 1.2 (got %.2f)" % ratio, ratio > 1.2) and ok

	# Markers: north pole marker stays up in local space while east
	# marker recedes - the tangent frame did not tumble.
	var cam: Camera3D = player.get_node("CameraPivot/Camera3D")
	var cam_xform: Transform3D = cam.global_transform
	var up_dot: float = cam_xform.basis.y.dot(player.get_surface_normal())
	ok = _check("camera up tracks local up (%.3f)" % up_dot, up_dot > 0.99) and ok
	_shoot("globe_stage2")

	# Stage 3: addressing - live position -> Icosahedral cell.
	var Ico = load("res://core/frame/math/icosahedral.gd").new()
	var pos: Vector3 = player.global_position
	var cell: int = Ico.position_to_cell(pos, _globe.planet_radius)
	ok = _check("cell resolved (got %d)" % cell, cell >= 0 and cell < 12) and ok
	var center: Vector3 = Ico.cell_center(cell)
	var near_center: Vector3 = (center.normalized() * _globe.planet_radius) - pos.normalized() * _globe.planet_radius
	ok = _check("player within ~6300 m of cell center (got %.0f)" % near_center.length(), \
		near_center.length() < _globe.planet_radius * 1.2) and ok
	# Neighbors of the resolved cell exist (adjacency live).
	var nbrs: PackedInt32Array = Ico.neighbors(cell)
	ok = _check("neighbors resolved (%d)" % nbrs.size(), nbrs.size() > 0) and ok
	# Sampling sweep: every probe position on the walk maps somewhere valid.
	var sweep_ok := true
	for i in range(CELLS_TO_SAMPLE):
		var f: float = float(i) / float(CELLS_TO_SAMPLE)
		var a: Vector3 = player._loop_start.normalized()
		var b: Vector3 = pos.normalized()
		var probe_pos: Vector3 = a.slerp(b, f).normalized() * _globe.planet_radius
		var c: int = Ico.position_to_cell(probe_pos, _globe.planet_radius)
		if c < 0 or c >= 12:
			sweep_ok = false
			break
	ok = _check("position->cell sweep valid", sweep_ok) and ok
	_shoot("globe_stage3")

	if not ok:
		push_error("GLOBE PROBE FAILED")
	quit(0 if ok else 1)


func _check(label: String, cond: bool) -> bool:
	print("  %s %s" % ["PASS" if cond else "FAIL", label])
	return cond


func _shoot(stage: String) -> void:
	_shots += 1
	if OS.get_environment("GODOT_PROBE_XVFB") == "":
		return
	# Guarantee a presented frame, else early shots capture the
	# pre-draw cleared buffer (all black) even with correct transforms.
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("no screenshot for %s" % stage)
		return
	var dir: String = "/tmp/play"
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png("%s/%s.png" % [dir, stage])
	print("  shot: %s/%s.png" % [dir, stage])
