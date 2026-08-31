## QuickAccessBar - Consumable items hotbar
## 4 quick-use slots for potions, food, etc.
class_name QuickAccessBar
extends Control

## Quick slots
const SLOT_COUNT: int = 4
var _slots: Array = []
var _keybinds: Array = []

signal item_used(index: int, item_id: String)
signal item_changed(index: int, item_data: Dictionary)

func _ready() -> void:
	_setup_ui()

func _setup_ui() -> void:
	var container := HBoxContainer.new()
	container.name = "Container"
	add_child(container)

	for i in range(SLOT_COUNT):
		var slot := _create_slot(i)
		container.add_child(slot)
		_slots.append(slot)

	_keybinds = [KEY_F1, KEY_F2, KEY_F3, KEY_F4]

func _create_slot(index: int) -> Control:
	var slot := PanelContainer.new()
	slot.name = "QuickSlot_%d" % index
	slot.custom_minimum_size = Vector2(45, 45)

var style := StyleBoxFlat.new()
style.bg_color = UIStyles.COLORS.background_dark
style.border_color = UIStyles.COLORS.border
style.corner_radius_top_left = 4
style.corner_radius_top_right = 4
style.corner_radius_bottom_left = 4
style.corner_radius_bottom_right = 4
slot.add_theme_stylebox_override("panel", style)

# Item icon placeholder
var icon := Panel.new()
icon.name = "Icon"
icon.modulate = Color(1, 1, 1, 0.3)
slot.add_child(icon)

# Keybind label
var keybind := Label.new()
keybind.name = "Keybind"
keybind.text = "F%d" % (index + 1)
keybind.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
keybind.add_theme_font_size_override("font_size", 9)
keybind.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
slot.add_child(keybind)

# Stack count
var stack := Label.new()
stack.name = "Stack"
stack.visible = false
stack.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
stack.add_theme_font_size_override("font_size", 10)
stack.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
slot.add_child(stack)

# Cooldown sweep
var cooldown := Panel.new()
cooldown.name = "Cooldown"
cooldown.visible = false
slot.add_child(cooldown)

return slot

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		for i in range(_keybinds.size()):
			if event.keycode == _keybinds[i]:
				_use_slot(i)
				break

func _use_slot(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return

	var slot: Control = _slots[index]
	var icon: Panel = slot.get_node_or_null("Icon")
	var cooldown: Panel = slot.get_node_or_null("Cooldown")

	# Check if empty
	if icon and icon.modulate.a < 0.5:
		return

		# Check if on cooldown
		if cooldown and cooldown.visible:
			return

			# Emit signal
			item_used.emit(index, "potion_health")  # TODO: Get actual item ID

func set_slot_item(index: int, item_data: Dictionary) -> void:
	if index < 0 or index >= _slots.size():
		return

	var slot: Control = _slots[index]
	var icon: Panel = slot.get_node_or_null("Icon")
	var stack: Label = slot.get_node_or_null("Stack")

	if item_data.is_empty():
		if icon:
			icon.modulate = Color(1, 1, 1, 0.3)
			if stack:
				stack.visible = false
				return

				if icon:
					icon.modulate = Color(1, 1, 1, 1)
					# TODO: Set actual icon texture

					if stack and item_data.has("quantity"):
						var qty: int = item_data.quantity
						stack.text = str(qty) if qty > 1 else ""
						stack.visible = qty > 1

					item_changed.emit(index, item_data)

func set_slot_cooldown(index: int, remaining: float) -> void:
	if index < 0 or index >= _slots.size():
		return

	var slot: Control = _slots[index]
	var cooldown: Panel = slot.get_node_or_null("Cooldown")

	if cooldown:
		cooldown.visible = remaining > 0
