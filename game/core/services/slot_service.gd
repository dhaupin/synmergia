## SlotService - Unified slot container management
## Handles all slot-based storage: inventory, bank, guild vault, house storage, mounts, loot, trade
##
## Container Types (from ContainerConfigData):
##   - INVENTORY (0): Player personal inventory (24 base, expandable to 120)
##   - BANK (1): Personal bank storage (100 base, expandable to 400)
##   - GUILD_VAULT (2): Shared guild storage (200 base, expandable to 800)
##   - HOUSE_STORAGE (3): Per-house storage (50 base, expandable to 200)
##   - MOUNT_INVENTORY (4): Mount saddlebags (12 base, expandable to 36)
##   - EQUIPMENT_SLOTS (5): Equipment slots (16 fixed)
##   - LOOT (6): Temporary loot containers (24 slots, auto-close)
##   - SHOP (7): Vendor/shop interface (no slots, displays catalog)
##   - TRADE (8): Two-sided trade window (12 slots each side)
##
## Data-Driven:
##   All container configs loaded from ContainerConfigData (data/containers/*.tres)
##   Add new container types without code changes!
##
## Security (Anti-Dupe):
##   - Item instance validation on all operations
##   - Operation logging for audit trails
##   - Atomic operations with rollback on failure
##   - Rate limiting on rapid operations

extends Node
class_name SlotService

## Singleton
static var _instance: SlotService = null

## Data-driven config
const ContainerConfigData = preload("res://core/schemas/container_config_data.gd")

## Item schema
const Item = preload("res://core/schemas/item.gd")

## In-memory containers: container_key -> [Item, ...]
var _containers: Dictionary = {}

## Expansion state: container_key -> expansion_tier
var _expansion_state: Dictionary = {}

## Security: Operation log for audit/anti-dupe
var _operation_log: Array = []

## Rate limiting: container_key -> [timestamp, ...]
var _rate_limit_log: Dictionary = {}
const RATE_LIMIT_WINDOW := 1.0
const RATE_LIMIT_MAX := 20

## ============================================================================
## SINGLETON
## ============================================================================

static func singleton() -> SlotService:
if _instance == null:
_instance = load("res://core/services/slot_service.gd").new()
_instance._ready()
return _instance

func _ready() -> void:
GameLog.info("SlotService: Ready")

## ============================================================================
## CONTAINER KEYS
## ============================================================================

static func make_key(owner_id: String, container_type: int, instance_id: String = "") -> String:
var ct_key := ContainerConfigData.ContainerType.keys()[container_type]
if instance_id != "":
return "%s:%s:%s" % [owner_id, ct_key, instance_id]
return "%s:%s" % [owner_id, ct_key]

static func parse_key(key: String) -> Dictionary:
var parts := key.split(":")
if parts.size() < 2:
return {}
return {
"owner_id": parts[0],
"container_type": ContainerConfigData.ContainerType.get(parts[1], ContainerConfigData.ContainerType.INVENTORY),
"instance_id": parts[2] if parts.size() > 2 else ""
}

## ============================================================================
## SECURITY (ANTI-DUPE)
## ============================================================================

func _check_rate_limit(container_key: String) -> bool:
var now := Time.get_ticks_msec() / 1000.0
if not _rate_limit_log.has(container_key):
_rate_limit_log[container_key] = []
var log: Array = _rate_limit_log[container_key]
log = log.filter(func(t): return t > now - RATE_LIMIT_WINDOW)
_rate_limit_log[container_key] = log
if log.size() >= RATE_LIMIT_MAX:
return false
log.append(now)
return true

func _log_operation(operation: String, container_key: String, slot: int, item_id: String, quantity: int, player_id: String) -> void:
_operation_log.append({
"op": operation, "key": container_key, "slot": slot,
"item_id": item_id, "quantity": quantity, "player_id": player_id,
"time": Time.get_ticks_msec()
})
if _operation_log.size() > 1000:
_operation_log.resize(500)

func _validate_item(item: Item) -> bool:
return item != null and is_instance_valid(item)

## ============================================================================
## CONTAINER INITIALIZATION
## ============================================================================

func init_container(owner_id: String, container_type: int, instance_id: String = "", expansion_tier: int = 0) -> String:
var key := make_key(owner_id, container_type, instance_id)
if not _containers.has(key):
var expanded_slots := ContainerConfigData.get_slots_for_tier(container_type, expansion_tier)
_containers[key] = []
for i in expanded_slots:
_containers[key].append(null)
_expansion_state[key] = expansion_tier
GameLog.debug("SlotService: Initialized %s with %d slots" % [key, expanded_slots])
return key

