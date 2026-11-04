## DeathFeatures - Comprehensive death system manager
## Handles: penalties, invincibility, griefing protection, kill streaks, stats
extends Node
# NOTE: AchievementService is an autoload; reference it directly.

const Item = preload("res://core/schemas/item.gd")
const GuardData = preload("res://core/schemas/guard_data.gd")
# Frame-level notification dispatch (typed-Kind pipeline).
# Death events route through NotifKind.* with sender "DeathFeatures".
# Dedupe keys carry event identity so a 5-second respawn-invincibility
# countdown doesn't re-toast every frame.
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind
const DictStore = preload("res://adapters/persistence/dict_store.gd")
const _kv_death_stats := "death:stats:"
const _kv_kill_streaks := "kill_streak:"

# Singleton reference
static var instance: DeathFeatures

# Configuration shortcuts
var Config := GameConfig.Respawn

## ============================================================================
## PLAYER STATE TRACKING
## ============================================================================

# Invincibility state per player
var _player_invincible: Dictionary = {}  # entity_id -> {end_time, type}

# Griefing protection state
var _griefing_tracking: Dictionary = {}  # victim_id -> {killer_id: [timestamps]}
var _griefing_protected: Dictionary = {}  # entity_id -> {end_time, active}

# Kill streak tracking
var _kill_streaks: Dictionary = {}  # killer_id -> {streak: int, last_kill_time: float}

# Death statistics
var _death_stats: Dictionary = {}  # entity_id -> DeathStats

class DeathStats:
	var total_deaths: int = 0
	var pvp_deaths: int = 0
	var pve_deaths: int = 0
	var total_revives_received: int = 0
	var total_self_rezzes: int = 0
	var total_revives_given: int = 0
	var longest_kill_streak: int = 0
	var longest_death_streak: int = 0
	var death_history: Array = []  # [{time, killer, zone, cause}]

	func to_dict() -> Dictionary:
		return {
			"total_deaths": total_deaths,
			"pvp_deaths": pvp_deaths,
			"pve_deaths": pve_deaths,
			"total_revives_received": total_revives_received,
			"total_self_rezzes": total_self_rezzes,
			"total_revives_given": total_revives_given,
			"longest_kill_streak": longest_kill_streak,
			"longest_death_streak": longest_death_streak,
			"death_history": death_history
		}

## ============================================================================
## SIGNALS
## ============================================================================

signal player_became_invincible(entity_id: String, duration: float, reason: String)
signal player_lost_invincibility(entity_id: String, reason: String)
signal griefing_protection_activated(entity_id: String, duration: float)
signal griefing_protection_expired(entity_id: String)
signal kill_streak_increased(killer_id: String, new_streak: int, threshold: int)
signal kill_streak_broken(killer_id: String, final_streak: int)
signal kill_streak_rewarded(killer_id: String, streak: int, xp_bonus: int, gold_bonus: int)
signal death_penalty_applied(entity_id: String, xp_loss: int, gold_loss: int, durability_loss: float)
signal zone_transfer_blocked_due_to_death(entity_id: String, reason: String)

## ============================================================================
## LIFECYCLE
## ============================================================================

func _ready() -> void:
	instance = self
	GameLog.info("DeathFeatures: Ready")
	_load_state()

	# Connect to relevant events
	if EventHub:
		EventHub.player_died.connect(_on_player_died)
		EventHub.player_respawned.connect(_on_player_respawned)
		EventHub.player_resurrected.connect(_on_player_resurrected)
		EventHub.self_resurrected.connect(_on_self_resurrected)
		EventHub.revive_completed.connect(_on_revive_completed)
		EventHub.entity_killed.connect(_on_entity_killed)
		EventHub.damage_dealt.connect(_on_guard_crime_check)

	# Start cleanup timer
	var cleanup_timer := Timer.new()
	cleanup_timer.wait_time = 60.0
	cleanup_timer.timeout.connect(_on_cleanup_timer)
	add_child(cleanup_timer)
	cleanup_timer.start()

func _on_cleanup_timer() -> void:
	_cleanup_old_tracking()

## ============================================================================
## INVINCIBILITY SYSTEM
## ============================================================================

## Check if player is currently invincible
func is_invincible(entity_id: String) -> bool:
	if not _player_invincible.has(entity_id):
		return false
	var data: Dictionary = _player_invincible[entity_id]
	return Time.get_unix_time_from_system() < data["end_time"]

## Get remaining invincibility time
func get_invincibility_remaining(entity_id: String) -> float:
	if not is_invincible(entity_id):
		return 0.0
	var data: Dictionary = _player_invincible[entity_id]
	return max(0.0, data["end_time"] - Time.get_unix_time_from_system())

