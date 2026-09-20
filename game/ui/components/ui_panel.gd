## UIPanel - Base class for Synmergia UI panels with common functionality
extends Control
class_name UIPanel

const UIStyles = preload("res://ui/components/ui_styles.gd")

## Panel state
var _is_open: bool = false
var _player_id: String = ""
var _panel_title: String = ""

## Accessibility state
var _high_contrast: bool = false
var _text_scale: float = 1.0
var _reduce_motion: bool = false

## Signals
signal panel_opened()
signal panel_closed()

## ============================================================================
## LIFECYCLE
## ============================================================================

func _ready() -> void:
	visible = false
	_load_accessibility_settings()
	_setup_overlay()
	_setup_panel()
	_setup_header()
	_setup_content()
	_apply_accessibility()
	_apply_visual_settings()

## Load accessibility settings from PlayerConfig
func _load_accessibility_settings() -> void:
	var pc = get_node_or_null("/root/PlayerConfig")
	if pc:
		_high_contrast = pc.get_account_setting("high_contrast", false)
		_text_scale = pc.get_account_setting("ui_scale", 1.0)
		_reduce_motion = pc.get_account_setting("reduce_motion", false)

## Override these in subclasses
func _setup_panel() -> void:
	pass

func _setup_header() -> void:
	pass

func _setup_content() -> void:
	pass

## ============================================================================
## ACCESSIBILITY
## ============================================================================

## Set the panel title for screen reader announcements
func set_panel_title(title: String) -> void:
	_panel_title = title
	_apply_accessibility()

## Get accessibility properties for screen readers
func get_accessibility_info() -> Dictionary:
	return {
		"role": "dialog",
		"label": _panel_title,
		"description": "Use Tab to navigate, Enter to activate, Escape to close"
	}

## Apply accessibility properties to the panel
func _apply_accessibility() -> void:
	# Enable focus for keyboard navigation
	focus_mode = Control.FOCUS_ALL
	
	# Set tooltip for mouse hover accessibility
	if has_node("Panel"):
		var panel := get_node("Panel")
		if panel is PanelContainer:
			panel.tooltip_text = _panel_title if not _panel_title.is_empty() else name
			panel.focus_mode = Control.FOCUS_ALL

## Apply visual settings (high contrast, text scale)
func _apply_visual_settings() -> void:
	if not has_node("Panel"):
		return
	var panel := get_node("Panel")
	if panel is PanelContainer:
		_apply_high_contrast_to_panel(panel)
		_apply_text_scaling_to_panel(panel)

## Apply high contrast theme to panel
func _apply_high_contrast_to_panel(panel: PanelContainer) -> void:
	if _high_contrast:
		var style := UIStyles.create_high_contrast_panel_style()
		panel.add_theme_stylebox_override("panel", style)
		
		# Apply to all child buttons and interactive elements
		_apply_high_contrast_recursive(panel)
	else:
		# Reset to default style
		var style := UIStyles.create_panel_style()
		panel.add_theme_stylebox_override("panel", style)

## Recursively apply high contrast to interactive children
func _apply_high_contrast_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			var focus_style := UIStyles.create_focus_style(8, true)
			child.add_theme_stylebox_override("focus", focus_style)
			child.add_theme_color_override("font_color", UIStyles.HIGH_CONTRAST_COLORS.text_primary)
			child.add_theme_color_override("font_focus_color", UIStyles.HIGH_CONTRAST_COLORS.accent_gold)
		elif child is HSlider or child is VSlider:
			var focus_style := UIStyles.create_focus_style(4, true)
			child.add_theme_stylebox_override("focus", focus_style)
		elif child is OptionButton:
			var focus_style := UIStyles.create_focus_style(4, true)
			child.add_theme_stylebox_override("focus", focus_style)
			child.add_theme_color_override("font_color", UIStyles.HIGH_CONTRAST_COLORS.text_primary)
		elif child is CheckButton:
			var focus_style := UIStyles.create_focus_style(4, true)
			child.add_theme_stylebox_override("focus", focus_style)
		elif child is LineEdit:
			var focus_style := UIStyles.create_focus_style(4, true)
			child.add_theme_stylebox_override("focus", focus_style)
			child.add_theme_color_override("font_color", UIStyles.HIGH_CONTRAST_COLORS.text_primary)
		elif child is ProgressBar:
			child.add_theme_color_override("fill", UIStyles.HIGH_CONTRAST_COLORS.success)
			child.add_theme_color_override("background", UIStyles.HIGH_CONTRAST_COLORS.background_dark)
		elif child is PanelContainer:
			_apply_high_contrast_recursive(child)
		elif child is Container:
			_apply_high_contrast_recursive(child)

## Apply text scaling to panel and children
func _apply_text_scaling_to_panel(panel: PanelContainer) -> void:
	if _text_scale != 1.0:
		UIStyles.apply_text_scaling(panel, _text_scale)

