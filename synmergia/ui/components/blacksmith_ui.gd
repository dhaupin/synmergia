## BlacksmithUI - Equipment repair interface
## Opened when player interacts with a BlacksmithNPC.
## Shows repairable equipment, costs, and executes repairs via BlacksmithService.
class_name BlacksmithUI

const UIPanel = preload("res://ui/components/ui_panel.gd")
extends UIPanel

var _player_id: String = ""
var _inventory: InventoryComponent = null
var _offers_discount: bool = true
var _cost_modifier: float = 1.0

var _item_list: VBoxContainer
var _total_label: Label
var _gold_label: Label
var _repair_btn: Button
var _close_btn: Button

func _ready() -> void:
	super._ready()
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

	# Gold display row
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

	# Discount badge
	var discount_badge := Label.new()
	discount_badge.text = "10% Bulk Discount!"
	discount_badge.add_theme_color_override("font_color", UIStyles.COLORS.text_success)
	discount_badge.visible = false
	discount_badge.name = "DiscountBadge"
	gold_row.add_child(discount_badge)

	# Item scroll area
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 320
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)

	var scroll_hbox := HBoxContainer.new()
	scroll.add_child(scroll_hbox)

	_item_list = VBoxContainer.new()
	_item_list.custom_minimum_size.x = 380
	_item_list.add_theme_constant_override("separation", 4)
	scroll_hbox.add_child(_item_list)

	# Summary row
	var summary_row := HBoxContainer.new()
	summary_row.custom_minimum_size.y = 36
	main.add_child(summary_row)

	var summary_title := Label.new()
	summary_title.text = "Total Cost: "
	summary_title.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	summary_row.add_child(summary_title)

	_total_label = Label.new()
	_total_label.text = "0"
	_total_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	summary_row.add_child(_total_label)

	spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_row.add_child(spacer)

	# Button row
	var btn_row := HBoxContainer.new()
	btn_row.custom_minimum_size.y = 44
	main.add_child(btn_row)

	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.custom_minimum_size.x = 100
	_close_btn.pressed.connect(_on_close_pressed)
	btn_row.add_child(_close_btn)

	spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	_repair_btn = Button.new()
	_repair_btn.text = "Repair All"
	_repair_btn.custom_minimum_size.x = 120
	_repair_btn.pressed.connect(_on_repair_pressed)
	btn_row.add_child(_repair_btn)

func _connect_signals() -> void:
	var bs = BlacksmithService.get_instance() if BlacksmithService else null
	if not bs:
		return
	if bs.has_signal("repair_completed"):
		if not bs.repair_completed.is_connected(_on_repair_completed):
			bs.repair_completed.connect(_on_repair_completed)
	if bs.has_signal("repair_failed"):
		if not bs.repair_failed.is_connected(_on_repair_failed):
			bs.repair_failed.connect(_on_repair_failed)
	if bs.has_signal("item_too_broken"):
		if not bs.item_too_broken.is_connected(_on_item_too_broken):
			bs.item_too_broken.connect(_on_item_too_broken)




func _on_item_too_broken(player_id: String, item_id: String) -> void:
	show_notification("Item too damaged to repair", false)
func _on_repair_completed(_player_id: String, _items_repaired: int, _total_cost: int) -> void:
	if is_open():
		_refresh()


func _on_repair_failed(_player_id: String, _reason: String) -> void:
	if is_open():
		_refresh()

func open_with_context(player_id: String, inventory: InventoryComponent, cost_modifier: float = 1.0, offers_discount: bool = true) -> void:
	_player_id = player_id
	_inventory = inventory
	_cost_modifier = cost_modifier
	_offers_discount = offers_discount
	_refresh()

func refresh() -> void:
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(_inventory):
		_clear_items()
		_update_gold(0)
		_update_total(0)
		return

	_update_gold(_inventory.get_gold())
	_clear_items()

	var bs := BlacksmithService.get_instance()
	if not bs:
		_update_total(0)
		return

	var preview: Dictionary = bs.get_repair_preview(_inventory, _offers_discount)
	var items: Array = preview.get("items", [])
	var adjusted_cost: int = int(preview.get("total_cost", 0) * _cost_modifier)
	var has_discount: bool = preview.get("discount_applied", false)
	var player_gold: int = _inventory.get_gold()

	# Show/hide discount badge
	var panel := get_panel()
	if panel:
		var badge := panel.get_node_or_null("Main/DiscountBadge")
		if badge is Label:
			badge.visible = has_discount

	for item_data in items:
		_add_item_row(item_data)

	_update_total(adjusted_cost)

	_repair_btn.disabled = items.is_empty() or player_gold < adjusted_cost

func _add_item_row(item_data: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 36

	# Durability bar background
	var dur_bar_bg := ColorRect.new()
	dur_bar_bg.custom_minimum_size.x = 60
	dur_bar_bg.custom_minimum_size.y = 12
	dur_bar_bg.color = Color(0.2, 0.2, 0.2)
	row.add_child(dur_bar_bg)

	# Durability bar fill
	var current: int = item_data.get("current_durability", 0)
	var max_dur: int = item_data.get("max_durability", 100)
	var pct: float = float(current) / float(max_dur) if max_dur > 0 else 0.0
	var is_broken: bool = item_data.get("is_broken", false)

	var dur_bar_fill := ColorRect.new()
	dur_bar_fill.custom_minimum_size.x = max(0, int(60 * pct))
	dur_bar_fill.custom_minimum_size.y = 12
	if is_broken:
		dur_bar_fill.color = Color(0.8, 0.1, 0.1)
	elif pct < 0.3:
		dur_bar_fill.color = Color(0.9, 0.6, 0.1)
	else:
		dur_bar_fill.color = Color(0.2, 0.7, 0.2)
	row.add_child(dur_bar_fill)

	# Durability text
	var dur_label := Label.new()
	dur_label.text = "%d/%d" % [current, max_dur]
	dur_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	dur_label.custom_minimum_size.x = 70
	row.add_child(dur_label)

	# Item name
	var item_name := Label.new()
	item_name.text = item_data.get("item_name", "?")
	if is_broken:
		item_name.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	else:
		item_name.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(item_name)

	# Cost
	var cost_label := Label.new()
	cost_label.text = "%d g" % [item_data.get("cost", 0)]
	cost_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_label.custom_minimum_size.x = 60
	row.add_child(cost_label)

	_item_list.add_child(row)

func _clear_items() -> void:
	for child in _item_list.get_children():
		_item_list.remove_child(child)
		child.queue_free()

func _update_gold(amount: int) -> void:
	if _gold_label:
		_gold_label.text = str(amount)

func _update_total(amount: int) -> void:
	if _total_label:
		_total_label.text = "%d g" % amount

func _on_close_pressed() -> void:
	close()

func _on_repair_pressed() -> void:
	if not is_instance_valid(_inventory) or _inventory == null:
		return

	var bs := BlacksmithService.get_instance()
	if not bs:
		return

	var result: Dictionary = bs.repair_all_equipped(_player_id, _inventory, _offers_discount)

	if result.get("success", false):
		show_notification("Repaired %d items for %d gold!" % [
			result.get("items_repaired", 0),
			result.get("total_cost", 0)
		])
		_refresh()
	else:
		show_notification(result.get("reason", "Repair failed"), false)
		_repair_btn.disabled = true