## Grant invincibility to a player
func grant_invincibility(entity_id: String, duration: float, reason: String = "respawn") -> void:
	var end_time := Time.get_unix_time_from_system() + duration

	# Extend if already invincible
	if _player_invincible.has(entity_id):
		var current_end = _player_invincible[entity_id]["end_time"]
		if current_end > end_time:
			return  # Don't reduce existing invincibility
		_player_invincible[entity_id]["end_time"] = end_time
		_player_invincible[entity_id]["reason"] = reason
	else:
		_player_invincible[entity_id] = {
			"end_time": end_time,
			"reason": reason,
			"start_time": Time.get_unix_time_from_system()
		}
		player_became_invincible.emit(entity_id, duration, reason)

	GameLog.debug("DeathFeatures: %s granted %ss invincibility (%s)" % [entity_id, duration, reason])

## Remove invincibility from a player
func remove_invincibility(entity_id: String, reason: String = "expired") -> void:
	if _player_invincible.has(entity_id):
		var was_reason = _player_invincible[entity_id]["reason"]
		_player_invincible.erase(entity_id)
		player_lost_invincibility.emit(entity_id, reason)
		GameLog.debug("DeathFeatures: %s lost invincibility (%s)" % [entity_id, was_reason])

## Check if damage should be blocked based on invincibility
func should_block_damage(entity_id: String, damage_source = null, is_pvp: bool = false) -> bool:
	if not is_invincible(entity_id):
		return false

	var data: Dictionary = _player_invincible[entity_id]
	var reason: String = data.get("reason", "")

	# Determine if this invincibility type blocks this damage
	match reason:
		"respawn":
			if is_pvp and Config.INVINCIBILITY_BLOCKS_PVP:
				return true
			if not is_pvp and Config.INVINCIBILITY_BLOCKS_ALL:
				return true
		"griefing_protection":
			return true  # Block all damage during griefing protection
		"safe_zone":
			return true  # Block all damage in safe zone

	return false

## Apply respawn invincibility
func apply_respawn_invincibility(entity) -> void:
	if Config.RESPAWN_INVINCIBILITY_DURATION <= 0:
		return

	grant_invincibility(entity.entity_id, Config.RESPAWN_INVINCIBILITY_DURATION, "respawn")

	if Config.SHOW_INVINCIBILITY_UI and is_instance_valid(NotificationService):
		var remaining := Config.RESPAWN_INVINCIBILITY_DURATION
		# Frame-level dispatch. RESPAWNED -> SYSTEM/HIGH via the
		# kind->type+priority map. Dedupe on (entity, "respawn_inv")
		# so re-application in the same frame is one toast.
		NotificationService.notify(
			NotifKind.RESPAWNED,
			" Invincible for %.0f seconds" % remaining,
			"DeathFeatures",
			"respawn_inv:%s" % entity.entity_id,
			{"type": "respawn_invincibility", "duration": remaining},
			entity.entity_id
		)

## ============================================================================
## DEATH PENALTIES
## ============================================================================

## Apply death penalties to a player
func apply_death_penalties(entity, killer = null, is_pvp: bool = false, was_duel: bool = false) -> Dictionary:
	var penalties := {
		"xp_loss": 0,
		"gold_loss": 0,
		"durability_loss": 0.0,
		"karma_loss": 0
	}

	# XP Loss
	if Config.XP_LOSS_PERCENT > 0:
		var current_xp: int = _read_xp(entity)
		var xp_loss := int(current_xp * Config.XP_LOSS_PERCENT)
		if xp_loss > 0 and _spend_xp(entity, xp_loss):
			penalties["xp_loss"] = xp_loss

	# Gold Loss
	if Config.GOLD_LOSS_PERCENT > 0:
		var current_gold: int = _read_gold(entity)
		var gold_loss := int(current_gold * Config.GOLD_LOSS_PERCENT)
		if gold_loss > 0 and _spend_gold(entity, gold_loss):
			penalties["gold_loss"] = gold_loss

	# Durability Loss
	if Config.DURABILITY_LOSS_PERCENT > 0 and "inventory_component" in entity and entity.inventory_component != null:
		var durability_loss: float = entity.inventory_component.apply_durability_loss(Config.DURABILITY_LOSS_PERCENT)
		penalties["durability_loss"] = durability_loss

	# Karma Loss (PVP only; duels are honorable -- no karma changes hands)
	if is_pvp and not was_duel and killer and killer != entity:
		if Config.PVP_KARMA_LOSS > 0:
			if RespawnService:
				RespawnService.remove_karma(entity.entity_id, Config.PVP_KARMA_LOSS, "Killed by %s" % killer.display_name)
				penalties["karma_loss"] = Config.PVP_KARMA_LOSS

	# Mirror the loss into PlayerManager (the HUD's XP/gold source) when
	# the victim is the local player, matching the reward-side mirror.
	if penalties["xp_loss"] > 0 or penalties["gold_loss"] > 0:
		_mirror_progress_to_player_manager(entity, -int(penalties["xp_loss"]), -int(penalties["gold_loss"]))

	# Log and emit
	if penalties.xp_loss > 0 or penalties.gold_loss > 0 or penalties.durability_loss > 0:
		death_penalty_applied.emit(entity.entity_id, penalties.xp_loss, penalties.gold_loss, penalties.durability_loss)
		GameLog.info("DeathFeatures: Penalties applied to %s: %s" % [entity.display_name, JSON.stringify(penalties)])

	# Notify player
	if is_instance_valid(NotificationService) and (penalties.xp_loss > 0 or penalties.gold_loss > 0):
		var msg_parts: Array = []
		if penalties.xp_loss > 0:
			msg_parts.append("%d XP" % penalties.xp_loss)
		if penalties.gold_loss > 0:
			msg_parts.append("%d gold" % penalties.gold_loss)
		if penalties.durability_loss > 0:
			msg_parts.append("%.0f%% durability" % penalties.durability_loss)

		var penalty_msg: String = "Death penalty: " + ", ".join(msg_parts)
		# Frame-level dispatch. RESPAWN_PENALTY_APPLIED -> WARNING/NORMAL.
		# Dedupe on (entity, "penalty") so a same-frame double-apply is
		# one toast. Different magnitudes (re-dying with a different
		# penalty) still surface because the dedupe window is short and
		# the kind stays the same.
		NotificationService.notify(
			NotifKind.RESPAWN_PENALTY_APPLIED,
			penalty_msg,
			"DeathFeatures",
			"penalty:%s" % entity.entity_id,
			penalties,
			entity.entity_id
		)

	return penalties