## Update accessibility settings from external source (e.g., SettingsPanel)
func update_accessibility_settings(high_contrast: bool, text_scale: float, reduce_motion: bool) -> void:
	_high_contrast = high_contrast
	_text_scale = text_scale
	_reduce_motion = reduce_motion
	_apply_visual_settings()

## ============================================================================
## ACCESSIBILITY HELPERS
## ============================================================================

## Create an accessible button with proper focus and tooltips
func create_accessible_button(text: String, tooltip: String = "") -> Button:
	var btn := UIStyles.create_accessible_button(text, text, tooltip, _high_contrast)
	return btn

## Create a canonical close button (X) for panel headers
func create_close_button() -> Button:
	var btn := Button.new()
	btn.text = "X"
	btn.custom_minimum_size = Vector2(36, 36)
	btn.focus_mode = Control.FOCUS_ALL
	btn.tooltip_text = "Close (ESC)"
	# Apply focus style
	btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style(8, _high_contrast))
	
	btn.pressed.connect(close)
	return btn

## Create accessible slider
func create_accessible_slider(min_val: float, max_val: float, default_val: float, step: float = 0.01, accessible_name: String = "", accessible_description: String = "") -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = default_val
	slider.step = step
	slider.focus_mode = Control.FOCUS_ALL
	# Accessibility properties - set if available in this Godot version
	# if accessible_name != "":
	# if accessible_description != "":
	slider.add_theme_stylebox_override("focus", UIStyles.create_focus_style(4, _high_contrast))
	return slider

## Create accessible dropdown (OptionButton)
func create_accessible_dropdown(options: Array, default_idx: int, accessible_name: String = "", accessible_description: String = "") -> OptionButton:
	var dropdown := OptionButton.new()
	for opt in options:
		dropdown.add_item(opt)
	dropdown.selected = default_idx
	dropdown.focus_mode = Control.FOCUS_ALL
	# if accessible_name != "":
	# if accessible_description != "":
	dropdown.add_theme_stylebox_override("focus", UIStyles.create_focus_style(4, _high_contrast))
	return dropdown

## Create accessible checkbox (CheckButton)
func create_accessible_checkbox(default_val: bool, accessible_name: String = "", accessible_description: String = "") -> CheckButton:
	var checkbox := CheckButton.new()
	checkbox.button_pressed = default_val
	checkbox.focus_mode = Control.FOCUS_ALL
	# Accessibility properties - set if available in this Godot version
	# if accessible_name != "":
	# if accessible_description != "":
	checkbox.add_theme_stylebox_override("focus", UIStyles.create_focus_style(4, _high_contrast))
	return checkbox

## Create accessible text input (LineEdit)
func create_accessible_line_edit(placeholder: String = "", accessible_name: String = "", accessible_description: String = "") -> LineEdit:
	var line_edit := LineEdit.new()
	line_edit.placeholder_text = placeholder
	line_edit.focus_mode = Control.FOCUS_ALL
	# Accessibility properties - set if available in this Godot version
	# if accessible_name != "":
	# if accessible_description != "":
	line_edit.add_theme_stylebox_override("focus", UIStyles.create_focus_style(4, _high_contrast))
	return line_edit

## Announce a change for screen readers (logs for now, extensible)
func announce_for_screen_reader(message: String) -> void:
	# Emit signal that can be connected to a screen reader service
	# For now, log to console for debug
	# print removed: print("[A11Y] " + message)
	pass

## Get animation duration respecting reduce motion
func get_animation_duration(default_duration: float) -> float:
	return UIStyles.get_animation_duration(default_duration)

## Create tween with reduce motion support
func create_accessible_tween(duration: float = 0.3) -> Tween:
	return UIStyles.create_accessible_tween(self, duration)

## ============================================================================
## DISTANCE-BASED CLOSE (for interactable panels like dialogs, shops)
## ============================================================================

var _max_interact_distance: float = 5.0  # Configurable per panel

## Set max distance for auto-close when player moves away
func set_max_interact_distance(distance: float) -> void:
	_max_interact_distance = distance

## Check if player is within interact distance - call in _process()
## Override in subclasses that need distance-based auto-close
func check_interact_distance(player_pos: Vector3, target_pos: Vector3) -> bool:
	var dist: float = player_pos.distance_to(target_pos)
	if dist > _max_interact_distance:
		close()
		return false
	return true

## Canonical distance calculation - use Vector3.distance_to() for 3D
## For planar (2D) checks, use position.project(Vector3.UP).distance_to()

## ============================================================================
## PLAYER HELPERS
## ============================================================================

## Canonical way to get the local player node
## Used for distance checks, position lookups, etc.
func _get_local_player() -> Node:
	var pm = get_node_or_null("/root/PlayerManager")
	if pm and pm.has_method("get_local_player"):
		return pm.get_local_player()
	return null

## ============================================================================
## PROGRESS / LOADING HELPERS
## ============================================================================

