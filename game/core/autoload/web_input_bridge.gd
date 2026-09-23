## WebInputBridge - Reads input from JS buffer when running in web browser
## Polls window.SynmergiaInput.drain() each frame and pushes events into
## Godot's input system.
##
## Event contract (mirrored by web/shared/input.js):
##   type 1 mouseDown  / 2 mouseUp  : x,y canvas coords, data = button
##             (0 left, 1 right, 2 middle)
##   type 3 mouseMove               : x,y canvas coords
##   type 4 wheel                   : data = 3 (up) / 4 (down); stateless,
##             no synthetic release is emitted
##   type 5 touchStart / 6 touchMove / 7 touchEnd
##                                  : x,y canvas coords, data = touch index
##   type 8 keyDown  / 9 keyUp      : x = JS keyCode, y = modifier bitmask
##             (1 shift, 2 ctrl, 4 alt), data = unicode char code (0 if none)
##   type 10 resize                 : x,y = new window size
##   type 11 gamepadButton          : x = device, y = button, data = pressed
##   type 12 gamepadAxis            : x = device, y = axis, data = int16 value
extends Node

var _poll_timer: float = 0.0
var _poll_interval: float = 0.016  # ~60fps

func _process(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	_poll_timer += delta
	if _poll_timer < _poll_interval:
		return
	_poll_timer = 0.0
	_poll_js_buffer()

func _poll_js_buffer() -> void:
	var events = JavaScriptBridge.eval("window.SynmergiaInput.drain()", true)
	if not (events is Array) or events.is_empty():
		return
	for evt in events:
		if not (evt is Dictionary):
			continue
		var ev = _convert_event(evt)
		if ev:
			Input.parse_input_event(ev)

func _convert_event(evt: Dictionary) -> InputEvent:
	var type: int = int(evt.get("type", -1))
	var x: int = int(evt.get("x", 0))
	var y: int = int(evt.get("y", 0))
	var data: int = int(evt.get("data", 0))

	match type:
		1:  # mouse down
			var e := InputEventMouseButton.new()
			e.button_index = _map_mouse_button(data)
			e.pressed = true
			e.position = Vector2(x, y)
			e.global_position = Vector2(x, y)
			return e
		2:  # mouse up
			var e := InputEventMouseButton.new()
			e.button_index = _map_mouse_button(data)
			# Wheel "buttons" are stateless impulses; a synthetic release
			# would double-fire zoom in the camera.
			if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				return null
			e.pressed = false
			e.position = Vector2(x, y)
			e.global_position = Vector2(x, y)
			return e
		3:  # mouse move
			var e := InputEventMouseMotion.new()
			e.position = Vector2(x, y)
			e.global_position = Vector2(x, y)
			e.relative = Vector2.ZERO
			return e
		4:  # wheel (data 3 = up, 4 = down, per contract)
			var e := InputEventMouseButton.new()
			e.button_index = _map_mouse_button(data)
			e.pressed = true
			e.position = Vector2(x, y)
			e.global_position = Vector2(x, y)
			return e
		5:  # touch start
			var e := InputEventScreenTouch.new()
			e.index = data
			e.pressed = true
			e.position = Vector2(x, y)
			return e
		6:  # touch move
			var e := InputEventScreenDrag.new()
			e.index = data
			e.position = Vector2(x, y)
			e.relative = Vector2.ZERO
			return e
		7:  # touch end
			var e := InputEventScreenTouch.new()
			e.index = data
			e.pressed = false
			e.position = Vector2(x, y)
			return e
		8:  # key down
			return _make_key_event(x, y, data, true)
		9:  # key up
			return _make_key_event(x, y, data, false)
		10:  # resize
			var vp = get_viewport()
			if vp:
				vp.size = Vector2i(x, y)
			return null
		11:  # gamepad_button: x=device_index, y=button_index, data=pressed(1/0)
			var e := InputEventJoypadButton.new()
			e.device = x
			e.button_index = y
			e.pressed = bool(data)
			e.pressure = 1.0 if data else 0.0
			return e
		12:  # gamepad_axis: x=device_index, y=axis_index, data=value(-32768..32767)
			var e := InputEventJoypadMotion.new()
			e.device = x
			e.axis = y
			e.axis_value = data / 32767.0
			return e
	return null

## Build an InputEventKey from the JS key contract:
## x = JS keyCode, y = modifier bitmask (1 shift, 2 ctrl, 4 alt),
## data = unicode char code for printable keys (0 otherwise).
func _make_key_event(key_code: int, mods: int, unicode: int, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = _map_keycode(key_code)
	e.keycode = e.physical_keycode
	e.pressed = pressed
	e.shift_pressed = (mods & 1) != 0
	e.ctrl_pressed = (mods & 2) != 0
	e.alt_pressed = (mods & 4) != 0
	if unicode > 0:
		e.unicode = unicode
	return e

static func _map_mouse_button(button: int) -> int:
	match button:
		0: return MOUSE_BUTTON_LEFT
		1: return MOUSE_BUTTON_RIGHT
		2: return MOUSE_BUTTON_MIDDLE
		3: return MOUSE_BUTTON_WHEEL_UP
		4: return MOUSE_BUTTON_WHEEL_DOWN
		5: return MOUSE_BUTTON_WHEEL_LEFT
		6: return MOUSE_BUTTON_WHEEL_RIGHT
	return button

static func _map_keycode(keycode: int) -> int:
	# JS keyCode values mapped to Godot physical keycodes
	# Uses e.code where possible (keyCode is deprecated)
	match keycode:
		8: return KEY_BACKSPACE
		9: return KEY_TAB
		13: return KEY_ENTER
		16: return KEY_SHIFT
		17: return KEY_CTRL
		18: return KEY_ALT
		19: return KEY_PAUSE
		20: return KEY_CAPSLOCK
		27: return KEY_ESCAPE
		32: return KEY_SPACE
		33: return KEY_PAGEUP
		34: return KEY_PAGEDOWN
		35: return KEY_END
		36: return KEY_HOME
		37: return KEY_LEFT
		38: return KEY_UP
		39: return KEY_RIGHT
		40: return KEY_DOWN
		44: return KEY_PRINT
		45: return KEY_INSERT
		46: return KEY_DELETE
		48: return KEY_0
		49: return KEY_1
		50: return KEY_2
		51: return KEY_3
		52: return KEY_4
		53: return KEY_5
		54: return KEY_6
		55: return KEY_7
		56: return KEY_8
		57: return KEY_9
		65: return KEY_A
		66: return KEY_B
		67: return KEY_C
		68: return KEY_D
		69: return KEY_E
		70: return KEY_F
		71: return KEY_G
		72: return KEY_H
		73: return KEY_I
		74: return KEY_J
		75: return KEY_K
		76: return KEY_L
		77: return KEY_M
		78: return KEY_N
		79: return KEY_O
		80: return KEY_P
		81: return KEY_Q
		82: return KEY_R
		83: return KEY_S
		84: return KEY_T
		85: return KEY_U
		86: return KEY_V
		87: return KEY_W
		88: return KEY_X
		89: return KEY_Y
		90: return KEY_Z
		91: return KEY_META
		92: return KEY_META
		93: return KEY_MENU
		96: return KEY_KP_0
		97: return KEY_KP_1
		98: return KEY_KP_2
		99: return KEY_KP_3
		100: return KEY_KP_4
		101: return KEY_KP_5
		102: return KEY_KP_6
		103: return KEY_KP_7
		104: return KEY_KP_8
		105: return KEY_KP_9
		106: return KEY_KP_MULTIPLY
		107: return KEY_KP_ADD
		108: return KEY_KP_ENTER
		109: return KEY_KP_SUBTRACT
		110: return KEY_KP_PERIOD
		111: return KEY_KP_DIVIDE
		112: return KEY_F1
		113: return KEY_F2
		114: return KEY_F3
		115: return KEY_F4
		116: return KEY_F5
		117: return KEY_F6
		118: return KEY_F7
		119: return KEY_F8
		120: return KEY_F9
		121: return KEY_F10
		122: return KEY_F11
		123: return KEY_F12
		124: return KEY_F13
		125: return KEY_F14
		126: return KEY_F15
		127: return KEY_F16
		128: return KEY_F17
		129: return KEY_F18
		130: return KEY_F19
		131: return KEY_F20
		132: return KEY_F21
		133: return KEY_F22
		134: return KEY_F23
		135: return KEY_F24
		136: return KEY_F25
		137: return KEY_F26
		138: return KEY_F27
		139: return KEY_F28
		140: return KEY_F29
		141: return KEY_F30
		142: return KEY_F31
		143: return KEY_F32
		144: return KEY_NUMLOCK
		145: return KEY_SCROLLLOCK
		160: return KEY_SHIFT
		161: return KEY_SHIFT
		162: return KEY_CTRL
		163: return KEY_CTRL
		164: return KEY_ALT
		165: return KEY_ALT
	return KEY_UNKNOWN
