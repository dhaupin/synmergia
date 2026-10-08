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
## R45 saddle: the humanoid laws restored on dismount (the body's own
## defaults -- captured indirections, not invented numbers).
const WALK_SPEED_HUMANOID: float = WALK_SPEED_DEFAULT
const JUMP_FORCE_HUMANOID: float = 7.0
## The saddle's sprint gear: the body runs the mount's sprint through
## this low ratio (the ANTICHEAT ceiling stays the full profile stamp
## x2.5 -- the body can never outride its legal ceiling).
const SADDLE_SPRINT_SCALE: float = 0.6

## Radius of the sphere this player stands on (set by the globe scene).
var planet_radius: float = 100.0
## S12: the entity/book id this body belongs to (ScopeService resolves
## the local player's node by it; harmless on scripts that never join
## an instance).
var entity_id: String = ""
## This body's inventory bag (round 7: the globe world had no bag at
## all -- the starter kit had nothing to land in and panels rendered
## empty). Created + registered in _setup_inventory_bag().
var _inventory_bag = null
## Same bag under the name the planar controller exposes. UI resolvers
## (character_panel._resolve_inventory) duck-type this property; the
## globe body only had _inventory_bag, so the panel's player-node
## fallback missed the bag it was standing on.
var inventory_component = null
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

## Play-day feedback: BOTW-STYLE CLIMBING. Hold jump against a steep
## or climbable face (big rocks, trees, future features) to grab it;
## climb while held; stamina drains while grabbing and regenerates on
## the ground. Tapping jump stays a hop -- the climb engages on HOLD.
const CLIMB_STAMINA_MAX: float = 6.0
const CLIMB_DRAIN_PER_S: float = 1.0
const CLIMB_REGEN_PER_S: float = 2.0
const CLIMB_SPEED: float = 2.2
const CLIMB_REACH: float = 1.7
const CLIMB_MIN_ANGLE_DEG: float = 50.0
const CLIMB_WALL_GROUP := "climbable"
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
## PERCH LAW: a walk-over cap this high above the terrain law is a
## climbable ledge (step off = airborne; the climb grabs it).
const PERCH_MIN_LIFT: float = 0.55
var climb_stamina: float = CLIMB_STAMINA_MAX
var _climbing: bool = false
var _climb_wall_normal: Vector3 = Vector3.ZERO

## -- CROUCH / SLIDE / SPRINT (terrain arc; terrain mobility law) -----
## Crouch: a TOGGLE (tap CRH / C) -- the Q-dodge lane is free on
## desktop and the touch CRH button is a tap. While crouched the walk
## speed drops and steep downhill faces become slide ground.
## Slide: crouch WHILE SPRINTING on a slope = a momentum slide that
## carries you down the fall line with steering, then it runs out.
## Sprint: hold SHIFT (or the stick-full auto-sprint the touch HUD
## already drives via sprint_override) -- SPRINT_MULT over walk speed
## while the stamina pool has reserve.
var is_crouching: bool = false
var is_sprinting: bool = false
var is_sliding: bool = false
var _slide_t: float = 0.0
var _slide_dir: Vector3 = Vector3.ZERO
const CROUCH_MULT: float = 0.5
const SPRINT_MULT: float = 1.55
const SLOPE_WALK_MULT: float = 0.55
const SLOPE_WALK_SIN: float = 0.55
const SLIDE_INIT_SPEED: float = 8.5
const SLIDE_MIN_SPEED: float = 3.0
const SLIDE_FRICTION: float = 3.5
const SLOPE_SLIDE_SIN: float = 0.55
## Terrain slope law: the surface tilt at the body's direction (0 on
## flat ground, 1 on a wall). Feeds walk slowdown and slide engage.
var _terrain_slope: float = 0.0
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

## Collision-bit law (round 10): named bits from the LayerProfile
## (data/physics_layers/), no magic numbers at the physics calls.
const Layers = preload("res://core/schemas/layer_profile.gd")

var _surface_normal: Vector3 = Vector3.UP
## Accumulated path length (for the probe's curvature assertion).
var path_walked: float = 0.0
var _loop_start: Vector3 = Vector3.ZERO
## Smoothed ride height above the base shell (rock walk-over).
var _ride_lift: float = 0.0
## Terrain slope (cos of the slope angle, 1 = flat) this frame.
var _slope_cos: float = 1.0
## Touch auto-sprint mirror (VirtualJoystick.sprint_override).
var _sprint_override_on: bool = false
## Surface slope at the body's direction this frame (cos of the slope
## angle; 1 on flat ground). The glue check adds the slope ramp:
## walking uphill puts the snap target a head above the surface --
## still glued while the slope is walkable.

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

