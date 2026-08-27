## SecurityService - Centralized security utilities
## Handles input validation, permission checks, and anti-exploit measures
class_name SecurityService
extends Node

## ============================================================================
## SIGNALS
## ============================================================================

signal exploit_detected(player_id: String, exploit_type: String, details: Dictionary)
signal permission_denied(player_id: String, action: String, required_level: int)
signal invalid_input(player_id: String, input_type: String, reason: String)

## ============================================================================
## INPUT VALIDATION
## ============================================================================

## Validate a player name
func validate_player_name(name: String) -> Dictionary:
	var result := {
		"valid": true,
		"reason": ""
	}
	
	# Check length
	if name.length() < GameConfig.Security.MIN_NAME_LENGTH:
		result.valid = false
		result.reason = "Name too short"
		return result
	
	if name.length() > GameConfig.Security.MAX_NAME_LENGTH:
		result.valid = false
		result.reason = "Name too long"
		return result
	
	# Check allowed characters (alphanumeric, spaces, some punctuation)
	var allowed := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-.'"
	for ch in name:
		if ch not in allowed:
			result.valid = false
			result.reason = "Invalid character: '%s'" % ch
			return result
	
	# Check for reserved words
	for reserved in GameConfig.Security.RESERVED_NAMES:
		if name.to_lower().contains(reserved.to_lower()):
			result.valid = false
			result.reason = "Name contains reserved word"
			return result
	
	return result

## Validate a chat message
func validate_message(message: String, sender_id: String = "") -> Dictionary:
	var result := {
		"valid": true,
		"reason": "",
		"sanitized": message
	}
	
	if message.length() > GameConfig.Security.MAX_MESSAGE_LENGTH:
		result.valid = false
		result.reason = "Message too long"
		return result
	
	# Check for empty message
	if message.strip_edges().is_empty():
		result.valid = false
		result.reason = "Empty message"
		return result
	
	# Sanitize: remove control characters
	var sanitized := ""
	for ch in message:
		if ch >= ' ' or ch == '\n' or ch == '\t':  # Allow printable + newlines/tabs
			sanitized += ch
	
	result.sanitized = sanitized
	
	# Check for spam patterns (repeated characters)
	if _detect_spam_pattern(sanitized):
		result.valid = false
		result.reason = "Spam pattern detected"
		if sender_id != "":
			invalid_input.emit(sender_id, "message", "Spam pattern detected")
	
	return result

## Validate guild/channel name
func validate_channel_name(name: String) -> Dictionary:
	var result := {
		"valid": true,
		"reason": ""
	}
	
	# Check length
	if name.length() < 2:
		result.valid = false
		result.reason = "Name too short"
		return result
	
	if name.length() > 30:
		result.valid = false
		result.reason = "Name too long"
		return result
	
	# Check allowed characters
	var allowed := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
	for ch in name:
		if ch not in allowed:
			result.valid = false
			result.reason = "Invalid character"
			return result
	
	return result

## Sanitize a string for safe storage/display
func sanitize_for_display(input: String) -> String:
	var output := ""
	for ch in input:
		# Only allow printable ASCII
		if ch >= ' ' and ch <= '~':
			output += ch
	return output

## Sanitize a string for log output (extra safe)
func sanitize_for_log(input: String) -> String:
	var output := ""
	for ch in input:
		# Only allow alphanumeric and basic punctuation
		if ch.is_valid_identifier() or ch in " .,-_":
			output += ch
		else:
			output += "?"
	return output

## ============================================================================
## PERMISSION CHECKS
## ============================================================================

## Check if player has required permission level
func check_permission(player_level: int, required_level: int) -> bool:
	return player_level >= required_level

## Check if player can perform admin action
func can_admin(player_level: int) -> bool:
	return check_permission(player_level, GameConfig.Security.ADMIN_LEVEL)

## Check if player can moderate
func can_moderate(player_level: int) -> bool:
	return check_permission(player_level, GameConfig.Security.MOD_LEVEL)

## Log permission denial
func log_permission_denied(player_id: String, action: String, required_level: int) -> void:
	permission_denied.emit(player_id, action, required_level)
	Logger.warn("SecurityService: Permission denied for %s on action '%s' (required: %d)" % [
		player_id, action, required_level
	])

## ============================================================================
## EXPLOIT DETECTION
## ============================================================================

## Track suspicious activity patterns
var _suspicious_activity: Dictionary = {}

## Track player restrictions (muted, trade-banned, etc.)
var _player_restrictions: Dictionary = {}

## Detect potential teleport hack (instant movement across large distance)
func check_teleport(player_id: String, from_pos: Vector3, to_pos: Vector3, time_delta: float) -> bool:
if time_delta <= 0:
return false

