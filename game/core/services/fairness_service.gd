## FairnessService - Ensures fair play for humans AND agents
## All players (human/agent) are equals with same capabilities and limits
extends Node
class_name FairnessService
const QoSService = preload("res://core/autoload/qos_service.gd")

signal fairness_violation(player_id: String, violation_type: String, severity: int)
signal trust_updated(player_id: String, new_trust: float)
signal rate_limit_exceeded(player_id: String, action_type: String)
signal consensus_requested(action_id: String, voters: Array)
signal consensus_reached(action_id: String, result: bool)

## Trust configuration
const INITIAL_TRUST: float = 0.5
const TRUST_DECAY_RATE: float = 0.001  # Per minute of inactivity
const TRUST_GAIN_RATE: float = 0.01  # Per action (normal behavior)
const TRUST_LOSS_SEVERITY: float = 0.1  # Per violation

## Session length (anti-marathon)
const MARATHON_THRESHOLD_HOURS: float = GameConfig.Fairness.MARATHON_THRESHOLD_HOURS
const MARATHON_DEBUFF_START: float = 0.05  # 5% debuff per hour after threshold

var _player_trust: Dictionary = {}  # player_id -> trust score (0.0 to 1.0)
var _player_actions: Dictionary = {}  # player_id -> action timestamps
var _player_session_start: Dictionary = {}  # player_id -> session start time
var _consensus_quests: Dictionary = {}  # action_id -> {votes, required, deadline}

## DictStore key prefix
const _kv_prefix := "fairness:"

func _ready() -> void:
	GameLog.info("FairnessService: Initialized - Humans and Agents are equals")

## Register a player (human or agent)
func register_player(player_id: String, is_agent: bool = false) -> void:
	if not _player_trust.has(player_id):
		_player_trust[player_id] = INITIAL_TRUST
		_player_session_start[player_id] = Time.get_ticks_msec()
		_player_actions[player_id] = {
			"total": 0,
			"movement": [],
			"combat": [],
			"chat": [],
			"last_action": 0
		}
		GameLog.info("FairnessService: Registered %s (%s)" % [player_id, "Agent" if is_agent else "Human"])

## Unregister player
func unregister_player(player_id: String) -> void:
	_player_trust.erase(player_id)
	_player_session_start.erase(player_id)
	_player_actions.erase(player_id)

## Check if action is allowed (rate limiting)
func check_action_rate(player_id: String, action_type: String) -> bool:
	# Delegate to QoSService for rate limiting (consolidation)
	if not _player_actions.has(player_id):
		register_player(player_id)

	var result = QoSService.rate_limit(player_id, action_type)
	if not result:
		rate_limit_exceeded.emit(player_id, action_type)
	return result

## Record an action
func record_action(player_id: String, action_type: String) -> void:
	if not _player_actions.has(player_id):
		return

	var actions: Dictionary = _player_actions[player_id]
	var now := Time.get_ticks_msec()

	actions["total"] += 1
	actions["last_action"] = now

	match action_type:
		"movement":
			actions["movement"].append(now)
		"combat", "skill":
			actions["combat"].append(now)
		"chat":
			actions["chat"].append(now)

	# Slight trust gain for normal activity
	_adjust_trust(player_id, TRUST_GAIN_RATE * 0.1)

## Get player trust score
func get_trust(player_id: String) -> float:
	return _player_trust.get(player_id, INITIAL_TRUST)

## Get player session duration in hours
func get_session_hours(player_id: String) -> float:
	if not _player_session_start.has(player_id):
		return 0.0
	var start_ms: int = _player_session_start[player_id]
	var duration_ms := Time.get_ticks_msec() - start_ms
	return duration_ms / 3600000.0

## Get marathon debuff multiplier
func get_marathon_debuff(player_id: String) -> float:
	var hours := get_session_hours(player_id)
	if hours < MARATHON_THRESHOLD_HOURS:
		return 0.0

	var extra_hours := hours - MARATHON_THRESHOLD_HOURS
	return min(extra_hours * MARATHON_DEBUFF_START, 0.5)  # Max 50% debuff

## Request consensus for contested actions
func request_consensus(action_id: String, involved_players: Array, threshold: float = 0.5) -> bool:
	_consensus_quests[action_id] = {
		"votes": {},
		"required": ceil(involved_players.size() * threshold),
		"players": involved_players,
		"deadline": Time.get_ticks_msec() + 30000,  # 30 second window
		"result": null
	}
	consensus_requested.emit(action_id, involved_players)
	return true

## Cast a vote for consensus
func cast_vote(action_id: String, player_id: String, vote: bool) -> bool:
	if not _consensus_quests.has(action_id):
		return false

	var quest: Dictionary = _consensus_quests[action_id]
	if not quest["players"].has(player_id):
		return false

	quest["votes"][player_id] = vote

	# Check if consensus reached
	var yes_votes := quest["votes"].values().count(true)
	if yes_votes >= quest["required"]:
		quest["result"] = true
		consensus_reached.emit(action_id, true)
		return true

	var total_voted := quest["votes"].size()
	var remaining := quest["players"].size() - total_voted
	var max_yes := yes_votes + remaining

	if max_yes < quest["required"]:
		quest["result"] = false
		consensus_reached.emit(action_id, false)
		return true

	return true