# R45 saddle: the riding layer (labs/prd-mounts.md sec 9). The body
# listens to RideService's summon/dismiss signals and adopts the
# mount's movement laws the way bind_to_world adopts a world's
# gravity -- a DECLARATION from the resolved MovementProfile, never a
# number invented here. While mounted: profile walk/sprint/jump/gravity
# replace the humanoid's, a saddle lift rides the body above the
# surface law, and the cliff law (fall_stamp_for) is fed per tick.
var ride_service = null                 # RideService (runtime; null in tests)
var mounted_mount_id: String = ""       # the mount's data id ("" = unmounted)
var _mount_profile = null               # the resolved MovementProfile
var _humanoid_gravity: float = -1.0     # pre-mount gravity, restored on dismount
const SADDLE_LIFT: float = 0.4          # m above the surface law (hooves, not boots)
# R46 camera-follow setup: the mount camera pulls back so the beast
# fits the frame. The seat is applied only when the pivot still
# carries the walk rig's code-built camera position (a world scene
# that places its own camera keeps it).
const CAMERA_SEAT: Vector3 = Vector3(0, 2.2, 4.5)
const MOUNT_CAMERA_SEAT: Vector3 = Vector3(0, 3.4, 7.0)


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


## -- R45 saddle: the mount's laws, adopted and handed back ------------

## The riding layer whistled: adopt the mount's movement laws from its
## resolved MovementProfile (the same ONE derivation RideService
## stamps the anticheat with). Only the profile's laws are adopted --
## walk/sprint/jump/gravity; the body's radial ground law, snap chain,
## and camera frame are untouched (the mount rides THIS body, it does
## not replace it).
func _on_mount_summoned(player_id: String, mount_id: String) -> void:
	if entity_id != player_id or ride_service == null:
		return
	var mount = ride_service.active_mount(player_id)
	if mount == null or DataService == null:
		return
	var profile = DataService.get_mount_movement_profile(mount)
	if profile == null:
		return
	_mount_profile = profile
	mounted_mount_id = str(mount_id)
	if _humanoid_gravity < 0.0:
		_humanoid_gravity = gravity_force
	walk_speed = float(profile.walk_speed)
	jump_force = float(profile.jump_force)
	gravity_force = float(profile.gravity_force)
	GameLog.info("GlobeWorldPlayer: %s takes the saddle of the %s" % [entity_id, str(mount.display_name)])


## Back to the whistle: restore the humanoid laws the body carried
## before the saddle (captured at adoption -- even the per-world
## gravity bind_to_world declared survives a mount round trip).
func _on_mount_dismounted(player_id: String, mount_id: String) -> void:
	if entity_id != player_id or not mounted_mount_id.is_empty() and mounted_mount_id != mount_id:
		return
	_mount_profile = null
	mounted_mount_id = ""
	if _humanoid_gravity >= 0.0:
		gravity_force = _humanoid_gravity
		_humanoid_gravity = -1.0
	walk_speed = WALK_SPEED_HUMANOID
	jump_force = JUMP_FORCE_HUMANOID


## True while a mount is under this body (drives the saddle lift,
## the speed scale, and the dismount tap).
func is_mounted() -> bool:
	return not mounted_mount_id.is_empty() and _mount_profile != null


## True while the player is typing into a text control (chat input,
## admin shell, settings fields). Raw Input polling leaks every key --
## including the dismount key -- so the saddle poll must respect the
## same text-entry law the event pipeline uses (InputManager's
## `_is_text_entry_focused` idiom, mirrored here for --script tests).
func _text_entry_focused() -> bool:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return false
	var focus: Control = (loop as SceneTree).root.gui_get_focus_owner()
	if focus == null:
		return false
	return focus is LineEdit or focus is TextEdit or focus is CodeEdit


## The mount's sprint law, resolved here (the body has no sprint
## profile field): profile sprint (0 = the body cannot sprint on this
## mount) x the saddle's low-gear scale. The anticheat is stamped by
## RideService with the FULL profile sprint x2.5, so the body can
## never outride its legal ceiling.
func mount_sprint_speed() -> float:
	if not is_mounted():
		return 0.0
	return float(_mount_profile.sprint_speed) * SADDLE_SPRINT_SCALE


