## AdminShell - Internal admin command system
## Provides a sandboxed command interface for game administration
## Not connected to OS shell - game-internal commands only
extends Node

const EntityScript = preload("res://core/entities/entity.gd")

func _get_gamelog() -> Object:
	var root = get_tree().root if has_node("/root") else null
	if root:
		return root.get_node_or_null("GameLog")
	return null

func _get_qos_service() -> Object:
	var root = get_tree().root if has_node("/root") else null
	if root:
		return root.get_node_or_null("QoSService")
	return null

static func _esc(text: String) -> String:
	return text.replace("[", "［").replace("]", "］")

## Command result structure
class CommandResult:
	var success: bool
	var output: String
	var error: String

	func _init(p_success: bool = false, p_output: String = "", p_error: String = ""):
		success = p_success
		output = p_output
		error = p_error

## Command definition
class Command:
	var name: String
	var aliases: Array
	var description: String
	var usage: String
	var permission_level: int  # From GameConfig.Security
	var callback: Callable

	func _init(p_name: String, p_callback: Callable, p_desc: String = "", p_usage: String = "",
			p_aliases: Array = [], p_perm: int = GameConfig.Security.ADMIN_LEVEL):
		name = p_name
		callback = p_callback
		description = p_desc
		usage = p_usage
		aliases = p_aliases
		permission_level = p_perm

## Signal emitted when command is executed
signal command_executed(cmd: String, result: CommandResult, executor_id: String)

## All registered commands
var _commands: Dictionary = {}
var _aliases: Dictionary = {}

## Command history
var history: Array = []
var history_index: int = -1
const MAX_HISTORY: int = 100

## Current executor (who is using the shell)
var _current_executor_id: String = ""

func _ready() -> void:
	_register_default_commands()
	var gl := _get_gamelog()
	if gl:
		gl.info("AdminShell: Initialized with %d commands" % _commands.size())

## Register a command
func register_command(cmd: Command) -> void:
	_commands[cmd.name.to_lower()] = cmd
	for alias in cmd.aliases:
		_aliases[alias.to_lower()] = cmd.name.to_lower()

## Execute a command string
func execute(command_line: String, executor_id: String = "") -> CommandResult:
	_current_executor_id = executor_id

	# Add to history
	if command_line.strip_edges() != "":
		history.push_front(command_line)
		if history.size() > MAX_HISTORY:
			history.pop_back()
		history_index = -1

	# Parse command
	var parts: Array = command_line.strip_edges().split(" ", false, 2)
	if parts.is_empty() or parts[0] == "":
		return CommandResult.new(false, "", "No command entered. Type 'help' for commands.")

	var cmd_name: String = parts[0].to_lower()
	var args: String = parts[1] if parts.size() > 1 else ""

	# Check if command exists (check aliases first)
	var actual_name: String = _aliases.get(cmd_name, cmd_name)
	if not _commands.has(actual_name):
		return CommandResult.new(false, "", "Unknown command: %s. Type 'help' for commands." % cmd_name)

	var cmd: Command = _commands[actual_name]

	# Check permission
	if executor_id != "" and not _has_permission(executor_id, cmd.permission_level):
		return CommandResult.new(false, "", "Permission denied. Required level: %d" % cmd.permission_level)

	# Execute command
	var result: CommandResult
	if cmd.callback.is_valid():
		result = cmd.callback.call(args, executor_id)
		if result == null:
			result = CommandResult.new(false, "", "Command execution failed")
	else:
		result = CommandResult.new(false, "", "Command callback invalid")

	command_executed.emit(command_line, result, executor_id)
	return result

## Get tab completion suggestions
func get_suggestions(partial: String, executor_id: String = "") -> Array:
	var suggestions: Array = []
	var search: String = partial.to_lower()

	for cmd_name in _commands.keys():
		if cmd_name.begins_with(search):
			var cmd: Command = _commands[cmd_name]
			if executor_id == "" or _has_permission(executor_id, cmd.permission_level):
				suggestions.append(cmd_name)

	# Also check aliases
	for alias in _aliases.keys():
		if alias.begins_with(search):
			var actual: String = _aliases[alias]
			if actual in suggestions:
				continue
			var cmd: Command = _commands[actual]
			if executor_id == "" or _has_permission(executor_id, cmd.permission_level):
				suggestions.append(actual)

	return suggestions

