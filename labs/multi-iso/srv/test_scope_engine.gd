## Ported from vant axolotl lib/brain.js
extends SceneTree

var _all_passed = true

func _init() -> void:
	_test_hierarchy_loading()
	_test_walk_and_find()
	_test_flip_and_resolve()
	_test_push_pop_stack()
	_test_pvp_zone_flip()
	_test_invalid_hierarchy_rejection()
	_test_custom_hierarchy()
	_test_deep_hierarchy()
	_test_resolution_constants()
	_test_stack_isolation()

	if _all_passed:
		print("ALL TESTS PASSED")
	else:
		push_error("SOME TESTS FAILED")
	quit(0 if _all_passed else 1)

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		push_error("ASSERT FAILED: %s" % msg)
		_all_passed = false
	else:
		print("PASS: %s" % msg)

func _assert_eq(actual, expected, msg: String) -> void:
	if actual != expected:
		push_error("ASSERT FAILED: %s (got %s, expected %s)" % [msg, actual, expected])
		_all_passed = false
	else:
		print("PASS: %s" % msg)

func _make_test_hierarchy() -> ScopeHierarchy:
	var hierarchy = ScopeHierarchy.new()

	var world_node = ScopeHierarchy.ScopeNode.new()
	world_node.name = "world"
	world_node.parent_name = ""
	world_node.environment_path = "world/environment.tres"
	world_node.rules_overrides = {}

	var shard_node = ScopeHierarchy.ScopeNode.new()
	shard_node.name = "shard"
	shard_node.parent_name = "world"
	shard_node.environment_path = "shard/environment.tres"
	shard_node.rules_overrides = {}

	var instance_node = ScopeHierarchy.ScopeNode.new()
	instance_node.name = "instance"
	instance_node.parent_name = "shard"
	instance_node.environment_path = "instance/environment.tres"
	instance_node.rules_overrides = {}

	var player_node = ScopeHierarchy.ScopeNode.new()
	player_node.name = "player"
	player_node.parent_name = "instance"
	player_node.environment_path = "player/environment.tres"
	player_node.rules_overrides = {}

	hierarchy.nodes = [world_node, shard_node, instance_node, player_node]
	return hierarchy

func _save_hierarchy_to_temp(hierarchy: ScopeHierarchy, path: String) -> void:
	var dir = DirAccess.open("user://")
	if not dir:
		dir = DirAccess.open("res://")
	ResourceSaver.save(hierarchy, path)

func _test_hierarchy_loading() -> void:
	print("\n=== test_hierarchy_loading ===")
	var engine = ScopeEngine.new()
	var hierarchy = _make_test_hierarchy()

	var temp_path = "user://test_hierarchy.tres"
	ResourceSaver.save(hierarchy, temp_path)

	var ok = engine.load_hierarchy(temp_path)
	_assert(ok, "load_hierarchy returns true for valid hierarchy")

	var root = engine.get_root()
	_assert(root != null, "get_root returns non-null")
	_assert_eq(root.name, "world", "root name is 'world'")

	var shard = engine.get_scope("shard")
	_assert(shard != null, "get_scope('shard') returns non-null")
	_assert_eq(shard.parent.name, "world", "shard parent is world")

	var instance = engine.get_scope("instance")
	_assert(instance != null, "get_scope('instance') returns non-null")
	_assert_eq(instance.parent.name, "shard", "instance parent is shard")

	var player = engine.get_scope("player")
	_assert(player != null, "get_scope('player') returns non-null")
	_assert_eq(player.parent.name, "instance", "player parent is instance")

	_assert(engine.get_scope("nonexistent") == null, "get_scope returns null for unknown")
end

func _test_walk_and_find() -> void:
	print("\n=== test_walk_and_find ===")
	var engine = ScopeEngine.new()
	var hierarchy = _make_test_hierarchy()
	var temp_path = "user://test_hierarchy.tres"
	ResourceSaver.save(hierarchy, temp_path)
	engine.load_hierarchy(temp_path)

	var visited = []
	engine.get_root().walk(Callable(self, "_walk_collector", visited))
	_assert_eq(visited.size(), 4, "walk visits all 4 nodes")
	_assert(visited.has("world"), "walk includes world")
	_assert(visited.has("shard"), "walk includes shard")
	_assert(visited.has("instance"), "walk includes instance")
	_assert(visited.has("player"), "walk includes player")

	var found = engine.get_root().find("instance")
	_assert(found != null, "find('instance') returns non-null")
	_assert_eq(found.name, "instance", "found name is 'instance'")

	_assert(engine.get_root().find("nonexistent") == null, "find returns null for unknown")
