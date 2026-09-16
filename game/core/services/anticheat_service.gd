## AntiCheatService - Detects and prevents cheating for humans AND agents
## Includes bot detection, macro detection, speed hacks, and anomaly detection
extends Node
const DictStore = preload("res://adapters/persistence/dict_store.gd")

signal cheat_detected(player_id: String, cheat_type: String, confidence: float, evidence: Dictionary)
signal player_flagged(player_id: String, flag_type: String)
signal player_banned(player_id: String, reason: String)
signal player_unbanned(player_id: String)

## Detection thresholds
const PERFECT_TIMING_THRESHOLD: float = 0.02  # Human jitter is ~50ms+
const MOVEMENT_PREDICTION_WINDOW: float = 5.0  # Seconds of movement to analyze
const RESPONSE_TIME_VARIANCE_HUMAN: float = 0.3  # Humans have ~30% variance
const IDLE_CHANCE_HUMAN: float = 0.02  # Humans idle ~2% of time
const PATH_REPETITION_THRESHOLD: float = 0.8  # 80% same path = suspicious

## Session heuristics
const SESSION_VARIANCE_HUMAN_MIN: float = 0.1  # Variance in session lengths
const BREAK_FREQUENCY_HUMAN: float = 0.1  # Expected breaks per hour

var _player_profiles: Dictionary = {}  # player_id -> Profile data
var _suspicion_scores: Dictionary = {}  # player_id -> suspicion (0.0 to 1.0)
var _banned_players: Dictionary = {}  # player_id -> ban info

## DictStore key prefix
const _kv_prefix := "anticheat:"

class PlayerProfile:
	var player_id: String
	var is_agent: bool
	var action_timestamps: Array = []
	var movement_paths: Array = []  # Array of Vector3 positions
	var response_times: Array = []  # ms between stimulus and action
	var idle_periods: Array = []  # Array of {start, end} idle times
	var session_start: int = 0
	var last_position: Vector3 = Vector3.ZERO
	var last_action_time: int = 0

	func _init(p_id: String, agent: bool):
		player_id = p_id
		is_agent = agent
		session_start = Time.get_ticks_msec()
		last_action_time = session_start

## Register a new player
func register_player(player_id: String, is_agent: bool = false) -> void:
	if not _player_profiles.has(player_id):
		_player_profiles[player_id] = PlayerProfile.new(player_id, is_agent)
		_suspicion_scores[player_id] = 0.0
		_persist_suspicion(player_id)
		GameLog.info("AntiCheatService: Monitoring %s (%s)" % [player_id, "Agent" if is_agent else "Human"])

## Unregister player
func unregister_player(player_id: String) -> void:
	_player_profiles.erase(player_id)
	_suspicion_scores.erase(player_id)

## Record an action with timing
func record_action(player_id: String, action_type: String, position: Vector3 = Vector3.ZERO,
					response_time_ms: int = -1) -> void:
	if not _player_profiles.has(player_id):
		register_player(player_id)

	var profile: PlayerProfile = _player_profiles[player_id]
	var now := Time.get_ticks_msec()

	profile.action_timestamps.append(now)
	profile.last_action_time = now

	if position != Vector3.ZERO:
		profile.last_position = position
		profile.movement_paths.append({
			"pos": position,
			"time": now
		})

	if response_time_ms >= 0:
		profile.response_times.append(response_time_ms)

	# Periodic analysis
	if profile.action_timestamps.size() % 50 == 0:
		_analyze_player(player_id)

## Record idle period
func record_idle(player_id: String, duration_ms: int) -> void:
	if not _player_profiles.has(player_id):
		return

	var profile: PlayerProfile = _player_profiles[player_id]
	var now := Time.get_ticks_msec()
	profile.idle_periods.append({
		"start": now - duration_ms,
		"end": now,
		"duration": duration_ms
	})

