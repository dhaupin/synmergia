## SystemEvents - Domain events for server/system lifecycle
## Server state, saves, config changes, and system alerts
class_name SystemEvents
extends BaseEventBus

# Server lifecycle events
signal server_starting(version: String, mode: String)
signal server_started(version: String, port: int)
signal server_stopping(reason: String)
signal server_stopped()
signal server_shutdown_requested(initiator: String, reason: String)

# Player session events
signal player_connecting(player_id: String, ip: String)
signal player_connected(player_id: String)
signal player_disconnected(player_id: String, reason: String)
signal player_session_ended(player_id: String, duration_sec: int)

# Save/load events
signal world_save_started()
signal world_save_completed(duration_ms: int)
signal world_save_failed(error: String)
signal player_save_started(player_id: String)
signal player_save_completed(player_id: String)
signal player_save_failed(player_id: String, error: String)

# Config events
signal config_changed(key: String, old_value, new_value)
signal config_reloaded(source: String)

# Alert events
signal alert_sent(alert_type: String, message: String, severity: int, target_ids: Array[String])
signal alert_acknowledged(alert_id: String, acknowledged_by: String)
signal server_message(message: String, target_ids: Array[String])

# Security events
signal exploit_detected(player_id: String, exploit_type: String, details: String)
signal flood_detected(player_id: String, channel: String, rate: float)
signal cheat_detected(player_id: String, cheat_type: String)
signal player_banned(player_id: String, banned_by: String, duration_sec: int, reason: String)
signal player_unbanned(player_id: String, unbanned_by: String)
signal player_kicked(player_id: String, kicked_by: String, reason: String)

# Performance/monitoring events
signal performance_warning(metric: String, value: float, threshold: float)
signal memory_warning(used_mb: float, limit_mb: float)
signal lag_detected(player_id: String, latency_ms: int)
signal server_overloaded(cause: String)

# Economy events
signal economic_event(event_type: String, player_id: String, amount: int, details: String)
signal inflation_detected(rate: float)
signal rare_item_spawned(item_id: String, rarity: String)

# Zone/shard events
signal zone_activated(zone_id: String)
signal zone_deactivated(zone_id: String)
signal shard_split(zone_id: String, new_shard_id: String)
signal shard_merged(zone_ids: Array[String], result_shard_id: String)

# Admin events
signal admin_command_executed(admin_id: String, command: String, args: String, success: bool)
signal admin_action_logged(action: String, admin_id: String, target_id: String, details: String)

## Emit server started event
func emit_server_started(version: String, port: int) -> void:
	_log_event("server_started", {"version": version, "port": port})
	server_started.emit(version, port)

## Emit server stopping event
func emit_server_stopping(reason: String = "") -> void:
	_log_event("server_stopping", {"reason": reason})
	server_stopping.emit(reason)

## Emit player connected event
func emit_player_connected(player_id: String) -> void:
	_log_event("player_connected", {"player_id": player_id})
	player_connected.emit(player_id)

## Emit player disconnected event
func emit_player_disconnected(player_id: String, reason: String = "") -> void:
	_log_event("player_disconnected", {"player_id": player_id, "reason": reason})
	player_disconnected.emit(player_id, reason)

## Emit world save completed event
func emit_world_save_completed(duration_ms: int) -> void:
	_log_event("world_save_completed", {"duration_ms": duration_ms})
	world_save_completed.emit(duration_ms)

## Emit exploit detected event
func emit_exploit_detected(player_id: String, exploit_type: String, details: String = "") -> void:
	_log_event("exploit_detected", {"player_id": player_id, "type": exploit_type})
	exploit_detected.emit(player_id, exploit_type, details)

## Emit admin command executed event
func emit_admin_command(admin_id: String, command: String, args: String, success: bool) -> void:
	_log_event("admin_command", {"admin_id": admin_id, "command": command, "success": success})
	admin_command_executed.emit(admin_id, command, args, success)
