## CharacterTransferUI - Quick transfer between own characters
class_name CharacterTransferUI
extends Control

var _player_id: String = ""
var _targets_list: ItemList
var _gold_input: SpinBox
var _transfer_btn: Button
var _cooldown_label: Label

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
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(350, 400)
	
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
	title.text = "Transfer to Alt"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	header.add_child(title)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	
	# Description
	var desc := Label.new()
	desc.text = "Quick transfer items/gold to your other characters"
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	main.add_child(desc)
	
	# Character selection
	var select_label := Label.new()
	select_label.text = "Select Target Character:"
	select_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	main.add_child(select_label)
	
	_targets_list = ItemList.new()
	_targets_list.custom_minimum_size.y = 150
	_targets_list.select_mode = ItemList.SELECT_SINGLE
	main.add_child(_targets_list)
	
	# Gold amount
	var gold_row := HBoxContainer.new()
	main.add_child(gold_row)
	
	var gold_label := Label.new()
	gold_label.text = "Gold:"
	gold_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	gold_row.add_child(gold_label)
	
	_gold_input = SpinBox.new()
	_gold_input.min_value = 0
	_gold_input.max_value = 999999999
	_gold_input.step = 100
	_gold_input.value = 0
	gold_row.add_child(_gold_input)
	
	# Cooldown info
	_cooldown_label = Label.new()
	_cooldown_label.text = ""
	_cooldown_label.add_theme_color_override("font_color", Color(0.7, 0.5, 0.3))
	main.add_child(_cooldown_label)
	
	# Transfer button
	_transfer_btn = Button.new()
	_transfer_btn.text = "Transfer"
	_transfer_btn.pressed.connect(_on_transfer)
	main.add_child(_transfer_btn)
	
	# Limits info
	var limits_label := Label.new()
	limits_label.name = "LimitsLabel"
	limits_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	main.add_child(limits_label)

func open(player_id: String) -> void:
	_player_id = player_id
	_refresh_targets()
	_update_cooldown()
	_update_limits()
	show()

func _refresh_targets() -> void:
	_targets_list.clear()
	
	if not SameAccountTransferService:
		_targets_list.add_item("Service not available")
		return
	
	var targets: Array = SameAccountTransferService.get_transfer_targets(_player_id)
	if targets.is_empty():
		_targets_list.add_item("No other characters found")
		return
	
	for target in targets:
		var name: String = target.get("name", "?")
		var level: int = target.get("level", 1)
		var online: bool = target.get("online", false)
		var status := "[Online] " if online else "[Offline] "
		_targets_list.add_item("%s%s (Lv.%d)" % [status, name, level])

func _update_cooldown() -> void:
	if not SameAccountTransferService:
		return
	
	var cooldown := SameAccountTransferService.get_cooldown_remaining(_player_id)
	if cooldown > 0:
		_cooldown_label.text = "Cooldown: %d seconds" % cooldown
		_transfer_btn.disabled = true
	else:
		_cooldown_label.text = ""
		_transfer_btn.disabled = false

func _update_limits() -> void:
	var limits: Label = get_node_or_null("Panel/LimitsLabel")
	if not limits:
		return
	
	if not SameAccountTransferService:
		limits.text = ""
		return
	
	var remaining := SameAccountTransferService.get_remaining_limits(_player_id)
	limits.text = "Daily: %d gold, %d items remaining" % [
		remaining.get("gold_remaining", 0),
		remaining.get("items_remaining", 0)
	]

func _on_transfer() -> void:
	var selected := _targets_list.get_selected_items()
	if selected.is_empty():
		show_notification("Please select a target character")
		return
	
	var targets: Array = SameAccountTransferService.get_transfer_targets(_player_id)
	var idx := selected[0]
	if idx >= targets.size():
		show_notification("Invalid target selection")
		return
	
	var target: Dictionary = targets[idx]
	var target_id: String = target.get("id", "")
	var gold: int = int(_gold_input.value)
	
	var result := SameAccountTransferService.transfer(_player_id, target_id, gold, [])
	
	if result.get("success", false):
		show_notification("Transfer complete!", true)
		_update_cooldown()
		_update_limits()
	else:
		show_notification("Transfer failed: " + result.get("message", ""))

func show_notification(message: String, success: bool = false) -> void:
	var notif := Label.new()
	notif.text = message
	notif.add_theme_color_override("font_color", 
		Color(0.3, 0.8, 0.3) if success else Color(1, 0.3, 0.3))
	notif.z_index = 1000
	notif.global_position = Vector2(100, 100)
	get_tree().root.add_child(notif)
	await get_tree().create_timer(2.0).timeout
	notif.queue_free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		closed.emit()