## Get help for a command
func get_help(cmd_name: String = "") -> String:
	if cmd_name == "":
		return _get_general_help()

	var actual_name: String = _aliases.get(cmd_name.to_lower(), cmd_name.to_lower())
	if not _commands.has(actual_name):
		return "Unknown command: %s" % cmd_name

	var cmd: Command = _commands[actual_name]
	var help_text: String = "[color=yellow]%s[/color]" % cmd.name

	if not cmd.aliases.is_empty():
		help_text += " (aliases: %s)" % ", ".join(cmd.aliases)

	help_text += "\n  " + cmd.description

	if cmd.usage != "":
		help_text += "\n  [color=cyan]Usage:[/color] %s" % cmd.usage

	help_text += "\n  [color=gray]Permission level:[/color] %d" % cmd.permission_level

	return help_text

func _get_general_help() -> String:
	var help_text: String = "[color=yellow]=== Admin Shell Commands ===[/color]\n"
	help_text += "Type 'help <command>' for detailed info.\n\n"

	for cmd_name in _commands.keys():
		var cmd: Command = _commands[cmd_name]
		if _current_executor_id == "" or _has_permission(_current_executor_id, cmd.permission_level):
			help_text += "  [color=cyan]%s[/color] - %s\n" % [cmd.name, cmd.description]

	help_text += "\n[color=gray]Use Tab for auto-complete, Up/Down for history[/color]"
	return help_text

func _has_permission(player_id: String, required_level: int) -> bool:
	# Use PermissionManager for ALL permission checks
	if PermissionManager:
		return PermissionManager.has_permission(player_id, required_level)

	# Fallback (should not be used in production)
	if SecurityService:
		return SecurityService.get_player_permission_level(player_id) >= required_level
	return required_level <= GameConfig.Security.PLAYER_LEVEL

func _register_default_commands() -> void:
	# Help command
	register_command(Command.new("help", _cmd_help, "Show help for commands", "help [command]"))

	# Player lookup
	register_command(Command.new("lookup", _cmd_lookup, "Look up player info", "lookup <player_id>"))
	register_command(Command.new("players", _cmd_players, "List online players", "players [filter]"))
	register_command(Command.new("count", _cmd_count, "Count online players", "count"))

	# Restrictions
	register_command(Command.new("restrict", _cmd_restrict, "Restrict a player", "restrict <player> <type> [duration_sec]"))
	register_command(Command.new("unrestrict", _cmd_unrestrict, "Remove player restriction", "unrestrict <player> [type]"))
	register_command(Command.new("restrictions", _cmd_restrictions, "List active restrictions", "restrictions [player]"))

	# Mute/Kick/Ban
	register_command(Command.new("mute", _cmd_mute, "Mute a player", "mute <player> [duration_sec]"))
	register_command(Command.new("unmute", _cmd_unmute, "Unmute a player", "unmute <player>"))
	register_command(Command.new("kick", _cmd_kick, "Kick a player", "kick <player> [reason]"))
	register_command(Command.new("ban", _cmd_ban, "Ban a player", "ban <player> [duration_sec] [reason]"))

	# QoS
	register_command(Command.new("qos", _cmd_qos, "Check QoS status for player", "qos <player>"))
	register_command(Command.new("rateinfo", _cmd_rateinfo, "Get rate limit info", "rateinfo"))

	# Admin shell
	register_command(Command.new("clear", _cmd_clear, "Clear the terminal", "clear", [], GameConfig.Security.PLAYER_LEVEL))
	register_command(Command.new("history", _cmd_history, "Show command history", "history", [], GameConfig.Security.PLAYER_LEVEL))
	register_command(Command.new("whoami", _cmd_whoami, "Show current admin info", "whoami", [], GameConfig.Security.PLAYER_LEVEL))

	# System
	register_command(Command.new("status", _cmd_status, "Show system status", "status"))
	register_command(Command.new("uptime", _cmd_uptime, "Show uptime", "uptime"))
	register_command(Command.new("stats", _cmd_stats, "Show service statistics", "stats"))

	# Config
	register_command(Command.new("config", _cmd_config, "View/modify config", "config [key] [value]"))
	register_command(Command.new("toggles", _cmd_toggles, "List security toggles", "toggles"))

	# Audit (ADMIN level required)
	register_command(Command.new("audit", _cmd_audit, "View admin audit log", "audit [limit] [admin] [action]"))

	# GM Movement Commands
	register_command(Command.new("invisible", _cmd_invisible, "Toggle invisibility mode", "invisible [0|1]", ["inv"], GameConfig.Security.ADMIN_LEVEL))
	register_command(Command.new("fly", _cmd_fly, "Toggle fly mode (no gravity)", "fly [0|1]", [], GameConfig.Security.ADMIN_LEVEL))
	register_command(Command.new("noclip", _cmd_noclip, "Toggle noclip mode (pass through walls)", "noclip [0|1]", [], GameConfig.Security.ADMIN_LEVEL))
	register_command(Command.new("speed", _cmd_speed, "Set movement speed multiplier", "speed [multiplier]", [], GameConfig.Security.ADMIN_LEVEL))
	register_command(Command.new("godmode", _cmd_godmode, "Toggle godmode (invincible)", "godmode [0|1]", ["god"], GameConfig.Security.ADMIN_LEVEL))
	register_command(Command.new("teleport", _cmd_teleport, "Teleport to coords or player", "teleport <x> <y> <z> OR <player_id>", ["tp"], GameConfig.Security.MOD_LEVEL))
	register_command(Command.new("goto", _cmd_goto_shell, "Teleport to a player", "goto <player_id>", [], GameConfig.Security.MOD_LEVEL))
	register_command(Command.new("summon", _cmd_summon, "Summon a player to you", "summon <player_id>", [], GameConfig.Security.MOD_LEVEL))
	register_command(Command.new("heal", _cmd_heal, "Heal yourself or another player", "heal [player_id]", [], GameConfig.Security.MOD_LEVEL))

