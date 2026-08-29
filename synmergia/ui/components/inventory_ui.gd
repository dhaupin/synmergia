## InventoryUI - Player inventory panel
class_name InventoryUI
extends Control

var _player_id: String = ""
var _grid: GridContainer
var _slots: Array = []
var _selected_slot: int = -1

const COLS: int = 5
const ROWS: int = 6
const SLOT_SIZE: int = 50

signal item_selected(slot_index: int, item_id: String)
signal item_used(slot_index: int, item_id: String)
signal item_dropped(slot_index: int, item_id: String)
signal closed()

func _ready() -> void:
	_setup_ui()
	hide()

func _setup_ui() -> void:
	# Overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.gui_input.connect(func(e): 
		if e is InputEventMouseButton and e.pressed: close()
	)
	add_child(overlay)
	
	# Panel
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_left = -450
	panel.custom_minimum_size = Vector2(400, 500)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.98)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.corner_radius_top_left = 12
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	
	var main := VBoxContainer.new()
	panel.add_child(main)
	
	# Header
	var header := HBoxContainer.new()
	main.add_child(header)
	
	var title := Label.new()
	title.text = "Inventory"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	header.add_child(title)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	var gold_label := Label.new()
	gold_label.text = "Gold: 0"
	gold_label.name = "GoldLabel"
	gold_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	header.add_child(gold_label)
	
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	
	# Grid
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.custom_minimum_size.y = SLOT_SIZE * ROWS
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_grid)
	
	# Create slots
	for i in range(COLS * ROWS):
		var slot := _create_slot(i)
		_grid.add_child(slot)
		_slots.append(slot)
	
	# Item info panel
	var info_panel := HBoxContainer.new()
	info_panel.custom_minimum_size.y = 60
	main.add_child(info_panel)
	
	var info_label := Label.new()
	info_label.name = "ItemInfo"
	info_label.text = "Select an item"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_panel.add_child(info_label)
	
	# Action buttons
	var btn_row := HBoxContainer.new()
	main.add_child(btn_row)
	
	var use_btn := Button.new()
	use_btn.text = "Use"
	use_btn.pressed.connect(_on_use_item)
	btn_row.add_child(use_btn)
	
	var equip_btn := Button.new()
	equip_btn.text = "Equip"
	equip_btn.pressed.connect(_on_equip_item)
	btn_row.add_child(equip_btn)
	
	var drop_btn := Button.new()
	drop_btn.text = "Drop"
	drop_btn.pressed.connect(_on_drop_item)
	btn_row.add_child(drop_btn)

func _create_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.9)
	style.border_color = Color(0.2, 0.2, 0.25)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	slot.add_theme_stylebox_override("panel", style)
	
	# Icon
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.name = "Icon"
	slot.add_child(icon)
	
	# Stack count
	var count := Label.new()
	count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -25
	count.offset_right = -5
	count.offset_top = -20
	count.offset_bottom = -5
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.add_theme_font_size_override("font_size", 12)
	count.add_theme_color_override("font_color", Color(1, 1, 1))
	count.name = "Count"
	count.visible = false
	slot.add_child(count)
	
	slot.gui_input.connect(func(e): _on_slot_input(index, e))
	
	return slot

func open(player_id: String) -> void:
	_player_id = player_id
	_refresh_inventory()
	show()

func close() -> void:
	hide()
	closed.emit()

func _refresh_inventory() -> void:
	if not InventoryService:
		return
	
	var items: Array = InventoryService.get_player_inventory(_player_id)
	
	# Clear all slots
	for slot in _slots:
		_clear_slot(slot)
	
	# Fill slots with items
	for i in range(mini(items.size(), _slots.size())):
		var item: Dictionary = items[i]
		_set_slot_item(i, item)
	
	# Update gold
	var gold: Label = get_node_or_null("Panel/GoldLabel")
	if gold:
		gold.text = "Gold: %d" % InventoryService.get_player_gold(_player_id)

