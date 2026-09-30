## ScrollFrame - a scrollable body with overflow hint arrows.
##
## Play-day feedback #5b: menus must scroll on low-res devices, and the
## player must KNOW there is more below. Any Control can ride inside:
##
##   var frame := ScrollFrameScript.new()   # preload this script
##   frame.set_content(my_vbox)
##   some_panel.add_child(frame)
##
## The arrows are Buttons (tappable on touch) and only appear when the
## content actually overflows in that direction, so short menus stay
## clean. Reusable across menus and panels by design.
extends VBoxContainer

const UIStyles = preload("res://ui/components/ui_styles.gd")

var _scroll: ScrollContainer
var _up_btn: Button
var _down_btn: Button

func _init() -> void:
	# Built in _init so set_content()/add_scroll_child() work before the
	# frame enters the tree (builders call them between new() and
	# add_child()).
	_up_btn = _make_arrow_btn("^")
	_up_btn.pressed.connect(_page_up)
	_up_btn.visible = false
	add_child(_up_btn)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_down_btn = _make_arrow_btn("v")
	_down_btn.pressed.connect(_page_down)
	_down_btn.visible = false
	add_child(_down_btn)

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Track scroll position so the up-arrow disappears at the top.
	var vbar := _scroll.get_v_scroll_bar()
	if vbar != null:
		vbar.value_changed.connect(func(_v: float) -> void: _update_arrows())

func _process(_delta: float) -> void:
	_update_arrows()

func _make_arrow_btn(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.tooltip_text = "More content" if label_text == "v" else "Back up"
	btn.custom_minimum_size = Vector2(0, 26)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 12)
	return btn

## Replace the scrollable content (previous content is freed).
func set_content(content: Control) -> void:
	for child in _scroll.get_children():
		_scroll.remove_child(child)
		child.queue_free()
	if content != null:
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll.add_child(content)

## Append without clearing (convenience for list builders).
func add_scroll_child(child: Control) -> void:
	if _scroll.get_child_count() == 0:
		var wrap := VBoxContainer.new()
		wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll.add_child(wrap)
	var wrap2 := _scroll.get_child(0)
	wrap2.add_child(child)

func _page_up() -> void:
	_scroll.scroll_vertical -= int(_scroll.size.y * 0.8)

func _page_down() -> void:
	_scroll.scroll_vertical += int(_scroll.size.y * 0.8)

func _update_arrows() -> void:
	if _scroll == null:
		return
	var vbar := _scroll.get_v_scroll_bar()
	if vbar == null:
		return
	var overflow: float = vbar.max_value - _scroll.size.y
	_up_btn.visible = _scroll.scroll_vertical > 1.0
	_down_btn.visible = overflow > 1.0 \
		and _scroll.scroll_vertical < vbar.max_value - _scroll.size.y - 1.0
