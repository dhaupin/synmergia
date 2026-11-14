## MarkovPredictor - canonical PropChunk movement prediction.
##
## Learns where a player moves BETWEEN canonical prop chunks and predicts
## the next one, so a consumer can pre-derive it (the clipmap's prop layer
## prefetches the predicted cell before the player arrives).
##
## Addressing is the CANONICAL layer: a key is a `PropChunk` int (terrain
## face + barycentric cell, player-independent and stable). This replaced
## the old planar `SpatialFragmenter` grid -- that scheme was the retired
## floor(pos/100) world and its keys addressed nothing the clipmap streams.
##
## Model:
## - Transition counts over OBSERVED moves: `from -> to`, canonical int
##   keys, no rigid grid. A row's counts give P(next | current).
## - Momentum fallback (cold start / unseen row): extrapolate the last
##   move's direction in 3D from the two chunk centers and resolve the
##   cell the player is heading into.
##
## Frame primitive: NO autoload, NO class_name, NO GameManager dependency.
extends RefCounted

const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")

## History window size (last N arrivals kept for diagnostics).
const HISTORY_WINDOW: int = 10

## Number of top predictions returned.
const TOP_PREDICTIONS: int = 3

## Minimum observed transitions before a prediction is considered informed.
const MIN_HISTORY_SAMPLES: int = 5

## Probability reserved for the momentum cell when a row has no observed
## transitions (the rest is spread over "stays put").
const MOMENTUM_CONFIDENCE: float = 0.9


## Per-player prediction state.
class PlayerState:
	var player_id: String = ""
	var current_key: int = -1
	var depth: int = PropChunk.DEFAULT_DEPTH
	var last_from_key: int = -1
	var last_to_key: int = -1
	var last_move_dir: Vector3 = Vector3.ZERO   # to_center - from_center
	var history: Array[int] = []
	var transition_counts: Dictionary = {}       # "from->to" (int) -> count
	var total_transitions: int = 0


var _states: Dictionary = {}   # player_id -> PlayerState


## Feed the player's CURRENT canonical chunk (call every frame or on tick).
## Learns a transition whenever the chunk changes; no-op otherwise.
func observe(player_id: String, key: int, depth: int = PropChunk.DEFAULT_DEPTH) -> void:
	var state: PlayerState = _get_or_create_state(player_id, depth)
	if state.current_key == key:
		return
	if state.current_key >= 0:
		record_movement(player_id, state.current_key, key, depth)
	else:
		state.current_key = key
		state.history.append(key)
		if state.history.size() > HISTORY_WINDOW:
			state.history.pop_front()


## Record an explicit move between two canonical chunks.
func record_movement(player_id: String, from_key: int, to_key: int,
		depth: int = PropChunk.DEFAULT_DEPTH) -> void:
	var state: PlayerState = _get_or_create_state(player_id, depth)
	if from_key >= 0 and to_key >= 0 and from_key != to_key:
		var tkey: String = "%d->%d" % [from_key, to_key]
		state.transition_counts[tkey] = int(state.transition_counts.get(tkey, 0)) + 1
		state.total_transitions += 1
		var from_dir: Vector3 = PropChunk.chunk_center_dir(from_key, depth)
		var to_dir: Vector3 = PropChunk.chunk_center_dir(to_key, depth)
		state.last_move_dir = to_dir - from_dir
		state.last_from_key = from_key
		state.last_to_key = to_key
	state.current_key = to_key
	state.history.append(to_key)
	if state.history.size() > HISTORY_WINDOW:
		state.history.pop_front()


## Predict the next canonical chunk(s) for a player. Returns an
## Array[Dictionary] sorted by probability desc, each
## {"chunk_key": int, "probability": float}. Empty when the player has no
## known current chunk.
func predict_next(player_id: String) -> Array[Dictionary]:
	var state: PlayerState = _states.get(player_id)
	if state == null or state.current_key < 0:
		return []

	var from_key: int = state.current_key
	var prefix: String = "%d->" % from_key
	var counts: Dictionary = {}
	var row_sum: float = 0.0
	for tkey in state.transition_counts.keys():
		var k: String = tkey
		if k.begins_with(prefix):
			var to_key: int = int(k.substr(prefix.length()))
			var c: float = float(state.transition_counts[tkey])
			counts[to_key] = c
			row_sum += c

	if row_sum > 0.0:
		var probs: Dictionary = {}
		for to_key in counts:
			probs[to_key] = float(counts[to_key]) / row_sum
		# Tiny momentum bias breaks ties toward movement continuity.
		var mom: int = _momentum_key(state)
		if mom >= 0 and probs.has(mom):
			probs[mom] = float(probs[mom]) + 0.001
		return _sort(probs)

	# No observed transitions from this chunk: momentum, else stay put.
	var mom_key: int = _momentum_key(state)
	if mom_key >= 0:
		return [{"chunk_key": mom_key, "probability": MOMENTUM_CONFIDENCE},
			{"chunk_key": from_key, "probability": 1.0 - MOMENTUM_CONFIDENCE}]
	return [{"chunk_key": from_key, "probability": 1.0}]


