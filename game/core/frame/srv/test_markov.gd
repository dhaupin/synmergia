## Tests for MarkovPredictor -- the frame's per-player movement model
## (co-located per labs conventions).
##
## Covers: the signed 16-bit chunk-key round-trip (the audit round 16
## _sign16 fix), transition learning, predict_next ordering and
## probabilities, the row-normalized predict_n_steps (audit round 17
## mass-leak fix), multi-horizon prediction, simulation accuracy, and
## the state helpers.
extends SceneTree

const MarkovScript = preload("res://core/frame/srv/markov.gd")

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	_test_signed_offset_round_trip()
	_test_predict_next_learns_transition()
	_test_predict_next_probabilities_and_order()
	_test_predict_next_empty()
	_test_predict_n_steps_row_normalized()
	_test_predict_multi_horizon()
	_test_simulation_accuracy()
	_test_compute_accuracy_empty()
	_test_sufficiency_current_and_clear()
	print("Markov tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_signed_offset_round_trip() -> void:
	var m = MarkovScript.new()
	# The 16-bit field is unsigned on the wire; the signed decoder must
	# recover negative local-grid offsets.
	_assert_eq(MarkovScript._sign16(0xFFFF), -1, "_sign16(0xFFFF) == -1")
	_assert_eq(MarkovScript._sign16(1), 1, "_sign16(1) == 1")
	_assert_eq(MarkovScript._sign16(0x8000), -32768, "_sign16(0x8000) == -32768")
	var offsets := [
		Vector2(0, 0), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1),
		Vector2(0, -1), Vector2(-1, -1), Vector2(3, -4), Vector2(-7, 9),
	]
	for off in offsets:
		var key: String = m._offset_to_chunk_key(off)
		var back: Vector2 = m._chunk_key_to_offset(key)
		_assert_eq(back, off, "chunk-key round-trip %s" % str(off))
	var neg_key: String = m._offset_to_chunk_key(Vector2(-1, 0))
	_assert(neg_key.begins_with("ffff-"), "negative x encodes as two's complement ffff")
	_assert(m._chunk_key_to_offset(neg_key) == Vector2(-1, 0),
		"negative key decodes back to (-1, 0), not (65535, 0)")


func _test_predict_next_learns_transition() -> void:
	var m = MarkovScript.new()
	var center: String = m._offset_to_chunk_key(Vector2.ZERO)
	var east: String = m._offset_to_chunk_key(Vector2(1, 0))
	for i in range(MarkovScript.HISTORY_WINDOW + 5):
		m.record_movement("p", center, east)
	var state = m._states["p"]
	state.current_chunk_key = center
	state.last_move_delta = Vector2.ZERO
	state.velocity_transition_counts.clear()
	state.prediction_cache.clear()
	var preds: Array = m.predict_next("p")
	_assert(not preds.is_empty(), "predict_next returns predictions after learning")
	_assert_eq(preds[0]["chunk_key"], east, "learned transition is the top prediction")
	_assert(absf(preds[0]["probability"] - 1.0) < 0.001, "single-outcome row predicts probability 1.0")


func _test_predict_next_probabilities_and_order() -> void:
	var m = MarkovScript.new()
	var center: String = m._offset_to_chunk_key(Vector2.ZERO)
	var east: String = m._offset_to_chunk_key(Vector2(1, 0))
	var west: String = m._offset_to_chunk_key(Vector2(-1, 0))
	var state = m._get_or_create_state("p")
	state.current_chunk_key = center
	state.last_move_delta = Vector2.ZERO
	state.transition_counts[m._transition_key(center, east)] = 7
	state.transition_counts[m._transition_key(center, west)] = 3
	state.prediction_cache.clear()
	var preds: Array = m.predict_next("p")
	_assert_eq(preds[0]["chunk_key"], east, "most-likely transition is first")
	_assert(absf(preds[0]["probability"] - 0.7) < 0.001, "east probability is 0.7")
	_assert(absf(preds[1]["probability"] - 0.3) < 0.001, "west probability is 0.3")
	_assert(preds[0]["probability"] >= preds[1]["probability"], "predictions are sorted descending")


func _test_predict_next_empty() -> void:
	var m = MarkovScript.new()
	_assert(m.predict_next("unknown").is_empty(), "unknown player has no predictions")
	var state = m._get_or_create_state("p")
	state.current_chunk_key = ""
	_assert(m.predict_next("p").is_empty(), "player with no current chunk has no predictions")


func _test_predict_n_steps_row_normalized() -> void:
	var m = MarkovScript.new()
	var center: String = m._offset_to_chunk_key(Vector2.ZERO)
	var east: String = m._offset_to_chunk_key(Vector2(1, 0))
	var other: String = m._offset_to_chunk_key(Vector2(50, 50))
	var other2: String = m._offset_to_chunk_key(Vector2(51, 50))
	var state = m._get_or_create_state("p")
	# Two independent rows, each with a row sum of 10 but a GLOBAL total of
	# 20. Row normalization must yield probability 1.0 for east; the old
	# global-total code yielded 0.5 and leaked mass.
	state.transition_counts[m._transition_key(center, east)] = 10
	state.transition_counts[m._transition_key(other, other2)] = 10
	state.total_transitions = 20
	state.current_chunk_key = center
	var preds: Array = m.predict_n_steps("p", 1)
	_assert(not preds.is_empty(), "predict_n_steps returns predictions")
	_assert_eq(preds[0]["chunk_key"], east, "predict_n_steps top step is the conditioned neighbour")
	_assert(absf(preds[0]["probability"] - 1.0) < 0.001,
		"predict_n_steps row-normalizes (global-total mass leak fixed)")


func _test_predict_multi_horizon() -> void:
	var m = MarkovScript.new()
	var center: String = m._offset_to_chunk_key(Vector2.ZERO)
	var east: String = m._offset_to_chunk_key(Vector2(1, 0))
	var state = m._get_or_create_state("p")
	state.transition_counts[m._transition_key(center, east)] = 10
	state.current_chunk_key = center
	var horizons: Dictionary = m.predict_multi_horizon("p")
	_assert(horizons.has("near") and horizons.has("mid") and horizons.has("far"),
		"predict_multi_horizon returns near/mid/far")
	_assert(not horizons["near"].is_empty(), "near horizon has predictions")
	var empty_horizons: Dictionary = m.predict_multi_horizon("unknown")
	_assert(empty_horizons["near"].is_empty() and empty_horizons["mid"].is_empty()
		and empty_horizons["far"].is_empty(), "unknown player yields empty horizons")


func _test_simulation_accuracy() -> void:
	var m = MarkovScript.new()
	var pattern := func(_tick: int, pos: Vector2) -> Vector2:
		return pos + Vector2(1, 0)
	var accuracy: float = m.simulate_and_evaluate("sim", pattern, 300)
	_assert(accuracy > MarkovScript.ACCURACY_THRESHOLD,
		"constant-direction simulation accuracy > %.2f (got %.3f)" % [MarkovScript.ACCURACY_THRESHOLD, accuracy])


func _test_compute_accuracy_empty() -> void:
	var m = MarkovScript.new()
	_assert_eq(m.compute_accuracy("nobody", []), 0.0, "empty movement list scores 0.0")


func _test_sufficiency_current_and_clear() -> void:
	var m = MarkovScript.new()
	var a: String = m._offset_to_chunk_key(Vector2.ZERO)
	var b: String = m._offset_to_chunk_key(Vector2(1, 0))
	_assert(not m.has_sufficient_history("p"), "no history is insufficient")
	for i in range(MarkovScript.MIN_HISTORY_SAMPLES):
		m.record_movement("p", a, b)
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