## Create a canonical progress bar with UIStyles colors
func create_progress_bar(width: float = 200, height: float = 8, show_percentage: bool = false) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, height)
	bar.show_percentage = show_percentage
	bar.max_value = 100
	bar.value = 0
	# Style the bar using UIStyles
	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.border_color = UIStyles.COLORS.border
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("background", style)
	bar.focus_mode = Control.FOCUS_ALL
	bar.add_theme_stylebox_override("focus", UIStyles.create_focus_style(4, _high_contrast))
	return bar

## Create a loading spinner (rotating texture simulation via animated label)
func create_loading_indicator() -> Label:
	var indicator := Label.new()
	indicator.text = "..."
	indicator.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	return indicator

## ============================================================================
## BASE SETUP
## ============================================================================

func _setup_overlay() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.gui_input.connect(_on_overlay_click)
	overlay.name = "Overlay"
	add_child(overlay)

func _setup_base_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(400, 500)

	var style := UIStyles.create_panel_style()
	panel.add_theme_stylebox_override("panel", style)
	panel.name = "Panel"
	panel.focus_mode = Control.FOCUS_ALL
	add_child(panel)

	return panel

func _on_overlay_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()

## Canonical close() - override in subclasses for custom cleanup
## Close mechanisms:
##   1. ESC key -> HudHotkeys -> _handle_escape() -> MenuManager -> close()
##   2. X button -> pressed.connect(close)
##   3. Click overlay -> _on_overlay_click()
##   4. Panel title close button (X) -> close()
##   5. Distance check -> close() (for interactable panels)
##   6. Timed auto-close -> close() (for notifications/toasts)

## Called by HudHotkeys for TAB focus cycling when panel is open.
func _on_tab_pressed(shift: bool) -> void:
	_cycle_focus()

## Default focus cycling - find next focusable control in panel
func _cycle_focus() -> void:
	if not has_node("Panel"):
		return

	var panel := get_node("Panel")
	var focusable := _get_focusable_children(panel)
	if focusable.is_empty():
		return

	var current := panel.get_node_or_null(".")
	var idx := 0
	if current != null:
		for i in range(focusable.size()):
			if focusable[i] == current or (current is Control and focusable[i] == current):
				idx = i + (1 if not Input.is_key_pressed(KEY_SHIFT) else -1)
				idx = posmod(idx, focusable.size())
				break

	focusable[idx].grab_focus()

## Collect all focusable children recursively
func _get_focusable_children(node: Node) -> Array[Control]:
	var result: Array[Control] = []
	for child in node.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			result.append(child)
		if child is Container:
			result.append_array(_get_focusable_children(child))
	return result

## ============================================================================
## OPEN/CLOSE
## ============================================================================

func open(player_id: String) -> void:
	_player_id = player_id
	_is_open = true
	visible = true
	_on_open()
	panel_opened.emit()
	# Focus first focusable element
	call_deferred("_focus_first_element")
	# print removed: print("UIPanel: Opened %s" % name)

func _focus_first_element() -> void:
	if not has_node("Panel"):
		return
	var panel := get_node("Panel")
	var focusable := _get_focusable_children(panel)
	if not focusable.is_empty():
		focusable[0].grab_focus()

func close() -> void:
	_is_open = false
	visible = false
	_on_close()
	panel_closed.emit()
	# print removed: print("UIPanel: Closed %s" % name)

func toggle(player_id: String) -> void:
	if _is_open:
		close()
	else:
		open(player_id)

func is_open() -> bool:
	return _is_open

## Override in subclasses for custom behavior
func _on_open() -> void:
	pass

func _on_close() -> void:
	pass

## ============================================================================
## UTILITY
## ============================================================================

func get_panel() -> PanelContainer:
	return get_node_or_null("Panel")

func get_content() -> VBoxContainer:
	var panel := get_panel()
	if panel:
		return panel.get_node_or_null("Content")
	return null

func add_content_to_panel(panel: PanelContainer) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.name = "Content"
	panel.add_child(content)
	return content

func show_notification(message: String, success: bool = true) -> void:
	var notif := Label.new()
	notif.text = message
	notif.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3) if success else Color(1, 0.3, 0.3))
	notif.z_index = 1000
	notif.global_position = Vector2(100, 100)
	get_tree().root.add_child(notif)
	await get_tree().create_timer(3.0).timeout
	notif.queue_free()

func set_title(text: String) -> void:
	var title: Label = get_node_or_null("Panel/Header/Title")
	if title == null:
		var panel := get_panel()
		if panel == null:
			return
		var header := HBoxContainer.new()
		header.name = "Header"
		panel.add_child(header)
		header.set_anchors_preset(Control.PRESET_TOP_WIDE)
		title = Label.new()
		title.name = "Title"
		title.text = text
		title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		title.add_theme_font_size_override("font_size", 18)
		header.add_child(title)
	else:
		title.text = text

func set_panel_size(size: Vector2) -> void:
	var panel := get_panel()
	if panel:
		panel.custom_minimum_size = size

func _get_focusable_recursive(node: Node, out: Array[Control]) -> void:
	if node is Control and node.focus_mode != FOCUS_NONE:
		out.append(node)
	for child in node.get_children():
		_get_focusable_recursive(child, out)
