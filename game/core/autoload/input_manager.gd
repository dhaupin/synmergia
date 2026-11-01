## InputManager - Unified input handling for desktop, mobile, and controller
## Handles keyboard/mouse, touch, and gamepad input with automatic platform detection
extends Node

## Input modes
enum InputMode {
	AUTO,          # Auto-detect based on last input
	KEYBOARD_MOUSE,
	TOUCH,
	CONTROLLER
}

## Current input mode
var _input_mode: InputMode = InputMode.AUTO
var _last_input_type: String = ""

## Signals
signal input_mode_changed(mode: InputMode)
signal player_input(action: String, pressed: bool)
signal controller_connected()
signal controller_disconnected()
signal camera_move(relative: Vector2)

## Platform detection
var _is_mobile: bool = false
var _is_desktop: bool = false
var _is_web: bool = false

## Controller state
var _controller_id: int = -1
var _controller_deadzone: float = 0.15
var _controller_last_used: float = 0.0
var _controller_left_stick: Vector2 = Vector2.ZERO
var _controller_right_stick: Vector2 = Vector2.ZERO

## Touch state (legacy - now handled by VirtualJoystick)
var _joystick_active: bool = false
var _joystick_offset: Vector2 = Vector2.ZERO
var _joystick_max_radius: float = 60.0
var _camera_move: Vector2 = Vector2.ZERO

## TouchHud component (res://ui/components/virtual_joystick.gd).
## The identifier must never collide with Godot's native VirtualJoystick
## class, which the old script's class_name shadowed until parse.
const TouchHud = preload("res://ui/components/virtual_joystick.gd")
var _virtual_joystick: TouchHud = null

## Keybindings (action -> key codes)
var _keybindings: Dictionary = {
	"move_forward": [KEY_W, KEY_UP],
	"move_backward": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"dodge": [KEY_Q],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL],
	"interact": [KEY_E],
	"target_self": [KEY_F1],
	"target_nearest": [KEY_F2],
	"target_previous": [KEY_TAB],
	"target_next": [KEY_TAB],
	"ability_1": [KEY_1],
	"ability_2": [KEY_2],
	"ability_3": [KEY_3],
	"ability_4": [KEY_4],
	"ability_5": [KEY_5],
	"ability_6": [KEY_6],
	"ability_7": [KEY_7],
	"ability_8": [KEY_8],
	"open_inventory": [KEY_I],
	"open_character": [KEY_C],
	"open_skills": [KEY_K],
	"open_quests": [KEY_J],
	"open_map": [KEY_M],
	"open_chat": [KEY_ENTER],
	"open_friends": [KEY_F],
	"open_party": [KEY_P],
	"open_guild": [KEY_G],
	"open_settings": [KEY_ESCAPE],
	"close_ui": [KEY_ESCAPE],
	"toggle_pvp": [KEY_H],
	"sit": [KEY_Z],
	"emote": [KEY_SLASH]
}

## Controller mappings (action -> joystick/button)
var _controller_mappings: Dictionary = {
	"move_axis_x": {"stick": 0, "axis": 0},  # Left stick X
	"move_axis_y": {"stick": 0, "axis": 1},  # Left stick Y
	"camera_x": {"stick": 1, "axis": 2},       # Right stick X
	"camera_y": {"stick": 1, "axis": 3},       # Right stick Y
	"interact": {"button": JOY_BUTTON_A},
	"jump": {"button": JOY_BUTTON_A},
	"dodge": {"button": JOY_BUTTON_B},
	"target_next": {"button": JOY_BUTTON_RIGHT_SHOULDER},
	"ability_1": {"button": JOY_BUTTON_DPAD_UP},
	"ability_2": {"button": JOY_BUTTON_DPAD_RIGHT},
	"ability_3": {"button": JOY_BUTTON_DPAD_DOWN},
	"ability_4": {"button": JOY_BUTTON_DPAD_LEFT},
	"open_inventory": {"button": JOY_BUTTON_Y},
	"open_character": {"button": JOY_BUTTON_X},
	"open_map": {"button": JOY_BUTTON_START},
	"pause": {"button": JOY_BUTTON_START}
}

