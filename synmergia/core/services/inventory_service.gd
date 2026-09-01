## InventoryService - Player inventory operations
## Handles inventory-related operations and cross-player inventory access
extends Node

# Singleton instance
static var instance: InventoryService

# Player inventories (player_id -> InventoryComponent)
var _player_inventories: Dictionary = {}

signal item_transferred(from_id: String, to_id: String, item: Item, quantity: int)
signal gold_transferred(from_id: String, to_id: String, amount: int)

# Frame-level notification dispatch (see synmergia/core/notifications/).
# InventoryService surfaces add/remove/full/soulbound/trade-reject events
# through the toast pipeline. Dedupe keys are item-aware so a player
# looting 50 of the same item sees one toast for the burst, not 50.
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

func _emit_inventory(
	player_id: String,
	kind: int,
	message: String,
	dedupe_key: String = "",
	data: Dictionary = {}
) -> void:
	if not is_instance_valid(NotificationService):
		return
	# Frame-level dispatch via the typed-Kind pipeline. notify()
	# builds the context internally and forwards through dedupe +
	# send(); the legacy NotificationContext wrapper is no longer
	# needed at this call site.
	NotificationService.notify(
		kind,
		message,
		"InventoryService",
		dedupe_key,
		data,
		player_id
	)

func _ready() -> void:
	instance = self
	GameLog.info("InventoryService: Ready")

## Register a player's inventory
func register_inventory(player_id: String, inventory: InventoryComponent) -> void:
	_player_inventories[player_id] = inventory
	GameLog.debug("InventoryService: Registered inventory for %s" % player_id)

## Unregister a player's inventory
func unregister_inventory(player_id: String) -> void:
	_player_inventories.erase(player_id)

## Get player's inventory
func get_inventory(player_id: String) -> InventoryComponent:
	return _player_inventories.get(player_id)

## Check if player has inventory registered
func has_inventory(player_id: String) -> bool:
	return _player_inventories.has(player_id)

## Transfer item from one player to another
func transfer_item(from_id: String, to_id: String, item: Item, quantity: int = -1) -> bool:
	# QoS: Rate limit inventory transfers
	if not QoSService.rate_limit(from_id, "inventory_transfer"):
		GameLog.debug("InventoryService: Rate limited transfer for %s" % from_id)
		return false
	
	# SECURITY: Validate inputs
	if from_id == "" or to_id == "" or item == null:
		GameLog.error("InventoryService: Invalid transfer parameters")
		return false
	
	if from_id == to_id:
		GameLog.warn("InventoryService: Cannot transfer to self")
		return false
	
	# SECURITY: Check both players are registered
	var from_inv: InventoryComponent = get_inventory(from_id)
	var to_inv: InventoryComponent = get_inventory(to_id)
	if not from_inv or not to_inv:
		GameLog.error("InventoryService: Missing inventory for transfer %s -> %s" % [from_id, to_id])
		return false

	# Find item in source inventory
	var slot: int = from_inv.find_item(item.id)
	if slot < 0:
		GameLog.warn("InventoryService: Item %s not found in %s" % [item.id, from_id])
		return false

	# SECURITY: Verify item is actually at this slot (ownership check)
	var source_item: Item = from_inv.get_item(slot)
	if source_item == null or source_item != item:
		GameLog.error("InventoryService: Item ownership verification failed for %s" % item.id)
		return false

	# SECURITY: Reject soulbound items. bind_on_pickup binds at first pickup;
	# soulbound is the explicit flag the schema exposes.
	if source_item.soulbound or source_item.bind_on_pickup:
		GameLog.warn("InventoryService: Refusing to transfer soulbound item %s from %s" % [item.id, from_id])
		_emit_inventory(
			from_id,
			NotifKind.ITEM_SOULBOUND_REJECT,
			"%s is soulbound and cannot be transferred" % item.display_name,
			"inv_soulbound:%s:%s" % [from_id, item.id],
			{"item_id": item.id, "reason": "soulbound"}
		)
		return false

	# Remove from source
	var removed: Item = from_inv.remove_item(slot, quantity)
	if not removed:
		return false

	# Add to destination
	if not to_inv.add_item(removed):
		# Failed to add - return to source
		from_inv.add_item(removed)
		GameLog.warn("InventoryService: Transfer failed - destination full")
		# Frame-level toast on the destination player. Dedupe on (to, item)
		# so a series of failed transfers for the same item doesn't spam.
		_emit_inventory(
			to_id,
			NotifKind.ITEM_FULL,
			"Inventory full — couldn't receive %s" % item.display_name,
			"inv_full:%s:%s" % [to_id, item.id],
			{"item_id": item.id, "from_id": from_id, "qty": removed.current_stack}
		)
		return false

	item_transferred.emit(from_id, to_id, removed, removed.current_stack)
	# Frame-level toasts: recipient sees "received", sender sees "sent".
	# Two distinct players → two distinct dedupe keys, both fire normally.
	_emit_inventory(
		to_id,
		NotifKind.ITEM_ADDED,
		"Received %s x%d" % [item.display_name, removed.current_stack],
		"inv_recv:%s:%s" % [to_id, item.id],
		{"item_id": item.id, "from_id": from_id, "qty": removed.current_stack}
	)
	_emit_inventory(
		from_id,
		NotifKind.ITEM_REMOVED,
		"Sent %s x%d" % [item.display_name, removed.current_stack],
		"inv_sent:%s:%s" % [from_id, item.id],
		{"item_id": item.id, "to_id": to_id, "qty": removed.current_stack}
	)
	GameLog.info("InventoryService: Transferred %s x%d from %s to %s" % [item.id, removed.current_stack, from_id, to_id])

	return true

