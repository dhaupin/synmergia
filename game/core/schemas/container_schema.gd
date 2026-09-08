## ContainerSchema - Slot container configuration
## Defines base slots, expansion tiers, and constraints for all container types
##
## Usage:
##   var schema := ContainerSchema.new()
##   schema.init_inventory(player_data)
##   var slots = schema.get_total_slots()

extends Resource
class_name ContainerSchema

## Container types
enum ContainerType {
	INVENTORY,
	BANK,
	GUILD_VAULT,
	HOUSE_STORAGE,
	MOUNT_INVENTORY,
	EQUIPMENT_SLOTS
}

## Expansion tier: [slots_added, currency_type, base_cost]
## Cost increases per tier
const EXPANSION_COSTS: Array = [
	{"slots": 12, "currency": "gold", "base_cost": 1000},
	{"slots": 12, "currency": "gold", "base_cost": 2500},
	{"slots": 12, "currency": "gold", "base_cost": 5000},
	{"slots": 12, "currency": "gold", "base_cost": 10000},
	{"slots": 12, "currency": "gold", "base_cost": 25000},
	{"slots": 12, "currency": "gold", "base_cost": 50000},
	{"slots": 12, "currency": "gold", "base_cost": 100000},
	{"slots": 12, "currency": "gold", "base_cost": 250000},
	{"slots": 12, "currency": "gold", "base_cost": 500000},
	{"slots": 12, "currency": "gold", "base_cost": 1000000},
]

## Container base configurations
const BASE_CONFIG: Dictionary = {
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
		"icon": "res://ui/icons/inventory.png"
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
		"icon": "res://ui/icons/bank.png"
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
		"icon": "res://ui/icons/guild_vault.png"
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
		"icon": "res://ui/icons/house_storage.png"
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
		"icon": "res://ui/icons/mount_inventory.png"
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
		"icon": "res://ui/icons/equipment.png"
	}
}

## ============================================================================
## INSTANCE DATA
## ============================================================================

## Current container type
var container_type: ContainerType = ContainerType.INVENTORY

## Expansion tier purchased
var expansion_tier: int = 0

## Instance ID (for multi-instance containers like houses)
var instance_id: String = ""

## ============================================================================
## INITIALIZATION
## ============================================================================

## Initialize from container type
func init(container_type: ContainerType, expansion_tier: int = 0, instance_id: String = "") -> void:
	self.container_type = container_type
	self.expansion_tier = expansion_tier
	self.instance_id = instance_id

## Initialize from player data (for inventory)
static func from_player_data(data: Dictionary) -> ContainerSchema:
	var schema := ContainerSchema.new()
	schema.init(ContainerType.INVENTORY, data.get("inventory_expansion_tier", 0))
	return schema

## Initialize from guild data
static func from_guild_data(data: Dictionary, guild_id: String) -> ContainerSchema:
	var schema := ContainerSchema.new()
	schema.init(ContainerType.GUILD_VAULT, data.get("vault_expansion_tier", 0), guild_id)
	return schema

## ============================================================================
## CONFIGURATION ACCESS
## ============================================================================

## Get base configuration for container type
static func get_base_config(container_type: ContainerType) -> Dictionary:
	return BASE_CONFIG.get(container_type, {})

## Get current configuration
func get_config() -> Dictionary:
	return BASE_CONFIG.get(container_type, {})

## Get base slots
func get_base_slots() -> int:
	return get_config().get("base_slots", 0)

## Get maximum slots
func get_max_slots() -> int:
	return get_config().get("max_slots", 0)

## Get total slots (base + expansion)
func get_total_slots() -> int:
	var base = get_base_slots()
	for i in range(expansion_tier):
		if i < EXPANSION_COSTS.size():
			base += EXPANSION_COSTS[i]["slots"]
	return mini(base, get_max_slots())

## Get remaining expandable slots
func get_remaining_expansion() -> int:
	return get_max_slots() - get_total_slots()

## Get grid dimensions
func get_grid_cols() -> int:
	return get_config().get("grid_cols", 6)

func get_grid_rows() -> int:
	var total = get_total_slots()
	var cols = get_grid_cols()
	return ceili(float(total) / float(cols))

## ============================================================================
## EXPANSION
## ============================================================================

## Get expansion tier info
func get_expansion_info(tier: int) -> Dictionary:
	if tier >= EXPANSION_COSTS.size():
		return {}
	return EXPANSION_COSTS[tier]

## Get next expansion cost
func get_next_expansion_cost() -> Dictionary:
	return get_expansion_info(expansion_tier)

## Get expansion tier count
func get_max_expansion_tier() -> int:
	return get_config().get("max_tier", 0)

## Check if can expand
func can_expand() -> bool:
	return expansion_tier < get_max_expansion_tier()

## Check if stacking allowed
func allows_stacking() -> bool:
	return get_config().get("allow_stack", false)

## Get max stack size
func get_max_stack() -> int:
	return get_config().get("max_stack", 1)

## ============================================================================
## SERIALIZATION
## ============================================================================

## Serialize to dictionary
func to_dict() -> Dictionary:
	return {
		"container_type": container_type,
		"expansion_tier": expansion_tier,
		"instance_id": instance_id
	}

## Deserialize from dictionary
static func from_dict(data: Dictionary) -> ContainerSchema:
	var schema := ContainerSchema.new()
	schema.container_type = data.get("container_type", ContainerType.INVENTORY)
	schema.expansion_tier = data.get("expansion_tier", 0)
	schema.instance_id = data.get("instance_id", "")
	return schema

## ============================================================================
## UI HELPERS
## ============================================================================

## Get display name
func get_display_name() -> String:
	return get_config().get("name", "Container")

## Get icon path
func get_icon_path() -> String:
	return get_config().get("icon", "")

## Get sort order
func get_sort_order() -> int:
	return get_config().get("sort_order", 99)