## The cliff law, fed per tick from the body (the surface data the
## service has no other way to know: airborne + radial altitude).
## A bail is EXECUTED here -- the body has already inherited the
## humanoid laws through the dismount signal by the time this
## returns, and the rider keeps the fall (the mount never falls).
func _feed_mount_fall_law(delta: float, up: Vector3, falling: bool, altitude: float) -> void:
	if not is_mounted() or ride_service == null:
		return
	var stamp: Dictionary = ride_service.fall_stamp_for(entity_id, falling, altitude)
	if str(stamp.get("action", "")) == "bail":
		velocity = horizontal_only(velocity, up) * 0.5 + up * -1.0


## Radial altitude above the surface law (the same number the glider
## branch feeds its state machine).
func _radial_altitude(up: Vector3) -> float:
	var altitude: float = planet_distance() - (planet_radius + ground_offset + SKIN)
	if snap_height_provider.is_valid():
		altitude -= snap_height_provider.call(global_position)
	return maxf(altitude, 0.0)


## Horizontal component of a velocity on the tangent plane.
func horizontal_only(v: Vector3, up: Vector3) -> Vector3:
	return v - up * v.dot(up)


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
	# Props layer (solid, round 10) is always in the mask: PropCollider
	# bodies (tree trunks, features) block and are climbable by default
	# -- a scene that forgets to wire the mask still gets one-law
	# collision.
	collision_layer = Layers.layer_bit("entity")
	collision_mask = collision_mask | Layers.layer_bit("solid")
	# INVENTORY BAG (round 7, item 3): the globe body never carried one,
	# so the globe world had NO inventory loop at all -- no bag for the
	# starter kit to land in (tabs rendered blank), nothing to receive
	# loot. Same wiring the planar controller does: create the bag,
	# stamp the id, register it with InventoryService. All resolves are
	# defensive (script-mode probes have no autoloads mounted).
	_setup_inventory_bag()
	# Local-player binding (the planar controller's law, line-for-line
	# the same wiring): panels and services resolve the bag through
	# PlayerManager.get_local_player_id(); the globe body never bound
	# itself, so in globe mode the character panel could not find the
	# bag it had just registered. Defensive: script-mode probes mount
	# no PlayerManager.
	var pm = Engine.get_main_loop().root.get_node_or_null("PlayerManager") if Engine.get_main_loop() is SceneTree else null
	if pm != null and pm.has_method("set_local_player"):
		pm.set_local_player(self)
	# Touch auto-sprint: the joystick flips the same sprint flag the
	# keyboard SHIFT does (defensive: headless/script contexts have no
	# joystick mounted).
	var jm = Engine.get_main_loop().root.get_node_or_null("InputManager") if Engine.get_main_loop() is SceneTree else null
	if jm != null and jm.has_method("get_virtual_joystick"):
		var stick = jm.get_virtual_joystick()
		if stick != null and not stick.sprint_override.is_connected(_on_sprint_override):
			stick.sprint_override.connect(_on_sprint_override)
	if glider == null:
		glider = load("res://core/frame/srv/glider_state.gd").new()
	# R45 saddle wiring: listen to the riding layer's signals (defensive
	# -- script-mode probes mount no RideService; they call the saddle
	# functions directly).
	ride_service = Engine.get_main_loop().root.get_node_or_null("RideService") if Engine.get_main_loop() is SceneTree else null
	if ride_service != null:
		if not ride_service.mount_summoned.is_connected(_on_mount_summoned):
			ride_service.mount_summoned.connect(_on_mount_summoned)
		if not ride_service.mount_dismounted.is_connected(_on_mount_dismounted):
			ride_service.mount_dismounted.connect(_on_mount_dismounted)
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

func _on_sprint_override(active: bool) -> void:
	_sprint_override_on = active

## Create + register the inventory bag (round-7 item 3). Deferred id
## stamp like the anticheat stamp: the scene fills entity_id after
## add_child, so registration uses the FINAL id exactly once.
func _setup_inventory_bag() -> void:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return
	var root_node: Node = (ml as SceneTree).root
	var InvComp = load("res://core/components/inventory_component.gd")
	var InvSvc = root_node.get_node_or_null("InventoryService")
	if _inventory_bag == null and InvComp != null:
		var bag = InvComp.new()
		bag.name = "InventoryComponent"
		add_child(bag)
		_inventory_bag = bag
		inventory_component = bag
	# The world scene assigns entity_id right after add_child(this);
	# stamp + register a moment later so the id is final. StarterKit
	# defers its grant while the bag is absent, so a 0.1 s delay is
	# inside its retry window.
	var tree := ml as SceneTree
	if tree != null:
		tree.create_timer(0.1).timeout.connect(func(): _register_bag())

