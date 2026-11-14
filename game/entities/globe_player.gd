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
extends PlayerBase

class_name GlobeWorldPlayer

## Runtime autoload lookup (script-mode-safe; the bare identifier fails
## to compile when autoloads are absent).
func _im() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("InputManager")) if tree and tree.root else null

## The AFK clock's account key for this body (the human's account). The
## body carries no account field, so the session account (LoginService) is
## the honest key; a script-mode probe with no login falls back to the
## entity id so the clock still works locally. Returns "" only when there
## is nothing to key on (never a fabricated identity).
func _activity_account() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return ""
	var ls := tree.root.get_node_or_null(NodePath("LoginService"))
	if ls != null and ls.has_method("get_current_account_id"):
		var acct: String = str(ls.get_current_account_id())
		if acct != "":
			return acct
	return str(entity_id)

## Record genuine activity on the AFK clock (labs/prd-agent-play.md sec
## 17.3): the human must stay active for their agents to keep playing.
## Called from the real input paths (movement, the input fan-out, clicks);
## defensive + silent when the service is absent (script-mode probes).
func _touch_activity() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var svc := tree.root.get_node_or_null(NodePath("ActivityService"))
	if svc == null or not svc.has_method("touch"):
		return
	var acct: String = _activity_account()
	if acct != "":
		svc.touch(acct)

func _ds() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("DataService")) if tree and tree.root else null

func _notify_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("NotificationService")) if tree and tree.root else null

func _inv_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("InventoryService")) if tree and tree.root else null

func _ground_loot() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GroundLootService")) if tree and tree.root else null

## The toast kinds the Concord-loop interact legs use (mirrors the
## planar controller's NotifKind preload).
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

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
## This body's inventory bag (round 7: the globe world had no bag at
## all -- the starter kit had nothing to land in and panels rendered
## empty). Created + registered in _setup_inventory_bag().
var _inventory_bag = null
## Same bag under the name the planar controller exposes. UI resolvers
## (character_panel._resolve_inventory) duck-type this property; the
## globe body only had _inventory_bag, so the panel's player-node
## fallback missed the bag it was standing on.
var inventory_component = null
## Respawn binding (Ankh.bind_player writes respawn_ankh_id; the planar
## controller declares these locally -- the globe body inherits PlayerBase,
## which does not, so the ankh bind leg errored on the globe). The ankh
## interact port (planar-retirement Step 3) needs them.
var respawn_ankh_id: String = ""
var respawn_point: Vector3 = Vector3.ZERO
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
## The Q / touch-DSL evasive roll (not sprinting): a short tangent
## shove along the movement line (the planar controller's dodge_force).
const DODGE_FORCE: float = 6.0
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
## THE ROAD FOLLOW (the auto-walk extension): with auto_walk on AND
## this on, the boot's heading snaps to the nearest cartway tangent -
## the player picks a road and WALKS it, turning where the road
## turns. The walk ends at the capitol anchor (the arrival law:
## a destination, not an echo).
var auto_walk_road: bool = false
## Optional provider: func(dir: Vector3) -> float, height above the
## base surface at that direction (rock tops). The radial snap rides
## rock tops smoothly so walk-over colliders decorate, not block.
var snap_height_provider: Callable = Callable()
## Diagnostic (S8): when false the radial surface snap is skipped and
## gravity still pulls, so the probe can separate snap interaction
## from raw contact physics. Default true = unchanged behavior.
var snap_enabled: bool = true
## RIVER FORD LAW (slice 3 downstream): the shallow water of a
## river/lake channel is walkable honestly -- depth of the carved
## water over the carved terrain at the body's direction. Wading
## bands: FORD (shallower than WADE_FORD_DEPTH, full speed) -> WADE
## (slow) -> SWIM (deeper than WADE_MAX_DEPTH: the aquatic service
## owns that band). Read on the TERRAIN LAWS only (no mesh reads),
## so the ford check cannot disagree with the ground draw.
var _wading: bool = false
var _wade_depth: float = 0.0
var _wade_stamp_live: bool = false  # the anticheat stamp owns this body
## THE CURRENT LAW bookkeeping: the ford pull this frame + the cartway
## underfoot (the road state vector: corridor weight, deck, surface).
var _wade_flow: Vector3 = Vector3.ZERO
var _road_underfoot: Vector3 = Vector3.ZERO
const WADE_MULT: float = 0.55       # wading walk multiplier
const WADE_FORD_DEPTH: float = 0.15 # deeper than this = feet in water (not a bridge)
const WADE_MAX_DEPTH: float = 1.6   # deeper than this is the swim service's band

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
## Per-body virtual input (labs/prd-agent-play.md sec 1/7): an AGENT body is
## driven by its OWN input, never the global Input singleton -- that is what
## lets two bodies (a human's and an agent's) share one process without the
## human's keys steering the agent (and vice versa). The agent driver sets this
## vector via set_virtual_input(); movement prefers it over Input when virtual
## input is live. A human body leaves it off and reads Input exactly as before.
var _virtual_move: Vector2 = Vector2.ZERO
var _virtual_sprint: bool = false
var _virtual_input_on: bool = false
## Targeting parity (planar-retirement Step 5): the globe body's input
## surface used to carry only `interact`. These mirror the planar
## controller's targeting state so the shared player_input fan-out
## (attack / Tab / F1 / F2 / ability_1..8) reaches the body.
var is_targeting: bool = false
## The body is the local player's avatar (input routes here). Mirrors the
## planar controller's flag so click/keys gate the same way.
var is_local_player: bool = true
## The code-built context menu (NPC/gate/loot/player fan-out). Created
## lazily on first use, exactly like the planar controller's.
var _action_menu = null
## Cached station panels (repair bench / workbench / skill academy / stats):
## reused across opens so a second interact does not stack a duplicate panel.
var _blacksmith_ui = null
var _workbench_ui = null
var _skill_academy_ui = null
var _character_stats_ui = null
## Tab-cycle target history (the "previous target" ring). One ring, local
## to this body -- TargetingManager keeps only a single previous slot.
var _target_history: Array = []
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


