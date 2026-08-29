## GatewayData - Teleportation gateway definition
## Defines teleportation points between zones
class_name GatewayData
extends Resource

## Gateway Types
enum GatewayType {
	ANKH,           # Respawn point (bound)
	WAYPOINT,       # Player-unlocked fast travel
	DUNGEON_ENTRY,  # Dungeon entrance portal
	TOWN_PORTAL,    # Wizard tower portal
	SHIP,           # Sea voyage
	CUSTOM,         # Quest/event gateway
}

## Activation Requirements
enum ActivationRequirement {
	NONE,           # Always accessible
	QUEST_COMPLETE, # Must complete quest
	LEVEL_REACH,    # Must reach level
	FACTION_RANK,   # Must have faction rank
	ITEM_HOLD,      # Must have item
	ZONE_VISITED,   # Must have visited zone
	GUILD_RANK,     # Must have guild rank
	DAILY,          # Once per day
}

@export var id: String = ""
@export var display_name: String = "Gateway"
@export var description: String = ""

# Gateway classification
@export var gateway_type: GatewayType = GatewayType.WAYPOINT

# Location
@export var source_zone_id: String = ""           # Zone this gateway is in
@export var source_position: Vector3 = Vector3.ZERO  # Position in source zone
@export var source_rotation: float = 0.0        # Y rotation

@export var destination_zone_id: String = ""     # Zone to teleport to
@export var destination_position: Vector3 = Vector3.ZERO  # Position in dest zone
@export var destination_rotation: float = 0.0    # Y rotation at destination

# Visual/Model
@export var model_path: String = ""
@export var particle_effect: String = ""          # Portal effect
@export var sound_idle: String = ""              # Ambient sound
@export var sound_activate: String = ""          # Teleport sound
@export var icon_path: String = ""

# Access requirements
@export var activation_requirement: ActivationRequirement = ActivationRequirement.NONE
@export var requirement_value: String = ""        # Quest ID, level, faction name, etc.
@export var requirement_value_int: int = 0       # Level needed, faction rank needed

# Cost
@export var gold_cost: int = 0                  # Gold to use
@export var requires_key: bool = false           # Needs a key item
@export var key_item_id: String = ""             # Item ID of key

# Restrictions
@export var min_level: int = 1
@export var max_level: int = 100
@export var pvp_zone: bool = false              # Destination is PvP zone
@export var combat_lockout: bool = true          # Can't use while in combat
@export var party_required: bool = false         # Must be in party
@export var party_leader_only: bool = false      # Only party leader can activate

# Cooldown & Limits
@export var cooldown_seconds: float = 0.0       # Personal cooldown
@export var daily_limit: int = 0                 # 0 = unlimited
@export var usage_limit: int = 0                # 0 = unlimited (one-time use)

# Quest integration
@export var related_quest_id: String = ""       # Quest that unlocks this gateway
@export var completes_quest_id: String = ""     # Using this completes a quest

# Dungeon specific
@export var dungeon_id: String = ""              # For dungeon entries
@export var difficulty: int = 1                 # Dungeon difficulty level
@export var reset_on_death: bool = true          # Dungeon resets on death
@export var required_party_size: int = 0         # 0 = soloable

# Zone connection type
@export var is_two_way: bool = true             # Can return via same gateway
@export var reverse_gateway_id: String = ""      # ID of reverse gateway (if one-way)

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Check if player meets requirements
func check_requirements(player: SynmergiaEntity) -> Dictionary:
	# Level check
	if player.level < min_level:
		return {
			"can_use": false,
			"reason": "Level %d required" % min_level
		}
	
	if player.level > max_level:
		return {
			"can_use": false,
			"reason": "Level %d or below only" % max_level
		}
	
	# Combat check
	if combat_lockout and player.is_in_combat:
		return {
			"can_use": false,
			"reason": "Cannot use while in combat"
		}
	
	# Party check
	if party_required:
		if not player.party_id or player.party_id == "":
			return {
				"can_use": false,
				"reason": "Must be in a party"
			}
		if party_leader_only and player.party_role != "leader":
			return {
				"can_use": false,
				"reason": "Only party leader can use"
			}
	
	# Gold check
	if gold_cost > 0:
		var inventory = player.inventory_component
		if inventory and inventory.get_gold() < gold_cost:
			return {
				"can_use": false,
				"reason": "Need %d gold" % gold_cost
			}
	
	# Key item check
	if requires_key and key_item_id != "":
		var inventory = player.inventory_component
		if not inventory or not inventory.has_item(key_item_id):
			return {
				"can_use": false,
				"reason": "Requires key item"
			}
	
	return {"can_use": true}

## Get activation summary for UI
func get_activation_summary() -> Dictionary:
	var summary := {
		"type": GatewayType.keys()[gateway_type],
		"destination_zone": destination_zone_id,
		"gold_cost": gold_cost,
		"has_key": requires_key
	}
	
	match activation_requirement:
		ActivationRequirement.LEVEL_REACH:
			summary["requirement"] = "Reach level %d" % requirement_value_int
		ActivationRequirement.QUEST_COMPLETE:
			summary["requirement"] = "Complete quest: %s" % requirement_value
		ActivationRequirement.FACTION_RANK:
			summary["requirement"] = "%s rank %d" % [requirement_value, requirement_value_int]
	
	return summary