## Analyze player for suspicious patterns
func _analyze_player(player_id: String) -> void:
	var profile: PlayerProfile = _player_profiles.get(player_id)
	if not profile:
		return

	var suspicion := 0.0
	var evidence: Dictionary = {}

	# Agent players get a "fairness pass" for some patterns
	var agent_penalty_modifier := 0.5 if profile.is_agent else 1.0

	# Check 1: Perfect timing detection (macro/keyboard)
	suspicion += _check_perfect_timing(profile) * agent_penalty_modifier
	if suspicion > 0:
		evidence["perfect_timing"] = true

	# Check 2: Movement prediction (bot pathing)
	suspicion += _check_movement_prediction(profile) * agent_penalty_modifier
	if suspicion > 0:
		evidence["predictable_movement"] = true

	# Check 3: Response time variance (humans are inconsistent)
	suspicion += _check_response_variance(profile) * agent_penalty_modifier
	if suspicion > 0:
		evidence["consistent_response"] = true

	# Check 4: Idle patterns (humans take breaks)
	suspicion += _check_idle_patterns(profile) * agent_penalty_modifier
	if suspicion > 0:
		evidence["no_idle_time"] = true

	# Check 5: Action rate (bots are consistent)
	suspicion += _check_action_rate(profile) * agent_penalty_modifier
	if suspicion > 0:
		evidence["consistent_action_rate"] = true

	# Update suspicion score
	_suspicion_scores[player_id] = clamp(_suspicion_scores[player_id] + suspicion * 0.1, 0.0, 1.0)
	_persist_suspicion(player_id)

	if suspicion > 0.3:
		cheat_detected.emit(player_id, "pattern_anomaly", suspicion, evidence)

	if _suspicion_scores[player_id] > 0.8:
		_flag_player(player_id, "high_suspicion")
	elif _suspicion_scores[player_id] > 0.5:
		_flag_player(player_id, "moderate_suspicion")

## Check for perfect timing (indicates macro)
func _check_perfect_timing(profile: PlayerProfile) -> float:
	if profile.action_timestamps.size() < 10:
		return 0.0

	# Calculate variance in time between actions
	var intervals: Array = []
	for i in range(1, min(profile.action_timestamps.size(), 20)):
		intervals.append(profile.action_timestamps[i] - profile.action_timestamps[i-1])

	if intervals.is_empty():
		return 0.0

	# Calculate variance
	var mean := 0.0
	for t in intervals:
		mean += t
	mean /= intervals.size()

	var variance := 0.0
	for t in intervals:
		var diff: float = float(t) - float(mean)
		variance += diff * diff
	variance /= intervals.size()

	# Low variance = suspicious
	var std_dev := sqrt(variance)
	var coefficient_of_variation := std_dev / mean if mean > 0 else 1.0

	if coefficient_of_variation < PERFECT_TIMING_THRESHOLD:
		return 0.5  # Very suspicious

	return 0.0

## Check for predictable movement (indicates bot)
func _check_movement_prediction(profile: PlayerProfile) -> float:
	if profile.movement_paths.size() < 20:
		return 0.0

	# Check if same path is repeated
	var path_count: Dictionary = {}
	for path_data in profile.movement_paths:
		var pos: Vector3 = path_data["pos"]
		var key := "%d,%d,%d" % [int(pos.x), int(pos.y), int(pos.z)]
		path_count[key] = path_count.get(key, 0) + 1

	var total := profile.movement_paths.size()
	var max_repetition := 0.0

	for key in path_count:
		max_repetition = max(max_repetition, float(path_count[key]) / float(total))

	if max_repetition > PATH_REPETITION_THRESHOLD:
		return 0.6  # Very suspicious - same spot repeatedly

	return 0.0

## Check response time variance (bots are consistent)
func _check_response_variance(profile: PlayerProfile) -> float:
	if profile.response_times.size() < 10:
		return 0.0

	var mean := 0.0
	for t in profile.response_times:
		mean += t
	mean /= profile.response_times.size()

	var variance := 0.0
	for t in profile.response_times:
		var diff: float = float(t) - float(mean)
		variance += diff * diff
	variance /= profile.response_times.size()

	var std_dev := sqrt(variance)
	var coefficient_of_variation := std_dev / mean if mean > 0 else 1.0

	# Humans have high variance, bots have low
	if coefficient_of_variation < RESPONSE_TIME_VARIANCE_HUMAN:
		return 0.3

	return 0.0

## Check idle patterns (humans idle)
func _check_idle_patterns(profile: PlayerProfile) -> float:
	var session_duration_ms := Time.get_ticks_msec() - profile.session_start
	var session_hours := session_duration_ms / 3600000.0

	# Expected idle: at least one break per hour
	var expected_breaks := session_hours * BREAK_FREQUENCY_HUMAN
	var actual_breaks := float(profile.idle_periods.size())

	if actual_breaks < expected_breaks * 0.5:  # Less than half expected
		return 0.2

	return 0.0