## Flush the glide session to the sky-road stats: routes the session's
## distance/altitude/time to the gliding achievements once per glide.
## The wing auto-deploys near the ground, so a session is often one
## glide rather than one frame -- landing is when it is complete.
func _flush_glide_session() -> void:
	_glide_session_active = false
	if _glide_session_distance <= 0.0:
		_glide_session_distance = 0.0
		return
	_glide_session_distance = 0.0
	if not (Engine.get_main_loop() is SceneTree):
		return
	var ts = Engine.get_main_loop().root.get_node_or_null("ThermalService")
	if ts != null and ts.has_method("push_glide_achievements"):
		ts.push_glide_achievements(entity_id)


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
## FORD LAW seam: a wading body is stamped with a wade cap (walk-law
## speed x WADE_MULT, the honest max in the band) so the aquatic
## override never masks a wade-speed hack, and the stamp clears when
## the body leaves the band (the aquatic service's own stamp, if one
## is live for a DEEPER band, owns the body and is never clobbered --
## the wade stamp only ever LOWERS the max).
func _validate_movement() -> void:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return
	var ac = (ml as SceneTree).root.get_node_or_null("AntiCheatService")
	if ac != null and ac.has_method("validate_movement"):
		ac.validate_movement(entity_id, global_position, velocity, get_physics_process_delta_time())
	if ac != null and ac.has_method("set_aquatic_limits") and terrain_on_local():
		if _wading:
			ac.set_aquatic_limits(entity_id, walk_speed * WADE_MULT, 0.0, 110.0)
		elif _wade_stamp_live:
			ac.set_aquatic_limits(entity_id, walk_speed, 0.0, 110.0)  # back to dry-law speeds
			_wade_stamp_live = false
	if _wading and not _wade_stamp_live:
		_wade_stamp_live = true

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
## Glide-session bookkeeping: whether this body was GLIDING last frame,
## and the distance it has carried in the current glide session. Landing
## (or the wing closing) flushes the session to ThermalService's
## achievements, so a completed glide is recognized without a per-frame
## cost -- the wing auto-deploys near the ground, so the tick rarely
## lands a full session in one frame.
var _glide_session_active: bool = false
var _glide_session_distance: float = 0.0

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
	var ds := _ds()
	if mount == null or ds == null:
		return
	var profile = ds.get_mount_movement_profile(mount)
	if profile == null:
		return
	_mount_profile = profile
	mounted_mount_id = str(mount_id)
	if _humanoid_gravity < 0.0:
		_humanoid_gravity = gravity_force
	walk_speed = float(profile.walk_speed)
	jump_force = float(profile.jump_force)
	gravity_force = float(profile.gravity_force)
	var gl := _glog()
	if gl:
		gl.info("GlobeWorldPlayer: %s takes the saddle of the %s" % [entity_id, str(mount.display_name)])


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
	# THE SHARED PLAYER SURFACE (planar-retirement Step 5): health component,
	# the "players" group, the class skillbar, and the combat effect stack
	# all live in PlayerBase._ready now -- one home, so a bare PlayerBase
	# (probes, fixture tests) carries the same surface as a scene body.
	super._ready()
	# Hitbox Profile System: the species-fair player capsule (the ONE player
	# hitbox). Applied deferred so the tree setup settles first; the globe's
	# ground law is a math check (planet_distance), so the shape only matters
	# for the hitbox sweep -- which is exactly why it must be the player shape.
	_apply_hitbox_profile.call_deferred()
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
	# Only a LOCAL body claims the local seat (labs/prd-agent-play.md sec
	# 1/7): an AGENT body (is_local_player = false) shares the world but
	# must never steal the seat from the human. A deferred re-adopt makes a
	# local body reclaim the seat if a later-added body ever displaced it.
	if is_local_player and pm != null and pm.has_method("set_local_player"):
		pm.set_local_player(self)
	_adopt_local_seat.call_deferred()
	# THE CONCORD-LOOP INTERACT (planar-retirement Step 1): listen to the
	# shared InputManager's "interact" action so E / gamepad A / touch ACT
	# reaches the world's interactables (ancient doors, concord stones).
	# Defensive + idempotent -- script-mode probes mount no InputManager.
	_connect_interact_input()
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

## Deferred local-seat adoption (labs/prd-agent-play.md sec 1/7): a LOCAL
## body re-claims the seat on the next frame, so an agent body added after
## the human can never leave the world seated on the wrong player.
func _adopt_local_seat() -> void:
	if not is_local_player:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var pm = tree.root.get_node_or_null("PlayerManager")
	if pm != null and pm.has_method("set_local_player"):
		pm.set_local_player(self)


func _on_sprint_override(active: bool) -> void:
	_sprint_override_on = active


## Per-body virtual input (labs/prd-agent-play.md sec 1/7). An agent body is
## driven by its OWN input, not the global Input singleton, so an agent and a
## human can share one process. move is a camera-relative stick vector (x =
## strafe right, y = forward), sprint a held bool. A zero vector still counts
## as "virtual input live" (a deliberate stop), so the body ignores the
## human's keys while an agent owns it.
func set_virtual_input(move: Vector2, sprint: bool = false) -> void:
	_virtual_move = move
	_virtual_sprint = sprint
	_virtual_input_on = true


## Drop virtual input: the body returns to reading the global Input singleton
## (a human body never calls this; an agent body calls it on despawn so a freed
## seat cannot leave stale input behind).
func clear_virtual_input() -> void:
	_virtual_move = Vector2.ZERO
	_virtual_sprint = false
	_virtual_input_on = false


