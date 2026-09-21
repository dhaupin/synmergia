## SettingsPanel - Game settings UI
## Categories: Graphics, Audio, Controls, Gameplay, Accessibility, Social
## Keybind remapping with conflict detection, UI scale, colorblind shaders
## Wired to PlayerConfig for persistent settings.
extends "res://ui/components/ui_panel.gd"
class_name SettingsPanel

enum Category {
	GRAPHICS = 0,
	AUDIO = 1,
	CONTROLS = 2,
	GAMEPLAY = 3,
	ACCESSIBILITY = 4,
	SOCIAL = 5
}

var _current_category: Category = Category.GRAPHICS
var _tab_buttons: Array = []
var _category_containers: Dictionary = {}

var _setting_controls: Dictionary = {}
var _setting_keys: Array = []

## Keybind remapping state
var _keybind_actions: Dictionary = {}
var _remapping_action: String = ""
var _remap_button: Button = null
var _keybind_conflicts: Dictionary = {}

func _ready() -> void:
	super._ready()
	set_title("Settings")
	set_panel_size(Vector2(700, 550))
	_setup_ui()
	if PlayerConfig:
		_load_from_config()
	_apply_current_settings()

func _setup_ui() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main: VBoxContainer = panel.get_node_or_null("Main")
	if not main:
		var content_vbox := VBoxContainer.new()
		content_vbox.name = "Main"
		content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.add_child(content_vbox)
		main = content_vbox

	## Tab bar
	var tab_bar := HBoxContainer.new()
	tab_bar.name = "TabBar"
	tab_bar.custom_minimum_size.y = 40
	tab_bar.add_theme_constant_override("separation", 4)
	main.add_child(tab_bar)

	var categories = [
		{"id": Category.GRAPHICS, "name": "Graphics"},
		{"id": Category.AUDIO, "name": "Audio"},
		{"id": Category.CONTROLS, "name": "Controls"},
		{"id": Category.GAMEPLAY, "name": "Gameplay"},
		{"id": Category.ACCESSIBILITY, "name": "Accessibility"},
		{"id": Category.SOCIAL, "name": "Social"}
	]

	for cat in categories:
		var btn := Button.new()
		btn.text = cat.name
		btn.toggle_mode = true
		btn.custom_minimum_size.x = 90
		btn.pressed.connect(_on_category_clicked.bind(cat.id))
		_tab_buttons.append(btn)
		tab_bar.add_child(btn)

	_tab_buttons[0].button_pressed = true

	## Content stack (one container per category)
	var stack := VBoxContainer.new()
	stack.name = "CategoryStack"
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(stack)

	for cat in categories:
		var container := VBoxContainer.new()
		container.name = "Category_%s" % cat.name
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		container.visible = (cat.id == Category.GRAPHICS)
		container.add_theme_constant_override("separation", 8)
		_category_containers[cat.id] = container
		stack.add_child(container)

	## Populate each category
	_populate_graphics_settings(_category_containers[Category.GRAPHICS])
	_populate_audio_settings(_category_containers[Category.AUDIO])
	_populate_controls_settings(_category_containers[Category.CONTROLS])
	_populate_gameplay_settings(_category_containers[Category.GAMEPLAY])
	_populate_accessibility_settings(_category_containers[Category.ACCESSIBILITY])
	_populate_social_settings(_category_containers[Category.SOCIAL])

	## Button row
	var btn_row := HBoxContainer.new()
	btn_row.custom_minimum_size.y = 40
	btn_row.add_theme_constant_override("separation", 8)
	main.add_child(btn_row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	var defaults_btn := Button.new()
	defaults_btn.text = "Defaults"
	defaults_btn.custom_minimum_size.x = 100
	defaults_btn.pressed.connect(_on_defaults)
	btn_row.add_child(defaults_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size.x = 100
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.custom_minimum_size.x = 100
	save_btn.pressed.connect(_on_save)
	btn_row.add_child(save_btn)

func _on_category_clicked(cat_id: int) -> void:
	_current_category = cat_id
	for cat_id_key in _category_containers:
		_category_containers[cat_id_key].visible = (cat_id_key == cat_id)
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].button_pressed = (i == cat_id)

func _create_setting_row(label_text: String, tooltip: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 36
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not tooltip.is_empty():
		lbl.tooltip_text = tooltip
	row.add_child(lbl)
	return row

func _create_slider_row(setting_key: String, label_text: String, min_val: float, max_val: float, default_val: float, step: float = 0.01, format: String = "%.2f", tooltip: String = "") -> HBoxContainer:
	var row := _create_setting_row(label_text, tooltip)
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = default_val
	slider.step = step
	slider.custom_minimum_size.x = 200
	slider.value_changed.connect(_on_slider_changed.bind(setting_key))
	row.add_child(slider)

	var value_label := Label.new()
	value_label.text = format % default_val
	value_label.custom_minimum_size.x = 50
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	_setting_controls[setting_key] = {"type": "slider", "control": slider, "label": value_label, "format": format}
	_setting_keys.append(setting_key)
	return row

func _create_toggle_row(setting_key: String, label_text: String, default_val: bool, tooltip: String = "") -> HBoxContainer:
	var row := _create_setting_row(label_text, tooltip)
	var toggle := CheckButton.new()
	toggle.button_pressed = default_val
	toggle.toggled.connect(_on_toggle_changed.bind(setting_key))
	row.add_child(toggle)
	_setting_controls[setting_key] = {"type": "toggle", "control": toggle}
	_setting_keys.append(setting_key)
	return row

func _create_dropdown_row(setting_key: String, label_text: String, options: Array, default_idx: int, tooltip: String = "") -> HBoxContainer:
	var row := _create_setting_row(label_text, tooltip)
	var dropdown := OptionButton.new()
	for opt in options:
		dropdown.add_item(opt)
	dropdown.selected = default_idx
	dropdown.custom_minimum_size.x = 200
	dropdown.item_selected.connect(_on_dropdown_changed.bind(setting_key))
	row.add_child(dropdown)
	_setting_controls[setting_key] = {"type": "dropdown", "control": dropdown, "options": options}
	_setting_keys.append(setting_key)
	return row

func _create_keybind_row(setting_key: String, label_text: String, default_key: int, action_name: String, tooltip: String = "") -> HBoxContainer:
	var row := _create_setting_row(label_text, tooltip)
	var btn := Button.new()
	btn.text = _keycode_to_string(default_key)
	btn.custom_minimum_size.x = 120
	btn.custom_minimum_size.y = 28
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_ALL
	btn.pressed.connect(_start_keybind_remap.bind(setting_key, action_name, btn))
	row.add_child(btn)

	var conflict_label := Label.new()
	conflict_label.text = ""
	conflict_label.custom_minimum_size.x = 100
	conflict_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)
	conflict_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	conflict_label.visible = false
	row.add_child(conflict_label)

	_keybind_actions[setting_key] = {
		"action_name": action_name,
		"button": btn,
		"conflict_label": conflict_label,
		"default_key": default_key,
		"current_key": default_key
	}
	_setting_controls[setting_key] = {"type": "keybind", "control": btn, "conflict_label": conflict_label}
	_setting_keys.append(setting_key)
	return row

func _keycode_to_string(keycode: int) -> String:
	match keycode:
		KEY_ESCAPE: return "Escape"
		KEY_TAB: return "Tab"
		KEY_SPACE: return "Space"
		KEY_ENTER: return "Enter"
		KEY_SHIFT: return "Shift"
		KEY_CTRL: return "Ctrl"
		KEY_ALT: return "Alt"
		KEY_BACKSPACE: return "Backspace"
		KEY_DELETE: return "Delete"
		KEY_INSERT: return "Insert"
		KEY_HOME: return "Home"
		KEY_END: return "End"
		KEY_PAGEUP: return "Page Up"
		KEY_PAGEDOWN: return "Page Down"
		KEY_UP: return "Up"
		KEY_DOWN: return "Down"
		KEY_LEFT: return "Left"
		KEY_RIGHT: return "Right"
		KEY_F1: return "F1"
		KEY_F2: return "F2"
		KEY_F3: return "F3"
		KEY_F4: return "F4"
		KEY_F5: return "F5"
		KEY_F6: return "F6"
		KEY_F7: return "F7"
		KEY_F8: return "F8"
		KEY_F9: return "F9"
		KEY_F10: return "F10"
		KEY_F11: return "F11"
		KEY_F12: return "F12"
		KEY_0: return "0"
		KEY_1: return "1"
		KEY_2: return "2"
		KEY_3: return "3"
		KEY_4: return "4"
		KEY_5: return "5"
		KEY_6: return "6"
		KEY_7: return "7"
		KEY_8: return "8"
		KEY_9: return "9"
		KEY_A: return "A"
		KEY_B: return "B"
		KEY_C: return "C"
		KEY_D: return "D"
		KEY_E: return "E"
		KEY_F: return "F"
		KEY_G: return "G"
		KEY_H: return "H"
		KEY_I: return "I"
		KEY_J: return "J"
		KEY_K: return "K"
		KEY_L: return "L"
		KEY_M: return "M"
		KEY_N: return "N"
		KEY_O: return "O"
		KEY_P: return "P"
		KEY_Q: return "Q"
		KEY_R: return "R"
		KEY_S: return "S"
		KEY_T: return "T"
		KEY_U: return "U"
		KEY_V: return "V"
		KEY_W: return "W"
		KEY_X: return "X"
		KEY_Y: return "Y"
		KEY_Z: return "Z"
		KEY_MINUS: return "-"
		KEY_EQUAL: return "="
		KEY_BRACKETLEFT: return "["
		KEY_BRACKETRIGHT: return "]"
		KEY_BACKSLASH: return "\\"
		KEY_SEMICOLON: return ";"
		KEY_APOSTROPHE: return "'"
		KEY_COMMA: return ","
		KEY_PERIOD: return "."
		KEY_SLASH: return "/"
		KEY_QUOTELEFT: return "`"
		KEY_CAPSLOCK: return "CapsLock"
		KEY_SCROLLLOCK: return "ScrollLock"
		KEY_NUMLOCK: return "NumLock"
		KEY_PRINT: return "Print"
		KEY_PAUSE: return "Pause"
		KEY_KP_0: return "Numpad 0"
		KEY_KP_1: return "Numpad 1"
		KEY_KP_2: return "Numpad 2"
		KEY_KP_3: return "Numpad 3"
		KEY_KP_4: return "Numpad 4"
		KEY_KP_5: return "Numpad 5"
		KEY_KP_6: return "Numpad 6"
		KEY_KP_7: return "Numpad 7"
		KEY_KP_8: return "Numpad 8"
		KEY_KP_9: return "Numpad 9"
		KEY_KP_PERIOD: return "Numpad ."
		KEY_KP_DIVIDE: return "Numpad /"
		KEY_KP_MULTIPLY: return "Numpad *"
		KEY_KP_SUBTRACT: return "Numpad -"
		KEY_KP_ADD: return "Numpad +"
		KEY_KP_ENTER: return "Numpad Enter"
		KEY_KP_MULTIPLY: return "Numpad ="
		_: return "Key(%d)" % keycode

func _start_keybind_remap(setting_key: String, action_name: String, button: Button) -> void:
	if _remapping_action != "":
		return

	_remapping_action = setting_key
	_remap_button = button
	button.text = "Press key..."
	button.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	button.grab_focus()

func _input(event: InputEvent) -> void:
	if _remapping_action != "" and event is InputEventKey and event.pressed and not event.echo:
		var new_key: int = (event as InputEventKey).keycode
		if new_key == KEY_ESCAPE:
			_cancel_keybind_remap()
			return

		_check_keybind_conflicts(new_key)
		_apply_keybind_remap(new_key)

func _check_keybind_conflicts(new_key: int) -> void:
	_keybind_conflicts.clear()
	for key in _keybind_actions:
		var data = _keybind_actions[key]
		if data.current_key == new_key and key != _remapping_action:
			var conflict_action: String = data.action_name
			var current_action: String = _keybind_actions[_remapping_action].action_name
			_keybind_conflicts[key] = true
			data.conflict_label.text = "Conflicts: %s" % current_action
			data.conflict_label.visible = true
			_keybind_actions[_remapping_action].conflict_label.text = "Conflicts: %s" % conflict_action
			_keybind_actions[_remapping_action].conflict_label.visible = true

func _apply_keybind_remap(new_key: int) -> void:
	var data: Dictionary = _keybind_actions[_remapping_action]
	data.current_key = new_key
	data.button.text = _keycode_to_string(new_key)
	data.button.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	data.button.button_pressed = false

	if PlayerConfig:
		PlayerConfig.set_account_setting(_remapping_action, new_key, false)

	_remapping_action = ""
	_remap_button = null

func _cancel_keybind_remap() -> void:
	if _remapping_action == "":
		return
	var data: Dictionary = _keybind_actions[_remapping_action]
	data.button.text = _keycode_to_string(data.current_key)
	data.button.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	data.button.button_pressed = false
	_remapping_action = ""
	_remap_button = null

func _load_from_config() -> void:
	for key in _setting_keys:
		var info: Dictionary = _setting_controls.get(key, {})
		var ctrl = info.get("control")
		if not ctrl:
			continue
		var val = PlayerConfig.get_account_setting(key)
		if val == null:
			continue
		match info.get("type"):
			"slider":
				if ctrl is HSlider:
					ctrl.value = val
					var fmt: String = info.get("format", "%.2f")
					var lbl: Variant = info.get("label")
					if lbl is Label:
						lbl.text = fmt % val
			"toggle":
				if ctrl is CheckButton:
					ctrl.button_pressed = val
			"dropdown":
				if ctrl is OptionButton:
					ctrl.selected = val
			"keybind":
				if ctrl is Button:
					var kb_data: Dictionary = _keybind_actions.get(key, {})
					kb_data.current_key = val
					ctrl.text = _keycode_to_string(val)

func _apply_current_settings() -> void:
	_apply_ui_scale()
	_apply_text_scale()
	_apply_colorblind_shader()
	_apply_reduce_motion()
	_apply_high_contrast()

func _on_slider_changed(value: float, key: String) -> void:
	if PlayerConfig:
		PlayerConfig.set_account_setting(key, value, false)
	var info: Dictionary = _setting_controls.get(key, {})
	var lbl = info.get("label")
	var fmt: String = info.get("format", "%.2f")
	if lbl is Label:
		lbl.text = fmt % value

	if key == "ui_scale":
		_apply_ui_scale()
	elif key == "ui_text_scale":
		_apply_text_scale()

func _on_toggle_changed(value: bool, key: String) -> void:
	if PlayerConfig:
		PlayerConfig.set_account_setting(key, value, false)

	if key == "colorblind_mode":
		_apply_colorblind_shader()
	elif key == "reduce_motion":
		_apply_reduce_motion()
	elif key == "high_contrast":
		_apply_high_contrast()
	elif key == "screen_shake":
		_apply_screen_shake()
	elif key == "touch_controls":
		# Live-apply: show/hide the touch HUD immediately.
		if InputManager:
			InputManager.set_touch_ui_visible(value)

func _on_dropdown_changed(index: int, key: String) -> void:
	if PlayerConfig:
		PlayerConfig.set_account_setting(key, index, false)

	if key == "colorblind_type":
		_apply_colorblind_shader()

func _apply_ui_scale() -> void:
	var scale: float = PlayerConfig.get_account_setting("ui_scale", 1.0)
	if scale < 0.75:
		scale = 0.75
	elif scale > 1.5:
		scale = 1.5
	
	var root := get_tree().root
	if root:
		for canvas_layer in root.get_children():
			if canvas_layer is CanvasLayer:
				canvas_layer.scale = Vector2(scale, scale)

func _apply_text_scale() -> void:
	var scale: float = PlayerConfig.get_account_setting("ui_text_scale", 1.0)
	if scale < 0.8:
		scale = 0.8
	elif scale > 1.5:
		scale = 1.5
	
	# Broadcast text scale change to all UI components
	# Components that listen for this will update themselves
	EventHub.emit_signal("accessibility_text_scale_changed", scale)

func _apply_colorblind_shader() -> void:
	var enabled: bool = PlayerConfig.get_account_setting("colorblind_mode", false)
	var type_idx: int = PlayerConfig.get_account_setting("colorblind_type", 0)
	
	## Shader application would go here
	## For now we just store the setting; actual shader application
	## requires a ShaderMaterial on the viewport or CanvasLayer
	if enabled:
		var mode_names := ["Deuteranopia", "Protanopia", "Tritanopia"]
		GameLog.info("Colorblind mode: %s" % mode_names[type_idx])
	else:
		GameLog.info("Colorblind mode: Off")

func _apply_reduce_motion() -> void:
	var enabled: bool = PlayerConfig.get_account_setting("reduce_motion", false)
	if enabled:
		GameLog.info("Reduce motion: Enabled (disabling UI animations)")
	else:
		GameLog.info("Reduce motion: Disabled")
	
	# Broadcast reduce motion change to all UI components
	EventHub.emit_signal("accessibility_reduce_motion_changed", enabled)

func _apply_high_contrast() -> void:
	var enabled: bool = PlayerConfig.get_account_setting("high_contrast", false)
	if enabled:
		GameLog.info("High contrast: Enabled")
	else:
		GameLog.info("High contrast: Disabled")
	
	# Broadcast high contrast change to all UI components
	EventHub.emit_signal("accessibility_high_contrast_changed", enabled)

func _apply_screen_shake() -> void:
	var enabled: bool = PlayerConfig.get_account_setting("screen_shake", true)
	GameLog.info("Screen shake: %s" % ("Enabled" if enabled else "Disabled"))

func _populate_graphics_settings(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	var section := Label.new()
	section.text = "Display"
	section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section.add_theme_font_size_override("font_size", 14)
	content.add_child(section)

	content.add_child(_create_dropdown_row("resolution", "Resolution:", ["1920x1080", "1600x900", "1280x720", "1366x768", "Windowed"], 0))
	content.add_child(_create_dropdown_row("graphics_quality", "Quality:", ["Low", "Medium", "High", "Ultra"], 2))
	content.add_child(_create_dropdown_row("window_mode", "Window Mode:", ["Fullscreen", "Borderless", "Windowed"], 0))
	content.add_child(_create_toggle_row("vsync_enabled", "VSync", true))
	content.add_child(_create_slider_row("max_fps", "Max FPS:", 30, 240, 60, 30, "%d"))
	content.add_child(_create_toggle_row("show_fps_counter", "Show FPS Counter", false))

	var section2 := Label.new()
	section2.text = "Effects"
	section2.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section2.add_theme_font_size_override("font_size", 14)
	content.add_child(section2)

	content.add_child(_create_toggle_row("bloom_effects", "Bloom Effects", true))
	content.add_child(_create_toggle_row("particle_effects", "Particle Effects", true))
	content.add_child(_create_toggle_row("ambient_occlusion", "Ambient Occlusion", true))
	content.add_child(_create_dropdown_row("shadow_quality", "Shadow Quality:", ["Low", "Medium", "High", "Ultra"], 2))
	content.add_child(_create_dropdown_row("antialiasing", "Anti-aliasing:", ["Off", "2x", "4x", "8x"], 1))

	var section3 := Label.new()
	section3.text = "UI"
	section3.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section3.add_theme_font_size_override("font_size", 14)
	content.add_child(section3)

	content.add_child(_create_slider_row("ui_scale", "UI Scale:", 0.75, 1.5, 1.0, 0.05, "%.2fx", "Live preview - applies immediately"))
	content.add_child(_create_toggle_row("show_damage_numbers", "Show Damage Numbers", true))
	content.add_child(_create_toggle_row("player_nameplates", "Show Name Plates", true))
	content.add_child(_create_toggle_row("show_health_bars", "Show Health Bars", true))

func _populate_audio_settings(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	var section := Label.new()
	section.text = "Volume"
	section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section.add_theme_font_size_override("font_size", 14)
	content.add_child(section)

	content.add_child(_create_slider_row("master_volume", "Master Volume:", 0.0, 1.0, 0.8, 0.05, "%.0f%%", "Overall volume"))
	content.add_child(_create_slider_row("music_volume", "Music Volume:", 0.0, 1.0, 0.7, 0.05, "%.0f%%"))
	content.add_child(_create_slider_row("sfx_volume", "SFX Volume:", 0.0, 1.0, 0.8, 0.05, "%.0f%%"))
	content.add_child(_create_slider_row("voice_volume", "Voice Volume:", 0.0, 1.0, 0.8, 0.05, "%.0f%%"))
	content.add_child(_create_slider_row("ambient_volume", "Ambient Volume:", 0.0, 1.0, 0.7, 0.05, "%.0f%%"))

	var section2 := Label.new()
	section2.text = "Options"
	section2.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section2.add_theme_font_size_override("font_size", 14)
	content.add_child(section2)

	content.add_child(_create_toggle_row("enable_music", "Enable Music", true))
	content.add_child(_create_toggle_row("ui_sounds", "UI Sounds", true))
	content.add_child(_create_toggle_row("mute_on_focus_loss", "Mute on Focus Loss", false))
	content.add_child(_create_toggle_row("enable_voice_chat", "Enable Voice Chat", false))

func _populate_controls_settings(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	var section := Label.new()
	section.text = "Mouse & Camera"
	section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section.add_theme_font_size_override("font_size", 14)
	content.add_child(section)

	content.add_child(_create_slider_row("mouse_sensitivity", "Mouse Sensitivity:", 0.1, 3.0, 1.0, 0.1, "%.1f"))
	content.add_child(_create_toggle_row("invert_y_axis", "Invert Y Axis", false))
	content.add_child(_create_toggle_row("invert_x_axis", "Invert X Axis", false))
	content.add_child(_create_dropdown_row("camera_mode", "Camera Mode:", ["Follow", "Action", "Fixed"], 0))
	content.add_child(_create_slider_row("camera_distance", "Camera Distance:", 5.0, 30.0, 10.0, 1.0, "%.1f"))

	var section2 := Label.new()
	section2.text = "Touch Controls"
	section2.add_theme_color_override("font_color", UIStyles.COLORS.info)
	section2.add_theme_font_size_override("font_size", 14)
	content.add_child(section2)

	content.add_child(_create_toggle_row("touch_controls", "On-screen Controls (touch HUD)", InputManager.is_mobile() if InputManager else false))

	var touch_hint := Label.new()
	touch_hint.text = "COD-style stick (left half), camera look (right half), action cluster with editable layout. Hold ATK to auto-repeat; hold full stick to auto-sprint."
	touch_hint.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	touch_hint.add_theme_font_size_override("font_size", 10)
	touch_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	touch_hint.custom_minimum_size = Vector2(0, 30)
	content.add_child(touch_hint)

	var section3 := Label.new()
	section3.text = "Keybinds"
	section3.add_theme_color_override("font_color", UIStyles.COLORS.info)
	section3.add_theme_font_size_override("font_size", 14)
	content.add_child(section3)

	var keybind_info := Label.new()
	keybind_info.text = "Click a button and press a new key. Conflicts will be highlighted."
	keybind_info.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	keybind_info.add_theme_font_size_override("font_size", 10)
	keybind_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	content.add_child(keybind_info)

	## Movement
	var move_section := Label.new()
	move_section.text = "Movement"
	move_section.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	move_section.add_theme_font_size_override("font_size", 12)
	content.add_child(move_section)

	content.add_child(_create_keybind_row("key_move_forward", "Move Forward", KEY_W, "move_forward"))
	content.add_child(_create_keybind_row("key_move_backward", "Move Backward", KEY_S, "move_backward"))
	content.add_child(_create_keybind_row("key_move_left", "Move Left", KEY_A, "move_left"))
	content.add_child(_create_keybind_row("key_move_right", "Move Right", KEY_D, "move_right"))
	content.add_child(_create_keybind_row("key_jump", "Jump", KEY_SPACE, "jump"))
	content.add_child(_create_keybind_row("key_dodge", "Dodge/Roll", KEY_Q, "dodge"))

	## Combat
	var combat_section := Label.new()
	combat_section.text = "Combat"
	combat_section.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	combat_section.add_theme_font_size_override("font_size", 12)
	content.add_child(combat_section)

	content.add_child(_create_keybind_row("key_attack", "Basic Attack", -1, "attack"))  # -1: mouse-bound
	content.add_child(_create_keybind_row("key_interact", "Interact", KEY_E, "interact"))
	content.add_child(_create_keybind_row("key_ability_1", "Ability 1", KEY_1, "ability_1"))
	content.add_child(_create_keybind_row("key_ability_2", "Ability 2", KEY_2, "ability_2"))
	content.add_child(_create_keybind_row("key_ability_3", "Ability 3", KEY_3, "ability_3"))
	content.add_child(_create_keybind_row("key_ability_4", "Ability 4", KEY_4, "ability_4"))
	content.add_child(_create_keybind_row("key_ability_5", "Ability 5", KEY_5, "ability_5"))
	content.add_child(_create_keybind_row("key_ability_6", "Ability 6", KEY_6, "ability_6"))
	content.add_child(_create_keybind_row("key_ultimate", "Ultimate", KEY_R, "ultimate"))

	## UI
	var ui_section := Label.new()
	ui_section.text = "UI & Menus"
	ui_section.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	ui_section.add_theme_font_size_override("font_size", 12)
	content.add_child(ui_section)

	content.add_child(_create_keybind_row("key_inventory", "Inventory", KEY_I, "inventory"))
	content.add_child(_create_keybind_row("key_character", "Character", KEY_C, "character"))
	content.add_child(_create_keybind_row("key_skills", "Skills", KEY_K, "skills"))
	content.add_child(_create_keybind_row("key_quest_log", "Quest Log", KEY_J, "quest_log"))
	content.add_child(_create_keybind_row("key_map", "Map", KEY_M, "map"))
	content.add_child(_create_keybind_row("key_social", "Social", KEY_O, "social"))
	content.add_child(_create_keybind_row("key_settings", "Settings", KEY_ESCAPE, "settings"))

func _populate_gameplay_settings(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	var section := Label.new()
	section.text = "Gameplay"
	section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section.add_theme_font_size_override("font_size", 14)
	content.add_child(section)

	content.add_child(_create_toggle_row("auto_loot", "Auto-loot Items", false))
	content.add_child(_create_toggle_row("auto_attack", "Auto-target on Attack", true))
	content.add_child(_create_toggle_row("show_minimap", "Show Minimap", true))
	content.add_child(_create_dropdown_row("auto_accept_party", "Auto-accept Party Invites:", ["Never", "Friends Only", "Guild Only", "Always"], 0))
	content.add_child(_create_dropdown_row("auto_accept_guild", "Auto-accept Guild Invites:", ["Never", "Friends Only", "Always"], 0))
	content.add_child(_create_toggle_row("block_trade_requests", "Block Trade Requests", false))
	content.add_child(_create_toggle_row("friend_on_whisper", "Add Friend on Whisper", false))

	var section2 := Label.new()
	section2.text = "Camera"
	section2.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section2.add_theme_font_size_override("font_size", 14)
	content.add_child(section2)

	content.add_child(_create_slider_row("camera_rotation_speed", "Camera Rotation Speed:", 0.5, 3.0, 1.0, 0.1, "%.1f"))
	content.add_child(_create_toggle_row("camera_smoothing", "Camera Smoothing", true))
	content.add_child(_create_slider_row("camera_fov", "Field of View:", 60, 110, 90, 5, "%d"))

	var section3 := Label.new()
	section3.text = "Chat"
	section3.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section3.add_theme_font_size_override("font_size", 14)
	content.add_child(section3)

	content.add_child(_create_slider_row("chat_font_size", "Chat Font Size:", 10, 24, 14, 1, "%d"))
	content.add_child(_create_slider_row("chat_opacity", "Chat Opacity:", 0.3, 1.0, 0.9, 0.1, "%.0f%%"))
	content.add_child(_create_dropdown_row("chat_timestamps", "Chat Timestamps:", ["Off", "12h", "24h"], 2))
	content.add_child(_create_toggle_row("chat_sounds", "Chat Sounds", true))
	content.add_child(_create_toggle_row("profanity_filter", "Profanity Filter", true))

func _populate_accessibility_settings(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	var section := Label.new()
	section.text = "Visual"
	section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section.add_theme_font_size_override("font_size", 14)
	content.add_child(section)

	content.add_child(_create_toggle_row("colorblind_mode", "Colorblind Mode", false, "Applies color correction shader"))
	content.add_child(_create_dropdown_row("colorblind_type", "Colorblind Type:", ["Deuteranopia (Green-blind)", "Protanopia (Red-blind)", "Tritanopia (Blue-blind)"], 0))
	content.add_child(_create_toggle_row("high_contrast", "High Contrast Mode", false, "Increases contrast for readability (WCAG 4.5:1 compliant)"))
	content.add_child(_create_slider_row("ui_text_scale", "UI Text Scale:", 0.8, 1.5, 1.0, 0.05, "%.2fx", "Scales all UI text (0.8x - 1.5x)"))

	var section2 := Label.new()
	section2.text = "Motion & Effects"
	section2.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section2.add_theme_font_size_override("font_size", 14)
	content.add_child(section2)

	content.add_child(_create_toggle_row("reduce_motion", "Reduce Motion", false, "Disables UI transitions, animations, and particle effects"))
	content.add_child(_create_toggle_row("screen_shake", "Screen Shake", true, "Enable camera shake effects"))
	content.add_child(_create_toggle_row("flash_effects", "Flash Effects", true, "Enable screen flash on crit/damage"))
	content.add_child(_create_toggle_row("damage_number_scale", "Scale Damage Numbers", true))

	var section3 := Label.new()
	section3.text = "Audio & Text"
	section3.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section3.add_theme_font_size_override("font_size", 14)
	content.add_child(section3)

	content.add_child(_create_toggle_row("enable_subtitles", "Subtitles", true))
	content.add_child(_create_toggle_row("screen_reader", "Screen Reader Support", false))
	content.add_child(_create_dropdown_row("language", "Language:", ["English", "Spanish", "French", "German", "Russian", "Chinese", "Japanese", "Korean"], 0))

func _populate_social_settings(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	var section := Label.new()
	section.text = "Privacy"
	section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section.add_theme_font_size_override("font_size", 14)
	content.add_child(section)

	content.add_child(_create_toggle_row("show_online_status", "Show Online Status", true))
	content.add_child(_create_toggle_row("allow_friend_requests", "Allow Friend Requests", true))
	content.add_child(_create_toggle_row("allow_guild_invites", "Allow Guild Invites", true))
	content.add_child(_create_toggle_row("receive_whispers", "Receive Whispers", true))
	content.add_child(_create_toggle_row("receive_party_invites", "Receive Party Invites", true))
	content.add_child(_create_toggle_row("show_location_to_friends", "Show Location to Friends", true))
	content.add_child(_create_dropdown_row("profile_visibility", "Profile Visibility:", ["Public", "Friends Only", "Hidden"], 0))

	var section2 := Label.new()
	section2.text = "Chat Channels"
	section2.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section2.add_theme_font_size_override("font_size", 14)
	content.add_child(section2)

	var channels := ["global", "zone", "party", "guild", "whisper", "trade", "system"]
	for ch in channels:
		content.add_child(_create_toggle_row("chat_channel_%s" % ch, "Show %s Channel" % ch.capitalize(), true))

	var section3 := Label.new()
	section3.text = "Notifications"
	section3.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section3.add_theme_font_size_override("font_size", 14)
	content.add_child(section3)

	content.add_child(_create_toggle_row("notify_friend_online", "Friend Online Alerts", true))
	content.add_child(_create_toggle_row("notify_guild_online", "Guild Member Online Alerts", true))
	content.add_child(_create_toggle_row("notify_party_invite", "Party Invite Alerts", true))
	content.add_child(_create_toggle_row("notify_trade_request", "Trade Request Alerts", true))
	content.add_child(_create_toggle_row("notify_quest_complete", "Quest Complete Alerts", true))
	content.add_child(_create_toggle_row("notify_achievement", "Achievement Alerts", true))

func _on_save() -> void:
	if PlayerConfig:
		PlayerConfig.save_account_settings()
		GameLog.info("SettingsPanel: Settings saved to PlayerConfig")
	show_notification("Settings saved")
	close()

func _on_cancel() -> void:
	_load_from_config()
	_apply_current_settings()
	close()

func _on_defaults() -> void:
	if PlayerConfig:
		PlayerConfig.reset_account_settings()
	_load_from_config()
	_apply_current_settings()
	show_notification("Settings reset to defaults")