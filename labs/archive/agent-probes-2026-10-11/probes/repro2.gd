extends SceneTree
var t := 0.0
var phase := 0
func _init() -> void:
	call_deferred("_boot")
func _boot() -> void:
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	var inst = scene.instantiate()
	root.add_child(inst)
	current_scene = inst
func _process(delta: float) -> bool:
	t += delta
	var im := root.get_node_or_null("InputManager")
	if im == null:
		return false
	var hud = im.get("_virtual_joystick")
	var cs = current_scene
	var p = cs.get_node_or_null("Player") if cs else null
	if p == null or hud == null:
		return false
	if phase == 0 and t >= 0.8:
		phase = 1
		hud.show_joystick()
		print("shown at pos=", p.global_position)
		_touch(0, Vector2(400, 500), true)
	elif phase == 1 and t >= 1.0:
		phase = 2
		_drag(0, Vector2(400, 500), Vector2(365, 500))
	elif phase == 2 and t >= 2.0:
		phase = 3
		print("after 1s drag pos=", p.global_position, " vel=", p.velocity)
		_touch(0, Vector2(365, 500), false)
	elif phase == 3 and t >= 3.0:
		print("after release pos=", p.global_position)
		quit(0)
	return false
func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = pos
	ev.pressed = pressed
	Input.parse_input_event(ev)
func _drag(idx: int, from: Vector2, to: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = to
	ev.relative = to - from
	Input.parse_input_event(ev)