## Does this body currently read virtual (agent) input rather than Input?
func has_virtual_input() -> bool:
	return _virtual_input_on


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
	# THE ONE PURSE mirror (planar-retirement Step 5): the globe node's
	# `gold` was never bound to the bag, so kill payouts paid the purse but
	# the node stayed at zero. Bind it the same way the planar controller
	# does -- shared helper, one home.
	_bind_purse_mirror()

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
	# Basic-attack edge (left-click / touch ATK / gamepad): the planar body's
	# state machine polled this; the globe body has no state machine, so the
	# same edge drives the shared combat entry point here (both modes).
	if is_local_player and Input.is_action_just_pressed("attack"):
		_try_attack()
	# The AFK clock's movement leg (labs/prd-agent-play.md sec 17.3):
	# sustained movement is genuine activity. Polled (not event-driven)
	# because movement is a held action; a cheap length check per frame.
	if is_local_player and Input.get_vector("move_left", "move_right", "move_forward", "move_back").length_squared() > 0.0001:
		_touch_activity()
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
		# THE ROAD FOLLOW: the cartway's own tangent outranks the
		# heading law (the boot rides the road, turning where it turns;
		# off-corridor it keeps the cam-heading law until the road picks
		# up again). The arrival law: inside the capitol anchor ring
		# the walk ends honest - a destination, not an echo.
		if auto_walk_road:
			var body_dir: Vector3 = (global_position - planet_center).normalized()
			if body_dir.angle_to(TerrainGen.capitol_plaza_dir()) < 0.012:
				auto_walk = false
				wish = Vector3.ZERO
			else:
				var road_dir: Vector3 = TerrainGen.road_walk_dir(body_dir, world_seed_bytes_local())
				if road_dir.length_squared() > 0.0001:
					wish = road_dir
	else:
		# Touch stick feeds the same pipeline as WASD: InputManager merges
		# controller > touch joystick > keyboard into one vector. Input is
		# CAMERA-RELATIVE like the planar controller: forward walks where
		# you look, so orbiting the view re-aims movement (walking used to
		# pin to map north/east regardless of where the camera pointed,
		# which read as "stuck" against invisible walls while circling).
		var input_vec: Vector2
		if _virtual_input_on:
			# _virtual_move is INTUITIVE (x = strafe right, y = forward); the
			# get_vector convention below is y-negative-forward, so negate y here
			# and keep the single wish formula.
			input_vec = Vector2(_virtual_move.x, -_virtual_move.y)
		else:
			var im := _im()
			input_vec = im.get_movement_input() if im \
			else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wish = cam_fwd * (-input_vec.y) + cam_right * input_vec.x
	if wish.length() > 1.0:
		wish = wish.normalized()

	# Crowd control: a stunned/rooted body cannot drive input (status effects
	# carry can_move == false). Velocity still integrates so gravity applies.
	if not _can_move():
		wish = Vector3.ZERO

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
	# -- DODGE (the Q lane / touch DSL): the planar Run state split this
	# input into Slide while sprinting and an evasive roll otherwise; the
	# globe body answered only crouch, so Q and the touch DSL button were
	# dead here. Same split, now on the globe: sprint -> slide (reuses the
	# crouch-chain slide, which was only reachable via CRH), else a
	# tangent-plane hop along the movement line.
	if allow_jump_input and Input.is_action_just_pressed("dodge") and grounded:
		if is_sprinting:
			is_sliding = true
			is_crouching = false
			_slide_t = 0.0
			var dirv: Vector3 = horizontal.normalized() if horizontal.length_squared() > 0.001 \
					else (wish if wish.length_squared() > 0.001 else cam_fwd)
			_slide_dir = dirv.normalized() if dirv.length_squared() > 0.001 else north
		else:
			var roll_dir: Vector3 = horizontal.normalized() if horizontal.length_squared() > 0.001 \
					else (wish if wish.length_squared() > 0.001 else cam_fwd)
			horizontal += (roll_dir.normalized() if roll_dir.length_squared() > 0.001 else north) * DODGE_FORCE
	# Sprint: keyboard SHIFT or the touch auto-sprint override. Needs
	# stamina reserve (stamina is the climb pool -- one pool, honest).
	# (Recomputed AFTER the chain: a bail leaves sprint live, so the
	# slide flows straight back into the run when the input is held.)
	var sprint_held: bool = _virtual_sprint if _virtual_input_on else Input.is_action_pressed("sprint")
	is_sprinting = (sprint_held or _sprint_override_on) \
		and climb_stamina > 0.6 and not is_crouching

	# THE SEA STEP (S14.7.2): deep water outranks the walk --
	# the water owns the body, the ford law never sees it.
	if _sea_swim_step(delta, up, wish):
		return

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
	# Status-effect movement multiplier (slow/root/haste from the .tres
	# status-effect data). 1.0 base; effects add a delta, so a -30% slow is
	# stats.movement_speed_multiplier == 0.7.
	speed *= float(stats.get("movement_speed_multiplier", 1.0))

	# -- RIVER FORD LAW (walkable shallow water) -------------------------
	# Depth of the carved water over the carved terrain at THIS body's
	# direction. In the WADE band (feet in water above the ford line,
	# below the swim handoff): the walk slows and jumps stop -- a river
	# is a stamina-free crossing, not a trampoline. FORD band (barely
	# wet): honest dry-foot speed, so shallow crossings stay real
	# bridges. Deeper than WADE_MAX: the aquatic service owns the body
	# (world scenes with swim law read their own band there).
	_wade_depth = _wade_depth_at()
	_wading = _wade_depth > WADE_FORD_DEPTH and _wade_depth <= WADE_MAX_DEPTH
	if _wading:
		speed *= WADE_MULT
		# THE CURRENT LAW (the river flow slice): wading water PULLS -
		# walking against the local flow taxes the pace. The pull
		# itself (at the velocity tail below) rides a capped fraction
		# of the channel law so the wading stamp stays honest.
		var ford_flow: Vector3 = TerrainGen.water_drift_at(_body_dir_law(), world_seed_bytes_local())
		_wade_flow = ford_flow
		if ford_flow.length_squared() > 0.0001 and wish.length_squared() > 0.001:
			var against: float = maxf(0.0, -wish.normalized().dot(ford_flow.normalized()))
			speed *= (1.0 - 0.45 * clampf(against, 0.0, 1.0))
		else:
			_wade_flow = Vector3.ZERO
	# THE CARTWAY LAW: road underfoot carries its surface's pace (the
	# dirt trail keeps a 1.05x walking pace; the RoadData speed law
	# overrides when the data service loads the road resource).
	var road_state: Vector3 = TerrainGen.road_state_at(_body_dir_law(), world_seed_bytes_local())
	_road_underfoot = road_state
	if road_state.x > 0.4:
		speed *= 1.05

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
			and Input.is_action_just_pressed("jump") \
			and not _wading:
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
			_glide_session_active = true
			_glide_session_distance += velocity.length() * delta
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
		# The wing closed (landed, stowed, or vacuum): flush the glide
		# session to ThermalService's achievements so a completed run
		# is recognized once, not per frame.
		if _glide_session_active:
			_flush_glide_session()
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

	# THE FORD PULL (the current law): the wading body drifts with its
	# local flow at a capped walk-band fraction (0.4 m/s law), so the
	# wading stamp reads a walk, never a teleport.
	if _wading and _wade_flow.length_squared() > 0.0001:
		horizontal += _wade_flow * 0.9
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

	# THE DECK RIDE (S14.6): while a carried deck anchor holds (the
	# vessel's ride law stamps it and clears it the tick after a
	# step-off), the terrain radial home owns nothing -- the deck
	# panel IS the ground this frame (physics' own floor contact;
	# the snap would re-home the body to the SEABED law mid-sea,
	# which is what made standing on a moving hull impossible).
	if has_meta("deck_rides"):
		var deck = get_meta("deck_rides")
		if deck != null and is_instance_valid(deck):
			snap_enabled = false

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


## THE BODY'S PLANET DIRECTION (the terrain law frame the current,
## road, and clearance laws all read).
func _body_dir_law() -> Vector3:
	return (global_position - planet_center).normalized()


## The terrain-on flag for the wade law (the retired retired streamer's live flag,
## resolved up the parent chain like terrain_h_at).
func terrain_on_local() -> bool:
	var node: Node = self
	for _hop in range(3):
		node = node.get_parent() if node != null else null
		if node == null:
			break
		if node.has_method("terrain_on_flag"):
			return node.terrain_on_flag()
	return false


## The surface gap the re-arm law accepts: the walk surface at the
## body's direction (terrain + cap), or 0 on the prototype shell.
## Depth of standing water at the body's direction: the gated water
## surface MINUS the carved terrain (both TerrainGen statics; the same
## Depth of standing water at the body's direction. TWO sources, both
## the same laws the mesh reads:
##  1. LAKE band: the gated water surface MINUS the carved terrain.
##  2. RIVER band: the channel capsule carries RIVER_BED_DEPTH x
##     channel of carved, flow-filled water (the river's bed IS the
##     carve; the deepest line runs the center, banks wade shallow --
##     cross at the slope, not the middle).
## 0.0 = dry. The SPAWN law applies to both (the apron stays dry --
## the river that would cross the boot plaza stays suppressed).
func _wade_depth_at() -> float:
	if not terrain_on_local():
		return 0.0
	var seed_b: PackedByteArray = world_seed_bytes_local()
	var d: Vector3 = (global_position - planet_center).normalized()
	# The SPAWN law: the same suppress band the hydro gates use
	# (SUPPRESS_IN..SUPPRESS_OUT around the boot plaza).
	if d.angle_to(TerrainGen.SPAWN_CENTER) < TerrainGen.Hydro.SUPPRESS_IN:
		return 0.0
	var depth: float = 0.0
	# Lake band.
	var surf: float = TerrainGen.hydro_water_surface(d, seed_b)
	if surf > -1e8:
		var ground: float = TerrainGen.terrain_height(d, seed_b)
		depth = maxf(depth, surf - ground)
	# River band: channel water fills the carved bed.
	var chan: float = TerrainGen.river_channel(d, seed_b)
	if chan > 0.25:
		depth = maxf(depth, TerrainGen.Hydro.RIVER_BED_DEPTH * chan)
	return depth


func lift_expected() -> float:
	if snap_height_provider.is_valid():
		return maxf(snap_height_provider.call(global_position), 0.0)
	return 0.0
## ============================================================================
## S14.7.2 THE SEA STEP (prd-ocean-depths.md sec 3/8-10)
## The world sea's wet half. ONE OceanService call answers everything
## (band, depth, current, breath); the body only obeys it. The bands are
## the service's, never re-derived here:
##   * DRY / WADING -> false: the ford law and the walk own the body.
##   * SURFACE_SWIM / SUBMERGED / SQUEEZE / CRUSH -> the water owns it:
##     the swim speed feeds the wish, the CURRENT carries the body along
##     the volume's declared flow (the ferry lane -- 0.5 m/s along the
##     RUN tangent in the Sundered Sea; a current-immune breather reads
##     ZERO from the service, not from here), and buoyancy holds the
##     body at the waterline unless the player dives (crouch) or climbs
##     (jump). CRUSH has no wish: the sea pushes up.
## ============================================================================
## Swim pace as a fraction of the walk pace (water is work).
const SEA_SWIM_MULT: float = 0.62
## How fast the wish steers the existing horizontal velocity (1/s).
const SEA_STEER_PER_S: float = 4.0
## Up/down swim speed (m/s) and the buoyancy spring that settles the
## body onto the waterline (no bob without input).
const SEA_SWIM_VERTICAL: float = 2.4
const SEA_FLOAT_SPRING: float = 1.6
## Depth under the sea line a body floats at while idle (head up).
const SEA_FLOAT_DEPTH: float = 0.6
## Drowning bite (per SECOND of continued submersion past breath 0)
## and the pressure pool's damage multiplier -- the driver converts
## SwimState's numbers here, once (prd-ocean-depths sec 4/8).
const SEA_DROWN_DPS: float = 10.0
const SEA_PRESSURE_MULT: float = 1.0

