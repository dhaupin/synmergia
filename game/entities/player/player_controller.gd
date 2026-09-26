## PlayerController - Main player character controller
## Free-form combat system (RYL2-style)
extends CharacterBody3D
class_name PlayerController

const CharacterData = preload("res://core/schemas/character_data.gd")
const SkillBook = preload("res://core/schemas/skill_book.gd")
const Skill = preload("res://core/combat/skill.gd")
const StateMachine = preload("res://core/state/state_machine_base.gd")
const ActionMenu = preload("res://ui/components/action_menu.gd")
const InventoryComponent = preload("res://core/components/inventory_component.gd")
# Entity is not an autoload (class_name only). PlayerController
# uses Entity.EntityType.X and `: Entity` type annotations, which
# require Entity's class_name registered at parse time. Preload it
# here -- no shadow: Entity is a class_name, not an autoload.
const Entity = preload("res://core/entities/entity.gd")
const BlacksmithUI = preload("res://ui/components/blacksmith_ui.gd")
const CharacterStatsUI = preload("res://ui/menus/character_stats_ui.gd")
const GMIndicator = preload("res://entities/player/components/gm_indicator.gd")
const ReportDialog = preload("res://ui/player/report_dialog.gd")
const SkillAcademyUI = preload("res://ui/components/skill_academy_ui.gd")


# Movement
## Data-driven profile (Movement Design System). Speeds/gravity below
## are FALLBACKS only; _ready() resolves movement_standard from
## DataService and overrides every field the profile defines. Editing
## feel is now a .tres edit, not a code edit.
@export var movement_profile_id: String = "movement_standard"
@export var move_speed: float = 5.0
@export var sprint_speed: float = 7.5
@export var air_dodge_force: float = 6.0  # Stronger air dodge
@export var jump_force: float = 10.0
@export var gravity_force: float = 20.0
@export var dodge_force: float = 4.5
@export var dodge_cost: float = 25.0
@export var dodge_cooldown: float = 1.5
@export var crouch_speed: float = 2.0  # COD-style crouch-walk speed
@export var void_kill_y: float = -25.0  # below this Y the void safety net fires

# Combat
@export var basic_attack: Skill = null
@export var skillbar: Array = []
@export var attack_range: float = 2.5

# State
@export var can_air_dodge: bool = true
var is_invincible: bool = false
var is_attacking: bool = false
var is_sprinting: bool = false
var is_sliding: bool = false
var is_crouching: bool = false
var is_targeting: bool = false

## Movement Design System gates (stamped from the movement profile in
## _ready). Movement states consult these before entering sprint/jump/
## crouch, so a profile can turn a capability off for whole archetypes.
var allow_sprint: bool = true
var allow_jump_input: bool = true
var allow_crouch: bool = true

## Hitbox Profile System: cached profile (resolved in _ready via the
## species-fairness path) + current stance ("standing" | "crouch").
## Crouch/Slide states swap the stance; the capsule changes size, never
## scale -- players of every species/sex/body_type share ONE hitbox.
var _hitbox_profile: HitboxProfile = null
var _hitbox_stance: String = "standing"
var current_target: Node3D = null

# Components
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var state_machine: Node = $StateMachine
@onready var camera_pivot: Node3D = $CameraPivot

## Movement Design System: pull the profile from DataService and stamp
## its values over the fallback exports. Profile fields only overwrite
## what they define (profiles are authoritative, exports are defaults).
## Species speed_modifier still multiplies on top via Entity stats.
func _apply_movement_profile() -> void:
	if DataService == null:
		return
	var profile: MovementProfile = DataService.get_movement_profile(movement_profile_id)
	if profile == null:
		GameLog.warn("PlayerController: movement profile '%s' missing -- using built-in defaults" % movement_profile_id)
		return
	move_speed = profile.walk_speed
	sprint_speed = profile.sprint_speed
	crouch_speed = profile.crouch_speed
	jump_force = profile.jump_force
	gravity_force = profile.gravity_force
	dodge_force = profile.dodge_force
	allow_sprint = profile.allow_sprint
	allow_jump_input = profile.allow_jump
	allow_crouch = profile.allow_crouch
	GameLog.info("PlayerController: applied movement profile '%s'" % profile.id)


## Give AntiCheatService the hard limits derived from THIS player's
## profile so movement validation always matches legal game feel (a
## .tres retune retunes the anticheat with it). GM characters exempt
## themselves here -- the service stays role-blind.
func _stamp_anticheat() -> void:
	if AntiCheatService == null or entity_id.is_empty():
		return
	var profile: MovementProfile = null
	if DataService != null:
		profile = DataService.get_movement_profile(movement_profile_id)
	if profile == null:
		# Built-in fallbacks mirror the historical defaults (5.0/10.0/10.0).
		AntiCheatService.set_movement_limits(entity_id, 25.0, 25.0, 110.0)
		return
	var char_data := _get_character_data()
	var gm: bool = char_data != null and char_data.is_gm()
	if gm:
		AntiCheatService.set_movement_exempt(entity_id, true)
		return
	var fastest_legal: float = maxf(profile.sprint_speed, profile.walk_speed * 1.9)
	AntiCheatService.set_movement_limits(
		entity_id,
		fastest_legal * AntiCheatService.SPEED_LIMIT_MULTIPLIER,
		profile.jump_force * AntiCheatService.JUMP_LIMIT_MULTIPLIER,
		profile.terminal_fall_speed * AntiCheatService.FALL_LIMIT_MULTIPLIER
	)


