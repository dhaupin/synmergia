## Terrain streaming probe (prd-spherical-mvp.md S5)
## Run headless: godot --headless --path . --script res://tests/probe_terrain_stream.gd
## Run rendered: GODOT_PROBE_XVFB=1 xvfb-run -a godot --path . --script res://tests/probe_terrain_stream.gd
##   -> writes /tmp/play/stream_stage{1,2}.png
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const FacesScript := "res://core/frame/math/icosahedral_faces.gd"

var _globe: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# PROTOTYPE-SCALE CONTRACT: streaming order/unload laws at the 100 m
	# shell (the shipped game boots 20 km with terrain; probe_terrain_planet
	# covers that). Pin the prototype radius explicitly.
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

	var streamer = _globe.get("streamer")
	if streamer == null:
		push_error("FAIL: streamer missing (stream_terrain off?)")
		quit(1)
		return

	# --- Invariant 1: initial active set = spawn face + 3 neighbors.
	var F0 = load(FacesScript)
	var spawn_face: int = F0.face_for_direction(_globe.player.global_position)
	var initial: Array = _globe.stream_active_faces()
	ok = _check("initial active == 4 patches (got %d)" % initial.size(), initial.size() == 4) and ok
	ok = _check("spawn face %d active" % spawn_face, streamer.is_loaded(spawn_face)) and ok
	var tris: int = _globe.stream_triangle_count()
	ok = _check("patch geometry present (%d tris)" % tris, tris > 500) and ok
	_shoot("stream_stage1")

	# --- Invariant 2: crossing a face border swaps stale patches.
	# Relocate to the face whose center is at lat 19.4712, lon 0 (id
	# derived from the primitive, never hardcoded).
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

	var start_face: int = streamer.current_face
	ok = _check("relocated to face %d (got %d)" % [target_face, start_face], start_face == target_face) and ok
	var before_set: Array = _globe.stream_active_faces()

	player.auto_walk = true
	var waited: float = 0.0
	var last_face: int = start_face
	while streamer.current_face == start_face and waited < 45.0:
		await root.get_tree().physics_frame
		waited += 1.0 / 60.0
	player.auto_walk = false
	var walked_to_cross: float = player.path_walked
	var crossed: bool = streamer.current_face != start_face
	ok = _check("face crossed in %.1f m (face %d -> %d)" % [walked_to_cross, start_face, streamer.current_face], crossed) and ok

	# The stale set changed: old face far from the new one is gone.
	var after_set: Array = _globe.stream_active_faces()
	var changed: bool = false
	for f in before_set:
		if not after_set.has(f):
			changed = true
	ok = _check("stale patch unloaded on crossing", changed) and ok
	ok = _check("steady state holds 4 patches (got %d)" % _globe.stream_active_faces().size(), \
		_globe.stream_active_faces().size() == 4) and ok
	ok = _check("current face is loaded", streamer.is_loaded(streamer.current_face)) and ok
	_shoot("stream_stage2")

	# --- Invariant 3: all 20 faces individually loadable/unloadable.
	var F = load(FacesScript)
	var sweep_ok := true
	for f in range(F.face_count()):
		var center: Vector3 = F.face_center(f) * 101.0
		var stats: Dictionary = streamer.update(center)
		if streamer.current_face != f or not streamer.is_loaded(f):
			sweep_ok = false
			break
		if stats["active"].size() != 4:
			sweep_ok = false
			break
	ok = _check("all 20 faces stream (4-patch steady state)", sweep_ok) and ok

	ProjectSettings.set_setting("synmergia/world/planet_radius", 20000.0)
	if not ok:
		push_error("TERRAIN STREAM PROBE FAILED")
	quit(0 if ok else 1)


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
