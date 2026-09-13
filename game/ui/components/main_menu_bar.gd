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
var _player_id: String = ""
var _is_admin_or_mod: bool = false
var _is_dev_mode: bool = false
var _last_focused_item: Control = null

signal panel_requested(panel_id: String)

func _ready() -> void:
	_setup_ui()
	_setup_touch()
	_setup_accessibility()
	_check_permissions()
	_refresh_admin_debug_visibility()
	hide_expanded()

func _setup_touch() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func _setup_accessibility() -> void:
	# Enable focus for keyboard navigation
	focus_mode = Control.FOCUS_ALL
	accessible_name = "Main Menu Bar"
	accessible_description = "Game menu bar with hamburger menu, character profile, and settings. Use Tab to navigate, Enter to activate, Escape to close."
	# High contrast mode will be applied in _apply_high_contrast()

func update_accessibility_settings() -> void:
	# Update main buttons
	for btn in [_menu_button, _avatar_button, _settings_button]:
		if btn and is_instance_valid(btn):
			btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
			var scale = UIStyles.get_text_scale()
			var current_size := btn.get_theme_font_size("font_size")
			if current_size > 0:
				btn.add_theme_font_size_override("font_size", int(current_size * scale))
	
	# Update expanded panel menu items
	if _menu_items:
		for child in _menu_items.get_children():
			if child is Button:
				child.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
				var scale = UIStyles.get_text_scale()
				var current_size := child.get_theme_font_size("font_size")
				if current_size > 0:
					child.add_theme_font_size_override("font_size", int(current_size * scale))

func _check_permissions() -> void:
	if GameManager and GameManager.selected_character_data:
		_player_id = GameManager.selected_character_data.id
		if PermissionManager:
			_is_admin_or_mod = PermissionManager.has_permission(_player_id, PermissionManager.Level.MOD)
			_is_dev_mode = PermissionManager.has_permission(_player_id, PermissionManager.Level.ADMIN) \
				or (GameConfig and GameConfig.Debug.ALLOW_CHEATS)

func _refresh_admin_debug_visibility() -> void:
	if not _menu_items:
		return
	
	for child in _menu_items.get_children():
		if child.name.begins_with("menu_item_admin") or child.name.begins_with("menu_item_debug"):
			child.visible = _is_admin_or_mod if child.name.begins_with("menu_item_admin") else _is_dev_mode

func _setup_ui() -> void:
	var bar := HBoxContainer.new()
	bar.name = "MainMenuBar"
	bar.anchors_preset = Control.PRESET_TOP_WIDE
	bar.offset_top = 8
	bar.offset_bottom = 68
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_constant_override("separation", 8)
	
	# Left: Hamburger menu button
	_menu_button = _create_icon_button("≡", "menu_button", "Open Main Menu (M)")
	_menu_button.pressed.connect(_on_menu_button_pressed)
	_menu_button.focus_mode = Control.FOCUS_ALL
	_menu_button.accessible_name = "Main Menu"
	bar.add_child(_menu_button)
	
	# Center spacer (pushes avatar to center-ish, settings to right)
	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(left_spacer)
	
	# Center: User avatar button (shows character name/level)
	_avatar_button = _create_avatar_button()
	_avatar_button.pressed.connect(_on_avatar_pressed)
	_avatar_button.focus_mode = Control.FOCUS_ALL
	_avatar_button.accessible_name = "Character Profile"
	bar.add_child(_avatar_button)
	
	# Right spacer
	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(right_spacer)
	
	# Right: Settings button
	_settings_button = _create_icon_button("⚙", "settings_button", "Settings (O)")
	_settings_button.pressed.connect(_on_settings_pressed)
	_settings_button.focus_mode = Control.FOCUS_ALL
	_settings_button.accessible_name = "Settings"
	bar.add_child(_settings_button)
	
	add_child(bar)
	
	# Expanded menu panel (initially hidden)
	_create_expanded_panel()
	
	_anchors_preset = Control.PRESET_TOP_WIDE
	_offset_top = 8
	_offset_bottom = 68