## ============================================================================
## PROGRESSION SURFACE (duck-typed)
## ============================================================================
## The authoritative progression lives on the player node as the
## `experience`/`gold` fields plus add_experience/add_gold (the same
## convention kill_rewards.gd pays through). Death penalties and
## kill-streak bonuses route through these helpers so they hit the
## real wallet; the node's own signals keep PlayerManager and the HUD
## in sync. Nothing here reads a `modify_xp`/`modify_gold`/`get_xp`
## method -- no class in the repo declares those.

## Current XP of a combatant, or 0 when the node carries no progress.
func _read_xp(entity) -> int:
	if entity != null and "experience" in entity:
		return int(entity.experience)
	return 0


## Current gold of a combatant, or 0 when the node carries no purse.
func _read_gold(entity) -> int:
	if entity != null and "gold" in entity:
		return int(entity.gold)
	return 0


## Deduct XP (a death penalty), never below zero. Returns true when
## XP actually moved so the caller books the loss honestly.
func _spend_xp(entity, amount: int) -> bool:
	if entity == null or amount <= 0 or not ("experience" in entity):
		return false
	var current: int = int(entity.experience)
	if current <= 0:
		return false
	# No negative-XP API exists (add_experience only grants). A penalty is
	# a direct field move; announce it so the HUD/PlayerManager mirror hears.
	var loss: int = mini(amount, current)
	entity.experience = current - loss
	_emit_xp_changed(entity)
	return true


## Deduct gold (a death penalty), never below zero. Routes through the
## node's remove_gold when present (the ONE-purse path), else the field.
func _spend_gold(entity, amount: int) -> bool:
	if entity == null or amount <= 0:
		return false
	if "remove_gold" in entity and entity.has_method("remove_gold"):
		return bool(entity.remove_gold(amount))
	if not ("gold" in entity):
		return false
	var current: int = int(entity.gold)
	if current <= 0:
		return false
	entity.gold = maxi(0, current - amount)
	return true


## Grant XP (a kill-streak bonus) through the real grant surface.
func _grant_xp(entity, amount: int) -> void:
	if entity == null or amount <= 0:
		return
	if "add_experience" in entity and entity.has_method("add_experience"):
		entity.add_experience(amount)
	elif "experience" in entity:
		entity.experience = int(entity.experience) + amount
		_emit_xp_changed(entity)


## Grant gold (a kill-streak bonus) through the real grant surface.
func _grant_gold(entity, amount: int) -> void:
	if entity == null or amount <= 0:
		return
	if "add_gold" in entity and entity.has_method("add_gold"):
		entity.add_gold(amount)
	elif "gold" in entity:
		entity.gold = int(entity.gold) + amount


## Re-announce XP after a direct field move so the HUD/PlayerManager
## mirror hears it (add_experience emits this itself).
func _emit_xp_changed(entity) -> void:
	if "experience_changed" in entity and entity.has_signal("experience_changed"):
		entity.experience_changed.emit(int(entity.experience), int(entity.level) if "level" in entity else 1)


## Mirror a progression delta into PlayerManager (the persistent stats
## the HUD reads). Signed: a kill-streak bonus is positive, a death
## penalty negative. Only the local player node is mirrored --
## PlayerManager holds the local player's stats, never another's.
func _mirror_progress_to_player_manager(entity, xp: int, gold: int) -> void:
	if entity == null:
		return
	var tree := get_tree()
	if tree == null:
		return
	var pm: Node = tree.root.get_node_or_null(NodePath("PlayerManager"))
	if pm == null or not pm.has_method("get_local_player"):
		return
	if pm.get_local_player() != entity:
		return
	if xp != 0 and pm.has_method("add_experience"):
		pm.add_experience(xp)
	if gold != 0 and pm.has_method("add_gold"):
		pm.add_gold(gold)


