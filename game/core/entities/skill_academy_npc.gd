## SkillAcademyNPC - Skill book vendor + upgrade + respec hub
## Interactable NPC that provides access to the Skill Academy UI
extends Entity

const Entity = preload("res://core/entities/entity.gd")
const NPCData = preload("res://core/schemas/npc_data.gd")
const Faction = preload("res://core/schemas/faction.gd")

class_name SkillAcademyNPC

var npc_data: NPCData = null
var faction: int = Faction.FRIENDLY

func _ready() -> void:
	npc_data = NPCData.new()
	npc_data.npc_id = "skill_academy_default"
	npc_data.display_name = "Skill Academy"
	npc_data.npc_type = NPCData.NPCType.SPECIALIST

func interact(player: Entity) -> void:
	faction = Faction.FRIENDLY

func get_interaction_prompt() -> String:
	return "[E] Open Skill Academy"
