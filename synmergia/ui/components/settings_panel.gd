## SettingsPanel - Game settings UI
## Audio, video, keybinds, accessibility options
class_name SettingsPanel
extends UIPanel

## Settings categories
enum Category { GENERAL, AUDIO, VIDEO, CONTROLS, ACCESSIBILITY }

var _current_category: Category = Category.GENERAL
var _tab_buttons: Array = []

func _ready() -> void:
super._ready()
set_title("Settings")
set_size(Vector2(600, 500))
_setup_ui()

func _setup_ui() -> void:
var panel := get_panel()
if not panel:
return

var main: VBoxContainer = panel.get_node_or_null("Main")
if not main:
return

# Tab bar
var tab_bar := HBoxContainer.new()
tab_bar.custom_minimum_size.y = 40
main.add_child(tab_bar)

var categories := [
{Category.GENERAL, "General"},
{Category.AUDIO, "Audio"},
{Category.VIDEO, "Video"},
{Category.CONTROLS, "Controls"},
{Category.ACCESSIBILITY, "Access"}
]

for cat in categories:
var btn := Button.new()
btn.text = cat.name
btn.toggle_mode = true
btn.custom_minimum_size.x = 80
btn.pressed.connect(_on_category_clicked.bind(cat.id))
_tab_buttons.append(btn)
tab_bar.add_child(btn)

# Content area
var scroll := ScrollContainer.new()
scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
main.add_child(scroll)

var content := VBoxContainer.new()
content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
scroll.add_child(content)

# Populate with settings
_populate_general_settings(content)
_populate_audio_settings(content)
_populate_video_settings(content)
_populate_control_settings(content)
_populate_accessibility_settings(content)

# Action buttons
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

var label := Label.new()
label.text = label_text
label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
row.add_child(label)

return row

func _create_slider_row(label_text: String, min_val: float, max_val: float, default_val: float) -> HBoxContainer:
var row := _create_setting_row(label_text)

var slider := HSlider.new()
slider.min_value = min_val
slider.max_value = max_val
slider.value = default_val
slider.custom_minimum_size.x = 150
row.add_child(slider)

var value_label := Label.new()
value_label.text = str(int(default_val))
value_label.custom_minimum_size.x = 40
row.add_child(value_label)

return row

func _create_toggle_row(label_text: String, default_val: bool) -> HBoxContainer:
var row := _create_setting_row(label_text)

var toggle := CheckButton.new()
toggle.button_pressed = default_val
row.add_child(toggle)

return row

func _create_dropdown_row(label_text: String, options: Array, default_idx: int) -> HBoxContainer:
var row := _create_setting_row(label_text)

var dropdown := OptionButton.new()
for opt in options:
dropdown.add_item(opt)
dropdown.selected = default_idx
dropdown.custom_minimum_size.x = 120
row.add_child(dropdown)

return row

func _populate_general_settings(parent: VBoxContainer) -> void:
var section := Label.new()
section.text = "General Settings"
section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
parent.add_child(section)

parent.add_child(_create_toggle_row("Auto-loot items", false))
parent.add_child(_create_toggle_row("Show damage numbers", true))
parent.add_child(_create_toggle_row("Show name plates", true))
parent.add_child(_create_dropdown_row("Language:", ["English"], 0))
parent.add_child(_create_dropdown_row("Chat timestamps:", ["Off", "12h", "24h"], 0))

func _populate_audio_settings(parent: VBoxContainer) -> void:
var section := Label.new()
section.text = "Audio Settings"
section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
parent.add_child(section)

parent.add_child(_create_slider_row("Master Volume:", 0, 100, 80))
parent.add_child(_create_slider_row("Music Volume:", 0, 100, 70))
parent.add_child(_create_slider_row("SFX Volume:", 0, 100, 80))
parent.add_child(_create_slider_row("Voice Volume:", 0, 100, 80))
parent.add_child(_create_toggle_row("Mute on focus loss", true))
parent.add_child(_create_toggle_row("Enable 3D audio", true))

func _populate_video_settings(parent: VBoxContainer) -> void:
var section := Label.new()
section.text = "Video Settings"
section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
parent.add_child(section)

parent.add_child(_create_dropdown_row("Resolution:", ["1920x1080", "1600x900", "1280x720", "Windowed"], 0))
parent.add_child(_create_dropdown_row("Quality:", ["Low", "Medium", "High", "Ultra"], 2))
parent.add_child(_create_dropdown_row("Anti-aliasing:", ["Off", "2x", "4x", "8x"], 1))
parent.add_child(_create_toggle_row("Fullscreen", false))
parent.add_child(_create_toggle_row("VSync", true))
parent.add_child(_create_toggle_row("Bloom effects", true))
parent.add_child(_create_toggle_row("Particle effects", true))
parent.add_child(_create_toggle_row("Shadow quality:", true))

func _populate_control_settings(parent: VBoxContainer) -> void:
var section := Label.new()
section.text = "Control Settings"
section.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
parent.add_child(section)

parent.add_child(_create_dropdown_row("Mouse sensitivity:", ["Very Low", "Low", "Medium", "High", "Very High"], 2))
parent.add_child(_create_dropdown_row("Controller sensitivity:", ["Very Low", "Low", "Medium", "High", "Very High"], 2))
parent.add_child(_create_toggle_row("Invert Y axis", false))
parent.add_child(_create_toggle_row("Auto-target on attack", true))
parent.add_child(_create_toggle_row("Show combat text", true))
parent.add_child(_create_dropdown_row("Camera mode:", ["Follow", "Action"], 0))

var keybind_section := Label.new()
keybind_section.text = "Keybinds"
keybind_section.add_theme_color_override("font_color", UIStyles.COLORS.info)
parent.add_child(keybind_section)

var keybinds := [
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

parent.add_child(_create_toggle_row("Colorblind mode", false))
parent.add_child(_create_dropdown_row("Colorblind type:", ["Deuteranopia", "Protanopia", "Tritanopia"], 0))
parent.add_child(_create_toggle_row("Large text", false))
parent.add_child(_create_toggle_row("Screen shake", true))
parent.add_child(_create_toggle_row("Flash effects", true))
parent.add_child(_create_slider_row("UI Scale:", 0.5, 2.0, 1.0))
parent.add_child(_create_toggle_row("Reduce motion", false))
parent.add_child(_create_toggle_row("Subtitles", true))
parent.add_child(_create_toggle_row("Screen reader support", false))

func _on_save() -> void:
# TODO: Save settings to config
NotificationService.send_to_local_player("Settings saved", NotificationService.NotificationType.SUCCESS)
close()

func _on_cancel() -> void:
close()

func _on_defaults() -> void:
NotificationService.send_to_local_player("Settings reset to defaults", NotificationService.NotificationType.INFO)
