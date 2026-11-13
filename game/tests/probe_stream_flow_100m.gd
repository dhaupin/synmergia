## Terrain streaming probe, CHUNK 1 of 2 (prototype flow laws)
## Carved from probe_terrain_stream.gd (prd-spherical-mvp.md S5) so
## CI minutes fit: this chunk runs only the 100 m prototype globe
## (cheap). The planet-scale walk/arc checks live in
## probe_terrain_planet.gd + the continent shards (heavy).
## Run headless: godot --headless --path . --script res://tests/probe_stream_flow_100m.gd
## Run rendered: GODOT_PROBE_XVFB=1 xvfb-run -a godot --path . --script res://tests/probe_stream_flow_100m.gd
##   -> writes /tmp/play/stream_stage{1,2}.png
##
## The clipmap is the SOLE renderer now. Its laws differ from the retired
## icosa clipmap's, so this probe pins the CLIPMAP's laws at the 100 m
## scale: a full ring ladder builds (cap + 5 rings), the triangle count is
## constant (geometric rings), the walk law the drawn world serves is the
## analytic law, and the world re-centres as the player walks (the L1
## hysteresis law). The clipmap's per-face want-set / skirt / discrete-LOD
## laws are GONE (constant SEG cells stitch the rings, no skirts); their
## replacements are pinned by probe_clipmap G1-G5 at planet scale.
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const FacesScript := "res://core/frame/math/icosahedral_faces.gd"

var _globe: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# PROTOTYPE-SCALE CONTRACT: the clipmap renders every scale (the old
	# sub-1000 m clipmap fallback is gone). Pin the prototype radius.
	ProjectSettings.set_setting("synmergia/world/planet_radius", 100.0)
	var ok := true
	var packed: PackedScene = load(GLOBE_SCENE)
	if packed == null or not packed.can_instantiate():
		push_error("FAIL: globe scene did not load")
		quit(1)
		return
	_globe = packed.instantiate()
	root.add_child(_globe)

	var player = _globe.get("player")
	if player == null or player.get_script() == null:
		push_error("FAIL: player missing (parse error upstream?)")
		quit(1)
		return
	await root.get_tree().physics_frame
	await root.get_tree().physics_frame

	var clipmap = _globe.get("clipmap")
	if clipmap == null:
		push_error("FAIL: clipmap missing (stream_terrain off?)")
		quit(1)
		return

	# --- Invariant 1: the clipmap builds its full ring ladder at boot.
	var F0 = load(FacesScript)
	var spawn_face: int = F0.face_for_direction(_globe.player.global_position)
	await _settle()
	ok = _check("spawn face %d active" % spawn_face, clipmap.is_loaded(spawn_face)) and ok
	var tris: int = _globe.stream_triangle_count()
	ok = _check("patch geometry present (%d tris)" % tris, tris > 500) and ok
	ok = _check("clipmap built the full ring ladder (5 rings)", clipmap.patch_count() >= 5) and ok
	_shoot("stream_stage1")

	# --- Invariant 2: the world re-centres as the player walks, and the
	# drawn mesh is CONSTANT (the geometric-ring law). Relocate to a face
	# center far from spawn and walk.
	var F1 = load(FacesScript)
	var Sph = load("res://core/frame/math/spherical.gd")
	var target_dir: Vector3 = Sph.spherical_to_cartesian(19.4712, 0.0, 0.0, _globe.planet_radius)
	var target_face: int = F1.face_for_direction(target_dir)
	var spawn: Vector3 = target_dir.normalized() * (_globe.planet_radius + 1.0)
	player.global_position = spawn
	player.velocity = Vector3.ZERO
	player.begin_loop()
	await root.get_tree().physics_frame
	await root.get_tree().physics_frame
	await root.get_tree().physics_frame

	var start_face: int = clipmap.current_face
	ok = _check("relocated to face %d (got %d)" % [target_face, start_face], start_face == target_face) and ok
	var center_before: Vector3 = clipmap._center_dir

	# Walk a bit: the body stays glued and the drawn mesh stays CONSTANT
	# (the geometric-ring law).
	player.auto_walk = true
	for i in range(90):
		await root.get_tree().physics_frame
	player.auto_walk = false
	await _settle()
	ok = _check("triangle count stays constant after the walk (%d)" % _globe.stream_triangle_count(), \
		_globe.stream_triangle_count() == tris) and ok

	# RE-CENTRE LAW (L1 hysteresis): the lattice re-snaps only past
	# RE_CENTER_M of ground arc. At the 100 m prototype that is a large
	# fraction of the circumference, so drive the player there directly
	# (a deterministic move, not a timed walk).
	var away: Vector3 = target_dir.normalized().rotated(Vector3(0, 1, 0), 1.8).normalized()
	player.global_position = away * (_globe.planet_radius + 1.0)
	player.velocity = Vector3.ZERO
	for i in range(8):
		await root.get_tree().physics_frame
	ok = _check("the lattice re-centres past the hysteresis ring", clipmap._center_dir != center_before) and ok

	# TERRAIN LOD (the clipmap's law): the drawn ground under the player IS
	# the analytic law (the walk surface the player rides). At the 100 m
	# scale the innermost cell is sub-metre, so the drawn-vs-law delta is
	# tight -- the whole point of the clipmap.
	var d_spawn: Vector3 = (player.global_position - _globe.planet_center).normalized()
	var walk_h: float = clipmap.walk_surface_h(d_spawn)
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var law_h: float = Gen.terrain_height(d_spawn, clipmap.world_seed)
	ok = _check("walk law == terrain law at the body (walk %.2f law %.2f)" % [walk_h, law_h], \
		absf(walk_h - law_h) < 6.0) and ok
	ok = _check("current face is loaded", clipmap.is_loaded(clipmap.current_face)) and ok
	_shoot("stream_stage2")

	# --- Invariant 3: the world stays alive as the player sweeps around.
	var sweep_ok := true
	for f in range(F1.face_count()):
		var center: Vector3 = F1.face_center(f) * 101.0
		clipmap.update(center)
		if clipmap.current_face != f or not clipmap.is_loaded(f):
			sweep_ok = false
			break
	ok = _check("every icosa face loads under the clipmap sweep", sweep_ok) and ok
	# The globe's own per-frame update then takes the wheel back and
	# re-centres on the PLAYER; pin that the world re-settles.
	ok = _check("post-sweep world re-settles on the player", await _settle_player()) and ok

	if not ok:
		push_error("TERRAIN STREAM FLOW PROBE FAILED")
	quit(0 if ok else 1)