func _create_icon_button(text: String, name: String, tooltip: String) -> Button:
	var btn := Button.new()
	btn.name = name
	btn.text = text
	btn.custom_minimum_size = Vector2(48, 48)  # 48dp minimum touch target
	btn.toggle_mode = false
	btn.focus_mode = Control.FOCUS_ALL
	btn.accessible_name = tooltip.split(" (")[0] if " (" in tooltip else tooltip
	btn.accessible_description = tooltip
	
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = _get_color("background_dark", Color(0.12, 0.12, 0.18, 0.9))
	style_normal.border_color = _get_color("border_highlight", Color(0.4, 0.35, 0.3))
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
	style_hover.bg_color = _get_color("background", Color(0.2, 0.18, 0.25, 0.95))
	btn.add_theme_stylebox_override("hover", style_hover)
	
	var style_pressed := style_normal.duplicate() as StyleBoxFlat
	style_pressed.bg_color = _get_color("background_dark", Color(0.15, 0.15, 0.22, 1.0))
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	var style_focus := style_normal.duplicate() as StyleBoxFlat
	style_focus.bg_color = _get_color("background", Color(0.2, 0.18, 0.25, 0.95))
	style_focus.border_color = _get_color("accent_gold", UIStyles.COLORS.accent_gold)
	style_focus.border_width_left = 3
	style_focus.border_width_right = 3
	style_focus.border_width_top = 3
	style_focus.border_width_bottom = 3
	btn.add_theme_stylebox_override("focus", style_focus)
	
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", _get_color("text_primary", UIStyles.COLORS.text_primary))
	btn.add_theme_color_override("font_focus_color", _get_color("accent_gold", UIStyles.COLORS.accent_gold))
	btn.tooltip_text = tooltip
	
	return btn

func _create_avatar_button() -> Button:
	var btn := Button.new()
	btn.name = "avatar_button"
	btn.custom_minimum_size = Vector2(160, 48)
	btn.toggle_mode = false
	btn.focus_mode = Control.FOCUS_ALL
	btn.clip_contents = true
	btn.accessible_name = "Character Profile"
	btn.accessible_description = "Shows your character name and level. Press to open character panel."
	
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = _get_color("background_dark", Color(0.12, 0.12, 0.18, 0.9))
	style_normal.border_color = _get_color("accent_gold", UIStyles.COLORS.accent_gold)
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
	style_hover.bg_color = _get_color("background", Color(0.18, 0.15, 0.1, 0.95))
	btn.add_theme_stylebox_override("hover", style_hover)
	
	var style_pressed := style_normal.duplicate() as StyleBoxFlat
	style_pressed.bg_color = _get_color("background_dark", Color(0.2, 0.15, 0.1, 1.0))
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	var style_focus := style_normal.duplicate() as StyleBoxFlat
	style_focus.bg_color = _get_color("background", Color(0.18, 0.15, 0.1, 0.95))
	style_focus.border_color = _get_color("accent_gold", UIStyles.COLORS.accent_gold)
	style_focus.border_width_left = 3
	style_focus.border_width_right = 3
	style_focus.border_width_top = 3
	style_focus.border_width_bottom = 3
	btn.add_theme_stylebox_override("focus", style_focus)
	
	# Avatar content: icon + name + level
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.focus_mode = Control.FOCUS_NONE
	
	# Character class icon placeholder
	var icon_label := Label.new()
	icon_label.text = "⚔"
	icon_label.custom_minimum_size = Vector2(32, 32)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 24)
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_label.focus_mode = Control.FOCUS_NONE
	hbox.add_child(icon_label)
	
	# Name and level
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.focus_mode = Control.FOCUS_NONE
	var name_label := Label.new()
	name_label.name = "name_label"
	name_label.text = "Player"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", _get_color("text_primary", UIStyles.COLORS.text_primary))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.focus_mode = Control.FOCUS_NONE
	vbox.add_child(name_label)
	
	var level_label := Label.new()
	level_label.name = "level_label"
	level_label.text = "Level 1"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	level_label.add_theme_font_size_override("font_size", 11)
	level_label.add_theme_color_override("font_color", _get_color("accent_gold", UIStyles.COLORS.accent_gold))
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.focus_mode = Control.FOCUS_NONE
	vbox.add_child(level_label)
	
	hbox.add_child(vbox)
	btn.add_child(hbox)
	
	return btn

