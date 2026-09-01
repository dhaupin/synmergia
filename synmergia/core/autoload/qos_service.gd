## QoSService - Quality of Service infrastructure
## Handles rate limiting, throttling, bulkhead pattern, and debouncing
class_name QoSService
extends Node

# Frame-level notification dispatch (see synmergia/core/notifications/).
# QoSService surfaces rate-limit and circuit-breaker events through the
# typed-Kind pipeline. The dispatch goes through NotificationService.notify
# (the service-level verb that wraps send_event), so call sites only need
# the kind enum and a dedupe key.
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## ============================================================================
## SIGNALS
## ============================================================================
signal rate_limited(player_id: String, action_type: String, current_rate: float, max_rate: float)
signal throttle_triggered(scope: String, action_type: String, current_rate: float, max_rate: float)
signal bulkhead_rejected(service_name: String)
signal action_queued(player_id: String, action_type: String, queue_size: int)

## ============================================================================
## ENUMS
## ============================================================================

enum CircuitState {
	CLOSED,  ## Normal operation
	OPEN,    ## Fail-fast mode
	HALF_OPEN  ## Probe mode
}

enum ConnectionQuality {
	EXCELLENT,
	GOOD,
	FAIR,
	POOR,
	BAD,
	UNKNOWN
}

## ============================================================================
## RATE LIMITING (Token Bucket)
## ============================================================================

## Per-player rate limit buckets: player_id -> action_type -> {tokens, last_update}
var _rate_limit_buckets: Dictionary = {}

## Rate limit configuration: action_type -> max_per_second. Built lazily so we
## can resolve GameConfig autoload values at runtime (the parser can't see them
## in check-only mode without class_name on GameConfig).
var _rate_limit_config: Dictionary = {}
var _rate_limit_config_built: bool = false

func _get_rate_limit_config() -> Dictionary:
	if _rate_limit_config_built:
		return _rate_limit_config
	_rate_limit_config = _build_rate_limit_config()
	_rate_limit_config_built = true
	return _rate_limit_config

func _build_rate_limit_config() -> Dictionary:
	var rate_limits: Variant = _get_game_config_value("QoS", "RateLimits")
	var rl: Dictionary = rate_limits if rate_limits is Dictionary else {}
	return {
		"movement": float(rl.get("MAX_MOVEMENT_PER_SECOND", 10.0)),
		"combat": float(rl.get("MAX_COMBAT_PER_SECOND", 20.0)),
		"chat": float(rl.get("MAX_CHAT_PER_MINUTE", 600.0)) / 60.0,
		"whisper": float(rl.get("MAX_WHISPER_PER_MINUTE", 60.0)) / 60.0,
		"trade": float(rl.get("MAX_TRADE_PER_MINUTE", 30.0)) / 60.0,
		"party": float(rl.get("MAX_PARTY_PER_MINUTE", 20.0)) / 60.0,
		"guild": float(rl.get("MAX_GUILD_PER_MINUTE", 30.0)) / 60.0,
		"item_action": float(rl.get("MAX_ITEM_ACTIONS_PER_MINUTE", 60.0)) / 60.0,
		"account_create": 0.1,
		"instance": 0.05,
		"transfer": 0.033,
		"general": float(rl.get("MAX_GENERAL_PER_SECOND", 10.0))
	}

func _get_game_config_value(section: String, key: String) -> Variant:
	var config: Node = _resolve_autoload("GameConfig")
	if config == null:
		return null
	var section_val: Variant = config.get(section)
	if section_val is Dictionary:
		return section_val.get(key)
	if section_val == null:
		return null
	return section_val.get(key)

func _get_config_float(section: String, key: String, default: float) -> float:
	var v: Variant = _get_game_config_value(section, key)
	if v == null:
		return default
	return float(v)

func _get_config_int(section: String, key: String, default: int) -> int:
	var v: Variant = _get_game_config_value(section, key)
	if v == null:
		return default
	return int(v)

## ============================================================================
## GLOBAL THROTTLING
## ============================================================================

## Global action counters: action_type -> {count, window_start}
var _throttle_counters: Dictionary = {}

## Action queues per player: player_id -> action_type -> [queued_actions]
var _action_queues: Dictionary = {}

## ============================================================================
## BULKHEAD PATTERN
## ============================================================================

