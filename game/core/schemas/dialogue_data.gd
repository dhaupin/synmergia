## DialogueData - NPC dialogue tree definition
extends Resource
class_name DialogueData

## Dialog action types that can be triggered from nodes/choices
enum DialogActionType {
	NONE,
	GIVE_QUEST,           # Triggers QuestService.accept_quest
	COMPLETE_QUEST,       # Triggers QuestService.turn_in_quest
	ABANDON_QUEST,        # Triggers QuestService.abandon_quest
	START_FOLLOW,         # Triggers FollowService.request_follow
	STOP_FOLLOW,          # Triggers FollowService.cancel_follow
	OPEN_SHOP,            # Opens shop/trade UI
	OPEN_VAULT,           # Opens vault UI
	TELEPORT,             # Teleports player to waypoint/zone
	SET_WAYPOINT,         # Creates waypoint at player position
	GIVE_ITEM,            # Gives item to player
	REMOVE_ITEM,          # Removes item from player
	GIVE_CURRENCY,        # Gives gold/coins
	REMOVE_CURRENCY,      # Removes gold/coins
	TEACH_SKILL,          # Unlocks skill
	EQUIP_ITEM,           # Equips item to player
	UNLOCK_TITLE,         # Unlocks title
	OPEN_TRADE,           # Opens trade with NPC
}

@export var id: String = ""
@export var npc_id: String = ""
@export var display_name: String = ""

# Store nodes as Dictionary arrays for .tres compatibility
# Each node dict: {
#   speaker: String,
#   text: String,
#   choices: Array of choice dicts,
#   action_type: DialogActionType (optional),
#   action_data: Dictionary (optional, e.g. {quest_id: "q001"})
# }
# Each choice dict: {
#   text: String,
#   next_node: int,
#   action_type: DialogActionType (optional),
#   action_data: Dictionary (optional)
# }
@export var nodes: Array[Dictionary] = []

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

func get_node(index: int) -> Dictionary:
	if index >= 0 and index < nodes.size():
		return nodes[index]
	return {}

func get_choices(node_index: int) -> Array[Dictionary]:
	var node := get_node(node_index)
	# .tres parses nested arrays as untyped Array (TYPE_ARRAY), so a
	# direct `return node["choices"]` fails the typed return and yields
	# [] silently (probed 2026-10-14). Rebuild a typed copy instead.
	var typed: Array[Dictionary] = []
	if node.has("choices"):
		for choice: Variant in node["choices"]:
			if choice is Dictionary:
				typed.append(choice)
	return typed

func get_node_action(node_index: int) -> Dictionary:
	var node := get_node(node_index)
	return {
		"type": node.get("action_type", DialogActionType.NONE),
		"data": node.get("action_data", {})
	}

func get_choice_action(node_index: int, choice_index: int) -> Dictionary:
	var choices := get_choices(node_index)
	if choice_index >= 0 and choice_index < choices.size():
		var choice: Dictionary = choices[choice_index]
		return {
			"type": choice.get("action_type", DialogActionType.NONE),
			"data": choice.get("action_data", {})
		}
	return {"type": DialogActionType.NONE, "data": {}}
