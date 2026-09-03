## DialogueData - NPC dialogue tree definition
## Loaded from data/dialogues/*.tres
extends Resource
class_name DialogueData

@export var id: String = ""
@export var npc_id: String = ""
@export var speaker: String = "NPC"
@export var nodes: Array = []
