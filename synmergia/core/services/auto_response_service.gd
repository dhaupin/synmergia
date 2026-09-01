## AutoResponseService - Automated responses to exploit detection
## Takes actions based on configured thresholds
extends Node

## ============================================================================
## SIGNALS
## ============================================================================

## Emitted whenever the service takes an automated action against a player.
## action is one of ActionType. Listeners (admin UI, QoS dashboards) can route
## this into the notification pipeline or audit log.
signal action_taken(player_id: String, action: int, exploit_type: String, reason: String)

## Emitted when a player receives a non-punitive warning (e.g. first spam
## offense). Separate from action_taken so UIs can render a softer style.
signal player_warned(player_id: String, exploit_type: String, message: String)

## Action types for the action_taken signal
enum ActionType {
	WARN,        ## First offense warning (no restriction)
	MUTE,        ## Chat restriction applied
	RESTRICT,    ## Generic restriction (e.g. chat)
	KICK,        ## Disconnected from server
	BAN,         ## Permanent ban issued
}

## ============================================================================
## STATE
## ============================================================================

## Track exploit confirmations per player
var _player_exploit_counts: Dictionary = {}  # player_id → {exploit_type: count}

## Track if auto-response is enabled
var _enabled: bool = false

## ============================================================================
## LIFECYCLE
## ============================================================================

func _ready() -> void:
	_enabled = GameConfig.AutoResponse.ENABLED
	_connect_signals()
	GameLog.info("AutoResponseService: %s" % ("Enabled" if _enabled else "Disabled"))

func _connect_signals() -> void:
	if SecurityService:
		SecurityService.exploit_detected.connect(_on_exploit_detected)

## ============================================================================
## EXPLOIT HANDLER
## ============================================================================

func _on_exploit_detected(player_id: String, exploit_type: String, details: Dictionary) -> void:
	if not _enabled:
		return
	
	# Track exploit count
	if not _player_exploit_counts.has(player_id):
		_player_exploit_counts[player_id] = {}
	
	var counts = _player_exploit_counts[player_id]
	if not counts.has(exploit_type):
		counts[exploit_type] = 0
	counts[exploit_type] += 1
	
	var count = counts[exploit_type]
	
	# Log the detection
	GameLog.info("AutoResponse: %s detected %s (count: %d)" % [player_id, exploit_type, count])
	
	# Check thresholds and take action
	match exploit_type:
		"spam":
			_handle_spam(player_id, count)
		"speed_hack":
			_handle_speed_hack(player_id, count)
		"teleport_hack":
			_handle_teleport_hack(player_id, count)
		"item_duplication":
			_handle_item_duplication(player_id, count)
	
	# Check total exploit count for auto-kick
	var total = counts.values().reduce(func(a, b): return a + b, 0)
	if total >= GameConfig.AutoResponse.AUTO_KICK_THRESHOLD:
		_auto_kick(player_id, "Too many exploit detections", exploit_type)

## ============================================================================
## HANDLER FUNCTIONS
## ============================================================================

func _handle_spam(player_id: String, count: int) -> void:
	# First offense: just warn
	if count == 1:
		var msg := "Warning: Spam detected. Continued spam will result in mute."
		_notify_player(player_id, msg)
		player_warned.emit(player_id, "spam", msg)
		return

	# Subsequent: mute
	if count >= 2:
		var duration = GameConfig.AutoResponse.SPAM_MUTE_DURATION
		SecurityService.restrict_player(player_id, "chat", duration)
		_notify_admins("Auto-muted %s for %d seconds (spam count: %d)" % [player_id, duration, count])
		_notify_player(player_id, "Muted for %d seconds for spam." % duration)
		action_taken.emit(player_id, ActionType.MUTE, "spam",
			"Auto-muted for %d seconds (count: %d)" % [duration, count])

func _handle_speed_hack(player_id: String, count: int) -> void:
	var required = GameConfig.AutoResponse.SPEEDHACK_CONFIRMATIONS_REQUIRED

	# Notify but don't auto-act unless configured
	if not GameConfig.AutoResponse.AUTO_BAN_SPEEDHACK:
		if count >= required:
			_notify_admins("Speed hack confirmed for %s (count: %d). Manual review needed." % [player_id, count])
			action_taken.emit(player_id, ActionType.WARN, "speed_hack",
				"Speed hack confirmed (count: %d), manual review needed" % count)
		return

	# Auto-ban if configured
	if count >= required:
		_auto_ban(player_id, "Speed hack (auto-banned after %d confirmations)" % required, "speed_hack")

