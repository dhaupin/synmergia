## TestFrameMemory
##
## Tests for FrameService memory leak prevention (Leak Threat 1).
## Verifies frame tree references are properly cleared on exit_frame().

extends SceneTree

# --script mode cannot resolve autoload identifiers at preload/parse time
# (GameLog inside frame_service.gd), so load FrameService at runtime instead.
var FrameServiceScript = null
const T3Script = preload("res://core/frame/kv/t3.gd")
const StateTreeScript = preload("res://core/frame/kv/state_tree.gd")

var FrameService
var ok: bool = true

func _init() -> void:
	pass

# NOTE: _init runs before _initialize in SceneTree scripts, so all test
# execution lives in _initialize (same pattern as test_login_flow.gd).
func _initialize() -> void:
	FrameService = root.get_node_or_null("FrameService")
	if FrameService == null:
		if FrameServiceScript == null:
			FrameServiceScript = load("res://core/services/frame_service.gd")
		FrameService = FrameServiceScript.new()
	_run_tests()
	quit(0 if ok else 1)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: %s" % msg)
		ok = false
	else:
		print("PASS: %s" % msg)

func _run_tests() -> void:
	_test_seed_tree_cleared_on_exit()
	_test_state_tree_cleared_on_exit()
	_test_nested_frames_cleared_in_order()
	_test_multiple_enter_exit_cycles()
	_test_t3_clear_empties_internal_dicts()
	_test_state_tree_clear_delegates_to_t3()
	_test_t3_full_scope_snapshot()
	_test_state_tree_apply_full_snapshot()

func _test_seed_tree_cleared_on_exit() -> void:
	var player_id = "mem_test_1"
	var frame_id = "dream_memory"
	
	FrameService.enter_frame(player_id, frame_id)
	var seed_tree = FrameService.get_seed_tree(player_id)
	_assert(seed_tree != null, "seed_tree exists after enter")
	
	# Add some data to the seed tree
	seed_tree.insert("/test/path", {"value": "test_data"}, Resource.new())
	var root_before = seed_tree.hash_subtree("/")
	_assert(not root_before == _empty_t3_hash(), "seed_tree has data before exit")
	
	FrameService.exit_frame(player_id)
	
	var seed_tree_after = FrameService.get_seed_tree(player_id)
	_assert(seed_tree_after == null, "seed_tree is null after exit_frame")
	
	# The original seed_tree reference should now be cleared internally
	# We can't directly test the old reference, but we verify the service returns null

func _test_state_tree_cleared_on_exit() -> void:
	var player_id = "mem_test_2"
	var frame_id = "tutorial_memory"
	
	FrameService.enter_frame(player_id, frame_id)
	var state_tree = FrameService.get_state_tree(player_id)
	_assert(state_tree != null, "state_tree exists after enter")
	
	# Add some data to the state tree
	state_tree.insert_state("/progress", player_id, "completion", {"step": 5})
	var root_before = state_tree.root_hash()
	_assert(not root_before == _empty_t3_hash(), "state_tree has data before exit")
	
	FrameService.exit_frame(player_id)
	
	var state_tree_after = FrameService.get_state_tree(player_id)
	_assert(state_tree_after == null, "state_tree is null after exit_frame")

