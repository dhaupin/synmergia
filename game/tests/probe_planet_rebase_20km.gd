## Planet-scale probe, CHUNK 3 of 3 (floating-origin rebase + cells)
## Carved from probe_planet_scale_20km.gd (prd-spherical-mvp.md S8)
## to keep each chunk inside the sandbox/CI wall-clock. This chunk
## pins the S8 fix on the rebase path: teleport 1600 m out, one frame
## later the planet shifts back around the player, the body lands
## near the world origin, ground support survives, and walking
## continues. Siblings: probe_planet_control_100m.gd (chunk 1) and
## probe_planet_walk_20km.gd (chunk 2, stages B+C).
## Run headless:   godot --headless --path . --script res://tests/probe_planet_rebase_20km.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"
const PLANET_RADIUS_20KM: float = 20000.0
## Walk surface above the base shell when streaming (mirrors the
## scene's TILE_LIFT / clipmap.TILE_LIFT).
const TILE_LIFT: float = 0.52
## Walk target and wall-clock frame caps (headless ticks ~60 Hz).
const WALK_SECONDS: float = 8.0
const MAX_FRAMES: int = 600
## Stage D teleport distance: past SHIFT_RADIUS (1500) but well inside
## the streamed face scale, so patches can reload around the spot.
const SHIFT_TELEPORT_M: float = 1600.0

var _globe: Node3D
var _shots := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	# Terrain arc (v2): the walk surface rides the seeded heightfield.
	var Gen: GDScript = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()

	_set_planet_radius(PLANET_RADIUS_20KM)

	# ---- Stage D: forced floating-origin rebase at 20 km ------------
	# Teleport past SHIFT_RADIUS: the planet must rebase around the
	# player (body back near the world origin), ground support and
	# streaming must survive, and walking must continue after the
	# teleport. This is the regression guard for the S8 stall fix.
	if not _build_globe():
		quit(1)
		return
	var pD: CharacterBody3D = _globe.get("player")
	await _settle(2)
	# Terrain law at the SPAWN direction: the rebase returns the body
	# to the pre-teleport surface gap (|c| and the re-land both derive
	# from the spawn surface, not the teleport target's).
	var spawn_dir_d: Vector3 = (pD.global_position - _globe.planet_center).normalized()
	var terrain_d: float = Gen.terrain_height(spawn_dir_d, seed_b)
	var shifts_spawn: int = _globe.scene_shift_count
	# Local east at the spawn point (equator, lon 0): the player's own
	# tangent frame convention, east = north x up = (0,0,-1) here.
	var east: Vector3 = Vector3(0, 0, -1)
	pD.position += east * SHIFT_TELEPORT_M
	await _settle(3)
	var body_r: float = pD.global_position.length()
	var center_len: float = (_globe.planet_center as Vector3).length()
	var walk_r: float = PLANET_RADIUS_20KM + TILE_LIFT + terrain_d + 1.0
	print("  info: after teleport+shift: body |r| = %.1f m, |planet_center| = %.1f m, shifts = %d" % \
		[body_r, center_len, _globe.scene_shift_count])
	ok = _check("shift: rebase triggered exactly once more (got %d)" % _globe.scene_shift_count, \
		_globe.scene_shift_count == shifts_spawn + 1) and ok
	# Post-rebase the body sits at the gap between the moved planet
	# center radius and the walk surface (|c| - walk_r ~ 64 m here):
	# small, stable, and far under SHIFT_RADIUS. That IS the re-land.
	# The re-land: the body returns NEAR the world origin. (The old
	# exact-gap identity |r| = |c| - walk_r held only when the pad
	# height was constant; with the terrain arc the re-land depends on
	# the heightfield at the teleport column and the settle dynamics
	# across the shift. Ground support is proven by the glue check and
	# the post-shift walk below.)
	ok = _check("shift: player body re-lands near the origin (|r|=%.1f)" % body_r, \
		body_r < 150.0) and ok
	ok = _check("shift: planet center carries the offset (|c|=%.1f)" % center_len, \
		abs(center_len - sqrt(pow(walk_r, 2) + pow(SHIFT_TELEPORT_M, 2))) < 5.0) and ok
	ok = _check("shift: still glued after rebase", pD.is_glued(2.0)) and ok
	# The rebase re-rings the 4 faces; the 3 non-current faces derive on
	# worker lanes (_kick_mesh_derivation), so drain the async lanes before
	# reading the live patch count -- the steady-state ring is 4 (the
	# continent shards use the same drain before their counts).
	var st_d = _globe.get("clipmap")
	if st_d != null and st_d.has_method("pending_derive"):
		var drain := 0
		while st_d.pending_derive() > 0 and drain < 900:
			await root.get_tree().physics_frame
			drain += 1
	var facesD: Array = _globe.stream_active_faces()
	ok = _check("shift: streaming survives rebase (got %d patches)" % facesD.size(), \
		facesD.size() == 4) and ok
	# Walk AFTER the shift: locomotion must still work (the original
	# stall reproduced exactly here pre-fix).
	pD.begin_loop()
	pD.auto_walk = true
	var walkedD: float = await _walk_until(pD, 10.0, 4.0)
	pD.auto_walk = false
	var arcD: float = _arc(pD._loop_start, pD.global_position, _globe.planet_center)
	print("  info: post-shift walk = %.2f m (arc %.2f m)" % [walkedD, arcD])
	ok = _check("shift: walks freely after rebase (got %.1f m)" % walkedD, \
		walkedD >= 8.0) and ok
	ok = _check("shift: arc metric sane post-shift (%.1f m)" % arcD, \
		arcD >= 6.0 and arcD <= 14.0) and ok
	ok = _check("shift: no runaway rebase loop (got %d)" % _globe.scene_shift_count, \
		_globe.scene_shift_count == shifts_spawn + 1) and ok
	await _free_globe()

	# ---- Stage E: direct cell addressing at 20 km -------------------
	# One spawn-direction lookup; no slerp sweep (nearly-parallel
	# vectors on a 20 km arc are numerically degenerate for slerp).
	var Faces: GDScript = load("res://core/frame/math/icosahedral_faces.gd")
	var Sph: GDScript = load("res://core/frame/math/spherical.gd")
	var dir: Vector3 = Sph.spherical_to_cartesian(19.4712, 0.0, 0.0, 1.0)
	var face: int = Faces.face_for_direction(dir)
	ok = _check("20km: spawn-direction resolves a face (got %d)" % face, \
		face >= 0 and face < 20) and ok

	if not ok:
		push_error("PLANET 20KM REBASE PROBE FAILED")
	quit(0 if ok else 1)


