## SkillAcademyNPC - Skill book vendor + upgrade + respec hub
## Interactable NPC that provides access to the Skill Academy UI.
## No trading or state — delegates entirely to SkillAcademyService + SkillAcademyUI.
extends Entity

class_name SkillAcademyNPC

var npc_data: NPCData = null
var faction: int = Faction.FRIENDLY

var _greeting: String = "Greetings, warrior. Would you like to expand your combat knowledge?"
var _farewell: String = "May your blade stay sharp."

signal interacted(player: Entity)

func _ready() -> void:
	super._ready()
	entity_type = EntityType.NPC
	controller_type = ControllerType.NPC
	if npc_data:
		_apply_npc_data()

func apply_data(data: NPCData) -> void:
	npc_data = data
	_apply_npc_data()

func _apply_npc_data() -> void:
	if not npc_data:
		return
	display_name = npc_data.display_name
	_greeting = npc_data.greeting if npc_data.greeting != "" else _greeting
	_farewell = npc_data.farewell if npc_data.farewell != "" else _farewell
	if npc_data.faction == "friendly":
		faction = Faction.FRIENDLY
	elif npc_data.faction == "hostile":
		faction = Faction.HOSTILE
	else:
		faction = Faction.NEUTRAL

## Trigger player interaction — emits signal, UI is opened by player_controller
func interact(player: Entity) -> Dictionary:
	interacted.emit(player)
	return {
		"success": true,
		"action": "skill_academy",
		"dialogue": _greeting
	}

func get_interaction_data() -> Dictionary:
	return {
		"type": "skill_academy",
		"name": display_name,
		"greeting": _greeting,
		"farewell": _farewell
	}
