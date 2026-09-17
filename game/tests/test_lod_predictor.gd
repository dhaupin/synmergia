## test_lod_predictor - Integration test for LOD Manager + Markov Predictor
##
## Tests:
## 1. Markov predictor accuracy >70% over 1000 ticks with predictable movement
## 2. LOD Manager HOT/WARM/COLD classification
## 3. Promotion/demotion triggers
## 4. Predictive prefetch integration
##
## Run with:
##   godot --headless --path game --script res://tests/test_lod_predictor.gd
extends SceneTree

var _markov: Object = null
var _lod_manager: Node = null
var _passed := 0
var _failed := 0


func _init() -> void:
	print("=== LOD PREDICTOR INTEGRATION TEST ===")
	_init_services()
	await process_frame

	_test_markov_accuracy()
	_test_markov_basic_prediction()
	_test_lod_classification()
	_test_lod_promotion_demotion()
	_test_predictive_prefetch_integration()
	_test_chunk_tracking_per_player()

	_print_summary()
	quit(0 if _failed == 0 else 1)


func _init_services() -> void:
	# Load and instantiate Markov predictor
	var MarkovScript = preload("res://core/frame/srv/markov.gd")
	_markov = MarkovScript.new()
	if _markov == null:
		_fail("Failed to instantiate Markov predictor")
	else:
		_ok("Markov predictor instantiated")

	# Load and instantiate LOD Manager
	var LODManagerScript = preload("res://core/services/lod_manager.gd")
	_lod_manager = LODManagerScript.new()
	if _lod_manager == null:
		_fail("Failed to instantiate LOD Manager")
	else:
		_ok("LOD Manager instantiated")
	root.add_child(_lod_manager)
	_lod_manager.call("_ready")
	await process_frame


## Test 1: Markov predictor accuracy >70% over 1000 ticks
func _test_markov_accuracy() -> void:
	print("\n--- Test 1: Markov Accuracy (>70% over 1000 ticks) ---")

	# Test pattern 1: Straight line movement (highly predictable)
	var accuracy1 := _simulate_pattern_accuracy("test_player_1", _straight_line_pattern, 1000)
	_ok("Straight line pattern accuracy: %.2f%%" % (accuracy1 * 100.0))
	if accuracy1 >= 0.70:
		_ok("PASS: Straight line accuracy >= 70%")
	else:
		_fail("FAIL: Straight line accuracy %.2f%% < 70%" % (accuracy1 * 100.0))

	# Test pattern 2: Square patrol (repeating pattern)
	var accuracy2 := _simulate_pattern_accuracy("test_player_2", _square_patrol_pattern, 1000)
	_ok("Square patrol pattern accuracy: %.2f%%" % (accuracy2 * 100.0))
	if accuracy2 >= 0.70:
		_ok("PASS: Square patrol accuracy >= 70%")
	else:
		_fail("FAIL: Square patrol accuracy %.2f%% < 70%" % (accuracy2 * 100.0))

	# Test pattern 3: Back-and-forth oscillation
	var accuracy3 := _simulate_pattern_accuracy("test_player_3", _oscillation_pattern, 1000)
	_ok("Oscillation pattern accuracy: %.2f%%" % (accuracy3 * 100.0))
	if accuracy3 >= 0.70:
		_ok("PASS: Oscillation accuracy >= 70%")
	else:
		_fail("FAIL: Oscillation accuracy %.2f%% < 70%" % (accuracy3 * 100.0))

	# Overall: at least one pattern should exceed 70% for the test to pass
	var max_accuracy := max(accuracy1, max(accuracy2, accuracy3))
	if max_accuracy >= 0.70:
		_ok("OVERALL PASS: Max pattern accuracy %.2f%% >= 70%" % (max_accuracy * 100.0))
	else:
		_fail("OVERALL FAIL: All patterns below 70%")


