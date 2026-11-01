## ShopUI - NPC vendor buy/sell panel
## Opened when player interacts with a "vendor" NPC.
## Two tabs: Buy (catalog) and Sell (player inventory).
## Proximity auto-closes at 8m.
extends "res://ui/components/ui_panel.gd"
class_name ShopUI

## Runtime autoload lookups (script-mode-safe; the bare identifiers
## fail compile when autoloads are absent -- test_islands).
func _notify_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("NotificationService")) if tree and tree.root else null
const NPCOffering = preload("res://core/schemas/npc_offering.gd")
const IconResolver = preload("res://core/utils/icon_resolver.gd")
const VendorService = preload("res://core/services/vendor_service.gd")


## Static instance -- one shop at a time
static var _instance: ShopUI = null
static func singleton() -> ShopUI:
	return _instance

## Open the shop by offering ref_id (e.g. "vendor_general").
## DialogService calls ShopUI.open_shop(shop_id); this facade loads
## the offering resource and forwards to open_for_offering().
static func open_shop(shop_id: String, player_id: String = "") -> void:
	var offering := load("res://data/npc_offerings/%s.tres" % shop_id) as NPCOffering
	if offering == null:
		push_warning("ShopUI.open_shop: no offering at res://data/npc_offerings/%s.tres" % shop_id)
		return
	open_for_offering(player_id, offering, null, Vector3.ZERO)

## Session state
var _offering: Resource = null
var _npc_data: Resource = null
var _npc_position: Vector3 = Vector3.ZERO
var _proximity_enabled: bool = false

## Tab state
enum Tab { BUY, SELL }
var _current_tab: Tab = Tab.BUY

## UI refs
var _tab_buy: Button
var _tab_sell: Button
var _gold_label: Label
var _item_grid: GridContainer
var _scroll: ScrollContainer
var _info_label: Label
var _buy_btn: Button
var _sell_btn: Button
var _qty_spin: SpinBox
var _qty_label: Label

## Selection state
var _catalog: Array[Dictionary] = []
var _sellable: Array[Dictionary] = []
var _selected_index: int = -1
var _selected_type: Tab = Tab.BUY

const COLS: int = 4
const SLOT_SIZE: int = 56

## ============================================================================
## STATIC OPEN / CLOSE
## ============================================================================

static func open_for_offering(player_id: String, offering, npc_data, npc_pos: Vector3) -> void:
	if _instance == null:
		_instance = load("res://ui/components/shop_ui.gd").new()
		# add_child triggers _ready() in-tree, which builds the panel UI.
		# The previous manual _instance._ready() call ran BEFORE the node
		# was in the tree, so every get_node/absolute-path lookup inside
		# the panel build returned null (dead grid, no footer, no tabs).
		var root: Window = Engine.get_main_loop().root
		root.add_child(_instance)

	_instance._offering = offering
	_instance._npc_data = npc_data
	_instance._player_id = player_id
	_instance._npc_position = npc_pos
	_instance._proximity_enabled = true
	# Vendors are reachable by tap-target + long-press from well beyond
	# the 5m default, so the default threshold closed the shop the frame
	# after opening ("Moved too far" toast) whenever the player traded
	# from just outside melee range. 12m matches the practical
	# target-then-browse flow while still closing on real walk-aways.
	_instance.set_max_interact_distance(12.0)
	_instance._selected_index = -1
	_instance._current_tab = Tab.BUY
	_instance._load_catalog()
	_instance._load_sellable()
	_instance._refresh_tabs()
	_instance._refresh_grid()
	_instance._refresh_info()
	_instance.open(player_id)

static func close_shop() -> void:
	if _instance != null:
		_instance.close()
	_instance = null


## ============================================================================
## LIFECYCLE
## ============================================================================

func _ready() -> void:
	super._ready()
	set_panel_size(Vector2(480, 580))
	set_title("Shop")
	_setup_tabs()
	_setup_grid()
	_setup_footer()


