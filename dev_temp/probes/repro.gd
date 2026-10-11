extends SceneTree
var t := 0.0
var steps := [[1.0, "drag"], [2.0, "check"], [2.2, "release"]]
var done := {}
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
	if t >= 1.0 and not done.has("drag") and hud != null and p != null:
		done["drag"] = true
		hud.show_joystick()
		_touch(0, Vector2(400, 500), true)
		_drag(0, Vector2(400, 500), Vector2(365, 500))
		print("after drag: player=%s vp=%s" % [p.global_position, get_root().size])
	if t >= 2.0 and not done.has("check"):
		done["check"] = true
		print("t=2 pos=%s vel=%s" % [p.global_position, p.velocity])
	if t >= 3.5:
		print("FINAL pos=%s" % str(p.global_position))
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
