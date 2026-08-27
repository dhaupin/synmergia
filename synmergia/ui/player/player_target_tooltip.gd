## PlayerTargetTooltip - Mobile-friendly player interaction tooltip
class_name PlayerTargetTooltip
extends Control

var _panel: PanelContainer
var _name_label: Label
var _info_label: Label
var _actions_container: HBoxContainer
var _status_label: Label
var _pin_btn: Button
var _target_system: PlayerTargetSystem
var _source_id: String = ""
var _action_buttons: Array = []
var _is_sticky: bool = false
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	_target_system = PlayerTargetSystem
	if _target_system:
		_target_system.target_changed.connect(_on_target_changed)
		_target_system.action_executed.connect(_on_action_executed)
	_setup_ui()
	hide()

func _setup_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -280
	_panel.offset_top = 10
	_panel.offset_right = -10
	_panel.offset_bottom = 400
	_panel.z_index = 1000
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_top = 12
	style.content_margin_right = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)
	
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(vbox)
	
	var header := HBoxContainer.new()
	vbox.add_child(header)
	
	_name_label = Label.new()
	_name_label.text = "Target"
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	header.add_child(_name_label)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	_pin_btn = Button.new()
	_pin_btn.text = "📍"
	_pin_btn.custom_minimum_size = Vector2(40, 40)
	_pin_btn.pressed.connect(_toggle_sticky)
	header.add_child(_pin_btn)
	
	_info_label = Label.new()
	_info_label.text = "Level 1 Player"
	_info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(_info_label)
	
	_status_label = Label.new()
	_status_label.text = "● Online"
	_status_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	vbox.add_child(_status_label)
	
	var sep := Label.new()
	sep.custom_minimum_size.y = 8
	vbox.add_child(sep)
	
	_actions_container = HBoxContainer.new()
	_actions_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_actions_container)

func update_tooltip(source_id: String) -> void:
	_source_id = source_id
	if not _target_system:
		return
	
	var target := _target_system.get_current_target()
	if target.id == "":
		if not _is_sticky:
			hide()
		return
	
	show()
	_name_label.text = target.name
	
	var info := _target_system.get_target_player_info()
	
	if target.type == PlayerTargetSystem.TargetType.PLAYER:
		var level: int = info.get("level", 0)
		_info_label.text = "Level %d Player" % level
		
		if info.get("online", false):
			_status_label.text = "● Online"
			_status_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
		else:
			_status_label.text = "○ Offline"
			_status_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	
	_update_action_buttons()

func _update_action_buttons() -> void:
	for btn in _action_buttons:
		btn.queue_free()
	_action_buttons.clear()
	
	if not _target_system:
		return
	
	var actions: Array = _target_system.get_available_actions(_source_id)
	
	for action in actions:
		var btn := _create_action_button(action)
		_actions_container.add_child(btn)
		_action_buttons.append(btn)

func _create_action_button(action: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = "%s %s" % [action.icon, action.name]
	btn.custom_minimum_size = Vector2(90, 50)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	
	var style := StyleBoxFlat.new()
	match action.category:
		PlayerTargetSystem.ActionCategory.SOCIAL:
			style.bg_color = Color(0.2, 0.3, 0.4)
		PlayerTargetSystem.ActionCategory.VIP_SOCIAL:
			style.bg_color = Color(0.3, 0.25, 0.35)
		PlayerTargetSystem.ActionCategory.MODERATION:
			style.bg_color = Color(0.4, 0.3, 0.2)
		PlayerTargetSystem.ActionCategory.ADMIN:
			style.bg_color = Color(0.4, 0.2, 0.2)
		_:
			style.bg_color = Color(0.2, 0.2, 0.25)
	
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	
	btn.add_theme_stylebox_override("normal", style)
	
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = style.bg_color.lightened(0.3)
	pressed_style.corner_radius_top_left = 6
	pressed_style.corner_radius_top_right = 6
	pressed_style.corner_radius_bottom_left = 6
	pressed_style.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("pressed", pressed_style)
	
	var action_id: String = action.id
	btn.pressed.connect(func(): _on_action_pressed(action_id))
	
	return btn

func _on_action_pressed(action_id: String) -> void:
	if not _target_system:
		return
	
	var result: Dictionary = _target_system.execute_action(_source_id, action_id)
	
	if result.success:
		_modulate_panel(Color(0.3, 0.5, 0.3))
	else:
		_modulate_panel(Color(0.5, 0.2, 0.2))
		_show_notification(result.get("message", "Action failed"))

func _modulate_panel(color: Color) -> void:
	var tween := create_tween()
	tween.tween_property(_panel, "modulate", color, 0.1)
	tween.tween_property(_panel, "modulate", Color.WHITE, 0.3)

func _show_notification(message: String) -> void:
	var notification := Label.new()
	notification.text = message
	notification.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
	notification.z_index = 1001
	notification.global_position = _panel.global_position + Vector2(_panel.size.x / 2, _panel.size.y + 10)
	get_tree().root.add_child(notification)
	
	var tween := create_tween()
	tween.tween_property(notification, "modulate:a", 0.0, 1.5)
	tween.tween_callback(notification.queue_free)

func _toggle_sticky() -> void:
	_is_sticky = not _is_sticky
	_pin_btn.text = "📌" if _is_sticky else "📍"
	
	var tween := create_tween()
	if _is_sticky:
		tween.tween_property(_panel, "modulate", Color(1, 1, 0.8), 0.2)
	else:
		tween.tween_property(_panel, "modulate", Color.WHITE, 0.2)

func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		if not _is_dragging:
			_is_dragging = true
			_drag_offset = event.position - _panel.global_position
		_panel.global_position = event.position - _drag_offset
	
	if event is InputEventScreenTouch:
		if not event.pressed:
			_is_dragging = false

func _on_target_changed(type: int, target_id: String, target_name: String) -> void:
	if target_id != "":
		update_tooltip(_source_id)
	elif not _is_sticky:
		hide()

func _on_action_executed(action_id: String, source_id: String, target_id: String, result: Dictionary) -> void:
	_update_action_buttons()

func set_source_player(player_id: String) -> void:
	_source_id = player_id
	if _target_system:
		var target := _target_system.get_current_target()
		if target.id != "":
			update_tooltip(player_id)

func open_sticky() -> void:
	_is_sticky = true
	_pin_btn.text = "📌"
	show()

func close_tooltip() -> void:
	_is_sticky = false
	_pin_btn.text = "📍"
	hide()