## Zone id for a death record. The entity itself never carries one --
## ZoneManager owns the entity->zone map.
func _zone_id_of(entity) -> String:
	if entity == null:
		return ""
	var tree := get_tree()
	if tree == null:
		return ""
	var zm: Node = tree.root.get_node_or_null(NodePath("ZoneManager"))
	if zm != null and zm.has_method("get_entity_zone_id"):
		return str(zm.get_entity_zone_id(entity))
	return ""


## ============================================================================
## GRIEFING PROTECTION
## ============================================================================

## Record a kill for griefing detection
func record_kill(victim_id: String, killer_id: String) -> void:
	if not Config.ENABLE_GRIEFING_PROTECTION:
		return

	var current_time := Time.get_unix_time_from_system()

	# Initialize victim tracking
	if not _griefing_tracking.has(victim_id):
		_griefing_tracking[victim_id] = {}

	var victim_tracking: Dictionary = _griefing_tracking[victim_id]

	# Initialize killer tracking
	if not victim_tracking.has(killer_id):
		victim_tracking[killer_id] = []

	var kill_times: Array = victim_tracking[killer_id]

	# Add current kill
	kill_times.append(current_time)

	# Clean old kills outside time window
	var cutoff := current_time - Config.GRIEFING_TIME_WINDOW
	kill_times = kill_times.filter(func(t): return t > cutoff)
	victim_tracking[killer_id] = kill_times

	# Check if griefing threshold exceeded
	if kill_times.size() >= Config.GRIEFING_KILL_THRESHOLD:
		_activate_griefing_protection(victim_id)

## Activate griefing protection for a player
func _activate_griefing_protection(entity_id: String) -> void:
	if _griefing_protected.has(entity_id):
		# Extend existing protection
		var current_end = _griefing_protected[entity_id]["end_time"]
		if Time.get_unix_time_from_system() < current_end:
			_griefing_protected[entity_id]["end_time"] = current_end + Config.GRIEFING_PROTECTION_DURATION
			return

	_griefing_protected[entity_id] = {
		"end_time": Time.get_unix_time_from_system() + Config.GRIEFING_PROTECTION_DURATION,
		"start_time": Time.get_unix_time_from_system()
	}

	griefing_protection_activated.emit(entity_id, Config.GRIEFING_PROTECTION_DURATION)

	# Grant invincibility
	grant_invincibility(entity_id, Config.GRIEFING_PROTECTION_DURATION, "griefing_protection")

	# Notify player
	if is_instance_valid(NotificationService):
		# Frame-level dispatch. SECURITY_WARNING -> WARNING/HIGH.
		# Dedupe on (entity, "griefing") so a re-activation within the
		# window collapses; a fresh griefing event after the window
		# expires surfaces.
		NotificationService.notify(
			NotifKind.SECURITY_WARNING,
			" Griefing protection activated! You are now in a safe zone.",
			"DeathFeatures",
			"griefing:%s" % entity_id,
			{"type": "griefing_protection", "duration": Config.GRIEFING_PROTECTION_DURATION},
			entity_id
		)

	GameLog.info("DeathFeatures: Griefing protection activated for %s" % entity_id)

## Check if player has griefing protection
func has_griefing_protection(entity_id: String) -> bool:
	if not _griefing_protected.has(entity_id):
		return false
	return Time.get_unix_time_from_system() < _griefing_protected[entity_id]["end_time"]

## Get griefing protection remaining time
func get_griefing_protection_remaining(entity_id: String) -> float:
	if not has_griefing_protection(entity_id):
		return 0.0
	return max(0.0, _griefing_protected[entity_id]["end_time"] - Time.get_unix_time_from_system())

## Check if player should be redirected to safe zone
func should_redirect_to_safe_zone(entity_id: String) -> bool:
	if not Config.ENABLE_GRIEFING_PROTECTION:
		return false
	if not Config.GRIEFING_SAFE_ZONE_REDIRECT:
		return false
	return has_griefing_protection(entity_id)

## ============================================================================
## KILL STREAK SYSTEM
## ============================================================================

