## SkillAcademyNPC - Skill book vendor + upgrade + respec hub
## Interactable NPC that provides access to the Skill Academy UI
extends "res://core/entities/entity.gd"
class_name SkillAcademyNPC

const NPCData = preload("res://core/schemas/npc_data.gd")
const Faction = preload("res://core/schemas/faction.gd")

var npc_data: NPCData = null
var faction: int = Faction.FRIENDLY

func _ready() -> void:
	npc_data = NPCData.new()
	npc_data.npc_id = "skill_academy_default"
	npc_data.display_name = "Skill Academy"
	npc_data.location_type = NPCData.LocationType.CITY

func interact(player: Entity) -> void:
	faction = Faction.FRIENDLY

func get_interaction_prompt() -> String:
	return "[E] Open Skill Academy"