## Test 2: Basic Markov prediction functionality
func _test_markov_basic_prediction() -> void:
	print("\n--- Test 2: Markov Basic Prediction ---")

	_markov.clear_all()
	var player_id := "basic_test_player"

	# Record some movements
	_markov.record_movement(player_id, _ck(0,0), _ck(1,0))
	_markov.record_movement(player_id, _ck(1,0), _ck(2,0))
	_markov.record_movement(player_id, _ck(2,0), _ck(3,0))
	_markov.record_movement(player_id, _ck(3,0), _ck(4,0))

	# Predict from current position
	var predictions := _markov.predict_next(player_id)
	if predictions.size() > 0:
		_ok("Predictions returned: %d" % predictions.size())
		_ok("Top prediction: %s (prob=%.2f)" % [predictions[0]["chunk_key"], predictions[0]["probability"]])
	else:
		_fail("No predictions returned")

	# Check that we get 3 top predictions
	if predictions.size() >= 3:
		_ok("Returns top 3 predictions")
	else:
		_fail("Expected at least 3 predictions, got %d" % predictions.size())

	# Check multi-horizon prediction
	var multi := _markov.predict_multi_horizon(player_id)
	if multi.has("near") and multi.has("mid") and multi.has("far"):
		_ok("Multi-horizon prediction has near/mid/far")
		_ok("Near preds: %d, Mid preds: %d, Far preds: %d" % [
			multi["near"].size(), multi["mid"].size(), multi["far"].size()])
	else:
		_fail("Multi-horizon prediction missing horizons")

	# Check accuracy threshold constant
	var threshold := _markov.get_accuracy_threshold()
	if abs(threshold - 0.70) < 0.001:
		_ok("Accuracy threshold is 70%")
	else:
		_fail("Accuracy threshold incorrect: %.2f" % threshold)


## Test 3: LOD Manager HOT/WARM/COLD classification
func _test_lod_classification() -> void:
	print("\n--- Test 3: LOD Classification ---")

	_lod_manager.clear_all()
	await process_frame

	# Manually set up player data via internal API
	var player_id := "lod_test_player"
	_lod_manager._update_all_players()

	# Simulate player at position (500, 0, 500) -> chunk (5, 5)
	# We need to inject mock player data since EntityService isn't available
	# For this test, we directly test the chunk classification logic

	# Add a player manually
	var player_data := _lod_manager._get_or_create_player_data(player_id)
	player_data.current_chunk_key = _ck(5,5)
	player_data.aoi_center = Vector3(500, 0, 500)
	player_data.aoi_radius = 500.0
	player_data.tracked_chunks = {
		_ck(5,5): 1,   # HOT (current chunk)
		_ck(4,5): 1,   # HOT (within AOI)
		_ck(6,5): 1,   # HOT (within AOI)
		_ck(5,4): 1,   # HOT (within AOI)
		_ck(5,6): 1,   # HOT (within AOI)
		_ck(6,6): 2,   # WARM (predicted)
	}
	player_data.predicted_chunks = [_ck(6,6), _ck(6,7), _ck(7,6)]
	player_data.last_aoi_update_tick = 1

	# Run classification
	_lod_manager._tick_number = 1
	_lod_manager._classify_chunks()
	_lod_manager._apply_lod_changes()

	# Check HOT chunks
	var hot_chunks := _lod_manager.get_chunks_by_state(1)  # HOT = 1
	if _ck(5,5) in hot_chunks and _ck(4,5) in hot_chunks:
		_ok("Current and adjacent chunks classified as HOT")
	else:
		_fail("Expected chunks 5,5 and 4,5 to be HOT, got: %s" % hot_chunks)

	# Check WARM chunks
	var warm_chunks := _lod_manager.get_chunks_by_state(2)  # WARM = 2
	if _ck(6,6) in warm_chunks:
		_ok("Predicted chunk classified as WARM")
	else:
		_fail("Expected chunk 6,6 to be WARM, got: %s" % warm_chunks)

	# Test COLD classification (chunks not tracked)
	var cold_chunks := _lod_manager.get_chunks_by_state(0)  # COLD = 0
	_ok("Total chunks tracked: %d" % _lod_manager._chunk_states.size())