func _register_bag() -> void:
	if _inventory_bag == null or not is_instance_valid(_inventory_bag):
		return
	if entity_id == null or str(entity_id) == "":
		entity_id = "globe_player_1"
	_inventory_bag.set_owner_id(str(entity_id))
	var root_node: Node = Engine.get_main_loop().root
	var InvSvc = root_node.get_node_or_null("InventoryService")
	if InvSvc != null and InvSvc.has_method("register_inventory"):
		# ONE PURSE PER PLAYER (R48): if the service already holds a LIVE
		# bag for this id -- a boot-restored wallet, or a purse a service
		# registered before this body spawned -- the body ADOPTS it
		# instead of clobbering it. A fresh bag here used to overwrite
		# the registration AND _persist_inventory would immediately save
		# the empty bag over the player's real wallet (the probe's buy
		# race: 'Not enough gold (need 150, have 0)'). A freed stale
		# registration still yields to the fresh bag.
		var existing = InvSvc.get_inventory(str(entity_id)) if InvSvc.has_method("get_inventory") else null
		if existing != null and is_instance_valid(existing) and existing != _inventory_bag:
			_inventory_bag.queue_free()
			_inventory_bag = existing
			inventory_component = existing
		else:
			InvSvc.register_inventory(str(entity_id), _inventory_bag)

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
	# Climb stamina regenerates whenever the body is not on a wall
	# (grounded or airborne -- gliding rests you too, this is a game).
	if not _climbing:
		climb_stamina = minf(CLIMB_STAMINA_MAX, climb_stamina + CLIMB_REGEN_PER_S * delta)

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

	# -- TERRAIN MOBILITY LAW (crouch / slide / sprint / slope) ----------
	# Terrain slope reads the TERRAIN COMPONENT of the ground law only
	# (the provider's terrain_h seam) -- walk-over rock CAPS are free
	# ground by law and must never read as "steep hills" that slow the
	# walk (probe-caught: capping the walk at 55% cost 175 m/30 s).
	var ground_law: float = 0.0
	if snap_height_provider.is_valid():
		ground_law = snap_height_provider.call(global_position)
	var terrain_now: float = _terrain_only(global_position, up, ground_law)
	if snap_enabled:
		var ahead: Vector3 = (global_position - planet_center).normalized() \
			* (planet_radius + ground_offset) + up * 0.5
		var terrain_ahead: float = _terrain_only(ahead, up, ground_law)
		var slope_sin: float = absf(terrain_ahead - terrain_now) / 0.5
		_slope_cos = clampf(sqrt(maxf(0.0, 1.0 - slope_sin * slope_sin)), 0.0, 1.0)
		_terrain_slope = _slope_cos
	var grounded: bool = is_on_floor() or snap_enabled

	# -- CROUCH CHAIN (one tap, one meaning, in priority order) ------
	# While SLIDING: the tap bails out of the slide -- back into the
	# run (the slide tick's own exit path also lands here, not in
	# crouch).
	# While SPRINTING on the ground: the tap ENGAGES the slide.
	# Otherwise: the tap toggles crouch.
	if allow_jump_input and Input.is_action_just_pressed("crouch"):
		if is_sliding:
			is_sliding = false
			is_crouching = false
			_slide_t = 0.0
		elif grounded and is_sprinting:
			is_sliding = true
			is_crouching = false
			_slide_t = 0.0
			var dirv: Vector3 = horizontal.normalized() if horizontal.length_squared() > 0.001 \
				else (wish if wish.length_squared() > 0.001 else cam_fwd)
			_slide_dir = dirv.normalized() if dirv.length_squared() > 0.001 else north
		else:
			is_crouching = not is_crouching
	# Sprint: keyboard SHIFT or the touch auto-sprint override. Needs
	# stamina reserve (stamina is the climb pool -- one pool, honest).
	# (Recomputed AFTER the chain: a bail leaves sprint live, so the
	# slide flows straight back into the run when the input is held.)
	is_sprinting = (Input.is_action_pressed("sprint") or _sprint_override_on) \
		and climb_stamina > 0.6 and not is_crouching

	# WALK SPEED law: base x crouch / sprint / slope, then the climb
	# check (a jump-hold against a wall outranks everything below).
	var mult: float = 1.0
	if is_sliding:
		mult = 0.0
	elif is_crouching:
		mult = CROUCH_MULT
	elif is_sprinting:
		mult = SPRINT_MULT
	# Steep uphill TERRAIN slows the walk (downhill keeps its speed;
	# walk-over caps are free ground and never slow it).
	if wish.length_squared() > 0.001:
		var terrain_wish: Vector3 = (global_position - planet_center).normalized() \
			* (planet_radius + ground_offset) + wish * 0.5
		var grad: float = (terrain_now - _terrain_only(terrain_wish, up, ground_law)) / 0.5
		if grad > 0.45:
			mult *= SLOPE_WALK_MULT

	var speed: float = walk_speed * mult

	# -- CLIMB LAW -------------------------------------------------------
	# Engage: jump HELD (not the tap that hops) + ground contact + a
	# steep/climbable face within reach ahead. While climbing, the body
	# rides the wall upward, stamina drains, and the radial snap stays
	# off (the wall is not the walk surface). Cresting the wall mantles
	# onto the top and hands control back to the snap law.
	if _climbing:
		_tick_climb(delta, up, wish, horizontal)
		return
	if is_mounted() and allow_jump_input and not _text_entry_focused() \
			and Input.is_action_just_pressed("dismount"):
		ride_service.dismiss(entity_id)
		return
	if allow_jump_input and is_on_floor() and climb_stamina > 0.25 \
			and Input.is_action_pressed("jump") and not Input.is_action_just_pressed("jump"):
		var probe_dir: Vector3 = (wish if wish.length_squared() > 0.001 \
			else cam_fwd).normalized()
		var wall := _wall_ahead(up, probe_dir)
		if wall != Vector3.ZERO:
			_climbing = true
			_climb_wall_normal = wall
			snap_enabled = false
			velocity = Vector3.ZERO
			return
	var vertical: Vector3 = velocity - horizontal

	# Jump: the same "jump" action the planar controller and the touch
	# JMP button feed. Fires only while surface contact holds (the glue
	# snap means is_on_floor() is always true at rest -- gate on radial
	# speed so a hop is never re-fired mid-air).
	if allow_jump_input and is_on_floor() \
			and Input.is_action_just_pressed("jump"):
		vertical += up * jump_force
		snap_enabled = false
	elif is_mounted() and wish.length_squared() > 0.0001:
		# The saddle's sprint gear: profile sprint x the low ratio, ONLY
		# under a held sprint (crouch outranks it as always; the climb
		# check above outranks everything). The anticheat is judged by
		# the mount's full profile -- this scale keeps the gallop legal.
		if is_sprinting and not is_crouching and mount_sprint_speed() > 0.0:
			speed = mount_sprint_speed()

	# The air-tap demount (R46, mobile first): a jump TAP while mounted
	# and airborne taps out of the saddle -- the touch JMP button feeds
	# this same action, so the mobile rider needs no new button to
	# bail off a cliff. Grounded taps stay hops: a gallop's first beat
	# must never dismiss the mount (hence the not-on-floor gate).
	if is_mounted() and not is_on_floor() and allow_jump_input \
			and Input.is_action_just_pressed("jump"):
		ride_service.dismiss(entity_id)
		return

	# S12 glider: feed the state machine (altitude above the surface,
	# no thermal model on the globe yet -- thermal zones land later),
	# then apply its vertical speed instead of raw gravity.
	if glider != null:
		# Altitude is height above the nearest LANDING SURFACE -- the
		# walk surface law (terrain + caps), not the bare static lift:
		# with the terrain arc, a body on a 9 m plaza is ON THE GROUND,
		# not 10 m in the air (the wing otherwise pops the moment you
		# walk -- dbg_walk caught the body GLIDING at spawn).
		var altitude: float = _radial_altitude(up)
		_feed_mount_fall_law(delta, up, true, altitude)
		if is_mounted():
			# THE MOUNTED FRAME INTEGRATES (R46 QC): a saddle here used
			# to return BEFORE the shared move_and_slide tail -- the body
			# kept its adopted laws but never moved (the frozen saddle:
			# value probes passed, physics never ran). Integrate and
			# validate, then rejoin the tick AFTER the glider machine,
			# which stays walk-surface law -- the saddle is, too.
			move_and_slide()
			_validate_movement()
			return
		var gstate: int = glider.tick(delta, maxf(altitude, 0.0), 0.0)
		# S16.4 vacuum rule: no atmosphere, no wing. If the machine
		# opened the wing over an airless world, the vacuum closes it
		# the same frame -- the body falls honestly.
		if gstate == glider.State.GLIDING and not _world_allows_gliding():
			glider.state = glider.State.FALLING
			gstate = glider.State.FALLING
		# MANUAL DEPLOY / STOW (runs for FALLING and GLIDING alike): a
		# jump tap mid-fall opens the wing (within the grace window);
		# tapping again mid-glide stows it and drops the body honestly.
		if allow_jump_input and Input.is_action_just_pressed("jump"):
			if gstate == glider.State.GLIDING:
				glider.on_stow_pressed()
				gstate = glider.State.STOWED_FALL
			elif gstate == glider.State.FALLING:
				glider.on_deploy_pressed()
				gstate = glider.state
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
			var glide_wish: Vector3 = wish
			# DIVE PITCH: looking DOWN pitches the wing into a dive (7 ->
			# 16 m/s); level flight holds by default. The camera pitch
			# IS the stick here -- no extra input to learn.
			var dive: float = clampf(-look_pitch / LOOK_PITCH_LIMIT, 0.0, 1.0)
			var forward: Vector3 = (glide_wish.normalized() if glide_wish.length_squared() > 0.0001 else -up.cross(Vector3(0, 0, 1)).normalized()) \
				* glider.glide_forward_speed(dive)
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
	if is_sliding:
		# -- SLIDE TICK: momentum down the fall line with steering ------
		# Speed law: the drop of the ground law AHEAD of the body
		# accelerates the slide (fall-line gravity, honest because the
		# height law IS the ground), friction decays it. Direction:
		# steering input blends the slide line while it lasts.
		var slide_v: Vector3 = horizontal if horizontal.length_squared() > 0.001 else _slide_dir * SLIDE_INIT_SPEED
		var sdir: Vector3 = slide_v.normalized()
		var h_now: float = ground_law
		var h_ahead: float = ground_law
		if snap_enabled and snap_height_provider.is_valid():
			h_ahead = snap_height_provider.call( \
				(global_position - planet_center).normalized() * (planet_radius + ground_offset) + sdir * 0.5)
		var slide_speed: float = maxf(slide_v.length() + (h_now - h_ahead) * gravity_force * delta \
			- SLIDE_FRICTION * delta, SLIDE_MIN_SPEED)
		if wish.length_squared() > 0.001:
			sdir = sdir.move_toward(wish.normalized(), 2.5 * delta).normalized()
		_slide_t += delta
		horizontal = sdir * slide_speed
		if _slide_t > 1.4 or (horizontal.length() <= SLIDE_MIN_SPEED and _slide_t > 0.25) \
				or not grounded:
			is_sliding = false
			is_crouching = false
			_slide_t = 0.0
			# Ends back into the RUN: is_sprinting recomputes next frame
			# from the held input (shift / full stick), so a still-held
			# sprint flows straight out of the slide at full speed.
	elif wish.length_squared() > 0.0001:
		horizontal = horizontal.move_toward(wish * speed, walk_speed * 8.0 * delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, walk_speed * 10.0 * delta)
	vertical -= up * gravity_force * delta

	velocity = horizontal + vertical
	var before: Vector3 = global_position
	move_and_slide()
	# Wedge assist: a head-on push into a thin prop (tree trunk) has
	# zero tangential velocity, so move_and_slide has nothing to slide
	# along and the body dead-stops. When the requested speed is high
	# but progress is tiny against a climbable wall, deflect along the
	# wall tangent toward the intended direction -- walking into a tree
	# slides you around it instead of freezing you (probe-caught: the
	# blind auto-walk wedged forever on a trunk exactly on its line).
	var moved: float = global_position.distance_to(before)
	if wish.length_squared() > 0.1 and moved < maxf(speed, walk_speed) * delta * 0.6:
		for i in range(get_slide_collision_count()):
			var c := get_slide_collision(i)
			var col = c.get_collider()
			if col is StaticBody3D and col.is_in_group(CLIMB_WALL_GROUP):
				var wn: Vector3 = c.get_normal()
				var t: Vector3 = wn.cross(up)
				if t.length_squared() < 0.0001:
					t = Vector3(1, 0, 0).cross(up)
				t = t.normalized()
				if t.dot(wish) < 0.0:
					t = -t
				global_position += t * walk_speed * delta * 0.8
				break
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
		# THE WALK LAW: terrain arc rides the walk surface (displaced
		# terrain + small-rock caps); the prototype rides the flat shell.
		# R45 saddle: a mount rides a LIFT above the surface law -- and
		# the lift is added BEFORE the perch check, so a mount standing
		# still is a saddle, not a perch awaiting a step-off fall.
		# The lift is applied EXACTLY, never lerped - the law is already
		# smooth in space, and a lagged lift lets the body intersect rock
		# colliders and stall (test-caught lesson).
		var lift: float = 0.0
		if snap_height_provider.is_valid():
			lift = snap_height_provider.call(global_position)
		if is_mounted():
			lift += SADDLE_LIFT
		var target_r: float = planet_radius + ground_offset + SKIN + lift
		_ride_lift = lift
		var err: float = planet_distance() - target_r
		if abs(err) > 0.001:
			global_position = planet_center + (global_position - planet_center).normalized() * target_r
		# PERCH LAW: standing on a walk-over cap whose top is a
		# climbable ledge (0.55 m or more above the terrain law) -- step
		# off it and the body becomes AIRBORNE immediately (no snap
		# crutch): the fall is honest, the arc is real. R45 saddle: a
		# mount standing still is a saddle, not a perch -- the 0.4 m
		# saddle lift alone never trips the perch (0.55 m gate).
		if _perch_height() >= PERCH_MIN_LIFT:
			snap_enabled = false
	elif vertical.dot(up) <= 0.0 and planet_distance() <= planet_radius + ground_offset + SKIN + lift_expected() + 0.05 \
			and not (is_mounted() and planet_distance() <= planet_radius + ground_offset + SKIN + lift_expected() + SADDLE_LIFT + 0.05):
		snap_enabled = true

	# Keep the camera pivot aligned with local up, then apply the
	# look orbit (yaw around local up, pitch around local east). With no
	# look input yet this reproduces the original fixed frame exactly.
	# The mounted camera pulls back so the beast fits the frame (R46
	# camera-follow setup; models stay future seams). Exact seat, only
	# when the pivot still carries the walk rig's code-built camera --
	# a world scene that placed its own camera keeps it. No lerp: the
	# pivot is teleported to the body every frame anyway.
	if pivot != null and is_mounted():
		var seat: Camera3D = pivot.get_node_or_null("Camera3D")
		if seat != null and seat.position == CAMERA_SEAT:
			seat.position = MOUNT_CAMERA_SEAT
	if pivot:
		var xform: Transform3D = pivot.global_transform
		xform.basis = Basis(east, up, -north)
		xform.basis = xform.basis.rotated(up, look_yaw)
		xform.basis = xform.basis.rotated(xform.basis.x, look_pitch)
		pivot.global_transform = xform


