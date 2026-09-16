## FrameClient - HTTP client for Synmergia Frame Bridge
## Game services use this to call frame primitives (RulesEngine, Scope, T3) via HTTP
## Implements circuit breaker, retries, and fallback to local RulesEngine
extends RefCounted

const HTTPRequest = HTTPRequest
const JSON = JSON

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

## Local RulesEngine fallback (for when frame is unavailable)
var _local_rules_engine: Object = null
var _use_local_fallback: bool = true

## HTTP client
var _http_request: HTTPRequest

func _init(base_url: String = "http://localhost:8080", use_local_fallback: bool = true) -> void:
	_base_url = base_url
	_use_local_fallback = use_local_fallback
	
	# Create HTTPRequest node
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	
	# Initialize local fallback
	if _use_local_fallback:
		var RulesEngineScript = preload("res://labs/srv/rules_engine.gd")
		_local_rules_engine = RulesEngineScript.new()
		_init_local_rules()
	
	print("FrameClient initialized (base_url: %s, fallback: %s)" % [_base_url, _use_local_fallback])

func _init_local_rules() -> void:
	# Register default rules locally (mirror frame server)
	if _local_rules_engine:
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

## Circuit breaker logic
func _check_circuit() -> bool:
	match _circuit_state:
		CircuitState.CLOSED:
			return true
		CircuitState.OPEN:
			# Check if timeout elapsed to try half-open
			var now = Time.get_ticks_msec()
			if now - _last_failure_time > _timeout_ms:
				_circuit_state = CircuitState.HALF_OPEN
				_success_count = 0
				print("FrameClient: Circuit breaker HALF_OPEN")
				return true
			return false
		CircuitState.HALF_OPEN:
			return true

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

## Main evaluation method
func evaluate_rule(action: String, context: Dictionary, scope_stack: Array) -> Dictionary:
	# Check circuit breaker
	if not _check_circuit():
		return _evaluate_local(action, context, scope_stack)
	
	# Try frame bridge with retries
	for attempt in range(_max_retries):
		var result = _evaluate_remote(action, context, scope_stack)
		if result != null:
			_record_success()
			return result
		
		# Wait before retry
		if attempt < _max_retries - 1:
			await get_tree().create_timer(_retry_delay).timeout
	
	# All retries failed
	_record_failure()
	return _evaluate_local(action, context, scope_stack)

func _evaluate_remote(action: String, context: Dictionary, scope_stack: Array) -> Dictionary:
	# Build scope IDs from stack
	var scope_ids: Array = []
	for scope in scope_stack:
		if scope and scope.has_method("get_id"):
			scope_ids.append(scope.get_id())
		elif scope and typeof(scope) == TYPE_DICTIONARY and scope.has("id"):
			scope_ids.append(scope["id"])
	
	var request_data = {
		"action": action,
		"context": context,
		"stack": scope_ids
	}
	
	var body = JSON.stringify(request_data)
	var headers = ["Content-Type: application/json"]
	
	# Use a signal to wait for response
	var response_data: Dictionary = {}
	var completed: bool = false
	var error_occurred: bool = false
	
	func _on_response(result, response_code, headers, body):
		nonlocal response_data, completed, error_occurred
		completed = true
		if result != HTTPRequest.RESULT_SUCCESS:
			error_occurred = true
			return
		
		if response_code != 200:
			error_occurred = true
			return
		
		var parse_result = JSON.parse_string(body.get_string_from_utf8())
		if parse_result.error != OK:
			error_occurred = true
			return
		
		response_data = parse_result.result
	
	# Temporarily connect signal
	var callable = _on_response.bind()
	_http_request.request_completed.connect(callable)
	
	var err = _http_request.request(_base_url + "/evaluate", headers, true, HTTPRequest.METHOD_POST, body)
	if err != OK:
		_http_request.request_completed.disconnect(callable)
		return null
	
	# Wait for response (with timeout)
	var timer = get_tree().create_timer(_timeout)
	await timer.timeout
	
	_http_request.request_completed.disconnect(callable)
	
	if not completed or error_occurred:
		return null
	
	return response_data

func _evaluate_local(action: String, context: Dictionary, scope_stack: Array) -> Dictionary:
	if not _local_rules_engine:
		return {
			"allow": false,
			"reason": "No local RulesEngine available",
			"modified_action": context.duplicate(true),
			"applied_rules": []
		}
	
	# Convert scope objects to format expected by local RulesEngine
	var local_stack: Array = []
	for scope in scope_stack:
		if scope and typeof(scope) == TYPE_DICTIONARY:
			local_stack.append(scope)
		elif scope and scope.has_method("get_overrides"):
			local_stack.append({
				"overrides": scope.get_overrides()
			})
	
	return _local_rules_engine.evaluate(action, context, local_stack)

## Scope management
func create_scope(name: String, parent_id: String = "", environment: String = "", overrides: Dictionary = {}) -> Dictionary:
	if not _check_circuit():
		return _create_scope_local(name, parent_id, environment, overrides)
	
	var request_data = {
		"name": name,
		"parent": parent_id if parent_id != "" else null,
		"environment": environment,
		"overrides": overrides
	}
	
	var result = _post("/scope/create", request_data)
	if result:
		_record_success()
		return result
	
	_record_failure()
	return _create_scope_local(name, parent_id, environment, overrides)

