## PlayerController - Main player character controller
## Free-form combat system (RYL2-style)
extends CharacterBody3D
class_name PlayerController

## Runtime autoload lookups (script-mode-safe; the bare identifiers
## fail compile when autoloads are absent -- test_islands).
func _ds() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("DataService")) if tree and tree.root else null

func _glog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

const _ac_script = preload("res://core/services/anticheat_service.gd")

## THE PROGRESSION RATIO LAW's preloads (mirror _pmgr()): the cap and the
## curve live in ONE authority; the node consults it, never forks it.
const LevelCurveScript = preload("res://core/progression/level_curve.gd")

## Runtime autoload lookup (script-mode-safe).
func _anti_cheat() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("AntiCheatService")) if tree and tree.root else null

func _im() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("InputManager")) if tree and tree.root else null

func _pmgr() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PlayerManager")) if tree and tree.root else null

func _tm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("TargetingManager")) if tree and tree.root else null

func _inv_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("InventoryService")) if tree and tree.root else null

func _il() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("InteractionLayer")) if tree and tree.root else null

func _chat_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("ChatService")) if tree and tree.root else null

func _party_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PartyService")) if tree and tree.root else null

func _guild_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GuildService")) if tree and tree.root else null

func _trade_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("TradeService")) if tree and tree.root else null

func _friends_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("FriendsService")) if tree and tree.root else null

func _loot_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("LootService")) if tree and tree.root else null

func _ground_loot() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GroundLootService")) if tree and tree.root else null

func _dialog_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("DialogService")) if tree and tree.root else null

func _mmgr() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var mm: Node = tree.root.get_node_or_null(NodePath("MenuManager"))
		if mm != null:
			return mm
	# Real client layout: MenuManager lives under the scene's HudLayer
	# (hud_integrator resolves it the same way). Without this fallback
	# every panel-opening context action silently no-op'd in scene runs.
	if tree != null and tree.current_scene != null:
		var hud: Node = tree.current_scene.get_node_or_null("HudLayer")
		if hud != null:
			return hud.get_node_or_null("MenuManager")
	return null

func _entity_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("EntityService")) if tree and tree.root else null

func _zone_mgr() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("ZoneManager")) if tree and tree.root else null

func _world_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("WorldService")) if tree and tree.root else null

func _notify_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("NotificationService")) if tree and tree.root else null

func _gm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameManager")) if tree and tree.root else null

func _lock_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PlayerLockService")) if tree and tree.root else null

func _follow_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("FollowService")) if tree and tree.root else null

func _pcfg() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PlayerConfig")) if tree and tree.root else null

func _a11y() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("A11yService")) if tree and tree.root else null

func _cs() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("CombatSystem")) if tree and tree.root else null

func _hub() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("EventHub")) if tree and tree.root else null

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
const WorkbenchUI = preload("res://ui/components/workbench_ui.gd")
# Named collision bits (round 10): data/physics_layers/ LayerProfile.
const Layers = preload("res://core/schemas/layer_profile.gd")
const CharacterStatsUI = preload("res://ui/menus/character_stats_ui.gd")
const GMIndicator = preload("res://entities/player/components/gm_indicator.gd")
const ReportDialog = preload("res://ui/player/report_dialog.gd")
const FloatingName = preload("res://entities/floating_name.gd")
const SkillAcademyUI = preload("res://ui/components/skill_academy_ui.gd")


# Movement
## Data-driven profile (Movement Design System). Speeds/gravity below
## are FALLBACKS only; _ready() resolves movement_standard from
## _ds() and overrides every field the profile defines. Editing
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

## Movement Design System: pull the profile from _ds() and stamp
## its values over the fallback exports. Profile fields only overwrite
## what they define (profiles are authoritative, exports are defaults).
## Species speed_modifier still multiplies on top via Entity stats.
func _apply_movement_profile() -> void:
	if _ds() == null:
		return
	var profile: MovementProfile = _ds().get_movement_profile(movement_profile_id)
	if profile == null:
		var gl := _glog()
		if gl:
			gl.warn("PlayerController: movement profile '%s' missing -- using built-in defaults" % movement_profile_id)
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
	var gl := _glog()
	if gl:
		gl.info("PlayerController: applied movement profile '%s'" % profile.id)


## Give _anti_cheat() the hard limits derived from THIS player's
## profile so movement validation always matches legal game feel (a
## .tres retune retunes the anticheat with it). GM characters exempt
## themselves here -- the service stays role-blind.
func _stamp_anticheat() -> void:
	if _anti_cheat() == null or entity_id.is_empty():
		return
	var profile: MovementProfile = null
	if _ds() != null:
		profile = _ds().get_movement_profile(movement_profile_id)
	if profile == null:
		# Built-in fallbacks mirror the historical defaults (5.0/10.0/10.0).
		_anti_cheat().set_movement_limits(entity_id, 25.0, 25.0, 110.0)
		return
	var char_data := _get_character_data()
	var gm: bool = char_data != null and char_data.is_gm()
	if gm:
		_anti_cheat().set_movement_exempt(entity_id, true)
		return
	var fastest_legal: float = maxf(profile.sprint_speed, profile.walk_speed * 1.9)
	_anti_cheat().set_movement_limits(
		entity_id,
		fastest_legal * _ac_script.SPEED_LIMIT_MULTIPLIER,
		profile.jump_force * _ac_script.JUMP_LIMIT_MULTIPLIER,
		profile.terminal_fall_speed * _ac_script.FALL_LIMIT_MULTIPLIER
	)


## Hitbox Profile System: resolve + apply the player collision shape.
## FAIRNESS RULE (species PvP): resolution goes through the species-fair
## path (_ds().resolve_player_hitbox_profile) so every playable
## species lands on the SAME profile. Species, sex, and body_type never
## scale or swap the player hitbox; hitbox_player.tres clamps scale to
## 1.0 hard, so even a bad future export cannot shrink or grow one
## species's capsule relative to another.
func _apply_hitbox_profile() -> void:
	if _ds() == null:
		return
	var species_id := "human"
	var char_data := _get_character_data()
	if char_data != null and not char_data.species_id.is_empty():
		species_id = char_data.species_id
	_hitbox_profile = _ds().resolve_player_hitbox_profile(species_id)
	if _hitbox_profile == null:
		var gl := _glog()
		if gl:
			gl.warn("PlayerController: hitbox profile missing -- keeping scene capsule")
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
	var gl := _glog()
	if gl:
		gl.info("PlayerController: applied hitbox profile '%s' (species-fair: %s)" % [_hitbox_profile.id, str(_hitbox_profile.pvp_fair)])


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
## _inv_svc()). Created in _ready -- every PlayerController gets
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
# EnemyAI, Skill, and _entity_svc() treat all combatants uniformly via this
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
# _entity_svc().is_enemy via `entity.faction`.
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
var _workbench_ui: WorkbenchUI = null
var _character_stats_ui: CharacterStatsUI = null
var _blessed_mark: Node3D = null
var _current_target_info: _tm_script.TargetInfo = null

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind
const _tm_script = preload("res://core/targeting/targeting_manager.gd")

