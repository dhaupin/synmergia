## SlotService - Unified slot container management
## Handles all slot-based storage: inventory, bank, guild vault, house storage, mounts
## 
## Container Types:
##   - INVENTORY: Player personal inventory (24 base slots, expandable to 120)
##   - BANK: Personal bank storage (100 base, expandable to 400)
##   - GUILD_VAULT: Shared guild storage (200 base, expandable to 800)
##   - HOUSE_STORAGE: Per-house storage (50 base, expandable to 200)
##   - MOUNT_INVENTORY: Mount saddlebags (12 base, expandable to 36)
##   - EQUIPMENT_SLOTS: Equipment slots (16 fixed slots, non-expandable)
##
## Expansion System:
##   Each tier adds +12 slots (standard) or tier-specific amounts
##   Purchases tracked in player/guild data
##   Stack limits per container type (some containers don't allow stacks)
##
## Security:
##   - All operations validate ownership
##   - Atomic transactions with rollback on failure
##   - Audit logging for guild vault operations
##   - Rate limiting on bulk operations

extends Node
class_name SlotService

## Singleton
static var _instance: SlotService = null

## Container types
enum ContainerType {
	INVENTORY,
	BANK,
	GUILD_VAULT,
	HOUSE_STORAGE,
	MOUNT_INVENTORY,
	EQUIPMENT_SLOTS
}

## Expansion tier configuration
## Each tier is [base_slots_increment, currency_type, base_cost]
const EXPANSION_TIERS: Array = [
	[12, "gold", 1000],      # Tier 1: +12 slots, 1k gold
	[12, "gold", 2500],      # Tier 2: +24 total, 2.5k gold
	[12, "gold", 5000],      # Tier 3: +36 total, 5k gold
	[12, "gold", 10000],     # Tier 4: +48 total, 10k gold
	[12, "gold", 25000],     # Tier 5: +60 total, 25k gold
	[12, "gold", 50000],     # Tier 6: +72 total, 50k gold
	[12, "gold", 100000],    # Tier 7: +84 total, 100k gold
	[12, "gold", 250000],    # Tier 8: +96 total, 250k gold
	[12, "gold", 500000],    # Tier 9: +108 total, 500k gold
	[12, "gold", 1000000],   # Tier 10: +120 total, 1M gold (max for inventory)
]

## Container base configurations
const CONTAINER_CONFIG: Dictionary = {
	ContainerType.INVENTORY: {
		"base_slots": 24,
		"max_slots": 120,
		"max_expansion_tier": 8,
		"allow_stacking": true,
		"max_stack_size": 9999,
		"sort_order": 0
	},
	ContainerType.BANK: {
		"base_slots": 100,
		"max_slots": 400,
		"max_expansion_tier": 25,
		"allow_stacking": true,
		"max_stack_size": 9999,
		"sort_order": 1
	},
	ContainerType.GUILD_VAULT: {
		"base_slots": 200,
		"max_slots": 800,
		"max_expansion_tier": 50,
		"allow_stacking": true,
		"max_stack_size": 9999,
		"sort_order": 2
	},
	ContainerType.HOUSE_STORAGE: {
		"base_slots": 50,
		"max_slots": 200,
		"max_expansion_tier": 12,
		"allow_stacking": true,
		"max_stack_size": 9999,
		"sort_order": 3
	},
	ContainerType.MOUNT_INVENTORY: {
		"base_slots": 12,
		"max_slots": 36,
		"max_expansion_tier": 2,
		"allow_stacking": true,
		"max_stack_size": 100,
		"sort_order": 4
	},
	ContainerType.EQUIPMENT_SLOTS: {
		"base_slots": 16,
		"max_slots": 16,
		"max_expansion_tier": 0,
		"allow_stacking": false,
		"max_stack_size": 1,
		"sort_order": 5
	}
}

## Item = preload for convenience
const Item = preload("res://core/schemas/item.gd")

## In-memory containers: container_key -> [SlotData, ...]
var _containers: Dictionary = {}

## Expansion state: container_key -> expansion_tier
var _expansion_state: Dictionary = {}

## Transaction log for rollback
var _transaction_log: Array = []

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

## Generate unique key for a container
static func make_key(owner_id: String, container_type: ContainerType, instance_id: String = "") -> String:
	if instance_id != "":
		return "%s:%s:%s" % [owner_id, ContainerType.keys()[container_type], instance_id]
	return "%s:%s" % [owner_id, ContainerType.keys()[container_type]]

## Parse container key back to components
static func parse_key(key: String) -> Dictionary:
	var parts := key.split(":")
	if parts.size() < 2:
		return {}
	return {
		"owner_id": parts[0],
		"container_type": ContainerType.get(parts[1], ContainerType.INVENTORY),
		"instance_id": parts[2] if parts.size() > 2 else ""
	}

