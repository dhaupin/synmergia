## MainMenuBar - In-game menu bar for mobile/desktop panel access
## Provides hamburger menu, user avatar, settings button
## Expands to show all panel shortcuts (inventory, character, guild, etc.)
extends Control
class_name MainMenuBar

const UIStyles = preload("res://ui/components/ui_styles.gd")

var _menu_button: Button
var _avatar_button: Button
var _settings_button: Button
var _expanded_panel: PanelContainer
var _menu_items: VBoxContainer
var _is_expanded: bool = false
var _mm: Node
var _hud: Node

signal panel_requested(panel_id: String)

func _ready() -> void:
	_setup_ui()
	_setup_touch()
	hide_expanded()

func _setup_touch() -> void:
	# Ensure we process touch/mouse events
	mouse_filter = Control.MOUSE_FILTER_PASS

func _setup_ui() -> void:
	# Main horizontal bar at top of screen
	var bar := HBoxContainer.new()
	bar.name = "MainMenuBar"
	bar.anchors_preset = Control.PRESET_TOP_WIDE
	bar.offset_top = 8
	bar.offset_bottom = 68
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_constant_override("separation", 8)
	
	# Left: Hamburger menu button
	_menu_button = _create_icon_button("≡", "menu_button", "Open Menu")
	_menu_button.pressed.connect(_on_menu_button_pressed)
	bar.add_child(_menu_button)
	
	# Center spacer (pushes avatar to center-ish, settings to right)
	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(left_spacer)
	
	# Center: User avatar button (shows character name/level)
	_avatar_button = _create_avatar_button()
	_avatar_button.pressed.connect(_on_avatar_pressed)
	bar.add_child(_avatar_button)
	
	# Right spacer
	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(right_spacer)
	
	# Right: Settings button
	_settings_button = _create_icon_button("⚙", "settings_button", "Settings")
	_settings_button.pressed.connect(_on_settings_pressed)
	bar.add_child(_settings_button)
	
	add_child(bar)
	
	# Expanded menu panel (initially hidden)
	_create_expanded_panel()
	
	# Position at top-left initially, will be repositioned on expand
	_anchors_preset = Control.PRESET_TOP_WIDE
	_offset_top = 8
	_offset_bottom = 68

func _create_icon_button(text: String, name: String, tooltip: String) -> Button:
	var btn := Button.new()
	btn.name = name
	btn.text = text
	btn.custom_minimum_size = Vector2(48, 48)
	btn.toggle_mode = false
	btn.focus_mode = Control.FOCUS_NONE
	
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.12, 0.12, 0.18, 0.9)
	style_normal.border_color = Color(0.4, 0.35, 0.3)
	style_normal.border_width_left = 2
	style_normal.border_width_right = 2
	style_normal.border_width_top = 2
	style_normal.border_width_bottom = 2
	style_normal.corner_radius_top_left = 8
	style_normal.corner_radius_top_right = 8
	style_normal.corner_radius_bottom_left = 8
	style_normal.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", style_normal)
	
	var style_hover := style_normal.duplicate() as StyleBoxFlat
	style_hover.bg_color = Color(0.2, 0.18, 0.25, 0.95)
	btn.add_theme_stylebox_override("hover", style_hover)
	
	var style_pressed := style_normal.duplicate() as StyleBoxFlat
	style_pressed.bg_color = Color(0.15, 0.15, 0.22, 1.0)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	btn.tooltip_text = tooltip
	
	return btn

