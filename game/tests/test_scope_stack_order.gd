## Scope stack order regression (audit round 20).
##
## The rules stack has ONE canonical order, pinned by the spec
## (prd-scope-engine.md US-006: resolve_rule walks from root to the
## player's current scope), by ScopeEngine (push appends the root first),
## by AppFirewall, and by RulesEngine (TOP_WINS reads stack[size-1] = the
## innermost/player; BOTTOM_WINS reads stack[0] = the outermost/root).
##
## SecurityService and MatchmakingQoS used to build the stack
## INNERMOST-FIRST, which silently inverted TOP_WINS and BOTTOM_WINS for
## both. This test fails loudly if either service regresses to that order.
##
## NOTE: service scripts are loaded at RUNTIME (not preload) because
## --script mode does not register autoload globals at parse time, so a
## parse-time preload of these files cannot compile (GameLog etc.).
extends SceneTree

const ScopeScript = preload("res://core/frame/srv/scope.gd")

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_security_stack_is_root_first()
	_test_qos_stack_is_root_first()
	print("ScopeStack order tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_security_stack_is_root_first() -> void:
	var script: GDScript = load("res://core/services/security_service.gd")
	if script == null:
		_fail("security_service.gd failed to load (cannot test scope order)")
		return
	var svc = script.new()
	svc._create_scopes()
	var pid := "player_1"
	svc._player_scopes[pid] = ScopeScript.new("player_" + pid, svc._instance_scope, "", {})
	var stack: Array = svc._build_scope_stack(pid)
	_assert(stack.size() == 4, "security stack has world/shard/instance/player")
	_assert(stack[0].parent == null, "security stack[0] is the hierarchy root (no parent)")
	_assert_eq(stack[0].name, "world", "security stack[0] is the world root")
	_assert_eq(stack[stack.size() - 1].name, "player_" + pid, "security stack[-1] is the player (innermost)")


func _test_qos_stack_is_root_first() -> void:
	var script: GDScript = load("res://core/services/matchmaking_qos.gd")
	if script == null:
		_fail("matchmaking_qos.gd failed to load (cannot test scope order)")
		return
	var svc = script.new()
	svc._create_scopes()
	var pid := "player_2"
	svc._player_scopes[pid] = ScopeScript.new("player_" + pid, svc._instance_scope, "", {})
	var stack: Array = svc._build_scope_stack(pid)
	_assert(stack.size() == 4, "qos stack has world/shard/instance/player")
	_assert(stack[0].parent == null, "qos stack[0] is the hierarchy root (no parent)")
	_assert_eq(stack[0].name, "world", "qos stack[0] is the world root")
	_assert_eq(stack[stack.size() - 1].name, "player_" + pid, "qos stack[-1] is the player (innermost)")


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


func _fail(label: String) -> void:
	_failed += 1
	print("  [FAIL] %s" % label)
