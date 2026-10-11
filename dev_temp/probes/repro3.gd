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
func _act(a: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = pressed
	Input.parse_input_event(ev)
func _process(delta: float) -> bool:
	t += delta
	var cs = current_scene
	var p = cs.get_node_or_null("Player") if cs else null
	if p == null:
		return false
	if phase == 0 and t >= 3.0:
		phase = 1
		_act("dodge", true)
	elif phase == 1 and t >= 3.2:
		phase = 2
		_act("dodge", false)
		print("after dodge pos=", p.global_position)
	elif phase == 2 and t >= 4.0:
		phase = 3
		_act("jump", true)
	elif phase == 3 and t >= 4.3:
		phase = 4
		_act("jump", false)
		print("after jump pos=", p.global_position)
	elif phase == 4 and t >= 5.5:
		phase = 5
		_act("crouch", true)
	elif phase == 5 and t >= 5.8:
		phase = 6
		_act("crouch", false)
		print("after crouch pos=", p.global_position)
	elif phase == 6 and t >= 6.5:
		print("FINAL pos=", p.global_position)
		quit(0)
	return false
