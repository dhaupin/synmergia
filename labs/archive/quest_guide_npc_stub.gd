## Quest: Guide the Merchant
## Stub Resource for the "Safe Passage" quest.
##
## Historical context: this file was added in 58e7401 ("Complete waypoint
## system + FollowService QC") as a fully scripted quest. It was never
## wired into the quest system (no .tres file references it, no service
## loads it) and several of its references were broken from day one:
##
##   - `res://core/schemas/quest_objective.gd` never existed
##   - `res://core/schemas/quest.gd` never existed
##   - `class_name QuestData` shadowed the real schema in
##     res://core/schemas/quest_data.gd
##   - It called `update_objective()` and `complete_quest()` which were
##     never defined in this script
##
## Rather than delete the file (the metadata is potentially useful when
## someone picks the quest back up) we keep it as a thin Resource stub
## that exposes the constants and the entity-spawn hook. To revive the
## full quest, copy this file and add the missing implementations.
extends Resource

# Quest metadata
const quest_id: String = "guide_merchant"
const quest_name: String = "Safe Passage"
const quest_description: String = "Help the merchant reach the eastern trading post. Follow them to ensure their safety along the dangerous path."
const quest_level: int = 5
const quest_zone: String = "starting_plains"

# NPC data
const npc_id: String = "merchant_traveler"
const npc_name: String = "Traveling Merchant"
const npc_start_position: Vector3 = Vector3(100, 0, 100)
const npc_end_position: Vector3 = Vector3(500, 0, 300)
const npc_follow_range: float = 8.0

# Returns the entity dict that should be spawned for this quest NPC.
# Callers (e.g. QuestService) are responsible for handing it to
# EntityService.spawn_entity() and routing the lifecycle events back.
func get_merchant_entity_template() -> Dictionary:
	return {
		"entity_id": "%s_%s" % [npc_id, str(Time.get_unix_time_from_system()).replace(".", "_")],
		"entity_type": "NPC",
		"display_name": npc_name,
		"position": npc_start_position,
		"level": 1,
		"npc_id": npc_id,
		"is_quest_giver": true,
		"quest_id": quest_id,
	}
