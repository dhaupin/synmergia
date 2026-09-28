## GlobeIsland - standalone spherical-world prototype scene root
## (prd-spherical-mvp.md S3). Builds the shell (visual sphere +
## sphere-shell collider), the player, a sun, and the probe markers.
## Deliberately additive: nothing in the live playable world changes.
##
## S8 FLOATING ORIGIN: everything planet-bound (shell, streamed
## patches, probe markers, surface pad) lives under world_root; the
## player is a direct child of this scene and stays near the world
## origin. When the player drifts past SHIFT_RADIUS, the whole planet
## is translated back around it (_maybe_shift_world). At planet scale
## ground support is a single re-anchored surface pad (see
## _build_surface_pad) - the megasphere SphereShape and face-scale
## patch trimeshes both degenerate at R = 20 km (measured, S8).
extends Node3D

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

var streamer  # GlobeTerrainStreamer; untyped - preload-by-path pattern

var player  # GlobeIslandPlayer; untyped on purpose - set_script + dynamic
# dispatch keeps this scene free of parse-time class_name dependencies.
var _probe_north: Node3D
var _probe_east: Node3D
var _probe_marker: Node3D


func _ready() -> void:
	planet_radius = float(ProjectSettings.get_setting(PLANET_RADIUS_SETTING, 100.0))
	# S8 floating origin: planet-bound content lives under world_root.
	world_root = Node3D.new()
	world_root.name = "WorldRoot"
	add_child(world_root)
	_build_shell()
	_build_surface_pad()
	_build_sun()
	_build_probe_markers()
	_build_player()
	_setup_streamer()
	planet_center = world_root.position
	player.planet_center = planet_center


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


func _setup_streamer() -> void:
	if not stream_terrain:
		return
	streamer = load("res://scenes/worlds/globe_terrain_streamer.gd").new()
	streamer.configure(planet_radius, 7.0, world_root)
	streamer.update(player.global_position)
	# Rock walk-over: the player's radial snap rides seeded rock tops
	# (S7). Callable receives the player's WORLD position; directions
	# are derived relative to planet_center (floating origin: the
	# world origin is NOT the planet center after the first shift).
	var Faces = load("res://core/frame/math/icosahedral_faces.gd")
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	player.snap_height_provider = func(wpos: Vector3) -> float:
		var dir: Vector3 = (wpos - planet_center).normalized()
		var face: int = Faces.face_for_direction(dir)
		return Gen.rock_top_height(dir, streamer.world_seed, face, planet_radius)


func _physics_process(_delta: float) -> void:
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
	_maybe_shift_world()


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
## player must keep shell contact (probe_globe_island asserts radial
## rest). At planet scale the re-anchored pad carries the collision
## at planet_radius + TILE_LIFT, matching the visual tile tops.
func _surface_lift() -> float:
	return STREAMER_TILE_LIFT if planet_radius > PLANAR_SHELL_MAX_R else 0.0


func _build_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.07, 0.12)  # night space
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.45, 0.5)
	e.ambient_light_energy = 0.6
	add_child(env)
	env.environment = e


## A tall box at the north pole and a second one one tangent-east step
## away: if radial gravity and the tangent frame are right, the north
## marker stays ABOVE the player (in local up) for the whole walk.
func _build_probe_markers() -> void:
	_probe_north = _make_marker(Color(0.9, 0.2, 0.2), Vector3(0, planet_radius + 4.0, 0))
	_probe_east = _make_marker(Color(0.2, 0.4, 0.9), Vector3(10.0, planet_radius + 4.0, 0))
	_probe_marker = _make_marker(Color(1.0, 0.85, 0.2), Vector3(0, planet_radius + 8.0, -40.0))


func _make_marker(color: Color, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 8.0, 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6
	box.material = mat
	mi.mesh = box
	root.add_child(mi)
	root.position = pos
	world_root.add_child(root)
	return root


func _build_player() -> void:
	var script: GDScript = load("res://entities/globe_player.gd")
	player = CharacterBody3D.new()
	player.set_script(script)
	player.name = "GlobePlayer"

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
	var surface_lift: float = _surface_lift()
	var Sph = load("res://core/frame/math/spherical.gd")
	var spawn: Vector3 = Sph.spherical_to_cartesian(
		SPAWN_LAT_DEG, SPAWN_LON_DEG, PLAYER_SKIN, planet_radius + surface_lift)
	player.position = spawn
	player.planet_radius = planet_radius
	player.ground_offset = surface_lift
	add_child(player)
	player.begin_loop()


## Drive the auto-walk for `seconds` of wall-clock physics, then stop.
func run_walk(seconds: float = WALK_SECONDS) -> void:
	player.auto_walk = true
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