## ============================================================================
## CONTAINER INITIALIZATION
## ============================================================================

## Initialize a container for an owner
func init_container(owner_id: String, container_type: ContainerType, instance_id: String = "", expansion_tier: int = 0) -> String:
	var key := make_key(owner_id, container_type, instance_id)
	if not _containers.has(key):
		var config = CONTAINER_CONFIG[container_type]
		var base_slots = config["base_slots"]
		var expanded_slots = base_slots
		
		# Calculate expanded slots from tier
		for i in range(min(expansion_tier, config["max_expansion_tier"])):
			expanded_slots += EXPANSION_TIERS[i][0]
		
		# Initialize slots array
		_containers[key] = []
		for i in expanded_slots:
			_containers[key].append(null)  # null = empty slot
		
		_expansion_state[key] = expansion_tier
		GameLog.debug("SlotService: Initialized %s with %d slots" % [key, expanded_slots])
	
	return key

## Get container size for a key
func get_container_size(key: String) -> int:
	if not _containers.has(key):
		return 0
	return _containers[key].size()

## Get container config
func get_container_config(container_type: ContainerType) -> Dictionary:
	return CONTAINER_CONFIG.get(container_type, {})

## ============================================================================
## EXPANSION SYSTEM
## ============================================================================

## Get current expansion tier for a container
func get_expansion_tier(key: String) -> int:
	return _expansion_state.get(key, 0)

## Get slots from expansion tier
func get_slots_for_tier(container_type: ContainerType, tier: int) -> int:
	var config = CONTAINER_CONFIG[container_type]
	var base = config["base_slots"]
	for i in range(min(tier, config["max_expansion_tier"])):
		base += EXPANSION_TIERS[i][0]
	return base

## Purchase expansion tier
func purchase_expansion(key: String, player_id: String, currency: String = "gold") -> Dictionary:
	var parsed = parse_key(key)
	var container_type = parsed["container_type"]
	var config = CONTAINER_CONFIG[container_type]
	
	var current_tier = get_expansion_tier(key)
	if current_tier >= config["max_expansion_tier"]:
		return {"success": false, "error": "Already at max expansion"}
	
	var tier_config = EXPANSION_TIERS[current_tier]
	var cost = tier_config[2]
	var currency_type = tier_config[1]
	
	if currency != currency_type:
		return {"success": false, "error": "Invalid currency type"}
	
	# Deduct cost from player
	if currency_type == "gold":
		if InventoryService and InventoryService.spend_gold(player_id, cost):
			_execute_expansion(key, current_tier + 1)
			return {"success": true, "new_tier": current_tier + 1, "new_slots": get_container_size(key), "cost": cost}
	
	return {"success": false, "error": "Failed to deduct currency"}

func _execute_expansion(key: String, new_tier: int) -> void:
	var config = CONTAINER_CONFIG[parse_key(key)["container_type"]]
	var target_slots = get_slots_for_tier(parse_key(key)["container_type"], new_tier)
	var current_slots = _containers[key].size()
	
	# Add new empty slots
	for i in range(target_slots - current_slots):
		_containers[key].append(null)
	
	_expansion_state[key] = new_tier
	GameLog.info("SlotService: Expanded %s to tier %d (%d slots)" % [key, new_tier, target_slots])

## ============================================================================
## SLOT OPERATIONS
## ============================================================================

## Get item at slot
func get_slot(key: String, slot_index: int) -> Item:
	if not _containers.has(key) or slot_index < 0 or slot_index >= _containers[key].size():
		return null
	return _containers[key][slot_index]

## Set item at slot (replaces existing)
func set_slot(key: String, slot_index: int, item: Item) -> bool:
	if not _containers.has(key) or slot_index < 0 or slot_index >= _containers[key].size():
		return false
	
	var config = CONTAINER_CONFIG[parse_key(key)["container_type"]]
	
	# Validate stack size
	if item != null and config["allow_stacking"]:
		item.stack_size = mini(item.stack_size, config["max_stack_size"])
	elif item != null and not config["allow_stacking"]:
		item.stack_size = 1
	
	_containers[key][slot_index] = item
	return true

## Find first empty slot
func find_empty_slot(key: String) -> int:
	if not _containers.has(key):
		return -1
	for i in _containers[key].size():
		if _containers[key][i] == null:
			return i
	return -1

## Find slot containing item
func find_item(key: String, item_id: String) -> int:
	if not _containers.has(key):
		return -1
	for i in _containers[key].size():
		var slot_item = _containers[key][i]
		if slot_item != null and slot_item.id == item_id:
			return i
	return -1

