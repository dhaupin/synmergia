## BlacksmithUI - Equipment repair interface
## Opened when player interacts with a BlacksmithNPC.
## Shows repairable equipment, costs, and executes repairs via BlacksmithService.
extends Control
class_name BlacksmithUI

const UIStyles = preload("res://ui/components/ui_styles.gd")

## Stub methods mirroring UIPanel -- real wiring via .tscn scene setup
var _is_open: bool = false
var _player_id: String = ""
signal panel_opened()
signal panel_closed()

func open(player_id: String) -> void:
	_player_id = player_id
	_is_open = true
	panel_opened.emit()

func close() -> void:
	_is_open = false
	panel_closed.emit()

func toggle(player_id: String) -> void:
	pass

func is_open() -> bool:
	return _is_open

func get_panel() -> PanelContainer:
	return null

func get_content() -> VBoxContainer:
	return null

func set_title(title: String) -> void:
	pass

func set_panel_size(size: Vector2) -> void:
	pass

func show_notification(msg: String, success: bool = true) -> void:
	pass

func _setup_panel() -> void:
	pass

func _setup_header() -> void:
	pass

func _setup_content() -> void:
	pass

func _setup_overlay() -> void:
	pass

func _on_open() -> void:
	pass

func _on_close() -> void:
	pass

var _inventory: InventoryComponent = null
var _offers_discount: bool = true
var _cost_modifier: float = 1.0

var _item_list: VBoxContainer
var _total_label: Label
var _gold_label: Label
var _repair_btn: Button
var _close_btn: Button

func _ready() -> void:
	set_title("The Smithy")
	set_panel_size(Vector2(420, 520))
	_setup_ui()
	_connect_signals()

func _setup_ui() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main: VBoxContainer = panel.get_node_or_null("Main")
	if not main:
		return
	var gold_row := HBoxContainer.new()
	gold_row.custom_minimum_size.y = 32
	main.add_child(gold_row)
	var gold_title := Label.new()
	gold_title.text = "Your Gold: "
	gold_title.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	gold_row.add_child(gold_title)
	_gold_label = Label.new()
	_gold_label.text = "0"
	_gold_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	gold_row.add_child(_gold_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold_row.add_child(spacer)
	var discount_badge := Label.new()
	discount_badge.text = "10% OFF!" if _offers_discount else ""
	discount_badge.add_theme_color_override("font_color", UIStyles.COLORS.success)
	gold_row.add_child(discount_badge)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 360
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	_item_list = VBoxContainer.new()
	_item_list.custom_minimum_size.y = 300
	scroll.add_child(_item_list)
	var summary_row := HBoxContainer.new()
	summary_row.custom_minimum_size.y = 36
	main.add_child(summary_row)
	var summary_title := Label.new()
	summary_title.text = "Total: "
	summary_title.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	summary_row.add_child(summary_title)
	_total_label = Label.new()
	_total_label.text = "0"
	_total_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	summary_row.add_child(_total_label)
	var btn_row := HBoxContainer.new()
	btn_row.custom_minimum_size.y = 44
	main.add_child(btn_row)
	_repair_btn = Button.new()
	_repair_btn.text = "Repair All"
	_repair_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_repair_btn.pressed.connect(_on_repair_all_pressed)
	btn_row.add_child(_repair_btn)
	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close_btn.pressed.connect(_on_close_pressed)
	btn_row.add_child(_close_btn)

func _connect_signals() -> void:
	var bs = BlacksmithService if BlacksmithService else null
	if not bs:
		return
	if bs.has_signal("repair_completed"):
		if not bs.repair_completed.is_connected(_on_repair_completed):
			bs.repair_completed.connect(_on_repair_completed)
	if bs.has_signal("repair_failed"):
		if not bs.repair_failed.is_connected(_on_repair_failed):
			bs.repair_failed.connect(_on_repair_failed)
	if InventoryService:
		if not InventoryService.inventory_updated.is_connected(_refresh_items):
			InventoryService.inventory_updated.connect(_refresh_items)

func open_for_player(player_id: String) -> void:
	_player_id = player_id
	_is_open = true
	_show()
	_refresh_items()

func _show() -> void:
	visible = true

func _hide_panel() -> void:
	visible = false
	_is_open = false

func toggle_for_player(player_id: String) -> void:
	if _is_open and _player_id == player_id:
		_hide_panel()
	else:
			open_for_player(player_id)

func _on_repair_all_pressed() -> void:
	if not _player_id:
		return
	if not BlacksmithService:
		return
	var items := _get_repairable_items()
	if items.is_empty():
		show_notification("No items need repair", false)
		return
	var cost := _calculate_total_cost(items)
	if cost <= 0:
		show_notification("No items need repair", false)
		return
	var gold := 0
	if PlayerManager and PlayerManager.has_player(_player_id):
		var player = PlayerManager.get_player(_player_id)
		if player and player.has("gold"):
			gold = int(player.get("gold", 0))
	if gold < cost:
		show_notification("Not enough gold", false)
		return
	BlacksmithService.repair_all(_player_id, items)

func _on_close_pressed() -> void:
	_hide_panel()
	panel_closed.emit()

func _refresh_items() -> void:
	if not _item_list:
		return
	for child in _item_list.get_children():
		child.queue_free()
	var items := _get_repairable_items()
	if items.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "All items are fully repaired"
		empty_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		_item_list.add_child(empty_lbl)
		_total_label.text = "0"
		return
	for item in items:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 32
		_item_list.add_child(row)
		var name_lbl := Label.new()
		name_lbl.text = item.get("name", "Unknown")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var dur_label := Label.new()
		var max_dur = item.get("max_durability", 100)
		var dur = item.get("durability", max_dur)
		dur_label.text = "%d/%d" % [dur, max_dur]
		dur_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		row.add_child(dur_label)
		var item_cost = int((1.0 - float(dur) / float(max_dur)) * 50 * _cost_modifier)
		var cost_label := Label.new()
		cost_label.text = "%d g" % item_cost
		cost_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
		row.add_child(cost_label)
	var total := _calculate_total_cost(items)
	_total_label.text = "%d g" % total

func _get_repairable_items() -> Array:
	var items := []
	if not _inventory:
		return items
	var inv_items = _inventory.get_all_items()
	for item in inv_items:
		if item.get("durability", 100) < item.get("max_durability", 100):
			if item.get("item_type", "") in ["weapon", "armor", "accessory"]:
				items.append(item)
	return items

func _calculate_total_cost(items: Array) -> int:
	var total := 0
	for item in items:
		var max_dur = item.get("max_durability", 100)
		var dur = item.get("durability", max_dur)
		total += int((1.0 - float(dur) / float(max_dur)) * 50 * _cost_modifier)
	return total

func _on_repair_completed(_p: String, _i: int, _c: int) -> void:
	_refresh_items()
	show_notification("Items repaired", true)

func _on_repair_failed(_p: String, _r: String) -> void:
	show_notification(_r, false)

func _on_inventory_changed() -> void:
	_refresh_items()