func _create_avatar_button() -> Button:
	var btn := Button.new()
	btn.name = "avatar_button"
	btn.custom_minimum_size = Vector2(160, 48)
	btn.toggle_mode = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_contents = true
	
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.12, 0.12, 0.18, 0.9)
	style_normal.border_color = UIStyles.COLORS.accent_gold
	style_normal.border_width_left = 2
	style_normal.border_width_right = 2
	style_normal.border_width_top = 2
	style_normal.border_width_bottom = 2
	style_normal.corner_radius_top_left = 8
	style_normal.corner_radius_top_right = 8
	style_normal.corner_radius_bottom_left = 8
	style_normal.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", style_normal)
	
	var style_hover := style_normal.duplicate() as StyleBoxFlat
	style_hover.bg_color = Color(0.18, 0.15, 0.1, 0.95)
	btn.add_theme_stylebox_override("hover", style_hover)
	
	var style_pressed := style_normal.duplicate() as StyleBoxFlat
	style_pressed.bg_color = Color(0.2, 0.15, 0.1, 1.0)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	# Avatar content: icon + name + level
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	# Character class icon placeholder
	var icon_label := Label.new()
	icon_label.text = "⚔"  # Default warrior icon
	icon_label.custom_minimum_size = Vector2(32, 32)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 24)
	hbox.add_child(icon_label)
	
	# Name and level
	var vbox := VBoxContainer.new()
	var name_label := Label.new()
	name_label.name = "name_label"
	name_label.text = "Player"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	vbox.add_child(name_label)
	
	var level_label := Label.new()
	level_label.name = "level_label"
	level_label.text = "Level 1"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	level_label.add_theme_font_size_override("font_size", 11)
	level_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	vbox.add_child(level_label)
	
	hbox.add_child(vbox)
	btn.add_child(hbox)
	
	return btn

func _create_expanded_panel() -> void:
	_expanded_panel = PanelContainer.new()
	_expanded_panel.name = "ExpandedMenu"
	_expanded_panel.anchors_preset = Control.PRESET_TOP_LEFT
	_expanded_panel.offset_left = 8
	_expanded_panel.offset_top = 76  # Below the main bar
	_expanded_panel.custom_minimum_size = Vector2(220, 0)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.98)
	style.border_color = UIStyles.COLORS.border_highlight
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_expanded_panel.add_theme_stylebox_override("panel", style)
	_expanded_panel.z_index = 100
	
	_menu_items = VBoxContainer.new()
	_menu_items.name = "MenuItems"
	_menu_items.add_theme_constant_override("separation", 4)
	_expanded_panel.add_child(_menu_items)
	
	# Add all panel shortcuts
	var panels := [
		{"id": "inventory", "text": "🎒 Inventory", "hotkey": "I"},
		{"id": "character", "text": "👤 Character", "hotkey": "C"},
		{"id": "skills", "text": "✨ Skills", "hotkey": "K"},
		{"id": "guild", "text": "🏰 Guild", "hotkey": "G"},
		{"id": "party", "text": "⚔ Party", "hotkey": "P"},
		{"id": "friends", "text": "👥 Friends", "hotkey": "F"},
		{"id": "quests", "text": "📜 Quests", "hotkey": "Q"},
		{"id": "bank", "text": "🏦 Bank/Vault", "hotkey": "B"},
		{"id": "blacksmith", "text": "🔨 Blacksmith", "hotkey": "H"},
		{"id": "world_map", "text": "🗺 World Map", "hotkey": "M"},
		{"id": "faction", "text": "⚖ Faction", "hotkey": "N"},
		{"id": "achievements", "text": "🏆 Achievements", "hotkey": "Y"},
		{"id": "titles", "text": "🎖 Titles", "hotkey": "T"},
		{"id": "trade", "text": "🤝 Trade", "hotkey": "R"},
		{"id": "transfer", "text": "🔄 Transfer", "hotkey": "X"},
	]
	
	for panel in panels:
		var btn := _create_menu_item(panel["id"], panel["text"], panel["hotkey"])
		_menu_items.add_child(btn)
	
	# Separator
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", UIStyles.COLORS.border)
	_menu_items.add_child(sep)
	
	# Settings item
	var settings_btn := _create_menu_item("settings", "⚙ Settings", "O")
	_menu_items.add_child(settings_btn)
	
	# Separator
	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("color", UIStyles.COLORS.border)
	_menu_items.add_child(sep2)
	
	# Close menu item
	var close_btn := _create_menu_item("close", "✕ Close Menu", "")
	_menu_items.add_child(close_btn)
	
	add_child(_expanded_panel)