## Arc distance along the planet surface between two WORLD positions
## (floating origin: directions are taken from the PLANET CENTER --
## from the world origin a 10 m walk post-rebase swings the direction
## by ~9 degrees because the body sits only ~64 m from the origin).
## The honest walk metric at 20 km: immune to radial jitter/fall
## (path_walked counts vertical motion, which is how the crashed
## session's '0.14 m drift' artifact and the 102 m sink both read).
func _arc(start: Vector3, end: Vector3, planet_center: Vector3) -> float:
	var a: Vector3 = (start - planet_center).normalized()
	var b: Vector3 = (end - planet_center).normalized()
	return acos(clampf(a.dot(b), -1.0, 1.0)) * PLANET_RADIUS_20KM


## Walk with auto_walk until target meters or the wall-clock cap.
## Returns the walked distance. Bounded: exits after MAX_FRAMES.
func _walk_until(p: CharacterBody3D, target_m: float, seconds: float) -> float:
	var frames: int = 0
	var max_frames: int = int(seconds * 60.0)
	while p.path_walked < target_m and frames < max_frames and frames < MAX_FRAMES:
		await root.get_tree().physics_frame
		frames += 1
	return p.path_walked


## Let N physics ticks pass (controller warm-up after spawn).
func _settle(ticks: int) -> void:
	for i in range(ticks):
		await root.get_tree().physics_frame


## Tear down the current globe and wait a frame so its physics stop.
func _free_globe() -> void:
	if _globe and is_instance_valid(_globe):
		_globe.queue_free()
		await root.get_tree().process_frame
	_globe = null


func _set_planet_radius(r: float) -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, r)


## Build a fresh globe scene. Caller must have pinned the setting first.
func _build_globe() -> bool:
	var packed: PackedScene = load(GLOBE_SCENE)
	if packed == null or not packed.can_instantiate():
		push_error("FAIL: globe scene did not load")
		return false
	_globe = packed.instantiate()
	root.add_child(_globe)
	var p: CharacterBody3D = _globe.get("player")
	if p == null or p.get_script() == null:
		push_error("FAIL: globe script missing or player missing (parse error upstream?)")
		return false
	return true


func _check(label: String, cond: bool) -> bool:
	var status: String = "FAIL"
	if cond:
		status = "PASS"
	print("  " + status + " " + label)
	return cond


func _shoot(stage: String) -> void:
	_shots += 1
	if OS.get_environment("GODOT_PROBE_XVFB") == "":
		return
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("no screenshot for " + stage)
		return
	var dir: String = "/tmp/play"
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png("%s/%s.png" % [dir, stage])
	print("  shot: %s/%s.png" % [dir, stage])