func _create_expanded_panel() -> void:
	_expanded_panel = PanelContainer.new()
	_expanded_panel.name = "ExpandedMenu"
	_expanded_panel.anchors_preset = Control.PRESET_TOP_LEFT
	_expanded_panel.offset_left = 8
	_expanded_panel.offset_top = 76
	_expanded_panel.custom_minimum_size = Vector2(220, 0)
	_expanded_panel.focus_mode = Control.FOCUS_ALL
	_expanded_panel.accessible_name = "Main Menu"
	_expanded_panel.accessible_description = "Expanded menu with all panel shortcuts. Use arrow keys to navigate, Enter to select, Escape to close."
	
	var style := StyleBoxFlat.new()
	style.bg_color = _get_color("background_dark", Color(0.08, 0.08, 0.12, 0.98))
	style.border_color = _get_color("border_highlight", UIStyles.COLORS.border_highlight)
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
	_menu_items.focus_mode = Control.FOCUS_ALL
	_expanded_panel.add_child(_menu_items)
	
	# Add all panel shortcuts
	var panels := [
		{"id": "inventory", "text": "Inventory", "hotkey": "I", "icon": "🎒"},
		{"id": "character", "text": "Character", "hotkey": "C", "icon": "👤"},
		{"id": "skills", "text": "Skills", "hotkey": "K", "icon": "✨"},
		{"id": "guild", "text": "Guild", "hotkey": "G", "icon": "🏰"},
		{"id": "party", "text": "Party", "hotkey": "P", "icon": "⚔"},
		{"id": "friends", "text": "Friends", "hotkey": "F", "icon": "👥"},
		{"id": "quests", "text": "Quests", "hotkey": "Q", "icon": "📜"},
		{"id": "bank", "text": "Bank/Vault", "hotkey": "B", "icon": "🏦"},
		{"id": "blacksmith", "text": "Blacksmith", "hotkey": "H", "icon": "🔨"},
		{"id": "world_map", "text": "World Map", "hotkey": "M", "icon": "🗺"},
		{"id": "faction", "text": "Faction", "hotkey": "N", "icon": "⚖"},
		{"id": "achievements", "text": "Achievements", "hotkey": "Y", "icon": "🏆"},
		{"id": "titles", "text": "Titles", "hotkey": "T", "icon": "🎖"},
		{"id": "trade", "text": "Trade", "hotkey": "R", "icon": "🤝"},
		{"id": "transfer", "text": "Transfer", "hotkey": "X", "icon": "🔄"},
	]
	
	for panel in panels:
		var btn := _create_menu_item(panel["id"], panel["text"], panel["hotkey"], panel["icon"])
		_menu_items.add_child(btn)
	
	# Separator
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", _get_color("border", UIStyles.COLORS.border))
	sep.focus_mode = Control.FOCUS_NONE
	_menu_items.add_child(sep)
	
	# Admin panel (only visible to MOD+)
	var admin_btn := _create_menu_item("admin", "Admin Panel", "", "🛡", true)
	admin_btn.name = "menu_item_admin_panel"
	admin_btn.visible = _is_admin_or_mod
	admin_btn.tooltip_text = "Admin Panel (requires Moderator+)"
	admin_btn.accessible_name = "Admin Panel"
	admin_btn.accessible_description = "Open admin panel. Requires moderator permissions."
	_menu_items.add_child(admin_btn)
	
	# Debug panel (only visible to ADMIN+ or dev mode)
	var debug_btn := _create_menu_item("debug", "Debug Panel", "", "🐛", true)
	debug_btn.name = "menu_item_debug_panel"
	debug_btn.visible = _is_dev_mode
	debug_btn.tooltip_text = "Debug Panel (requires Admin/Dev Mode)"
	debug_btn.accessible_name = "Debug Panel"
	debug_btn.accessible_description = "Open debug panel. Requires admin permissions or dev mode."
	_menu_items.add_child(debug_btn)
	
	# Settings item
	var settings_btn := _create_menu_item("settings", "Settings", "O", "⚙")
	settings_btn.accessible_name = "Settings"
	settings_btn.accessible_description = "Open settings panel."
	_menu_items.add_child(settings_btn)
	
	# Separator
	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("color", _get_color("border", UIStyles.COLORS.border))
	sep2.focus_mode = Control.FOCUS_NONE
	_menu_items.add_child(sep2)
	
	# Close menu item
	var close_btn := _create_menu_item("close", "Close Menu", "", "✕")
	close_btn.accessible_name = "Close Menu"
	close_btn.accessible_description = "Close the main menu."
	_menu_items.add_child(close_btn)
	
	add_child(_expanded_panel)