## Hitbox Profile System: resolve + apply the player collision shape.
## FAIRNESS RULE (species PvP): resolution goes through the species-fair
## path (DataService.resolve_player_hitbox_profile) so every playable
## species lands on the SAME profile. Species, sex, and body_type never
## scale or swap the player hitbox; hitbox_player.tres clamps scale to
## 1.0 hard, so even a bad future export cannot shrink or grow one
## species's capsule relative to another.
func _apply_hitbox_profile() -> void:
	if DataService == null:
		return
	var species_id := "human"
	var char_data := _get_character_data()
	if char_data != null and not char_data.species_id.is_empty():
		species_id = char_data.species_id
	_hitbox_profile = DataService.resolve_player_hitbox_profile(species_id)
	if _hitbox_profile == null:
		GameLog.warn("PlayerController: hitbox profile missing -- keeping scene capsule")
		return
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		# Deferred: _ready-time tree setup can reject sync adds.
		shape_node = CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		add_child.call_deferred(shape_node)
	shape_node.shape = _hitbox_profile.build_shape(1.0, _hitbox_stance)
	var dims: Dictionary = _hitbox_profile.get_dims(1.0, _hitbox_stance)
	shape_node.position = Vector3(0.0, float(dims["offset"]), 0.0)
	GameLog.info("PlayerController: applied hitbox profile '%s' (species-fair: %s)" % [_hitbox_profile.id, str(_hitbox_profile.pvp_fair)])


## Stance swap for Crouch/Slide states: same profile, same species,
## SAME scale -- only the crouch variant's smaller capsule applies.
## Falls back to standing when the profile has no crouch variant.
func set_hitbox_stance(stance: String) -> void:
	if _hitbox_profile == null:
		_hitbox_stance = stance
		return
	if stance == _hitbox_stance:
		return
	if stance != "standing" and stance != "crouch":
		return
	_hitbox_stance = stance
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	shape_node.shape = _hitbox_profile.build_shape(1.0, _hitbox_stance)
	var dims: Dictionary = _hitbox_profile.get_dims(1.0, _hitbox_stance)
	shape_node.position = Vector3(0.0, float(dims["offset"]), 0.0)


## Respawn binding (Ankh.bind_player writes respawn_ankh_id;
## RespawnService reads it when offering the ANKH respawn mode).
var respawn_ankh_id: String = ""
var respawn_point: Vector3 = Vector3.ZERO

## Player bag (GroundLootService routes pickups here via
## InventoryService). Created in _ready -- every PlayerController gets
## one regardless of which scene instantiates it.
var inventory_component: InventoryComponent = null

# Multiplayer
var player_id: int = 1
var is_local_player: bool = true
var entity_id: String = ""
## Canonical fallback id when the scene doesn't assign one (matches
## world_playable.LOCAL_PLAYER_ID; the old int str(player_id) fallback
## produced "1" and desynced every service keyed by entity_id).
const LOCAL_PLAYER_ID := "player_1"

# --- Combat surface ------------------------------------------------------
# EnemyAI, Skill, and EntityService treat all combatants uniformly via this
# duck-typed surface. PlayerController is a CharacterBody3D (not an Entity
# subclass), so these mirror the Entity API at runtime.
const HealthComponent = preload("res://core/components/health_component.gd")

## Entity.EntityType.PLAYER constant, mirrored so `entity.entity_type`
## reads work without an Entity cast.
var entity_type: int = 1

var display_name: String = "Player"
var level: int = 1

## The player's class id ("human_warrior", ...). Required by
## Skill.can_cast's required_class gate; boot paths without login use
## the default class so the starting skillbar is actually castable.
var character_class: String = "human_warrior"

# Standard stat block (Entity-compatible shape used by get_* accessors).
var stats: Dictionary = {
	"strength": 10,
	"agility": 10,
	"intelligence": 10,
	"vitality": 10,
	"wisdom": 10,
}

## Health component (created in _ready, mirrors Enemy's pattern).
var health_component: HealthComponent = null
var max_health: int = 100
var current_health: int = 100
var team_id: int = 0

# Allegiance alias (Entity.Relation.HOSTILE etc.) read by
# EntityService.is_enemy via `entity.faction`.
var faction: int = 0
var relation: int = 0
# Entity parity: services (FactionManager wars, RespawnService rez rules,
# ZoneData entry gates, PlacementAccess) read faction_id off any
# combatant. Empty string = unaligned.
var faction_id: String = ""

# Context menu
var _action_menu: ActionMenu = null
var _skill_academy_ui: SkillAcademyUI = null
var _blacksmith_ui: BlacksmithUI = null
var _character_stats_ui: CharacterStatsUI = null
var _current_target_info: TargetingManager.TargetInfo = null

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

func _ready() -> void:
	# Connect to input
	InputManager.player_input.connect(_on_player_input)
	PlayerManager.set_local_player(self)
	add_to_group("players")
	_apply_movement_profile()
	_setup_starting_skills()
	# Anticheat limits key on entity_id, which resolves AFTER the
	# inventory fallback below had a chance to fill it (see _inv_id).
	# Call deferred so stamping sees the FINAL id exactly once.
	call_deferred("_stamp_anticheat")
	# Hitbox likewise keys on the final character data (species); the
	# scene-authored capsule is the pre-profile placeholder.
	call_deferred("_apply_hitbox_profile")

	# Set collision
	collision_mask = 0b0000111
	collision_layer = 0b0000001

	# Initialize basic attack if null
	if basic_attack == null:
		basic_attack = _create_basic_attack()

	# Register with TargetingManager
	TargetingManager.register_targetable(
		entity_id,
		"player",
		self,
		name,
		global_position,
		Entity.EntityType.PLAYER
	)

	# Set local player for TargetingManager
	TargetingManager.set_local_player(entity_id)

	# Mirror the live targeting context so context-menu actions (Talk,
	# Trade->vendor shop, loot) can resolve NPC data/position. Without this
	# _current_target_info stayed null and NPC vendor routing silently fell
	# through to player-to-player trade.
	TargetingManager.target_acquired.connect(_on_target_acquired)
	TargetingManager.target_cleared.connect(_on_target_cleared)

	# Connect to InteractionLayer for touch targeting
	_connect_interaction_layer()

	# Health component: created here (not a scene child) so every
	# player gets one regardless of which scene instantiates them.
	if health_component == null:
		health_component = HealthComponent.new()
		health_component.max_health = max_health
		health_component.current_health = current_health
		add_child(health_component)

	# Inventory component: was never created for the local player, so
	# loot pickups had nowhere to land. Register with InventoryService
	# (GroundLootService routes pickups through it by entity_id).
	if inventory_component == null:
		inventory_component = InventoryComponent.new()
		inventory_component.name = "InventoryComponent"
		add_child(inventory_component)
	# Stable id BEFORE anything else keys off it: world_playable only fills
	# entity_id when it's still empty, so an int fallback here (str(1) -> "1")
	# used to win the race and desync InventoryService/EntityService/quest
	# credit from the canonical "player_1". Use the scene-agnostic string id.
	var _inv_id := entity_id if entity_id != "" else LOCAL_PLAYER_ID
	if entity_id == "":
		entity_id = _inv_id
	inventory_component.set_owner_id(_inv_id)
	if InventoryService and InventoryService.has_method("register_inventory"):
		InventoryService.register_inventory(_inv_id, inventory_component)

	# Duck-typed respawn fields RespawnService/Ankh read (CharacterBody3D
	# has none of them natively; Ankh.bind_player sets respawn_ankh_id).
	respawn_ankh_id = ""
	respawn_point = global_position

	# Add GM indicator if this is a GM character
	_add_gm_indicator()

	GameLog.info("PlayerController ready")

