## GlobeWorld - spherical-world scene root (prd-spherical-mvp.md S3).
## Builds the shell (visual sphere + sphere-shell collider), the player,
## the sun, and the arena gateway. The playable HUD is installed by the
## shared HudLayer.ensure_installed() init so every playable scene gets
## the same composition.
##
## S8 FLOATING ORIGIN: everything planet-bound (shell, streamed
## patches, surface pad) lives under world_root; the player is a direct
## child of this scene and stays near the world origin. When the player
## drifts past SHIFT_RADIUS, the whole planet is translated back around
## it (_maybe_shift_world). At planet scale ground support is a single
## re-anchored surface pad (see _build_surface_pad) - the megasphere
## SphereShape and face-scale patch trimeshes both degenerate at
## R = 20 km (measured, S8).
extends Node3D

## Named collision bits (round 10): data/physics_layers/ LayerProfile.
const Layers = preload("res://core/schemas/layer_profile.gd")

const PLAYER_SKIN: float = 1.0
## Visual shell sits slightly above the collider to avoid z-fighting.
const SKIN_THICKNESS: float = 0.5
## Configurable planet scale: `synmergia/world/planet_radius` (meters).
## Default 100 = the prototype globe; 20000 = the v1 planet scale
## (prd.md). S8 probe verifies systems at both scales.
const PLANET_RADIUS_SETTING: String = "synmergia/world/planet_radius"
## S8: keep in sync with globe_terrain_streamer.TILE_LIFT (0.52) --
## the walk surface sits this far above the base shell when the
## terrain streamer is on. (Constant mirrored rather than preloaded
## to keep the scene's load order simple.)
const STREAMER_TILE_LIFT: float = 0.52
## S8: shells larger than this cannot resolve a 1 m body contact
## (stall threshold measured between 2 km and 10 km; conservative
## cutoff). Above it, patch trimeshes carry the collision.
const PLANAR_SHELL_MAX_R: float = 2000.0
## S8 surface pad geometry: curved disc, outer ring radius in meters
## and ring segment count. Local shape coordinates stay <= PAD_RADIUS
## (physics needs SMALL shape coordinates); the pad hugs the sphere
## via the exact sagitta per ring.
const PAD_RADIUS: float = 64.0
const PAD_SEGMENTS: int = 16
const SPAWN_LAT_DEG: float = 0.0
const SPAWN_LON_DEG: float = 0.0
const WALK_SECONDS: float = 30.0
## ~40% of a full equator lap at 6 m/s on a 100 m sphere.
const WALK_DISTANCE_METERS: float = 250.0

var planet_radius: float = 100.0
## S8: the shell's CollisionShape3D, disabled at planet scale (see
## PLANAR_SHELL_MAX_R); the re-anchored surface pad takes over.
var shell_col: CollisionShape3D
## S8: the planet-scale ground collider, re-anchored under the player
## every physics frame (null at prototype scale; see _build_surface_pad).
var surface_pad: StaticBody3D
## S8: how many floating-origin rebases have run (probe observability).
var scene_shift_count: int = 0
## S8 FLOATING ORIGIN: everything that lives on the planet (shell,
## streamed patches, probe markers) is a child of this node. When the
## player drifts past SHIFT_RADIUS from the world origin, the whole
## world root is translated by -player_offset so the player re-lands
## near the origin and every float32 transform stays small.
var world_root: Node3D
## World-space position of the planet center == world_root.position
## (the planet is centered on the world root by construction).
var planet_center: Vector3 = Vector3.ZERO
## S8: how far the player may drift from the world origin before the
## world is shifted back. 1500 m is comfortably inside the measured
## stall threshold (~2 km walks free, ~5 km degraded).
const SHIFT_RADIUS: float = 1500.0

## S5: when true the ground visual is STREAMED face patches (the
## sphere StaticBody stays the physics truth either way).
var stream_terrain: bool = true

## WATER (terrain arc): at planet scale the scene paints a water shell
## at the terrain sea line (TerrainGen.sea_level). The shell is visual
## only -- the floor is the displaced terrain itself (the ocean depth
## law: the sea floor IS the ground law, no second collision truth).
const WATER_ON: bool = true
var water_body: MeshInstance3D = null

var streamer  # GlobeTerrainStreamer; untyped - preload-by-path pattern

var player  # GlobeWorldPlayer; untyped on purpose - set_script + dynamic
# dispatch keeps this scene free of parse-time class_name dependencies.

## S14-web: the playable HUD. Kept as a thin wrapper for back-compat:
## the real install is the shared HudLayer.ensure_installed() init
## (feedback #5 -- one cohesive playable-HUD system loaded the same way
## on every playable scene).
var hud: CanvasLayer = null
## Spawn-truth throttle (round 7, item 4): the on-screen lat/lon/
## height line refreshes twice a second, not every physics tick.
var _truth_accum: float = 0.0
## The truth line itself (built into the playable HUD CanvasLayer).
var _truth_label: Label = null

## CHART-LOD GLUE (turn 8): the scene-level wiring -- the adapter feeds
## the player's live lat/lon into the PenroseChartLod policy and turns
## the emitted work orders into REAL MeshInstance3D chart overlays
## under world_root (PenroseMeshBuilder draw + skirt_strip rims).
## Untyped per this scene's preload-by-path dispatch law.
var chart_lod  # PenroseChartAdapter; untyped - preload-by-path pattern
var chart_lod_root: Node3D = null
## chart_index -> MeshInstance3D of the current climb overlay.
var _chart_nodes: Dictionary = {}
## LOD tick throttle: the policy is cheap but the ORDER consumer is a
## mesh build; run at 2 Hz alongside the truth line.
var _chart_accum: float = 0.0
## Last observer lat/lon fed to the adapter (probe readout).
var last_chart_lat: float = 0.0
var last_chart_lon: float = 0.0


