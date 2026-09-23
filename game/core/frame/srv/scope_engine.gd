## Ported from vant axolotl lib/brain.js
extends RefCounted

const ScopeScript = preload("res://core/frame/srv/scope.gd")

const TOP_WINS = "TOP_WINS"
const BOTTOM_WINS = "BOTTOM_WINS"
const PREDICATE_GATED = "PREDICATE_GATED"
const ALL_WINS_WITH_EFFECT = "ALL_WINS_WITH_EFFECT"

var _root: Object = null
var _scopes: Dictionary = {}
var _stacks: Dictionary = {}

func load_hierarchy(path: String) -> bool:
	var hierarchy: Object = ResourceLoader.load(path)
	if not hierarchy:
		push_error("ScopeEngine: Failed to load hierarchy from '%s'" % path)
		return false

	var errors = hierarchy._validate()
	if errors.size() > 0:
		for err in errors:
			push_error("ScopeEngine: Hierarchy validation failed: %s" % err)
		return false

	var base_dir = path.get_base_dir()
	var env_errors = hierarchy._check_environment_paths(base_dir)
	if env_errors.size() > 0:
		for err in env_errors:
			push_error("ScopeEngine: %s" % err)
		return false

	_scopes.clear()
	_root = null

	var root_node = null
	for node in hierarchy.nodes:
		if node.parent_name == "":
			root_node = node
			break

	if not root_node:
		push_error("ScopeEngine: No root node found in hierarchy")
		return false

	_root = ScopeScript.new(root_node.name, null, root_node.environment_path, root_node.rules_overrides)
	_scopes[root_node.name] = _root

	var built = {root_node.name: true}
	var changed = true
	while changed:
		changed = false
		for node in hierarchy.nodes:
			if node.name in built:
				continue
			if node.parent_name in built:
				var parent_scope = _scopes[node.parent_name]
				var scope = ScopeScript.new(node.name, parent_scope, node.environment_path, node.rules_overrides)
				_scopes[node.name] = scope
				built[node.name] = true
				changed = true

	if built.size() != hierarchy.nodes.size():
		push_error("ScopeEngine: Failed to build all scopes (missing parents or cycles)")
		return false

	_stacks.clear()
	return true

func get_root() -> Scope:
	return _root

func get_scope(name: String) -> Scope:
	return _scopes.get(name, null)

func push(player_id: String, scope_name: String) -> bool:
	var scope = _scopes.get(scope_name)
	if not scope:
		push_error("ScopeEngine: Scope '%s' not found for player '%s'" % [scope_name, player_id])
		return false

	if not _stacks.has(player_id):
		_stacks[player_id] = []

	_stacks[player_id].append(scope)
	return true

func pop(player_id: String) -> bool:
	if not _stacks.has(player_id):
		return false

	var stack = _stacks[player_id]
	if stack.is_empty():
		return false

	stack.pop_back()
	if stack.is_empty():
		_stacks.erase(player_id)
	return true

## 4.7.2 strictness: "get_stack" collides with a native 0-arg Object method,
## so the member must carry a non-colliding name (see lru_cache.gd, t3.gd).
func get_stack_for_player(player_id: String) -> Array[ScopeScript]:
	var result: Array[ScopeScript] = []
	if not _stacks.has(player_id):
		return result
	# _stacks holds untyped Arrays; duplicate() alone would return a plain
	# Array and fail the declared Array[ScopeScript] return type.
	for scope in _stacks[player_id]:
		result.append(scope)
	return result

func resolve_rule(player_id: String, rule_id: String, default_resolution: String) -> String:
	var stack = get_stack_for_player(player_id)
	for scope in stack:
		var override = scope.get_override(rule_id)
		if override != "":
			return override
	return default_resolution

func _get_stack_depth(player_id: String) -> int:
	var stack = _stacks.get(player_id)
	return stack.size() if stack else 0

func clear_player_stack(player_id: String) -> void:
	_stacks.erase(player_id)
