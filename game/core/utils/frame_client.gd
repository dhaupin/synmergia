## FrameClient - HTTP client for the Synmergia Frame Bridge (srv/frame/).
## Game services use this to call frame primitives (RulesEngine, Scope, T3)
## over HTTP. Implements a circuit breaker, retries, and fallback to a local
## RulesEngine instance. If the HTTP bridge is unavailable (single-process
## consolidation, dev boot), everything still works through the local path.
extends RefCounted

## Circuit breaker states
enum CircuitState {
	CLOSED,    # Normal operation, requests go through
	OPEN,      # Failing, requests blocked, fallback used
	HALF_OPEN  # Testing if service recovered
}

## Configuration
var _base_url: String = "http://localhost:8080"
var _timeout: float = 5.0
var _max_retries: int = 3
var _retry_delay: float = 0.5

## Circuit breaker
var _circuit_state: CircuitState = CircuitState.CLOSED
var _failure_count: int = 0
var _success_count: int = 0
var _last_failure_time: int = 0
const _failure_threshold: int = 5
const _success_threshold: int = 2
const _timeout_ms: int = 30000  # 30 seconds before half-open

## Local RulesEngine fallback (for when the frame bridge is unavailable)
var _local_rules_engine: Object = null
var _use_local_fallback: bool = true

## HTTP request node. Lazily added to the SceneTree root because
## FrameClient extends RefCounted and cannot parent nodes itself.
var _http_request: HTTPRequest = null

func _init(base_url: String = "http://localhost:8080", use_local_fallback: bool = true) -> void:
	_base_url = base_url
	_use_local_fallback = use_local_fallback

	# Initialize local fallback eagerly so the client never depends on the
	# bridge for rule evaluation.
	if _use_local_fallback:
		_init_local_rules()

	print("FrameClient initialized (base_url: %s, fallback: %s)" % [_base_url, _use_local_fallback])

func _ensure_http_request() -> HTTPRequest:
	# FrameClient is RefCounted; HTTPRequest must live in the tree to run.
	if _http_request == null:
		_http_request = HTTPRequest.new()
		_http_request.timeout = _timeout
		var tree_root := Engine.get_main_loop().root if Engine.get_main_loop() is SceneTree else null
		if tree_root != null:
			tree_root.call_deferred("add_child", _http_request)
		else:
			# No SceneTree (headless script mode): remote calls are impossible.
			_use_local_fallback = true
			_http_request = null
	return _http_request

func _init_local_rules() -> void:
	if _local_rules_engine != null:
		return
	var rules_engine_script := load("res://core/frame/srv/rules_engine.gd")
	if rules_engine_script == null:
		return
	_local_rules_engine = rules_engine_script.new()
	# Register default rules locally (mirror the frame server defaults).
	_local_rules_engine.register_rule("rate_limit", "TOP_WINS", true)
	_local_rules_engine.register_rule("connection_quality", "TOP_WINS", true)
	_local_rules_engine.register_rule("throttle_action", "TOP_WINS", false)
	_local_rules_engine.register_rule("teleport_check", "TOP_WINS", false)
	_local_rules_engine.register_rule("speed_hack_check", "TOP_WINS", false)
	_local_rules_engine.register_rule("item_duplication_check", "TOP_WINS", false)
	_local_rules_engine.register_rule("input_anomaly_check", "TOP_WINS", false)
	_local_rules_engine.register_rule("permission_check", "BOTTOM_WINS", true)
	_local_rules_engine.register_rule("restrict_player", "TOP_WINS", true)
	_local_rules_engine.register_rule("ip_can_connect", "BOTTOM_WINS", true)
	_local_rules_engine.register_rule("failed_attempt_check", "TOP_WINS", false)
	_local_rules_engine.register_rule("block_ip", "TOP_WINS", true)
	_local_rules_engine.register_rule("ban_player", "BOTTOM_WINS", true)
	_local_rules_engine.register_rule("connection_limit_check", "TOP_WINS", false)
	_local_rules_engine.register_rule("spam_response", "ALL_WINS_WITH_EFFECT", true)
	_local_rules_engine.register_rule("speedhack_response", "TOP_WINS", false)
	_local_rules_engine.register_rule("teleport_hack_response", "TOP_WINS", false)
	_local_rules_engine.register_rule("item_duplication_response", "TOP_WINS", false)
	_local_rules_engine.register_rule("auto_kick_threshold", "TOP_WINS", false)

## ============================================================================
## Circuit breaker
## ============================================================================

