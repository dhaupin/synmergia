## ServerManager - Server state, maintenance, and restart scheduling
## Handles server restarts, maintenance windows, and player notifications
class_name ServerManager
extends Node

# Server state
enum ServerState {
	ONLINE,        # Normal operation
	RESTARTING,    # Preparing for restart
	MAINTENANCE,   # In maintenance mode
	EMERGENCY      # Emergency shutdown
}

var _state: ServerState = ServerState.ONLINE
var _was_online: ServerState = ServerState.ONLINE  # State before maintenance

# Restart scheduling
var _restart_scheduled: bool = false
var _restart_time: int = 0  # Unix timestamp
var _restart_countdown_seconds: int = 0
var _restart_warned_players: bool = false

# Maintenance
var _maintenance_message: String = "Server under maintenance"
var _maintenance_start_time: int = 0

# Restart warning intervals (seconds before restart)
const WARNING_INTERVALS: Array[int] = [3600, 1800, 900, 600, 300, 60, 30, 10, 5, 4, 3, 2, 1]

signal server_state_changed(new_state: ServerState, old_state: ServerState)
signal restart_scheduled(restart_time: int, seconds_remaining: int)
signal restart_cancelled()
signal restart_countdown(seconds_remaining: int)
signal restart_executed()
signal maintenance_started(message: String)
signal maintenance_ended()
signal player_kicked(entity_id: String, reason: String)

func _ready() -> void:
	Logger.info("ServerManager: Ready")

func _process(delta: float) -> void:
	if _restart_scheduled:
		_process_restart_countdown(delta)

## Get current server state
func get_state() -> ServerState:
	return _state

func get_state_string() -> String:
	return ServerState.keys()[_state]

## Check if server is accepting new connections
func is_accepting_connections() -> bool:
	return _state == ServerState.ONLINE

## Check if server is shutting down
func is_shutting_down() -> bool:
	return _state == ServerState.RESTARTING or _state == ServerState.EMERGENCY

# --- Restart Scheduling ---

## Schedule a server restart
func schedule_restart(seconds_from_now: int, message: String = "Server restart scheduled") -> void:
	_restart_scheduled = true
	_restart_time = Time.get_unix_time_from_system() + seconds_from_now
	_restart_countdown_seconds = seconds_from_now
	_restart_warned_players = false
	
	Logger.info("ServerManager: Restart scheduled in %d seconds" % seconds_from_now)
	Logger.info("ServerManager: Message: %s" % message)
	
	restart_scheduled.emit(_restart_time, seconds_from_now)
	
	# Immediate notification
	_broadcast_restart_warning(seconds_from_now, message)

## Cancel scheduled restart
func cancel_restart() -> void:
	if not _restart_scheduled:
		return
	
	_restart_scheduled = false
	var seconds_remaining = _restart_countdown_seconds
	_restart_countdown_seconds = 0
	
	Logger.info("ServerManager: Restart cancelled")
	restart_cancelled.emit()
	
	# Notify players restart was cancelled
	NotificationService.broadcast_all(
		"Server restart has been cancelled. Continue playing!",
		NotificationService.NotificationType.SYSTEM,
		NotificationService.Priority.HIGH,
		NotificationService.DisplayLocation.CENTER_SCREEN,
		NotificationService.SoundType.NOTIFICATION
	)

## Execute restart immediately
func execute_restart() -> void:
	Logger.info("ServerManager: Executing restart")
	restart_executed.emit()
	
	# Final warning
	NotificationService.broadcast_all(
		"SERVER RESTARTING NOW",
		NotificationService.NotificationType.SYSTEM,
		NotificationService.Priority.CRITICAL,
		NotificationService.DisplayLocation.CENTER_SCREEN,
		NotificationService.SoundType.WARNING
	)
	
	# TODO: Trigger actual server restart/shutdown
	# This would typically call GameManager.shutdown() or similar

## Get time until restart
func get_restart_seconds_remaining() -> int:
	if not _restart_scheduled:
		return 0
	return max(0, _restart_time - Time.get_unix_time_from_system())

## Is restart scheduled
func is_restart_scheduled() -> bool:
	return _restart_scheduled

func _process_restart_countdown(delta: float) -> void:
	var remaining = get_restart_seconds_remaining()
	_restart_countdown_seconds = remaining
	
	if remaining <= 0:
		# Time's up, execute restart
		_restart_scheduled = false
		_restart_countdown_seconds = 0
		execute_restart()
		return
	
	# Check if we need to send a warning
	_restart_countdown_seconds = remaining
	restart_countdown.emit(remaining)
	
	# Check warning intervals
	for warning_seconds in WARNING_INTERVALS:
		if remaining == warning_seconds:
			_broadcast_restart_warning(warning_seconds)
			break
	
	# Send countdown every minute in final 5 minutes
	if remaining <= 300 and remaining % 60 == 0:
		_broadcast_restart_warning(remaining)