func _ready() -> void:
	_detect_platform()
	_check_controller()
	_setup_input_actions()
	camera_move.connect(_on_camera_move)
	# Engine-level joypad plug/drop: controller_disconnected had zero
	# emitters for the whole scaffolding era (the boot check only
	# connected), so HUD could never drop the pad's soft state. One
	# engine signal, both legs honest.
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)

	# The COD-style touch HUD is created on every platform so desktop
	# players can toggle it on too (Settings > Controls > Touch Controls).
	# It is created HIDDEN on every platform: gameplay gating (feedback
	# #1) owns its visibility, and _on_gameplay_state_changed re-reveals
	# it the moment the game reaches a playable state. Without the gate
	# the controls rendered over the main menu, character select, and
	# every non-playable scene on touch devices.
	_create_virtual_joystick()
	if GameManager:
		if not GameManager.game_state_changed.is_connected(_on_gameplay_state_changed):
			GameManager.game_state_changed.connect(_on_gameplay_state_changed)
		if not GameManager.paused.is_connected(_on_gameplay_state_changed):
			GameManager.paused.connect(_on_gameplay_state_changed)
		if not GameManager.resumed.is_connected(_on_gameplay_state_changed):
			GameManager.resumed.connect(_on_gameplay_state_changed)
		_on_gameplay_state_changed()
	else:
		GameLog.warn("InputManager: GameManager absent; touch HUD stays hidden")

	GameLog.info("InputManager: Mode=%s Mobile=%s Desktop=%s" % [_input_mode, _is_mobile, _is_desktop])


## Touch-HUD gameplay gate (feedback #1 + #5): the touch controls are
## part of the cohesive playable-HUD system, so they may only render in
## a playable state (PLAYING, or PAUSED where the HUD keeps context).
## Menus, character select, and any non-playable scene never see them.
## The per-platform PREFERENCE (PlayerConfig "touch_controls") decides
## WHETHER the controls appear in gameplay, not the state gate itself.
func _on_gameplay_state_changed(_state: int = 0) -> void:
	var gameplay: bool = false
	if GameManager:
		var st := GameManager.get_state()
		gameplay = (st == GameManager.GameState.PLAYING or st == GameManager.GameState.PAUSED)
	if _virtual_joystick == null:
		return
	if not gameplay:
		# hide_joystick, not just visible=false: CanvasLayer._input still
		# receives events while invisible, so an "enabled but hidden" HUD
		# would keep capturing touches in menus.
		_virtual_joystick.hide_joystick()
		_virtual_joystick.set_panels_open(false)
		return
	var want: bool = _is_mobile or _input_mode == InputMode.TOUCH
	if PlayerConfig:
		want = bool(PlayerConfig.get_account_setting("touch_controls", want))
	if want:
		set_touch_ui_visible(true)
		# A panel opened while we were hidden (or the boot race) must not
		# leave the touch HUD armed over it.
		_virtual_joystick.set_panels_open(false)
		var mm = get_node_or_null("/root/MenuManager")
		if mm != null and mm.get("_is_menu_open"):
			_virtual_joystick.set_panels_open(true)
	else:
		_virtual_joystick.hide_joystick()


## Panels opened/closed (MenuManager funnel). Forwards to the touch HUD
## so it yields while any panel is up (feedback #3: panels over touch).
func set_touch_hud_panels_open(open_now: bool) -> void:
	var vj := get_virtual_joystick()
	if vj != null and vj.has_method("set_panels_open"):
		vj.set_panels_open(open_now)


