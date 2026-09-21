## LootRulesService - delegation and smart/fair routing for ground drops.
##
## Given a drop and a candidate looter, resolve_delegation() answers one
## question: may THIS player pick it up right now?
##   "" returned -> yes, no delegation applies
##   non-""      -> blocked; the drop is reserved for someone else
##
## Layers, checked in order:
##   1. Karma gate      -- drops can carry "karma_min"; candidates below
##                         it are barred (future faction/honor systems).
##   2. Guild lock      -- drops with owner_id "guild:<id>" are reserved
##                         for that guild's members.
##   3. Party rules     -- FREE_FOR_ALL / ROUND_ROBIN / LEADER /
##                         MASTER_LOOTER on the credit player's party.
##   4. Smart routing   -- class-locked items (required_class) that
##                         exactly one party member can use are
##                         auto-delegated to that member regardless of
##                         the party rule. "Fair" beats "random" when
##                         only one person benefits.
##
## Sources feed context in through drop options (see create_drop):
##   "credit_player_id" -- who the kill is credited to (threat fallback
##                         resolved by the caller, same semantics as XP).
##   "karma_min"        -- minimum karma to loot (default: none).
##
## Round-robin is pointer-based: the turn marker advances only when the
## designated member actually picks up a drop, never on failed attempts.
extends Node

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

signal delegation_changed(drop_id: String, delegated_to: String, reason: String)

enum Policy { FREE_FOR_ALL, ROUND_ROBIN, LEADER, MASTER_LOOTER }

## Max tracked designations before pruning (despawned drops leak a
## few bytes each; this keeps the map bounded).
const MAX_PENDING_DESIGNATIONS: int = 512

var _round_robin_next: Dictionary = {}   # party_id -> member_id whose turn it is
var _pending_designations: Dictionary = {}  # drop_id -> {party_id, designated}

## Test seams / headless registries (checked before autoloads).
var _party_override: Dictionary = {}   # player_id -> party dict
var _guild_override: Dictionary = {}   # player_id -> guild_id
var _class_override: Dictionary = {}   # player_id -> class string
## Optional karma source for drops with "karma_min" (overrides the
## RespawnService lookup when valid).
var karma_lookup: Callable = Callable()


func _ready() -> void:
	# NOTE: do not reference GroundLootService as a bare identifier here.
	# GroundLootService references this service (the delegation gate), and
	# a bare-identifier cycle aborts the script-mode autoload registry
	# build, breaking compile-time resolution for every autoload. Lazy
	# resolution breaks the cycle (same convention as script-mode tests).
	var gls = _resolve("GroundLootService")
	if gls != null and gls.has_signal("drop_picked_up") \
			and not gls.drop_picked_up.is_connected(_on_drop_picked_up):
		gls.drop_picked_up.connect(_on_drop_picked_up)
	GameLog.info("LootRulesService: Ready")


## ---------------------------------------------------------------------------
## CORE RESOLUTION
## ---------------------------------------------------------------------------

## May candidate_id pick up this drop? "" = yes; non-empty = blocked.
## The credit player may always loot their own kill (pragmatic deadlock
## breaker when the designated member has wandered off).
func resolve_delegation(drop: Dictionary, candidate_id: String) -> String:
	if candidate_id == "":
		return "no-candidate"

	# 1. Karma gate (future faction/honor systems; no-op by default).
	if drop.has("karma_min"):
		var karma: int = -2147483648
		if karma_lookup.is_valid():
			karma = int(karma_lookup.call(candidate_id))
		else:
			# Lazy /root resolution: RespawnService is registered earlier,
			# but a bare identifier here closes a parse-time cycle with
			# GroundLootService (which forward-references this service).
			var rs = get_node_or_null(NodePath("/root/RespawnService"))
			if rs != null and rs.has_method("get_karma"):
				karma = int(rs.get_karma(candidate_id))
		if karma != -2147483648 and karma < int(drop["karma_min"]):
			return _not_you(drop, candidate_id, "karma")

	# 2. Guild lock: owner_id "guild:<id>".
	var owner_id := str(drop.get("owner_id", ""))
	if owner_id.begins_with("guild:"):
		if _is_guild_member(candidate_id, owner_id.trim_prefix("guild:")):
			return ""
		return _not_you(drop, candidate_id, "guild")

	# 3. Party rules -- enemy-credit drops when the credit player is in
	# a party with a non-FFA rule.
	var credit_id := str(drop.get("credit_player_id", ""))
	if credit_id == "":
		return ""
	var party: Dictionary = _party_of(credit_id)
	if party.is_empty():
		return ""
	var policy := int(party.get("loot_rule", Policy.FREE_FOR_ALL))
	if policy == Policy.FREE_FOR_ALL:
		return ""

	# Designation is computed and recorded BEFORE the credit-player
	# check: when the designated member IS the credit player (a common
	# case), their pickup must still advance the round-robin pointer.
	var designated := _designated_looter(drop, party)
	if designated != "":
		_pending_designations[str(drop.get("id", ""))] = {
			"party_id": str(party.get("party_id", "")),
			"designated": designated,
		}
		_prune_pending()

	# The credit player may always loot their own kill (pragmatic
	# deadlock breaker when the designated member has wandered off).
	if credit_id == candidate_id:
		return ""
	if designated == "" or designated == candidate_id:
		return ""
	return _not_you(drop, candidate_id, "party_rule")