## Sea bookkeeping (read by the HUD/anticheat legs later).
var _sea_wet: bool = false
var _sea_band: int = 0
var _sea_depth: float = -1.0
var _sea_flow: Vector3 = Vector3.ZERO
## The horizontal velocity the sea law applied this frame (the current
## plus the swim steering) -- read by the receipt and the HUD.
var _sea_carry: Vector3 = Vector3.ZERO
## THE SWIM BOOK (S14.7.3): what the water does to this body right
## now -- the HUD's SeaBar reads these directly, the damage law fires
## on them. All snapshots of the last tick_swimmer.
var _sea_breath_s: float = -1.0
var _sea_breath_max: float = -1.0
var _sea_pressure: float = 0.0
var _sea_drowning_s: float = 0.0
var _sea_burn_dps: float = 0.0
## Fractional damage carried between ticks (take_damage is int).
var _sea_dps_debt: float = 0.0

## The live OceanService node (null in bare/script hosts).
func _ocean_service() -> Node:
	var main_loop = Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return null
	var tree: SceneTree = main_loop
	return tree.root.get_node_or_null("OceanService")


## The sea owns this frame? Returns true when the water moved the body.
func _sea_swim_step(delta: float, up: Vector3, wish: Vector3) -> bool:
	var os := _ocean_service()
	if os == null or not os.has_method("tick_swimmer"):
		return false
	var grace: float = 0.0
	var immune: bool = false
	var breath_mult: float = 1.0
	if os.has_method("breather_for"):
		var br: Dictionary = os.breather_for(entity_id)
		grace = maxf(float(br.get("grace_m", 0.0)), 0.0)
		immune = bool(br.get("current_immune", false))
		breath_mult = maxf(float(br.get("mult", 1.0)), 1.0)
	# THE MOUNT HANDOFF (S14.6's ticket, fed here since S14.7.3): the
	# ride law answers BEFORE the sea law -- a land mount that is
	# past the waterline is dismissed by the service itself; a
	# swimmer mount stamps its grace/crush/current-immunity into the
	# SAME tick call, so a mounted body and a naked body obey one
	# ocean law. The band estimate for the handoff is the service's
	# own (the raw gear grace; the mount's grace rides into the REAL
	# call below). No ride service == the old naked path unchanged.
	var mount_grace := 0.0
	var mount_crush := 0.0
	if ride_service != null and ride_service.has_method("water_stamp_for"):
		var est_band: int = -1
		if os.has_method("band_at"):
			est_band = int(os.band_at(global_position, grace))
		var stamp: Dictionary = ride_service.water_stamp_for(entity_id, est_band)
		if str(stamp.get("action", "none")) == "swim":
			mount_grace = maxf(float(stamp.get("grace", 0.0)), 0.0)
			mount_crush = maxf(float(stamp.get("crush_bonus", 0.0)), 0.0)
			immune = immune or bool(stamp.get("immune", false))
	var st: Dictionary = os.tick_swimmer(entity_id, global_position, delta,
		grace, mount_grace, mount_crush, immune)
	var band: int = int(st.get("band", 0))
	var depth: float = float(st.get("depth", -1.0))
	# The wade band belongs to the ford law (it reads the terrain, this
	# reads the water column); below it the sea owns the body.
	if band <= 1 or depth <= WADE_MAX_DEPTH:
		if _sea_wet:
			_sea_wet = false
			_sea_flow = Vector3.ZERO
			_sea_depth = -1.0
			_sea_breath_s = -1.0
			_sea_breath_max = -1.0
			_sea_pressure = 0.0
			_sea_drowning_s = 0.0
			_sea_burn_dps = 0.0
			_sea_dps_debt = 0.0
			if os.has_method("forget_swimmer"):
				os.forget_swimmer(entity_id)
		return false
	_sea_wet = true
	_sea_band = band
	_sea_depth = depth
	_sea_flow = st.get("current", Vector3.ZERO)
	# THE SWIM BOOK: snapshot the state for the HUD, then the DAMAGE
	# LAW -- the driver converts (SwimState speaks pools and seconds,
	# the body speaks health). Drowning past an empty breath, the
	# squeeze/crush pressure pool (the pool IS the per-second rate),
	# and a non-water volume's burn each pull the debt up; the debt
	# pays out through the health component in whole points. Surfaced
	# refills and eased pools are the service's law, never re-derived.
	var SwimState = load("res://core/frame/srv/swim_state.gd")
	_sea_breath_s = float(st.get("breath", 0.0))
	_sea_breath_max = maxf(float(SwimState.BREATH_SECONDS) * breath_mult, 1.0)
	_sea_pressure = maxf(float(st.get("pressure", 0.0)), 0.0)
	_sea_drowning_s = maxf(float(st.get("drowning_s", 0.0)), 0.0)
	_sea_burn_dps = maxf(float(st.get("burn_dps", 0.0)), 0.0)
	var dps: float = _sea_burn_dps + _sea_pressure * SEA_PRESSURE_MULT
	if _sea_drowning_s > 0.0:
		dps += SEA_DROWN_DPS
	if dps > 0.0:
		_sea_dps_debt += dps * delta
		if _sea_dps_debt >= 1.0:
			var dmg: int = int(_sea_dps_debt)
			_sea_dps_debt -= float(dmg)
			take_damage(dmg, null, "drowning")
	# Horizontal: the swim pace steers the existing velocity toward the
	# wish; the current RIDES ON TOP at its own speed (the ferry lane).
	var horiz: Vector3 = velocity - up * velocity.dot(up)
	var want: Vector3 = wish * (walk_speed * SEA_SWIM_MULT)
	horiz = horiz.lerp(want, clampf(SEA_STEER_PER_S * delta, 0.0, 1.0))
	horiz += _sea_flow
	_sea_carry = horiz
	# Vertical law: buoyancy settles on the waterline; crouch dives,
	# jump rises, and CRUSH ignores the wish (the ocean says no).
	var vertical: float = 0.0
	if band >= 4:
		vertical = SEA_SWIM_VERTICAL
		horiz = horiz.lerp(Vector3.ZERO, clampf(SEA_STEER_PER_S * delta, 0.0, 1.0))
	elif Input.is_action_pressed("crouch") and not _text_entry_focused():
		vertical = -SEA_SWIM_VERTICAL
	elif Input.is_action_pressed("jump"):
		vertical = SEA_SWIM_VERTICAL
	else:
		vertical = clampf((depth - SEA_FLOAT_DEPTH) * SEA_FLOAT_SPRING,
			-SEA_SWIM_VERTICAL, SEA_SWIM_VERTICAL)
	velocity = horiz + up * vertical
	move_and_slide()
	_validate_movement()
	return true


# ---- THE CONCORD-LOOP INTERACT (planar-retirement Step 1) ---------------
#
# The planar controller resolved E against the ancient_doors /
# concord_stones groups; the globe body never carried that path, so the
# Concord loop (once its props exist -- see globe_world._build_concord_loop)
# had no way to be triggered on the planet the player actually plays.
# These legs mirror player_controller's resolve law: nearest group member
# within a 4 m reach, the entity's own try_interact returns the
# {ok, message} contract, and the result toasts through NotificationService.

