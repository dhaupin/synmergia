## GuildService - Guild management
## Handles guild creation, roster, ranks, permissions, alliances, and guild vs guild
extends Node
# QoSService uses static shim methods (AGENTS.md allowlist); the const is required.
const QoSService = preload("res://core/autoload/qos_service.gd")

## Resolve CooldownService autoload safely.
func _cooldown():
	var ml = Engine.get_main_loop()
	if ml == null:
		return null
	if not ml is SceneTree:
		return null
	return (ml as SceneTree).root.get_node_or_null("CooldownService")
const DictStore = preload("res://adapters/persistence/dict_store.gd")

# Frame-level notification dispatch (see game/core/notifications/).
# _notify_player uses the typed-Kind pipeline; remove_member uses
# PLAYER_WARNED to tell the kicked member that an officer acted.
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind
const TerritoryData = preload("res://core/schemas/territory_data.gd")

# Guild data (guild_id -> guild data dict)
var _guilds: Dictionary = {}

# Player to guild mapping (entity_id -> guild_id)
var _player_guilds: Dictionary = {}

## DictStore key prefix
const _kv_prefix := "guild:"

# Guild limits (using GameConfig for centralized configuration)
const MAX_GUILD_NAME_LENGTH: int = GameConfig.Guild.MAX_NAME_LENGTH
const MAX_GUILD_SIZE: int = GameConfig.Guild.MAX_SIZE
const MAX_ALLIANCE_SIZE: int = GameConfig.Guild.MAX_ALLIANCE_SIZE
const GUILD_TAG_LENGTH: int = GameConfig.Guild.MAX_TAG_LENGTH

# Default ranks
enum GuildRank {
				GUILDMASTER = 0,
				OFFICER = 1,
				MEMBER = 2,
				RECRUIT = 3
}

# Permissions
enum Permission {
				INVITE = 1,
				KICK = 2,
				PROMOTE = 4,
				DEMOTE = 8,
				EDIT_INFO = 16,
				SET_RANK_PERMISSIONS = 32,
				CREATE_ALLIANCE = 64,
				DISBAND_ALLIANCE = 128,
				MANAGE_GVG = 256,
				WITHDRAW_GOLD = 512,
				MANAGE_NOTICES = 1024
}

# Rank permissions (defaults)
var _rank_permissions: Dictionary = {
				GuildRank.GUILDMASTER: Permission.INVITE | Permission.KICK | Permission.PROMOTE |
																Permission.DEMOTE | Permission.EDIT_INFO | Permission.SET_RANK_PERMISSIONS |
																Permission.CREATE_ALLIANCE | Permission.DISBAND_ALLIANCE |
																Permission.MANAGE_GVG | Permission.WITHDRAW_GOLD | Permission.MANAGE_NOTICES,
				GuildRank.OFFICER: Permission.INVITE | Permission.KICK | Permission.PROMOTE |
														Permission.DEMOTE | Permission.MANAGE_NOTICES,
				GuildRank.MEMBER: Permission.INVITE,
				GuildRank.RECRUIT: 0
}

# Pending applications (guild_id -> [applications])
var _pending_applications: Dictionary = {}
var _pending_guild_invites: Dictionary = {}
var _next_invite_id: int = 1
var _INVITE_TIMEOUT_SECONDS: int = 300

# Pending alliance invites (alliance_invite_id -> {alliance_id, from_guild_id, to_guild_id, timestamp})
var _pending_alliance_invites: Dictionary = {}
var _next_alliance_invite_id: int = 1

# Alliances (alliance_id -> {name, guild_ids})
var _alliances: Dictionary = {}

signal guild_created(guild_id: String, name: String, leader_id: String)
signal guild_disbanded(guild_id: String)
signal player_joined_guild(guild_id: String, player_id: String, rank: GuildRank)
signal player_left_guild(guild_id: String, player_id: String, reason: String)
signal player_kicked(guild_id: String, player_id: String, kicker_id: String)
signal rank_changed(guild_id: String, player_id: String, old_rank: GuildRank, new_rank: GuildRank)
signal leader_changed(guild_id: String, old_leader_id: String, new_leader_id: String)
signal alliance_created(alliance_id: String, name: String, guild_ids: Array)
signal alliance_disbanded(alliance_id: String)
signal alliance_guild_joined(alliance_id: String, guild_id: String)
signal alliance_guild_left(alliance_id: String, guild_id: String)
signal guild_info_updated(guild_id: String)
signal guild_notice_updated(guild_id: String, notice: String)
signal guildMOTD_updated(guild_id: String, motd: String)
signal guild_invite_sent(guild_id: String, from_id: String, to_id: String)
signal guild_invite_accepted(guild_id: String, from_id: String, to_id: String)
signal guild_invite_declined(guild_id: String, from_id: String, to_id: String)
signal guild_invite_expired(guild_id: String, to_id: String)
signal alliance_invite_sent(alliance_id: String, from_guild_id: String, to_guild_id: String)
signal alliance_invite_accepted(alliance_id: String, to_guild_id: String)
signal alliance_invite_declined(alliance_id: String, to_guild_id: String)
signal alliance_invite_expired(alliance_id: String, to_guild_id: String)