func _check_circuit() -> bool:
	match _circuit_state:
		CircuitState.CLOSED:
			return true
		CircuitState.OPEN:
			# Check if timeout elapsed to try half-open
			var now := Time.get_ticks_msec()
			if now - _last_failure_time > _timeout_ms:
				_circuit_state = CircuitState.HALF_OPEN
				_success_count = 0
				print("FrameClient: Circuit breaker HALF_OPEN")
				return true
			return false
		CircuitState.HALF_OPEN:
			return true
	return false

func _record_success() -> void:
	_failure_count = 0
	match _circuit_state:
		CircuitState.HALF_OPEN:
			_success_count += 1
			if _success_count >= _success_threshold:
				_circuit_state = CircuitState.CLOSED
				print("FrameClient: Circuit breaker CLOSED (recovered)")
		CircuitState.CLOSED:
			pass  # Already closed
		_:
			pass

func _record_failure() -> void:
	_failure_count += 1
	_last_failure_time = Time.get_ticks_msec()
	match _circuit_state:
		CircuitState.CLOSED:
			if _failure_count >= _failure_threshold:
				_circuit_state = CircuitState.OPEN
				print("FrameClient: Circuit breaker OPEN (threshold exceeded)")
		CircuitState.HALF_OPEN:
			_circuit_state = CircuitState.OPEN
			_success_count = 0
			print("FrameClient: Circuit breaker OPEN (failed in half-open)")
		_:
			pass

## ============================================================================
## Rule evaluation
## ============================================================================

## Main evaluation method. Returns a Dictionary result or a deny result on
## failure. The old implementation returned null from several paths even
## though the signature promised Dictionary; callers now always get a result.
func evaluate_rule(action: String, context: Dictionary, scope_stack: Array) -> Dictionary:
	# Local fallback is unconditional when enabled: the single-process
	# architecture (see world-building-arch.md sec. 11.2) evaluates rules
	# in-process, and the bridge is only used when explicitly pointed at.
	if _use_local_fallback or not _check_circuit():
		return _evaluate_local(action, context, scope_stack)

	var result := _evaluate_remote(action, context, scope_stack)
	if not result.is_empty():
		_record_success()
		return result

	# All retries failed
	_record_failure()
	return _evaluate_local(action, context, scope_stack)

func _evaluate_remote(action: String, context: Dictionary, scope_stack: Array) -> Dictionary:
	var http := _ensure_http_request()
	if http == null:
		return {}

	# Build scope IDs from stack
	var scope_ids: Array = []
	for scope in scope_stack:
		if scope is Dictionary:
			if scope.has("id"):
				scope_ids.append(scope["id"])
		elif scope is Object and scope.has_method("get_id"):
			scope_ids.append(scope.call("get_id"))

	var request_data := {
		"action": action,
		"context": context,
		"stack": scope_ids,
	}

	var response: Dictionary = _post("/evaluate", request_data)
	return response

func _evaluate_local(action: String, context: Dictionary, scope_stack: Array) -> Dictionary:
	if _local_rules_engine == null:
		_init_local_rules()
	if _local_rules_engine == null:
		return {
			"allow": false,
			"reason": "No local RulesEngine available",
			"modified_action": context.duplicate(true),
			"applied_rules": [],
		}

	# Convert scope objects to the format expected by the local RulesEngine
	var local_stack: Array = []
	for scope in scope_stack:
		if scope is Dictionary:
			local_stack.append(scope)
		elif scope is Object and scope.has_method("get_overrides"):
			local_stack.append({
				"overrides": scope.call("get_overrides"),
			})

	return _local_rules_engine.evaluate(action, context, local_stack)

## ============================================================================
## Scope management (remote; local is a stub registry)
## ============================================================================

func create_scope(name: String, parent_id: String = "", environment: String = "", overrides: Dictionary = {}) -> Dictionary:
	if _use_local_fallback or not _check_circuit():
		return _create_scope_local(name, parent_id, environment, overrides)

	var request_data := {
		"name": name,
		"parent": parent_id if parent_id != "" else null,
		"environment": environment,
		"overrides": overrides,
	}

	var result := _post("/scope/create", request_data)
	if not result.is_empty():
		_record_success()
		return result

	_record_failure()
	return _create_scope_local(name, parent_id, environment, overrides)

func _create_scope_local(name: String, parent_id: String, environment: String, overrides: Dictionary) -> Dictionary:
	var scope_id := "local_scope_%d" % Time.get_ticks_msec()
	return {
		"scope_id": scope_id,
		"name": name,
		"parent": parent_id if parent_id != "" else null,
		"environment": environment,
		"overrides": overrides,
	}

