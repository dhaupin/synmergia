## VirtualJoystick - COD Mobile-style touch HUD (CanvasLayer).
## Floating left-half joystick, right-side action cluster (attack / jump /
## crouch / slide / interact / skills 1-4), hold-to-repeat attack,
## auto-sprint at full stick, camera-look drags on the right half, and a
## layout edit mode whose button positions persist through PlayerConfig
## ("touch_hud_layout" account setting).
##
## Button presses for movement-poll actions (jump/dodge/crouch/attack) are
## injected with Input.parse_input_event(InputEventAction) so state scripts
## using Input.is_action_just_pressed() react to touch the same way they do
## to the keyboard. Ability/interact buttons go through the button_pressed
## signal -> InputManager.player_input path instead.
extends CanvasLayer
class_name TouchHud

const LAYOUT_SETTING := "touch_hud_layout"
const AUTO_SPRINT_ENGAGE := 0.92     # stick magnitude to start auto-sprint
const AUTO_SPRINT_RELEASE := 0.75    # magnitude below which it cancels
const AUTO_SPRINT_DELAY := 0.28      # seconds at full stick before engaging
const ATTACK_REPEAT_INTERVAL := 0.45 # hold-to-repeat cadence
const STICK_RADIUS := 70.0
const HINT_ALPHA := 0.35
## Layering (play-day feedback #3: panels must cover the touch HUD).
## MenuManager (which owns every panel) is a CanvasLayer at 20; the
## touch HUD sits just BELOW it so open panels always draw over the
## movement controls, and drops to 6 when hidden. The panel funnel
## (MenuManager._open_panel/_close_panel) calls
## InputManager.set_touch_hud_panels_open() so the touch controls also
## STOP CAPTURING input while a panel is up -- layering alone keeps
## drawing honest, but _input would still eat drags meant for panels.
const LAYER_ABOVE_HUD := 18
const LAYER_IDLE := 6

## Controls this HUD replaces while active. When the touch HUD is
## visible the desktop action bar / quick access bar are hidden: the
## same abilities sit in the touch cluster, and their STOP-filter slot
## rows overlay the CRH/ACT buttons otherwise.
const REPLACED_HUD_NODES := ["ActionBar", "QuickAccessBar"]

signal joystick_moved(offset: Vector2, normalized: Vector2)
signal joystick_released()
signal button_pressed(action: String)
signal button_released(action: String)
signal camera_look(delta: Vector2)
signal sprint_override(active: bool)

## Default COD-style cluster. Positions are normalized screen centers
## (0-1), so the layout survives any resolution. "repeat" = hold-to-repeat.
const DEFAULT_BUTTONS: Array = [
	{"action": "attack", "text": "ATK", "pos": Vector2(0.86, 0.80), "size": Vector2(96, 96), "repeat": true},
	{"action": "jump", "text": "JMP", "pos": Vector2(0.955, 0.655), "size": Vector2(72, 72), "repeat": false},
	{"action": "crouch", "text": "CRH", "pos": Vector2(0.755, 0.925), "size": Vector2(72, 72), "repeat": false},
	{"action": "dodge", "text": "DSL", "pos": Vector2(0.655, 0.795), "size": Vector2(80, 80), "repeat": false},
	{"action": "interact", "text": "ACT", "pos": Vector2(0.555, 0.905), "size": Vector2(64, 64), "repeat": false},
	{"action": "ability_1", "text": "1", "pos": Vector2(0.555, 0.655), "size": Vector2(56, 56), "repeat": false},
	{"action": "ability_2", "text": "2", "pos": Vector2(0.635, 0.565), "size": Vector2(56, 56), "repeat": false},
	{"action": "ability_3", "text": "3", "pos": Vector2(0.725, 0.475), "size": Vector2(56, 56), "repeat": false},
	{"action": "ability_4", "text": "4", "pos": Vector2(0.825, 0.395), "size": Vector2(56, 56), "repeat": false},
]