## Who is the drop for under this party's rule? "" = anyone.
func _designated_looter(drop: Dictionary, party: Dictionary) -> String:
	var members: Array = party.get("members", [])
	if members.is_empty():
		return ""
	var party_id := str(party.get("party_id", ""))
	var policy := int(party.get("loot_rule", Policy.FREE_FOR_ALL))

	match policy:
		Policy.LEADER, Policy.MASTER_LOOTER:
			var leader_id := str(party.get("leader_id", ""))
			# Smart routing: a class-locked item exactly one member can
			# use goes straight to that member; the leader holds the
			# rest (master loot distributes from there by hand).
			var smart := _smart_class_route(drop, members, leader_id)
			if smart != "":
				return smart
			return leader_id
		Policy.ROUND_ROBIN:
			var current := str(_round_robin_next.get(party_id, ""))
			if current == "" or not members.has(current):
				current = str(members[0])
			return current
	return ""


## If the drop's items are all class-locked and exactly ONE member can
## use them, return that member. Empty otherwise.
func _smart_class_route(drop: Dictionary, members: Array, fallback: String) -> String:
	var items: Array = drop.get("items", [])
	var needed_class := ""
	for item in items:
		var req := ""
		if item != null and "required_class" in item:
			req = str(item.required_class)
		if req == "":
			return ""  # at least one universally usable item -> normal rule
		if needed_class == "":
			needed_class = req
		elif needed_class != req:
			return ""  # mixed class locks -> no unambiguous owner

	# Leader counts as a member first; if the leader matches, normal rule.
	if _class_matches(fallback, needed_class):
		return ""
	var eligible: Array[String] = []
	for member_id in members:
		if _class_matches(str(member_id), needed_class):
			eligible.append(str(member_id))
	if eligible.size() == 1:
		return eligible[0]
	return ""


## ---------------------------------------------------------------------------
## ROUND-ROBIN POINTER ADVANCE
## ---------------------------------------------------------------------------

## Advance the pointer when the designated member actually picks up.
func _on_drop_picked_up(drop_id: String, player, _items: Array) -> void:
	var entry: Dictionary = _pending_designations.get(drop_id, {})
	if entry.is_empty():
		return
	_pending_designations.erase(drop_id)
	var party_id := str(entry.get("party_id", ""))
	var designated := str(entry.get("designated", ""))
	if party_id == "" or designated == "":
		return
	var picker_id := _player_id_of(player)
	if picker_id != designated:
		return  # someone else took it off-turn; rotation unchanged
	var party: Dictionary = _party_of(designated)
	if str(party.get("party_id", "")) != party_id:
		party = {"party_id": party_id, "members": []}
		if PartyService != null and PartyService.has_method("get_party_members"):
			party["members"] = PartyService.get_party_members(party_id)
	var members: Array = party.get("members", [])
	if members.size() < 2:
		return
	var idx := members.find(designated)
	_round_robin_next[party_id] = str(members[(idx + 1) % members.size()])


func _prune_pending() -> void:
	while _pending_designations.size() > MAX_PENDING_DESIGNATIONS:
		var first_key: String = _pending_designations.keys()[0]
		_pending_designations.erase(first_key)


## ---------------------------------------------------------------------------
## DROP-SIDE HELPERS (used by drop creators)
## ---------------------------------------------------------------------------

## Stamp party credit context onto drop options before create_drop.
## enemy.gd resolves kill credit the same way XP does, then calls this.
func build_enemy_drop_options(credit_player_id: String, base_options: Dictionary = {}) -> Dictionary:
	var options := base_options.duplicate()
	if credit_player_id != "":
		options["credit_player_id"] = credit_player_id
	return options