## E-to-use radius for the Concord props (mirrors the planar controller).
const CONCORD_INTERACT_RANGE: float = 4.0


## Wire the shared InputManager's "interact" action to this body (the
## planar controller's law: InputManager.player_input emits (action,
## pressed); the globe body never listened). Defensive + idempotent --
## script-mode probes mount no InputManager, and a re-enter must not
## double-connect.
func _connect_interact_input() -> void:
	var im := _im()
	if im == null or not im.has_signal("player_input"):
		return
	if not im.player_input.is_connected(_on_player_input):
		im.player_input.connect(_on_player_input)


## The shared player_input fan-out (planar-retirement Step 5 parity): the
## planar controller answered the whole action set here while the globe body
## answered only `interact`, so on the globe the player could not attack,
## target, or cast. These legs mirror the planar controller's exactly so
## keyboard, touch, and gamepad route through one surface on both bodies.
func _on_player_input(action: String, pressed: bool) -> void:
	if not is_local_player:
		return
	if pressed:
		_touch_activity()
	match action:
		"target_next":
			if pressed:
				cycle_target()
		"target_previous":
			if pressed:
				cycle_target_previous()
		"target_nearest":
			# F2: hard nearest-enemy select (Tab is camera-relative).
			if pressed:
				_find_and_set_nearest_target()
		"target_self":
			# F1: target yourself (healers/casters, self-buff flow).
			if pressed:
				var tm := _tm()
				if tm != null:
					tm.set_target(entity_id, "player", display_name, global_position, self, entity_type)
					is_targeting = true
		"interact":
			if pressed:
				_try_interact()
		"ability_1", "ability_2", "ability_3", "ability_4", \
		"ability_5", "ability_6", "ability_7", "ability_8":
			# Skill slots: keyboard 1-8 and touch skill buttons route here
			# through the same player_input signal.
			if pressed:
				var slot := int(action.replace("ability_", "")) - 1
				use_skill(slot)

## Crowd-control movement gate: false when any active status effect carries
## can_move == false (stun/root/snare from the .tres status-effect data).
func _can_move() -> bool:
	for effect in status_effects:
		if effect.has_method("allows_movement") and not effect.allows_movement():
			return false
	return true

## Basic attack (left-click / touch ATK / gamepad). The planar body's state
## machine polls Input.is_action_just_pressed("attack"); the globe body has no
## state machine, so _physics_process polls the same action edge and drives the
## swing straight through the shared combat entry point (create_hitbox) --
## exactly what the Attack state does.
func _try_attack() -> void:
	if _text_entry_focused():
		return
	var skill = basic_attack
	if skill == null or not skill.can_cast(self):
		return
	# A live target in range aims the swing; otherwise it lands in front of
	# the body (create_hitbox's own fallback), matching planar behavior.
	var target: Node = null
	var tm := _tm()
	if tm != null and tm.has_target():
		var info = tm.get_current_target()
		if info != null and is_instance_valid(info.node):
			target = info.node
	create_hitbox(skill, target)

## Tab: cycle to the next targetable in the camera's look direction (raycast
## first, nearest-enemy fallback), pushing the outgoing target onto the
## local history ring so Tab can walk back. Mirrors the planar controller's
## cycle_target.
func cycle_target() -> void:
	var tm := _tm()
	if tm == null:
		return
	var camera := _get_camera()
	var info = null
	if camera != null:
		var look_dir: Vector3 = -camera.global_transform.basis.z
		info = tm.get_target_in_direction(global_position, look_dir, 50.0)
	if info == null:
		_find_and_set_nearest_target()
		return
	_push_target_history()
	tm.set_target(
		info.id, info.schema_id, info.display_name, info.world_position,
		info.node, info.entity_type, info.metadata)
	is_targeting = true

## Shift+Tab: walk back through the local target ring.
func cycle_target_previous() -> void:
	var tm := _tm()
	if tm == null:
		return
	if _target_history.is_empty():
		# Nothing cycled yet: mirror the planar controller's history restore.
		tm.restore_previous()
		return
	var prev: Dictionary = _target_history.pop_back()
	if not is_instance_valid(prev.get("node")):
		return
	tm.set_target(
		str(prev.get("id", "")), str(prev.get("schema_id", "enemy")),
		str(prev.get("display_name", "")), prev.get("world_position", Vector3.ZERO),
		prev.get("node"), int(prev.get("entity_type", Entity.EntityType.ENEMY)),
		prev.get("metadata", {}))
	is_targeting = true

## F2: hard nearest-enemy select (distance only, no camera raycast).
func _find_and_set_nearest_target() -> void:
	var tm := _tm()
	if tm == null:
		return
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var nearest: Node3D = null
	var best_d: float = INF
	for e in enemies:
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		if not ("entity_id" in e):
			continue
		# Skip the dead: the corpse is still in the group until it frees.
		if e.has_method("is_alive") and not e.is_alive():
			continue
		var d: float = global_position.distance_to((e as Node3D).global_position)
		if d < best_d:
			best_d = d
			nearest = e
	if nearest == null:
		return
	_push_target_history()
	tm.set_target(
		str(nearest.get("entity_id")),
		"enemy",
		str(nearest.get("display_name")) if nearest.get("display_name") != null else "Enemy",
		(nearest as Node3D).global_position,
		nearest,
		Entity.EntityType.ENEMY)
	is_targeting = true

## Push the current target onto the local history ring (cap 8).
func _push_target_history() -> void:
	var tm := _tm()
	if tm == null or not tm.has_target():
		return
	var cur = tm.get_current_target()
	if cur == null:
		return
	_target_history.append({
		"id": cur.id,
		"schema_id": cur.schema_id,
		"display_name": cur.display_name,
		"world_position": cur.world_position,
		"node": cur.node,
		"entity_type": cur.entity_type,
		"metadata": cur.metadata,
	})
	if _target_history.size() > 8:
		_target_history.pop_front()

## The active camera (the globe scene parents it under CameraPivot).
func _get_camera() -> Camera3D:
	var pivot: Node3D = get_node_or_null("CameraPivot")
	if pivot != null and pivot.get_child_count() > 0:
		var cam = pivot.get_child(0)
		if cam is Camera3D:
			return cam
	return null

## The body's look direction (the planar controller's law, restored on the
## globe): a live target faces it, otherwise the camera pivot's forward. The
## HUD integrator feeds this to the minimap arrow heading
## (hud_integrator._process -> Minimap.set_player_rotation); without it the
## arrow froze at spawn heading -- the exact bug the heading feed fixed for
## the planar body, which the globe body silently re-opened.
func get_look_direction() -> Vector3:
	var tm := _tm()
	if is_targeting and tm != null and tm.has_method("get_current_target"):
		var info = tm.get_current_target()
		if info != null and info.node != null and is_instance_valid(info.node) and info.node is Node3D:
			var to_target: Vector3 = (info.node as Node3D).global_position - global_position
			if to_target.length_squared() > 0.0001:
				return to_target.normalized()
	var pivot: Node3D = get_node_or_null("CameraPivot")
	return -pivot.global_transform.basis.z if pivot != null else Vector3.ZERO

## Left/right click targeting + Escape clear (the planar controller's law).
## Left-click also swings (PC click-to-attack) via the polled `attack` action
## edge; the UI guard keeps clicks on HUD panels from firing into the world.
func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player:
		return
	if (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventKey and event.pressed):
		_touch_activity()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not _is_click_on_ui(event.position):
			_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and not _is_click_on_ui(event.position):
			_handle_right_click()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		clear_target()

