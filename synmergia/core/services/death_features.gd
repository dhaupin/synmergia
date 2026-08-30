## DeathFeatures - Comprehensive death system manager
## Handles: penalties, invincibility, griefing protection, kill streaks, stats
extends Node

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
	
	# Connect to relevant events
	if EventHub:
		EventHub.player_died.connect(_on_player_died)
		EventHub.player_respawned.connect(_on_player_respawned)
		EventHub.player_resurrected.connect(_on_player_resurrected)
		EventHub.self_resurrected.connect(_on_self_resurrected)
		EventHub.revive_completed.connect(_on_revive_completed)
		EventHub.entity_killed.connect(_on_entity_killed)
	
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
	
	if Config.SHOW_INVINCIBILITY_UI and NotificationService:
		var remaining := Config.RESPAWN_INVINCIBILITY_DURATION
		NotificationService.send(entity.entity_id, "🛡️ Invincible for %.0f seconds" % remaining, 
			NotificationService.NotificationType.SYSTEM, NotificationService.Priority.NORMAL,
			NotificationService.DisplayLocation.CENTER_SCREEN, NotificationService.SoundType.NOTIFICATION, {
			"type": "respawn_invincibility",
			"duration": remaining
		})

## ============================================================================
## DEATH PENALTIES
## ============================================================================

## Apply death penalties to a player
func apply_death_penalties(entity, killer = null, is_pvp: bool = false) -> Dictionary:
	var penalties := {
		"xp_loss": 0,
		"gold_loss": 0,
		"durability_loss": 0.0,
		"karma_loss": 0
	}
	
	# XP Loss
	if Config.XP_LOSS_PERCENT > 0 and entity.has_method("get_xp"):
		var current_xp: int = entity.get_xp()
		var xp_loss := int(current_xp * Config.XP_LOSS_PERCENT)
		if xp_loss > 0:
			entity.modify_xp(-xp_loss)
			penalties["xp_loss"] = xp_loss
	
	# Gold Loss
	if Config.GOLD_LOSS_PERCENT > 0 and entity.has_method("get_gold"):
		var current_gold: int = entity.get_gold()
		var gold_loss := int(current_gold * Config.GOLD_LOSS_PERCENT)
		if gold_loss > 0:
			entity.modify_gold(-gold_loss)
			penalties["gold_loss"] = gold_loss
	
	# Durability Loss
	if Config.DURABILITY_LOSS_PERCENT > 0 and entity.inventory_component:
		var durability_loss: float = entity.inventory_component.apply_durability_loss(Config.DURABILITY_LOSS_PERCENT)
		penalties["durability_loss"] = durability_loss
	
	# Karma Loss (PVP only)
	if is_pvp and killer and killer != entity:
		if Config.PVP_KARMA_LOSS > 0:
			if RespawnService:
				RespawnService.remove_karma(entity.entity_id, Config.PVP_KARMA_LOSS, "Killed by %s" % killer.display_name)
				penalties["karma_loss"] = Config.PVP_KARMA_LOSS
	
	# Log and emit
	if penalties.xp_loss > 0 or penalties.gold_loss > 0 or penalties.durability_loss > 0:
		death_penalty_applied.emit(entity.entity_id, penalties.xp_loss, penalties.gold_loss, penalties.durability_loss)
		GameLog.info("DeathFeatures: Penalties applied to %s: %s" % [entity.display_name, JSON.stringify(penalties)])
	
	# Notify player
	if NotificationService and (penalties.xp_loss > 0 or penalties.gold_loss > 0):
		var msg_parts: Array = []
		if penalties.xp_loss > 0:
			msg_parts.append("%d XP" % penalties.xp_loss)
		if penalties.gold_loss > 0:
			msg_parts.append("%d gold" % penalties.gold_loss)
		if penalties.durability_loss > 0:
			msg_parts.append("%.0f%% durability" % penalties.durability_loss)
		
		var penalty_msg: String = "Death penalty: " + ", ".join(msg_parts)
		NotificationService.send(entity.entity_id, penalty_msg, 
			NotificationService.NotificationType.WARNING, NotificationService.Priority.NORMAL,
			NotificationService.DisplayLocation.CHAT_LOG, NotificationService.SoundType.WARNING, penalties)
	
	return penalties

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
	if NotificationService:
		NotificationService.send(entity_id, 
			"🛡️ Griefing protection activated! You are now in a safe zone.", 
			NotificationService.NotificationType.WARNING, NotificationService.Priority.HIGH,
			NotificationService.DisplayLocation.CENTER_SCREEN, NotificationService.SoundType.WARNING, {
			"type": "griefing_protection",
			"duration": Config.GRIEFING_PROTECTION_DURATION
		})
	
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
		if AchievementService:
			AchievementService.unlock_achievement(killer_id, "kill_streak_%d" % streak_data["streak"])
	
	# Check for threshold
	var thresholds: Array = Config.KILL_STREAK_THRESHOLDS
	for threshold in thresholds:
		if streak_data["streak"] == threshold:
			kill_streak_increased.emit(killer_id, streak_data["streak"], threshold)
			_apply_kill_streak_reward(killer_id, streak_data["streak"])
			
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
	
	# Apply rewards
	if EntityService:
		var killer = EntityService.get_entity(killer_id)
		if killer:
			if killer.has_method("modify_xp") and xp_bonus > 0:
				killer.modify_xp(xp_bonus)
			if killer.has_method("modify_gold") and gold_bonus > 0:
				killer.modify_gold(gold_bonus)
	
	kill_streak_rewarded.emit(killer_id, streak, xp_bonus, gold_bonus)
	
	# Notify
	if NotificationService:
		var msg := "🔥 Kill streak %d! +%d XP, +%d gold" % [streak, xp_bonus, gold_bonus]
		NotificationService.send(killer_id, msg, 
			NotificationService.NotificationType.COMBAT, NotificationService.Priority.HIGH,
			NotificationService.DisplayLocation.BOTH, NotificationService.SoundType.ACHIEVEMENT, {
			"streak": streak,
			"xp_bonus": xp_bonus,
			"gold_bonus": gold_bonus
		})

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
	
	NotificationService.broadcast_server(message, 
		NotificationService.NotificationType.COMBAT, NotificationService.Priority.HIGH,
		NotificationService.DisplayLocation.CENTER_SCREEN, NotificationService.SoundType.ACHIEVEMENT, {
		"type": "kill_streak_announcement",
		"killer_id": killer_id,
		"streak": streak
	})

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
	
	# Check for death streak achievement
	if stats.total_deaths >= 100 and AchievementService:
		AchievementService.unlock_achievement(entity.entity_id, "died_100_times")

## Record a revive received
func record_revive_received(entity_id: String) -> void:
	if not Config.TRACK_DEATH_STATS:
		return
	get_death_stats(entity_id).total_revives_received += 1

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
	# Apply death penalties
	var is_pvp: bool = killer if killer else false
	apply_death_penalties(entity, killer, is_pvp)
	
	# Record for death stats
	var zone_id := ""
	if entity.has_method("get_zone_id"):
		zone_id = entity.get_zone_id()
	record_death(entity, killer, zone_id, "death")
	
	# Record kill for griefing detection
	if killer:
		record_kill(entity.entity_id, killer.entity_id)

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
