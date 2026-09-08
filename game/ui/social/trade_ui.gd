## TradeUI - Item trading panel
## Migrated onto UIPanel base class.
extends "res://ui/components/ui_panel.gd"
const UIPanel = preload("res://ui/components/ui_panel.gd")
class_name TradeUI

enum TradeState { IDLE, PROPOSING, COUNTER_OFFER, ACCEPTED, CONFIRMING, COMPLETED, CANCELED }

var _initiator_id: String = ""
var _target_id: String = ""
var _trade_id: String = ""
var _initiator_items: ItemList
var _target_items: ItemList
var _initiator_gold: int = 0
var _target_gold: int = 0
var _trade_state: int = TradeState.IDLE
var _status_value: Label
var _gold_label: Label
var _their_gold_label: Label
var _confirm_btn: Button
var _cancel_btn: Button
var _lock_btn: Button
var _my_confirmed: bool = false
var _their_confirmed: bool = false

signal trade_completed(initiator_id: String, target_id: String)
signal trade_canceled()
signal closed()  # Alias of panel_closed for back-compat.

func _ready() -> void:
	super._ready()
	panel_closed.connect(func() -> void: closed.emit())
	_bind_service_signals()


func _bind_service_signals() -> void:
	if not TradeService:
		return
	var sigs := {
		"trade_started": _on_trade_started,
		"trade_completed": _on_trade_completed,
		"trade_cancelled": _on_trade_cancelled,
		"trade_expired": _on_trade_expired,
		"item_added_to_trade": _on_item_added_to_trade,
		"item_removed_from_trade": _on_item_removed_from_trade,
		"gold_added_to_trade": _on_gold_added_to_trade,
		"gold_removed_from_trade": _on_gold_removed_from_trade,
		"trade_confirmed": _on_trade_confirmed,
		"trade_unconfirmed": _on_trade_unconfirmed,
		"confirmation_countdown_tick": _on_countdown_tick,
	}
	for sig_name in sigs:
		if TradeService.has_signal(sig_name):
			var handler = sigs[sig_name]
			if not TradeService.get(sig_name).is_connected(handler):
				TradeService.get(sig_name).connect(handler)



func _on_trade_started(trade_id: String, player1: String, player2: String) -> void:
	# Sync trade state when trade actually begins (both players accepted).
	_trade_id = trade_id
	_trade_state = TradeState.ACCEPTED
	_my_confirmed = false
	_their_confirmed = false
	_update_confirm_button()
	_update_status("Trade started with %s" % _target_id)

func _on_item_added_to_trade(trade_id: String, player_id: String, item_id: String, quantity: int) -> void:
	if _trade_id == trade_id and is_open():
		_refresh_items()

func _on_item_removed_from_trade(trade_id: String, player_id: String, item_id: String, quantity: int) -> void:
	if _trade_id == trade_id and is_open():
		_refresh_items()

func _on_gold_added_to_trade(trade_id: String, player_id: String, amount: int) -> void:
	if _trade_id == trade_id and is_open():
		_refresh_gold()
		_unconfirm_if_needed(player_id)

func _on_gold_removed_from_trade(trade_id: String, player_id: String, amount: int) -> void:
	if _trade_id == trade_id and is_open():
		_refresh_gold()
		_unconfirm_if_needed(player_id)

func _refresh_gold() -> void:
	if not TradeService or _trade_id.is_empty():
		return
	var trade: Dictionary = TradeService.get_trade(_trade_id)
	if trade.is_empty():
		return
	var my_id := _initiator_id
	var is_p1 := trade.get("player1") == my_id
	var my_gold := trade.get("player1_gold", 0) if is_p1 else trade.get("player2_gold", 0)
	var their_gold := trade.get("player2_gold", 0) if is_p1 else trade.get("player1_gold", 0)
	_initiator_gold = my_gold
	_target_gold = their_gold
	_update_gold_labels()

func _on_trade_confirmed(trade_id: String, player_id: String) -> void:
	if _trade_id == trade_id and is_open():
		var my_id := _initiator_id
		if player_id == my_id:
			_my_confirmed = true
			_update_confirm_button()
		else:
			_their_confirmed = true
		_update_status("Trade confirmed by %s" % player_id if player_id != my_id else "You confirmed. Waiting...")
		_update_confirm_visual()

func _on_trade_unconfirmed(trade_id: String, player_id: String) -> void:
	if _trade_id == trade_id and is_open():
		var my_id := _initiator_id
		if player_id == my_id:
			_my_confirmed = false
			_update_confirm_button()
		else:
			_their_confirmed = false
		_update_status("Trade unconfirmed by %s" % player_id if player_id != my_id else "Waiting for both to confirm...")
		_update_confirm_visual()