end

func _walk_collector(visited: Array, scope: Scope) -> void:
	visited.append(scope.name)

func _test_flip_and_resolve() -> void:
	print("\n=== test_flip_and_resolve ===")
	var engine = ScopeEngine.new()
	var hierarchy = _make_test_hierarchy()
	var temp_path = "user://test_hierarchy.tres"
	ResourceSaver.save(hierarchy, temp_path)
	engine.load_hierarchy(temp_path)

	var shard = engine.get_scope("shard")
	shard.flip("can_pvp", ScopeEngine.BOTTOM_WINS)

	engine.push("player1", "world")
	engine.push("player1", "shard")

	var resolved = engine.resolve_rule("player1", "can_pvp", ScopeEngine.TOP_WINS)
	_assert_eq(resolved, ScopeEngine.BOTTOM_WINS, "flip on shard overrides TOP_WINS default")

	engine.push("player1", "instance")
	resolved = engine.resolve_rule("player1", "can_pvp", ScopeEngine.TOP_WINS)
	_assert_eq(resolved, ScopeEngine.BOTTOM_WINS, "BOTTOM_WINS persists down stack")

	engine.push("player1", "player")
	resolved = engine.resolve_rule("player1", "can_pvp", ScopeEngine.TOP_WINS)
	_assert_eq(resolved, ScopeEngine.BOTTOM_WINS, "BOTTOM_WINS still wins at player level")

	var no_override = engine.resolve_rule("player1", "unknown_rule", ScopeEngine.TOP_WINS)
	_assert_eq(no_override, ScopeEngine.TOP_WINS, "default returned when no override")

	engine.pop("player1")
	engine.pop("player1")
	resolved = engine.resolve_rule("player1", "can_pvp", ScopeEngine.TOP_WINS)
	_assert_eq(resolved, ScopeEngine.TOP_WINS, "after pop to world level, default returns")
end

func _test_push_pop_stack() -> void:
	print("\n=== test_push_pop_stack ===")
	var engine = ScopeEngine.new()
	var hierarchy = _make_test_hierarchy()
	var temp_path = "user://test_hierarchy.tres"
	ResourceSaver.save(hierarchy, temp_path)
	engine.load_hierarchy(temp_path)

	_assert(engine.get_stack("unknown").is_empty(), "get_stack returns empty for unknown player")

	var ok = engine.push("p1", "world")
	_assert(ok, "push returns true for valid scope")
	_assert_eq(engine.get_stack("p1").size(), 1, "stack size 1 after one push")
	_assert_eq(engine.get_stack("p1")[0].name, "world", "stack[0] is world")

	ok = engine.push("p1", "shard")
	_assert(ok, "push returns true for second scope")
	_assert_eq(engine.get_stack("p1").size(), 2, "stack size 2 after second push")

	ok = engine.push("p1", "nonexistent")
	_assert(not ok, "push returns false for invalid scope")
	_assert_eq(engine.get_stack("p1").size(), 2, "stack unchanged after failed push")

	ok = engine.pop("p1")
	_assert(ok, "pop returns true for non-empty stack")
	_assert_eq(engine.get_stack("p1").size(), 1, "stack size 1 after pop")

	ok = engine.pop("p1")
	_assert(ok, "pop returns true for last element")
	_assert_eq(engine.get_stack("p1").size(), 0, "stack empty after pop all")

	ok = engine.pop("p1")
	_assert(not ok, "pop returns false for empty stack")

	engine.push("p2", "world")
	engine.push("p2", "shard")
	_assert_eq(engine.get_stack("p2").size(), 2, "p2 has independent stack")
	_assert_eq(engine.get_stack("p1").size(), 0, "p1 stack unchanged")
end

