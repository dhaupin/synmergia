## UIPanel - Base class for Synmergia UI panels with common functionality
class_name UIPanel
extends Control

## Panel state
var _is_open: bool = false
var _player_id: String = ""

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

## Override these in subclasses
func _setup_panel() -> void:
	pass

func _setup_header() -> void:
	pass

func _setup_content() -> void:
	pass

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

## ============================================================================
## OPEN/CLOSE
## ============================================================================

func open(player_id: String) -> void:
	_player_id = player_id
	_is_open = true
	visible = true
	_on_open()
	panel_opened.emit()
	GameLog.debug("UIPanel: Opened %s" % name)

func close() -> void:
	_is_open = false
	visible = false
	_on_close()
	panel_closed.emit()
	GameLog.debug("UIPanel: Closed %s" % name)

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
