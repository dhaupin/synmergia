## AgentAction - Action data from an agent connector
## Represents an action the agent wants to take
class_name AgentAction
extends Resource

const __AgentAction__ = preload("res://core/schemas/agent_action.gd")
enum ActionType {
	UNKNOWN,
	MOVEMENT,
	COMBAT,
	SKILL,
	TARGETING,
	INTERACTION,
	CHAT,
	ADMIN
}

@export var action_type: ActionType = ActionType.UNKNOWN
@export var action_name: String = ""
@export var parameters: Dictionary = {}
@export var timestamp: int = 0

# Movement parameters
var movement_direction: Vector3 = Vector3.ZERO
var is_sprinting: bool = false
var is_jumping: bool = false

# Combat parameters
var target_entity_id: String = ""
var skill_id: String = ""
var ground_target_position: Vector3 = Vector3.ZERO

# Interaction parameters
var interact_target_id: String = ""
var use_item_slot: int = -1

# Chat parameters
var chat_message: String = ""
var chat_channel: String = "say"

func _init() -> void:
	timestamp = Time.get_ticks_msec()

## Parse from dictionary
static func from_dict(data: Dictionary) -> AgentAction:
	var action := __AgentAction__.new()
	
	action.action_name = data.get("action", "unknown")
	action.parameters = data.get("parameters", {})
	
	match action.action_name:
		"move_forward":
			action.action_type = ActionType.MOVEMENT
			action.movement_direction = Vector3.FORWARD
		"move_back":
			action.action_type = ActionType.MOVEMENT
			action.movement_direction = Vector3.BACK
		"move_left":
			action.action_type = ActionType.MOVEMENT
			action.movement_direction = Vector3.LEFT
		"move_right":
			action.action_type = ActionType.MOVEMENT
			action.movement_direction = Vector3.RIGHT
		"jump":
			action.action_type = ActionType.MOVEMENT
			action.is_jumping = true
		"sprint":
			action.action_type = ActionType.MOVEMENT
			action.is_sprinting = true
		"attack":
			action.action_type = ActionType.COMBAT
		"cast_skill_1", "cast_skill_2", "cast_skill_3", "cast_skill_4":
			action.action_type = ActionType.SKILL
			var skill_num := action.action_name.replace("cast_skill_", "")
			action.skill_id = "skill_slot_" + skill_num
		"dodge":
			action.action_type = ActionType.COMBAT
		"interact":
			action.action_type = ActionType.INTERACTION
			action.interact_target_id = data.get("target_id", "")
		"pickup":
			action.action_type = ActionType.INTERACTION
		"use_item":
			action.action_type = ActionType.INTERACTION
			action.use_item_slot = data.get("slot", -1)
		"target_nearest_enemy":
			action.action_type = ActionType.TARGETING
			action.parameters["mode"] = "nearest_enemy"
		"target_next_enemy":
			action.action_type = ActionType.TARGETING
			action.parameters["mode"] = "next"
		"clear_target":
			action.action_type = ActionType.TARGETING
			action.parameters["mode"] = "clear"
		"say", "yell", "party", "guild":
			action.action_type = ActionType.CHAT
			action.chat_message = data.get("message", "")
			action.chat_channel = action.action_name
	
	return action

## Validate action
func is_valid() -> bool:
	match action_type:
		ActionType.SKILL:
			return skill_id != ""
		ActionType.TARGETING:
			return true  # All targeting actions are valid
		ActionType.INTERACTION:
			return true
		ActionType.CHAT:
			return chat_message.length() <= 200  # Max message length
	
	return action_type != ActionType.UNKNOWN

## Get debug string
func to_string() -> String:
	return "AgentAction(%s: %s)" % [ActionType.keys()[action_type], action_name]
