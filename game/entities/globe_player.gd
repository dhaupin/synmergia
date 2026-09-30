## GlobeWorldPlayer - radial-gravity CharacterBody3D (prd-spherical-mvp.md S3)
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
## (floating-origin rebase, see globe_world._maybe_shift_world), and
## ALL radial math here is done RELATIVE TO planet_center - never the
## world origin. planet_center is maintained by the globe scene.
##
## Tangent-frame conventions (planar-matching, verified):
##   north = pole direction projected onto the tangent plane
##   east  = north x up          (planar: north=-Z, up=+Y -> east=+X)
##   camera basis = Basis(east, up, -north)  (right-handed; camera
##   sits behind at +z local and looks along forward/north)
extends CharacterBody3D

class_name GlobeWorldPlayer

const GRAVITY_DEFAULT: float = 20.0
const WALK_SPEED_DEFAULT: float = 6.0
## Height of the collision-sphere center above the surface.
const SKIN: float = 1.0

## Radius of the sphere this player stands on (set by the globe scene).
var planet_radius: float = 100.0
## S12: the entity/book id this body belongs to (ScopeService resolves
## the local player's node by it; harmless on scripts that never join
## an instance).
var entity_id: String = ""
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
## Jump (play-day feedback #5): the same action the planar controller
## polls ("jump", touch JMP injects it). A real ballistic hop off the
## tangent plane; the radial snap only pins the body back when it is
## NOT above the surface (snap target = radius + skin + ground offset,
## so an airborne body at higher radius is left alone).
var jump_force: float = 7.0
## Movement Design System stamp: the anticheat ceiling for this body.
## Stamped at bind/ready like the planar controller does.
var allow_jump_input: bool = true
## S16.4: which world this body stands on ("" = the main world). Set
## through bind_to_world(); drives per-world gravity/speeds and the
## no-atmosphere glider gate.
var world_id: String = ""
## Set true by the probe to auto-walk forward (along the camera
## heading) without input. auto_walk_yaw is a look offset in radians
## the walk follows.
var auto_walk: bool = false
var auto_walk_yaw: float = 0.0
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

## Touch-look state (S14-web): the VirtualJoystick's camera_look feeds
## orbit_camera(); the pivot's basis is then re-derived from (yaw,
## pitch) every physics frame instead of the fixed north/east frame.
var look_yaw: float = 0.0
var look_pitch: float = 0.0
## Sane clamp: near +/-90 deg the pivot basis degenerates (east and
## north collapse); the planar camera clamps to similar bounds.
const LOOK_PITCH_LIMIT: float = 1.35 # ~77 deg

## Rotate the camera around the player (radians). Called by the touch
## HUD's camera_look (pixel deltas * sensitivity) and available to any
## other look source. Same sign convention as the planar
## ThirdPersonCamera.orbit: positive dx turns the view right (yaw
## decreases toward -north, matching Godot's -Z forward convention).
func orbit_camera(dx: float, dy: float) -> void:
	look_yaw -= dx
	look_pitch = clampf(look_pitch - dy, -LOOK_PITCH_LIMIT, LOOK_PITCH_LIMIT)


## Radial direction from the planet center to this body (local up).
## Anticheat glide-flag helper (defensive resolve; GM/spawn contexts
## without a limit stamp are no-ops there).
func _set_ac_gliding(gliding: bool) -> void:
	var ac = Engine.get_main_loop().root.get_node_or_null("AntiCheatService") if Engine.get_main_loop() is SceneTree else null
	if ac != null and ac.has_method("set_glide_active"):
		ac.set_glide_active(entity_id, gliding)


## Anticheat seam (S12.5): the radial body feeds the same movement
## validator the planar controller does, so the glide speed/fall
## ceilings are ENFORCED on the globe, not just declared. The launch
## ticket book (ThermalService -> grant_launch_grace) forgives the
## upward vector while an ancient launcher throws this body.
func _validate_movement() -> void:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return
	var ac = (ml as SceneTree).root.get_node_or_null("AntiCheatService")
	if ac != null and ac.has_method("validate_movement"):
		ac.validate_movement(entity_id, global_position, velocity, get_physics_process_delta_time())

