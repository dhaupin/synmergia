## ZoneManager definition-tree mirroring tests (arch §9 wiring).
extends SceneTree

var _passed := 0
var _failed := 0


func _initialize() -> void:
	# Wait one frame so autoloads finish _ready (load_zones mirrors into the tree).
	await process_frame
	_test_zone_manager_has_tree()
	_test_mirror_from_load_zones()
	_test_get_zone_def()
	_test_def_tree_contents()
	print("ZoneDefTree tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_zone_manager_has_tree() -> void:
	var zm = root.get_node_or_null("ZoneManager")
	_assert(zm != null, "ZoneManager autoload exists")
	_assert(zm._get_definition_tree() != null, "ZoneManager resolves definition tree")


func _test_mirror_from_load_zones() -> void:
	var zm = root.get_node_or_null("ZoneManager")
	# Re-run load to ensure mirroring happens even if zones were already loaded.
	zm.load_zones()
	var def_tree = zm._get_definition_tree()
	var zone_defs: Array = def_tree.find_by_type("zone")
	_assert(zone_defs.size() > 0, "definition tree has zone defs after load_zones")
	for path in zone_defs:
		_assert(str(path).begins_with("definitions/zones/"), "zone def paths live under definitions/zones/")


func _test_get_zone_def() -> void:
	var zm = root.get_node_or_null("ZoneManager")
	var def_tree = zm._get_definition_tree()
	var zone_defs: Array = def_tree.find_by_type("zone")
	if zone_defs.is_empty():
		_assert(false, "cannot test get_zone_def: no zone defs")
		return
	var zone_id := str(def_tree.get_def(str(zone_defs[0])).get("key"))
	var got: Dictionary = zm.get_zone_def(zone_id)
	_assert(not got.is_empty(), "get_zone_def returns a def for an existing zone")
	_assert(got.get("def_type") == "zone", "get_zone_def result has def_type zone")
	_assert(got.get("key") == zone_id, "get_zone_def result key matches zone id")
	_assert(zm.get_zone_def("__nonexistent_zone__").is_empty(), "get_zone_def returns empty for unknown zone")


func _test_def_tree_contents() -> void:
	var zm = root.get_node_or_null("ZoneManager")
	var def_tree = zm._get_definition_tree()
	var zone_defs: Array = def_tree.find_by_type("zone")
	var first: Dictionary = def_tree.get_def(str(zone_defs[0]))
	var data: Dictionary = first.get("data", {})
	_assert(data.has("display_name"), "zone def data carries display_name")
	_assert(data.has("pvp_mode"), "zone def data carries pvp_mode")
	_assert(data.has("level_requirement"), "zone def data carries level_requirement")


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % msg)