## Bounded settle: the clipmap builds incrementally through its job queue,
## so a steady world is a SETTLE law. Waits on the derive lane + a few
## frames for the deferred applies to run.
func _settle(seconds: float = 30.0) -> void:
	var st = _globe.get("clipmap")
	var waited: float = 0.0
	while st != null and st.pending_jobs() > 0 and waited < seconds:
		await root.get_tree().physics_frame
		waited += 1.0 / 60.0
	for _i in range(4):
		await root.get_tree().physics_frame


## Wait until the derive lane is idle AND the clipmap holds the current
## face's full ring ladder. Bounded at 60 s (the headless VM's cold build
## is multi-second).
func _settle_player(seconds: float = 60.0) -> bool:
	var st = _globe.get("clipmap")
	var waited: float = 0.0
	while waited < seconds:
		await root.get_tree().physics_frame
		waited += 1.0 / 60.0
		if st.pending_jobs() > 0:
			continue
		if st.is_loaded(st.current_face):
			return true
	return false


func _check(label: String, cond: bool) -> bool:
	print("  %s %s" % ["PASS" if cond else "FAIL", label])
	return cond


func _shoot(stage: String) -> void:
	if OS.get_environment("GODOT_PROBE_XVFB") == "":
		return
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("no screenshot for %s" % stage)
		return
	var dir: String = "/tmp/play"
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png("%s/%s.png" % [dir, stage])
	print("  shot: %s/%s.png" % [dir, stage])