## ============================================================================
## COMMAND IMPLEMENTATIONS
## ============================================================================

func _cmd_help(args: String, executor_id: String) -> CommandResult:
	return CommandResult.new(true, get_help(args), "")

func _cmd_lookup(args: String, executor_id: String) -> CommandResult:
	if args == "":
		return CommandResult.new(false, "", "Usage: lookup <player_id>")

	var player_id: String = args.strip_edges()

	# Use PermissionManager for secured lookup
	if PermissionManager:
		var result := PermissionManager.lookup_player(executor_id, player_id)
		if result.success:
			return CommandResult.new(true, _format_player_info(result.info), "")
		else:
			return CommandResult.new(false, "", "Failed: %s" % result.message)

	# Fallback
	var info: String = _get_player_info(player_id)
	if info == "":
		return CommandResult.new(false, "", "Player not found: %s" % player_id)
	return CommandResult.new(true, info, "")

func _cmd_players(args: String, executor_id: String) -> CommandResult:
	var filter: String = args.strip_edges().to_lower()
	var output: String = "[color=yellow]=== Online Players ===[/color]\n"

	var count: int = 0
	var players: Array = _get_online_players()

	for player in players:
		var id: String = player if player is String else str(player)
		if filter == "" or id.to_lower().contains(filter):
			var restricted: String = ""
			if SecurityService and SecurityService.is_restricted(id, "chat"):
				restricted = " [color=red](MUTED)[/color]"
			output += "  %s%s\n" % [_esc(id), restricted]
			count += 1

	output += "\n[color=gray]Total: %d player(s)[/color]" % count
	return CommandResult.new(true, output, "")

func _cmd_count(args: String, executor_id: String) -> CommandResult:
	var players: Array = _get_online_players()
	return CommandResult.new(true, "Online players: %d" % players.size(), "")

func _cmd_restrict(args: String, executor_id: String) -> CommandResult:
	var parts: Array = args.split(" ", false, 2)
	if parts.size() < 2:
		return CommandResult.new(false, "", "Usage: restrict <player> <type> [duration_sec]")

	var player_id: String = parts[0].strip_edges()
	var restriction_type: String = parts[1].strip_edges()
	var duration: int = 300  # 5 minutes default

	if parts.size() > 2:
		duration = int(parts[2])

	# Use PermissionManager for secured operation
	if PermissionManager:
		var result := PermissionManager.restrict(executor_id, player_id, restriction_type, duration)
		if result.success:
			var type_str: String = restriction_type if restriction_type != "chat" else "mute"
			return CommandResult.new(true, "Restricted %s: %s for %d seconds" % [player_id, type_str, duration], "")
		else:
			return CommandResult.new(false, "", "Failed: %s" % result.message)

	# Fallback
	if not SecurityService:
		return CommandResult.new(false, "", "SecurityService not available")

	SecurityService.restrict_player(player_id, restriction_type, duration)
	var type_str: String = restriction_type if restriction_type != "chat" else "mute"
	return CommandResult.new(true, "Restricted %s: %s for %d seconds" % [player_id, type_str, duration], "")