var distance := from_pos.distance_to(to_pos)
var speed := distance / time_delta

if speed > GameConfig.Security.MAX_TELEPORT_DISTANCE:
_report_exploit(player_id, "teleport_hack", {
"from": {"x": from_pos.x, "y": from_pos.y, "z": from_pos.z},
"to": {"x": to_pos.x, "y": to_pos.y, "z": to_pos.z},
"distance": distance,
"speed": speed,
"max_allowed": GameConfig.Security.MAX_TELEPORT_DISTANCE
})
return true

return false

## Detect potential speed hack (movement too fast)
func check_movement_speed(player_id: String, reported_distance: float, time_delta: float, max_speed: float) -> bool:
	if time_delta <= 0:
		return false
	
	var actual_speed := reported_distance / time_delta
	var max_allowed := max_speed * GameConfig.Security.MAX_SPEED_HACK_MULTIPLIER
	
	if actual_speed > max_allowed:
		_report_exploit(player_id, "speed_hack", {
			"reported_speed": actual_speed,
			"max_allowed": max_allowed,
			"distance": reported_distance,
			"time": time_delta
		})
		return true
	
	return false

## Detect potential item duplication
func check_item_duplication(player_id: String, item_id: String, quantity_change: int) -> bool:
	if quantity_change <= 0:
		return false
	
	# Track item creation rate
	if not _suspicious_activity.has(player_id):
		_suspicious_activity[player_id] = {"item_creations": {}}
	
	var player_data := _suspicious_activity[player_id]
	if not player_data["item_creations"].has(item_id):
		player_data["item_creations"][item_id] = []
	
	var now := Time.get_ticks_msec()
	var recent := player_data["item_creations"][item_id].filter(func(t): return now - t < 60000)
	recent.append(now)
	player_data["item_creations"][item_id] = recent
	
	if recent.size() > GameConfig.Security.MAX_ITEMS_PER_MINUTE:
		_report_exploit(player_id, "item_duplication", {
			"item_id": item_id,
			"count": recent.size(),
			"quantity": quantity_change
		})
		return true
	
	return false

## Detect potential packet manipulation (unusual input patterns)
func check_input_anomaly(player_id: String, input_type: String, value: float) -> bool:
	var threshold := GameConfig.Security.MAX_INPUT_VALUE
	
	# Check for impossible values
	if absf(value) > threshold:
		_report_exploit(player_id, "input_anomaly", {
			"type": input_type,
			"value": value,
			"threshold": threshold
		})
		return true
	
	return false

## Internal: Report exploit
func _report_exploit(player_id: String, exploit_type: String, details: Dictionary) -> void:
	exploit_detected.emit(player_id, exploit_type, details)
	Logger.warn("SecurityService: Exploit detected - %s for player %s: %s" % [
		exploit_type, player_id, JSON.stringify(details)
	])

## Internal: Detect spam patterns
func _detect_spam_pattern(message: String) -> bool:
	# Check for repeated characters (> 5 same char in a row)
	var last_char := ""
	var count := 0
	for ch in message:
		if ch == last_char:
			count += 1
			if count > 5:
				return true
		else:
			count = 1
			last_char = ch
	return false

## ============================================================================
## RATE TRACKING (for manual security checks)
## ============================================================================

## Track actions per player for anomaly detection
var _action_tracker: Dictionary = {}

## Record an action for tracking
func track_action(player_id: String, action_type: String) -> int:
	if not _action_tracker.has(player_id):
		_action_tracker[player_id] = {}
	
	var now := Time.get_ticks_msec()
	var window := 10000  # 10 second window
	
	if not _action_tracker[player_id].has(action_type):
		_action_tracker[player_id][action_type] = []
	
	var actions := _action_tracker[player_id][action_type]
	# Filter to recent
	var recent := actions.filter(func(t): return now - t < window)
	recent.append(now)
	_action_tracker[player_id][action_type] = recent
	
	return recent.size()

## Get action count in recent window
func get_action_count(player_id: String, action_type: String, window_ms: int = 10000) -> int:
	if not _action_tracker.has(player_id) or not _action_tracker[player_id].has(action_type):
		return 0
	
	var now := Time.get_ticks_msec()
	var actions := _action_tracker[player_id][action_type]
	return actions.filter(func(t): return now - t < window_ms).size()

## ============================================================================
## PLAYER RESTRICTIONS
## ============================================================================