var _buttons: Dictionary = {}          # action -> {"button": Button, "pos": Vector2, "size": Vector2, "repeat": bool}
var _edit_mode: bool = false
var _edit_button: Button = null
var _done_button: Button = null
var _reset_button: Button = null
var _edit_hint: Label = null

var _stick_visible: bool = false
var _joystick_touch_id: int = -1
var _joystick_center: Vector2 = Vector2.ZERO
var _stick_offset: Vector2 = Vector2.ZERO
var _camera_touch_id: int = -1
var _camera_last_pos: Vector2 = Vector2.ZERO
var _edit_drag_action: String = ""
var _edit_drag_offset: Vector2 = Vector2.ZERO

var _base: TextureRect = null
var _thumb: TextureRect = null
var _hint_base: TextureRect = null

var _enabled: bool = true
var _panels_open: bool = false      # a panel/menu is up: yield to it
var _debug_touch: bool = false      # tests: trace raw touch routing
var _high_contrast: bool = false
var _repeat_timer: float = 0.0
var _repeat_action: String = ""
var _auto_sprint_on: bool = false
var _full_stick_time: float = 0.0

func _ready() -> void:
	layer = LAYER_IDLE
	_setup_high_contrast()
	_create_stick_visuals()
	_create_buttons()
	_create_edit_ui()
	_load_layout()
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)
	set_process(true)

func _setup_high_contrast() -> void:
	if PlayerConfig:
		_high_contrast = bool(PlayerConfig.get_account_setting("high_contrast", false))

## ---------------------------------------------------------------------------
## Controls construction
## ---------------------------------------------------------------------------

func _create_stick_visuals() -> void:
	var colors: Dictionary = UIStyles.get_effective_colors(_high_contrast)
	_base = _make_circle_rect(Vector2(140, 140), colors.get("background_dark", Color(0.1, 0.1, 0.14, 0.6)))
	_thumb = _make_circle_rect(Vector2(64, 64), colors.get("accent", Color(0.9, 0.75, 0.3, 0.9)))
	_hint_base = _make_circle_rect(Vector2(140, 140), Color(1, 1, 1, 0.06))
	_hint_base.modulate.a = HINT_ALPHA
	add_child(_hint_base)
	add_child(_base)
	add_child(_thumb)
	_base.visible = false
	_thumb.visible = false
	_hint_base.visible = false

func _make_circle_rect(size: Vector2, color: Color) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = size
	rect.size = size
	rect.texture = _create_circle_texture(int(size.x * 0.5), color)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _create_circle_texture(radius: int, color: Color) -> ImageTexture:
	var img := Image.create(radius * 2, radius * 2, false, Image.FORMAT_RGBA8)
	var center := Vector2(radius, radius)
	for x in range(radius * 2):
		for y in range(radius * 2):
			if Vector2(x, y).distance_to(center) <= float(radius):
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)

func _create_buttons() -> void:
	var colors: Dictionary = UIStyles.get_effective_colors(_high_contrast)
	for cfg in DEFAULT_BUTTONS:
		var btn := Button.new()
		btn.text = str(cfg.text)
		btn.size = cfg.size
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 16 if cfg.size.x >= 72 else 13)
		btn.add_theme_color_override("font_color", colors.get("text_primary", Color.WHITE))
		btn.add_theme_color_override("font_pressed_color", colors.get("text_primary", Color.WHITE))
		btn.add_theme_color_override("font_hover_color", colors.get("text_primary", Color.WHITE))
		btn.add_theme_stylebox_override("normal", _button_style(colors, false))
		btn.add_theme_stylebox_override("hover", _button_style(colors, false))
		btn.add_theme_stylebox_override("pressed", _button_style(colors, true))
		btn.add_theme_stylebox_override("focus", _button_style(colors, false))
		btn.button_down.connect(_on_button_down.bind(str(cfg.action)))
		btn.button_up.connect(_on_button_up.bind(str(cfg.action)))
		# A11y (round 2): short HUD labels are meaningless to readers and
		# agents; the annotated action names the VERB ("Attack", "Jump").
		var verb_map := {
			"attack": "Attack", "jump": "Jump", "crouch": "Crouch",
			"dodge": "Dodge", "interact": "Interact",
			"ability_1": "Use ability 1", "ability_2": "Use ability 2",
			"ability_3": "Use ability 3", "ability_4": "Use ability 4",
		}
		var verb: String = verb_map.get(str(cfg.action), str(cfg.action))
		if UIStyles and "apply_accessibility" in UIStyles:
			UIStyles.apply_accessibility(
				btn,
				verb,
				"Hold to act" if bool(cfg.get("repeat", false)) else "Tap to " + verb.to_lower()
			)
		add_child(btn)
		_buttons[str(cfg.action)] = {
			"button": btn,
			"pos": cfg.pos,
			"size": cfg.size,
			"repeat": bool(cfg.get("repeat", false)),
		}

