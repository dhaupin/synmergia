## TooltipManager - Unified tooltip system
## Item tooltips, ability tooltips, NPC info tooltips
class_name TooltipManager
extends Control

## Tooltip types
enum TooltipType { ITEM, ABILITY, NPC, QUEST, PLAYER }

## Singleton
static var instance: TooltipManager

## Current tooltip
var _current_type: TooltipType = TooltipType.ITEM
var _data: Dictionary = {}
var _owner: Control = null

## Components
var _panel: PanelContainer
var _content: VBoxContainer

## Positioning
var _offset: Vector2 = Vector2(10, 10)
var _follow_mouse: bool = true


func _ready() -> void:
	instance = self
	_setup_ui()
	hide()


func _setup_ui() -> void:
	name = "TooltipManager"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.name = "TooltipPanel"
	_panel.custom_minimum_size = Vector2(250, 100)
	_panel.z_index = 1000
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.95)
	if UIStyles:
		style.border_color = UIStyles.COLORS.accent_gold
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_panel.add_theme_stylebox_override("panel", style)

	_content = VBoxContainer.new()
	_content.name = "Content"
	_panel.add_child(_content)


func _process(_delta: float) -> void:
	if visible and _follow_mouse:
		_update_position()


func _update_position() -> void:
	if not _panel:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var screen_size := get_viewport().get_visible_rect().size
	var pos := mouse_pos + _offset

	# Keep on screen
	if pos.x + _panel.custom_minimum_size.x > screen_size.x:
		pos.x = mouse_pos.x - _panel.custom_minimum_size.x - _offset.x
	if pos.y + _panel.custom_minimum_size.y > screen_size.y:
		pos.y = mouse_pos.y - _panel.custom_minimum_size.y - _offset.y

	_panel.global_position = pos


## ============================================================================
## PUBLIC API
## ============================================================================

static func get_instance() -> TooltipManager:
	return instance


func show_item(item_data: Dictionary, at_owner: Control = null) -> void:
	_current_type = TooltipType.ITEM
	_data = item_data
	_owner = at_owner
	_populate_item_tooltip()
	_update_size()
	show()
	_update_position()


func show_ability(ability_data: Dictionary, at_owner: Control = null) -> void:
	_current_type = TooltipType.ABILITY
	_data = ability_data
	_owner = at_owner
	_populate_ability_tooltip()
	_update_size()
	show()
	_update_position()


func show_npc(npc_data: Dictionary, at_owner: Control = null) -> void:
	_current_type = TooltipType.NPC
	_data = npc_data
	_owner = at_owner
	_populate_npc_tooltip()
	_update_size()
	show()
	_update_position()


func show_player(player_data: Dictionary, at_owner: Control = null) -> void:
	_current_type = TooltipType.PLAYER
	_data = player_data
	_owner = at_owner
	_populate_player_tooltip()
	_update_size()
	show()
	_update_position()


func show_quest(quest_data: Dictionary, at_owner: Control = null) -> void:
	_current_type = TooltipType.QUEST
	_data = quest_data
	_owner = at_owner
	_populate_quest_tooltip()
	_update_size()
	show()
	_update_position()


func hide_tooltip() -> void:
	hide()
	_data = {}
	_owner = null


func is_visible_for(p_owner: Control) -> bool:
	return visible and _owner == p_owner


## ============================================================================
## TOOLTIP CONTENT
## ============================================================================

func _clear_content() -> void:
	if not _content:
		return
	for child in _content.get_children():
		child.queue_free()


func _add_title(text: String, color: Color = Color(1, 1, 1)) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	if _content:
		_content.add_child(label)


func _add_line(text: String, color: Color = Color(0.7, 0.7, 0.7)) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	if _content:
		_content.add_child(label)


func _add_spacer(height: int = 5) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	if _content:
		_content.add_child(spacer)


func _add_divider() -> void:
	var sep := HSeparator.new()
	if _content:
		_content.add_child(sep)