func _broadcast_restart_warning(seconds_remaining: int, custom_message: String = "") -> void:
	var message := custom_message if custom_message != "" else "Server restart"
	
	if seconds_remaining >= 3600:
		var minutes = seconds_remaining / 60
		message = "%s in %d hour%s" % [message, minutes, "s" if minutes > 1 else ""]
	elif seconds_remaining >= 60:
		var minutes = seconds_remaining / 60
		message = "%s in %d minute%s" % [message, minutes, "s" if minutes > 1 else ""]
	else:
		message = "%s in %d second%s" % [message, seconds_remaining, "s" if seconds_remaining > 1 else ""]
	
	# Higher priority for shorter countdowns
	var priority = NotificationService.Priority.NORMAL
	var location = NotificationService.DisplayLocation.CENTER_SCREEN
	var sound = NotificationService.SoundType.WARNING
	
	if seconds_remaining <= 60:
		priority = NotificationService.Priority.HIGH
	if seconds_remaining <= 10:
		priority = NotificationService.Priority.CRITICAL
	
	NotificationService.broadcast_all(
		message,
		NotificationService.NotificationType.WARNING,
		priority,
		location,
		sound
	)

# --- Maintenance Mode ---

## Start maintenance mode
func start_maintenance(message: String = "Server under maintenance", duration_seconds: int = 0) -> void:
	_was_online = _state
	_state = ServerState.MAINTENANCE
	_maintenance_message = message
	_maintenance_start_time = Time.get_unix_time_from_system()
	
	Logger.info("ServerManager: Entering maintenance mode")
	Logger.info("ServerManager: Message: %s" % message)
	
	maintenance_started.emit(message)
	
	NotificationService.broadcast_all(
		message,
		NotificationService.NotificationType.SYSTEM,
		NotificationService.Priority.CRITICAL,
		NotificationService.DisplayLocation.CENTER_SCREEN,
		NotificationService.SoundType.WARNING,
		{"maintenance": true, "duration": duration_seconds}
	)

## End maintenance mode
func end_maintenance() -> void:
	if _state != ServerState.MAINTENANCE:
		return
	
	_state = _was_online if _was_online != ServerState.MAINTENANCE else ServerState.ONLINE
	var duration = Time.get_unix_time_from_system() - _maintenance_start_time
	
	Logger.info("ServerManager: Ending maintenance mode (duration: %d seconds)" % duration)
	maintenance_ended.emit()
	
	NotificationService.broadcast_all(
		"Server maintenance complete! You may resume playing.",
		NotificationService.NotificationType.SYSTEM,
		NotificationService.Priority.HIGH,
		NotificationService.DisplayLocation.CENTER_SCREEN,
		NotificationService.SoundType.NOTIFICATION
	)

## Set server state directly
func set_state(new_state: ServerState) -> void:
	var old_state = _state
	_state = new_state
	
	Logger.info("ServerManager: State changed from %s to %s" % [ServerState.keys()[old_state], ServerState.keys()[new_state]])
	server_state_changed.emit(new_state, old_state)

# --- Player Management ---

## Kick player from server
func kick_player(entity_id: String, reason: String = "You have been disconnected") -> void:
	Logger.info("ServerManager: Kicking player %s: %s" % [entity_id, reason])
	player_kicked.emit(entity_id, reason)
	
	# Send kick notification
	NotificationService.send(
		entity_id,
		reason,
		NotificationService.NotificationType.ERROR,
		NotificationService.Priority.HIGH,
		NotificationService.DisplayLocation.CENTER_SCREEN,
		NotificationService.SoundType.ERROR
	)
	
	# TODO: Actually disconnect the player
	# This would typically call NetworkManager.disconnect_player(entity_id)

## Kick all players (for maintenance/shutdown)
func kick_all_players(reason: String = "Server is shutting down") -> void:
	var entity_service = EntityService
	if entity_service:
		var players = entity_service.get_all_players()
		for player in players:
			kick_player(player.entity_id, reason)

# --- Server Info ---

## Get server uptime
var _server_start_time: int = 0

func start_server() -> void:
	_server_start_time = Time.get_unix_time_from_system()
	_state = ServerState.ONLINE
	Logger.info("ServerManager: Server started, uptime tracking begun")

func get_uptime_seconds() -> int:
	if _server_start_time == 0:
		return 0
	return Time.get_unix_time_from_system() - _server_start_time

func get_uptime_string() -> String:
	var seconds = get_uptime_seconds()
	var hours = seconds / 3600
	var minutes = (seconds % 3600) / 60
	var secs = seconds % 60
	
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, secs]
	return "%02d:%02d" % [minutes, secs]

## Get server info for client
func get_server_info() -> Dictionary:
	return {
		"state": get_state_string(),
		"uptime": get_uptime_string(),
		"uptime_seconds": get_uptime_seconds(),
		"player_count": ShardManager.get_player_count() if ShardManager else 0,
		"restart_scheduled": is_restart_scheduled(),
		"restart_seconds": get_restart_seconds_remaining(),
		"shard_id": ShardManager.shard_id if ShardManager else "unknown",
		"world_name": ShardManager.world_name if ShardManager else "unknown"
	}
