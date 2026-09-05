## DialogueData - NPC dialogue tree definition
extends Resource
class_name DialogueData

@export var id: String = ""
@export var npc_id: String = ""
@export var display_name: String = ""

## Dialogue node — one screen of conversation
class DialogueNode extends Resource:
	@export var speaker: String = ""
	@export var text: String = ""
	@export var choices: Array[DialogueChoice] = []

## One choice the player can select
class DialogueChoice extends Resource:
	@export var text: String = ""
	@export var next_node: int = -1  # -1 = end conversation

@export var nodes: Array[DialogueNode] = []

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")