func _ready() -> void:
	GameLog.info("GuildService: Ready")
	_load_guilds()

## Create a new guild
func create_guild(name: String, tag: String, leader_id: String) -> String:
		# QoS: Rate limit guild creation
	if not QoSService.rate_limit(leader_id, "guild"):
		GameLog.debug("GuildService: Rate limited guild creation for %s" % leader_id)
		return ""

	if _player_guilds.has(leader_id):
		GameLog.warn("GuildService: Player %s already in a guild" % leader_id)
		return ""

		# Security: Validate guild name
	var name_validation := SecurityService.validate_channel_name(name)
	if not name_validation.valid:
		GameLog.warn("GuildService: Invalid guild name '%s': %s" % [name, name_validation.reason])
		return ""

		# Validate name and tag
	if name.length() > MAX_GUILD_NAME_LENGTH or name.length() < 3:
		GameLog.warn("GuildService: Invalid guild name length")
		return ""

	if tag.length() > GUILD_TAG_LENGTH or tag.length() < 2:
		GameLog.warn("GuildService: Invalid guild tag length")
		return ""

	var guild_id := "guild_%s_%d" % [tag.to_lower(), Time.get_ticks_msec()]

	var guild := {
	"id": guild_id,
	"name": name,
	"tag": tag.to_upper(),
	"leader_id": leader_id,
	"members": [{
	"id": leader_id,
	"rank": GuildRank.GUILDMASTER,
	"joined_at": Time.get_unix_time_from_system()
	}],
	"ranks": _get_default_ranks(),
	"rank_permissions": _rank_permissions.duplicate(),
	"info": {
	"description": "",
	"level": 1,
	"experience": 0,
	"gold": 0,
	"created_at": Time.get_unix_time_from_system()
	},
	"settings": {
	"min_invite_rank": GuildRank.RECRUIT,
	"public_applications": true,
	"allow_alts": true
	},
	"alliance_id": "",
	"notice": "",
	"motd": "Welcome to the guild!"
	}

	_guilds[guild_id] = guild
	_player_guilds[leader_id] = guild_id
	_persist_guild(guild_id)

	guild_created.emit(guild_id, name, leader_id)
	GameLog.info("GuildService: Created guild %s (%s)" % [name, guild_id])

	return guild_id

## Get default ranks
func _get_default_ranks() -> Dictionary:
	return {
	GuildRank.GUILDMASTER: "Guildmaster",
	GuildRank.OFFICER: "Officer",
	GuildRank.MEMBER: "Member",
	GuildRank.RECRUIT: "Recruit"
	}

## Disband a guild
func disband_guild(leader_id: String) -> bool:
	var guild_id : String = _player_guilds.get(leader_id, "")
	if guild_id == "":
		return false

	var guild : Dictionary = _guilds.get(guild_id)
	if not guild or guild["leader_id"] != leader_id:
		GameLog.warn("GuildService: Only guildmaster can disband")
		return false

		# Leave alliance first
	if guild["alliance_id"] != "":
		leave_alliance(leader_id)

		# Remove all members
	for member in guild["members"]:
		_player_guilds.erase(member["id"])

		# Clean up applications
	_pending_applications.erase(guild_id)

	_guilds.erase(guild_id)
	guild_disbanded.emit(guild_id)
	GameLog.info("GuildService: Disbanded guild %s" % guild_id)

	return true

