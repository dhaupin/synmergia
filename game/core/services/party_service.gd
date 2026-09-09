## PartyService - Party management
## Handles party creation, invites, member management, loot rules, and XP sharing
extends Node

## Resolve CooldownService autoload safely.
func _cooldown():
	var ml = Engine.get_main_loop()
	if ml == null:
		return null
	if not ml is SceneTree:
		return null
	return (ml as SceneTree).root.get_node_or_null("CooldownService")
const CharacterData = preload("res://core/schemas/character_data.gd")
const QoSService = preload("res://core/autoload/qos_service.gd")
const DictStore = preload("res://adapters/persistence/dict_store.gd")

# Frame-level notification dispatch (see game/core/notifications/).
# kick_player dispatches a PARTY kind toast to the kicked member so
# they know it was a leader action (vs. a disconnect or a disband).
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

# Party data (party_id -> party data dict)
var _parties: Dictionary = {}

# Player to party mapping (entity_id -> party_id)
var _player_parties: Dictionary = {}

# Party limits (using GameConfig for centralized configuration)
const MAX_PARTY_SIZE: int = GameConfig.Party.MAX_SIZE
const MAX_PARTY_ROSTER_SIZE: int = GameConfig.Party.MAX_ROSTER_SIZE
const INVITE_TIMEOUT_SECONDS: float = GameConfig.Party.INVITE_TIMEOUT_SECONDS

# Pending invites (invite_id -> {from, to, timestamp})
var _pending_invites: Dictionary = {}
var _next_invite_id: int = 1

const _kv_party := "party:"
const _kv_invite := "party:invite:"

# Loot rules
enum LootRule {
				FREE_FOR_ALL,		 # Everyone can loot
				ROUND_ROBIN,		 # Rotate who can loot
				LEADER,					 # Only leader can loot
				MASTER_LOOTER		 # Leader assigns loot
}

signal party_created(party_id: String, leader_id: String)
signal party_disbanded(party_id: String)
signal player_joined_party(party_id: String, player_id: String)
signal player_left_party(party_id: String, player_id: String, reason: String)
signal party_invite_sent(from_id: String, to_id: String)
signal party_invite_accepted(from_id: String, to_id: String)
signal party_invite_declined(from_id: String, to_id: String)
signal party_invite_expired(invite_id: String)
signal leader_changed(party_id: String, old_leader_id: String, new_leader_id: String)
signal loot_rule_changed(party_id: String, rule: LootRule)
signal party_member_updated(party_id: String, player_id: String)
signal xp_shared(party_id: String, base_xp: int, xp_distribution: Dictionary, killer_id: String)

func _ready() -> void:
	GameLog.info("PartyService: Ready")

	_load_parties()

## Create a new party
func create_party(leader_id: String, is_raid: bool = false) -> String:
		# QoS: Rate limit party creation (player notified by QoSService)
	if not QoSService.rate_limit(leader_id, "party"):
		return ""

		# Security: Check if player is party restricted
	if SecurityService.is_restricted(leader_id, "party"):
		_notify_player(leader_id, "You are temporarily restricted from creating parties.")
		return ""

	if _player_parties.has(leader_id):
		GameLog.warn("PartyService: Player %s already in a party" % leader_id)
		return ""

	var party_id := "party_%s_%d" % [leader_id, Time.get_ticks_msec()]
	var party := {
	"id": party_id,
	"leader_id": leader_id,
	"is_raid": is_raid,
	"members": [leader_id],
	"max_size": MAX_PARTY_ROSTER_SIZE if is_raid else MAX_PARTY_SIZE,
	"loot_rule": LootRule.FREE_FOR_ALL,
	"xp_share_enabled": true,
	"created_at": Time.get_unix_time_from_system()
	}

	_parties[party_id] = party
	_player_parties[leader_id] = party_id

	_persist_party(party_id)

	party_created.emit(party_id, leader_id)
	GameLog.info("PartyService: Created party %s with leader %s" % [party_id, leader_id])

	return party_id

