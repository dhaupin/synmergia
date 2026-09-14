## VirtualJoystick - Touch-native virtual joystick and action buttons
## Replaces web-based touch UI with Godot-native CanvasLayer implementation
extends CanvasLayer
class_name VirtualJoystick

## Signals
signal joystick_moved(offset: Vector2, normalized: Vector2)
signal joystick_released()
signal button_pressed(action: String)
signal button_released(action: String)

## Exported properties
@export var joystick_max_radius: float = 60.0
@export var joystick_zone: Rect2 = Rect2(0.0, 0.3, 0.35, 0.7)
@export var camera_zone: Rect2 = Rect2(0.65, 0.3, 0.35, 0.7)
@export var button_configs: Array[Dictionary] = [
	{"action": "jump", "text": "JUMP", "anchor": Vector2(1.0, 1.0), "offset": Vector2(-100, -100)},
	{"action": "interact", "text": "ACT", "anchor": Vector2(1.0, 1.0), "offset": Vector2(-100, -210)},
	{"action": "attack", "text": "ATK", "anchor": Vector2(1.0, 1.0), "offset": Vector2(-100, -320)}
]

## Internal state
var _joystick_active: bool = false
var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_touch_id: int = -1
var _joystick_base: TextureRect = null
var _joystick_thumb: TextureRect = null
var _action_buttons: Array[TextureButton] = []
var _enabled: bool = true
var _high_contrast: bool = false
var _reduce_motion: bool = false

func _ready() -> void:
	layer = 5
	_setup_high_contrast()
	_reduce_motion = UIStyles.is_reduce_motion_enabled()
	_create_joystick_visuals()
	_create_action_buttons()
	hide_joystick()
	set_process_input(true)

func _setup_high_contrast() -> void:
	if PlayerConfig:
		_high_contrast = PlayerConfig.get_account_setting("high_contrast", false)

func _create_joystick_visuals() -> void:
	var colors = UIStyles.get_effective_colors(_high_contrast)
	
	_joystick_base = TextureRect.new()
	_joystick_base.custom_minimum_size = Vector2(120, 120)
	_joystick_base.texture = _create_circle_texture(60, colors.background_dark)
	_joystick_base.add_theme_stylebox_override("normal", UIStyles.create_panel_style(colors.background_dark, colors.border, 2, 60))
	_joystick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick_base.visible = false
	_joystick_base.accessible_name = "Virtual Joystick Base"
	add_child(_joystick_base)
	
	_joystick_thumb = TextureRect.new()
	_joystick_thumb.custom_minimum_size = Vector2(60, 60)
	_joystick_thumb.texture = _create_circle_texture(30, colors.accent)
	_joystick_thumb.add_theme_stylebox_override("normal", UIStyles.create_panel_style(colors.accent, colors.border_highlight, 2, 30))
	_joystick_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick_thumb.visible = false
	_joystick_thumb.accessible_name = "Virtual Joystick Thumb"
	add_child(_joystick_thumb)

func _create_circle_texture(radius: int, color: Color) -> ImageTexture:
	var img = Image.create(radius * 2, radius * 2, false, Image.FORMAT_RGBA8)
	img.lock()
	var center = Vector2(radius, radius)
	for x in range(radius * 2):
		for y in range(radius * 2):
			var pos = Vector2(x, y)
			if pos.distance_to(center) <= radius:
				img.set_pixel(x, y, color)
	img.unlock()
	var tex = ImageTexture.create_from_image(img)
	return tex

func _create_action_buttons() -> void:
	var colors = UIStyles.get_effective_colors(_high_contrast)
	var viewport_size = get_viewport().get_visible_rect().size
	
	for i, cfg in button_configs:
		var btn = TextureButton.new()
		btn.custom_minimum_size = Vector2(80, 80)
		btn.text = cfg.text
		btn.focus_mode = Control.FOCUS_ALL
		btn.accessible_name = cfg.action.capitalize() + " Button"
		btn.tooltip_text = cfg.text
		
		var normal_style = UIStyles.create_panel_style(colors.background, colors.border, 2, 12)
		var hover_style = UIStyles.create_panel_style(colors.background_dark, colors.border_highlight, 2, 12)
		var pressed_style = UIStyles.create_panel_style(colors.accent, colors.border_highlight, 2, 12)
		var focus_style = UIStyles.create_focus_style(12, _high_contrast)
		
		btn.add_theme_stylebox_override("normal", normal_style)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("pressed", pressed_style)
		btn.add_theme_stylebox_override("focus", focus_style)
		btn.add_theme_color_override("font_color", colors.text_primary)
		btn.add_theme_font_size_override("font_size", 14)
		
		btn.pressed.connect(_on_button_pressed.bind(cfg.action))
		btn.button_up.connect(_on_button_released.bind(cfg.action))
		
		var anchor = cfg.anchor
		var offset = cfg.offset
		btn.anchor_right = anchor.x
		btn.anchor_bottom = anchor.y
		btn.offset_right = offset.x
		btn.offset_bottom = offset.y
		btn.offset_left = offset.x + 80
		btn.offset_top = offset.y + 80
		
		btn.visible = false
		_action_buttons.append(btn)
		add_child(btn)