func _cmd_unrestrict(args: String, executor_id: String) -> CommandResult:
	var parts: Array = args.split(" ", false, 1)
	if parts.is_empty():
		return CommandResult.new(false, "", "Usage: unrestrict <player> [type]")

	var player_id: String = parts[0].strip_edges()
	var restriction_type: String = "" if parts.size() < 2 else parts[1].strip_edges()

	# Use PermissionManager for secured operation
	if PermissionManager:
		var result := PermissionManager.unrestrict(executor_id, player_id, restriction_type)
		if result.success:
			return CommandResult.new(true, "Unrestricted %s" % player_id, "")
		else:
			return CommandResult.new(false, "", "Failed: %s" % result.message)

	# Fallback
	if not SecurityService:
		return CommandResult.new(false, "", "SecurityService not available")

	SecurityService.unrestrict_player(player_id, restriction_type)
	return CommandResult.new(true, "Unrestricted %s" % player_id, "")

func _cmd_restrictions(args: String, executor_id: String) -> CommandResult:
	var player_id: String = args.strip_edges()
	var output: String = "[color=yellow]=== Active Restrictions ===[/color]\n"

	if player_id != "":
		output += "[color=cyan]Player:[/color] %s\n\n" % _esc(player_id)
		if SecurityService:
			var restrictions: Array = SecurityService.get_active_restrictions(player_id)
			if restrictions.is_empty():
				output += "  No active restrictions"
			else:
				for r in restrictions:
					var expires: int = int(r.get("expires_at", 0)) - int(Time.get_unix_time_from_system())
					var time_str: String = "%d seconds" % expires if expires > 0 else "expired"
					output += "  [color=red]%s[/color] - expires in %s\n" % [r.get("type", "?"), time_str]
	else:
		# List all restrictions
		if SecurityService:
			var all: Dictionary = SecurityService.get_all_restrictions()
			if all.is_empty():
				output += "  No active restrictions"
			else:
				for player in all.keys():
					output += "  [color=cyan]%s:[/color] %s\n" % [_esc(player), ", ".join(all[player])]

	return CommandResult.new(true, output, "")

func _cmd_mute(args: String, executor_id: String) -> CommandResult:
	var parts: Array = args.split(" ", false, 1)
	if parts.is_empty():
		return CommandResult.new(false, "", "Usage: mute <player> [duration_sec]")

	var player_id: String = parts[0].strip_edges()
	var duration: int = 300

	if parts.size() > 1:
		duration = int(parts[1])

	# Use PermissionManager for secured operation
	if PermissionManager:
		var result := PermissionManager.mute(executor_id, player_id, duration)
		if result.success:
			return CommandResult.new(true, "Muted %s for %d seconds" % [player_id, duration], "")
		else:
			return CommandResult.new(false, "", "Failed: %s" % result.message)

	# Fallback
	return _cmd_restrict("%s chat %d" % [player_id, duration], executor_id)

func _cmd_unmute(args: String, executor_id: String) -> CommandResult:
	if args == "":
		return CommandResult.new(false, "", "Usage: unmute <player>")

	var player_id: String = args.strip_edges()

	# Use PermissionManager for secured operation
	if PermissionManager:
		var result := PermissionManager.unmute(executor_id, player_id)
		if result.success:
			return CommandResult.new(true, "Unmuted %s" % player_id, "")
		else:
			return CommandResult.new(false, "", "Failed: %s" % result.message)

	# Fallback
	return _cmd_unrestrict("%s chat" % player_id, executor_id)

func _cmd_kick(args: String, executor_id: String) -> CommandResult:
	var parts: Array = args.split(" ", false, 1)
	if parts.is_empty():
		return CommandResult.new(false, "", "Usage: kick <player> [reason]")

	var player_id: String = parts[0].strip_edges()
	var reason: String = "" if parts.size() < 2 else parts[1]

	# Use PermissionManager for secured operation (includes hierarchy check)
	if PermissionManager:
		var result := PermissionManager.kick(executor_id, player_id, reason)
		if result.success:
			return CommandResult.new(true, "Kicked %s: %s" % [player_id, reason], "")
		else:
			return CommandResult.new(false, "", "Failed: %s" % result.message)

	# Fallback (emit signal anyway)
	player_kicked.emit(player_id, reason, executor_id)
	return CommandResult.new(true, "Kicked %s: %s" % [player_id, reason], "")

