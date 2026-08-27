## PlayerTargetSystem - Player targeting and context actions
## Handles player-to-player interactions via target system
class_name PlayerTargetSystem
extends Node

## Target type
enum TargetType {
	NONE
	PLAYER
	NPC
	ENEMY
	OBJECT
}

## Action types available based on permission level
enum ActionCategory {
	# Available to all players
	SOCIAL = 0
	# Requires VIP
	VIP_SOCIAL = 1
	# Requires MOD
	MODERATION = 2
	# Requires ADMIN
	ADMIN = 3
}

## Player action definition
class PlayerAction:
	var id: String
	var name: String
	var icon: String  # Emoji or icon name
	var category: ActionCategory
	var min_level: int  # Permission level required
	var requires_target_online: bool
	var callback: Callable  # func(source_id, target_id) -> Dictionary
	
	func _init(p_id: String, p_name: String, p_icon: String, p_category: ActionCategory,
			p_callback: Callable, p_requires_online: bool = true, p_min_level: int = 0):
		id = p_id
		name = p_name
		icon = p_icon
		category = p_category
		callback = p_callback
		requires_target_online = p_requires_online
		min_level = p_min_level

## Current target info
var _current_target_type: TargetType = TargetType.NONE
var _current_target_id: String = ""
var _current_target_name: String = ""
var _target_position: Vector3 = Vector3.ZERO

## All available actions
var _actions: Dictionary = {}

## Player info cache
var _player_info_cache: Dictionary = {}
var _cache_ttl_ms: int = 5000

signal target_changed(target_type: TargetType, target_id: String, target_name: String)
signal action_executed(action_id: String, source_id: String, target_id: String, result: Dictionary)

func _ready() -> void:
	_register_default_actions()
	Logger.info("PlayerTargetSystem: Initialized with %d actions" % _actions.size())

## Register an action
func register_action(action: PlayerAction) -> void:
	_actions[action.id] = action

## Set current target
func set_target(type: TargetType, target_id: String, target_name: String = "", position: Vector3 = Vector3.ZERO) -> void:
	_current_target_type = type
	_current_target_id = target_id
	_current_target_name = target_name if target_name != "" else target_id
	_target_position = position
	
	target_changed.emit(type, target_id, _current_target_name)
	
	# Clear cache when target changes
	if type != TargetType.NONE:
		_player_info_cache.erase(target_id)

## Clear target
func clear_target() -> void:
	set_target(TargetType.NONE, "", "")

## Get current target
func get_current_target() -> Dictionary:
	return {
		"type": _current_target_type,
		"id": _current_target_id,
		"name": _current_target_name,
		"position": _target_position
	}

## Get available actions for source player targeting current target
func get_available_actions(source_id: String) -> Array:
	if _current_target_id == "" or _current_target_type == TargetType.NONE:
		return []
	
	var actions: Array = []
	var source_level := _get_player_level(source_id)
	
	for action_id in _actions.keys():
		var action: PlayerAction = _actions[action_id]
		
		# Check permission level
		if action.min_level > 0 and source_level < action.min_level:
			continue
		
		# Check category requirements
		if action.category == ActionCategory.MODERATION and source_level < PermissionSystem.Global.MOD:
			continue
		if action.category == ActionCategory.ADMIN and source_level < PermissionSystem.Global.ADMIN:
			continue
		
		# Check if target is online for online-required actions
		if action.requires_target_online and _current_target_type == TargetType.PLAYER:
			if not _is_target_online():
				continue
		
		# Check special conditions
		if not _check_action_conditions(action, source_id):
			continue
		
		actions.append({
			"id": action.id,
			"name": action.name,
			"icon": action.icon,
			"category": action.category
		})
	
	return actions

## Execute an action
func execute_action(source_id: String, action_id: String) -> Dictionary:
	if not _actions.has(action_id):
		return {"success": false, "message": "Unknown action"}
	
	var action: PlayerAction = _actions[action_id]
	
	# Verify permissions again
	var source_level := _get_player_level(source_id)
	if action.min_level > 0 and source_level < action.min_level:
		return {"success": false, "message": "Insufficient permissions"}
	
	# Execute callback
	if action.callback.is_valid():
		var result: Dictionary = action.callback.call(source_id, _current_target_id)
		action_executed.emit(action_id, source_id, _current_target_id, result)
		return result
	
	return {"success": false, "message": "Action not available"}

