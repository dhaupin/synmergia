## AutoResponseService - Automated responses to exploit detection
## Takes actions based on configured thresholds using RulesEngine for policy evaluation
extends Node

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind
const RulesEngineScript = preload("res://labs/multi-iso/srv/rules_engine.gd")
const ScopeScript = preload("res://labs/multi-iso/srv/scope.gd")

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
var _player_exploit_counts: Dictionary = {}  # player_id -> {exploit_type: count}

## DictStore key prefix
const _kv_prefix := "auto_response:"

## Track if auto-response is enabled
var _enabled: bool = false

## RulesEngine instance for policy evaluation
var _rules_engine: Object = null

## Scope stack for RulesEngine evaluation (innermost to outermost)
var _scope_stack: Array = []

## ============================================================================
## LIFECYCLE
## ============================================================================

func _ready() -> void:
	_enabled = GameConfig.AutoResponse.ENABLED
	_init_rules_engine()
	_connect_signals()
	_load_state()
	GameLog.info("AutoResponseService: %s" % ("Enabled" if _enabled else "Disabled"))

func _init_rules_engine() -> void:
	_rules_engine = RulesEngineScript.new()

	# Create scope hierarchy: PlayerScope (innermost) -> InstanceScope -> ShardScope -> WorldScope (outermost)
	var world_scope = ScopeScript.new("WorldScope", null, "", {})
	var shard_scope = ScopeScript.new("ShardScope", world_scope, "", {})
	var instance_scope = ScopeScript.new("InstanceScope", shard_scope, "", {})
	var player_scope = ScopeScript.new("PlayerScope", instance_scope, "", {})

	# Stack order: innermost first (PlayerScope) to outermost last (WorldScope)
	_scope_stack = [player_scope, instance_scope, shard_scope, world_scope]

	# Register rules with their resolution strategies
	_rules_engine.register_rule("spam_response", RulesEngineScript.ALL_WINS_WITH_EFFECT, true)
	_rules_engine.register_rule("speedhack_response", RulesEngineScript.TOP_WINS, false)
	_rules_engine.register_rule("teleport_hack_response", RulesEngineScript.TOP_WINS, false)
	_rules_engine.register_rule("item_duplication_response", RulesEngineScript.TOP_WINS, false)
	_rules_engine.register_rule("auto_kick_threshold", RulesEngineScript.TOP_WINS, false)

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

	# Build base context
	var base_context = {
		"player_id": player_id,
		"exploit_type": exploit_type,
		"count": count
	}

	# Evaluate appropriate rule based on exploit type
	match exploit_type:
		"spam":
			var context = base_context.duplicate(true)
			context.warn_threshold = 1
			context.mute_threshold = 2
			context.mute_duration = GameConfig.AutoResponse.SPAM_MUTE_DURATION
			var result = _rules_engine.evaluate("spam_response", context, _scope_stack)
			if result.allow:
				_handle_spam(player_id, count, context)
		"speed_hack":
			var context = base_context.duplicate(true)
			context.required_confirmations = GameConfig.AutoResponse.SPEEDHACK_CONFIRMATIONS_REQUIRED
			context.auto_ban = GameConfig.AutoResponse.AUTO_BAN_SPEEDHACK
			var result = _rules_engine.evaluate("speedhack_response", context, _scope_stack)
			if result.allow:
				_handle_speed_hack(player_id, count, context)
		"teleport_hack":
			var context = base_context.duplicate(true)
			context.required_confirmations = GameConfig.AutoResponse.TELEPORTHACK_CONFIRMATIONS_REQUIRED
			context.auto_ban = GameConfig.AutoResponse.AUTO_BAN_TELEPORTHACK
			var result = _rules_engine.evaluate("teleport_hack_response", context, _scope_stack)
			if result.allow:
				_handle_teleport_hack(player_id, count, context)
		"item_duplication":
			var context = base_context.duplicate(true)
			context.required_confirmations = GameConfig.AutoResponse.ITEM_DUP_CONFIRMATIONS_REQUIRED
			context.auto_ban = GameConfig.AutoResponse.AUTO_BAN_ITEM_DUPLICATION
			var result = _rules_engine.evaluate("item_duplication_response", context, _scope_stack)
			if result.allow:
				_handle_item_duplication(player_id, count, context)

	# Check total exploit count for auto-kick
	var total = counts.values().reduce(func(a, b): return a + b, 0)
	var kick_context = {
		"player_id": player_id,
		"total_exploits": total,
		"threshold": GameConfig.AutoResponse.AUTO_KICK_THRESHOLD
	}
	var kick_result = _rules_engine.evaluate("auto_kick_threshold", kick_context, _scope_stack)
	if kick_result.allow and total >= GameConfig.AutoResponse.AUTO_KICK_THRESHOLD:
		_auto_kick(player_id, "Too many exploit detections", exploit_type)

