## DwellingData - Housing/dwelling item definition
## Defines placeable items for player housing
extends Resource
class_name DwellingData

enum DwellingCategory {
	FURNITURE,      # Tables, chairs, beds, benches
	DECORATION,     # Paintings, statues, plants, rugs
	LIGHTING,       # Torches, candles, chandeliers, lanterns
	STORAGE,        # Chests, wardrobes, barrels, shelves
	FUNCTIONAL,     # Crafting stations, forges, anvil, cooking pot
	STRUCTURAL,      # Walls, doors, windows, stairs, platforms
	OUTDOOR,        # Garden items, fountains, fences, trees
	TROPHY,         # Display cases, trophy walls, award shelves
	TECHNICAL,      # Teleporter, storage access, mailbox
	MISC            # Everything else
}

enum PlacementSurface {
	ANY,
	FLOOR,
	WALL,
	CEILING,
	OUTDOOR_GROUND
}

enum OwnershipModel {
	PERSONAL,      # Owned by one player
	GUILD,         # Guild owned
	PUBLIC,        # Anyone can interact
	INSTANCE       # Instance-specific (dungeon loot)
}

@export var id: String = ""
@export var display_name: String = "Dwelling Item"
@export var description: String = ""

# Category
@export var dwelling_category: DwellingCategory = DwellingCategory.MISC
@export var icon_path: String = ""

# Visual
@export var model_path: String = ""
@export var thumbnail_path: String = ""
@export var color: Color = Color.WHITE
@export var is_animated: bool = false
@export var animation_path: String = ""

# Size (in housing grid units, 1 unit = 1 meter typically)
@export var grid_size: Vector3 = Vector3(1, 1, 1)

# Placement
@export var placement_surface: PlacementSurface = PlacementSurface.FLOOR
@export var can_rotate: bool = true
@export var rotation_snap: int = 90  # Degrees, 90 = snap to cardinals
@export var can_stack: bool = false
@export var max_stack: int = 1

# Ownership
@export var ownership: OwnershipModel = OwnershipModel.PERSONAL
@export var required_guild_rank: int = 0  # For guild items

# Interaction
@export var is_interactable: bool = false
@export var interaction_type: String = ""  # "open_chest", "sit", "gather", etc.
@export var interaction_radius: float = 1.0
@export var cooldown_seconds: float = 0.0

# Functional (for crafting stations, etc.)
@export var provides_function: String = ""  # "crafting_alchemy", "storage_100", etc.
@export var function_capacity: int = 0  # Storage slots, crafting slots, etc.

# Economics
@export var tax_modifier: float = 0.0  # Extra tax for this item
@export var maintenance_cost: float = 0.0  # Gold per day/week
@export var decay_time_days: float = 0.0  # 0 = never decays

# Permissions
@export var allow_guild_access: bool = false
@export var allow_friends_access: bool = false
@export var allow_public_view: bool = false  # Others can see but not interact
@export var allowed_zones: Array[String] = []  # Empty = all housing zones

# Dye channels (for customizable items)
@export var dyeable: bool = false
@export var dye_channels: int = 1  # Number of color channels that can be dyed
@export var default_colors: Array[Color] = [Color.WHITE]

# Dismantle/reclaim
@export var dismantle_returns: Array[Dictionary] = []
# Example: [{"type": "resource", "id": "wood", "amount": 5}]

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Check if this item can be placed in a zone
func can_place_in_zone(zone_id: String) -> bool:
	if allowed_zones.is_empty():
		return true
	return allowed_zones.has(zone_id)

## Get grid footprint (for UI placement preview)
func get_footprint() -> Vector2:
	return Vector2(grid_size.x, grid_size.z)

## Check if item has a specific function
func has_function(function: String) -> bool:
	return provides_function == function

## Get interaction info for UI
func get_interaction_info() -> Dictionary:
	if not is_interactable:
		return {}
	return {
		"type": interaction_type,
		"radius": interaction_radius,
		"cooldown": cooldown_seconds,
		"function": provides_function
	}

## Get display info for UI
func get_info() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"description": description,
		"category": DwellingCategory.keys()[dwelling_category],
		"grid_size": grid_size,
		"can_rotate": can_rotate,
		"dyeable": dyeable,
		"interactable": is_interactable,
		"function": provides_function
	}
