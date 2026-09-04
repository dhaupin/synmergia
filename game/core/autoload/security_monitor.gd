## SecurityMonitor - Centralized security event monitoring
## Listens to security events and logs/alerts appropriately
extends Node
const QoSService = preload("res://core/autoload/qos_service.gd")

# Frame-level notification dispatch (see game/core/notifications/).
# SecurityMonitor surfaces anti-cheat / exploit alerts to the admin
# scope through the typed-Kind pipeline. ADMIN_ALERT → ALERT + HIGH.
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## ============================================================================
## CONFIGURATION
## ============================================================================

## Enable/disable monitoring
var enabled: bool = true

## Log level for security events
enum SecurityLevel {
	DEBUG = 0,
	INFO = 1,
	WARN = 2,
	CRITICAL = 3
}

var _log_level: SecurityLevel = SecurityLevel.INFO

## ============================================================================
## LIFECYCLE
## ============================================================================

func _ready() -> void:
	_connect_signals()
	GameLog.info("SecurityMonitor: Initialized")

func _connect_signals() -> void:
	if SecurityService:
		SecurityService.exploit_detected.connect(_on_exploit_detected)
		SecurityService.permission_denied.connect(_on_permission_denied)
		SecurityService.invalid_input.connect(_on_invalid_input)
	
	var qos: Node = QoSService.get_instance()
	if qos != null:
		qos.rate_limited.connect(_on_rate_limited)

## ============================================================================
## SIGNAL HANDLERS
## ============================================================================

func _on_exploit_detected(player_id: String, exploit_type: String, details: Dictionary) -> void:
	if not enabled:
		return

	var severity := _get_exploit_severity(exploit_type)
	
	match severity:
		SecurityLevel.CRITICAL:
			GameLog.error("SECURITY CRITICAL: Player %s detected %s exploit! Details: %s" % [
				player_id, exploit_type, JSON.stringify(details)
			])
			_alert_admin("CRITICAL", player_id, exploit_type, details)
		SecurityLevel.WARN:
			GameLog.warn("SECURITY WARNING: Player %s flagged for %s. Details: %s" % [
				player_id, exploit_type, JSON.stringify(details)
			])
		_:
			GameLog.debug("Security: Player %s %s attempt (details: %s)" % [
				player_id, exploit_type, JSON.stringify(details)
			])

func _on_permission_denied(player_id: String, action: String, required_level: int) -> void:
	if not enabled:
		return

	GameLog.warn("Permission Denied: Player %s attempted '%s' (requires level %d)" % [
		player_id, action, required_level
	])

func _on_invalid_input(player_id: String, input_type: String, reason: String) -> void:
	if not enabled:
		return

	GameLog.debug("Invalid Input: Player %s - %s: %s" % [player_id, input_type, reason])

func _on_rate_limited(player_id: String, action_type: String, current_rate: float, max_rate: float) -> void:
	if not enabled:
		return

	GameLog.debug("Rate limited: Player %s - %s (%.2f/%.2f)" % [
		player_id, action_type, current_rate, max_rate
	])

## ============================================================================
## HELPERS
## ============================================================================

func _get_exploit_severity(exploit_type: String) -> SecurityLevel:
	var critical := ["speed_hack", "item_duplication", "teleport_hack", "money_exploit"]
	if exploit_type in critical:
		return SecurityLevel.CRITICAL

	var warning := ["spam", "invalid_input", "rapid_fire", "macro_detected"]
	if exploit_type in warning:
		return SecurityLevel.WARN

	return SecurityLevel.INFO

func _alert_admin(severity: String, player_id: String, exploit_type: String, details: Dictionary) -> void:
	var alert_msg := "SECURITY ALERT [%s] Player: %s | Type: %s | Details: %s" % [
		severity, player_id, exploit_type, JSON.stringify(details)
	]
	print(alert_msg)

	# Route to the in-game toast/notification pipeline so admins watching
	# the HUD see critical exploits in real time. The frame dispatch fires
	# notification_received / notification_sent unconditionally, so the
	# toast/combat-log path lights up even when no players are in scope
	# (server-only boot, headless tests).
	if not is_instance_valid(NotificationService):
		return

	# Frame-level dispatch. ADMIN_ALERT → ALERT + HIGH in the kind table.
	# Dedupe on (player, exploit_type) so a single attack that fires 20
	# signals in 200ms collapses to one admin toast.
	NotificationService.notify(
		NotifKind.ADMIN_ALERT,
		"[SECURITY] " + alert_msg,
		"SecurityMonitor",
		"sec_alert:%s:%s" % [player_id, exploit_type],
		{"severity": severity, "player_id": player_id, "exploit_type": exploit_type, "details": details},
		"admins"
	)

## ============================================================================
## CONFIGURATION METHODS
## ============================================================================

func set_log_level(level: SecurityLevel) -> void:
	_log_level = level

func disable() -> void:
	enabled = false
	GameLog.info("SecurityMonitor: Disabled")

func enable() -> void:
	enabled = true
	GameLog.info("SecurityMonitor: Enabled")