func _detect_platform() -> void:
	_is_web = OS.has_feature("web")
	_is_mobile = (
		DisplayServer.get_name() == "Android" or
		DisplayServer.get_name() == "iOS" or
		OS.has_feature("mobile")
	)
	# S14-web: the web export IS touch-capable hardware whenever the
	# browser reports a coarse pointer (phones/tablets). Without this,
	# a phone browser was classed desktop: no touch HUD, no stick, no
	# buttons -- the world rendered but had no controls at all. The
	# PlayerConfig "touch_controls" setting still overrides in either
	# direction.
	if _is_web and DisplayServer.is_touchscreen_available():
		_is_mobile = true
	_is_desktop = (
		DisplayServer.get_name() == "Windows" or
		DisplayServer.get_name() == "Linux" or
		DisplayServer.get_name() == "macOS"
	)

	# Default mode based on platform
	if _is_mobile:
		_input_mode = InputMode.TOUCH
	elif _is_web:
		_input_mode = InputMode.AUTO
	else:
		_input_mode = InputMode.KEYBOARD_MOUSE

func _setup_input_actions() -> void:
	# Create input actions if they don't exist
	var actions := [
		"move_forward", "move_backward", "move_left", "move_right",
		"jump", "dodge", "sprint", "crouch", "interact",
		"ability_1", "ability_2", "ability_3", "ability_4",
		"ability_5", "ability_6", "ability_7", "ability_8"
	]
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

func _check_controller() -> void:
	for i in Input.get_connected_joypads():
		_controller_id = i
		controller_connected.emit()
		break

## Engine hook: the plug/drop law. A drop only counts when it is THE
## pad we were tracking; a plug re-checks and re-emits connected.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_check_controller()
		GameLog.info("InputManager: Joypad %d connected" % device)
		return
	if _controller_id == device:
		_controller_id = -1
		controller_disconnected.emit()
		GameLog.info("InputManager: Joypad %d disconnected" % device)

func _create_virtual_joystick() -> void:
	if _virtual_joystick:
		return

	_virtual_joystick = TouchHud.new()
	add_child(_virtual_joystick)
	_virtual_joystick.joystick_moved.connect(_on_virtual_joystick_moved)
	_virtual_joystick.joystick_released.connect(_on_virtual_joystick_released)
	_virtual_joystick.button_pressed.connect(_on_virtual_button_pressed)
	_virtual_joystick.button_released.connect(_on_virtual_button_released)
	# Camera-look drags from the touch HUD feed the same camera_move
	# pipeline the controller right stick uses.
	_virtual_joystick.camera_look.connect(_on_virtual_camera_look)
	# COD auto-sprint: full-stick hold engages sprint like the Shift key.
	_virtual_joystick.sprint_override.connect(_on_virtual_sprint_override)

func _on_virtual_joystick_moved(_offset: Vector2, normalized: Vector2) -> void:
	_joystick_active = true
	_joystick_offset = normalized * _joystick_max_radius

func _on_virtual_joystick_released() -> void:
	_joystick_active = false
	_joystick_offset = Vector2.ZERO

func _on_virtual_camera_look(delta: Vector2) -> void:
	_camera_move = delta
	camera_move.emit(delta)

func _on_virtual_sprint_override(active: bool) -> void:
	player_input.emit("sprint", active)

func _on_virtual_button_pressed(action: String) -> void:
	player_input.emit(action, true)

func _on_virtual_button_released(action: String) -> void:
	player_input.emit(action, false)

func _input(event: InputEvent) -> void:
	_detect_input_type(event)
	_handle_event(event)

func _process(_delta: float) -> void:
	# Poll controller periodically
	if _input_mode == InputMode.CONTROLLER or _input_mode == InputMode.AUTO:
		_update_controller()

func _detect_input_type(event: InputEvent) -> void:
	var new_type := ""
	if event is InputEventKey:
		new_type = "keyboard"
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		new_type = "mouse"
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		new_type = "touch"
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		new_type = "controller"

	# Emulated mouse from touch must never fight the touch mode: every
	# parsed ScreenTouch/Drag also synthesizes a mouse event on desktop,
	# and honoring it downgraded TOUCH -> KEYBOARD_MOUSE while a finger
	# was still down (stick and camera-look died instantly). Ignore
	# synthesized mouse until all fingers lift.
	if (new_type == "mouse"
			and _input_mode == InputMode.TOUCH
			and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE):
		return

	if new_type != _last_input_type and new_type != "":
		_last_input_type = new_type
		_update_input_mode(new_type)