func _create_menu_item(panel_id: String, text: String, hotkey: String, icon: String = "", is_special: bool = false) -> Button:
	var btn := Button.new()
	btn.name = "menu_item_%s" % panel_id
	btn.custom_minimum_size = Vector2(200, 48)  # 48dp minimum height for touch
	btn.toggle_mode = false
	btn.focus_mode = Control.FOCUS_ALL
	btn.flat = false
	btn.accessible_name = text
	btn.accessible_description = "Open %s panel. Hotkey: %s" % [text, hotkey] if hotkey != "" else "Open %s panel" % text
	
	var display_text := "%s %s" % [icon, text] if icon != "" else text
	if hotkey != "":
		display_text = "%s  [%s]" % [display_text, hotkey]
	btn.text = display_text
	btn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.tooltip_text = "%s (Hotkey: %s)" % [text, hotkey] if hotkey != "" else text
	
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0, 0, 0, 0)
	style_normal.border_color = Color(0, 0, 0, 0)
	btn.add_theme_stylebox_override("normal", style_normal)
	
	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = _get_color("background", Color(0.2, 0.18, 0.25, 0.8))
	style_hover.border_color = Color(0, 0, 0, 0)
	style_hover.corner_radius_top_left = 4
	style_hover.corner_radius_top_right = 4
	style_hover.corner_radius_bottom_left = 4
	style_hover.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("hover", style_hover)
	
	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = _get_color("background_dark", Color(0.15, 0.15, 0.22, 1.0))
	style_pressed.border_color = Color(0, 0, 0, 0)
	style_pressed.corner_radius_top_left = 4
	style_pressed.corner_radius_top_right = 4
	style_pressed.corner_radius_bottom_left = 4
	style_pressed.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	var style_focus := StyleBoxFlat.new()
	style_focus.bg_color = _get_color("background", Color(0.25, 0.22, 0.3, 0.9))
	style_focus.border_color = _get_color("accent_gold", UIStyles.COLORS.accent_gold)
	style_focus.border_width_left = 3
	style_focus.border_width_right = 3
	style_focus.border_width_top = 3
	style_focus.border_width_bottom = 3
	style_focus.corner_radius_top_left = 4
	style_focus.corner_radius_top_right = 4
	style_focus.corner_radius_bottom_left = 4
	style_focus.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("focus", style_focus)
	
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", _get_color("text_primary", UIStyles.COLORS.text_primary))
	btn.add_theme_color_override("font_focus_color", _get_color("accent_gold", UIStyles.COLORS.accent_gold))
	
	btn.pressed.connect(func(): _on_menu_item_pressed(panel_id))
	btn.focus_entered.connect(func(): _on_menu_item_focused(btn))
	
	return btn

func _get_color(key: String, fallback: Color) -> Color:
	if UIStyles and UIStyles.COLORS.has(key):
		return UIStyles.COLORS[key]
	return fallback

func _on_menu_button_pressed() -> void:
	if _is_expanded:
		hide_expanded()
	else:
		show_expanded()

func _on_avatar_pressed() -> void:
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
	elif panel_id == "admin":
		panel_requested.emit("admin")
		hide_expanded()
	elif panel_id == "debug":
		panel_requested.emit("debug")
		hide_expanded()
	else:
		panel_requested.emit(panel_id)
		hide_expanded()

func _on_menu_item_focused(item: Control) -> void:
	_last_focused_item = item

func show_expanded() -> void:
	_is_expanded = true
	_expanded_panel.visible = true
	_menu_button.text = "✕"
	_menu_button.tooltip_text = "Close Main Menu (M)"
	_menu_button.accessible_name = "Close Menu"
	
	# Focus first visible menu item for keyboard navigation
	call_deferred("_focus_first_menu_item")
	
	# Animate in
	var tween := create_tween()
	tween.tween_property(_expanded_panel, "modulate:a", 1.0, 0.15)
	tween.tween_property(_expanded_panel, "offset_top", 76, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _focus_first_menu_item() -> void:
	if not _menu_items:
		return
	for child in _menu_items.get_children():
		if child.visible and child is Button and child.focus_mode != Control.FOCUS_NONE:
			child.grab_focus()
			_last_focused_item = child
			break

func hide_expanded() -> void:
	_is_expanded = false
	_menu_button.text = "≡"
	_menu_button.tooltip_text = "Open Main Menu (M)"
	_menu_button.accessible_name = "Main Menu"
	
	# Return focus to menu button
	call_deferred("_return_focus_to_menu_button")
	
	var tween := create_tween()
	tween.tween_property(_expanded_panel, "modulate:a", 0.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): _expanded_panel.visible = false)
	tween.tween_property(_expanded_panel, "offset_top", 68, 0.1)

