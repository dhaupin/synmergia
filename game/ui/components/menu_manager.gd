## MenuManager - Central HUD manager for Synmergia
extends CanvasLayer
class_name MenuManager
const UIStyles = preload("res://ui/components/ui_styles.gd")


## Singleton
static var instance: MenuManager = null

## UI references
var _action_bar: HBoxContainer
var _quick_access_bar: HBoxContainer
var _buff_bar: HBoxContainer
var _status_bar: HBoxContainer

## Panel references
var _inventory_panel: Control
var _chat_panel: Control
var _character_panel: Control
var _guild_panel: Control
var _party_panel: Control
var _friends_panel: Control
var _quest_panel: Control
var _bank_panel: Control
var _blacksmith_panel: Control
var _skill_academy_panel: Control
var _faction_panel: Control
var _achievement_panel: Control
var _title_panel: Control
var _dialog_panel: Control
var _shop_panel: Control
var _transfer_panel: Control

## State
var _is_hud_visible: bool = true
var _is_menu_open: bool = false
var _open_panels: Array = []

signal menu_toggled(menu_name: String, is_open: bool)
signal hud_visibility_changed(visible: bool)

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return

	_setup_hud()
	_initialize_panels()
	_connect_signals()

func _setup_hud() -> void:
	# Action bar (bottom center) - skills/actions
	_action_bar = HBoxContainer.new()
	_action_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_action_bar.offset_top = -80
	_action_bar.offset_bottom = -10
	_action_bar.custom_minimum_size.y = 60
	_action_bar.z_index = 100
	add_child(_action_bar)

	# Quick access bar (bottom left) - consumables
	_quick_access_bar = HBoxContainer.new()
	_quick_access_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_quick_access_bar.offset_right = 250
	_quick_access_bar.offset_bottom = 60
	_quick_access_bar.custom_minimum_size.y = 50
	_quick_access_bar.z_index = 100
	add_child(_quick_access_bar)

	# Buff bar (top right)
	_buff_bar = HBoxContainer.new()
	_buff_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_buff_bar.offset_left = -200
	_buff_bar.offset_top = 50
	_buff_bar.custom_minimum_size.y = 40
	_buff_bar.z_index = 100
	add_child(_buff_bar)

	# Status bar (top center) - HP, MP, XP
	_status_bar = HBoxContainer.new()
	_status_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status_bar.offset_top = 10
	_status_bar.z_index = 100
	add_child(_status_bar)

	# Add placeholder slots
	_setup_action_slots()
	_setup_quick_slots()
	_setup_status_bar()