## Disband a party
func disband_party(party_id: String) -> bool:
		# QoS: Rate limit party disband
	if not QoSService.rate_limit(party_id, "party"):
		GameLog.debug("PartyService: Rate limited party disband for %s" % party_id)
		return false

	var party: Dictionary = _parties.get(party_id)
	if not party:
		return false

		# Remove all members from party tracking
	for member_id in party["members"]:
		_player_parties.erase(member_id)

		# Emit events for each member
	for member_id in party["members"]:
		player_left_party.emit(party_id, member_id, "Party disbanded")

	_parties.erase(party_id)
	_persist_party(party_id)
	party_disbanded.emit(party_id)
	GameLog.info("PartyService: Disbanded party %s" % party_id)

	return true

## Invite a player to party
func invite_player(from_id: String, to_id: String) -> bool:
		# Use CooldownService for unified cooldown management
	if _cooldown() and not _cooldown().try_start(from_id, "party_invite"):
		return false

		# Security: Check if player is party restricted
	if SecurityService.is_restricted(from_id, "party"):
		_notify_player(from_id, "You are temporarily restricted from party invites.")
		return false

	if from_id == to_id:
		return false

		# Check if inviter is in a party
	var inviter_party_id: String = _player_parties.get(from_id, "")
	if inviter_party_id == "":
		GameLog.warn("PartyService: Inviter %s not in a party" % from_id)
		return false

	var party: Dictionary = _parties.get(inviter_party_id)
	if not party:
		return false

		# Check party size
	if party["members"].size() >= party["max_size"]:
		GameLog.warn("PartyService: Party %s is full" % inviter_party_id)
		return false

		# Check if invitee is already in a party
	if _player_parties.has(to_id):
		GameLog.warn("PartyService: Target %s already in a party" % to_id)
		return false

		# Create invite
	var invite_id := "invite_%d" % _next_invite_id
	_next_invite_id += 1

	_pending_invites[invite_id] = {
	"from": from_id,
	"to": to_id,
	"party_id": inviter_party_id,
	"timestamp": Time.get_unix_time_from_system()
	}

	_persist_invite(invite_id)

	party_invite_sent.emit(from_id, to_id)
	GameLog.info("PartyService: Invite %s from %s to %s" % [invite_id, from_id, to_id])

		# Set up expire timer (simplified - in production use a proper timer)
	return true

## Accept a party invite
func accept_invite(to_id: String) -> bool:
		# Find the invite for this player
	for invite_id in _pending_invites:
		var invite: Dictionary = _pending_invites[invite_id]
		if invite["to"] == to_id:
			var party_id: String = invite["party_id"]
			var from_id: String = invite["from"]

		# Remove expired invites
			var age: float = Time.get_unix_time_from_system() - invite["timestamp"]
			if age > INVITE_TIMEOUT_SECONDS:
				_pending_invites.erase(invite_id)
				party_invite_expired.emit(invite_id)
				return false

		# Add to party
			var party: Dictionary = _parties.get(party_id)
			if party and party["members"].size() < party["max_size"]:
				party["members"].append(to_id)
				_player_parties[to_id] = party_id
				_pending_invites.erase(invite_id)
				_persist_invite(invite_id)
				_persist_party(party_id)

				player_joined_party.emit(party_id, to_id)
				party_invite_accepted.emit(from_id, to_id)
				GameLog.info("PartyService: %s joined party %s" % [to_id, party_id])
				return true

	return false

## Decline a party invite
func decline_invite(to_id: String) -> bool:
	for invite_id in _pending_invites:
		var invite: Dictionary = _pending_invites[invite_id]
		if invite["to"] == to_id:
			var from_id: String = invite["from"]
			_pending_invites.erase(invite_id)
			_persist_invite(invite_id)
			party_invite_declined.emit(from_id, to_id)
			GameLog.info("PartyService: %s declined invite from %s" % [to_id, from_id])
			return true

	return false