func _button_style(colors: Dictionary, pressed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colors.get("accent", Color(0.9, 0.75, 0.3)) if pressed \
			else Color(colors.get("background", Color(0.12, 0.12, 0.16, 0.75)).r,
				colors.get("background", Color(0.12, 0.12, 0.16, 0.75)).g,
				colors.get("background", Color(0.12, 0.12, 0.16, 0.75)).b, 0.75)
	style.set_corner_radius_all(999)  # circle
	style.set_border_width_all(2)
	style.border_color = colors.get("border_highlight", Color(1, 1, 1, 0.5))
	return style

func _create_edit_ui() -> void:
	var colors: Dictionary = UIStyles.get_effective_colors(_high_contrast)
	_edit_button = Button.new()
	_edit_button.text = "EDIT"
	_edit_button.size = Vector2(56, 30)
	_edit_button.focus_mode = Control.FOCUS_NONE
	_edit_button.add_theme_font_size_override("font_size", 12)
	_edit_button.add_theme_color_override("font_color", colors.get("text_primary", Color.WHITE))
	_edit_button.add_theme_stylebox_override("normal", _chip_style(colors))
	_edit_button.add_theme_stylebox_override("hover", _chip_style(colors))
	_edit_button.add_theme_stylebox_override("pressed", _chip_style(colors))
	_edit_button.pressed.connect(toggle_edit_mode)
	add_child(_edit_button)
	_buttons["_edit"] = {"button": _edit_button, "pos": Vector2(0.965, 0.045), "size": _edit_button.size, "repeat": false}

	_done_button = Button.new()
	_done_button.text = "DONE"
	_done_button.size = Vector2(64, 34)
	_done_button.focus_mode = Control.FOCUS_NONE
	_done_button.add_theme_font_size_override("font_size", 13)
	_done_button.add_theme_color_override("font_color", Color(0.1, 0.4, 0.2))
	_done_button.add_theme_stylebox_override("normal", _chip_style(colors))
	_done_button.add_theme_stylebox_override("hover", _chip_style(colors))
	_done_button.add_theme_stylebox_override("pressed", _chip_style(colors))
	_done_button.pressed.connect(toggle_edit_mode)
	_done_button.visible = false
	add_child(_done_button)

	_reset_button = Button.new()
	_reset_button.text = "RESET"
	_reset_button.size = Vector2(72, 34)
	_reset_button.focus_mode = Control.FOCUS_NONE
	_reset_button.add_theme_font_size_override("font_size", 13)
	_reset_button.add_theme_color_override("font_color", colors.get("text_primary", Color.WHITE))
	_reset_button.add_theme_stylebox_override("normal", _chip_style(colors))
	_reset_button.add_theme_stylebox_override("hover", _chip_style(colors))
	_reset_button.add_theme_stylebox_override("pressed", _chip_style(colors))
	_reset_button.pressed.connect(_reset_layout)
	_reset_button.visible = false
	add_child(_reset_button)

	_edit_hint = Label.new()
	_edit_hint.text = "Drag buttons to rearrange, then DONE (saved to your account)"
	_edit_hint.add_theme_font_size_override("font_size", 13)
	_edit_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_edit_hint.visible = false
	add_child(_edit_hint)

func _chip_style(colors: Dictionary) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(colors.get("background", Color(0.12, 0.12, 0.16)).r,
		colors.get("background", Color(0.12, 0.12, 0.16)).g,
		colors.get("background", Color(0.12, 0.12, 0.16)).b, 0.8)
	style.set_corner_radius_all(8)
	style.set_border_width_all(1)
	style.border_color = colors.get("border", Color(1, 1, 1, 0.3))
	return style

## ---------------------------------------------------------------------------
## Layout edit mode + persistence
## ---------------------------------------------------------------------------

func toggle_edit_mode() -> void:
	_set_edit_mode(not _edit_mode)

func _set_edit_mode(active: bool) -> void:
	_edit_mode = active
	var vp_size := get_viewport().get_visible_rect().size
	for action in _buttons:
		var entry: Dictionary = _buttons[action]
		var btn: Button = entry.button
		# In edit mode buttons stop consuming input so raw drags move them.
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE if active else Control.MOUSE_FILTER_STOP
		entry.pos.x = clampf(entry.pos.x, 0.04, 0.96)
		entry.pos.y = clampf(entry.pos.y, 0.04, 0.96)
	_edit_button.visible = not active
	_done_button.visible = active
	_reset_button.visible = active
	_edit_hint.visible = active
	if active:
		_done_button.position = Vector2(vp_size.x * 0.965 - 64, vp_size.y * 0.045 - 17)
		_reset_button.position = Vector2(vp_size.x * 0.965 - 64 - 80, vp_size.y * 0.045 - 17)
		_edit_hint.position = Vector2(vp_size.x * 0.5 - 200, 10)
	if not active:
		_save_layout()

## Save button positions as the account-level touch layout.
func _save_layout() -> void:
	if PlayerConfig == null:
		return
	var data: Dictionary = {}
	for action in _buttons:
		var entry: Dictionary = _buttons[action]
		if str(action).begins_with("_"):
			continue  # edit-mode chrome is not part of the layout
		data[str(action)] = {"pos": [entry.pos.x, entry.pos.y]}
	PlayerConfig.set_account_setting(LAYOUT_SETTING, data)

func _load_layout() -> void:
	if PlayerConfig == null:
		return
	var data: Variant = PlayerConfig.get_account_setting(LAYOUT_SETTING, {})
	if not (data is Dictionary):
		return
	var saved: Dictionary = data
	for action in saved:
		if not _buttons.has(str(action)):
			continue
		var entry: Dictionary = _buttons[str(action)]
		var pos_val: Variant = saved[action].get("pos") if saved[action] is Dictionary else null
		if pos_val is Array and (pos_val as Array).size() == 2:
			entry.pos = Vector2(float(pos_val[0]), float(pos_val[1]))

func _reset_layout() -> void:
	for cfg in DEFAULT_BUTTONS:
		if _buttons.has(str(cfg.action)):
			_buttons[str(cfg.action)].pos = cfg.pos
	_apply_layout()
	_save_layout()

func _apply_layout() -> void:
	if not is_inside_tree():
		return
	var vp_size := get_viewport().get_visible_rect().size
	for action in _buttons:
		var entry: Dictionary = _buttons[action]
		var btn: Button = entry.button
		btn.size = entry.size
		var center: Vector2 = Vector2(entry.pos.x * vp_size.x, entry.pos.y * vp_size.y)
		btn.position = center - entry.size * 0.5
	_hint_base.position = _default_stick_spot() - _hint_base.size * 0.5
	_hint_base.visible = _enabled and visible and not _stick_visible and not _edit_mode

func _default_stick_spot() -> Vector2:
	var vp_size := get_viewport().get_visible_rect().size
	return Vector2(vp_size.x * 0.14, vp_size.y * 0.72)

## ---------------------------------------------------------------------------
## Raw input: joystick, camera look, edit drags
## ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _enabled or _panels_open:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_on_touch_start(event)
		else:
			_on_touch_end(event)
	elif event is InputEventScreenDrag:
		_on_touch_drag(event)

func _touch_over_control(pos: Vector2) -> bool:
	for action in _buttons:
		var btn: Button = _buttons[action].button
		if btn.visible and Rect2(btn.global_position, btn.size).has_point(pos):
			return true
	return false

func _dbg(msg: String) -> void:
	if _debug_touch:
		print("[vj-dbg] %s" % msg)

func _on_touch_start(event: InputEventScreenTouch) -> void:
	var vp_size := get_viewport().get_visible_rect().size
	_dbg("start idx=%d pos=%s edit=%s over_btn=%s" % [
		event.index, str(event.position), str(_edit_mode), str(_touch_over_control(event.position))])

	if _edit_mode:
		if _touch_over_control(event.position):
			var action := _action_at(event.position)
			if action != "":
				_edit_drag_action = action
				_edit_drag_offset = _buttons[action].button.global_position - event.position
				_dbg("edit drag armed: action=%s offset=%s" % [action, str(_edit_drag_offset)])
		return

	if _touch_over_control(event.position):
		return  # the button itself handles the press

	if event.position.x < vp_size.x * 0.5:
		# Left half: floating movement stick (COD dynamic stick).
		_joystick_touch_id = event.index
		_joystick_center = event.position
		_stick_offset = Vector2.ZERO
		_stick_visible = true
		_base.position = _joystick_center - _base.size * 0.5
		_thumb.position = _joystick_center - _thumb.size * 0.5
		_base.visible = true
		_thumb.visible = true
		_hint_base.visible = false
	else:
		# Right half empty area: camera look.
		_camera_touch_id = event.index
		_camera_last_pos = event.position

func _on_touch_drag(event: InputEventScreenDrag) -> void:
	_dbg("drag idx=%d pos=%s edit=%s drag_action='%s'" % [
		event.index, str(event.position), str(_edit_mode), _edit_drag_action])
	if _edit_mode and _edit_drag_action != "" and event.index == 0:
		var entry: Dictionary = _buttons[_edit_drag_action]
		var vp_size := get_viewport().get_visible_rect().size
		var new_pos: Vector2 = event.position + _edit_drag_offset + entry.size * 0.5
		entry.pos = Vector2(clampf(new_pos.x / vp_size.x, 0.04, 0.96),
				clampf(new_pos.y / vp_size.y, 0.04, 0.96))
		_apply_layout()
		return

	if event.index == _joystick_touch_id:
		var offset: Vector2 = event.position - _joystick_center
		if offset.length() > STICK_RADIUS:
			offset = offset.normalized() * STICK_RADIUS
		_stick_offset = offset
		_thumb.position = _joystick_center + offset - _thumb.size * 0.5
		joystick_moved.emit(offset, offset / STICK_RADIUS)
	elif event.index == _camera_touch_id:
		camera_look.emit(event.position - _camera_last_pos)
		_camera_last_pos = event.position
	else:
		_dbg("drag idx=%d matched nothing (joystick=%d camera=%d)" % [
			event.index, _joystick_touch_id, _camera_touch_id])

func _on_touch_end(event: InputEventScreenTouch) -> void:
	if _edit_mode:
		if _edit_drag_action != "":
			_edit_drag_action = ""
			_save_layout()
		return

	if event.index == _joystick_touch_id:
		_joystick_touch_id = -1
		_stick_offset = Vector2.ZERO
		_stick_visible = false
		_base.visible = false
		_thumb.visible = false
		joystick_moved.emit(Vector2.ZERO, Vector2.ZERO)
		joystick_released.emit()
		_cancel_auto_sprint()
		_hint_base.visible = _enabled and visible
	elif event.index == _camera_touch_id:
		_camera_touch_id = -1

func _action_at(pos: Vector2) -> String:
	for action in _buttons:
		var btn: Button = _buttons[action].button
		if btn.visible and Rect2(btn.global_position, btn.size).has_point(pos):
			return str(action)
	return ""

## ---------------------------------------------------------------------------
## Button press plumbing
## ---------------------------------------------------------------------------

func _on_button_down(action: String) -> void:
	if not _enabled or _edit_mode:
		return
	_press_action(action)

func _on_button_up(action: String) -> void:
	if not _enabled or _edit_mode:
		return
	_release_action(action)

## Inject the press into the global Input state (so state scripts polling
## Input.is_action_just_pressed react) and notify listeners.
func _press_action(action: String) -> void:
	_dbg("press '%s'" % action)
	if _debug_touch:
		for frame in get_stack():
			_dbg("  via %s:%s (%s)" % [str(frame.get("source", "?")), str(frame.get("line", "?")), str(frame.get("function", "?"))])
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	button_pressed.emit(action)
	if _buttons.has(action) and _buttons[action].repeat:
		_repeat_action = action
		_repeat_timer = 0.0

func _release_action(action: String) -> void:
	_dbg("release '%s'" % action)
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)
	button_released.emit(action)
	if _repeat_action == action:
		_repeat_action = ""