## Record a kill for streak tracking
func record_kill_for_streak(killer_id: String, victim_id: String) -> void:
	if not Config.ENABLE_KILL_STREAK_BONUS:
		return

	var current_time := Time.get_unix_time_from_system()

	if not _kill_streaks.has(killer_id):
		_kill_streaks[killer_id] = {
			"streak": 0,
			"last_kill_time": 0.0,
			"best_streak": 0
		}

	var streak_data: Dictionary = _kill_streaks[killer_id]

	# Check if streak is still active (within time window)
	var streak_timeout := 30.0  # Streak expires after 30 seconds
	if current_time - streak_data["last_kill_time"] > streak_timeout:
		# Streak broken
		if streak_data["streak"] > 0:
			kill_streak_broken.emit(killer_id, streak_data["streak"])
		streak_data["streak"] = 0

	# Increment streak
	streak_data["streak"] += 1
	streak_data["last_kill_time"] = current_time

	# Track best streak
	if streak_data["streak"] > streak_data["best_streak"]:
		streak_data["best_streak"] = streak_data["streak"]
		_persist_kill_streak(killer_id)

	# Check for threshold
	var thresholds: Array = Config.KILL_STREAK_THRESHOLDS
	for threshold in thresholds:
		if streak_data["streak"] == threshold:
			kill_streak_increased.emit(killer_id, streak_data["streak"], threshold)
			_apply_kill_streak_reward(killer_id, streak_data["streak"])
			# Streak achievements exist only for configured thresholds; the
			# unlock is direct (event achievements, not counters).
			if AchievementService:
				AchievementService.unlock(killer_id, "kill_streak_%d" % threshold)

			# Announce if enabled
			if Config.ANNOUNCE_KILL_STREAKS and streak_data["streak"] >= Config.KILL_STREAK_ANNOUNCE_THRESHOLD:
				_announce_kill_streak(killer_id, streak_data["streak"])
			break

	GameLog.debug("DeathFeatures: Kill streak for %s: %d" % [killer_id, streak_data["streak"]])

## Get current kill streak for a player
func get_kill_streak(killer_id: String) -> int:
	if not _kill_streaks.has(killer_id):
		return 0
	return _kill_streaks[killer_id]["streak"]

## Apply kill streak rewards
func _apply_kill_streak_reward(killer_id: String, streak: int) -> void:
	var xp_bonus := int(streak * Config.KILL_STREAK_XP_MULTIPLIER * 100)
	var gold_bonus := streak * Config.KILL_STREAK_GOLD_BONUS

	# Apply rewards through the real duck-typed progression surface
	# (experience field + add_experience/add_gold). The old guards probed
	# modify_xp/modify_gold, which no class declares -- the enabled
	# streak bonus silently granted nothing.
	if EntityService:
		var killer = EntityService.get_entity(killer_id)
		if killer:
			if xp_bonus > 0:
				_grant_xp(killer, xp_bonus)
			if gold_bonus > 0:
				_grant_gold(killer, gold_bonus)
			# The HUD XP bar reads PlayerManager, so mirror the bonus into
			# the persistent stats the same way kill_rewards does.
			_mirror_progress_to_player_manager(killer, xp_bonus, gold_bonus)

	kill_streak_rewarded.emit(killer_id, streak, xp_bonus, gold_bonus)

	# Notify
	if is_instance_valid(NotificationService):
		var msg := " Kill streak %d! +%d XP, +%d gold" % [streak, xp_bonus, gold_bonus]
		# Frame-level dispatch. CUSTOM (no dedicated kill_streak kind).
		# Dedupe on (killer, streak) so re-entering the same streak tier
		# within the window collapses, but stepping up (5->10) is a new
		# key and surfaces.
		NotificationService.notify(
			NotifKind.CUSTOM,
			msg,
			"DeathFeatures",
			"kill_streak:%s:%d" % [killer_id, streak],
			{"streak": streak, "xp_bonus": xp_bonus, "gold_bonus": gold_bonus},
			killer_id
		)

## Announce kill streak server-wide
func _announce_kill_streak(killer_id: String, streak: int) -> void:
	if not NotificationService:
		return

	var killer_name := killer_id
	if EntityService:
		var killer = EntityService.get_entity(killer_id)
		if killer:
			killer_name = killer.display_name

	var announcements := {
		5: " is on a RAMPAGE!",
		10: " is UNSTOPPABLE!",
		15: " is GODLIKE!",
		25: " is LEGENDARY!",
		50: " is DIVINE!"
	}

	var suffix = announcements.get(streak, " has a %d kill streak!" % streak)
	var message: String = killer_name + suffix

	# Frame-level dispatch, broadcast (recipient = ""). CUSTOM (no
	# dedicated kill_streak kind). Dedupe on (killer, streak) so the
	# same announcement isn't fanned out twice within the window.
	NotificationService.notify(
		NotifKind.CUSTOM,
		message,
		"DeathFeatures",
		"kill_streak_ann:%s:%d" % [killer_id, streak],
		{"type": "kill_streak_announcement", "killer_id": killer_id, "streak": streak},
		""
	)

## Break a kill streak (called when killer dies)
func break_kill_streak(killer_id: String) -> void:
	if not _kill_streaks.has(killer_id):
		return

	var streak: int = _kill_streaks[killer_id]["streak"]
	if streak > 0:
		_kill_streaks[killer_id]["streak"] = 0
		kill_streak_broken.emit(killer_id, streak)

## ============================================================================
## DEATH STATISTICS
## ============================================================================

## Get or create death stats for a player
func get_death_stats(entity_id: String) -> DeathStats:
	if not _death_stats.has(entity_id):
		_death_stats[entity_id] = DeathStats.new()
	return _death_stats[entity_id]

