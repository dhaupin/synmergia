## MarkovPredictor - Per-player movement prediction using a
## Markov chain over a 3x3 chunk-grid state space.
##
## The state space is centered on the player's current chunk:
##   (0,0) = current chunk, (-1,-1) to (1,1) = neighboring chunks.
##
## Transition matrix: P(next_state | current_state, last_10_movements)
## Prediction: argmax over transition matrix.
##
## Frame primitive: NO autoload, NO class_name, NO GameManager dependency.
##
## Spec: labs/world-building.md sec.14.4, sec.18.5
extends RefCounted

const SpatialFragmenterScript = preload("res://core/frame/geometry/spatial_fragmenter.gd")

## The 3x3 grid offsets relative to the current chunk.
const GRID_OFFSETS: Array[Vector2] = [
	Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1),
	Vector2(-1,  0), Vector2(0,  0), Vector2(1,  0),
	Vector2(-1,  1), Vector2(0,  1), Vector2(1,  1),
]

## History window size (last N movements)
const HISTORY_WINDOW: int = 10

## Number of top predictions to return
const TOP_PREDICTIONS: int = 3

## Prediction horizon in ticks (5s at 10Hz)
const PREDICTION_HORIZON_TICKS: int = 50

## Accuracy threshold required
const ACCURACY_THRESHOLD: float = 0.70

## Minimum history samples before prediction is valid
const MIN_HISTORY_SAMPLES: int = 5


## Per-player Markov state.
class PlayerMarkovState:
	var player_id: String = ""
	var history: Array[Dictionary] = []  # [{chunk_key: String, tick: int}, ...]
	var transition_counts: Dictionary = {}  # "from->to" -> count
	var total_transitions: int = 0
	var current_chunk_key: String = ""
	var last_10_movements: Array[Vector2] = []  # Relative offsets from current
	var prediction_cache: Dictionary = {}  # chunk_key -> probability
	var cache_tick: int = 0


	func _init(p_player_id: String) -> void:
		player_id = p_player_id
		current_chunk_key = ""
		last_10_movements = []
		transition_counts = {}
		total_transitions = 0
		history = []
		prediction_cache = {}
		cache_tick = 0


## The main predictor.
var _states: Dictionary = {}  # player_id -> PlayerMarkovState
var _spatial_fragmenter: SpatialFragmenterScript = null
var _tick_number: int = 0


func _init() -> void:
	_spatial_fragmenter = SpatialFragmenterScript.new()
	_tick_number = 0


## Record a player's movement from one chunk to another.
func record_movement(player_id: String, from_chunk_key: String, to_chunk_key: String) -> void:
	var state := _get_or_create_state(player_id)
	state.history.append({
		"chunk_key": to_chunk_key,
		"tick": _tick_number,
	})
	if state.history.size() > HISTORY_WINDOW * 2:
		state.history.erase(state.history.front())

	# Update transition counts
	if from_chunk_key != "":
		var key := _transition_key(from_chunk_key, to_chunk_key)
		state.transition_counts[key] = state.transition_counts.get(key, 0) + 1
		state.total_transitions += 1

	# Update current chunk
	state.current_chunk_key = to_chunk_key

	# Update last 10 movements (relative offsets from current chunk)
	var offset := _chunk_key_to_offset(to_chunk_key)
	state.last_10_movements.append(offset)
	if state.last_10_movements.size() > HISTORY_WINDOW:
		state.last_10_movements.erase(state.last_10_movements.front())

	# Invalidate prediction cache
	state.prediction_cache.clear()