func _handle_left_click(screen_pos: Vector2) -> void:
	var tm := _tm()
	var camera := _get_camera()
	if tm == null or camera == null:
		return
	var info = tm.raycast_from_camera(screen_pos, camera)
	if info != null:
		_push_target_history()
		tm.set_target(
			info.id, info.schema_id, info.display_name, info.world_position,
			info.node, info.entity_type, info.metadata)
		is_targeting = true
	else:
		clear_target()

func _handle_right_click() -> void:
	var tm := _tm()
	if tm != null and tm.has_target():
		_show_target_context_menu(tm.get_current_target())

func clear_target() -> void:
	var tm := _tm()
	if tm != null:
		tm.clear_target()
	is_targeting = false

## Clicks that land on a HUD Control belong to the UI, not the world.
func _is_click_on_ui(screen_pos: Vector2) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for control in tree.get_nodes_in_group("clickable"):
		if control is Control and Rect2(control.global_position, control.size).has_point(screen_pos):
			return true
	return false

## The context menu for the current target (the NPC walk-up fan-out: Talk /
## Quests / Trade / Blacksmith / ...). ActionMenu is code-built and parented
## to this body, the same construction the planar controller uses.
func _show_target_context_menu(info) -> void:
	if info == null:
		return
	if _action_menu == null:
		_action_menu = ActionMenu.new()
		add_child(_action_menu)
		_action_menu.action_selected.connect(_on_context_action)
	var at: Vector2 = get_viewport().get_visible_rect().size * 0.5
	_action_menu.show_menu(at, info.id, info.entity_type, info.npc_data if "npc_data" in info else null)

## Context-menu dispatch (the planar controller's vocabulary, ported whole).
## The world-facing legs resolve their own service/panel; the social
## player-menu legs (whisper/party/guild/friend/report/follow/inspect) reuse
## the HUD integrator's one handler so the menu vocabulary never forks.
func _on_context_action(action_id: String, target_id: String) -> void:
	match action_id:
		"talk":
			_open_npc_dialogue(target_id)
		"quest":
			_open_npc_quests(target_id)
		"trade":
			var info = _current_target_info()
			if info != null and info.id == target_id and info.entity_type == Entity.EntityType.NPC:
				_open_npc_vendor(target_id, info)
			else:
				var trade_svc = get_node_or_null("/root/TradeService")
				if trade_svc != null and trade_svc.has_method("initiate_trade"):
					trade_svc.initiate_trade(str(entity_id), target_id)
		"bank":
			var mm := _mmgr()
			if mm != null:
				mm.open_menu("bank", _menu_anchor_pos(target_id))
		"premium":
			var mm_v := _mmgr()
			if mm_v != null:
				mm_v.open_menu("premium", _menu_anchor_pos(target_id))
		"skill_academy":
			_open_skill_academy_ui()
			_attach_npc_panel_proximity(_skill_academy_ui, target_id)
		"blacksmith":
			_open_blacksmith_ui()
			_attach_npc_panel_proximity(_blacksmith_ui, target_id)
		"character_stats":
			_open_character_stats_ui()
		"craft":
			_open_workbench_ui()
		"loot":
			_pickup_loot_target(target_id)
		"pass":
			var loot_svc = get_node_or_null("/root/LootService")
			if loot_svc != null and loot_svc.has_method("pass_loot"):
				loot_svc.pass_loot(target_id, str(entity_id))
		"enter":
			_activate_gateway_target(target_id)
		"ankh_set":
			_handle_ankh_action("bind", target_id)
		"ankh_info":
			_handle_ankh_action("info", target_id)
		"queue_bout", "leave_bout_queue":
			# Bout stones: one implementation shared with the HUD menu.
			var tm := _tm()
			if tm != null and tm.has_method("execute_action_on"):
				tm.execute_action_on(action_id, target_id)
		"check_lobby":
			var mm_l := _mmgr()
			if mm_l != null:
				mm_l.open_menu("lobby")
		_:
			# Social legs (whisper/party/guild/friend/report/follow/inspect) live
			# in the HUD integrator's one handler -- reuse it rather than forking
			# the menu vocabulary on the globe body.
			_route_social_action(action_id, target_id)

func _current_target_info():
	var tm := _tm()
	return tm.get_current_target() if tm != null else null

func _menu_anchor_pos(target_id: String) -> Vector3:
	var info = _current_target_info()
	if info != null and info.id == target_id:
		return info.world_position
	return Vector3.ZERO

## Reuse the HUD integrator's action handler for the social menu legs (one
## implementation). No-op when no HUD is mounted (script-mode probes).
func _route_social_action(action_id: String, target_id: String) -> void:
	var hi := _hud_integrator()
	if hi == null:
		return
	if hi.has_method("handle_context_action"):
		hi.handle_context_action(action_id, target_id)
	elif hi.has_method("_on_action_selected"):
		hi.call("_on_action_selected", action_id, target_id)

## The live HUD integrator node (the social menu handler). HudLayer is
## scene-parented on the globe (installed by HudLayer.ensure_installed), so
## resolve through the scene root first, then the tree root.
func _hud_integrator() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	if tree.current_scene != null:
		var hi: Node = tree.current_scene.get_node_or_null("HudLayer/HudIntegrator")
		if hi != null:
			return hi
	return tree.root.get_node_or_null("HudLayer/HudIntegrator")

func _open_npc_dialogue(target_id: String) -> void:
	var npc_data = _npc_data_for_target(target_id)
	if npc_data == null:
		return
	var dialogue_id: String = npc_data.get_dialogue_id()
	if dialogue_id.is_empty():
		return
	var ds := _dialog_svc()
	if ds != null and ds.start_dialogue(target_id, dialogue_id):
		var gl := _glog()
		if gl:
			gl.info("GlobeWorldPlayer: dialogue started with %s (%s)" % [target_id, dialogue_id])

func _open_npc_quests(target_id: String) -> void:
	var npc_data = _npc_data_for_target(target_id)
	if npc_data == null:
		return
	var quest_ids: Array = []
	for inc: Dictionary in npc_data.includes:
		var t := str(inc.get("type", ""))
		if t == "quest":
			# Inline shape: quest_ids array. Ref shape: the ref_id IS the
			# quest id (data/quests/<ref_id>.tres carries it as its own id).
			var qids: Variant = inc.get("quest_ids")
			if qids is Array:
				quest_ids = qids
			elif str(inc.get("ref_id", "")) != "":
				quest_ids = [str(inc.get("ref_id"))]
			if not quest_ids.is_empty():
				break
		if t == "offering":
			var res := load("res://data/npc_offerings/%s.tres" % str(inc.get("ref_id", "")))
			if res != null and str(res.get("type")) == "quest":
				var qids2: Variant = res.get("quest_ids")
				if qids2 is Array:
					quest_ids = qids2
				break
	if quest_ids.is_empty():
		return
	var mm := _mmgr()
	if mm != null:
		mm.open_menu("quests")
		var panel: Control = mm.get_panel_node("quests") if mm.has_method("get_panel_node") else null
		if panel and panel.has_method("refresh_quest_list"):
			panel.refresh_quest_list()

func _open_npc_vendor(target_id: String, info) -> void:
	var npc_data = _npc_data_for_target(target_id)
	var vendor_offering: Resource = npc_data.get_vendor_offering() if npc_data != null else null
	if vendor_offering == null:
		return
	var npc_pos: Vector3 = info.world_position if info != null else Vector3.ZERO
	var ShopUI = load("res://ui/components/shop_ui.gd")
	ShopUI.open_for_offering(str(entity_id), vendor_offering, npc_data, npc_pos)