func _clear_slot(slot: PanelContainer) -> void:
	var icon: TextureRect = slot.get_node_or_null("Icon")
	if icon:
		icon.texture = null
	var count: Label = slot.get_node_or_null("Count")
	if count:
		count.visible = false
	slot.tooltip_text = ""

func _set_slot_item(index: int, item: Dictionary) -> void:
	if index >= _slots.size():
		return
	
	var slot: PanelContainer = _slots[index]
	
	# Set icon (placeholder for now)
	var color := _get_rarity_color(item.get("rarity", "common"))
	var tex := _create_color_texture(color, SLOT_SIZE)
	
	var icon: TextureRect = slot.get_node_or_null("Icon")
	if icon:
		icon.texture = tex
	
	# Stack count
	var stack_size: int = item.get("stack_size", 1)
	var count: Label = slot.get_node_or_null("Count")
	if count and stack_size > 1:
		count.text = str(stack_size)
		count.visible = true
	
	# Tooltip
	var name: String = item.get("name", "Unknown Item")
	var rarity: String = item.get("rarity", "common")
	slot.tooltip_text = "%s [%s]" % [name, rarity]

func _get_rarity_color(rarity: String) -> Color:
	match rarity.to_lower():
		"common": return Color(0.6, 0.6, 0.6)
		"uncommon": return Color(0.2, 0.9, 0.2)
		"rare": return Color(0.2, 0.4, 1.0)
		"epic": return Color(0.6, 0.2, 0.9)
		"legendary": return Color(1.0, 0.6, 0.1)
		_: return Color(0.6, 0.6, 0.6)

func _create_color_texture(color: Color, size: int = 32) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var tex := ImageTexture.create_from_image(img)
	return tex

func _on_slot_input(slot_index: int, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_select_slot(slot_index)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_use_item(slot_index)

func _select_slot(index: int) -> void:
	# Deselect previous
	if _selected_slot >= 0 and _selected_slot < _slots.size():
		_set_slot_selected(_selected_slot, false)
	
	_selected_slot = index
	_set_slot_selected(index, true)
	
	# Update info
	var items: Array = InventoryService.get_player_inventory(_player_id) if InventoryService else []
	if index < items.size():
		var item: Dictionary = items[index]
		var info: Label = get_node_or_null("Panel/ItemInfo")
		if info:
			info.text = item.get("name", "Unknown")
	else:
		var info: Label = get_node_or_null("Panel/ItemInfo")
		if info:
			info.text = "Empty slot"

func _set_slot_selected(index: int, selected: bool) -> void:
	if index >= _slots.size():
		return
	
	var slot: PanelContainer = _slots[index]
	var style := slot.get_theme_stylebox("panel")
	if style:
		style.border_color = Color(1, 0.8, 0.2) if selected else Color(0.2, 0.2, 0.25)

func _use_item(slot_index: int) -> void:
	if not InventoryService:
		return
	
	var items: Array = InventoryService.get_player_inventory(_player_id)
	if slot_index < items.size():
		var item: Dictionary = items[slot_index]
		var result := InventoryService.use_item(_player_id, item.get("id", ""))
		if result.get("success", false):
			_refresh_inventory()

func _on_use_item() -> void:
	if _selected_slot >= 0:
		_use_item(_selected_slot)

func _on_equip_item() -> void:
	if _selected_slot >= 0 and InventoryService:
		var items: Array = InventoryService.get_player_inventory(_player_id)
		if _selected_slot < items.size():
			var item: Dictionary = items[_selected_slot]
			var result := InventoryService.equip_item(_player_id, item.get("id", ""))
			if result.get("success", false):
				_refresh_inventory()

func _on_drop_item() -> void:
	if _selected_slot >= 0 and InventoryService:
		var items: Array = InventoryService.get_player_inventory(_player_id)
		if _selected_slot < items.size():
			var item: Dictionary = items[_selected_slot]
			var result := InventoryService.drop_item(_player_id, item.get("id", ""))
			if result.get("success", false):
				_refresh_inventory()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		_selected_slot = -1
		closed.emit()