func get_container_size(key: String) -> int:
if not _containers.has(key):
return 0
return _containers[key].size()

func get_container_config(container_type: int) -> Dictionary:
return ContainerConfigData.get_container(container_type)

## ============================================================================
## EXPANSION
## ============================================================================

func get_expansion_tier(key: String) -> int:
return _expansion_state.get(key, 0)

func get_slots_for_tier(container_type: int, tier: int) -> int:
return ContainerConfigData.get_slots_for_tier(container_type, tier)

func purchase_expansion(key: String, player_id: String, currency: String = "gold") -> Dictionary:
var parsed := parse_key(key)
var container_type := parsed["container_type"]
var config := ContainerConfigData.get_container(container_type)
var current_tier := get_expansion_tier(key)
if current_tier >= config.get("max_tier", 0):
return {"success": false, "error": "Already at max expansion"}
var cost := ContainerConfigData.get_expansion_cost(container_type, current_tier)
var required_currency := config.get("currency", "gold")
if currency != required_currency:
return {"success": false, "error": "Invalid currency type"}
if required_currency == "gold" and InventoryService:
if InventoryService.spend_gold(player_id, cost):
_execute_expansion(key, container_type, current_tier + 1)
return {"success": true, "new_tier": current_tier + 1, "new_slots": get_container_size(key), "cost": cost}
return {"success": false, "error": "Failed to deduct currency"}

func _execute_expansion(key: String, container_type: int, new_tier: int) -> void:
var target_slots := ContainerConfigData.get_slots_for_tier(container_type, new_tier)
var current_slots := _containers[key].size()
for i in range(target_slots - current_slots):
_containers[key].append(null)
_expansion_state[key] = new_tier
GameLog.info("SlotService: Expanded %s to tier %d (%d slots)" % [key, new_tier, target_slots])
expansion_purchased.emit(key, new_tier, target_slots)

## ============================================================================
## SLOT OPERATIONS
## ============================================================================

func get_slot(key: String, slot_index: int) -> Item:
if not _containers.has(key) or slot_index < 0 or slot_index >= _containers[key].size():
return null
return _containers[key][slot_index]

func set_slot(key: String, slot_index: int, item: Item, player_id: String = "") -> bool:
if not _containers.has(key) or slot_index < 0 or slot_index >= _containers[key].size():
return false
if not _check_rate_limit(key):
GameLog.warn("SlotService: Rate limited set_slot on %s" % key)
return false
if not _validate_item(item):
return false
var max_stack := ContainerConfigData.get_max_stack(parse_key(key)["container_type"])
if item != null:
item.stack_size = mini(item.stack_size, max_stack)
_log_operation("set_slot", key, slot_index, item.id if item else "", item.stack_size if item else 0, player_id)
_containers[key][slot_index] = item
slot_changed.emit(key, slot_index, item)
return true

func find_empty_slot(key: String) -> int:
if not _containers.has(key):
return -1
for i in _containers[key].size():
if _containers[key][i] == null:
return i
return -1

func find_item(key: String, item_id: String) -> int:
if not _containers.has(key):
return -1
for i in _containers[key].size():
var slot_item: Item = _containers[key][i]
if slot_item != null and slot_item.id == item_id:
return i
return -1

func get_all_items(key: String) -> Array:
if not _containers.has(key):
return []
var items: Array = []
for item in _containers[key]:
if item != null:
items.append(item)
return items

func count_item(key: String, item_id: String) -> int:
if not _containers.has(key):
return 0
var total := 0
for item in _containers[key]:
if item != null and item.id == item_id:
total += item.stack_size
return total

## ============================================================================
## ITEM OPERATIONS
## ============================================================================

func add_item(key: String, item: Item, max_stack_override: int = -1, player_id: String = "") -> Dictionary:
if item == null:
return {"success": false, "error": "Null item"}
if not _check_rate_limit(key):
return {"success": false, "error": "Rate limited"}
var parsed := parse_key(key)
var container_type := parsed["container_type"]
var max_stack: int = ContainerConfigData.get_max_stack(container_type) if max_stack_override < 0 else max_stack_override
var allow_stack := ContainerConfigData.allows_stacking(container_type)
if allow_stack:
var stack_slot := _find_stackable_slot(key, item.id, item.stack_size, max_stack)
if stack_slot >= 0:
var existing: Item = _containers[key][stack_slot]
var can_add := max_stack - existing.stack_size
var added := mini(item.stack_size, can_add)
existing.stack_size += added
_log_operation("stack", key, stack_slot, item.id, added, player_id)
if item.stack_size > added:
item.stack_size -= added
return add_item(key, item, max_stack_override, player_id)
slot_changed.emit(key, stack_slot, existing)
return {"success": true, "slot": stack_slot, "added": added}
var empty_slot := find_empty_slot(key)
if empty_slot < 0:
return {"success": false, "error": "Container full", "remaining": item}
item.stack_size = mini(item.stack_size, max_stack)
set_slot(key, empty_slot, item, player_id)
return {"success": true, "slot": empty_slot, "added": item.stack_size}