func planet_up() -> Vector3:
	return (global_position - planet_center).normalized()


## Distance from the planet center to this body's collision center.
func planet_distance() -> float:
	return (global_position - planet_center).length()


## S12 scene swap: when true the player renders inside a PLANAR
## instance room (the InstanceContract), so radial math yields to the
## planar gravity + world-up contract. Set by ScopeService on swap;
## never touches the globe path when false (locked decision 3 holds:
## instances never change the globe's radial ground).
var planar_mode: bool = false

## S12 glider: the state machine lives in the frame primitive; this
## body feeds it altitude + up and applies its vertical speed. The
## deployment setting is fed by PlayerConfig ("auto"/"manual").
var glider = null  # GliderState (load-time assigned; frame primitive)
var _glide_up: Vector3 = Vector3.UP  # up vector captured per frame


## S16.4: bind this body to a lattice world. Per-world physics is a
## DECLARATION (WorldData.gravity_force), never a hard-coded number:
## the moon's 6 m/s^2 is a law of that globe, not a tweak. Only the
## world's gravity is adopted (walk_speed keeps its profile layer --
## species/profile modifiers stay authoritative for feel).
func bind_to_world(id: String) -> void:
	world_id = id
	if id == "" or id == "main":
		return
	var ws = Engine.get_main_loop().root.get_node_or_null("ScopeService") if Engine.get_main_loop() is SceneTree else null
	if ws == null or not ws.has_method("world_data"):
		return
	var w = ws.world_data(id)
	if w != null:
		gravity_force = float(w.gravity_force)


## S16.4: can this body's CURRENT world deploy a glider? No
## atmosphere = the wing stays stowed (WorldData.allows_gliding --
## "the wing is a wing"). Unknown/unbound worlds allow (the main
## world is the atmosphere world).
func _world_allows_gliding() -> bool:
	if world_id == "" or world_id == "main":
		return true
	var ws = Engine.get_main_loop().root.get_node_or_null("ScopeService") if Engine.get_main_loop() is SceneTree else null
	if ws == null or not ws.has_method("world_data"):
		return true
	var w = ws.world_data(world_id)
	return w == null or w.allows_gliding()

func _ready() -> void:
	if glider == null:
		glider = load("res://core/frame/srv/glider_state.gd").new()
	# Deployment setting: runtime resolve (script-mode/check-only has
	# no autoloads mounted).
	var pc = Engine.get_main_loop().root.get_node_or_null("PlayerConfig") if Engine.get_main_loop() is SceneTree else null
	if pc != null:
		var mode = pc.get_account_setting("glider_deployment", "auto")
		if mode != null:
			glider.deployment_mode = str(mode)
	# Anticheat stamp (the planar controller's law): the validator
	# needs a jump ceiling for this body or any hop reads as a hack.
	_call_deferred_stamp()

## Deferred stamp so entity_id is final (the planar controller's
## pattern). Defensive: missing AC is a no-op (deep script mode).
func _call_deferred_stamp() -> void:
	var ac = Engine.get_main_loop().root.get_node_or_null("AntiCheatService") if Engine.get_main_loop() is SceneTree else null
	if ac != null and ac.has_method("set_movement_limits"):
		ac.set_movement_limits(
			entity_id,
			walk_speed * 2.4,
			jump_force * 2.0,
			40.0
		)