## Invite player to guild
func invite_player(inviter_id: String, target_id: String) -> bool:
		# Use CooldownService for unified cooldown management
	if _cooldown() and not _cooldown().try_start(inviter_id, "guild_invite"):
		return false

		# Security: Check if player is guild restricted
	if SecurityService.is_restricted(inviter_id, "guild"):
		_notify_player(inviter_id, "You are temporarily restricted from guild invites.")
		return false

	if inviter_id == target_id:
		return false

	var guild_id : String = _player_guilds.get(inviter_id, "")
	if guild_id == "":
		return false

	var guild : Dictionary = _guilds.get(guild_id)
	if not guild:
		return false

		# Check if inviter has permission
	var inviter_rank := _get_member_rank(guild, inviter_id)
	if not _has_permission(inviter_rank, Permission.INVITE):
		return false

		# Check guild size
	if guild["members"].size() >= MAX_GUILD_SIZE:
		return false

		# Check if target is already in a guild
	if _player_guilds.has(target_id):
		return false

		# Create guild invite
	var invite_id := str(_next_invite_id)
	_next_invite_id += 1
	_pending_guild_invites[invite_id] = {
	"guild_id": guild_id,
	"from_id": inviter_id,
	"to_id": target_id,
	"created_at": Time.get_unix_time_from_system(),
	"expires_at": Time.get_unix_time_from_system() + _INVITE_TIMEOUT_SECONDS
	}
	guild_invite_sent.emit(guild_id, inviter_id, target_id)
	GameLog.info("GuildService: %s invited %s to guild %s (invite_id: %s)" % [inviter_id, target_id, guild_id, invite_id])

	return true

## Apply to join guild
func apply_to_guild(player_id: String, guild_id: String) -> bool:
	if _player_guilds.has(player_id):
		return false

	if not _guilds.has(guild_id):
		return false

	if not _pending_applications.has(guild_id):
		_pending_applications[guild_id] = []

		# Check if already applied
	var applications: Array = _pending_applications[guild_id]
	for app in applications:
		if app["id"] == player_id:
			return false

	applications.append({
	"id": player_id,
	"applied_at": Time.get_unix_time_from_system(),
	"message": ""
	})

	GameLog.info("GuildService: %s applied to guild %s" % [player_id, guild_id])
	return true

## Accept application
func accept_application(approver_id: String, applicant_id: String) -> bool:
	var guild_id : String = _player_guilds.get(approver_id, "")
	if guild_id == "":
		return false

	var guild : Dictionary = _guilds.get(guild_id)
	if not guild:
		return false

		# Check permission
	var approver_rank := _get_member_rank(guild, approver_id)
	if not _has_permission(approver_rank, Permission.INVITE):
		return false

		# Remove from applications
	var applications: Array = _pending_applications.get(guild_id, [])
	var removed := false
	for i in range(applications.size()):
		if applications[i]["id"] == applicant_id:
			applications.remove_at(i)
			removed = true
			break

	if not removed:
		return false

		# Add to guild
	return _add_member(guild_id, applicant_id, GuildRank.RECRUIT)

## Pending guild invites for one guild. guild_ui._refresh_pending called
## this method before it existed -- the invite browser could never
## render. Rows carry player_name (ids are display names here).
func get_pending_invites(guild_id: String) -> Array:
	var out: Array = []
	for invite_id in _pending_guild_invites.keys():
		var inv: Dictionary = _pending_guild_invites[invite_id]
		if str(inv.get("guild_id", "")) != guild_id:
			continue
		out.append({
		"id": str(invite_id),
		"player_id": str(inv.get("to_id", "")),
		"player_name": str(inv.get("to_id", "")),
		"from_id": str(inv.get("from_id", "")),
		"expires_at": float(inv.get("expires_at", 0.0))
		})
	return out

## Accept a pending guild invite by id. closes the half-built invite
## loop: invites were created, persisted, and then unreachable -- no
## accept/decline endpoint existed and guild_ui's connect map for
## guild_invite_accepted/declined fired into a stop sign.
func accept_guild_invite(invite_id: String, player_id: String) -> bool:
	var inv: Dictionary = _pending_guild_invites.get(invite_id, {})
	if inv.is_empty():
		return false
	if str(inv.get("to_id", "")) != player_id:
		return false
	if _player_guilds.has(player_id):
		_pending_guild_invites.erase(invite_id)
		_persist_invite_erase(invite_id)
		return false

	var guild_id: String = str(inv.get("guild_id", ""))
	var inviter_id: String = str(inv.get("from_id", ""))
	_pending_guild_invites.erase(invite_id)
	_persist_invite_erase(invite_id)

	if not _add_member(guild_id, player_id, GuildRank.RECRUIT):
		return false

	guild_invite_accepted.emit(guild_id, inviter_id, player_id)
	_notify_player(inviter_id, "%s accepted your guild invite." % player_id, NotifKind.SECURITY_BLOCKED, "invite_acc_%s" % invite_id)
	GameLog.info("GuildService: %s accepted invite %s into %s" % [player_id, invite_id, guild_id])
	return true

