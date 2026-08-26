## EventData - Global event modifier definition
## Defines time-limited events that modify gameplay
class_name EventData
extends Resource

enum EventType {
	XP_BOOST,         # Double XP weekend
	GOLD_BOOST,       # Double gold from mobs
	DROP_BOOST,       # Increased drop rates
	LOOT_PARTY,       # Party finder bonus
	PVP_WEEKEND,      # Extra honor/reputation
	HOLIDAY,          # Christmas, Halloween, etc.
	RAID_WEEK,        # Reduced raid cooldowns
	CRAFTING_MASTER,  # Reduced crafting costs
	GUILD_FESTIVAL,   # Guild activity bonuses
	NEW_PLAYER,       # Help new players bonus
	SEASONAL,         # Seasonal event (spring, summer, etc.)
}

enum EventStatus {
	INACTIVE,   # Not running
	ACTIVE,     # Currently running
	UPCOMING,   # Announced but not started
	ENDED       # Finished, data kept for records
}

@export var id: String = ""
@export var display_name: String = "Event"
@export var description: String = ""

# Event classification
@export var event_type: EventType = EventType.XP_BOOST
@export var icon_path: String = ""

# Timing
@export var start_date: String = ""  # ISO 8601 format
@export var end_date: String = ""    # ISO 8601 format
@export var is_recurring: bool = false
@export var recurrence_pattern: String = ""  # "weekly", "monthly", etc.

# Status
var _status: EventStatus = EventStatus.INACTIVE

# Modifiers (what this event changes)
@export var xp_multiplier: float = 1.0       # 2.0 = double XP
@export var gold_multiplier: float = 1.0    # 2.0 = double gold
@export var drop_rate_multiplier: float = 1.0  # 1.5 = 50% better drops
@export var reputation_multiplier: float = 1.0
@export var crafting_cost_reduction: float = 0.0  # 0.2 = 20% cheaper
@export var pvp_honor_multiplier: float = 1.0

# Zones affected (empty = all zones)
@export var affected_zones: Array[String] = []

# Factions affected (empty = all)
@export var affected_factions: Array[String] = []

# Level range affected (0 = no limit)
@export var min_level: int = 0
@export var max_level: int = 0

# Rewards granted by event
@export var rewards: Array[Dictionary] = []
# Example: [{"type": "item", "id": "event_token", "amount": 10}]

# Quests enabled by event
@export var event_quests: Array[String] = []

# Required achievements to participate
@export var requirements: Array[String] = []

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Check if event is currently active
func is_active() -> bool:
	return _status == EventStatus.ACTIVE

## Check if a given time is within event range
func is_within_time_range(utc_time: String = "") -> bool:
	var current_time := utc_time if utc_time != "" else Time.get_datetime_string_from_system()
	return current_time >= start_date and current_time <= end_date

## Check if zone is affected by this event
func affects_zone(zone_id: String) -> bool:
	if affected_zones.is_empty():
		return true  # All zones affected
	return affected_zones.has(zone_id)

## Check if level is affected by this event
func affects_level(level: int) -> bool:
	if min_level > 0 and level < min_level:
		return false
	if max_level > 0 and level > max_level:
		return false
	return true

## Get XP multiplier for an entity
func get_xp_multiplier(entity_level: int = 0) -> float:
	if entity_level > 0 and not affects_level(entity_level):
		return 1.0
	return xp_multiplier

## Get drop rate for an entity
func get_drop_multiplier(entity_level: int = 0) -> float:
	if entity_level > 0 and not affects_level(entity_level):
		return 1.0
	return drop_rate_multiplier

## Get display info for UI
func get_info() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"description": description,
		"type": EventType.keys()[event_type],
		"status": EventStatus.keys()[_status],
		"start": start_date,
		"end": end_date,
		"modifiers": {
			"xp": xp_multiplier,
			"gold": gold_multiplier,
			"drops": drop_rate_multiplier
		}
	}