## -- Climb internals ---------------------------------------------------

## One climbing frame: radial climb toward the wall top, stamina law,
## release conditions. Runs INSTEAD of the normal movement tail (the
## caller returns right after).
func _tick_climb(delta: float, up: Vector3, wish: Vector3, horizontal: Vector3) -> void:
	# Release: button let go, or the wall is gone (streamed away).
	if not Input.is_action_pressed("jump") or climb_stamina <= 0.0:
		_end_climb(up)
		return
	var dir: Vector3 = -_climb_wall_normal
	var still := _wall_ahead(up, dir)
	if still == Vector3.ZERO:
		# Crested the top: mantle -- a short down-ray from above the
		# crest lands the body ON the walk surface (terrain law, boulder
		# top, whatever the climb topped out on), then the snap law
		# keeps it there.
		var radial: Vector3 = (global_position - planet_center).normalized()
		var top_r: float = planet_radius + ground_offset + SKIN + lift_expected() + CLIMB_REACH
		global_position = planet_center + radial * top_r
		var space := get_world_3d().direct_space_state
		var down := PhysicsRayQueryParameters3D.create( \
			planet_center + radial * top_r, planet_center + radial * (planet_radius + ground_offset), Layers.group_mask("everything"), [get_rid()])
		down.collision_mask = Layers.group_mask("everything")
		var dh := space.intersect_ray(down)
		var land_r: float = planet_radius + ground_offset + SKIN
		if dh.has("position"):
			land_r = (dh["position"] as Vector3).distance_to(planet_center) + SKIN
		global_position = planet_center + radial * land_r
		velocity = Vector3.ZERO
		_end_climb(up)
		return
	_climb_wall_normal = still
	climb_stamina = maxf(0.0, climb_stamina - CLIMB_DRAIN_PER_S * delta)
	# Ride the wall: press into it (stick), climb up its face.
	var wall_up: Vector3 = (up - _climb_wall_normal * up.dot(_climb_wall_normal)).normalized()
	var radial: Vector3 = (global_position - planet_center).normalized()
	velocity = -_climb_wall_normal * 0.6 + wall_up * CLIMB_SPEED
	# Keep gravity honest (the wall friction cancels it via the stick).
	velocity += -radial * 0.0
	move_and_slide()
	# Never sink below the walk surface while stuck to a low wall.
	var floor_r: float = planet_radius + ground_offset + SKIN
	if planet_distance() < floor_r - 0.05:
		global_position = planet_center + radial * floor_r
	_validate_movement()