## Build the base "Panel" node. UIPanel's default _setup_panel() is a
## no-op stub -- subclasses must create the named Panel themselves
## (see dialog_ui.gd). Without this, get_panel() returned null, so
## _setup_tabs() bailed and every _tab_buy/_grid/_gold_label refresh
## crashed on Nil (shop grid dead, no buy/sell possible).
func _setup_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(480, 580)
	var style := UIStyles.create_panel_style()
	panel.add_theme_stylebox_override("panel", style)
	panel.name = "Panel"
	panel.focus_mode = Control.FOCUS_ALL
	add_child(panel)

func update_accessibility_settings(high_contrast: bool, text_scale: float, reduce_motion: bool) -> void:
	pass

## ============================================================================
## SETUP
## ============================================================================

func _setup_tabs() -> void:
	var panel := get_panel()
	if not panel:
		return

	var main := add_content_to_panel(panel)
	var tab_bar := HBoxContainer.new()
	tab_bar.name = "TabBar"
	tab_bar.custom_minimum_size.y = 40
	main.add_child(tab_bar)

	_tab_buy = Button.new()
	_tab_buy.text = "Buy"
	_tab_buy.toggle_mode = true
	_tab_buy.custom_minimum_size.x = 100
	_tab_buy.pressed.connect(_on_tab_buy_pressed)
	tab_bar.add_child(_tab_buy)

	_tab_sell = Button.new()
	_tab_sell.text = "Sell"
	_tab_sell.toggle_mode = true
	_tab_sell.custom_minimum_size.x = 100
	_tab_sell.pressed.connect(_on_tab_sell_pressed)
	tab_bar.add_child(_tab_sell)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.add_child(spacer)

	# Gold row
	var gold_row := HBoxContainer.new()
	gold_row.name = "GoldRow"
	gold_row.custom_minimum_size.y = 28
	main.add_child(gold_row)

	var gold_lbl := Label.new()
	gold_lbl.text = "Gold: "
	gold_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	gold_row.add_child(gold_lbl)

	_gold_label = Label.new()
	_gold_label.text = "0"
	_gold_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	gold_row.add_child(_gold_label)

	# Scroll + grid
	_scroll = preload("res://ui/components/drag_scroll.gd").new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(_scroll)

	var scroll_content := HBoxContainer.new()
	_scroll.add_child(scroll_content)

	_item_grid = GridContainer.new()
	_item_grid.name = "ItemGrid"
	_item_grid.columns = COLS
	scroll_content.add_child(_item_grid)

	# Info label
	_info_label = Label.new()
	_info_label.name = "InfoLabel"
	_info_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	_info_label.text = "Select an item"
	main.add_child(_info_label)

	# Footer
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.custom_minimum_size.y = 44
	main.add_child(footer)

	var qty_lbl := Label.new()
	qty_lbl.text = "Qty:"
	qty_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	footer.add_child(qty_lbl)

	_qty_spin = SpinBox.new()
	_qty_spin.name = "QtySpin"
	_qty_spin.min_value = 1
	_qty_spin.max_value = 999
	_qty_spin.value = 1
	_qty_spin.custom_minimum_size.x = 70
	_qty_spin.value_changed.connect(_on_qty_changed)
	footer.add_child(_qty_spin)

	var expand := Control.new()
	expand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(expand)

	_buy_btn = Button.new()
	_buy_btn.text = "Buy"
	_buy_btn.custom_minimum_size.x = 90
	_buy_btn.pressed.connect(_on_buy_pressed)
	footer.add_child(_buy_btn)

	_sell_btn = Button.new()
	_sell_btn.text = "Sell"
	_sell_btn.custom_minimum_size.x = 90
	_sell_btn.pressed.connect(_on_sell_pressed)
	footer.add_child(_sell_btn)

	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.custom_minimum_size.x = 90
	leave_btn.pressed.connect(_on_leave_pressed)
	footer.add_child(leave_btn)


func _setup_grid() -> void:
	# Pre-populate grid with empty slots. Skip when constructed without a
	# scene (get_panel() was null in _setup_tabs, so the grid never built).
	if _item_grid == null:
		return
	for i in range(COLS * 4):
		var slot := _make_slot(i)
		_item_grid.add_child(slot)


func _setup_footer() -> void:
	pass  # handled in _setup_tabs


## ============================================================================
## TAB HANDLERS
## ============================================================================

