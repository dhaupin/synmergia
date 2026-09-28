## GlobeIsland - standalone spherical-world prototype scene root
## (prd-spherical-mvp.md S3). Builds the shell (visual sphere +
## sphere-shell collider), the player, a sun, and the probe markers.
## Deliberately additive: nothing in the live playable world changes.
extends Node3D

const SHELL_RADIUS: float = 100.0
## Visual shell is slightly proud of the collider to avoid z-fighting.
const SKIN_THICKNESS: float = 0.5
const PLAYER_SKIN: float = 1.0
const SPAWN_LAT_DEG: float = 0.0
const SPAWN_LON_DEG: float = 0.0
const WALK_SECONDS: float = 30.0
## ~40% of a full equator lap at 6 m/s on a 100 m sphere.
const WALK_DISTANCE_METERS: float = 250.0

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
	_build_shell()
	_build_sun()
	_build_probe_markers()
	_build_player()
	_setup_streamer()


func _setup_streamer() -> void:
	if not stream_terrain:
		return
	streamer = load("res://scenes/worlds/globe_terrain_streamer.gd").new()
	streamer.configure(SHELL_RADIUS, 7.0, self)
	streamer.update(player.global_position)
	# Rock walk-over: the player's radial snap rides seeded rock tops
	# (S7). Callable receives the player's world direction.
	var Faces = load("res://core/frame/math/icosahedral_faces.gd")
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	player.snap_height_provider = func(dir: Vector3) -> float:
		var face: int = Faces.face_for_direction(dir)
		return Gen.rock_top_height(dir, streamer.world_seed, face, SHELL_RADIUS)


func _physics_process(_delta: float) -> void:
	if streamer and player:
		streamer.update(player.global_position)


func _build_shell() -> void:
	var shell := StaticBody3D.new()
	shell.name = "GlobeShell"
	shell.physics_material_override = PhysicsMaterial.new()
	shell.physics_material_override.friction = 1.0
	shell.physics_material_override.bounce = 0.0

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = SHELL_RADIUS
	col.shape = sphere
	shell.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = SHELL_RADIUS + SKIN_THICKNESS
	mesh.height = (SHELL_RADIUS + SKIN_THICKNESS) * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.55, 0.35)  # grass green
	mat.roughness = 0.95
	mesh.material = mat
	mesh_inst.mesh = mesh
	shell.add_child(mesh_inst)

	add_child(shell)


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
	_probe_north = _make_marker(Color(0.9, 0.2, 0.2), Vector3(0, SHELL_RADIUS + 4.0, 0))
	_probe_east = _make_marker(Color(0.2, 0.4, 0.9), Vector3(10.0, SHELL_RADIUS + 4.0, 0))
	_probe_marker = _make_marker(Color(1.0, 0.85, 0.2), Vector3(0, SHELL_RADIUS + 8.0, -40.0))


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
	add_child(root)
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

	# Spawn on the equator via the shared spherical convention.
	var Sph = load("res://core/frame/math/spherical.gd")
	var spawn: Vector3 = Sph.spherical_to_cartesian(
		SPAWN_LAT_DEG, SPAWN_LON_DEG, PLAYER_SKIN, SHELL_RADIUS)
	player.position = spawn
	player.planet_radius = SHELL_RADIUS
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


## Distance from the player's feet to the shell surface (probe).
func player_surface_error() -> float:
	return player.global_position.length() - SHELL_RADIUS


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
