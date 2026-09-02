## TradeUI - Item trading panel
## Migrated onto UIPanel base class.
class_name TradeUI
extends UIPanel

enum TradeState { IDLE, PROPOSING, COUNTER_OFFER, ACCEPTED, COMPLETED, CANCELED }

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
		"trade_completed": _on_trade_completed,
		"trade_cancelled": _on_trade_cancelled,
		"trade_expired": _on_trade_expired,
	}
	for sig_name in sigs:
		if TradeService.has_signal(sig_name):
			var handler = sigs[sig_name]
			if not TradeService.get(sig_name).is_connected(handler):
				TradeService.get(sig_name).connect(handler)


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

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel)
	center.add_child(cancel_btn)

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
	# TODO: Get actual items from TradeService or InventoryService (Phase C).
	_initiator_items.add_item("(No items)")
	_target_items.add_item("(No items)")

func _on_add_item() -> void:
	show_notification("Select item from inventory (not implemented)")

func _on_add_gold() -> void:
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
	else:
		show_notification("Invalid gold amount")

func _update_gold_labels() -> void:
	if _gold_label:
		_gold_label.text = "Gold: %d" % _initiator_gold
	if _their_gold_label:
		_their_gold_label.text = "Gold: %d" % _target_gold

func _on_accept() -> void:
	if _trade_state == TradeState.PROPOSING:
		_trade_state = TradeState.COUNTER_OFFER
		_update_status("Waiting for %s to accept..." % _target_id)
		show_notification("Trade offer sent!")
	elif _trade_state == TradeState.COUNTER_OFFER:
		_complete_trade()

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
		# No live trade registered yet — surface a clear status to the player.
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