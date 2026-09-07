## ContainerConfigData - Data-driven container configuration
## All container types and expansion tiers defined here
## 
## Usage:
##   var data := ContainerConfigData.load()
##   var config = data.get_container(ContainerType.INVENTORY)

extends Resource
class_name ContainerConfigData

## Container types (matches ContainerSchema.ContainerType)
enum ContainerType {
	INVENTORY = 0,
	BANK = 1,
	GUILD_VAULT = 2,
	HOUSE_STORAGE = 3,
	MOUNT_INVENTORY = 4,
	EQUIPMENT_SLOTS = 5,
	LOOT = 6,
	SHOP = 7,
	TRADE = 8,
}

## Default expansion tier costs (per tier, escalating)
const DEFAULT_EXPANSION_COSTS: Array = [
	1000,    # Tier 1: +12 slots
	2500,    # Tier 2: +24 total
	5000,    # Tier 3: +36 total
	10000,   # Tier 4: +48 total
	25000,   # Tier 5: +60 total
	50000,   # Tier 6: +72 total
	100000,  # Tier 7: +84 total
	250000,  # Tier 8: +96 total
	500000,  # Tier 9: +108 total
	1000000, # Tier 10: +120 total
]

## Default slots per expansion tier
const SLOTS_PER_TIER: int = 12

## Container configurations (loaded from data or defaults)
var containers: Dictionary = {
	ContainerType.INVENTORY: {
		"name": "Inventory",
		"base_slots": 24,
		"max_slots": 120,
		"max_tier": 8,
		"allow_stack": true,
		"max_stack": 9999,
		"grid_cols": 6,
		"grid_rows": 4,
		"sort_order": 0,
		"icon": "res://ui/icons/inventory.png",
		"expandable": true,
		"tradable": true,
		"requires_permission": false,
		"currency": "gold"
	},
	ContainerType.BANK: {
		"name": "Bank",
		"base_slots": 100,
		"max_slots": 400,
		"max_tier": 25,
		"allow_stack": true,
		"max_stack": 9999,
		"grid_cols": 10,
		"grid_rows": 10,
		"sort_order": 1,
		"icon": "res://ui/icons/bank.png",
		"expandable": true,
		"tradable": false,
		"requires_permission": false,
		"currency": "gold"
	},
	ContainerType.GUILD_VAULT: {
		"name": "Guild Vault",
		"base_slots": 200,
		"max_slots": 800,
		"max_tier": 50,
		"allow_stack": true,
		"max_stack": 9999,
		"grid_cols": 10,
		"grid_rows": 20,
		"sort_order": 2,
		"icon": "res://ui/icons/guild_vault.png",
		"expandable": true,
		"tradable": false,
		"requires_permission": true,
		"currency": "guild_funds",
		"permission_levels": ["view", "deposit", "withdraw", "manage"]
	},
	ContainerType.HOUSE_STORAGE: {
		"name": "House Storage",
		"base_slots": 50,
		"max_slots": 200,
		"max_tier": 12,
		"allow_stack": true,
		"max_stack": 9999,
		"grid_cols": 10,
		"grid_rows": 5,
		"sort_order": 3,
		"icon": "res://ui/icons/house_storage.png",
		"expandable": true,
		"tradable": false,
		"requires_permission": false,
		"owner_only": true,
		"currency": "gold"
	},
	ContainerType.MOUNT_INVENTORY: {
		"name": "Saddlebags",
		"base_slots": 12,
		"max_slots": 36,
		"max_tier": 2,
		"allow_stack": true,
		"max_stack": 100,
		"grid_cols": 6,
		"grid_rows": 2,
		"sort_order": 4,
		"icon": "res://ui/icons/mount_inventory.png",
		"expandable": true,
		"tradable": false,
		"requires_permission": false,
		"currency": "gold"
	},
	ContainerType.EQUIPMENT_SLOTS: {
		"name": "Equipment",
		"base_slots": 16,
		"max_slots": 16,
		"max_tier": 0,
		"allow_stack": false,
		"max_stack": 1,
		"grid_cols": 4,
		"grid_rows": 4,
		"sort_order": 5,
		"icon": "res://ui/icons/equipment.png",
		"expandable": false,
		"tradable": false,
		"requires_permission": false,
		"currency": ""
	},
	ContainerType.LOOT: {
		"name": "Loot",
		"base_slots": 24,
		"max_slots": 24,
		"max_tier": 0,
		"allow_stack": false,
		"max_stack": 1,
		"grid_cols": 6,
		"grid_rows": 4,
		"sort_order": 10,
		"icon": "res://ui/icons/loot.png",
		"expandable": false,
		"tradable": false,
		"requires_permission": false,
		"temporary": true,
		"auto_close_distance": 10.0,
		"currency": ""
	},
	ContainerType.SHOP: {
		"name": "Shop",
		"base_slots": 0,
		"max_slots": 0,
		"max_tier": 0,
		"allow_stack": false,
		"max_stack": 1,
		"grid_cols": 6,
		"grid_rows": 0,
		"sort_order": 20,
		"icon": "res://ui/icons/shop.png",
		"expandable": false,
		"tradable": false,
		"requires_permission": false,
		"is_vendor": true,
		"currency": ""
	},
	ContainerType.TRADE: {
		"name": "Trade",
		"base_slots": 12,
		"max_slots": 12,
		"max_tier": 0,
		"allow_stack": true,
		"max_stack": 9999,
		"grid_cols": 4,
		"grid_rows": 3,
		"sort_order": 15,
		"icon": "res://ui/icons/trade.png",
		"expandable": false,
		"tradable": false,
		"requires_permission": false,
		"two_sided": true,
		"currency": ""
	},
}

