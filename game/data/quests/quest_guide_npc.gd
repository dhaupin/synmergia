## Quest: Guide the Merchant
## Example quest that uses FollowService for NPC quest followers
## The NPC needs to get to another area and the player must lead them there
class_name QuestData
extends Resource

const QuestObjective = preload("res://core/schemas/quest_objective.gd").QuestObjective
const QuestStatus = preload("res://core/schemas/quest.gd").QuestStatus

# Quest metadata
const quest_id: String = "guide_merchant"
const quest_name: String = "Safe Passage"
const quest_description: String = "Help the merchant reach the eastern trading post. Follow them to ensure their safety along the dangerous path."
const quest_level: int = 5
const quest_zone: String = "starting_plains"
const quest_area: Vector3 = Vector3(500, 0, 300)

# NPC data
const npc_id: String = "merchant_traveler"
const npc_name: String = "Traveling Merchant"
const npc_start_position: Vector3 = Vector3(100, 0, 100)
const npc_end_position: Vector3 = Vector3(500, 0, 300)
const npc_follow_range: float = 8.0

# Quest objectives
var objectives: Array[Dictionary] = [
	{
		"id": "talk_to_merchant",
		"type": "interact",
		"target": npc_id,
		"description": "Talk to the Traveling Merchant",
		"required_count": 1,
		"current_count": 0,
		"completed": false
	},
	{
		"id": "lead_merchant",
		"type": "follow",
		"target": npc_id,
		"description": "Lead the merchant to the trading post",
		"required_count": 1,
		"current_count": 0,
		"completed": false
	},
	{
		"id": "arrive_at_trading_post",
		"type": "reach_location",
		"target": "trading_post",
		"position": npc_end_position,
		"range": 20.0,
		"description": "Arrive at the Eastern Trading Post",
		"required_count": 1,
		"current_count": 0,
		"completed": false
	}
]

# Rewards
var rewards: Dictionary = {
	"gold": 100,
	"experience": 500,
	"items": [
		{"item_id": "health_potion", "quantity": 3},
		{"item_id": "merchant_token", "quantity": 1}
	],
	"faction_reputation": {
		"merchants_guild": 10
	}
}

# Quest state
var _quest_npc_id: String = ""
var _is_following: bool = false

## Initialize quest for player
func initialize(quest_id: String, player_id: String) -> Dictionary:
	_quest_npc_id = "%s_%s" % [npc_id, player_id]
	
	return {
		"quest_id": quest_id,
		"status": QuestStatus.ACTIVE,
		"objectives": objectives.duplicate(true),
		"progress": 0.0,
		"started_at": Time.get_unix_time_from_system()
	}

## Called when player talks to quest NPC
func on_npc_interaction(player_id: String, npc_entity) -> Dictionary:
	# Spawn the merchant NPC if not already spawned
	if not EntityService.has_entity(_quest_npc_id):
		_spawn_merchant_npc(player_id)
	
	# Update objective
	var result := update_objective(player_id, "talk_to_merchant", 1)
	
	return {
		"dialog": [
			"Thank you for stopping! I'm trying to reach the Eastern Trading Post.",
			"The roads are dangerous with all the bandits lately...",
			"Would you follow me and make sure I get there safely?",
			"I'll stay close behind you. Just lead the way!"
		],
		"action": "start_follow",
		"started": true
	}

## Spawn the merchant NPC that will follow
func _spawn_merchant_npc(player_id: String) -> void:
	# Create merchant entity
	var merchant_entity := {
		"entity_id": _quest_npc_id,
		"entity_type": Entity.EntityType.NPC,
		"display_name": npc_name,
		"position": npc_start_position,
		"level": 1,
		"npc_id": npc_id,
		"is_quest_giver": true,
		"quest_id": quest_id
	}
	
	if EntityService:
		var spawned := EntityService.spawn_entity(merchant_entity)
		if spawned:
			GameLog.info("Quest %s: Spawned merchant NPC %s" % [quest_id, _quest_npc_id])

## Start the NPC following the player
func start_npc_follow(player_id: String) -> bool:
	if not FollowService:
		GameLog.warn("Quest %s: FollowService not available" % quest_id)
		return false
	
	# Start NPC following player
	var success := FollowService.request_follow(_quest_npc_id, player_id)
	if success:
		_is_following = true
		GameLog.info("Quest %s: Merchant started following %s" % [quest_id, player_id])
		
		# Set waypoint at destination
		if WaypointService:
			WaypointService.create_quest_waypoint(
				player_id,
				quest_id,
				"Eastern Trading Post",
				npc_end_position,
				"eastern_territory",
				WaypointService.WaypointIcon.HOUSE
			)
		
		# Notify player
		if NotificationService:
			NotificationService.notify(
				NotificationService.NotificationType.QUEST,
				"Merchant is following you! Lead them to the Eastern Trading Post.",
				"QuestService",
				"quest_follow:%s" % quest_id,
				{"quest_id": quest_id}
			)
	
	return success

## Called when player reaches location
func on_location_reached(player_id: String, position: Vector3) -> Dictionary:
	# Check if we're at the destination
	var distance := position.distance_to(npc_end_position)
	
	if distance <= 20.0:  # Within range of destination
		# Complete the follow objective
		update_objective(player_id, "lead_merchant", 1)
		update_objective(player_id, "arrive_at_trading_post", 1)
		
		# Stop NPC following
		if FollowService and _is_following:
			FollowService.stop_follow(_quest_npc_id, "quest_complete")
			_is_following = false
		
		# Remove quest waypoint
		if WaypointService:
			WaypointService.remove_quest_waypoints(player_id, quest_id)
		
		# Complete quest
		return complete_quest(player_id)
	
	return {"progress": distance / npc_end_position.distance_to(npc_start_position)}

## Clean up when quest is abandoned or completed
func on_quest_abandon(player_id: String) -> void:
	# Stop NPC following
	if FollowService and _is_following:
		FollowService.stop_follow(_quest_npc_id, "quest_abandoned")
		_is_following = false
	
	# Remove NPC
	if EntityService and EntityService.has_entity(_quest_npc_id):
		EntityService.despawn_entity(_quest_npc_id, "quest_abandoned")
	
	# Remove waypoint
	if WaypointService:
		WaypointService.remove_quest_waypoints(player_id, quest_id)
	
	GameLog.info("Quest %s: Cleaned up for player %s" % [quest_id, player_id])
