## NPCEntity -- unified NPC entity that reads offerings from NPCData.
## Unified NPC entity -- reads includes[] from NPCData and dispatches to the correct panel/service on interact.
## Each NPC has one or more offerings in npc_data.includes[].
## on_interact() reads the offering and routes to the appropriate panel.
extends "res://core/entities/entity.gd"
class_name NPCEntity

const NPCData = preload("res://core/schemas/npc_data.gd")
const NPCOffering = preload("res://core/schemas/npc_offering.gd")
# MenuManager is not an autoload (class_name only). on_interact()
# calls MenuManager.open_menu(...) bare, which requires the
# class_name registered at parse time. Preload it here. This does
# NOT form a cycle: npc_entity -> menu_manager -> dialog_ui ->
# dialog_service, and dialog_service no longer preloads
# menu_manager (it loads it lazily at the call site).
const MenuManager = preload("res://ui/components/menu_manager.gd")
const ShopUI = preload("res://ui/components/shop_ui.gd")

## Set by SpawnService when the entity is placed
var npc_data: NPCData = null

## Hitbox Profile System: cached profile (null until _ready resolves).
var _hitbox_profile_cache: HitboxProfile = null

func _ready() -> void:
	entity_type = EntityType.NPC
	relation = Relation.FRIENDLY
	add_to_group("offering_npcs")
	super._ready()
	if npc_data != null:
		npc_data.normalize_includes()
	_apply_hitbox_profile()
	_play_model_idle()


## Hitbox Profile System: apply npc_data.hitbox_profile_id (default
## hitbox_npc) to the scene-authored CollisionShape3D, or build one.
## Keeps NPC capsule size a data edit instead of a per-scene edit.
func _apply_hitbox_profile() -> void:
	if DataService == null:
		return
	var profile_id := "hitbox_npc"
	if npc_data != null:
		var requested = npc_data.get("hitbox_profile_id")
		if requested != null and not str(requested).is_empty():
			profile_id = str(requested)
	var profile: HitboxProfile = DataService.get_hitbox_profile(profile_id)
	if profile == null:
		return
	_hitbox_profile_cache = profile
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		# Deferred: _ready-time tree setup can reject sync adds.
		shape_node = CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		add_child.call_deferred(shape_node)
	shape_node.shape = profile.build_shape(1.0)
	var dims: Dictionary = profile.get_dims(1.0)
	shape_node.position = Vector3(0.0, float(dims["offset"]), 0.0)


## Play the idle clip on an instanced .glb model (scene_path scenes that
## embed a ModelRoot with its own AnimationPlayer). Silence is fine:
## not every NPC scene carries a skinned model yet.
func _play_model_idle() -> void:
	var ap := get_node_or_null("ModelRoot/model/AnimationPlayer") as AnimationPlayer
	if ap == null:
		# Older .glb imports nest the player under the model root itself.
		ap = get_node_or_null("ModelRoot/AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation("idle"):
		return
	# The .glb's AnimationPlayer targets an absolute root
	# (/rig_blacksmith/Skeleton3D); repoint it relative to this scene so
	# instancing under any parent resolves.
	ap.root_node = ap.get_parent().get_path()
	ap.play("idle")


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


## Load an offering resource from data/npc_offerings/<ref_id>.tres.
## Only ref_id entries point at offering files; inline entries
## (dialogue_id / quest_ids / service_id directly on the include
## dictionary) are the canonical data/npc/*.tres shape.
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
		else:
			_dispatch_inline_offering(inc, player)


## Wrap an inline include dictionary into an NPCOffering resource so it
## can flow through the _dispatch_offering/_dispatch_service resource
## path (service_id, vault_type, etc.). Returns null when the include
## carries no service_id.
func _inline_inc_to_offering(inc: Dictionary) -> Resource:
	var OfferingClass := load("res://core/schemas/npc_offering.gd")
	var offering: Resource = OfferingClass.new() if OfferingClass else null
	if offering == null:
		return null
	offering.type = str(inc.get("type", ""))
	offering.service_id = str(inc.get("service_id", ""))
	var params: Variant = inc.get("service_params")
	if params is Dictionary:
		offering.service_params = params
	return offering


## Route an INLINE include (from data/npc/*.tres: {type: "dialogue",
## dialogue_id}, {type: "vendor", ref_id}, {type: "quest", quest_ids},
## {type: "service", service_id}, {type: "bank"}). The ref-based
## npc_offering.tres path is handled by _dispatch_offering; this covers
## the shape the playable world actually ships with.
func _dispatch_inline_offering(inc: Dictionary, player: Entity) -> void:
	var type: String = inc.get("type", "")
	match type:
		"dialogue":
			var dlg_id := str(inc.get("dialogue_id", ""))
			if not dlg_id.is_empty() and DialogService:
				DialogService.start_dialogue(entity_id, dlg_id)
			else:
				push_warning("NPCEntity: dialogue include missing dialogue_id on NPC %s" % entity_id)
		"vendor":
			var offering := _load_offering(str(inc.get("ref_id", "")))
			if offering:
				_dispatch_offering(offering, player)
			else:
				push_warning("NPCEntity: vendor include missing ref_id on NPC %s" % entity_id)
		"quest":
			if MenuManager:
				MenuManager.open_menu("quests")
		"bank":
			if MenuManager:
				MenuManager.open_menu("bank")
		"service":
			_dispatch_service(_inline_inc_to_offering(inc), player)
		_:
			push_warning("NPCEntity: Unknown include type: %s on NPC %s" % [type, entity_id])


## Route an offering resource to the right panel/service.
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

		"FerryService":
			# The dock gets its own door (S16.10): the dock panel reads
			# FerryService truth live (schedule, boarding window, the
			# skiff's ticket law). One gate chain, same as blacksmith.
			if MenuManager:
				MenuManager.open_menu("dock")
			var dock_panel := MenuManager.get_panel_node("dock") if MenuManager else null
			if dock_panel != null and dock_panel.has_method("open_for_player"):
				dock_panel.open_for_player(player_id)

		_:
			push_warning("NPCEntity: Unknown service_id: " + str(offering.service_id))