## Transfer gold from one player to another
func transfer_gold(from_id: String, to_id: String, amount: int) -> bool:
	# QoS: Rate limit gold transfers
	if not QoSService.rate_limit(from_id, "gold_transfer"):
		GameLog.debug("InventoryService: Rate limited gold transfer for %s" % from_id)
		return false
	
	# SECURITY: Validate inputs
	if from_id == "" or to_id == "":
		GameLog.error("InventoryService: Invalid gold transfer parameters")
		return false
	
	if from_id == to_id:
		GameLog.warn("InventoryService: Cannot transfer gold to self")
		return false
	
	if amount <= 0:
		GameLog.warn("InventoryService: Cannot transfer negative or zero gold")
		return false
	
	# Check both players are registered
	var from_inv: InventoryComponent = get_inventory(from_id)
	var to_inv: InventoryComponent = get_inventory(to_id)
	if not from_inv or not to_inv:
		GameLog.error("InventoryService: Missing inventory for gold transfer %s -> %s" % [from_id, to_id])
		return false

	if not from_inv.remove_gold(amount):
		GameLog.warn("InventoryService: %s has insufficient gold for transfer" % from_id)
		return false

	to_inv.add_gold(amount)
	gold_transferred.emit(from_id, to_id, amount)
	GameLog.info("InventoryService: Transferred %d gold from %s to %s" % [amount, from_id, to_id])

	return true

## Transfer multiple items at once
func transfer_items(from_id: String, to_id: String, items: Array) -> Dictionary:
	var results := {
		"success": true,
		"transferred": [],
		"failed": []
	}

	for item_data in items:
		var item_id: String = item_data.get("item_id", "")
		var quantity: int = item_data.get("quantity", -1)

		if item_id == "":
			results["failed"].append({"item_id": item_id, "reason": "Invalid item_id"})
			results["success"] = false
			continue

		# Find item in source
		var from_inv: InventoryComponent = get_inventory(from_id)
		if not from_inv:
			results["failed"].append({"item_id": item_id, "reason": "Source inventory not found"})
			results["success"] = false
			continue

		var slot: int = from_inv.find_item(item_id)
		if slot < 0:
			results["failed"].append({"item_id": item_id, "reason": "Item not found"})
			results["success"] = false
			continue

		# Transfer this item
		if not transfer_item(from_id, to_id, from_inv.get_item(slot), quantity):
			results["failed"].append({"item_id": item_id, "reason": "Transfer failed"})
			results["success"] = false
		else:
			results["transferred"].append(item_id)

	# Frame-level toast on the sender: if the whole batch failed and nothing
	# transferred, surface a single trade-reject. The per-item toasts already
	# fire from transfer_item, so this is just the summary line.
	if not results["success"] and results["transferred"].is_empty() and not results["failed"].is_empty():
		var first_fail: Dictionary = results["failed"][0]
		_emit_inventory(
			from_id,
			NotifKind.ITEM_TRADE_REJECT,
			"Trade rejected (%d item(s) failed)" % results["failed"].size(),
			"trade_reject:%s:%s" % [from_id, first_fail.get("item_id", "unknown")],
			{"failed_count": results["failed"].size(), "to_id": to_id}
		)

	return results

