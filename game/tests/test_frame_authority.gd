## TestFrameAuthority
##
## Tests for FrameService frame seed authority (labs/prd-frame-authority.md)
## Covers US-001 through US-005 + edge cases

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
	_test_enter_frame()
	_test_get_frame_seed()
	_test_exit_frame()
	_test_double_enter_rejected()
	_test_exit_without_enter_rejected()
	_test_state_tree_empty_on_enter()
	_test_cross_frame_isolation()
	_test_frame_state_discarded()

func _test_enter_frame() -> void:
	var player_id = "test_player_1"
	var frame_id = "dream_tutorial"
	
	var result = FrameService.enter_frame(player_id, frame_id)
	_assert(result == true, "enter_frame returns true")
	_assert(FrameService.in_frame(player_id) == true, "in_frame true after enter")
	_assert(FrameService.get_current_frame_id(player_id) == frame_id, "current frame_id matches")
	
	var seed = FrameService.get_frame_seed(player_id)
	_assert(seed.size() == 32, "frame_seed is 32 bytes")
	
	var seed_tree = FrameService.get_seed_tree(player_id)
	_assert(seed_tree != null, "seed_tree not null")
	_assert(seed_tree is T3Script, "seed_tree is T3")
	
	var state_tree = FrameService.get_state_tree(player_id)
	_assert(state_tree != null, "state_tree not null")
	_assert(state_tree is StateTreeScript, "state_tree is StateTree")
	
	FrameService.exit_frame(player_id)

func _test_get_frame_seed() -> void:
	var player_id = "test_player_2"
	var frame_id = "jail_cell"
	
	var seed_before = FrameService.get_frame_seed(player_id)
	_assert(seed_before.size() == 0, "get_frame_seed empty before enter")
	
	FrameService.enter_frame(player_id, frame_id)
	var seed_after = FrameService.get_frame_seed(player_id)
	_assert(seed_after.size() == 32, "get_frame_seed 32 bytes after enter")
	
	FrameService.exit_frame(player_id)
	var seed_after_exit = FrameService.get_frame_seed(player_id)
	_assert(seed_after_exit.size() == 0, "get_frame_seed empty after exit")

func _test_exit_frame() -> void:
	var player_id = "test_player_3"
	var frame_id = "tutorial_island"
	
	FrameService.enter_frame(player_id, frame_id)
	_assert(FrameService.in_frame(player_id) == true, "in_frame before exit")
	
	var result = FrameService.exit_frame(player_id)
	_assert(result == true, "exit_frame returns true")
	_assert(FrameService.in_frame(player_id) == false, "in_frame false after exit")
	_assert(FrameService.get_current_frame_id(player_id) == "", "frame_id cleared after exit")
	_assert(FrameService.get_frame_seed(player_id).size() == 0, "seed cleared after exit")
	_assert(FrameService.get_seed_tree(player_id) == null, "seed_tree null after exit")
	_assert(FrameService.get_state_tree(player_id) == null, "state_tree null after exit")

func _test_double_enter_rejected() -> void:
	var player_id = "test_player_4"
	var frame_id = "dream_1"
	
	var result1 = FrameService.enter_frame(player_id, frame_id)
	_assert(result1 == true, "first enter succeeds")
	
	var result2 = FrameService.enter_frame(player_id, "dream_2")
	_assert(result2 == false, "second enter rejected")
	_assert(FrameService.get_current_frame_id(player_id) == "dream_1", "still in first frame")
	
	FrameService.exit_frame(player_id)

func _test_exit_without_enter_rejected() -> void:
	var player_id = "test_player_5"
	
	var result = FrameService.exit_frame(player_id)
	_assert(result == false, "exit without enter returns false")
	_assert(FrameService.in_frame(player_id) == false, "not in frame")

func _test_state_tree_empty_on_enter() -> void:
	var player_id = "test_player_6"
	var frame_id = "empty_test"
	
	FrameService.enter_frame(player_id, frame_id)
	var state_tree = FrameService.get_state_tree(player_id)
	
	var root_hash = state_tree.root_hash()
	var fresh_tree = StateTreeScript.new()
	_assert(root_hash == fresh_tree.root_hash(), "state tree root is empty hash")
	
	FrameService.exit_frame(player_id)

func _test_cross_frame_isolation() -> void:
	var player_id = "test_player_7"
	
	FrameService.enter_frame(player_id, "frame_A")
	var tree_a = FrameService.get_state_tree(player_id)
	tree_a.insert_state("/progress", player_id, "completion", {"step": 1})
	var hash_a = tree_a.root_hash()
	FrameService.exit_frame(player_id)
	
	FrameService.enter_frame(player_id, "frame_B")
	var tree_b = FrameService.get_state_tree(player_id)
	var hash_b = tree_b.root_hash()
	_assert(hash_b != hash_a, "frame_B state tree different from frame_A")
	_assert(tree_b.get_state("/progress").is_empty(), "frame_B state tree is empty")
	
	FrameService.exit_frame(player_id)

func _test_frame_state_discarded() -> void:
	var player_id = "test_player_8"
	
	FrameService.enter_frame(player_id, "frame_X")
	var frame_tree = FrameService.get_state_tree(player_id)
	frame_tree.insert_state("/temp", player_id, "data", {"value": 42})
	var frame_hash = frame_tree.root_hash()
	var fresh_tree_x = StateTreeScript.new()
	_assert(not frame_hash == fresh_tree_x.root_hash(), "frame tree has data")
	FrameService.exit_frame(player_id)
	
	FrameService.enter_frame(player_id, "frame_Y")
	var new_frame_tree = FrameService.get_state_tree(player_id)
	var new_hash = new_frame_tree.root_hash()
	var fresh_tree_y = StateTreeScript.new()
	_assert(new_hash == fresh_tree_y.root_hash(), "new frame tree is empty")
	
	var player_tree = FrameService.get_player_state_tree(player_id)
	player_tree.insert_state("/persistent", player_id, "xp", {"amount": 100})
	FrameService.exit_frame(player_id)
	
	FrameService.enter_frame(player_id, "frame_Z")
	var player_tree2 = FrameService.get_player_state_tree(player_id)
	var persisted = player_tree2.get_state("/persistent")
	_assert(not persisted.is_empty(), "persistent state survives frame exit")
	_assert(persisted.get("payload", {}).get("amount", 0) == 100, "persistent state value correct")
	
	FrameService.exit_frame(player_id)

func _empty_hash() -> PackedByteArray:
	var t3 = T3Script.new()
	return t3.hash_subtree("/")