func _ready() -> void:
	# The canon radius comes from world_main.tres (20000, the v1 planet
	# scale); the project setting must match it (AGENTS data law: the
	# .tres is the declaration). The 100 m prototype is a TEST scale --
	# probes pin it explicitly; the shipped game boots the real planet
	# (terrain heightfield, ocean, island -- all planet-scale systems).
	planet_radius = float(ProjectSettings.get_setting(PLANET_RADIUS_SETTING, 20000.0))
	# S8 floating origin: planet-bound content lives under world_root.
	world_root = Node3D.new()
	world_root.name = "WorldRoot"
	add_child(world_root)
	_build_shell()
	_build_surface_pad()
	_install_world_backend()
	_build_sun()
	_build_sky_sun()
	_build_sky_moon()
	# Streamer FIRST: the player spawn height rides the terrain law
	# (walk surface at the spawn direction), so the ground must exist
	# before the boot lands on it.
	_setup_streamer()
	_build_water()
	_build_arena_gateway()
	_build_starter_village()
	_build_capitol_monolith()
	_build_player()
	_setup_ambience()
	planet_center = world_root.position
	player.planet_center = planet_center
	_install_hud()
	_setup_touch_hud()
	# SPAWN TRUTH (play-test round 7, item 4): the Android reporter
	# cannot read GameLog, so the boot/terrain truth also lives ON
	# SCREEN -- one small line, top-right of the playable HUD: lat/lon,
	# ground height, sea line. The next "I spawned on the ocean" report
	# settles WHERE and WHETHER with one glance (WET vs dry). Built
	# HERE, after _install_hud(): _build_player runs before the HUD
	# exists, and the line parents into it.
	_build_spawn_truth()


## THE AUTHORED TERRAFORM (data-driven, backend-seam-first): the
## world's WorldData declares `terrain_backend_id` -- which authored
## heightfield legally reshapes THIS world's raw land. Empty = the
## natural analytic law (no declaration, no install). THE STREAMER
## MUST SEE IT: install BEFORE _setup_streamer() reads its first
## height, so patch 0 renders the authored world, not a two-frame
## flash of the natural one. The id resolves through the BACKEND
## REGISTRY (terrain backends class_name map); an unknown id is a
## DATA error and logs loud (fail the lore, not the boot -- the
## natural law still renders and the world stays playable).
func _install_world_backend() -> void:
	var wd = _world_data()
	if wd == null or str(wd.terrain_backend_id).is_empty():
		return
	var ids := str(wd.terrain_backend_id)
	var script_path := "res://scenes/worlds/backend_%s.gd" % ids
	if not ResourceLoader.exists(script_path):
		_log_backend("error", "world '%s' declares terrain_backend_id '%s' -- no res://scenes/worlds/backend_%s.gd. Natural law renders; fix the declaration or ship the backend." % [wd.id, ids, ids])
		return
	var backend_script = load(script_path)
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	Gen.install_terrain_backend(Callable(backend_script, "field"))
	_log_backend("info", "authored terrain backend '%s' installed for world '%s' (the strait is real)" % [ids, wd.id])


## The islands-suite law: bare autoload reads fail --script-mode
## compilation, so every autoload touch goes through root lookup.
func _log_backend(level: String, msg: String) -> void:
	var log4 = get_node_or_null("/root/GameLog")
	if log4 == null:
		return
	var callable: Callable = Callable(log4, level)
	if callable.is_valid():
		callable.call(msg)


## This scene's WorldData: probed via the boot sequence's world id if
## available (meta "world_id" set by the boot/lobby journey), else
## the MAIN world (the playable home is world_main's declaration).
func _world_data():
	var wid := str(get_meta("world_id", "main"))
	var reg = get_node_or_null("/root/WorldRegistry")
	if reg != null and reg.has_method("get_world"):
		return reg.get_world(wid)
	var packed = load("res://data/worlds/world_%s.tres" % wid)
	return packed if packed != null else null


## S8 floating-origin rebase: when the player has drifted SHIFT_RADIUS
## from the world origin, translate world_root (the whole planet) by
## -player_offset. The player's next global transform is then near
## origin (small float32 magnitude) while the planet geometry is
## unchanged. The player's planet_center reference is re-read from the
## moved world_root; nothing else needs to know.
func _maybe_shift_world() -> void:
	if player == null:
		return
	var offset: Vector3 = player.global_position
	if offset.length() < SHIFT_RADIUS:
		return
	# Translate the planet so the player's next position re-lands near
	# the world origin...
	world_root.position -= offset
	planet_center = world_root.position
	# ...and move the player body by the SAME delta. The body's own
	# transform is exactly what floating origin fixes (measured: at
	# |r| ~20 km the body's float32 integration stalls locomotion even
	# on a perfect local floor); the planet geometry is what "moves".
	# Zeroing velocity drops the pre-shift motion so no stale slide
	# survives the teleport.
	player.global_position -= offset
	player.velocity = Vector3.ZERO
	player.planet_center = planet_center
	scene_shift_count += 1
	# Streamer patches are planet-relative children of world_root, so
	# the shift moves them for free. Re-anchor the pad under the moved
	# player now (its next move_and_slide must find ground) and reset
	# the loop metrics for honest post-shift walk measurements.
	_update_surface_pad()
	player.begin_loop()


## S14-web: instantiate the playable HUD. The globe previously booted
## bare (no menus, no bars, no touch controls) because the HUD lived
## only inside world_playable.tscn and this scene builds itself at
## runtime. Same composition, one CanvasLayer, added last so it draws
## above the world.
func _install_hud() -> void:
	if hud != null:
		return
	HudLayer.ensure_installed(self)
	hud = get_node_or_null("HudLayer") as CanvasLayer
	if hud != null:
		GameLog.info("GlobeWorld: playable HUD installed")


