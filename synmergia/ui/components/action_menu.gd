## ActionMenu - Context/right-click action menu for entities
class_name ActionMenu
extends Control

## Menu items
var _menu_panel: PanelContainer
var _menu_items: VBoxContainer
var _target_id: String = ""
var _target_type: int = 0
var _item_buttons: Array = []

signal action_selected(action_id: String, target_id: String)
signal menu_closed()

func _ready() -> void:
	_setup_ui()
	hide()

func _setup_ui() -> void:
	_menu_panel = PanelContainer.new()
	_menu_panel.custom_minimum_size = Vector2(180, 0)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.18, 0.98)
	style.border_color = Color(0.4, 0.35, 0.3)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_menu_panel.add_theme_stylebox_override("panel", style)
	_menu_panel.z_index = 2000
	add_child(_menu_panel)
	
	_menu_items = VBoxContainer.new()
	_menu_items.name = "MenuItems"
	_menu_panel.add_child(_menu_items)

func show_menu(position: Vector2, target_id: String, target_type: int) -> void:
	_target_id = target_id
	_target_type = target_type
	
	_populate_menu()
	
	# Position menu near click, but keep on screen
	var viewport_size := get_viewport_rect().size
	var menu_size := _menu_panel.get_minimum_size()
	
	_menu_panel.global_position = position
	if _menu_panel.global_position.x + menu_size.x > viewport_size.x:
		_menu_panel.global_position.x = viewport_size.x - menu_size.x - 10
	if _menu_panel.global_position.y + menu_size.y > viewport_size.y:
		_menu_panel.global_position.y = viewport_size.y - menu_size.y - 10
	
	show()

func _populate_menu() -> void:
	# Clear existing items
	for btn in _item_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_item_buttons.clear()
	
	# Get actions based on target type
	var actions := _get_actions_for_type(_target_type)
	
	for action in actions:
		var btn := _create_menu_item(action)
		_menu_items.add_child(btn)
		_item_buttons.append(btn)

func _get_actions_for_type(target_type: int) -> Array:
	var actions := []
	
	match target_type:
		1:  # Entity.EntityType.PLAYER
			actions = [
				{"id": "whisper", "text": "Whisper", "icon": "💬"},
				{"id": "invite_party", "text": "Invite to Party", "icon": "⚔️"},
				{"id": "invite_guild", "text": "Invite to Guild", "icon": "🏰"},
				{"id": "trade", "text": "Trade", "icon": "💱"},
				{"id": "add_friend", "text": "Add Friend", "icon": "👤"},
				{"id": "report", "text": "Report Player", "icon": "⚠️", "danger": true}
			]
		2:  # Entity.EntityType.NPC
			actions = [
				{"id": "talk", "text": "Talk", "icon": "💬"},
				{"id": "trade", "text": "Trade", "icon": "💱"},
				{"id": "quest", "text": "Quests", "icon": "📜"},
				{"id": "bank", "text": "Bank", "icon": "🏦"}
			]
		3:  # Entity.EntityType.LOOT
			actions = [
				{"id": "loot", "text": "Loot", "icon": "📦"},
				{"id": "pass", "text": "Pass", "icon": "➡️"}
			]
		4:  # Entity.EntityType.TELEPORT
			actions = [
				{"id": "enter", "text": "Enter", "icon": "🚪"},
				{"id": "cancel", "text": "Cancel", "icon": "✕"}
			]
		5:  # Entity.EntityType.ENEMY
			actions = [
				{"id": "attack", "text": "Attack", "icon": "⚔️"},
				{"id": "spell", "text": "Cast Spell", "icon": "✨"}
			]
	
	return actions

func _create_menu_item(action: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size.y = 36
	
	var text := "%s %s" % [action.get("icon", "•"), action.get("text", "?")]
	btn.text = text
	
	# Color for dangerous actions
	if action.get("danger", false):
		btn.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.12, 0.18, 0)
	normal_style.border_color = Color(0.12, 0.12, 0.18, 0)
	btn.add_theme_stylebox_override("normal", normal_style)
	
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.2, 0.2, 0.3, 0.9)
	hover_style.border_color = Color(0.4, 0.35, 0.3)
	hover_style.border_width_bottom = 1
	btn.add_theme_stylebox_override("hover", hover_style)
	
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.15, 0.15, 0.22, 0.9)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	
	btn.pressed.connect(func(): _on_action_selected(action.get("id", "")))
	
	return btn

func _on_action_selected(action_id: String) -> void:
	action_selected.emit(action_id, _target_id)
	hide()
	menu_closed.emit()

func hide() -> void:
	super.hide()
	_target_id = ""
	_target_type = 0

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_visible() and not _menu_panel.get_global_rect().has_point(event.position):
			hide()
			menu_closed.emit()
