## EnemyAI memory-tree integration tests (arch §9 wiring).
extends SceneTree

const MemoryTreeScript = preload("res://core/frame/kv/memory_tree.gd")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	await process_frame
	_test_ai_compiles_and_loads()
	_test_remember_writes_memory()
	_test_known_threats_updated()
	_test_multiple_threats_tracked()
	print("AIMemory tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_ai_compiles_and_loads() -> void:
	var s = load("res://core/ai/enemy_ai.gd")
	_assert(s != null, "enemy_ai.gd compiles with memory wiring")
	var ai = s.new()
	_assert(ai._get_memory_tree() != null, "AI resolves a memory tree lazily")
	ai.free()


func _test_remember_writes_memory() -> void:
	var s = load("res://core/ai/enemy_ai.gd")
	var ai = s.new()
	ai._memory_agent_path = "memory/enemies/test_enemy_1"
	ai.remember("hit_p1_1", {"player_id": "p1", "action": "attacked", "time": 100.0}, 1.0)
	var tree = ai._get_memory_tree()
	var mem: Dictionary = tree.get_memory("memory/enemies/test_enemy_1/events/hit_p1_1")
	_assert(not mem.is_empty(), "remember() writes an event memory")
	_assert(mem.get("kind") == "event", "memory kind is event")
	_assert(mem.get("content").get("player_id") == "p1", "memory content carries player_id")
	_assert(absf(float(mem.get("weight")) - 1.0) < 0.001, "memory weight stored")
	ai.free()


func _test_known_threats_updated() -> void:
	var s = load("res://core/ai/enemy_ai.gd")
	var ai = s.new()
	ai._memory_agent_path = "memory/enemies/test_enemy_2"
	ai.remember("hit_p2_1", {"player_id": "p2", "action": "attacked", "time": 200.0}, 1.0)
	_assert(ai._known_threats.get("p2", 0.0) == 1.0, "known_threats updated after remember()")
	ai.free()


func _test_multiple_threats_tracked() -> void:
	var s = load("res://core/ai/enemy_ai.gd")
	var ai = s.new()
	ai._memory_agent_path = "memory/enemies/test_enemy_3"
	ai.remember("hit_p3_1", {"player_id": "p3", "action": "attacked", "time": 300.0}, 1.0)
	ai.remember("hit_p4_1", {"player_id": "p4", "action": "attacked", "time": 301.0}, 1.5)
	_assert(ai._known_threats.size() == 2, "two distinct threat memories tracked")
	_assert(float(ai._known_threats.get("p3", 0.0)) == 1.0, "p3 weight remembered")
	_assert(float(ai._known_threats.get("p4", 0.0)) == 1.5, "p4 weight remembered")
	ai.free()


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % msg)