## Bridge the touch HUD into the globe player's camera (same shape as
## WorldPlayable._setup_touch_hud): the VirtualJoystick emits
## camera_look in raw pixel deltas; the player's orbit_camera turns
## them into yaw/pitch on the local tangent frame.
func _setup_touch_hud() -> void:
	if player == null or not player.has_method("orbit_camera"):
		return
	var joystick = InputManager.get_virtual_joystick() if InputManager else null
	if joystick == null:
		return
	var cam_speed: float = 0.003
	var sensitivity: float = 1.0
	if "sensitivity" in player:
		sensitivity = float(player.sensitivity)
	var look_handler := func(delta_px: Vector2) -> void:
		player.orbit_camera(delta_px.x * cam_speed * 1.5 * sensitivity, \
			delta_px.y * cam_speed * 1.5 * sensitivity)
	if not joystick.camera_look.is_connected(look_handler):
		joystick.camera_look.connect(look_handler)
	GameLog.info("GlobeWorld: touch HUD wired to orbit_camera")


func _setup_streamer() -> void:
	if not stream_terrain:
		return
	streamer = load("res://scenes/worlds/globe_terrain_streamer.gd").new()
	streamer.configure(planet_radius, 7.0, world_root)
	# Terrain arc: the heightfield joins the tiles at planet scale only
	# (prototype stays the flat shell -- every S5b/S8 probe contract
	# keeps its geometry).
	streamer.terrain_on = planet_radius > PLANAR_SHELL_MAX_R
	streamer.update(_spawn_dir() * planet_radius)
	_setup_chart_lod()
	# SPAWN MESH GATE (round 10): the boot must be able to SEE its own
	# ground. The first update is synchronous, so an unloaded spawn face
	# means the streamer is broken -- fail LOUD here instead of booting
	# over a bare water shell (the round-5/9 "spawned on the ocean"
	# reports were render-side; this gate splits loader failure from
	# renderer failure with one log line).
	var log4 = get_node_or_null("/root/GameLog")
	if streamer.is_loaded(streamer.current_face):
		if log4:
			log4.info("GlobeWorld: spawn face %d mesh-ready at boot (%d faces, %d tris)" % [streamer.current_face, streamer.active_faces().size(), streamer.triangle_count()])
	else:
		if log4:
			log4.error("GlobeWorld: spawn face %d did NOT load at boot -- the world will render as bare shell/water. Streamer load path is broken." % streamer.current_face)


## CHART-LOD GLUE setup: the adapter + the overlay root under
## world_root. Kept SEPARATE from the terrain streamer's heightfield
## patches: the chart overlays are the penrose lattice climbing
## beside it, occasionally denser but never competing with the
## heightfield's own seam laws (same takeaway as the prd's
## "rendering-engine heartbeat" scoping).
func _setup_chart_lod() -> void:
	# The adapter owns the policy chain (it preloads the LOD policy +
	# the pentagrid frame script itself).
	chart_lod = load("res://scenes/worlds/penrose_chart_adapter.gd").new()
	chart_lod_root = Node3D.new()
	chart_lod_root.name = "ChartLodRoot"
	world_root.add_child(chart_lod_root)


## The player's radial snap rides the WALK SURFACE (displaced terrain
## + seeded rock caps) via the streamer's single ground law. Callable
## receives the player's WORLD position; directions are derived
## relative to planet_center (floating origin: the world origin is
## NOT the planet center after the first shift). Installed by
## _build_player (the streamer is built first; the player second).
func _install_walk_provider() -> void:
	if streamer == null or player == null:
		return
	player.snap_height_provider = func(wpos: Vector3) -> float:
		var dir: Vector3 = (wpos - planet_center).normalized()
		return streamer.walk_surface_h(dir)


## Terrain-only read at a world position (the player's mobility law
## samples this seam so walk-over rock caps never read as hills).
func terrain_h_at(wpos: Vector3) -> float:
	if streamer == null:
		return 0.0
	return streamer.terrain_h((wpos - planet_center).normalized())


## The ford law's flag seam (globe_player.terrain_on_local resolves
## this up the parent chain): one truthful answer, no re-derivation.
func terrain_on_flag() -> bool:
	return streamer != null and streamer.terrain_on


