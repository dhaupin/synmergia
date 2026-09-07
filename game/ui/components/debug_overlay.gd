## DebugOverlay - Visual debug layer for UI inspection
##
## Shows:
##  - Current game state (e.g. "LOGIN", "LOBBY")
##  - Hovered element name + type
##  - Mouse position
##
## Toggle: DebugOverlay.toggle() or F11 key
## Accessibility: Announces state changes for screen readers

extends CanvasLayer

static var instance: CanvasLayer

var _panel: Panel
var _state_label: Label
var _hover_label: Label
var _mouse_label: Label

## Accessibility: Description for screen readers
func _get_accessibility_properties() -> Dictionary:
	return {"role": "log", "label": "Debug overlay - Game state inspector"}

static func toggle() -> void:
	if instance:
		instance.visible = not instance.visible

static func log_click(element_name: String, action: String, success: bool) -> void:
	var status = "OK" if success else "FAIL"
	print("[DEBUG] Click: %s -> %s [%s]" % [element_name, action, status])

func _ready() -> void:
	instance = self
	_build_panel()
	print("DebugOverlay: ready (F11 to toggle)")

func _process(_delta: float) -> void:
	if not _panel or not _panel.visible:
		return

	var root = get_tree().root
	var gm = root.get_node_or_null("GameManager")
	if not gm:
		return
	var state = gm.current_state
	var state_name = "?"
	match state:
		0: state_name = "LOADING"
		1: state_name = "MAIN_MENU"
		2: state_name = "LOGIN"
		3: state_name = "LOBBY"
		4: state_name = "CHAR_SELECT"
		5: state_name = "PLAYING"
		6: state_name = "SETTINGS"
	_state_label.text = "State: " + state_name

	var hovered = _get_hovered_control()
	if hovered:
		var text = "Hover: " + str(hovered.name)
		if hovered is Button:
			text += " [BTN]"
		elif hovered is LineEdit:
			text += " [INPUT]"
		_hover_label.text = text
	else:
		_hover_label.text = "Hover: ---"

	var mp = get_viewport().get_mouse_position()
	_mouse_label.text = "Mouse: (%.0f, %.0f)" % [mp.x, mp.y]

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F11:
			toggle()

func _build_panel() -> void:
	_panel = Panel.new()
	_panel.anchors_preset = Control.PRESET_TOP_RIGHT
	_panel.offset_left = -220
	_panel.offset_top = 10
	_panel.offset_right = -10
	_panel.offset_bottom = 120
	_panel.z_index = 1000
	add_child(_panel)

	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.05, 0.1, 0.9)
	s.border_color = Color(0.6, 0.5, 0.2, 0.8)
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_top = 2
	s.border_width_bottom = 2
	_panel.add_theme_stylebox_override("panel", s)

	var title = Label.new()
	title.text = "[ DEBUG ]"
	title.position = Vector2(10, 8)
	_panel.add_child(title)

	_state_label = Label.new()
	_state_label.text = "State: ---"
	_state_label.position = Vector2(10, 30)
	_panel.add_child(_state_label)

	_hover_label = Label.new()
	_hover_label.text = "Hover: ---"
	_hover_label.position = Vector2(10, 50)
	_panel.add_child(_hover_label)

	_mouse_label = Label.new()
	_mouse_label.text = "Mouse: (0, 0)"
	_mouse_label.position = Vector2(10, 70)
	_panel.add_child(_mouse_label)

	var hint = Label.new()
	hint.text = "F11 = toggle"
	hint.position = Vector2(10, 95)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.add_theme_font_size_override("font_size", 10)
	_panel.add_child(hint)

func _get_hovered_control() -> Control:
	var root = get_tree().root
	var mp = root.get_mouse_position()
	return _find_deepest(root, mp)

func _find_deepest(node: Node, pos: Vector2) -> Control:
	if not node is Control:
		return null
	var ctrl = node as Control
	if not ctrl.is_inside_tree() or not ctrl.visible:
		return null
	if not ctrl.get_global_rect().has_point(pos):
		return null
	var deepest: Control = ctrl
	for c in ctrl.get_children():
		var found = _find_deepest(c, pos)
		if found:
			deepest = found
	return deepest
