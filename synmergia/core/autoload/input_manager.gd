## InputManager - Unified input handling for desktop, mobile, and controller
## Handles keyboard/mouse, touch, and gamepad input with automatic platform detection
extends Node

## Input modes
enum InputMode {
	AUTO,          # Auto-detect based on last input
	KEYBOARD_MOUSE,
	TOUCH,
	CONTROLLER
}

## Current input mode
var _input_mode: InputMode = InputMode.AUTO
var _last_input_type: String = ""

## Signals
signal input_mode_changed(mode: InputMode)
signal player_input(action: String, pressed: bool)
signal controller_connected()
signal controller_disconnected()

## Platform detection
var _is_mobile: bool = false
var _is_desktop: bool = false
var _is_web: bool = false

## Controller state
var _controller_id: int = -1
var _controller_deadzone: float = 0.15
var _controller_last_used: float = 0.0
var _controller_left_stick: Vector2 = Vector2.ZERO
var _controller_right_stick: Vector2 = Vector2.ZERO

## Touch state
var _touch_active: bool = false
var _touch_positions: Dictionary = {}
var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_offset: Vector2 = Vector2.ZERO
var _joystick_max_radius: float = 60.0
var _joystick_touch_id: int = -1

## Touch zones (normalized 0-1)
const LEFT_ZONE := Rect2(0.0, 0.3, 0.35, 0.7)
const RIGHT_ZONE := Rect2(0.65, 0.3, 0.35, 0.7)

## Keybindings (action -> key codes)
var _keybindings: Dictionary = {
	"move_forward": [KEY_W, KEY_UP],
	"move_backward": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"dodge": [KEY_Q],
	"sprint": [KEY_SHIFT],
	"interact": [KEY_E, KEY_F],
	"target_self": [KEY_F1],
	"target_nearest": [KEY_F2],
	"target_party": [KEY_F3],
	"target_previous": [KEY_TAB],
	"target_next": [KEY_TAB],
	"ability_1": [KEY_1],
	"ability_2": [KEY_2],
	"ability_3": [KEY_3],
	"ability_4": [KEY_4],
	"ability_5": [KEY_5],
	"ability_6": [KEY_6],
	"ability_7": [KEY_7],
	"ability_8": [KEY_8],
	"open_inventory": [KEY_I],
	"open_character": [KEY_C],
	"open_skills": [KEY_K],
	"open_quests": [KEY_J],
	"open_map": [KEY_M],
	"open_chat": [KEY_ENTER],
	"close_ui": [KEY_ESCAPE],
	"toggle_pvp": [KEY_P],
	"sit": [KEY_Z],
	"emote": [KEY_SLASH]
}

## Controller mappings (action -> joystick/button)
var _controller_mappings: Dictionary = {
	"move_axis_x": {"stick": 0, "axis": 0},  # Left stick X
	"move_axis_y": {"stick": 0, "axis": 1},  # Left stick Y
	"camera_x": {"stick": 1, "axis": 2},       # Right stick X
	"camera_y": {"stick": 1, "axis": 3},       # Right stick Y
	"interact": {"button": JOY_BUTTON_A},
	"jump": {"button": JOY_BUTTON_A},
	"dodge": {"button": JOY_BUTTON_B},
	"target_next": {"button": JOY_BUTTON_RIGHT_SHOULDER},
	"ability_1": {"button": JOY_BUTTON_DPAD_UP},
	"ability_2": {"button": JOY_BUTTON_DPAD_RIGHT},
	"ability_3": {"button": JOY_BUTTON_DPAD_DOWN},
	"ability_4": {"button": JOY_BUTTON_DPAD_LEFT},
	"open_inventory": {"button": JOY_BUTTON_Y},
	"open_character": {"button": JOY_BUTTON_X},
	"open_map": {"button": JOY_BUTTON_START},
	"pause": {"button": JOY_BUTTON_START}
}

func _ready() -> void:
	_detect_platform()
	_check_controller()
	_setup_input_actions()
	print("InputManager: Mode=", _input_mode, " Mobile=", _is_mobile, " Desktop=", _is_desktop)