## The blessed-class visual (prd-psy.md section 8): sky-cyan motes
## only while SignService says the class is the wheel's pick on an
## earned day. Idempotent -- the world scene also attaches directly.
func _attach_blessed_mark() -> void:
	if get_node_or_null("BlessedMark") != null:
		if _blessed_mark != null:
			_blessed_mark.set_wearer(character_class, self)
		return
	var mark_script = load("res://entities/blessed_mark.gd")
	if mark_script == null:
		return
	_blessed_mark = Node3D.new()
	_blessed_mark.name = "BlessedMark"
	_blessed_mark.set_script(mark_script)
	add_child(_blessed_mark)
	_blessed_mark.set_wearer(character_class, self)


## ---- Nameplate law (titles ride the name) --------------------------------
## Attach the player's floating plate: "[Prefix] Name, Suffix", tinted
## by the custom title color when one is set. Restamps on equip change
## (title_equipped/unequipped) so the world label never goes stale.
func _attach_floating_name() -> void:
	_refresh_floating_name()
	var svc := _titlesvc()
	if svc and svc.has_signal("title_equipped") \
			and not svc.title_equipped.is_connected(_on_title_state_changed):
		svc.title_equipped.connect(_on_title_state_changed)
	if svc and svc.has_signal("title_unequipped") \
			and not svc.title_unequipped.is_connected(_on_title_state_changed):
		svc.title_unequipped.connect(_on_title_state_changed)


func _on_title_state_changed(player_id: String, _title_id: String, _slot: String = "") -> void:
	if str(entity_id) != "" and player_id == str(entity_id):
		_refresh_floating_name()


func _refresh_floating_name() -> void:
	var cfg := {}
	var svc := _titlesvc()
	if svc:
		var color: Color = svc.call("get_title_color", str(entity_id))
		if color != Color(0, 0, 0):
			cfg["tint"] = color
	FloatingName.ensure(self, FloatingName.player_text(self), "player", cfg)


func _titlesvc() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and (ml as SceneTree).root:
		return (ml as SceneTree).root.get_node_or_null("TitleService")
	return null


func _ready() -> void:
	# Connect to input
	_im().player_input.connect(_on_player_input)
	_pmgr().set_local_player(self)
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
	# Combat effect stack (R28): GCD/casting component + aura tracker,
	# the same attach pattern the Entity families use.
	_ensure_effect_stack(true)
	# The blessed mark keys on the final class id (character data may
	# arrive after _ready, like the hitbox); call_deferred sees it.
	call_deferred("_attach_blessed_mark")
	# Floating plate likewise keys on final character data + TitleService
	# state; deferred attach restamps in place.
	call_deferred("_attach_floating_name")

	# Set collision (named bits, round 10): the body rides the entity
	# layer and collides with the whole world (entities, props, ground).
	collision_mask = Layers.group_mask("world")
	collision_layer = Layers.layer_bit("entity")

	# Initialize basic attack if null
	if basic_attack == null:
		basic_attack = _create_basic_attack()

	# Register with _tm()
	_tm().register_targetable(
		entity_id,
		"player",
		self,
		name,
		global_position,
		Entity.EntityType.PLAYER
	)

	# Set local player for _tm()
	_tm().set_local_player(entity_id)

	# Mirror the live targeting context so context-menu actions (Talk,
	# Trade->vendor shop, loot) can resolve NPC data/position. Without this
	# _current_target_info stayed null and NPC vendor routing silently fell
	# through to player-to-player trade.
	_tm().target_acquired.connect(_on_target_acquired)
	_tm().target_cleared.connect(_on_target_cleared)

	# Connect to _il() for touch targeting
	_connect_interaction_layer()

	# Health component: created here (not a scene child) so every
	# player gets one regardless of which scene instantiates them.
	if health_component == null:
		health_component = HealthComponent.new()
		health_component.max_health = max_health
		health_component.current_health = current_health
		add_child(health_component)

	# Inventory component: was never created for the local player, so
	# loot pickups had nowhere to land. Register with _inv_svc()
	# (GroundLootService routes pickups through it by entity_id).
	if inventory_component == null:
		inventory_component = InventoryComponent.new()
		inventory_component.name = "InventoryComponent"
		add_child(inventory_component)
	# Stable id BEFORE anything else keys off it: world_playable only fills
	# entity_id when it's still empty, so an int fallback here (str(1) -> "1")
	# used to win the race and desync _inv_svc()/_entity_svc()/quest
	# credit from the canonical "player_1". Use the scene-agnostic string id.
	var _inv_id := entity_id if entity_id != "" else LOCAL_PLAYER_ID
	if entity_id == "":
		entity_id = _inv_id
	inventory_component.set_owner_id(_inv_id)
	var inv_svc := _inv_svc()
	if inv_svc and inv_svc.has_method("register_inventory"):
		# ONE PURSE PER PLAYER (R48): adopt a live registration for this
		# id (a boot-restored wallet, or a purse registered before this
		# body's _ready) instead of clobbering it with a fresh empty bag
		# -- the clobber overwrote the registration and persisted the
		# empty bag over the player's real wallet. A freed stale
		# registration still yields to the fresh bag.
		var _existing_bag = _inv_svc().get_inventory(_inv_id) if _inv_svc().has_method("get_inventory") else null
		if _existing_bag != null and is_instance_valid(_existing_bag) and _existing_bag != inventory_component:
			inventory_component.queue_free()
			inventory_component = _existing_bag
		else:
			inv_svc.register_inventory(_inv_id, inventory_component)
	# THE ONE PURSE mirror: the adopted bag may already carry a
	# boot-restored wallet, so the mirror follows the purse from this
	# frame on (silently; the PURSE emits the rows).
		_wallet_swallow = true
		gold = int(inventory_component.get_gold())
		_wallet_swallow = false
	if inventory_component != null and not inventory_component.gold_changed.is_connected(_on_component_gold_changed_mirror):
		inventory_component.gold_changed.connect(_on_component_gold_changed_mirror)

	# Duck-typed respawn fields RespawnService/Ankh read (CharacterBody3D
	# has none of them natively; Ankh.bind_player sets respawn_ankh_id).
	respawn_ankh_id = ""
	respawn_point = global_position

	# Add GM indicator if this is a GM character
	_add_gm_indicator()

	var gl := _glog()
	if gl:
		gl.info("PlayerController ready")

func _add_gm_indicator() -> void:
	var char_data := _get_character_data()
	if char_data and char_data.is_gm():
		var indicator := GMIndicator.new()
		indicator.name = "GMIndicator"
		add_child(indicator)
		var gl := _glog()
		if gl:
			gl.info("Added GM star indicator")

