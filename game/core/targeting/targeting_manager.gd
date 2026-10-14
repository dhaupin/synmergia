## TargetingManager - Unified targeting system
## Single source of truth for all targeting operations
##
## Features:
## - Data-driven via TargetSchema (.tres files)
## - Schema caching with memoization
## - EventBus integration for entity registration
## - Action execution with _perm_svc()
## - 3D highlight management
## - Target history (restore previous)
extends Node

# Entity is not an autoload (class_name only). TargetingManager
# references Entity.EntityType.X in several places, which requires
# Entity's class_name to be registered at parse time. Preload it
# here -- no shadow: Entity is a class_name, not an autoload.
const Entity = preload("res://core/entities/entity.gd")

## Tree-safe GameLog lookup (script-mode-safe; the bare identifier
## fails compile when autoloads are absent -- test_islands).
func _glog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

func _hub() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("EventHub")) if tree and tree.root else null

func _respawn_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("RespawnService")) if tree and tree.root else null

func _chat_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("ChatService")) if tree and tree.root else null

func _party_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PartyService")) if tree and tree.root else null

func _guild_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GuildService")) if tree and tree.root else null

func _friends_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("FriendsService")) if tree and tree.root else null

func _trade_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("TradeService")) if tree and tree.root else null

func _duel_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("DuelService")) if tree and tree.root else null

func _perm_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PermissionManager")) if tree and tree.root else null

func _admin_cmds() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("AdminCommands")) if tree and tree.root else null

func _pm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PlayerManager")) if tree and tree.root else null



# PlayerController resolves through its GLOBAL class_name, not a
# const preload: player_controller.gd preloads targeting_manager back
# (the camera/targeting bridge), so this const preload closed the
# graph's last cyclic edge (the lint's 2-node WARN). Type usages below
# (`is PlayerController`) belong to the global script registry.
const SpawnMetadata = preload("res://core/events/spawn_metadata.gd")
const NPCData = preload("res://core/schemas/npc_data.gd")
const TargetSchema = preload("res://core/schemas/target_schema.gd")
## Named collision bits (round 10): data/physics_layers/ LayerProfile.
const Layers = preload("res://core/schemas/layer_profile.gd")
## ============================================================================
## SINGLETON
## ============================================================================

static var instance: TargetingManager

static func singleton() -> TargetingManager:
	return instance

## ============================================================================
## SIGNALS
## ============================================================================

signal target_acquired(target: TargetInfo)
signal target_cleared(previous_target: TargetInfo)
signal target_updated(target: TargetInfo)
signal target_type_changed(entity_type: int)
signal action_executed(action_id: String, target_id: String, result: Dictionary)
signal action_blocked(action_id: String, target_id: String, reason: String)

## ============================================================================
## TARGET INFO (runtime object)
## ============================================================================

class TargetInfo:
	var id: String = ""
	var schema_id: String = ""
	var entity_type: int = 0  # Uses Entity.EntityType bitflags
	var display_name: String = ""
	var position: Vector3 = Vector3.ZERO
	var world_position: Vector3 = Vector3.ZERO  # For 3D highlighting
	var node: Node = null
	var metadata: Dictionary = {}
	var npc_data: NPCData = null  # Populated if entity_type == NPC

	# Computed from schema
	var actions: Array[String] = []
	var highlight_color: Color = Color(1.0, 0.8, 0.0)
	var highlight_size: float = 1.0

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"schema_id": schema_id,
			"entity_type": entity_type,
			"name": display_name,
			"position": position,
			"world_position": world_position,
			"metadata": metadata
		}

## ============================================================================
## ACTION DEFINITIONS
## ============================================================================

class ActionDef:
	var id: String
	var name: String
	var icon: String  # Emoji or icon name
	var category: ActionCategory
	var min_permission_level: int
	var requires_target_online: bool
	var requires_target_alive: bool
	var callback: Callable

	enum ActionCategory {
		SOCIAL,        # Available to all
		VIP_SOCIAL,    # Requires VIP
		MODERATION,    # Requires MOD
		ADMIN,         # Requires ADMIN
		INTERACTION,   # General interactions
	}

	func _init(p_id: String, p_name: String, p_icon: String, p_category: ActionCategory,
			p_callback: Callable, p_requires_online: bool = true,
			p_requires_alive: bool = true, p_min_level: int = 0):
		id = p_id
		name = p_name
		icon = p_icon
		category = p_category
		callback = p_callback
		requires_target_online = p_requires_online
		requires_target_alive = p_requires_alive
		min_permission_level = p_min_level

## ============================================================================
## STATE
## ============================================================================

## Current target
var _current_target: TargetInfo = null

## Target history (for restore)
var _target_history: Array[TargetInfo] = []
const MAX_HISTORY: int = 10

## Allowed entity types (bitmask)
var _allowed_types: int = Entity.EntityType.ALL

## Selection mode
var _selection_mode: TargetSchema.SelectionMode = TargetSchema.SelectionMode.SINGLE

## Local player ID (for permission checks)
var _local_player_id: String = ""

## Current 3D highlight node
var _highlight_node: Node3D = null

## ============================================================================
## SCHEMA CACHE (data-driven)
## ============================================================================