## Decline a pending guild invite by id.
func decline_guild_invite(invite_id: String, player_id: String) -> bool:
	var inv: Dictionary = _pending_guild_invites.get(invite_id, {})
	if inv.is_empty():
		return false
	if str(inv.get("to_id", "")) != player_id:
		return false

	var guild_id: String = str(inv.get("guild_id", ""))
	var inviter_id: String = str(inv.get("from_id", ""))
	_pending_guild_invites.erase(invite_id)
	_persist_invite_erase(invite_id)

	guild_invite_declined.emit(guild_id, inviter_id, player_id)
	_notify_player(inviter_id, "%s declined your guild invite." % player_id, NotifKind.SECURITY_BLOCKED, "invite_dec_%s" % invite_id)
	GameLog.info("GuildService: %s declined invite %s" % [player_id, invite_id])
	return true

## Expire sweep for BOTH invite families. Nothing swept before, so
## expired rows sat in memory and the store forever; now both lanes
## clear and announce through their *_expired signals (guild_ui's
## connect map listens on the guild one).
func _sweep_expired_invites() -> void:
	var now := Time.get_unix_time_from_system()
	for invite_id in _pending_guild_invites.keys().duplicate():
		var inv: Dictionary = _pending_guild_invites[invite_id]
		if float(inv.get("expires_at", 0.0)) <= now:
			var guild_id: String = str(inv.get("guild_id", ""))
			var to_id: String = str(inv.get("to_id", ""))
			_pending_guild_invites.erase(invite_id)
			_persist_invite_erase(invite_id)
			guild_invite_expired.emit(guild_id, to_id)
	for invite_id in _pending_alliance_invites.keys().duplicate():
		var inv: Dictionary = _pending_alliance_invites[invite_id]
		if float(inv.get("expires_at", 0.0)) <= now:
			var alliance_id: String = str(inv.get("alliance_id", ""))
			var to_guild_id: String = str(inv.get("to_guild_id", ""))
			_pending_alliance_invites.erase(invite_id)
			alliance_invite_expired.emit(alliance_id, to_guild_id)

## Throttled sweater: the invite families are tiny, so a half-minute
## cadence is plenty (GameLog.debug, never per-frame spam).
var _invite_sweep_accum: float = 0.0

func _process(delta: float) -> void:
	_invite_sweep_accum += delta
	if _invite_sweep_accum < 30.0:
		return
	_invite_sweep_accum = 0.0
	if _pending_guild_invites.is_empty() and _pending_alliance_invites.is_empty():
		return
	_sweep_expired_invites()

## Add member to guild
func _add_member(guild_id: String, player_id: String, rank: GuildRank) -> bool:
	var guild : Dictionary = _guilds.get(guild_id)
	if not guild:
		return false

	if guild["members"].size() >= MAX_GUILD_SIZE:
		return false

	if _player_guilds.has(player_id):
		return false

	guild["members"].append({
	"id": player_id,
	"rank": rank,
	"joined_at": Time.get_unix_time_from_system()
	})

	_player_guilds[player_id] = guild_id
	player_joined_guild.emit(guild_id, player_id, rank)

	return true

## Remove member from guild
func remove_member(remover_id: String, target_id: String) -> bool:
	var guild_id : String = _player_guilds.get(remover_id, "")
	if guild_id == "":
		return false

	var guild : Dictionary = _guilds.get(guild_id)
	if not guild:
		return false

		# Check if remover has kick permission or is removing self
	var remover_rank := _get_member_rank(guild, remover_id)
	if remover_id != target_id and not _has_permission(remover_rank, Permission.KICK):
		return false

		# Can't kick the guildmaster
	var target_rank := _get_member_rank(guild, target_id)
	if target_rank == GuildRank.GUILDMASTER:
		return false

	guild["members"].erase({"id": target_id})
	_player_guilds.erase(target_id)

	if remover_id != target_id:
		player_kicked.emit(guild_id, target_id, remover_id)
		# Frame-level dispatch to the kicked member. PLAYER_WARNED is
		# the right kind: an officer (a player, not the system) acted
		# against the kicked member, and the message reads as a notice
		# rather than a security block. Dedupe on (target, guild_id)
		# so a UI double-fire (officer re-clicks "kick") collapses.
		_notify_player(
			target_id,
			"You were removed from the guild by %s." % remover_id,
			NotifKind.PLAYER_WARNED,
			"kick:%s" % guild_id
		)
	else:
		player_left_guild.emit(guild_id, target_id, "Left guild")

	return true