## CHART-LOD GLUE tick (2 Hz alongside the truth line): feed the
## player's live lat/lon to the adapter, apply the padded skirts to
## the plan BEFORE ordering, then funnel each work order into a real
## mesh build (PenroseMeshBuilder for the surface + skirt_strip data
## appended as a third, darker surface). Empty delta = no-op.
##
## BOOT CRASH LAW (the play-day crash report: playable loads ~60 s,
## then dies; cold-start figure: ONE tick meshes ~42 chart overlays
## synchronously -- build_region + sphere projection + skirt PER
## CHART -- a multi-second main-thread hang in the boot window that
## starves the engine's progress signal and trips the shell watchdog).
## FIX, two layers:
##   1. GATE: overlay builds are OFF by default (chart_overlays_on =
##      false). The Turn-9 ground backend now carries the Penrose
##      identity on the REAL terrain, so the overlays are redundant
##      decoration; the policy/adapter probes still exercise the full
##      path by driving the funnel directly (probe_chart_lod_scene
##      flips the gate on).
##   2. BUDGET: when the gate is on, at most MAX_ORDERS_PER_TICK
##      meshes build per tick; the adapter's last_plan state only
##      advances for the orders actually APPLIED, so the rest re-queue
##      next tick (trickle, never a spike).
var chart_overlays_on: bool = false
const MAX_ORDERS_PER_TICK: int = 2
var _chart_room_x: float = 0.0
var _chart_room_y: float = 0.0
func _update_chart_lod(delta: float) -> void:
	if chart_lod == null or player == null:
		return
	_chart_accum += delta
	if _chart_accum < 0.5:
		return
	_chart_accum = 0.0
	var Sph = load("res://core/frame/math/spherical.gd")
	var dir: Vector3 = (player.global_position - planet_center).normalized()
	var ll: Vector2 = Sph.cartesian_to_spherical(dir * planet_radius, planet_radius)
	last_chart_lat = ll.x
	last_chart_lon = ll.y
	# The padded plan: settle seams first, then pad trailing rims so
	# orders carry the REAL skirt depth the seam needs right now.
	var policy = load("res://scenes/worlds/penrose_chart_lod.gd")
	var plan: Dictionary = policy.plan_safe(ll.x, ll.y, 1)
	var orders: Array = chart_lod.apply_plan(plan, 1)
	if orders.is_empty():
		return
	# BUDGET (the cold-start trickle): only the first
	# MAX_ORDERS_PER_TICK orders build this tick. The adapter's state
	# advances ONLY for what we apply, so unapplied orders re-queue on
	# the next 2 Hz tick — the boot window stays smooth and the shell
	# watchdog never starves.
	var applied: Array = orders.slice(0, MAX_ORDERS_PER_TICK)
	var deferred: Array = orders.slice(MAX_ORDERS_PER_TICK)
	if not deferred.is_empty():
		# Roll last_plan back to cover only the applied prefix, so the
		# deferred half re-emerges as the delta next tick.
		var partial: Dictionary = {}
		var applied_ids := {}
		for o in applied:
			applied_ids[int(o["chart_index"])] = true
		for i in chart_lod.last_plan:
			if applied_ids.has(int(i)):
				partial[i] = chart_lod.last_plan[i]
		chart_lod.last_plan = partial
	var builder = load("res://scenes/worlds/penrose_mesh_builder.gd")
	for o in applied:
		var idx: int = int(o["chart_index"])
		var center: Vector2 = load("res://core/frame/math/pentagrid.gd").atlas_centers_dense(1)[idx]
		var patch: Array = policy.PentagridScript.build_region(
			policy.PentagridScript.GAMMA, float(o["half_extent"]))
		var mi: MeshInstance3D = builder.build_instance(
			patch, "ChartLod_%d" % idx, false, 1.0, center.x, center.y, planet_radius)
		# Skirt rim: same patch, padded depth, sphere-projected -- append
		# as an extra darkened surface so the rim reads as seam fabric,
		# not terrain.
		var padded: float = chart_lod.padded_skirt(idx, plan, 1)
		var skirt: Dictionary = policy.PentagridScript.skirt_strip(patch, padded, 1.0, 0.0)
		if not (skirt["positions"] as PackedVector3Array).is_empty():
			var skirt_arrays := []
			skirt_arrays.resize(Mesh.ARRAY_MAX)
			skirt_arrays[Mesh.ARRAY_VERTEX] = _project_skirt(skirt["positions"], center, planet_radius)
			skirt_arrays[Mesh.ARRAY_NORMAL] = skirt_arrays[Mesh.ARRAY_VERTEX]
			skirt_arrays[Mesh.ARRAY_COLOR] = _skirt_colors((skirt_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), Color(0.16, 0.13, 0.10))
			mi.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, skirt_arrays)
		# Swap in the overlay root (planet-relative parent chain).
		var old: MeshInstance3D = _chart_nodes.get(idx, null)
		if old != null and is_instance_valid(old):
			old.queue_free()
		mi.name = "ChartLod_%d" % idx
		chart_lod_root.add_child(mi)
		_chart_nodes[idx] = mi


## Project skirt positions (planar tiling coords) onto the sphere via
## the chart's tangent plane, matching PenroseMeshBuilder's gnomonic
## path (the skirt lands exactly where the surface's rim dropped).
func _project_skirt(pos: PackedVector3Array, center: Vector2, radius: float) -> PackedVector3Array:
	var PG = load("res://core/frame/math/pentagrid.gd")
	var out := PackedVector3Array()
	for p in pos:
		# skirt_strip emits (x*scale, y*scale, z) in tiling units where
		# x,y already carry the scale: unpack to the planar Vector2 the
		# gnomonic path expects by undoing the z-only split.
		out.append(PG.gnomonic_project(Vector2(p.x, p.y), center.x, center.y, radius))
	return out


## Flat skirt colors (one authored color; the tag nuance is a
## future material pass).
func _skirt_colors(count: int, color: Color) -> PackedColorArray:
	var out := PackedColorArray()
	for _i in range(count):
		out.append(color)
	return out


func _physics_process(delta: float) -> void:
	if player == null:
		return
	# Pad first: the player's move_and_slide this frame must find
	# ground at its CURRENT position (this scene node processes before
	# its player child).
	_update_surface_pad()
	if streamer:
		# Planet-relative position: patches are parented planet-relative
		# under world_root, so face addressing uses the direction from
		# the planet CENTER, never the world origin (invariant across
		# floating-origin shifts).
		streamer.update(player.global_position - planet_center)
		if chart_overlays_on:
			_update_chart_lod(delta)
		else:
			_chart_accum = 0.0
	_maybe_shift_world()
	# SPAWN TRUTH (round 7, item 4): keep the on-screen position line
	# fresh at 2 Hz. No-op until _build_spawn_truth() made the label
	# (terrain globes with a playable HUD only).
	_truth_accum += delta
	if _truth_accum >= 0.5:
		_truth_accum = 0.0
		_update_spawn_truth()


func _build_shell() -> void:
	var shell := StaticBody3D.new()
	shell.name = "GlobeShell"
	shell.physics_material_override = PhysicsMaterial.new()
	shell.physics_material_override.friction = 1.0
	shell.physics_material_override.bounce = 0.0

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = planet_radius
	col.shape = sphere
	shell.add_child(col)
	# S8 fix: past PLANAR_SHELL_MAX_R the megasphere contact cannot
	# support a 1 m body (solver precision; the body sinks through at
	# |v_r| ~2.7 m/s and locomotion dies). The re-anchored surface pad
	# (see _build_surface_pad) becomes the physics truth instead, so
	# the sphere collider is disabled at planet scale. Visual mesh and
	# 100 m prototype behavior are unchanged.
	shell_col = col
	col.disabled = planet_radius > PLANAR_SHELL_MAX_R

	var mesh_inst := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = planet_radius + SKIN_THICKNESS
	mesh.height = (planet_radius + SKIN_THICKNESS) * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.55, 0.35)  # grass green
	mat.roughness = 0.95
	mesh.material = mat
	mesh_inst.mesh = mesh
	shell.add_child(mesh_inst)

	world_root.add_child(shell)