func _on_countdown_tick(trade_id: String, seconds_remaining: float) -> void:
	if _trade_id == trade_id and is_open():
		_update_status("Confirm in %.0fs..." % seconds_remaining)

func _update_confirm_button() -> void:
	if not _confirm_btn:
		return
	var state := _my_confirmed
	_confirm_btn.text = "✓ Confirmed" if state else "Confirm Trade"
	_confirm_btn.disabled = state

	# Visual feedback for my confirmation
	if _confirm_btn.has_theme_stylebox_override("normal"):
		var style = _confirm_btn.get_theme_stylebox("normal") as StyleBoxFlat
		if style:
			if state:
				style.bg_color = UIStyles.COLORS.success * 0.5
			else:
				style.bg_color = UIStyles.COLORS.background_dark

func _unconfirm_if_needed(player_id: String) -> void:
	# If the OTHER party changes their offer, unconfirm them
	var trade: Dictionary = TradeService.get_trade(_trade_id) if TradeService else {}
	if trade.is_empty():
		return
	var my_id := _initiator_id
	var is_p1 := trade.get("player1") == my_id
	if player_id != my_id:
		if is_p1:
			trade["player2_confirmed"] = false
		else:
			trade["player1_confirmed"] = false
		_their_confirmed = false
	_update_confirm_visual()

func _update_confirm_visual() -> void:
	# Update UI to show confirm status
	var trade: Dictionary = TradeService.get_trade(_trade_id) if TradeService else {}
	if trade.is_empty():
		return
	var my_id := _initiator_id
	var is_p1 := trade.get("player1") == my_id
	var p1_conf := trade.get("player1_confirmed", false)
	var p2_conf := trade.get("player2_confirmed", false)
	var my_conf := p1_conf if is_p1 else p2_conf
	var their_conf := p2_conf if is_p1 else p1_conf

	if my_conf and their_conf:
		_update_status("Both confirmed! Executing trade...")
		_complete_trade()

func _on_trade_completed(_trade_id: String, _trades: Dictionary) -> void:
	trade_completed.emit(_initiator_id, _target_id)
	close()


func _on_trade_cancelled(_trade_id: String, _cancelled_by: String) -> void:
	trade_canceled.emit()
	close()


func _on_trade_expired(_trade_id: String) -> void:
	trade_canceled.emit()
	close()

func _setup_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(600, 400)
	panel.add_theme_stylebox_override("panel", UIStyles.create_panel_style(
		UIStyles.COLORS.background_dark,
		UIStyles.COLORS.border,
		2,
		12
	))
	panel.name = "Panel"
	add_child(panel)

	var main := HBoxContainer.new()
	main.name = "Main"
	panel.add_child(main)

	var left_vbox := VBoxContainer.new()
	left_vbox.custom_minimum_size.x = 250
	left_vbox.name = "YourOffer"
	main.add_child(left_vbox)

	var your_label := Label.new()
	your_label.text = "Your Offer"
	your_label.add_theme_font_size_override("font_size", 16)
	left_vbox.add_child(your_label)

	_initiator_items = ItemList.new()
	_initiator_items.custom_minimum_size.y = 250
	left_vbox.add_child(_initiator_items)

	_gold_label = Label.new()
	_gold_label.text = "Gold: 0"
	_gold_label.name = "GoldLabel"
	left_vbox.add_child(_gold_label)

	var left_btns := HBoxContainer.new()
	left_vbox.add_child(left_btns)

	var add_item_btn := Button.new()
	add_item_btn.text = "+ Item"
	add_item_btn.pressed.connect(_on_add_item)
	left_btns.add_child(add_item_btn)

	var add_gold_btn := Button.new()
	add_gold_btn.text = "+ Gold"
	add_gold_btn.pressed.connect(_on_add_gold)
	left_btns.add_child(add_gold_btn)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.name = "Center"
	main.add_child(center)

	var status_label := Label.new()
	status_label.text = "Trade Status"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(status_label)

	_status_value = Label.new()
	_status_value.text = "Waiting..."
	_status_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_value.name = "StatusValue"
	center.add_child(_status_value)

	var center_spacer := Control.new()
	center_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(center_spacer)

	var accept_btn := Button.new()
	accept_btn.text = "Accept Trade"
	accept_btn.custom_minimum_size.y = 40
	accept_btn.pressed.connect(_on_accept)
	center.add_child(accept_btn)
	_confirm_btn = accept_btn

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel)
	center.add_child(cancel_btn)
	_cancel_btn = cancel_btn

	var right_vbox := VBoxContainer.new()
	right_vbox.custom_minimum_size.x = 250
	right_vbox.name = "TheirOffer"
	main.add_child(right_vbox)

	var their_label := Label.new()
	their_label.text = "Their Offer"
	their_label.add_theme_font_size_override("font_size", 16)
	right_vbox.add_child(their_label)

	_target_items = ItemList.new()
	_target_items.custom_minimum_size.y = 250
	right_vbox.add_child(_target_items)

	_their_gold_label = Label.new()
	_their_gold_label.text = "Gold: -"
	_their_gold_label.name = "TheirGoldLabel"
	right_vbox.add_child(_their_gold_label)