func _handle_teleport_hack(player_id: String, count: int) -> void:
	var required = GameConfig.AutoResponse.TELEPORTHACK_CONFIRMATIONS_REQUIRED

	if not GameConfig.AutoResponse.AUTO_BAN_TELEPORTHACK:
		if count >= required:
			_notify_admins("Teleport hack confirmed for %s (count: %d). Manual review needed." % [player_id, count])
			action_taken.emit(player_id, ActionType.WARN, "teleport_hack",
				"Teleport hack confirmed (count: %d), manual review needed" % count)
		return

	if count >= required:
		_auto_ban(player_id, "Teleport hack (auto-banned after %d confirmations)" % required, "teleport_hack")

func _handle_item_duplication(player_id: String, count: int) -> void:
	var required = GameConfig.AutoResponse.ITEM_DUP_CONFIRMATIONS_REQUIRED

	if not GameConfig.AutoResponse.AUTO_BAN_ITEM_DUPLICATION:
		if count >= required:
			_notify_admins("Item duplication confirmed for %s (count: %d). Manual review needed." % [player_id, count])
			action_taken.emit(player_id, ActionType.WARN, "item_duplication",
				"Item duplication confirmed (count: %d), manual review needed" % count)
		return

	if count >= required:
		_auto_ban(player_id, "Item duplication (auto-banned after %d confirmations)" % required, "item_duplication")

## ============================================================================
## AUTO ACTIONS
## ============================================================================

func _auto_kick(player_id: String, reason: String, exploit_type: String = "exploit_threshold") -> void:
	GameLog.warn("AutoResponse: Kicking %s: %s" % [player_id, reason])

	# Find peer ID and kick
	var peer_id = _get_peer_for_player(player_id)
	if peer_id > 0:
		NetworkManager.kick_player(peer_id, reason)

	_notify_admins("Auto-kicked %s: %s" % [player_id, reason])
	action_taken.emit(player_id, ActionType.KICK, exploit_type, reason)

func _auto_ban(player_id: String, reason: String, exploit_type: String = "exploit_threshold") -> void:
	GameLog.warn("AutoResponse: Banning %s: %s" % [player_id, reason])

	# Issue permanent ban
	NetworkManager.ban_player(player_id, reason, "auto_response")

	# Kick if still connected
	var peer_id = _get_peer_for_player(player_id)
	if peer_id > 0:
		NetworkManager.kick_player(peer_id, "Banned: " + reason)

	_notify_admins("Auto-banned %s: %s" % [player_id, reason])
	action_taken.emit(player_id, ActionType.BAN, exploit_type, reason)

## ============================================================================
## HELPERS
## ============================================================================

func _get_peer_for_player(player_id: String) -> int:
	# Try to find peer ID from NetworkManager or PlayerManager
	if PlayerManager and PlayerManager.has_player(player_id):
		var info = PlayerManager.get_player_info(player_id)
		return info.get("peer_id", -1)
	return -1

func _notify_player(player_id: String, message: String) -> void:
	# Send in-game notification to player
	if NotificationService:
		NotificationService.send_to_player(player_id, message, NotificationService.NotificationType.WARNING)

func _notify_admins(message: String) -> void:
	# Log for admin review
	GameLog.warn("ADMIN: " + message)
	
	# Send to all admins if configured
	if GameConfig.AutoResponse.NOTIFY_ADMINS and NotificationService:
		NotificationService.broadcast_alert(
			"[ADMIN] " + message,
			[NotificationService.AlertScope.server_wide()],
			NotificationService.NotificationType.WARNING
		)

## ============================================================================
## CONFIGURATION
## ============================================================================

func enable() -> void:
	_enabled = true
	GameLog.info("AutoResponseService: Enabled")

func disable() -> void:
	_enabled = false
	GameLog.info("AutoResponseService: Disabled")

func is_enabled() -> bool:
	return _enabled

func reset_player_count(player_id: String) -> void:
	_player_exploit_counts.erase(player_id)

func get_player_counts(player_id: String) -> Dictionary:
	return _player_exploit_counts.get(player_id, {})
