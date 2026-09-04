## SettingsPanel - Game settings UI
## Audio, video, keybinds, accessibility options
## Wired to PlayerConfig for persistent settings.
extends UIPanel
const UIStyles = preload("res://ui/components/ui_styles.gd")


const UIPanel = preload("res://ui/components/ui_panel.gd")
class_name SettingsPanel

enum Category { GENERAL, AUDIO, VIDEO, CONTROLS, ACCESSIBILITY }

var _current_category: Category = Category.GENERAL
var _tab_buttons: Array = []

var _setting_controls: Dictionary = {}
var _setting_keys: Array = []

func _ready() -> void:
	super._ready()
	set_title("Settings")
	set_panel_size(Vector2(600, 500))
	_setup_ui()
	if PlayerConfig:
		_load_from_config()

func _setup_ui() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main: VBoxContainer = panel.get_node_or_null("Main")
	if not main:
		return
	var tab_bar := HBoxContainer.new()
	tab_bar.custom_minimum_size.y = 40
	main.add_child(tab_bar)
	var categories = [
		{"id": Category.GENERAL, "name": "General"},
		{"id": Category.AUDIO, "name": "Audio"},
		{"id": Category.VIDEO, "name": "Video"},
		{"id": Category.CONTROLS, "name": "Controls"},
		{"id": Category.ACCESSIBILITY, "name": "Access"}
	]
	for cat in categories:
		var btn := Button.new()
		btn.text = cat.name
		btn.toggle_mode = true
		btn.custom_minimum_size.x = 80
		btn.pressed.connect(_on_category_clicked.bind(cat.id))
		_tab_buttons.append(btn)
		tab_bar.add_child(btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	_populate_general_settings(content)
	_populate_audio_settings(content)
	_populate_video_settings(content)
	_populate_control_settings(content)
	_populate_accessibility_settings(content)
	var btn_row := HBoxContainer.new()
	btn_row.custom_minimum_size.y = 40
	main.add_child(btn_row)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_on_save)
	btn_row.add_child(save_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)
	var defaults_btn := Button.new()
	defaults_btn.text = "Defaults"
	defaults_btn.pressed.connect(_on_defaults)
	btn_row.add_child(defaults_btn)

func _on_category_clicked(cat_id: int) -> void:
	_current_category = cat_id

func _create_setting_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 35
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	return row

func _create_slider_row(setting_key: String, label_text: String, min_val: float, max_val: float, default_val: float) -> HBoxContainer:
	var row := _create_setting_row(label_text)
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = default_val
	slider.custom_minimum_size.x = 150
	slider.value_changed.connect(_on_slider_changed.bind(setting_key))
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = str(int(default_val))
	value_label.custom_minimum_size.x = 40
	row.add_child(value_label)
	_setting_controls[setting_key] = {"type": "slider", "control": slider, "label": value_label}
	_setting_keys.append(setting_key)
	return row

func _create_toggle_row(setting_key: String, label_text: String, default_val: bool) -> HBoxContainer:
	var row := _create_setting_row(label_text)
	var toggle := CheckButton.new()
	toggle.button_pressed = default_val
	toggle.toggled.connect(_on_toggle_changed.bind(setting_key))
	row.add_child(toggle)
	_setting_controls[setting_key] = {"type": "toggle", "control": toggle}
	_setting_keys.append(setting_key)
	return row

func _create_dropdown_row(setting_key: String, label_text: String, options: Array, default_idx: int) -> HBoxContainer:
	var row := _create_setting_row(label_text)
	var dropdown := OptionButton.new()
	for opt in options:
		dropdown.add_item(opt)
	dropdown.selected = default_idx
	dropdown.custom_minimum_size.x = 120
	dropdown.item_selected.connect(_on_dropdown_changed.bind(setting_key))
	row.add_child(dropdown)
	_setting_controls[setting_key] = {"type": "dropdown", "control": dropdown, "options": options}
	_setting_keys.append(setting_key)
	return row

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
			"toggle":
				if ctrl is CheckButton:
					ctrl.button_pressed = val
			"dropdown":
				if ctrl is OptionButton:
					ctrl.selected = val

func _on_slider_changed(value: float, key: String) -> void:
	if PlayerConfig:
		PlayerConfig.set_account_setting(key, value, false)
	var info: Dictionary = _setting_controls.get(key, {})
	var lbl = info.get("label")
	if lbl is Label:
		lbl.text = str(int(value))

func _on_toggle_changed(value: bool, key: String) -> void:
	if PlayerConfig:
		PlayerConfig.set_account_setting(key, value, false)

func _on_dropdown_changed(index: int, key: String) -> void:
	if PlayerConfig:
		PlayerConfig.set_account_setting(key, index, false)

