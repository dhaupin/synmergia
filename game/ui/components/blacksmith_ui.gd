## BlacksmithUI - Equipment repair interface
## Opened when player interacts with an NPC that has a blacksmith offering.
## Shows repairable equipment, costs, and executes repairs via BlacksmithService.
extends "res://ui/components/ui_panel.gd"

class_name BlacksmithUI

const UIPanel = preload("res://ui/components/ui_panel.gd")
const InventoryComponent = preload("res://core/components/inventory_component.gd")

var _inventory: InventoryComponent = null
var _offers_discount: bool = true
var _cost_modifier: float = 1.0

var _npc_position: Vector3 = Vector3.ZERO
var _proximity_enabled: bool = false

## Context passed by PlayerController at interaction time. Assigns the
## repair list's inventory source and the NPC's pricing. Previously
## player_controller called open_with_context(), a method this class
## never had, so the context silently never applied and _inventory
## stayed null (repair list always empty).
func open_with_context(player_id: String, inventory: InventoryComponent,
		cost_modifier: float = 1.0, offers_discount: bool = true) -> void:
	_inventory = inventory
	_cost_modifier = cost_modifier
	_offers_discount = offers_discount
	open(player_id)
	_refresh_items()

## MenuManager hotkey path: no NPC context, just the player's bag so
## the repair list has a data source.
func set_inventory(inventory: InventoryComponent) -> void:
	_inventory = inventory
	_refresh_items()

const ItemScript = preload("res://core/schemas/item.gd")

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


func _ready() -> void:
	super._ready()
	_setup_accessibility()


## ============================================================================
## ACCESSIBILITY
## ============================================================================

func _setup_accessibility() -> void:
	pass

func update_accessibility_settings(high_contrast: bool, text_scale: float, reduce_motion: bool) -> void:
	# Update focus styles for buttons and item list
	for btn in [_repair_btn, _close_btn]:
		if btn and is_instance_valid(btn):
			btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	
	# Update item list focus styles
	if _item_list:
		for child in _item_list.get_children():
			if child is PanelContainer:
				child.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
				var style: StyleBoxFlat = child.get_theme_stylebox("panel")
				if style:
					if high_contrast:
						style.bg_color = UIStyles.HIGH_CONTRAST_COLORS.background
						style.border_color = UIStyles.HIGH_CONTRAST_COLORS.border
					else:
						style.bg_color = UIStyles.COLORS.background_dark
						style.border_color = UIStyles.COLORS.border
			
			# Update text sizes
			var scale = UIStyles.get_text_scale()
			for label_name in ["ItemName", "Durability", "Cost"]:
				var label: Label = child.get_node_or_null(label_name)
				if label:
					var current_size := label.get_theme_font_size("font_size")
					if current_size > 0:
						label.add_theme_font_size_override("font_size", int(current_size * scale))


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
	# Use canonical distance check with configurable threshold
	if not check_interact_distance(player.global_position, _npc_position):
		close()
		var ns = get_node_or_null("/root/NotificationService")
		if ns:
			var NotifKind = load("res://core/notifications/notification_kind.gd").NotifKind
			ns.notify(NotifKind.CUSTOM, "Moved too far from the blacksmith.",
				"BlacksmithUI", "bs_out_of_range", {}, _player_id)



func _on_open() -> void:
	_refresh_items()

	var bs = get_node_or_null("/root/BlacksmithService")
	if not bs:
		return
	if bs.has_signal("repair_completed"):
		if not bs.repair_completed.is_connected(_on_repair_completed):
			bs.repair_completed.connect(_on_repair_completed)
	if bs.has_signal("repair_failed"):
		if not bs.repair_failed.is_connected(_on_repair_failed):
			bs.repair_failed.connect(_on_repair_failed)
	var inv = get_node_or_null("/root/InventoryService")
	if inv:
		# InventoryService has no inventory_updated signal (that is on the
		# per-player InventoryComponent); subscribe to the component's
		# item signals instead so the list refreshes on changes.
		var comp = inv.get_inventory(_player_id) if inv.has_method("get_inventory") else null
		if comp:
			if not comp.item_added.is_connected(_on_inventory_changed):
				comp.item_added.connect(_on_inventory_changed)
			if not comp.item_removed.is_connected(_on_inventory_changed):
				comp.item_removed.connect(_on_inventory_changed)
			if not comp.gold_changed.is_connected(_on_inventory_changed):
				comp.gold_changed.connect(_on_inventory_changed)


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
	var bs = get_node_or_null("/root/BlacksmithService")
	if not bs:
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
	var pm = get_node_or_null("/root/PlayerManager")
	if pm and pm.has_player(_player_id):
		var player = pm.get_player(_player_id)
		if player and player.has("gold"):
			gold = int(player.get("gold", 0))
	if gold < cost:
		show_notification("Not enough gold", false)
		return
	bs.repair_all(_player_id, items)


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
	# Repairable category law: WEAPON/ARMOR/ACCESSORY ItemCategory ids
	# (0/1/2). The old filter matched a nonexistent item_type STRING
	# property with two-arg gets -- both fatal on typed Items: the
	# two-arg Variant get throws and "" matched nothing, so the smithy
	# list was EMPTY whenever it ran through a typed-bag path.
	var repairable_ids := [
		ItemScript.ItemCategory.WEAPON,
		ItemScript.ItemCategory.ARMOR,
		ItemScript.ItemCategory.ACCESSORY,
	]
	var inv_items = _inventory.get_all_items()
	for item in inv_items:
		if item == null:
			continue
		var max_dur_raw = item.get("max_durability")
		var max_dur := int(max_dur_raw) if max_dur_raw != null else 100
		var dur_raw = item.get("durability")
		var dur := int(dur_raw) if dur_raw != null else 100
		var cat_raw = item.get("item_category")
		var cat := int(cat_raw) if cat_raw != null else -1
		if cat in repairable_ids and dur < max_dur:
			items.append(item)
	return items

func _calculate_total_cost(items: Array) -> int:
	var total := 0
	for item in items:
		# One-arg get + null-coalesce (typed Items; see the list filter).
		var max_dur_raw = item.get("max_durability")
		var max_dur := int(max_dur_raw) if max_dur_raw != null else 100
		var dur_raw = item.get("durability")
		var dur := int(dur_raw) if dur_raw != null else max_dur
		total += int((1.0 - float(dur) / float(max_dur)) * 50 * _cost_modifier)
	return total

func _on_repair_completed(_p: String, _i: int, _c: int) -> void:
	_refresh_items()
	show_notification("Items repaired", true)

func _on_repair_failed(_p: String, _r: String) -> void:
	show_notification(_r, false)

func _on_inventory_changed() -> void:
	_refresh_items()
