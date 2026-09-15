## DefinitionTree tests. Spec: labs/world-building-arch.md §9
extends SceneTree

const T3Script = preload("res://labs/multi-iso/kv/t3.gd")
const DefinitionTreeScript = preload("res://labs/multi-iso/kv/definition_tree.gd")
const DefinitionSchemaScript = preload("res://labs/multi-iso/kv/definition_schema.gd")

var _passed := 0
var _failed := 0


func _init() -> void:
	_test_init()
	_test_insert_get_zone()
	_test_insert_get_npc()
	_test_insert_get_quest()
	_test_update()
	_test_root_hash_32b()
	_test_find_by_type()
	_test_diff_same()
	_test_diff_different()
	_test_apply_diff_roundtrip()
	_test_determinism()
	_test_multiple_paths()
	print("DefinitionTree tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_init() -> void:
	var tree := DefinitionTreeScript.new()
	_assert(tree != null, "init creates DefinitionTree")
	var schema := DefinitionSchemaScript.new()
	_assert(schema != null, "DefinitionSchema creates instance")
	var hash := tree.root_hash()
	_assert(hash.size() == 32, "empty tree has 32-byte root hash")


func _test_insert_get_zone() -> void:
	var tree := DefinitionTreeScript.new()
	var hash := tree.insert_def("definitions/zone_1", "zone", "zone_1", {"name": "Spawn Islands", "capacity": 50})
	_assert(hash.size() == 32, "insert_def zone returns 32-byte hash")
	var def := tree.get_def("definitions/zone_1")
	_assert(def.get("def_type") == "zone", "retrieved def has def_type zone")
	_assert(def.get("key") == "zone_1", "retrieved def has key zone_1")
	_assert(def.get("data").get("name") == "Spawn Islands", "retrieved data has correct name")
	_assert(def.get("data").get("capacity") == 50, "retrieved data has correct capacity")


func _test_insert_get_npc() -> void:
	var tree := DefinitionTreeScript.new()
	var hash := tree.insert_def("definitions/npc_1", "npc", "npc_1", {"name": "IronForge Guard", "level": 12})
	_assert(hash.size() == 32, "insert_def npc returns 32-byte hash")
	var def := tree.get_def("definitions/npc_1")
	_assert(def.get("def_type") == "npc", "retrieved def has def_type npc")
	_assert(def.get("key") == "npc_1", "retrieved def has key npc_1")
	_assert(def.get("data").get("name") == "IronForge Guard", "retrieved data has correct name")
	_assert(def.get("data").get("level") == 12, "retrieved data has correct level")


func _test_insert_get_quest() -> void:
	var tree := DefinitionTreeScript.new()
	var hash := tree.insert_def("definitions/quest_1", "quest", "quest_1", {"title": "The Lost Scroll", "reward": 100})
	_assert(hash.size() == 32, "insert_def quest returns 32-byte hash")
	var def := tree.get_def("definitions/quest_1")
	_assert(def.get("def_type") == "quest", "retrieved def has def_type quest")
	_assert(def.get("key") == "quest_1", "retrieved def has key quest_1")
	_assert(def.get("data").get("title") == "The Lost Scroll", "retrieved data has correct title")
	_assert(def.get("data").get("reward") == 100, "retrieved data has correct reward")


func _test_update() -> void:
	var tree := DefinitionTreeScript.new()
	tree.insert_def("definitions/zone_1", "zone", "zone_1", {"name": "Spawn Islands", "capacity": 50})
	var hash1 := tree.root_hash()
	var hash2 := tree.update_def("definitions/zone_1", "zone", "zone_1", {"name": "Spawn Islands", "capacity": 100})
	_assert(hash2.size() == 32, "update_def returns 32-byte hash")
	_assert(hash2 != hash1, "root hash changes after update")
	var def := tree.get_def("definitions/zone_1")
	_assert(def.get("data").get("capacity") == 100, "capacity updated to 100")


func _test_root_hash_32b() -> void:
	var tree := DefinitionTreeScript.new()
	var hash := tree.root_hash()
	_assert(hash.size() == 32, "root_hash returns 32 bytes")
	tree.insert_def("definitions/zone_1", "zone", "zone_1", {"name": "Test", "capacity": 1})
	var hash2 := tree.root_hash()
	_assert(hash2.size() == 32, "root_hash still 32 bytes after insert")
	_assert(hash2 != hash, "root hash changes after insert")


func _test_find_by_type() -> void:
	var tree := DefinitionTreeScript.new()
	tree.insert_def("definitions/zone_1", "zone", "zone_1", {"name": "Zone A"})
	tree.insert_def("definitions/zone_2", "zone", "zone_2", {"name": "Zone B"})
	tree.insert_def("definitions/npc_1", "npc", "npc_1", {"name": "NPC A"})
	tree.insert_def("definitions/quest_1", "quest", "quest_1", {"name": "Quest A"})
	var zones := tree.find_by_type("zone")
	_assert(zones.size() == 2, "find_by_type zone returns 2 paths")
	var zone_paths := []
	for p in zones:
		zone_paths.append(p)
	zone_paths.sort()
	_assert(zone_paths == ["definitions/zone_1", "definitions/zone_2"], "zone paths are correct")
	var npcs := tree.find_by_type("npc")
	_assert(npcs.size() == 1 and npcs[0] == "definitions/npc_1", "find_by_type npc returns 1 path")
	var quests := tree.find_by_type("quest")
	_assert(quests.size() == 1 and quests[0] == "definitions/quest_1", "find_by_type quest returns 1 path")


func _test_diff_same() -> void:
	var tree := DefinitionTreeScript.new()
	var root := tree.root_hash()
	var diff := tree.diff_defs(root, root)
	_assert(diff.is_empty(), "diff of same roots is empty")


func _test_diff_different() -> void:
	var tree := DefinitionTreeScript.new()
	var root_a := tree.root_hash()
	tree.insert_def("definitions/zone_1", "zone", "zone_1", {"name": "Zone A"})
	tree.insert_def("definitions/npc_1", "npc", "npc_1", {"name": "NPC A"})
	var root_b := tree.root_hash()
	var diff := tree.diff_defs(root_a, root_b)
	_assert(diff.size() == 2, "diff reports two changed paths")
	var paths := []
	for entry in diff:
		paths.append(entry[0])
	paths.sort()
	_assert(paths == ["definitions/npc_1", "definitions/zone_1"], "diff paths are correct and ordered")


func _test_apply_diff_roundtrip() -> void:
	var tree := DefinitionTreeScript.new()
	var root_a := tree.root_hash()
	tree.insert_def("definitions/zone_1", "zone", "zone_1", {"name": "Zone A"})
	tree.insert_def("definitions/npc_1", "npc", "npc_1", {"name": "NPC A"})
	var root_b := tree.root_hash()
	var diff := tree.diff_defs(root_a, root_b)
	var tree2 := DefinitionTreeScript.new()
	var applied_root := tree2.apply_diff(root_a, diff)
	_assert(applied_root == root_b, "apply_diff roundtrip returns target root")
	var def1 := tree2.get_def("definitions/zone_1")
	var def2 := tree2.get_def("definitions/npc_1")
	_assert(def1.get("data").get("name") == "Zone A", "zone def restored")
	_assert(def2.get("data").get("name") == "NPC A", "npc def restored")


func _test_determinism() -> void:
	var tree1 := DefinitionTreeScript.new()
	var tree2 := DefinitionTreeScript.new()
	tree1.insert_def("definitions/zone_1", "zone", "zone_1", {"name": "Zone A", "capacity": 50})
	tree2.insert_def("definitions/zone_1", "zone", "zone_1", {"name": "Zone A", "capacity": 50})
	_assert(tree1.root_hash() == tree2.root_hash(), "same inserts produce same root hash")


func _test_multiple_paths() -> void:
	var tree := DefinitionTreeScript.new()
	tree.insert_def("definitions/zone_1", "zone", "zone_1", {"name": "Zone A"})
	tree.insert_def("definitions/zone_2", "zone", "zone_2", {"name": "Zone B"})
	tree.insert_def("definitions/npc_1", "npc", "npc_1", {"name": "NPC A"})
	tree.insert_def("definitions/quest_1", "quest", "quest_1", {"name": "Quest A"})
	tree.insert_def("definitions/item_1", "item", "item_1", {"name": "Sword"})
	tree.insert_def("definitions/skill_1", "skill", "skill_1", {"name": "Fireball"})
	_assert(tree.root_hash().size() == 32, "root hash is 32 bytes with multiple paths")
	_assert(tree.get_def("definitions/zone_1").get("key") == "zone_1", "zone_1 key correct")
	_assert(tree.get_def("definitions/zone_2").get("key") == "zone_2", "zone_2 key correct")
	_assert(tree.get_def("definitions/npc_1").get("key") == "npc_1", "npc_1 key correct")
	_assert(tree.get_def("definitions/quest_1").get("key") == "quest_1", "quest_1 key correct")
	_assert(tree.get_def("definitions/item_1").get("key") == "item_1", "item_1 key correct")
	_assert(tree.get_def("definitions/skill_1").get("key") == "skill_1", "skill_1 key correct")
	var all_zones := tree.find_by_type("zone")
	_assert(all_zones.size() == 2, "find_by_type zone finds 2 with multiple paths")


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
