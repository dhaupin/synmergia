## CharacterTransferUI - Quick transfer between own characters
## Migrated onto UIPanel base class.
class_name CharacterTransferUI
extends UIPanel

var _targets_list: ItemList
var _gold_input: SpinBox
var _transfer_btn: Button
var _cooldown_label: Label
var _limits_label: Label

signal closed()  # Alias of panel_closed for back-compat.

func _ready() -> void:
	super._ready()
	panel_closed.connect(func() -> void: closed.emit())

func _setup_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(350, 400)
	panel.add_theme_stylebox_override("panel", UIStyles.create_panel_style(
		UIStyles.COLORS.background_dark,
		UIStyles.COLORS.border,
		2,
		12
	))
	panel.name = "Panel"
	add_child(panel)

	var main := VBoxContainer.new()
	main.name = "Main"
	panel.add_child(main)

	var desc := Label.new()
	desc.text = "Quick transfer items/gold to your other characters"
	desc.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	main.add_child(desc)

	var select_label := Label.new()
	select_label.text = "Select Target Character:"
	select_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	main.add_child(select_label)

	_targets_list = ItemList.new()
	_targets_list.custom_minimum_size.y = 150
	_targets_list.select_mode = ItemList.SELECT_SINGLE
	main.add_child(_targets_list)

	var gold_row := HBoxContainer.new()
	main.add_child(gold_row)

	var gold_label := Label.new()
	gold_label.text = "Gold:"
	gold_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	gold_row.add_child(gold_label)

	_gold_input = SpinBox.new()
	_gold_input.min_value = 0
	_gold_input.max_value = 999999999
	_gold_input.step = 100
	_gold_input.value = 0
	gold_row.add_child(_gold_input)

	_cooldown_label = Label.new()
	_cooldown_label.text = ""
	_cooldown_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)
	main.add_child(_cooldown_label)

	_transfer_btn = Button.new()
	_transfer_btn.text = "Transfer"
	_transfer_btn.pressed.connect(_on_transfer)
	main.add_child(_transfer_btn)

	_limits_label = Label.new()
	_limits_label.name = "LimitsLabel"
	_limits_label.add_theme_color_override("font_color", UIStyles.COLORS.text_disabled)
	main.add_child(_limits_label)

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
	title.text = "Transfer to Alt"
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
	_refresh_targets()
	_update_cooldown()
	_update_limits()

func refresh() -> void:
	_refresh_targets()

func _refresh_targets() -> void:
	if not _targets_list:
		return
	_targets_list.clear()

	if not SameAccountTransferService:
		_targets_list.add_item("Service not available")
		return

	var targets: Array = SameAccountTransferService.get_transfer_targets(_player_id)
	if targets.is_empty():
		_targets_list.add_item("No other characters found")
		return

	for target in targets:
		var target_data: Dictionary = target
		var tname: String = target_data.get("name", "?")
		var level: int = target_data.get("level", 1)
		var online: bool = target_data.get("online", false)
		var status: String = "[Online] " if online else "[Offline] "
		_targets_list.add_item("%s%s (Lv.%d)" % [status, tname, level])

func _update_cooldown() -> void:
	if not SameAccountTransferService or not _cooldown_label:
		return

	var cooldown: int = SameAccountTransferService.get_cooldown_remaining(_player_id)
	if cooldown > 0:
		_cooldown_label.text = "Cooldown: %d seconds" % cooldown
		_transfer_btn.disabled = true
	else:
		_cooldown_label.text = ""
		_transfer_btn.disabled = false

func _update_limits() -> void:
	if not _limits_label:
		return

	if not SameAccountTransferService:
		_limits_label.text = ""
		return

	var remaining: Dictionary = SameAccountTransferService.get_remaining_limits(_player_id)
	_limits_label.text = "Daily: %d gold, %d items remaining" % [
		remaining.get("gold_remaining", 0),
		remaining.get("items_remaining", 0)
	]

func _on_transfer() -> void:
	if not SameAccountTransferService:
		return
	var selected: PackedInt32Array = _targets_list.get_selected_items()
	if selected.is_empty():
		show_notification("Please select a target character")
		return

	var targets: Array = SameAccountTransferService.get_transfer_targets(_player_id)
	var idx: int = selected[0]
	if idx >= targets.size():
		show_notification("Invalid target selection")
		return

	var target: Dictionary = targets[idx]
	var target_id: String = target.get("id", "")
	var gold: int = int(_gold_input.value)

	var result: Dictionary = SameAccountTransferService.transfer(_player_id, target_id, gold, [])

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
		UIStyles.COLORS.success if success else UIStyles.COLORS.error)
	notif.z_index = 1000
	notif.global_position = Vector2(100, 100)
	get_tree().root.add_child(notif)
	await get_tree().create_timer(2.0).timeout
	notif.queue_free()