func _initialize_panels() -> void:
	# Chat panel - created from script
	_chat_panel = preload("res://ui/components/chat_ui.gd").new()
	_chat_panel.name = "ChatUI"
	_chat_panel.z_index = 90
	add_child(_chat_panel)

	# Inventory panel
	_inventory_panel = load("res://ui/components/inventory_ui.gd").new()
	_inventory_panel.name = "InventoryUI"
	_inventory_panel.z_index = 500
	add_child(_inventory_panel)

	# Character stats panel
	_character_panel = load("res://ui/components/character_panel.gd").new()
	_character_panel.name = "CharacterStatsUI"
	_character_panel.z_index = 500
	add_child(_character_panel)

	# Social panels
	_guild_panel = preload("res://ui/social/guild_ui.gd").new()
	_guild_panel.name = "GuildUI"
	_guild_panel.z_index = 500
	add_child(_guild_panel)

	_party_panel = preload("res://ui/social/party_ui.gd").new()
	_party_panel.name = "PartyUI"
	_party_panel.z_index = 500
	add_child(_party_panel)

	_friends_panel = preload("res://ui/social/friends_list.gd").new()

		# Quest panel
	_quest_panel = preload("res://ui/components/quest_ui.gd").new()
	_quest_panel.name = "QuestUI"
	_quest_panel.z_index = 500
	add_child(_quest_panel)

	# Bank/Vault panel
	_bank_panel = preload("res://ui/components/bank_ui.gd").new()
	_bank_panel.name = "BankUI"
	_bank_panel.z_index = 500
	add_child(_bank_panel)

	# Blacksmith panel
	_blacksmith_panel = preload("res://ui/components/blacksmith_ui.gd").new()
	_blacksmith_panel.name = "BlacksmithUI"
	_blacksmith_panel.z_index = 500
	add_child(_blacksmith_panel)

	# Skill Academy panel
	_skill_academy_panel = preload("res://ui/components/skill_academy_ui.gd").new()
	_skill_academy_panel.name = "SkillAcademyUI"
	_skill_academy_panel.z_index = 500
	add_child(_skill_academy_panel)

	_friends_panel.name = "FriendsUI"
	_friends_panel.z_index = 500
	add_child(_friends_panel)

	# Connect panel_closed signals
	_inventory_panel.panel_closed.connect(_on_panel_closed.bind("inventory"))
	_character_panel.panel_closed.connect(_on_panel_closed.bind("character"))
	_guild_panel.panel_closed.connect(_on_panel_closed.bind("guild"))
	_party_panel.panel_closed.connect(_on_panel_closed.bind("party"))
	_friends_panel.panel_closed.connect(_on_panel_closed.bind("friends"))
	_quest_panel.panel_closed.connect(_on_panel_closed.bind("quests"))
	_bank_panel.panel_closed.connect(_on_panel_closed.bind("bank"))
	_blacksmith_panel.panel_closed.connect(_on_panel_closed.bind("blacksmith"))
	_skill_academy_panel.panel_closed.connect(_on_panel_closed.bind("skill_academy"))

	# Faction panel
	_faction_panel = preload("res://ui/social/faction_ui.gd").new()
	_faction_panel.name = "FactionUI"
	_faction_panel.z_index = 500
	add_child(_faction_panel)
	_faction_panel.panel_closed.connect(_on_panel_closed.bind("faction"))

	# Achievement panel
	_achievement_panel = preload("res://ui/social/achievement_ui.gd").new()
	_achievement_panel.name = "AchievementUI"
	_achievement_panel.z_index = 500
	add_child(_achievement_panel)
	_achievement_panel.panel_closed.connect(_on_panel_closed.bind("achievement"))

	# Transfer panel (character-to-character transfers)
	_transfer_panel = preload("res://ui/social/character_transfer_ui.gd").new()
	_transfer_panel.name = "CharacterTransferUI"
	_transfer_panel.z_index = 500
	add_child(_transfer_panel)
	_transfer_panel.panel_closed.connect(_on_panel_closed.bind("transfer"))

	# Dialog panel
	_title_panel = preload("res://ui/components/title_ui.gd").new()
	_title_panel.name = "TitleUI"
	_title_panel.z_index = 500
	add_child(_title_panel)

	_dialog_panel = preload("res://ui/components/dialog_ui.gd").new()
	_dialog_panel.name = "DialogUI"
	_dialog_panel.z_index = 500
	add_child(_dialog_panel)

	# Shop panel
	_shop_panel = preload("res://ui/components/shop_ui.gd").new()
	_shop_panel.name = "ShopUI"
	_shop_panel.z_index = 500
	add_child(_shop_panel)

func _on_panel_closed(panel_name: String) -> void:
	if _open_panels.has(panel_name):
		_open_panels.erase(panel_name)
	menu_toggled.emit(panel_name, false)

func _setup_action_slots() -> void:
	for i in range(8):
		var slot := _create_action_slot(i)
		_action_bar.add_child(slot)

func _setup_quick_slots() -> void:
	for i in range(4):
		var slot := _create_quick_slot(i)
		_quick_access_bar.add_child(slot)