var _schema_cache: Dictionary = {}  # schema_id -> TargetSchema
var _entity_type_to_schema: Dictionary = {}  # entity_type -> schema_id
var _triggers_by_target: Dictionary = {}  # target_id -> [objective_ids] (for future ObjectiveManager)

## ============================================================================
## ACTION REGISTRY
## ============================================================================

var _actions: Dictionary = {}  # action_id -> ActionDef
var _actions_by_category: Dictionary = {}  # category -> [action_ids]

## ============================================================================
## TARGETABLE ENTITIES
## ============================================================================

var _targetables: Dictionary = {}  # entity_id -> {schema_id, node, position, name, entity_type}

## Look up a registered targetable by entity id. Returns the underlying node
## so callers can access domain-specific properties (e.g. health_component).
func get_entity_by_id(entity_id: String) -> Node:
	if entity_id == "" or not _targetables.has(entity_id):
		return null
	var info: Dictionary = _targetables[entity_id]
	return info.get("node", null)

## ============================================================================
## 3D HIGHLIGHT SYSTEM
## ============================================================================

var _highlight_mesh: MeshInstance3D = null
var _highlight_tween: Tween = null
var _highlight_pulse_enabled: bool = true
var _highlight_layer: int = 0xFFFFFFFF  # Layer for highlights

## ============================================================================
## LIFECYCLE
## ============================================================================

func _ready() -> void:
	instance = self

	# Load schemas
	_load_schemas()

	# Register default actions
	_register_default_actions()

	# Connect to EventBus for entity registration
	_connect_eventbus()

	var _glt := _glog()
	if _glt: _glt.info("TargetingManager: Initialized with %d schemas, %d actions" % [
		_schema_cache.size(), _actions.size()
	])

func _connect_eventbus() -> void:
	var hub := _hub()
	if hub:
		# Entity events
		hub.entity_spawned.connect(_on_entity_spawned)
		hub.entity_despawned.connect(_on_entity_despawned)
		hub.entity_died.connect(_on_entity_died)

		# Combat events
		hub.skill_executed.connect(_on_skill_executed)

## ============================================================================
## SCHEMA LOADING
## ============================================================================

const ResourceScan = preload("res://core/frame/srv/resource_scan.gd")

func _load_schemas() -> void:
	var schema_dir := "res://data/targets/"
	# Export-safe scan: the pack stores .tres as .res + .tres.remap.
	var paths := ResourceScan.list_resources(schema_dir)
	if paths.is_empty() and DirAccess.open(schema_dir) == null:
		var _glt := _glog()
		if _glt:
			_glt.warn("TargetingManager: Cannot open schema directory: " + schema_dir)
		return
	for p in paths:
		var schema: TargetSchema = load(p)
		if schema and schema.id != "":
			_schema_cache[schema.id] = schema
			_entity_type_to_schema[schema.entity_type] = schema.id
			var _glt := _glog()
			if _glt:
				_glt.debug("TargetingManager: Loaded schema: " + schema.id)

## Get schema by ID (with caching)
func get_schema(schema_id: String) -> TargetSchema:
	if schema_id == "":
		return null

	if not _schema_cache.has(schema_id):
		# Lazy load
		var schema_path := "res://data/targets/target_%s.tres" % schema_id
		var schema: TargetSchema = load(schema_path)
		if schema:
			_schema_cache[schema_id] = schema

	return _schema_cache.get(schema_id)

## Get schema for entity type
func get_schema_for_entity_type(entity_type: int) -> TargetSchema:
	var schema_id = _entity_type_to_schema.get(entity_type, "")
	return get_schema(schema_id)

## ============================================================================
## ACTION REGISTRATION
## ============================================================================

func register_action(action: ActionDef) -> void:
	_actions[action.id] = action

	if not _actions_by_category.has(action.category):
		_actions_by_category[action.category] = []
	_actions_by_category[action.category].append(action.id)

