## ActionMenu - Context/right-click action menu for entities
## Uses UIStyles for consistent theming
## Supports both mouse (right-click) and touch (long-press)
extends Control
class_name ActionMenu
const Entity = preload("res://core/entities/entity.gd")

const UIStyles = preload("res://ui/components/ui_styles.gd")

const NPCData = preload("res://core/schemas/npc_data.gd")


## Menu items
var _menu_panel: PanelContainer
var _menu_items: VBoxContainer
var _target_id: String = ""
var _target_type: int = 0
var _npc_data: NPCData = null
var _item_buttons: Array = []

## Touch support
var _long_press_timer: Timer
var _touch_start_pos: Vector2 = Vector2.ZERO
var _is_touch_opened: bool = false
const LONG_PRESS_DURATION: float = 0.5

signal action_selected(action_id: String, target_id: String)
signal menu_closed()

func _ready() -> void:
	_setup_ui()
	_setup_touch()
	hide_menu()

func _setup_touch() -> void:
	_long_press_timer = Timer.new()
	_long_press_timer.wait_time = LONG_PRESS_DURATION
	_long_press_timer.one_shot = true
	_long_press_timer.timeout.connect(_on_long_press)
	add_child(_long_press_timer)

func _setup_ui() -> void:
	_menu_panel = PanelContainer.new()
	_menu_panel.custom_minimum_size = Vector2(180, 0)
	
	var style := UIStyles.create_panel_style(
			UIStyles.COLORS.background,
			UIStyles.COLORS.border_highlight,
			2,
			6
		)
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

## Show the action menu for an NPC, with NPC-specific action filtering.
func show_menu_for_npc(position: Vector2, target_id: String, npc_data: NPCData) -> void:
	show_menu(position, target_id, Entity.EntityType.NPC, npc_data)

func show_menu(position: Vector2, target_id: String, target_type: int, npc_data: NPCData = null) -> void:
	_target_id = target_id
	_target_type = target_type
	_npc_data = npc_data
	
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

func _filter_npc_actions(actions: Array, npc_data: NPCData) -> Array:
	var filtered := []
	for action in actions:
		var id: String = action.get("id", "")
		match id:
			"skill_academy":
				if _npc_has_offering_type(npc_data, "service", "skill_academy"):
					filtered.append(action)
			"blacksmith":
				if _npc_has_offering_type(npc_data, "service", "blacksmith"):
					filtered.append(action)
			"bank":
				if _npc_has_offering_type(npc_data, "bank", "") or _npc_has_offering_type(npc_data, "service", "bank"):
					filtered.append(action)
			"trade":
				if _npc_has_offering_type(npc_data, "vendor", ""):
					filtered.append(action)
			"quest":
				if _npc_has_offering_type(npc_data, "quest", ""):
					filtered.append(action)
			"talk":
				filtered.append(action)
			_:
				filtered.append(action)
	return filtered


func _npc_has_offering_type(npc_data: NPCData, offering_type: String, service_id: String) -> bool:
	if npc_data == null:
		return false
	if not npc_data.includes.is_empty():
		for inc: Dictionary in npc_data.includes:
			if inc.get("type", "") == "offering":
				var ref_id: String = inc.get("ref_id", "")
				if not ref_id.is_empty():
					var offering := _load_offering(ref_id)
					if offering and offering.type == offering_type:
						if service_id.is_empty() or offering.service_id == service_id:
							return true
		return false
	# Fallback: use old NPCType enum for NPCs without includes[]
	match offering_type:
		"service":
			if service_id == "blacksmith":
				return npc_data.npc_type == NPCData.NPCType.BLACKSMITH
			if service_id == "skill_academy":
				return npc_data.npc_type == NPCData.NPCType.SKILL_ACADEMY
	return false


func _load_offering(ref_id: String) -> Resource:
	if ref_id.is_empty():
		return null
	var path := "res://data/npc_offerings/%s.tres" % ref_id
	return load(path)

func _populate_menu() -> void:
	# Clear existing items
	for btn in _item_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_item_buttons.clear()
	
	# Get actions based on target type
	var actions := _get_actions_for_type(_target_type)
	
	# Filter NPC actions by offerings (or fall back to NPCType)
	if _target_type == Entity.EntityType.NPC and _npc_data != null:
		actions = _filter_npc_actions(actions, _npc_data)
	
	for action in actions:
		var btn := _create_menu_item(action)
		_menu_items.add_child(btn)
		_item_buttons.append(btn)

func _get_actions_for_type(target_type: int) -> Array:
	var actions := []
	
	match target_type:
		Entity.EntityType.PLAYER:
			actions = [
				{"id": "whisper", "text": "Whisper", "icon": "💬"},
				{"id": "invite_party", "text": "Invite to Party", "icon": "⚔️"},
				{"id": "invite_guild", "text": "Invite to Guild", "icon": "🏰"},
				{"id": "trade", "text": "Trade", "icon": "💱"},
				{"id": "add_friend", "text": "Add Friend", "icon": "👤"},
				{"id": "report", "text": "Report Player", "icon": "⚠️", "danger": true}
			]
		Entity.EntityType.NPC:
			actions = [
				{"id": "talk", "text": "Talk", "icon": "💬"},
				{"id": "trade", "text": "Trade", "icon": "💱"},
				{"id": "quest", "text": "Quests", "icon": "📜"},
				{"id": "bank", "text": "Bank", "icon": "🏦"},
				{"id": "skill_academy", "text": "Skill Academy", "icon": "📖"},
				{"id": "blacksmith", "text": "Blacksmith", "icon": "⚒️"},
			]
		Entity.EntityType.LOOT:
			actions = [
				{"id": "loot", "text": "Loot", "icon": "📦"},
				{"id": "pass", "text": "Pass", "icon": "➡️"}
			]
		Entity.EntityType.TELEPORT:
			actions = [
				{"id": "enter", "text": "Enter", "icon": "🚪"},
				{"id": "cancel", "text": "Cancel", "icon": "✕"}
			]
		Entity.EntityType.ENEMY:
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
		btn.add_theme_color_override("font_color", UIStyles.COLORS.error)
	
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
	hide_menu()
	menu_closed.emit()

func hide_menu() -> void:
	visible = false
	_target_id = ""
	_target_type = 0
	_is_touch_opened = false

func _input(event: InputEvent) -> void:
	# Mouse click to close
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_visible() and not _menu_panel.get_global_rect().has_point(event.position):
			hide_menu()
			menu_closed.emit()
	
	# Touch handling for long-press
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_start_pos = event.position
			_long_press_timer.start()
		else:
			_long_press_timer.stop()
			if _is_touch_opened:
				# Tap on menu item handled by button press
				pass
			_is_touch_opened = false

func _on_long_press() -> void:
	# Long press detected - show menu if we have a target
	if _target_id != "":
		_is_touch_opened = true
		show_menu(_touch_start_pos, _target_id, _target_type)