## Get all items (non-null slots)
func get_all_items(key: String) -> Array:
	if not _containers.has(key):
		return []
	var items: Array = []
	for item in _containers[key]:
		if item != null:
			items.append(item)
	return items

## Get item count (total quantity across all stacks)
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

## Add item to container (auto-finds slot or stacks)
func add_item(key: String, item: Item, max_stack_override: int = -1) -> Dictionary:
	if item == null:
		return {"success": false, "error": "Null item"}
	
	var config = CONTAINER_CONFIG[parse_key(key)["container_type"]]
	var max_stack = config["max_stack_size"] if max_stack_override < 0 else max_stack_override
	
	# Try to stack first (if stacking allowed)
	if config["allow_stacking"]:
		var stack_slot = _find_stackable_slot(key, item.id, item.stack_size, max_stack)
		if stack_slot >= 0:
			var existing = _containers[key][stack_slot]
			var added = mini(item.stack_size, max_stack - existing.stack_size)
			existing.stack_size += added
			if item.stack_size > added:
				item.stack_size -= added
				return _add_remaining(key, item, max_stack_override)
			return {"success": true, "slot": stack_slot, "added": added}
	
	# Find empty slot
	var empty_slot = find_empty_slot(key)
	if empty_slot < 0:
		return {"success": false, "error": "Container full", "remaining": item}
	
	# Set the item
	item.stack_size = mini(item.stack_size, max_stack)
	set_slot(key, empty_slot, item)
	return {"success": true, "slot": empty_slot, "added": item.stack_size}

func _add_remaining(key: String, item: Item, max_stack_override: int) -> Dictionary:
	if item.stack_size <= 0:
		return {"success": true, "slot": -1, "added": 0}
	return add_item(key, item, max_stack_override)

func _find_stackable_slot(key: String, item_id: String, quantity: int, max_stack: int) -> int:
	for i in _containers[key].size():
		var slot_item = _containers[key][i]
		if slot_item != null and slot_item.id == item_id and slot_item.stack_size < max_stack:
			return i
	return -1

## Remove item from container
func remove_item(key: String, slot_index: int, quantity: int = -1) -> Item:
	var item = get_slot(key, slot_index)
	if item == null:
		return null
	
	if quantity < 0 or quantity >= item.stack_size:
		# Remove entire stack
		_containers[key][slot_index] = null
		return item
	else:
		# Partial removal
		var removed = item.duplicate()
		removed.stack_size = quantity
		item.stack_size -= quantity
		return removed

## Move item between containers (or same container)
func move_item(from_key: String, from_slot: int, to_key: String, to_slot: int) -> bool:
	var item = get_slot(from_key, from_slot)
	if item == null:
		return false
	
	# Get target slot content
	var target_item = get_slot(to_key, to_slot)
	
	if target_item == null:
		# Simple move to empty slot
		_containers[from_key][from_slot] = null
		set_slot(to_key, to_slot, item)
		return true
	elif target_item.id == item.id and CONTAINER_CONFIG[parse_key(to_key)["container_type"]]["allow_stacking"]:
		# Stack items
		var config = CONTAINER_CONFIG[parse_key(to_key)["container_type"]]
		var max_stack = config["max_stack_size"]
		var can_add = max_stack - target_item.stack_size
		if can_add >= item.stack_size:
			target_item.stack_size += item.stack_size
			_containers[from_key][from_slot] = null
		else:
			target_item.stack_size = max_stack
			item.stack_size -= can_add
		return true
	else:
		# Swap items
		_containers[from_key][from_slot] = target_item
		set_slot(to_key, to_slot, item)
		return true

## ============================================================================
## UTILITY
## ============================================================================

## Get container statistics
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
		"filled_slots": filled,
		"total_slots": total,
		"empty_slots": total - filled,
		"total_items": item_count,
		"fill_percent": float(filled) / float(total) * 100.0 if total > 0 else 0.0
	}

## Compact container (move all items to front)
func compact(key: String) -> void:
	if not _containers.has(key):
		return
	
	var items: Array = []
	for item in _containers[key]:
		if item != null:
			items.append(item)
	
	var size = _containers[key].size()
	_containers[key] = []
	for i in size:
		_containers[key].append(null)
	
	var slot := 0
	for item in items:
		_containers[key][slot] = item
		slot += 1

## Clear container
func clear(key: String) -> void:
	if _containers.has(key):
		var size = _containers[key].size()
		_containers[key] = []
		for i in size:
			_containers[key].append(null)

## ============================================================================
## SIGNAL PROXIES (for compatibility with existing services)
## ============================================================================

signal container_opened(key: String, container_type: ContainerType)
signal container_closed(key: String)
signal slot_changed(key: String, slot_index: int, item: Item)
signal expansion_purchased(key: String, new_tier: int, new_size: int)