func _on_tab_buy_pressed() -> void:
	_current_tab = Tab.BUY
	_refresh_tabs()
	_refresh_grid()
	_refresh_info()

func _on_tab_sell_pressed() -> void:
	_current_tab = Tab.SELL
	_refresh_tabs()
	_refresh_grid()
	_refresh_info()


## ============================================================================
## DATA LOADING
## ============================================================================

func _load_catalog() -> void:
	_catalog = []
	if _offering == null or _offering.type != "vendor":
		return
	var svc = VendorService.singleton()
	if svc:
		# Copy element-wise: the autoload's typed return degrades to a plain
		# Array across the service boundary, and assigning that to a typed
		# Array[Dictionary] throws "Cannot assign Array to Dictionary".
		var raw = svc.get_catalog(_offering, _npc_data)
		for entry in raw:
			if entry is Dictionary:
				_catalog.append(entry)
		svc.ensure_stock(_offering, _npc_data)

func _load_sellable() -> void:
	_sellable = []
	if _offering == null or _offering.type != "vendor":
		return
	var svc = VendorService.singleton()
	if svc:
		# Same cross-boundary typed-array guard as _load_catalog.
		var raw = svc.get_sellable_items(_player_id, _offering, _npc_data)
		for entry in raw:
			if entry is Dictionary:
				_sellable.append(entry)


## ============================================================================
## REFRESH
## ============================================================================

func _refresh_tabs() -> void:
	_tab_buy.button_pressed = (_current_tab == Tab.BUY)
	_tab_sell.button_pressed = (_current_tab == Tab.SELL)
	_tab_buy.add_theme_color_override("font_color",
		UIStyles.COLORS.accent_gold if _current_tab == Tab.BUY else UIStyles.COLORS.text_secondary)
	_tab_sell.add_theme_color_override("font_color",
		UIStyles.COLORS.accent_gold if _current_tab == Tab.SELL else UIStyles.COLORS.text_secondary)

	_buy_btn.visible = (_current_tab == Tab.BUY)
	_sell_btn.visible = (_current_tab == Tab.SELL)

func _refresh_grid() -> void:
	# Clear existing items (keep slot containers)
	for i in range(_item_grid.get_child_count()):
		var slot: PanelContainer = _item_grid.get_child(i)
		var icon: TextureRect = slot.get_node_or_null("Icon")
		var qty: Label = slot.get_node_or_null("Qty")
		var sel: TextureRect = slot.get_node_or_null("Selected")
		if icon:
			icon.texture = null
			icon.visible = false
		if qty:
			qty.visible = false
		if sel:
			sel.visible = false

	var items: Array = (_catalog if _current_tab == Tab.BUY else _sellable)
	var slot_idx := 0
	for i in range(items.size()):
		if slot_idx >= _item_grid.get_child_count():
			break
		var entry: Dictionary = items[i]
		var item: Resource = entry.get("item")
		if item == null:
			continue

		var slot: PanelContainer = _item_grid.get_child(slot_idx)
		var icon: TextureRect = slot.get_node_or_null("Icon")
		var qty: Label = slot.get_node_or_null("Qty")
		var sel: TextureRect = slot.get_node_or_null("Selected")

		if icon:
			icon.texture = _load_item_icon(item)
			icon.visible = true
		if qty:
			var stack: int = entry.get("quantity") if entry.has("quantity") else (entry.get("stock") if entry.has("stock") else 1)
			qty.text = str(stack) if stack > 1 else ""
			qty.visible = (stack > 1)

		if slot.gui_input.is_connected(_on_slot_input):
			slot.gui_input.disconnect(_on_slot_input)
		slot.gui_input.connect(_on_slot_input.bind(slot_idx, _current_tab))
		slot_idx += 1

