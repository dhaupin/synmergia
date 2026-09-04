## VendorService - Handles all NPC vendor buy/sell transactions.
##
## Players buy items from vendors and sell items back.
## Pricing: buy = item.buy_price * sell_multiplier * price_multiplier * location_mod
##           sell = item.sell_price * buy_multiplier * location_mod
##
## Stock is tracked in-memory per offering instance. Limited-stock vendors
## track remaining qty per item. Unlimited vendors skip tracking.
##
## Restock: triggered when player closes shop (restock_trigger == "close").
## Location modifiers come from NPCData.location_type.
extends Node
class_name VendorService

const Item = preload("res://core/schemas/item.gd")
const NPCOffering = preload("res://core/schemas/npc_offering.gd")
const InventoryComponent = preload("res://core/components/inventory_component.gd")

## In-memory stock: offering_id -> {item_id -> qty}
var _stock: Dictionary = {}

## Buyback items: player_id -> [{item, qty, price}]
## Temporarily held items the player can buy back immediately after selling.
var _buyback: Dictionary = {}

## ============================================================================
## PUBLIC API
## ============================================================================

## Get the catalog of items a vendor sells to the player.
## Returns Array[Dictionary] with {item, price, stock_remaining}.
func get_catalog(offering, npc_data) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if offering.type != "vendor":
		return result

	var items := _resolve_catalog_items(offering, npc_data)
	for item_res in items:
		var item: Item = item_res
		if item == null:
			continue
		var price := _calculate_buy_price(item, offering, npc_data)
		var stock := _get_stock_remaining(offering, item.id)
		result.append({
			"item": item,
			"price": price,
			"stock": stock,
			"unlimited": offering.unlimited_stock
		})
	return result


## Get the player's sellable items — inventory filtered by what vendor buys.
func get_sellable_items(player_id: String, offering, npc_data) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if offering.type != "vendor":
		return result

	if not offering.buy_categories.is_empty():
		var inv: InventoryComponent = _get_player_inventory(player_id)
		if inv != null:
			var all_items: Array = inv.get_all_items()
			for i in range(all_items.size()):
				var item: Item = all_items[i]
				if item == null:
					continue
				var qty: int = item.current_stack
				if qty <= 0:
					continue
				if offering.buy_categories.has(item.item_category):
					var price := _calculate_sell_price(item, offering, npc_data)
					result.append({
						"item": item,
						"quantity": qty,
						"price": price,
						"slot": i
					})
	return result


## Buy an item from the vendor.
## Returns {success: bool, message: String, item: Item}
func buy_item(player_id: String, offering, npc_data, item_id: String, qty: int) -> Dictionary:
	if offering.type != "vendor":
		return _fail("Not a vendor")

	if qty <= 0:
		return _fail("Invalid quantity")

	var item: Item = _find_item(item_id)
	if item == null:
		return _fail("Item not found: %s" % item_id)

	var price: int = _calculate_buy_price(item, offering, npc_data) * qty

	# Stock check for limited vendors
	if not offering.unlimited_stock:
		var remaining: int = _get_stock_remaining(offering, item_id)
		if remaining < qty:
			return _fail("Not enough stock (only %d remaining)" % remaining)

	# Verify player can afford it
	var gold: int = _get_player_gold(player_id)
	if gold < price:
		return _fail("Not enough gold (need %d, have %d)" % [price, gold])

	# Verify player has inventory space
	var inv: InventoryComponent = _get_player_inventory(player_id)
	var empty_slots: int = _count_empty_slots(inv)
	if empty_slots < 1:
		return _fail("Inventory full")

	# Execute transaction
	_remove_player_gold(player_id, price)
	_add_item_to_player_inventory(player_id, item, qty)

	# Decrement stock
	if not offering.unlimited_stock:
		_decrement_stock(offering, item_id, qty)

	return _ok("Purchased %s" % item.display_name, item)