func _test_pvp_zone_flip() -> void:
	print("\n=== test_pvp_zone_flip ===")
	var engine = ScopeEngine.new()
	var hierarchy = _make_test_hierarchy()
	var temp_path = "user://test_hierarchy.tres"
	ResourceSaver.save(hierarchy, temp_path)
	engine.load_hierarchy(temp_path)

	var instance = engine.get_scope("instance")
	instance.flip("can_pvp", ScopeEngine.BOTTOM_WINS)

	engine.push("player_in_zone", "world")
	engine.push("player_in_zone", "shard")
	engine.push("player_in_zone", "instance")

	var resolved = engine.resolve_rule("player_in_zone", "can_pvp", ScopeEngine.TOP_WINS)
	_assert_eq(resolved, ScopeEngine.BOTTOM_WINS, "player in PvP zone: BOTTOM_WINS wins")

	engine.push("player_out_zone", "world")
	engine.push("player_out_zone", "shard")

	resolved = engine.resolve_rule("player_out_zone", "can_pvp", ScopeEngine.TOP_WINS)
	_assert_eq(resolved, ScopeEngine.TOP_WINS, "player outside PvP zone: TOP_WINS default wins")
end

func _test_invalid_hierarchy_rejection() -> void:
	print("\n=== test_invalid_hierarchy_rejection ===")

	var hierarchy = ScopeHierarchy.new()
	var n1 = ScopeHierarchy.ScopeNode.new()
	n1.name = "a"
	n1.parent_name = ""
	n1.environment_path = "a.tres"
	n1.rules_overrides = {}
	var n2 = ScopeHierarchy.ScopeNode.new()
	n2.name = "b"
	n2.parent_name = ""
	n2.environment_path = "b.tres"
	n2.rules_overrides = {}
	hierarchy.nodes = [n1, n2]
	var temp_path = "user://bad_multi_root.tres"
	ResourceSaver.save(hierarchy, temp_path)

	var engine = ScopeEngine.new()
	var ok = engine.load_hierarchy(temp_path)
	_assert(not ok, "multiple roots rejected")

	hierarchy = ScopeHierarchy.new()
	n1 = ScopeHierarchy.ScopeNode.new()
	n1.name = "a"
	n1.parent_name = "b"
	n1.environment_path = "a.tres"
	n1.rules_overrides = {}
	n2 = ScopeHierarchy.ScopeNode.new()
	n2.name = "b"
	n2.parent_name = "a"
	n2.environment_path = "b.tres"
	n2.rules_overrides = {}
	hierarchy.nodes = [n1, n2]
	temp_path = "user://bad_cycle.tres"
	ResourceSaver.save(hierarchy, temp_path)

	engine = ScopeEngine.new()
	ok = engine.load_hierarchy(temp_path)
	_assert(not ok, "cycle rejected")

	hierarchy = ScopeHierarchy.new()
	n1 = ScopeHierarchy.ScopeNode.new()
	n1.name = "a"
	n1.parent_name = "missing"
	n1.environment_path = "a.tres"
	n1.rules_overrides = {}
	hierarchy.nodes = [n1]
	temp_path = "user://bad_missing_parent.tres"
	ResourceSaver.save(hierarchy, temp_path)

	engine = ScopeEngine.new()
	ok = engine.load_hierarchy(temp_path)
	_assert(not ok, "missing parent rejected")

	hierarchy = _make_test_hierarchy()
	hierarchy.nodes[0].environment_path = "nonexistent.tres"
	temp_path = "user://bad_env.tres"
	ResourceSaver.save(hierarchy, temp_path)

	engine = ScopeEngine.new()
	ok = engine.load_hierarchy(temp_path)
	_assert(not ok, "missing environment file rejected")
end

