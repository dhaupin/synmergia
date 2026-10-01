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
	# Safety net: UIPanel._setup_panel() is a no-op stub and subclasses
	# must create the named "Panel" themselves. Nine subclasses never did
	# (action_bar, bank_ui, quest_ui, title_ui, faction_ui, achievement_ui,
	# quick_access_bar, character_panel, loading_ui): every one of their
	# _setup_ui bodies starts with `get_panel()` + `if not panel: return`,
	# so the whole panel rendered as an invisible/empty overlay. If a
	# subclass did not build its own Panel, build the base one for it so
	# at minimum the standard content path works.
	if get_panel() == null:
		_setup_base_panel()
	_setup_standard_header()
	_setup_content()
	# Second pass, DEFERRED: subclasses that build their Main after
	# super._ready() (settings_panel builds Main inside _setup_ui, called
	# from its own _ready) had no Main yet during the first pass, so
	# their header/close X never attached. Deferred runs after the whole
	# _ready chain (subclass included) and is idempotent -- panels with a
	# hand-rolled header are untouched.
	call_deferred("_setup_standard_header")
	_apply_accessibility()
	_apply_visual_settings()
	# Keep-in-view guard (see _clamp_panel_to_viewport): run after the
	# whole _ready chain so the panel's final minimum size is what gets
	# clamped. call_deferred also re-clamps panels whose Main is built
	# later in the subclass chain.
	call_deferred("_clamp_panel_to_viewport")

## Play-day feedback #2 + #6: EVERY panel gets a title row with a close
## (X) button, and the content box expands to fill the panel (the old
## base Main collapsed to minimum height -- the Character panel's tabs
## rendered over an empty body). Subclasses that build their own header
## (inventory_ui, guild_ui, ...) keep theirs; _setup_standard_header
## only fills the gap, and _ensure_close_button guarantees the X even
## on hand-rolled headers.
func _setup_standard_header() -> void:
	# Loading screens never get a header/close X (there is nothing to
	# close -- the world is loading). Duck-typed: no preload cycle.
	if self.has_method("show_loading"):
		return
	var panel := get_panel()
	if panel == null:
		return
	var main := panel.get_node_or_null("Main") as VBoxContainer
	if main == null:
		return
	# The content box must claim the panel's height. ScrollContainers
	# inside (tab pages, lists) need an expand-fill parent to show at
	# all; without this they render 0 px tall ("empty tabs").
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var header := main.get_node_or_null("Header") as HBoxContainer
	if header == null:
		header = HBoxContainer.new()
		header.name = "Header"
		main.add_child(header)
		main.move_child(header, 0)
	# Title (set_title writes into it later; a default reads the panel
	# name until then). A hand-rolled header may already carry an
	# unnamed title Label (inventory_ui's first child is its title) --
	# adding our own would duplicate the row, so only add when the row
	# has no Label at all.
	if header.get_node_or_null("Title") == null and not _header_row_has_label(header):
		var title := Label.new()
		title.name = "Title"
		title.text = _panel_title if not _panel_title.is_empty() else String(name)
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
		header.add_child(title)
	if header.get_node_or_null("Spacer") == null:
		var spacer := Control.new()
		spacer.name = "Spacer"
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(spacer)
	_ensure_close_button(header)

## Guarantee a close (X) on the given header row (or the panel's
## standard header). Idempotent: panels that already built one keep it.
func _ensure_close_button(header: HBoxContainer = null) -> void:
	var row := header
	if row == null:
		var panel := get_panel()
		if panel == null:
			return
		row = panel.get_node_or_null("Main/Header") as HBoxContainer
	if row == null or row.get_node_or_null("CloseButton") != null:
		return
	var close_btn := create_close_button()
	close_btn.name = "CloseButton"
	row.add_child(close_btn)

## True when the header row already carries any Label (a hand-rolled
## header's title). The standard header must not stack a second title
## next to it.
func _header_row_has_label(row: HBoxContainer) -> bool:
	for child in row.get_children():
		if child is Label:
			return true
	return false

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

	# Standard content container: most subclasses hang their UI off
	# panel/"Main" (VBoxContainer). Panels that build their own layout
	# simply ignore it.
	var main := VBoxContainer.new()
	main.name = "Main"
	panel.add_child(main)

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
	# Re-clamp at open time: the viewport may have changed since ready
	# (phone rotation, resize) and the guard must hold then too.
	_clamp_panel_to_viewport()
	_on_open()
	panel_opened.emit()
	# Focus first focusable element
	call_deferred("_focus_first_element")
	# print removed: print("UIPanel: Opened %s" % name)

func _focus_first_element() -> void:
	if not has_node("Panel"):
		return
	var panel := get_node("Panel")
	# Focus the panel container itself, NOT the first focusable child.
	# The first child is typically the header X button; while it held
	# focus it swallowed every subsequent letter hotkey (K, ESC, ...)
	# as GUI input and other panels could not open until the user
	# clicked somewhere. Keyboard navigation still works via Tab from
	# the panel, and hotkeys stay live in HudHotkeys' unhandled phase.
	if panel is Control:
		(panel as Control).grab_focus()

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
	_panel_title = text
	var title: Label = get_node_or_null("Panel/Main/Header/Title")
	if title == null:
		var panel := get_panel()
		if panel == null:
			return
		var header := panel.get_node_or_null("Main/Header") as HBoxContainer
		if header == null:
			# No header yet: build the standard one (title + spacer + X)
			# so the title has a home and the close law holds.
			_setup_standard_header()
			header = panel.get_node_or_null("Main/Header") as HBoxContainer
			if header == null:
				return
		title = header.get_node_or_null("Title") as Label
		if title == null:
			title = Label.new()
			title.name = "Title"
			header.add_child(title)
			header.move_child(title, 0)
	title.text = text

func set_panel_size(size: Vector2) -> void:
	var panel := get_panel()
	if panel:
		panel.custom_minimum_size = size

## VIEWPORT GUARD (play-test round 6, item 7): a centered panel whose
## minimum size exceeds the viewport (700x550 settings on a phone)
## bleeds off-screen with no way to reach the far edge. Clamp the
## minimum to 92% of the viewport so the panel always fits; content
## inside scrolls (ScrollFrame paths). Idempotent -- safe to call on
## every open (orientation flips while closed are caught there).
func _clamp_panel_to_viewport() -> void:
	var panel := get_panel()
	if panel == null:
		return
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var max_size := Vector2(vp.x * 0.92, vp.y * 0.92)
	var min_size := panel.custom_minimum_size
	if min_size.x > max_size.x or min_size.y > max_size.y:
		panel.custom_minimum_size = Vector2(minf(min_size.x, max_size.x), minf(min_size.y, max_size.y))

func _get_focusable_recursive(node: Node, out: Array[Control]) -> void:
	if node is Control and node.focus_mode != FOCUS_NONE:
		out.append(node)
	for child in node.get_children():
		_get_focusable_recursive(child, out)