## Record a death
func record_death(entity, killer = null, zone_id: String = "", cause: String = "unknown") -> void:
	if not Config.TRACK_DEATH_STATS:
		return

	var stats := get_death_stats(entity.entity_id)
	stats.total_deaths += 1

	# Track PvP vs PvE
	if killer and killer:
		stats.pvp_deaths += 1
	else:
		stats.pve_deaths += 1

	# Add to history
	var death_record := {
		"time": Time.get_unix_time_from_system(),
		"killer_id": killer.entity_id if killer else "",
		"killer_name": killer.display_name if killer else "",
		"zone_id": zone_id,
		"cause": cause
	}
	stats.death_history.append(death_record)

	# Trim history
	while stats.death_history.size() > Config.MAX_DEATH_HISTORY:
		stats.death_history.pop_at(0)

	# Break kill streak of killer
	if killer:
		break_kill_streak(killer.entity_id)
	_persist_death_stats(entity.entity_id)

	# Check for death streak achievement
	if stats.total_deaths >= 100 and AchievementService:
			AchievementService.unlock(entity.entity_id, "died_100_times")

## Record a revive received
func record_revive_received(entity_id: String) -> void:
	if not Config.TRACK_DEATH_STATS:
		return
	get_death_stats(entity_id).total_revives_received += 1
	_persist_death_stats(entity_id)

## Record a self-rez
func record_self_rez(entity_id: String) -> void:
	if not Config.TRACK_DEATH_STATS:
		return
	get_death_stats(entity_id).total_self_rezzes += 1

## Record a revive given
func record_revive_given(entity_id: String) -> void:
	if not Config.TRACK_DEATH_STATS:
		return
	get_death_stats(entity_id).total_revives_given += 1

## Get stats as dictionary (for saving)
func get_stats_dict(entity_id: String) -> Dictionary:
	if not _death_stats.has(entity_id):
		return {}
	return get_death_stats(entity_id).to_dict()

## ============================================================================
## ZONE TRANSFER WHILE DEAD
## ============================================================================

## Check if player can transfer zones while dead
func can_transfer_zone_while_dead(entity, target_zone: String = "") -> Dictionary:
	var result := {
		"can_transfer": true,
		"reason": "",
		"delay_remaining": 0.0
	}

	if not entity.health_component or not entity.health_component.is_dead():
		return result  # Not dead, allow transfer

	# Check if dead zone transfer is allowed
	if not Config.ALLOW_ZONE_TRANSFER_WHILE_DEAD:
		result["can_transfer"] = false
		result["reason"] = "Cannot transfer zones while dead"
		zone_transfer_blocked_due_to_death.emit(entity.entity_id, result.reason)
		return result

	# Check safe zone restriction
	if Config.DEAD_ONLY_SAFE_ZONE_TRANSFER and not _is_safe_zone(target_zone):
		result["can_transfer"] = false
		result["reason"] = "Dead players can only transfer to safe zones"
		zone_transfer_blocked_due_to_death.emit(entity.entity_id, result.reason)
		return result

	return result

## Check if a zone is safe
func _is_safe_zone(zone_id: String) -> bool:
	# Safe zones would be defined in zone configuration
	# For now, just check if it's the safe zone ankh
	if zone_id == Config.GRIEFING_SAFE_ZONE_ANKH:
		return true
	# Could check against a safe zone list in GameConfig
	return false

## ============================================================================
## EVENT HANDLERS
## ============================================================================

func _on_player_died(entity, killer) -> void:
	# Duel resolution: the duel flag is stamped on the victim by
	# DuelService. Resolve the duel BEFORE anything reads the flag so the
	# outcome (no drops, no karma) is captured here and threaded through.
	var was_duel: bool = entity.has_meta("_duel_death") and bool(entity.get_meta("_duel_death"))
	if was_duel and DuelService != null and DuelService.has_method("resolve_duel_death"):
		var killer_id: String = str(killer.entity_id) if killer != null and "entity_id" in killer else ""
		DuelService.resolve_duel_death(str(entity.entity_id), killer_id)

	# Apply death penalties. PvP = killed by a player, duck-typed (an
	# entity_id on the killer and no loot table => a player). Duel kills
	# are honorable combat: no karma loss.
	var is_pvp: bool = killer != null and "entity_id" in killer \
		and not "loot_table_id" in killer
	apply_death_penalties(entity, killer, is_pvp, was_duel)

	# PvP/duel ground drops: dead player scatters equipment into the
	# world where the killer (or anyone, after the loot window) can
	# pick it up. Zone rules decide how much drops; duels drop nothing.
	_drop_player_loot(entity, killer, was_duel)

	# Record for death stats. Zone comes from ZoneManager (no entity
	# declares get_zone_id), so the death-history row carries a real
	# zone instead of an empty string.
	var zone_id := _zone_id_of(entity)
	record_death(entity, killer, zone_id, "death")

	# Record kill for griefing detection. Duel kills are consensual --
	# they never count toward griefing.
	if killer and not was_duel:
		record_kill(entity.entity_id, killer.entity_id)