func _register_default_actions() -> void:
	# === SOCIAL ACTIONS ===
	register_action(ActionDef.new(
		"whisper", "Whisper", "",
		ActionDef.ActionCategory.SOCIAL,
		func(src, tgt): return _action_whisper(src, tgt)
	))

	register_action(ActionDef.new(
		"invite_party", "Invite to Party", "",
		ActionDef.ActionCategory.SOCIAL,
		func(src, tgt): return _action_invite_party(src, tgt)
	))

	register_action(ActionDef.new(
		"invite_guild", "Invite to Guild", "",
		ActionDef.ActionCategory.SOCIAL,
		func(src, tgt): return _action_invite_guild(src, tgt)
	))

	register_action(ActionDef.new(
		"add_friend", "Add Friend", "",
		ActionDef.ActionCategory.SOCIAL,
		func(src, tgt): return _action_add_friend(src, tgt)
	))

	register_action(ActionDef.new(
		"ignore", "Ignore Player", "",
		ActionDef.ActionCategory.SOCIAL,
		func(src, tgt): return _action_ignore(src, tgt)
	))

	register_action(ActionDef.new(
		"report", "Report Player", "",
		ActionDef.ActionCategory.SOCIAL,
		func(src, tgt): return _action_report(src, tgt),
		false,  # doesn't require target online
		true     # target can be offline
	))

	# === VIP SOCIAL ===
	register_action(ActionDef.new(
		"trade", "Trade", "",
		ActionDef.ActionCategory.VIP_SOCIAL,
		func(src, tgt): return _action_trade(src, tgt),
		true, true,
		GameConfig.Security.VIP_LEVEL
	))

	# === MODERATION ===
	register_action(ActionDef.new(
		"mod_mute", "Mute Player", "",
		ActionDef.ActionCategory.MODERATION,
		func(src, tgt): return _action_mute(src, tgt),
		true, true,
		GameConfig.Security.MOD_LEVEL
	))

	register_action(ActionDef.new(
		"mod_kick", "Kick Player", "",
		ActionDef.ActionCategory.MODERATION,
		func(src, tgt): return _action_kick(src, tgt),
		true, true,
		GameConfig.Security.MOD_LEVEL
	))

	register_action(ActionDef.new(
		"mod_lookup", "View Player Info", "",
		ActionDef.ActionCategory.MODERATION,
		func(src, tgt): return _action_lookup(src, tgt),
		true, false,  # can lookup offline players
		GameConfig.Security.MOD_LEVEL
	))

	# === ADMIN ===
	register_action(ActionDef.new(
		"admin_ban", "Ban Player", "",
		ActionDef.ActionCategory.ADMIN,
		func(src, tgt): return _action_ban(src, tgt),
		true, true,
		GameConfig.Security.ADMIN_LEVEL
	))

	register_action(ActionDef.new(
		"admin_restrict", "Restrict Player", "",
		ActionDef.ActionCategory.ADMIN,
		func(src, tgt): return _action_restrict(src, tgt),
		true, true,
		GameConfig.Security.ADMIN_LEVEL
	))

	register_action(ActionDef.new(
		"resurrect", "Resurrect", "",
		ActionDef.ActionCategory.ADMIN,
		func(src, tgt): return _action_resurrect(src, tgt),
		true, false,  # requires_target=true, requires_line_of_sight=false
		GameConfig.Security.MOD_LEVEL
	))

	# === INTERACTION ===
	register_action(ActionDef.new(
		"talk", "Talk", "",
		ActionDef.ActionCategory.INTERACTION,
		func(src, tgt): return _action_talk(src, tgt)
	))

	register_action(ActionDef.new(
		"loot", "Loot", "",
		ActionDef.ActionCategory.INTERACTION,
		func(src, tgt): return _action_loot(src, tgt)
	))

	register_action(ActionDef.new(
		"use", "Use", "",
		ActionDef.ActionCategory.INTERACTION,
		func(src, tgt): return _action_use(src, tgt)
	))

	register_action(ActionDef.new(
		"enter", "Enter", "",
		ActionDef.ActionCategory.INTERACTION,
		func(src, tgt): return _action_enter(src, tgt)
	))

## ============================================================================
## ACTION IMPLEMENTATIONS
## ============================================================================

func _action_whisper(source_id: String, target_id: String) -> Dictionary:
	if _chat_svc():
		_chat_svc().start_whisper(target_id)
		return {"success": true, "message": "Opening whisper with %s" % target_id}
	return {"success": false, "message": "Chat service unavailable"}

func _action_invite_party(source_id: String, target_id: String) -> Dictionary:
	if _party_svc():
		var party := _party_svc()
		var result: bool = party.invite_player(source_id, target_id)
		if result:
			return {"success": true, "message": "Party invite sent to %s" % target_id}
		return {"success": false, "message": "Failed to invite %s to party" % target_id}
	return {"success": false, "message": "Party service unavailable"}

func _action_invite_guild(source_id: String, target_id: String) -> Dictionary:
	if _guild_svc():
		var result: bool = _guild_svc().invite_player(source_id, target_id)
		if result:
			return {"success": true, "message": "Guild invite sent to %s" % target_id}
		return {"success": false, "message": "Failed to invite %s to guild" % target_id}
	return {"success": false, "message": "Guild service unavailable"}

func _action_add_friend(_source_id: String, target_id: String) -> Dictionary:
	return {"success": true, "message": "Friend request sent to %s" % target_id}

func _action_ignore(source_id: String, target_id: String) -> Dictionary:
	if _chat_svc():
		_chat_svc().ignore_player(source_id, target_id)
		return {"success": true, "message": "%s ignored" % target_id}
	return {"success": false, "message": "Chat service unavailable"}

func _action_report(_source_id: String, target_id: String) -> Dictionary:
	return {"success": true, "message": "Report dialog opened", "action": "open_report_dialog"}

func _action_trade(_source_id: String, target_id: String) -> Dictionary:
	return {"success": true, "message": "Trade request sent to %s" % target_id}

func _action_mute(source_id: String, target_id: String) -> Dictionary:
	if _perm_svc():
		return _perm_svc().mute(source_id, target_id, 300)
	return {"success": false, "message": "Permission manager unavailable"}

func _action_kick(source_id: String, target_id: String) -> Dictionary:
	if _perm_svc():
		return _perm_svc().kick(source_id, target_id, "Kicked by %s" % source_id)
	return {"success": false, "message": "Permission manager unavailable"}