func _refresh_info() -> void:
	_refresh_gold()
	if _selected_index < 0:
		_info_label.text = "Select an item"
		return

	var items: Array = (_catalog if _selected_type == Tab.BUY else _sellable)
	if _selected_index >= items.size():
		_info_label.text = "Select an item"
		return

	var entry: Dictionary = items[_selected_index]
	var item: Resource = entry.get("item")
	if item == null:
		return

	var name: String = item.get("display_name") if item.has("display_name") else "Unknown"
	var price: int = entry.get("price") if entry.has("price") else 0
	var qty: int = _qty_spin.value if _qty_spin else 1
	var total: int = price * qty

	if _selected_type == Tab.BUY:
		# Non-gold catalog entries (the ledger wares: junker scrip,
		# concord sigils) price BY the entry's own currency and quote the
		# purse spend through the unified ledger's get_currency_amount.
		var cid := str(entry.get("currency", ""))
		if cid.is_empty() or cid == "currency_gold":
			_info_label.text = "%s -- %d gold each (total: %d)" % [name, price, total]
		else:
			var label := _currency_label(cid)
			var have := _wallet_balance(cid)
			_info_label.text = "%s -- %d %s each (you have %d, total: %d)" % [name, price, label, have, total]
	else:
		var owned: int = entry.get("quantity") if entry.has("quantity") else 1
		_info_label.text = "%s -- %d gold each (you have %d, total: %d)" % [name, price, owned, total]


func _refresh_gold() -> void:
	if _player_id.is_empty():
		_gold_label.text = "0"
		return
	var tree := Engine.get_main_loop() as SceneTree
	var inv_service := tree.root.get_node_or_null(NodePath("InventoryService")) if tree and tree.root else null
	if inv_service:
		# InventoryService is an autoload instance; call get_gold on it
		# directly (there is no .singleton() accessor on the script).
		# The ONE purse: gold is the default currency id on the wallet.
		var gold: int = _wallet_balance("")
		_gold_label.text = str(gold)
	else:
		_gold_label.text = "0"

## The unified ledger's balance for any currency ("" = gold).
func _wallet_balance(cid: String) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var inv_service := tree.root.get_node_or_null(NodePath("InventoryService")) if tree and tree.root else null
	if inv_service == null or not inv_service.has_method("get_inventory"):
		return 0
	var inv = inv_service.get_inventory(_player_id)
	if inv == null or not is_instance_valid(inv) or not inv.has_method("get_currency_amount"):
		return 0
	return int(inv.get_currency_amount(cid))

## DataService display_name for a currency id (the id itself as fallback).
func _currency_label(cid: String) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var data_service := tree.root.get_node_or_null(NodePath("DataService")) if tree and tree.root else null
	if data_service != null and data_service.has_method("get_currency"):
		var cd = data_service.get_currency(cid)
		if cd != null and "display_name" in cd and str(cd.display_name) != "":
			return str(cd.display_name)
	return cid


## ============================================================================
## SLOT FACTORY
## ============================================================================

func _make_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = "Slot_%d" % index
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)

	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.border_color = UIStyles.COLORS.border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	slot.add_theme_stylebox_override("panel", style)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.visible = false
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(SLOT_SIZE - 8, SLOT_SIZE - 8)
	slot.add_child(icon)

	var qty_lbl := Label.new()
	qty_lbl.name = "Qty"
	qty_lbl.visible = false
	qty_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	qty_lbl.add_theme_font_size_override("font_size", 10)
	qty_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	slot.add_child(qty_lbl)

	var sel := TextureRect.new()
	sel.name = "Selected"
	sel.visible = false
	sel.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(sel)

	return slot


## ============================================================================
## SLOT INPUT
## ============================================================================

func _on_slot_input(event: InputEvent, slot_idx: int, tab: Tab) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_slot(slot_idx, tab)


func _select_slot(index: int, tab: Tab) -> void:
	# Deselect old
	if _selected_index >= 0:
		var old_slot: PanelContainer = _item_grid.get_child(_selected_index)
		if old_slot:
			var old_sel: TextureRect = old_slot.get_node_or_null("Selected")
			if old_sel:
				old_sel.visible = false
			var style: StyleBoxFlat = old_slot.get_theme_stylebox("panel")
			if style:
				style.border_color = UIStyles.COLORS.border

	_selected_index = index
	_selected_type = tab

	# Highlight new
	var items: Array = (_catalog if tab == Tab.BUY else _sellable)
	if index >= items.size():
		return
	var slot: PanelContainer = _item_grid.get_child(index)
	if slot:
		var sel: TextureRect = slot.get_node_or_null("Selected")
		if sel:
			sel.visible = true
			var overlay := ColorRect.new()
			overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
			overlay.color = Color(0.3, 0.6, 1.0, 0.3)
			sel.add_child(overlay)
		var style: StyleBoxFlat = slot.get_theme_stylebox("panel")
		if style:
			style.border_color = UIStyles.COLORS.accent

	# Update qty spin max
	var entry: Dictionary = items[index]
	var max_qty: int = entry.get("quantity") if entry.has("quantity") else (entry.get("stock") if entry.has("stock") else 1)
	if _qty_spin:
		_qty_spin.max_value = max_qty
		_qty_spin.value = mini(_qty_spin.value, max_qty)

	_refresh_info()


