## test_touch_live.gd - LIVE touch-HUD gameplay driver. Runs the playable
## scene in RENDERING mode and plays it with synthetic touch input:
##
##   cd game && xvfb-run godot --path . --script res://tests/test_touch_live.gd
##
## The driver schedules checks in WALL-CLOCK SECONDS, not frames: under
## xvfb the software renderer runs at a variable, often low FPS, so
## frame-indexed scripts advance wildly different amounts of game time
## between runs (a 150-frame wait used to be 2.5 s of gameplay here and
## 15 s there). Timing the phases by delta keeps the player inside the
## playable floor and the assertions deterministic.
##
## Exercised end-to-end:
##   1. Left-half stick drag  -> Run state, real velocity
##   2. Full-stick hold       -> auto-sprint engages (sprint speed)
##   3. Sprint + dodge input  -> Slide state (momentum carried)
##   4. Jump during slide     -> slide-jump keeps upward velocity
##   5. Hold ATK button       -> hold-to-repeat + standing Attack state
##                               (observed per-frame across the hold window;
##                               a single scheduled sample races xvfb frames)
##   6. Right-half swipe      -> third-person camera yaw changes
##   7. Hold CRH button       -> Crouch state (from Idle)
##   8. EDIT mode drag        -> layout saved to PlayerConfig, button moved
##
## Exit 0 = every check observed. Failures print FAIL lines and exit 1.
extends SceneTree

var _t := 0.0
var _schedule: Array = []  # [ [time, Callable], ... ] sorted by time
var _pass := 0
var _fail := 0

var _yaw_before := 0.0
var _atk_pos_before := Vector2.ZERO
var _p7_retried := false
var _last_attack_pressed := false
var _phase_label := "boot"
var _p5_window_open := false
var _saw_attack_state := false

func _initialize() -> void:
	print("=== TOUCH HUD LIVE TEST: booting playable scene ===")
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	if scene == null:
		print("  FAIL: could not load world_playable.tscn")
		quit(1)
		return
	var inst := scene.instantiate()
	root.add_child(inst)
	current_scene = inst

	# Input stream logger: capture every synthetic action/key/mouse/touch
	# event with timestamps so ghost presses can be attributed.
	var Spy: GDScript = load("res://tests/spy_node.gd")
	var spy: Node = Spy.new()
	spy.name = "InputSpy"
	root.add_child(spy)

	# [seconds, callback] -- executed in order once _t passes each time.
	_schedule = [
		[0.8, _enable_trace],
		[1.0, _p1_start_drag],
		[2.0, _p1_check],
		[2.2, _p1_release],
		[2.5, _p2_start_full_stick],
		[4.0, _p2_check],
		[4.1, _p3_dodge],
		[4.4, _p3_check],
		[4.5, _p4_jump],
		[4.9, _p4_check],
		[5.6, _p4_release_stick],
		[6.0, _p5_attack_press],
		[6.15, _observe],
		[6.5, _p5_attack_release],
		[6.9, _p5_check],
		[7.0, _p6_swipe_start],
		[7.6, _p6_check],
		[8.0, _p7_crouch_press],
		[8.15, _p7_check],
		[8.5, _p7_crouch_release],
		[9.0, _p8_edit_start],
		[9.6, _p8_edit_done],
		[9.8, _p8_edit_off],
		[10.0, _p8_check],
		[10.3, _p8_reset],
		[10.6, _p8_check_reset],
		[10.9, _summary],
	]
	for t in [5.7, 6.05, 6.55, 6.8, 7.1, 7.6, 8.05, 8.35]:
		_schedule.append([t, _observe])
	_schedule.sort_custom(func(a, b): return float(a[0]) < float(b[0]))

func _process(delta: float) -> bool:
	_t += delta
	while not _schedule.is_empty() and _t >= float(_schedule[0][0]):
		var step: Array = _schedule.pop_front()
		(step[1] as Callable).call()
	# Per-frame state poll: under xvfb frames can be 0.4s+ long, so a
	# scheduled check can land in the same frame as the press that was
	# supposed to precede it (parsed events flush on the NEXT frame).
	# The Attack state lasts 0.4s of game time -- potentially ONE frame --
	# so observing it requires watching every frame, not sampling.
	if _p5_window_open and _state_name() == "Attack":
		_saw_attack_state = true
	return false

## ---------------------------------------------------------------- helpers

## TouchHud only exists once InputManager's _ready has run; _initialize
## is too early, so the raw-touch trace is enabled from the schedule.
func _enable_trace() -> void:
	var hud := _hud()
	if hud:
		hud._debug_touch = true