func _physics_process(delta: float) -> void:
	if planar_mode:
		# Planar contract: -Y at InstanceContract.GRAVITY_FORCE, world up.
		up_direction = Vector3.UP
		var horizontal: Vector3 = velocity - Vector3.UP * velocity.dot(Vector3.UP)
		var vertical: Vector3 = velocity - horizontal
		var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var cam_dir: Vector3 = -global_transform.basis.z
		cam_dir.y = 0.0
		cam_dir = cam_dir.normalized() if cam_dir.length_squared() > 0.0001 else Vector3.FORWARD
		var right: Vector3 = cam_dir.cross(Vector3.UP).normalized()
		var wish: Vector3 = (cam_dir * -input_vec.y + right * input_vec.x)
		if wish.length() > 1.0:
			wish = wish.normalized()
		if wish.length_squared() > 0.0001:
			horizontal = horizontal.move_toward(wish * walk_speed, walk_speed * 8.0 * delta)
		else:
			horizontal = horizontal.move_toward(Vector3.ZERO, walk_speed * 10.0 * delta)
		vertical -= Vector3.DOWN * gravity_force * delta
		velocity = horizontal + vertical
		move_and_slide()
		return
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

	# Camera heading on the tangent plane. The pivot's basis is rebuilt
	# every physics frame at the bottom of this function, so read the
	# PREVIOUS frame's basis here (one-frame lag; same as the planar
	# controller reading the camera in _physics_process). Forward is
	# the projected camera forward, right the projected camera right.
	var cam_fwd: Vector3 = north
	var cam_right: Vector3 = east
	var pivot: Node3D = get_node_or_null("CameraPivot")
	if pivot:
		var f: Vector3 = -pivot.global_transform.basis.z
		var r: Vector3 = pivot.global_transform.basis.x
		# Project onto the tangent plane (drop the radial component);
		# at extreme pitch the projected forward collapses toward zero,
		# then the compass frame keeps movement sane.
		var fp: Vector3 = f - up * f.dot(up)
		var rp: Vector3 = r - up * r.dot(up)
		if fp.length_squared() > 0.000001:
			cam_fwd = fp.normalized()
		if rp.length_squared() > 0.000001:
			cam_right = rp.normalized()

	var wish: Vector3 = Vector3.ZERO
	if auto_walk:
		# Probe/automation walk: follow the camera heading rotated by
		# auto_walk_yaw (0 = straight ahead).
		var dir: Vector3 = cam_fwd.rotated(up, auto_walk_yaw)
		wish = (dir - up * dir.dot(up)).normalized()
	else:
		# Touch stick feeds the same pipeline as WASD: InputManager merges
		# controller > touch joystick > keyboard into one vector. Input is
		# CAMERA-RELATIVE like the planar controller: forward walks where
		# you look, so orbiting the view re-aims movement (walking used to
		# pin to map north/east regardless of where the camera pointed,
		# which read as "stuck" against invisible walls while circling).
		var input_vec: Vector2 = InputManager.get_movement_input() if InputManager \
			else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wish = cam_fwd * (-input_vec.y) + cam_right * input_vec.x
	if wish.length() > 1.0:
		wish = wish.normalized()

	var horizontal: Vector3 = velocity - up * velocity.dot(up)
	var vertical: Vector3 = velocity - horizontal

	# Jump: the same "jump" action the planar controller and the touch
	# JMP button feed. Fires only while surface contact holds (the glue
	# snap means is_on_floor() is always true at rest -- gate on radial
	# speed so a hop is never re-fired mid-air).
	if allow_jump_input and is_on_floor() \
			and Input.is_action_just_pressed("jump"):
		vertical += up * jump_force
		snap_enabled = false

	# S12 glider: feed the state machine (altitude above the surface,
	# no thermal model on the globe yet -- thermal zones land later),
	# then apply its vertical speed instead of raw gravity.
	if glider != null:
		var altitude: float = global_position.distance_to(planet_center) - planet_radius - ground_offset
		var gstate: int = glider.tick(delta, maxf(altitude, 0.0), 0.0)
		# S16.4 vacuum rule: no atmosphere, no wing. If the machine
		# opened the wing over an airless world, the vacuum closes it
		# the same frame -- the body falls honestly.
		if gstate == glider.State.GLIDING and not _world_allows_gliding():
			glider.state = glider.State.FALLING
			gstate = glider.State.FALLING
		if gstate == glider.State.GLIDING:
			_glide_up = up
			var ac = Engine.get_main_loop().root.get_node_or_null("AntiCheatService") if Engine.get_main_loop() is SceneTree else null
			if ac != null and ac.has_method("set_glide_active"):
				ac.set_glide_active(entity_id, true)
			# S12.5 sky roads: sample the thermal book; updrafts reduce
			# the sink (a launcher bursts you up the column).
			var lift: float = 0.0
			var ts = Engine.get_main_loop().root.get_node_or_null("ThermalService") if Engine.get_main_loop() is SceneTree else null
			if ts != null:
				# entity_id passed through: an ancient launcher ride grants
				# this body's anticheat book a launch ticket (server-side;
				# the 30+ m/s throw is the world throwing you, not a hack).
				lift = ts.sample(global_position, entity_id)
				ts.record_glide_tick(entity_id, velocity.length() * delta, altitude)
			var sink: Vector3 = up * glider.glide_vertical_speed(clampf(lift / 3.0, 0.0, 1.0))
			var glide_wish: Vector3 = wish if wish.length_squared() > 0.0001 \
				else (north if true else Vector3.ZERO)
			var forward: Vector3 = (glide_wish.normalized() if glide_wish.length_squared() > 0.0001 else -up.cross(Vector3(0, 0, 1)).normalized()) \
				* glider.glide_forward_speed(0.0)
			horizontal = horizontal.move_toward(forward, walk_speed * 4.0 * delta)
			# Launchers throw: a positive lift burst overrides the sink
			# entirely while inside the launch column.
			if lift > 0.0:
				vertical = vertical.move_toward(up * lift, gravity_force * 6.0 * delta)
			else:
				vertical = vertical.move_toward(-sink, gravity_force * 2.0 * delta)
			velocity = horizontal + vertical
			move_and_slide()
			_validate_movement()
			return
		if is_on_floor():
			glider.on_grounded()
			_set_ac_gliding(false)
		elif vertical.dot(up) < 0.0 or wish.length_squared() > 0.0001:
			glider.on_airborne()

	# Accelerate along the tangent plane, gravity toward the center.
	if wish.length_squared() > 0.0001:
		horizontal = horizontal.move_toward(wish * walk_speed, walk_speed * 8.0 * delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, walk_speed * 10.0 * delta)
	vertical -= up * gravity_force * delta

	velocity = horizontal + vertical
	var before: Vector3 = global_position
	move_and_slide()
	_validate_movement()
	path_walked += global_position.distance_to(before)

	# Snap to the surface: cancel residual radial drift so the body
	# rides the surface exactly (probe asserts this stays true). The
	# snap provider (rock tops, S7) lifts the target ride height.
	# IMPORTANT: the lift is applied EXACTLY, never lerped - the cap
	# profile is already smooth in space, and a lagged lift lets the
	# body intersect rock colliders and stall (test-caught lesson).
	# A JUMP disables the snap until the body falls back to contact
	# (radial velocity <= 0 and at/below the surface again), so the
	# hop is a real ballistic arc, not a teleport back to the ground.
	if snap_enabled:
		var target_r: float = planet_radius + ground_offset + SKIN
		if snap_height_provider.is_valid():
			_ride_lift = snap_height_provider.call(global_position)
			target_r += _ride_lift
		var err: float = planet_distance() - target_r
		if abs(err) > 0.001:
			global_position = planet_center + (global_position - planet_center).normalized() * target_r
	elif vertical.dot(up) <= 0.0 and planet_distance() <= planet_radius + ground_offset + SKIN + 0.05:
		snap_enabled = true

	# Keep the camera pivot aligned with local up, then apply the
	# look orbit (yaw around local up, pitch around local east). With no
	# look input yet this reproduces the original fixed frame exactly.
	if pivot:
		var xform: Transform3D = pivot.global_transform
		xform.basis = Basis(east, up, -north)
		xform.basis = xform.basis.rotated(up, look_yaw)
		xform.basis = xform.basis.rotated(xform.basis.x, look_pitch)
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