## Leave a party
func leave_party(player_id: String) -> bool:
	var party_id: String = _player_parties.get(player_id, "")
	if party_id == "":
		return false

	var party: Dictionary = _parties.get(party_id)
	if not party:
		return false

		# Remove from members
	party["members"].erase(player_id)
	_player_parties.erase(player_id)

		# If leader left, assign new leader
	var old_leader: String = party["leader_id"]
	if player_id == old_leader:
		if party["members"].size() > 0:
			party["leader_id"] = party["members"][0]
			leader_changed.emit(party_id, old_leader, party["leader_id"])
			GameLog.info("PartyService: New leader %s for party %s" % [party["leader_id"], party_id])
		else:
		# No members left, disband
			disband_party(party_id)
			return true

	player_left_party.emit(party_id, player_id, "Left party")
	GameLog.info("PartyService: %s left party %s" % [player_id, party_id])

		# Check if party should be disbanded
	if party["members"].size() == 0:
		disband_party(party_id)

	return true

## Kick a player from party
func kick_player(leader_id: String, target_id: String) -> bool:
	var party_id: String = _player_parties.get(leader_id, "")
	if party_id == "":
		return false

	var party: Dictionary = _parties.get(party_id)
	if not party or party["leader_id"] != leader_id:
		GameLog.warn("PartyService: Only leader can kick players")
		return false

	if not party["members"].has(target_id):
		return false

	party["members"].erase(target_id)
	_player_parties.erase(target_id)
	player_left_party.emit(party_id, target_id, "Kicked by leader")
	GameLog.info("PartyService: Kicked %s from party %s" % [target_id, party_id])

	# Frame-level dispatch. PLAYER_WARNED -> ALERT + NORMAL. The kicked
	# member needs to know it was a leader action (so they don't think
	# the party just disbanded or they disconnected). Dedupe on
	# (target, party_id) so a kick from a different party leader within
	# the 2s PLAYER_WARNED window still surfaces, but a re-kick from
	# the same leader for the same party (e.g. a UI double-fire) collapses.
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.PLAYER_WARNED,
			"You were kicked from the party by %s." % leader_id,
			"PartyService",
			"party_kick:%s:%s" % [target_id, party_id],
			{"party_id": party_id, "leader_id": leader_id, "event": "kicked"},
			target_id
		)

	return true

## Get party by ID
func get_party(party_id: String) -> Dictionary:
	return _parties.get(party_id, {})

## Get player's party
func get_player_party(player_id: String) -> Dictionary:
	var party_id: String = _player_parties.get(player_id, "")
	return get_party(party_id)

## Get party members
func get_party_members(party_id: String) -> Array:
	var party: Dictionary = _parties.get(party_id, {})
	return party.get("members", [])

## Get enriched party member data with names, classes, and GM status
func get_party_member_details(party_id: String) -> Array[Dictionary]:
	var party: Dictionary = _parties.get(party_id, {})
	var member_ids: Array = party.get("members", [])
	var details: Array[Dictionary] = []

	for member_id in member_ids:
		var detail: Dictionary = {"id": member_id, "name": "?", "class": "?", "is_gm": false, "is_leader": false}

		# Get player entity data
		var entity = EntityService.get_entity(member_id) if EntityService else null
		if entity:
			var char_data = entity.get("character_data") if entity else null
			if char_data:
				detail["name"] = char_data.get("display_name", member_id)
				detail["class"] = char_data.get("class_id", "?")
				if char_data.has("is_gm"):
					detail["is_gm"] = char_data.is_gm()
				elif char_data.has("class_id"):
					detail["is_gm"] = CharacterData.is_gm_class(char_data.get("class_id"))
			else:
				detail["name"] = entity.get("display_name", member_id)
		else:
			detail["name"] = member_id

		# Check if leader
		if party.get("leader_id", "") == member_id:
			detail["is_leader"] = true

		details.append(detail)

	return details

## Check if player is in a party
func is_in_party(player_id: String) -> bool:
	return _player_parties.has(player_id)

## Get party size
func get_party_size(party_id: String) -> int:
	var party: Dictionary = _parties.get(party_id)
	return party["members"].size() if party else 0

## Set loot rule
func set_loot_rule(leader_id: String, rule: LootRule) -> bool:
	var party_id: String = _player_parties.get(leader_id, "")
	if party_id == "":
		return false

	var party: Dictionary = _parties.get(party_id)
	if not party or party["leader_id"] != leader_id:
		return false

	party["loot_rule"] = rule
	loot_rule_changed.emit(party_id, rule)
	GameLog.info("PartyService: Loot rule changed to %s for party %s" % [LootRule.keys()[rule], party_id])

	return true

