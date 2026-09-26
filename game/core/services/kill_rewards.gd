## kill_rewards.gd -- XP/gold kill-reward hook for the spawn-to-combat loop.
##
## Called from Enemy._on_died when a player (or their party) kills an
## enemy. Closes the reward half of the loop that loot rolls already
## closed: enemies now pay out XP and gold, the result is granted via
## the duck-typed combat surface (same pattern as the vertical slice)
## and mirrored into PlayerManager, which IS the player's persistent
## stats in the current build -- the HUD XP bar and level read from it.
##
## Preload-only static utility: no autoload, no class_name (AGENTS.md
## frame/service conventions). Kill-credit resolution order:
##   1. Direct killer (the killer passed down the death flow).
##   2. Threat-table owner (highest threat) -- so the tank holding
##      aggro keeps credit while DPS lands the killing blow, and
##      heal-threat still pays out. Matches the aggro system semantics.
##   3. No valid combatant -> no rewards, no signal.
extends RefCounted

# Reward curves. Classic-MMO-flavored, one tunable table; tweak here.
const XP_PER_ENEMY_LEVEL: int = 12
const XP_PER_KILLER_LEVEL: int = 2
const GOLD_PER_ENEMY_LEVEL: int = 3
const GOLD_PER_KILLER_LEVEL: int = 1
const MIN_REWARD_SCALE: float = 0.1  # grey-kill floor
const MAX_REWARD_SCALE: float = 5.0  # lowbie-farming cap
# Killers more than this many levels above the enemy get the floor.
const GREY_LEVEL_SPREAD: int = 8

## Guard schema for the WatchTrigger enum (preload is parse-safe:
## guard_data.gd has no autoload references).
const GuardDataScript = preload("res://core/schemas/guard_data.gd")

## Entry point: resolve credit, grant rewards, broadcast the event.
## Emits only when a valid credit holder was resolved -- a creditless
## kill (wild animal died to fall damage, despawn, etc.) is not a
## reward event.
static func award_kill(entity, killer) -> void:
	var result := award_kill_detailed(entity, killer)
	if result.get("killer", null) == null:
		return
	var hub := _event_hub()
	if hub == null or not hub.has_signal("kill_rewarded"):
		return
	# player_id rides along so QuestService kill-objective credit (and any
	# other consumer attributing the kill) resolves the same winner as the
	# XP payout -- direct killer, else threat-table owner.
	hub.kill_rewarded.emit(
			entity,
			result.get("killer", null),
			{
				"xp": int(result.get("xp", 0)),
				"gold": int(result.get("gold", 0)),
				"player_id": str(result.get("player_id", "")),
				"credit_source": str(result.get("credit_source", "")),
				"party_shared": bool(result.get("party_shared", false)),
				"scaling": float(result.get("scaling", 1.0)),
				"party_distribution": result.get("party_distribution", {}),
			}
		)