## Restrict a player's action (e.g., mute)
func restrict_player(player_id: String, restriction_type: String, duration_seconds: int) -> void:
	if not _player_restrictions.has(player_id):
		_player_restrictions[player_id] = {}
	
	var expires_at := Time.get_ticks_msec() + (duration_seconds * 1000)
	_player_restrictions[player_id][restriction_type] = {
		"expires_at": expires_at,
		"duration": duration_seconds
	}
	
	# Notify player
	_notify_player_restricted(player_id, restriction_type, duration_seconds)
	
	Logger.info("SecurityService: Restricted %s from %s for %ds" % [player_id, restriction_type, duration_seconds])

## Remove restriction from player
func unrestrict_player(player_id: String, restriction_type: String) -> bool:
	if not _player_restrictions.has(player_id):
		return false
	
	if not _player_restrictions[player_id].has(restriction_type):
		return false
	
	_player_restrictions[player_id].erase(restriction_type)
	
	if _player_restrictions[player_id].is_empty():
		_player_restrictions.erase(player_id)
	
	# Notify player
	_notify_player_unrestricted(player_id, restriction_type)
	
	Logger.info("SecurityService: Unrestricted %s from %s" % [player_id, restriction_type])
	return true

## Check if player is restricted from an action
func is_restricted(player_id: String, restriction_type: String) -> bool:
	if not _player_restrictions.has(player_id):
		return false
	
	if not _player_restrictions[player_id].has(restriction_type):
		return false
	
	var restriction := _player_restrictions[player_id][restriction_type]
	var expires_at: int = restriction["expires_at"]
	var now := Time.get_ticks_msec()
	
	# Check if expired
	if now > expires_at:
		_player_restrictions[player_id].erase(restriction_type)
		if _player_restrictions[player_id].is_empty():
			_player_restrictions.erase(player_id)
		return false
	
	return true

## Notify player they've been restricted
func _notify_player_restricted(player_id: String, restriction_type: String, duration_seconds: int) -> void:
	# Respect config toggle
	if not GameConfig.Security.ENABLE_SECURITY_ALERTS:
		return
	if not GameConfig.Security.ALERT_ON_RESTRICTION:
		return
	if not NotificationService:
		return
	
	var message := ""
	match restriction_type:
		"chat":
			if duration_seconds >= 3600:
				message = "You have been muted for %.1f hours for spam." % (duration_seconds / 3600.0)
			elif duration_seconds >= 60:
				message = "You have been muted for %d minutes for spam." % (duration_seconds / 60)
			else:
				message = "You have been muted for %d seconds for spam." % duration_seconds
		"trade":
			message = "You have been temporarily restricted from trading for %d seconds." % duration_seconds
		"party":
			message = "You have been temporarily restricted from creating parties for %d seconds." % duration_seconds
		_:
			message = "You have been restricted from %s for %d seconds." % [restriction_type, duration_seconds]
	
	NotificationService.send_to_player(
		player_id,
		message,
		NotificationService.NotificationType.WARNING,
		NotificationService.Priority.HIGH
	)

## Notify player their restriction has been lifted
func _notify_player_unrestricted(player_id: String, restriction_type: String) -> void:
	# Respect config toggle
	if not GameConfig.Security.ENABLE_SECURITY_ALERTS:
		return
	if not GameConfig.Security.ALERT_ON_UNRESTRICTION:
		return
	if not NotificationService:
		return
	
	var message := ""
	match restriction_type:
		"chat":
			message = "Your mute has been lifted. Please follow chat guidelines."
		"trade":
			message = "Trading restriction lifted. You can trade again."
		"party":
			message = "Party creation restriction lifted. You can create parties again."
		_:
			message = "Your restriction on %s has been lifted." % restriction_type
	
	NotificationService.send_to_player(
		player_id,
		message,
		NotificationService.NotificationType.SYSTEM,
		NotificationService.Priority.NORMAL
	)

## ============================================================================
## CLEANUP
## ============================================================================

func _process(delta: float) -> void:
	# Periodic cleanup of old tracking data
	var now := Time.get_ticks_msec()
	
	# Cleanup suspicious activity (older than 5 minutes)
	for player_id in _suspicious_activity.keys():
		var data := _suspicious_activity[player_id]
		var has_recent := false
		for item_id in data["item_creations"].keys():
			var recent := data["item_creations"][item_id].filter(func(t): return now - t < 300000)
			if not recent.is_empty():
				has_recent = true
				data["item_creations"][item_id] = recent
		if not has_recent:
			_suspicious_activity.erase(player_id)
	
	# Cleanup action tracker (older than 1 minute)
	for player_id in _action_tracker.keys():
		var actions := _action_tracker[player_id]
		var has_recent := false
		for action_type in actions.keys():
			var recent := actions[action_type].filter(func(t): return now - t < 60000)
			if not recent.is_empty():
				has_recent = true
				actions[action_type] = recent
		if not has_recent:
			_action_tracker.erase(player_id)