## ============================================================================
## STATIC ACCESSORS
## ============================================================================

static func load() -> ContainerConfigData:
	# Try to load from .tres file first
	var path := "res://data/containers/container_configs.tres"
	if ResourceLoader.exists(path):
		return load(path)
	# Fallback to hardcoded defaults
	return ContainerConfigData.new()

## Get container config by type
static func get_container(container_type: int) -> Dictionary:
	var data := load()
	return data.containers.get(container_type, {})

## Get expansion cost for tier
static func get_expansion_cost(container_type: int, tier: int) -> int:
	if tier < 0 or tier >= DEFAULT_EXPANSION_COSTS.size():
		return 0
	return DEFAULT_EXPANSION_COSTS[tier]

## Get slots for tier
static func get_slots_for_tier(container_type: int, tier: int) -> int:
	var config := get_container(container_type)
	var base := config.get("base_slots", 0)
	return base + (tier * SLOTS_PER_TIER)

## Check if container is expandable
static func is_expandable(container_type: int) -> bool:
	var config := get_container(container_type)
	return config.get("expandable", false)

## Check if container allows stacking
static func allows_stacking(container_type: int) -> bool:
	var config := get_container(container_type)
	return config.get("allow_stack", false)

## Get max stack size
static func get_max_stack(container_type: int) -> int:
	var config := get_container(container_type)
	return config.get("max_stack", 1)

## ============================================================================
## INSTANCE METHODS
## ============================================================================

## Get all container types
func get_all_types() -> Array:
	return containers.keys()

## Get containers sorted by sort_order
func get_sorted_containers() -> Array:
	var sorted: Array = []
	for ct in containers:
		sorted.append({"type": ct, "config": containers[ct]})
	sorted.sort_custom(func(a, b): 
		return a["config"].get("sort_order", 99) < b["config"].get("sort_order", 99)
	)
	return sorted

## Validate container type
func is_valid_type(container_type: int) -> bool:
	return containers.has(container_type)

## Get display name
func get_display_name(container_type: int) -> String:
	var config := containers.get(container_type, {})
	return config.get("name", "Unknown")