func _action_lookup(source_id: String, target_id: String) -> Dictionary:
	if _perm_svc():
		var result = _perm_svc().lookup_player(source_id, target_id)
		if result.success:
			return {"success": true, "message": "Player info retrieved", "data": result.info}
		return result
	return {"success": false, "message": "Permission manager unavailable"}

func _action_ban(source_id: String, target_id: String) -> Dictionary:
	if _perm_svc():
		return _perm_svc().ban(source_id, target_id, -1, "Banned by %s" % source_id)
	return {"success": false, "message": "Permission manager unavailable"}

func _action_restrict(source_id: String, target_id: String) -> Dictionary:
	if _perm_svc():
		return _perm_svc().restrict(source_id, target_id, "all", 3600, "Restricted by %s" % source_id)
	return {"success": false, "message": "Permission manager unavailable"}

func _action_resurrect(source_id: String, target_id: String) -> Dictionary:
	# Find the target entity
	var target_entity = get_entity_by_id(target_id)
	if not target_entity:
		return {"success": false, "message": "Target not found"}

	# Check if target is a player
	if not target_entity is PlayerController:
		return {"success": false, "message": "Can only resurrect players"}

	# Check if target is dead
	var health_comp = target_entity.health_component
	if not health_comp:
		return {"success": false, "message": "Target has no health component"}

	if not health_comp.is_dead():
		return {"success": false, "message": "Target is not dead"}

	# Check permission (already done by action system, but double-check)
	var player_level = _get_player_permission_level()
	var mod_level = GameConfig.Security.MOD_LEVEL if GameConfig.Security else 1
	if player_level < mod_level:
		return {"success": false, "message": "Permission denied"}

	# Perform resurrection via _admin_cmds()
	if _admin_cmds():
		var result = _admin_cmds()._do_resurrect(target_entity, 1.0, 1.0)
		if result.get("success", false):
			return {"success": true, "message": "Resurrected %s" % target_entity.display_name}
		else:
			return {"success": false, "message": result.get("reason", "Failed to resurrect")}

	# Fallback if _admin_cmds() not available
	_do_resurrect_fallback(target_entity)
	return {"success": true, "message": "Resurrected %s" % target_entity.display_name}

func _do_resurrect_fallback(entity) -> void:
	var health_comp = entity.health_component

	# Remove corpse if exists
	if health_comp._corpse:
		health_comp._corpse.queue_free()
		health_comp._corpse = null

	# Restore health
	health_comp.current_health = health_comp.max_health
	health_comp._is_dead = false
	health_comp._respawn_timer = 0.0

	# Clear death state
	entity.health_component.respawned.emit()
	var hub := _hub()
	if hub:
		hub.emit_signal("entity_spawned", entity, null)
		hub.emit_signal("player_resurrected", entity, "tooltip_action")
		hub.emit_signal("player_respawned", entity, entity.global_position, _respawn_svc().RespawnMode.REVIVE)

func _action_talk(_source_id: String, _target_id: String) -> Dictionary:
	return {"success": true, "message": "Opening dialogue", "action": "open_dialogue"}

func _action_loot(_source_id: String, _target_id: String) -> Dictionary:
	return {"success": true, "message": "Looting...", "action": "loot"}

func _action_use(_source_id: String, _target_id: String) -> Dictionary:
	return {"success": true, "message": "Using...", "action": "use"}

func _action_enter(_source_id: String, _target_id: String) -> Dictionary:
	return {"success": true, "message": "Entering...", "action": "enter_gateway"}

## ============================================================================
## TARGETING API
## ============================================================================

## Set the local player (for permission checks)
func set_local_player(player_id: String) -> void:
	_local_player_id = player_id

## Get current target
func get_current_target() -> TargetInfo:
	return _current_target

## Check if we have a target
func has_target() -> bool:
	return _current_target != null and _current_target.id != ""

## Set target
func set_target(entity_id: String, schema_id: String, display_name: String = "",
		position: Vector3 = Vector3.ZERO, node: Node = null,
		entity_type: int = Entity.EntityType.NONE,
		metadata: Dictionary = {}) -> void:

	# Check if type is allowed
	if not _is_type_allowed(entity_type):
		return

	# Create target info
	var new_target := TargetInfo.new()
	new_target.id = entity_id
	new_target.schema_id = schema_id
	new_target.entity_type = entity_type
	new_target.display_name = display_name if display_name != "" else entity_id
	new_target.position = position
	new_target.world_position = position
	new_target.node = node
	new_target.metadata = metadata

	# Get schema for computed properties
	var schema: Variant = get_schema(schema_id)
	if schema:
		new_target.actions = schema.available_actions
		new_target.highlight_color = schema.highlight_color
		new_target.highlight_size = schema.highlight_size

	# Save previous target to history
	if _current_target and _current_target.id != "":
		_add_to_history(_current_target)

	# Emit signals
	var previous := _current_target
	_current_target = new_target

	if previous:
		target_cleared.emit(previous)

	target_acquired.emit(new_target)

	# Update 3D highlight
	_update_3d_highlight(new_target)

## Clear current target
func clear_target() -> void:
	if _current_target:
		var previous := _current_target
		_current_target = null
		target_cleared.emit(previous)
		_hide_3d_highlight()