func _on_button_pressed(action: String) -> void:
	if not _enabled:
		return
	button_pressed.emit(action)

func _on_button_released(action: String) -> void:
	if not _enabled:
		return
	button_released.emit(action)

func _process_touch(event: InputEvent) -> void:
	if not _enabled:
		return
	
	if event is InputEventScreenTouch:
		_handle_touch_start(event)
	elif event is InputEventScreenDrag:
		_handle_touch_drag(event)

func _handle_touch_start(event: InputEventScreenTouch) -> void:
	if not event.pressed:
		return
	
	var pos = event.position
	var screen_size = get_viewport().get_visible_rect().size
	var normalized = pos / screen_size
	
	if joystick_zone.has_point(normalized):
		_joystick_active = true
		_joystick_center = pos
		_joystick_touch_id = event.index
		_show_joystick_at(pos)
	elif camera_zone.has_point(normalized):
		pass

func _handle_touch_drag(event: InputEventScreenDrag) -> void:
	if event.index != _joystick_touch_id or not _joystick_active:
		return
	
	var pos = event.position
	var offset = pos - _joystick_center
	var dist = offset.length()
	
	if dist > joystick_max_radius:
		offset = offset.normalized() * joystick_max_radius
	
	_update_joystick_visual(offset)
	joystick_moved.emit(offset, offset / joystick_max_radius)

func _process(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		_handle_touch_end(event)

func _handle_touch_end(event: InputEventScreenTouch) -> void:
	if event.index == _joystick_touch_id:
		_joystick_active = false
		_joystick_touch_id = -1
		_hide_joystick()
		joystick_released.emit()

func _show_joystick_at(pos: Vector2) -> void:
	_joystick_base.global_position = pos - Vector2(60, 60)
	_joystick_thumb.global_position = pos - Vector2(30, 30)
	_joystick_base.visible = true
	_joystick_thumb.visible = true

func _update_joystick_visual(offset: Vector2) -> void:
	_joystick_thumb.global_position = _joystick_center + offset - Vector2(30, 30)

func _hide_joystick() -> void:
	_joystick_base.visible = false
	_joystick_thumb.visible = false

func show_joystick() -> void:
	var screen_size = get_viewport().get_visible_rect().size
	var default_pos = Vector2(screen_size.x * 0.175, screen_size.y * 0.65)
	_show_joystick_at(default_pos)
	for btn in _action_buttons:
		btn.visible = true

func hide_joystick() -> void:
	_hide_joystick()
	for btn in _action_buttons:
		btn.visible = false

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		hide_joystick()
		_joystick_active = false
		_joystick_touch_id = -1

func is_enabled() -> bool:
	return _enabled

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESOLUTION_CHANGED:
		_setup_high_contrast()
		_update_visuals_for_accessibility()

func _update_visuals_for_accessibility() -> void:
	var colors = UIStyles.get_effective_colors(_high_contrast)
	
	if _joystick_base:
		_joystick_base.add_theme_stylebox_override("normal", UIStyles.create_panel_style(colors.background_dark, colors.border, 2, 60))
	if _joystick_thumb:
		_joystick_thumb.add_theme_stylebox_override("normal", UIStyles.create_panel_style(colors.accent, colors.border_highlight, 2, 30))
	
	for btn in _action_buttons:
		btn.add_theme_stylebox_override("normal", UIStyles.create_panel_style(colors.background, colors.border, 2, 12))
		btn.add_theme_stylebox_override("hover", UIStyles.create_panel_style(colors.background_dark, colors.border_highlight, 2, 12))
		btn.add_theme_stylebox_override("pressed", UIStyles.create_panel_style(colors.accent, colors.border_highlight, 2, 12))
		btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style(12, _high_contrast))
		btn.add_theme_color_override("font_color", colors.text_primary)