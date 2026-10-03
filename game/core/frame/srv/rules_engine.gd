## RulesEngine -- evaluates actions against a rules tree using scope overrides.
##
## Specification: labs/world-building-arch.md В§5.1-5.3
## Architecture: labs/world-building-arch.md В§10 (data flow / tick model)
##
## Wraps a T3 instance as the rules tree. Each rule is a node keyed by
## action name. Scope overrides flip resolution strategies per-rule.
## Ported from vant axolotl lib/brain.js (rules portion)
extends RefCounted

const T3Script = preload("res://core/frame/kv/t3.gd")
const RulesSchemaScript = preload("res://core/frame/srv/rules_schema.gd")
const ScopeEngineScript = preload("res://core/frame/srv/scope_engine.gd")

const TOP_WINS := "TOP_WINS"
const BOTTOM_WINS := "BOTTOM_WINS"
const PREDICATE_GATED := "PREDICATE_GATED"
const ALL_WINS_WITH_EFFECT := "ALL_WINS_WITH_EFFECT"

var _rules_tree: Object = null
var _scope_engine: ScopeEngineScript = null
var _schema: Object = null

## Predicates live OUTSIDE the T3 content tree (audit round 17).
## A rule's predicate is runtime behavior, not content-addressed data:
## storing it in the node payload forced register_rule to write
## str(predicate) (a non-invokable descriptor like "<anonymous
## lambda>(lambda)") into the tree, and a real Callable in the payload
## would break var_to_bytes/bytes_to_var round-trips in diff/apply_diff.
## Keyed by rule_id; an invalid predicate on re-register drops the old one.
var _predicates: Dictionary = {}

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
	# The predicate is held on the engine, not in the tree payload; the
	# payload stays portable (no Callable, no str(callable) descriptor).
	if predicate.is_valid():
		_predicates[rule_id] = predicate
	else:
		_predicates.erase(rule_id)
	return _rules_tree.insert(rule_id, value, _schema)


func evaluate(action: String, context: Dictionary, stack: Array, player_id: String = "") -> Dictionary:
	var rule_value = get_rule(action)
	if rule_value.is_empty():
		return {
			"allow": false,
			"reason": "no rule registered for action: %s" % action,
			"modified_action": {},
			"applied_rules": []
		}

	var resolution: String = rule_value.get("resolution", TOP_WINS)
	var default_allow: bool = rule_value.get("default_allow", true)
	var predicate: Callable = _predicates.get(action, Callable())

	if _scope_engine != null and _scope_engine.has_method("resolve_rule"):
		var resolved: String = _scope_engine.resolve_rule(player_id, action, resolution)
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
			allow = _evaluate_predicate_gated(default_allow, predicate, action, context)
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
	var value = _rules_tree.get_at(rule_id)
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


## Stack convention (audit round 17, see ScopeEngine): push() appends, so
## stack[0] is the FIRST scope pushed (root/outermost, the BOTTOM of the
## stack) and stack[stack.size() - 1] is the LAST scope pushed
## (player/innermost, the TOP of the stack).
##   TOP_WINS    -> the innermost scope decides (player's setting wins)
##   BOTTOM_WINS -> the outermost scope decides (world/root rule wins)
## This matches the spec (prd-scope-engine.md US-006: under BOTTOM_WINS
## the world's rule overrides the player's; under TOP_WINS the player's
## setting wins) and the reason strings below.
func _evaluate_top_wins(stack: Array, action: String, context: Dictionary) -> bool:
	if stack.is_empty():
		return _default_allow_for(action)
	var top_scope = stack[stack.size() - 1]
	var override := _scope_override(top_scope, action)
	if override != "":
		return _override_allows(override)
	return _default_allow_for(action)


func _evaluate_bottom_wins(stack: Array, action: String, context: Dictionary) -> bool:
	if stack.is_empty():
		return _default_allow_for(action)
	var bottom_scope = stack[0]
	var override := _scope_override(bottom_scope, action)
	if override != "":
		return _override_allows(override)
	return _default_allow_for(action)


## Evaluate the registered predicate. The predicate is invoked with
## (action, context) and must return a bool; an invalid predicate or a
## non-bool result falls back to default_allow.
func _evaluate_predicate_gated(default_allow: bool, predicate: Callable, action: String, context: Dictionary) -> bool:
	if not predicate.is_valid():
		return default_allow
	var result = predicate.call(action, context)
	if typeof(result) == TYPE_BOOL:
		return result
	push_warning("RulesEngine: predicate for action '%s' returned %s, not bool; using default_allow" % [action, type_string(typeof(result))])
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