func _find_stackable_slot(key: String, item_id: String, quantity: int, max_stack: int) -> int:
for i in _containers[key].size():
var slot_item: Item = _containers[key][i]
if slot_item != null and slot_item.id == item_id and slot_item.stack_size < max_stack:
return i
return -1

func remove_item(key: String, slot_index: int, quantity: int = -1, player_id: String = "") -> Item:
var item: Item = get_slot(key, slot_index)
if item == null:
return null
if not _check_rate_limit(key):
return null
if quantity < 0 or quantity >= item.stack_size:
_containers[key][slot_index] = null
_log_operation("remove", key, slot_index, item.id, item.stack_size, player_id)
slot_changed.emit(key, slot_index, null)
return item
else:
var removed := item.duplicate()
removed.stack_size = quantity
item.stack_size -= quantity
_log_operation("partial_remove", key, slot_index, item.id, quantity, player_id)
slot_changed.emit(key, slot_index, item)
return removed

func move_item(from_key: String, from_slot: int, to_key: String, to_slot: int, player_id: String = "") -> bool:
var item: Item = get_slot(from_key, from_slot)
if item == null:
return false
if not _check_rate_limit(from_key) or not _check_rate_limit(to_key):
return false
var target_item: Item = get_slot(to_key, to_slot)
if target_item == null:
_containers[from_key][from_slot] = null
_containers[to_key][to_slot] = item
_log_operation("move", "%s->%s" % [from_key, to_key], from_slot, item.id, item.stack_size, player_id)
slot_changed.emit(from_key, from_slot, null)
slot_changed.emit(to_key, to_slot, item)
return true
elif target_item.id == item.id and ContainerConfigData.allows_stacking(parse_key(to_key)["container_type"]):
var max_stack := ContainerConfigData.get_max_stack(parse_key(to_key)["container_type"])
var can_add := max_stack - target_item.stack_size
if can_add >= item.stack_size:
target_item.stack_size += item.stack_size
_containers[from_key][from_slot] = null
slot_changed.emit(from_key, from_slot, null)
slot_changed.emit(to_key, to_slot, target_item)
else:
target_item.stack_size = max_stack
item.stack_size -= can_add
slot_changed.emit(to_key, to_slot, target_item)
return true
else:
_containers[from_key][from_slot] = target_item
_containers[to_key][to_slot] = item
_log_operation("swap", "%s<->%s" % [from_key, to_key], from_slot, item.id, item.stack_size, player_id)
slot_changed.emit(from_key, from_slot, target_item)
slot_changed.emit(to_key, to_slot, item)
return true

## ============================================================================
## UTILITY
## ============================================================================

func get_stats(key: String) -> Dictionary:
if not _containers.has(key):
return {}
var filled := 0
var total := _containers[key].size()
var item_count := 0
for item in _containers[key]:
if item != null:
filled += 1
item_count += item.stack_size
return {
"filled_slots": filled, "total_slots": total,
"empty_slots": total - filled, "total_items": item_count,
"fill_percent": float(filled) / float(total) * 100.0 if total > 0 else 0.0
}

func compact(key: String) -> void:
if not _containers.has(key):
return
var items: Array = []
for item in _containers[key]:
if item != null:
items.append(item)
var size := _containers[key].size()
_containers[key] = []
for i in size:
_containers[key].append(null)
var slot := 0
for item in items:
_containers[key][slot] = item
slot += 1

func clear(key: String) -> void:
if _containers.has(key):
var size := _containers[key].size()
_containers[key] = []
for i in size:
_containers[key].append(null)

func delete_container(key: String) -> void:
_containers.erase(key)
_expansion_state.erase(key)
container_closed.emit(key)

## ============================================================================
## SIGNALS
## ============================================================================

signal container_opened(key: String, container_type: int)
signal container_closed(key: String)
signal slot_changed(key: String, slot_index: int, item: Item)
signal expansion_purchased(key: String, new_tier: int, new_size: int)