func _end_climb(up: Vector3) -> void:
	_climbing = false
	snap_enabled = true
	velocity = Vector3.ZERO

## Probe for a steep or climbable surface within reach ahead. Returns
## the wall NORMAL (globe-frame) or Vector3.ZERO when nothing climbable
## is in reach. Two sources: (a) physics bodies in the "climbable"
## group (PropCollider-attached props), (b) the walk surface itself
## when its slope exceeds CLIMB_MIN_ANGLE_DEG (sheer cliffs).
func _wall_ahead(up: Vector3, probe_dir: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return Vector3.ZERO
	var from: Vector3 = global_position + up * 0.5
	var to: Vector3 = from + probe_dir * CLIMB_REACH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = Layers.layer_bit("solid")  # world props layer (PropCollider)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.has("collider") and is_instance_valid(hit["collider"]):
		var col = hit["collider"]
		if col.is_in_group(CLIMB_WALL_GROUP) or col is StaticBody3D:
			var n: Vector3 = hit["normal"]
			# Steepness: wall normal vs local up. A slope steeper than
			# the climb angle is climbable; a wall is always near 90 deg.
			var steepness: float = 1.0 - absf(n.dot(up))
			if steepness >= sin(deg_to_rad(CLIMB_MIN_ANGLE_DEG)):
				return n.normalized()
	return Vector3.ZERO

## Surface normal at the player (probe helper).
func get_surface_normal() -> Vector3:
	return _surface_normal


## True when the player is glued to the walk surface (probe helper).
func is_glued(tolerance: float = 0.5) -> bool:
	# THE SNAP EQUATION: glued means the body rests at SKIN above the
	# WALK SURFACE law at its own direction (terrain + caps; the same
	# value the snap targets). The prototype (no provider) keeps the
	# bare-shell check. Tolerance absorbs the slope ramp (the law is
	# evaluated pointwise; on a tilt the contact sits a hair high).
	return abs(planet_distance() - (planet_radius + ground_offset + SKIN + lift_expected())) <= tolerance


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


## -- Terrain arc helpers -----------------------------------------------

## The TERRAIN component of the ground law at a world position: the
## scene's terrain_h seam when wired (globe_world), else the walk law
## passthrough. Slope/mobility must read terrain, never the walk-over
## caps on top of it. The seam resolves up the parent chain (the
## player's parent IS the globe scene in game AND in script-mode
## probes, where current_scene is null).
func _terrain_only(wpos: Vector3, up: Vector3, walk_law: float) -> float:
	var node: Node = self
	for _hop in range(3):
		node = node.get_parent() if node != null else null
		if node == null:
			break
		if node.has_method("terrain_h_at"):
			return node.terrain_h_at(wpos)
	if snap_height_provider.is_valid():
		return walk_law
	return 0.0

## Perch height this frame: the walk-surface law at the body's
## direction MINUS the terrain law (how far the body rides above the
## ground -- positive only on walk-over caps and boulder tops).
func _perch_height() -> float:
	if not snap_height_provider.is_valid():
		return 0.0
	var d: Vector3 = (global_position - planet_center).normalized()
	var walk: float = snap_height_provider.call(global_position)
	var ground: float = TerrainGen.terrain_height(d, world_seed_bytes_local())
	return walk - ground


## World seed bytes for the terrain law (project setting resolve;
## mirrors TerrainGen.world_seed_bytes -- one source of truth).
func world_seed_bytes_local() -> PackedByteArray:
	return TerrainGen.world_seed_bytes()


## The surface gap the re-arm law accepts: the walk surface at the
## body's direction (terrain + cap), or 0 on the prototype shell.
func lift_expected() -> float:
	if snap_height_provider.is_valid():
		return maxf(snap_height_provider.call(global_position), 0.0)
	return 0.0
