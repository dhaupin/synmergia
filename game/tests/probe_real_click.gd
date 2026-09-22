## probe_real_click.gd - Does a REAL X11 mouse click also report device=-1
## (like synthesized-from-touch mouse events), or a real device id? Run
## under a display with xdotool available:
##
##   cd game && xvfb-run -a sh -c 'godot --path . --script res://tests/probe_real_click.gd & sleep 6; xdotool search --name Godot | head -1 | xargs -I{} xdotool mousemove --window {} 300 300 click 1'
extends SceneTree

var _t := 0.0
var _done := false

func _initialize() -> void:
	var watcher := Node.new()
	watcher.set_script(load("res://tests/spy_node.gd"))
	root.add_child(watcher)
	print("=== REAL CLICK PROBE: waiting for an X11 click... ===")

func _process(delta: float) -> bool:
	_t += delta
	if _t > 12.0 and not _done:
		_done = true
		print("=== END PROBE (timeout) ===")
		quit(0)
		return true
	return false
