## BankUI - Vault/Bank interface panel
## Provides access to personal, guild, and account vaults
extends UIPanel

class_name BankUI

const UIPanel = preload("res://ui/components/ui_panel.gd")
const UIStyles = preload("res://ui/components/ui_styles.gd")
const IconResolver = preload("res://core/utils/icon_resolver.gd")
const Item = preload("res://core/schemas/item.gd")
const InventoryComponent = preload("res://core/components/inventory_component.gd")

## Vault tabs
enum VaultTab { PERSONAL, GUILD, ACCOUNT }
var _current_tab: VaultTab = VaultTab.PERSONAL

## Components
var _vault_grid: GridContainer
var _gold_label: Label
var _slot_count_label: Label
var _tab_buttons: Array = []
var _deposit_btn: Button
var _withdraw_btn: Button

## State
var _vault_data: Dictionary = {}
var _selected_slot: int = -1
var _slot_data: Dictionary = {}  # slot_index -> {id, quantity, icon_path}

const GRID_COLS: int = 5
const GRID_ROWS: int = 10
const SLOT_SIZE: int = 48

func _ready() -> void:
	super._ready()
	set_title("Bank")
	set_panel_size(Vector2(480, 580))
	_setup_ui()
	_connect_signals()

func _setup_ui() -> void:
	var panel := get_panel()
	if not panel:
		return

	var main: VBoxContainer = panel.get_node_or_null("Main")
	if not main:
		return

	# Tab bar
	var tab_bar := HBoxContainer.new()
	tab_bar.custom_minimum_size.y = 40
	main.add_child(tab_bar)

	var tabs := [
		{"id": VaultTab.PERSONAL, "name": "Personal"},
		{"id": VaultTab.GUILD, "name": "Guild"},
		{"id": VaultTab.ACCOUNT, "name": "Account"}
	]

	for tab in tabs:
		var btn := Button.new()
		btn.text = tab.name
		btn.toggle_mode = true
		btn.custom_minimum_size.x = 100
		btn.pressed.connect(_on_tab_clicked.bind(tab.id))
		_tab_buttons.append(btn)
		tab_bar.add_child(btn)

	# Gold display
	var gold_row := HBoxContainer.new()
	gold_row.custom_minimum_size.y = 30
	main.add_child(gold_row)

	var gold_title := Label.new()
	gold_title.text = "Gold: "
	gold_title.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	gold_row.add_child(gold_title)

	_gold_label = Label.new()
	_gold_label.text = "0"
	_gold_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	gold_row.add_child(_gold_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold_row.add_child(spacer)

	_slot_count_label = Label.new()
	_slot_count_label.text = "0/0"
	_slot_count_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	gold_row.add_child(_slot_count_label)

	# Vault grid
	var _scroll: ScrollContainer = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_scroll)

	var grid_container := HBoxContainer.new()
	_scroll.add_child(grid_container)

	_vault_grid = GridContainer.new()
	_vault_grid.name = "VaultGrid"
	_vault_grid.columns = GRID_COLS
	grid_container.add_child(_vault_grid)

	# Create slots
	for i in range(GRID_COLS * GRID_ROWS):
		var slot := _create_slot(i)
		_vault_grid.add_child(slot)

	# Action buttons
	var action_row := HBoxContainer.new()
	action_row.custom_minimum_size.y = 40
	main.add_child(action_row)

	_deposit_btn = Button.new()
	_deposit_btn.text = "Deposit"
	_deposit_btn.pressed.connect(_on_deposit)
	action_row.add_child(_deposit_btn)

	_withdraw_btn = Button.new()
	_withdraw_btn.text = "Withdraw"
	_withdraw_btn.pressed.connect(_on_withdraw)
	action_row.add_child(_withdraw_btn)

	var expand_btn := Button.new()
	expand_btn.text = "Expand"
	expand_btn.pressed.connect(_on_expand)
	action_row.add_child(expand_btn)

	# Set initial tab
	_update_tabs(0)
	_refresh_vault()

var _scroll: ScrollContainer

func _connect_signals() -> void:
	if VaultService:
		VaultService.item_deposited.connect(_on_item_changed)
		VaultService.item_withdrawn.connect(_on_item_changed)
		VaultService.gold_deposited.connect(_on_gold_changed)
		VaultService.gold_withdrawn.connect(_on_gold_changed)

func _on_tab_clicked(tab_id: int) -> void:
	_update_tabs(tab_id)
	_refresh_vault()

func _update_tabs(active_index: int) -> void:
	_current_tab = active_index
	for i in range(_tab_buttons.size()):
		var btn: Button = _tab_buttons[i]
		btn.button_pressed = (i == active_index)
		if btn.button_pressed:
			btn.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
		else:
			btn.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)

	# Update buttons based on vault type
	var can_access_guild := _can_access_guild_vault()
	_tab_buttons[VaultTab.GUILD].disabled = not can_access_guild

