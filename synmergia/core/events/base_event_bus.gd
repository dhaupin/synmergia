## BaseEventBus - Abstract base for domain-specific event buses
## Provides common functionality for all event buses
class_name BaseEventBus
extends Node

## Event history for debugging/replays
var _event_history: Array[Dictionary] = []
var _max_history: int = 1000

## Enable/disable event logging
var _logging_enabled: bool = true

## Log an event to history
func _log_event(event_name: String, data: Dictionary = {}) -> void:
	if not _logging_enabled:
		return
	
	var entry := {
		"bus": get_class(),
		"name": event_name,
		"data": data,
		"time": Time.get_ticks_msec()
	}
	_event_history.append(entry)
	
	# Trim history if needed
	if _event_history.size() > _max_history:
		_event_history.pop_front()

## Get recent events from this bus
func get_recent_events(count: int = 100) -> Array[Dictionary]:
	var start := maxi(0, _event_history.size() - count)
	return _event_history.slice(start)

## Clear event history for this bus
func clear_history() -> void:
	_event_history.clear()

## Get event count
func get_event_count() -> int:
	return _event_history.size()