func _create_menu_item(panel_id: String, text: String, hotkey: String) -> Button:
	var btn := Button.new()
	btn.name = "menu_item_%s" % panel_id
	btn.custom_minimum_size = Vector2(200, 40)
	btn.toggle_mode = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.flat = false
	
	var display_text := text
	if hotkey != "":
		display_text = "%s  [%s]" % [text, hotkey]
	btn.text = display_text
	btn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.1, 0.1, 0.15, 0)
	style_normal.border_color = Color(0, 0, 0, 0)
	btn.add_theme_stylebox_override("normal", style_normal)
	
	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.2, 0.18, 0.25, 0.8)
	style_hover.border_color = Color(0, 0, 0, 0)
	style_hover.corner_radius_top_left = 4
	style_hover.corner_radius_top_right = 4
	style_hover.corner_radius_bottom_left = 4
	style_hover.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("hover", style_hover)
	
	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.15, 0.15, 0.22, 1.0)
	style_pressed.border_color = Color(0, 0, 0, 0)
	style_pressed.corner_radius_top_left = 4
	style_pressed.corner_radius_top_right = 4
	style_pressed.corner_radius_bottom_left = 4
	style_pressed.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	
	btn.pressed.connect(func(): _on_menu_item_pressed(panel_id))
	
	return btn

func _on_menu_button_pressed() -> void:
	if _is_expanded:
		hide_expanded()
	else:
		show_expanded()

func _on_avatar_pressed() -> void:
	# Open character panel
	panel_requested.emit("character")
	hide_expanded()

func _on_settings_pressed() -> void:
	panel_requested.emit("settings")
	hide_expanded()

func _on_menu_item_pressed(panel_id: String) -> void:
	if panel_id == "close":
		hide_expanded()
	elif panel_id == "settings":
		panel_requested.emit("settings")
		hide_expanded()
	else:
		panel_requested.emit(panel_id)
		hide_expanded()

func show_expanded() -> void:
	_is_expanded = true
	_expanded_panel.visible = true
	_menu_button.text = "✕"
	# Animate in
	var tween := create_tween()
	tween.tween_property(_expanded_panel, "modulate:a", 1.0, 0.15)
	tween.tween_property(_expanded_panel, "offset_top", 76, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_expanded() -> void:
	_is_expanded = false
	_menu_button.text = "≡"
	var tween := create_tween()
	tween.tween_property(_expanded_panel, "modulate:a", 0.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): _expanded_panel.visible = false)
	tween.tween_property(_expanded_panel, "offset_top", 68, 0.1)

func update_character_info(name: String, level: int, class_icon: String = "⚔") -> void:
	if _avatar_button:
		var hbox = _avatar_button.get_child(0)
		if hbox and hbox.get_child_count() >= 2:
			var icon_label = hbox.get_child(0)
			var vbox = hbox.get_child(1)
			if icon_label:
				icon_label.text = class_icon
			if vbox and vbox.get_child_count() >= 2:
				var name_label = vbox.get_child(0)
				var level_label = vbox.get_child(1)
				if name_label:
					name_label.text = name
				if level_label:
					level_label.text = "Level %d" % level

func bind(hud: Node, menu_manager: Node) -> void:
	_hud = hud
	_mm = menu_manager
	
	# Connect panel_requested to MenuManager
	if _mm:
		panel_requested.connect(_mm.callable("_on_main_menu_panel_requested"))

func _input(event: InputEvent) -> void:
	# Close expanded menu on click outside
	if _is_expanded and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos := get_viewport().get_mouse_position()
		if not _expanded_panel.get_global_rect().has_point(mouse_pos) and not _menu_button.get_global_rect().has_point(mouse_pos):
			hide_expanded()
	
	# Touch support
	if _is_expanded and event is InputEventScreenTouch and event.pressed:
		var touch_pos := event.position
		if not _expanded_panel.get_global_rect().has_point(touch_pos) and not _menu_button.get_global_rect().has_point(touch_pos):
			hide_expanded()