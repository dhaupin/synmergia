## QoSService - Quality of Service for fair matchmaking
## Handles latency compensation, throttling, and connection quality
extends Node
class_name MatchmakingQoS

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

signal connection_quality_changed(player_id: String, quality: ConnectionQuality)
signal latency_warning(player_id: String, latency_ms: int)
signal throttled(player_id: String, reason: String)

enum ConnectionQuality {
	EXCELLENT,  # < 50ms
	GOOD,        # 50-100ms
	FAIR,       # 100-200ms
	POOR,       # 200-500ms
	BAD         # > 500ms or packet loss
}

## Thresholds
const EXCELLENT_MAX_LATENCY: int = 50
const GOOD_MAX_LATENCY: int = 100
const FAIR_MAX_LATENCY: int = 200
const POOR_MAX_LATENCY: int = 500

const PACKET_LOSS_WARNING: float = 0.05  # 5%
const PACKET_LOSS_CRITICAL: float = 0.15  # 15%

## Latency compensation windows
const INTERPOLATION_DELAY_MS: int = 100
const PREDICTION_SALT_MS: int = 50

var _player_latency: Dictionary = {}  # player_id -> latency in ms
var _player_quality: Dictionary = {}   # player_id -> ConnectionQuality
var _player_packet_loss: Dictionary = {}  # player_id -> packet loss ratio
var _player_jitter: Dictionary = {}  # player_id -> jitter in ms

var _latency_history: Dictionary = {}  # player_id -> Array of recent latencies

func _ready() -> void:
	GameLog.info("QoSService: Quality of Service initialized")

## Register a player connection
func register_connection(player_id: String, estimated_latency: int = 100) -> void:
	_player_latency[player_id] = estimated_latency
	_player_quality[player_id] = _calculate_quality(estimated_latency)
	_player_packet_loss[player_id] = 0.0
	_player_jitter[player_id] = 0
	_latency_history[player_id] = []
	GameLog.info("QoSService: Registered %s (latency: %dms)" % [player_id, estimated_latency])

## Unregister player
func unregister_connection(player_id: String) -> void:
	_player_latency.erase(player_id)
	_player_quality.erase(player_id)
	_player_packet_loss.erase(player_id)
	_player_jitter.erase(player_id)
	_latency_history.erase(player_id)

## Update latency measurement
func update_latency(player_id: String, latency_ms: int, packet_loss: float = 0.0) -> void:
	if not _player_latency.has(player_id):
		register_connection(player_id, latency_ms)
	
	# Update history
	if not _latency_history.has(player_id):
		_latency_history[player_id] = []
	
	_latency_history[player_id].append(latency_ms)
	if _latency_history[player_id].size() > 20:  # Keep last 20 samples
		_latency_history[player_id].pop_at(0)
	
	# Calculate jitter (variance)
	var history: Array = _latency_history[player_id]
	if history.size() >= 2:
		var jitter := 0
		for i in range(1, history.size()):
			jitter += abs(history[i] - history[i-1])
		jitter /= history.size() - 1
		_player_jitter[player_id] = jitter
	
	# Update values
	_player_latency[player_id] = latency_ms
	_player_packet_loss[player_id] = packet_loss
	
	var old_quality: ConnectionQuality = _player_quality.get(player_id, ConnectionQuality.GOOD)
	var new_quality := _calculate_quality(latency_ms, packet_loss)
	_player_quality[player_id] = new_quality
	
	if old_quality != new_quality:
		connection_quality_changed.emit(player_id, new_quality)
		# Frame notification: surface the transition to the toast
		# pipeline. Worse than before -> QOS_DEGRADED; better ->
		# QOS_RECOVERED. The dedupe key includes the player and the
		# second-resolution bucket so a flapping connection doesn't
		# spam the toasts but a real recovery does surface.
		if is_instance_valid(NotificationService):
			var kind: int = NotifKind.QOS_DEGRADED if new_quality > old_quality else NotifKind.QOS_RECOVERED
			NotificationService.notify(
				kind,
				"Connection quality: %s (latency %dms, loss %.0f%%)" % [
					ConnectionQuality.keys()[new_quality], latency_ms, packet_loss * 100.0
				],
				"QoSService",
				"qos:quality:%s:%d" % [player_id, Time.get_ticks_msec() / 1000],
				{
					"player_id": player_id,
					"old_quality": ConnectionQuality.keys()[old_quality],
					"new_quality": ConnectionQuality.keys()[new_quality],
					"latency_ms": latency_ms,
					"packet_loss": packet_loss,
				},
				player_id
			)

	# Warnings
	if new_quality == ConnectionQuality.POOR:
		latency_warning.emit(player_id, latency_ms)