func _detect_platform() -> void:
	_is_web = OS.has_feature("web")
	_is_mobile = (
		DisplayServer.get_name() == "Android" or
		DisplayServer.get_name() == "iOS" or
		OS.has_feature("mobile")
	)
	_is_desktop = (
		DisplayServer.get_name() == "Windows" or
		DisplayServer.get_name() == "Linux" or
		DisplayServer.get_name() == "macOS"
	)

	# Default mode based on platform
	if _is_mobile:
		_input_mode = InputMode.TOUCH
	elif _is_web:
		_input_mode = InputMode.AUTO
	else:
		_input_mode = InputMode.KEYBOARD_MOUSE

func _setup_input_actions() -> void:
	# Create input actions if they don't exist
	var actions := [
		"move_forward", "move_backward", "move_left", "move_right",
		"jump", "dodge", "sprint", "interact",
		"ability_1", "ability_2", "ability_3", "ability_4",
		"ability_5", "ability_6", "ability_7", "ability_8"
	]
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

func _check_controller() -> void:
	for i in Input.get_connected_joypads():
		_controller_id = i
		controller_connected.emit()
		break

func _input(event: InputEvent) -> void:
	_detect_input_type(event)
	_handle_event(event)

func _process(_delta: float) -> void:
	# Poll controller periodically
	if _input_mode == InputMode.CONTROLLER or _input_mode == InputMode.AUTO:
		_update_controller()

func _detect_input_type(event: InputEvent) -> void:
	var new_type := ""
	if event is InputEventKey:
		new_type = "keyboard"
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		new_type = "mouse"
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		new_type = "touch"
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		new_type = "controller"

	if new_type != _last_input_type and new_type != "":
		_last_input_type = new_type
		_update_input_mode(new_type)

func _update_input_mode(new_type: String) -> void:
	var old_mode := _input_mode
	var new_mode := _input_mode

	match new_type:
		"keyboard", "mouse":
			if _input_mode != InputMode.KEYBOARD_MOUSE:
				new_mode = InputMode.KEYBOARD_MOUSE
		"touch":
			new_mode = InputMode.TOUCH
		"controller":
			new_mode = InputMode.CONTROLLER
			_controller_last_used = Time.get_ticks_msec()

	if new_mode != old_mode and _input_mode != InputMode.AUTO:
		_input_mode = new_mode
		input_mode_changed.emit(new_mode)
	elif new_mode != old_mode:
		_input_mode = new_mode

func _handle_event(event: InputEvent) -> void:
	match _input_mode:
		InputMode.KEYBOARD_MOUSE:
			_handle_keyboard_mouse(event)
		InputMode.TOUCH:
			_handle_touch(event)
		InputMode.CONTROLLER:
			_handle_controller(event)

func _handle_keyboard_mouse(event: InputEvent) -> void:
	# Keyboard actions
	if event is InputEventKey and event.pressed:
		var action := _get_keyboard_action(event)
		if action != "":
			player_input.emit(action, true)

	if event is InputEventKey and not event.pressed:
		var action := _get_keyboard_action(event)
		if action != "":
			player_input.emit(action, false)

	# Mouse click for interact
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			player_input.emit("interact", true)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			player_input.emit("target_next", true)

