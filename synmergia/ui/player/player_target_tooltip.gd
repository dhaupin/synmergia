## PlayerTargetTooltip - In-game tooltip for player interactions
class_name PlayerTargetTooltip
extends Control

var _panel: PanelContainer
var _name_label: Label
var _info_label: Label
var _actions_container: HBoxContainer
var _status_label: Label

var _target_system: PlayerTargetSystem
var _source_id: String = ""
var _action_buttons: Array = []

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
	
	add_child(_panel)
	
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(vbox)
	
	# Name
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
	
	# Info
	_info_label = Label.new()
	_info_label.text = "Level 1 Player"
	_info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(_info_label)
	
	# Status
	_status_label = Label.new()
	_status_label.text = "● Online"
	_status_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	vbox.add_child(_status_label)
	
	# Separator
	var sep := Label.new()
	sep.custom_minimum_size.y = 8
	vbox.add_child(sep)
	
	# Actions
	_actions_container = HBoxContainer.new()
	_actions_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_actions_container)

func update_tooltip(source_id: String) -> void:
	_source_id = source_id
	
	if not _target_system:
		return
	
	var target := _target_system.get_current_target()
	if target.id == "":
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
		
		if info.get("restricted", false):
			_status_label.text += " [color=#ff6666]MUTED[/color]"
	
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
	btn.custom_minimum_size.x = 100
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
	
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	
	btn.add_theme_stylebox_override("normal", style)
	
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = style.bg_color.lightened(0.2)
	hover_style.corner_radius_top_left = 4
	hover_style.corner_radius_top_right = 4
	hover_style.corner_radius_bottom_left = 4
	hover_style.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("hover", hover_style)
	
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
	
	var pos := _panel.global_position + Vector2(_panel.size.x / 2, _panel.size.y + 10)
	notification.global_position = pos
	
	get_tree().root.add_child(notification)
	
	var tween := create_tween()
	tween.tween_property(notification, "modulate:a", 0.0, 1.5)
	tween.tween_callback(notification.queue_free)

func _on_target_changed(type: int, target_id: String, target_name: String) -> void:
	if target_id != "":
		update_tooltip(_source_id)
	else:
		hide()

func _on_action_executed(action_id: String, source_id: String, target_id: String, result: Dictionary) -> void:
	_update_action_buttons()

func set_source_player(player_id: String) -> void:
	_source_id = player_id
	if _target_system:
		var target := _target_system.get_current_target()
		if target.id != "":
			update_tooltip(player_id)