## Test 4: LOD Promotion/Demotion triggers
func _test_lod_promotion_demotion() -> void:
	print("\n--- Test 4: Promotion/Demotion Triggers ---")

	_lod_manager.clear_all()
	await process_frame

	var player_id := "promo_test_player"
	var player_data := _lod_manager._get_or_create_player_data(player_id)
	player_data.current_chunk_key = _ck(10,10)
	player_data.aoi_center = Vector3(1000, 0, 1000)
	player_data.aoi_radius = 500.0
	player_data.tracked_chunks = {
		_ck(10,10): 1,  # HOT
		_ck(9,10): 1,   # HOT
		_ck(11,10): 2,  # WARM (predicted)
	}
	player_data.predicted_chunks = [_ck(11,10), _ck(12,10)]
	player_data.last_aoi_update_tick = 1

	_lod_manager._tick_number = 1
	_lod_manager._classify_chunks()
	_lod_manager._apply_lod_changes()

	# Check initial state
	var chunk_10_10 := _lod_manager.get_chunk_lod(_ck(10,10))
	if chunk_10_10 == 1:  # HOT
		_ok("Chunk 10,10 is HOT initially")
	else:
		_fail("Expected 10,10 to be HOT, got %d" % chunk_10_10)

	var chunk_11_10 := _lod_manager.get_chunk_lod(_ck(11,10))
	if chunk_11_10 == 2:  # WARM
		_ok("Chunk 11,10 is WARM initially")
	else:
		_fail("Expected 11,10 to be WARM, got %d" % chunk_11_10)

	# Simulate time passing - player moves away, no longer in AOI or predicted
	_lod_manager._tick_number = 350  # Past HOT_DEMOTION_TICKS (300)
	player_data.tracked_chunks = {}  # Player gone
	player_data.predicted_chunks = []

	_lod_manager._classify_chunks()
	_lod_manager._apply_lod_changes()

	# After 300+ ticks idle, HOT should demote to WARM
	chunk_10_10 = _lod_manager.get_chunk_lod(_ck(10,10))
	if chunk_10_10 == 2:  # WARM
		_ok("HOT chunk demoted to WARM after idle timeout")
	else:
		_fail("Expected HOT->WARM demotion, got %d" % chunk_10_10)

	# Advance further for WARM->COLD
	_lod_manager._tick_number = 450  # Past WARM_DEMOTION_TICKS (50) from last warm
	_lod_manager._classify_chunks()
	_lod_manager._apply_lod_changes()

	chunk_11_10 = _lod_manager.get_chunk_lod(_ck(11,10))
	if chunk_11_10 == 0:  # COLD
		_ok("WARM chunk demoted to COLD after idle timeout")
	else:
		_fail("Expected WARM->COLD demotion, got %d" % chunk_11_10)


## Test 5: Predictive prefetch integration
func _test_predictive_prefetch_integration() -> void:
	print("\n--- Test 5: Predictive Prefetch Integration ---")

	_lod_manager.clear_all()
	_markov.clear_all()
	await process_frame

	var player_id := "prefetch_test"
	var player_data := _lod_manager._get_or_create_player_data(player_id)
	player_data.current_chunk_key = _ck(20,20)
	player_data.aoi_center = Vector3(2000, 0, 2000)
	player_data.aoi_radius = 500.0

	# Record movement history in Markov
	_markov.record_movement(player_id, _ck(18,20), _ck(19,20))
	_markov.record_movement(player_id, _ck(19,20), _ck(20,20))
	_markov.record_movement(player_id, _ck(20,20), _ck(21,20))
	_markov.record_movement(player_id, _ck(21,20), _ck(22,20))
	_markov.record_movement(player_id, _ck(22,20), _ck(23,20))

	# Run LOD tick with predictions
	_lod_manager._tick_number = 1
	_lod_manager._update_predictions()
	_lod_manager._classify_chunks()
	_lod_manager._apply_lod_changes()

	# Check that predicted chunks are WARM
	var predicted := [_ck(24,20), _ck(25,20), _ck(23,21)]  # Likely next positions
	var warm_found := 0
	for key in predicted:
		if _lod_manager.get_chunk_lod(key) == 2:  # WARM
			warm_found += 1

	if warm_found > 0:
		_ok("Predictive prefetch promoted %d chunks to WARM" % warm_found)
	else:
		_fail("No predicted chunks promoted to WARM")

	# Test manual promotion
	_lod_manager.promote_chunk(_ck(30,30), 1)  # Promote to HOT
	if _lod_manager.get_chunk_lod(_ck(30,30)) == 1:
		_ok("Manual promotion to HOT works")
	else:
		_fail("Manual promotion failed")

	_lod_manager.demote_chunk(_ck(30,30), 0)  # Demote to COLD
	if _lod_manager.get_chunk_lod(_ck(30,30)) == 0:
		_ok("Manual demotion to COLD works")
	else:
		_fail("Manual demotion failed")


