## ShardParameters - Shard-level parameter writes with critical/non-critical paths
##
## Registered as the `ShardParameters` autoload.
##
## Criticality is CONFIG-TIME: each parameter's `critical` flag lives in
## its ShardParameterDefinition .tres. ShardParameters.set reads the flag
## from the definition and either applies immediately (critical) or queues
## for the 5-minute coalesce window (non-critical). There is no runtime
## setter for criticality -- a player cannot escalate a non-critical
## parameter to critical (see labs/prd-critical-params.md US-005).
##
## State tree integration: writes apply by calling
##   state_tree.insert("/shards/<shard_id>/parameters/<param_name>", value, schema)
## on the shard's state tree (game/core/frame/kv/state_tree.gd).

extends Node

## Emitted whenever a parameter value is actually applied to a state tree
## (both critical and flushed non-critical).
signal param_applied(shard_id: String, param_name: String, value: Variant, actor_id: String)

## Coalesce window for non-critical parameters: 5 minutes (300,000 ms).
const COALESCE_WINDOW_MS: int = 300000

## Parameter definitions (.tres files under game/data/roots/world/parameters/).
const ShardParameterDefinitionScript = preload("res://core/schemas/shard_parameter_definition.gd")

## State tree wrapper (game/core/frame/kv/state_tree.gd). Loaded at runtime
## to avoid a parse-time dependency on the frame primitive.
const T3Script = preload("res://core/frame/kv/t3.gd")
const StateTreeScript = preload("res://core/frame/kv/state_tree.gd")

## Per-shard state trees: shard_id -> StateTree wrapper
var _state_trees: Dictionary = {}

## Per-shard coalesce queues: shard_id -> { param_name -> {value, actor_id} }
var _queues: Dictionary = {}

## Per-shard coalesce timers: shard_id -> Timer
var _timers: Dictionary = {}

## Path prefix under which shard parameters live in the state tree.
const _PARAM_PATH_PREFIX := "shards"

## Path prefix for the parameter definitions on disk.
const _DEFINITION_DIR := "res://data/roots/world/parameters/"

## Cache of loaded definitions: param_name -> ShardParameterDefinition
var _definitions: Dictionary = {}


func _ready() -> void:
	load_definitions()


## Load every ShardParameterDefinition .tres under the parameters dir.
## Definitions are cached by param_name for O(1) lookup in set().
func load_definitions() -> void:
	_definitions = {}
	var dir := DirAccess.open(_DEFINITION_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		if entry.ends_with(".tres"):
			var res = load(_DEFINITION_DIR + entry)
			if res is ShardParameterDefinitionScript:
				_definitions[res.name] = res
		entry = dir.get_next()
	dir.list_dir_end()


## Return the definition for a parameter, or null if unknown.
func get_definition(param_name: String) -> ShardParameterDefinitionScript:
	return _definitions.get(param_name)


## Set a shard parameter's value.
##
## Criticality is read from the parameter's .tres definition, never from
## the caller. Critical parameters apply immediately to the shard's state
## tree, log to GameLog at INFO, and emit param_applied. Non-critical
## parameters are queued and applied after the coalesce window.
## The public API is set_param(). It reads criticality from .tres definitions
## and routes to the appropriate apply path. There is no runtime criticality
## setter -- a player cannot escalate a non-critical parameter to critical.
func set_param(shard_id: String, param_name: String, value: Variant, actor_id: String = "") -> void:
	var def := get_definition(param_name)
	if def == null:
		return
	if def.critical:
		_apply_critical(shard_id, param_name, value, actor_id)
	else:
		_apply_non_critical(shard_id, param_name, value, actor_id)


## Apply a critical parameter immediately to the shard's state tree.
func _apply_critical(shard_id: String, param_name: String, value: Variant, actor_id: String) -> void:
	var tree: Variant = _get_state_tree(shard_id)
	if tree == null:
		return
	var path := "%s/%s/parameters/%s" % [_PARAM_PATH_PREFIX, shard_id, param_name]
	tree.insert_state(path, shard_id, "other", {"param_name": param_name, "value": value})
	GameLog.info("ShardParameters: critical param applied shard=%s param=%s value=%s actor=%s" % [shard_id, param_name, str(value), actor_id])
	param_applied.emit(shard_id, param_name, value, actor_id)


## Queue a non-critical parameter for the coalesce window.
func _apply_non_critical(shard_id: String, param_name: String, value: Variant, actor_id: String) -> void:
	if not _queues.has(shard_id):
		_queues[shard_id] = {}
	var queue: Dictionary = _queues[shard_id]
	queue[param_name] = {"value": value, "actor_id": actor_id}
	# Latest write wins within the window.
	if not _timers.has(shard_id):
		var timer := Timer.new()
		timer.name = "ShardParametersCoalesce_%s" % shard_id
		timer.wait_time = float(COALESCE_WINDOW_MS) / 1000.0
		timer.one_shot = true
		timer.timeout.connect(_on_coalesce_timeout.bind(shard_id))
		add_child(timer)
		_timers[shard_id] = timer
		timer.start()


## Force all queued non-critical parameters on a shard to apply now.
func flush(shard_id: String) -> void:
	if not _timers.has(shard_id):
		return
	var timer: Timer = _timers[shard_id]
	timer.stop()
	_apply_queue(shard_id)
	timer.queue_free()
	_timers.erase(shard_id)


## Apply every queued parameter for a shard and clear the queue.
func _apply_queue(shard_id: String) -> void:
	if not _queues.has(shard_id):
		return
	var queue: Dictionary = _queues[shard_id]
	var tree: Variant = _get_state_tree(shard_id)
	if tree == null:
		_queues.erase(shard_id)
		return
	for param_name in queue.keys():
		var entry: Dictionary = queue[param_name]
		var value: Variant = entry["value"]
		var actor_id: String = entry["actor_id"]
		var path := "%s/%s/parameters/%s" % [_PARAM_PATH_PREFIX, shard_id, param_name]
		tree.insert_state(path, shard_id, "other", {"param_name": param_name, "value": value})
		param_applied.emit(shard_id, param_name, value, actor_id)
	_queues.erase(shard_id)


## Timer callback: apply the queued parameters for a shard.
func _on_coalesce_timeout(shard_id: String) -> void:
	_apply_queue(shard_id)
	_timers.erase(shard_id)


## Lazily build (or return) the StateTree wrapper for a shard.
func _get_state_tree(shard_id: String) -> Variant:
	if _state_trees.has(shard_id):
		return _state_trees[shard_id]
	var t3: Variant = T3Script.new()
	var wrapper = StateTreeScript.new(t3)
	_state_trees[shard_id] = wrapper
	return wrapper


## Set the state tree implementation for a shard (used by tests/world boot).
func set_state_tree(shard_id: String, tree) -> void:
	_state_trees[shard_id] = tree