func _cmd_ban(args: String, executor_id: String) -> CommandResult:
	var parts: Array = args.split(" ", false, 2)
	if parts.is_empty():
		return CommandResult.new(false, "", "Usage: ban <player> [duration_sec] [reason]")

	var player_id: String = parts[0].strip_edges()
	var duration: int = -1  # Permanent

	if parts.size() > 1:
		duration = int(parts[1])

	var reason: String = "" if parts.size() < 3 else parts[2]

	# Use PermissionManager for secured operation (includes hierarchy check)
	if PermissionManager:
		var result := PermissionManager.ban(executor_id, player_id, duration, reason)
		if result.success:
			var dur_str := "permanently" if duration == -1 else "for %d seconds" % duration
			return CommandResult.new(true, "Banned %s %s: %s" % [player_id, dur_str, reason], "")
		else:
			return CommandResult.new(false, "", "Failed: %s" % result.message)

	# Fallback
	if SecurityService:
		var actual_duration: int = 31536000 if duration == -1 else duration
		SecurityService.restrict_player(player_id, "all", actual_duration)

	player_banned.emit(player_id, duration, reason, executor_id)
	var dur_str := "permanently" if duration == -1 else "for %d seconds" % duration
	return CommandResult.new(true, "Banned %s %s: %s" % [player_id, dur_str, reason], "")

func _cmd_qos(args: String, executor_id: String) -> CommandResult:
	if args == "":
		return CommandResult.new(false, "", "Usage: qos <player>")

	var player_id: String = args.strip_edges()
	var output: String = "[color=yellow]=== QoS Status for %s ===[/color]\n" % _esc(player_id)

	var qos := _get_qos_service()
	if qos:
		var rates: Dictionary = qos.get_player_rates(player_id)
		if rates.is_empty():
			output += "  No recent activity"
		else:
			for action in rates.keys():
				var rate: float = rates[action]
				output += "  %s: %.2f/sec\n" % [action, rate]
	else:
		output += "  QoSService not available"

	return CommandResult.new(true, output, "")

func _cmd_rateinfo(args: String, executor_id: String) -> CommandResult:
	var output: String = "[color=yellow]=== Rate Limit Configuration ===[/color]\n"

	var qos := _get_qos_service()
	if qos:
		var info: Dictionary = qos.get_rate_limit_info()
		for action in info.keys():
			var limit: Dictionary = info[action]
			output += "  [color=cyan]%s:[/color] max %.2f/sec\n" % [action, limit.get("max_rate", 0)]

	return CommandResult.new(true, output, "")

func _cmd_clear(args: String, executor_id: String) -> CommandResult:
	return CommandResult.new(true, "", "")  # UI handles clearing

func _cmd_history(args: String, executor_id: String) -> CommandResult:
	var output: String = "[color=yellow]=== Command History ===[/color]\n"

	var limit: int = 20
	if args != "":
		limit = int(args)

	var shown: int = 0
	for cmd in history:
		if shown >= limit:
			break
		output += "  %s\n" % cmd
		shown += 1

	return CommandResult.new(true, output, "")

func _cmd_whoami(args: String, executor_id: String) -> CommandResult:
	var output: String = "[color=yellow]=== Current Admin ===[/color]\n"
	output += "  ID: %s\n" % (_current_executor_id if _current_executor_id != "" else "(none)")

	if SecurityService and _current_executor_id != "":
		var level: int = SecurityService.get_player_permission_level(_current_executor_id)
		output += "  Level: %d\n" % level

	return CommandResult.new(true, output, "")

func _cmd_status(args: String, executor_id: String) -> CommandResult:
	var output: String = "[color=yellow]=== System Status ===[/color]\n"

	# Player count
	var players: Array = _get_online_players()
	output += "[color=green]Players online:[/color] %d\n" % players.size()

	# Restrictions
	if SecurityService:
		var restrictions: Dictionary = SecurityService.get_all_restrictions()
		output += "[color=red]Active restrictions:[/color] %d\n" % restrictions.size()

	# Services
	output += "\n[color=cyan]Services:[/color]\n"
	output += "  SecurityService: %s\n" % ("[color=green]OK[/color]" if SecurityService else "[color=red]OFFLINE[/color]")
	var qos: Object = _get_qos_service()
	output += "  QoSService: %s\n" % ("[color=green]OK[/color]" if qos else "[color=red]OFFLINE[/color]")
	output += "  NotificationService: %s\n" % ("[color=green]OK[/color]" if NotificationService else "[color=red]OFFLINE[/color]")

	return CommandResult.new(true, output, "")