## Sell an item to the vendor.
## Returns {success: bool, message: String, gold_earned: int}
func sell_item(player_id: String, offering, npc_data, item_id: String, slot_key: int, qty: int) -> Dictionary:
	if offering.type != "vendor":
		return _fail("Not a vendor")

	if qty <= 0:
		return _fail("Invalid quantity")

	# Find item in player inventory by slot index
	var inv: InventoryComponent = _get_player_inventory(player_id)
	if inv == null:
		return _fail("Cannot access inventory")

	var item: Item = inv.get_item(slot_key)
	if item == null or item.id != item_id:
		return _fail("Item not in that slot")

	var owned_qty: int = item.current_stack
	if owned_qty < qty:
		return _fail("Not enough items to sell")

	# Check vendor buys this category
	if not offering.buy_categories.is_empty():
		if not offering.buy_categories.has(item.item_category):
			return _fail("This vendor does not buy %s items" % Item.ItemCategory.keys()[item.item_category])

	var sell_price: int = _calculate_sell_price(item, offering, npc_data) * qty

	# Execute transaction
	_remove_item_from_inventory(player_id, slot_key, qty)
	_add_player_gold(player_id, sell_price)

	# Add to buyback
	_add_buyback(player_id, item, qty, sell_price)

	return _ok_sell("Sold %s for %d gold" % [item.display_name, sell_price], sell_price)


## Get the player's buyback list for a vendor session.
func get_buyback(player_id: String) -> Array[Dictionary]:
	if _buyback.has(player_id):
		return _buyback[player_id]
	return []


## Clear buyback for a player.
func clear_buyback(player_id: String) -> void:
	_buyback.erase(player_id)


## Trigger restock for an offering. Called when shop closes.
func restock(offering) -> void:
	if offering.unlimited_stock:
		return
	if offering.restock_trigger == "close":
		_full_restock(offering)


## Initialize stock for an offering if not already initialized.
func ensure_stock(offering, npc_data) -> void:
	if offering.unlimited_stock:
		return
	var offering_id: String = offering.id
	if not _stock.has(offering_id):
		_initialize_stock(offering, npc_data)


## ============================================================================
## INTERNAL — CATALOG RESOLUTION
## ============================================================================

func _resolve_catalog_items(offering, npc_data) -> Array:
	var items: Array = []
	match offering.stock_mode:
		"by_category":
			items = _get_items_by_categories(offering.sell_categories)
		"by_item_id":
			items = _get_items_by_id_list(offering.catalog_items)
		"mixed":
			var by_cat: Array = _get_items_by_categories(offering.sell_categories)
			var by_ids: Array = _get_items_by_id_list(offering.catalog_items)
			for itm in by_ids:
				if not items.has(itm):
					items.append(itm)
			for itm in by_cat:
				if not items.has(itm):
					items.append(itm)
	return items


func _get_items_by_categories(categories: Array[int]) -> Array:
	var result: Array = []
	var all_items: Dictionary = DataService.get_all_items() if DataService else {}
	for item_id in all_items:
		var item: Item = all_items[item_id]
		if item != null and categories.has(item.item_category):
			result.append(item)
	return result


func _get_items_by_id_list(catalog_items: Array[Dictionary]) -> Array:
	var result: Array = []
	for entry: Dictionary in catalog_items:
		var item_id: String = entry.get("item_id", "")
		if item_id.is_empty():
			continue
		var item: Item = DataService.get_item(item_id) if DataService else null
		if item != null:
			result.append(item)
	return result


## ============================================================================
## INTERNAL — PRICING
## ============================================================================

func _calculate_buy_price(item: Item, offering, npc_data) -> int:
	var base: float = float(item.buy_price)
	if base <= 0:
		base = float(item.sell_price) * 2.0  # fallback

	var sell_mult: float = 1.0
	if npc_data and "sell_multiplier" in npc_data:
		sell_mult = npc_data.sell_multiplier

	var offering_mult: float = offering.price_multiplier if "price_multiplier" in offering else 1.0
	var location_mult: float = _get_location_multiplier(npc_data)

	var total := base * sell_mult * offering_mult * location_mult
	return maxi(1, int(total))


func _calculate_sell_price(item: Item, offering, npc_data) -> int:
	var base: float = float(item.sell_price)
	if base <= 0:
		base = 1.0

	var buy_mult: float = 0.5
	if npc_data and "buy_multiplier" in npc_data:
		buy_mult = npc_data.buy_multiplier

	var location_mult: float = _get_location_multiplier(npc_data)

	var total := base * buy_mult * location_mult
	return maxi(1, int(total))


func _get_location_multiplier(npc_data) -> float:
	if npc_data == null:
		return 1.0
	var loc_type: int = 0
	if "location_type" in npc_data:
		loc_type = npc_data.location_type
	# NPCData.LocationType enum: 0=TOWN, 1=OUTPOST, 2=VILLAGE, 3=DUNGEON, 4=CAPITAL
	match loc_type:
		0: return 1.0   # TOWN
		1: return 1.25  # OUTPOST
		2: return 0.9   # VILLAGE
		3: return 2.0   # DUNGEON
		4: return 1.5   # CAPITAL
	return 1.0


