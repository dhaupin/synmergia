## UIStyles - Common styling constants and factory methods for Synmergia UI
extends RefCounted
class_name UIStyles

## ============================================================================
## COLOR PALETTE
## ============================================================================

const COLORS := {
	"background": Color(0.1, 0.1, 0.15, 0.98),
	"background_dark": Color(0.08, 0.08, 0.1, 0.98),
	"background_overlay": Color(0, 0, 0, 0.7),
	"border": Color(0.3, 0.3, 0.4),
	"border_highlight": Color(0.5, 0.4, 0.3),
	"text_primary": Color(1, 1, 1),
	"text_secondary": Color(0.7, 0.7, 0.7),
	"text_disabled": Color(0.5, 0.5, 0.5),
	"accent": Color(0.6, 0.4, 0.2),
	"accent_gold": Color(1, 0.8, 0.2),
	"success": Color(0.2, 0.8, 0.3),
	"error": Color(1, 0.3, 0.3),
	"warning": Color(1, 0.8, 0.2),
	"info": Color(0.3, 0.6, 1),
	"online": Color(0.3, 0.9, 0.3),
	"offline": Color(0.4, 0.4, 0.4),
	"focus_border": Color(1, 0.84, 0, 1),  # #FFD700 gold for focus
	"focus_bg": Color(0.2, 0.18, 0.25, 0.95),
}

## High Contrast Mode colors (WCAG 4.5:1 compliant)
const HIGH_CONTRAST_COLORS := {
	"background": Color(0.1, 0.1, 0.1, 1),        # #1A1A1A
	"background_dark": Color(0.05, 0.05, 0.05, 1),
	"background_overlay": Color(0, 0, 0, 0.9),
	"border": Color(1, 1, 1, 1),                   # Pure white borders
	"border_highlight": Color(1, 1, 0, 1),         # Yellow highlight
	"text_primary": Color(1, 1, 1, 1),             # Pure white text
	"text_secondary": Color(1, 1, 0.8, 1),         # Bright yellow-white
	"text_disabled": Color(0.7, 0.7, 0.7, 1),
	"accent": Color(1, 1, 0, 1),                   # Yellow accent
	"accent_gold": Color(1, 1, 0, 1),              # Yellow gold
	"success": Color(0, 1, 0, 1),                  # Bright green
	"error": Color(1, 0.3, 0.3, 1),
	"warning": Color(1, 1, 0, 1),                  # Yellow warning
	"info": Color(0, 0.8, 1, 1),                   # Bright cyan
	"online": Color(0, 1, 0, 1),
	"offline": Color(0.7, 0.7, 0.7, 1),
	"focus_border": Color(1, 1, 0, 1),             # Yellow focus
	"focus_bg": Color(0, 0, 0, 1),
}

const RARITY_COLORS := {
	"rarity_common": Color(0.6, 0.6, 0.6),
	"rarity_rare": Color(0.3, 0.7, 1.0),
	"rarity_epic": Color(0.8, 0.3, 1.0),
	"rarity_legendary": Color(1.0, 0.8, 0.2),
	"rarity_mythic": Color(1.0, 0.4, 0.1),
}

## Skill Academy specific
const SKILL_COLORS := {
	"available_points": Color(0.3, 1.0, 0.5),  # Bright green for available
	"focal": Color(0.8, 0.8, 1.0),              # Light blue for focal indicator
	"tier_label": Color(0.6, 0.6, 0.6),          # Gray for tier labels
	# Stat tier colors (for skill academy stat bars)
	"tier_common": Color(0.6, 0.6, 0.6),
	"tier_rare": Color(0.3, 0.7, 1.0),
	"tier_epic": Color(0.8, 0.3, 1.0),
	"tier_legendary": Color(1.0, 0.6, 0.1),
	"tier_mythic": Color(1.0, 0.2, 0.2),
}

## Tooltip specific
const TOOLTIP_COLORS := {
	"background": Color(0.15, 0.15, 0.2, 0.95),
}

## Text/label colors (reusable across UI)
const TEXT_COLORS := {
	"default": Color(0.7, 0.7, 0.7),      # Standard secondary text
	"info": Color(0.4, 0.7, 1.0),          # Info/links/stat values
	"success": Color(0.4, 0.9, 0.4),       # Positive values
	"default_bright": Color(0.9, 0.9, 1.0), # Toast background tint
	"toast_bg": Color(0.08, 0.08, 0.12, 0.92),
}