func _process(delta: float) -> void:
	# Hold-to-repeat attack.
	if _repeat_action != "":
		_repeat_timer += delta
		if _repeat_timer >= ATTACK_REPEAT_INTERVAL:
			_repeat_timer = 0.0
			_press_action(_repeat_action)

	# Auto-sprint: full stick for a beat engages sprint until the stick
	# eases off or releases. Routed through InputManager.player_input so
	# PlayerController.is_sprinting flips exactly like the keyboard key.
	if _joystick_touch_id >= 0:
		var mag := _stick_offset.length() / STICK_RADIUS
		if not _auto_sprint_on:
			if mag >= AUTO_SPRINT_ENGAGE:
				_full_stick_time += delta
				if _full_stick_time >= AUTO_SPRINT_DELAY:
					_auto_sprint_on = true
					sprint_override.emit(true)
			else:
				_full_stick_time = 0.0
		elif mag < AUTO_SPRINT_RELEASE:
			_cancel_auto_sprint()

func _cancel_auto_sprint() -> void:
	_full_stick_time = 0.0
	if _auto_sprint_on:
		_auto_sprint_on = false
		sprint_override.emit(false)

## ---------------------------------------------------------------------------
## Visibility / enable API (used by InputManager)
## ---------------------------------------------------------------------------

