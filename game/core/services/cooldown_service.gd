## CooldownService - Unified cooldown management for player-to-player actions
## Prevents spam of requests (trade, party, guild, friend, etc)
extends Node

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind
const CacheWrapper = preload("res://adapters/cache/cache_wrapper.gd")

# Cooldown definitions (action_type -> cooldown_seconds)
const DEFAULT_COOLDOWN: float = 30.0
var _cache: CacheWrapper = CacheWrapper.new()  # key: "cooldown:<player_id>:<action_type>" -> timestamp

# Default cooldowns for common actions
const COOLDOWNS: Dictionary = {
	"party_invite": 30.0,
	"guild_invite": 30.0,
	"friend_request": 30.0,
	"follow_request": 10.0,
	"trade": 30.0,
	"whisper": 5.0,           # Faster for whispers
	"duel": 60.0,             # Longer for duels
	"trade_request": 30.0,    # Alias for trade
	"party_join_request": 30.0,
}

signal cooldown_started(player_id: String, action_type: String, duration: float)
signal cooldown_ended(player_id: String, action_type: String)
signal cooldown_tick(player_id: String, action_type: String, remaining: float)

func _ready() -> void:
	GameLog.info("CooldownService: Ready")

## Check if action is on cooldown
func is_on_cooldown(player_id: String, action_type: String) -> bool:
	var key := "cooldown:%s:%s" % [player_id, action_type]
	var ts: float = _cache.get(key)
	if ts == null or ts == 0:
		return false
	var elapsed: float = Time.get_unix_time_from_system() - ts
	var duration := get_cooldown_duration(action_type)
	return elapsed < duration

## Get remaining cooldown time
func get_remaining(player_id: String, action_type: String) -> float:
	if not is_on_cooldown(player_id, action_type):
		return 0.0
	var key := "cooldown:%s:%s" % [player_id, action_type]
	var ts: float = _cache.get(key)
	var elapsed: float = Time.get_unix_time_from_system() - ts
	var duration := get_cooldown_duration(action_type)
	return max(0.0, duration - elapsed)

## Start a cooldown
func start_cooldown(player_id: String, action_type: String, duration: float = -1.0) -> void:
	if duration < 0:
		duration = get_cooldown_duration(action_type)

	var key := "cooldown:%s:%s" % [player_id, action_type]
	_cache.set(key, Time.get_unix_time_from_system(), int(duration) + 1)
	cooldown_started.emit(player_id, action_type, duration)

	GameLog.debug("CooldownService: %s started cooldown for %s (%.1fs)" % [player_id, action_type, duration])

## Check and start cooldown (returns true if started, false if on cooldown)
func try_start(player_id: String, action_type: String, show_notification: bool = true) -> bool:
	if is_on_cooldown(player_id, action_type):
		if show_notification:
			var remaining := get_remaining(player_id, action_type)
			_show_cooldown_notification(player_id, action_type, remaining)
		return false

	start_cooldown(player_id, action_type)
	return true

## Get cooldown duration for action type
func get_cooldown_duration(action_type: String) -> float:
	if COOLDOWNS.has(action_type):
		return COOLDOWNS[action_type]
	return DEFAULT_COOLDOWN

## Cancel a cooldown early
func cancel_cooldown(player_id: String, action_type: String) -> void:
	if _cooldowns.has(player_id) and _cooldowns[player_id].has(action_type):
		_cooldowns[player_id].erase(action_type)
		cooldown_ended.emit(player_id, action_type)
		GameLog.debug("CooldownService: %s cancelled cooldown for %s" % [player_id, action_type])

## Cancel all cooldowns for a player
func cancel_all(player_id: String) -> void:
	if _cooldowns.has(player_id):
		for action_type in _cooldowns[player_id].keys():
			cooldown_ended.emit(player_id, action_type)
		_cooldowns.erase(player_id)

## Get all active cooldowns for a player
func get_active_cooldowns(player_id: String) -> Dictionary:
	if not _cooldowns.has(player_id):
		return {}

	var active := {}
	for action_type in _cooldowns[player_id].keys():
		var remaining := get_remaining(player_id, action_type)
		if remaining > 0:
			active[action_type] = remaining
	return active

## Process: Clean up expired cooldowns
func _process(delta: float) -> void:
	for player_id in _cooldowns.keys():
		_cleanup_player_cooldowns(player_id)

func _cleanup_player_cooldowns(player_id: String) -> void:
	if not _cooldowns.has(player_id):
		return

	var to_remove := []
	for action_type in _cooldowns[player_id].keys():
		if not is_on_cooldown(player_id, action_type):
			to_remove.append(action_type)
			cooldown_ended.emit(player_id, action_type)

	for action_type in to_remove:
		_cooldowns[player_id].erase(action_type)

	if _cooldowns[player_id].is_empty():
		_cooldowns.erase(player_id)

func _show_cooldown_notification(player_id: String, action_type: String, remaining: float) -> void:
	var action_name := _get_action_name(action_type)
	var message := "Wait %.0f seconds before %s again." % [remaining, action_name]

	if NotificationService:
		NotificationService.notify(
			NotifKind.TRADE_COOLDOWN,
			message,
			"CooldownService",
			"cooldown:%s:%s" % [player_id, action_type],
			{"action": action_type, "remaining": remaining},
			player_id
		)

func _get_action_name(action_type: String) -> String:
	match action_type:
		"trade", "trade_request": return "trading"
		"party_invite", "party_join_request": return "sending party invites"
		"guild_invite": return "sending guild invites"
		"friend_request": return "sending friend requests"
		"whisper": return "whispering"
		"duel": return "challenging to duel"
		"follow_request": return "following"
	return "performing that action"
