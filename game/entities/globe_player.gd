## GlobeIslandPlayer - radial-gravity CharacterBody3D (prd-spherical-mvp.md S3)
## Prototype-only: up_direction is the surface normal every physics
## frame and gravity pulls toward the planet center. Live movement uses
## the MovementProfile schema values (gravity_force / walk_speed),
## consistent with the movement profile system.
##
## S8 FLOATING ORIGIN: at planet scale (R = 20 km) a CharacterBody at
## world magnitude ~20000 stalls: the body's OWN float32 transform
## precision degenerates horizontal locomotion (experiment: walks
## freely at |r| = 200, stalls at |r| >= ~5000, ON A PERFECT LOCAL
## FLOOR). So the scene shifts the whole world back around the player
## (floating-origin rebase, see globe_island._maybe_shift_world), and
## ALL radial math here is done RELATIVE TO planet_center - never the
## world origin. planet_center is maintained by the globe scene.
##
## Tangent-frame conventions (planar-matching, verified):
##   north = pole direction projected onto the tangent plane
##   east  = north x up          (planar: north=-Z, up=+Y -> east=+X)
##   camera basis = Basis(east, up, -north)  (right-handed; camera
##   sits behind at +z local and looks along forward/north)
extends CharacterBody3D

class_name GlobeIslandPlayer

const GRAVITY_DEFAULT: float = 20.0
const WALK_SPEED_DEFAULT: float = 6.0
## Height of the collision-sphere center above the surface.
const SKIN: float = 1.0

## Radius of the sphere this player stands on (set by the globe scene).
var planet_radius: float = 100.0
## S8: world-space position of the PLANET CENTER. The scene keeps the
## PLAYER near the world origin (floating origin); the planet moves.
## All radial quantities derive from (global_position - planet_center).
var planet_center: Vector3 = Vector3.ZERO
## S8: height of the WALKABLE SURFACE above planet_radius. Zero for
## the bare shell; the streamed patch tiles sit TILE_LIFT (0.52) above
## it, so a streaming globe sets this and every height that matters
## (snap target, glue check, spawn) is measured from the surface the
## player actually stands on. One reference, no per-system drift.
var ground_offset: float = 0.0

var walk_speed: float = WALK_SPEED_DEFAULT
var gravity_force: float = GRAVITY_DEFAULT
## Set true by the probe to auto-walk eastward without input.
var auto_walk: bool = false
## Optional provider: func(dir: Vector3) -> float, height above the
## base surface at that direction (rock tops). The radial snap rides
## rock tops smoothly so walk-over colliders decorate, not block.
var snap_height_provider: Callable = Callable()
## Diagnostic (S8): when false the radial surface snap is skipped and
## gravity still pulls, so the probe can separate snap interaction
## from raw contact physics. Default true = unchanged behavior.
var snap_enabled: bool = true

var _surface_normal: Vector3 = Vector3.UP
## Accumulated path length (for the probe's curvature assertion).
var path_walked: float = 0.0
var _loop_start: Vector3 = Vector3.ZERO
## Smoothed ride height above the base shell (rock walk-over).
var _ride_lift: float = 0.0


## Radial direction from the planet center to this body (local up).
func planet_up() -> Vector3:
	return (global_position - planet_center).normalized()


## Distance from the planet center to this body's collision center.
func planet_distance() -> float:
	return (global_position - planet_center).length()


func _physics_process(delta: float) -> void:
	var up: Vector3 = planet_up()
	_surface_normal = up
	up_direction = up

	# True-north tangent: project the +Y pole direction onto the
	# tangent plane. Degenerate only at the poles; fall back to the
	# -Z hint there (compass-at-pole semantics, spherical PRD sec 5.3).
	var pole_hint: Vector3 = Vector3(0, 1, 0)
	if abs(up.dot(pole_hint)) > 0.999:
		pole_hint = Vector3(0, 0, -1)
	var north: Vector3 = (pole_hint - up * pole_hint.dot(up)).normalized()
	var east: Vector3 = north.cross(up)

	var wish: Vector3 = Vector3.ZERO
	if auto_walk:
		wish = east
	else:
		var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wish = east * input_vec.x + north * (-input_vec.y)
	if wish.length() > 1.0:
		wish = wish.normalized()

	var horizontal: Vector3 = velocity - up * velocity.dot(up)
	var vertical: Vector3 = velocity - horizontal

	# Accelerate along the tangent plane, gravity toward the center.
	if wish.length_squared() > 0.0001:
		horizontal = horizontal.move_toward(wish * walk_speed, walk_speed * 8.0 * delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, walk_speed * 10.0 * delta)
	vertical -= up * gravity_force * delta

	velocity = horizontal + vertical
	var before: Vector3 = global_position
	move_and_slide()
	path_walked += global_position.distance_to(before)

	# Snap to the surface: cancel residual radial drift so the body
	# rides the surface exactly (probe asserts this stays true). The
	# snap provider (rock tops, S7) lifts the target ride height.
	# IMPORTANT: the lift is applied EXACTLY, never lerped - the cap
	# profile is already smooth in space, and a lagged lift lets the
	# body intersect rock colliders and stall (test-caught lesson).
	if snap_enabled:
		var target_r: float = planet_radius + ground_offset + SKIN
		if snap_height_provider.is_valid():
			_ride_lift = snap_height_provider.call(global_position)
			target_r += _ride_lift
		var err: float = planet_distance() - target_r
		if abs(err) > 0.001:
			global_position = planet_center + (global_position - planet_center).normalized() * target_r

	# Keep the camera pivot aligned with local up.
	var pivot: Node3D = get_node_or_null("CameraPivot")
	if pivot:
		var xform: Transform3D = pivot.global_transform
		xform.basis = Basis(east, up, -north)
		pivot.global_transform = xform


## Surface normal at the player (probe helper).
func get_surface_normal() -> Vector3:
	return _surface_normal


## True when the player is glued to the walk surface (probe helper).
func is_glued(tolerance: float = 0.5) -> bool:
	return abs(planet_distance() - (planet_radius + ground_offset + SKIN)) <= tolerance


## Curvature signature: a closed equator loop walks 2*pi*R but ends
## near the start, so walked distance far exceeds straight-line
## displacement. On a flat plane the ratio approaches ~1.0.
func walked_curvature_ratio() -> float:
	var displacement: float = _loop_start.distance_to(global_position)
	if displacement < 0.001:
		return INF
	return path_walked / displacement


## Mark the start of a measured loop (probe helper).
func begin_loop() -> void:
	_loop_start = global_position
	path_walked = 0.0
