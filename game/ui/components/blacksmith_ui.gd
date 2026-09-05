## BlacksmithUI - Equipment repair interface
## Opened when player interacts with an NPC that has a blacksmith offering.
## Shows repairable equipment, costs, and executes repairs via BlacksmithService.
extends UIPanel

class_name BlacksmithUI

const UIPanel = preload("res://ui/components/ui_panel.gd")
const UIStyles = preload("res://ui/components/ui_styles.gd")

var _inventory: InventoryComponent = null
var _offers_discount: bool = true
var _cost_modifier: float = 1.0

var _npc_position: Vector3 = Vector3.ZERO
var _proximity_enabled: bool = false

var _item_list: VBoxContainer
var _total_label: Label
var _gold_label: Label
var _repair_btn: Button
var _close_btn: Button

func _setup_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 520)
	panel.add_theme_stylebox_override("panel", UIStyles.create_panel_style(
		UIStyles.COLORS.background_dark,
		UIStyles.COLORS.border, 2, 12
	))
	panel.name = "Panel"
	add_child(panel)

	var main := VBoxContainer.new()
	main.name = "Main"
	panel.add_child(main)

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
	title.text = "The Smithy"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

func _setup_content() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main: VBoxContainer = panel.get_node_or_null("Main") as VBoxContainer
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
	scroll.custom_minimum_size.y = 340
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
	_close_btn.pressed.connect(close)
	btn_row.add_child(_close_btn)

func _process(_delta: float) -> void:
	if not _proximity_enabled or _npc_position == Vector3.ZERO:
		return
	var player := _get_local_player()
	if player == null:
		return
	if player.global_position.distance_to(_npc_position) > 8.0:
		close()
		if NotificationService:
			var NotifKind = load("res://core/notifications/notification_kind.gd").NotifKind
			NotificationService.notify(NotifKind.CUSTOM, "Moved too far from the blacksmith.",
				"BlacksmithUI", "bs_out_of_range", {}, _player_id)


func _get_local_player() -> Node:
	if PlayerManager and PlayerManager.has_method("get_local_player"):
		return PlayerManager.get_local_player()
	return null


func _on_open() -> void:
	_connect_signals()
	_refresh_items()

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


func set_npc_proximity(pos: Vector3) -> void:
	_npc_position = pos
	_proximity_enabled = true


func open_for_player(player_id: String) -> void:
	open(player_id)
	_refresh_items()

func toggle_for_player(player_id: String) -> void:
	toggle(player_id)

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
	close()

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