func _populate_item_tooltip() -> void:
	_clear_content()

	var item_name: String = _data.get("name", "Unknown Item")
	var rarity: String = _data.get("rarity", "common")

	var rarity_color: Color = Color(0.6, 0.6, 0.6)
	match rarity.to_lower():
		"common": rarity_color = Color(0.6, 0.6, 0.6)
		"uncommon": rarity_color = Color(0.2, 0.9, 0.2)
		"rare": rarity_color = Color(0.2, 0.6, 1.0)
		"epic": rarity_color = Color(0.7, 0.3, 1.0)
		"legendary": rarity_color = Color(1.0, 0.6, 0.1)

	_add_title(item_name, rarity_color)

	var item_type: String = _data.get("type", "Item")
	_add_line(item_type, Color(0.7, 0.7, 0.7))

	_add_spacer()

	# Stats
	var stats: Array = _data.get("stats", [])
	for stat in stats:
		var stat_text := "  %s: +%d" % [stat.get("name", ""), stat.get("value", 0)]
		_add_line(stat_text, Color(0.4, 0.9, 0.4))

	_add_spacer()

	# Description
	var desc: String = _data.get("description", "")
	if not desc.is_empty():
		_add_line(desc, Color(0.7, 0.7, 0.7))

	_add_spacer()

	# Bind status
	if _data.get("soulbound", false):
		_add_line("Soulbound", Color(1, 0.7, 0.2))
	elif _data.get("bind_on_pickup", false):
		_add_line("Binds on pickup", Color(1, 0.7, 0.2))

	# Stack info
	if _data.get("stack_size", 1) > 1:
		_add_line("Stack: %d" % _data.get("stack_size", 1), Color(0.7, 0.7, 0.7))


func _populate_ability_tooltip() -> void:
	_clear_content()

	var ability_name: String = _data.get("name", "Unknown Ability")
	var gold: Color = Color(1, 0.85, 0.4)
	_add_title(ability_name, gold)

	var ability_type: String = _data.get("type", "Ability")
	_add_line(ability_type, Color(0.7, 0.7, 0.7))

	_add_spacer()

	# Cost
	var mana_cost: int = _data.get("mana_cost", 0)
	if mana_cost > 0:
		_add_line("Mana Cost: %d" % mana_cost, Color(0.4, 0.7, 1))

	# Cooldown
	var cooldown: float = _data.get("cooldown", 0.0)
	if cooldown > 0:
		_add_line("Cooldown: %.1fs" % cooldown, Color(1, 0.7, 0.2))

	_add_spacer()

	# Range
	var range_val: float = _data.get("range", 0.0)
	if range_val > 0:
		_add_line("Range: %.1fm" % range_val, Color(0.7, 0.7, 0.7))

	# Cast time
	var cast_time: float = _data.get("cast_time", 0.0)
	if cast_time > 0:
		_add_line("Cast Time: %.1fs" % cast_time, Color(0.7, 0.7, 0.7))

	_add_spacer()

	# Description
	var desc: String = _data.get("description", "")
	if not desc.is_empty():
		_add_line(desc, Color(0.7, 0.7, 0.7))


func _populate_npc_tooltip() -> void:
	_clear_content()

	var npc_name: String = _data.get("name", "Unknown NPC")
	var gold: Color = Color(1, 0.85, 0.4)
	_add_title(npc_name, gold)

	var npc_type: String = _data.get("type", "NPC")
	_add_line(npc_type, Color(0.7, 0.7, 0.7))

	_add_spacer()

	# Level (if combat NPC)
	var level: int = _data.get("level", 0)
	if level > 0:
		_add_line("Level: %d" % level, Color(1, 1, 1))

	# Services
	var services: Array = _data.get("services", [])
	for service in services:
		_add_line("[%s]" % service, Color(0.4, 0.7, 1))


func _populate_player_tooltip() -> void:
	_clear_content()

	var player_name: String = _data.get("name", "Unknown")
	var guild_name: String = _data.get("guild", "")
	var gold: Color = Color(1, 0.85, 0.4)

	_add_title(player_name, gold)

	if not guild_name.is_empty():
		_add_line("[%s]" % guild_name, Color(0.4, 0.7, 1))

	_add_spacer()

	var level: int = _data.get("level", 1)
	var class_name: String = _data.get("class", "Adventurer")
	_add_line("Level %d %s" % [level, class_name], Color(0.7, 0.7, 0.7))

	# PvP status
	if _data.get("pvp_enabled", false):
		_add_line("PvP Enabled", Color(1, 0.7, 0.2))


func _populate_quest_tooltip() -> void:
	_clear_content()

	var quest_name: String = _data.get("name", "Unknown Quest")
	var quest_type: String = _data.get("type", "Side")

	var type_color: Color = Color(0.7, 0.7, 0.7)
	match quest_type.to_lower():
		"main": type_color = Color(1, 0.85, 0.4)
		"side": type_color = Color(0.4, 0.7, 1)
		"daily": type_color = Color(0.4, 0.9, 0.4)

	_add_title(quest_name, type_color)
	_add_line("[%s Quest]" % quest_type, type_color)

	_add_spacer()

	var desc: String = _data.get("description", "")
	if not desc.is_empty():
		_add_line(desc, Color(0.7, 0.7, 0.7))


func _update_size() -> void:
	# Auto-size based on content
	if not _content or not _panel:
		return
	var height := 0.0
	for child in _content.get_children():
		if child is Control:
			height += (child as Control).get_combined_minimum_size().y
	_panel.custom_minimum_size.y = maxi(60, height + 20)