func _test_nested_frames_cleared_in_order() -> void:
	var player_id = "mem_test_3"
	
	# Per prd-frame-authority.md US-001, a second enter_frame while a frame is
	# active is rejected (frames do not nest). Verify the rejected enter leaves
	# the outer frame's trees untouched, then that the outer exit clears them.
	FrameService.enter_frame(player_id, "outer_frame")
	var outer_seed = FrameService.get_seed_tree(player_id)
	var outer_state = FrameService.get_state_tree(player_id)
	outer_seed.insert("/outer", {"data": 1}, Resource.new())
	outer_state.insert_state("/outer", player_id, "test", {"v": 1})
	
	var inner_result = FrameService.enter_frame(player_id, "inner_frame")
	_assert(inner_result == false, "second enter_frame rejected while in frame")
	_assert(FrameService.get_current_frame_id(player_id) == "outer_frame", "still in outer frame after rejected enter")
	
	var seed_after_reject = FrameService.get_seed_tree(player_id)
	var state_after_reject = FrameService.get_state_tree(player_id)
	_assert(seed_after_reject == outer_seed, "outer seed_tree untouched by rejected enter")
	_assert(state_after_reject == outer_state, "outer state_tree untouched by rejected enter")
	
	# Exit the outer frame - trees should be cleared
	FrameService.exit_frame(player_id)
	_assert(FrameService.get_seed_tree(player_id) == null, "seed_tree null after outer exit")
	_assert(FrameService.get_state_tree(player_id) == null, "state_tree null after outer exit")

func _test_multiple_enter_exit_cycles() -> void:
	var player_id = "mem_test_4"
	
	for i in range(10):
		var frame_id = "cycle_frame_%d" % i
		FrameService.enter_frame(player_id, frame_id)
		var seed_tree = FrameService.get_seed_tree(player_id)
		var state_tree = FrameService.get_state_tree(player_id)
		
		seed_tree.insert("/cycle/%d" % i, {"iteration": i}, Resource.new())
		state_tree.insert_state("/cycle/%d" % i, player_id, "iteration", {"count": i})
		
		FrameService.exit_frame(player_id)
		
		_assert(FrameService.get_seed_tree(player_id) == null, "seed_tree null after cycle %d" % i)
		_assert(FrameService.get_state_tree(player_id) == null, "state_tree null after cycle %d" % i)
		_assert(not FrameService.in_frame(player_id), "not in frame after cycle %d" % i)

func _test_t3_clear_empties_internal_dicts() -> void:
	var t3 = T3Script.new()
	
	# Add data
	t3.insert("/a", {"v": 1}, Resource.new())
	t3.insert("/b", {"v": 2}, Resource.new())
	t3.insert("/c", {"v": 3}, Resource.new())
	
	_assert(t3.hash_subtree("/") != _empty_t3_hash(), "T3 has data before clear")
	
	# Call clear
	t3.clear()
	
	# Verify internal state is reset
	var root_after = t3.hash_subtree("/")
	_assert(root_after == _empty_t3_hash(), "T3 root hash is empty after clear")
	
	# Verify we can use it again after clear
	t3.insert("/new", {"v": 4}, Resource.new())
	_assert(t3.hash_subtree("/") != _empty_t3_hash(), "T3 works after clear")

func _test_state_tree_clear_delegates_to_t3() -> void:
	var state_tree = StateTreeScript.new()
	
	# Add data
	state_tree.insert_state("/test", "entity_1", "type_a", {"value": 100})
	_assert(state_tree.root_hash() != _empty_t3_hash(), "StateTree has data before clear")
	
	# Call clear
	state_tree.clear()
	
	# Verify it's empty
	_assert(state_tree.root_hash() == _empty_t3_hash(), "StateTree root hash empty after clear")
	_assert(state_tree.get_state("/test").is_empty(), "StateTree get_state returns empty after clear")
	
	# Verify we can use it again
	state_tree.insert_state("/new", "entity_2", "type_b", {"value": 200})
	_assert(not state_tree.root_hash() == _empty_t3_hash(), "StateTree works after clear")

