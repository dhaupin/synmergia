## probe_long_walk - the "invisible wall" regression.
## Boots the 20 km globe and walks the body along a great circle, then
## raycasts the live collision under the body and a little ahead of it,
## asserting the collided ground matches the walk-surface law at every
## step. The flat collision disc that used to stand in for the ground
## stopped the walk dead at ~500 m wherever the analytic walk surface rose
## faster than the disc; the terrain-conforming surface pad
## (globe_world._update_surface_pad) removed it, so collision == the drawn
## ground everywhere the player can stand.
## Run headless: godot --headless --path . --script res://tests/probe_long_walk.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"
const RADIUS := 20000.0
const TARGET_M := 1200.0
const STEP_M := 8.0
## The drawn ground is the walk law lifted by the clipmap tile lift
## (globe_world.TILE_LIFT); the pad rides that same lift, so the
## probe compares collision against walk_law + lift.
const TILE_LIFT := 0.52
## Collision may only differ from the drawn ground by the pad grid's linear
## interpolation error: tight at the pad centre (a real vertex), looser at
## a point between grid rings.
const CENTER_TOL_M := 0.35
const AHEAD_TOL_M := 2.5
const AHEAD_M := 20.0

var _globe: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var packed: PackedScene = load(GLOBE_SCENE)
	_globe = packed.instantiate()
	root.add_child(_globe)
	for _i in range(6):
		await process_frame
	for _i in range(60):
		await root.get_tree().physics_frame

	var clipmap = _globe.get("clipmap")
	var player: CharacterBody3D = _globe.get("player")
	var pad: StaticBody3D = _globe.get("surface_pad")
	var space := _globe.get_world_3d().direct_space_state
	var center: Vector3 = _globe.get("planet_center")

	var up: Vector3 = (player.global_position - center).normalized()
	var tangent: Vector3 = Vector3(0.0, 1.0, 0.0).cross(up).normalized()
	var axis: Vector3 = up.cross(tangent).normalized()

	var s := 0.0
	var max_err_center := 0.0
	var max_err_ahead := 0.0
	var misses := 0
	while s < TARGET_M:
		tangent = tangent.rotated(axis, STEP_M / RADIUS).normalized()
		player.global_position += tangent * STEP_M
		await root.get_tree().physics_frame
		center = _globe.get("planet_center")
		s += STEP_M
		var pd: Vector3 = (player.global_position - center).normalized()
		var e_c := _collide_err(space, center, pd, clipmap, pad, player)
		var pd_ahead: Vector3 = pd.rotated(axis, AHEAD_M / RADIUS)
		var e_a := _collide_err(space, center, pd_ahead, clipmap, pad, player)
		if e_c == -1.0 or e_a == -1.0:
			misses += 1
		if e_c >= 0.0:
			max_err_center = maxf(max_err_center, e_c)
		if e_a >= 0.0:
			max_err_ahead = maxf(max_err_ahead, e_a)

	var ok := true
	if misses > 0:
		push_error("probe_long_walk: %d/%d samples had no collision under the walk" % [misses, int(TARGET_M / STEP_M)])
		ok = false
	if max_err_center > CENTER_TOL_M:
		push_error("probe_long_walk: collision vs walk law error at pad centre %.2f m (tol %.2f)" % [max_err_center, CENTER_TOL_M])
		ok = false
	if max_err_ahead > AHEAD_TOL_M:
		push_error("probe_long_walk: collision vs walk law error ahead %.2f m (tol %.2f)" % [max_err_ahead, AHEAD_TOL_M])
		ok = false
	print("LONG-WALK %s: %.0f m walked, misses=%d, err centre %.2f m, err ahead %.2f m" % [
		"PASS" if ok else "FAIL", s, misses, max_err_center, max_err_ahead])
	_globe.queue_free()
	await process_frame
	quit(0 if ok else 1)


## Raycast straight down at `dir` and return |collision_radius - walk_law|
## for the SURFACE PAD only, or -1.0 when the ray misses. Rocks and props
## legitimately sit above the walk law (walk-over caps), so a hit on any
## collider that is not the pad is reported as -2.0 and ignored.
func _collide_err(space: PhysicsDirectSpaceState3D, center: Vector3, dir: Vector3, clipmap, pad: StaticBody3D, player: CharacterBody3D) -> float:
	var from: Vector3 = center + dir * (RADIUS + 120.0)
	var to: Vector3 = center + dir * (RADIUS - 60.0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = pad.collision_layer
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -1.0
	if hit["collider"] != pad:
		return -2.0
	var got: float = (hit["position"] as Vector3).distance_to(center) - RADIUS
	var want: float = clipmap.walk_surface_h(dir) + TILE_LIFT
	return absf(got - want)
