## InputManager - Movement input handling for mobile and desktop
## 
## Uses InteractionLayer for UI interactions (tap, swipe, etc.)
## Handles movement joystick and camera control
extends Node

signal player_input(action: String, pressed: bool)
signal touch_started(position: Vector2)
signal touch_ended(position: Vector2)
signal touch_moved(position: Vector2, delta: Vector2)

var last_direction: Vector2 = Vector2.ZERO
var current_touch_position: Vector2 = Vector2.ZERO
var is_touch_active: bool = false

# Touch zones (normalized 0-1)
var left_zone := Rect2(0.0, 0.3, 0.35, 0.7)  # Left side for movement
var right_zone := Rect2(0.65, 0.3, 0.35, 0.7)  # Right side for camera

# Joystick state
var joystick_active: bool = false
var joystick_center: Vector2 = Vector2.ZERO
var joystick_offset: Vector2 = Vector2.ZERO
var joystick_deadzone: float = 0.15

# Reference to InteractionLayer (set by InteractionLayer when ready)
var _interaction_layer: Node = null

func _ready() -> void:
	GameLog.info("InputManager initialized")
	
	# Enable touch emulation on desktop for testing
	if DisplayServer.touchscreen_is_available():
		pass  # touch emulation on desktop  # static call
	Input.set_use_accumulated_input(true)
	
	# Try to get InteractionLayer
	_interaction_layer = get_tree().root.find_child("InteractionLayer", true, false)
	if _interaction_layer:
		GameLog.info("InputManager: Connected to InteractionLayer")

func _input(event: InputEvent) -> void:
	# Forward to InteractionLayer for UI interactions (tap, swipe, etc.)
	if _interaction_layer and _interaction_layer.has_method("_process_input"):
		_interaction_layer._process_input(event)
	
	# Handle movement input
	_handle_touch_events(event)
	_handle_mouse_events(event)
	_emit_input_actions(event)

func _handle_touch_events(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			is_touch_active = true
			current_touch_position = event.position
			touch_started.emit(event.position)
			_process_touch_zone(event.position)
		else:
			is_touch_active = false
			joystick_active = false
			joystick_offset = Vector2.ZERO
			touch_ended.emit(event.position)
	
	elif event is InputEventScreenDrag:
		current_touch_position = event.position
		var delta: Vector2 = event.relative
		touch_moved.emit(event.position, delta)
		
		if joystick_active:
			_update_joystick(event.position)

func _handle_mouse_events(event: InputEvent) -> void:
	# For desktop testing without touch
	if event is InputEventMouseMotion:
		last_direction = event.relative / 100.0

func _process_touch_zone(position: Vector2) -> void:
	var screen_size := get_viewport().get_visible_rect().size
	var normalized_pos := position / screen_size
	
	if left_zone.has_point(normalized_pos):
		joystick_active = true
		joystick_center = position
	elif right_zone.has_point(normalized_pos):
		# Camera control handled elsewhere
		pass

func _update_joystick(position: Vector2) -> void:
	joystick_offset = (position - joystick_center)
	
	# Clamp to joystick radius
	var max_radius := 60.0  # pixels
	var distance := joystick_offset.length()
	if distance > max_radius:
		joystick_offset = joystick_offset.normalized() * max_radius
	
	# Apply deadzone
	if joystick_offset.length() < joystick_deadzone * max_radius:
		joystick_offset = Vector2.ZERO

func _emit_input_actions(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var action := _get_keyboard_action(event)
		if action:
			player_input.emit(action, true)
	elif event is InputEventKey and not event.pressed:
		var action := _get_keyboard_action(event)
		if action:
			player_input.emit(action, false)

func _get_keyboard_action(event: InputEventKey) -> String:
	match event.physical_keycode:
		KEY_SPACE:
			return "jump"
		KEY_Q:
			return "dodge"
		KEY_TAB:
			return "target_next"
		KEY_ESCAPE:
			return "pause"
	return ""

func get_movement_input() -> Vector2:
	# Check joystick first
	if joystick_active and joystick_offset.length() > 0:
		return joystick_offset / 60.0  # Normalize to -1 to 1
	
	# Keyboard fallback
	var input := Vector2.ZERO
	input.x = Input.get_axis("move_left", "move_right")
	input.y = Input.get_axis("move_forward", "move_back")
	return input.normalized()

func get_camera_input() -> Vector2:
	# For mouse/camera drag
	return last_direction

func is_moving() -> bool:
	return get_movement_input().length() > 0.1

func get_joystick_position() -> Vector2:
	return joystick_offset

func is_joystick_active() -> bool:
	return joystick_active