func _connect_interaction_layer() -> void:
	if _il():
		_il().tap.connect(_on_interaction_tap)
		_il().double_tap.connect(_on_interaction_double_tap)
		_il().long_press.connect(_on_interaction_long_press)
		_il().action_triggered.connect(_on_interaction_action)

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
		var target_info: Variant = _tm().raycast_from_touch(position, camera)
		if target_info:
			_show_target_context_menu(target_info, position)

## Handle action triggers from _il()
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
	_tm().set_target(
		entity_id,
		"player",
		name,
		global_position,
		self,
		Entity.EntityType.PLAYER
	)
	is_targeting = false  # Self-target doesn't enable targeting mode

## Show target context menu. `at` positions the menu explicitly (the
## Interact path centers it on the viewport so touch/gamepad presses
## -- no live mouse cursor -- still land the menu on screen); the
## default keeps the long-press raycast behavior at the cursor.
func _show_target_context_menu(target_info: _tm_script.TargetInfo, at := Vector2(-1.0, -1.0)) -> void:
	match target_info.entity_type:
		Entity.EntityType.PLAYER:
			_show_player_context_menu(target_info, at)
		Entity.EntityType.NPC:
			_show_npc_context_menu(target_info, at)
		Entity.EntityType.LOOT:
			_show_loot_context_menu(target_info, at)
		Entity.EntityType.TELEPORT:
			_show_gateway_context_menu(target_info, at)

func _menu_pos(at: Vector2) -> Vector2:
	# The Interact path passes no cursor: center the menu so it opens
	# in the middle of the screen instead of a stale touch corner.
	var pos := get_viewport().get_visible_rect().size * 0.5
	if at.x >= 0.0:
		pos = at
	return pos

func _show_npc_context_menu(target_info: _tm_script.TargetInfo, at := Vector2(-1.0, -1.0)) -> void:
	if not _action_menu:
		_action_menu = ActionMenu.new()
		add_child(_action_menu)
		_action_menu.action_selected.connect(_on_context_action)
	_action_menu.show_menu(_menu_pos(at), target_info.id, target_info.entity_type, target_info.npc_data)

func _show_loot_context_menu(target_info: _tm_script.TargetInfo, at := Vector2(-1.0, -1.0)) -> void:
	if not _action_menu:
		_action_menu = ActionMenu.new()
		add_child(_action_menu)
		_action_menu.action_selected.connect(_on_context_action)
	_action_menu.show_menu(_menu_pos(at), target_info.id, target_info.entity_type)

func _show_gateway_context_menu(target_info: _tm_script.TargetInfo, at := Vector2(-1.0, -1.0)) -> void:
	if not _action_menu:
		_action_menu = ActionMenu.new()
		add_child(_action_menu)
		_action_menu.action_selected.connect(_on_context_action)
	_action_menu.show_menu(_menu_pos(at), target_info.id, target_info.entity_type)

func _show_player_context_menu(target_info, at := Vector2(-1.0, -1.0)) -> void:
	if not _action_menu:
		_action_menu = ActionMenu.new()
		add_child(_action_menu)
		_action_menu.action_selected.connect(_on_context_action)
	_action_menu.show_menu(_menu_pos(at), target_info.id, target_info.entity_type)

func _on_context_action(action_id: String, target_id: String) -> void:
	match action_id:
		"whisper":
			_chat_svc().send_whisper(player_id, target_id, "")
		"invite_party":
			if _party_svc(): _party_svc().invite_player(str(player_id), target_id)
		"invite_guild":
			if _guild_svc(): _guild_svc().invite_player(str(player_id), target_id)
		"trade":
			# NPC vendors open the shop panel; players open the trade panel.
			if _current_target_info and _current_target_info.id == target_id \
					and _current_target_info.entity_type == Entity.EntityType.NPC:
				_open_npc_vendor(target_id, _current_target_info)
			elif _trade_svc():
				_trade_svc().initiate_trade(str(player_id), target_id)
		"add_friend":
			if _friends_svc(): _friends_svc().send_friend_request(str(player_id), str(player_id), target_id)
		"report":
			_open_report_dialog(target_id)
		"talk":
			_open_npc_dialogue(target_id)
		"quest":
			_open_npc_quests(target_id)
		"bank":
			# The banker law: the vault opens at the banker (walk-away
			# close attaches here); hotkey/main-menu opens are gated on
			# proximity in MenuManager instead.
			if _mmgr():
				var bank_pos: Vector3 = Vector3.ZERO
				if _current_target_info and _current_target_info.id == target_id \
						and _current_target_info.entity_type == Entity.EntityType.NPC:
					bank_pos = _current_target_info.world_position
				_mmgr().open_menu("bank", bank_pos)
		"loot":
			_pickup_loot_target(target_id)
		"pass":
			if _loot_svc():
				_loot_svc().pass_loot(target_id, str(player_id))
		"enter":
			_activate_gateway_target(target_id)

		"skill_academy":
			_open_skill_academy_ui()
			_attach_npc_panel_proximity(_skill_academy_ui, target_id)
		"blacksmith":
			_open_blacksmith_ui()
			_attach_npc_panel_proximity(_blacksmith_ui, target_id)
		"premium":
			# The vault rides the MenuManager registry (banker law:
			# gates + the walk-away close attach to the NPC position).
			if _mmgr():
				var vault_pos: Vector3 = Vector3.ZERO
				if _current_target_info and _current_target_info.id == target_id \
						and _current_target_info.entity_type == Entity.EntityType.NPC:
					vault_pos = _current_target_info.world_position
				_mmgr().open_menu("premium", vault_pos)
		"craft":
			_open_workbench_ui()
		"character_stats":
			_open_character_stats_ui()

		# --- Ankh targeted law (action menu on the ankh itself) ---
		"ankh_set":
			_handle_ankh_action("bind", target_id)
		"ankh_info":
			_handle_ankh_action("info", target_id)
		# --- Bout stones (locator pass): route through TargetingManager
		# so the world menu and the HUD share one implementation.
		"queue_bout", "leave_bout_queue":
			_tm().execute_action_on(action_id, target_id)
		"check_lobby":
			if _mmgr().has_method("open_menu"):
				_mmgr().open_menu("lobby")

		# --- Player-to-player menu surface (view/Follow) ---
		"view_character":
			_open_player_inspect(target_id)
		"follow":
			_start_follow_target(target_id)
		"stop_follow":
			if _follow_svc():
				_follow_svc().stop_follow(str(player_id), "cancelled")