## Cycle to next valid target
func cycle_next(valid_entity_ids: Array[String]) -> void:
	if valid_entity_ids.is_empty():
		return

	var current_idx := -1
	if _current_target:
		current_idx = valid_entity_ids.find(_current_target.id)

	# Find next valid
	for i in range(current_idx + 1, valid_entity_ids.size()):
		var entity_id = valid_entity_ids[i]
		if _targetables.has(entity_id):
			var data = _targetables[entity_id]
			set_target(entity_id, data.schema_id, data.name, data.position, data.node, data.entity_type)
			return

	# Wrap around
	for i in range(0, current_idx + 1):
		var entity_id = valid_entity_ids[i]
		if _targetables.has(entity_id):
			var data = _targetables[entity_id]
			set_target(entity_id, data.schema_id, data.name, data.position, data.node, data.entity_type)
			return

## Cycle targets: forward (shift=false) or backward (shift=true).
## Queries all registered targetables and cycles through them.
func cycle_target(reverse: bool) -> void:
	if _targetables.is_empty():
		return
	var ids: Array[String] = _targetables.keys()
	if reverse:
		ids.reverse()
	var current_idx := -1
	if _current_target:
		current_idx = ids.find(_current_target.id)
	var step := 1 if not reverse else -1
	var tries := ids.size()
	for offset in range(1, tries + 1):
		var next_idx := posmod(current_idx + offset * step, ids.size())
		var entity_id: String = ids[next_idx]
		var data: Dictionary = _targetables[entity_id]
		set_target(entity_id, data.schema_id, data.name, data.position, data.node, data.entity_type)
		return


## Restore previous target
func restore_previous() -> bool:
	if _target_history.is_empty():
		return false

	var previous: TargetInfo = _target_history.pop_back()
	if previous and previous.id != "":
		set_target(previous.id, previous.schema_id, previous.display_name,
			previous.position, previous.node, previous.entity_type, previous.metadata)
		return true

	return false

## ============================================================================
## TARGETABLE REGISTRATION
## ============================================================================

## Register an entity as targetable
func register_targetable(entity_id: String, schema_id: String, node: Node = null,
		display_name: String = "", position: Vector3 = Vector3.ZERO,
		entity_type: int = 0) -> void:

	_targetables[entity_id] = {
		"schema_id": schema_id,
		"node": node,
		"name": display_name if display_name != "" else entity_id,
		"position": position,
		"entity_type": entity_type
	}

## Unregister a targetable
func unregister_targetable(entity_id: String) -> void:
	_targetables.erase(entity_id)

	# Clear if this was our target
	if _current_target and _current_target.id == entity_id:
		clear_target()

## Update a targetable's position (for moving entities)
func update_targetable_position(entity_id: String, new_position: Vector3) -> void:
	if not _targetables.has(entity_id):
		return

	_targetables[entity_id]["position"] = new_position

	# Update current target position if this is the active target
	if _current_target and _current_target.id == entity_id:
		_current_target.position = new_position
		_current_target.world_position = new_position
		_update_3d_highlight(_current_target)

## Update a targetable's node reference (e.g., after scene change)
func update_targetable_node(entity_id: String, new_node: Node) -> void:
	if not _targetables.has(entity_id):
		return

	_targetables[entity_id]["node"] = new_node

## Get targetable data
func get_targetable(entity_id: String) -> Dictionary:
	return _targetables.get(entity_id, {})

## Get all targetables of a type
func get_targetables_by_type(entity_type: int) -> Array:
	var results = []
	for entity_id in _targetables:
		var data = _targetables[entity_id]
		if data.entity_type == entity_type:
			results.append(entity_id)
	return results

## ============================================================================
## ACTION EXECUTION
## ============================================================================

## Execute an action on current target
func execute_action(action_id: String) -> Dictionary:
	if not has_target():
		return {"success": false, "message": "No target selected"}

	return execute_action_on(action_id, _current_target.id)

## Execute action on specific target
func execute_action_on(action_id: String, target_id: String) -> Dictionary:
	# Get action definition
	if not _actions.has(action_id):
		return {"success": false, "message": "Unknown action: " + action_id}

	var action: ActionDef = _actions[action_id]

	# Permission check
	var player_level := _get_player_permission_level()
	if player_level < action.min_permission_level:
		action_blocked.emit(action_id, target_id, "Insufficient permissions")
		return {"success": false, "message": "Insufficient permissions"}

	# Target online check
	if action.requires_target_online:
		if not _is_target_online(target_id):
			action_blocked.emit(action_id, target_id, "Target is offline")
			return {"success": false, "message": "Target is offline"}

	# Execute callback
	if action.callback.is_valid():
		var result: Dictionary = action.callback.call(_local_player_id, target_id)
		action_executed.emit(action_id, target_id, result)
		return result

	return {"success": false, "message": "Action not available"}

## Get available actions for current target
func get_available_actions() -> Array[String]:
	if not has_target():
		return []
	return get_available_actions_for(_current_target.id)

