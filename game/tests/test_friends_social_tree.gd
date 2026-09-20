## FriendsService social-tree mirror tests (arch §9 wiring).
extends SceneTree

const SocialTreeScript = preload("res://core/frame/kv/social_tree.gd")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	await process_frame
	_test_service_loads()
	_test_add_friend_mirrors_edge()
	_test_remove_friend_unmirrors()
	_test_block_mirrors_rival()
	_test_unblock_unmirrors()
	_test_verify_social_mirror()
	_test_social_accessors()
	print("FriendsSocial tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _get_service():
	return root.get_node_or_null("FriendsService")


func _test_service_loads() -> void:
	var svc = _get_service()
	_assert(svc != null, "FriendsService autoload exists")
	_assert(svc._social() != null, "FriendsService resolves social tree")


func _test_add_friend_mirrors_edge() -> void:
	var svc = _get_service()
	var res: Dictionary = svc.add_friend("social_t_a", "social_t_b", "B")
	_assert(res.get("success") == true, "add_friend succeeds")
	var tree = svc._social()
	var edge: Dictionary = tree.get_edge("social/social_t_a/friend/social_t_b")
	_assert(not edge.is_empty(), "friend edge mirrored into social tree")
	_assert(edge.get("rel") == "friend", "mirrored edge has rel friend")
	_assert(edge.get("other_id") == "social_t_b", "mirrored edge has other_id")


func _test_remove_friend_unmirrors() -> void:
	var svc = _get_service()
	svc.add_friend("social_t_c", "social_t_d", "D")
	var res: Dictionary = svc.remove_friend("social_t_c", "social_t_d")
	_assert(res.get("success") == true, "remove_friend succeeds")
	var tree = svc._social()
	_assert(tree.get_edge("social/social_t_c/friend/social_t_d").is_empty(), "friend edge removed from social tree")


func _test_block_mirrors_rival() -> void:
	var svc = _get_service()
	var res: Dictionary = svc.block_player("social_t_e", "social_t_f", "test")
	_assert(res.get("success") == true, "block_player succeeds")
	var tree = svc._social()
	var edge: Dictionary = tree.get_edge("social/social_t_e/rival/social_t_f")
	_assert(not edge.is_empty(), "block edge mirrored as rival in social tree")
	# Cleanup: unblock to keep lists clean for other runs
	svc.unblock_player("social_t_e", "social_t_f")


func _test_unblock_unmirrors() -> void:
	var svc = _get_service()
	svc.block_player("social_t_g", "social_t_h")
	svc.unblock_player("social_t_g", "social_t_h")
	var tree = svc._social()
	_assert(tree.get_edge("social/social_t_g/rival/social_t_h").is_empty(), "unblock removes rival edge from social tree")


func _test_verify_social_mirror() -> void:
	var svc = _get_service()
	svc.add_friend("social_t_i", "social_t_j", "J")
	var report: Dictionary = svc.verify_social_mirror("social_t_i")
	_assert(report.get("in_sync") == true, "verify_social_mirror reports in_sync after add")
	_assert(report.get("memory_count") == report.get("tree_count"), "memory and tree counts match")
	svc.remove_friend("social_t_i", "social_t_j")
	var after: Dictionary = svc.verify_social_mirror("social_t_i")
	_assert(after.get("in_sync") == true, "mirror stays in sync after removal")
	_assert(after.get("tree_count") == 0, "tree count back to zero after removal")


func _test_social_accessors() -> void:
	var svc = _get_service()
	svc.add_friend("social_t_k", "social_t_l", "L")
	svc.add_friend("social_t_k", "social_t_m", "M")
	var ids: Array = svc.get_social_friend_ids("social_t_k")
	_assert(ids.size() == 2, "get_social_friend_ids returns both friends")
	_assert("social_t_l" in ids and "social_t_m" in ids, "ids contain both friend ids")
	_assert(svc.get_social_edge_count("social_t_k", "friend") == 2, "get_social_edge_count counts friend edges")
	_assert(svc.get_social_edge_count("social_t_k", "guild") == 0, "get_social_edge_count returns 0 for absent kind")
	# Cleanup
	svc.remove_friend("social_t_k", "social_t_l")
	svc.remove_friend("social_t_k", "social_t_m")


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % msg)
