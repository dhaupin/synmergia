## BlacksmithNPC - Equipment repair vendor
extends Node3D
class_name BlacksmithNPC

var npc_data
var faction: int = 1  # Faction.NEUTRAL

func _ready() -> void:
	npc_data = {
		"npc_id": "blacksmith_default",
		"display_name": "Blacksmith",
		"npc_type": 3  # NPCType.BLACKSMITH
	}

func interact(player) -> void:
	pass

func get_interaction_prompt() -> String:
	return "[E] Talk to Blacksmith"
