## RulesEngine test suite. Spec: labs/world-building-arch.md В§5
extends SceneTree

const T3Script = preload("res://core/frame/kv/t3.gd")
const RulesEngineScript = preload("res://core/frame/srv/rules_engine.gd")
const RulesSchemaScript = preload("res://core/frame/srv/rules_schema.gd")
const ScopeScript = preload("res://core/frame/srv/scope.gd")

var _passed := 0
var _failed := 0


func _init() -> void:
	_test_register_and_retrieve_rule()
	_test_evaluate_no_rule()
	_test_evaluate_top_wins_default()
	_test_evaluate_bottom_wins_default()
	_test_evaluate_with_scope_override()
	_test_scope_override_flips_resolution()
	_test_set_override_via_method()
	_test_root_hash_changes_after_registration()
	_test_get_rule_returns_dictionary()
	_test_evaluate_returns_all_fields()
	_test_multiple_rules_independent()
	_test_all_wins_with_effect()
	_test_predicate_gated_no_predicate()
	_test_top_wins_uses_innermost()
	_test_bottom_wins_uses_outermost()
	_test_predicate_gated_invokes_predicate()
	_test_register_rule_excludes_predicate_from_payload()
	_test_canonical_bytes_deterministic()
	_test_schema_validate()
	_test_schema_display()
	print("RulesEngine tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_register_and_retrieve_rule() -> void:
	var engine := RulesEngineScript.new()
	var hash := engine.register_rule("can_build", "TOP_WINS", true)
	_assert(hash.size() == 32, "register_rule returns 32-byte hash")
	var rule := engine.get_rule("can_build")
	_assert(not rule.is_empty(), "get_rule returns the rule value")
	_assert_eq(rule.get("resolution"), "TOP_WINS", "rule resolution is preserved")
	_assert_eq(rule.get("default_allow"), true, "rule default_allow is true")


func _test_evaluate_no_rule() -> void:
	var engine := RulesEngineScript.new()
	var result := engine.evaluate("nonexistent_action", {}, [])
	_assert_eq(result["allow"], false, "unregistered action is denied")
	_assert(result["reason"].find("no rule") >= 0, "result includes reason about missing rule")


func _test_evaluate_top_wins_default() -> void:
	var engine := RulesEngineScript.new()
	engine.register_rule("can_build", "TOP_WINS", true)
	var result := engine.evaluate("can_build", {}, [])
	_assert_eq(result["allow"], true, "TOP_WINS with no stack returns default_allow")


func _test_evaluate_bottom_wins_default() -> void:
	var engine := RulesEngineScript.new()
	engine.register_rule("can_build", "BOTTOM_WINS", false)
	var result := engine.evaluate("can_build", {}, [])
	_assert_eq(result["allow"], false, "BOTTOM_WINS with no stack returns default_allow")


func _test_evaluate_with_scope_override() -> void:
	var engine := RulesEngineScript.new()
	var scope := ScopeScript.new("player", null, "", {"can_build": "BOTTOM_WINS"})
	engine.register_rule("can_build", "TOP_WINS", true)
	var result := engine.evaluate("can_build", {}, [scope])
	_assert_eq(result["allow"], true, "scope override applies during evaluation")


func _test_scope_override_flips_resolution() -> void:
	var engine := RulesEngineScript.new()
	engine.register_rule("pvp", "TOP_WINS", true)
	var scope := ScopeScript.new("pvp_zone", null, "", {})
	scope.flip("pvp", "BOTTOM_WINS")
	var result := engine.evaluate("pvp", {}, [scope])
	_assert_eq(result["allow"], true, "flipped resolution uses BOTTOM_WINS strategy")


func _test_set_override_via_method() -> void:
	var engine := RulesEngineScript.new()
	var scope := ScopeScript.new("test_scope", null, "", {})
	engine.register_rule("test_rule", "TOP_WINS", true)
	engine.set_override(scope, "test_rule", "BOTTOM_WINS")
	_assert_eq(scope.get_override("test_rule"), "BOTTOM_WINS", "set_override calls scope.flip")


func _test_root_hash_changes_after_registration() -> void:
	var engine := RulesEngineScript.new()
	var root_before := engine.root_hash()
	engine.register_rule("new_rule", "TOP_WINS", true)
	var root_after := engine.root_hash()
	_assert(root_before != root_after, "root hash changes after rule registration")


func _test_get_rule_returns_dictionary() -> void:
	var engine := RulesEngineScript.new()
	engine.register_rule("test_rule", "TOP_WINS", false)
	var rule := engine.get_rule("test_rule")
	_assert(rule is Dictionary, "get_rule returns a Dictionary")
	_assert(not rule.is_empty(), "rule dictionary has content")


func _test_evaluate_returns_all_fields() -> void:
	var engine := RulesEngineScript.new()
	engine.register_rule("can_build", "TOP_WINS", true)
	var result := engine.evaluate("can_build", {"player": "p1"}, [])
	_assert(result.has("allow"), "result has allow field")
	_assert(result.has("reason"), "result has reason field")
	_assert(result.has("modified_action"), "result has modified_action field")
	_assert(result.has("applied_rules"), "result has applied_rules field")


func _test_multiple_rules_independent() -> void:
	var engine := RulesEngineScript.new()
	engine.register_rule("rule_a", "TOP_WINS", true)
	engine.register_rule("rule_b", "BOTTOM_WINS", false)
	var result_a := engine.evaluate("rule_a", {}, [])
	var result_b := engine.evaluate("rule_b", {}, [])
	_assert_eq(result_a["allow"], true, "rule_a allows")
	_assert_eq(result_b["allow"], false, "rule_b denies")


func _test_all_wins_with_effect() -> void:
	var engine := RulesEngineScript.new()
	var scope1 := ScopeScript.new("s1", null, "", {})
	var scope2 := ScopeScript.new("s2", null, "", {})
	engine.register_rule("all_rule", "ALL_WINS_WITH_EFFECT", true)
	var result := engine.evaluate("all_rule", {}, [scope1, scope2])
	_assert(result["applied_rules"].size() >= 2, "ALL_WINS collects rules from stack scopes")


func _test_predicate_gated_no_predicate() -> void:
	var engine := RulesEngineScript.new()
	engine.register_rule("pred_rule", "PREDICATE_GATED", true)
	var result := engine.evaluate("pred_rule", {}, [])
	_assert_eq(result["allow"], true, "PREDICATE_GATED without predicate falls back to default_allow")


# Stack order: push() appends, so stack[0] is the outermost (root) scope
# and the last element is the innermost (player) scope. TOP_WINS must read
# the innermost; BOTTOM_WINS must read the outermost. (_override_allows:
# PREDICATE_GATED denies, TOP_WINS allows, so a scope's strategy value is
# usable as an allow/deny marker here.)
func _test_top_wins_uses_innermost() -> void:
	var engine := RulesEngineScript.new()
	var outer := ScopeScript.new("outer", null, "", {"can_x": "PREDICATE_GATED"})
	var inner := ScopeScript.new("inner", null, "", {"can_x": "TOP_WINS"})
	engine.register_rule("can_x", "TOP_WINS", false)
	var result := engine.evaluate("can_x", {}, [outer, inner])
	_assert_eq(result["allow"], true, "TOP_WINS: innermost (last pushed) scope decides")


func _test_bottom_wins_uses_outermost() -> void:
	var engine := RulesEngineScript.new()
	var outer := ScopeScript.new("outer", null, "", {"can_x": "TOP_WINS"})
	var inner := ScopeScript.new("inner", null, "", {"can_x": "PREDICATE_GATED"})
	engine.register_rule("can_x", "BOTTOM_WINS", false)
	var result := engine.evaluate("can_x", {}, [outer, inner])
	_assert_eq(result["allow"], true, "BOTTOM_WINS: outermost (first pushed) scope decides")


func _test_predicate_gated_invokes_predicate() -> void:
	var engine := RulesEngineScript.new()
	engine.register_rule("pred_allow", "PREDICATE_GATED", false, func(_action, _context): return true)
	var allow := engine.evaluate("pred_allow", {"k": 1}, [])
	_assert_eq(allow["allow"], true, "PREDICATE_GATED: predicate true allows")

	var engine_deny := RulesEngineScript.new()
	engine_deny.register_rule("pred_deny", "PREDICATE_GATED", true, func(_action, _context): return false)
	var deny := engine_deny.evaluate("pred_deny", {}, [])
	_assert_eq(deny["allow"], false, "PREDICATE_GATED: predicate false denies (overrides default_allow)")


func _test_register_rule_excludes_predicate_from_payload() -> void:
	var engine := RulesEngineScript.new()
	engine.register_rule("pred_rule", "PREDICATE_GATED", true, func(_action, _context): return true)
	var rule := engine.get_rule("pred_rule")
	_assert(not rule.has("predicate"), "register_rule does not store a predicate descriptor in the rule payload")


func _test_canonical_bytes_deterministic() -> void:
	var schema := RulesSchemaScript.new()
	var value := {"rule_id": "test", "resolution": "TOP_WINS", "default_allow": true}
	var first := schema._to_canonical_bytes(value)
	var second := schema._to_canonical_bytes(value)
	_assert_eq(first, second, "same input produces identical canonical bytes")


func _test_schema_validate() -> void:
	var schema := RulesSchemaScript.new()
	var valid := {"rule_id": "test_rule", "resolution": "TOP_WINS", "default_allow": true}
	_assert(schema._validate(valid) == true, "valid rule passes validation")
	var missing := {"rule_id": "", "resolution": "TOP_WINS", "default_allow": true}
	_assert(schema._validate(missing) == false, "empty rule_id fails validation")
	var bad_res := {"rule_id": "test", "resolution": "UNKNOWN", "default_allow": true}
	_assert(schema._validate(bad_res) == false, "unknown resolution fails validation")
	var bad_allow := {"rule_id": "test", "resolution": "TOP_WINS", "default_allow": "yes"}
	_assert(schema._validate(bad_allow) == false, "non-bool default_allow fails validation")


func _test_schema_display() -> void:
	var schema := RulesSchemaScript.new()
	var value := {"rule_id": "build_zone", "resolution": "BOTTOM_WINS", "default_allow": false}
	var display := schema._to_display(value)
	_assert_eq(display, "[BOTTOM_WINS] build_zone (allow=false)", "display format matches spec")


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
		print("  [FAIL] %s" % label)