func _setup_header() -> void:
	# TradeUI is a special case: the "main" content is HBoxContainer (not VBox),
	# so we inject a top banner via a VBox wrapper. Easiest approach: put a
	# header row into a wrapper that contains both the header and the HBox.
	# For now, place a header row at the top of the panel directly so it
	# sits above the HBox content.
	var panel := get_panel()
	if not panel:
		return

	# Replace the existing HBox "Main" with a VBox wrapper that contains
	# the header and the existing HBox.
	var old_main: Node = panel.get_node_or_null("Main")
	if not old_main:
		return

	var wrapper := VBoxContainer.new()
	wrapper.name = "Wrapper"
	panel.remove_child(old_main)
	panel.add_child(wrapper)
	wrapper.add_child(old_main)

	var header := HBoxContainer.new()
	header.name = "Header"
	wrapper.add_child(header)
	wrapper.move_child(header, 0)

	var title := Label.new()
	title.text = "Trade"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

func _on_open() -> void:
	# Try to load any active trade for the local player.
	if TradeService and PlayerManager:
		var pid := str(PlayerManager.get_local_player_id())
		if not pid.is_empty():
			var active: Dictionary = TradeService.get_player_trade(pid)
			if not active.is_empty():
				_trade_id = active.get("trade_id", "")
				_initiator_id = active.get("player1", "")
				_target_id = active.get("player2", "")
				_trade_state = TradeState.ACCEPTED
				_update_status("Trade in progress with %s" % _target_id)
				_refresh_items()



func open_trade(initiator_id: String, target_id: String) -> void:
	_initiator_id = initiator_id
	_target_id = target_id
	_trade_state = TradeState.PROPOSING
	_update_status("Waiting for %s to add items..." % target_id)
	# Use UIPanel's open with initiator_id; that sets _player_id and shows us.
	open(initiator_id)

func _on_close() -> void:
	_trade_state = TradeState.IDLE
	_initiator_id = ""
	_target_id = ""

func _update_status(message: String) -> void:
	if _status_value:
		_status_value.text = message

func _refresh_items() -> void:
	_initiator_items.clear()
	_target_items.clear()

	if not TradeService or _trade_id.is_empty():
		_initiator_items.add_item("(No items)")
		_target_items.add_item("(No items)")
		return

	var trade: Dictionary = TradeService.get_player_trade(_initiator_id)
	if trade.is_empty():
		_initiator_items.add_item("(No items)")
		_target_items.add_item("(No items)")
		return

	var items_key := "player1_items"
	var their_key := "player2_items"
	var my_items: Array = trade.get(items_key, [])
	var their_items: Array = trade.get(their_key, [])

	if my_items.is_empty():
		_initiator_items.add_item("(No items)")
	else:
		for item: Dictionary in my_items:
			var name := item.get("name", "Unknown Item")
			var qty := item.get("quantity", 1)
			var label := name if qty <= 1 else "%s x%d" % [name, qty]
			_initiator_items.add_item(label)

	if their_items.is_empty():
		_target_items.add_item("(No items)")
	else:
		for item: Dictionary in their_items:
			var name := item.get("name", "Unknown Item")
			var qty := item.get("quantity", 1)
			var label := name if qty <= 1 else "%s x%d" % [name, qty]
			_target_items.add_item(label)

func _on_add_item() -> void:
	# Check if locked (confirmed)
	if _my_confirmed:
		show_notification("Trade is locked. Unconfirm first.")
		return

	if InventoryService and _trade_id:
		var inv := InventoryService.get_inventory(_initiator_id)
		if inv:
			var available := _get_available_items(inv)
			if available.is_empty():
				show_notification("No items to trade")
				return
			_show_item_selection_dialog(available)
	else:
		show_notification("Cannot add items right now")

func _get_available_items(inv) -> Array:
	# Get non-equipped, tradeable items from inventory
	var available: Array = []
	if "_inventory" in inv:
		var slots: Array = inv._inventory
		for i in range(slots.size()):
			var item = slots[i]
			if item != null and "id" in item:
				available.append({"slot": i, "item": item})
	return available