func _add_gm_indicator() -> void:
	var char_data := _get_character_data()
	if char_data and char_data.is_gm():
		var indicator := GMIndicator.new()
		indicator.name = "GMIndicator"
		add_child(indicator)
		GameLog.info("Added GM star indicator")

func _connect_interaction_layer() -> void:
	if InteractionLayer:
		InteractionLayer.tap.connect(_on_interaction_tap)
		InteractionLayer.double_tap.connect(_on_interaction_double_tap)
		InteractionLayer.long_press.connect(_on_interaction_long_press)
		InteractionLayer.action_triggered.connect(_on_interaction_action)

## Handle tap (touch) - target entity
func _on_interaction_tap(position: Vector2) -> void:
	if not is_local_player:
		return

	# Only handle taps on right side of screen (for movement)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if position.x < viewport_size.x * 0.3:
		return  # Left side is movement joystick

	_handle_left_click(position)

## Handle double tap - quick target
func _on_interaction_double_tap(position: Vector2) -> void:
	if not is_local_player:
		return

	# Quick target nearest enemy
	_find_and_set_nearest_target()

## Handle long press - context menu
func _on_interaction_long_press(position: Vector2) -> void:
	if not is_local_player:
		return

	# Raycast to find target
	var camera := _get_camera()
	if camera:
		var target_info: Variant = TargetingManager.raycast_from_touch(position, camera)
		if target_info:
			_show_target_context_menu(target_info)

## Handle action triggers from InteractionLayer
func _on_interaction_action(action_name: String) -> void:
	if not is_local_player:
		return

	match action_name:
		"target_next":
			cycle_target()
		"target_prev":
			cycle_target_previous()
		"focus":
			# Focus on current target
			pass
		"target_self":
			_target_self()
		"cancel":
			clear_target()

## Target self
func _target_self() -> void:
	TargetingManager.set_target(
		entity_id,
		"player",
		name,
		global_position,
		self,
		Entity.EntityType.PLAYER
	)
	is_targeting = false  # Self-target doesn't enable targeting mode

## Show target context menu
func _show_target_context_menu(target_info: TargetingManager.TargetInfo) -> void:
	match target_info.entity_type:
		Entity.EntityType.PLAYER:
			_show_player_context_menu(target_info)
		Entity.EntityType.NPC:
			_show_npc_context_menu(target_info)
		Entity.EntityType.LOOT:
			_show_loot_context_menu(target_info)
		Entity.EntityType.TELEPORT:
			_show_gateway_context_menu(target_info)

func _show_npc_context_menu(target_info: TargetingManager.TargetInfo) -> void:
	if not _action_menu:
		_action_menu = ActionMenu.new()
		add_child(_action_menu)
		_action_menu.action_selected.connect(_on_context_action)
	_action_menu.show_menu(get_viewport().get_mouse_position(), target_info.id, target_info.entity_type, target_info.npc_data)

func _show_loot_context_menu(target_info: TargetingManager.TargetInfo) -> void:
	if not _action_menu:
		_action_menu = ActionMenu.new()
		add_child(_action_menu)
		_action_menu.action_selected.connect(_on_context_action)
	_action_menu.show_menu(get_viewport().get_mouse_position(), target_info.id, target_info.entity_type)

func _show_gateway_context_menu(target_info: TargetingManager.TargetInfo) -> void:
	if not _action_menu:
		_action_menu = ActionMenu.new()
		add_child(_action_menu)
		_action_menu.action_selected.connect(_on_context_action)
	_action_menu.show_menu(get_viewport().get_mouse_position(), target_info.id, target_info.entity_type)

func _show_player_context_menu(target_info) -> void:
	if not _action_menu:
		_action_menu = ActionMenu.new()
		add_child(_action_menu)
		_action_menu.action_selected.connect(_on_context_action)
	_action_menu.show_menu(get_viewport().get_mouse_position(), target_info.id, target_info.entity_type)

func _on_context_action(action_id: String, target_id: String) -> void:
	match action_id:
		"whisper":
			ChatService.send_whisper(player_id, target_id, "")
		"invite_party":
			if PartyService: PartyService.invite_player(str(player_id), target_id)
		"invite_guild":
			if GuildService: GuildService.invite_player(str(player_id), target_id)
		"trade":
			# NPC vendors open the shop panel; players open the trade panel.
			if _current_target_info and _current_target_info.id == target_id \
					and _current_target_info.entity_type == Entity.EntityType.NPC:
				_open_npc_vendor(target_id, _current_target_info)
			elif TradeService:
				TradeService.initiate_trade(str(player_id), target_id)
		"add_friend":
			if FriendsService: FriendsService.send_friend_request(str(player_id), str(player_id), target_id)
		"report":
			_open_report_dialog(target_id)
		"talk":
			_open_npc_dialogue(target_id)
		"quest":
			_open_npc_quests(target_id)
		"bank":
			if MenuManager:
				MenuManager.open_menu("bank")
		"loot":
			_pickup_loot_target(target_id)
		"pass":
			if LootService:
				LootService.pass_loot(target_id, str(player_id))
		"enter":
			_activate_gateway_target(target_id)

		"skill_academy":
			_open_skill_academy_ui()
		"blacksmith":
			_open_blacksmith_ui()
		"character_stats":
			_open_character_stats_ui()