func _can_access_guild_vault() -> bool:
	var player_id := str(PlayerManager.get_local_player_id()) if PlayerManager else ""
	if player_id.is_empty():
		return false
	if not GuildService:
		return false
	if not GuildService.has_method("is_in_guild"):
		return false
	return GuildService.is_in_guild(player_id)

func _refresh_vault() -> void:
	var player_id := str(PlayerManager.get_local_player_id()) if PlayerManager else ""
	if player_id.is_empty():
		return

	var vault_type: int
	match _current_tab:
		VaultTab.PERSONAL:
			vault_type = VaultService.VaultType.PERSONAL
		VaultTab.GUILD:
			vault_type = VaultService.VaultType.GUILD
		VaultTab.ACCOUNT:
			vault_type = VaultService.VaultType.ACCOUNT
		_:
			return

	_vault_data = VaultService.open_vault(player_id, vault_type)

	# Update UI
	_update_gold_display()
	_update_slot_display()
	_populate_grid()

func _update_gold_display() -> void:
	var gold: int = _vault_data.get("gold", 0)
	_gold_label.text = str(gold)

func _get_slot_icon(slot_info: Dictionary) -> Texture2D:
	return IconResolver.get_item_icon_from_dict(slot_info)

func _update_slot_display() -> void:
	var size: int = _vault_data.get("size", 0)
	var used: int = 0
	for slot in _vault_data.get("slots", []):
		if not slot.is_empty():
			used += 1
	_slot_count_label.text = "%d/%d" % [used, size]

func _populate_grid() -> void:
	var slots: Array = _vault_data.get("slots", [])
	_slot_data.clear()
	
	for i in range(_vault_grid.get_child_count()):
		var slot: Control = _vault_grid.get_child(i)
		if slot and slot.has_node("ItemIcon"):
			var icon: TextureRect = slot.get_node("ItemIcon")
			if i < slots.size() and not slots[i].is_empty():
				var slot_info: Dictionary = slots[i]
				_slot_data[i] = slot_info
				
				icon.visible = true
				icon.modulate = Color(1, 1, 1, 1)
				icon.texture = _get_slot_icon(slot_info)
			else:
				icon.visible = false
				icon.texture = null

		# Update selection highlight
		var style_name := "selected" if i == _selected_slot else "normal"
		var style := _get_slot_style(style_name)
		slot.add_theme_stylebox_override("panel", style)

func _create_slot(index: int) -> Control:
	var slot := PanelContainer.new()
	slot.name = "Slot_%d" % index
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)

	var style := _get_slot_style("normal")
	slot.add_theme_stylebox_override("panel", style)

	# Item icon placeholder
	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.visible = false
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(SLOT_SIZE - 8, SLOT_SIZE - 8)
	slot.add_child(icon)

	# Quantity label
	var qty := Label.new()
	qty.name = "Quantity"
	qty.visible = false
	qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	qty.add_theme_font_size_override("font_size", 10)
	qty.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	slot.add_child(qty)

	# Slot number
	var num := Label.new()
	num.text = str(index + 1)
	num.set_anchors_preset(Control.PRESET_TOP_LEFT)
	num.add_theme_font_size_override("font_size", 8)
	num.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	slot.add_child(num)

	return slot

func _get_slot_style(type: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	match type:
		"normal":
			style.bg_color = UIStyles.COLORS.background_dark
			style.border_color = UIStyles.COLORS.border
		"hover":
			style.bg_color = Color(0.2, 0.2, 0.25)
			style.border_color = UIStyles.COLORS.border_highlight
		"selected":
			style.bg_color = Color(0.15, 0.2, 0.3)
			style.border_color = UIStyles.COLORS.accent_gold
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _on_slot_clicked(index: int) -> void:
	_selected_slot = index
	_populate_grid()

func _on_deposit() -> void:
	if not VaultService:
		show_notification("VaultService unavailable", false)
		return

	var player_id := str(PlayerManager.get_local_player_id()) if PlayerManager else ""
	if player_id.is_empty():
		return

	if not InventoryService:
		show_notification("InventoryService unavailable", false)
		return

	var inv: InventoryComponent = InventoryService.get_inventory(player_id)
	if inv == null:
		show_notification("Could not load inventory", false)
		return

	var items: Array = inv.get_all_items()
	if items.is_empty():
		show_notification("No items to deposit", false)
		return

	_show_deposit_dialog(items)

func _show_deposit_dialog(items: Array) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Deposit Item"
	dialog.dialog_text = "Select item to deposit:"
	add_child(dialog)

	# Create scrollable item list
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 200)
	dialog.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size.x = 280
	scroll.add_child(vbox)

	var selected_idx := -1

	for i in range(items.size()):
		var item: Item = items[i]
		if item == null:
			continue

		var btn := Button.new()
		btn.text = item.name if item.name else "Item #%d" % i
		btn.custom_minimum_size.y = 30
		btn.pressed.connect(func() -> void:
			selected_idx = i
		)
		vbox.add_child(btn)

	dialog.confirmed.connect(func() -> void:
		if selected_idx < 0:
			show_notification("No item selected", false)
			return
		_deposit_item(items[selected_idx])
	)

	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)

	dialog.popup_centered(Vector2(350, 300))