## Get available actions for a specific target
func get_available_actions_for(target_id: String) -> Array[String]:
	var available = []

	# Check against schema
	var target_data = _targetables.get(target_id, {})
	var schema_id = target_data.get("schema_id", "")
	var schema = get_schema(schema_id)

	if schema:
		# Filter by permission
		var player_level = _get_player_permission_level()
		for action_id in schema.available_actions:
			if not _actions.has(action_id):
				continue
			var action: ActionDef = _actions[action_id]
			if player_level >= action.min_permission_level:
				available.append(action_id)
	else:
		# No schema - return all actions user can perform
		for action_id in _actions:
			var action: ActionDef = _actions[action_id]
			var player_level = _get_player_permission_level()
			if player_level >= action.min_permission_level:
				available.append(action_id)

	# Check for resurrect action if target is dead player
	available = _add_resurrect_action_if_applicable(target_id, available)

	return available

## Add resurrect action if target is a dead player and caster has permission
func _add_resurrect_action_if_applicable(target_id: String, available: Array[String]) -> Array[String]:
	var target_entity = get_entity_by_id(target_id)
	if not target_entity:
		return available

	# Check if target is a dead player
	if target_entity is PlayerController:
		var health_comp = target_entity.health_component
		if health_comp and health_comp.is_dead():
			# Check if caster (local player) has permission
			var player_level = _get_player_permission_level()
			var mod_level = GameConfig.Security.MOD_LEVEL if GameConfig.Security else 1

			if player_level >= mod_level:
				# Add resurrect action if not already present
				if not "resurrect" in available:
					available.append("resurrect")

	return available

## ============================================================================
## TARGETING FILTERS
## ============================================================================

func set_allowed_types(types: int) -> void:
	_allowed_types = types

func add_allowed_type(type: int) -> void:
	_allowed_types |= type

func remove_allowed_type(type: int) -> void:
	_allowed_types &= ~type

func _is_type_allowed(entity_type: int) -> bool:
	return (_allowed_types & entity_type) != 0

func set_selection_mode(mode: TargetSchema.SelectionMode) -> void:
	_selection_mode = mode

## ============================================================================
## 3D HIGHLIGHT
## ============================================================================

func set_highlight_node(node: Node3D) -> void:
	_highlight_node = node

func update_highlight() -> void:
	if not _highlight_node:
		return

	if has_target():
		_highlight_node.show()
		_highlight_node.global_position = _current_target.world_position

		# Update color if highlight supports it
		if _highlight_node.has_method("set_color"):
			_highlight_node.set_color(_current_target.highlight_color)
	else:
		_highlight_node.hide()

## ============================================================================
## RAYCAST METHODS
## ============================================================================

## Raycast from camera at screen position
func raycast_from_camera(screen_pos: Vector2, camera: Camera3D) -> TargetInfo:
	if not camera:
		camera = _get_active_camera()
	if not camera:
		return null

	var from := camera.global_position
	var direction := camera.project_ray_normal(screen_pos)
	var to := from + direction * 100.0

	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = Layers.layer_bit("entity")  # Entity layer

	var result := space_state.intersect_ray(query)
	if result.size() > 0:
		var collider: Node = result["collider"]
		if collider and ("entity_id" in collider):
			return _create_target_info_from_node(collider, result.get("position", Vector3.ZERO))

	return null

## Raycast from mouse position (desktop)
func raycast_from_mouse(camera: Camera3D = null) -> TargetInfo:
	if not camera:
		camera = _get_active_camera()
	if not camera:
		return null

	var mouse_pos := camera.get_viewport().get_mouse_position()
	return raycast_from_camera(mouse_pos, camera)

## Raycast from touch position (mobile)
func raycast_from_touch(touch_pos: Vector2, camera: Camera3D = null) -> TargetInfo:
	return raycast_from_camera(touch_pos, camera)

## Raycast from screen center (for direction-based targeting)
func raycast_from_center(camera: Camera3D = null) -> TargetInfo:
	if not camera:
		camera = _get_active_camera()
	if not camera:
		return null

	var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
	var center_pos := viewport_size / 2.0
	return raycast_from_camera(center_pos, camera)

## Get entity at screen position (raw node reference)
func get_entity_at_screen_position(screen_pos: Vector2, camera: Camera3D = null) -> Node:
	if not camera:
		camera = _get_active_camera()
	if not camera:
		return null

	var from := camera.global_position
	var direction := camera.project_ray_normal(screen_pos)
	var to := from + direction * 100.0

	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = Layers.layer_bit("entity")  # Entity layer

	var result := space_state.intersect_ray(query)
	if result.size() > 0:
		return result["collider"]

	return null

## Get first targetable entity in direction from origin
func get_target_in_direction(origin: Vector3, direction: Vector3, max_distance: float = 50.0) -> TargetInfo:
	var camera := _get_active_camera()
	if not camera:
		return null
	var space_state := camera.get_world_3d().direct_space_state
	var to := origin + direction * max_distance

	var query := PhysicsRayQueryParameters3D.create(origin, to)
	query.collision_mask = Layers.layer_bit("entity")  # Entity layer

	var result := space_state.intersect_ray(query)
	if result.size() > 0:
		var collider: Node = result["collider"]
		if collider and ("entity_id" in collider):
			return _create_target_info_from_node(collider, result.get("position", Vector3.ZERO))

	return null

