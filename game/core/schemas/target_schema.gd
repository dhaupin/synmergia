## TargetSchema - Targeting configuration for entities
## Data-driven targeting settings via .tres files
## 
## Usage:
##   var schema = TargetingManager.get_schema("player")
##   var color = schema.highlight_color
extends Resource
class_name TargetSchema
const Entity = preload("res://core/entities/entity.gd")


## ============================================================================
## ENUMS
## ============================================================================

## Entity types that can be targeted
## NOTE: These MUST match Entity.EntityType values (core/entities/entity.gd)
enum EntityType {
	NONE = 0,
	PLAYER = 1,       # Player characters
	ENEMY = 2,        # Hostile NPCs/monsters
	NPC = 4,          # Neutral interactive NPCs
	DESTRUCTIBLE = 8, # Breakable objects
	OBJECT = 16,      # Interactable world objects
	TELEPORT = 32,    # Teleporters/portals
	LOOT = 64,        # Lootable items/dropped objects
	ALL = 0xFFFFFFFF  # Mask for all types
}

## How the target is selected/interacted with
enum InteractionMode {
	HOVER = 0,      # Target on mouse hover (show interact hint)
	CLICK = 1,       # Target on click/tap
	PROXIMITY = 2   # Auto-target when in range
}

## Selection mode for targeting
enum SelectionMode {
	SINGLE = 0,     # One target at a time
	MULTI = 1,       # Multiple targets (shift+click)
	RADIAL = 2      # Select all in radius
}

## ============================================================================
## IDENTIFICATION
## ============================================================================

## Unique identifier (matches filename without extension)
@export var id: String = ""

## Display name for UI
@export var display_name: String = "Target"

## Description for tooltips
@export var description: String = ""

## Which entity type this schema applies to
@export var entity_type: EntityType = EntityType.NPC

## ============================================================================
## TARGETING BEHAVIOR
## ============================================================================

## How to interact with this target type
@export var interaction_mode: InteractionMode = InteractionMode.CLICK

## Selection mode
@export var selection_mode: SelectionMode = SelectionMode.SINGLE

## Maximum number of targets in multi selection
@export var max_selection: int = 1

## Range for proximity selection (units)
@export var selection_range: float = 10.0

## Can target self (for buffs, etc.)
@export var can_target_self: bool = false

## Can target while dead
@export var can_target_while_dead: bool = false

## Requires line of sight to target
@export var requires_line_of_sight: bool = true

## ============================================================================
## VISUAL CONFIGURATION
## ============================================================================

## 3D highlight color when targeted
@export var highlight_color: Color = Color(1.0, 0.8, 0.0, 1.0)

## 3D highlight size multiplier
@export var highlight_size: float = 1.0

## Highlight animation speed
@export var highlight_speed: float = 1.0

## Icon/marker for minimap
@export var minimap_icon: String = ""

## ============================================================================
## ACTIONS
## ============================================================================

## Available actions for this target type
## References action IDs defined in TargetingManager
@export var available_actions: Array[String] = []

## Default action when interacting (auto-execute)
@export var default_action: String = ""

## ============================================================================
## TOOLTIP CONFIGURATION
## ============================================================================

## Custom tooltip scene path (empty = use default)
@export var tooltip_scene: String = ""

## Show health bar in tooltip
@export var show_health: bool = true

## Show level in tooltip
@export var show_level: bool = true

## Show status effects in tooltip
@export var show_status: bool = true

## ============================================================================
## TARGETING REQUIREMENTS
## ============================================================================

## Minimum level to target this entity
@export var min_targeter_level: int = 1

## Maximum level difference to target (0 = no limit)
@export var max_level_difference: int = 0

## Faction requirement to target (empty = any)
@export var required_faction: String = ""

## ============================================================================
## CACHE (runtime, not exported)
## ============================================================================

var _cached: bool = false

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## ============================================================================
## UTILITY METHODS
## ============================================================================

## Check if this action is available for this target type
func has_action(action_id: String) -> bool:
	return available_actions.has(action_id)

## Get all available actions
func get_actions() -> Array[String]:
	return available_actions.duplicate()

## Check if targeter meets requirements
func can_be_targeted_by(targeter_level: int, targeter_faction: String = "") -> bool:
	# Level check
	if targeter_level < min_targeter_level:
		return false
	
	# Level difference check
	if max_level_difference > 0:
		# This would need the target's level - handled in TargetingManager
		pass
	
	# Faction check
	if required_faction != "" and targeter_faction != required_faction:
		return false
	
	return true

## Get highlight color as hex string (for UI)
func get_highlight_hex() -> String:
	return "#%02X%02X%02X" % [
		int(highlight_color.r * 255),
		int(highlight_color.g * 255),
		int(highlight_color.b * 255)
	]

## Get info dictionary for tooltip/UI
func get_info() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"description": description,
		"entity_type": EntityType.keys()[entity_type],
		"interaction_mode": InteractionMode.keys()[interaction_mode],
		"selection_mode": SelectionMode.keys()[selection_mode],
		"highlight_color": get_highlight_hex(),
		"actions": available_actions,
		"show_health": show_health,
		"show_level": show_level
	}
