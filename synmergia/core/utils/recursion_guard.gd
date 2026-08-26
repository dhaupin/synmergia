## RecursionGuard - Prevents stack overflow from unbounded recursion
## Tracks call depth per context and enforces maximum depth limits
class_name RecursionGuard
extends RefCounted

## Call stack tracking: context -> depth
var _depth_tracker: Dictionary = {}

## Maximum depth per context
var _max_depth_config: Dictionary = {}

## Default maximum depth
var _default_max_depth: int

## Statistics
var _total_guards_triggered: int = 0
var _guard_trigger_counts: Dictionary = {}

## ============================================================================
## LIFECYCLE
## ============================================================================

func _init(default_max_depth: int = -1) -> void:
	if default_max_depth < 0:
		_default_max_depth = GameConfig.QoS.Recursion.DEFAULT_MAX_DEPTH
	else:
		_default_max_depth = default_max_depth
	
	Logger.debug("RecursionGuard: Initialized with default max depth=%d" % _default_max_depth)

## ============================================================================
## GUARD ENTER/EXIT
## ============================================================================

## Attempt to enter a recursive context
## Returns true if entry is allowed, false if max depth exceeded
func enter(context: String) -> bool:
	var max_depth = _max_depth_config.get(context, _default_max_depth)
	var current_depth = _depth_tracker.get(context, 0)
	
	if current_depth >= max_depth:
		_total_guards_triggered += 1
		_guard_trigger_counts[context] = _guard_trigger_counts.get(context, 0) + 1
		Logger.warn("RecursionGuard: Max depth %d exceeded for context '%s' (current: %d)" % [
			max_depth, context, current_depth
		])
		return false
	
	_depth_tracker[context] = current_depth + 1
	return true

## Exit a recursive context (call at end of function)
func exit(context: String) -> void:
	var current_depth = _depth_tracker.get(context, 0)
	if current_depth > 0:
		_depth_tracker[context] = current_depth - 1
	else:
		_depth_tracker.erase(context)

## Execute a callable with recursion protection
## Returns the result or null if max depth exceeded
func execute(context: String, callable: Callable, default_result: Variant = null) -> Variant:
	if not enter(context):
		return default_result
	
	var result = callable.call()
	exit(context)
	return result

## ============================================================================
## CONFIGURATION
## ============================================================================

## Set maximum depth for a specific context
func set_max_depth(context: String, max_depth: int) -> void:
	_max_depth_config[context] = max_depth
	Logger.debug("RecursionGuard: Set max depth for '%s' to %d" % [context, max_depth])

## Remove custom max depth for a context (reverts to default)
func clear_max_depth(context: String) -> void:
	_max_depth_config.erase(context)

## Set the default maximum depth for all contexts
func set_default_max_depth(max_depth: int) -> void:
	_default_max_depth = max_depth

## ============================================================================
## INSPECTION
## ============================================================================

## Get current depth for a context
func get_depth(context: String) -> int:
	return _depth_tracker.get(context, 0)

## Get max depth for a context
func get_max_depth(context: String) -> int:
	return _max_depth_config.get(context, _default_max_depth)

## Check if currently in a recursive call
func is_in_context(context: String) -> bool:
	return _depth_tracker.get(context, 0) > 0

## Get all current contexts and depths
func get_all_depths() -> Dictionary:
	return _depth_tracker.duplicate(true)

## Get statistics
func get_stats() -> Dictionary:
	return {
		"total_guards_triggered": _total_guards_triggered,
		"guard_trigger_counts": _guard_trigger_counts.duplicate(true),
		"default_max_depth": _default_max_depth,
		"active_contexts": _depth_tracker.keys(),
		"total_active_depth": _depth_tracker.values().reduce(func(a, b): return a + b, 0)
	}

## Reset statistics
func reset_stats() -> void:
	_total_guards_triggered = 0
	_guard_trigger_counts.clear()
	Logger.debug("RecursionGuard: Statistics reset")

## ============================================================================
## STATIC HELPERS
## ============================================================================

## Create a guard with preset configurations
static func create_entity_guard() -> RecursionGuard:
	var guard = RecursionGuard.new(GameConfig.QoS.Recursion.ENTITY_TREE_MAX_DEPTH)
	guard.set_max_depth("entity_tree", GameConfig.QoS.Recursion.ENTITY_TREE_MAX_DEPTH)
	guard.set_max_depth("get_children_recursive", GameConfig.QoS.Recursion.ENTITY_TREE_MAX_DEPTH)
	guard.set_max_depth("get_all_entities_recursive", GameConfig.QoS.Recursion.ENTITY_TREE_MAX_DEPTH)
	return guard

static func create_zone_guard() -> RecursionGuard:
	var guard = RecursionGuard.new(GameConfig.QoS.Recursion.ZONE_NEIGHBOR_MAX_DEPTH)
	guard.set_max_depth("zone_neighbors", GameConfig.QoS.Recursion.ZONE_NEIGHBOR_MAX_DEPTH)
	guard.set_max_depth("get_neighbor_zones_recursive", GameConfig.QoS.Recursion.ZONE_NEIGHBOR_MAX_DEPTH)
	return guard

static func create_aura_guard() -> RecursionGuard:
	var guard = RecursionGuard.new(GameConfig.QoS.Recursion.AURA_CHAIN_MAX_DEPTH)
	guard.set_max_depth("aura_chain", GameConfig.QoS.Recursion.AURA_CHAIN_MAX_DEPTH)
	guard.set_max_depth("apply_effects_recursive", GameConfig.QoS.Recursion.AURA_CHAIN_MAX_DEPTH)
	return guard

## ============================================================================
## LAMBDA WRAPPER
## ============================================================================

## Wrap a recursive function with recursion protection
## Usage: var safe_func = recursion_guard.wrap("my_func", my_func)
func wrap(context: String, func_callable: Callable, default_result: Variant = null) -> Callable:
	return func() -> Variant:
		return execute(context, func_callable, default_result)
