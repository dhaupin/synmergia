## Planet-scale probe, CHUNK 1 of 3 (the 100 m control walk)
## Carved from probe_planet_scale_20km.gd (prd-spherical-mvp.md S8)
## to keep each chunk inside the sandbox/CI wall-clock. This chunk
## pins prototype radius STA A: 100 m globe, snap on, walk 30 m. The
## baseline proves the radial-snap walker works at prototype scale on
## the megasphere shell (the planar prototype is gone). The 20 km
## chunks: probe_planet_walk_20km.gd (chunks B+C) and
## probe_planet_rebase_20km.gd (stage D+E).
## Walk metric: ARC distance (acos(dot(start_dir,end_dir)) * R) -- the
## honest metric at 20 km (path_walked counts vertical jitter/fall).
## Run headless:   godot --headless --path . --script res://tests/probe_planet_control_100m.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"
const PLANET_RADIUS_100: float = 100.0
## Walk surface above the base shell when streaming (mirrors the
## scene's TILE_LIFT / clipmap.TILE_LIFT).
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

	# ---- Stage A: 100 m control walk --------------------------------
	_set_planet_radius(PLANET_RADIUS_100)
	if not _build_globe():
		quit(1)
		return
	var pA: CharacterBody3D = _globe.get("player")
	pA.begin_loop()
	pA.auto_walk = true
	var walkedA: float = await _walk_until(pA, WALK_TARGET_M, WALK_SECONDS)
	pA.auto_walk = false
	ok = _check("control: 100 m walk reaches ~30 m (got %.1f)" % walkedA, \
		walkedA >= WALK_TARGET_M * 0.8) and ok
	ok = _check("control: glued after walk", pA.is_glued(0.5)) and ok
	ok = _check("control: megasphere collider DISABLED at every scale (surface pad is physics truth)", \
		_globe.shell_col.disabled) and ok
	ok = _check("control: surface pad built at every scale (planar mode removed)", \
		_globe.surface_pad != null) and ok
	await _free_globe()

	# THE VERDICT-AND-EXIT LAW: the green path used to fall through this
	# guard and NEVER call quit(), so a passing run left the tree alive
	# until the engine died at teardown (exit 139, no verdict line).
	if ok:
		print("PLANET CONTROL PROBE: ALL PASS")
	else:
		push_error("PLANET CONTROL PROBE FAILED")
	quit(0 if ok else 1)


## Walk with auto_walk until target meters or the wall-clock cap.
## Returns the walked distance. Bounded: exits after MAX_FRAMES.
func _walk_until(p: CharacterBody3D, target_m: float, seconds: float) -> float:
	var frames: int = 0
	var max_frames: int = int(seconds * 60.0)
	while p.path_walked < target_m and frames < max_frames and frames < MAX_FRAMES:
		await root.get_tree().physics_frame
		frames += 1
	return p.path_walked


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
