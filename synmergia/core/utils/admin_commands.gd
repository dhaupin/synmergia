## AdminCommands - Administrative command handlers for server management
class_name AdminCommands
extends Node

## ============================================================================
## ADMIN COMMANDS REGISTRY
## ============================================================================

var _commands: Dictionary = {}

func _ready() -> void:
	_register_commands()
	Logger.info("AdminCommands: Initialized")

func _register_commands() -> void:
	_commands = {
		"ban": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Permanently ban a player",
			"usage": "/ban <player_id> <reason>",
			"handler": _cmd_ban
		},
		"unban": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Remove a player ban",
			"usage": "/unban <player_id>",
			"handler": _cmd_unban
		},
		"kick": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Kick a player from server",
			"usage": "/kick <player_id> [reason]",
			"handler": _cmd_kick
		},
		"mute": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Mute a player",
			"usage": "/mute <player_id> [duration_minutes]",
			"handler": _cmd_mute
		},
		"unmute": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Unmute a player",
			"usage": "/unmute <player_id>",
			"handler": _cmd_unmute
		},
		"block_ip": {
			"permission": GameConfig.Security.ADMIN_LEVEL,
			"description": "Block an IP address",
			"usage": "/block_ip <ip> <duration_seconds> <reason>",
			"handler": _cmd_block_ip
		},
		"unblock_ip": {
			"permission": GameConfig.Security.ADMIN_LEVEL,
			"description": "Unblock an IP address",
			"usage": "/unblock_ip <ip>",
			"handler": _cmd_unblock_ip
		},
		"player_info": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Get player info",
			"usage": "/player_info <player_id>",
			"handler": _cmd_player_info
		},
		"list_players": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "List connected players",
			"usage": "/list_players",
			"handler": _cmd_list_players
		},
		"firewall_status": {
			"permission": GameConfig.Security.ADMIN_LEVEL,
			"description": "Show firewall status",
			"usage": "/firewall_status",
			"handler": _cmd_firewall_status
		},
		"shutdown": {
			"permission": GameConfig.Security.ADMIN_LEVEL,
			"description": "Shutdown the server",
			"usage": "/shutdown [delay_seconds]",
			"handler": _cmd_shutdown
		},
		"broadcast": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Send server-wide message",
			"usage": "/broadcast <message>",
			"handler": _cmd_broadcast
		}
	}

## Execute a command
func execute_command(cmd_name: String, args: Array, caller_id: String) -> Dictionary:
	if not _commands.has(cmd_name):
		return {"success": false, "message": "Unknown command: " + cmd_name}
	
	var cmd = _commands[cmd_name]
	var caller_level = _get_caller_permission_level(caller_id)
	
	if caller_level < cmd["permission"]:
		SecurityService.log_permission_denied(caller_id, "admin_command:" + cmd_name, cmd["permission"])
		return {"success": false, "message": "Permission denied"}
	
	var handler: Callable = cmd["handler"]
	var result = handler.call(args)
	Logger.info("AdminCommand: %s executed /%s" % [caller_id, cmd_name])
	
	return result

func _get_caller_permission_level(caller_id: String) -> int:
	var player_info = PlayerManager.get_player_info(caller_id)
	if player_info.is_empty():
		return GameConfig.Security.PLAYER_LEVEL
	return player_info.get("permission_level", GameConfig.Security.PLAYER_LEVEL)

## Command handlers
func _cmd_ban(args: Array) -> Dictionary:
	if args.size() < 2:
		return {"success": false, "message": "Usage: /ban <player_id> <reason>"}
	var player_id = args[0]
	var reason = " ".join(args.slice(1, args.size()))
	NetworkManager.ban_player(player_id, reason, "admin")
	return {"success": true, "message": "Banned: " + player_id}

func _cmd_unban(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /unban <player_id>"}
	var firewall = NetworkManager.get_firewall()
	if firewall:
		firewall.lift_ban(args[0])
		return {"success": true, "message": "Unbanned: " + args[0]}
	return {"success": false, "message": "Firewall not available"}

func _cmd_kick(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /kick <player_id> [reason]"}
	var peer_id = int(args[0])
	var reason = "Kicked" if args.size() < 2 else " ".join(args.slice(1, args.size()))
	NetworkManager.kick_player(peer_id, reason)
	return {"success": true, "message": "Kicked: " + args[0]}

func _cmd_mute(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /mute <player_id> [duration]"}
	var duration = 60 if args.size() < 2 else int(args[1]) * 60
	SecurityService.restrict_player(args[0], "chat", duration)
	return {"success": true, "message": "Muted: " + args[0]}

func _cmd_unmute(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /unmute <player_id>"}
	SecurityService.unrestrict_player(args[0], "chat")
	return {"success": true, "message": "Unmuted: " + args[0]}

func _cmd_block_ip(args: Array) -> Dictionary:
	if args.size() < 3:
		return {"success": false, "message": "Usage: /block_ip <ip> <duration> <reason>"}
	var firewall = NetworkManager.get_firewall()
	if firewall:
		firewall.block_ip(args[0], args.slice(2, args.size()).join(" "), int(args[1]))
		return {"success": true, "message": "Blocked IP: " + args[0]}
	return {"success": false, "message": "Firewall not available"}

func _cmd_unblock_ip(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /unblock_ip <ip>"}
	var firewall = NetworkManager.get_firewall()
	if firewall:
		firewall.unblock_ip(args[0])
		return {"success": true, "message": "Unblocked IP: " + args[0]}
	return {"success": false, "message": "Firewall not available"}

func _cmd_player_info(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /player_info <player_id>"}
	var info = PlayerManager.get_player_info(args[0])
	if info.is_empty():
		return {"success": false, "message": "Player not found"}
	return {"success": true, "message": JSON.stringify(info)}

func _cmd_list_players(args: Array) -> Dictionary:
	var players = PlayerManager.get_all_players()
	var msg = "Players (%d):" % players.size()
	for p in players:
		msg += "\n- %s" % p.get("name", "Unknown")
	return {"success": true, "message": msg}

func _cmd_firewall_status(args: Array) -> Dictionary:
	var firewall = NetworkManager.get_firewall()
	if not firewall:
		return {"success": false, "message": "Firewall not available"}
	return {"success": true, "message": "Firewall active"}

func _cmd_shutdown(args: Array) -> Dictionary:
	var delay = 0 if args.size() < 1 else int(args[0])
	NotificationService.broadcast_alert("Server shutdown in %d seconds!" % delay)
	var t = Timer.new()
	t.timeout.connect(func(): get_tree().quit())
	t.one_shot = true
	t.wait_time = delay
	add_child(t)
	t.start()
	return {"success": true, "message": "Shutting down in %d seconds" % delay}

func _cmd_broadcast(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /broadcast <message>"}
	NotificationService.broadcast_alert(" ".join(args))
	return {"success": true, "message": "Broadcast sent"}
