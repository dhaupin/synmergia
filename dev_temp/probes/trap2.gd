extends SceneTree
var armed := false
var p = null
func _init() -> void:
	call_deferred("_boot")
func _boot() -> void:
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	var inst = scene.instantiate()
	root.add_child(inst)
	current_scene = inst
	var im = root.get_node_or_null("InputManager")
	# REPLICATE the touch test schedule faithfully: 1.0 drag, 2.0 check, 2.2 release, 2.5 full stick, 4.0 check, 4.1 dodge...
	var sched := [
		[1.0, func(): im.get("_virtual_joystick").show_joystick(); _touch(0, Vector2(400,500), true); _drag(0, Vector2(400,500), Vector2(365,500))],
		[2.2, func(): _touch(0, Vector2(365,500), false)],
		[2.5, func(): _touch(0, Vector2(400,500), true); _drag(0, Vector2(400,500), Vector2(325,500))],
		[4.1, func(): _act("dodge", true)],
		[4.4, func(): _act("dodge", false)],
		[4.5, func(): _act("jump", true)],
		[4.9, func(): _act("jump", false)],
	]
	var t := 0.0
	var idx := 0
	while t < 6.0:
		await process_frame
		t += 1.0/60.0
		while idx < sched.size() and t >= float(sched[idx][0]):
			(sched[idx][1] as Callable).call()
			idx += 1
		if p == null:
			p = current_scene.get_node_or_null("Player")
		elif p.global_position.y > 100.0:
			print("TRIP t=%.2f pos=%s" % [t, p.global_position])
			quit(0)
			return
	print("clean: %s" % str(p.global_position if p else Vector3.ZERO))
	quit(0)
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
func _act(a: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = pressed
	Input.parse_input_event(ev)
