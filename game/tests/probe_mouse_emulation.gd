## probe_mouse_emulation.gd - What does Godot 4.7.2 report for the mouse
## event synthesized from a parsed InputEventScreenTouch? If emulated
## events carry a distinct device id (or position/flags), InputManager
## can drop them deterministically instead of racing a latch.
##
##   cd game && xvfb-run godot --path . --script res://tests/probe_mouse_emulation.gd
extends SceneTree

var _step := 0
var _t := 0.0

func _initialize() -> void:
	var watcher := Node.new()
	watcher.set_script(load("res://tests/spy_node.gd"))
	root.add_child(watcher)
	print("=== MOUSE EMULATION PROBE ===")
	print("project emulate_touch_from_mouse=true; parsing one ScreenTouch...")

func _process(delta: float) -> bool:
	_t += delta
	match _step:
		0:
			if _t < 0.5:
				return false
			var ev := InputEventScreenTouch.new()
			ev.index = 0
			ev.position = Vector2(500, 400)
			ev.pressed = true
			Input.parse_input_event(ev)
			_step = 1
		1:
			if _t < 1.0:
				return false
			var ev := InputEventScreenTouch.new()
			ev.index = 0
			ev.position = Vector2(500, 400)
			ev.pressed = false
			Input.parse_input_event(ev)
			_step = 2
		2:
			if _t < 1.5:
				return false
			print("=== END PROBE ===")
			quit(0)
			return true
	return false