func show_joystick() -> void:
	visible = true
	_enabled = true
	layer = LAYER_ABOVE_HUD
	_set_replaced_hud_hidden(true)
	_apply_layout()

func hide_joystick() -> void:
	visible = false
	_hint_base.visible = false
	if _edit_mode:
		_set_edit_mode(false)
	layer = LAYER_IDLE
	_set_replaced_hud_hidden(false)
	_enabled = false
	_joystick_touch_id = -1
	_camera_touch_id = -1
	_cancel_auto_sprint()
	joystick_released.emit()

## S15 play-day feedback #3: while any panel/menu is open the touch
## HUD yields -- it drops below the panel stack (layer 18 < MenuManager
## 20) AND stops capturing input entirely (a hidden-but-enabled
## CanvasLayer still gets _input, so layering alone is not enough).
## The gate lives here so every panel opener gets it for free.
func set_panels_open(open_now: bool) -> void:
	_panels_open = open_now
	if _panels_open:
		layer = LAYER_IDLE
		_enabled = false
		_cancel_auto_sprint()
		_joystick_touch_id = -1
		_camera_touch_id = -1
		joystick_released.emit()
	elif visible:
		# Re-arm only if we are in a playable context (InputManager
		# re-runs its own gate on the next state change anyway).
		layer = LAYER_ABOVE_HUD
		_enabled = true

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		hide_joystick()
	else:
		show_joystick()

func is_enabled() -> bool:
	return _enabled

func is_edit_mode() -> bool:
	return _edit_mode

## Show/hide the desktop HUD widgets this touch HUD replaces. Duck-typed:
## nodes that don't exist in a scene are skipped silently.
func _set_replaced_hud_hidden(hidden_now: bool) -> void:
	var hud_root := get_tree().root if is_inside_tree() else null
	if hud_root == null:
		return
	for node_name in REPLACED_HUD_NODES:
		var node := hud_root.find_child(node_name, true, false)
		if node is CanvasItem:
			(node as CanvasItem).visible = not hidden_now