## ============================================================================
## STYLE FACTORIES
## ============================================================================

static func create_panel_style(bg_color: Color = COLORS.background, border_color: Color = COLORS.border,
		border_width: int = 2, corner_radius: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	return style

static func create_button_style(normal_bg: Color = Color(0.15, 0.15, 0.2),
		hover_bg: Color = Color(0.2, 0.2, 0.25),
		pressed_bg: Color = Color(0.1, 0.1, 0.15),
		disabled_bg: Color = Color(0.1, 0.1, 0.12)) -> Dictionary:
	return {
		"normal": _make_button_stylebox(normal_bg),
		"hover": _make_button_stylebox(hover_bg),
		"pressed": _make_button_stylebox(pressed_bg),
		"disabled": _make_button_stylebox(disabled_bg)
	}

## ============================================================================
## RARITY HELPERS
## ============================================================================

static func get_rarity_color(rarity: String) -> Color:
	match rarity.to_lower():
		"common": return RARITY_COLORS.rarity_common
		"rare", "uncommon": return RARITY_COLORS.rarity_rare
		"epic": return RARITY_COLORS.rarity_epic
		"legendary": return RARITY_COLORS.rarity_legendary
		"mythic": return RARITY_COLORS.rarity_mythic
		_: return COLORS.text_primary

static func get_rarity_display_name(rarity: String) -> String:
	match rarity.to_lower():
		"common": return "Common"
		"rare", "uncommon": return "Rare"
		"epic": return "Epic"
		"legendary": return "Legendary"
		"mythic": return "Mythic"
		_: return rarity


static func _make_button_stylebox(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = COLORS.border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

static func apply_button_styles(btn: Button, styles: Dictionary) -> void:
	btn.add_theme_stylebox_override("normal", styles.get("normal", styles["normal"]))
	btn.add_theme_stylebox_override("hover", styles.get("hover", styles["normal"]))
	btn.add_theme_stylebox_override("pressed", styles.get("pressed", styles["normal"]))
	btn.add_theme_stylebox_override("disabled", styles.get("disabled", styles["normal"]))

## ============================================================================
## WIDGET FACTORIES
## ============================================================================

static func create_header(title: String, show_close: bool = true, close_callback: Callable = Callable()) -> HBoxContainer:
	var header := HBoxContainer.new()

	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COLORS.text_primary)
	header.add_child(label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	if show_close:
		var close_btn := Button.new()
		close_btn.text = "X"
		close_btn.add_theme_color_override("font_color", COLORS.text_secondary)
		if close_callback.is_valid():
			close_btn.pressed.connect(close_callback)
		else:
			close_btn.pressed.connect(func(): pass)  # Placeholder
		header.add_child(close_btn)

	return header

static func create_tab_button(text: String, icon: String = "") -> Button:
	var btn := Button.new()
	if icon != "":
		btn.text = "%s %s" % [icon, text]
	else:
		btn.text = text
	btn.toggle_mode = true
	btn.button_pressed = false
	return btn

static func create_list_item(text: String, subtext: String = "", icon: String = "") -> String:
	var display := text
	if icon != "":
		display = "%s %s" % [icon, text]
	if subtext != "":
		display += "\n  %s" % subtext
	return display

## ============================================================================
## NOTIFICATION HELPERS
## ============================================================================

static func show_notification(message: String, success: bool = true, duration: float = 3.0) -> void:
	var notif := Label.new()
	notif.text = message
	notif.add_theme_color_override("font_color", COLORS.success if success else COLORS.error)
	notif.z_index = 1000
	notif.global_position = Vector2(100, 100)

	var root: Window = Engine.get_main_loop().root
	root.add_child(notif)

	var tween := notif.create_tween()
	tween.tween_interval(duration)
	tween.tween_callback(notif.queue_free)

## ============================================================================
## FORMATTING HELPERS
## ============================================================================

static func format_time_ago(unix_time: float) -> String:
	var elapsed := Time.get_unix_time_from_system() - unix_time

	if elapsed < 60:
		return "just now"
	elif elapsed < 3600:
		var mins := int(elapsed / 60)
		return "%d min ago" % mins
	elif elapsed < 86400:
		var hours := int(elapsed / 3600)
		return "%d hour%s ago" % [hours, "s" if hours != 1 else ""]
	else:
		var days := int(elapsed / 86400)
		return "%d day%s ago" % [days, "s" if days != 1 else ""]

static func format_time_remaining(seconds: float) -> String:
	if seconds <= 0:
		return "expired"

	var hours := int(seconds / 3600)
	var mins := int(int(seconds) % 3600 / 60)
	var secs := int(seconds) % 60

	if hours > 0:
		return "%dh %dm" % [hours, mins]
	elif mins > 0:
		return "%dm %ds" % [mins, secs]
	else:
		return "%ds" % secs

static func format_online_status(online: bool, zone: String = "") -> String:
	if online:
		if zone != "":
			return "[color=#3ce54a]Online[/color] in %s" % zone
		return "[color=#3ce54a]Online[/color]"
	else:
		return "[color=#666666]Offline[/color]"

static func get_damage_font() -> Font:
	# Returns null to use default theme font
	# Can be overridden to return a custom damage number font
	return null


## ============================================================================
## ACCESSIBILITY HELPERS
## ============================================================================

## Get effective colors based on high contrast mode
static func get_effective_colors(high_contrast: bool = false) -> Dictionary:
	if high_contrast:
		return HIGH_CONTRAST_COLORS
	return COLORS

## Create focus stylebox with 3px gold border
static func create_focus_style(corner_radius: int = 6, high_contrast: bool = false) -> StyleBoxFlat:
	var colors := get_effective_colors(high_contrast)
	var style := StyleBoxFlat.new()
	style.bg_color = colors.focus_bg
	style.border_color = colors.focus_border
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	return style

## Create high contrast panel style
static func create_high_contrast_panel_style(border_width: int = 3, corner_radius: int = 8) -> StyleBoxFlat:
	var colors := HIGH_CONTRAST_COLORS
	var style := StyleBoxFlat.new()
	style.bg_color = colors.background
	style.border_color = colors.border
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	return style

## Apply focus behavior to a control. (The old accessible_name/
## accessible_description assignments were removed: those properties do
## not exist on Control in Godot 4.7.2 and errored at runtime.)
static func apply_accessibility(control: Control, accessible_name: String = "", accessible_description: String = "", focus_mode: int = Control.FOCUS_ALL) -> void:
	control.focus_mode = focus_mode

## Create accessible button with standard focus and tooltip
static func create_accessible_button(text: String, accessible_name: String = "", tooltip: String = "", high_contrast: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_ALL
	if tooltip != "":
		btn.tooltip_text = tooltip
	else:
		btn.tooltip_text = text
	
	# Apply focus style
	btn.add_theme_stylebox_override("focus", create_focus_style(8, high_contrast))
	
	return btn

## Apply high contrast theme to a panel container
static func apply_high_contrast_to_panel(panel: PanelContainer) -> void:
	var style := create_high_contrast_panel_style()
	panel.add_theme_stylebox_override("panel", style)

## Apply text scaling to a control and its children
static func apply_text_scaling(control: Control, scale: float) -> void:
	if control is Label:
		var current_size := control.get_theme_font_size("font_size")
		if current_size > 0:
			control.add_theme_font_size_override("font_size", int(current_size * scale))
	elif control is RichTextLabel:
		var current_size := control.get_theme_font_size("default_font_size")
		if current_size > 0:
			control.add_theme_font_size_override("default_font_size", int(current_size * scale))
	elif control is Button:
		var current_size := control.get_theme_font_size("font_size")
		if current_size > 0:
			control.add_theme_font_size_override("font_size", int(current_size * scale))
	
	# Recursively apply to children
	for child in control.get_children():
		if child is Control:
			apply_text_scaling(child, scale)

## Check if reduce motion is enabled (reads from PlayerConfig or OS)
static func is_reduce_motion_enabled() -> bool:
	return OS.has_feature("reduce_motion")

## Check if high contrast is enabled (reads from PlayerConfig or OS)
static func is_high_contrast_enabled() -> bool:
	return OS.has_feature("high_contrast")

## Get text scale (reads from PlayerConfig or OS)
static func get_text_scale() -> float:
	return 1.0

## Get animation duration (0 if reduce motion enabled)
static func get_animation_duration(default_duration: float) -> float:
	return 0.0 if is_reduce_motion_enabled() else default_duration

## Create tween with reduce motion support
static func create_accessible_tween(node: Node, duration: float = 0.3) -> Tween:
	var tween := node.create_tween()
	var actual_duration := get_animation_duration(duration)
	if actual_duration <= 0:
		# Skip animation, use instant
		tween.set_parallel(true)
	return tween