## ============================================================================
## PLAYER LOOT DROPS (PvP zones / duels)
## ============================================================================

## Drop rules by context:
##   - Duel: nothing drops (honor duel -- kill_rewarded signals credit
##     but the loser keeps their gear).
##   - WARZONE / FREE_PVP zone: full loot -- every equipped and bagged
##     item hits the ground with an owner-lock window for the killer.
##   - Other PvP zones: no equipment drops (penalties already applied).
##   - PvE death: nothing drops (equipment survives).
## Dropped items are removed from the victim's inventory -- the ground
## copy is now the only copy.
const DUEL_DROP_ITEMS: int = 0
const FULL_LOOT_OWNER_LOCK: float = 0.25  # killer claims first 25% of lifetime

func _drop_player_loot(entity, killer, was_duel: bool = false) -> void:
	if GroundLootService == null:
		return
	if not ("inventory_component" in entity) or entity.inventory_component == null:
		return

	var drop_mode := _resolve_drop_mode(entity, killer, was_duel)
	match drop_mode:
		"duel":
			GameLog.info("DeathFeatures: %s died in a duel -- no items dropped" % entity.display_name)
			return
		"none":
			return
		"full":
			pass  # handled below

	var inventory = entity.inventory_component
	var dropped_items: Array = []

	# Equipment first (the valuable part of full loot). Equipment lives
	# in its own dict keyed by EquipSlot, not in bag slots.
	var equipment: Dictionary = inventory.get_all_equipment()
	for slot in equipment.keys():
		var item = equipment[slot]
		if item == null:
			continue
		inventory.clear_equipment_slot(slot)
		dropped_items.append(item)

	# Then bag items. remove_item(slot) hands back the removed Item.
	for slot in range(inventory.max_inventory_slots):
		var removed = inventory.remove_item(slot)
		if removed != null:
			dropped_items.append(removed)

	if dropped_items.is_empty():
		GameLog.info("DeathFeatures: %s had nothing to drop" % entity.display_name)
		return

	# Scatter around the death spot so items do not perfectly stack.
	var base_pos: Vector3 = entity.global_position
	var killer_id := ""
	if killer != null and "entity_id" in killer:
		killer_id = str(killer.entity_id)
	var placed := 0
	for item in dropped_items:
		var offset := Vector3(
			randf_range(-1.0, 1.0) * GroundLootService.DROP_SCATTER_RADIUS,
			-0.5,
			randf_range(-1.0, 1.0) * GroundLootService.DROP_SCATTER_RADIUS)
		var drop_id: String = GroundLootService.create_drop(base_pos + offset, [item], {
			"source": "pvp_drop",
			"owner_id": killer_id,
			"owner_lock_fraction": FULL_LOOT_OWNER_LOCK,
		})
		if drop_id != "":
			placed += 1

	GameLog.info("DeathFeatures: %s dropped %d/%d items in %s" % [
		entity.display_name, placed, dropped_items.size(), drop_mode])

	# Victim toast so the loss is communicated, not silent.
	if placed > 0 and is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.ITEM_REMOVED,
			"You dropped %d item(s) on death." % placed,
			"DeathFeatures",
			"pvp_drop:%s" % entity.entity_id,
			{"dropped": placed},
			entity.entity_id
		)

## "duel" | "full" | "none"
func _resolve_drop_mode(entity, killer, was_duel: bool = false) -> String:
	if killer == null:
		return "none"
	# Player-killer check, duck-typed (PlayerController is a
	# CharacterBody3D with an entity_id; Enemy is an Entity with a
	# loot_table_id). Anything that itself carries a loot table is a
	# monster, not a player.
	if not "entity_id" in killer or "loot_table_id" in killer:
		return "none"  # PvE death: environment/enemy kill, gear survives

	# Duel tracking: DeathStats records duels when flagged by the
	# combat layer; a duel kill is recorded with context "duel".
	# Duel tracking: the duel flag is stamped on the victim by the
	# combat layer before the death lands (meta so any Node can carry
	# it); a duel kill drops nothing. was_duel is captured by
	# _on_player_died before DuelService clears the flags.
	if was_duel or (entity.has_meta("_duel_death") and bool(entity.get_meta("_duel_death"))):
		return "duel"

	# Zone-based rules.
	var zone_id := ""
	if ZoneManager != null and ZoneManager.has_method("get_entity_zone_id"):
		zone_id = ZoneManager.get_entity_zone_id(entity)
	var zone: ZoneData = null
	if ZoneManager != null and zone_id != "" and ZoneManager.has_method("get_zone"):
		zone = ZoneManager.get_zone(zone_id)
	if zone == null:
		return "none"
	match zone.pvp_mode:
		ZoneData.PvPZoneMode.WARZONE, ZoneData.PvPZoneMode.FREE_PVP:
			return "full"
		_:
			return "none"

func _on_player_respawned(entity, respawn_point: Vector3, mode: RespawnService.RespawnMode) -> void:
	# Apply respawn invincibility
	apply_respawn_invincibility(entity)