func _return_focus_to_menu_button() -> void:
	_menu_button.grab_focus()

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
		
		# Update accessibility info
		_avatar_button.accessible_name = "%s, Level %d" % [name, level]
		_avatar_button.tooltip_text = "Character: %s (Level %d)" % [name, level]

func bind(hud: Node, menu_manager: Node) -> void:
	_hud = hud
	_mm = menu_manager
	
	if _mm:
		panel_requested.connect(_mm.callable("_on_main_menu_panel_requested"))
	
	# Re-check permissions after bind (in case GameManager wasn't ready)
	call_deferred("_check_permissions")
	call_deferred("_refresh_admin_debug_visibility")

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
	
	# Keyboard navigation: Escape to close
	if _is_expanded and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide_expanded()
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_apply_high_contrast()

func _apply_high_contrast() -> void:
	# Check if high contrast mode is enabled via PlayerConfig
	var high_contrast := false
	if PlayerConfig:
		high_contrast = PlayerConfig.get_account_setting("high_contrast", false)
	
	if high_contrast:
		# Apply high contrast colors to all buttons
		var buttons := [_menu_button, _avatar_button, _settings_button]
		for btn in buttons:
			if btn:
				var style_focus := UIStyles.create_focus_style(8, true)
				btn.add_theme_stylebox_override("focus", style_focus)
				
				btn.add_theme_color_override("font_color", UIStyles.HIGH_CONTRAST_COLORS.text_primary)
				btn.add_theme_color_override("font_focus_color", UIStyles.HIGH_CONTRAST_COLORS.accent_gold)
				
				# Update normal/hover/pressed styles for high contrast
				var style_normal := StyleBoxFlat.new()
				style_normal.bg_color = UIStyles.HIGH_CONTRAST_COLORS.background_dark
				style_normal.border_color = UIStyles.HIGH_CONTRAST_COLORS.border
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
				style_hover.bg_color = UIStyles.HIGH_CONTRAST_COLORS.background
				btn.add_theme_stylebox_override("hover", style_hover)
				
				var style_pressed := style_normal.duplicate() as StyleBoxFlat
				style_pressed.bg_color = UIStyles.HIGH_CONTRAST_COLORS.background_dark
				btn.add_theme_stylebox_override("pressed", style_pressed)
		
		# Update expanded panel items
		if _menu_items:
			for child in _menu_items.get_children():
				if child is Button:
					var style_focus := UIStyles.create_focus_style(4, true)
					child.add_theme_stylebox_override("focus", style_focus)
					
					child.add_theme_color_override("font_color", UIStyles.HIGH_CONTRAST_COLORS.text_primary)
					child.add_theme_color_override("font_focus_color", UIStyles.HIGH_CONTRAST_COLORS.accent_gold)
					
					# Update normal/hover/pressed
					var style_normal := StyleBoxFlat.new()
					style_normal.bg_color = Color(0, 0, 0, 0)
					style_normal.border_color = Color(0, 0, 0, 0)
					child.add_theme_stylebox_override("normal", style_normal)
					
					var style_hover := StyleBoxFlat.new()
					style_hover.bg_color = UIStyles.HIGH_CONTRAST_COLORS.background
					style_hover.corner_radius_top_left = 4
					style_hover.corner_radius_top_right = 4
					style_hover.corner_radius_bottom_left = 4
					style_hover.corner_radius_bottom_right = 4
					child.add_theme_stylebox_override("hover", style_hover)
					
					var style_pressed := StyleBoxFlat.new()
					style_pressed.bg_color = UIStyles.HIGH_CONTRAST_COLORS.background_dark
					style_pressed.corner_radius_top_left = 4
					style_pressed.corner_radius_top_right = 4
					style_pressed.corner_radius_bottom_left = 4
					style_pressed.corner_radius_bottom_right = 4
					child.add_theme_stylebox_override("pressed", style_pressed)
				elif child is HSeparator:
					child.add_theme_color_override("color", UIStyles.HIGH_CONTRAST_COLORS.border)
		
		# Update expanded panel style
		if _expanded_panel:
			var style := UIStyles.create_high_contrast_panel_style()
			_expanded_panel.add_theme_stylebox_override("panel", style)

func update_admin_debug_visibility(is_admin_or_mod: bool, is_dev_mode: bool) -> void:
	_is_admin_or_mod = is_admin_or_mod
	_is_dev_mode = is_dev_mode
	_refresh_admin_debug_visibility()