## Resolve the dialogue id for an NPC's dialogue offering (inline or
## ref-based), or "" when the NPC has none.
func _find_npc_dialogue_id(target_id: String) -> String:
	var npc_data: NPCData = _npc_data_for_target(target_id)
	if npc_data == null:
		return ""
	return npc_data.get_dialogue_id()

func _open_npc_dialogue(target_id: String) -> void:
	var dialogue_id := _find_npc_dialogue_id(target_id)
	if dialogue_id.is_empty():
		GameLog.warn("PlayerController: NPC %s has no dialogue offering" % target_id)
		return
	if DialogService and DialogService.start_dialogue(target_id, dialogue_id):
		GameLog.info("PlayerController: dialogue started with %s (%s)" % [target_id, dialogue_id])
	else:
		GameLog.warn("PlayerController: failed to start dialogue %s" % dialogue_id)


## Open the QuestUI tab for an NPC's quest offering, if it has one.
func _open_npc_quests(target_id: String) -> void:
	var quest_ids := _npc_quest_ids_for_target(target_id)
	if quest_ids.is_empty():
		GameLog.warn("PlayerController: NPC %s has no quest offering" % target_id)
		return
	if MenuManager:
		MenuManager.open_menu("quests")
		var panel: Control = MenuManager.get_panel_node("quests")
		if panel and panel.has_method("refresh_quest_list"):
			panel.refresh_quest_list()


func _npc_quest_ids_for_target(target_id: String) -> Array:
	var ids: Array = []
	var npc_data: NPCData = _npc_data_for_target(target_id)
	if npc_data == null:
		return ids
	for inc: Dictionary in npc_data.includes:
		var t := str(inc.get("type", ""))
		if t == "quest":
			var qids: Variant = inc.get("quest_ids")
			if qids is Array:
				ids = qids
			break
		if t == "offering":
			var res := load("res://data/npc_offerings/%s.tres" % str(inc.get("ref_id", "")))
			if res != null and str(res.get("type")) == "quest":
				var qids2: Variant = res.get("quest_ids")
				if qids2 is Array:
					ids = qids2
				break
	return ids


## Open the vendor shop for an NPC with a vendor offering.
func _open_npc_vendor(target_id: String, target_info) -> void:
	var npc_data: NPCData = _npc_data_for_target(target_id)
	var vendor_offering: Resource = npc_data.get_vendor_offering() if npc_data else null
	if vendor_offering == null:
		GameLog.warn("PlayerController: NPC %s has no vendor offering" % target_id)
		return
	var npc_pos: Vector3 = target_info.world_position if target_info else Vector3.ZERO
	ShopUI.open_for_offering(str(player_id), vendor_offering, npc_data, npc_pos)



## Keep the context-action mirror of the current target in sync. These
## fire from TargetingManager whenever the player acquires/clears a
## target (long-press context menu, [E] interact, tab-targeting).
func _on_target_acquired(target: TargetingManager.TargetInfo) -> void:
	if target != null:
		_current_target_info = target


func _on_target_cleared(_previous: TargetingManager.TargetInfo) -> void:
	_current_target_info = null


## Resolve the live NPCData for a target id (entity node first, then
## the TargetingManager snapshot from the active context menu).
func _npc_data_for_target(target_id: String) -> NPCData:
	if EntityService:
		var npc: Variant = EntityService.get_entity(target_id)
		if npc != null and is_instance_valid(npc) and "npc_data" in npc \
				and npc.npc_data != null:
			return npc.npc_data as NPCData
	if _current_target_info and _current_target_info.id == target_id \
			and _current_target_info.npc_data != null:
		return _current_target_info.npc_data
	return null


## Loot a corpse/loot target: LootService.pickup_loot(player_id) for
## pending rolls, GroundLootService.try_pickup(player, drop_id) for
## live ground drops.
func _pickup_loot_target(target_id: String) -> void:
	var pid := str(player_id)
	var picked: Array = []
	if LootService and LootService.has_method("pickup_loot"):
		picked = LootService.pickup_loot(pid, target_id)
	if picked.is_empty() and GroundLootService and GroundLootService.has_method("try_pickup"):
		picked = GroundLootService.try_pickup(self, target_id)
	if picked.is_empty():
		GameLog.info("PlayerController: nothing to loot at %s" % target_id)


## Walk the player through a gateway via WorldService.use_gateway.
func _activate_gateway_target(gateway_id: String) -> void:
	if not WorldService:
		return
	var destination: Dictionary = WorldService.use_gateway(gateway_id, self)
	if destination.is_empty():
		GameLog.warn("PlayerController: gateway %s cannot be used" % gateway_id)
		return
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.CUSTOM,
			"You pass through the gateway.",
			"PlayerController",
			"gw_use:%s:%s" % [str(player_id), gateway_id],
			{"gateway_id": gateway_id},
			str(player_id)
		)


func _get_character_data() -> CharacterData:
	if GameManager and is_instance_valid(GameManager.selected_character_data):
		return GameManager.selected_character_data as CharacterData
	return null

func _get_inventory_books() -> Array:
	var books: Array = []
	if InventoryService:
		# get_player_items() never existed; the registered
		# InventoryComponent is the authoritative item store.
		var inv: InventoryComponent = InventoryService.get_inventory(str(player_id))
		if inv != null:
			for item in inv.get_all_items():
				if item is SkillBook:
					books.append(item)
	return books

func _open_skill_academy_ui() -> void:
	if not _skill_academy_ui:
		_skill_academy_ui = SkillAcademyUI.new()
		add_child(_skill_academy_ui)
	_skill_academy_ui.load_player_context(str(player_id))
	_skill_academy_ui.open_with_context(str(player_id), _get_character_data(), _get_inventory_books())

