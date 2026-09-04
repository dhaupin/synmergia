## InteractionLayer - Abstracts input handling for different platforms
## Handles desktop (mouse/keyboard), mobile (touch), and gamepad input
##
## Autoload: Access via `InteractionLayer` globally
extends Node

static var instance: InteractionLayer

enum Platform {
	AUTO = 0,
	DESKTOP = 1,
	MOBILE = 2,
	GAMEPAD = 3
}

enum InteractionType {
	TAP = 0,
	LONG_PRESS = 1,
	DRAG = 2,
	DOUBLE_TAP = 3,
	SWIPE = 4,
	HOVER = 5
}

var _current_platform: Platform = Platform.AUTO
var _is_mobile: bool = false
var _has_gamepad: bool = false

var _is_touching: bool = false
var _touch_start_pos: Vector2 = Vector2.ZERO
var _touch_current_pos: Vector2 = Vector2.ZERO
var _touch_start_time: float = 0
var _last_tap_time: float = 0
var _is_hovering: bool = false
var _hover_position: Vector2 = Vector2.ZERO

var _tap_max_distance: float = 20.0
var _tap_max_time: float = 0.3
var _long_press_time: float = 0.5
var _double_tap_time: float = 0.4

signal interaction(type: InteractionType, position: Vector2)
signal tap(position: Vector2)
signal long_press(position: Vector2)
signal drag(from: Vector2, to: Vector2)
signal double_tap(position: Vector2)
signal swipe(direction: Vector2)
signal hover(position: Vector2)
signal action_triggered(action_name: String)
signal platform_changed(platform: Platform)

func _ready() -> void:
	instance = self
	_detect_platform()
	GameLog.info("InteractionLayer: Initialized for %s" % _get_platform_name())

func _input(event: InputEvent) -> void:
	_process_input(event)

func _process_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
		return
	
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
		return
	
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)
		return
	
	if event is InputEventScreenDrag:
		_handle_screen_drag(event)
		return
	
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_handle_gamepad(event)
		return
	
	if event is InputEventKey and event.pressed:
		_handle_keyboard_action(event)

func _detect_platform() -> void:
	var display_size := DisplayServer.window_get_size()
	
	# Force Desktop mode (Docker/Xvfb doesn't handle touch events well)
	_current_platform = Platform.DESKTOP
	
	platform_changed.emit(_current_platform)

func _get_platform_name() -> String:
	match _current_platform:
		Platform.DESKTOP: return "Desktop"
		Platform.MOBILE: return "Mobile"
		Platform.GAMEPAD: return "Gamepad"
		_: return "Auto"

func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_is_touching = true
		_touch_start_pos = event.position
		_touch_current_pos = event.position
		_touch_start_time = Time.get_ticks_msec() / 1000.0
		
		var time_since_last := Time.get_ticks_msec() / 1000.0 - _last_tap_time
		if time_since_last < _double_tap_time:
			_emit_interaction(InteractionType.DOUBLE_TAP, event.position)
			double_tap.emit(event.position)
			_last_tap_time = 0
		else:
			_last_tap_time = Time.get_ticks_msec() / 1000.0
		
		_start_long_press_check()
	else:
		_handle_touch_end(event.position)

func _handle_touch_end(position: Vector2) -> void:
	if not _is_touching:
		return
	
	var duration := Time.get_ticks_msec() / 1000.0 - _touch_start_time
	var distance: float = _touch_start_pos.distance_to(position)
	
	if distance < _tap_max_distance and duration < _tap_max_time:
		_emit_interaction(InteractionType.TAP, position)
		tap.emit(position)
	elif distance > _tap_max_distance:
		var direction := (position - _touch_start_pos).normalized()
		_emit_interaction(InteractionType.SWIPE, position)
		swipe.emit(direction)
	
	_is_touching = false

func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	_touch_current_pos = event.position
	var total_distance := _touch_start_pos.distance_to(event.position)
	if total_distance > _tap_max_distance:
		_emit_interaction(InteractionType.DRAG, event.position)
		drag.emit(_touch_start_pos, event.position)

func _start_long_press_check() -> void:
	await get_tree().create_timer(_long_press_time).timeout
	if _is_touching:
		var duration := Time.get_ticks_msec() / 1000.0 - _touch_start_time
		if duration >= _long_press_time:
			_emit_interaction(InteractionType.LONG_PRESS, _touch_current_pos)
			long_press.emit(_touch_current_pos)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_emit_interaction(InteractionType.TAP, event.position)
		tap.emit(event.position)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _hover_position != event.position:
		_hover_position = event.position
		_emit_interaction(InteractionType.HOVER, event.position)
		hover.emit(event.position)

func _handle_gamepad(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A:
				_emit_interaction(InteractionType.TAP, Vector2.ZERO)
				tap.emit(Vector2.ZERO)
			JOY_BUTTON_B:
				action_triggered.emit("cancel")
			JOY_BUTTON_X:
				action_triggered.emit("secondary")
			JOY_BUTTON_Y:
				action_triggered.emit("tertiary")

func _handle_keyboard_action(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			action_triggered.emit("cancel")
		KEY_TAB:
			if event.shift_pressed:
				action_triggered.emit("target_prev")
			else:
				action_triggered.emit("target_next")
		KEY_F:
			action_triggered.emit("focus")
		KEY_T:
			action_triggered.emit("target_self")

func _emit_interaction(type: InteractionType, position: Vector2) -> void:
	interaction.emit(type, position)

func get_platform() -> Platform:
	return _current_platform

func is_mobile() -> bool:
	return _is_mobile

func is_desktop() -> bool:
	return _current_platform == Platform.DESKTOP

func has_gamepad() -> bool:
	return _has_gamepad

func get_touch_position() -> Vector2:
	return _touch_current_pos

func is_touching() -> bool:
	return _is_touching

func get_interaction_mode() -> String:
	match _current_platform:
		Platform.MOBILE: return "touch"
		Platform.GAMEPAD: return "gamepad"
		_: return "mouse"

func should_show_tooltips() -> bool:
	return _current_platform == Platform.DESKTOP

func get_button_size() -> Vector2:
	return Vector2(90, 50) if _is_mobile else Vector2(80, 35)

static func get_instance() -> InteractionLayer:
	return instance