func _on_player_resurrected(entity, source: String) -> void:
	record_revive_received(entity.entity_id)

func _on_self_resurrected(entity, item: Item) -> void:
	record_self_rez(entity.entity_id)

func _on_revive_completed(caster, target) -> void:
	record_revive_given(caster.entity_id)

func _on_entity_killed(killer, victim, damage_type: String) -> void:
	# Record kill for streak tracking
	if killer and killer:
		record_kill_for_streak(killer.entity_id, victim.entity_id)

## Town-watch crime reporting: when a player attacks a FRIENDLY NPC that
## exposes report_offense (guards), every watching guard marks the
## attacker. Guards stay FRIENDLY to everyone else -- hostility is
## per-player, so no global relation flip occurs. This is the
## ATTACKED_FACTION trigger (a guard's protected_faction covers its own
## watch); future hooks: theft reports, trespass checkpoints.
func _on_guard_crime_check(source, target, _amount: int, _damage_type: String, _is_crit: bool = false) -> void:
	if source == null or target == null or not is_instance_valid(target):
		return
	if not "entity_id" in source or "loot_table_id" in source:
		return  # only players commit crimes here
	if not target.has_method("report_offense"):
		return
	if "relation" in target and target.relation == Entity.Relation.FRIENDLY:
		target.report_offense(str(source.entity_id), GuardData.WatchTrigger.ATTACKED_FACTION,
			"assaulted %s" % str(target.display_name))

## ============================================================================
## CLEANUP
## ============================================================================

func _cleanup_old_tracking() -> void:
	var current_time := Time.get_unix_time_from_system()

	# Clean up expired invincibility
	for entity_id in _player_invincible.keys():
		if current_time >= _player_invincible[entity_id]["end_time"]:
			_player_invincible.erase(entity_id)
			player_lost_invincibility.emit(entity_id, "expired")

	# Clean up expired griefing protection
	for entity_id in _griefing_protected.keys():
		if current_time >= _griefing_protected[entity_id]["end_time"]:
			_griefing_protected.erase(entity_id)
			griefing_protection_expired.emit(entity_id)

	# Clean up old griefing tracking
	for victim_id in _griefing_tracking.keys():
		var victim_tracking: Dictionary = _griefing_tracking[victim_id]
		for killer_id in victim_tracking.keys():
			var kill_times: Array = victim_tracking[killer_id]
			var cutoff := current_time - Config.GRIEFING_TIME_WINDOW * 2
			victim_tracking[killer_id] = kill_times.filter(func(t): return t > cutoff)
			if victim_tracking[killer_id].is_empty():
				victim_tracking.erase(killer_id)
		if victim_tracking.is_empty():
			_griefing_tracking.erase(victim_id)

	# Clean up inactive streak tracking
	for killer_id in _kill_streaks.keys():
		var streak_data: Dictionary = _kill_streaks[killer_id]
		if current_time - streak_data["last_kill_time"] > 300:  # 5 minutes
			if streak_data["streak"] > 0:
				kill_streak_broken.emit(killer_id, streak_data["streak"])
			_kill_streaks.erase(killer_id)

## == Persistence ============================================================

func _load_state() -> void:
	var store := DictStore.new()
	_death_stats = {}
	_kill_streaks = {}
	for key in store.all_keys():
		if key.begins_with(_kv_death_stats):
			var entity_id = key.substr(_kv_death_stats.length())
			var data: Dictionary = store.get_value(key) as Dictionary
			if data == null:
				data = {}
			if not data.is_empty():
				var stats := DeathStats.new()
				stats.total_deaths = data.get("total_deaths", 0)
				stats.pvp_deaths = data.get("pvp_deaths", 0)
				stats.pve_deaths = data.get("pve_deaths", 0)
				stats.total_revives_received = data.get("total_revives_received", 0)
				stats.total_self_rezzes = data.get("total_self_rezzes", 0)
				stats.total_revives_given = data.get("total_revives_given", 0)
				stats.longest_kill_streak = data.get("longest_kill_streak", 0)
				stats.longest_death_streak = data.get("longest_death_streak", 0)
				stats.death_history = data.get("death_history", [])
				_death_stats[entity_id] = stats
		elif key.begins_with(_kv_kill_streaks):
			var killer_id = key.substr(_kv_kill_streaks.length())
			_kill_streaks[killer_id] = store.get_value(key)

func _persist_death_stats(entity_id: String) -> void:
	var store := DictStore.new()
	if _death_stats.has(entity_id):
		store.set_value(_kv_death_stats + entity_id, _death_stats[entity_id].to_dict())
	else:
		store.erase(_kv_death_stats + entity_id)

func _persist_kill_streak(killer_id: String) -> void:
	var store := DictStore.new()
	if _kill_streaks.has(killer_id):
		store.set_value(_kv_kill_streaks + killer_id, _kill_streaks[killer_id])
	else:
		store.erase(_kv_kill_streaks + killer_id)