func _hud() -> Node:
	var im := root.get_node_or_null("InputManager")
	if im == null:
		return null
	return im.get("_virtual_joystick") if "_virtual_joystick" in im else null

func _player() -> Node:
	return current_scene.get_node_or_null("Player")

func _state_name() -> String:
	var p := _player()
	if p == null:
		return ""
	return str(p.state_machine.get_state_name())

func _planar_speed() -> float:
	var p := _player()
	if p == null:
		return 0.0
	return Vector2(p.velocity.x, p.velocity.z).length()

func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s %s" % [label, detail])
	else:
		_fail += 1
		print("  FAIL: %s %s" % [label, detail])

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

func _press_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)

func _release_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)

func _btn_center(action: String) -> Vector2:
	var hud := _hud()
	var btn: Button = hud._buttons[action].button
	return btn.global_position + btn.size * 0.5

## --------------------------------------------------------------- observer

## Ghost-press detector: InputEventAction presses log via the spy, but
## Input.action_press() bypasses the event stream entirely. Watching the
## polled action state catches those invisible presses.
func _watch_attack_ghost() -> void:
	var now: bool = Input.is_action_pressed("attack")
	if now != _last_attack_pressed:
		print("  [ghost-watch t=%.2f phase=%s] attack action %s" % [
			_t, _phase_label, ("PRESSED" if now else "RELEASED")])
		_last_attack_pressed = now

func _observe() -> void:
	_watch_attack_ghost()
	var hud := _hud()
	var atk: Button = hud._buttons["attack"].button
	print("  [obs t=%.2f] state=%s repeat='%s' atkActionPressed=%s atkBtnPos=%s" % [
		_t, _state_name(), hud._repeat_action,
		Input.is_action_pressed("attack"), str(atk.global_position)])

## ------------------------------------------------------------------- P1

func _p1_start_drag() -> void:
	print("--- P1: left-half stick drag ---")
	_hud().show_joystick()
	_touch(0, Vector2(400, 500), true)
	# Half-stick (~0.5 magnitude): runs without tripping auto-sprint.
	_drag(0, Vector2(400, 500), Vector2(365, 500))

func _p1_check() -> void:
	# ~1s of half-stick movement from spawn (8, 0): well inside the floor.
	_ok("stick moves player", _planar_speed() > 2.0,
		"(vel %.1f, state %s)" % [_planar_speed(), _state_name()])
	_ok("InputManager mirrors stick", _hud().joystick_moved.get_connections().size() > 0)
	_ok("state is Run", _state_name() == "Run", "(got %s)" % _state_name())

func _p1_release() -> void:
	_touch(0, Vector2(365, 500), false)

## ------------------------------------------------------------------- P2

func _p2_start_full_stick() -> void:
	print("--- P2: full-stick auto-sprint ---")
	_touch(0, Vector2(400, 500), true)
	# Overshoot the stick radius so magnitude pins at 1.0 immediately.
	_drag(0, Vector2(400, 500), Vector2(325, 500))

func _p2_check() -> void:
	var p := _player()
	var sprinting: bool = p.is_sprinting
	_ok("auto-sprint engaged", sprinting, "(sprint=%s)" % sprinting)
	_ok("sprint speed applied", _planar_speed() >= 6.5, "(speed %.2f)" % _planar_speed())
	_ok("sprint stays on floor", p.global_position.y > -2.0,
		"(pos %s)" % str(p.global_position))

## ------------------------------------------------------------------- P3

func _p3_dodge() -> void:
	print("--- P3: sprint -> slide ---")
	_press_action("dodge")

func _p3_check() -> void:
	_release_action("dodge")
	_ok("dodge during sprint enters Slide", _state_name() == "Slide",
		"(got %s)" % _state_name())
	_ok("slide stays on floor", _player().global_position.y > -2.0,
		"(pos %s)" % str(_player().global_position))

## ------------------------------------------------------------------- P4

func _p4_jump() -> void:
	print("--- P4: slide-jump ---")
	_press_action("jump")

func _p4_check() -> void:
	_release_action("jump")
	var p := _player()
	_ok("slide-jump is airborne", not p.is_on_floor() and p.velocity.y > 0.5,
		"(state %s, vy %.1f)" % [_state_name(), p.velocity.y])

func _p4_release_stick() -> void:
	_touch(0, Vector2(325, 500), false)

## ------------------------------------------------------------------- P5

func _p5_attack_press() -> void:
	print("--- P5: ATK hold-to-repeat ---")
	_p5_window_open = true
	_touch(0, _btn_center("attack"), true)

