## ThirdPersonCamera - 3rd person camera following player
## Supports mouse/keyboard and touch input
extends Camera3D
class_name ThirdPersonCamera

@export var distance: float = 6.0
@export var height: float = 2.5
@export var rotation_speed: float = 0.003
@export var follow_smoothness: float = 10.0
@export var min_pitch: float = -30.0
@export var max_pitch: float = 60.0
@export var min_distance: float = 3.0
@export var max_distance: float = 12.0

var target: Node3D
var yaw: float = 0.0
var pitch: float = 30.0
var current_distance: float = 6.0

var is_rotating: bool = false
var is_zooming: bool = false

func _ready() -> void:
	# Find player target
	target = get_parent()
	if not target:
		GameLog.warn("ThirdPersonCamera: No target (parent) found")

func _input(event: InputEvent) -> void:
	if not is_instance_valid(target):
		return
	
	# Mouse rotation
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= event.relative.x * rotation_speed
			pitch -= event.relative.y * rotation_speed
			pitch = clamp(pitch, min_pitch, max_pitch)
	
	# Mouse zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_distance = max(min_distance, current_distance - 0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_distance = min(max_distance, current_distance + 0.5)
	
	# Touch rotation
	if event is InputEventScreenDrag:
		if event.position.x > get_viewport().get_visible_rect().size.x * 0.5:
			# Right side of screen - camera control
			yaw -= event.relative.x * rotation_speed * 2
			pitch -= event.relative.y * rotation_speed * 2
			pitch = clamp(pitch, min_pitch, max_pitch)
		elif event.position.y < get_viewport().get_visible_rect().size.y * 0.3:
			# Top of screen - zoom
			current_distance = clamp(current_distance - event.relative.y * 0.05, min_distance, max_distance)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	
	_update_camera(delta)

func _update_camera(delta: float) -> void:
	# Calculate offset based on yaw and pitch
	var offset := Vector3.ZERO
	offset.x = sin(deg_to_rad(yaw)) * cos(deg_to_rad(pitch)) * current_distance
	offset.y = sin(deg_to_rad(pitch)) * current_distance
	offset.z = -cos(deg_to_rad(yaw)) * cos(deg_to_rad(pitch)) * current_distance
	
	# Target position + offset
	var desired_position := target.global_position + offset
	desired_position.y += height
	
	# Smooth follow
	global_position = global_position.lerp(desired_position, follow_smoothness * delta)
	
	# Look at target
	var look_target := target.global_position + Vector3(0, height * 0.7, 0)
	look_at(look_target)

func set_target(new_target: Node3D) -> void:
	target = new_target

func set_yaw(new_yaw: float) -> void:
	yaw = new_yaw

func set_pitch(new_pitch: float) -> void:
	pitch = clamp(new_pitch, min_pitch, max_pitch)

func get_yaw() -> float:
	return yaw

func get_pitch() -> float:
	return pitch

func get_look_direction() -> Vector3:
	return -global_transform.basis.z

func get_forward_direction() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0
	return forward.normalized()

func get_right_direction() -> Vector3:
	var right := global_transform.basis.x
	right.y = 0
	return right.normalized()

func reset_rotation() -> void:
	yaw = 0.0
	pitch = 30.0