func _open_blacksmith_ui() -> void:
	if not _blacksmith_ui:
		_blacksmith_ui = BlacksmithUI.new()
		add_child(_blacksmith_ui)
	var inventory: InventoryComponent = null
	if InventoryService:
		inventory = InventoryService.get_inventory(str(player_id))
	var cost_modifier: float = 1.0
	var offers_discount: bool = true
	if _current_target_info and _current_target_info.npc_data:
		cost_modifier = _current_target_info.npc_data.get_total_cost_modifier()
		offers_discount = _current_target_info.npc_data.offers_bulk_discount
	_blacksmith_ui.open_with_context(str(player_id), inventory, cost_modifier, offers_discount)
	_blacksmith_ui.open(str(player_id))

func _open_character_stats_ui() -> void:
	if not _character_stats_ui:
		_character_stats_ui = CharacterStatsUI.new()
		add_child(_character_stats_ui)
	_character_stats_ui.open(str(player_id))

func _create_basic_attack() -> Skill:
	var skill: Skill = Skill.new()
	skill.skill_name = "Strike"
	skill.skill_id = "strike"
	skill.skill_type = Skill.SkillType.MELEE
	skill.damage = 20
	skill.mana_cost = 0
	skill.cast_time = 0.0
	skill.cooldown = 1.0
	skill.animation_duration = 0.4
	skill.range = 2.5
	skill.hitbox_size = 1.5
	skill.allow_movement = true
	skill.allow_jumping = true
	skill.combo_chain = ["heavy_strike"]
	return skill

func _physics_process(delta: float) -> void:
	if not is_local_player:
		return

	# SECURITY: Block movement if player is locked
	if PlayerLockService and entity_id and PlayerLockService.is_movement_blocked(entity_id):
		return

	# Handle follow mode - if following, auto-move to target
	if FollowService and entity_id and FollowService.is_following(entity_id):
		_handle_follow_movement()
		return

	# Gravity + integration always run: this is local physics, not a
	# networked action. The old QoS token-bucket gate here consumed one
	# "movement" token per physics frame against a 10/s budget, so
	# move_and_slide() was skipped on ~5 of every 6 frames (visible as
	# jerky, mostly-frozen movement and endless "Rate limited" spam).
	# Server-side movement throttling belongs to the transport layer.
	if not is_on_floor():
		velocity.y -= gravity_force * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()
	_report_movement_frame(delta)
	_void_recovery(delta)
	# Walk-over auto-loot (settings toggle): when enabled, walking
	# over a lootable drop vacuums it without pressing interact.
	_try_auto_loot()

	# Out-of-combat mana regen (5/s matches the class-schema default).
	_mana_regen_accum += 5.0 * delta
	if _mana_regen_accum >= 1.0:
		var gain := int(_mana_regen_accum)
		_mana_regen_accum -= gain
		if current_mana < max_mana:
			current_mana = mini(max_mana, current_mana + gain)
			mana_changed.emit(current_mana, max_mana)

## Void safety net: the playable floor is finite, so sprinting off the
## edge used to mean falling forever (state machine stuck in Fall with
## no ground to land on). Below void_kill_y we restore the player to
## their respawn point (spawn position by default) and re-ground the
## state machine through Land. The cooldown guards against a broken
## respawn point retriggering every frame.
## One frame of movement telemetry to AntiCheatService. The service
## owns the hard limits (stamped from our profile at spawn), the
## sustained-streak logic, and escalation; this is just the feed. Cheap
## by design: vector math + a Dictionary lookup, no allocation.
func _report_movement_frame(delta: float) -> void:
	if AntiCheatService == null or entity_id.is_empty():
		return
	AntiCheatService.validate_movement(entity_id, global_position, velocity, delta)


func _exit_tree() -> void:
	# Drop per-player anticheat state (limits, streaks, exemption) so a
	# departed player's entry can't leak into a recycled entity id.
	if AntiCheatService != null and not entity_id.is_empty():
		AntiCheatService.unregister_player(entity_id)


func _void_recovery(delta: float) -> void:
	if _void_recovery_cooldown > 0.0:
		_void_recovery_cooldown -= delta
		return
	if global_position.y >= void_kill_y:
		return
	_void_recovery_cooldown = 0.5
	GameLog.warn("Void recovery: %s fell out of the world" % entity_id)
	if is_instance_valid(NotificationService) and NotificationService.has_method("notify"):
		NotificationService.notify(
			NotifKind.PLAYER_WARNED,
			"You fell out of the world!",
			"PlayerController",
			"void_recovery:%s" % entity_id,
			{}, entity_id)
	global_position = respawn_point if respawn_point != Vector3.ZERO else Vector3(0, 1.5, 0)
	velocity = Vector3.ZERO
	if state_machine and state_machine.has_method("transition_to") and state_machine.has_state("Land"):
		state_machine.transition_to("Land")

## Handle automatic follow movement
func _handle_follow_movement() -> void:
	if not FollowService or not entity_id:
		return

	var target_pos: Vector3 = FollowService.get_target_position(entity_id)
	var distance: float = FollowService.get_distance_to_target(entity_id)
	var state: int = FollowService.get_follow_state(entity_id)

	if target_pos == Vector3.INF or distance < 0:
		return

	# Only actively move if catching up
	if state == FollowService.FollowState.CATCHING_UP:
		var direction: Vector3 = (target_pos - global_position).normalized()
		direction.y = 0  # Keep on ground

		# Apply speed boost for catching up
		var speed: float = move_speed * FollowService.DEFAULT_FOLLOW_SPEED_BUFF

		velocity = direction * speed
		move_and_slide()
	else:
		# Within threshold - just stand still
		velocity = Vector3.ZERO

func is_moving() -> bool:
	var input := InputManager.get_movement_input()
	return input.length() > 0.1

