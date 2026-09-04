## NPCData - NPC template definition
## Base schema for NPC templates (vendors, quest givers, etc.)
extends Resource
class_name NPCData

## NPC Types
enum NPCType {
	GENERIC,       # Generic NPC, no special behavior
	VENDOR,        # Sells items
	BLACKSMITH,    # Repairs equipment
	QUEST_GIVER,   # Has quests
	GUARD,         # Protective NPC
	INNKEEPER,     # Rest/respawn point
	MERCHANT,      # General merchant
	SPECIALIST,    # Skill trainer, etc.
	SKILL_ACADEMY # Skill book vendor + upgrades + respec
}

## Location Type (affects pricing)
enum LocationType {
	TOWN,      # Standard pricing
	OUTPOST,   # Slightly more expensive
	VILLAGE,   # Cheaper (rural)
	DUNGEON,   # Emergency repairs (expensive)
	CAPITAL    # Premium pricing
}

@export var id: String = ""
@export var display_name: String = "NPC"
@export var description: String = ""

# NPC Classification
@export var npc_type: NPCType = NPCType.GENERIC
@export var level: int = 1
@export var faction: String = "friendly"

# Visual
@export var model_path: String = ""
@export var icon_path: String = ""
@export var scale: float = 1.0

# Dialog
@export var greeting: String = "Hello there."
@export var farewell: String = "Take care."
@export var shop_title: String = ""  # For vendors

# Location-based behavior
@export var location_type: LocationType = LocationType.TOWN

# Vendor settings
@export var buy_multiplier: float = 0.5    # What % of value we buy items for
@export var sell_multiplier: float = 1.0    # What % of value we sell items for
@export var buy_categories: Array[String] = []  # Item categories we buy
@export var sell_categories: Array[String] = []  # Item categories we sell

# Blacksmith settings (used if npc_type == BLACKSMITH)
@export var base_repair_cost_multiplier: float = 1.0
@export var offers_bulk_discount: bool = true
@export var bulk_discount_percent: float = 10.0
@export var bulk_discount_threshold: int = 5

# Stats (for combat-capable NPCs like guards)
@export var health: int = 100
@export var strength: int = 10
@export var agility: int = 10
@export var intelligence: int = 10
@export var vitality: int = 10

# Combat settings
@export var attack_power: int = 10
@export var armor: int = 5
@export var is_aggressive: bool = false  # Only guards should be aggressive

# Skills/Services offered
@export var skills: Array[String] = []  # Skill IDs this NPC can teach
@export var services: Array[String] = []  # Service IDs (repair, respec, etc.)

# Position in world (relative to spawn point)
@export var spawn_offset: Vector3 = Vector3.ZERO
@export var spawn_rotation: float = 0.0  # Y rotation in degrees

## Includes — what this NPC provides when the player interacts.
## Each entry: {type: String, ref_id: String}
## type "offering" → data/npc_offerings/<ref_id>.tres
## Future types: "dialogue", "quest", etc.
@export var includes: Array[Dictionary] = []

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Get location cost modifier
func get_location_cost_modifier() -> float:
	match location_type:
		LocationType.TOWN:
			return 1.0
		LocationType.OUTPOST:
			return 1.25
		LocationType.VILLAGE:
			return 0.9
		LocationType.DUNGEON:
			return 2.0
		LocationType.CAPITAL:
			return 1.5
	return 1.0

## Get total cost modifier for pricing
func get_total_cost_modifier() -> float:
	return base_repair_cost_multiplier * get_location_cost_modifier()
