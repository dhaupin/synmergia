## probe_button_touch.gd - Empirical probes used while debugging the
## touch HUD:
##   A. Do synthetic InputEventScreenTouch press/release pairs drive a
##      Godot Button (index 0)? Does InputEventAction register?
##   B. Does a touch at index 1 (secondary finger) drive the Button?
##   C. After a real GLOBE boot (planar-retirement Step 5): does TouchHud._input's
##      edit-mode drag path move a button when fed the exact P8
##      event sequence from test_touch_live.gd?
##
##   cd game && xvfb-run godot --path . --script res://tests/probe_button_touch.gd
extends SceneTree

const CROUCH_POS := Vector2(966.4, 666.0)

var _btn: Button
var _world: Node = null
var _downs := 0
var _ups := 0
var _step := 0
var _t := 0.0
var _step_t := 0.0
var _hud_ref: Node = null
var _atk_before := Vector2.ZERO
var _crh_center := Vector2.ZERO

func _initialize() -> void:
	_btn = Button.new()
	_btn.text = "PROBE"
	_btn.size = Vector2(80, 80)
	_btn.position = Vector2(300, 300)
	_btn.button_down.connect(func(): _downs += 1)
	_btn.button_up.connect(func(): _ups += 1)
	root.add_child(_btn)
	# Boot the real open world (the globe) so HUD stacking matches the
	# live test. Async: the globe streams its mesh lane, so _process waits
	# until _world is live before stepping.
	_boot()

func _boot() -> void:
	var boot = load("res://tests/support/globe_boot.gd")
	_world = await boot.boot(self)
	if _world != null:
		current_scene = _world


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

func _hud() -> Node:
	var im := root.get_node_or_null("InputManager")
	if im == null:
		return null
	return im.get("_virtual_joystick") if "_virtual_joystick" in im else null