## The ankh targeted law: the action menu's Set-Ankh item binds the
## player to the targeted ankh (denial reasons surf to typed toasts,
## mirroring the proximity bind path); Ankh Info echoes the respawn
## info dictionary.
func _handle_ankh_action(kind: String, target_id: String) -> void:
	var tdata: Dictionary = _tm().get_targetable(target_id)
	var ankh: Node = tdata.get("node", null)
	if ankh == null or not is_instance_valid(ankh) or not ankh.has_method("bind_player"):
		var gl := _glog()
		if gl:
			gl.warn("PlayerController: ankh action %s on non-ankh target %s" % [kind, target_id])
		return
	if kind == "info" and ankh.has_method("get_respawn_info"):
		var info: Dictionary = ankh.call("get_respawn_info", self)
		var notif := _notify_svc()
		if notif != null and notif.has_method("notify"):
			notif.notify(
				NotifKind.CUSTOM,
				"%s (%s) -- respawn x%.2f in %s" % [
					ankh.display_name,
					info.get("ankh_type", "ANKH"),
					float(info.get("respawn_time_modifier", 1.0)),
					info.get("zone_id", "?")],
				"Ankh",
				"ankh_info:%s" % target_id,
				info)
		return
	# Bind (kind == "bind"): same denial vocabulary the proximity path
	# serves, so a refused bind toasts why instead of failing silently.
	var denial := ""
	if ankh.has_method("describe_bind_denial"):
		denial = str(ankh.call("describe_bind_denial", self))
	var ok := false
	var denial_msg := ""
	match denial:
		"":
			ok = bool(ankh.call("bind_player", self))
		"cooldown":
			denial_msg = "This ankh is still cooling down from your last bind."
		"dead":
			denial_msg = "You cannot bind while dead."
		"guild", "guild_rank":
			denial_msg = "This ankh answers only to its guild."
		"faction":
			denial_msg = "This ankh cannot serve your faction."
		"not_allowed":
			denial_msg = "This ankh is not yours to bind."
		"quest":
			denial_msg = "You have not earned the right to bind here yet."
		"level_low":
			denial_msg = "You are not ready to bind here yet."
		"level_high":
			denial_msg = "This ankh is beneath you."
		_:
			denial_msg = "This ankh resists your touch."
	var notif2 := _notify_svc()
	if notif2 != null and notif2.has_method("notify"):
		if ok:
			var bind_name := "Respawn point set"
			if "display_name" in ankh:
				bind_name = str(ankh.get("display_name"))
			notif2.notify(
				NotifKind.CUSTOM,
				"Respawn point set: %s. You will revive here." % bind_name,
				"Ankh",
				"ankh_bind:%s:ok" % target_id,
				{"ankh_id": target_id})
		else:
			notif2.notify(
				NotifKind.CUSTOM,
				denial_msg,
				"Ankh",
				"ankh_bind:%s:%s" % [target_id, denial],
				{"ankh_id": target_id, "reason": denial})


## Player-to-player menu actions: open the character panel in inspect
## mode for the target (capability-probed, mirroring the HUD path).
func _open_player_inspect(target_id: String) -> void:
	var mm := _mmgr()
	if mm == null:
		return
	if mm.has_method("open_character_inspect"):
		mm.call("open_character_inspect", target_id)
	elif mm.has_method("open_menu"):
		mm.open_menu("character")


## Follow a target player through FollowService (same call the HUD
## menu router makes).
func _start_follow_target(target_id: String) -> void:
	var fs := _follow_svc()
	if fs == null or PlayerManager == null:
		return
	var my_id := str(PlayerManager.get_local_player_id()) if PlayerManager.has_method("get_local_player_id") else str(player_id)
	var ok := bool(fs.call("request_follow", my_id, target_id))
	if not ok:
		var gl := _glog()
		if gl:
			gl.info("PlayerController: follow request failed for %s" % target_id)


## The NPC-panel attach law: a panel opened from an NPC's action menu
## binds to that NPC's position and auto-closes when the player walks
## away past the canonical interact radius (UIPanel, 12m). The same
## panel opened by hotkey/main menu (player skill management, K)
## stays unattached and works everywhere. ShopUI already follows this
## law via open_for_offering(npc_pos).
func _attach_npc_panel_proximity(panel: Node, target_id: String) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	if not "set_npc_proximity" in panel:
		return
	if _current_target_info == null or _current_target_info.id != target_id \
			or _current_target_info.entity_type != Entity.EntityType.NPC:
		return
	var npc_pos: Vector3 = _current_target_info.world_position
	if npc_pos == Vector3.ZERO and _current_target_info.node != null \
			and is_instance_valid(_current_target_info.node) \
			and _current_target_info.node is Node3D:
		npc_pos = (_current_target_info.node as Node3D).global_position
	if npc_pos != Vector3.ZERO:
		panel.call("set_npc_proximity", npc_pos)

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
		var gl := _glog()
		if gl:
			gl.warn("PlayerController: NPC %s has no dialogue offering" % target_id)
		return
	if _dialog_svc() and _dialog_svc().start_dialogue(target_id, dialogue_id):
		var gl := _glog()
		if gl:
			gl.info("PlayerController: dialogue started with %s (%s)" % [target_id, dialogue_id])
	else:
		var gl := _glog()
		if gl:
			gl.warn("PlayerController: failed to start dialogue %s" % dialogue_id)


## Open the QuestUI tab for an NPC's quest offering, if it has one.
func _open_npc_quests(target_id: String) -> void:
	var quest_ids := _npc_quest_ids_for_target(target_id)
	if quest_ids.is_empty():
		var gl := _glog()
		if gl:
			gl.warn("PlayerController: NPC %s has no quest offering" % target_id)
		return
	if _mmgr():
		_mmgr().open_menu("quests")
		var panel: Control = _mmgr().get_panel_node("quests")
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
			# Inline shape: quest_ids array. Ref shape: the ref_id IS the
			# quest id (data/quests/<ref_id>.tres carries it as its own
			# id; the blacksmith's "intro_core_npcs" include reads this
			# way and previously resolved to nothing, killing the
			# quests-panel context action silently).
			var qids: Variant = inc.get("quest_ids")
			if qids is Array:
				ids = qids
			elif str(inc.get("ref_id", "")) != "":
				ids = [str(inc.get("ref_id"))]
			if not ids.is_empty():
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
		var gl := _glog()
		if gl:
			gl.warn("PlayerController: NPC %s has no vendor offering" % target_id)
		return
	var npc_pos: Vector3 = target_info.world_position if target_info else Vector3.ZERO
	ShopUI.open_for_offering(str(player_id), vendor_offering, npc_data, npc_pos)



## Keep the context-action mirror of the current target in sync. These
## fire from _tm() whenever the player acquires/clears a
## target (long-press context menu, [E] interact, tab-targeting).
func _on_target_acquired(target: _tm_script.TargetInfo) -> void:
	if target != null:
		_current_target_info = target


func _on_target_cleared(_previous: _tm_script.TargetInfo) -> void:
	_current_target_info = null


## Resolve the live NPCData for a target id (entity node first, then
## the _tm() snapshot from the active context menu).
func _npc_data_for_target(target_id: String) -> NPCData:
	if _entity_svc():
		var npc: Variant = _entity_svc().get_entity(target_id)
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
	if _loot_svc() and _loot_svc().has_method("pickup_loot"):
		picked = _loot_svc().pickup_loot(pid, target_id)
	if picked.is_empty() and _ground_loot() and _ground_loot().has_method("try_pickup"):
		picked = _ground_loot().try_pickup(self, target_id)
	if picked.is_empty():
		var gl := _glog()
		if gl:
			gl.info("PlayerController: nothing to loot at %s" % target_id)