## Get latency for a player
func get_latency(player_id: String) -> int:
	return _player_latency.get(player_id, 9999)

## Get connection quality
func get_quality(player_id: String) -> ConnectionQuality:
	return _player_quality.get(player_id, ConnectionQuality.BAD)

## Get jitter
func get_jitter(player_id: String) -> int:
	return _player_jitter.get(player_id, 0)

## Get interpolation delay for client prediction
func get_interpolation_delay(player_id: String) -> int:
	return INTERPOLATION_DELAY_MS + get_latency(player_id) / 2

## Get prediction salt (anti-cheat for server reconciliation)
func get_prediction_salt(player_id: String) -> int:
	return PREDICTION_SALT_MS + get_jitter(player_id) / 2

## Check if player should be throttled
func should_throttle(player_id: String, action_rate: float) -> bool:
	var quality: ConnectionQuality = get_quality(player_id)
	
	match quality:
		ConnectionQuality.EXCELLENT:
			return action_rate > 20.0  # 20 actions/sec
		ConnectionQuality.GOOD:
			return action_rate > 15.0
		ConnectionQuality.FAIR:
			return action_rate > 10.0
		ConnectionQuality.POOR:
			return action_rate > 5.0  # Very limited
		ConnectionQuality.BAD:
			return true  # Throttle everything
	
	return false

## Calculate quality from latency and packet loss
func _calculate_quality(latency_ms: int, packet_loss: float = 0.0) -> ConnectionQuality:
	if packet_loss > PACKET_LOSS_CRITICAL:
		return ConnectionQuality.BAD
	if latency_ms < EXCELLENT_MAX_LATENCY and packet_loss < PACKET_LOSS_WARNING:
		return ConnectionQuality.EXCELLENT
	if latency_ms < GOOD_MAX_LATENCY:
		return ConnectionQuality.GOOD
	if latency_ms < FAIR_MAX_LATENCY:
		return ConnectionQuality.FAIR
	if latency_ms < POOR_MAX_LATENCY:
		return ConnectionQuality.POOR
	return ConnectionQuality.BAD

## Get fair matchmaking group
## Players with similar latency are matched together
func get_matchmaking_group(player_ids: Array, max_latency_spread: int = 100) -> Array:
	var sorted := player_ids.filter(func(p): return _player_latency.has(p))
	sorted.sort_custom(func(a, b): 
		return _player_latency[a] < _player_latency[b]
	)
	
	if sorted.size() <= 1:
		return sorted
	
	var result: Array = [sorted[0]]
	var base_latency: int = _player_latency[sorted[0]]
	
	for i in range(1, sorted.size()):
		if _player_latency[sorted[i]] - base_latency <= max_latency_spread:
			result.append(sorted[i])
	
	return result

## Get QoS report for player
func get_qos_report(player_id: String) -> Dictionary:
	return {
		"player_id": player_id,
		"latency_ms": get_latency(player_id),
		"quality": ConnectionQuality.keys()[get_quality(player_id)],
		"jitter_ms": get_jitter(player_id),
		"packet_loss": _player_packet_loss.get(player_id, 0.0),
		"interpolation_delay_ms": get_interpolation_delay(player_id),
		"prediction_salt_ms": get_prediction_salt(player_id)
	}

## Get all players with poor quality
func get_poor_quality_players() -> Array:
	var poor: Array = []
	for player_id in _player_quality:
		if _player_quality[player_id] == ConnectionQuality.POOR or \
			_player_quality[player_id] == ConnectionQuality.BAD:
			poor.append(player_id)
	return poor

## Throttle a player
func throttle_player(player_id: String, reason: String, duration_ms: int = 5000) -> void:
	throttled.emit(player_id, reason)
	GameLog.warn("QoSService: Throttled %s: %s" % [player_id, reason])
	# Frame notification: THROTTLED maps to WARNING + NORMAL (per
	# _priority_for_kind). The dedupe key includes the player and the
	# second-resolution bucket so repeated throttles within the same
	# second collapse.
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.THROTTLED,
			"You're casting too fast. %s" % reason,
			"QoSService",
			"qos:throttle:%s:%d" % [player_id, Time.get_ticks_msec() / 1000],
			{
				"player_id": player_id,
				"reason": reason,
				"duration_ms": duration_ms,
			},
			player_id
		)

	# Auto-unthrottle after duration
	await get_tree().create_timer(duration_ms / 1000.0).timeout
	# Notify unthrottled (would need more complex state management for this)
