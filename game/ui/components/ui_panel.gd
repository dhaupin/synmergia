## UIPanel - Base class for Synmergia UI panels with common functionality
extends Control
class_name UIPanel

## Panel state
var _is_open: bool = false
var _player_id: String = ""
var _panel_title: String = ""

## Signals
signal panel_opened()
signal panel_closed()

## ============================================================================
## LIFECYCLE
## ============================================================================

func _ready() -> void:
	visible = false
	_setup_overlay()
	_setup_panel()
	_setup_header()
	_setup_content()
	_apply_accessibility()

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
	# Set tooltip for mouse hover accessibility
	if has_node("Panel"):
		var panel := get_node("Panel")
		if panel is PanelContainer:
			panel.tooltip_text = _panel_title if not _panel_title.is_empty() else name

## ============================================================================
## ACCESSIBILITY HELPERS
## ============================================================================

## Create an accessible button with proper focus and tooltips
func create_accessible_button(text: String, tooltip: String = "") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_ALL  # Enable keyboard navigation
	if not tooltip.is_empty():
		btn.tooltip_text = tooltip
	else:
		btn.tooltip_text = text
	return btn

## Create a canonical close button (X) for panel headers
func create_close_button() -> Button:
	var btn := Button.new()
	btn.text = "X"
	btn.custom_minimum_size = Vector2(36, 36)
	btn.focus_mode = Control.FOCUS_ALL
	btn.tooltip_text = "Close (ESC)"
	btn.pressed.connect(close)
	return btn

## Announce a change for screen readers (logs for now, extensible)
func announce_for_screen_reader(message: String) -> void:
	# Emit signal that can be connected to a screen reader service
	# For now, log to console for debug
	print("[A11Y] " + message)

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
	if PlayerManager and PlayerManager.has_method("get_local_player"):
		return PlayerManager.get_local_player()
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
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.98)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", style)
	panel.name = "Panel"
	add_child(panel)
	
	return panel

func _on_overlay_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()

## Canonical close() - override in subclasses for custom cleanup
## Close mechanisms:
##   1. ESC key → HudHotkeys → _handle_escape() → MenuManager → close()
##   2. X button → pressed.connect(close)
##   3. Click overlay → _on_overlay_click()
##   4. Panel title close button (X) → close()
##   5. Distance check → close() (for interactable panels)
##   6. Timed auto-close → close() (for notifications/toasts)

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
	print("UIPanel: Opened %s" % name)

func close() -> void:
	_is_open = false
	visible = false
	_on_close()
	panel_closed.emit()
	print("UIPanel: Closed %s" % name)

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
