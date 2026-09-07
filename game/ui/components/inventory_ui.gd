## InventoryUI - Player inventory panel
## Migrated onto UIPanel base class.
extends UIPanel
class_name InventoryUI
const UIStyles = preload("res://ui/components/ui_styles.gd")
const InventoryComponent = preload("res://core/components/inventory_component.gd")
const Item = preload("res://core/schemas/item.gd")
const IconResolver = preload("res://core/utils/icon_resolver.gd")


const COLS: int = 5
const ROWS: int = 6
const SLOT_SIZE: int = 50

var _grid: GridContainer
var _slots: Array = []
var _selected_slot: int = -1
var _info_label: Label
var _gold_label: Label

signal item_selected(slot_index: int, item_id: String)
signal item_used(slot_index: int, item_id: String)
signal item_dropped(slot_index: int, item_id: String)

var _inv_bind_done := false

func _bind_service_signals() -> void:
	if _inv_bind_done or not is_instance_valid(InventoryService):
		return
	_inv_bind_done = true
	InventoryService.item_transferred.connect(_on_inventory_changed)
	InventoryService.gold_transferred.connect(_on_inventory_changed)

func _on_inventory_changed(...) -> void:
	_refresh_inventory()

func _setup_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_left = -470
	panel.custom_minimum_size = Vector2(440, 520)
	panel.add_theme_stylebox_override("panel", UIStyles.create_panel_style())
	panel.name = "Panel"
	add_child(panel)

	var main := VBoxContainer.new()
	main.name = "Main"
	panel.add_child(main)

	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = COLS
	_grid.custom_minimum_size.y = SLOT_SIZE * ROWS
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_grid)

	for i in range(COLS * ROWS):
		var slot := _create_slot(i)
		_grid.add_child(slot)
		_slots.append(slot)

	var info_panel := HBoxContainer.new()
	info_panel.custom_minimum_size.y = 60
	main.add_child(info_panel)

	_info_label = Label.new()
	_info_label.name = "ItemInfo"
	_info_label.text = "Select an item"
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_panel.add_child(_info_label)

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