## ============================================================================
## HANDLER FUNCTIONS
## ============================================================================

func _handle_spam(player_id: String, count: int, context: Dictionary = {}) -> void:
	# First offense: just warn
	if count == 1:
		var msg := "Warning: Spam detected. Continued spam will result in mute."
		_notify_player(player_id, msg)
		player_warned.emit(player_id, "spam", msg)
		return

	# Subsequent: mute
	if count >= 2:
		var duration = context.get("mute_duration", GameConfig.AutoResponse.SPAM_MUTE_DURATION)
		# SecurityService.restrict_player emits the player-facing mute
		# toast (with the right units: "5 minutes" instead of "300
		# seconds"). Don't add a second one here -- clarity means one
		# message, not two.
		SecurityService.restrict_player(player_id, "chat", duration)
		_notify_admins("Auto-muted %s for %d seconds (spam count: %d)" % [player_id, duration, count])
		action_taken.emit(player_id, ActionType.MUTE, "spam",
			"Auto-muted for %d seconds (count: %d)" % [duration, count])

func _handle_speed_hack(player_id: String, count: int, context: Dictionary = {}) -> void:
	var required = context.get("required_confirmations", GameConfig.AutoResponse.SPEEDHACK_CONFIRMATIONS_REQUIRED)
	var auto_ban = context.get("auto_ban", GameConfig.AutoResponse.AUTO_BAN_SPEEDHACK)

	# Notify but don't auto-act unless configured
	if not auto_ban:
		if count >= required:
			_notify_admins("Speed hack confirmed for %s (count: %d). Manual review needed." % [player_id, count])
			action_taken.emit(player_id, ActionType.WARN, "speed_hack",
				"Speed hack confirmed (count: %d), manual review needed" % count)
		return

	# Auto-ban if configured
	if count >= required:
		_auto_ban(player_id, "Speed hack (auto-banned after %d confirmations)" % required, "speed_hack")

func _handle_teleport_hack(player_id: String, count: int, context: Dictionary = {}) -> void:
	var required = context.get("required_confirmations", GameConfig.AutoResponse.TELEPORTHACK_CONFIRMATIONS_REQUIRED)
	var auto_ban = context.get("auto_ban", GameConfig.AutoResponse.AUTO_BAN_TELEPORTHACK)

	if not auto_ban:
		if count >= required:
			_notify_admins("Teleport hack confirmed for %s (count: %d). Manual review needed." % [player_id, count])
			action_taken.emit(player_id, ActionType.WARN, "teleport_hack",
				"Teleport hack confirmed (count: %d), manual review needed" % count)
		return

	if count >= required:
		_auto_ban(player_id, "Teleport hack (auto-banned after %d confirmations)" % required, "teleport_hack")