## ============================================================================
## INTERNAL — STOCK
## ============================================================================

func _initialize_stock(offering, npc_data) -> void:
	var offering_id: String = offering.id
	_stock[offering_id] = {}

	if offering.stock_mode == "by_item_id" or offering.stock_mode == "mixed":
		for entry: Dictionary in offering.catalog_items:
			var item_id: String = entry.get("item_id", "")
			var qty: int = entry.get("qty", offering.stock_qty)
			if not item_id.is_empty():
				_stock[offering_id][item_id] = qty
	else:
		# BY_CATEGORY: initialize all matching items
		var items: Array = _resolve_catalog_items(offering, npc_data)
		for item_res in items:
			var item: Item = item_res
			if item != null:
				_stock[offering_id][item.id] = offering.stock_qty


func _get_stock_remaining(offering, item_id: String) -> int:
	if offering.unlimited_stock:
		return 9999
	var offering_id: String = offering.id
	if not _stock.has(offering_id):
		return offering.stock_qty
	return _stock[offering_id].get(item_id, 0)


func _decrement_stock(offering, item_id: String, qty: int) -> void:
	if offering.unlimited_stock:
		return
	var offering_id: String = offering.id
	if not _stock.has(offering_id):
		return
	var current: int = _stock[offering_id].get(item_id, 0)
	_stock[offering_id][item_id] = maxi(0, current - qty)


func _full_restock(offering) -> void:
	if offering.unlimited_stock:
		return
	var offering_id: String = offering.id
	if not _stock.has(offering_id):
		return
	for item_id in _stock[offering_id]:
		_stock[offering_id][item_id] = offering.stock_qty


## ============================================================================
## INTERNAL — INVENTORY BRIDGE
## ============================================================================

func _get_player_inventory(player_id: String) -> InventoryComponent:
	if InventoryService == null:
		return null
	return InventoryService.get_inventory(player_id)


func _get_player_gold(player_id: String) -> int:
	if InventoryService == null:
		return 0
	return InventoryService.get_gold(player_id)


func _add_player_gold(player_id: String, amount: int) -> void:
	if InventoryService == null:
		return
	var inv: InventoryComponent = InventoryService.get_inventory(player_id)
	if inv:
		inv.add_gold(amount)


func _remove_player_gold(player_id: String, amount: int) -> void:
	if InventoryService == null:
		return
	var inv: InventoryComponent = InventoryService.get_inventory(player_id)
	if inv:
		inv.remove_gold(amount)


func _add_item_to_player_inventory(player_id: String, item: Item, qty: int) -> void:
	if InventoryService == null:
		return
	var inv: InventoryComponent = InventoryService.get_inventory(player_id)
	if inv:
		var instance := item.duplicate()
		instance.current_stack = mini(qty, item.stack_size)
		inv.add_item(instance)


func _remove_item_from_inventory(player_id: String, slot: int, qty: int) -> void:
	if InventoryService == null:
		return
	var inv: InventoryComponent = InventoryService.get_inventory(player_id)
	if inv:
		inv.remove_item(slot, qty)


func _count_empty_slots(inv: InventoryComponent) -> int:
	if inv == null:
		return 0
	return inv.get_free_slot_count()


func _find_item(item_id: String) -> Item:
	if DataService and DataService.has_method("get_item"):
		return DataService.get_item(item_id)
	return null


## ============================================================================
## INTERNAL — BUYBACK
## ============================================================================

func _add_buyback(player_id: String, item: Item, qty: int, price: int) -> void:
	if not _buyback.has(player_id):
		_buyback[player_id] = []
	# Keep last 10 buyback items
	if _buyback[player_id].size() >= 10:
		_buyback[player_id].pop_front()
	_buyback[player_id].append({
		"item": item,
		"quantity": qty,
		"price": price
	})


## ============================================================================
## INTERNAL — RESULT HELPERS
## ============================================================================

func _ok(msg: String, item: Item = null) -> Dictionary:
	return {"success": true, "message": msg, "item": item}

func _ok_sell(msg: String, gold: int) -> Dictionary:
	return {"success": true, "message": msg, "gold_earned": gold}

func _fail(msg: String) -> Dictionary:
	return {"success": false, "message": msg, "item": null}
