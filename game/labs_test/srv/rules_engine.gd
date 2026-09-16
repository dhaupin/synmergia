## RulesEngine — evaluates actions against a rules tree using scope overrides.
##
## Specification: labs/world-building-arch.md В§5.1-5.3
## Architecture: labs/world-building-arch.md В§10 (data flow / tick model)
##
## Wraps a T3 instance as the rules tree. Each rule is a node keyed by
## action name. Scope overrides flip resolution strategies per-rule.
## Ported from vant axolotl lib/brain.js (rules portion)
extends RefCounted

const T3Script = preload("res://labs/kv/t3.gd")
const RulesSchemaScript = preload("res://labs/srv/rules_schema.gd")
const ScopeEngineScript = preload("res://labs/srv/scope_engine.gd")

const TOP_WINS := "TOP_WINS"
const BOTTOM_WINS := "BOTTOM_WINS"
const PREDICATE_GATED := "PREDICATE_GATED"
const ALL_WINS_WITH_EFFECT := "ALL_WINS_WITH_EFFECT"

var _rules_tree: Object = null
var _scope_engine: ScopeEngine = null
var _schema: Object = null

func _init(scope_engine: Object = null) -> void:
	_rules_tree = T3Script.new()
	_schema = RulesSchemaScript.new()
	if scope_engine != null:
		_scope_engine = scope_engine


func register_rule(rule_id: String, resolution: String = TOP_WINS, default_allow: bool = true, predicate: Callable = Callable()) -> PackedByteArray:
	var value := {
		"rule_id": rule_id,
		"resolution": resolution,
		"default_allow": default_allow
	}
	if predicate.is_valid():
		value["predicate"] = str(predicate)
	return _rules_tree.insert(rule_id, value, _schema)


func evaluate(action: String, context: Dictionary, stack: Array) -> Dictionary:
	var rule_value = get_rule(action)
	if rule_value == null:
		return {
			"allow": false,
			"reason": "no rule registered for action: %s" % action,
			"modified_action": {},
			"applied_rules": []
		}

	var resolution: String = rule_value.get("resolution", TOP_WINS)
	var default_allow: bool = rule_value.get("default_allow", true)
	var predicate_str: String = rule_value.get("predicate", "")

	if _scope_engine != null and _scope_engine.has_method("resolve_rule"):
		var resolved: String = _scope_engine.resolve_rule("", action, resolution)
		if resolved != "":
			resolution = resolved

	var allow := false
	var reason := ""
	var applied_rules: Array = []

	match resolution:
		TOP_WINS:
			allow = _evaluate_top_wins(stack, action, context)
			reason = "TOP_WINS: innermost scope decision"
		BOTTOM_WINS:
			allow = _evaluate_bottom_wins(stack, action, context)
			reason = "BOTTOM_WINS: outermost scope decision"
		PREDICATE_GATED:
			allow = _evaluate_predicate_gated(default_allow, predicate_str, action, context)
			reason = "PREDICATE_GATED: predicate evaluation"
		ALL_WINS_WITH_EFFECT:
			var results := _evaluate_all_wins(stack, action, context)
			allow = results[0]
			applied_rules = results[1]
			reason = "ALL_WINS_WITH_EFFECT: %d rules applied" % applied_rules.size()
		_:
			allow = default_allow
			reason = "UNKNOWN_RESOLUTION: fallback to default_allow"

	var modified_action: Dictionary = context.duplicate(true)

	return {
		"allow": allow,
		"reason": reason,
		"modified_action": modified_action,
		"applied_rules": applied_rules
	}


func get_rule(rule_id: String) -> Dictionary:
	var value = _rules_tree.get(rule_id)
	if value is Dictionary:
		return value
	return {}


func set_override(scope: Object, rule_id: String, resolution: String) -> void:
	if scope != null and scope.has_method("flip"):
		scope.flip(rule_id, resolution)


func root_hash() -> PackedByteArray:
	return _rules_tree.hash_subtree("/")


func diff_rules(old_root: PackedByteArray, new_root: PackedByteArray) -> Array:
	return _rules_tree.diff(old_root, new_root)


func apply_diff(root: PackedByteArray, diff: Array) -> PackedByteArray:
	return _rules_tree.apply_diff(root, diff)


func _evaluate_top_wins(stack: Array, action: String, context: Dictionary) -> bool:
	if stack.is_empty():
		return true
	var top_scope = stack[0]
	var override := _scope_override(top_scope, action)
	if override != "":
		return _override_allows(override)
	return _default_allow_for(action)


func _evaluate_bottom_wins(stack: Array, action: String, context: Dictionary) -> bool:
	if stack.is_empty():
		return true
	var bottom_scope = stack[stack.size() - 1]
	var override := _scope_override(bottom_scope, action)
	if override != "":
		return _override_allows(override)
	return _default_allow_for(action)


func _evaluate_predicate_gated(default_allow: bool, predicate_str: String, action: String, context: Dictionary) -> bool:
	if predicate_str == "":
		return default_allow
	return default_allow


func _evaluate_all_wins(stack: Array, action: String, context: Dictionary) -> Array:
	var any_deny := false
	var any_allow := false
	var applied: Array = []
	for scope in stack:
		var override := _scope_override(scope, action)
		if override != "":
			applied.append(override)
			if _override_allows(override):
				any_allow = true
			else:
				any_deny = true
		else:
			applied.append("default")
			any_allow = true
	return [any_allow and not any_deny, applied]


func _scope_override(scope: Object, rule_id: String) -> String:
	if scope == null:
		return ""
	if scope.has_method("get_override"):
		return scope.get_override(rule_id)
	return ""


func _override_allows(override: String) -> bool:
	match override:
		TOP_WINS, BOTTOM_WINS, ALL_WINS_WITH_EFFECT:
			return true
		PREDICATE_GATED:
			return false
		_:
			return true


func _default_allow_for(action: String) -> bool:
	var rule_value = get_rule(action)
	if rule_value.is_empty():
		return false
	return rule_value.get("default_allow", true)