## Predict N steps ahead by iterating the learned transition rows
## (row-normalized so probability mass never leaks), falling back to
## momentum then stay-put per row.
func predict_n_steps(player_id: String, steps: int) -> Array[Dictionary]:
	var state: PlayerState = _states.get(player_id)
	if state == null or state.current_key < 0:
		return []

	var probs: Dictionary = {state.current_key: 1.0}
	for _step in range(steps):
		var next_probs: Dictionary = {}
		for key in probs.keys():
			var p: float = float(probs[key])
			var prefix: String = "%d->" % key
			var row: Dictionary = {}
			var row_sum: float = 0.0
			for tkey in state.transition_counts.keys():
				var k: String = tkey
				if k.begins_with(prefix):
					var to_key: int = int(k.substr(prefix.length()))
					var c: float = float(state.transition_counts[tkey])
					row[to_key] = c
					row_sum += c
			if row_sum > 0.0:
				for to_key in row:
					next_probs[to_key] = float(next_probs.get(to_key, 0.0)) + p * (float(row[to_key]) / row_sum)
			else:
				# Carry probability forward: momentum cell then stay-put.
				var stay_key: int = key
				var mom: int = _momentum_key_from(state, key)
				if mom >= 0:
					next_probs[mom] = float(next_probs.get(mom, 0.0)) + p * MOMENTUM_CONFIDENCE
					next_probs[stay_key] = float(next_probs.get(stay_key, 0.0)) + p * (1.0 - MOMENTUM_CONFIDENCE)
				else:
					next_probs[stay_key] = float(next_probs.get(stay_key, 0.0)) + p
		probs = next_probs

	var sorted: Array[Dictionary] = []
	for key in probs.keys():
		sorted.append({"chunk_key": key, "probability": float(probs[key])})
	sorted.sort_custom(_sort_by_probability)
	if sorted.size() > TOP_PREDICTIONS:
		sorted.resize(TOP_PREDICTIONS)
	return sorted


## True once the player has enough observed transitions to be informed.
func has_sufficient_history(player_id: String) -> bool:
	var state: PlayerState = _states.get(player_id)
	return state != null and state.total_transitions >= MIN_HISTORY_SAMPLES


## The player's current canonical chunk key, or -1.
func get_current_chunk(player_id: String) -> int:
	var state: PlayerState = _states.get(player_id)
	return state.current_key if state != null else -1


func get_player_state(player_id: String) -> Dictionary:
	var state: PlayerState = _states.get(player_id)
	if state == null:
		return {}
	return {
		"player_id": player_id,
		"current_chunk_key": state.current_key,
		"total_transitions": state.total_transitions,
		"history_size": state.history.size(),
		"has_sufficient_history": has_sufficient_history(player_id),
	}


func clear_all() -> void:
	_states.clear()


## ---- Internal helpers -----------------------------------------------------

func _get_or_create_state(player_id: String, depth: int) -> PlayerState:
	if not _states.has(player_id):
		var s := PlayerState.new()
		s.player_id = player_id
		s.depth = depth
		_states[player_id] = s
	return _states[player_id] as PlayerState


## The canonical cell the player is heading into from their last move.
func _momentum_key(state: PlayerState) -> int:
	return _momentum_key_from(state, state.current_key)


## Momentum from an explicit origin key: extrapolate the last move's
## direction (a 3D delta of chunk centers) and resolve the target cell.
func _momentum_key_from(state: PlayerState, from_key: int) -> int:
	if from_key < 0 or state.last_move_dir == Vector3.ZERO:
		return -1
	var from_dir: Vector3 = PropChunk.chunk_center_dir(from_key, state.depth)
	var target: Vector3 = from_dir + state.last_move_dir
	if target.length() < 1e-6:
		return -1
	return PropChunk.chunk_for_dir(target, state.depth)


func _sort(probs: Dictionary) -> Array[Dictionary]:
	var sorted: Array[Dictionary] = []
	for key in probs.keys():
		sorted.append({"chunk_key": key, "probability": float(probs[key])})
	sorted.sort_custom(_sort_by_probability)
	return sorted


static func _sort_by_probability(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("probability", 0.0)) > float(b.get("probability", 0.0))