## Test 6: Per-player chunk tracking
func _test_chunk_tracking_per_player() -> void:
	print("\n--- Test 6: Per-Player Chunk Tracking ---")

	_lod_manager.clear_all()
	await process_frame

	var player_id := "tracking_test"
	var player_data := _lod_manager._get_or_create_player_data(player_id)
	player_data.current_chunk_key = _ck(100,100)
	player_data.aoi_center = Vector3(10000, 0, 10000)
	player_data.aoi_radius = 500.0
	player_data.tracked_chunks = {
		_ck(100,100): 1,
		_ck(99,100): 1,
		_ck(101,100): 2,
	}
	player_data.predicted_chunks = [_ck(101,100), _ck(102,100)]
	player_data.last_aoi_update_tick = 1

	_lod_manager._tick_number = 1
	_lod_manager._classify_chunks()
	_lod_manager._apply_lod_changes()

	var tracked := _lod_manager.get_player_chunks(player_id)
	if tracked.has(_ck(100,100)) and tracked[_ck(100,100)] == 1:
		_ok("Player tracks current chunk as HOT")
	else:
		_fail("Current chunk tracking failed: %s" % tracked)

	if tracked.has(_ck(101,100)) and tracked[_ck(101,100)] == 2:
		_ok("Player tracks predicted chunk as WARM")
	else:
		_fail("Predicted chunk tracking failed: %s" % tracked)

	# Test get_chunk_lod returns correct state
	if _lod_manager.get_chunk_lod(_ck(100,100)) == 1:
		_ok("Global chunk state matches player tracking")
	else:
		_fail("Global state mismatch")


## ============================================================================
## MOVEMENT PATTERNS FOR ACCURACY TESTING
## ============================================================================

## Straight line: player moves +1 x every tick
func _straight_line_pattern(tick: int, current_offset: Vector2) -> Vector2:
	return Vector2(current_offset.x + 1, current_offset.y)


## Square patrol: moves in a 10x10 square
func _square_patrol_pattern(tick: int, current_offset: Vector2) -> Vector2:
	var cycle := tick % 40
	if cycle < 10:
		return Vector2(current_offset.x + 1, current_offset.y)
	elif cycle < 20:
		return Vector2(current_offset.x, current_offset.y + 1)
	elif cycle < 30:
		return Vector2(current_offset.x - 1, current_offset.y)
	else:
		return Vector2(current_offset.x, current_offset.y - 1)


## Oscillation: back and forth between two positions
func _oscillation_pattern(tick: int, current_offset: Vector2) -> Vector2:
	var cycle := tick % 20
	if cycle < 10:
		return Vector2(current_offset.x + 1, current_offset.y)
	else:
		return Vector2(current_offset.x - 1, current_offset.y)


## Simulate pattern and compute accuracy using Markov's built-in method
func _simulate_pattern_accuracy(player_id: String, pattern_func: Callable, ticks: int) -> float:
	_markov.clear_all()

	# Use the Markov predictor's built-in simulation
	var accuracy := _markov.simulate_and_evaluate(player_id, pattern_func, ticks)
	return accuracy


## ============================================================================
## HELPER FUNCTIONS
## ============================================================================

func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _print_summary() -> void:
	print("\n=== TEST SUMMARY ===")
	print("Passed: %d" % _passed)
	print("Failed: %d" % _failed)
	if _failed == 0:
		print("RESULT: ALL TESTS PASSED")
	else:
		print("RESULT: %d TESTS FAILED" % _failed)


func _ck(x: int, y: int, z: int = 0, d: int = 0, f: int = 0) -> String:
	return "%04x-%04x-%04x-d%d-f%d" % [x, y, z, d, f]