func _cmd_uptime(args: String, executor_id: String) -> CommandResult:
	var elapsed: float = Time.get_ticks_msec() / 1000.0
	var hours: int = int(elapsed / 3600)
	var minutes: int = int(fmod(elapsed, 3600) / 60)
	var seconds: int = int(fmod(elapsed, 60))
	return CommandResult.new(true, "Uptime: %02d:%02d:%02d" % [hours, minutes, seconds], "")

func _cmd_stats(args: String, executor_id: String) -> CommandResult:
	var output: String = "[color=yellow]=== Service Statistics ===[/color]\n"

	var qos: Object = _get_qos_service()
	if qos:
		var stats: Dictionary = qos.get_statistics()
		output += "[color=cyan]QoS:[/color]\n"
		output += "  Total checks: %d\n" % stats.get("total_checks", 0)
		output += "  Rate limited: %d\n" % stats.get("rate_limited_count", 0)

	if SecurityService:
		var stats: Dictionary = SecurityService.get_statistics()
		output += "[color=cyan]Security:[/color]\n"
		output += "  Blocks: %d\n" % stats.get("blocks", 0)
		output += "  Restrictions: %d\n" % stats.get("restrictions", 0)

	return CommandResult.new(true, output, "")

func _cmd_config(args: String, executor_id: String) -> CommandResult:
	var parts: Array = args.split(" ", false, 1)
	var key: String = parts[0] if not parts.is_empty() else ""
	var value: String = parts[1] if parts.size() > 1 else ""

	if key == "":
		return _cmd_toggles("", executor_id)

	# For now, just show the config (no runtime modification)
	return CommandResult.new(false, "", "Runtime config modification not implemented. Use toggles command.")

func _cmd_toggles(args: String, executor_id: String) -> CommandResult:
	var output: String = "[color=yellow]=== Security/QoS Toggles ===[/color]\n"
	output += "[color=cyan]GameConfig.Security:[/color]\n"
	output += "  ENABLE_SECURITY_ALERTS: %s\n" % GameConfig.Security.ENABLE_SECURITY_ALERTS
	output += "  ALERT_ON_RATE_LIMIT: %s\n" % GameConfig.Security.ALERT_ON_RATE_LIMIT
	output += "  ALERT_ON_RESTRICTION: %s\n" % GameConfig.Security.ALERT_ON_UNRESTRICTION
	output += "  ALERT_ON_UNRESTRICTION: %s\n" % GameConfig.Security.ALERT_ON_UNRESTRICTION
	output += "  ALERT_ON_EXPLOIT_DETECTED: %s\n" % GameConfig.Security.ALERT_ON_EXPLOIT_DETECTED

	return CommandResult.new(true, output, "")

## ============================================================================
## HELPER FUNCTIONS
## ============================================================================

func _get_player_info(player_id: String) -> String:
	var info: String = "[color=yellow]=== Player Info: %s ===[/color]\n" % _esc(player_id)

	# Online status
	var online: bool = _is_player_online(player_id)
	info += "[color=cyan]Status:[/color] %s\n" % ("[color=green]Online[/color]" if online else "[color=gray]Offline[/color]")

	# Permissions
	if SecurityService:
		var level: int = SecurityService.get_player_permission_level(player_id)
		var perm_name: String = "Player"
		if level >= GameConfig.Security.ADMIN_LEVEL:
			perm_name = "Admin"
		elif level >= GameConfig.Security.MOD_LEVEL:
			perm_name = "Moderator"
		elif level >= GameConfig.Security.VIP_LEVEL:
			perm_name = "VIP"
		info += "[color=cyan]Permission:[/color] %s (level %d)\n" % [perm_name, level]

	# Restrictions
	if SecurityService:
		var restricted: bool = SecurityService.is_restricted(player_id, "chat")
		if restricted:
			info += "[color=red]MUTED[/color]\n"
		restricted = SecurityService.is_restricted(player_id, "trade")
		if restricted:
			info += "[color=red]TRADE RESTRICTED[/color]\n"

	# QoS rates
	var qos: Object = _get_qos_service()
	if qos:
		var rates: Dictionary = qos.get_player_rates(player_id)
		if not rates.is_empty():
			info += "\n[color=cyan]Recent activity:[/color]\n"
			for action in rates.keys():
				info += "  %s: %.2f/sec\n" % [action, rates[action]]

	return info

func _is_player_online(player_id: String) -> bool:
	# This should check the actual player manager
	# For now, return true if we have any data about them
	return PlayerManager != null and PlayerManager.has_player(player_id)

