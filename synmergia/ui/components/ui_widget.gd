## UIWidget - Base class for HUD chrome (buff bar, action bar, status bar,
## admin toolbar, etc.). Sibling to UIPanel, which is for popup-style panels.
##
## Key differences from UIPanel:
##   - No full-screen overlay (HUD elements must not block input behind them).
##   - No mandatory centered panel container or close button.
##   - Subclasses are free to use any layout container (HBox, VBox, etc.) as
##     a child of the root Control.
##   - Optional hotkey toggle (e.g., F3 for the admin toolbar) via
##     `set_hotkey(keycode)`.
##
## Subclasses override `_setup_widget()` to build their content. The base
## does no anchor/margin work of its own — subclasses set their own
## position via anchor presets in `_setup_widget()`.
class_name UIWidget
extends Control

var _hotkey_keycode: int = KEY_NONE
var _is_always_visible: bool = true

signal widget_shown()
signal widget_hidden()

func _ready() -> void:
	_setup_widget()
	if _is_always_visible:
		show()
	else:
		hide()

func _setup_widget() -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	if _hotkey_keycode == KEY_NONE:
		return
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event
	if key_event.pressed and not key_event.echo and key_event.keycode == _hotkey_keycode:
		toggle_visibility()
		get_viewport().set_input_as_handled()

func set_hotkey(keycode: int) -> void:
	_hotkey_keycode = keycode

func set_always_visible(value: bool) -> void:
	_is_always_visible = value
	if is_inside_tree() and value:
		show()

func toggle_visibility() -> void:
	if visible:
		hide()
		widget_hidden.emit()
	else:
		show()
		widget_shown.emit()