func get_movement_direction() -> Vector3:
	var input := InputManager.get_movement_input()
	var cam_basis := get_camera_basis()

	var forward: Vector3 = -cam_basis.z
	var right := cam_basis.x
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()

	# Do NOT normalize the result: the keyboard path is already unit
	# length, and the touch path reports true analog magnitude (0..1),
	# so half-stick = half-speed walking. Normalizing here collapsed
	# every stick deflection to full run speed (observed: half-stick
	# drag measured 5.0 u/s, identical to a full push).
	var direction := (forward * input.y + right * input.x)
	return direction if direction.length() <= 1.0 else direction.normalized()

func get_camera_basis() -> Basis:
	if camera_pivot and camera_pivot.get_child_count() > 0:
		var cam = camera_pivot.get_child(0)
		if cam is Camera3D:
			return cam.global_transform.basis
	return Transform3D().basis

func _on_player_input(action: String, pressed: bool) -> void:
	if not is_local_player:
		return

	match action:
		"sprint":
			is_sprinting = pressed and allow_sprint
		"target_next":
			if pressed:
				cycle_target()
		"target_previous":
			if pressed:
				cycle_target_previous()
		"target_nearest":
			# F2: hard nearest-enemy select (Tab is camera-relative).
			if pressed:
				_find_and_set_nearest_target()
				is_targeting = true
		"target_self":
			# F1: target yourself (healers/casters, self-buff flow).
			if pressed:
				TargetingManager.set_target(
					entity_id, "player", display_name, global_position, self, entity_type)
				is_targeting = true
		"interact":
			if pressed:
				_try_interact()
		"ability_1", "ability_2", "ability_3", "ability_4", \
		"ability_5", "ability_6", "ability_7", "ability_8":
			# Skill slots: keyboard 1-8 and touch skill buttons route here
			# through the same player_input signal.
			if pressed:
				var slot := int(action.replace("ability_", "")) - 1
				use_skill(slot)

## Interact (E / F / gamepad A / right-click): pick up the nearest
## ground drop in range, else activate a nearby ankh (bind respawn
## point). Objects declare themselves via groups ("ground_drops" are
## resolved by GroundLootService; ankhs by RespawnService).
func _try_interact() -> void:
	if GroundLootService and GroundLootService.has_method("try_pickup"):
		var picked: Array = GroundLootService.try_pickup(self)
		if not picked.is_empty():
			return
	_activate_nearby_ankh()
	_activate_nearby_ancient_door()
	_activate_nearby_concord_stone()

## Walk-over auto-loot. Enabled via Settings > Gameplay > Auto-loot
## Items (PlayerConfig "auto_loot"). Skipped entirely in full-loot PvP
## zones so looting a battlefield is always a deliberate act.
func _try_auto_loot() -> void:
	if GroundLootService == null or not GroundLootService.has_method("find_nearest_pickup"):
		return
	if PlayerConfig and not bool(PlayerConfig.get_account_setting("auto_loot", false)):
		return
	var zone_id := ""
	if ZoneManager != null and ZoneManager.has_method("get_entity_zone_id"):
		zone_id = str(ZoneManager.get_entity_zone_id(self))
	if zone_id != "" and ZoneManager.has_method("get_zone"):
		var zone = ZoneManager.get_zone(zone_id)
		if zone != null and "pvp_mode" in zone \
				and (zone.pvp_mode == ZoneData.PvPZoneMode.WARZONE \
					or zone.pvp_mode == ZoneData.PvPZoneMode.FREE_PVP):
			return
	if GroundLootService.find_nearest_pickup(self).is_empty():
		return
	GroundLootService.try_pickup(self)

## Bind to the closest ankh within activation range.
## Skyward Concord consumer: press E at an Ancient Door. Resolves the
## nearest "ancient_doors" group member the same way ankhs resolve.
## Sealed doors get a hint toast (how many glyphs the tribe has);
## unlocked doors play the open transition server-side.
func _activate_nearby_ancient_door() -> void:
	var doors := get_tree().get_nodes_in_group("ancient_doors")
	var best: Node3D = null
	var best_dist := INF
	for door in doors:
		if door == null or not is_instance_valid(door):
			continue
		var d: float = global_position.distance_to(door.global_position)
		if d < best_dist:
			best_dist = d
			best = door
	if best == null or best_dist > 4.0:
		return
	var result: Dictionary = best.try_interact(self)
	if NotificationService:
		NotificationService.notify(
			NotifKind.CUSTOM if bool(result.get("ok", false)) else NotifKind.SIGN_INSIGHT_RECORDED,
			str(result.get("message", "")),
			"AncientDoor",
			"ancient:interact:%s:%d" % [str(best.name), Time.get_ticks_msec()],
			{"door": str(best.name), "ok": bool(result.get("ok", false))}
		)


## Skyward Concord trigger: press E at a Concord Stone to record this
## window's insight. Resolves the nearest "concord_stones" group
## member exactly like ancient_doors; the stone returns the same
## {ok, message} contract so the toast pipeline is shared.
func _activate_nearby_concord_stone() -> void:
	var stones := get_tree().get_nodes_in_group("concord_stones")
	var best: Node3D = null
	var best_dist := INF
	for stone in stones:
		if stone == null or not is_instance_valid(stone):
			continue
		var d: float = global_position.distance_to(stone.global_position)
		if d < best_dist:
			best_dist = d
			best = stone
	if best == null or best_dist > 4.0:
		return
	var result: Dictionary = best.try_interact(self)
	if NotificationService:
		NotificationService.notify(
			NotifKind.CUSTOM if bool(result.get("ok", false)) else NotifKind.SIGN_INSIGHT_RECORDED,
			str(result.get("message", "")),
			"ConcordStone",
			"concord:%s:%d" % [str(best.name), Time.get_ticks_msec()],
			{"stone": str(best.name), "ok": bool(result.get("ok", false))}
		)


