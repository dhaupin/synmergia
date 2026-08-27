## PermissionSystem - Unified permission system for all contexts
class_name PermissionSystem
extends Node

static var instance: PermissionSystem

enum Context {
	GLOBAL = 0
	PARTY = 1
	GUILD = 2
	FACTION = 3
}

## Global permissions
class Global:
	const PLAYER: int = 0
	const VIP: int = 10
	const MOD: int = 50
	const ADMIN: int = 100
	const OWNER: int = 200
	
	static func get_name(level: int) -> String:
		match level:
			PLAYER: return "Player"
			VIP: return "VIP"
			MOD: return "Moderator"
			ADMIN: return "Admin"
			OWNER: return "Owner"
			_: return "Unknown"
	
	static func get_color(level: int) -> Color:
		match level:
			PLAYER: return Color(0.6, 0.6, 0.6)
			VIP: return Color(1.0, 0.84, 0.0)
			MOD: return Color(0.3, 0.6, 1.0)
			ADMIN: return Color(1.0, 0.3, 0.3)
			OWNER: return Color(1.0, 0.5, 1.0)
			_: return Color.WHITE
	
	static func get_icon(level: int) -> String:
		match level:
			PLAYER: return "👤"
			VIP: return "⭐"
			MOD: return "🛡️"
			ADMIN: return "⚔️"
			OWNER: return "👑"
			_: return "❓"

## Party permissions
class Party:
	const MEMBER: int = 0
	const OFFICER: int = 10
	const LEADER: int = 20
	
	static func get_name(role: int) -> String:
		match role:
			MEMBER: return "Member"
			OFFICER: return "Officer"
			LEADER: return "Leader"
			_: return "Unknown"
	
	static func get_color(role: int) -> Color:
		match role:
			MEMBER: return Color(0.5, 0.5, 0.5)
			OFFICER: return Color(0.3, 0.7, 0.3)
			LEADER: return Color(1.0, 0.7, 0.3)
			_: return Color.WHITE
	
	static func get_icon(role: int) -> String:
		match role:
			MEMBER: return "👥"
			OFFICER: return "🎖️"
			LEADER: return "👑"
			_: return "❓"

## Guild permissions
class Guild:
	const RECRUIT: int = 0
	const MEMBER: int = 10
	const OFFICER: int = 20
	const GUILD_MASTER: int = 30
	
	static func get_name(role: int) -> String:
		match role:
			RECRUIT: return "Recruit"
			MEMBER: return "Member"
			OFFICER: return "Officer"
			GUILD_MASTER: return "Guild Master"
			_: return "Unknown"
	
	static func get_color(role: int) -> Color:
		match role:
			RECRUIT: return Color(0.4, 0.4, 0.4)
			MEMBER: return Color(0.6, 0.6, 0.8)
			OFFICER: return Color(0.8, 0.6, 0.2)
			GUILD_MASTER: return Color(1.0, 0.8, 0.2)
			_: return Color.WHITE
	
	static func get_icon(role: int) -> String:
		match role:
			RECRUIT: return "🌱"
			MEMBER: return "🛡️"
			OFFICER: return "⚔️"
			GUILD_MASTER: return "👑"
			_: return "❓"

## Faction permissions
class Faction:
	const INITIATE: int = 0
	const MEMBER: int = 10
	const VETERAN: int = 20
	const COMMANDER: int = 30
	const LEADER: int = 40
	
	static func get_name(rank: int) -> String:
		match rank:
			INITIATE: return "Initiate"
			MEMBER: return "Member"
			VETERAN: return "Veteran"
			COMMANDER: return "Commander"
			LEADER: return "Leader"
			_: return "Unknown"
	
	static func get_color(rank: int) -> Color:
		match rank:
			INITIATE: return Color(0.5, 0.5, 0.5)
			MEMBER: return Color(0.7, 0.7, 0.7)
			VETERAN: return Color(0.8, 0.5, 0.2)
			COMMANDER: return Color(0.6, 0.3, 0.6)
			LEADER: return Color(0.2, 0.6, 0.8)
			_: return Color.WHITE
	
	static func get_icon(rank: int) -> String:
		match rank:
			INITIATE: return "🌱"
			MEMBER: return "⚔️"
			VETERAN: return "🛡️"
			COMMANDER: return "🎖️"
			LEADER: return "🏆"
			_: return "❓"