## Testable core: pure calculation + grant, returns a report Dictionary.
static func award_kill_detailed(entity, killer) -> Dictionary:
	var result := {
		"killer": null,
		"player_id": "",
		"xp": 0,
		"gold": 0,
		"party_shared": false,
		"party_distribution": {},
		"scaling": 1.0,
		"credit_source": "none",
	}

	if not _is_valid_combatant(entity):
		return result

	# 1. Direct killer; 2. threat-table owner.
	var credit: Object = null
	if _is_valid_combatant(killer):
		credit = killer
		result["credit_source"] = "direct"
	else:
		credit = _threat_owner(entity)
		if credit != null:
			result["credit_source"] = "threat_table"

	if credit == null:
		return result
	result["killer"] = credit

	# GUARD HARDENING: guards are not XP/gold pinatas. Killing one pays
	# nothing -- and IS the KILLING offense (worse than Assault): the
	# dying guard reports the killer so the whole watch marks them.
	if _is_guard(entity):
		result["credit_source"] = "guard_no_reward"
		if entity.has_method("report_offense") and _is_valid_combatant(credit) \
				and "entity_id" in credit and not ("loot_table_id" in credit):
			entity.report_offense(str(credit.entity_id), GuardDataScript.WatchTrigger.KILLING,
					"killed %s" % str(entity.display_name))
		var hub := _event_hub()
		if hub != null and hub.has_signal("kill_rewarded"):
			hub.kill_rewarded.emit(entity, credit, {"xp": 0, "gold": 0, "guard": true})
		return result

	# EnemyData is the data-driven source of truth when present.
	var xp := 0
	var gold := 0
	var data := _enemy_data_of(entity)
	if data != null and "xp_reward" in data:
		xp = int(data.xp_reward)
		gold = int(data.gold_min) if "gold_min" in data else 0
		if "gold_max" in data and int(data.gold_max) > int(data.gold_min):
			gold = randi_range(int(data.gold_min), int(data.gold_max))
		# Optional per-enemy gold multiplier if a schema adds one later.
	elif "level" in entity:
		# Deterministic fallback so every enemy pays something.
		xp = XP_PER_ENEMY_LEVEL * int(entity.level)
		gold = GOLD_PER_ENEMY_LEVEL * int(entity.level)

	# Level-difference scaling (party size handled inside share_xp).
	var scale := _level_scale(entity, credit)
	xp = int(float(xp) * scale)
	gold = int(float(gold) * scale)
	result["scaling"] = scale
	if xp < 0:
		xp = 0
	if gold < 0:
		gold = 0
	result["xp"] = xp
	result["gold"] = gold
	if xp == 0 and gold == 0:
		return result

	var pm := _player_manager()
	var player_id := _player_id_of(credit, pm)
	result["player_id"] = player_id

	# --- Party split ------------------------------------------------------
	var distribution := _party_distribution(player_id, xp)
	if distribution.size() > 1:
		result["party_shared"] = true
		result["party_distribution"] = distribution
		xp = int(distribution.get(player_id, xp))

	# --- Grant ------------------------------------------------------------
	_grant_xp(credit, xp)
	_grant_gold(credit, gold)
	if distribution.size() > 1:
		# Party members other than the killer: only those we can find as
		# live player nodes get granted here; offline shares are logged.
		for member_id in distribution:
			if member_id == player_id:
				continue
			var member = _find_player_node(member_id, pm)
			if member != null and member != credit:
				_grant_xp(member, int(distribution[member_id]))

	if pm != null and player_id != "":
		_mirror_into_player_manager(pm, result)

	return result


## Level-difference multiplier for a kill. 1.0 at parity; killers above
## the enemy's level slide toward the grey floor; killers below get a
## flat 1.0 (no bonus for underleveled kills; tuning later as needed).
static func _level_scale(entity, killer) -> float:
	var enemy_level := 0
	if "level" in entity:
		enemy_level = int(entity.level)
	var killer_level := 1
	if "level" in killer and int(killer.level) > 0:
		killer_level = int(killer.level)
	var spread := killer_level - enemy_level
	if spread <= 0:
		return 1.0
	if spread >= GREY_LEVEL_SPREAD:
		return MIN_REWARD_SCALE
	var t := float(spread) / float(GREY_LEVEL_SPREAD)
	return maxf(MIN_REWARD_SCALE, 1.0 - t * (1.0 - MIN_REWARD_SCALE))


## XP distribution across the killer's party (killer included).
## Returns {member_id: xp} -- empty when solo (no party).
static func _party_distribution(player_id: String, xp: int) -> Dictionary:
	var ps := _party_service()
	if ps == null or player_id.is_empty():
		return {}
	if not ps.has_method("get_player_party") or not ps.has_method("share_xp"):
		return {}
	var party: Dictionary = ps.get_player_party(player_id)
	if party.is_empty() or not party.has("id"):
		return {}
	var dist: Dictionary = ps.share_xp(party["id"], xp, player_id)
	return dist if dist is Dictionary else {}


static func _party_service() -> Node:
	return _resolve_autoload("PartyService")


static func _grant_xp(recipient, amount: int) -> void:
	if recipient == null or amount <= 0:
		return
	# Daily Class Blessing (prd-psy.md section 8): the sky-blessed class
	# earns +20% XP for the day (same multiplier as damage/healing).
	# Duck-typed + late-resolved: bare Entities and script-mode tests
	# never touch a bare autoload identifier.
	if "character_class" in recipient:
		var cid := str(recipient.get("character_class"))
		if not cid.is_empty():
			var ml := Engine.get_main_loop()
			if ml != null and (ml is SceneTree):
				var svc = (ml as SceneTree).root.get_node_or_null("SignService")
				if svc != null and svc.has_method("is_class_blessed") and svc.is_class_blessed(cid):
					amount = int(float(amount) * float(svc.BLESSED_DAMAGE_MULTIPLIER))
	if "add_experience" in recipient and recipient.has_method("add_experience"):
		recipient.add_experience(amount)
	elif "xp" in recipient:
		recipient.xp = int(recipient.xp) + amount
		if "stat_changed" in recipient and recipient.has_signal("stat_changed"):
			recipient.stat_changed.emit("xp", int(recipient.xp))