## Predict the next chunk positions for a player.
## Returns an Array[Dictionary] sorted by probability desc, each:
##   {"chunk_key": String, "probability": float, "offset": Vector2}
func predict_next(player_id: String) -> Array[Dictionary]:
	var state := _states.get(player_id)
	if state == null or state.current_chunk_key == "":
		return []

	# Check cache validity
	if state.prediction_cache.size() > 0 and _tick_number - state.cache_tick < 5:
		return _sort_predictions(state.prediction_cache)

	# Build 3x3 transition probabilities from current chunk
	var from_key := state.current_chunk_key
	var current_offset := _chunk_key_to_offset(from_key)
	var probabilities: Dictionary = {}

	# For each possible next position in the 3x3 grid
	for offset in GRID_OFFSETS:
		var to_key := _offset_to_chunk_key(current_offset + offset)
		var trans_key := _transition_key(from_key, to_key)
		var count := float(state.transition_counts.get(trans_key, 0))
		var total := float(max(state.total_transitions, 1))
		probabilities[to_key] = count / total

	# If no transitions recorded, use uniform distribution over neighbors
	if state.total_transitions == 0:
		var neighbor_count := float(GRID_OFFSETS.size())
		for offset in GRID_OFFSETS:
			var to_key := _offset_to_chunk_key(current_offset + offset)
			probabilities[to_key] = 1.0 / neighbor_count

	state.prediction_cache = probabilities
	state.cache_tick = _tick_number
	return _sort_predictions(probabilities)


## Predict positions T+5s, T+30s, T+5min (multiple steps ahead).
## Returns a Dictionary with "near" (5s), "mid" (30s), "far" (5min) arrays.
func predict_multi_horizon(player_id: String) -> Dictionary:
	var state := _states.get(player_id)
	if state == null or state.current_chunk_key == "":
		return {"near": [], "mid": [], "far": []}

	var near_preds := predict_n_steps(player_id, 5)
	var mid_preds := predict_n_steps(player_id, 30)
	var far_preds := predict_n_steps(player_id, 50)

	return {
		"near": near_preds,
		"mid": mid_preds,
		"far": far_preds,
	}


## Predict N steps ahead by iterating the transition matrix.
func predict_n_steps(player_id: String, steps: int) -> Array[Dictionary]:
	var state := _states.get(player_id)
	if state == null or state.current_chunk_key == "":
		return []

	var current_key := state.current_chunk_key
	var current_offset := _chunk_key_to_offset(current_key)
	var probs: Dictionary = {current_key: 1.0}

	for step in range(steps):
		var next_probs: Dictionary = {}
		for key in probs.keys():
			var p := probs[key]
			var offset := _chunk_key_to_offset(key)
			for grid_offset in GRID_OFFSETS:
				var neighbor_key := _offset_to_chunk_key(offset + grid_offset)
				var trans_key := _transition_key(key, neighbor_key)
				var count := float(state.transition_counts.get(trans_key, 0))
				var total := float(max(state.total_transitions, 1))
				var prob := count / total if total > 0 else 1.0 / float(GRID_OFFSETS.size())
				next_probs[neighbor_key] = next_probs.get(neighbor_key, 0.0) + p * prob
		probs = next_probs

	# Sort by probability and return top predictions
	var sorted := []
	for key in probs.keys():
		sorted.append({"chunk_key": key, "probability": probs[key]})
	sorted.sort_custom(_sort_by_probability)
	if sorted.size() > TOP_PREDICTIONS:
		sorted.resize(TOP_PREDICTIONS)
	return sorted


## Compute prediction accuracy over a series of actual movements.
## actual_movements is an Array[Vector2] of relative offsets from current chunk.
## Returns accuracy as float [0.0, 1.0].
func compute_accuracy(player_id: String, actual_movements: Array) -> float:
	var state := _states.get(player_id)
	if state == null or actual_movements.is_empty():
		return 0.0

	var correct := 0
	var total := 0

	for i in range(actual_movements.size()):
		# Rebuild state up to point i
		var test_state := _states.get(player_id)
		if test_state == null:
			continue

		# Get prediction at this point
		var predictions := predict_next(player_id)
		if predictions.is_empty():
			total += 1
			continue

		# Check if actual movement matches the top prediction
		var actual_offset := actual_movements[i]
		var actual_key := _offset_to_chunk_key(test_state.current_chunk_key)
		actual_key = _offset_to_chunk_key(_chunk_key_to_offset(actual_key) + actual_offset)

		if predictions[0]["chunk_key"] == actual_key:
			correct += 1
		total += 1

		# Advance the state
		if i + 1 < actual_movements.size():
			var next_offset := actual_movements[i + 1]
			record_movement(player_id, test_state.current_chunk_key, actual_key)

	return float(correct) / float(max(total, 1))