## S8 planet-scale ground support: ONE re-anchored surface pad.
## Measured (S8 experiments): the megasphere SphereShape cannot
## support a 1 m body at R = 20 km, and per-patch trimesh colliders
## carry face-scale local coordinates (a whole icosahedron face spans
## ~10 km at R = 20 km) that the concave solver also handles badly.
## The reliable primitive is a SMALL local collider with meter-scale
## coordinates re-anchored under the body every frame. The pad is a
## fixed curved disc (local coords <= PAD_RADIUS) whose rings dip by
## the exact spherical sagitta; only its transform ever changes.
func _build_surface_pad() -> void:
	if planet_radius <= PLANAR_SHELL_MAX_R:
		return
	var body := StaticBody3D.new()
	body.name = "SurfacePad"
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.friction = 1.0
	body.physics_material_override.bounce = 0.0
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	# Winding-independent: the pad is contacted from above only.
	shape.backface_collision = true
	shape.set_faces(_pad_faces())
	col.shape = shape
	body.add_child(col)
	world_root.add_child(body)
	surface_pad = body
	_update_surface_pad()


## The pad's fixed local-space triangles: center vertex ON the walk
## surface, two rings dipped by the sphere's sagitta at their chord
## distance (local y is radial: negative = below the surface).
func _pad_faces() -> PackedVector3Array:
	var faces: PackedVector3Array = PackedVector3Array()
	var ring_radii: Array = [PAD_RADIUS * 0.5, PAD_RADIUS]
	var rings: Array = []
	for d in ring_radii:
		var dip: float = planet_radius - sqrt(planet_radius * planet_radius - d * d)
		var ring: PackedVector3Array = PackedVector3Array()
		for i in range(PAD_SEGMENTS):
			var a: float = TAU * float(i) / float(PAD_SEGMENTS)
			ring.append(Vector3(cos(a) * d, -dip, sin(a) * d))
		rings.append(ring)
	var inner: PackedVector3Array = rings[0]
	var outer: PackedVector3Array = rings[1]
	for i in range(PAD_SEGMENTS):
		var j: int = (i + 1) % PAD_SEGMENTS
		faces.append(Vector3.ZERO)
		faces.append(inner[i])
		faces.append(inner[j])
		faces.append(inner[i])
		faces.append(outer[i])
		faces.append(outer[j])
		faces.append(inner[i])
		faces.append(outer[j])
		faces.append(inner[j])
	return faces


## Re-anchor the pad under the player: set the planet-relative
## transform from the player's current radial direction. Runs every
## physics frame BEFORE the player's move_and_slide, and again after
## every floating-origin shift.
func _update_surface_pad() -> void:
	if surface_pad == null or player == null:
		return
	var dir: Vector3 = (player.global_position - planet_center).normalized()
	surface_pad.position = dir * (planet_radius + _surface_lift())
	# Align local +Y with radial up. The disc is rotationally
	# symmetric, so only the up axis matters; keep the basis proper
	# (right-handed, same convention as the player camera).
	var north: Vector3 = Vector3(0, 1, 0)
	if abs(dir.dot(north)) > 0.999:
		north = Vector3(0, 0, -1)
	north = (north - dir * north.dot(dir)).normalized()
	var east: Vector3 = north.cross(dir)
	surface_pad.basis = Basis(east, dir, -north)


## Height of the WALKABLE SURFACE above planet_radius. At prototype
## scale the collision shell IS the walk surface (lift 0): the
## streamed tiles are visual-only there (no colliders, S5b) and the
## player must keep shell contact (probe_globe_world asserts radial
## rest). At planet scale the re-anchored pad carries the collision
## at planet_radius + TILE_LIFT + TERRAIN: the walk surface is the
## displaced terrain under the player (the streamer's ground law --
## the same law the snap provider rides), so hills lift the pad and
## the sea floor drops it.
func _surface_lift() -> float:
	if planet_radius <= PLANAR_SHELL_MAX_R:
		return 0.0
	if streamer == null:
		return STREAMER_TILE_LIFT
	var dir: Vector3 = _spawn_dir()
	if player != null:
		dir = (player.global_position - planet_center).normalized()
	return STREAMER_TILE_LIFT + streamer.terrain_h(dir)


## The spawn direction (unit) -- the scene's lat/lon convention.
func _spawn_dir() -> Vector3:
	var Sph = load("res://core/frame/math/spherical.gd")
	return Sph.spherical_to_cartesian(SPAWN_LAT_DEG, SPAWN_LON_DEG, 0.0, 1.0)


## WATER (terrain arc): one translucent shell at the sea line. Visual
## only: the ocean floor is the displaced terrain (one ground law; the
## sea floor IS the ground). Prototype globes stay dry (WATER_ON and
## planet scale both gate).
func _build_water() -> void:
	if not WATER_ON or planet_radius <= PLANAR_SHELL_MAX_R:
		return
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var sea: float = Gen.sea_level(streamer.world_seed)
	water_body = MeshInstance3D.new()
	water_body.name = "WaterShell"
	var wmesh := SphereMesh.new()
	wmesh.radius = planet_radius + STREAMER_TILE_LIFT + sea
	wmesh.height = wmesh.radius * 2.0
	wmesh.radial_segments = 96
	wmesh.rings = 48
	var wmat := StandardMaterial3D.new()
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.albedo_color = Color(0.12, 0.35, 0.5, 0.62)
	wmat.roughness = 0.15
	wmat.metallic = 0.1
	wmesh.material = wmat
	water_body.mesh = wmesh
	world_root.add_child(water_body)