func _setup_status_bar() -> void:
	# Health bar
	var hp_container := VBoxContainer.new()
	hp_container.custom_minimum_size.x = 150

	var hp_label := Label.new()
	hp_label.text = "HP"
	hp_label.add_theme_font_size_override("font_size", 10)
	hp_label.add_theme_color_override("font_color", UIStyles.COLORS.error)
	hp_container.add_child(hp_label)

	var hp_bar := _create_progress_bar(UIStyles.COLORS.error)
	hp_bar.name = "HPBar"
	hp_container.add_child(hp_bar)

	_status_bar.add_child(hp_container)

	# Mana bar
	var mp_container := VBoxContainer.new()
	mp_container.custom_minimum_size.x = 150

	var mp_label := Label.new()
	mp_label.text = "MP"
	mp_label.add_theme_font_size_override("font_size", 10)
	mp_label.add_theme_color_override("font_color", UIStyles.COLORS.info)
	mp_container.add_child(mp_label)

	var mp_bar := _create_progress_bar(UIStyles.COLORS.info)
	mp_bar.name = "MPBar"
	mp_container.add_child(mp_bar)

	_status_bar.add_child(mp_container)

	# XP bar
	var xp_container := VBoxContainer.new()
	xp_container.custom_minimum_size.x = 150

	var xp_label := Label.new()
	xp_label.text = "XP"
	xp_label.add_theme_font_size_override("font_size", 10)
	xp_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	xp_container.add_child(xp_label)

	var xp_bar := _create_progress_bar(UIStyles.COLORS.accent_gold)
	xp_bar.name = "XPBar"
	xp_container.add_child(xp_bar)

	_status_bar.add_child(xp_container)

func _create_action_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(50, 50)
	slot.name = "ActionSlot%d" % index

	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.border_color = UIStyles.COLORS.border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	slot.add_theme_stylebox_override("panel", style)

	# Keybind label
	var keybind := Label.new()
	keybind.text = str(index + 1)
	keybind.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	keybind.add_theme_font_size_override("font_size", 10)
	keybind.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	keybind.offset_left = -15
	keybind.offset_right = -3
	keybind.offset_top = -12
	keybind.offset_bottom = -2
	slot.add_child(keybind)

	return slot

func _create_quick_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(40, 40)
	slot.name = "QuickSlot%d" % index

	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.border_color = UIStyles.COLORS.border
	slot.add_theme_stylebox_override("panel", style)

	return slot

func _create_progress_bar(color: Color) -> PanelContainer:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(150, 12)

	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("panel", style)

	# Fill
	var fill := Panel.new()
	fill.custom_minimum_size = Vector2(150, 12)
	fill.name = "Fill"

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2

	fill.add_theme_stylebox_override("panel", fill_style)
	bar.add_child(fill)

	return bar

func _connect_signals() -> void:
	# ChatService messages
	if ChatService:
		ChatService.message_received.connect(_on_chat_message_received)

## ============================================================================
## PUBLIC API
## ============================================================================

static func singleton() -> MenuManager:
	return instance

static func toggle_menu(menu_name: String) -> void:
	if instance:
		instance._toggle_menu_internal(menu_name)

static func open_menu(menu_name: String) -> void:
	if instance:
		instance._open_menu_internal(menu_name)

static func close_menu(menu_name: String) -> void:
	if instance:
		instance._close_menu_internal(menu_name)

static func get_open_panels() -> Array:
	if instance:
		return instance._open_panels.duplicate()
	return []

static func get_panel_node(panel_name: String) -> Control:
	if instance:
		return instance._get_panel(panel_name)
	return null

static func close_top_menu() -> void:
	if instance:
		instance._close_top_menu_internal()

static func close_all_menus() -> void:
	if instance:
		instance._close_all_menus_internal()

static func set_hud_visible(visible: bool) -> void:
	if instance:
		instance._set_hud_visible_internal(visible)

static func update_hp(current: int, maximum: int) -> void:
	if instance:
		instance._update_hp_internal(current, maximum)

static func update_mp(current: int, maximum: int) -> void:
	if instance:
		instance._update_mp_internal(current, maximum)

static func update_xp(current: int, maximum: int) -> void:
	if instance:
		instance._update_xp_internal(current, maximum)

## ============================================================================
## INTERNAL
## ============================================================================