## Cycle to next target in list
func cycle_to_index(index: int, entity_ids: Array) -> void:
	if index < 0 or index >= entity_ids.size():
		return

	var entity_id = entity_ids[index]
	if _targetables.has(entity_id):
		var data = _targetables[entity_id]
		set_target(entity_id, data.schema_id, data.name, data.position, data.node, data.entity_type)

## Get camera reference
func _get_active_camera() -> Camera3D:
	# Try to get the current camera
	var viewport := get_tree().root if get_tree() else null
	if viewport:
		var camera := viewport.get_camera_3d()
		if camera:
			return camera

	# Fallback: find any camera in scene
	var cameras = get_tree().get_nodes_in_group("cameras")
	if not cameras.is_empty():
		return cameras[0] as Camera3D

	return null

## ============================================================================
## INTERNAL HELPERS
## ============================================================================

func _create_target_info_from_node(node: Node, hit_position: Vector3 = Vector3.ZERO) -> TargetInfo:
	# `in` probes, not Object.has() (which does not exist on Node/Object in
	# Godot 4; hitbox StaticBody3D children arrive here from raycasts).
	if not ("entity_id" in node):
		return null

	var entity_id = node.entity_id
	var entity_type: int = node.entity_type if ("entity_type" in node) else 0

	# Get schema for this entity type
	var schema_id = _entity_type_to_schema.get(entity_type, "")
	if schema_id == "":
		schema_id = _infer_schema_id(node)

	var info := TargetInfo.new()
	info.id = entity_id
	info.schema_id = schema_id
	info.entity_type = entity_type
	info.display_name = node.display_name if node.has("display_name") else entity_id
	info.world_position = node.global_position if node is Node3D else hit_position
	info.position = hit_position
	info.node = node
	# Extract npc_data if this is an NPC
	if entity_type == Entity.EntityType.NPC and node.has("npc_data"):
		info.npc_data = node.npc_data

	# Get schema for computed properties
	var schema: Variant = get_schema(schema_id)
	if schema:
		info.actions = schema.available_actions
		info.highlight_color = schema.highlight_color
		info.highlight_size = schema.highlight_size

	return info

## ============================================================================
## QUERY METHODS (for UI, AI, etc.)
## ============================================================================

## Get tooltip data for current target
func get_tooltip_data() -> Dictionary:
	if not has_target():
		return {}

	var data: Dictionary = {
		"target": _current_target.to_dict(),
		"actions": get_available_actions(),
		"schema": null
	}

	var schema = get_schema(_current_target.schema_id)
	if schema:
		data.schema = schema.get_info()

	return data

## Get targets near position
func get_targets_in_radius(origin: Vector3, radius: float, entity_type: int = 0) -> Array:
	var results = []
	for entity_id in _targetables:
		var data = _targetables[entity_id]
		var pos = data.position if data.has("position") else Vector3.ZERO
		if pos.distance_to(origin) <= radius:
			if entity_type == 0 or data.entity_type == entity_type:
				results.append(entity_id)
	return results

## ============================================================================
## EVENT HANDLERS
## ============================================================================

func _on_entity_spawned(entity, _metadata: SpawnMetadata) -> void:
	# Entities are Nodes, not Dictionaries: use the `in` operator for
	# property presence and avoid Object.get(key, default) (removed in 4.7.2).
	if entity == null or not ("entity_id" in entity):
		return
	var entity_type: int = entity.entity_type if "entity_type" in entity else 0
	var schema_id: String = _entity_type_to_schema.get(entity_type, "")
	if schema_id == "":
		schema_id = _infer_schema_id(entity)

	register_targetable(
		entity.entity_id,
		schema_id,
		entity,
		entity.display_name if "display_name" in entity else entity.entity_id,
		entity.global_position if entity is Node3D else Vector3.ZERO,
		entity_type
	)

func _on_entity_despawned(entity, _metadata: SpawnMetadata) -> void:
	if entity != null and "entity_id" in entity:
		unregister_targetable(entity.entity_id)

func _on_entity_died(entity, _killer, _metadata: SpawnMetadata) -> void:
	if entity != null and "entity_id" in entity:
		# Optionally clear target if they died
		if _current_target and _current_target.id == entity.entity_id:
			# Don't auto-clear, let player decide
			pass

## Connected to EventHub.skill_executed (caster_id, skill_id, target_ids)
## -- the STRING-typed hub signal, not CombatSystem's object-typed one.
## Node/Resource annotations here made every emit throw a conversion
## error (R29).
func _on_skill_executed(_caster_id: String, _skill_id: String, _targets: Array) -> void:
	# Could trigger targeting-related logic
	pass

## ============================================================================
## HELPERS
## ============================================================================

func _add_to_history(target: TargetInfo) -> void:
	_target_history.push_front(target)
	if _target_history.size() > MAX_HISTORY:
		_target_history.pop_back()

func _get_player_permission_level() -> int:
	if _local_player_id == "":
		return 0
	if _perm_svc():
		return _perm_svc().get_player_level(_local_player_id)
	return 0

func _is_target_online(target_id: String) -> bool:
	if _pm():
		return _pm().is_player_online(target_id)
	return false

