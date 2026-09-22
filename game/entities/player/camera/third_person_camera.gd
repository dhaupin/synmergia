## ThirdPersonCamera - COD Mobile-style 3rd person follow camera.
## Shoulder offset, mouse/touch orbit, wheel/pinch zoom, and a GUI-hover
## guard so a drag starting on HUD controls never spins the camera.
extends Camera3D
class_name ThirdPersonCamera

@export var distance: float = 5.5
@export var height: float = 1.7
@export var shoulder_offset: float = 0.9  # right-side over-the-shoulder frame
@export var rotation_speed: float = 0.003
@export var follow_smoothness: float = 12.0
@export var min_pitch: float = -55.0
@export var max_pitch: float = 70.0
@export var min_distance: float = 2.5
@export var max_distance: float = 10.0
@export var aim_distance: float = 3.0
@export var aim_height: float = 1.55
@export var aim_shoulder: float = 0.55
@export var aim_fov: float = 55.0

var target: Node3D
var yaw: float = 0.0
var pitch: float = 18.0
var current_distance: float = 6.0
var is_aiming: bool = false

# User settings (PlayerConfig-backed; live-updated via setting_changed).
# sensitivity is the multiplier on rotation_speed (1.0 = default feel).
var sensitivity: float = 1.0
var invert_x: bool = false
var invert_y: bool = false

var _dragging: bool = false
var _last_mouse: Vector2 = Vector2.ZERO
var _default_fov: float = 70.0
var _wheel_accum: float = 0.0

func _ready() -> void:
	target = get_parent()
	if not target:
		GameLog.warn("ThirdPersonCamera: No target (parent) found")
	_default_fov = fov
	current_distance = distance
	_apply_user_settings()
	if PlayerConfig:
		PlayerConfig.setting_changed.connect(_on_setting_changed)

## Pull the saved camera settings. rotation_speed stays the base rad/px
## constant; the slider (0.5..3.0, default 1.0) scales both the mouse
## path and the touch bridge in world_playable.
func _apply_user_settings() -> void:
	if PlayerConfig == null:
		return
	sensitivity = float(PlayerConfig.get_account_setting("camera_rotation_speed", 1.0))
	invert_x = bool(PlayerConfig.get_account_setting("invert_x_axis", false))
	invert_y = bool(PlayerConfig.get_account_setting("invert_y_axis", false))

func _on_setting_changed(_cat: int, key: String, value: Variant) -> void:
	match key:
		"camera_rotation_speed":
			sensitivity = float(value)
		"invert_x_axis":
			invert_x = bool(value)
		"invert_y_axis":
			invert_y = bool(value)

func _input(event: InputEvent) -> void:
	if not is_instance_valid(target):
		return

	# Mouse orbit (right-button drag), with a GUI guard: when the press
	# starts over a Control, the camera must ignore the whole drag.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if not _is_mouse_over_gui(event.position):
					_dragging = true
					_last_mouse = event.position
			else:
				_dragging = false
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_wheel_accum -= 0.5
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_wheel_accum += 0.5
		_apply_zoom()

	if event is InputEventMouseMotion and _dragging:
		var rel: Vector2 = event.position - _last_mouse
		_last_mouse = event.position
		# 1.0x (not the legacy *60) keeps the mouse path at the same
		# rad/px as the touch bridge; both scale by the user sensitivity.
		orbit(rel * rotation_speed * sensitivity)

	# Aim mode (right mouse button hold).
	is_aiming = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	# Touch orbit is owned by the TouchHud (which routes right-half drags
	# through InputManager -> world_playable bridge into orbit()); this
	# camera must NOT also consume ScreenDrag or every swipe rotates twice.

	# Touch pinch zoom (two-finger gesture reported by the viewport).
	if event is InputEventMagnifyGesture:
		current_distance = clampf(
			current_distance / event.factor, min_distance, max_distance)

func _is_mouse_over_gui(pos: Vector2) -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var over: Control = vp.gui_get_hovered_control()
	if over == null:
		# Hover tracking can lag the press by a frame; fall back to a
		# focus check so clicks inside a text field never spin the view.
		over = vp.gui_get_focus_owner()
	return over != null

func orbit(delta: Vector2) -> void:
	var dx: float = -delta.x if invert_x else delta.x
	var dy: float = -delta.y if invert_y else delta.y
	yaw -= dx
	pitch -= dy
	pitch = clampf(pitch, min_pitch, max_pitch)

func _apply_zoom() -> void:
	if _wheel_accum == 0.0:
		return
	current_distance = clampf(current_distance + _wheel_accum, min_distance, max_distance)
	_wheel_accum = 0.0

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	_update_camera(delta)

func _update_camera(delta: float) -> void:
	var pitch_rad := deg_to_rad(pitch)
	var yaw_rad := deg_to_rad(yaw)

	# Orbit offset around the pivot.
	var offset := Vector3.ZERO
	offset.x = sin(yaw_rad) * cos(pitch_rad)
	offset.y = sin(pitch_rad)
	offset.z = -cos(yaw_rad) * cos(pitch_rad)
	offset = offset.normalized()

	# Pivot at the player's upper body; camera keeps a level horizon
	# reference so the shoulder offset is applied in view space.
	var pivot := target.global_position + Vector3(0, height, 0)
	var shoulder := aim_shoulder if is_aiming else shoulder_offset
	var dist := aim_distance if is_aiming else current_distance
	var eye_height := aim_height if is_aiming else height

	# Shift the pivot sideways in view space for the over-the-shoulder frame.
	var right := Vector3(cos(yaw_rad), 0.0, sin(yaw_rad))
	pivot += right * shoulder

	var desired_position := pivot + offset * dist
	desired_position.y = maxf(desired_position.y, pivot.y - dist * 0.25 + eye_height * 0.5)

	# Tighter follow while aiming; smooth otherwise.
	var smooth := follow_smoothness * (2.0 if is_aiming else 1.0)
	global_position = global_position.lerp(desired_position, clampf(smooth * delta, 0.0, 1.0))

	var look_target := pivot
	look_target.y += (eye_height - height) * 0.5
	look_at(look_target)

	var target_fov := aim_fov if is_aiming else _default_fov
	fov = lerpf(fov, target_fov, clampf(8.0 * delta, 0.0, 1.0))

func set_target(new_target: Node3D) -> void:
	target = new_target

func set_yaw(new_yaw: float) -> void:
	yaw = new_yaw

func set_pitch(new_pitch: float) -> void:
	pitch = clampf(new_pitch, min_pitch, max_pitch)

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
	pitch = 18.0