## ============================================================================
## ACTIONS
## ============================================================================

func _on_buy_pressed() -> void:
	if _selected_index < 0 or _selected_type != Tab.BUY:
		show_notification("Select an item to buy", false)
		return
	if _offering == null:
		show_notification("Shop unavailable", false)
		return
	var svc = VendorService.singleton()
	if svc == null:
		show_notification("Shop unavailable", false)
		return

	var entry: Dictionary = _catalog[_selected_index]
	var item: Resource = entry.get("item")
	if item == null:
		return

	var qty: int = int(_qty_spin.value) if _qty_spin else 1
	var result: Dictionary = svc.buy_item(_player_id, _offering, _npc_data, item.id, qty)
	if result.get("success"):
		show_notification(result.get("message") if result.has("message") else "Purchased!")
		_load_catalog()
		_refresh_grid()
		_refresh_gold()
	else:
		show_notification(result.get("message") if result.has("message") else "Purchase failed", false)


func _on_sell_pressed() -> void:
	if _selected_index < 0 or _selected_type != Tab.SELL:
		show_notification("Select an item to sell", false)
		return
	if _offering == null:
		show_notification("Shop unavailable", false)
		return
	var svc = VendorService.singleton()
	if svc == null:
		show_notification("Shop unavailable", false)
		return

	var entry: Dictionary = _sellable[_selected_index]
	var item: Resource = entry.get("item")
	if item == null:
		return

	var qty: int = int(_qty_spin.value) if _qty_spin else 1
	var slot: int = entry.get("slot") if entry.has("slot") else 0
	var result: Dictionary = svc.sell_item(_player_id, _offering, _npc_data, item.id, slot, qty)
	if result.get("success"):
		show_notification(result.get("message") if result.has("message") else "Sold!")
		_load_sellable()
		_refresh_grid()
		_refresh_gold()
	else:
		show_notification(result.get("message") if result.has("message") else "Sale failed", false)


func _on_leave_pressed() -> void:
	close()


func _on_qty_changed(value: float) -> void:
	_refresh_info()


## ============================================================================
## OPEN / CLOSE
## ============================================================================

func _on_open() -> void:
	_load_catalog()
	_load_sellable()
	_refresh_gold()
	_refresh_grid()
	_refresh_info()


func _on_close() -> void:
	# Handle restock on close
	if _offering != null and _offering.type == "vendor":
		if _offering.restock_trigger == "close":
			var svc = VendorService.singleton()
			if svc:
				svc.restock(_offering)
	_proximity_enabled = false
	_offering = null
	_npc_data = null
	_player_id = ""
	_instance = null


## ============================================================================
## PROXIMITY (uses canonical check_interact_distance)
## ============================================================================

func _process(_delta: float) -> void:
	if not _proximity_enabled or _npc_position == Vector3.ZERO:
		return
	var player := _get_local_player()
	if player == null:
		return
	# Use canonical distance check with configurable threshold
	if not check_interact_distance(player.global_position, _npc_position):
		close()
		if _notify_svc():
			var NotifKind = load("res://core/notifications/notification_kind.gd").NotifKind
			_notify_svc().notify(NotifKind.CUSTOM, "Moved too far from the shop.",
				"ShopUI", "shop_out_of_range", {}, _player_id)


## ============================================================================
## HELPERS
## ============================================================================

func _load_item_icon(item: Resource) -> Texture2D:
	return IconResolver.get_item_icon(item)