## Play-day feedback #8: the visible sun on the globe too (the clock
## arc rides on top of the scene's static fill light).
## CELESTIAL FRAME: the sun node is a child of the PLAYER, not the
## scene/world_root -- at planet scale the floating origin slides the
## world under the player, and a scene-anchored disc swung across the
## sky with every step (round 5). As a player child it rides the
## rebase for free and stays a fixed star overhead.
func _build_sky_sun() -> void:
	var sun_script: GDScript = load("res://entities/sky_sun.gd")
	if sun_script == null:
		return
	var sun := Node3D.new()
	sun.name = "SkySun"
	sun.set_script(sun_script)
	if player != null:
		player.add_child(sun)
	else:
		# Player not built yet (build order); fall back to the scene
		# and let the player adopt it after _build_player.
		add_child(sun)
		sun.set_meta("adopt_by_player", true)


## The moon in the globe sky: same entity the planar world mounts
## (disc + synodic phase shading + moonlight). Built beside the sun
## so the player adoption re-parents them together.
func _build_sky_moon() -> void:
	var moon_script: GDScript = load("res://entities/sky_moon.gd")
	if moon_script == null:
		return
	var moon := Node3D.new()
	moon.name = "SkyMoon"
	moon.set_script(moon_script)
	if player != null:
		player.add_child(moon)
	else:
		# Player not built yet (build order); fall back to the scene
		# and let the player adopt it after _build_player (the sun's
		# fallback pattern; the adopt block re-parents it).
		add_child(moon)



func _build_sun() -> void:
	# THE ONE-SUN LAW: the static fixed sun light is retired -- the
	# re-parented SkySun owns the arc-tracking DirectionalLight that
	# dims to the night floor on the clock (globe sun build, round 5).
	# This node owns the SKY SHADE: background + ambient, driven per
	# frame by the same day curve the bodies ride.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = NIGHT_BG
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.45, 0.5)
	e.ambient_light_energy = NIGHT_AMBIENT
	add_child(env)
	env.environment = e
	_env = e


# THE SKY SHADE LAW (one clock): the background gradient and the
# ambient energy are pure functions of the Concord epoch's day phase
# (the SAME clock SkySun/SkyMoon/SignService read -- no second clock)
# through three keyed ramps: deep blue-black night, amber dusk band,
# clean blue day.
const NIGHT_BG: Color = Color(0.015, 0.025, 0.055)
const DAY_BG: Color = Color(0.30, 0.48, 0.66)
const DUSK_BG: Color = Color(0.52, 0.24, 0.18)
const NIGHT_AMBIENT: float = 0.20
const DAY_AMBIENT: float = 0.60

var _env: Environment = null


func _process(_delta: float) -> void:
	if _env == null:
		return
	var svc := get_node_or_null("/root/SignService")
	var epoch: float = svc.sky_epoch_days() if svc != null and svc.has_method("sky_epoch_days") \
		else float(Time.get_unix_time_from_system()) / 86400.0
	var phase := fposmod(epoch, 1.0)
	# The day curve mirrors sky_sun's (0 = dawn, 0.25 = noon, 0.5 =
	# dusk); the dusk band fires mid-ramp only.
	var day := clampf(sin(phase * TAU) * 1.6 + 0.08, 0.0, 1.0)
	var dusk := smoothstep(0.0, 0.45, day) * (1.0 - smoothstep(0.45, 0.95, day))
	var bg: Color = NIGHT_BG.lerp(DAY_BG, day)
	_env.background_color = bg.lerp(DUSK_BG, dusk * 0.55)
	_env.ambient_light_energy = NIGHT_AMBIENT + (DAY_AMBIENT - NIGHT_AMBIENT) * day


## S10: the arena gateway trigger at the village edge. An Area3D under
## world_root (shift-invariant: it rides the world rebase like every
## other planet-bound node) whose body_entered fires InstanceService.
func _build_arena_gateway() -> void:
	var GatewayScript = load("res://scenes/worlds/arena_gateway.gd")
	var gateway: Area3D = GatewayScript.new()
	gateway.zone_id = "zone_arena_coliseum"
	gateway.name = "ArenaGateway"
	# East of spawn on the sand line: tangent-east, just above the
	# shell so walking through it fires the join once.
	# ON the walk surface: the trigger rides the walk law at its
	# placement direction (a fixed radius + 1 would be buried under
	# the plaza at planet scale -- 9 m of terrain above the bare
	# shell), lifted a body-height so the walking player crosses it.
	var gw_dir: Vector3 = Vector3(14.0, 0.0, 0.0).normalized()
	var gw_r: float = planet_radius + STREAMER_TILE_LIFT \
		+ (streamer.walk_surface_h(gw_dir) if streamer else 0.0) + 1.0
	gateway.position = gw_dir * gw_r
	world_root.add_child(gateway)
	arena_gateway = gateway


var arena_gateway: Node3D = null


## THE STARTER VILLAGE PROTO (the ledger's parked build): the authored
## boots-and-stalls village on the spawn plaza flats -- hall, forge
## stall, signpost riding the plaza's own laws (exact flat ground,
## dry apron, cartway bent around the ring). Placed on the SAME frame
## the gateway rides, colliders via the one-law prop belt.
func _build_starter_village() -> void:
	var SV: GDScript = load("res://entities/starter_village.gd")
	starter_village = SV.build(world_root, planet_radius, STREAMER_TILE_LIFT, \
		Callable(streamer, "walk_surface_h"))


## THE CAPITOL MONOLITH (the ledger's coast build): the authored
## megalith the road law walks the cart to -- the arrival anchor ring
## points here; the structure rides the same authored-install frame
## the village carries.
func _build_capitol_monolith() -> void:
	var CM: GDScript = load("res://entities/capitol_monolith.gd")
	capitol_monolith = CM.build(world_root, planet_radius, STREAMER_TILE_LIFT, \
		Callable(streamer, "walk_surface_h"))


var starter_village: Node3D = null
var capitol_monolith: Node3D = null


