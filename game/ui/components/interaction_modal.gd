## InteractionModal - an in-canvas modal dialog (play-test round 9)
##
## Replaces native AcceptDialog / ConfirmationDialog popups, whose
## close buttons never receive touches in the embedded web canvas
## (round 9: the Add Friend dialog's X was dead and the dialog was
## unclosable -- the user had to exit the whole game). Everything here
## is plain Control nodes in the opener's CanvasLayer, so touch input
## behaves like every other panel.
##
## Modals self-register with MenuManager's INTERACTION STACK: the back
## gesture (ESC / Android back / web back / the on-screen Back button)
## closes the topmost interaction before touching panels, and the
## permanent Back button appears while any interaction is live.
##
## No UTF-8, tabs only.
## class_name is REQUIRED here: the static factory annotates its
## return type, and callers invoke the global class directly.
extends Control
class_name InteractionModal
## NOTE: menu_manager.gd is resolved with RUNTIME load(), never
## preload(): menu_manager load-time-preloads the social panels, so a
## preload here would close a menu_manager -> friends_list -> here ->
## menu_manager cycle (parse error in all three files).

signal closed

var _on_confirm: Callable = Callable()
var _input_field: LineEdit = null
var _registered_with: Node = null


## Show a modal. host = the node whose CanvasLayer the modal joins
## (pass a MenuManager child like a panel, or any node inside one).
## on_confirm receives the trimmed input text ("" when show_input is
## false). Returns the modal so callers can await `closed`.
## NOTE the absence of any self-name reference (no "-> InteractionModal"
## return annotation, no InteractionModal.new()): in --script mode the
## global class cache can be stale for a brand-new class_name and the
## self-identifier would not resolve. new() inside a static resolves
## to this script in every mode.
static func show_modal(host: Node, title_text: String, body_text: String,
		confirm_text: String = "OK", show_input: bool = false,
		on_confirm: Callable = Callable()):
	var modal = new()
	modal._on_confirm = on_confirm
	modal._build(title_text, body_text, confirm_text, show_input)
	host.add_child(modal)
	modal._register()
	return modal


func _build(title_text: String, body_text: String, confirm_text: String, show_input: bool) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dim.grow_vertical = Control.GROW_DIRECTION_BOTH
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# CenterContainer does the centering -- never hand-place a
	# center-anchored box (the round-7 frozen-offsets trap).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.custom_minimum_size = Vector2(56, 48)
	x_btn.add_theme_font_size_override("font_size", 20)
	x_btn.focus_mode = Control.FOCUS_NONE
	x_btn.pressed.connect(close_modal)
	header.add_child(title)
	header.add_child(x_btn)

	var body := Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(440, 0)
	body.add_theme_font_size_override("font_size", 17)

	v.add_child(header)
	v.add_child(body)

	if show_input:
		_input_field = LineEdit.new()
		_input_field.placeholder_text = "player name"
		_input_field.custom_minimum_size = Vector2(0, 52)
		_input_field.add_theme_font_size_override("font_size", 18)
		v.add_child(_input_field)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 16)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(140, 54)
	cancel.add_theme_font_size_override("font_size", 19)
	cancel.pressed.connect(close_modal)
	var ok := Button.new()
	ok.text = confirm_text
	ok.custom_minimum_size = Vector2(140, 54)
	ok.add_theme_font_size_override("font_size", 19)
	ok.pressed.connect(_confirm)
	buttons.add_child(cancel)
	buttons.add_child(ok)
	v.add_child(buttons)

	margin.add_child(v)
	box.add_child(margin)
	center.add_child(box)


func _register() -> void:
	var mm = _menu_manager()
	if mm != null and mm.has_method("push_interaction"):
		mm.push_interaction(self)
		_registered_with = mm


func _menu_manager() -> Node:
	# Same resolution the settings panel uses (the script's instance
	# singleton -- MenuManager is a HUD-scoped CanvasLayer, not an
	# autoload), but through runtime load() to break the preload cycle
	# (see the NOTE at the top).
	var script = load("res://ui/components/menu_manager.gd")
	if script == null:
		return null
	var mm = script.instance
	return mm if is_instance_valid(mm) else null


func close_modal() -> void:
	if _registered_with != null and is_instance_valid(_registered_with):
		if _registered_with.has_method("pop_interaction"):
			_registered_with.pop_interaction(self)
	closed.emit()
	queue_free()


func _confirm() -> void:
	var text := ""
	if _input_field != null:
		text = _input_field.text.strip_edges()
	if _on_confirm.is_valid():
		_on_confirm.call(text)
	close_modal()
