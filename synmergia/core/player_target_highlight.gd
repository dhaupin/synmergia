## PlayerTargetHighlight - 3D visual indicator for targeted players
## Shows a target ring/highlight around the selected player
class_name PlayerTargetHighlight
extends Node3D

## Target mesh
var _ring_mesh: MeshInstance3D
var _material: StandardMaterial3D

## Animation
var _rotate_speed: float = 1.0
var _pulse_speed: float = 2.0
var _pulse_amount: float = 0.1
var _base_scale: float = 1.0

## State
var _target_node: Node3D
var _is_visible: bool = false

func _ready() -> void:
	_setup_ring()
	hide()

func _setup_ring() -> void:
	# Create ring mesh (torus)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 16
	
	_ring_mesh = MeshInstance3D.new()
	_ring_mesh.mesh = torus
	
	# Create material
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(1, 0.8, 0, 0.8)  # Orange glow
	_material.emission_enabled = true
	_material.emission = Color(1, 0.6, 0, 1)
	_material.emission_energy_multiplier = 2.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # See from both sides
	
	_ring_mesh.material_override = _material
	add_child(_ring_mesh)
	
	# Position slightly above ground
	_ring_mesh.position.y = 0.5

func _process(delta: float) -> void:
	if not _is_visible:
		return
	
	# Rotate ring
	_ring_mesh.rotate_y(_rotate_speed * delta)
	
	# Pulse effect
	var pulse := (sin(_pulse_speed * Time.get_ticks_msec() / 1000.0) + 1.0) / 2.0
	var scale := _base_scale + (pulse * _pulse_amount)
	_ring_mesh.scale = Vector3(scale, 1, scale)
	
	# Follow target if set
	if _target_node:
		global_position = _target_node.global_position

## Set the target node to follow
func set_target(node: Node3D) -> void:
	_target_node = node
	if node:
		global_position = node.global_position
		show()
		_is_visible = true
	else:
		hide()
		_is_visible = false

## Clear target
func clear_target() -> void:
	_target_node = null
	hide()
	_is_visible = false

## Set highlight color
func set_color(color: Color) -> void:
	_material.albedo_color = Color(color.r, color.g, color.b, 0.8)
	_material.emission = color

## Set ring size
func set_size(radius: float) -> void:
	if _ring_mesh.mesh is TorusMesh:
		var torus: TorusMesh = _ring_mesh.mesh
		torus.outer_radius = radius
		torus.inner_radius = radius * 0.8

## Get highlight color for different states
static func get_color_for_action(action_category: int) -> Color:
	match action_category:
		PlayerTargetSystem.ActionCategory.SOCIAL:
			return Color(0.3, 0.6, 1, 1)  # Blue
		PlayerTargetSystem.ActionCategory.VIP_SOCIAL:
			return Color(0.8, 0.4, 1, 1)  # Purple
		PlayerTargetSystem.ActionCategory.MODERATION:
			return Color(1, 0.6, 0.2, 1)  # Orange
		PlayerTargetSystem.ActionCategory.ADMIN:
			return Color(1, 0.2, 0.2, 1)  # Red
		_:
			return Color(1, 0.8, 0, 1)  # Orange (default)
