## QuickAccessBar - Enhanced consumable items hotbar
## 6 slots for consumables with cooldown spiral, stack counts, drag-drop, auto-fill
extends "res://ui/components/ui_panel.gd"
class_name QuickAccessBar
const IconResolver = preload("res://core/utils/icon_resolver.gd")

## Configuration
const SLOT_COUNT: int = 6

## Slots data
var _slots: Array = []
var _keybinds: Array = []
var _slot_items: Dictionary = {}
var _slot_cooldowns: Dictionary = {}

## Drag-drop state
var _dragging: bool = false
var _drag_source_index: int = -1
var _drag_preview: Control = null
var _qa_high_contrast: bool = false

## Signals
signal item_used(index: int, item_id: String)
signal item_changed(index: int, item_data: Dictionary)
signal slot_cleared(index: int)

func _ready() -> void:
	super._ready()
	set_title("Quick Access")
	set_panel_size(Vector2(360, 80))
	_setup_ui()
	_build_keybinds()
	_setup_accessibility()

func _setup_accessibility() -> void:
	focus_mode = Control.FOCUS_ALL
func _on_open() -> void:
	pass

func _on_close() -> void:
	pass

func update_accessibility_settings(high_contrast: bool, text_scale: float, reduce_motion: bool) -> void:
	_qa_high_contrast = high_contrast
	# Update focus styles for all slots
	for slot in _slots:
		if slot and is_instance_valid(slot):
			slot.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
			var style: StyleBoxFlat = slot.get_theme_stylebox("panel")
			if style:
				if high_contrast:
					style.bg_color = UIStyles.HIGH_CONTRAST_COLORS.background
					style.border_color = UIStyles.HIGH_CONTRAST_COLORS.border
				else:
					style.bg_color = UIStyles.COLORS.background_dark
					style.border_color = UIStyles.COLORS.border
			
			# Update text sizes
			var keybind: Label = slot.get_node_or_null("Keybind")
			var stack: Label = slot.get_node_or_null("StackCount")
			var cooldown_text: Label = slot.get_node_or_null("CooldownText")
			var scale = UIStyles.get_text_scale()
			if keybind:
				keybind.add_theme_font_size_override("font_size", int(8 * scale))
			if stack:
				stack.add_theme_font_size_override("font_size", int(11 * scale))
			if cooldown_text:
				cooldown_text.add_theme_font_size_override("font_size", int(12 * scale))

func _build_keybinds() -> void:
	_keybinds = [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6]

func _setup_ui() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main: VBoxContainer = add_content_to_panel(panel)

	var container := HBoxContainer.new()
	container.name = "Container"
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 4)
	main.add_child(container)

	for i in range(SLOT_COUNT):
		var slot := _create_slot(i)
		container.add_child(slot)
		_slots.append(slot)