## Resolve the live NPCData for a target id (entity node first, then the
## TargetingManager snapshot). Ported from the planar controller so the
## globe's NPC menu reads the same data truth.
func _npc_data_for_target(target_id: String):
	var es := _entity_svc()
	if es != null and es.has_method("get_entity"):
		var npc = es.get_entity(target_id)
		if npc != null and is_instance_valid(npc) and "npc_data" in npc and npc.npc_data != null:
			return npc.npc_data
	var info = _current_target_info()
	if info != null and info.id == target_id and "npc_data" in info and info.npc_data != null:
		return info.npc_data
	return null

## MenuManager is scene-parented (under the scene's HudLayer), not an
## autoload: resolve through root, then the HudLayer fallback (the planar
## controller's law).
func _mmgr() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	if tree.root:
		var mm: Node = tree.root.get_node_or_null(NodePath("MenuManager"))
		if mm != null:
			return mm
	if tree.current_scene != null:
		var hud: Node = tree.current_scene.get_node_or_null("HudLayer")
		if hud != null:
			return hud.get_node_or_null("MenuManager")
	return null

func _entity_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("EntityService")) if tree and tree.root else null

func _dialog_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("DialogService")) if tree and tree.root else null

func _open_blacksmith_ui() -> void:
	if _blacksmith_ui == null:
		var BlacksmithUI = load("res://ui/components/blacksmith_ui.gd")
		_blacksmith_ui = BlacksmithUI.new()
		add_child(_blacksmith_ui)
	_blacksmith_ui.set_inventory(inventory_component)
	_blacksmith_ui.open_for_player(entity_id if entity_id != "" else str(name))

func _open_workbench_ui() -> void:
	if _workbench_ui == null:
		var WorkbenchUI = load("res://ui/components/workbench_ui.gd")
		_workbench_ui = WorkbenchUI.new()
		add_child(_workbench_ui)
	_workbench_ui.set_inventory(inventory_component)
	_workbench_ui.open_for_player(entity_id if entity_id != "" else str(name), 0)

## The skill academy panel (the NPC menu's Skill Academy leg). Opens with the
## player's character data + inventory skill books, mirroring the planar
## controller's _open_skill_academy_ui.
func _open_skill_academy_ui() -> void:
	if _skill_academy_ui == null:
		var SkillAcademyUI = load("res://ui/components/skill_academy_ui.gd")
		_skill_academy_ui = SkillAcademyUI.new()
		add_child(_skill_academy_ui)
	var pid: String = entity_id if entity_id != "" else str(name)
	_skill_academy_ui.load_player_context(pid)
	_skill_academy_ui.open_with_context(pid, _get_character_data(), _get_inventory_books())

## The character stats panel (the NPC menu's Character Stats leg).
func _open_character_stats_ui() -> void:
	if _character_stats_ui == null:
		var CharacterStatsUI = load("res://ui/menus/character_stats_ui.gd")
		_character_stats_ui = CharacterStatsUI.new()
		add_child(_character_stats_ui)
	_character_stats_ui.open(entity_id if entity_id != "" else str(name))

## The selected character's data (the boot loader's pick), when a GameManager
## is present. Script-mode probes have none -- the panels tolerate null.
func _get_character_data():
	var gm = get_node_or_null("/root/GameManager")
	if gm != null and "selected_character_data" in gm and is_instance_valid(gm.selected_character_data):
		return gm.selected_character_data
	return null

## The SkillBook items in the player's own inventory (the academy's list).
func _get_inventory_books() -> Array:
	var books: Array = []
	var inv = inventory_component
	var inv_svc := _inv_svc()
	if inv_svc != null and inv_svc.has_method("get_inventory"):
		var registered = inv_svc.get_inventory(entity_id if entity_id != "" else str(name))
		if registered != null:
			inv = registered
	if inv != null and inv.has_method("get_all_items"):
		for item in inv.get_all_items():
			if item is SkillBook:
				books.append(item)
	return books

## The NPC-panel attach law: a panel opened from an NPC's action menu binds to
## that NPC's position and auto-closes when the player walks away. Ported from
## the planar controller so the globe's NPC panels share the walk-away law.
func _attach_npc_panel_proximity(panel: Node, target_id: String) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	if not "set_npc_proximity" in panel:
		return
	var info = _current_target_info()
	if info == null or info.id != target_id or info.entity_type != Entity.EntityType.NPC:
		return
	var npc_pos: Vector3 = info.world_position
	if npc_pos == Vector3.ZERO and info.node != null and is_instance_valid(info.node) and info.node is Node3D:
		npc_pos = (info.node as Node3D).global_position
	if npc_pos != Vector3.ZERO:
		panel.call("set_npc_proximity", npc_pos)

func _pickup_loot_target(target_id: String) -> void:
	var loot := _ground_loot()
	if loot != null and loot.has_method("pickup_target"):
		loot.pickup_target(target_id, self)
	elif loot != null and loot.has_method("try_pickup"):
		loot.try_pickup(self)

func _activate_gateway_target(target_id: String) -> void:
	var tm := _tm()
	if tm != null and tm.has_method("execute_action_on"):
		tm.execute_action_on("enter", target_id)

func _handle_ankh_action(kind: String, target_id: String) -> void:
	var tm := _tm()
	if tm == null:
		return
	var tdata: Dictionary = tm.get_targetable(target_id) if tm.has_method("get_targetable") else {}
	var ankh = tdata.get("node", null)
	if ankh == null or not is_instance_valid(ankh) or not ankh.has_method("bind_player"):
		return
	var notify := _notify_svc()
	if kind == "info":
		if ankh.has_method("get_respawn_info") and notify != null and notify.has_method("notify"):
			var info: Dictionary = ankh.get_respawn_info(self)
			notify.notify(
				NotifKind.CUSTOM,
				"%s (%s) -- respawn x%.2f in %s" % [
					str(ankh.get("display_name")), info.get("ankh_type", "ANKH"),
					float(info.get("respawn_time_modifier", 1.0)), info.get("zone_id", "?")],
				"Ankh", "ankh_info:%s" % target_id, info)
		return
	var ok: bool = bool(ankh.bind_player(self))
	if notify != null and notify.has_method("notify"):
		if ok:
			notify.notify(
				NotifKind.CUSTOM,
				"Respawn point set: %s. You will revive here." % str(ankh.get("display_name")),
				"Ankh", "ankh_bind:%s:ok" % target_id, {"ankh_id": target_id})
		else:
			notify.notify(
				NotifKind.CUSTOM, "This ankh resists your touch.",
				"Ankh", "ankh_bind:%s:refused" % target_id, {"ankh_id": target_id})


## Interact dispatch (E / gamepad A / touch ACT). The Concord loop's
## props are the globe's interactables today; other world interactables
## join this dispatch as they are ported (planar-retirement Steps 2-3).
func _try_interact() -> void:
	# Ground loot first (the planar controller's order): the nearest drop
	# in range wins; only when nothing was picked up do the props resolve.
	var loot := _ground_loot()
	if loot != null and loot.has_method("try_pickup"):
		var picked: Array = loot.try_pickup(self)
		if not picked.is_empty():
			return
	# Positional props win: standing on a station / ankh / door / stone and
	# pressing E activates THAT prop (the player is on it, not near it).
	if _use_nearby_placed_station():
		return
	if _activate_nearby_ankh():
		return
	if _activate_nearby_ancient_door():
		return
	if _activate_nearby_concord_stone():
		return
	# THE ACTION MENU for NPCs/gates in arm's reach (the walk-up-and-press
	# loop beat): nearest-in-range resolve + centered menu, no cursor needed.
	if _try_target_context_interact():
		return
	# Gates are not menu targetables; the direct leg enters them when no
	# NPC/menu target is in range.
	if _activate_nearby_moon_gate():
		return