var _player_levels: Dictionary = {}
var _party_roles: Dictionary = {}
var _guild_roles: Dictionary = {}
var _faction_ranks: Dictionary = {}
var _player_groups: Dictionary = {}

func _ready() -> void:
	instance = self
	Logger.info("PermissionSystem: Initialized")

## Global permissions
func get_global_level(player_id: String) -> int:
	return _player_levels.get(player_id, Global.PLAYER)

func set_global_level(player_id: String, level: int) -> void:
	_player_levels[player_id] = level

func has_global_permission(player_id: String, required_level: int) -> bool:
	return get_global_level(player_id) >= required_level

func is_vip(player_id: String) -> bool:
	return has_global_permission(player_id, Global.VIP)

func is_mod(player_id: String) -> bool:
	return has_global_permission(player_id, Global.MOD)

func is_admin(player_id: String) -> bool:
	return has_global_permission(player_id, Global.ADMIN)

func is_owner(player_id: String) -> bool:
	return has_global_permission(player_id, Global.OWNER)

## Party permissions
func get_party_role(player_id: String) -> int:
	return _party_roles.get(player_id, Party.MEMBER)

func set_party_role(player_id: String, role: int) -> void:
	_party_roles[player_id] = role

func has_party_permission(player_id: String, required_role: int) -> bool:
	if not has_party(player_id):
		return false
	return get_party_role(player_id) >= required_role

func is_party_leader(player_id: String) -> bool:
	return has_party_permission(player_id, Party.LEADER)

func is_party_officer(player_id: String) -> bool:
	return has_party_permission(player_id, Party.OFFICER)

func has_party(player_id: String) -> bool:
	var groups := _player_groups.get(player_id, {})
	return groups.has("party_id") and groups["party_id"] != ""

func get_party_id(player_id: String) -> String:
	var groups := _player_groups.get(player_id, {})
	return groups.get("party_id", "")

## Guild permissions
func get_guild_role(player_id: String) -> int:
	return _guild_roles.get(player_id, Guild.RECRUIT)

func set_guild_role(player_id: String, role: int) -> void:
	_guild_roles[player_id] = role

func has_guild_permission(player_id: String, required_role: int) -> bool:
	if not has_guild(player_id):
		return false
	return get_guild_role(player_id) >= required_role

func is_guild_master(player_id: String) -> bool:
	return has_guild_permission(player_id, Guild.GUILD_MASTER)

func is_guild_officer(player_id: String) -> bool:
	return has_guild_permission(player_id, Guild.OFFICER)

func has_guild(player_id: String) -> bool:
	var groups := _player_groups.get(player_id, {})
	return groups.has("guild_id") and groups["guild_id"] != ""

func get_guild_id(player_id: String) -> String:
	var groups := _player_groups.get(player_id, {})
	return groups.get("guild_id", "")

## Faction permissions
func get_faction_rank(player_id: String) -> int:
	return _faction_ranks.get(player_id, Faction.INITIATE)

func set_faction_rank(player_id: String, rank: int) -> void:
	_faction_ranks[player_id] = rank

func has_faction_permission(player_id: String, required_rank: int) -> bool:
	if not has_faction(player_id):
		return false
	return get_faction_rank(player_id) >= required_rank

func is_faction_leader(player_id: String) -> bool:
	return has_faction_permission(player_id, Faction.LEADER)

func is_faction_commander(player_id: String) -> bool:
	return has_faction_permission(player_id, Faction.COMMANDER)

func has_faction(player_id: String) -> bool:
	var groups := _player_groups.get(player_id, {})
	return groups.has("faction_id") and groups["faction_id"] != ""

func get_faction_id(player_id: String) -> String:
	var groups := _player_groups.get(player_id, {})
	return groups.get("faction_id", "")