## Active operations per service: service_name -> count
var _bulkhead_active: Dictionary = {}

## Waiting operations per service: service_name -> [waiting_callbacks]
var _bulkhead_waiting: Dictionary = {}

## ============================================================================
## DEBOUNCE
## ============================================================================

## Pending debounced calls: key -> {callback, timer, data}
var _debounce_timers: Dictionary = {}

## ============================================================================
## CIRCUIT BREAKERS
## ============================================================================

## Circuit breaker states: service_name -> {state, failures, successes, last_failure_time}
var _circuit_breakers: Dictionary = {}

## ============================================================================
## CONNECTION QUALITY
## ============================================================================

## Per-player latency data: player_id -> {latency_history[], packet_loss, jitter}
var _connection_quality: Dictionary = {}
var _total_checks: int = 0
var _rate_limited_count: int = 0

## ============================================================================
## LIFECYCLE
## ============================================================================

func _ready() -> void:
	pass  # GameLog.info removed
	# Start cleanup timer for stale data
	var cleanup_timer := Timer.new()
	cleanup_timer.timeout.connect(_cleanup_stale_data)
	cleanup_timer.wait_time = 60.0  # Cleanup every minute
	cleanup_timer.autostart = true
	add_child(cleanup_timer)

## ============================================================================
## RATE LIMITING
## ============================================================================

## Static facade: call sites use `QoSService.rate_limit(...)` as a singleton-style
## call. This shim resolves the autoload instance and delegates to the real
## implementation. Fails open (returns true) if the service is unreachable so
## callers don't get a hard crash outside of a live scene tree.
static func rate_limit(player_id: String, action_type: String) -> bool:
	if player_id == "":
		return false
	var inst: Node = get_instance()
	if inst == null:
		return true
	return inst.call("_rate_limit_impl", player_id, action_type)

