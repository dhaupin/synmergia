## Unit tests for WebInputBridge event conversion (contract with
## web/shared/input.js). Run:
##   godot --headless --path . --script res://tests/test_web_input_bridge.gd
extends SceneTree

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		printerr("FAIL  ", label)
		_fails += 1

func _run() -> void:
	var bridge = load("res://core/autoload/web_input_bridge.gd").new()

	# --- Mouse buttons ---
	var md = bridge._convert_event({"type": 1, "x": 120, "y": 64, "data": 0})
	_check(md is InputEventMouseButton and md.pressed \
		and md.button_index == MOUSE_BUTTON_LEFT \
		and md.position == Vector2(120, 64), "mouse down left at coords")
	var mr = bridge._convert_event({"type": 2, "x": 5, "y": 6, "data": 1})
	_check(mr is InputEventMouseButton and not mr.pressed \
		and mr.button_index == MOUSE_BUTTON_RIGHT, "mouse up right")
	var mm = bridge._convert_event({"type": 3, "x": 10, "y": 20, "data": 0})
	_check(mm is InputEventMouseMotion \
		and mm.position == Vector2(10, 20), "mouse move carries position")

	# --- Wheel: data 3 = WHEEL_UP, 4 = WHEEL_DOWN, no synthetic release ---
	var wu = bridge._convert_event({"type": 4, "x": 0, "y": 0, "data": 3})
	_check(wu is InputEventMouseButton and wu.pressed \
		and wu.button_index == MOUSE_BUTTON_WHEEL_UP, "wheel up = data 3")
	var wd = bridge._convert_event({"type": 4, "x": 0, "y": 0, "data": 4})
	_check(wd is InputEventMouseButton and wd.pressed \
		and wd.button_index == MOUSE_BUTTON_WHEEL_DOWN, "wheel down = data 4")
	_check(bridge._convert_event({"type": 2, "x": 0, "y": 0, "data": 3}) == null,
		"wheel release is dropped (stateless)")

	# --- Touch: coords carried on all three phases ---
	var ts = bridge._convert_event({"type": 5, "x": 30, "y": 40, "data": 2})
	_check(ts is InputEventScreenTouch and ts.pressed \
		and ts.index == 2 and ts.position == Vector2(30, 40), "touch start")
	var tm = bridge._convert_event({"type": 6, "x": 31, "y": 42, "data": 2})
	_check(tm is InputEventScreenDrag and tm.index == 2 \
		and tm.position == Vector2(31, 42), "touch move carries coords")
	var te = bridge._convert_event({"type": 7, "x": 33, "y": 44, "data": 2})
	_check(te is InputEventScreenTouch and not te.pressed \
		and te.position == Vector2(33, 44), "touch end carries last position")

	# --- Keys: x = JS keyCode, y = modifier mask, data = unicode ---
	var kd = bridge._convert_event({"type": 8, "x": 87, "y": 1, "data": 119})
	_check(kd is InputEventKey and kd.physical_keycode == KEY_W \
		and kd.keycode == KEY_W and kd.shift_pressed \
		and not kd.ctrl_pressed and kd.unicode == 119,
		"key down W +shift +unicode (chat-ready)")
	var ke = bridge._convert_event({"type": 9, "x": 87, "y": 0, "data": 0})
	_check(ke is InputEventKey and not ke.pressed \
		and ke.physical_keycode == KEY_W, "key up W")
	var ka = bridge._convert_event({"type": 8, "x": 65, "y": 2, "data": 97})
	_check(ka.physical_keycode == KEY_A and ka.ctrl_pressed \
		and not ka.shift_pressed, "key down A +ctrl")

	# --- Gamepad ---
	var gb = bridge._convert_event({"type": 11, "x": 0, "y": 5, "data": 1})
	_check(gb is InputEventJoypadButton and gb.device == 0 \
		and gb.button_index == 5 and gb.pressed, "gamepad button")
	var ga = bridge._convert_event({"type": 12, "x": 1, "y": 2, "data": 16384})
	_check(ga is InputEventJoypadMotion and ga.device == 1 \
		and ga.axis == 2 and absf(ga.axis_value - 0.5) < 0.001, "gamepad axis 0.5")

	# --- Misc ---
	_check(bridge._convert_event({"type": 999}) == null, "unknown type -> null")
	_check(bridge._map_keycode(13) == KEY_ENTER, "keycode map ENTER")
	_check(bridge._map_keycode(27) == KEY_ESCAPE, "keycode map ESCAPE")
	_check(bridge._map_keycode(99999) == KEY_UNKNOWN, "unknown keycode -> KEY_UNKNOWN")

	print("SUMMARY: %d checks, %d failed" % [18, _fails])
	if _fails == 0:
		print("ALL TESTS PASSED")
	quit(0 if _fails == 0 else 1)