## Interact-menu range (mirrors the planar controller).
const INTERACT_MENU_RANGE: float = 6.0


## Walk up to an NPC or a gate, press E -- the press TARGETS the nearest
## interactable still in range (a live target in range wins) and opens ITS
## action menu. Ported from the planar controller so the globe's NPC loop
## (Talk/Quests/Trade/Blacksmith) matches the planar one. Returns true when
## a menu opened.
func _try_target_context_interact() -> bool:
	var tm := _tm()
	if tm == null:
		return false
	var types: Array[int] = [Entity.EntityType.NPC, Entity.EntityType.TELEPORT]
	var info = tm.get_nearest_targetable_by_types(global_position, types, INTERACT_MENU_RANGE)
	var cur = tm.get_current_target()
	if cur != null and types.has(cur.entity_type):
		# A live target in range outranks the nearest scan -- the player
		# SAID who they meant.
		if is_instance_valid(cur.node) and cur.node is Node3D \
				and global_position.distance_to((cur.node as Node3D).global_position) <= INTERACT_MENU_RANGE:
			if "npc_data" in cur.node:
				cur.npc_data = cur.node.npc_data
			info = cur
	if info == null:
		return false
	if cur == null or cur.id != info.id:
		tm.set_target(
			info.id, info.schema_id, info.display_name, info.world_position,
			info.node, info.entity_type, info.metadata)
		info = tm.get_current_target()
	is_targeting = true
	_show_target_context_menu(info)
	return true


## A placed crafting/repair station in range: open ITS UI at ITS station
## (repair -> BlacksmithUI; crafting_* -> WorkbenchUI at the
## STATION_FUNCTIONS id). Ported from the planar controller so the
## housing loop (DwellingService.place_station) is usable on the globe.
func _use_nearby_placed_station() -> bool:
	var dw = get_node_or_null("/root/DwellingService")
	if dw == null or not dw.has_method("resolve_nearby_station"):
		return false
	var hit: Dictionary = dw.resolve_nearby_station(self)
	if not bool(hit.get("ok", false)):
		return false
	var pid: String = entity_id if entity_id != "" else str(name)
	var inventory = null
	var inv_svc := _inv_svc()
	if inv_svc != null and inv_svc.has_method("get_inventory"):
		inventory = inv_svc.get_inventory(pid)
	if inventory == null:
		inventory = inventory_component
	var function := str(hit.get("function", ""))
	if function == "blacksmith":
		var BlacksmithUI = load("res://ui/components/blacksmith_ui.gd")
		var ui = BlacksmithUI.new()
		add_child(ui)
		ui.set_inventory(inventory)
		ui.open_for_player(pid)
		return true
	var stations: Dictionary = dw.STATION_FUNCTIONS if "STATION_FUNCTIONS" in dw else {}
	var station: int = int(stations.get(function, -1))
	if station < 0:
		return false
	var WorkbenchUI = load("res://ui/components/workbench_ui.gd")
	var wb = WorkbenchUI.new()
	add_child(wb)
	wb.set_inventory(inventory)
	wb.open_for_player(pid, station)
	return true


## Nearest "ankhs" group member within its own activation range; binds
## the respawn point through the ankh's own bind_player (the planar
## controller's law). Returns true only when a bind happened (an
## out-of-scope or dead refusal falls through to the next interactable).
func _activate_nearby_ankh() -> bool:
	var best: Node3D = null
	var best_dist: float = INF
	for ankh in get_tree().get_nodes_in_group("ankhs"):
		if ankh == null or not is_instance_valid(ankh) or not (ankh is Node3D):
			continue
		if ankh.has_method("is_within_activation_range") \
				and not ankh.is_within_activation_range(global_position):
			continue
		var d: float = global_position.distance_to((ankh as Node3D).global_position)
		if d < best_dist:
			best_dist = d
			best = ankh
	if best == null or not best.has_method("bind_player"):
		return false
	var notify := _notify_svc()
	if best.bind_player(self):
		if notify != null and notify.has_method("notify_ankh_bound"):
			notify.notify_ankh_bound(entity_id, str(best.get("display_name")))
		return true
	# Scoped ankhs explain themselves (guild/faction/personal denials) the
	# same way the planar controller does.
	var reason: String = ""
	if best.has_method("describe_bind_denial"):
		reason = str(best.describe_bind_denial(self))
	if notify != null and notify.has_method("notify"):
		notify.notify(
			NotifKind.PLAYER_WARNED,
			"You cannot bind to %s yet. (%s)" % [str(best.get("display_name")), reason],
			"GlobeWorldPlayer",
			"ankh_deny:%s:%s" % [str(best.get("ankh_id")), reason],
			{}, entity_id
		)
	return false


## Nearest "moon_gates" group member in range; the gate returns the same
## {ok, message} contract as the ancient door (mirrors the planar
## controller's _activate_nearby_moon_gate).
func _activate_nearby_moon_gate() -> bool:
	var best: Node3D = _nearest_in_group("moon_gates")
	if best == null:
		return false
	var result: Dictionary = best.try_interact(self)
	var notify := _notify_svc()
	if notify != null:
		notify.notify(
			NotifKind.CUSTOM if bool(result.get("ok", false)) else NotifKind.PLAYER_WARNED,
			str(result.get("message", "")),
			"MoonGate",
			"moon_gate:%s:%d" % [str(best.name), Time.get_ticks_msec()],
			{"gate": str(best.name), "ok": bool(result.get("ok", false))},
			entity_id
		)
	return true


## Nearest "ancient_doors" group member within reach; the door returns
## the {ok, message} contract and the result toasts (mirrors
## player_controller._activate_nearby_ancient_door).
func _activate_nearby_ancient_door() -> bool:
	var best: Node3D = _nearest_in_group("ancient_doors")
	if best == null:
		return false
	var result: Dictionary = best.try_interact(self)
	var notify := _notify_svc()
	if notify != null:
		notify.notify(
			NotifKind.CUSTOM if bool(result.get("ok", false)) else NotifKind.SIGN_INSIGHT_RECORDED,
			str(result.get("message", "")),
			"AncientDoor",
			"ancient:interact:%s:%d" % [str(best.name), Time.get_ticks_msec()],
			{"door": str(best.name), "ok": bool(result.get("ok", false))}
		)
	return true


## Nearest "concord_stones" group member within reach; the stone records
## the window insight through SignService and returns the same contract.
func _activate_nearby_concord_stone() -> bool:
	var best: Node3D = _nearest_in_group("concord_stones")
	if best == null:
		return false
	var result: Dictionary = best.try_interact(self)
	var notify := _notify_svc()
	if notify != null:
		notify.notify(
			NotifKind.CUSTOM if bool(result.get("ok", false)) else NotifKind.SIGN_INSIGHT_RECORDED,
			str(result.get("message", "")),
			"ConcordStone",
			"concord:%s:%d" % [str(best.name), Time.get_ticks_msec()],
			{"stone": str(best.name), "ok": bool(result.get("ok", false))}
		)
	return true


## Nearest live group member within CONCORD_INTERACT_RANGE, or null.
func _nearest_in_group(group: String) -> Node3D:
	var best: Node3D = null
	var best_dist: float = INF
	for n in get_tree().get_nodes_in_group(group):
		if n == null or not is_instance_valid(n) or not (n is Node3D):
			continue
		var d: float = global_position.distance_to((n as Node3D).global_position)
		if d < best_dist:
			best_dist = d
			best = n
	if best == null or best_dist > CONCORD_INTERACT_RANGE:
		return null
	return best

