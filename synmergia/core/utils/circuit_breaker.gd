## CircuitBreaker - Circuit breaker pattern implementation
## Protects against cascading failures by failing fast when a service is unhealthy
class_name CircuitBreaker
extends RefCounted

## Emitted whenever the breaker changes state. Listeners (admin UI,
## QoS dashboards) can route this into the notification pipeline.
## Carries the previous state for context.
signal state_changed(from: BreakerState, to: BreakerState, breaker_name: String)

## Circuit states
enum BreakerState {
	CLOSED,    ## Normal operation, calls pass through
	OPEN,      ## Fail-fast mode, calls rejected immediately
	HALF_OPEN  ## Probe mode, limited calls allowed
}

## Current state
var _state: BreakerState = BreakerState.CLOSED

## Configuration
var _failure_threshold: int
var _recovery_timeout: float
var _success_threshold: int

## Counters
var _failure_count: int = 0
var _success_count: int = 0
var _last_failure_time: float = 0.0

## Circuit name for logging
var _name: String

## ============================================================================
## LIFECYCLE
## ============================================================================

func _init(
	name: String = "default",
	failure_threshold: int = -1,
	recovery_timeout: float = -1.0,
	success_threshold: int = -1
) -> void:
	_name = name
	
	# Use GameConfig defaults if not specified
	if failure_threshold < 0:
		_failure_threshold = GameConfig.QoS.CircuitBreakerCfg.FAILURE_THRESHOLD
	else:
		_failure_threshold = failure_threshold

	if recovery_timeout < 0.0:
		_recovery_timeout = GameConfig.QoS.CircuitBreakerCfg.RECOVERY_TIMEOUT_SEC
	else:
		_recovery_timeout = recovery_timeout

	if success_threshold < 0:
		_success_threshold = GameConfig.QoS.CircuitBreakerCfg.SUCCESS_THRESHOLD
	else:
		_success_threshold = success_threshold

	pass

## ============================================================================
## EXECUTION
## ============================================================================

## Execute a callable through the circuit breaker
## Returns a Dictionary with 'success', 'data', and 'error' keys
func execute(operation: Callable) -> Dictionary:
	var now = Time.get_ticks_msec() / 1000.0
	
	# Check state transition
	match _state:
		BreakerState.OPEN:
			if now - _last_failure_time >= _recovery_timeout:
				_transition_to_half_open()
			else:
				return {
					"success": false,
					"data": null,
					"error": "Circuit is OPEN",
					"rejected": true
				}
		
		BreakerState.HALF_OPEN:
			# Allow limited calls in half-open state
			pass
		
		BreakerState.CLOSED:
			# Normal operation
			pass
	
	# Execute the operation
	var result = _do_execute(operation)
	
	if result.get("success", false):
		_on_success()
	else:
		_on_failure()
	
	return result

## Execute with async/await support
func execute_async(operation: Callable) -> Dictionary:
	var now = Time.get_ticks_msec() / 1000.0
	
	# Check state transition
	match _state:
		BreakerState.OPEN:
			if now - _last_failure_time >= _recovery_timeout:
				_transition_to_half_open()
			else:
				return {
					"success": false,
					"data": null,
					"error": "Circuit is OPEN",
					"rejected": true
				}
	
	# Execute and await
	var result = await operation.call()
	
	if result is Dictionary:
		if result.get("success", false):
			_on_success()
		else:
			_on_failure()
		return result
	else:
		_on_success()
		return {"success": true, "data": result, "rejected": false}

func _do_execute(operation: Callable) -> Dictionary:
	if not operation.is_valid():
		return {
			"success": false,
			"data": null,
			"error": "Invalid callable"
		}
	
	var result = operation.call()
	
	if result is Dictionary:
		return result
	
	return {
		"success": true,
		"data": result,
		"error": ""
	}

## ============================================================================
## STATE TRANSITIONS
## ============================================================================

func _on_success() -> void:
	match _state:
		BreakerState.HALF_OPEN:
			_success_count += 1
			if _success_count >= _success_threshold:
				_transition_to_closed()
		BreakerState.CLOSED:
			# Reset failure count on success
			_failure_count = 0

func _on_failure() -> void:
	_failure_count += 1
	_last_failure_time = Time.get_ticks_msec() / 1000.0
	
	match _state:
		BreakerState.HALF_OPEN:
			# Any failure in half-open goes back to open
			_transition_to_open()
		BreakerState.CLOSED:
			if _failure_count >= _failure_threshold:
				_transition_to_open()

func _transition_to_open() -> void:
	if _state != BreakerState.OPEN:
		var prev := _state
		_state = BreakerState.OPEN
		_success_count = 0
		state_changed.emit(prev, _state, _name)

func _transition_to_half_open() -> void:
	if _state != BreakerState.HALF_OPEN:
		var prev := _state
		_state = BreakerState.HALF_OPEN
		_success_count = 0
		state_changed.emit(prev, _state, _name)

func _transition_to_closed() -> void:
	if _state != BreakerState.CLOSED:
		var prev := _state
		_state = BreakerState.CLOSED
		_failure_count = 0
		_success_count = 0
		state_changed.emit(prev, _state, _name)

## ============================================================================
## MANUAL CONTROL
## ============================================================================

## Force the circuit to a specific state
func set_state(state: BreakerState) -> void:
	match state:
		BreakerState.CLOSED:
			_transition_to_closed()
		BreakerState.OPEN:
			_transition_to_open()
		BreakerState.HALF_OPEN:
			_transition_to_half_open()

## Reset the circuit to initial state
func reset() -> void:
	_state = BreakerState.CLOSED
	_failure_count = 0
	_success_count = 0
	_last_failure_time = 0.0

## ============================================================================
## INSPECTION
## ============================================================================

## Get current state
func get_state() -> BreakerState:
	return _state

## Get state as string
func get_state_string() -> String:
	return BreakerState.keys()[_state]

## Check if circuit allows execution
func is_closed() -> bool:
	return _state == BreakerState.CLOSED

func is_open() -> bool:
	return _state == BreakerState.OPEN

func is_half_open() -> bool:
	return _state == BreakerState.HALF_OPEN

## Get statistics
func get_stats() -> Dictionary:
	return {
		"name": _name,
		"state": get_state_string(),
		"failure_count": _failure_count,
		"success_count": _success_count,
		"failure_threshold": _failure_threshold,
		"recovery_timeout": _recovery_timeout,
		"success_threshold": _success_threshold,
		"last_failure_time": _last_failure_time,
		"time_until_half_open": maxi(0.0, _recovery_timeout - (Time.get_ticks_msec() / 1000.0 - _last_failure_time)) if _state == BreakerState.OPEN else 0.0
	}

## ============================================================================
## FACTORY
## ============================================================================

## Create a pre-configured circuit breaker
static func create(
	name: String,
	failure_threshold: int = 5,
	recovery_timeout: float = 30.0,
	success_threshold: int = 3
) -> CircuitBreaker:
	return CircuitBreaker.new(name, failure_threshold, recovery_timeout, success_threshold)