func _get_online_players() -> Array:
	if PlayerManager:
		return PlayerManager.get_online_player_ids()
	return []

func _cmd_audit(args: String, executor_id: String) -> CommandResult:
	# Parse arguments
	var parts: Array = args.split(" ", false, 3)
	var limit: int = 50
	var admin_filter: String = ""
	var action_filter: String = ""

	if parts.size() >= 1 and parts[0].is_valid_int():
		limit = int(parts[0])
	if parts.size() >= 2:
		admin_filter = parts[1]
	if parts.size() >= 3:
		action_filter = parts[2]

	# Use PermissionManager to get audit log
	if PermissionManager:
		var log: Array = PermissionManager.get_audit_log(limit, admin_filter, action_filter)
		var output: String = "[color=yellow]=== Admin Audit Log ===[/color]\n\n"

		if log.is_empty():
			output += "[color=gray]No audit entries found[/color]"
		else:
			for entry in log:
				var time_str: String = Time.get_datetime_string_from_unix_time(entry.timestamp)
				var status: String = "[color=green][/color]" if entry.success else "[color=red][/color]"
				output += "[%s] %s %s: %s -> %s\n" % [
					time_str,
					status,
					entry.admin_id,
					entry.action,
					entry.target_id if entry.target_id != "" else "(none)"
				]

		return CommandResult.new(true, output, "")

	return CommandResult.new(false, "", "PermissionManager not available")

func _format_player_info(info: Dictionary) -> String:
	var output: String = "[color=yellow]=== Player: %s ===[/color]\n" % _esc(info.get("id", "?"))
	output += "[color=cyan]Level:[/color] %s (Lvl %d)\n" % [_esc(str(info.get("level_name", "?"))), info.get("level", 0)]
	output += "[color=cyan]Online:[/color] %s\n" % ("Yes" if info.get("online", false) else "No")

	if info.get("restricted_chat", false):
		output += "[color=red]MUTED[/color]\n"
	if info.get("restricted_trade", false):
		output += "[color=red]TRADE RESTRICTED[/color]\n"

	var restrictions: Array = info.get("active_restrictions", [])
	if not restrictions.is_empty():
		output += "\n[color=yellow]Active Restrictions:[/color]\n"
		for r in restrictions:
			var expires_in: int = int(r.get("expires_at", 0)) - int(Time.get_unix_time_from_system())
			output += "  - %s (expires in %ds)\n" % [r.get("type", "?"), expires_in]

	return output

## ============================================================================
## GM MOVEMENT COMMANDS
## ============================================================================

func _cmd_invisible(args: String, executor_id: String) -> CommandResult:
	var admin: Object = _get_executor_entity(executor_id)
	if not admin:
		return CommandResult.new(false, "", "Could not find your entity")

	var enable: bool = true
	if args == "0":
		enable = false

	if enable:
		admin.collision_layer = 0b0000000
		admin.collision_mask = 0b0000000
		if admin.has_method("set_visible"):
			admin.set_visible(false)
	else:
		admin.collision_layer = 0b0000001
		admin.collision_mask = 0b0000111
		if admin.has_method("set_visible"):
			admin.set_visible(true)

	return CommandResult.new(true, "You are now %s" % ("invisible" if enable else "visible"), "")

func _cmd_fly(args: String, executor_id: String) -> CommandResult:
	var admin: Object = _get_executor_entity(executor_id)
	if not admin:
		return CommandResult.new(false, "", "Could not find your entity")

	var enable: bool = true
	if args == "0":
		enable = false

	if admin is CharacterBody3D:
		admin.set("gravity_scale", 0.0 if enable else 1.0)

	return CommandResult.new(true, "Fly mode %s" % ("enabled" if enable else "disabled"), "")

func _cmd_noclip(args: String, executor_id: String) -> CommandResult:
	var admin: Object = _get_executor_entity(executor_id)
	if not admin:
		return CommandResult.new(false, "", "Could not find your entity")

	var enable: bool = true
	if args == "0":
		enable = false

	if enable:
		admin.collision_layer = 0b0000000
		admin.collision_mask = 0b0000000
		admin.set("gravity_scale", 0.0)
	else:
		admin.collision_layer = 0b0000001
		admin.collision_mask = 0b0000111
		admin.set("gravity_scale", 1.0)

	return CommandResult.new(true, "Noclip %s" % ("enabled" if enable else "disabled"), "")