func _activate_nearby_ankh() -> void:
	var ankhs := get_tree().get_nodes_in_group("ankhs")
	var best: Node3D = null
	var best_dist := INF
	for ankh in ankhs:
		if ankh == null or not is_instance_valid(ankh):
			continue
		if ankh.has_method("is_within_activation_range") \
				and not ankh.is_within_activation_range(global_position):
			continue
		var dist: float = global_position.distance_to(ankh.global_position)
		if dist < best_dist:
			best_dist = dist
			best = ankh
	if best != null and best.has_method("bind_player"):
		if best.bind_player(self):
			GameLog.info("Bound to ankh: %s" % best.display_name)
			if is_instance_valid(NotificationService) and NotificationService.has_method("notify_ankh_bound"):
				NotificationService.notify_ankh_bound(entity_id, str(best.display_name))
		else:
			# Scoped ankhs explain themselves: guild/faction/personal
			# denials surface as toasts instead of failing silently.
			var reason: String = ""
			if best.has_method("describe_bind_denial"):
				reason = best.describe_bind_denial(self)
			GameLog.info("Cannot bind to ankh: %s (%s)" % [best.display_name, reason])
			if is_instance_valid(NotificationService) and NotificationService.has_method("notify"):
				NotificationService.notify(
					preload("res://core/notifications/notification_kind.gd").NotifKind.PLAYER_WARNED,
					"You cannot bind to %s yet. (%s)" % [str(best.display_name), reason],
					"PlayerController",
					"ankh_deny:%s:%s" % [str(best.ankh_id), reason],
					{}, entity_id)

## Cycle to next target (Tab)
func cycle_target() -> void:
	var camera := _get_camera()
	if not camera:
		return

	# Raycast in look direction to find targetable
	var look_dir := -camera.global_transform.basis.z
	var target_info: Variant = TargetingManager.get_target_in_direction(global_position, look_dir, 50.0)

	if target_info:
		TargetingManager.set_target(
			target_info.id,
			target_info.schema_id,
			target_info.display_name,
			target_info.world_position,
			target_info.node,
			target_info.entity_type
		)
		is_targeting = true
	else:
		# Find nearest targetable if raycast didn't hit
		_find_and_set_nearest_target()

## Cycle to previous target (Shift+Tab)
func cycle_target_previous() -> void:
	TargetingManager.restore_previous()

func _find_and_set_nearest_target() -> void:
	# Get all enemies and find nearest
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return

	# Sort by distance
	enemies.sort_custom(func(a, b):
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
	)

	# Target nearest
	var nearest = enemies[0]
	if nearest.has("entity_id"):
		TargetingManager.set_target(
			nearest.entity_id,
			"enemy",
			nearest.get("display_name") if nearest.get("display_name") != null else "Enemy",
			nearest.global_position,
			nearest,
			Entity.EntityType.ENEMY
		)
		is_targeting = true

## --- Combat surface (duck-typed Entity API) -----------------------------

## Receive damage from any combatant (enemies route here through
## EnemyAI._perform_attack and skill.gd's untyped take_damage).
func take_damage(amount: int, source = null, damage_type: String = "physical") -> int:
	if health_component == null:
		return 0
	var dealt: int = health_component.take_damage(amount, source, damage_type)
	if dealt > 0:
		health_changed.emit(current_health, max_health, -dealt)
		GameLog.info("Player hit: %d %s damage (HP %d/%d)" % [
			dealt, damage_type, health_component.current_health, health_component.max_health])
	return dealt

## Heal (skill.gd target.heal / self-heal path).
func heal(amount: int, source = null) -> int:
	if health_component == null:
		return 0
	return health_component.heal(amount, source)

signal health_changed(current: int, maximum: int, delta: int)
signal player_died(killer)

func is_dead() -> bool:
	return health_component != null and health_component.is_dead()

func get_attack_power() -> int:
	return get_stat("strength") * 2

func get_spell_power() -> int:
	return get_stat("intelligence") * 2

func get_healing_power() -> int:
	return get_stat("wisdom") * 2

func get_defense() -> int:
	return get_stat("vitality") * 2

func get_crit_chance() -> float:
	return 0.05 + (get_stat("agility") * 0.003)

func get_crit_multiplier() -> float:
	return 1.5

# --- Progression surface (duck-typed Entity API) --------------------------
# Mirrors PlayerManager's add_experience/add_gold so the XP/kill-reward
# hook (core/services/kill_rewards.gd) can pay any combatant through the
# same duck-typed convention as the combat surface above. The node-level
# values are authoritative for the player in the world; PlayerManager is
# the persistent mirror the HUD reads.

var experience: int = 0
var experience_to_next_level: int = 1000
var gold: int = 0

# Respawn cycle state parked here by RespawnService between the death
# signal and the delayed respawn execution. Declared on the node because
# GDScript 4 cannot add undeclared properties via dot-assignment: the
# service's `player._pending_respawn_mode_int = ...` used to fail with
# "Invalid assignment" and silently abort the service cycle (the legacy
# health timer then respawned the player instead, skipping the
# checkpoint and player_respawned broadcast).
var _pending_respawn_mode_int = null      # int(RespawnMode) or null
var _pending_respawn_position = null      # Vector3 or null
var _pending_respawn_choice: Dictionary = {}  # UI choice, consumed by the service

# Resource pool. Entity carries current_mana/max_mana; PlayerController
# (CharacterBody3D) never had one, so skill mana costs were silently
# skipped by the duck-typed cost checks and _consume_resources would
# have crashed writing to a nonexistent property.
var current_mana: int = 100
var max_mana: int = 100
var _mana_regen_accum: float = 0.0
var _void_recovery_cooldown: float = 0.0

signal experience_changed(current: int, level: int)
signal gold_changed(current: int)
signal leveled_up(new_level: int)
signal mana_changed(current: int, maximum: int)

func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	experience += amount
	while experience >= experience_to_next_level:
		experience -= experience_to_next_level
		level += 1
		experience_to_next_level = int(experience_to_next_level * 1.5)
		# Full restore on level up, mirroring PlayerManager.
		if health_component != null:
			max_health += 10
			current_health = max_health
		leveled_up.emit(level)
		GameLog.info("Player level up: now level %d" % level)
	experience_changed.emit(experience, level)

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)

func get_stat(stat_name: String) -> int:
	return int(stats.get(stat_name, 0))

## SKILL SYSTEM

