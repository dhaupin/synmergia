## Tests for MarkovPredictor -- the frame's canonical PropChunk movement
## model (co-located per labs conventions).
##
## Covers: canonical-key learning, predict_next ordering and
## probabilities, momentum cold-start, row-normalized predict_n_steps,
## and the state helpers. The planar SpatialFragmenter addressing is gone;
## keys are PropChunk ints (terrain face + barycentric cell).
extends SceneTree

const MarkovScript = preload("res://core/frame/srv/markov.gd")
const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	_test_learns_transition()
	_test_probabilities_and_order()
	_test_empty_states()
	_test_momentum_cold_start()
	_test_predict_n_steps_row_normalized()
	_test_sufficiency_current_and_clear()
	print("Markov tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## Two canonical cells a short step apart near a known direction.
func _pair() -> Array:
	var d0: Vector3 = PropChunk.chunk_center_dir(PropChunk.chunk_for_dir(Vector3(0.3, 0.4, 0.5)), 6)
	var a: int = PropChunk.chunk_for_dir(d0, 6)
	var b: int = PropChunk.chunk_for_dir((d0 + Vector3(0.1, 0.0, 0.0)).normalized(), 6)
	return [a, b]


func _test_learns_transition() -> void:
	var m = MarkovScript.new()
	var p: Array = _pair()
	var a: int = p[0]
	var b: int = p[1]
	_assert(a != b, "sample cells are distinct")
	for _i in range(MarkovScript.MIN_HISTORY_SAMPLES + 3):
		m.record_movement("p", a, b, 6)
	m.observe("p", a, 6)
	var preds: Array = m.predict_next("p")
	_assert(not preds.is_empty(), "predict_next returns predictions after learning")
	_assert_eq(int(preds[0]["chunk_key"]), b, "learned transition is the top prediction")
	_assert(absf(float(preds[0]["probability"]) - 1.0) < 0.001, "single-outcome row predicts probability 1.0")


func _test_probabilities_and_order() -> void:
	var m = MarkovScript.new()
	var p: Array = _pair()
	var a: int = p[0]
	var b: int = p[1]
	var c: int = PropChunk.chunk_for_dir(
		(PropChunk.chunk_center_dir(a, 6) + Vector3(0.0, 0.1, 0.0)).normalized(), 6)
	# Hand-seed the transition rows: a->b weight 7, a->c weight 3.
	m.record_movement("p", a, b, 6)
	m.record_movement("p", a, c, 6)
	var state = m._states["p"]
	state.transition_counts["%d->%d" % [a, b]] = 7
	state.transition_counts["%d->%d" % [a, c]] = 3
	state.current_key = a
	state.last_move_dir = Vector3.ZERO   # disable momentum bias
	var preds: Array = m.predict_next("p")
	_assert_eq(int(preds[0]["chunk_key"]), b, "most-likely transition is first")
	_assert(absf(float(preds[0]["probability"]) - 0.7) < 0.001, "b probability is 0.7")
	_assert(absf(float(preds[1]["probability"]) - 0.3) < 0.001, "c probability is 0.3")
	_assert(float(preds[0]["probability"]) >= float(preds[1]["probability"]), "predictions are sorted descending")


func _test_empty_states() -> void:
	var m = MarkovScript.new()
	_assert(m.predict_next("unknown").is_empty(), "unknown player has no predictions")
	_assert_eq(m.get_current_chunk("unknown"), -1, "unknown player has no current chunk")


func _test_momentum_cold_start() -> void:
	var m = MarkovScript.new()
	var p: Array = _pair()
	var a: int = p[0]
	var b: int = p[1]
	# One observed move sets the momentum direction; a fresh chunk with no
	# outgoing row should extrapolate toward the momentum cell.
	m.record_movement("p", a, b, 6)
	# Move the player somewhere new with no learned row.
	var far: int = PropChunk.chunk_for_dir(Vector3(-0.5, 0.6, 0.3).normalized(), 6)
	var state = m._states["p"]
	state.current_key = far
	var preds: Array = m.predict_next("p")
	_assert(not preds.is_empty(), "cold-start row still returns a prediction")
	# Momentum extrapolates a's last direction from `far`; whatever the cell,
	# it must be a real canonical key.
	_assert(int(preds[0]["chunk_key"]) >= 0, "cold-start prediction is a valid canonical key")


func _test_predict_n_steps_row_normalized() -> void:
	var m = MarkovScript.new()
	var p: Array = _pair()
	var a: int = p[0]
	var b: int = p[1]
	# Two independent rows, each sum 10 but a GLOBAL total of 20. Row
	# normalization must yield probability 1.0 for b; a global-total divide
	# would yield 0.5 and leak mass.
	var other: int = PropChunk.chunk_for_dir(Vector3(-0.2, 0.8, 0.1).normalized(), 6)
	var other2: int = PropChunk.chunk_for_dir(Vector3(-0.2, 0.8, 0.2).normalized(), 6)
	# Build via record_movement to create state, then hand-seed counts.
	m.record_movement("p", a, b, 6)
	m.record_movement("p", other, other2, 6)
	var ps = m._states["p"]
	ps.transition_counts["%d->%d" % [a, b]] = 10
	ps.transition_counts["%d->%d" % [other, other2]] = 10
	ps.current_key = a
	var preds: Array = m.predict_n_steps("p", 1)
	_assert(not preds.is_empty(), "predict_n_steps returns predictions")
	_assert_eq(int(preds[0]["chunk_key"]), b, "predict_n_steps top step is the conditioned cell")
	_assert(absf(float(preds[0]["probability"]) - 1.0) < 0.001,
			"predict_n_steps row-normalizes (no global-total mass leak)")


func _test_sufficiency_current_and_clear() -> void:
	var m = MarkovScript.new()
	var p: Array = _pair()
	var a: int = p[0]
	var b: int = p[1]
	_assert(not m.has_sufficient_history("p"), "no history is insufficient")
	for _i in range(MarkovScript.MIN_HISTORY_SAMPLES):
		m.record_movement("p", a, b, 6)
	_assert(m.has_sufficient_history("p"), "enough transitions is sufficient")
	_assert_eq(m.get_current_chunk("p"), b, "current chunk tracks the last arrival")
	_assert(m.get_player_state("p").has("total_transitions"), "get_player_state exposes diagnostics")
	m.clear_all()
	_assert(m.get_player_state("p").is_empty(), "clear_all drops player state")


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s (got %s, want %s)" % [label, str(actual), str(expected)])
