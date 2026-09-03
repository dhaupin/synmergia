## ServerManager - Server state, maintenance, and restart scheduling
## Handles server restarts, maintenance windows, and player notifications
extends Node

const State = preload("res://scripts/state.gd")
# Frame-level notification dispatch (see synmergia/core/notifications/).
# kick_player dispatches SECURITY_BLOCKED via the typed-Kind pipeline so
# the kick lands on the player's toast feed through the same channel
# the firewall/admin commands use. The legacy NotificationService.send
# call is kept for clients that haven't migrated to the new pipeline.
const NotifKind = preload("res://core/notifications/notification_kind.gd").Kind

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
	GameLog.info("ServerManager: Ready")

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
	
	GameLog.info("ServerManager: Restart scheduled in %d seconds" % seconds_from_now)
	GameLog.info("ServerManager: Message: %s" % message)
	
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
	
	GameLog.info("ServerManager: Restart cancelled")
	restart_cancelled.emit()
	
	# Notify players restart was cancelled
	# Frame-level broadcast. ADMIN_ALERT → ALERT/HIGH via the kind map.
	# Empty recipient + ADMIN_ALERT routes to every player.
	NotificationService.notify(
		NotifKind.ADMIN_ALERT,
		"Server restart has been cancelled. Continue playing!",
		"ServerManager",
		"sm:restart_cancelled",
		{},
		""
	)

## Execute restart immediately
func execute_restart() -> void:
	GameLog.info("ServerManager: Executing restart")
	restart_executed.emit()
	
	# Final warning
	# Frame-level broadcast. ADMIN_ALERT, the kind→priority map returns
	# HIGH (the highest tier the map has), which matches the CRITICAL
	# urgency the legacy call had.
	NotificationService.notify(
		NotifKind.ADMIN_ALERT,
		"SERVER RESTARTING NOW",
		"ServerManager",
		"sm:restart_now",
		{},
		""
	)
	
	# Trigger actual server shutdown via event bus
	EventHub.server_shutdown.emit()
	
	# Schedule actual process quit after a brief delay
	var t = Timer.new()
	t.timeout.connect(_do_actual_shutdown)
	t.one_shot = true
	t.wait_time = 2.0
	add_child(t)
	t.start()

func _do_actual_shutdown() -> void:
	GameLog.info("ServerManager: Quitting process")
	get_tree().quit()

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
	var message: String = custom_message if custom_message != "" else "Server restart"
	
	if seconds_remaining >= 3600:
		var minutes = seconds_remaining / 60
		message = "%s in %d hour%s" % [message, minutes, "s" if minutes > 1 else ""]
	elif seconds_remaining >= 60:
		var minutes = seconds_remaining / 60
		message = "%s in %d minute%s" % [message, minutes, "s" if minutes > 1 else ""]
	else:
		message = "%s in %d second%s" % [message, seconds_remaining, "s" if seconds_remaining > 1 else ""]
	
	# Frame-level broadcast. ADMIN_ALERT routes through kind→priority
	# HIGH. The legacy CRITICAL-for-≤10s tier can't be reproduced via
	# the kind→priority map (HIGH is the cap), so we drop the
	# escalation since the restart_executed broadcast at 0s already
	# fires on the way out.
	NotificationService.notify(
		NotifKind.ADMIN_ALERT,
		message,
		"ServerManager",
		"sm:restart_warning:%d" % seconds_remaining,
		{"seconds_remaining": seconds_remaining},
		""
	)

# --- Maintenance Mode ---

## Start maintenance mode
func start_maintenance(message: String = "Server under maintenance", duration_seconds: int = 0) -> void:
	_was_online = _state
	_state = ServerState.MAINTENANCE
	_maintenance_message = message
	_maintenance_start_time = Time.get_unix_time_from_system()
	
	GameLog.info("ServerManager: Entering maintenance mode")
	GameLog.info("ServerManager: Message: %s" % message)
	
	maintenance_started.emit(message)
	
	NotificationService.notify(
		NotifKind.ADMIN_ALERT,
		message,
		"ServerManager",
		"sm:start_maintenance",
		{"maintenance": true, "duration": duration_seconds},
		""
	)

## End maintenance mode
func end_maintenance() -> void:
	if _state != ServerState.MAINTENANCE:
		return
	
	_state = _was_online if _was_online != ServerState.MAINTENANCE else ServerState.ONLINE
	var duration = Time.get_unix_time_from_system() - _maintenance_start_time
	
	GameLog.info("ServerManager: Ending maintenance mode (duration: %d seconds)" % duration)
	maintenance_ended.emit()
	
	NotificationService.notify(
		NotifKind.ADMIN_ALERT,
		"Server maintenance complete! You may resume playing.",
		"ServerManager",
		"sm:end_maintenance",
		{},
		""
	)

## Set server state directly
func set_state(new_state: ServerState) -> void:
	var old_state = _state
	_state = new_state
	
	GameLog.info("ServerManager: State changed from %s to %s" % [ServerState.keys()[old_state], ServerState.keys()[new_state]])
	server_state_changed.emit(new_state, old_state)

# --- Player Management ---

## Kick player from server
func kick_player(entity_id: String, reason: String = "You have been disconnected") -> void:
	GameLog.info("ServerManager: Kicking player %s: %s" % [entity_id, reason])
	player_kicked.emit(entity_id, reason)

	# Frame-level dispatch. SECURITY_BLOCKED → ALERT + HIGH. The player
	# must know the disconnect was deliberate (so they don't blame their
	# own connection). Dedupe on (player, reason) so a kick then a
	# re-kick for the same reason collapses, but a different reason (e.g.
	# admin kicks first, then a maintenance shutdown kicks for a
	# different reason) both surface.
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.SECURITY_BLOCKED,
			reason,
			"ServerManager",
			"server_kick:%s:%s" % [entity_id, reason],
			{"reason": reason, "kind": "server_kick"},
			entity_id
		)

	# TODO(server): wire the actual disconnect once NetworkManager exposes
	# kick_player / disconnect_peer and PlayerManager has a player-registry
	# query. Today the underlying chain (PlayerManager.has_player /
	# PlayerManager.get_player_info / NetworkManager.kick_player) does not
	# exist, so the toast layer is correct but the peer is not actually
	# disconnected. Tracked separately from this PR.
	if PlayerManager and PlayerManager.has_method("has_player") and PlayerManager.has_player(entity_id):
		var info = PlayerManager.get_player_info(entity_id)
		var peer_id: int = info.get("peer_id", -1)
		if peer_id > 0 and NetworkManager and NetworkManager.has_method("kick_player"):
			NetworkManager.kick_player(peer_id, reason)

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
	GameLog.info("ServerManager: Server started, uptime tracking begun")

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
