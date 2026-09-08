## NPCEntity -- unified NPC entity that reads offerings from NPCData.
## Unified NPC entity -- reads includes[] from NPCData and dispatches to the correct panel/service on interact.
## Each NPC has one or more offerings in npc_data.includes[].
## on_interact() reads the offering and routes to the appropriate panel.
extends "res://core/entities/entity.gd"
class_name NPCEntity

const NPCData = preload("res://core/schemas/npc_data.gd")
const NPCOffering = preload("res://core/schemas/npc_offering.gd")
## DISABLED: const ShopUI = preload("res://ui/components/shop_ui.gd")

## Set by SpawnService when the entity is placed
var npc_data: NPCData = null

func _ready() -> void:
	entity_type = EntityType.NPC
	relation = Relation.FRIENDLY
	super._ready()


## Build interaction prompt from the first offering in includes[].
func get_interaction_prompt() -> String:
	if npc_data == null or npc_data.includes.is_empty():
		return "[E] Talk"
	var first: Dictionary = npc_data.includes[0]
	match first.get("type", ""):
		"offering":
			var offering := _load_offering(first.get("ref_id", ""))
			if offering:
				return _prompt_for_offering(offering)
	return "[E] Interact"


## Load an offering resource from data/npc_offerings/<ref_id>.tres
func _load_offering(ref_id: String) -> Resource:
	if ref_id.is_empty():
		return null
	var path := "res://data/npc_offerings/%s.tres" % ref_id
	var res := load(path)
	if res == null:
		push_warning("NPCEntity: Failed to load offering: " + path)
	return res


## Derive a human-readable prompt from the offering type.
func _prompt_for_offering(offering: Resource) -> String:
	if offering.type == "vendor":
		return "[E] Open Shop"
	if offering.type == "service":
		match offering.service_id:
			"BlacksmithService":    return "[E] Talk to Blacksmith"
			"SkillAcademyService":   return "[E] Open Skill Academy"
			"BankService":           return "[E] Access Bank"
			"TavernService":         return "[E] Enter Tavern"
			"ReforgeService":        return "[E] Open Reforge"
			"EnchantService":        return "[E] Open Enchant"
			_:                      return "[E] Use Service"
	if offering.type == "quest":
		return "[E] View Quests"
	if offering.type == "dialogue":
		return "[E] Talk"
	if offering.type == "bank":
		return "[E] Access Bank"
	return "[E] Interact"


## Called when player presses E on this NPC.
## Reads includes[] and opens the appropriate panel.
func on_interact(player: Entity) -> void:
	if npc_data == null:
		push_warning("NPCEntity: No NPC data on entity %s" % entity_id)
		return

	for inc: Dictionary in npc_data.includes:
		var type: String = inc.get("type", "")
		if type == "offering":
			var offering := _load_offering(inc.get("ref_id", ""))
			if offering:
				_dispatch_offering(offering, player)


## Route an offering to the right panel/service.
func _dispatch_offering(offering: Resource, player: Entity) -> void:
	match offering.type:
		"vendor":
			var offering_res := offering as Resource
			var npc_pos := global_position if is_instance_valid(self) else Vector3.ZERO
			ShopUI.open_for_offering(
				player.entity_id if player else "",
				offering_res,
				npc_data,
				npc_pos
			)

		"service":
			_dispatch_service(offering, player)

		"bank":
			if MenuManager:
				MenuManager.open_menu("bank")

		"quest":
			if MenuManager:
				MenuManager.open_menu("quests")

		"dialogue":
			if not offering.dialogue_id.is_empty() and DialogService:
				DialogService.start_dialogue(entity_id, offering.dialogue_id)
			else:
				push_warning("NPCEntity: dialogue offering missing dialogue_id on NPC %s" % entity_id)

		_:
			push_warning("NPCEntity: Unknown offering type: " + str(offering.type))


## Route service offerings to the appropriate existing panel.
func _dispatch_service(offering: Resource, player: Entity) -> void:
	var player_id := player.entity_id if player else ""

	match offering.service_id:
		"BlacksmithService":
			if PlayerManager:
				PlayerManager.open_blacksmith_ui(player_id, npc_data)

		"SkillAcademyService":
			if PlayerManager:
				PlayerManager.open_skill_academy_ui(player_id, npc_data)

		"BankService":
			if MenuManager:
				MenuManager.open_menu("bank")

		"ReforgeService":
			if MenuManager:
				MenuManager.open_menu("reforge")

		"EnchantService":
			if MenuManager:
				MenuManager.open_menu("enchant")

		"TavernService":
			if MenuManager:
				MenuManager.open_menu("tavern")

		_:
			push_warning("NPCEntity: Unknown service_id: " + str(offering.service_id))
