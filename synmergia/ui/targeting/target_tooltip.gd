## TargetTooltip - Generic tooltip for any targeting system
class_name TargetTooltip
extends Control

var _targeting_system: TargetingSystem
var _interaction_layer: InteractionLayer

var _header_label: Label
var _info_label: Label
var _actions_container: HBoxContainer
var _status_label: Label
var _pin_btn: Button
var _close_btn: Button
var _action_buttons: Array = []
var _panel: PanelContainer
var _is_sticky: bool = false
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _action_provider: Callable

signal action_clicked(action_id: String, target_id: String)
signal tooltip_closed()
signal tooltip_opened()

func _ready() -> void:
	_setup_ui()
	hide()

func set_targeting_system(system: TargetingSystem) -> void:
	_targeting_system = system
	if _targeting_system:
		_targeting_system.target_acquired.connect(_on_target_acquired)
		_targeting_system.target_cleared.connect(_on_target_cleared)

func set_interaction_layer(layer: InteractionLayer) -> void:
	_interaction_layer = layer
	if _interaction_layer:
		_interaction_layer.tap.connect(_on_interaction_tap)

func set_action_provider(provider: Callable) -> void:
	_action_provider = provider

func _setup_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -300
	_panel.offset_top = 10
	_panel.offset_right = -10
	_panel.offset_bottom = 450
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
	
	_header_label = Label.new()
	_header_label.text = "Target"
	_header_label.add_theme_font_size_override("font_size", 18)
	_header_label.add_theme_color_override("font_color", Color(1, 1, 1))
	header.add_child(_header_label)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	_close_btn = Button.new()
	_close_btn.text = "✕"
	_close_btn.custom_minimum_size = Vector2(40, 40)
	_close_btn.pressed.connect(close_tooltip)
	header.add_child(_close_btn)
	
	_pin_btn = Button.new()
	_pin_btn.text = "📍"
	_pin_btn.custom_minimum_size = Vector2(40, 40)
	_pin_btn.pressed.connect(_toggle_sticky)
	header.add_child(_pin_btn)
	
	_info_label = Label.new()
	_info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_info_label)
	
	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	vbox.add_child(_status_label)
	
	var sep := Label.new()
	sep.custom_minimum_size.y = 8
	vbox.add_child(sep)
	
	_actions_container = HBoxContainer.new()
	_actions_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_actions_container)

func update_tooltip(target_info: Dictionary, actions: Array = []) -> void:
	if target_info.is_empty():
		if not _is_sticky:
			hide()
		return
	
	show()
	tooltip_opened.emit()
	
	_header_label.text = target_info.get("name", target_info.get("id", "Unknown"))
	var entity_type: int = target_info.get("type", TargetingSystem.EntityType.NONE)
	var type_str := TargetingSystem.entity_type_to_string(entity_type as TargetingSystem.EntityType)
	_info_label.text = type_str
	_status_label.text = _get_status_for_type(target_info)
	_update_action_buttons(actions)

func _update_action_buttons(actions: Array) -> void:
	for btn in _action_buttons:
		btn.queue_free()
	_action_buttons.clear()
	
	var button_size := Vector2(90, 50)
	if _interaction_layer:
		button_size = _interaction_layer.get_button_size()
	
	for action in actions:
		var btn := _create_action_button(action, button_size)
		_actions_container.add_child(btn)
		_action_buttons.append(btn)

func _create_action_button(action: Dictionary, size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = "%s %s" % [action.get("icon", "•"), action.get("name", "Action")]
	btn.custom_minimum_size = size
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.3, 0.4)
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
	
	var action_id: String = action.get("id", "")
	var target_id: String = ""
	if _targeting_system:
		var target := _targeting_system.get_current_target()
		if target:
			target_id = target.entity_id
	
	btn.pressed.connect(func(): action_clicked.emit(action_id, target_id))
	
	return btn

func _get_status_for_type(target_info: Dictionary) -> String:
	var entity_type: int = target_info.get("type", TargetingSystem.EntityType.NONE)
	
	match entity_type as TargetingSystem.EntityType:
		TargetingSystem.EntityType.PLAYER:
			return "● Online" if target_info.get("online", false) else "○ Offline"
		TargetingSystem.EntityType.ENEMY:
			return "⚔️ Hostile"
		TargetingSystem.EntityType.NPC:
			return "💬 Interactive"
		TargetingSystem.EntityType.LOOT:
			return "📦 Can loot"
		TargetingSystem.EntityType.TELEPORT:
			return "🌀 Teleport"
		TargetingSystem.EntityType.OBJECT:
			return "🔧 Interact"
		_:
			return ""

func _on_target_acquired(target) -> void:
	var target_info := {
		"id": target.entity_id,
		"type": target.entity_type,
		"name": target.entity_name,
		"position": target.position,
		"metadata": target.metadata
	}
	
	var actions := []
	if _action_provider.is_valid():
		actions = _action_provider.call(target)
	
	update_tooltip(target_info, actions)

func _on_target_cleared(previous_target) -> void:
	if not _is_sticky:
		hide()
		tooltip_closed.emit()

func _on_interaction_tap(position: Vector2) -> void:
	pass

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
	
	if event is InputEventScreenTouch and not event.pressed:
		_is_dragging = false

func close_tooltip() -> void:
	_is_sticky = false
	_pin_btn.text = "📍"
	hide()
	tooltip_closed.emit()

func open_sticky() -> void:
	_is_sticky = true
	_pin_btn.text = "📌"
	show()