## Leave guild
func leave_guild(player_id: String) -> bool:
	return remove_member(player_id, player_id)

## Change member rank
func change_rank(changer_id: String, target_id: String, new_rank: GuildRank) -> bool:
	var guild_id : String = _player_guilds.get(changer_id, "")
	if guild_id == "":
		return false

	var guild : Dictionary = _guilds.get(guild_id)
	if not guild:
		return false

	var changer_rank := _get_member_rank(guild, changer_id)

		# Can only promote/demote to ranks at or below your own rank
	if not _has_permission(changer_rank, Permission.PROMOTE if new_rank < changer_rank else Permission.DEMOTE):
		return false

	var old_rank := _get_member_rank(guild, target_id)

		# Can't change guildmaster rank
	if old_rank == GuildRank.GUILDMASTER:
		return false

		# Update member
	for member in guild["members"]:
		if member["id"] == target_id:
			member["rank"] = new_rank
			rank_changed.emit(guild_id, target_id, old_rank, new_rank)
			return true

	return false

## Transfer guild leadership
func transfer_leadership(current_leader_id: String, new_leader_id: String) -> bool:
	var guild_id : String = _player_guilds.get(current_leader_id, "")
	if guild_id == "":
		return false

	var guild : Dictionary = _guilds.get(guild_id)
	if not guild or guild["leader_id"] != current_leader_id:
		return false

		# Verify new leader is a member
	var new_rank := _get_member_rank(guild, new_leader_id)
	if new_rank == -1:
		return false

		# Update leader
	guild["leader_id"] = new_leader_id

		# Update ranks
	for member in guild["members"]:
		if member["id"] == current_leader_id:
			member["rank"] = GuildRank.OFFICER
		elif member["id"] == new_leader_id:
			member["rank"] = GuildRank.GUILDMASTER

	leader_changed.emit(guild_id, current_leader_id, new_leader_id)
	GameLog.info("GuildService: Leadership transferred from %s to %s" % [current_leader_id, new_leader_id])

	return true

## Get member rank
func _get_member_rank(guild: Dictionary, player_id: String) -> GuildRank:
	for member in guild["members"]:
		if member["id"] == player_id:
			return member["rank"]
	return -1

## Check if player has permission
func _has_permission(rank: GuildRank, permission: int) -> bool:
	var perms = _rank_permissions.get(rank, 0)
	return (perms & permission) != 0

## Claim a territory for a guild. MANAGE_GVG is the gate; the caller must be
## a guild member whose rank carries it. TerritoryService owns the state.
func claim_territory(guild_id: String, player_id: String, territory_id: String) -> bool:
	var guild: Dictionary = _guilds.get(guild_id, {})
	if guild.is_empty():
		return false
	var rank: int = _get_member_rank(guild, player_id)
	if rank == -1 or not _has_permission(rank, Permission.MANAGE_GVG):
		GameLog.warn("GuildService: %s lacks MANAGE_GVG for territory %s" % [player_id, territory_id])
		return false
	var territory_service = _territory_service()
	if territory_service == null:
		return false
	var claimed: bool = territory_service.claim(
		territory_id, TerritoryData.Controller.GUILD, guild_id, 50
	)
	if claimed:
		GameLog.info("GuildService: %s claimed territory %s" % [guild_id, territory_id])
	return claimed

## Read back the territories this guild controls (UI / roster surface).
func get_guild_territories(guild_id: String) -> Array:
	var territory_service = _territory_service()
	if territory_service == null:
		return []
	return territory_service.territories_for_guild(guild_id)

func _territory_service():
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath("TerritoryService"))

## Create alliance
func create_alliance(leader_id: String, name: String) -> String:
	var guild_id : String = _player_guilds.get(leader_id, "")
	if guild_id == "":
		return ""

	var guild : Dictionary = _guilds.get(guild_id)
	if not guild or guild["leader_id"] != leader_id:
		return ""

		# Check if already in alliance
	if guild["alliance_id"] != "":
		return ""

	var alliance_id := "alliance_%d" % Time.get_ticks_msec()

	_alliances[alliance_id] = {
	"id": alliance_id,
	"name": name,
	"guild_ids": [guild_id]
	}

	guild["alliance_id"] = alliance_id
	alliance_created.emit(alliance_id, name, [guild_id])
	GameLog.info("GuildService: Created alliance %s" % alliance_id)

	return alliance_id