## Populate the skillbar from the character's class data. The class
## schema (core/schemas/character_class.gd) declares starting_skills;
## DataService resolves the ids to loaded Skill resources. Was never
## called before, so the skillbar (and thus keys 1-8) started empty.
func _setup_starting_skills() -> void:
	if not skillbar.is_empty():
		return
	var class_data = null
	var char_data = GameManager.selected_character_data if is_instance_valid(GameManager) else null
	if char_data != null and "class_data" in char_data and char_data.class_data != null:
		class_data = char_data.class_data
	else:			# Boot paths without login (demo scene, showcases) run the
			# default class; CharacterData.class_id defaults to human_warrior.
		var class_id: String = "human_warrior"
		if char_data != null and "class_id" in char_data and str(char_data.class_id) != "":
			class_id = str(char_data.class_id)
		if is_instance_valid(DataService) and DataService.has_method("get_character_class"):
			class_data = DataService.get_character_class(class_id)
	# Keep can_cast's class gate consistent with the skillbar source.
	if class_data != null and "id" in class_data and str(class_data.id) != "":
		character_class = str(class_data.id)
	if class_data == null or not ("starting_skills" in class_data) \
			or class_data.starting_skills.is_empty():
		return
	for skill_id: String in class_data.starting_skills:
		if is_instance_valid(DataService) and DataService.has_method("get_skill"):
			var schema = DataService.get_skill(skill_id)
			if schema != null:
				# .tres skills load as SkillSchema; the skillbar + combat
				# pipeline run on the runtime Skill class.
				skillbar.append(Skill.from_schema(schema))
	if not skillbar.is_empty():
		GameLog.info("Player skillbar loaded: %d starting skill(s)" % skillbar.size())


func use_skill(slot: int) -> void:
	if slot < 0 or slot >= skillbar.size():
		return

	var skill: Skill = skillbar[slot]
	if skill and skill.can_cast(self):
		# Get target from TargetingManager
		var target: Node = null
		var target_info: Variant = TargetingManager.get_current_target()
		if target_info:
			target = target_info.node

		# Check if ground targeted
		if skill.is_ground_targeted:
			var ground_pos := _get_ground_target_position(skill.ground_target_range)
			CombatSystem.execute_skill(self, skill, null, ground_pos)
		else:
			CombatSystem.execute_skill(self, skill, target as Entity)

func _get_ground_target_position(max_range: float) -> Vector3:
	var direction: Vector2 = InputManager.last_direction
	if direction == Vector2.ZERO:
		direction = Vector2(0, -1)  # Default forward

	return CombatSystem.get_ground_target_position(self, direction, max_range)

## TARGETING

func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player:
		return

	# Left click - target entity
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(event.position)
		# Right click - clear target or context menu
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click()

	# Escape - clear target
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			clear_target()

func _handle_left_click(screen_pos: Vector2) -> void:
	var camera := _get_camera()
	if not camera:
		return

	# Raycast from camera
	var target_info: Variant = TargetingManager.raycast_from_camera(screen_pos, camera)

	if target_info:
		# Target the entity
		TargetingManager.set_target(
			target_info.id,
			target_info.schema_id,
			target_info.display_name,
			target_info.world_position,
			target_info.node,
			target_info.entity_type
		)
		is_targeting = true

		# Show tooltip if applicable
		_show_target_tooltip(target_info)
	else:
		# Clicked on nothing - clear target if not clicking on UI
		if not _is_click_on_ui(screen_pos):
			clear_target()

func _handle_right_click() -> void:
	if TargetingManager.has_target():
		var target_info = TargetingManager.get_current_target()
		_show_target_context_menu(target_info)

func clear_target() -> void:
	TargetingManager.clear_target()
	is_targeting = false
	_hide_target_tooltip()

func _get_camera() -> Camera3D:
	if camera_pivot and camera_pivot.get_child_count() > 0:
		var cam = camera_pivot.get_child(0)
		if cam is Camera3D:
			return cam
	return null

func _is_click_on_ui(screen_pos: Vector2) -> bool:
	var tree := get_tree()
	if not tree:
		return false
	var root := tree.root
	if not root:
		return false

	# Check for UI elements at position (group lookup belongs to the
	# SceneTree, not the root Window).
	var controls: Array = tree.get_nodes_in_group("clickable")
	for control in controls:
		if control is Control:
			var rect := Rect2(control.global_position, control.size)
			if rect.has_point(screen_pos):
				return true
	return false

func _show_target_tooltip(target_info: TargetingManager.TargetInfo) -> void:
	# Emit signal or show tooltip UI
	EventHub.entity_targeted.emit(entity_id, target_info.id, target_info.entity_type)

func _hide_target_tooltip() -> void:
	# Hide tooltip UI
	pass

## HITBOX & COMBAT

func create_hitbox(skill: Skill, target: Entity = null, ground_pos: Vector3 = Vector3.ZERO) -> void:
	CombatSystem.create_hitbox(self, skill, target, ground_pos)

func show_aoe_indicator(skill: Skill) -> void:
	# Visual indicator for ground-targeted AoE
	# Will be implemented with UI/VFX
	pass

func hide_aoe_indicator() -> void:
	pass

## STATE HELPERS

func get_look_direction() -> Vector3:
	if is_targeting and current_target:
		return (current_target.global_position - global_position).normalized()
	return -camera_pivot.global_transform.basis.z if camera_pivot else Vector3.ZERO

## MULTIPLAYER

@rpc("call_local")
func receive_position(pos: Vector3, rot: float) -> void:
	if is_local_player:
		return
	global_position = global_position.lerp(pos, 0.3)
	rotation.y = rot

@rpc("call_local")
func receive_animation(anim_name: String) -> void:
	if animation_player and animation_player.has_animation(anim_name):
		animation_player.play(anim_name)

func get_network_state() -> Dictionary:
	return {
		"position": global_position,
		"rotation": rotation.y,
		"velocity": velocity,
		"state": state_machine.get_state_name()
	}

func _open_report_dialog(target_id: String) -> void:
	var dialog := ReportDialog.new()
	add_child(dialog)
	dialog.open(str(player_id))