## Ambience driver (entities/ambience_driver.gd): resolves weather at
## the player every 2s and feeds AudioService.apply_weather. The same
## seam world_playable carries; on the globe the driver reads the
## player's REAL cartesian lat/lon (its own bulb law), so band/season
## weather follows the sphere's cells.
func _setup_ambience() -> void:
	var amb_script: GDScript = load("res://entities/ambience_driver.gd")
	if amb_script == null:
		return
	var amb := Node3D.new()
	amb.name = "AmbienceDriver"
	amb.set_script(amb_script)
	add_child(amb)
	GameLog.info("GlobeWorld: ambience driver active (the weather sings)")


func _build_player() -> void:
	var script: GDScript = load("res://entities/globe_player.gd")
	player = CharacterBody3D.new()
	player.set_script(script)
	player.name = "GlobePlayer"
	# Named bits (round 10): the player rides the entity layer; the mask
	# is world props (solid) + walk surfaces (ground via the pad, solid
	# via PropCollider).
	player.collision_layer = Layers.layer_bit("entity")
	player.collision_mask = Layers.group_mask("entity_solid")

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = PLAYER_SKIN
	col.shape = shape
	player.add_child(col)

	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.6
	mesh.height = 1.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.75, 0.3)
	mesh.material = mat
	mi.mesh = mesh
	mi.position = Vector3(0, 0, 0)
	player.add_child(mi)

	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0, 2.2, 4.5)
	cam.fov = 70.0
	pivot.add_child(cam)
	player.add_child(pivot)

	# Spawn on the equator via the shared spherical convention, on the
	# WALK SURFACE (S8): with streaming the tiles sit TILE_LIFT above
	# the base shell, so spawn height = radius + TILE_LIFT + skin. The
	# same offset feeds the player's snap target and glue check. The
	# player is added to THIS scene (NOT world_root): it is the
	# floating-origin anchor and stays near the world origin.
	# The body's ground_offset is the STATIC tile lift only -- the
	# terrain law arrives through the snap provider (double-counting
	# it here would float the body a terrain-height above the ground).
	# The spawn POSITION does ride the terrain (born on the surface;
	# the frame-1 snap would otherwise teleport it up from inside the
	# hill).
	var static_lift: float = STREAMER_TILE_LIFT if planet_radius > PLANAR_SHELL_MAX_R else 0.0
	var spawn_terrain: float = (streamer.terrain_h(_spawn_dir()) if streamer else 0.0) \
		if planet_radius > PLANAR_SHELL_MAX_R else 0.0
	# SEA GUARD (play-test round 6, item 4): the spawn plaza flattens to
	# SPAWN_HEIGHT (9 m) and the sea line tops out at SEA_LEVEL_MIN +
	# SEA_LEVEL_SPAN (7 m), so the boot can never legally land in water.
	# Enforce it here anyway -- a future const drift or seed-rule change
	# must fail LOUD (log + lifted boot) instead of quietly drowning the
	# player ("I spawned on the ocean, green above me").
	if planet_radius > PLANAR_SHELL_MAX_R:
		var Gen4Spawn = load("res://scenes/worlds/terrain_gen.gd")
		var sea_at_spawn: float = Gen4Spawn.sea_level(streamer.world_seed) if streamer else 0.0
		if spawn_terrain < sea_at_spawn:
			if get_node_or_null("/root/GameLog"):
				get_node_or_null("/root/GameLog").error(
					"GlobeWorld: spawn height %.1f m is BELOW the sea line %.1f m -- lifting the boot onto dry land. Fix the terrain law (SPAWN_HEIGHT vs sea band)." % [spawn_terrain, sea_at_spawn])
			spawn_terrain = sea_at_spawn + 1.0
	# IDENTITY (round 7, item 3): the planar world stamps its player's
	# entity_id before registration; the globe never did, so the body
	# had no id to register a bag under and the starter kit had no
	# owner. Prefer the selected character's id (the account flow's
	# identity), fall back to the planar scene's local id.
	if str(player.entity_id) == "":
		var gm_id = get_node_or_null("/root/GameManager")
		var cd_id = (gm_id.selected_character_data if gm_id != null and "selected_character_data" in gm_id else null)
		if cd_id != null and "character_id" in cd_id and str(cd_id.character_id) != "":
			player.entity_id = str(cd_id.character_id)
		else:
			player.entity_id = "player_1"
	var Sph = load("res://core/frame/math/spherical.gd")
	var spawn: Vector3 = Sph.spherical_to_cartesian(
		SPAWN_LAT_DEG, SPAWN_LON_DEG, PLAYER_SKIN, planet_radius + static_lift + spawn_terrain)
	player.position = spawn
	# Boot truth line (round-6 follow-up): one always-on log so the next
	# play-test report can settle "spawned in the ocean" with the spawn
	# height vs the sea line in black and white. Prototype globes run
	# terrain-off (no water exists there), so say so instead of reading
	# like an underwater boot.
	if get_node_or_null("/root/GameLog"):
		if planet_radius > PLANAR_SHELL_MAX_R:
			get_node_or_null("/root/GameLog").info(
				"GlobeWorld: boot at lat %.1f lon %.1f, walk surface %.1f m (sea line %.1f m)" % [SPAWN_LAT_DEG, SPAWN_LON_DEG, spawn_terrain, (load("res://scenes/worlds/terrain_gen.gd").sea_level(streamer.world_seed) if streamer else 0.0)])
		else:
			get_node_or_null("/root/GameLog").info(
				"GlobeWorld: boot at lat %.1f lon %.1f (prototype globe, terrain off)" % [SPAWN_LAT_DEG, SPAWN_LON_DEG])
	player.planet_radius = planet_radius
	player.ground_offset = static_lift
	add_child(player)
	_install_walk_provider()
	# Adopt the sky sun (built before the player existed): the celestial
	# frame is the PLAYER (floating origin -- see _build_sky_sun).
	var sky_sun := get_node_or_null("SkySun")
	if sky_sun != null:
		sky_sun.position = Vector3.ZERO
		sky_sun.get_parent().remove_child(sky_sun)
		player.add_child(sky_sun)
	# Adopt the moon the same way: the pale stone rides the celestial
	# frame next to the sun (the floating-origin law, one frame).
	var sky_moon := get_node_or_null("SkyMoon")
	if sky_moon != null:
		sky_moon.position = Vector3.ZERO
		sky_moon.get_parent().remove_child(sky_moon)
		player.add_child(sky_moon)
	player.begin_loop()
	# WORLD ENTRY (round 7, item 3): world_playable emits
	# player_entered_world so StarterKitService grants the kit; the
	# globe scene never did -- players spawned with an empty bag and
	# the character/eq tabs rendered blank. Same emission, defensively
	# resolved (script-mode probes mount no autoloads).
	_notify_world_entry()