func _handle_touch(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_process_touch_start(event)
		else:
			_process_touch_end(event)
	elif event is InputEventScreenDrag:
		_process_touch_drag(event)

func _process_touch_start(event: InputEventScreenTouch) -> void:
	_touch_active = true
	var pos := event.position
	var screen_size := get_viewport().get_visible_rect().size
	var normalized := pos / screen_size

	if LEFT_ZONE.has_point(normalized):
		_joystick_active = true
		_joystick_center = pos
		_joystick_touch_id = event.index
	elif RIGHT_ZONE.has_point(normalized):
		# Camera control handled elsewhere
		pass
	else:
		# UI tap - let UI handle it
		pass

var _joystick_active: bool = false

func _process_touch_end(event: InputEventScreenTouch) -> void:
	if event.index == _joystick_touch_id:
		_joystick_active = false
		_joystick_offset = Vector2.ZERO
		_joystick_touch_id = -1
	_touch_active = false

func _process_touch_drag(event: InputEventScreenDrag) -> void:
	if event.index == _joystick_touch_id and _joystick_active:
		_joystick_offset = event.position - _joystick_center
		# Clamp to max radius
		var dist := _joystick_offset.length()
		if dist > _joystick_max_radius:
			_joystick_offset = _joystick_offset.normalized() * _joystick_max_radius

func _handle_controller(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		var action := _get_controller_action(event.button_index)
		if action != "":
			player_input.emit(action, true)

	if event is InputEventJoypadButton and not event.pressed:
		var action := _get_controller_action(event.button_index)
		if action != "":
			player_input.emit(action, false)

func _update_controller() -> void:
	if _controller_id < 0:
		return

	# Left stick - movement
	var lx := Input.get_joy_axis(_controller_id, JOY_AXIS_LEFT_X)
	var ly := Input.get_joy_axis(_controller_id, JOY_AXIS_LEFT_Y)
	_controller_left_stick = _apply_deadzone(Vector2(lx, ly))

	# Right stick - camera
	var rx := Input.get_joy_axis(_controller_id, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(_controller_id, JOY_AXIS_RIGHT_Y)
	_controller_right_stick = _apply_deadzone(Vector2(rx, ry))

	# Check if controller is in use
	if _controller_left_stick.length() > 0.1 or _controller_right_stick.length() > 0.1:
		_controller_last_used = Time.get_ticks_msec()
		if _input_mode != InputMode.CONTROLLER:
			_input_mode = InputMode.CONTROLLER
			input_mode_changed.emit(InputMode.CONTROLLER)

func _apply_deadzone(value: Vector2) -> Vector2:
	var result := value
	if result.length() < _controller_deadzone:
		result = Vector2.ZERO
	return result

func _get_keyboard_action(event: InputEventKey) -> String:
	var code := event.physical_keycode
	for action in _keybindings:
		if code in _keybindings[action]:
			return action
	return ""

func _get_controller_action(button: int) -> String:
	for action in _controller_mappings:
		var mapping: Dictionary = _controller_mappings[action]
		if mapping.has("button") and mapping["button"] == button:
			return action
	return ""

## ============================================================================
## PUBLIC API
## ============================================================================

static func get_instance() -> InputManager:
	return Engine.get_main_loop().root.find_child("InputManager", true, false)

func get_input_mode() -> InputMode:
	return _input_mode

func set_input_mode(mode: InputMode) -> void:
	_input_mode = mode
	input_mode_changed.emit(mode)

func is_mobile() -> bool:
	return _is_mobile

func is_desktop() -> bool:
	return _is_desktop

func is_controller_connected() -> bool:
	return _controller_id >= 0

func get_movement_input() -> Vector2:
	# Priority: Controller > Touch joystick > Keyboard
	if _input_mode == InputMode.CONTROLLER and _controller_left_stick.length() > 0:
		return _controller_left_stick

	if _input_mode == InputMode.TOUCH and _joystick_active:
		return _joystick_offset / _joystick_max_radius

	# Keyboard
	var input := Vector2.ZERO
	if Input.is_action_pressed("move_forward") or Input.is_key_pressed(KEY_W):
		input.y -= 1
	if Input.is_action_pressed("move_backward") or Input.is_key_pressed(KEY_S):
		input.y += 1
	if Input.is_action_pressed("move_left") or Input.is_key_pressed(KEY_A):
		input.x -= 1
	if Input.is_action_pressed("move_right") or Input.is_key_pressed(KEY_D):
		input.x += 1

	return input.normalized()

func get_camera_input() -> Vector2:
	if _input_mode == InputMode.CONTROLLER:
		return _controller_right_stick

	# Mouse drag or touch right zone
	return Vector2.ZERO

func get_joystick_position() -> Vector2:
	return _joystick_offset

func is_joystick_active() -> bool:
	return _joystick_active

func rebind_key(action: String, key_code: int) -> bool:
	if not _keybindings.has(action):
		return false
	_keybindings[action] = [key_code]
	return true

func get_keybind(action: String) -> Array:
	return _keybindings.get(action, [])
