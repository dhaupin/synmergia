## ActionMenu - Context/right-click action menu for entities
## Uses UIStyles for consistent theming
## Supports both mouse (right-click) and touch (long-press)
extends "res://ui/components/ui_panel.gd"
class_name ActionMenu

const NPCData = preload("res://core/schemas/npc_data.gd")
# Entity is not an autoload (class_name only). ActionMenu uses
# Entity.EntityType.X for menu item classification, which requires
# Entity's class_name registered at parse time. Preload it here.
const Entity = preload("res://core/entities/entity.gd")


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
	super._ready()
	_setup_touch()
	_setup_ui()
	hide()
	visible = false


## Build the base "Panel" node. UIPanel's default _setup_panel() is a
## no-op stub -- subclasses must create the named Panel themselves
## (see dialog_ui.gd). Without this, get_panel() returned null, so
## _setup_ui() bailed and the menu rendered empty (no Talk/Trade items
## for NPC targets).
func _setup_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(200, 80)
	var style := UIStyles.create_panel_style()
	panel.add_theme_stylebox_override("panel", style)
	panel.name = "Panel"
	panel.focus_mode = Control.FOCUS_ALL
	add_child(panel)


func _setup_touch() -> void:
	_long_press_timer = Timer.new()
	_long_press_timer.wait_time = LONG_PRESS_DURATION
	_long_press_timer.one_shot = true
	_long_press_timer.timeout.connect(_on_long_press)
	add_child(_long_press_timer)

func _setup_ui() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main: VBoxContainer = add_content_to_panel(panel)

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
	main.add_child(_menu_panel)

	_menu_items = VBoxContainer.new()
	_menu_items.name = "MenuItems"
	_menu_panel.add_child(_menu_items)

## Show the action menu for an NPC, with NPC-specific action filtering.
func show_menu_for_npc(position: Vector2, target_id: String, npc_data: NPCData) -> void:
	show_menu(position, target_id, Entity.EntityType.NPC, npc_data)

func open_for_npc(target_id: String, npc_data: Dictionary = {}) -> void:
	# Open menu at screen center for now
	var screen_pos := get_viewport_rect().size / 2
	show_menu(screen_pos, target_id, Entity.EntityType.NPC, null)

func show_menu(position: Vector2, target_id: String, target_type: int, npc_data: NPCData = null) -> void:
	_target_id = target_id
	_target_type = target_type
	_npc_data = npc_data

	# Lazy build: _menu_panel is created in _ready(), which only runs once
	# the node enters the tree. Guard so a programmatic open on a node not
	# yet in the tree does not crash on get_minimum_size() below.
	if _menu_panel == null:
		_setup_ui()
	if _menu_panel == null:
		push_warning("ActionMenu: panel not built, cannot open menu")
		return

	_populate_menu()

	# Position menu near click, but keep on screen
	var viewport_size := get_viewport_rect().size
	var menu_size := _menu_panel.get_minimum_size()

	_menu_panel.global_position = position
	if _menu_panel.global_position.x + menu_size.x > viewport_size.x:
		_menu_panel.global_position.x = viewport_size.x - menu_size.x - 10
	if _menu_panel.global_position.y + menu_size.y > viewport_size.y:
		_menu_panel.global_position.y = viewport_size.y - menu_size.y - 10

	open("")

func _on_open() -> void:
	pass

func _on_close() -> void:
	_target_id = ""
	_target_type = 0
	_is_touch_opened = false

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
				if _npc_has_offering_type(npc_data, "dialogue", ""):
					filtered.append(action)
			_:
				filtered.append(action)
	return filtered


func _npc_has_offering_type(npc_data: NPCData, offering_type: String, service_id: String) -> bool:
	if npc_data == null:
		return false
	if npc_data.includes.is_empty():
		return false
	# Inline includes (the data/npc/*.tres shape: {type: "dialogue",
	# "vendor", "quest", "bank"}) resolve through the NPCData helper,
	# which understands both inline and ref-based entries. Previously
	# this filter only recognized ref-based "offering" includes, so the
	# world's actual NPCs filtered down to an empty menu.
	if service_id.is_empty():
		return npc_data.has_offering(offering_type)
	# Service-id match: ref-based offerings carry service_id on the
	# resource; inline "service" includes carry it on the dictionary.
	for inc: Dictionary in npc_data.includes:
		if inc.get("type", "") == "offering":
			var ref_id: String = inc.get("ref_id", "")
			if not ref_id.is_empty():
				var offering := _load_offering(ref_id)
				if offering and offering.type == offering_type \
						and str(offering.service_id) == service_id:
					return true
		elif inc.get("type", "") == "service" and offering_type == "service":
			if str(inc.get("service_id", "")) == service_id:
				return true
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
				{"id": "whisper", "text": "Whisper", "icon": ""},
					{"id": "follow", "text": "Follow", "icon": ""},
				{"id": "invite_party", "text": "Invite to Party", "icon": ""},
				{"id": "invite_guild", "text": "Invite to Guild", "icon": ""},
				{"id": "trade", "text": "Trade", "icon": ""},
				{"id": "add_friend", "text": "Add Friend", "icon": ""},
					{"id": "view_character", "text": "View Character", "icon": ""},
				{"id": "report", "text": "Report Player", "icon": "", "danger": true}
			]
		Entity.EntityType.NPC:
			actions = [
				{"id": "talk", "text": "Talk", "icon": ""},
				{"id": "trade", "text": "Trade", "icon": ""},
				{"id": "quest", "text": "Quests", "icon": ""},
				{"id": "bank", "text": "Bank", "icon": ""},
				{"id": "skill_academy", "text": "Skill Academy", "icon": ""},
				{"id": "blacksmith", "text": "Blacksmith", "icon": ""},
			]
		Entity.EntityType.LOOT:
			actions = [
				{"id": "loot", "text": "Loot", "icon": ""},
				{"id": "pass", "text": "Pass", "icon": "->"}
			]
		Entity.EntityType.TELEPORT:
			actions = [
				{"id": "enter", "text": "Enter", "icon": ""},
				{"id": "cancel", "text": "Cancel", "icon": ""}
			]
		Entity.EntityType.ENEMY:
			actions = [
				{"id": "attack", "text": "Attack", "icon": ""},
				{"id": "spell", "text": "Cast Spell", "icon": ""}
			]

	return actions

func _create_menu_item(action: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size.y = 36

	var text := "%s %s" % [action.get("icon", "*"), action.get("text", "?")]
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
	close()
	menu_closed.emit()

func _input(event: InputEvent) -> void:
	# Mouse click to close
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_visible() and not _menu_panel.get_global_rect().has_point(event.position):
			close()
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