## Simulate movement and compute accuracy over N ticks.
## movement_pattern is a function that takes (tick, current_offset) and returns next_offset.
## Returns accuracy as float.
func simulate_and_evaluate(player_id: String, movement_pattern: Callable, ticks: int = 1000) -> float:
	var state := _get_or_create_state(player_id)
	state.current_chunk_key = "0,0"
	state.last_10_movements = []
	state.transition_counts = {}
	state.total_transitions = 0
	state.history.clear()
	state.prediction_cache.clear()

	var current_offset := Vector2.ZERO
	var correct := 0
	var total := 0

	for tick in range(ticks):
		_tick_number = tick
		state.current_chunk_key = _offset_to_chunk_key(current_offset)

		# Get prediction
		var predictions := predict_next(player_id)

		# Determine actual next position
		var next_offset := movement_pattern.call(tick, current_offset)
		var actual_key := _offset_to_chunk_key(next_offset)

		# Check accuracy
		if predictions.size() > 0:
			total += 1
			if predictions[0]["chunk_key"] == actual_key:
				correct += 1

		# Record the movement for learning
		record_movement(player_id, state.current_chunk_key, actual_key)
		current_offset = next_offset

	var accuracy := float(correct) / float(max(total, 1))
	return accuracy


## Get the accuracy threshold.
func get_accuracy_threshold() -> float:
	return ACCURACY_THRESHOLD


## Check if a player has enough history for valid prediction.
func has_sufficient_history(player_id: String) -> bool:
	var state := _states.get(player_id)
	if state == null:
		return false
	return state.total_transitions >= MIN_HISTORY_SAMPLES


## Get the current chunk key for a player.
func get_current_chunk(player_id: String) -> String:
	var state := _states.get(player_id)
	if state == null:
		return ""
	return state.current_chunk_key


## Get player state for debugging.
func get_player_state(player_id: String) -> Dictionary:
	var state := _states.get(player_id)
	if state == null:
		return {}
	return {
		"player_id": player_id,
		"current_chunk_key": state.current_chunk_key,
		"total_transitions": state.total_transitions,
		"history_size": state.history.size(),
		"has_sufficient_history": has_sufficient_history(player_id),
	}


## Clear all player states.
func clear_all() -> void:
	_states.clear()


## ============================================================================
## INTERNAL HELPERS
## ============================================================================

func _get_or_create_state(player_id: String) -> PlayerMarkovState:
	if not _states.has(player_id):
		var new_state := PlayerMarkovState.new()
		new_state.player_id = player_id
		_states[player_id] = new_state
	return _states[player_id] as PlayerMarkovState


func _transition_key(from_key: String, to_key: String) -> String:
	return "%s->%s" % [from_key, to_key]


func _chunk_key_to_offset(key: String) -> Vector2:
	if key == "":
		return Vector2.ZERO
	var parts := key.split(",")
	if parts.size() < 2:
		return Vector2.ZERO
	return Vector2(float(parts[0]), float(parts[1]))


func _offset_to_chunk_key(offset: Vector2) -> String:
	return "%d,%d" % [int(offset.x), int(offset.y)]


func _sort_predictions(probabilities: Dictionary) -> Array[Dictionary]:
	var sorted := []
	for key in probabilities.keys():
		sorted.append({"chunk_key": key, "probability": probabilities[key]})
	sorted.sort_custom(_sort_by_probability)
	return sorted


static func _sort_by_probability(a: Dictionary, b: Dictionary) -> bool:
	return a.get("probability", 0.0) > b.get("probability", 0.0)