## Check action rate consistency (bots are mechanical)
func _check_action_rate(profile: PlayerProfile) -> float:
	var session_duration_ms := Time.get_ticks_msec() - profile.session_start
	if session_duration_ms < 60000:  # Need at least 1 minute
		return 0.0

	var actions_per_minute := float(profile.action_timestamps.size()) / (session_duration_ms / 60000.0)

	# Humans average 10-60 actions per minute depending on playstyle
	# Bots often have very consistent rates
	if actions_per_minute > 100:
		return 0.4  # Extremely high

	return 0.0

## Flag a player for review
func _flag_player(player_id: String, flag_type: String) -> void:
	player_flagged.emit(player_id, flag_type)
	GameLog.warn("AntiCheatService: Player %s flagged: %s" % [player_id, flag_type])

## Check if player is banned
func is_banned(player_id: String) -> bool:
	return _banned_players.has(player_id)

## Ban a player
func ban_player(player_id: String, reason: String) -> void:
	_banned_players[player_id] = {
		"reason": reason,
		"timestamp": Time.get_ticks_msec()
	}
	player_banned.emit(player_id, reason)
	GameLog.info("AntiCheatService: Player %s banned: %s" % [player_id, reason])

## Unban a player
func unban_player(player_id: String) -> void:
	_banned_players.erase(player_id)
	_suspicion_scores[player_id] = 0.0
	player_unbanned.emit(player_id)
	GameLog.info("AntiCheatService: Player %s unbanned" % player_id)

## Get suspicion score
func get_suspicion(player_id: String) -> float:
	return _suspicion_scores.get(player_id, 0.0)

## Get player report
func get_player_report(player_id: String) -> Dictionary:
	var profile: PlayerProfile = _player_profiles.get(player_id)
	if not profile:
		return {}

	return {
		"player_id": player_id,
		"is_agent": profile.is_agent,
		"suspicion_score": get_suspicion(player_id),
		"is_banned": is_banned(player_id),
		"action_count": profile.action_timestamps.size(),
		"session_duration_hours": (Time.get_ticks_msec() - profile.session_start) / 3600000.0,
		"idle_periods": profile.idle_periods.size(),
		"avg_response_time_ms": _calculate_avg_response_time(profile)
	}

func _calculate_avg_response_time(profile: PlayerProfile) -> float:
	if profile.response_times.is_empty():
		return -1.0
	var sum := 0.0
	for t in profile.response_times:
		sum += t
	return sum / profile.response_times.size()

## Periodic cleanup
func _process(delta: float) -> void:
	# Clean up old movement data (keep last 5 minutes)
	var cutoff := Time.get_ticks_msec() - 300000

	for player_id in _player_profiles:
		var profile: PlayerProfile = _player_profiles[player_id]
		profile.movement_paths = profile.movement_paths.filter(func(p): return p["time"] > cutoff)

## == Persistence ============================================================

func _load_state() -> void:
	var store := DictStore.new()
	_suspicion_scores = {}
	_banned_players = {}
	for key in store.all_keys():
		if key.begins_with(_kv_prefix + "suspicion:"):
			var player_id = key.substr(_kv_prefix.length() + 10)
			_suspicion_scores[player_id] = store.get_kv(key)
		elif key.begins_with(_kv_prefix + "ban:"):
			var player_id = key.substr(_kv_prefix.length() + 4)
			_banned_players[player_id] = store.get_kv(key)

func _persist_suspicion(player_id: String) -> void:
	var store := DictStore.new()
	if _suspicion_scores.has(player_id):
		store.set_kv(_kv_prefix + "suspicion:" + player_id, {"score": _suspicion_scores[player_id]})
	else:
		store.erase(_kv_prefix + "suspicion:" + player_id)

func _persist_ban(player_id: String) -> void:
	var store := DictStore.new()
	if _banned_players.has(player_id):
		store.set_kv(_kv_prefix + "ban:" + player_id, _banned_players[player_id])
	else:
		store.erase(_kv_prefix + "ban:" + player_id)