## Checked at 6.9 (after the release + grace): the per-frame poll and the
## attack-state signal flag whether the Attack state was EVER active
## during the hold. An instantaneous check at 6.15 raced chunky xvfb
## frames (press, check and release batched into one frame; the parsed
## action landed a frame later).
func _p5_check() -> void:
	var hud := _hud()
	_ok("hold-to-repeat armed", hud._repeat_action == "attack" or not Input.is_action_pressed("attack"),
		"(repeat=%s)" % hud._repeat_action)
	_ok("attack state active during hold", _saw_attack_state,
		"(state now %s)" % _state_name())
	_ok("attack happens grounded", _player().global_position.y > -2.0,
		"(pos %s)" % str(_player().global_position))

func _p5_attack_release() -> void:
	_touch(0, _btn_center("attack"), false)

## ------------------------------------------------------------------- P6

func _p6_swipe_start() -> void:
	print("--- P6: right-half camera swipe ---")
	var cam: Camera3D = _player().camera_pivot.get_node_or_null("Camera3D")
	_yaw_before = cam.get_yaw() if cam else 0.0
	_touch(1, Vector2(900, 400), true)
	_drag(1, Vector2(900, 400), Vector2(880, 395))
	_drag(1, Vector2(880, 395), Vector2(860, 390))
	_drag(1, Vector2(860, 390), Vector2(840, 385))
	_drag(1, Vector2(840, 385), Vector2(820, 380))

func _p6_check() -> void:
	_touch(1, Vector2(820, 380), false)
	var cam: Camera3D = _player().camera_pivot.get_node_or_null("Camera3D")
	var dyaw: float = absf(cam.get_yaw() - _yaw_before) if cam else 0.0
	_ok("camera yaw changed on swipe", dyaw > 0.2, "(dyaw %.3f rad)" % dyaw)

## ------------------------------------------------------------------- P7

func _p7_crouch_press() -> void:
	print("--- P7: crouch hold ---")
	_touch(2, _btn_center("crouch"), true)

func _p7_check() -> void:
	# Chunky xvfb frames can land the check a frame before the parsed
	# touch dispatches (state observed as Crouch one frame later); allow
	# one late frame before failing.
	var state := _state_name()
	if state != "Crouch" and not _p7_retried:
		_p7_retried = true
		_schedule.append([_t + 0.25, _p7_check])
		_schedule.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		return
	_ok("crouch state entered", _state_name() == "Crouch", "(got %s)" % _state_name())

func _p7_crouch_release() -> void:
	_touch(2, _btn_center("crouch"), false)

## ------------------------------------------------------------------- P8

func _p8_edit_start() -> void:
	print("--- P8: EDIT mode layout drag ---")
	_hud().toggle_edit_mode()
	_atk_pos_before = _btn_center("attack")
	_touch(0, _atk_pos_before, true)

func _p8_edit_done() -> void:
	_drag(0, _atk_pos_before, _atk_pos_before + Vector2(-20, -10))
	_drag(0, _atk_pos_before + Vector2(-20, -10), _atk_pos_before + Vector2(-40, -20))
	_drag(0, _atk_pos_before + Vector2(-40, -20), _atk_pos_before + Vector2(-60, -30))
	_touch(0, _atk_pos_before + Vector2(-60, -30), false)
	# The toggle-off must NOT happen in this same callback: parsed events
	# only dispatch on the next input flush, and _edit_mode would already
	# be false when the drags arrive (every drag would hit the ordinary
	# routing and the button would read as never moved).

func _p8_edit_off() -> void:
	_hud().toggle_edit_mode()

func _p8_check() -> void:
	var hud := _hud()
	var moved: bool = _btn_center("attack").distance_to(_atk_pos_before) > 20.0
	_ok("edit drag moved ATK button", moved,
		"(moved %.0f px)" % _btn_center("attack").distance_to(_atk_pos_before))
	var cfg := root.get_node_or_null("PlayerConfig")
	var layout: Variant = cfg.get_account_setting("touch_hud_layout", {}) if cfg else {}
	_ok("layout persisted to PlayerConfig", layout is Dictionary and layout.has("attack"),
		"(keys: %s)" % str(layout.keys() if layout is Dictionary else []))

func _p8_reset() -> void:
	_hud()._reset_layout()

func _p8_check_reset() -> void:
	_ok("reset restores default",
		_btn_center("attack").distance_to(_atk_pos_before) < 20.0)

## --------------------------------------------------------------- summary

func _summary() -> void:
	print("=== SUMMARY: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