## Get target player info
func get_target_player_info() -> Dictionary:
	if _current_target_type != TargetType.PLAYER or _current_target_id == "":
		return {}
	
	# Check cache
	if _player_info_cache.has(_current_target_id):
		var cached: Dictionary = _player_info_cache[_current_target_id]
		if Time.get_ticks_msec() - cached["time"] < _cache_ttl_ms:
			return cached["data"]
	
	# Fetch fresh info
	var info := _fetch_player_info(_current_target_id)
	
	# Cache it
	_player_info_cache[_current_target_id] = {
		"time": Time.get_ticks_msec(),
		"data": info
	}
	
	return info

## Get tooltip data for target
func get_tooltip_data(source_id: String) -> Dictionary:
	var target := get_current_target()
	if target.id == "":
		return {}
	
	var data := {
		"target": target,
		"player_info": {},
		"available_actions": get_available_actions(source_id),
		"can_target": true
	}
	
	if target.type == TargetType.PLAYER:
		data["player_info"] = get_target_player_info()
	
	return data

## ============================================================================
## DEFAULT ACTIONS
## ============================================================================

func _register_default_actions() -> void:
	# === SOCIAL ACTIONS (Available to all) ===
	register_action(PlayerAction.new(
		"whisper",
		"Whisper",
		"💭",
		ActionCategory.SOCIAL,
		func(src, tgt): return _action_whisper(src, tgt)
	))
	
	register_action(PlayerAction.new(
		"invite_party",
		"Invite to Party",
		"🎮",
		ActionCategory.SOCIAL,
		func(src, tgt): return _action_invite_party(src, tgt)
	))
	
	register_action(PlayerAction.new(
		"invite_guild",
		"Invite to Guild",
		"🏰",
		ActionCategory.SOCIAL,
		func(src, tgt): return _action_invite_guild(src, tgt)
	))
	
	register_action(PlayerAction.new(
		"invite_faction",
		"Invite to Faction",
		"⚔️",
		ActionCategory.SOCIAL,
		func(src, tgt): return _action_invite_faction(src, tgt)
	))
	
	register_action(PlayerAction.new(
		"add_friend",
		"Add Friend",
		"❤️",
		ActionCategory.SOCIAL,
		func(src, tgt): return _action_add_friend(src, tgt)
	))
	
	register_action(PlayerAction.new(
		"ignore",
		"Ignore Player",
		"🚫",
		ActionCategory.SOCIAL,
		func(src, tgt): return _action_ignore(src, tgt)
	))
	
	register_action(PlayerAction.new(
		"report",
		"Report Player",
		"🚩",
		ActionCategory.SOCIAL,
		func(src, tgt): return _action_report(src, tgt),
		false  # Target doesn't need to be online
	))
	
	# === VIP SOCIAL (Requires VIP) ===
	register_action(PlayerAction.new(
		"trade",
		"Trade",
		"💰",
		ActionCategory.VIP_SOCIAL,
		func(src, tgt): return _action_trade(src, tgt),
		true,
		PermissionSystem.Global.VIP
	))
	
	# === MODERATION (Requires MOD) ===
	register_action(PlayerAction.new(
		"mod_mute",
		"Mute Player",
		"🔇",
		ActionCategory.MODERATION,
		func(src, tgt): return _action_mute(src, tgt),
		true,
		PermissionSystem.Global.MOD
	))
	
	register_action(PlayerAction.new(
		"mod_kick",
		"Kick Player",
		"👢",
		ActionCategory.MODERATION,
		func(src, tgt): return _action_kick(src, tgt),
		true,
		PermissionSystem.Global.MOD
	))
	
	register_action(PlayerAction.new(
		"mod_lookup",
		"View Player Info",
		"🔍",
		ActionCategory.MODERATION,
		func(src, tgt): return _action_mod_lookup(src, tgt),
		true,
		PermissionSystem.Global.MOD
	))
	
	# === ADMIN (Requires ADMIN) ===
	register_action(PlayerAction.new(
		"admin_ban",
		"Ban Player",
		"⛔",
		ActionCategory.ADMIN,
		func(src, tgt): return _action_ban(src, tgt),
		true,
		PermissionSystem.Global.ADMIN
	))
	
	register_action(PlayerAction.new(
		"admin_restrict",
		"Restrict Player",
		"🔒",
		ActionCategory.ADMIN,
		func(src, tgt): return _action_restrict(src, tgt),
		true,
		PermissionSystem.Global.ADMIN
	))

## ============================================================================
## ACTION IMPLEMENTATIONS
## ============================================================================

