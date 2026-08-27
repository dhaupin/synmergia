## AutoResponseService - Automated responses to exploit detection
## Takes actions based on configured thresholds
class_name AutoResponseService
extends Node

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
	Logger.info("AutoResponseService: %s" % ("Enabled" if _enabled else "Disabled"))

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
	Logger.info("AutoResponse: %s detected %s (count: %d)" % [player_id, exploit_type, count])
	
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
		_auto_kick(player_id, "Too many exploit detections")

## ============================================================================
## HANDLER FUNCTIONS
## ============================================================================

func _handle_spam(player_id: String, count: int) -> void:
	# First offense: just warn
	if count == 1:
		_notify_player(player_id, "Warning: Spam detected. Continued spam will result in mute.")
		return
	
	# Subsequent: mute
	if count >= 2:
		var duration = GameConfig.AutoResponse.SPAM_MUTE_DURATION
		SecurityService.restrict_player(player_id, "chat", duration)
		_notify_admins("Auto-muted %s for %d seconds (spam count: %d)" % [player_id, duration, count])
		_notify_player(player_id, "Muted for %d seconds for spam." % duration)

func _handle_speed_hack(player_id: String, count: int) -> void:
	var required = GameConfig.AutoResponse.SPEEDHACK_CONFIRMATIONS_REQUIRED
	
	# Notify but don't auto-act unless configured
	if not GameConfig.AutoResponse.AUTO_BAN_SPEEDHACK:
		if count >= required:
			_notify_admins("Speed hack confirmed for %s (count: %d). Manual review needed." % [player_id, count])
		return
	
	# Auto-ban if configured
	if count >= required:
		_auto_ban(player_id, "Speed hack (auto-banned after %d confirmations)" % required)

func _handle_teleport_hack(player_id: String, count: int) -> void:
	var required = GameConfig.AutoResponse.TELEPORTHACK_CONFIRMATIONS_REQUIRED
	
	if not GameConfig.AutoResponse.AUTO_BAN_TELEPORTHACK:
		if count >= required:
			_notify_admins("Teleport hack confirmed for %s (count: %d). Manual review needed." % [player_id, count])
		return
	
	if count >= required:
		_auto_ban(player_id, "Teleport hack (auto-banned after %d confirmations)" % required)

func _handle_item_duplication(player_id: String, count: int) -> void:
	var required = GameConfig.AutoResponse.ITEM_DUP_CONFIRMATIONS_REQUIRED
	
	if not GameConfig.AutoResponse.AUTO_BAN_ITEM_DUPLICATION:
		if count >= required:
			_notify_admins("Item duplication confirmed for %s (count: %d). Manual review needed." % [player_id, count])
		return
	
	if count >= required:
		_auto_ban(player_id, "Item duplication (auto-banned after %d confirmations)" % required)

## ============================================================================
## AUTO ACTIONS
## ============================================================================

func _auto_kick(player_id: String, reason: String) -> void:
	Logger.warn("AutoResponse: Kicking %s: %s" % [player_id, reason])
	
	# Find peer ID and kick
	var peer_id = _get_peer_for_player(player_id)
	if peer_id > 0:
		NetworkManager.kick_player(peer_id, reason)
	
	_notify_admins("Auto-kicked %s: %s" % [player_id, reason])

func _auto_ban(player_id: String, reason: String) -> void:
	Logger.warn("AutoResponse: Banning %s: %s" % [player_id, reason])
	
	# Issue permanent ban
	NetworkManager.ban_player(player_id, reason, "auto_response")
	
	# Kick if still connected
	var peer_id = _get_peer_for_player(player_id)
	if peer_id > 0:
		NetworkManager.kick_player(peer_id, "Banned: " + reason)
	
	_notify_admins("Auto-banned %s: %s" % [player_id, reason])

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
	Logger.warn("ADMIN: " + message)
	
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
	Logger.info("AutoResponseService: Enabled")

func disable() -> void:
	_enabled = false
	Logger.info("AutoResponseService: Disabled")

func is_enabled() -> bool:
	return _enabled

func reset_player_count(player_id: String) -> void:
	_player_exploit_counts.erase(player_id)

func get_player_counts(player_id: String) -> Dictionary:
	return _player_exploit_counts.get(player_id, {})