## Execute a full trade (used by TradeService)
func execute_trade(trade_id: String, player1: String, player2: String, 
				   player1_items: Array, player2_items: Array,
				   player1_gold: int, player2_gold: int) -> Dictionary:
	# QoS: Rate limit trades for both players
	if not QoSService.rate_limit(player1, "inventory_trade"):
		GameLog.debug("InventoryService: Rate limited trade for %s" % player1)
		return {"success": false, "error": "Rate limited"}
	if not QoSService.rate_limit(player2, "inventory_trade"):
		GameLog.debug("InventoryService: Rate limited trade for %s" % player2)
		return {"success": false, "error": "Rate limited"}

	var results := {
		"trade_id": trade_id,
		"player1": {
			"items_transferred": [],
			"gold_transferred": 0
		},
		"player2": {
			"items_transferred": [],
			"gold_transferred": 0
		},
		"success": true
	}

	# Transfer gold
	if player1_gold > 0:
		if transfer_gold(player1, player2, player1_gold):
			results["player1"]["gold_transferred"] = player1_gold
		else:
			results["success"] = false

	if player2_gold > 0:
		if transfer_gold(player2, player1, player2_gold):
			results["player2"]["gold_transferred"] = player2_gold
		else:
			results["success"] = false

	# Transfer items from player1 to player2
	for item_data in player1_items:
		var item_id: String = item_data.get("item_id", "")
		var quantity: int = item_data.get("quantity", -1)

		var from_inv: InventoryComponent = get_inventory(player1)
		if not from_inv:
			continue

		var slot: int = from_inv.find_item(item_id)
		if slot < 0:
			continue

		var item: Item = from_inv.get_item(slot)
		if item and transfer_item(player1, player2, item, quantity):
			results["player1"]["items_transferred"].append(item_id)

	# Transfer items from player2 to player1
	for item_data in player2_items:
		var item_id: String = item_data.get("item_id", "")
		var quantity: int = item_data.get("quantity", -1)

		var from_inv: InventoryComponent = get_inventory(player2)
		if not from_inv:
			continue

		var slot: int = from_inv.find_item(item_id)
		if slot < 0:
			continue

		var item: Item = from_inv.get_item(slot)
		if item and transfer_item(player2, player1, item, quantity):
			results["player2"]["items_transferred"].append(item_id)

	GameLog.info("InventoryService: Trade %s completed - success: %s" % [trade_id, results["success"]])
	return results

## Get player's gold
func get_gold(player_id: String) -> int:
	var inv: InventoryComponent = get_inventory(player_id)
	if inv:
		return inv.get_gold()
	return 0

## Check if player can receive item (has space and weight)
func can_receive_item(player_id: String, item: Item) -> bool:
	var inv: InventoryComponent = get_inventory(player_id)
	if not inv:
		return false

	# Check weight
	if not inv.can_carry(item):
		return false
	
	# Check slot (will return false if no space)
	return true

## Get inventory summary
func get_inventory_summary(player_id: String) -> Dictionary:
	var inv: InventoryComponent = get_inventory(player_id)
	if not inv:
		return {}

	return {
		"player_id": player_id,
		"gold": inv.get_gold(),
		"current_weight": inv.get_current_weight(),
		"max_weight": inv.get_max_weight(),
		"encumbered": inv.is_encumbered(),
		"slots_used": inv.get_inventory_count(),
		"slots_total": inv.get_total_slots(),
		"free_slots": inv.get_free_slot_count()
	}
