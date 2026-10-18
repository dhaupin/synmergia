## Planet-scale probe, CHUNK 2 of 3 (20 km walks, snap ON and OFF)
## Carved from probe_planet_scale_20km.gd (prd-spherical-mvp.md S8)
## to keep each chunk inside the sandbox/CI wall-clock. This chunk
## proves the S8 fix on the two 20 km walk stages: the floating
## origin + re-anchored surface pad. Original stage B: 20 km globe,
## snap on, walk 30 m. Spawn sits on the walk surface
## (R + TILE_LIFT + SKIN = 20001.52); the megasphere collider is
## DISABLED at planet scale and the re-anchored surface pad is the
## physics truth (S8 fix). Original stage C: 20 km globe, snap OFF.
## The pad alone must hold the body against gravity AND allow free
## walking. Pre-fix stage C FAILED past R ~5 km (body-magnitude
## float32 degeneracy). Siblings: probe_planet_control_100m.gd
## (chunk 1) and probe_planet_rebase_20km.gd (chunk 3, stage D+E).
## Walk metric: ARC distance (acos(dot(start_dir,end_dir)) * R) -- the
## honest metric at 20 km (path_walked counts vertical jitter/fall).
## Run headless:   godot --headless --path . --script res://tests/probe_planet_walk_20km.gd
## Run rendered:   GODOT_PROBE_XVFB=1 xvfb-run -a godot --path . --script res://tests/probe_planet_walk_20km.gd
##   -> writes /tmp/play/planet_stageB.png
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"
const PLANET_RADIUS_20KM: float = 20000.0
## Walk surface above the base shell when streaming (mirrors the
## scene's STREAMER_TILE_LIFT / streamer.TILE_LIFT).
const TILE_LIFT: float = 0.52
## Walk target and wall-clock frame caps (headless ticks ~60 Hz).
const WALK_TARGET_M: float = 30.0
const WALK_SECONDS: float = 8.0
const MAX_FRAMES: int = 600

var _globe: Node3D
var _shots := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	# Terrain arc (v2): the walk surface rides the seeded heightfield.
	# Surface expectations below add the TERRAIN LAW value at the body's
	# direction (the same law the scene's pad and snap provider ride).
	var Gen: GDScript = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()

	_set_planet_radius(PLANET_RADIUS_20KM)

	# ---- Stage B: 20 km, snap ON (the fixed walk) -------------------- 
	if not _build_globe():
		quit(1)
		return
	var pB: CharacterBody3D = _globe.get("player")
	pB.snap_enabled = true
	await _settle(2)
	# Terrain law at the spawn direction (the plaza is flat at
	# SPAWN_HEIGHT, so the constant read is exact).
	var spawn_dir_b: Vector3 = (pB.global_position - _globe.planet_center).normalized()
	var spawn_terrain_b: float = Gen.terrain_height(spawn_dir_b, seed_b)
	var spawn_r: float = pB.planet_distance()
	ok = _check("20km: spawned on walk surface (r=%.2f m)" % spawn_r, \
		abs(spawn_r - (PLANET_RADIUS_20KM + TILE_LIFT + spawn_terrain_b + 1.0)) < 0.5) and ok
	ok = _check("20km: megasphere collider disabled at planet scale", \
		_globe.shell_col.disabled) and ok
	ok = _check("20km: surface pad live (planet-scale ground truth)", \
		_globe.surface_pad != null) and ok
	# The spawn itself (20 km out) triggers one rebase on frame 1; the
	# player then sits ~60 m from the world origin (the gap between the
	# moved planet center and the walk surface). Assert the rebase ran.
	ok = _check("20km: spawn rebase ran (got %d)" % _globe.scene_shift_count, \
		_globe.scene_shift_count == 1) and ok
	ok = _check("20km: body near origin post-rebase (|r|=%.1f)" % pB.global_position.length(), \
		pB.global_position.length() < 150.0) and ok
	var shiftsB: int = _globe.scene_shift_count
	pB.begin_loop()
	pB.auto_walk = true
	var walkedB: float = await _walk_until(pB, WALK_TARGET_M, WALK_SECONDS)
	pB.auto_walk = false
	var arcB: float = _arc(pB._loop_start, pB.global_position, _globe.planet_center)
	print("  info: 20km walk = %.2f m (arc %.2f m) in %.1f s" % [walkedB, arcB, WALK_SECONDS])
	ok = _check("20km: walks freely (got %.1f m)" % walkedB, \
		walkedB >= WALK_TARGET_M * 0.8) and ok
	ok = _check("20km: arc distance tracks walked path (%.1f m arc)" % arcB, \
		arcB >= WALK_TARGET_M * 0.5 and arcB <= WALK_TARGET_M * 1.5) and ok
	ok = _check("20km: glued after walk", pB.is_glued(2.0)) and ok
	ok = _check("20km: no rebase during a 30 m walk (got %d)" % _globe.scene_shift_count, \
		_globe.scene_shift_count == shiftsB) and ok
	_shoot("planet_stageB")
	await _free_globe()

	# ---- Stage C: 20 km, snap OFF (no snap crutch) ------------------
	# The surface pad alone must hold the body AND allow free walking.
	# Pre-fix this stage FAILED: the megasphere contact could not
	# support the 1 m body (|v_r| sank ~2.7 m/s through the shell).
	if not _build_globe():
		quit(1)
		return
	var pC: CharacterBody3D = _globe.get("player")
	pC.snap_enabled = false
	await _settle(2)
	# The pad must hold the body at the TERRAIN surface. The walk runs
	# WITHIN the flat spawn plaza (20 m; the plaza is SPAWN_HEIGHT
	# everywhere, so a single terrain read is exact for the stage).
	var spawn_dir_c: Vector3 = (pC.global_position - _globe.planet_center).normalized()
	var spawn_terrain_c: float = Gen.terrain_height(spawn_dir_c, seed_b)
	pC.begin_loop()
	pC.auto_walk = true
	var walkedC: float = await _walk_until(pC, 20.0, WALK_SECONDS)
	pC.auto_walk = false
	var radial_v: float = pC.velocity.dot(pC.planet_up())
	var rC: float = pC.planet_distance()
	print("  info: 20km snap-OFF walk = %.2f m (arc %.2f), |v_r| = %.3f m/s" % \
		[walkedC, _arc(pC._loop_start, pC.global_position, _globe.planet_center), radial_v])
	ok = _check("20km: snap-OFF walks freely (got %.1f m)" % walkedC, \
		walkedC >= 20.0 * 0.8) and ok
	ok = _check("20km: snap-OFF does not sink (|v_r|=%.3f)" % radial_v, \
		abs(radial_v) < 0.5) and ok
	ok = _check("20km: snap-OFF stays on surface (r=%.1f)" % rC, \
		abs(rC - (PLANET_RADIUS_20KM + TILE_LIFT + spawn_terrain_c + 1.0)) < 3.0) and ok
	await _free_globe()

	if not ok:
		push_error("PLANET 20KM WALK PROBE FAILED")
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