## Guild-locked drop: only that guild's members may loot it.
func create_guild_drop(guild_id: String, position: Vector3, items: Array,
		currency: Dictionary = {}) -> String:
	# Lazy resolution: this service and GroundLootService reference each
	# other; a bare identifier here would close a parse-time cycle.
	var gls = _resolve("GroundLootService")
	if gls == null:
		return ""
	return gls.create_drop(position, items, {
		"source": "guild_chest",
		"owner_id": "guild:%s" % guild_id,
		"currency": currency,
		"despawn_seconds": gls.DEFAULT_DESPAWN_SECONDS * 3.0,
	})


## Human-readable reservation for HUD/toasts.
func describe_reservation(drop: Dictionary) -> String:
	match str(drop.get("reserved_reason", "")):
		"karma":
			return "reserved (karma requirement)"
		"guild":
			return "reserved (guild lock)"
		"party_rule":
			return "reserved (party loot rules)"
	return ""


# --- chat integration -------------------------------------------------------

## /lootrule <ffa|round|leader|master> -- party leader only.
func handle_loot_rule_command(sender_id: String, rule_arg: String) -> bool:
	var party: Dictionary = _party_of(sender_id)
	if party.is_empty():
		_toast(sender_id, "You are not in a party.", "lr_noparty:%s" % sender_id)
		return true
	if str(party.get("leader_id", "")) != sender_id:
		_toast(sender_id, "Only the party leader can change loot rules.", "lr_notlead:%s" % sender_id)
		return true
	var rule_name := rule_arg.to_lower()
	var rule := -1
	match rule_name:
		"ffa", "free", "free_for_all":
			rule = Policy.FREE_FOR_ALL
		"round", "round_robin", "robin":
			rule = Policy.ROUND_ROBIN
		"leader":
			rule = Policy.LEADER
		"master", "master_looter":
			rule = Policy.MASTER_LOOTER
	if rule < 0:
		_toast(sender_id, "Usage: /lootrule ffa|round|leader|master", "lr_usage:%s" % sender_id)
		return true
	if PartyService != null and PartyService.has_method("set_loot_rule"):
		PartyService.set_loot_rule(sender_id, rule)
		_toast(sender_id, "Party loot rule set to %s." % Policy.keys()[rule].to_lower(),
			"lr_set:%s:%d" % [sender_id, rule])
	return true


# --- helpers ----------------------------------------------------------------

func _not_you(drop: Dictionary, candidate_id: String, reason: String) -> String:
	# Stamp for HUD/toast display (the drop dict is shared with
	# GroundLootService while the pickup attempt runs).
	drop["reserved_for"] = candidate_id
	drop["reserved_reason"] = reason
	delegation_changed.emit(str(drop.get("id", "")), candidate_id, reason)
	return candidate_id  # any non-empty value means "blocked"


func _party_of(player_id: String) -> Dictionary:
	if _party_override.has(player_id):
		var p: Dictionary = _party_override[player_id]
		return p if not p.is_empty() else {}
	if PartyService == null or not PartyService.has_method("get_player_party"):
		return {}
	var party: Dictionary = PartyService.get_player_party(player_id)
	if party.is_empty() or not party.has("members"):
		return {}
	return party


func _is_party_member(party: Dictionary, player_id: String) -> bool:
	return party.get("members", []).has(player_id)


func _is_guild_member(player_id: String, guild_id: String) -> bool:
	if _guild_override.has(player_id):
		return str(_guild_override[player_id]) == guild_id
	if GuildService == null or not GuildService.has_method("get_player_guild"):
		return false
	var guild: Dictionary = GuildService.get_player_guild(player_id)
	if guild.is_empty():
		return false
	return str(guild.get("guild_id", guild.get("id", ""))) == guild_id


func _class_matches(player_id: String, required_class: String) -> bool:
	if required_class == "":
		return true
	if _class_override.has(player_id):
		return str(_class_override[player_id]) == required_class
	var es = _resolve("EntityService")
	if es == null or not es.has_method("get_entity"):
		return false
	var entity = es.get_entity(player_id)
	if entity == null or not ("character_class" in entity):
		return false
	return str(entity.character_class) == required_class


func _player_id_of(player) -> String:
	if player == null:
		return ""
	if "entity_id" in player and str(player.entity_id) != "":
		return str(player.entity_id)
	if "player_id" in player:
		return str(player.player_id)
	return ""


func _toast(player_id: String, message: String, dedupe_key: String) -> void:
	if not is_instance_valid(NotificationService):
		return
	NotificationService.notify(
		NotifKind.AUTO_ACTION,
		message,
		"LootRulesService",
		dedupe_key,
		{},
		player_id
	)


func _resolve(autoload_name: String):
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	var tree := ml as SceneTree
	return tree.root.get_node_or_null(NodePath(autoload_name))