func _cmd_speed(args: String, executor_id: String) -> CommandResult:
	var admin: Object = _get_executor_entity(executor_id)
	if not admin:
		return CommandResult.new(false, "", "Could not find your entity")

	if args == "":
		var current: Variant = admin.get("move_speed") if admin.has("move_speed") else "unknown"
		return CommandResult.new(true, "Current speed: %s" % str(current), "")

	var multiplier: float = float(args)
	if multiplier <= 0:
		return CommandResult.new(false, "", "Speed must be > 0")

	if not admin.has("_original_move_speed"):
		admin.set("_original_move_speed", admin.get("move_speed") if admin.has("move_speed") else 5.0)

	var original: float = admin.get("_original_move_speed")
	admin.set("move_speed", original * multiplier)

	return CommandResult.new(true, "Speed set to %.1fx (%.1f)" % [multiplier, original * multiplier], "")

func _cmd_godmode(args: String, executor_id: String) -> CommandResult:
	var admin: Object = _get_executor_entity(executor_id)
	if not admin:
		return CommandResult.new(false, "", "Could not find your entity")

	var enable: bool = true
	if args == "0":
		enable = false

	if not admin.has("is_invincible"):
		admin.set("is_invincible", false)
	admin.set("is_invincible", enable)

	return CommandResult.new(true, "Godmode %s" % ("enabled" if enable else "disabled"), "")

func _cmd_teleport(args: String, executor_id: String) -> CommandResult:
	var admin: Object = _get_executor_entity(executor_id)
	if not admin:
		return CommandResult.new(false, "", "Could not find your entity")

	var parts: Array = args.split(" ", false)
	if parts.is_empty():
		return CommandResult.new(false, "", "Usage: teleport <x> <y> <z> OR <player_id>")

	if parts.size() >= 3:
		var x: float = float(parts[0])
		var y: float = float(parts[1])
		var z: float = float(parts[2])
		admin.global_position = Vector3(x, y, z)
		return CommandResult.new(true, "Teleported to (%.1f, %.1f, %.1f)" % [x, y, z], "")
	else:
		var target_id: String = parts[0]
		var target: Object = _find_entity_by_id_shell(target_id)
		if not target:
			return CommandResult.new(false, "", "Player not found: " + target_id)
		admin.global_position = target.global_position
		return CommandResult.new(true, "Teleported to: %s" % target.display_name, "")

func _cmd_goto_shell(args: String, executor_id: String) -> CommandResult:
	return _cmd_teleport(args, executor_id)

func _cmd_summon(args: String, executor_id: String) -> CommandResult:
	if args == "":
		return CommandResult.new(false, "", "Usage: summon <player_id>")

	var target: Object = _find_entity_by_id_shell(args)
	if not target:
		return CommandResult.new(false, "", "Player not found: " + args)

	var admin: Object = _get_executor_entity(executor_id)
	if not admin:
		return CommandResult.new(false, "", "Could not find your entity")

	target.global_position = admin.global_position
	return CommandResult.new(true, "Summoned: %s" % target.display_name, "")

func _cmd_heal(args: String, executor_id: String) -> CommandResult:
	var admin: Object = _get_executor_entity(executor_id)
	if not admin:
		return CommandResult.new(false, "", "Could not find your entity")

	var target: Object = admin
	var target_name: String = "yourself"

	if args != "":
		target = _find_entity_by_id_shell(args)
		if not target:
			return CommandResult.new(false, "", "Player not found: " + args)
		target_name = target.display_name

	if not target.health_component:
		return CommandResult.new(false, "", "Target has no health component")

	target.health_component.current_health = target.health_component.max_health
	if target.has_method("restore_mana"):
		target.restore_mana(target.max_mana if target.has("max_mana") else 1000)

	return CommandResult.new(true, "Healed %s to full HP" % target_name, "")

func _get_executor_entity(executor_id: String) -> Object:
	if executor_id == "" and PlayerManager:
		var local: Object = PlayerManager.get_local_player()
		return local
	return _find_entity_by_id_shell(executor_id)

func _find_entity_by_id_shell(entity_id: String) -> Object:
	if EntityService:
		var entity: Object = EntityService.get_entity(entity_id)
		if entity:
			return entity
	if PlayerManager:
		var players: Array = PlayerManager.get_all_players()
		for p: Object in players:
			if p.get("entity_id") == entity_id or p.get("name") == entity_id:
				return p as Object
	return null

## ============================================================================
## SIGNALS
## ============================================================================

signal player_kicked(player_id: String, reason: String, admin_id: String)
signal player_banned(player_id: String, duration: int, reason: String, admin_id: String)