func _populate_general_settings(parent: VBoxContainer) -> void:
	var section := Label.new()
	section.text = "General Settings"
	section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	parent.add_child(section)
	parent.add_child(_create_toggle_row("auto_loot", "Auto-loot items", false))
	parent.add_child(_create_toggle_row("show_damage_numbers", "Show damage numbers", true))
	parent.add_child(_create_toggle_row("player_nameplates", "Show name plates", true))
	parent.add_child(_create_dropdown_row("language", "Language:", ["English"], 0))
	parent.add_child(_create_dropdown_row("chat_timestamps", "Chat timestamps:", ["Off", "12h", "24h"], 0))

func _populate_audio_settings(parent: VBoxContainer) -> void:
	var section := Label.new()
	section.text = "Audio Settings"
	section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	parent.add_child(section)
	parent.add_child(_create_slider_row("master_volume", "Master Volume:", 0, 1, 0.8))
	parent.add_child(_create_slider_row("music_volume", "Music Volume:", 0, 1, 0.7))
	parent.add_child(_create_slider_row("sfx_volume", "SFX Volume:", 0, 1, 0.8))
	parent.add_child(_create_slider_row("voice_volume", "Voice Volume:", 0, 1, 0.8))
	parent.add_child(_create_toggle_row("ui_sounds", "Mute on focus loss", false))
	parent.add_child(_create_toggle_row("enable_voice_chat", "Enable 3D audio", true))

func _populate_video_settings(parent: VBoxContainer) -> void:
	var section := Label.new()
	section.text = "Video Settings"
	section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	parent.add_child(section)
	parent.add_child(_create_dropdown_row("resolution", "Resolution:", ["1920x1080", "1600x900", "1280x720", "Windowed"], 0))
	parent.add_child(_create_dropdown_row("graphics_quality", "Quality:", ["Low", "Medium", "High", "Ultra"], 2))
	parent.add_child(_create_dropdown_row("antialiasing", "Anti-aliasing:", ["Off", "2x", "4x", "8x"], 1))
	parent.add_child(_create_toggle_row("fullscreen", "Fullscreen", false))
	parent.add_child(_create_toggle_row("vsync_enabled", "VSync", true))
	parent.add_child(_create_toggle_row("bloom_effects", "Bloom effects", true))
	parent.add_child(_create_toggle_row("particle_effects", "Particle effects", true))

func _populate_control_settings(parent: VBoxContainer) -> void:
	var section := Label.new()
	section.text = "Control Settings"
	section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	parent.add_child(section)
	parent.add_child(_create_dropdown_row("mouse_sensitivity", "Mouse sensitivity:", ["Very Low", "Low", "Medium", "High", "Very High"], 2))
	parent.add_child(_create_dropdown_row("controller_sensitivity", "Controller sensitivity:", ["Very Low", "Low", "Medium", "High", "Very High"], 2))
	parent.add_child(_create_toggle_row("invert_y_axis", "Invert Y axis", false))
	parent.add_child(_create_toggle_row("auto_attack", "Auto-target on attack", true))
	parent.add_child(_create_dropdown_row("camera_mode", "Camera mode:", ["Follow", "Action"], 0))
	var keybind_section := Label.new()
	keybind_section.text = "Keybinds"
	keybind_section.add_theme_color_override("font_color", UIStyles.COLORS.info)
	parent.add_child(keybind_section)
	var keybinds = [
		"Move Forward: W",
		"Move Backward: S",
		"Move Left: A",
		"Move Right: D",
		"Jump: Space",
		"Dodge: Q",
		"Interact: E"
	]
	for kb in keybinds:
		var row := _create_setting_row(kb)
		var rebind_btn := Button.new()
		rebind_btn.text = "[Rebind]"
		rebind_btn.custom_minimum_size.x = 80
		row.add_child(rebind_btn)
		parent.add_child(row)

func _populate_accessibility_settings(parent: VBoxContainer) -> void:
	var section := Label.new()
	section.text = "Accessibility"
	section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	parent.add_child(section)
	parent.add_child(_create_toggle_row("colorblind_mode", "Colorblind mode", false))
	parent.add_child(_create_dropdown_row("colorblind_type", "Colorblind type:", ["Deuteranopia", "Protanopia", "Tritanopia"], 0))
	parent.add_child(_create_toggle_row("large_text", "Large text", false))
	parent.add_child(_create_toggle_row("screen_shake", "Screen shake", true))
	parent.add_child(_create_toggle_row("flash_effects", "Flash effects", true))
	parent.add_child(_create_slider_row("ui_scale", "UI Scale:", 0.5, 2.0, 1.0))
	parent.add_child(_create_toggle_row("reduce_motion", "Reduce motion", false))
	parent.add_child(_create_toggle_row("enable_subtitles", "Subtitles", true))
	parent.add_child(_create_toggle_row("screen_reader", "Screen reader support", false))

func _on_save() -> void:
	if PlayerConfig:
		PlayerConfig.save_account_settings()
	show_notification("Settings saved")
	close()

func _on_cancel() -> void:
	close()

func _on_defaults() -> void:
	if PlayerConfig:
		PlayerConfig.reset_account_settings()
	show_notification("Settings reset to defaults")
	close()