func _update_input_mode(new_type: String) -> void:
	var old_mode := _input_mode
	var new_mode := _input_mode

	match new_type:
		"keyboard", "mouse":
			if _input_mode != InputMode.KEYBOARD_MOUSE:
				new_mode = InputMode.KEYBOARD_MOUSE
		"touch":
			new_mode = InputMode.TOUCH
		"controller":
			new_mode = InputMode.CONTROLLER
			_controller_last_used = Time.get_ticks_msec()

	if new_mode != old_mode and _input_mode != InputMode.AUTO:
		_input_mode = new_mode
		input_mode_changed.emit(new_mode)
	elif new_mode != old_mode:
		_input_mode = new_mode

func _handle_event(event: InputEvent) -> void:
	match _input_mode:
		InputMode.KEYBOARD_MOUSE:
			_handle_keyboard_mouse(event)
		InputMode.TOUCH:
			# Touch input is fully owned by the VirtualJoystick HUD: floating
			# stick (left half), camera look (right half), buttons via GUI.
			pass
		InputMode.CONTROLLER:
			_handle_controller(event)

func _handle_keyboard_mouse(event: InputEvent) -> void:
	# Text entry guard: while the user is typing in a chat LineEdit or
	# any text field, gameplay keys must be inert (typing WASD in chat
	# must not walk the character). _input runs BEFORE GUI focus
	# consumes the event, so this check is the only thing standing
	# between the keyboard and the player.
	if _is_text_entry_focused():
		return
	# Keyboard actions
	if event is InputEventKey and event.pressed:
		var action := _get_keyboard_action(event)
		if action != "":
			player_input.emit(action, true)

	if event is InputEventKey and not event.pressed:
		var action := _get_keyboard_action(event)
		if action != "":
			player_input.emit(action, false)

	# Mouse click for interact. device >= 0 excludes the synthesized
	# echo mouse events Godot generates from parsed touches (they carry
	# device=-1; real X11/Win32 pointer events carry a real id): without
	# this, every touch tap ALSO forged an interact press.
	if event is InputEventMouseButton and event.pressed and event.device >= 0:
		if event.button_index == MOUSE_BUTTON_LEFT:
			player_input.emit("interact", true)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			player_input.emit("target_next", true)

	# Left click - attack. The InputMap mouse binding was removed because
	# emulate_mouse_from_touch synthesized a left click for EVERY touch
	# (stick drags, camera swipes, button taps), forging attack
	# just_pressed edges on mobile. Keyboard/mouse mode re-injects the
	# action edge here so PC click-to-attack still works and touch mode
	# stays clean. device >= 0 is the deterministic synthesized-event
	# filter (probed: parsed touches synthesize mouse events with
	# device=-1; real pointer events carry device=32 under X11): the
	# synthetic click for the FIRST touch can arrive before the touch
	# itself, so mode-based guards alone cannot catch it.
	if event is InputEventMouseButton and event.device >= 0 \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			Input.action_press("attack")
		else:
			Input.action_release("attack")

