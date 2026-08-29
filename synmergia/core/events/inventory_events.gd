## InventoryEvents - Domain events for inventory management
class_name InventoryEvents
extends Node

# Item pickup/drop events
signal item_picked_up(entity_id: String, item_id: String, slot: int)
signal item_dropped(entity_id: String, item_id: String, position: Vector3)
signal item_destroyed(item_id: String, reason: String)

# Equipment events
signal item_equipped(entity_id: String, item_id: String, slot: String)
signal item_unequipped(entity_id: String, item_id: String, slot: String)
signal equipment_changed(entity_id: String, slot: String, old_item_id: String, new_item_id: String)

# Inventory operations
signal item_moved(entity_id: String, item_id: String, from_slot: int, to_slot: int)
signal inventory_full(entity_id: String, rejected_item_id: String)

# Trade events
signal trade_requested(from_entity_id: String, to_entity_id: String, trade_id: String)
signal trade_completed(trade_id: String, from_entity_id: String, to_entity_id: String)

# Currency/gold events
signal gold_gained(entity_id: String, amount: int, source: String)
signal gold_spent(entity_id: String, amount: int, destination: String)

# Event history
var _history: Array = []
const MAX_HISTORY := 1000

func _log_event(name: String, data: Dictionary = {}) -> void:
	_history.append({"name": name, "data": data, "time": Time.get_ticks_msec()})
	if _history.size() > MAX_HISTORY:
		_history.pop_front()

func get_event_count() -> int:
	return _history.size()

func clear_history() -> void:
	_history.clear()