## Public accessor for the autoload instance. Useful when callers need to
## connect to instance signals (e.g. `QoSService.get_instance().rate_limited.connect(...)`),
## which the parser cannot expose via the class_name alone.
static func get_instance() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	if not ml is SceneTree:
		return null
	var root: Window = (ml as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null("QoSService")

## Resolve any autoload by name. Returns null outside a live scene tree.
static func _resolve_autoload(autoload_name: String) -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	if not ml is SceneTree:
		return null
	var root: Window = (ml as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null(autoload_name)

## Instance implementation. Uses self state (token buckets, config).
func _rate_limit_impl(player_id: String, action_type: String) -> bool:
	var cfg: Dictionary = _get_rate_limit_config()
	var max_rate: float = cfg.get(action_type, cfg.get("general", 10.0))

	if not _rate_limit_buckets.has(player_id):
		_rate_limit_buckets[player_id] = {}

	var buckets = _rate_limit_buckets[player_id]
	if not buckets.has(action_type):
		buckets[action_type] = {"tokens": max_rate, "last_update": Time.get_ticks_msec()}

	var bucket = buckets[action_type]
	var now = Time.get_ticks_msec()
	var elapsed = (now - bucket["last_update"]) / 1000.0

	# Replenish tokens based on elapsed time
	var tokens_to_add = elapsed * max_rate
	bucket["tokens"] = mini(bucket["tokens"] + tokens_to_add, max_rate)
	bucket["last_update"] = now

	# Check if we have tokens available
	if bucket["tokens"] >= 1.0:
		bucket["tokens"] -= 1.0
		return true

	# Rate limited - notify player
	rate_limited.emit(player_id, action_type, bucket["tokens"], max_rate)
	_notify_player_rate_limit(player_id, action_type, max_rate)
	return false

## Notify player they've been rate limited
func _notify_player_rate_limit(player_id: String, action_type: String, max_rate: float) -> void:
	# Respect config toggle. GameConfig.Security is an inner class with
	# const booleans; the previous runtime-dict lookup (config.get("Security"))
	# never matched because Node has no generic .get(String) for an inner-class
	# const, so the function bailed early. Access the const directly.
	if not GameConfig.Security.ENABLE_SECURITY_ALERTS:
		return
	if not GameConfig.Security.ALERT_ON_RATE_LIMIT:
		return

	if not is_instance_valid(NotificationService):
		return

	var message: String = _get_rate_limit_message(action_type, max_rate)
	var cooldown := _get_cooldown_seconds(action_type, max_rate)

	if cooldown > 0:
		message += " Wait %.1fs." % cooldown

	# Frame-level dispatch via the service-level notify() verb. The frame
	# handles dedupe (5s window per (player, action) so a spam loop can't
	# toast 100x/sec) and type/priority mapping (RATE_LIMITED → WARNING+
	# NORMAL in the kind table). NotificationService is an autoload, so
	# the is_instance_valid guard is the only check we need.
	NotificationService.notify(
		NotifKind.RATE_LIMITED,
		message,
		"QoSService",
		"qos_rl:%s:%s" % [player_id, action_type],
		{"action_type": action_type, "max_rate": max_rate, "cooldown": cooldown},
		player_id
	)

## Get human-readable action name
func _get_action_display_name(action_type: String) -> String:
	var names := {
		"chat": "chat messages",
		"whisper": "whispers",
		"trade": "trade requests",
		"party": "party invites",
		"guild": "guild actions",
		"inventory_transfer": "item transfers",
		"gold_transfer": "gold transfers",
		"inventory_trade": "trades",
		"loot_roll": "loot rolls",
		"loot_pickup": "loot pickups",
		"loot_abandon": "loot abandons",
		"movement": "movements",
		"combat": "combat actions",
		"item_action": "item actions"
	}
	return names.get(action_type, action_type)

## Get human-readable rate limit message
func _get_rate_limit_message(action_type: String, max_rate: float) -> String:
	var action_name := _get_action_display_name(action_type)
	return "Too many %s! Slow down." % action_name

## Calculate cooldown in seconds until next token available
func _get_cooldown_seconds(action_type: String, max_rate: float) -> float:
	if max_rate <= 0:
		return 1.0
	return 1.0 / max_rate

## Set custom rate limit for an action type
func set_rate_limit(action_type: String, max_per_second: float) -> void:
	_rate_limit_config[action_type] = max_per_second

## Get current rate for a player/action
func get_current_rate(player_id: String, action_type: String) -> float:
	if not _rate_limit_buckets.has(player_id):
		return 0.0
	if not _rate_limit_buckets[player_id].has(action_type):
		return 0.0
	return _rate_limit_buckets[player_id][action_type].get("tokens", 0.0)

## ============================================================================
## GLOBAL THROTTLING
## ============================================================================

## Look up a scope's max rate from the GameConfig autoload without referencing
## the class identifier (which check-only mode can't see).
func _get_throttle_max_rate(scope: String) -> float:
	var config: Node = _resolve_autoload("GameConfig")
	if config == null:
		return 100.0
	var throttle_node: Variant = config.get("Throttle")
	if throttle_node == null:
		return 100.0
	match scope:
		"global_chat":
			var v: Variant = throttle_node.get("MAX_GLOBAL_CHAT_PER_SECOND") if throttle_node is Dictionary else throttle_node.MAX_GLOBAL_CHAT_PER_SECOND if "MAX_GLOBAL_CHAT_PER_SECOND" in throttle_node else 100.0
			return float(v) if v != null else 100.0
		"global_combat":
			var v: Variant = throttle_node.get("MAX_GLOBAL_COMBAT_PER_SECOND") if throttle_node is Dictionary else throttle_node.MAX_GLOBAL_COMBAT_PER_SECOND if "MAX_GLOBAL_COMBAT_PER_SECOND" in throttle_node else 50.0
			return float(v) if v != null else 50.0
		_:
			return 100.0

## Check if an action is throttled globally
## Returns true if allowed, false if throttled
func throttle(scope: String, action_type: String) -> bool:
	var max_rate: float = _get_throttle_max_rate(scope)


	match scope:
		_:
			pass  # max_rate is already set above

	if not _throttle_counters.has(action_type):
		_throttle_counters[action_type] = {"count": 0, "window_start": Time.get_ticks_msec()}
	
	var counter = _throttle_counters[action_type]
	var now = Time.get_ticks_msec()
	var elapsed = (now - counter["window_start"]) / 1000.0
	
	# Reset window if elapsed time exceeds 1 second
	if elapsed >= 1.0:
		counter["count"] = 0
		counter["window_start"] = now
	
	# Check against limit
	if counter["count"] < max_rate:
		counter["count"] += 1
		return true
	
	# Throttled
	throttle_triggered.emit(scope, action_type, counter["count"], max_rate)
	return false

## Queue an action for later processing
func queue_action(player_id: String, action_type: String, action_data: Dictionary) -> bool:
	if not _action_queues.has(player_id):
		_action_queues[player_id] = {}
	
	var queue = _action_queues[player_id].get(action_type, [])
	
	if queue.size() >= _get_config_int("Throttle", "MAX_QUEUED_ACTIONS", 50):
		return false
	
	queue.append({"data": action_data, "timestamp": Time.get_ticks_msec()})
	_action_queues[player_id][action_type] = queue
	action_queued.emit(player_id, action_type, queue.size())
	return true

## Get next queued action for processing
func get_next_queued(player_id: String, action_type: String) -> Dictionary:
	if not _action_queues.has(player_id):
		return {}
	
	var queue = _action_queues[player_id].get(action_type, [])
	if queue.is_empty():
		return {}
	
	var action = queue.pop_at(0)
	_action_queues[player_id][action_type] = queue
	return action.get("data", {})

## ============================================================================
## BULKHEAD PATTERN
## ============================================================================

## Execute a callback through the bulkhead
## Returns the result or null if rejected
func bulkhead_execute(service_name: String, player_id: String, callback: Callable) -> Variant:
	var global_active = _bulkhead_active.get("__global__", 0)
	
	# Check global limit
	if global_active >= _get_config_int("QoS", "MAX_CONCURRENT_GLOBAL", 100):
		bulkhead_rejected.emit(service_name)
		return null

	# Check per-service limit
	var service_active = _bulkhead_active.get(service_name, 0)
	if service_active >= _get_config_int("QoS", "MAX_CONCURRENT_PER_SERVICE", 10):
		bulkhead_rejected.emit(service_name)
		return null

	# Check per-player limit
	var player_active = _bulkhead_active.get(player_id, 0)
	if player_active >= _get_config_int("QoS", "MAX_CONCURRENT_PER_PLAYER", 3):
		# Per-player saturation. The bulkhead_rejected signal (above) is
		# service-scoped, so we toast the player here directly via the
		# frame. THROTTLED → WARNING + NORMAL. Dedupe on
		# (player, service) so a flood of rejections in a second doesn't
		# spam toasts.
		if is_instance_valid(NotificationService):
			NotificationService.notify(
				NotifKind.THROTTLED,
				"%s is busy — please slow down." % service_name,
				"QoSService",
				"bulkhead_player:%s:%s" % [player_id, service_name],
				{"service": service_name, "active": player_active, "max": _get_config_int("QoS", "MAX_CONCURRENT_PER_PLAYER", 3)},
				player_id
			)
		return null
	
	# Increment counters
	_bulkhead_active["__global__"] = global_active + 1
	_bulkhead_active[service_name] = service_active + 1
	_bulkhead_active[player_id] = player_active + 1
	
	# Execute the callback
	var result = callback.call()
	
	# Decrement counters
	_bulkhead_active["__global__"] = _bulkhead_active.get("__global__", 1) - 1
	_bulkhead_active[service_name] = _bulkhead_active.get(service_name, 1) - 1
	_bulkhead_active[player_id] = _bulkhead_active.get(player_id, 1) - 1
	
	return result

## Get current bulkhead stats
func get_bulkhead_stats() -> Dictionary:
	return {
		"global_active": _bulkhead_active.get("__global__", 0),
		"per_service": _bulkhead_active.duplicate(),
		"max_global": _get_config_int("QoS", "MAX_CONCURRENT_GLOBAL", 100),
		"max_per_service": _get_config_int("QoS", "MAX_CONCURRENT_PER_SERVICE", 10)
	}

## ============================================================================
## DEBOUNCE
## ============================================================================

## Look up debounce bounds from GameConfig.QoS.Debounce without referencing
## the class identifier. Returns sensible defaults if unavailable.
func _get_debounce_bounds() -> Dictionary:
	var config: Node = _resolve_autoload("GameConfig")
	if config == null:
		return {"default": 250, "max": 5000}
	var qos: Variant = config.get("QoS")
	if qos == null:
		return {"default": 250, "max": 5000}
	var debounce: Variant = qos.get("Debounce") if qos is Dictionary else null
	if debounce == null:
		return {"default": 250, "max": 5000}
	var d_default: int = int(debounce.get("DEFAULT_DELAY_MS", 250)) if debounce is Dictionary else 250
	var d_max: int = int(debounce.get("MAX_DELAY_MS", 5000)) if debounce is Dictionary else 5000
	return {"default": d_default, "max": d_max}

## Debounce a callback - cancels previous if called again within delay
func debounce(key: String, callback: Callable, delay_ms: int = -1, data: Variant = null) -> void:
	var bounds := _get_debounce_bounds()
	if delay_ms < 0:
		delay_ms = bounds["default"]
	delay_ms = mini(delay_ms, bounds["max"])
	
	# Cancel existing timer if any
	if _debounce_timers.has(key):
		var existing = _debounce_timers[key]
		if existing.has("timer") and is_instance_valid(existing["timer"]):
			existing["timer"].stop()
			existing["timer"].queue_free()
	
	# Create new timer
	var timer := Timer.new()
	timer.wait_time = delay_ms / 1000.0
	timer.one_shot = true
	
	var debounce_data = {"callback": callback, "data": data, "key": key}
	timer.timeout.connect(_debounce_callback.bind(debounce_data))
	
	add_child(timer)
	timer.start()
	
	_debounce_timers[key] = {"timer": timer, "callback": callback, "data": data}

## Internal debounce callback
func _debounce_callback(data: Dictionary) -> void:
	var key = data.get("key", "")
	var callback: Callable = data.get("callback")
	var callback_data = data.get("data")
	
	if callback.is_valid():
		if callback_data != null:
			callback.call(callback_data)
		else:
			callback.call()
	
	# Cleanup
	_debounce_timers.erase(key)

## Cancel a debounced call
func cancel_debounce(key: String) -> void:
	if _debounce_timers.has(key):
		var existing = _debounce_timers[key]
		if existing.has("timer") and is_instance_valid(existing["timer"]):
			existing["timer"].stop()
			existing["timer"].queue_free()
		_debounce_timers.erase(key)

## ============================================================================
## CIRCUIT BREAKER
## ============================================================================

## Execute with circuit breaker protection
func circuit_execute(service_name: String, operation: Callable) -> Dictionary:
	var breaker = _get_or_create_breaker(service_name)
	var now = Time.get_ticks_msec() / 1000.0
	
	match breaker["state"]:
		CircuitState.OPEN:
			# Check if recovery timeout has passed
			if now - breaker["last_failure_time"] >= _get_config_float("QoS", "RECOVERY_TIMEOUT_SEC", 30.0):
				breaker["state"] = CircuitState.HALF_OPEN
				pass  # GameLog.debug removed
			else:
				return {"success": false, "error": "Circuit OPEN", "rejected": true}
		
		CircuitState.HALF_OPEN:
			# Allow limited calls in half-open state
			pass
	
	# Execute the operation
	var result = operation.call()
	
	if result is Dictionary and result.get("success", false):
		_on_circuit_success(breaker, service_name)
		return {"success": true, "data": result.get("data"), "rejected": false}
	else:
		_on_circuit_failure(breaker, service_name)
		return {"success": false, "error": result.get("error", "Unknown error"), "rejected": breaker["state"] == CircuitState.OPEN}

func _get_or_create_breaker(service_name: String) -> Dictionary:
	if not _circuit_breakers.has(service_name):
		_circuit_breakers[service_name] = {
			"state": CircuitState.CLOSED,
			"failures": 0,
			"successes": 0,
			"last_failure_time": 0.0
		}
	return _circuit_breakers[service_name]

func _on_circuit_success(breaker: Dictionary, service_name: String) -> void:
	breaker["successes"] += 1
	if breaker["state"] == CircuitState.HALF_OPEN:
		if breaker["successes"] >= _get_config_int("QoS", "SUCCESS_THRESHOLD", 3):
			breaker["state"] = CircuitState.CLOSED
			breaker["failures"] = 0
			breaker["successes"] = 0
			# Recovery complete — let admins know service is healthy again.
			_notify_circuit_change(service_name, "CLOSED", "recovered after probes")

func _on_circuit_failure(breaker: Dictionary, service_name: String) -> void:
	breaker["failures"] += 1
	breaker["last_failure_time"] = Time.get_ticks_msec() / 1000.0

	if breaker["state"] == CircuitState.HALF_OPEN:
		breaker["state"] = CircuitState.OPEN
		breaker["successes"] = 0
		_notify_circuit_change(service_name, "OPEN", "probe failed; back to fail-fast")
	elif breaker["failures"] >= _get_config_int("QoS", "FAILURE_THRESHOLD", 5):
		breaker["state"] = CircuitState.OPEN
		_notify_circuit_change(service_name, "OPEN", "failure threshold reached")

## Send a notification when a service's circuit breaker changes state.
## Routes through the typed NotifKind pipeline. CLOSED-after-recovery
## uses QOS_RECOVERED; OPEN/HALF_OPEN use CIRCUIT_OPEN. Dedupe on
## (service, state) so a chatter of probe failures during a single
## recovery cycle doesn't toast admins 20 times in a row.
func _notify_circuit_change(service_name: String, new_state: String, detail: String) -> void:
	if not is_instance_valid(NotificationService):
		return
	var msg := "[QoS] Circuit '%s' → %s (%s)" % [service_name, new_state, detail]
	var kind: int = NotifKind.QOS_RECOVERED if new_state == "CLOSED" else NotifKind.CIRCUIT_OPEN
	NotificationService.notify(
		kind,
		msg,
		"QoSService",
		"qos_circuit:%s:%s" % [service_name, new_state],
		{"service_name": service_name, "new_state": new_state, "detail": detail},
		"admins"
	)

## Get circuit breaker state
func get_circuit_state(service_name: String) -> String:
	if not _circuit_breakers.has(service_name):
		return "UNKNOWN"
	
	match _circuit_breakers[service_name]["state"]:
		CircuitState.CLOSED:
			return "CLOSED"
		CircuitState.OPEN:
			return "OPEN"
		CircuitState.HALF_OPEN:
			return "HALF_OPEN"
	return "UNKNOWN"

## ============================================================================
## CONNECTION QUALITY
## ============================================================================

## Record latency for a player
func record_latency(player_id: String, latency_ms: int, packet_loss: float = 0.0) -> void:
	if not _connection_quality.has(player_id):
		_connection_quality[player_id] = {
			"latency_history": [],
			"packet_loss": 0.0,
			"jitter_history": []
		}
	
	var data = _connection_quality[player_id]
	
	# Add to history (keep last 20 samples)
	data["latency_history"].append(latency_ms)
	if data["latency_history"].size() > 20:
		data["latency_history"].pop_at(0)
	
	# Update packet loss (exponential moving average)
	data["packet_loss"] = data["packet_loss"] * 0.9 + packet_loss * 0.1
	
	# Calculate jitter
	if data["latency_history"].size() >= 2:
		var jitter = absi(data["latency_history"][-1] - data["latency_history"][-2])
		data["jitter_history"].append(jitter)
		if data["jitter_history"].size() > 10:
			data["jitter_history"].pop_at(0)

## Get connection quality for a player
func get_connection_quality(player_id: String) -> ConnectionQuality:
	if not _connection_quality.has(player_id):
		return ConnectionQuality.UNKNOWN
	
	var data = _connection_quality[player_id]
	if data["latency_history"].is_empty():
		return ConnectionQuality.UNKNOWN
	
	# Use average latency
	var avg_latency = 0
	for latency in data["latency_history"]:
		avg_latency += latency
	avg_latency /= data["latency_history"].size()
	
	# Check latency thresholds
	if avg_latency <= _get_config_int("QoS", "EXCELLENT_LATENCY_MS", 50):
		return ConnectionQuality.EXCELLENT
	elif avg_latency <= _get_config_int("QoS", "GOOD_LATENCY_MS", 100):
		return ConnectionQuality.GOOD
	elif avg_latency <= _get_config_int("QoS", "FAIR_LATENCY_MS", 200):
		return ConnectionQuality.FAIR
	elif avg_latency <= _get_config_int("QoS", "POOR_LATENCY_MS", 500):
		return ConnectionQuality.POOR
	else:
		return ConnectionQuality.BAD

## Get latency stats for a player
func get_latency_stats(player_id: String) -> Dictionary:
	if not _connection_quality.has(player_id):
		return {}
	
	var data = _connection_quality[player_id]
	var avg_latency = 0
	var min_latency = 999999
	var max_latency = 0
	
	for latency in data["latency_history"]:
		avg_latency += latency
		min_latency = mini(min_latency, latency)
		max_latency = maxi(max_latency, latency)
	
	if not data["latency_history"].is_empty():
		avg_latency /= data["latency_history"].size()
	
	var avg_jitter = 0
	if not data["jitter_history"].is_empty():
		for j in data["jitter_history"]:
			avg_jitter += j
		avg_jitter /= data["jitter_history"].size()
	
	return {
		"avg_latency": avg_latency,
		"min_latency": min_latency,
		"max_latency": max_latency,
		"packet_loss": data["packet_loss"],
		"avg_jitter": avg_jitter,
		"quality": ConnectionQuality.keys()[get_connection_quality(player_id)]
	}

## ============================================================================
## CLEANUP
## ============================================================================

func _cleanup_stale_data() -> void:
	var now = Time.get_ticks_msec()
	
	# Cleanup stale rate limit buckets (no activity for 5 minutes)
	for player_id in _rate_limit_buckets.keys():
		var buckets = _rate_limit_buckets[player_id]
		var has_activity = false
		for action_type in buckets.keys():
			var elapsed = (now - buckets[action_type]["last_update"]) / 1000.0
			if elapsed < 300:  # 5 minutes
				has_activity = true
				break
		if not has_activity:
			_rate_limit_buckets.erase(player_id)
	
	# Cleanup stale queues
	for player_id in _action_queues.keys():
		var queues = _action_queues[player_id]
		var has_valid = false
		for action_type in queues.keys():
			var queue = queues[action_type]
			# Remove expired items
			var valid_items = []
			for item in queue:
				var item_age = (now - item["timestamp"]) / 1000.0
				if item_age < _get_config_float("QoS", "QUEUE_TIMEOUT_SEC", 60.0):
					valid_items.append(item)
					has_valid = true
			if valid_items.is_empty():
				queues.erase(action_type)
			else:
				queues[action_type] = valid_items
		if not has_valid:
			_action_queues.erase(player_id)
	
	# Cleanup dead circuit breakers (been closed for 10 minutes)
	for service_name in _circuit_breakers.keys():
		var breaker = _circuit_breakers[service_name]
		if breaker["state"] == CircuitState.CLOSED:
			var elapsed = (now / 1000.0 - breaker.get("last_failure_time", 0))
			if elapsed > 600:  # 10 minutes
				_circuit_breakers.erase(service_name)

## ============================================================================
## ADMIN HELPERS (for AdminShell)
## ============================================================================

## Get rate limit info for all action types
func get_rate_limit_info() -> Dictionary:
	var info: Dictionary = {}
	for action_type in _rate_limit_config.keys():
		info[action_type] = {
			"max_rate": _rate_limit_config[action_type]
		}
	# Add defaults for known action types
	for action_type in ["chat", "whisper", "trade", "party", "guild"]:
		if not info.has(action_type):
			info[action_type] = {
				"max_rate": _get_config_float("QoS", "MAX_ACTIONS_PER_SECOND", 10.0)
			}
	return info

## Get player's current rates
func get_player_rates(player_id: String) -> Dictionary:
	var rates: Dictionary = {}
	var now := Time.get_ticks_msec()
	
	if _rate_limit_buckets.has(player_id):
		var buckets: Dictionary = _rate_limit_buckets[player_id]
		for action_type in buckets.keys():
			var bucket: Array = buckets[action_type]
			# Calculate rate over last second
			var recent: Array = bucket.filter(func(t): return now - t < 1000)
			if not recent.is_empty():
				rates[action_type] = float(recent.size())
	
	return rates

## Get QoS statistics
func get_statistics() -> Dictionary:
	var stats: Dictionary = {
		"total_checks": _total_checks,
		"rate_limited_count": _rate_limited_count,
		"circuit_open_count": 0,
		"active_players": _rate_limit_buckets.keys().size()
	}
	
	# Count open circuits
	for service_name in _circuit_breakers.keys():
		var breaker = _circuit_breakers[service_name]
		if breaker["state"] == CircuitState.OPEN:
			stats["circuit_open_count"] += 1
	
	return stats
