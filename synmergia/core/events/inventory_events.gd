## InventoryEvents - Domain events for inventory and item management
## Pickup, drop, equip, trade, and item transactions
class_name InventoryEvents
extends BaseEventBus

# Item pickup/drop events
signal item_picked_up(entity_id: String, item_id: String, slot: int)
signal item_dropped(entity_id: String, item_id: String, position: Vector3)
signal item_destroyed(item_id: String, reason: String)

# Item stack events
signal item_stacked(entity_id: String, source_item_id: String, target_item_id: String, amount: int)
signal item_unstacked(entity_id: String, item_id: String, new_item_id: String, amount: int)

# Equipment events
signal item_equipped(entity_id: String, item_id: String, slot: String)
signal item_unequipped(entity_id: String, item_id: String, slot: String)
signal equipment_changed(entity_id: String, slot: String, old_item_id: String, new_item_id: String)

# Inventory operations
signal item_moved(entity_id: String, item_id: String, from_slot: int, to_slot: int)
signal item_swapped(entity_id: String, item1_id: String, slot1: int, item2_id: String, slot2: int)
signal inventory_full(entity_id: String, rejected_item_id: String)
signal inventory_sorted(entity_id: String)

# Trade events
signal trade_requested(from_entity_id: String, to_entity_id: String, trade_id: String)
signal trade_accepted(trade_id: String, from_entity_id: String, to_entity_id: String)
signal trade_declined(trade_id: String, declined_by: String)
signal trade_cancelled(trade_id: String, cancelled_by: String)
signal trade_completed(trade_id: String, from_entity_id: String, to_entity_id: String, items_from: Array, items_to: Array)

# Loot events
signal loot_opened(looter_id: String, loot_id: String)
signal loot_taken(looter_id: String, loot_id: String, item_id: String)
signal loot_rejected(looter_id: String, loot_id: String, item_id: String)
signal loot_expired(loot_id: String)

# Crafting events
signal crafting_started(crafter_id: String, recipe_id: String, material_ids: Array)
signal crafting_progress(crafter_id: String, recipe_id: String, progress: float)
signal crafting_completed(crafter_id: String, recipe_id: String, result_item_id: String)
signal crafting_failed(crafter_id: String, recipe_id: String, reason: String)
signal crafting_cancelled(crafter_id: String, recipe_id: String)

# Merchant transactions
signal item_purchased(buyer_id: String, merchant_id: String, item_id: String, price: int)
signal item_sold(seller_id: String, merchant_id: String, item_id: String, price: int)
signal item_locked_for_trade(entity_id: String, item_id: String)
signal item_unlocked_from_trade(entity_id: String, item_id: String)

# Currency/gold events
signal gold_gained(entity_id: String, amount: int, source: String)
signal gold_spent(entity_id: String, amount: int, destination: String)
signal gold_transfer(from_entity_id: String, to_entity_id: String, amount: int, reason: String)

## Emit item picked up event
func emit_item_picked_up(entity_id: String, item_id: String, slot: int = -1) -> void:
	_log_event("item_picked_up", {"entity_id": entity_id, "item_id": item_id})
	item_picked_up.emit(entity_id, item_id, slot)

## Emit equipment change event
func emit_equipment_changed(entity_id: String, slot: String, old_item_id: String, new_item_id: String) -> void:
	_log_event("equipment_changed", {"entity_id": entity_id, "slot": slot})
	equipment_changed.emit(entity_id, slot, old_item_id, new_item_id)

## Emit gold gained event
func emit_gold_gained(entity_id: String, amount: int, source: String) -> void:
	_log_event("gold_gained", {"entity_id": entity_id, "amount": amount, "source": source})
	gold_gained.emit(entity_id, amount, source)

## Emit gold spent event
func emit_gold_spent(entity_id: String, amount: int, destination: String) -> void:
	_log_event("gold_spent", {"entity_id": entity_id, "amount": amount, "destination": destination})
	gold_spent.emit(entity_id, amount, destination)