func _create_scope_local(name: String, parent_id: String, environment: String, overrides: Dictionary) -> Dictionary:
	var ScopeScript = preload("res://labs/srv/scope.gd")
	var parent = null
	# In local mode, we'd need a scope registry - simplified for now
	var scope = ScopeScript.new(name, parent, environment, overrides)
	var scope_id = "local_scope_%d" % Time.get_ticks_msec()
	return {
		"scope_id": scope_id,
		"name": name,
		"parent": parent_id if parent_id != "" else null
	}

func flip_scope(scope_id: String, rule_id: String, resolution: String) -> Dictionary:
	if not _check_circuit():
		return _flip_scope_local(scope_id, rule_id, resolution)
	
	var request_data = {
		"scope_id": scope_id,
		"rule_id": rule_id,
		"resolution": resolution
	}
	
	var result = _post("/scope/flip", request_data)
	if result:
		_record_success()
		return result
	
	_record_failure()
	return _flip_scope_local(scope_id, rule_id, resolution)

func _flip_scope_local(scope_id: String, rule_id: String, resolution: String) -> Dictionary:
	# Local fallback - would need scope registry
	return {
		"success": true,
		"scope_id": scope_id,
		"rule_id": rule_id,
		"resolution": resolution
	}

## Tree operations
func tree_insert(tree_name: String, path: String, value: Dictionary, schema: String = "rules") -> Dictionary:
	if not _check_circuit():
		return _tree_insert_local(tree_name, path, value, schema)
	
	var request_data = {
		"tree_name": tree_name,
		"path": path,
		"value": value,
		"schema": schema
	}
	
	var result = _post("/tree/insert", request_data)
	if result:
		_record_success()
		return result
	
	_record_failure()
	return _tree_insert_local(tree_name, path, value, schema)

func _tree_insert_local(tree_name: String, path: String, value: Dictionary, schema: String) -> Dictionary:
	var T3Script = preload("res://labs/kv/t3.gd")
	var t3 = T3Script.new()
	
	# Get schema
	var schema_obj = _get_local_schema(schema)
	var hash = t3.insert(path, value, schema_obj)
	return {
		"hash": hash.encode_hex(),
		"path": path
	}

func tree_get(tree_name: String, path: String) -> Dictionary:
	if not _check_circuit():
		return _tree_get_local(tree_name, path)
	
	var request_data = {
		"tree_name": tree_name,
		"path": path
	}
	
	var result = _post("/tree/get", request_data)
	if result:
		_record_success()
		return result
	
	_record_failure()
	return _tree_get_local(tree_name, path)

func _tree_get_local(tree_name: String, path: String) -> Dictionary:
	# Simplified - would need tree registry
	return {
		"value": null,
		"found": false
	}

## Generic POST helper
func _post(endpoint: String, data: Dictionary) -> Dictionary:
	var body = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]
	
	var response_data: Dictionary = {}
	var completed: bool = false
	var error_occurred: bool = false
	
	func _on_response(result, response_code, headers, body):
		nonlocal response_data, completed, error_occurred
		completed = true
		if result != HTTPRequest.RESULT_SUCCESS:
			error_occurred = true
			return
		
		if response_code != 200:
			error_occurred = true
			return
		
		var parse_result = JSON.parse_string(body.get_string_from_utf8())
		if parse_result.error != OK:
			error_occurred = true
			return
		
		response_data = parse_result.result
	
	var callable = _on_response.bind()
	_http_request.request_completed.connect(callable)
	
	var err = _http_request.request(_base_url + endpoint, headers, true, HTTPRequest.METHOD_POST, body)
	if err != OK:
		_http_request.request_completed.disconnect(callable)
		return null
	
	var timer = get_tree().create_timer(_timeout)
	await timer.timeout
	
	_http_request.request_completed.disconnect(callable)
	
	if not completed or error_occurred:
		return null
	
	return response_data

func _get_local_schema(name: String) -> Object:
	match name:
		"rules": return preload("res://labs/srv/rules_schema.gd").new()
		"seed": return preload("res://game/data/roots/seed_schema.gd").new()
		"state": return preload("res://game/data/roots/state_schema.gd").new()
		"definition": return preload("res://labs/kv/definition_schema.gd").new()
		_: return preload("res://labs/srv/rules_schema.gd").new()

## Status and configuration
func get_circuit_state() -> String:
	return CircuitState.keys()[_circuit_state]

func is_healthy() -> bool:
	return _circuit_state != CircuitState.OPEN

func set_base_url(url: String) -> void:
	_base_url = url

func set_timeout(timeout: float) -> void:
	_timeout = timeout

func set_max_retries(retries: int) -> void:
	_max_retries = retries

func enable_local_fallback(enabled: bool) -> void:
	_use_local_fallback = enabled
	if enabled and not _local_rules_engine:
		var RulesEngineScript = preload("res://labs/srv/rules_engine.gd")
		_local_rules_engine = RulesEngineScript.new()
		_init_local_rules()

func get_local_rules_engine() -> Object:
	return _local_rules_engine