func _process(delta: float) -> bool:
	if _world == null:
		return false
	_t += delta
	match _step:
		0:
			if _t < 0.5:
				return false
			_touch(0, Vector2(340, 340), true)
			_step = 1
		1:
			print("[A] idx0 press: downs=%d ups=%d" % [_downs, _ups])
			_touch(0, Vector2(340, 340), false)
			_step = 2
		2:
			print("[A] idx0 release: downs=%d ups=%d" % [_downs, _ups])
			var eva := InputEventAction.new()
			eva.action = "attack"
			eva.pressed = true
			Input.parse_input_event(eva)
			_step = 3
		3:
			print("[A] attack action after InputEventAction: pressed=%s" % Input.is_action_pressed("attack"))
			# B: does a SECONDARY touch index drive the Button at all?
			_btn.pressed.connect(_b_done, CONNECT_ONE_SHOT)
			_touch(1, Vector2(340, 340), true)
			_step = 4
		4:
			print("[B] idx1 press: downs=%d ups=%d" % [_downs, _ups])
			_touch(1, Vector2(340, 340), false)
			_step = 5
		5:
			# C: edit-mode drag with the exact P8 sequence. NOTE: parsed
			# events dispatch on the NEXT input flush, so every stage here
			# waits ~0.2 s before acting/checking. Checking in the same
			# frame always reads 0 px and once masked a harness bug as a
			# code bug.
			_hud_ref = _hud()
			if _hud_ref == null:
				print("[C] no TouchHud found")
				quit(0)
				return true
			_hud_ref.show_joystick()
			_hud_ref._debug_touch = true
			_hud_ref.toggle_edit_mode()
			var atk: Button = _hud_ref._buttons["attack"].button
			_atk_before = atk.global_position
			print("[C] edit=%s atk_before=%s btn_mouse_filter=%d" % [
				_hud_ref._edit_mode, str(_atk_before), atk.mouse_filter])
			_touch(0, _atk_before, true)
			_step = 50
			_step_t = _t
		50:
			if _t - _step_t < 0.2:
				return false
			_drag(0, _atk_before, _atk_before + Vector2(-20, -10))
			_drag(0, _atk_before + Vector2(-20, -10), _atk_before + Vector2(-40, -20))
			_step = 51
			_step_t = _t
		51:
			if _t - _step_t < 0.2:
				return false
			_touch(0, _atk_before + Vector2(-40, -20), false)
			_step = 52
			_step_t = _t
		52:
			if _t - _step_t < 0.2:
				return false
			# [C] result
			var atk2: Button = _hud_ref._buttons["attack"].button
			var moved := (atk2.global_position - _atk_before).length()
			print("[C] after drag: moved=%.1f px edit=%s" % [moved, _hud_ref._edit_mode])
			_hud_ref.toggle_edit_mode()
			_step = 60
			_step_t = _t
		60:
			# [D] Crouch-button probe. The live test touches CRH with
			# finger index 2 and got no action event. Isolate: does the
			# button fire at index 0? Dump any sibling Controls covering
			# the point so a stacking steal is visible.
			if _t - _step_t < 0.5:
				return false
			if _downs > 0:
				_btn.button_down.disconnect(_count_down)
			if _ups > 0:
				_btn.button_up.disconnect(_count_up)
			var crh: Button = _hud_ref._buttons["crouch"].button
			var crh_center: Vector2 = crh.global_position + crh.size * 0.5
			_crh_center = crh_center
			var hud_layer: Node = _world.get_node_or_null("HudLayer")
			var mm: Node = hud_layer.get_node_or_null("MenuManager") if hud_layer else null
			print("[D] touchhud.layer=%d hudlayer.layer=%s menumanager.layer=%s" % [
				_hud_ref.layer,
				str(hud_layer.layer) if hud_layer else "?",
				str(mm.layer) if mm else "?"])
			_downs = 0
			_ups = 0
			crh.button_down.connect(_count_down)
			crh.button_up.connect(_count_up)
			print("[D] crh center=%s filter=%d visible=%s" % [
				str(crh_center), crh.mouse_filter, str(crh.is_visible_in_tree())])
			_dump_controls_at(crh_center)
			_touch(0, crh_center, true)
			_step = 61
			_step_t = _t
		61:
			if _t - _step_t < 0.3:
				return false
			_touch(0, _crh_center, false)
			_step = 62
			_step_t = _t
		62:
			if _t - _step_t < 0.3:
				return false
			print("[D] idx0: downs=%d ups=%d attack_pressed=%s" % [
				_downs, _ups, str(Input.is_action_pressed("crouch"))])
			# [E] same point, index 2 (the live test's finger)
			_downs = 0
			_ups = 0
			_touch(2, _crh_center, true)
			_step = 63
			_step_t = _t
		63:
			if _t - _step_t < 0.3:
				return false
			_touch(2, _crh_center, false)
			_step = 64
			_step_t = _t
		64:
			if _t - _step_t < 0.3:
				return false
			print("[D] idx2: downs=%d ups=%d crouch_pressed=%s" % [
				_downs, _ups, str(Input.is_action_pressed("crouch"))])
			quit(0)
			return true
	return false

func _count_down() -> void:
	_downs += 1

func _count_up() -> void:
	_ups += 1

## Print every visible Control whose rect covers `pos`, deepest last
## (GUI dispatch gives the event to the DEEPEST topmost control).
func _dump_controls_at(pos: Vector2) -> void:
	var stack: Array = [[root, 0]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node = entry[0]
		var depth: int = entry[1]
		if node is Control:
			var ctl := node as Control
			if ctl.is_visible_in_tree() and Rect2(ctl.global_position, ctl.size).has_point(pos):
				print("[D]   cover: depth=%d %s (filter=%d)" % [depth, node.get_path(), ctl.mouse_filter])
		for child in node.get_children():
			stack.push_back([child, depth + 1])

func _b_done() -> void:
	print("[B] idx1 press DID reach the button (button_down fired)")