func _toggle_menu_internal(menu_name: String) -> void:
	var panel := _get_panel(menu_name)
	if not panel:
		return

	if panel.visible:
		_close_panel(menu_name, panel)
	else:
		_open_panel(menu_name, panel)

func _open_menu_internal(menu_name: String) -> void:
	var panel := _get_panel(menu_name)
	if not panel:
		return

	if not _open_panels.has(menu_name):
		_open_panels.append(menu_name)
	_is_menu_open = true
	panel.visible = true
	menu_toggled.emit(menu_name, true)

func _close_menu_internal(menu_name: String) -> void:
	var panel := _get_panel(menu_name)
	if not panel:
		return

	_close_panel(menu_name, panel)

func _close_panel(menu_name: String, panel: Control) -> void:
	if _open_panels.has(menu_name):
		_open_panels.erase(menu_name)
	panel.visible = false
	if _open_panels.is_empty():
		_is_menu_open = false
	menu_toggled.emit(menu_name, false)

func _open_panel(menu_name: String, panel: Control) -> void:
	if not _open_panels.has(menu_name):
		_open_panels.append(menu_name)
	_is_menu_open = true
	panel.visible = true
	menu_toggled.emit(menu_name, true)

func _close_top_menu_internal() -> void:
	if _open_panels.is_empty():
		return
	var top: String = _open_panels[-1]
	var panel: Control = _get_panel(top)
	if panel:
		_close_panel(top, panel)

func _close_all_menus_internal() -> void:
	for panel_name in _open_panels:
		var panel := _get_panel(panel_name)
		if panel:
			panel.visible = false
		menu_toggled.emit(panel_name, false)
	_open_panels.clear()
	_is_menu_open = false

func _get_panel(menu_name: String) -> Control:
	match menu_name:
		"inventory": return _inventory_panel
		"character": return _character_panel
		"guild": return _guild_panel
		"party": return _party_panel
		"friends": return _friends_panel
		"chat": return _chat_panel
		"quests": return _quest_panel
		"bank": return _bank_panel
		"blacksmith": return _blacksmith_panel
		"skill_academy": return _skill_academy_panel
		"faction": return _faction_panel
		"achievement": return _achievement_panel
		"titles": return _title_panel
		"transfer": return _transfer_panel
		"dialog": return _dialog_panel
		"shop": return _shop_panel
	return null

func _set_hud_visible_internal(visible: bool) -> void:
	_is_hud_visible = visible
	_action_bar.visible = visible
	_quick_access_bar.visible = visible
	_buff_bar.visible = visible
	_status_bar.visible = visible
	hud_visibility_changed.emit(visible)

func _update_hp_internal(current: int, maximum: int) -> void:
	_update_bar("HPBar", current, maximum, UIStyles.COLORS.error)

func _update_mp_internal(current: int, maximum: int) -> void:
	_update_bar("MPBar", current, maximum, UIStyles.COLORS.info)

func _update_xp_internal(current: int, maximum: int) -> void:
	_update_bar("XPBar", current, maximum, UIStyles.COLORS.accent_gold)

func _update_bar(bar_name: String, current: int, maximum: int, color: Color) -> void:
	var bar: PanelContainer = _status_bar.get_node_or_null(bar_name)
	if not bar:
		return

	var fill: Panel = bar.get_node_or_null("Fill")
	if not fill:
		return

	var ratio := float(current) / float(maximum) if maximum > 0 else 0.0
	var bar_width := 150.0 * ratio

	fill.custom_minimum_size.x = bar_width

	var style := fill.get_theme_stylebox("panel")
	if style:
		style.bg_color = color

func _on_chat_message_received(sender_id: String, channel: int, message: String, targets: Array) -> void:
	if _chat_panel and _chat_panel.has_method("add_message"):
		_chat_panel.add_message(sender_id, channel, message)

func _input(event: InputEvent) -> void:
	# NOTE: Panel hotkeys (I, C, P, G, F, Q, ESC) are handled by HudHotkeys.
	# This only handles chat-specific input.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		if _chat_panel and _chat_panel.has_method("focus_input"):
			_chat_panel.focus_input()
