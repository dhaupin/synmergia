## DragScroll - the ONE drag-scroll law for every menu body.
##
## Godot's ScrollContainer handles touch drags natively but NOT mouse
## drags, and each panel kept patching its own sort of scroll tweak
## (the "canonical drag-scroll handler" ask). This drop-in scroll body
## owns the whole surface once:
##
##   var scroll := preload("res://ui/components/drag_scroll.gd").new()
##   scroll.set_content(my_vbox)   # add_child also fine
##
##   - touch drag: native ScrollContainer law, preserved
##   - mouse drag: press anywhere on the body and drag -- the panel
##     scrolls with the pointer (MMO convention), released on lift
##   - wheel + arrows: untouched (ScrollContainer owns them)
##
## Clicks still land on buttons: a press that ALSO lands on a Button
## child is not swallowed (the button consumes it in its own
## gui_input pass first; the drag law only reacts to events the
## container itself receives).
extends ScrollContainer

var _mouse_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_scroll_at: float = 0.0

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_exited.connect(_exit_drag)

## The doc'd drop-in idiom: hand over the body like ScrollFrame does.
## The content expands horizontally so labels/lists span the panel;
## vertical sizing stays content-driven so the scroll law engages.
func set_content(content: Control) -> void:
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(content)

## THE NO-GHOST-DRAG LAW: a drag that ends OUTSIDE the body (pointer
## slid past the edge before the lift) would otherwise leave
## _mouse_dragging armed and later hover-motion would scroll the
## panel on its own. Leaving the rect clears the law.
func _exit_drag() -> void:
	_mouse_dragging = false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# A press over scrollable content: arm the drag law.
				_mouse_dragging = true
				_drag_start = event.position
				_drag_scroll_at = scroll_vertical
			else:
				_mouse_dragging = false
	elif event is InputEventMouseMotion and _mouse_dragging:
		var dy: float = event.position.y - _drag_start.y
		scroll_vertical = int(_drag_scroll_at - dy)
		accept_event()
	elif event is InputEventScreenTouch:
		# Native touch drag already scrolls; do not double-drive it.
		pass