## Get vote status
func get_vote_status(action_id: String) -> Dictionary:
	if not _consensus_quests.has(action_id):
		return {}
	return _consensus_quests[action_id].duplicate(true)

## Report a fairness violation
func report_violation(player_id: String, violation_type: String, severity: int = 1) -> void:
	fairness_violation.emit(player_id, violation_type, severity)
	_adjust_trust(player_id, -TRUST_LOSS_SEVERITY * severity)

	match severity:
		1:  # Minor
			GameLog.warn("FairnessService: Minor violation by %s: %s" % [player_id, violation_type])
		2:  # Moderate
			GameLog.warn("FairnessService: Moderate violation by %s: %s" % [player_id, violation_type])
		3:  # Severe
			GameLog.error("FairnessService: SEVERE violation by %s: %s" % [player_id, violation_type])

func _adjust_trust(player_id: String, delta: float) -> void:
	if not _player_trust.has(player_id):
		_player_trust[player_id] = INITIAL_TRUST

	_player_trust[player_id] = clamp(_player_trust[player_id] + delta, 0.0, 1.0)
	trust_updated.emit(player_id, _player_trust[player_id])

## Get fairness report for a player
func get_fairness_report(player_id: String) -> Dictionary:
	return {
		"trust_score": get_trust(player_id),
		"session_hours": get_session_hours(player_id),
		"marathon_debuff": get_marathon_debuff(player_id),
		"actions_per_minute": _get_action_rate(player_id),
		"is_trusted": get_trust(player_id) > 0.3,
		"is_highly_trusted": get_trust(player_id) > 0.7
	}

func _get_action_rate(player_id: String) -> float:
	if not _player_actions.has(player_id):
		return 0.0
	var actions: Dictionary = _player_actions[player_id]
	var now := Time.get_ticks_msec()
	var window_ms := 60000  # Last minute
	var cutoff := now - window_ms

	# Count recent actions from all arrays
	var recent_total := 0
	for key in ["movement", "combat", "chat"]:
		if actions.has(key) and typeof(actions[key]) == TYPE_ARRAY:
			recent_total += actions[key].filter(func(t): return t > cutoff).size()
	return float(recent_total)

	var recent: Array = actions["total"].filter(func(t): return t > cutoff) if typeof(actions["total"]) == TYPE_ARRAY else 0
	return float(recent.size()) if typeof(recent) == TYPE_ARRAY else 0.0

## Periodic maintenance
func _process(delta: float) -> void:
	# Decay trust for inactive players
	for player_id in _player_trust:
		var actions: Dictionary = _player_actions.get(player_id, {})
		if actions.get("last_action", 0) < Time.get_ticks_msec() - 300000:  # 5 min inactive
			_adjust_trust(player_id, -TRUST_DECAY_RATE * delta * 60)

	# Check consensus deadlines
	for action_id in _consensus_quests.keys():
		var quest: Dictionary = _consensus_quests[action_id]
		if Time.get_ticks_msec() > quest["deadline"] and quest["result"] == null:
			var yes_votes := quest["votes"].values().count(true)
			quest["result"] = false
			consensus_reached.emit(action_id, false)

## == Persistence ============================================================

func _load_state() -> void:
	var store := DictStore.new()
	_player_trust = {}
	_player_actions = {}
	_player_session_start = {}
	for key in store.all_keys():
		if key.begins_with(_kv_prefix + "trust:"):
			var player_id = key.substr(_kv_prefix.length() + 6)
			_player_trust[player_id] = float(store.get_kv(key).get("trust", 0.0))
		elif key.begins_with(_kv_prefix + "actions:"):
			var player_id = key.substr(_kv_prefix.length() + 8)
			_player_actions[player_id] = store.get_kv(key)
		elif key.begins_with(_kv_prefix + "session:"):
			var player_id = key.substr(_kv_prefix.length() + 8)
			_player_session_start[player_id] = int(store.get_kv(key).get("start", 0))

func _persist_trust(player_id: String) -> void:
	var store := DictStore.new()
	if _player_trust.has(player_id):
		store.set_kv(_kv_prefix + "trust:" + player_id, {"trust": _player_trust[player_id]})
	else:
		store.erase(_kv_prefix + "trust:" + player_id)

func _persist_actions(player_id: String) -> void:
	var store := DictStore.new()
	if _player_actions.has(player_id):
		store.set_kv(_kv_prefix + "actions:" + player_id, _player_actions[player_id])
	else:
		store.erase(_kv_prefix + "actions:" + player_id)

func _persist_session(player_id: String) -> void:
	var store := DictStore.new()
	if _player_session_start.has(player_id):
		store.set_kv(_kv_prefix + "session:" + player_id, {"start": _player_session_start[player_id]})
	else:
		store.erase(_kv_prefix + "session:" + player_id)