func _test_state_tree_apply_full_snapshot() -> void:
	var state_tree = StateTreeScript.new()
	
	# Add data
	state_tree.insert_state("/world/entity_1", "entity_1", "position", {"x": 100, "z": 200})
	state_tree.insert_state("/world/entity_2", "entity_2", "position", {"x": 300, "z": 400})
	state_tree.insert_state("/world/chunk_0_0", "chunk_0_0", "terrain", {"height": 50})
	
	var root_before = state_tree.root_hash()
	_assert(not root_before == _empty_t3_hash(), "StateTree has data before snapshot")
	
	# Get full snapshot of "/world" scope
	var snapshot = state_tree.get_full_scope_snapshot("/world")
	_assert(snapshot.size() == 3, "Snapshot has 3 entries")
	
	# Create new state tree and apply snapshot
	var new_state_tree = StateTreeScript.new()
	new_state_tree.apply_full_snapshot(snapshot, root_before)
	
	var root_after = new_state_tree.root_hash()
	_assert(root_after == root_before, "Applied snapshot root matches original root")
	
	# Verify data is accessible. Stored values are {type, entity_id, payload}
	# per insert_state's contract.
	var entity1 = new_state_tree.get_state("/world/entity_1")
	_assert(entity1.get("type", "") == "position", "Entity 1 data preserved")
	_assert(entity1.get("payload", {}).get("x", 0) == 100, "Entity 1 x position correct")
	
	var entity2 = new_state_tree.get_state("/world/entity_2")
	_assert(entity2.get("type", "") == "position", "Entity 2 data preserved")
	_assert(entity2.get("payload", {}).get("x", 0) == 300, "Entity 2 x position correct")
	
	var chunk = new_state_tree.get_state("/world/chunk_0_0")
	_assert(chunk.get("type", "") == "terrain", "Chunk data preserved")
	_assert(chunk.get("payload", {}).get("height", 0) == 50, "Chunk height correct")


func _test_t3_full_scope_snapshot() -> void:
	var t3 = T3Script.new()
	
	# Add data under different scopes
	t3.insert("/world/entity_1", {"type": "position", "entity_id": "entity_1", "payload": {"x": 100}}, Resource.new())
	t3.insert("/world/entity_2", {"type": "position", "entity_id": "entity_2", "payload": {"x": 200}}, Resource.new())
	t3.insert("/world/chunk_0_0/terrain", {"type": "terrain", "entity_id": "chunk_0_0", "payload": {"height": 50}}, Resource.new())
	t3.insert("/other_scope/data", {"type": "test", "entity_id": "test", "payload": {"value": 999}}, Resource.new())
	
	var root_before = t3.hash_subtree("/")
	
	# Get full snapshot of "/world" scope
	var snapshot = t3.get_full_scope_snapshot("/world")
	_assert(snapshot.size() == 3, "Snapshot has 3 entries under /world")
	
	# Verify snapshot entries have correct structure
	for entry in snapshot:
		_assert(entry.size() == 4, "Snapshot entry has 4 elements: [path, old_hash, new_hash, value_bytes]")
		_assert(entry[1].size() == 0, "Old hash is empty (full state marker)")
		_assert(entry[2].size() == 32, "New hash is 32 bytes")
		_assert(entry[3] != null, "Value bytes present")
	
	# Get full snapshot of root (should include everything)
	var full_snapshot = t3.get_full_scope_snapshot("/")
	_assert(full_snapshot.size() == 4, "Full root snapshot has 4 entries")
	
	# Create new T3 and apply snapshot manually
	var new_t3 = T3Script.new()
	for entry in snapshot:
		var node_path: String = str(entry[0])
		var new_hash: PackedByteArray = entry[2]
		var value_bytes: PackedByteArray = entry[3]
		var value: Variant = bytes_to_var(value_bytes)
		var schema: Resource = Resource.new()
		new_t3.insert(node_path, value, schema)
	
	var root_after = new_t3.hash_subtree("/")
	# Note: root hash won't match exactly because /other_scope/data is missing
	# but the /world subtree should match
	var world_hash_before = t3.hash_subtree("/world")
	var world_hash_after = new_t3.hash_subtree("/world")
	_assert(world_hash_before == world_hash_after, "World subtree hash matches after manual apply")


func _empty_t3_hash() -> PackedByteArray:
	var t3 = T3Script.new()
	return t3.hash_subtree("/")