func _test_custom_hierarchy() -> void:
	print("\n=== test_custom_hierarchy ===")
	var engine = ScopeEngine.new()

	var hierarchy = ScopeHierarchy.new()

	var galaxy = ScopeHierarchy.ScopeNode.new()
	galaxy.name = "galaxy"
	galaxy.parent_name = ""
	galaxy.environment_path = "galaxy/environment.tres"
	galaxy.rules_overrides = {}

	var sector = ScopeHierarchy.ScopeNode.new()
	sector.name = "sector"
	sector.parent_name = "galaxy"
	sector.environment_path = "sector/environment.tres"
	sector.rules_overrides = {}

	var system = ScopeHierarchy.ScopeNode.new()
	system.name = "system"
	system.parent_name = "sector"
	system.environment_path = "system/environment.tres"
	system.rules_overrides = {}

	var planet = ScopeHierarchy.ScopeNode.new()
	planet.name = "planet"
	planet.parent_name = "system"
	planet.environment_path = "planet/environment.tres"
	planet.rules_overrides = {}

	var character = ScopeHierarchy.ScopeNode.new()
	character.name = "character"
	character.parent_name = "planet"
	character.environment_path = "character/environment.tres"
	character.rules_overrides = {}

	hierarchy.nodes = [galaxy, sector, system, planet, character]

	var temp_path = "user://custom_hierarchy.tres"
	ResourceSaver.save(hierarchy, temp_path)

	var ok = engine.load_hierarchy(temp_path)
	_assert(ok, "custom 5-level hierarchy loads")

	var root = engine.get_root()
	_assert_eq(root.name, "galaxy", "custom root is galaxy")

	var char = engine.get_scope("character")
	_assert(char != null, "get_scope('character') works")
	_assert_eq(char.parent.name, "planet", "character parent is planet")
	_assert_eq(char.parent.parent.name, "system", "grandparent is system")
	_assert_eq(char.parent.parent.parent.name, "sector", "great-grandparent is sector")
	_assert_eq(char.parent.parent.parent.parent.name, "galaxy", "great-great-grandparent is galaxy")
end

func _test_deep_hierarchy() -> void:
	print("\n=== test_deep_hierarchy ===")
	var engine = ScopeEngine.new()

	var hierarchy = ScopeHierarchy.new()
	var prev = "root"
	var root_node = ScopeHierarchy.ScopeNode.new()
	root_node.name = "root"
	root_node.parent_name = ""
	root_node.environment_path = "root.tres"
	root_node.rules_overrides = {}
	hierarchy.nodes.append(root_node)

	for i in range(20):
		var node = ScopeHierarchy.ScopeNode.new()
		node.name = "level_%d" % i
		node.parent_name = prev
		node.environment_path = "level_%d.tres" % i
		node.rules_overrides = {}
		hierarchy.nodes.append(node)
		prev = node.name

	var temp_path = "user://deep_hierarchy.tres"
	ResourceSaver.save(hierarchy, temp_path)

	var ok = engine.load_hierarchy(temp_path)
	_assert(ok, "20-level deep hierarchy loads")

	engine.push("p1", "root")
	for i in range(20):
		engine.push("p1", "level_%d" % i)

	var stack = engine.get_stack("p1")
	_assert_eq(stack.size(), 21, "deep stack has 21 elements (root + 20 levels)")

	var resolved = engine.resolve_rule("p1", "test_rule", ScopeEngine.TOP_WINS)
	_assert_eq(resolved, ScopeEngine.TOP_WINS, "default resolution at deep level")
end

func _test_resolution_constants() -> void:
	print("\n=== test_resolution_constants ===")
	_assert_eq(ScopeEngine.TOP_WINS, "TOP_WINS", "TOP_WINS constant")
	_assert_eq(ScopeEngine.BOTTOM_WINS, "BOTTOM_WINS", "BOTTOM_WINS constant")
	_assert_eq(ScopeEngine.PREDICATE_GATED, "PREDICATE_GATED", "PREDICATE_GATED constant")
	_assert_eq(ScopeEngine.ALL_WINS_WITH_EFFECT, "ALL_WINS_WITH_EFFECT", "ALL_WINS_WITH_EFFECT constant")
end

func _test_stack_isolation() -> void:
	print("\n=== test_stack_isolation ===")
	var engine = ScopeEngine.new()
	var hierarchy = _make_test_hierarchy()
	var temp_path = "user://test_hierarchy.tres"
	ResourceSaver.save(hierarchy, temp_path)
	engine.load_hierarchy(temp_path)

	engine.push("alice", "world")
	engine.push("alice", "shard")
	engine.push("bob", "world")
	engine.push("bob", "instance")

	_assert_eq(engine.get_stack("alice").size(), 2, "alice has 2 scopes")
	_assert_eq(engine.get_stack("bob").size(), 2, "bob has 2 scopes")
	_assert_eq(engine.get_stack("alice")[1].name, "shard", "alice at shard")
	_assert_eq(engine.get_stack("bob")[1].name, "instance", "bob at instance")

	engine.clear_player_stack("alice")
	_assert(engine.get_stack("alice").is_empty(), "clear_player_stack empties alice")
	_assert_eq(engine.get_stack("bob").size(), 2, "bob unaffected")
end