## Emit player_entered_world exactly once per boot for the local globe
## player (StarterKitService listens and grants the kit into the bag
## the player just registered -- one frame later, via its own
## _register_bag deferral).
func _notify_world_entry() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm == null or not gm.has_method("notify_player_entered_world"):
		return
	var cd = gm.selected_character_data if "selected_character_data" in gm else null
	var player_id := str(player.entity_id) if player != null and "entity_id" in player else ""
	if player_id.is_empty():
		return
	gm.notify_player_entered_world(player_id, cd)


## Build the on-screen spawn-truth line into the playable HUD (round
## 7, item 4). Terrain globes only: prototype globes run terrain-off
## (no sea exists there), and probes mount no HUD. Silent no-op when
## either is missing.
func _build_spawn_truth() -> void:
	if planet_radius <= PLANAR_SHELL_MAX_R or streamer == null or hud == null:
		return
	var label := Label.new()
	label.name = "SpawnTruthLabel"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.text = ""
	# Top-right, growing leftward: the menu bar owns the top-left and
	# the touch joystick owns the bottom-left.
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	# Round 10: the line grew the mesh-stream tag; widen the box so the
	# extra segment never clips on the right-anchored label.
	label.offset_left = -620.0
	label.offset_right = -12.0
	label.offset_top = 8.0
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(label)
	_truth_label = label
	_update_spawn_truth()


## Refresh the spawn-truth line from the player's live position:
## lat/lon (same convention as the boot log), ground height at the
## player's direction, the sea line, and the MESH STREAM STATE (round
## 10). WET tints the line amber so an ocean report is self-evident
## from a screenshot; mesh:OFF / mesh:fN tell the render half of the
## story -- "dry at 9.0 m" over a rendered ocean is now visible AS a
## render bug on the screenshot itself (the sim-vs-render split).
func _update_spawn_truth() -> void:
	if _truth_label == null or player == null or streamer == null:
		return
	var Sph = load("res://core/frame/math/spherical.gd")
	var dir: Vector3 = (player.global_position - planet_center).normalized()
	var ll: Vector2 = Sph.cartesian_to_spherical(dir * planet_radius, planet_radius)
	var Gen4 = load("res://scenes/worlds/terrain_gen.gd")
	var ground: float = streamer.terrain_h(dir)
	var sea: float = Gen4.sea_level(streamer.world_seed)
	var wet: bool = ground < sea
	var faces: int = streamer.active_faces().size()
	var stream_tag: String = "mesh:OFF"
	if faces > 0:
		stream_tag = "mesh:f%d x%d/%d" % [streamer.current_face, faces, streamer.triangle_count()]
	# ALT: the PLAYER BODY's actual altitude above the base shell. The
	# ground/sea readings are the terrain LAW; ALT is the body. Round-12
	# web question: law said dry but pixels showed ocean -- if ALT ~ 10
	# while the screen is teal, the body never sank and the break is in
	# the draw; if ALT collapsed to ~6 (the sea line), the body sank.
	var alt_m: float = -1.0
	if player != null and is_instance_valid(player):
		alt_m = (player.global_position - planet_center).length() - planet_radius
	var vis: int = streamer.visible_patch_count()
	# Mesh tag FIRST: the right end of this line sits under the minimap
	# on phone/portrait layouts, and the round-10 pack-freshness question
	# ("did the client run the UV-fix pack?") is exactly the tag that got
	# hidden. Leading segment = always on screen.
	_truth_label.text = "%s vis%d | ALT %.1f | lat %.2f lon %.2f | ground %.1f m | sea %.1f m | %s" % \
		[stream_tag, vis, alt_m, ll.x, ll.y, ground, sea, "WET" if wet else "dry"]
	# Feed the full map's player dot (round 13: the map is generated
	# from the terrain law; the gold dot rides the same lat/lon).
	var map := hud.find_child("WorldMap", true, false) if hud != null else null
	if map != null and map.has_method("set_player_lat_lon"):
		map.set_player_lat_lon(ll.x, ll.y)
	_truth_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2, 0.95) if wet else Color(1, 1, 1, 0.85))


## Drive the auto-walk for `seconds` of wall-clock physics, then stop.
func run_walk(seconds: float = WALK_SECONDS) -> void:
	player.auto_walk = true
	player.auto_walk_yaw = 0.0
	var elapsed: float = 0.0
	while elapsed < seconds and is_inside_tree():
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
	player.auto_walk = false


## Distance from the player's body center to the walk surface, above
## planet_radius (probe). Planet-relative: immune to floating-origin
## shifts (the world origin is NOT the planet center after a shift).
func player_surface_error() -> float:
	return player.planet_distance() - (planet_radius + _surface_lift())


## How far the player has walked along the surface (probe).
func player_path_walked() -> float:
	return player.path_walked


## Straight-line displacement since begin_loop (probe).
func player_displacement() -> float:
	return _loop_start_position().distance_to(player.global_position)


## Streamer observability (probe): face ids currently streaming.
func stream_active_faces() -> Array:
	return streamer.active_faces() if streamer else []


## Streamer observability (probe): live triangle count.
func stream_triangle_count() -> int:
	return streamer.triangle_count() if streamer else 0


func _loop_start_position() -> Vector3:
	# begin_loop() recorded it (player script state; dynamic access).
	return player._loop_start