func _handle_item_duplication(player_id: String, count: int, context: Dictionary = {}) -> void:
	var required = context.get("required_confirmations", GameConfig.AutoResponse.ITEM_DUP_CONFIRMATIONS_REQUIRED)
	var auto_ban = context.get("auto_ban", GameConfig.AutoResponse.AUTO_BAN_ITEM_DUPLICATION)

	if not auto_ban:
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

	# Player-facing toast BEFORE the disconnect. NetworkManager.kick_player
	# drops the connection; the player needs a moment to see WHY. The
	# AppFirewall ban/lift path is the precedent for this.
	_notify_player(player_id, "You have been kicked: %s" % reason, NotifKind.AUTO_ACTION, "kick:" + exploit_type)

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
	# Defensive: PlayerManager may not expose the lookup methods we expect
	# in every environment (fresh autoloads in tests, headless mode, etc.).
	# We try a few known method names and return -1 if any step fails so
	# callers can still proceed with the action (e.g. the ban path doesn't
	# strictly need a peer id, since NetworkManager routes via firewall).
	if PlayerManager == null:
		return -1
	for method_name in ["get_player_info", "get_player", "find_player"]:
		if PlayerManager.has_method(method_name):
			var result = PlayerManager.call(method_name, player_id)
			if result is Dictionary:
				var info: Dictionary = result
				var peer_id = info.get("peer_id", -1)
				if peer_id is int and peer_id > 0:
					return peer_id
			elif result is int and result > 0:
				return result
	# Fallback: scan NetworkManager.connected_peers by player_id key.
	if NetworkManager and NetworkManager.has_method("get"):
		var connected = NetworkManager.get("connected_peers")
		if connected is Dictionary:
			var connected_dict: Dictionary = connected
			for peer_id in connected_dict.keys():
				if "peer_%d" % peer_id == player_id:
					return int(peer_id)
	return -1

func _notify_player(player_id: String, message: String, kind: int = NotifKind.PLAYER_WARNED, dedupe_suffix: String = "") -> void:
	# Frame-level notify(). The dispatcher applies the per-kind window
	# (PLAYER_WARNED = 2s, AUTO_ACTION = 0 -> never dedupe), so callers
	# don't need to manage dedupe state. dedupe_suffix lets callers
	# collapse multiple identical toasts for the same (player, exploit).
	if is_instance_valid(NotificationService):
		var key := "ars:%s:%s" % [_action_key_for_kind(kind), player_id]
		if dedupe_suffix != "":
			key += ":" + dedupe_suffix
		NotificationService.notify(kind, message, "AutoResponseService", key, {}, player_id)

func _action_key_for_kind(kind: int) -> String:
	# Short tag for the dedupe key. Keeps the key readable in the
	# dispatcher's tracked map.
	match kind:
		NotifKind.PLAYER_WARNED: return "warn"
		NotifKind.AUTO_ACTION: return "action"
		NotifKind.SECURITY_BLOCKED: return "block"
		NotifKind.SECURITY_WARNING: return "secwarn"
		_: return "x"

func _notify_admins(message: String) -> void:
	# Log for admin review
	GameLog.warn("ADMIN: " + message)

	# Frame-level admin alert. ADMIN_ALERT kind has a 0 window in the
	# dispatcher -- admins never want a dropped alert, even if the same
	# auto-action fires twice in 5s.
	if GameConfig.AutoResponse.NOTIFY_ADMINS and is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.ADMIN_ALERT,
			message,
			"AutoResponseService",
			"ars_admin:%s:%d" % [message, Time.get_ticks_msec()],
			{}
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

## == Persistence ============================================================

func _load_state() -> void:
	var store := DictStore.new()
	_player_exploit_counts = {}
	for key in store.all_keys():
		if key.begins_with(_kv_prefix):
			var player_id = key.substr(_kv_prefix.length())
			_player_exploit_counts[player_id] = store.get_value(key)

func _persist_exploit_counts(player_id: String) -> void:
	var store := DictStore.new()
	if _player_exploit_counts.has(player_id):
		store.set_value(_kv_prefix + player_id, _player_exploit_counts[player_id])
	else:
		store.erase(_kv_prefix + player_id)