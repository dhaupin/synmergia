## DialogueData - NPC dialogue tree definition
extends Resource
class_name DialogueData

@export var id: String = ""
@export var npc_id: String = ""
@export var display_name: String = ""

# Store nodes as Dictionary arrays for .tres compatibility
# Each node dict: {speaker: String, text: String, choices: Array of choice dicts}
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
	if node.has("choices"):
		return node["choices"]
	return []
