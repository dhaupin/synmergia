## QoSService - Quality of Service infrastructure
## Handles rate limiting, throttling, bulkhead pattern, and debouncing
extends Node

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

## Rate limit configuration: action_type -> max_per_second
var _rate_limit_config: Dictionary = {
	"movement": GameConfig.QoS.RateLimits.MAX_MOVEMENT_PER_SECOND,
	"combat": GameConfig.QoS.RateLimits.MAX_COMBAT_PER_SECOND,
	"chat": GameConfig.QoS.RateLimits.MAX_CHAT_PER_MINUTE / 60.0,
	"whisper": GameConfig.QoS.RateLimits.MAX_WHISPER_PER_MINUTE / 60.0,
	"trade": GameConfig.QoS.RateLimits.MAX_TRADE_PER_MINUTE / 60.0,
	"party": GameConfig.QoS.RateLimits.MAX_PARTY_PER_MINUTE / 60.0,
	"guild": GameConfig.QoS.RateLimits.MAX_GUILD_PER_MINUTE / 60.0,
	"item_action": GameConfig.QoS.RateLimits.MAX_ITEM_ACTIONS_PER_MINUTE / 60.0,
	"account_create": 0.1,  # 1 per 10 seconds max
	"instance": 0.05,       # 1 per 20 seconds max
	"transfer": 0.033,       # 1 per 30 seconds max
	"general": GameConfig.QoS.RateLimits.MAX_GENERAL_PER_SECOND
}

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
	pass  # Logger.info removed
	# Start cleanup timer for stale data
	var cleanup_timer := Timer.new()
	cleanup_timer.timeout.connect(_cleanup_stale_data)
	cleanup_timer.wait_time = 60.0  # Cleanup every minute
	cleanup_timer.autostart = true
	add_child(cleanup_timer)

## ============================================================================
## RATE LIMITING
## ============================================================================

## Check if an action is rate limited for a player
## Returns true if allowed, false if rate limited
func rate_limit(player_id: String, action_type: String) -> bool:
	# Defensive: reject empty player IDs
	if player_id == "":
		return false

	var max_rate: float = _rate_limit_config.get(action_type, _rate_limit_config["general"])
	
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
	# Respect config toggle
	if not GameConfig.Security.ENABLE_SECURITY_ALERTS:
		return
	if not GameConfig.Security.ALERT_ON_RATE_LIMIT:
		return
	if not NotificationService:
		return
	
	var message := _get_rate_limit_message(action_type, max_rate)
	var cooldown := _get_cooldown_seconds(action_type, max_rate)
	
	if cooldown > 0:
		message += " Wait %.1fs." % cooldown
	
	NotificationService.send_to_player(
		player_id,
		message,
		NotificationService.NotificationType.SYSTEM,
		NotificationService.Priority.HIGH
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

## Check if an action is throttled globally
## Returns true if allowed, false if throttled
func throttle(scope: String, action_type: String) -> bool:
	var max_rate: float
	match scope:
		"global_chat":
			max_rate = GameConfig.Throttle.MAX_GLOBAL_CHAT_PER_SECOND
		"global_combat":
			max_rate = GameConfig.Throttle.MAX_GLOBAL_COMBAT_PER_SECOND
		_:
			max_rate = 100.0  # Default
	
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
	
	if queue.size() >= GameConfig.Throttle.MAX_QUEUED_ACTIONS:
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
	if global_active >= GameConfig.QoS.Bulkhead.MAX_CONCURRENT_GLOBAL:
		bulkhead_rejected.emit(service_name)
		return null
	
	# Check per-service limit
	var service_active = _bulkhead_active.get(service_name, 0)
	if service_active >= GameConfig.QoS.Bulkhead.MAX_CONCURRENT_PER_SERVICE:
		bulkhead_rejected.emit(service_name)
		return null
	
	# Check per-player limit
	var player_active = _bulkhead_active.get(player_id, 0)
	if player_active >= GameConfig.QoS.Bulkhead.MAX_CONCURRENT_PER_PLAYER:
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
		"max_global": GameConfig.QoS.Bulkhead.MAX_CONCURRENT_GLOBAL,
		"max_per_service": GameConfig.QoS.Bulkhead.MAX_CONCURRENT_PER_SERVICE
	}

## ============================================================================
## DEBOUNCE
## ============================================================================

## Debounce a callback - cancels previous if called again within delay
func debounce(key: String, callback: Callable, delay_ms: int = GameConfig.QoS.Debounce.DEFAULT_DELAY_MS, data: Variant = null) -> void:
	delay_ms = mini(delay_ms, GameConfig.QoS.Debounce.MAX_DELAY_MS)
	
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
			if now - breaker["last_failure_time"] >= GameConfig.QoS.CircuitBreaker.RECOVERY_TIMEOUT_SEC:
				breaker["state"] = CircuitState.HALF_OPEN
				pass  # Logger.debug removed
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
		if breaker["successes"] >= GameConfig.QoS.CircuitBreaker.SUCCESS_THRESHOLD:
			breaker["state"] = CircuitState.CLOSED
			breaker["failures"] = 0
			breaker["successes"] = 0
			pass  # Logger.info removed

func _on_circuit_failure(breaker: Dictionary, service_name: String) -> void:
	breaker["failures"] += 1
	breaker["last_failure_time"] = Time.get_ticks_msec() / 1000.0
	
	if breaker["state"] == CircuitState.HALF_OPEN:
		breaker["state"] = CircuitState.OPEN
		breaker["successes"] = 0
		pass  # Logger.warn removed
	elif breaker["failures"] >= GameConfig.QoS.CircuitBreaker.FAILURE_THRESHOLD:
		breaker["state"] = CircuitState.OPEN
		pass  # Logger.warn removed

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
	if avg_latency <= GameConfig.QoS.Latency.EXCELLENT:
		return ConnectionQuality.EXCELLENT
	elif avg_latency <= GameConfig.QoS.Latency.GOOD:
		return ConnectionQuality.GOOD
	elif avg_latency <= GameConfig.QoS.Latency.FAIR:
		return ConnectionQuality.FAIR
	elif avg_latency <= GameConfig.QoS.Latency.POOR:
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
				if item_age < GameConfig.Throttle.QUEUE_TIMEOUT_SEC:
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
				"max_rate": GameConfig.QoS.MAX_ACTIONS_PER_SECOND
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