## Invite guild to alliance
func invite_to_alliance(inviter_id: String, target_guild_id: String) -> bool:
	var guild_id : String = _player_guilds.get(inviter_id, "")
	if guild_id == "":
		return false

	var guild : Dictionary = _guilds.get(guild_id)
	if not guild or guild["leader_id"] != inviter_id:
		return false

	if guild["alliance_id"] == "":
		return false

	var alliance: Dictionary = _alliances.get(guild["alliance_id"], {})
	if alliance.is_empty():
		return false

	if alliance["guild_ids"].size() >= MAX_ALLIANCE_SIZE:
		return false

		# Create alliance invite
	var invite_id := str(_next_alliance_invite_id)
	_next_alliance_invite_id += 1
	_pending_alliance_invites[invite_id] = {
	"alliance_id": alliance["id"],
	"from_guild_id": guild_id,
	"to_guild_id": target_guild_id,
	"created_at": Time.get_unix_time_from_system(),
	"expires_at": Time.get_unix_time_from_system() + _INVITE_TIMEOUT_SECONDS
	}
	alliance_invite_sent.emit(alliance["id"], guild_id, target_guild_id)
	GameLog.info("GuildService: Guild %s invited to alliance %s (invite_id: %s)" % [target_guild_id, alliance["id"], invite_id])

	return true

## Join alliance
func join_alliance(leader_id: String, alliance_id: String) -> bool:
	var guild_id : String = _player_guilds.get(leader_id, "")
	if guild_id == "":
		return false

	var guild : Dictionary = _guilds.get(guild_id)
	if not guild or guild["leader_id"] != leader_id:
		return false

	if guild["alliance_id"] != "":
		return false

	var alliance: Dictionary = _alliances.get(alliance_id, {})
	if alliance.is_empty():
		return false

	if alliance["guild_ids"].size() >= MAX_ALLIANCE_SIZE:
		return false

	alliance["guild_ids"].append(guild_id)
	guild["alliance_id"] = alliance_id
	alliance_guild_joined.emit(alliance_id, guild_id)

	return true

## Leave alliance
func leave_alliance(leader_id: String) -> bool:
	var guild_id : String = _player_guilds.get(leader_id, "")
	if guild_id == "":
		return false

	var guild : Dictionary = _guilds.get(guild_id)
	if not guild or guild["leader_id"] != leader_id:
		return false

	var alliance_id: String = guild["alliance_id"]
	if alliance_id == "":
		return false

	var alliance: Dictionary = _alliances.get(alliance_id, {})
	if not alliance.is_empty():
		alliance["guild_ids"].erase(guild_id)

		# Disband if only one guild left
		if alliance["guild_ids"].size() <= 1:
			_alliances.erase(alliance_id)
			alliance_disbanded.emit(alliance_id)
		# Update remaining guild
			for remaining_id in alliance["guild_ids"]:
				var remaining_guild: Dictionary = _guilds.get(remaining_id, {})
				if not remaining_guild.is_empty():
					remaining_guild["alliance_id"] = ""

		alliance_guild_left.emit(alliance_id, guild_id)

	guild["alliance_id"] = ""
	return true

## Get guild by ID
func get_guild(guild_id: String) -> Dictionary:
	return _guilds.get(guild_id, {})

## Get player's guild
func get_player_guild(player_id: String) -> Dictionary:
	var guild_id : String = _player_guilds.get(player_id, "")
	return get_guild(guild_id)

## Check if player is in a guild
func is_in_guild(player_id: String) -> bool:
	return _player_guilds.has(player_id)

## Get guild roster
func get_guild_roster(guild_id: String) -> Array:
	var guild : Dictionary = _guilds.get(guild_id, {})
	return guild.get("members", [])

## Set guild info
func set_guild_info(leader_id: String, description: String) -> bool:
	var guild_id : String = _player_guilds.get(leader_id, "")
	if guild_id == "":
		return false

	var guild : Dictionary = _guilds.get(guild_id)
	if not guild or guild["leader_id"] != leader_id:
		return false

	guild["info"]["description"] = description
	guild_info_updated.emit(guild_id)

	return true