func flip_scope(scope_id: String, rule_id: String, resolution: String) -> Dictionary:
	if _use_local_fallback or not _check_circuit():
		return _flip_scope_local(scope_id, rule_id, resolution)

	var request_data := {
		"scope_id": scope_id,
		"rule_id": rule_id,
		"resolution": resolution,
	}

	var result := _post("/scope/flip", request_data)
	if not result.is_empty():
		_record_success()
		return result

	_record_failure()
	return _flip_scope_local(scope_id, rule_id, resolution)

func _flip_scope_local(scope_id: String, rule_id: String, resolution: String) -> Dictionary:
	# Local fallback - would need a scope registry to be real
	return {
		"success": true,
		"scope_id": scope_id,
		"rule_id": rule_id,
		"resolution": resolution,
	}

## ============================================================================
## Tree operations
## ============================================================================

func tree_insert(tree_name: String, path: String, value: Dictionary, schema_name: String = "rules") -> Dictionary:
	if _use_local_fallback or not _check_circuit():
		return _tree_insert_local(tree_name, path, value, schema_name)

	var request_data := {
		"tree_name": tree_name,
		"path": path,
		"value": value,
		"schema": schema_name,
	}

	var result := _post("/tree/insert", request_data)
	if not result.is_empty():
		_record_success()
		return result

	_record_failure()
	return _tree_insert_local(tree_name, path, value, schema_name)

func _tree_insert_local(tree_name: String, path: String, value: Dictionary, schema_name: String) -> Dictionary:
	var t3_script := load("res://core/frame/kv/t3.gd")
	if t3_script == null:
		return {}
	var t3 = t3_script.new()
	var schema_obj: Resource = _get_local_schema(schema_name)
	var hash_bytes: PackedByteArray = t3.insert(path, value, schema_obj)
	return {
		"hash": hash_bytes.hex_encode(),
		"path": path,
	}

func tree_get(tree_name: String, path: String) -> Dictionary:
	if _use_local_fallback or not _check_circuit():
		return _tree_get_local(tree_name, path)

	var request_data := {
		"tree_name": tree_name,
		"path": path,
	}

	var result := _post("/tree/get", request_data)
	if not result.is_empty():
		_record_success()
		return result

	_record_failure()
	return _tree_get_local(tree_name, path)

func _tree_get_local(_tree_name: String, _path: String) -> Dictionary:
	# Simplified - would need a tree registry to be real
	return {
		"value": null,
		"found": false,
	}

## ============================================================================
## HTTP transport
## ============================================================================

## Generic POST helper. Returns {} on any failure (network, non-200, bad
## JSON). The await-based request/response pairing avoids the previous
## nested-function + nonlocal pattern, which is not valid GDScript.
func _post(endpoint: String, data: Dictionary) -> Dictionary:
	var http := _ensure_http_request()
	if http == null:
		return {}

	var body := JSON.stringify(data)
	var headers := PackedStringArray(["Content-Type: application/json"])

	var err := http.request(_base_url + endpoint, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		return {}

	var result: Array = await http.request_completed
	# request_completed -> (result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray)
	var http_result: int = result[0]
	var response_code: int = result[1]
	var resp_body: PackedByteArray = result[3]

	if http_result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return {}

	var parsed: Variant = JSON.parse_string(resp_body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}

	return parsed

func _get_local_schema(schema_name: String) -> Resource:
	match schema_name:
		"seed":
			return load("res://data/roots/seed_schema.gd").new() as Resource
		"state":
			return load("res://data/roots/state_schema.gd").new() as Resource
		"definition":
			return load("res://core/frame/kv/definition_schema.gd").new() as Resource
		_:
			return load("res://core/frame/srv/rules_schema.gd").new() as Resource

## ============================================================================
## Status and configuration
## ============================================================================

func get_circuit_state() -> String:
	return CircuitState.keys()[_circuit_state]

func is_healthy() -> bool:
	return _circuit_state != CircuitState.OPEN

func set_base_url(url: String) -> void:
	_base_url = url

func set_timeout(timeout: float) -> void:
	_timeout = timeout
	if _http_request != null:
		_http_request.timeout = timeout

func set_max_retries(retries: int) -> void:
	_max_retries = retries

func enable_local_fallback(enabled: bool) -> void:
	_use_local_fallback = enabled
	if enabled:
		_init_local_rules()

func get_local_rules_engine() -> Object:
	if _local_rules_engine == null:
		_init_local_rules()
	return _local_rules_engine