func _action_whisper(source_id: String, target_id: String) -> Dictionary:
	if ChatService:
		# Open whisper with target
		ChatService.start_whisper(target_id)
		return {"success": true, "message": "Opening whisper with %s" % target_id}
	return {"success": false, "message": "Chat service not available"}

func _action_invite_party(source_id: String, target_id: String) -> Dictionary:
	if PartyService:
		var result := PartyService.invite_player(source_id, target_id)
		if result.success:
			return {"success": true, "message": "Party invite sent to %s" % target_id}
		return result
	return {"success": false, "message": "Party service not available"}

func _action_invite_guild(source_id: String, target_id: String) -> Dictionary:
	if GuildService:
		var result := GuildService.invite_player(source_id, target_id)
		if result.success:
			return {"success": true, "message": "Guild invite sent to %s" % target_id}
		return result
	return {"success": false, "message": "Guild service not available"}

func _action_invite_faction(source_id: String, target_id: String) -> Dictionary:
	# Faction invites would go through FactionService
	return {"success": false, "message": "Faction invites not yet implemented"}

func _action_add_friend(source_id: String, target_id: String) -> Dictionary:
	# Friends system
	return {"success": true, "message": "Friend request sent to %s" % target_id}

func _action_ignore(source_id: String, target_id: String) -> Dictionary:
	if ChatService:
		ChatService.ignore_player(source_id, target_id)
		return {"success": true, "message": "%s ignored" % target_id}
	return {"success": false, "message": "Chat service not available"}

func _action_report(source_id: String, target_id: String) -> Dictionary:
	# Open report dialog
	return {"success": true, "message": "Report dialog opened", "action": "open_report_dialog"}

func _action_trade(source_id: String, target_id: String) -> Dictionary:
	return {"success": true, "message": "Trade request sent to %s" % target_id}

func _action_mute(source_id: String, target_id: String) -> Dictionary:
	if PermissionManager:
		var result := PermissionManager.mute(source_id, target_id, 300)
		return result
	return {"success": false, "message": "Permission manager not available"}

func _action_kick(source_id: String, target_id: String) -> Dictionary:
	if PermissionManager:
		var result := PermissionManager.kick(source_id, target_id, "Kicked by %s" % source_id)
		return result
	return {"success": false, "message": "Permission manager not available"}

func _action_mod_lookup(source_id: String, target_id: String) -> Dictionary:
	if PermissionManager:
		var result := PermissionManager.lookup_player(source_id, target_id)
		if result.success:
			return {"success": true, "message": "Player info retrieved", "data": result.info}
		return result
	return {"success": false, "message": "Permission manager not available"}

func _action_ban(source_id: String, target_id: String) -> Dictionary:
	if PermissionManager:
		var result := PermissionManager.ban(source_id, target_id, -1, "Banned by %s" % source_id)
		return result
	return {"success": false, "message": "Permission manager not available"}

func _action_restrict(source_id: String, target_id: String) -> Dictionary:
	if PermissionManager:
		var result := PermissionManager.restrict(source_id, target_id, "all", 3600, "Restricted by %s" % source_id)
		return result
	return {"success": false, "message": "Permission manager not available"}

## ============================================================================
## HELPERS
## ============================================================================

func _get_player_level(player_id: String) -> int:
	if PermissionSystem:
		return PermissionSystem.get().get_global_level(player_id)
	return 0

func _is_target_online() -> bool:
	if PlayerManager:
		return PlayerManager.is_player_online(_current_target_id)
	return false

func _check_action_conditions(action: PlayerAction, source_id: String) -> bool:
	# Add custom condition checks here
	match action.id:
		"invite_party":
			# Cannot invite if already in party
			if PartyService:
				return not PartyService.is_in_party(source_id)
		"invite_guild":
			# Must be guild leader to invite
			if GuildService:
				return GuildService.is_guild_leader(source_id)
		"add_friend":
			# Cannot friend yourself
			return source_id != _current_target_id
	
	return true

func _fetch_player_info(player_id: String) -> Dictionary:
	var info := {
		"id": player_id,
		"name": player_id,
		"level": 0,
		"online": false
	}
	
	# Get from PermissionManager
	if PermissionManager:
		info["level"] = PermissionManager.get_player_level(player_id)
	
	# Get online status
	if PlayerManager:
		info["online"] = PlayerManager.is_player_online(player_id)
	
	# Get restrictions
	if SecurityService:
		info["restricted"] = SecurityService.is_restricted(player_id, "chat")
	
	return info