## Walk the player through a gateway via _world_svc().use_gateway.
func _activate_gateway_target(gateway_id: String) -> void:
	if not _world_svc():
		return
	var destination: Dictionary = _world_svc().use_gateway(gateway_id, self)
	if destination.is_empty():
		var gl := _glog()
		if gl:
			gl.warn("PlayerController: gateway %s cannot be used" % gateway_id)
		return
	if is_instance_valid(_notify_svc()):
		_notify_svc().notify(
			NotifKind.CUSTOM,
			"You pass through the gateway.",
			"PlayerController",
			"gw_use:%s:%s" % [str(player_id), gateway_id],
			{"gateway_id": gateway_id},
			str(player_id)
		)


func _get_character_data() -> CharacterData:
	if _gm() and is_instance_valid(_gm().selected_character_data):
		return _gm().selected_character_data as CharacterData
	return null

func _get_inventory_books() -> Array:
	var books: Array = []
	if _inv_svc():
		# get_player_items() never existed; the registered
		# InventoryComponent is the authoritative item store.
		var inv: InventoryComponent = _inv_svc().get_inventory(str(player_id))
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

## Open the crafting recipe table at the target NPC's station (the
## station law is DATA truth: npc_data.get_crafting_station, the
## offering's service_params.station). Every craft still executes
## through CraftingService.craft -- the UI owns no gate of its own.
func _open_workbench_ui() -> void:
	if not _workbench_ui:
		_workbench_ui = WorkbenchUI.new()
		add_child(_workbench_ui)
	var inventory: InventoryComponent = null
	if _inv_svc():
		inventory = _inv_svc().get_inventory(str(player_id))
	_workbench_ui.set_inventory(inventory)
	var station := -1
	if _current_target_info and _current_target_info.npc_data \
			and _current_target_info.npc_data.has_method("get_crafting_station"):
		station = _current_target_info.npc_data.get_crafting_station()
	_workbench_ui.open_for_player(str(player_id), station)

func _open_blacksmith_ui() -> void:
	if not _blacksmith_ui:
		_blacksmith_ui = BlacksmithUI.new()
		add_child(_blacksmith_ui)
	var inventory: InventoryComponent = null
	if _inv_svc():
		inventory = _inv_svc().get_inventory(str(player_id))
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
	if _lock_svc() and entity_id and _lock_svc().is_movement_blocked(entity_id):
		return

	# Handle follow mode - if following, auto-move to target
	if _follow_svc() and entity_id and _follow_svc().is_following(entity_id):
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
## One frame of movement telemetry to _anti_cheat(). The service
## owns the hard limits (stamped from our profile at spawn), the
## sustained-streak logic, and escalation; this is just the feed. Cheap
## by design: vector math + a Dictionary lookup, no allocation.
func _report_movement_frame(delta: float) -> void:
	if _anti_cheat() == null or entity_id.is_empty():
		return
	_anti_cheat().validate_movement(entity_id, global_position, velocity, delta)


func _exit_tree() -> void:
	# Drop per-player anticheat state (limits, streaks, exemption) so a
	# departed player's entry can't leak into a recycled entity id.
	if _anti_cheat() != null and not entity_id.is_empty():
		_anti_cheat().unregister_player(entity_id)