## Set guild notice
func set_guild_notice(leader_id: String, notice: String) -> bool:
	var guild_id : String = _player_guilds.get(leader_id, "")
	if guild_id == "":
		return false

	var guild : Dictionary = _guilds.get(guild_id)
	if not guild:
		return false

	var rank := _get_member_rank(guild, leader_id)
	if not _has_permission(rank, Permission.MANAGE_NOTICES):
		return false

	guild["notice"] = notice
	guild_notice_updated.emit(guild_id, notice)

	return true

## Set MOTD
func set_guild_motd(leader_id: String, motd: String) -> bool:
	var guild_id : String = _player_guilds.get(leader_id, "")
	if guild_id == "":
		return false

	var guild : Dictionary = _guilds.get(guild_id)
	if not guild:
		return false

	var rank := _get_member_rank(guild, leader_id)
	if not _has_permission(rank, Permission.MANAGE_NOTICES):
		return false

	guild["motd"] = motd
	guildMOTD_updated.emit(guild_id, motd)

	return true

## Get alliance info
func get_alliance(alliance_id: String) -> Dictionary:
	return _alliances.get(alliance_id, {})

## Get guild's alliance
func get_guild_alliance(guild_id: String) -> Dictionary:
	var guild : Dictionary = _guilds.get(guild_id, {})
	if guild.is_empty():
		return {}
	return get_alliance(guild.get("alliance_id", ""))

# ============ GUILD BANK ============

## Initialize guild bank
func _init_guild_bank(guild: Dictionary) -> void:
	if not guild.has("bank"):
		guild["bank"] = {"gold": 0, "items": [], "logs": []}
		guild["bank_tabs"] = [{"name": "Main", "size": 98, "unlocked": true}]

## Get guild bank
func get_guild_bank(guild_id: String) -> Dictionary:
	var guild : Dictionary = _guilds.get(guild_id, {})
	if guild.is_empty():
		return {}
	if not guild.has("bank"):
		_init_guild_bank(guild)
	return guild.get("bank", {})

## Deposit gold to guild bank
func deposit_gold(player_id: String, amount: int) -> bool:
	var guild_id : String = _player_guilds.get(player_id, "")
	if guild_id == "":
		return false
	var guild : Dictionary = _guilds.get(guild_id)
	if not guild:
		return false
	if not guild.has("bank"):
		_init_guild_bank(guild)
	guild["bank"]["gold"] += amount
	_log_bank_transaction(guild, "deposit_gold", player_id, {"amount": amount})
	GameLog.info("GuildService: %s deposited %d gold" % [player_id, amount])
	return true

## Withdraw gold from guild bank
func withdraw_gold(player_id: String, amount: int) -> bool:
	var guild_id : String = _player_guilds.get(player_id, "")
	if guild_id == "":
		return false
	var guild : Dictionary = _guilds.get(guild_id)
	if not guild:
		return false
	if not guild.has("bank"):
		_init_guild_bank(guild)
	if guild["bank"]["gold"] < amount:
		return false
	guild["bank"]["gold"] -= amount
	_log_bank_transaction(guild, "withdraw_gold", player_id, {"amount": amount})
	return true

## Deposit item to guild bank
func deposit_item(player_id: String, item_id: String, quantity: int, tab_index: int = 0) -> bool:
	var guild_id : String = _player_guilds.get(player_id, "")
	if guild_id == "":
		return false
	var guild : Dictionary = _guilds.get(guild_id)
	if not guild:
		return false
	if not guild.has("bank"):
		_init_guild_bank(guild)
	var items: Array = guild["bank"]["items"]
	for item in items:
		if item["item_id"] == item_id:
			item["quantity"] += quantity
			_log_bank_transaction(guild, "deposit_item", player_id, {"item_id": item_id, "quantity": quantity})
			return true
	items.append({"item_id": item_id, "quantity": quantity, "deposited_by": player_id, "deposited_at": Time.get_unix_time_from_system(), "tab": tab_index})
	_log_bank_transaction(guild, "deposit_item", player_id, {"item_id": item_id, "quantity": quantity})
	return true

## Withdraw item from guild bank
func withdraw_item(player_id: String, item_id: String, quantity: int) -> bool:
	var guild_id : String = _player_guilds.get(player_id, "")
	if guild_id == "":
		return false
	var guild : Dictionary = _guilds.get(guild_id)
	if not guild or not guild.has("bank"):
		return false
	var items: Array = guild["bank"]["items"]
	for i in range(items.size()):
		var item: Dictionary = items[i]
		if item["item_id"] == item_id and item["quantity"] >= quantity:
			item["quantity"] -= quantity
			if item["quantity"] <= 0:
				items.remove_at(i)
			_log_bank_transaction(guild, "withdraw_item", player_id, {"item_id": item_id, "quantity": quantity})
			return true
	return false