func _deposit_item(item: Item) -> void:
	if VaultService == null or item == null:
		return

	var player_id := str(PlayerManager.get_local_player_id()) if PlayerManager else ""
	if player_id.is_empty():
		return

	var vault_type: int
	match _current_tab:
		VaultTab.PERSONAL:
			vault_type = VaultService.VaultType.PERSONAL
		VaultTab.GUILD:
			vault_type = VaultService.VaultType.GUILD
		VaultTab.ACCOUNT:
			vault_type = VaultService.VaultType.ACCOUNT
		_:
			return

	var success: bool = VaultService.deposit_item(player_id, vault_type, item)
	if not success:
		show_notification("Failed to deposit item", false)
	else:
		var item_name: String = item.name if item.name else "item"
		show_notification("Deposited: %s" % item_name)
		_refresh_vault()

func _on_withdraw() -> void:
	if _selected_slot < 0:
		show_notification("Select a slot to withdraw from", false)
		return
	if not VaultService:
		show_notification("VaultService unavailable", false)
		return

	var player_id := str(PlayerManager.get_local_player_id()) if PlayerManager else ""
	if player_id.is_empty():
		return

	var vault_type: int
	match _current_tab:
		VaultTab.PERSONAL:
			vault_type = VaultService.VaultType.PERSONAL
		VaultTab.GUILD:
			vault_type = VaultService.VaultType.GUILD
		VaultTab.ACCOUNT:
			vault_type = VaultService.VaultType.ACCOUNT
		_:
			return

	var result: Dictionary = VaultService.withdraw_item(player_id, vault_type, _selected_slot)
	if result.is_empty():
		show_notification("Failed to withdraw item", false)
	else:
		var item_name: String = result.get("item_name", "item")
		show_notification("Withdrew: %s" % item_name)
		_refresh_vault()

func _on_expand() -> void:
	if not VaultService:
		show_notification("VaultService unavailable", false)
		return

	var cost := VaultService.get_expansion_cost(_current_tab, _vault_data.get("size", 0))
	var gold_cost: int = cost.get("gold", 0)

	var dialog := ConfirmationDialog.new()
	dialog.title = "Expand Vault"
	dialog.dialog_text = "Expand vault by 10 slots for %d gold?" % gold_cost
	add_child(dialog)

	dialog.confirmed.connect(_on_expand_confirmed.bind(gold_cost))
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered()

func _on_expand_confirmed(gold_cost: int) -> void:
	var player_id := str(PlayerManager.get_local_player_id()) if PlayerManager else ""
	if player_id.is_empty():
		return

	var vault_type: int
	match _current_tab:
		VaultTab.PERSONAL:
			vault_type = VaultService.VaultType.PERSONAL
		VaultTab.GUILD:
			vault_type = VaultService.VaultType.GUILD
		VaultTab.ACCOUNT:
			vault_type = VaultService.VaultType.ACCOUNT
		_:
			return

	var result: bool = VaultService.expand_vault(player_id, vault_type, 10)
	if result:
		show_notification("Vault expanded by 10 slots!")
		_refresh_vault()
	else:
		show_notification("Failed to expand vault - not enough gold?", false)

func _on_item_changed(player_id: String, vault_type: int, item_id: String, quantity: int) -> void:
	_refresh_vault()

func _on_gold_changed(player_id: String, vault_type: int, amount: int) -> void:
	_refresh_vault()

func close() -> void:
	var player_id := str(PlayerManager.get_local_player_id()) if PlayerManager else ""
	if not player_id.is_empty():
		var vault_type: int
		match _current_tab:
			VaultTab.PERSONAL:
				vault_type = VaultService.VaultType.PERSONAL
			VaultTab.GUILD:
				vault_type = VaultService.VaultType.GUILD
			VaultTab.ACCOUNT:
				vault_type = VaultService.VaultType.ACCOUNT
		VaultService.close_vault(player_id, vault_type)

	super.close()