## Unified permission check
func has_permission(player_id: String, permission: int, context: Context = Context.GLOBAL) -> bool:
	match context:
		Context.GLOBAL:
			return has_global_permission(player_id, permission)
		Context.PARTY:
			return has_party_permission(player_id, permission)
		Context.GUILD:
			return has_guild_permission(player_id, permission)
		Context.FACTION:
			return has_faction_permission(player_id, permission)
	return false

func get_role_name(permission: int, context: Context = Context.GLOBAL) -> String:
	match context:
		Context.GLOBAL: return Global.get_name(permission)
		Context.PARTY: return Party.get_name(permission)
		Context.GUILD: return Guild.get_name(permission)
		Context.FACTION: return Faction.get_name(permission)
	return "Unknown"

func get_role_color(permission: int, context: Context = Context.GLOBAL) -> Color:
	match context:
		Context.GLOBAL: return Global.get_color(permission)
		Context.PARTY: return Party.get_color(permission)
		Context.GUILD: return Guild.get_color(permission)
		Context.FACTION: return Faction.get_color(permission)
	return Color.WHITE

func get_role_icon(permission: int, context: Context = Context.GLOBAL) -> String:
	match context:
		Context.GLOBAL: return Global.get_icon(permission)
		Context.PARTY: return Party.get_icon(permission)
		Context.GUILD: return Guild.get_icon(permission)
		Context.FACTION: return Faction.get_icon(permission)
	return "❓"

func get_player_summary(player_id: String) -> Dictionary:
	return {
		"global": {
			"level": get_global_level(player_id),
			"name": Global.get_name(get_global_level(player_id)),
			"icon": Global.get_icon(get_global_level(player_id)),
			"is_vip": is_vip(player_id),
			"is_mod": is_mod(player_id),
			"is_admin": is_admin(player_id),
			"is_owner": is_owner(player_id)
		},
		"party": {
			"role": get_party_role(player_id),
			"name": Party.get_name(get_party_role(player_id)),
			"icon": Party.get_icon(get_party_role(player_id)),
			"has_party": has_party(player_id),
			"is_leader": is_party_leader(player_id)
		},
		"guild": {
			"role": get_guild_role(player_id),
			"name": Guild.get_name(get_guild_role(player_id)),
			"icon": Guild.get_icon(get_guild_role(player_id)),
			"has_guild": has_guild(player_id),
			"is_master": is_guild_master(player_id)
		},
		"faction": {
			"rank": get_faction_rank(player_id),
			"name": Faction.get_name(get_faction_rank(player_id)),
			"icon": Faction.get_icon(get_faction_rank(player_id)),
			"has_faction": has_faction(player_id),
			"is_leader": is_faction_leader(player_id)
		}
	}

## Group management
func join_party(player_id: String, party_id: String, role: int = Party.MEMBER) -> void:
	if not _player_groups.has(player_id):
		_player_groups[player_id] = {}
	_player_groups[player_id]["party_id"] = party_id
	_party_roles[player_id] = role

func leave_party(player_id: String) -> void:
	if _player_groups.has(player_id):
		_player_groups[player_id].erase("party_id")
	_party_roles.erase(player_id)

func join_guild(player_id: String, guild_id: String, role: int = Guild.RECRUIT) -> void:
	if not _player_groups.has(player_id):
		_player_groups[player_id] = {}
	_player_groups[player_id]["guild_id"] = guild_id
	_guild_roles[player_id] = role

func leave_guild(player_id: String) -> void:
	if _player_groups.has(player_id):
		_player_groups[player_id].erase("guild_id")
	_guild_roles.erase(player_id)

func join_faction(player_id: String, faction_id: String, rank: int = Faction.INITIATE) -> void:
	if not _player_groups.has(player_id):
		_player_groups[player_id] = {}
	_player_groups[player_id]["faction_id"] = faction_id
	_faction_ranks[player_id] = rank

func leave_faction(player_id: String) -> void:
	if _player_groups.has(player_id):
		_player_groups[player_id].erase("faction_id")
	_faction_ranks.erase(player_id)

static func get() -> PermissionSystem:
	return instance