## Promote member to leader
func promote_to_leader(current_leader_id: String, new_leader_id: String) -> bool:
	var party_id: String = _player_parties.get(current_leader_id, "")
	if party_id == "":
		return false

	var party: Dictionary = _parties.get(party_id)
	if not party or party["leader_id"] != current_leader_id:
		return false

	if not party["members"].has(new_leader_id):
		return false

	var old_leader: String = party["leader_id"]
	party["leader_id"] = new_leader_id

		# Move old leader to end of members list
	party["members"].erase(new_leader_id)
	party["members"].insert(0, new_leader_id)
	party["members"].append(old_leader)

	leader_changed.emit(party_id, old_leader, new_leader_id)
	GameLog.info("PartyService: Promoted %s to leader of party %s" % [new_leader_id, party_id])

	return true

## Get nearby party members (for sharing buffs, XP, etc.)
func get_nearby_members(player_id: String, range: float = 100.0) -> Array[String]:
	var party_id: String = _player_parties.get(player_id, "")
	if party_id == "":
		return []

	var party: Dictionary = _parties.get(party_id)
	if not party:
		return []

		# This would need access to player positions
		# For now, return all members except self
	var nearby: Array[String] = []
	for member_id in party["members"]:
		if member_id != player_id:
			nearby.append(member_id)

	return nearby

## Share XP with party members
func share_xp(party_id: String, base_xp: int, killer_id: String) -> Dictionary:
	var party: Dictionary = _parties.get(party_id)
	if not party:
		return {}

	var members: Array = party["members"]
	var member_count: int = members.size()

	# Guard against empty party
	if member_count == 0:
		return {}

	# XP sharing bonus per additional member
	var xp_bonus: float = 1.0 + (member_count - 1) * 0.1

	var xp_distribution: Dictionary = {}
	for member_id in members:
		var xp := int(base_xp * xp_bonus / member_count)
		xp_distribution[member_id] = xp

	return xp_distribution

## Periodic cleanup of expired invites
func _process(delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	var to_remove: Array = []

	for invite_id in _pending_invites:
		var invite: Dictionary = _pending_invites[invite_id]
		var age: float = now - invite.get("timestamp", 0.0)
		if age > INVITE_TIMEOUT_SECONDS:
			to_remove.append(invite_id)

	for invite_id in to_remove:
		_pending_invites.erase(invite_id)
		party_invite_expired.emit(invite_id)


func _notify_player(player_id: String, message: String, kind: int = NotifKind.SECURITY_BLOCKED) -> void:
	if not is_instance_valid(NotificationService):
		GameLog.warn("PartyService: NotificationService not available, cannot notify %s" % player_id)
		return
	# Frame-level dispatch. Default kind is SECURITY_BLOCKED because
	# both call sites (line 57/117) are security-driven restrictions
	# from SecurityService.is_restricted.
	NotificationService.notify(
		kind,
		message,
		"PartyService",
		"party_notif:%s:%s" % [player_id, message.hash()],
		{"player_id": player_id},
		player_id
	)

func _load_parties() -> void:
	var store := DictStore.new()
	var keys := store.all_keys()
	for key in keys:
		if key.begins_with(_kv_party):
			var data := store.get(key)
			if data:
				var party_id := key.substr(_kv_party.length())
				_parties[party_id] = data
				for member_id in data.get("members", []):
					_player_parties[member_id] = party_id
		elif key.begins_with(_kv_invite):
			var data := store.get(key)
			if data:
				var invite_id := key.substr(_kv_invite.length())
				_pending_invites[invite_id] = data

func _persist_party(party_id: String) -> void:
	var store := DictStore.new()
	var key := _kv_party + party_id
	if _parties.has(party_id) and not _parties[party_id].is_empty():
		store.set(key, _parties[party_id])
	else:
		store.erase(key)

func _persist_invite(invite_id: String) -> void:
	var store := DictStore.new()
	var key := _kv_invite + invite_id
	if _pending_invites.has(invite_id) and not _pending_invites[invite_id].is_empty():
		store.set(key, _pending_invites[invite_id])
	else:
		store.erase(key)
