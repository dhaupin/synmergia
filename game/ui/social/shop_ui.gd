## ShopUI - Merchant/shop interaction panel
## Browse and purchase items from NPCs
extends Control
class_name ShopUI

const UIStyles = preload("res://ui/components/ui_styles.gd")

var _npc_id: String = ""
var _shop_inventory: Array = []
var _cart: Dictionary = {}  # item_id -> quantity

signal panel_opened()
signal panel_closed()
signal item_purchased(item_id: String, quantity: int)

## Static entry point called by NPCEntity.on_interact()
static func open_for_offering(player_id: String, offering: Resource, npc_data, npc_pos: Vector3) -> void:
	# Find or create ShopUI instance
	var shop: ShopUI = _get_shop_instance()
	if shop == null:
		push_warning("ShopUI: No instance found in scene")
		return
	
	# Build shop data from offering
	var shop_name := "Merchant"
	if npc_data != null:
		if npc_data.get("display_name"):
			shop_name = npc_data.display_name
		elif typeof(npc_data) == TYPE_OBJECT and "display_name" in npc_data:
			shop_name = npc_data.display_name
	var shop_data := {
		"name": shop_name,
		"items": _build_inventory_from_offering(offering)
	}
	shop.open("shop", shop_data)


static func _get_shop_instance() -> ShopUI:
	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	var root: SceneTree = tree as SceneTree
	if root == null:
		return null
	return root.root.get_node_or_null("HudLayer/ShopUI") as ShopUI


static func _build_inventory_from_offering(offering: Resource) -> Array:
	var items: Array = []
	if offering == null:
		return items
	# Items come from offering.items or default to empty
	# Use get() for Dictionary-like access, fallback to property access
	if typeof(offering) == TYPE_OBJECT:
		if "catalog_items" in offering:
			items = offering.catalog_items if offering.catalog_items else []
		elif "items" in offering:
			items = offering.items if offering.items else []
	return items

func _ready() -> void:
	name = "ShopUI"
	visible = false
	_setup_ui()

func _setup_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	add_child(vbox)

	# Header
	var header := Label.new()
	header.name = "Header"
	header.text = "Shop"
	header.add_theme_font_size_override("font_size", 18)
	vbox.add_child(header)

	# NPC name
	var npc_lbl := Label.new()
	npc_lbl.name = "NPCName"
	npc_lbl.text = ""
	vbox.add_child(npc_lbl)

	# Item list
	var scroll := ScrollContainer.new()
	scroll.name = "ShopScroll"
	scroll.custom_minimum_size.y = 300
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "ItemList"
	scroll.add_child(list)

	# Cart section
	var cart_lbl := Label.new()
	cart_lbl.name = "CartLabel"
	cart_lbl.text = "Cart: Empty"
	vbox.add_child(cart_lbl)

	var total_lbl := Label.new()
	total_lbl.name = "TotalLabel"
	total_lbl.text = "Total: 0 gold"
	vbox.add_child(total_lbl)

	# Buttons
	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)

	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.pressed.connect(_on_buy_pressed)
	btn_row.add_child(buy_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close)
	btn_row.add_child(close_btn)

func open(npc_id: String, shop_data: Dictionary) -> void:
	_npc_id = npc_id
	visible = true
	panel_opened.emit()
	
	# Update NPC name
	var npc_lbl: Label = get_node_or_null("VBox/NPCName")
	if npc_lbl:
		npc_lbl.text = shop_data.get("name", "Merchant")
	
	# Load shop inventory
	_shop_inventory = shop_data.get("items", [])
	_refresh_items()

func close() -> void:
	visible = false
	_cart.clear()
	panel_closed.emit()

func toggle(panel_id: String = "") -> void:
	if visible:
		close()
	else:
		open("", {})

func is_open() -> bool:
	return visible

func _refresh_items() -> void:
	var list: VBoxContainer = get_node_or_null("VBox/ShopScroll/ItemList")
	if not list:
		return
	
	# Clear existing
	for child in list.get_children():
		child.queue_free()
	
	# Add items
	for item in _shop_inventory:
		var row := _create_item_row(item)
		list.add_child(row)

func _create_item_row(item: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 45
	
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)
	
	# Item name
	var name_lbl := Label.new()
	name_lbl.text = item.get("name", "Item")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)
	
	# Price
	var price_lbl := Label.new()
	price_lbl.text = "%d gold" % item.get("price", 0)
	hbox.add_child(price_lbl)
	
	# Buy button
	var buy_btn := Button.new()
	buy_btn.text = "+"
	buy_btn.pressed.connect(_on_add_to_cart.bind(item))
	hbox.add_child(buy_btn)
	
	return panel

func _on_add_to_cart(item: Dictionary) -> void:
	var item_id := item.get("id", "")
	if not _cart.has(item_id):
		_cart[item_id] = 0
	_cart[item_id] += 1
	_update_cart()

func _update_cart() -> void:
	var cart_lbl: Label = get_node_or_null("VBox/CartLabel")
	var total_lbl: Label = get_node_or_null("VBox/TotalLabel")
	
	if cart_lbl:
		var items := _cart.values().reduce(func(acc, x): return acc + x, 0)
		cart_lbl.text = "Cart: %d items" % items
	
	if total_lbl:
		var total := 0
		for item_id in _cart:
			for item in _shop_inventory:
				if item.get("id", "") == item_id:
					total += item.get("price", 0) * _cart[item_id]
		total_lbl.text = "Total: %d gold" % total

func _on_buy_pressed() -> void:
	if _cart.is_empty():
		return
	
	# In full implementation, this would call InventoryService/payment service
	for item_id in _cart:
		item_purchased.emit(item_id, _cart[item_id])
	
	close()
