## SystemEvents - Domain events for server lifecycle
extends Node
class_name SystemEvents

# Server lifecycle events
signal server_starting(version: String, mode: String)
signal server_started(version: String, port: int)
signal server_stopping(reason: String)
signal server_stopped()

# Player session events
signal player_connecting(player_id: String, ip: String)
signal player_connected(player_id: String)
signal player_disconnected(player_id: String, reason: String)

# Save/load events
signal world_save_started()
signal world_save_completed(duration_ms: int)
signal world_save_failed(error: String)

# Config events
signal config_changed(key: String, old_value, new_value)
signal config_reloaded(source: String)

# Security events
signal exploit_detected(player_id: String, exploit_type: String, details: String)
signal player_banned(player_id: String, banned_by: String, duration_sec: int, reason: String)
signal player_kicked(player_id: String, kicked_by: String, reason: String)

# Admin events
signal admin_command_executed(admin_id: String, command: String, args: String, success: bool)

# Event history
var _history: Array = []
const MAX_HISTORY := 1000

func _log_event(name: String, data: Dictionary = {}) -> void:
	_history.append({"name": name, "data": data, "time": Time.get_ticks_msec()})
	if _history.size() > MAX_HISTORY:
		_history.pop_front()

func get_event_count() -> int:
	return _history.size()

func clear_history() -> void:
	_history.clear()