func _setup_header() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main := panel.get_node_or_null("Main") as VBoxContainer
	if not main:
		return

	var header := HBoxContainer.new()
	header.name = "Header"
	main.add_child(header)
	main.move_child(header, 0)

	var title := Label.new()
	title.text = "Inventory"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_gold_label = Label.new()
	_gold_label.text = "Gold: 0"
	_gold_label.name = "GoldLabel"
	_gold_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	header.add_child(_gold_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

func _on_open() -> void:
	_bind_service_signals()
	_refresh_inventory()

func _on_close() -> void:
	_selected_slot = -1

func refresh_inventory() -> void:
	_refresh_inventory()

func _refresh_inventory() -> void:
	var comp: InventoryComponent = _get_inventory_component()
	var items: Array = []
	if comp:
		var count: int = comp.get_inventory_count()
		for i in range(count):
			var item: Item = comp.get_item(i)
			if item:
				items.append(item)

	for slot in _slots:
		_clear_slot(slot)

	for i in range(mini(items.size(), _slots.size())):
		_set_slot_item(i, items[i])

	if _gold_label:
		var gold: int = 0
		if comp:
			gold = comp.get_gold()
		_gold_label.text = "Gold: %d" % gold

func _get_inventory_component() -> InventoryComponent:
	if not InventoryService or _player_id == "":
		return null
	return InventoryService.get_inventory(_player_id)

func _create_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.add_theme_stylebox_override("panel", UIStyles.create_panel_style(
		UIStyles.COLORS.background_dark,
		UIStyles.COLORS.border,
		1,
		4
	))

	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.name = "Icon"
	slot.add_child(icon)

	var count := Label.new()
	count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -25
	count.offset_right = -5
	count.offset_top = -20
	count.offset_bottom = -5
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.add_theme_font_size_override("font_size", 12)
	count.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	count.name = "Count"
	count.visible = false
	slot.add_child(count)

	slot.gui_input.connect(func(e: InputEvent) -> void: _on_slot_input(index, e))
	return slot

func _clear_slot(slot: PanelContainer) -> void:
	var icon: TextureRect = slot.get_node_or_null("Icon")
	if icon:
		icon.texture = null
	var count: Label = slot.get_node_or_null("Count")
	if count:
		count.visible = false
	slot.tooltip_text = ""

func _set_slot_item(index: int, item: Item) -> void:
	if index >= _slots.size() or item == null:
		return

	var slot: PanelContainer = _slots[index]

	var icon: TextureRect = slot.get_node_or_null("Icon")
	if icon:
		icon.texture = _get_item_icon(item)

	var stack_size: int = item.current_stack if item.current_stack > 0 else item.stack_size
	var count: Label = slot.get_node_or_null("Count")
	if count and stack_size > 1:
		count.text = str(stack_size)
		count.visible = true

	slot.tooltip_text = "%s [%s]" % [item.display_name, _rarity_name(item.rarity)]

func _rarity_name(rarity: int) -> String:
	match rarity:
		Item.Rarity.COMMON: return "common"
		Item.Rarity.UNCOMMON: return "uncommon"
		Item.Rarity.RARE: return "rare"
		Item.Rarity.EPIC: return "epic"
		Item.Rarity.LEGENDARY: return "legendary"
		_: return "common"

func _get_rarity_color(rarity: int) -> Color:
	match rarity:
		Item.Rarity.COMMON: return Color(0.6, 0.6, 0.6)
		Item.Rarity.UNCOMMON: return Color(0.2, 0.9, 0.2)
		Item.Rarity.RARE: return Color(0.2, 0.4, 1.0)
		Item.Rarity.EPIC: return Color(0.6, 0.2, 0.9)
		Item.Rarity.LEGENDARY: return Color(1.0, 0.6, 0.1)
		_: return Color(0.6, 0.6, 0.6)

func _get_item_icon(item: Item) -> Texture2D:
	return IconResolver.get_item_icon(item)

func _on_slot_input(slot_index: int, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: _select_slot(slot_index)
			MOUSE_BUTTON_RIGHT: _use_item(slot_index)
	elif event is InputEventScreenTouch and event.pressed:
		_select_slot(slot_index)

func _select_slot(index: int) -> void:
	if _selected_slot >= 0 and _selected_slot < _slots.size():
		_set_slot_selected(_selected_slot, false)
	_selected_slot = index
	_set_slot_selected(index, true)

	var comp: InventoryComponent = _get_inventory_component()
	if not _info_label:
		return
	if comp and index < comp.get_inventory_count():
		var item: Item = comp.get_item(index)
		_info_label.text = item.display_name if item else "Empty slot"
	else:
		_info_label.text = "Empty slot"

func _set_slot_selected(index: int, selected: bool) -> void:
	if index >= _slots.size():
		return
	var slot: PanelContainer = _slots[index]
	var style := slot.get_theme_stylebox("panel")
	if style:
		style.border_color = UIStyles.COLORS.accent_gold if selected else UIStyles.COLORS.border

func _use_item(slot_index: int) -> void:
	var comp: InventoryComponent = _get_inventory_component()
	if not comp:
		return
	if slot_index < comp.get_inventory_count():
		# Phase C will wire InventoryComponent.item_used signal back to refresh.
		# For now, mark the slot dropped so the user sees feedback.
		var item: Item = comp.get_item(slot_index)
		if item and comp.remove_item(slot_index) != null:
			item_used.emit(slot_index, item.id)
			_refresh_inventory()

func _on_use_item() -> void:
	if _selected_slot >= 0:
		_use_item(_selected_slot)

func _on_equip_item() -> void:
	if _selected_slot < 0:
		return
	var comp: InventoryComponent = _get_inventory_component()
	if not comp:
		return
	if _selected_slot < comp.get_inventory_count():
		if comp.equip_item(_selected_slot):
			_refresh_inventory()

func _on_drop_item() -> void:
	if _selected_slot < 0:
		return
	var comp: InventoryComponent = _get_inventory_component()
	if not comp:
		return
	if _selected_slot < comp.get_inventory_count():
		var item: Item = comp.get_item(_selected_slot)
		if item and comp.remove_item(_selected_slot) != null:
			item_dropped.emit(_selected_slot, item.id)
			_refresh_inventory()
