## SocialTree tests. Spec: labs/world-building-arch.md §9
extends SceneTree

const T3Script = preload("res://core/frame/kv/t3.gd")
const SocialTreeScript = preload("res://core/frame/kv/social_tree.gd")
const SocialSchemaScript = preload("res://core/frame/kv/social_schema.gd")

var _passed := 0
var _failed := 0


func _init() -> void:
	_test_init()
	_test_insert_get()
	_test_delete()
	_test_list()
	_test_list_by_rel()
	_test_list_related_ids()
	_test_player_root_hash()
	_test_diff_same()
	_test_diff_different()
	_test_apply_diff_roundtrip()
	_test_determinism()
	print("SocialTree tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_init() -> void:
	var tree := SocialTreeScript.new()
	_assert(tree != null, "init creates SocialTree")
	var schema := SocialSchemaScript.new()
	_assert(schema != null, "SocialSchema creates instance")
	var hash := tree.player_root_hash("/social/player_1")
	_assert(hash.size() == 32, "empty subtree has 32-byte root hash")


func _test_insert_get() -> void:
	var tree := SocialTreeScript.new()
	var hash := tree.insert_edge("/social/alice/friends/bob", "friend", "bob", {"since": 1234})
	_assert(hash.size() == 32, "insert_edge returns 32-byte hash")
	var edge := tree.get_edge("/social/alice/friends/bob")
	_assert(edge.get("rel") == "friend", "retrieved edge has rel")
	_assert(edge.get("other_id") == "bob", "retrieved edge has other_id")
	_assert(edge.get("meta").get("since") == 1234, "retrieved edge has meta")


func _test_delete() -> void:
	var tree := SocialTreeScript.new()
	tree.insert_edge("/social/alice/rivals/zed", "rival", "zed")
	_assert(tree.delete_edge("/social/alice/rivals/zed"), "delete returns true for existing")
	_assert(not tree.delete_edge("/social/alice/rivals/zed"), "delete returns false for missing")
	_assert(tree.get_edge("/social/alice/rivals/zed").is_empty(), "deleted edge gone")


func _test_list() -> void:
	var tree := SocialTreeScript.new()
	tree.insert_edge("/social/carol/friends/dan", "friend", "dan")
	tree.insert_edge("/social/carol/guild/g1", "guild", "g1")
	tree.insert_edge("/social/carol/party/p1", "party", "p1")
	var all := tree.list_edges("/social/carol")
	_assert(all.size() == 3, "list_edges returns all 3")


func _test_list_by_rel() -> void:
	var tree := SocialTreeScript.new()
	tree.insert_edge("/social/erin/friends/f1", "friend", "f1")
	tree.insert_edge("/social/erin/friends/f2", "friend", "f2")
	tree.insert_edge("/social/erin/party/p1", "party", "p1")
	var friends := tree.list_by_rel("/social/erin", "friend")
	_assert(friends.size() == 2, "list_by_rel returns only friends")
	var parties := tree.list_by_rel("/social/erin", "party")
	_assert(parties.size() == 1, "list_by_rel returns only party")


func _test_list_related_ids() -> void:
	var tree := SocialTreeScript.new()
	tree.insert_edge("/social/frank/friends/a", "friend", "alice")
	tree.insert_edge("/social/frank/friends/b", "friend", "bob")
	tree.insert_edge("/social/frank/party/p1", "party", "carol")
	var ids := tree.list_related_ids("/social/frank", "friend")
	_assert(ids.size() == 2, "list_related_ids returns 2 friend ids")
	_assert("alice" in ids and "bob" in ids, "ids contain alice and bob")
	_assert("carol" not in ids, "party member not in friend ids")


func _test_player_root_hash() -> void:
	var tree := SocialTreeScript.new()
	tree.insert_edge("/social/gina/friends/h", "friend", "h")
	var h1 := tree.player_root_hash("/social/gina")
	_assert(h1.size() == 32, "player subtree hash is 32 bytes")
	tree.insert_edge("/social/gina/friends/i", "friend", "i")
	var h2 := tree.player_root_hash("/social/gina")
	_assert(h1 != h2, "adding edge changes subtree hash")


func _test_diff_same() -> void:
	var tree := SocialTreeScript.new()
	var r_empty := tree.root_hash()
	tree.insert_edge("/social/hank/friends/j", "friend", "j")
	var diffs := tree.diff_social(r_empty, tree.root_hash())
	_assert(diffs.size() == 1, "diff of empty->one edge reports one changed path")


func _test_diff_different() -> void:
	var tree := SocialTreeScript.new()
	var r1 := tree.root_hash()
	tree.insert_edge("/social/ivy/friends/j", "friend", "j")
	var r2 := tree.root_hash()
	var diffs := tree.diff_social(r1, r2)
	_assert(diffs.size() == 1, "diff between two snapshots reports one changed path")
	_assert(str(diffs[0][0]) == "social/ivy/friends/j", "diff path is the inserted edge (normalized, no leading slash)")


func _test_apply_diff_roundtrip() -> void:
	var tree := SocialTreeScript.new()
	var r1 := tree.root_hash()
	tree.insert_edge("/social/jack/friends/k", "friend", "k")
	tree.insert_edge("/social/jack/guild/g1", "guild", "g1")
	var r2 := tree.root_hash()
	var diffs := tree.diff_social(r1, r2)
	var other := SocialTreeScript.new()
	var applied := other.apply_diff(r1, diffs)
	_assert(applied == r2, "apply_diff roundtrips to source root")
	var edge := other.get_edge("/social/jack/friends/k")
	_assert(edge.get("other_id") == "k", "applied edge restored")
	var guild := other.get_edge("/social/jack/guild/g1")
	_assert(guild.get("rel") == "guild", "applied guild edge restored")


func _test_determinism() -> void:
	var t1 := SocialTreeScript.new()
	t1.insert_edge("/social/kate/friends/l", "friend", "l", {"a": 1, "b": [1, 2]})
	var t2 := SocialTreeScript.new()
	t2.insert_edge("/social/kate/friends/l", "friend", "l", {"a": 1, "b": [1, 2]})
	_assert(t1.root_hash() == t2.root_hash(), "same inserts in same order produce same root hash")


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % msg)