func _show_item_selection_dialog(items: Array) -> void:
	var dialog := ItemSelectDialog.new()
	dialog.title = "Select Item to Trade"
	add_child(dialog)
	dialog.popup_centered(Vector2(400, 300))

	# Populate item list
	for idx in range(items.size()):
		var entry: Dictionary = items[idx]
		var item = entry.get("item")
		if item and "display_name" in item:
			dialog.add_item(item.display_name, idx)

	var selected_idx: int = await dialog.item_selected
	if selected_idx >= 0 and selected_idx < items.size():
		var entry: Dictionary = items[selected_idx]
		var slot_idx: int = entry.get("slot", -1)
		var item = entry.get("item")
		if slot_idx >= 0 and item and TradeService:
			var success := TradeService.add_item(_trade_id, _initiator_id, item.id, 1)
			if success:
				show_notification("Added %s to trade" % item.display_name)
				_refresh_items()
			else:
				show_notification("Failed to add item")

	dialog.queue_free()

func _on_add_gold() -> void:
	# Check if locked (confirmed)
	if _my_confirmed:
		show_notification("Trade is locked. Unconfirm first.")
		return

	var dialog := AcceptDialog.new()
	dialog.dialog_text = "Enter gold amount:"
	dialog.title = "Add Gold"
	add_child(dialog)
	dialog.popup_centered()

	await dialog.confirmed
	var gold_text: String = dialog.dialog_text.strip_edges()
	dialog.queue_free()

	if gold_text.is_valid_int():
		_initiator_gold = gold_text.to_int()
		_update_gold_labels()
		# Also update TradeService
		if TradeService and _trade_id:
			TradeService.add_gold(_trade_id, _initiator_id, _initiator_gold)
	else:
		show_notification("Invalid gold amount")

func _update_gold_labels() -> void:
	if _gold_label:
		_gold_label.text = "Gold: %d" % _initiator_gold
	if _their_gold_label:
		_their_gold_label.text = "Gold: %d" % _target_gold

func _on_accept() -> void:
	if _trade_state == TradeState.PROPOSING:
		# Send the trade request
		if TradeService:
			var ok := TradeService.request_trade(_initiator_id, _target_id)
			if not ok:
				show_notification("Failed to send trade request")
				return
		_trade_state = TradeState.COUNTER_OFFER
		_update_status("Waiting for %s to accept..." % _target_id)
		show_notification("Trade offer sent!")
	elif _trade_state == TradeState.ACCEPTED:
		# Confirm/lock the trade
		if TradeService and _trade_id:
			var ok := TradeService.confirm_trade(_trade_id, _initiator_id)
			if ok:
				_my_confirmed = true
				_update_confirm_button()
				_update_status("Trade confirmed! Waiting for %s..." % _target_id)
			else:
				show_notification("Failed to confirm trade")
	elif _trade_state == TradeState.CONFIRMING:
		# Already confirming, just toggle
		_on_toggle_confirm()

func _on_toggle_confirm() -> void:
	# Toggle confirmation state
	if _my_confirmed:
		# Unconfirm
		_my_confirmed = false
		if TradeService and _trade_id:
			TradeService.unconfirm_trade(_trade_id, _initiator_id)
		_update_confirm_button()
		_update_status("Select items and confirm when ready")
	else:
		# Confirm
		if TradeService and _trade_id:
			var ok := TradeService.confirm_trade(_trade_id, _initiator_id)
			if ok:
				_my_confirmed = true
				_update_confirm_button()
				_update_status("Trade confirmed! Waiting for %s..." % _target_id)

func _on_cancel() -> void:
	_trade_state = TradeState.CANCELED
	trade_canceled.emit()
	show_notification("Trade canceled")
	close()

func _complete_trade() -> void:
	_trade_state = TradeState.COMPLETED

	if TradeService and _trade_id != "":
		var ok: bool = TradeService.confirm_trade(_trade_id, _initiator_id)
		if ok:
			show_notification("Trade completed!")
			trade_completed.emit(_initiator_id, _target_id)
		else:
			show_notification("Trade confirmation failed.", false)
	elif not TradeService or _trade_id == "":
		# No live trade registered yet -- surface a clear status to the player.
		show_notification("Trade completed (offline).", false)
		trade_completed.emit(_initiator_id, _target_id)

	close()

func show_notification(message: String, _success: bool = true) -> void:
	var notif := Label.new()
	notif.text = message
	notif.add_theme_color_override("font_color", UIStyles.COLORS.success)
	notif.z_index = 1000
	notif.global_position = Vector2(100, 100)
	get_tree().root.add_child(notif)
	await get_tree().create_timer(2.0).timeout
	notif.queue_free()