func _infer_schema_id(entity: Node) -> String:
	# Try to infer schema from entity type (`in` probe: Object.has() does not
	# exist in Godot 4 and Node3D-based entities arrive here).
	if ("entity_type" in entity):
		match entity.entity_type:
			1: return "player"  # PLAYER
			2: return "enemy"    # ENEMY
			3: return "npc"      # NPC
	return ""

## ============================================================================
## 3D HIGHLIGHT MANAGEMENT
## ============================================================================

## Update 3D highlight for target
func _update_3d_highlight(target: TargetInfo) -> void:
	if not target:
		_hide_3d_highlight()
		return

	var highlight_color := target.highlight_color
	var highlight_size := target.highlight_size
	var target_pos := target.world_position

	if target.node is Node3D:
		target_pos = target.node.global_position

	_create_or_update_highlight_mesh(target_pos, highlight_color, highlight_size, target.entity_type)

## Create or update highlight mesh
func _create_or_update_highlight_mesh(position: Vector3, color: Color, size: float, entity_type: int) -> void:
	var world_root := _get_world_root()
	if not world_root:
		return

	if not _highlight_node or not is_instance_valid(_highlight_node):
		_highlight_node = Node3D.new()
		_highlight_node.name = "TargetingHighlight"
		world_root.add_child(_highlight_node)

	if not _highlight_mesh or not is_instance_valid(_highlight_mesh):
		_highlight_mesh = MeshInstance3D.new()
		_highlight_node.add_child(_highlight_mesh)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.3

	var mesh := _create_ring_mesh(size)
	_highlight_mesh.mesh = mesh
	_highlight_mesh.material_override = material
	_highlight_node.global_position = Vector3(position.x, position.y + 0.05, position.z)
	_highlight_node.visible = true
	_start_highlight_pulse()

## Create ring mesh for highlight
func _create_ring_mesh(radius: float) -> ArrayMesh:
	var array_mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()

	var segments := 32
	for i in range(segments + 1):
		var angle := TAU * i / segments
		verts.append(Vector3(cos(angle) * radius, 0, sin(angle) * radius))
		colors.append(Color(1, 1, 1, 1))

	for i in range(segments):
		indices.append(i)
		indices.append(i + 1)
		indices.append(segments + 1 + i)
		indices.append(i + 1)
		indices.append(segments + 2 + i)
		indices.append(segments + 1 + i)

	var arrays := []
	arrays.append(verts)
	arrays.append(indices)
	arrays.append(colors)
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return array_mesh

## Start highlight pulse animation
func _start_highlight_pulse() -> void:
	if not _highlight_pulse_enabled or not _highlight_mesh:
		return

	if _highlight_tween:
		_highlight_tween.kill()

	_highlight_tween = create_tween()
	_highlight_tween.set_loops()

	var mat := _highlight_mesh.material_override as StandardMaterial3D
	if mat:
		_highlight_tween.tween_property(mat, "emission_energy_multiplier", 3.0, 0.5)
		_highlight_tween.tween_property(mat, "emission_energy_multiplier", 1.5, 0.5)

## Stop highlight pulse
func _stop_highlight_pulse() -> void:
	if _highlight_tween:
		_highlight_tween.kill()
		_highlight_tween = null

## Hide 3D highlight
func _hide_3d_highlight() -> void:
	_stop_highlight_pulse()
	if _highlight_node and is_instance_valid(_highlight_node):
		_highlight_node.visible = false

## Get world root for highlights
func _get_world_root() -> Node3D:
	var scene_root := get_tree().root
	if scene_root:
		var existing := scene_root.find_child("Highlights", false, false)
		if existing:
			return existing as Node3D
		var container := Node3D.new()
		container.name = "Highlights"
		scene_root.add_child(container)
		return container
	return null

## Enable/disable highlight pulsing
func set_highlight_pulse(enabled: bool) -> void:
	_highlight_pulse_enabled = enabled
	if not enabled:
		_stop_highlight_pulse()
	elif _highlight_node and _highlight_node.visible:
		_start_highlight_pulse()

## Get current highlight state
func is_highlight_visible() -> bool:
	return _highlight_node and _highlight_node.visible

## ============================================================================
## STATIC UTILITIES
## ============================================================================

## Convert entity type int to human-readable string
## Uses Entity.EntityType (see core/entities/entity.gd)
static func entity_type_to_string(entity_type: int) -> String:
	match entity_type:
		Entity.EntityType.PLAYER: return "Player"
		Entity.EntityType.ENEMY: return "Enemy"
		Entity.EntityType.NPC: return "NPC"
		Entity.EntityType.DESTRUCTIBLE: return "Destructible"
		Entity.EntityType.OBJECT: return "Object"
		Entity.EntityType.TELEPORT: return "Teleport"
		Entity.EntityType.LOOT: return "Loot"
		_: return "Unknown"

## Convert entity type string to int
static func string_to_entity_type(type_str: String) -> int:
	match type_str.to_lower():
		"player": return Entity.EntityType.PLAYER
		"enemy": return Entity.EntityType.ENEMY
		"npc": return Entity.EntityType.NPC
		"destructible": return Entity.EntityType.DESTRUCTIBLE
		"object": return Entity.EntityType.OBJECT
		"teleport": return Entity.EntityType.TELEPORT
		"loot": return Entity.EntityType.LOOT
		_: return Entity.EntityType.NONE