func _void_recovery(delta: float) -> void:
	if _void_recovery_cooldown > 0.0:
		_void_recovery_cooldown -= delta
		return
	if global_position.y >= void_kill_y:
		return
	_void_recovery_cooldown = 0.5
	var gl := _glog()
	if gl:
		gl.warn("Void recovery: %s fell out of the world" % entity_id)
	if is_instance_valid(_notify_svc()) and _notify_svc().has_method("notify"):
		_notify_svc().notify(
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
	if not _follow_svc() or not entity_id:
		return

	var target_pos: Vector3 = _follow_svc().get_target_position(entity_id)
	var distance: float = _follow_svc().get_distance_to_target(entity_id)
	var state: int = _follow_svc().get_follow_state(entity_id)

	if target_pos == Vector3.INF or distance < 0:
		return

	# Only actively move if catching up
	if state == _follow_svc().FollowState.CATCHING_UP:
		var direction: Vector3 = (target_pos - global_position).normalized()
		direction.y = 0  # Keep on ground

		# Apply speed boost for catching up
		var speed: float = move_speed * _follow_svc().DEFAULT_FOLLOW_SPEED_BUFF

		velocity = direction * speed
		move_and_slide()
	else:
		# Within threshold - just stand still
		velocity = Vector3.ZERO

func is_moving() -> bool:
	var input = _im().get_movement_input()
	return input.length() > 0.1

func get_movement_direction() -> Vector3:
	var input = _im().get_movement_input()
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
	var direction: Vector3 = (forward * input.y + right * input.x)
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
				_tm().set_target(
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

## THE INTERACT MENU (the missing loop beat): walk up to an NPC or a
## gate, press E / ACT / left-click -- the press TARGETS the nearest
## interactable still in range (a live Tab target in range wins) and
## opens ITS action menu centered on the screen. Picks up the whole
## context fan-out the long-press menu already drives, so a gate
## enters and the NPC offers Talk/Quests/Trade/Blacksmith from one
## consistent resolve. Returns true when a menu opened.
func _try_target_context_interact() -> bool:
	var tm := _tm()
	if tm == null:
		return false
	var types: Array[int] = [Entity.EntityType.NPC, Entity.EntityType.TELEPORT]
	var info = tm.get_nearest_targetable_by_types(global_position, types, INTERACT_MENU_RANGE)
	var cur = tm.get_current_target()
	if cur != null and types.has(cur.entity_type):
		# A live Tab/quick target in range outranks the nearest scan --
		# the player SAID who they meant.
		if is_instance_valid(cur.node) and cur.node is Node3D \
				and global_position.distance_to((cur.node as Node3D).global_position) <= INTERACT_MENU_RANGE:
			if "npc_data" in cur.node:
				cur.npc_data = cur.node.npc_data
			info = cur
	if info == null:
		return false
	if cur == null or cur.id != info.id:
		tm.set_target(
			info.id, info.schema_id, info.display_name, info.world_position,
			info.node, info.entity_type, info.metadata)
		info = tm.get_current_target()
	is_targeting = true
	_show_target_context_menu(info)
	return true

const INTERACT_MENU_RANGE := 6.0

## Interact (E / F / gamepad A / right-click): pick up the nearest
## ground drop in range, else use a nearby PLACED station (the
## walk-up-and-press law: DwellingService.resolve_nearby_station is
## the ONE resolving door; the bench opens at the station's own law),
## else activate a nearby ankh (bind respawn point). Objects declare
## themselves via groups ("ground_drops" are resolved by
## GroundLootService; placed stations by DwellingService; ankhs by
## RespawnService).
func _try_interact() -> void:
	if _ground_loot() and _ground_loot().has_method("try_pickup"):
		var picked: Array = _ground_loot().try_pickup(self)
		if not picked.is_empty():
			return
	# THE ACTION MENU first for NPCs/gates in arm's reach: this is the
	# walk-up-and-press loop beat the long-press raycast never carried
	# (no cursor needed -- near-est-in-range resolve + centered menu).
	if _try_target_context_interact():
		return
	if _use_nearby_placed_station():
		return
	_open_nearby_ship_dock()
	_activate_nearby_ankh()
	_activate_nearby_ancient_door()
	_activate_nearby_concord_stone()
	_activate_nearby_moon_gate()

## A placed crafting/repair station in range: open ITS UI at ITS
## station (repair -> BlacksmithUI; crafting_* -> WorkbenchUI at the
## STATION_FUNCTIONS id). Every craft still executes through
## CraftingService.craft -- the walk-up path is the same gate the NPC
## context action uses, just resolved by proximity instead of target.
func _use_nearby_placed_station() -> bool:
	var dw = get_node_or_null("/root/DwellingService")
	if dw == null or not dw.has_method("resolve_nearby_station"):
		return false
	var hit: Dictionary = dw.resolve_nearby_station(self)
	if not bool(hit.get("ok", false)):
		return false
	# The purse keys off the CANONICAL entity id (the id every service
	# registers under -- the int player_id's str() fallback "1" once
	# desynced the whole service family; see _ready's ONE PURSE law).
	var pid := entity_id if entity_id != "" else str(player_id)
	var inventory: InventoryComponent = null
	if _inv_svc():
		inventory = _inv_svc().get_inventory(pid)
	var function := str(hit.get("function", ""))
	if function == "blacksmith":
		# The home smithy: the plot host has no NPC pricing, so the
		# bench runs at face costs (1.0 modifier, no bulk discount).
		if not _blacksmith_ui:
			_blacksmith_ui = BlacksmithUI.new()
			add_child(_blacksmith_ui)
		_blacksmith_ui.set_inventory(inventory)
		_blacksmith_ui.open_for_player(pid)
		return true
	var stations: Dictionary = dw.STATION_FUNCTIONS if "STATION_FUNCTIONS" in dw else {}
	var station: int = int(stations.get(function, -1))
	if station < 0:
		return false
	if not _workbench_ui:
		_workbench_ui = WorkbenchUI.new()
		add_child(_workbench_ui)
	_workbench_ui.set_inventory(inventory)
	_workbench_ui.open_for_player(pid, station)
	return true

## Walk-up law for the sea: a SHIP-classed gateway pin in range opens
## the ferry dock panel (the moor pin is the dock face -- the panel
## scopes to the vessel whose route names that pin's shoreline, so a
## walk-up at the moor reads the barque's schedule, not whatever dict
## order says). One front-end, no side-doors: the dock's own Board/
## Charter presses route through the same gated chain the NPC fence
## opens. Gateways declare themselves on the WorldService registry
## (data/gateways/*.tres: the SHIP gateway_type = 4 arrows), so the
## E-interact resolves against the same data truth the probe pinned.
func _open_nearby_ship_dock() -> void:
	var ws = get_node_or_null("/root/WorldService")
	if ws == null or not ws.has_method("get_nearby_gateway"):
		return
	var gw = ws.get_nearby_gateway(self)
	if gw == null or not ("gateway_type" in gw) or int(gw.gateway_type) != 4:
		return
	var mm = get_node_or_null("/root/MenuManager")
	if mm != null:
		mm.open_menu("dock")
	var dock_panel = mm.get_panel_node("dock") if mm else null
	if dock_panel != null and dock_panel.has_method("open_for_player"):
		# THE PIN LAW (the harbor callers law): the dock resolves its
		# lines from the PIN's own data truth -- a shared harbor pin
		# fronts every route naming it (the capitol pier carries two
		# lines now; the dock cycles them). No pin-to-boat table.
		dock_panel.pin_gateway_id = str(gw.id)
		dock_panel.open_for_player(entity_id if entity_id != "" else str(player_id))

## The vessel a dock pin fronts: the ferry whose ROUTE names the pin
## (moor/seaward -> the Sundered Barque; village/capitol pier -> the
## Haven Ferry; village/island dock -> the Island Ferry). One truth
## door: the pin id only resolves through a vehicle's data-truth
## route gateways -- no pin-to-boat lookup table to drift.
func _dock_vehicle_for_pin(gateway_pin_id: String) -> String:
	var ds = get_node_or_null("/root/DataService")
	if ds == null:
		return ""
	for v in ds.get_all_vehicles():
		if v == null or int(v.ferries_per_day) <= 0:
			continue
		for port in v.route_gateways:
			if str(port) == gateway_pin_id:
				return str(v.id)
	return ""

## Walk-over auto-loot. Enabled via Settings > Gameplay > Auto-loot
## Items (_pcfg() "auto_loot"). Skipped entirely in full-loot PvP
## zones so looting a battlefield is always a deliberate act.
func _try_auto_loot() -> void:
	if _ground_loot() == null or not _ground_loot().has_method("find_nearest_pickup"):
		return
	if _pcfg() and not bool(_pcfg().get_account_setting("auto_loot", false)):
		return
	var zone_id := ""
	if _zone_mgr() != null and _zone_mgr().has_method("get_entity_zone_id"):
		zone_id = str(_zone_mgr().get_entity_zone_id(self))
	if zone_id != "" and _zone_mgr().has_method("get_zone"):
		var zone = _zone_mgr().get_zone(zone_id)
		if zone != null and "pvp_mode" in zone \
				and (zone.pvp_mode == ZoneData.PvPZoneMode.WARZONE \
					or zone.pvp_mode == ZoneData.PvPZoneMode.FREE_PVP):
			return
	if _ground_loot().find_nearest_pickup(self).is_empty():
		return
	_ground_loot().try_pickup(self)

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
	if _notify_svc():
		_notify_svc().notify(
			NotifKind.CUSTOM if bool(result.get("ok", false)) else NotifKind.SIGN_INSIGHT_RECORDED,
			str(result.get("message", "")),
			"AncientDoor",
			"ancient:interact:%s:%d" % [str(best.name), Time.get_ticks_msec()],
			{"door": str(best.name), "ok": bool(result.get("ok", false))}
		)


## Traversal trigger (labs/prd-multiworld.md sec 3): press E at a
## Moon Gate. Resolves the nearest "moon_gates" group member exactly
## like ancient_doors; the gate returns the same {ok, message}
## contract so the toast pipeline is shared.
func _activate_nearby_moon_gate() -> void:
	var gates := get_tree().get_nodes_in_group("moon_gates")
	var best: Node3D = null
	var best_dist := INF
	for gate in gates:
		if gate == null or not is_instance_valid(gate):
			continue
		var d: float = global_position.distance_to(gate.global_position)
		if d < best_dist:
			best_dist = d
			best = gate
	if best == null or best_dist > 4.0:
		return
	var result: Dictionary = best.try_interact(self)
	if _notify_svc():
		_notify_svc().notify(
			NotifKind.CUSTOM if bool(result.get("ok", false)) else NotifKind.SIGN_INSIGHT_RECORDED,
			str(result.get("message", "")),
			"MoonGate",
			"moon_gate:%s:%d" % [str(best.name), Time.get_ticks_msec()],
			{"gate": str(best.name), "ok": bool(result.get("ok", false))}
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
	if _notify_svc():
		_notify_svc().notify(
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
			var gl := _glog()
			if gl:
				gl.info("Bound to ankh: %s" % best.display_name)
			if is_instance_valid(_notify_svc()) and _notify_svc().has_method("notify_ankh_bound"):
				_notify_svc().notify_ankh_bound(entity_id, str(best.display_name))
		else:
			# Scoped ankhs explain themselves: guild/faction/personal
			# denials surface as toasts instead of failing silently.
			var reason: String = ""
			if best.has_method("describe_bind_denial"):
				reason = best.describe_bind_denial(self)
			var gl := _glog()
			if gl:
				gl.info("Cannot bind to ankh: %s (%s)" % [best.display_name, reason])
			if is_instance_valid(_notify_svc()) and _notify_svc().has_method("notify"):
				_notify_svc().notify(
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
	var target_info: Variant = _tm().get_target_in_direction(global_position, look_dir, 50.0)

	if target_info:
		_tm().set_target(
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
	_tm().restore_previous()

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
	# `in` is the property-existence operator; `nearest.has("entity_id")` was a
	# call to a method Node3D does not have, so it threw and F2 never targeted.
	if "entity_id" in nearest:
		_tm().set_target(
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
		# Emit the health_component truth, not the stale local field --
		# the component owns the damage path (same dual-store miss the
		# Enemy fix closed; R37 audit).
		health_changed.emit(health_component.current_health, health_component.max_health, -dealt)
		_glog().info("Player hit: %d %s damage (HP %d/%d)" % [
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
# Mirrors _pmgr()'s add_experience/add_gold so the XP/kill-reward
# hook (core/services/kill_rewards.gd) can pay any combatant through the
# same duck-typed convention as the combat surface above. The node-level
# values are authoritative for the player in the world; _pmgr() is
# the persistent mirror the HUD reads.

var experience: int = 0
var experience_to_next_level: int = 1000
# THE ONE PURSE (unified wallet law): the mounted InventoryComponent is
# the authoritative wallet for this player; `gold` is its synced mirror
# (persistence, HUD, and duck-typed payers read it). Direct writes to
# `gold` (restore, horde shares, dwelling spends) convert into REAL
# deltas in the component purse, so every payment speaks through the
# ONE wallet-voice lane instead of a silent field write.
var _wallet_swallow: bool = false

var gold: int = 0:
	set(value):
		var v := maxi(0, int(value))
		if _wallet_swallow:
			gold = v
			return
		var comp: Variant = null
		if "inventory_component" in self:
			comp = self.get("inventory_component")
		if comp != null and is_instance_valid(comp) and comp.has_method("add_gold"):
			var current := int(comp.get_gold())
			if v > current:
				comp.add_gold(v - current)
				_wallet_swallow = true
				gold = int(comp.get_gold())
				_wallet_swallow = false
				return
			if v < current and comp.has_method("remove_gold"):
				if comp.remove_gold(current - v):
					_wallet_swallow = true
					gold = int(comp.get_gold())
					_wallet_swallow = false
					return
				# The purse refused (fresh body adopted a richer bag,
				# then a stale restore wanted less). Keep the mirror in
				# sync with the truth the purse holds.
			_wallet_swallow = true
			gold = int(comp.get_gold()) if comp != null and is_instance_valid(comp) else v
			_wallet_swallow = false
			return
		gold = v
		gold_changed.emit(v)

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
	# THE CAP LAW mirrors _pmgr() (#54): the node never encodes the cap --
	# LevelCurve is the ONE authority. Overflow XP past the cap banks (the
	# experience field keeps its value; no level, no stat, no heal), so a
	# seasonal cap raise pays out from what the body already banked.
	while experience >= experience_to_next_level \
			and level < LevelCurveScript.max_level():
		experience -= experience_to_next_level
		level += 1
		# The curve (not a compounding drift) owns the next level's cost: a
		# body AT `level` carries level_cost(level) -- the level_curve
		# docstring law, byte-equal to the shipped 1.5^n band pin the quest
		# authors assume. (#54: the old inline int(1.5x) compounding never
		# consulted the cap and unstoppered past-band growth.)
		experience_to_next_level = LevelCurveScript.level_cost(level)
		# Full restore on level up, mirroring _pmgr().
		if health_component != null:
			max_health += 10
			# Sync into the component: it owns the damage/heal path, so
			# the bump must land where take_damage actually reads
			# (dual-store hygiene, R37 audit).
			health_component.max_health = max_health
			current_health = max_health
			health_component.current_health = current_health
		leveled_up.emit(level)
		var gl := _glog()
		if gl:
			gl.info("Player level up: now level %d" % level)
	experience_changed.emit(experience, level)

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	# THE ONE PURSE: when the component wallet is mounted, it is the
	# authoritative purse and its gold_changed is the ONE speak lane --
	# the mirror just follows (no duplicate node emit). Standalone
	# bodies (probes, unmounted stubs) keep their own voice.
	var comp: Variant = null
	if "inventory_component" in self:
		comp = self.get("inventory_component")
	if comp != null and is_instance_valid(comp) and comp.has_method("add_gold"):
		comp.add_gold(amount)
		return
	gold += amount
	gold_changed.emit(gold)

## Duck-typed currency surface (the ONE purse for every currency).
## Prefer the component when mounted; standalone bodies keep an
## honest zero (never invent balance).
func get_currency_amount(currency_id: String) -> int:
	var comp: Variant = null
	if "inventory_component" in self:
		comp = self.get("inventory_component")
	if comp != null and is_instance_valid(comp) and comp.has_method("get_currency_amount"):
		return int(comp.get_currency_amount(currency_id))
	return 0

func add_currency(currency_id: String, amount: int) -> bool:
	var comp: Variant = null
	if "inventory_component" in self:
		comp = self.get("inventory_component")
	if comp != null and is_instance_valid(comp) and comp.has_method("add_currency"):
		return bool(comp.add_currency(currency_id, amount))
	return false

func remove_currency(currency_id: String, amount: int) -> bool:
	var comp: Variant = null
	if "inventory_component" in self:
		comp = self.get("inventory_component")
	if comp != null and is_instance_valid(comp) and comp.has_method("remove_currency"):
		return bool(comp.remove_currency(currency_id, amount))
	return false

## Mirror-sync leg: the component purse was paid/spent through a path
## that does not touch the node (vendors, restores into the adopted
## bag, vault transfers). Keep `gold` equal to the truth the purse
## holds -- silently; the PURSE emits the roster rows.
func _on_component_gold_changed_mirror(_delta: int) -> void:
	var comp: Variant = null
	if "inventory_component" in self:
		comp = self.get("inventory_component")
	if comp == null or not is_instance_valid(comp):
		return
	_wallet_swallow = true
	gold = int(comp.get_gold())
	_wallet_swallow = false

func get_stat(stat_name: String) -> int:
	return int(stats.get(stat_name, 0))

## Entity-parity stat surface. PlayerController extends CharacterBody3D, not
## Entity, so it lacked the get_stat/set_stat pair that InventoryComponent's
## _apply_equipment_stats drives: equipping gear threw a missing-method error
## and moved no attributes. set_stat is deliberately silent -- the player has
## no stat_changed listener, so emitting one (which KillRewards would also do
## for "xp") would be a zero-listener signal under the no-void law.
func set_stat(stat_name: String, value: int) -> void:
	stats[stat_name] = value

func add_stat(stat_name: String, amount: int) -> void:
	set_stat(stat_name, get_stat(stat_name) + amount)

## SKILL SYSTEM

## Populate the skillbar from the character's class data. The class
## schema (core/schemas/character_class.gd) declares starting_skills;
## _ds() resolves the ids to loaded Skill resources. Was never
## called before, so the skillbar (and thus keys 1-8) started empty.
func _setup_starting_skills() -> void:
	if not skillbar.is_empty():
		return
	var class_data = null
	var char_data = _gm().selected_character_data if is_instance_valid(_gm()) else null
	if char_data != null and "class_data" in char_data and char_data.class_data != null:
		class_data = char_data.class_data
	else:			# Boot paths without login (demo scene, showcases) run the
			# default class; CharacterData.class_id defaults to human_warrior.
		var class_id: String = "human_warrior"
		if char_data != null and "class_id" in char_data and str(char_data.class_id) != "":
			class_id = str(char_data.class_id)
		if is_instance_valid(_ds()) and _ds().has_method("get_character_class"):
			class_data = _ds().get_character_class(class_id)
	# Keep can_cast's class gate consistent with the skillbar source.
	if class_data != null and "id" in class_data and str(class_data.id) != "":
		character_class = str(class_data.id)
	if class_data == null or not ("starting_skills" in class_data) \
			or class_data.starting_skills.is_empty():
		return
	for skill_id: String in class_data.starting_skills:
		if is_instance_valid(_ds()) and _ds().has_method("get_skill"):
			var schema = _ds().get_skill(skill_id)
			if schema != null:
				# .tres skills load as SkillSchema; the skillbar + combat
				# pipeline run on the runtime Skill class.
				skillbar.append(Skill.from_schema(schema))
	if not skillbar.is_empty():
		var gl := _glog()
		if gl:
			gl.info("Player skillbar loaded: %d starting skill(s)" % skillbar.size())


## COMBAT EFFECT STACK (R28)
# Status-effect surface mirroring Entity's block so live DoTs/CCs can
# land on the player (the hitbox sweep calls target.apply_status_effect
# on whichever family it hits).
const AuraComponentScript = preload("res://core/components/aura_component.gd")
const CombatComponentScript = preload("res://core/components/combat_component.gd")

var status_effects: Array = []
var aura_component = null
var combat_component = null

func _ensure_effect_stack(with_combat: bool = false) -> void:
	if aura_component == null:
		aura_component = AuraComponentScript.new()
		add_child(aura_component)
	if with_combat and combat_component == null:
		combat_component = CombatComponentScript.new()
		add_child(combat_component)

func apply_status_effect(effect) -> void:
	if effect == null or effect.is_expired():
		return
	status_effects.append(effect)
	effect.apply(self)
	# effect_expired is a no-arg signal; bind the effect so the handler
	# receives it (same reasoning as Entity).
	effect.effect_expired.connect(_on_status_effect_expired.bind(effect))
	# Ticks apply through StatusEffect._apply_tick_effect (R31 canonical:
	# duck-typed take_damage/heal with the effect's source). No local
	# tick_occurred connect -- a handler here would DOUBLE-apply damage.

func _on_status_effect_expired(effect) -> void:
	status_effects.erase(effect)
	if aura_component:
		aura_component.untrack_effect(effect)

func remove_status_effect(effect) -> void:
	if status_effects.has(effect):
		effect.remove(self)
		status_effects.erase(effect)
		if aura_component:
			aura_component.untrack_effect(effect)

func clear_all_status_effects() -> void:
	for effect in status_effects:
		effect.remove(self)
		if aura_component:
			aura_component.untrack_effect(effect)
	status_effects.clear()


func use_skill(slot: int) -> void:
	if slot < 0 or slot >= skillbar.size():
		return

	var skill: Skill = skillbar[slot]
	if skill and skill.can_cast(self):
		# Get target from _tm()
		var target: Node = null
		var target_info: Variant = _tm().get_current_target()
		if target_info:
			target = target_info.node

		# Route through the component when present (GCD, casting state,
		# anticheat); it forwards the hitbox family to _cs() itself,
		# so the live execution path is unchanged.
		if combat_component:
			if skill.is_ground_targeted:
				combat_component.execute_skill(skill, null, _get_ground_target_position(skill.ground_target_range))
			else:
				combat_component.execute_skill(skill, target)
			return

		# Legacy fallback (no component attached)
		if skill.is_ground_targeted:
			var ground_pos := _get_ground_target_position(skill.ground_target_range)
			_cs().execute_skill(self, skill, null, ground_pos)
		else:
			_cs().execute_skill(self, skill, target as Entity)

func _get_ground_target_position(max_range: float) -> Vector3:
	var direction: Vector2 = _im().last_direction
	if direction == Vector2.ZERO:
		direction = Vector2(0, -1)  # Default forward

	return _cs().get_ground_target_position(self, direction, max_range)

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
	var target_info: Variant = _tm().raycast_from_camera(screen_pos, camera)

	if target_info:
		# Target the entity
		_tm().set_target(
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
	if _tm().has_target():
		var target_info = _tm().get_current_target()
		_show_target_context_menu(target_info)

func clear_target() -> void:
	_tm().clear_target()
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

func _show_target_tooltip(target_info: _tm_script.TargetInfo) -> void:
	# Emit signal or show tooltip UI
	var hub := _hub()
	if hub: hub.emit_signal("entity_targeted", entity_id, target_info.id, target_info.entity_type)

func _hide_target_tooltip() -> void:
	# Hide tooltip UI
	pass

## HITBOX & COMBAT

func create_hitbox(skill: Skill, target: Entity = null, ground_pos: Vector3 = Vector3.ZERO) -> void:
	_cs().create_hitbox(self, skill, target, ground_pos)

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
