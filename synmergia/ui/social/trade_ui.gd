## TradeUI - Item trading panel
class_name TradeUI
extends Control

var _initiator_id: String = ""
var _target_id: String = ""
var _initiator_items: ItemList
var _target_items: ItemList
var _initiator_gold: int = 0
var _target_gold: int = 0
var _trade_state: int = TradeState.IDLE

enum TradeState { IDLE, PROPOSING, COUNTER_OFFER, ACCEPTED, COMPLETED, CANCELED }

signal trade_completed(initiator_id: String, target_id: String)
signal trade_canceled()
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
		if e is InputEventMouseButton and e.pressed: _on_cancel()
	)
	add_child(overlay)
	
	# Panel
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(600, 400)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.98)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.corner_radius_top_left = 12
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	
	var main := HBoxContainer.new()
	panel.add_child(main)
	
	# Left side - Your offer
	var left_vbox := VBoxContainer.new()
	left_vbox.custom_minimum_size.x = 250
	main.add_child(left_vbox)
	
	var your_label := Label.new()
	your_label.text = "Your Offer"
	your_label.add_theme_font_size_override("font_size", 16)
	left_vbox.add_child(your_label)
	
	_initiator_items = ItemList.new()
	_initiator_items.custom_minimum_size.y = 250
	left_vbox.add_child(_initiator_items)
	
	var gold_label := Label.new()
	gold_label.text = "Gold: 0"
	gold_label.name = "GoldLabel"
	left_vbox.add_child(gold_label)
	
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
	
	# Center - Trade status
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(center)
	
	var status_label := Label.new()
	status_label.text = "Trade Status"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.name = "StatusLabel"
	center.add_child(status_label)
	
	var status_value := Label.new()
	status_value.text = "Waiting..."
	status_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_value.name = "StatusValue"
	center.add_child(status_value)
	
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
	
	# Right side - Their offer
	var right_vbox := VBoxContainer.new()
	right_vbox.custom_minimum_size.x = 250
	main.add_child(right_vbox)
	
	var their_label := Label.new()
	their_label.text = "Their Offer"
	their_label.add_theme_font_size_override("font_size", 16)
	right_vbox.add_child(their_label)
	
	_target_items = ItemList.new()
	_target_items.custom_minimum_size.y = 250
	right_vbox.add_child(_target_items)
	
	var their_gold_label := Label.new()
	their_gold_label.text = "Gold: -"
	their_gold_label.name = "TheirGoldLabel"
	right_vbox.add_child(their_gold_label)

func open_trade(initiator_id: String, target_id: String) -> void:
	_initiator_id = initiator_id
	_target_id = target_id
	_trade_state = TradeState.PROPOSING
	_update_status("Waiting for %s to add items..." % target_id)
	show()

func _update_status(message: String) -> void:
	var status: Label = get_node_or_null("Panel/StatusLabel/../StatusValue")
	if status:
		status.text = message

func _refresh_items() -> void:
	_initiator_items.clear()
	_target_items.clear()
	
	# TODO: Get actual items from TradeService or InventoryService
	_initiator_items.add_item("(No items)")
	_target_items.add_item("(No items)")

func _on_add_item() -> void:
	# TODO: Open inventory to select item
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
		var gold := gold_text.to_int()
		_initiator_gold = gold
		_update_gold_labels()
	else:
		show_notification("Invalid gold amount")

func _update_gold_labels() -> void:
	var my_gold: Label = get_node_or_null("Panel/YourOffer/GoldLabel")
	var their_gold: Label = get_node_or_null("Panel/TheirOffer/TheirGoldLabel")
	
	if my_gold:
		my_gold.text = "Gold: %d" % _initiator_gold
	if their_gold:
		their_gold.text = "Gold: %d" % _target_gold

func _on_accept() -> void:
	if _trade_state == TradeState.PROPOSING:
		_trade_state = TradeState.COUNTER_OFFER
		_update_status("Waiting for %s to accept..." % _target_id)
		show_notification("Trade offer sent!")
		# TODO: Notify target via network
	elif _trade_state == TradeState.COUNTER_OFFER:
		_complete_trade()

func _on_cancel() -> void:
	_trade_state = TradeState.CANCELED
	trade_canceled.emit()
	show_notification("Trade canceled")
	close()

func _complete_trade() -> void:
	_trade_state = TradeState.COMPLETED
	
	if TradeService:
		var result := TradeService.complete_trade(_initiator_id, _target_id)
		if result.get("success", false):
			show_notification("Trade completed!")
			trade_completed.emit(_initiator_id, _target_id)
		else:
			show_notification("Trade failed: " + result.get("message", ""))
	
	close()

func show_notification(message: String) -> void:
	var notif := Label.new()
	notif.text = message
	notif.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	notif.z_index = 1000
	notif.global_position = Vector2(100, 100)
	get_tree().root.add_child(notif)
	await get_tree().create_timer(2.0).timeout
	notif.queue_free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		closed.emit()
		_trade_state = TradeState.IDLE
		_initiator_id = ""
		_target_id = ""