func _create_slot(index: int) -> Control:
	var slot := PanelContainer.new()
	slot.name = "QuickSlot_%d" % index
	slot.custom_minimum_size = Vector2(50, 50)
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	slot.focus_mode = Control.FOCUS_ALL
	slot.add_theme_stylebox_override("focus", UIStyles.create_focus_style())

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = UIStyles.COLORS.background_dark
	bg_style.border_color = UIStyles.COLORS.border
	bg_style.border_width_left = 2
	bg_style.border_width_right = 2
	bg_style.border_width_top = 2
	bg_style.border_width_bottom = 2
	bg_style.corner_radius_top_left = 6
	bg_style.corner_radius_top_right = 6
	bg_style.corner_radius_bottom_left = 6
	bg_style.corner_radius_bottom_right = 6
	slot.add_theme_stylebox_override("panel", bg_style)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(vbox)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(38, 38)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(1, 1, 1, 0.3)
	vbox.add_child(icon)

	var cooldown_spiral := TextureProgressBar.new()
	cooldown_spiral.name = "CooldownSpiral"
	cooldown_spiral.visible = false
	cooldown_spiral.set_anchors_preset(Control.PRESET_FULL_RECT)
	cooldown_spiral.min_value = 0
	cooldown_spiral.max_value = 100
	cooldown_spiral.value = 100
	cooldown_spiral.texture_under = _create_spiral_under()
	cooldown_spiral.texture_progress = _create_spiral_progress()
	cooldown_spiral.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	cooldown_spiral.radial_initial_angle = -90
	cooldown_spiral.radial_fill_degrees = 360.0
	cooldown_spiral.clip_contents = true
	slot.add_child(cooldown_spiral)

	var cooldown_text := Label.new()
	cooldown_text.name = "CooldownText"
	cooldown_text.visible = false
	cooldown_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cooldown_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cooldown_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	cooldown_text.add_theme_font_size_override("font_size", 12)
	cooldown_text.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	cooldown_text.add_theme_constant_override("outline_size", 2)
	cooldown_text.add_theme_color_override("outline_color", Color(0, 0, 0, 1))
	slot.add_child(cooldown_text)

	var keybind := Label.new()
	keybind.name = "Keybind"
	keybind.text = "F%d" % (index + 1)
	keybind.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	keybind.offset_left = 2
	keybind.offset_right = 30
	keybind.offset_top = -14
	keybind.offset_bottom = -2
	keybind.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	keybind.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	keybind.add_theme_font_size_override("font_size", 8)
	keybind.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	keybind.add_theme_constant_override("outline_size", 1)
	keybind.add_theme_color_override("outline_color", Color(0, 0, 0, 1))
	slot.add_child(keybind)

	var stack_label := Label.new()
	stack_label.name = "StackCount"
	stack_label.visible = false
	stack_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	stack_label.offset_left = -35
	stack_label.offset_right = -2
	stack_label.offset_top = -14
	stack_label.offset_bottom = -2
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	stack_label.add_theme_font_size_override("font_size", 11)
	stack_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	stack_label.add_theme_constant_override("outline_size", 2)
	stack_label.add_theme_color_override("outline_color", Color(0, 0, 0, 1))
	slot.add_child(stack_label)

	var low_stack_warning := ColorRect.new()
	low_stack_warning.name = "LowStackWarning"
	low_stack_warning.visible = false
	low_stack_warning.color = Color(1, 0.8, 0.2, 0.8)
	low_stack_warning.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(low_stack_warning)

	slot.gui_input.connect(_on_slot_gui_input.bind(index))
	return slot

func _create_spiral_under() -> Texture2D:
	var img := Image.create(46, 46, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.1, 0.15, 0.8))
	return ImageTexture.create_from_image(img)

func _create_spiral_progress() -> Texture2D:
	var img := Image.create(46, 46, false, Image.FORMAT_RGBA8)
	var center := Vector2(23, 23)
	var radius: float = 21.0
	for x in range(46):
		for y in range(46):
			var pos := Vector2(x, y)
			var dist := pos.distance_to(center)
			if dist <= radius and dist >= radius - 3:
				var angle := atan2(pos.y - center.y, pos.x - center.x)
				var deg := rad_to_deg(angle) + 90
				if deg < 0:
					deg += 360
				var alpha: float = 0.6 * (1.0 - (dist - (radius - 3)) / 3.0)
				img.set_pixel(x, y, Color(0.3, 1.0, 0.5, alpha))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)

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
	var icon: TextureRect = slot.get_node_or_null("VBox/Icon")
	var cooldown_spiral: TextureProgressBar = slot.get_node_or_null("CooldownSpiral")
	var cooldown_text: Label = slot.get_node_or_null("CooldownText")

	if icon and icon.modulate.a < 0.5:
		return

	if cooldown_spiral and cooldown_spiral.visible:
		return

	if _slot_items.has(index):
		item_used.emit(index, _slot_items[index].get("id", ""))
	else:
		item_used.emit(index, "")

