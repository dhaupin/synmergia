## WaypointBeacon - Visual indicator for waypoints in game world
## Creates a pillar of light / marker that can be seen from a distance
extends Node3D

const WaypointService = preload("res://core/services/waypoint_service.gd")

# Beacon components
var _pillar: ImmediateMeshInstance3D
var _base: MeshInstance3D
var _icon_label: Label3D
var _particles: GPUParticles3D

# State
var _waypoint_id: String = ""
var _is_visible: bool = false
var _color: Color = Color(0.3, 0.6, 1.0)
var _height_offset: float = 50.0

func _ready() -> void:
	_setup_beacon()
	visible = false

func _setup_beacon() -> void:
	# Base ring
	_base = MeshInstance3D.new()
	_base.name = "Base"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 2.0
	cylinder.bottom_radius = 2.0
	cylinder.height = 0.5
	_base.mesh = cylinder

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = _color
	mat.emission_enabled = true
	mat.emission = _color
	mat.emission_energy_multiplier = 2.0
	_base.material_override = mat
	add_child(_base)

	# Pillar (cone)
	_pillar = ImmediateMeshInstance3D.new()
	_pillar.name = "Pillar"
	add_child(_pillar)

	# 3D Label
	_icon_label = Label3D.new()
	_icon_label.name = "IconLabel"
	_icon_label.text = "📍"
	_icon_label.font_size = 48
	_icon_label.pixel_size = 0.01
	_icon_label.modulate = Color(1, 1, 0.8)
	_icon_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon_label.position = Vector3(0, 5, 0)
	add_child(_icon_label)

	# Particles (floating light)
	_particles = GPUParticles3D.new()
	_particles.name = "Particles"
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	_particles.draw_pass_1 = sphere
	_particles.amount = 50
	_particles.lifetime = 3.0
	_particles.explosiveness = 0.8
	_particles.randomness = 0.5

	var particle_mat := ParticleProcessMaterial.new()
	particle_mat.direction = Vector3(0, 1, 0)
	particle_mat.spread = 30.0
	particle_mat.initial_velocity_min = 10.0
	particle_mat.initial_velocity_max = 20.0
	particle_mat.gravity = Vector3(0, -2, 0)
	particle_mat.color = _color
	_particles.process_material = particle_mat
	_particles.position = Vector3(0, 2, 0)
	add_child(_particles)

func setup(waypoint_id: String, position: Vector3, color: Color, icon: int) -> void:
	_waypoint_id = waypoint_id
	global_position = position
	_color = color
	_icon_label.text = WaypointService.get_icon_string(icon) if WaypointService else "📍"

	# Update colors
	if _base and _base.material_override:
		var mat := _base.material_override as StandardMaterial3D
		mat.albedo_color = _color
		mat.emission = _color

	if _particles and _particles.process_material:
		var p_mat := _particles.process_material as ParticleProcessMaterial
		p_mat.color = _color

func _process(delta: float) -> void:
	if not visible:
		return

	# Animate pillar
	_pillar.clear()
	_pillar.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	# Pulsing effect
	var pulse := 0.8 + 0.2 * sin(Time.get_ticks_msec() / 500.0)
	var alpha := 0.3 * pulse

	# Draw cone shape
	var segments := 16
	var height := _height_offset
	var base_radius := 3.0

	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var angle := t * TAU
		var x := cos(angle) * base_radius * (1.0 - t * 0.3)
		var z := sin(angle) * base_radius * (1.0 - t * 0.3)

		# Bottom vertex
		_pillar.set_color(Color(_color.r, _color.g, _color.b, alpha * 0.5))
		_pillar.add_vertex(Vector3(x, 0.5, z))

		# Top vertex
		_pillar.set_color(Color(_color.r, _color.g, _color.b, alpha * 0.2))
		_pillar.add_vertex(Vector3(x * 0.3, height, z * 0.3))

	_pillar.end()

	# Rotate label to face camera
	_icon_label.rotate_y(delta * 0.5)

func show_beacon() -> void:
	visible = true
	_is_visible = true

func hide_beacon() -> void:
	visible = false
	_is_visible = false

func toggle_beacon() -> void:
	visible = not visible
	_is_visible = visible

func is_visible() -> bool:
	return _is_visible

func get_waypoint_id() -> String:
	return _waypoint_id