func _handle_controller(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		var action := _get_controller_action(event.button_index)
		if action != "":
			player_input.emit(action, true)

	if event is InputEventJoypadButton and not event.pressed:
		var action := _get_controller_action(event.button_index)
		if action != "":
			player_input.emit(action, false)

func _update_controller() -> void:
	if _controller_id < 0:
		return

	# Left stick - movement
	var lx := Input.get_joy_axis(_controller_id, JOY_AXIS_LEFT_X)
	var ly := Input.get_joy_axis(_controller_id, JOY_AXIS_LEFT_Y)
	_controller_left_stick = _apply_deadzone(Vector2(lx, ly))

	# Right stick - camera
	var rx := Input.get_joy_axis(_controller_id, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(_controller_id, JOY_AXIS_RIGHT_Y)
	_controller_right_stick = _apply_deadzone(Vector2(rx, ry))

	# Check if controller is in use
	if _controller_left_stick.length() > 0.1 or _controller_right_stick.length() > 0.1:
		_controller_last_used = Time.get_ticks_msec()
		if _input_mode != InputMode.CONTROLLER:
			_input_mode = InputMode.CONTROLLER
			input_mode_changed.emit(InputMode.CONTROLLER)

func _apply_deadzone(value: Vector2) -> Vector2:
	var result := value
	if result.length() < _controller_deadzone:
		result = Vector2.ZERO
	return result

func _get_keyboard_action(event: InputEventKey) -> String:
	var code := event.physical_keycode
	for action in _keybindings:
		if code in _keybindings[action]:
			return action
	return ""


## True while the user is typing into a text control (chat input,
## admin shell, settings fields). Guards both the event pipeline and
## the raw-key movement poll.
func _is_text_entry_focused() -> bool:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return false
	var focus: Control = (loop as SceneTree).root.gui_get_focus_owner()
	if focus == null:
		return false
	return focus is LineEdit or focus is TextEdit or focus is CodeEdit

func _get_controller_action(button: int) -> String:
	for action in _controller_mappings:
		var mapping: Dictionary = _controller_mappings[action]
		if mapping.has("button") and mapping["button"] == button:
			return action
	return ""

func _on_camera_move(relative: Vector2) -> void:
	_camera_move = relative

## ============================================================================
## PUBLIC API
## ============================================================================

static func singleton() -> InputManager:
	return Engine.get_main_loop().root.find_child("InputManager", true, false)

func get_input_mode() -> InputMode:
	return _input_mode

func set_input_mode(mode: InputMode) -> void:
	_input_mode = mode
	input_mode_changed.emit(mode)

func is_mobile() -> bool:
	return _is_mobile

func is_desktop() -> bool:
	return _is_desktop

func is_controller_connected() -> bool:
	return _controller_id >= 0

func get_movement_input() -> Vector2:
	# Text entry guard: raw-key polling ignores GUI focus, so chat
	# typing would otherwise keep driving movement.
	if _is_text_entry_focused():
		return Vector2.ZERO
	# Priority: Controller > Touch joystick > Keyboard
	if _input_mode == InputMode.CONTROLLER and _controller_left_stick.length() > 0:
		return _controller_left_stick

	if _input_mode == InputMode.TOUCH and _joystick_active:
		return _joystick_offset / _joystick_max_radius

	# Keyboard
	var input := Vector2.ZERO
	if Input.is_action_pressed("move_forward") or Input.is_key_pressed(KEY_W):
		input.y -= 1
	if Input.is_action_pressed("move_backward") or Input.is_key_pressed(KEY_S):
		input.y += 1
	if Input.is_action_pressed("move_left") or Input.is_key_pressed(KEY_A):
		input.x -= 1
	if Input.is_action_pressed("move_right") or Input.is_key_pressed(KEY_D):
		input.x += 1

	return input.normalized()

func get_camera_input() -> Vector2:
	if _input_mode == InputMode.CONTROLLER:
		return _controller_right_stick

	if _input_mode == InputMode.TOUCH:
		var move := _camera_move
		_camera_move = Vector2.ZERO
		return move

	return Vector2.ZERO

func get_joystick_position() -> Vector2:
	return _joystick_offset

func is_joystick_active() -> bool:
	return _joystick_active

func set_touch_ui_visible(visible: bool) -> void:
	if _virtual_joystick:
		if visible:
			_virtual_joystick.show_joystick()
		else:
			_virtual_joystick.hide_joystick()
	if PlayerConfig and visible != bool(PlayerConfig.get_account_setting("touch_controls", not visible)):
		PlayerConfig.set_account_setting("touch_controls", visible)

## Direct access for scenes that bridge touch-HUD signals (world_playable
## connects camera_look into the player's ThirdPersonCamera).
func get_virtual_joystick() -> TouchHud:
	return _virtual_joystick

func rebind_key(action: String, key_code: int) -> bool:
	if not _keybindings.has(action):
		return false
	_keybindings[action] = [key_code]
	return true

func get_keybind(action: String) -> Array:
	return _keybindings.get(action, [])