static func _grant_gold(recipient, amount: int) -> void:
	if recipient == null or amount <= 0:
		return
	if "add_gold" in recipient and recipient.has_method("add_gold"):
		recipient.add_gold(amount)
	elif "gold" in recipient:
		recipient.gold = int(recipient.gold) + amount


## PlayerManager is the persistent stats mirror for the local player in
## the current build (HUD XP bar, level, gold all read from it). Keep
## it in sync with whatever was granted to the player node.
static func _mirror_into_player_manager(pm, result: Dictionary) -> void:
	if pm == null:
		return
	if "add_experience" in pm and pm.has_method("add_experience") and int(result.get("xp", 0)) > 0:
		pm.add_experience(int(result["xp"]))
	if "add_gold" in pm and pm.has_method("add_gold") and int(result.get("gold", 0)) > 0:
		pm.add_gold(int(result["gold"]))


## Highest-threat holder on the dying enemy's threat table. This is how
## the tank keeps kill credit while a DPS lands the last hit.
static func _threat_owner(entity):
	if entity == null:
		return null
	if not "aggro_component" in entity or entity.aggro_component == null:
		return null
	var aggro = entity.aggro_component
	if not aggro.has_method("get_highest_threat_target"):
		return null
	var owner_node = aggro.get_highest_threat_target()
	# get_highest_threat_target may return a dead node that is still on
	# the table; require a live combatant.
	if _is_valid_combatant(owner_node):
		return owner_node
	return null


static func _enemy_data_of(entity) -> Resource:
	if entity != null and "enemy_data" in entity and entity.enemy_data != null:
		return entity.enemy_data
	return null


## A valid credit holder: in-tree Node3D-ish combatant with an entity
## id. Deliberately duck-typed so PlayerController (not an Entity)
## qualifies -- same convention as the vertical slice.
## Is the victim a guard? Duck-typed: guards expose report_offense and
## carry GuardData; regular enemies never do either. Kept duck-typed so
## this static stays script-mode safe (no preload of entity classes).
static func _is_guard(victim) -> bool:
	if victim == null or not (victim is Node):
		return false
	return victim.has_method("report_offense") and "guard_data" in victim \
			and victim.get("guard_data") != null


static func _is_valid_combatant(node) -> bool:
	if node == null or not (node is Node):
		return false
	if not is_instance_valid(node) or not node.is_inside_tree():
		return false
	if "is_dead" in node and node.has_method("is_dead") and node.is_dead():
		return false
	return "entity_id" in node or "player_id" in node


static func _player_id_of(credit, pm) -> String:
	if credit != null and "entity_id" in credit and str(credit.entity_id) != "":
		return str(credit.entity_id)
	if credit != null and "player_id" in credit:
		return str(credit.player_id)
	if pm != null and pm.local_player != null and credit == pm.local_player:
		return pm.character_name
	return ""


## Party members are found via EntityService (authoritative registry) or
## the PlayerManager local-player fallback.
static func _find_player_node(member_id: String, pm):
	var es := _entity_service()
	if es != null and es.has_method("get_entity"):
		var found = es.get_entity(member_id)
		if found != null and _is_valid_combatant(found):
			return found
	if pm != null and pm.local_player != null and "entity_id" in pm.local_player:
		if str(pm.local_player.entity_id) == member_id:
			return pm.local_player
	return null


# --- Service lookups (script-mode safe) ----------------------------------
# --script tests do not pre-load autoloads; resolve via the tree, with
# a bare-identifier fallback for full boot. Same convention as tests.

static func _event_hub() -> Node:
	return _resolve_autoload("EventHub")


static func _player_manager() -> Node:
	return _resolve_autoload("PlayerManager")


static func _entity_service() -> Node:
	return _resolve_autoload("EntityService")


## Autoloads are children of /root in full boot; in --script test mode
## they simply do not exist, and null is the correct, graceful answer.
## (Never fall back to the bare identifier here: that is the documented
## source of --script-mode runtime noise.)
static func _resolve_autoload(autoload_name: String) -> Node:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	var tree := ml as SceneTree
	if tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(autoload_name))