## Get bank items for a tab
func get_bank_items(guild_id: String, tab_index: int = 0) -> Array:
	var guild : Dictionary = _guilds.get(guild_id, {})
	if guild.is_empty():
		return []
	var items: Array = guild.get("bank", {}).get("items", [])
	var tab_items: Array = []
	for item in items:
		if item.get("tab", 0) == tab_index:
			tab_items.append(item)
	return tab_items

## Get bank gold
func get_bank_gold(guild_id: String) -> int:
	var guild : Dictionary = _guilds.get(guild_id, {})
	if guild.is_empty():
		return 0
	return guild.get("bank", {}).get("gold", 0)

## Get bank logs
func get_bank_logs(guild_id: String, limit: int = 20) -> Array:
	var guild : Dictionary = _guilds.get(guild_id, {})
	if guild.is_empty():
		return []
	var logs: Array = guild.get("bank", {}).get("logs", [])
	return logs.slice(max(0, logs.size() - limit), logs.size())

## Log bank transaction
func _log_bank_transaction(guild: Dictionary, transaction_type: String, player_id: String, data: Dictionary) -> void:
	if not guild.has("bank"):
		return
	var logs: Array = guild["bank"]["logs"]
	logs.append({"type": transaction_type, "player_id": player_id, "data": data, "timestamp": Time.get_unix_time_from_system()})
	while logs.size() > 100:
		logs.pop_at(0)

## ============================================================================
## PLAYER NOTIFICATIONS
## ============================================================================

## Send notification to player. Defaults to SECURITY_BLOCKED because
## today's call sites (e.g. bank deposit failures) surface as warnings
## a player needs to act on; callers can override.
func _notify_player(player_id: String, message: String, kind: int = NotifKind.SECURITY_BLOCKED, dedupe_key_suffix: String = "guild") -> void:
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			kind,
			message,
			"GuildService",
			"guild_notif:%s:%s:%s" % [player_id, dedupe_key_suffix, message.hash()],
			{"player_id": player_id},
			player_id
		)
		GameLog.debug("GuildService: Notified %s: %s" % [player_id, message])

## == Persistence ============================================================

func _load_guilds() -> void:
	var store := DictStore.new()
	_guilds = {}
	_player_guilds = {}
	var keys: Array = store.all_keys()
	var guild_keys: Array = []
	for key in keys:
		if key.begins_with(_kv_prefix) and ":" in key:
			var parts = key.split(":")
			if parts.size() >= 3:
				guild_keys.append(key)

	if not guild_keys.is_empty():
		var results: Dictionary = store.get_many(guild_keys)
		for key in guild_keys:
			var parts = key.split(":")
			if parts.size() >= 3:
				var guild_id = parts[1] + ":" + parts[2]
				_guilds[guild_id] = results.get(key, {})
				# Rebuild player->guild mapping
				var members = _guilds[guild_id].get("members", [])
				for member in members:
					if member is Dictionary and member.has("id"):
						_player_guilds[member["id"]] = guild_id

func _persist_guild(guild_id: String) -> void:
	var store := DictStore.new()
	if _guilds.has(guild_id):
		store.set_kv(_kv_prefix + guild_id, _guilds[guild_id])
	else:
		store.erase(_kv_prefix + guild_id)

## Persist one invite row. The old body indexed _pending_guild_invites
## by player_id, but the dict is keyed by invite_id, so the row never
## matched and invite writes silently did nothing. Keyed by invite_id
## now, matching persist_all's store layout.
func _persist_invite(invite_id: String) -> void:
	var store := DictStore.new()
	if _pending_guild_invites.has(invite_id):
		store.set_kv("guild:invite:" + invite_id, _pending_guild_invites[invite_id])

## Erase a persisted invite row when its live row dies (accept,
## decline, expire). Same kv lane as _persist_invite / persist_all.
func _persist_invite_erase(invite_id: String) -> void:
	var store := DictStore.new()
	store.erase("guild:invite:" + invite_id)


func persist_all() -> void:
	var store := DictStore.new()
	var entries: Dictionary = {}
	for guild_id in _guilds.keys():
		entries[_kv_prefix + guild_id] = _guilds[guild_id]
	for player_id in _pending_guild_invites.keys():
		entries["guild:invite:" + player_id] = _pending_guild_invites[player_id]
	if not entries.is_empty():
		store.set_batch(entries)