func _on_slot_gui_input(index: int, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag(index, event.position)
			else:
				_end_drag(index, event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_clear_slot(index)

	if event is InputEventMouseMotion and _dragging:
		_update_drag_preview(event.position)

func _start_drag(index: int, position: Vector2) -> void:
	if not _slot_items.has(index):
		return

	_dragging = true
	_drag_source_index = index

	_drag_preview = PanelContainer.new()
	_drag_preview.name = "DragPreview"
	_drag_preview.custom_minimum_size = Vector2(46, 46)
	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.border_color = UIStyles.COLORS.accent_gold
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_drag_preview.add_theme_stylebox_override("panel", style)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(34, 34)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var source_slot: Control = _slots[index]
	if source_slot:
		var src_icon: TextureRect = source_slot.get_node_or_null("VBox/Icon")
		if src_icon:
			icon.texture = src_icon.texture
	_drag_preview.add_child(icon)

	get_viewport().gui_add_child(_drag_preview)
	_drag_preview.global_position = position - Vector2(23, 23)
	_drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_preview.z_index = 1000

	if source_slot:
		source_slot.modulate = Color(1, 1, 1, 0.5)

func _update_drag_preview(position: Vector2) -> void:
	if _drag_preview and is_instance_valid(_drag_preview):
		_drag_preview.global_position = position - Vector2(23, 23)

func _end_drag(source_index: int, position: Vector2) -> void:
	if not _dragging:
		return

	_dragging = false

	if _drag_preview and is_instance_valid(_drag_preview):
		_drag_preview.queue_free()
		_drag_preview = null

	var source_slot: Control = _slots[source_index]
	if source_slot:
		source_slot.modulate = Color(1, 1, 1, 1)

	var target_index: int = -1
	for i in range(SLOT_COUNT):
		var slot: Control = _slots[i]
		if slot and slot.has_point(slot.get_local_mouse_position()):
			target_index = i
			break

	if target_index >= 0 and target_index != source_index:
		_swap_slots(source_index, target_index)

	_drag_source_index = -1

func _swap_slots(index_a: int, index_b: int) -> void:
	var data_a: Dictionary = _slot_items.get(index_a, {})
	var data_b: Dictionary = _slot_items.get(index_b, {})

	_slot_items[index_a] = data_b
	_slot_items[index_b] = data_a

	set_slot_item(index_a, data_b)
	set_slot_item(index_b, data_a)

	item_changed.emit(index_a, data_b)
	item_changed.emit(index_b, data_a)

func _clear_slot(index: int) -> void:
	if not _slot_items.has(index):
		return

	_slot_items.erase(index)
	_slot_cooldowns.erase(index)

	var slot: Control = _slots[index]
	var icon: TextureRect = slot.get_node_or_null("VBox/Icon")
	var stack: Label = slot.get_node_or_null("StackCount")
	var low_warning: ColorRect = slot.get_node_or_null("LowStackWarning")
	var cooldown_spiral: TextureProgressBar = slot.get_node_or_null("CooldownSpiral")
	var cooldown_text: Label = slot.get_node_or_null("CooldownText")
	var style: StyleBoxFlat = slot.get_theme_stylebox("panel")

	if icon:
		icon.modulate = Color(1, 1, 1, 0.3)
		icon.texture = null
	if stack:
		stack.visible = false
	if low_warning:
		low_warning.visible = false
	if cooldown_spiral:
		cooldown_spiral.visible = false
	if cooldown_text:
		cooldown_text.visible = false
	if style:
		style.border_color = UIStyles.HIGH_CONTRAST_COLORS.border if _qa_high_contrast else UIStyles.COLORS.border

	slot_cleared.emit(index)

func set_slot_item(index: int, item_data: Dictionary) -> void:
	if index < 0 or index >= _slots.size():
		return

	var slot: Control = _slots[index]
	var icon: TextureRect = slot.get_node_or_null("VBox/Icon")
	var stack: Label = slot.get_node_or_null("StackCount")
	var low_warning: ColorRect = slot.get_node_or_null("LowStackWarning")
	var style: StyleBoxFlat = slot.get_theme_stylebox("panel")

	if item_data.is_empty():
		_slot_items.erase(index)
		_slot_cooldowns.erase(index)
		if icon:
			icon.modulate = Color(1, 1, 1, 0.3)
			icon.texture = null
		if stack:
			stack.visible = false
		if low_warning:
			low_warning.visible = false
		if style:
			style.border_color = UIStyles.HIGH_CONTRAST_COLORS.border if _qa_high_contrast else UIStyles.COLORS.border
		# A11y: empty consumable slots self-describe (round 2).
		UIStyles.apply_accessibility(slot, "Empty item slot %d" % (index + 1), "Drag a consumable here")
		return

	_slot_items[index] = item_data
	# A11y: name the ITEM and its stack, state the use verb.
	var item_label: String = str(item_data.get("name", item_data.get("id", "Item")))
	var qty_note := " x%s" % str(item_data["quantity"]) if item_data.has("quantity") and int(item_data["quantity"]) > 1 else ""
	UIStyles.apply_accessibility(
		slot,
		"Use %s%s" % [item_label, qty_note],
		"Consumable. Click or press its key to use."
	)
	if icon:
		icon.modulate = Color(1, 1, 1, 1)
		icon.texture = IconResolver.get_item_icon_from_dict(item_data)

	if stack and item_data.has("quantity"):
		var qty: int = item_data.quantity
		stack.text = str(qty) if qty > 1 else ""
		stack.visible = qty > 1

		# Low stack warning
		if low_warning and style:
			if qty > 0 and qty < 3:
				low_warning.visible = true
				style.border_color = UIStyles.HIGH_CONTRAST_COLORS.warning if _qa_high_contrast else UIStyles.COLORS.warning
			else:
				low_warning.visible = false
				style.border_color = UIStyles.HIGH_CONTRAST_COLORS.border if _qa_high_contrast else UIStyles.COLORS.border

	item_changed.emit(index, item_data)

func get_slot_item(index: int) -> Dictionary:
	return _slot_items.get(index, {})

func load_from_inventory() -> void:
	if not InventoryService:
		return

	# get_inventory returns an InventoryComponent, not an Array.
	var inv: InventoryComponent = InventoryService.get_inventory("")
	if inv == null:
		return

	var items: Array = inv.get_all_items()
	if items.is_empty():
		return

	var consumables: Array = []
	for item in items:
		if item is Item and item.item_category == Item.ItemCategory.CONSUMABLE:
			consumables.append(item)

	# Sort by priority: potions > food > scrolls > tools, then by stack size
	consumables.sort_custom(func(a, b):
		var a_priority: int = _get_item_priority(a)
		var b_priority: int = _get_item_priority(b)
		if a_priority != b_priority:
			return a_priority < b_priority
		return a.current_stack > b.current_stack
	)

	for i in range(min(SLOT_COUNT, consumables.size())):
		var item_dict: Dictionary = consumables[i].to_dict()
		item_dict["quantity"] = consumables[i].current_stack
		set_slot_item(i, item_dict)

func _get_item_priority(item: Item) -> int:
	var name_lower: String = item.display_name.to_lower()

	if "potion" in name_lower:
		return 0
	if "food" in name_lower or "bread" in name_lower or "meat" in name_lower:
		return 1
	if "scroll" in name_lower:
		return 2
	if "tool" in name_lower or "kit" in name_lower:
		return 3
	return 4

func clear_slots() -> void:
	for i in range(SLOT_COUNT):
		set_slot_item(i, {})

func set_slot_cooldown(index: int, remaining: float, total: float = 0) -> void:
	if index < 0 or index >= _slots.size():
		return

	var slot: Control = _slots[index]
	var cooldown_spiral: TextureProgressBar = slot.get_node_or_null("CooldownSpiral")
	var cooldown_text: Label = slot.get_node_or_null("CooldownText")

	if not cooldown_spiral or not cooldown_text:
		return

	if remaining > 0:
		cooldown_spiral.visible = true
		cooldown_text.visible = true
		if total > 0:
			cooldown_spiral.max_value = total
			cooldown_spiral.value = remaining
		cooldown_text.text = str(int(ceil(remaining)))
		_slot_cooldowns[index] = {"remaining": remaining, "total": total}
	else:
		cooldown_spiral.visible = false
		cooldown_text.visible = false
		_slot_cooldowns.erase(index)

func process_cooldowns(delta: float) -> void:
	for index in _slot_cooldowns.keys():
		var data: Dictionary = _slot_cooldowns[index]
		var remaining: float = data.remaining - delta
		if remaining <= 0:
			set_slot_cooldown(index, 0)
		else:
			set_slot_cooldown(index, remaining, data.total)

func get_slot_cooldown(index: int) -> float:
	return _slot_cooldowns.get(index, {}).get("remaining", 0.0)

func is_slot_on_cooldown(index: int) -> bool:
	return _slot_cooldowns.has(index)

func get_item_count(item_id: String) -> int:
	var total = 0
	for index in _slot_items.keys():
		var item = _slot_items[index]
		if item.get("id") == item_id:
			total += item.get("quantity", 1)
	return total

func has_item(item_id: String) -> bool:
	for index in _slot_items.keys():
		if _slot_items[index].get("id") == item_id:
			return true
	return false

func consume_item(item_id: String, amount: int = 1) -> bool:
	for index in _slot_items.keys():
		var item = _slot_items[index]
		if item.get("id") == item_id:
			var current_qty = item.get("quantity", 1)
			if current_qty >= amount:
				item.quantity = current_qty - amount
				set_slot_item(index, item)
				return true
	return false

func get_all_items() -> Array:
	var items = []
	for index in _slot_items.keys():
		items.append({"index": index, "data": _slot_items[index]})
	return items
