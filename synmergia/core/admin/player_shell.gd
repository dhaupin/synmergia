## PlayerShell - Power user command interface for players
## Provides a customizable command interface for regular players
## Completely separate from admin tools - sandboxed to player actions only
class_name PlayerShell
extends Node

## Escape BBCode brackets in user-supplied strings.
static func _esc(text: String) -> String:
	return text.replace('[', '［').replace(']', '］')

## Player command definition
class PlayerCommand:
	var name: String
	var aliases: Array
	var description: String
	var usage: String
	var category: String  # "info", "settings", "social", "stats"
	var callback: Callable
	var min_level: int  # Permission level required
	
	func _init(p_name: String, p_callback: Callable, p_desc: String = "", p_usage: String = "", 
			p_category: String = "info", p_aliases: Array = [], p_min_level: int = 0):
		name = p_name
		callback = p_callback
		description = p_desc
		usage = p_usage
		category = p_category
		aliases = p_aliases
		min_level = p_min_level

## Command result
class CommandResult:
	var success: bool
	var output: String
	var error: String
	
	func _init(p_success: bool = false, p_output: String = "", p_error: String = ""):
		success = p_success
		output = p_output
		error = p_error

## Player customization data
class PlayerCustomization:
	var aliases: Dictionary = {}  # alias -> command
	var macros: Dictionary = {}   # name -> command string
	var hidden_categories: Array = []
	var theme: String = "default"
	var keybindings: Dictionary = {}  # key -> command
	
	func to_dict() -> Dictionary:
		return {
			"aliases": aliases,
			"macros": macros,
			"hidden_categories": hidden_categories,
			"theme": theme,
			"keybindings": keybindings
		}
	
	func from_dict(data: Dictionary) -> void:
		aliases = data.get("aliases", {})
		macros = data.get("macros", {})
		hidden_categories = data.get("hidden_categories", [])
		theme = data.get("theme", "default")
		keybindings = data.get("keybindings", {})

## Signal when player command is executed
signal command_executed(cmd: String, result: CommandResult, player_id: String)

## All registered player commands
var _commands: Dictionary = {}
var _aliases: Dictionary = {}
var _categories: Array = ["info", "settings", "social", "stats", "custom"]

## Player customizations: player_id -> PlayerCustomization
var _player_customizations: Dictionary = {}

## Current player using this shell
var _current_player_id: String = ""

func _ready() -> void:
	_register_default_commands()
	GameLog.info("PlayerShell: Initialized with %d commands" % _commands.size())

## Register a player command
func register_command(cmd: PlayerCommand) -> void:
	_commands[cmd.name.to_lower()] = cmd
	for alias in cmd.aliases:
		_aliases[alias.to_lower()] = cmd.name.to_lower()

## Register custom command from player
func register_custom_command(player_id: String, name: String, command: String) -> bool:
	# Validate command doesn't conflict with existing
	var actual := name.to_lower()
	if _commands.has(actual) or _aliases.has(actual):
		return false
	
	# Store in player customization
	var custom := _get_player_customization(player_id)
	custom.macros[name] = command
	
	# Create a wrapper command
	var wrapper := PlayerCommand.new(
		name, 
		func(args, pid): return execute_command(command + (" " + args if args else ""), pid),
		"[Custom] Player-created command",
		name,
		"custom",
		[],
		0
	)
	_commands[actual] = wrapper
	
	return true

## Execute a command string
func execute(command_line: String, player_id: String = "") -> CommandResult:
	_current_player_id = player_id
	
	# Check for macro first
	var parts := command_line.strip_edges().split(" ", false, 1)
	var cmd_name := parts[0].to_lower()
	var args := parts[1] if parts.size() > 1 else ""
	
	# Check for player-defined alias
	var custom := _get_player_customization(player_id)
	if custom.aliases.has(cmd_name):
		var alias_cmd := custom.aliases[cmd_name]
		return execute(alias_cmd + (" " + args if args else ""), player_id)
	
	# Check for custom macro
	if custom.macros.has(cmd_name):
		var macro := custom.macros[cmd_name]
		return execute(macro + (" " + args if args else ""), player_id)
	
	# Parse command
	if cmd_name == "":
		return CommandResult.new(false, "", "No command entered. Type 'help' for commands.")
	
	# Check if command exists
	var actual_name := _aliases.get(cmd_name, cmd_name)
	if not _commands.has(actual_name):
		return CommandResult.new(false, "", "Unknown command: %s. Type 'help' for commands." % cmd_name)
	
	var cmd: PlayerCommand = _commands[actual_name]
	
	# Check permission level
	if player_id != "" and not _has_permission(player_id, cmd.min_level):
		return CommandResult.new(false, "", "You don't have permission to use this command.")
	
	# Check if category is hidden
	if cmd.category in custom.hidden_categories:
		return CommandResult.new(false, "", "This command is hidden in your settings.")
	
	# Execute command
	var result: CommandResult
	if cmd.callback.is_valid():
		result = cmd.callback.call(args, player_id)
		if result == null:
			result = CommandResult.new(false, "", "Command execution failed")
	else:
		result = CommandResult.new(false, "", "Command callback invalid")
	
	command_executed.emit(command_line, result, player_id)
	return result

## Get suggestions for tab completion
func get_suggestions(partial: String, player_id: String = "") -> Array:
	var suggestions: Array = []
	var search := partial.to_lower()
	var custom := _get_player_customization(player_id)
	
	# Check player aliases and macros
	for alias in custom.aliases.keys():
		if alias.begins_with(search):
			suggestions.append(alias)
	for macro in custom.macros.keys():
		if macro.begins_with(search) and not macro in suggestions:
			suggestions.append(macro)
	
	# Check registered commands
	for cmd_name in _commands.keys():
		if cmd_name.begins_with(search):
			var cmd: PlayerCommand = _commands[cmd_name]
			if player_id == "" or _has_permission(player_id, cmd.min_level):
				if not cmd_name in suggestions and not cmd.category in custom.hidden_categories:
					suggestions.append(cmd_name)
	
	return suggestions

## Get help text
func get_help(category: String = "") -> String:
	var custom := _get_player_customization(_current_player_id)
	
	if category == "":
		return _get_general_help()
	
	if not category in _categories:
		return "Unknown category: %s" % category
	
	return _get_category_help(category)

func _get_general_help() -> String:
	var custom := _get_player_customization(_current_player_id)
	var help_text := "[color=yellow]=== Player Commands ===[/color]\n"
	help_text += "Type 'help <category>' for detailed commands.\n\n"
	
	var by_category: Dictionary = {}
	for cmd_name in _commands.keys():
		var cmd: PlayerCommand = _commands[cmd_name]
		if cmd.category in custom.hidden_categories:
			continue
		if not by_category.has(cmd.category):
			by_category[cmd.category] = []
		by_category[cmd.category].append(cmd_name)
	
	for cat in _categories:
		if by_category.has(cat):
			help_text += "[color=cyan]%s:[/color] %s\n" % [_esc(cat.capitalize()), ", ".join(by_category[cat])]
	
	help_text += "\n[color=gray]Player Customization:[/color]\n"
	help_text += "  alias <name> <command> - Create alias\n"
	help_text += "  unalias <name> - Remove alias\n"
	help_text += "  macro <name> <commands> - Create macro\n"
	help_text += "  hide <category> - Hide category\n"
	help_text += "  show <category> - Show category\n"
	help_text += "  settings - View customization settings\n"
	
	return help_text

func _get_category_help(category: String) -> String:
	var custom := _get_player_customization(_current_player_id)
	var help_text := "[color=yellow]=== %s Commands ===[/color]\n\n" % category.capitalize()
	
	for cmd_name in _commands.keys():
		var cmd: PlayerCommand = _commands[cmd_name]
		if cmd.category != category:
			continue
		if category in custom.hidden_categories:
			continue
		
		help_text += "  [color=cyan]%s[/color] - %s\n" % [_esc(cmd.name), _esc(cmd.description)]
		if cmd.usage != "":
			help_text += "    Usage: %s\n" % _esc(cmd.usage)
	
	return help_text

func _has_permission(player_id: String, required_level: int) -> bool:
	if required_level <= 0:
		return true
	if PermissionManager:
		return PermissionManager.has_permission(player_id, required_level)
	return false

func _get_player_customization(player_id: String) -> PlayerCustomization:
	if not _player_customizations.has(player_id):
		_player_customizations[player_id] = PlayerCustomization.new()
	return _player_customizations[player_id]

func _register_default_commands() -> void:
	# Info commands
	register_command(PlayerCommand.new("help", _cmd_help, "Show help", "help [category|command]"))
	register_command(PlayerCommand.new("me", _cmd_me, "Show your player info", "me"))
	register_command(PlayerCommand.new("stats", _cmd_stats, "Show your stats", "stats"))
	register_command(PlayerCommand.new("online", _cmd_online, "Show online players", "online [filter]"))
	
	# Settings commands
	register_command(PlayerCommand.new("alias", _cmd_alias, "Create command alias", "alias <name> <command>"))
	register_command(PlayerCommand.new("unalias", _cmd_unalias, "Remove an alias", "unalias <name>"))
	register_command(PlayerCommand.new("macro", _cmd_macro, "Create a macro", "macro <name> <commands>"))
	register_command(PlayerCommand.new("unmacro", _cmd_unmacro, "Remove a macro", "unmacro <name>"))
	register_command(PlayerCommand.new("hide", _cmd_hide, "Hide a category", "hide <category>"))
	register_command(PlayerCommand.new("show", _cmd_show, "Show a hidden category", "show <category>"))
	register_command(PlayerCommand.new("settings", _cmd_settings, "Show your settings", "settings"))
	
	# Social commands
	register_command(PlayerCommand.new("whois", _cmd_whois, "Look up a player", "whois <player>"))
	register_command(PlayerCommand.new("friends", _cmd_friends, "Show friends list", "friends"))
	register_command(PlayerCommand.new("ignore", _cmd_ignore, "Ignore a player", "ignore <player>"))
	register_command(PlayerCommand.new("unignore", _cmd_unignore, "Stop ignoring a player", "unignore <player>"))
	register_command(PlayerCommand.new("muted", _cmd_muted, "Show muted players", "muted"))
	
	# Report commands (requires VIP for abuse reports)
	register_command(PlayerCommand.new("report", _cmd_report, "Report a player", "report <player> <reason>"))
	register_command(PlayerCommand.new("bug", _cmd_bug, "Report a bug", "bug <description>"))
	register_command(PlayerCommand.new("feedback", _cmd_feedback, "Send feedback", "feedback <message>"))

## ============================================================================
## COMMAND IMPLEMENTATIONS
## ============================================================================

func _cmd_help(args: String, player_id: String) -> CommandResult:
	return CommandResult.new(true, get_help(args.strip_edges()), "")

func _cmd_me(args: String, player_id: String) -> CommandResult:
	var output := "[color=yellow]=== Your Info ===[/color]\n"
	output += "[color=cyan]ID:[/color] %s\n" % _esc(player_id)
	
	if PlayerManager and PlayerManager.local_player:
		var data: Dictionary = PlayerManager.local_player
		output += "[color=cyan]Name:[/color] %s\n" % _esc(data.get("name", "Unknown"))
		output += "[color=cyan]Level:[/color] %d\n" % data.get("level", 1)
	
	# Check permissions
	if PermissionManager:
		var level := PermissionManager.get_player_level(player_id)
		var level_name := "Player"
		if level >= PermissionManager.Level.VIP:
			level_name = "VIP"
		if level >= PermissionManager.Level.MOD:
			level_name = "Moderator"
		if level >= PermissionManager.Level.ADMIN:
			level_name = "Admin"
		output += "[color=cyan]Status:[/color] %s\n" % _esc(level_name)
	
	return CommandResult.new(true, output, "")

func _cmd_stats(args: String, player_id: String) -> CommandResult:
	var output := "[color=yellow]=== Your Stats ===[/color]\n"
	
	# Get QoS stats for player
	if QoSService:
		var rates := QoSService.get_player_rates(player_id)
		if not rates.is_empty():
			output += "[color=cyan]Activity:[/color]\n"
			for action in rates.keys():
				output += "  %s: %.2f/sec\n" % [action, rates[action]]
	
	# Get game stats from PlayerManager
	if PlayerManager and PlayerManager.local_player:
		var data: Dictionary = PlayerManager.local_player
		output += "\n[color=cyan]Character:[/color]\n"
		output += "  Kills: %d\n" % data.get("kills", 0)
		output += "  Deaths: %d\n" % data.get("deaths", 0)
		output += "  Playtime: %d hours\n" % data.get("playtime_hours", 0)
	
	return CommandResult.new(true, output, "")

func _cmd_online(args: String, player_id: String) -> CommandResult:
	var filter := args.strip_edges().to_lower()
	var output := "[color=yellow]=== Online Players ===[/color]\n"
	
	var count: int = 0
	var players := []
	if PlayerManager:
		players = PlayerManager.get_online_player_ids()
	
	for pid in players:
		if filter == "" or pid.to_lower().contains(filter):
			output += "  %s\n" % _esc(pid)
			count += 1
	
	output += "\n[color=gray]Total: %d[/color]" % count
	return CommandResult.new(true, output, "")

func _cmd_alias(args: String, player_id: String) -> CommandResult:
	var parts := args.split(" ", false, 1)
	if parts.size() < 2:
		return CommandResult.new(false, "", "Usage: alias <name> <command>")
	
	var alias_name := parts[0].strip_edges().to_lower()
	var command := parts[1].strip_edges()
	
	if alias_name == "" or command == "":
		return CommandResult.new(false, "", "Usage: alias <name> <command>")
	
	# Check if command exists
	var cmd_parts := command.split(" ", false, 1)
	if not _commands.has(cmd_parts[0].to_lower()) and not _aliases.has(cmd_parts[0].to_lower()):
		return CommandResult.new(false, "", "Unknown command: %s" % cmd_parts[0])
	
	var custom := _get_player_customization(player_id)
	custom.aliases[alias_name] = command
	
	_save_player_customization(player_id)
	
	return CommandResult.new(true, "Created alias '%s' for '%s'" % [alias_name, command], "")

func _cmd_unalias(args: String, player_id: String) -> CommandResult:
	var alias_name := args.strip_edges().to_lower()
	
	if alias_name == "":
		return CommandResult.new(false, "", "Usage: unalias <name>")
	
	var custom := _get_player_customization(player_id)
	if custom.aliases.has(alias_name):
		custom.aliases.erase(alias_name)
		_save_player_customization(player_id)
		return CommandResult.new(true, "Removed alias '%s'" % alias_name, "")
	
	return CommandResult.new(false, "", "Alias '%s' not found" % alias_name)

func _cmd_macro(args: String, player_id: String) -> CommandResult:
	var parts := args.split(" ", false, 1)
	if parts.size() < 2:
		return CommandResult.new(false, "", "Usage: macro <name> <commands>")
	
	var macro_name := parts[0].strip_edges().to_lower()
	var commands := parts[1].strip_edges()
	
	if macro_name == "" or commands == "":
		return CommandResult.new(false, "", "Usage: macro <name> <commands>")
	
	var custom := _get_player_customization(player_id)
	custom.macros[macro_name] = commands
	
	_save_player_customization(player_id)
	
	return CommandResult.new(true, "Created macro '%s'" % macro_name, "")

func _cmd_unmacro(args: String, player_id: String) -> CommandResult:
	var macro_name := args.strip_edges().to_lower()
	
	if macro_name == "":
		return CommandResult.new(false, "", "Usage: unmacro <name>")
	
	var custom := _get_player_customization(player_id)
	if custom.macros.has(macro_name):
		custom.macros.erase(macro_name)
		_save_player_customization(player_id)
		return CommandResult.new(true, "Removed macro '%s'" % macro_name, "")
	
	return CommandResult.new(false, "", "Macro '%s' not found" % macro_name)

func _cmd_hide(args: String, player_id: String) -> CommandResult:
	var category := args.strip_edges().to_lower()
	
	if category == "":
		return CommandResult.new(false, "", "Usage: hide <category>")
	
	if not category in _categories:
		return CommandResult.new(false, "", "Unknown category: %s" % category)
	
	var custom := _get_player_customization(player_id)
	if not category in custom.hidden_categories:
		custom.hidden_categories.append(category)
		_save_player_customization(player_id)
	
	return CommandResult.new(true, "Hidden '%s' category" % category, "")

func _cmd_show(args: String, player_id: String) -> CommandResult:
	var category := args.strip_edges().to_lower()
	
	if category == "":
		return CommandResult.new(false, "", "Usage: show <category>")
	
	var custom := _get_player_customization(player_id)
	if category in custom.hidden_categories:
		custom.hidden_categories.erase(category)
		_save_player_customization(player_id)
	
	return CommandResult.new(true, "Showing '%s' category" % category, "")

func _cmd_settings(args: String, player_id: String) -> CommandResult:
	var custom := _get_player_customization(player_id)
	var output := "[color=yellow]=== Your Settings ===[/color]\n"
	
	output += "\n[color=cyan]Aliases (%d):[/color]\n" % custom.aliases.size()
	for alias in custom.aliases.keys():
		output += "  %s -> %s\n" % [_esc(alias), _esc(custom.aliases[alias])]
	
	output += "\n[color=cyan]Macros (%d):[/color]\n" % custom.macros.size()
	for macro in custom.macros.keys():
		output += "  %s -> %s\n" % [macro, custom.macros[macro]]
	
	output += "\n[color=cyan]Hidden Categories:[/color] %s\n" % ", ".join(custom.hidden_categories) if custom.hidden_categories else "None"
	
	output += "\n[color=cyan]Commands:[/color]\n"
	output += "  alias <name> <cmd> - Create alias\n"
	output += "  macro <name> <cmds> - Create macro\n"
	output += "  hide/show <cat> - Toggle category visibility\n"
	
	return CommandResult.new(true, output, "")

func _cmd_whois(args: String, player_id: String) -> CommandResult:
	if args == "":
		return CommandResult.new(false, "", "Usage: whois <player>")
	
	var target: Variant = args.strip_edges()
	
	# Use PermissionManager for lookup
	if PermissionManager:
		var result := PermissionManager.lookup_player(player_id, target)
		if result.success:
			return CommandResult.new(true, _format_player_info(result.info), "")
		else:
			return CommandResult.new(false, "", result.message)
	
	return CommandResult.new(false, "", "Player not found: %s" % target)

func _cmd_friends(args: String, player_id: String) -> CommandResult:
	# Placeholder - would integrate with social system
	var output := "[color=yellow]=== Friends ===[/color]\n"
	output += "[color=gray]No friends system configured[/color]"
	return CommandResult.new(true, output, "")

func _cmd_ignore(args: String, player_id: String) -> CommandResult:
	if args == "":
		return CommandResult.new(false, "", "Usage: ignore <player>")
	
	var target: Variant = args.strip_edges()
	
	# Use ChatService ignore system
	if ChatService:
		ChatService.ignore_player(player_id, target)
		return CommandResult.new(true, "Ignored %s" % target, "")
	
	return CommandResult.new(false, "", "Ignore system not available")

func _cmd_unignore(args: String, player_id: String) -> CommandResult:
	if args == "":
		return CommandResult.new(false, "", "Usage: unignore <player>")
	
	var target: Variant = args.strip_edges()
	
	if ChatService:
		ChatService.unignore_player(player_id, target)
		return CommandResult.new(true, "Stopped ignoring %s" % target, "")
	
	return CommandResult.new(false, "", "Ignore system not available")

func _cmd_muted(args: String, player_id: String) -> CommandResult:
	var output := "[color=yellow]=== Ignored Players ===[/color]\n"
	
	if ChatService:
		var ignored := ChatService.get_ignored_players(player_id)
		if ignored.is_empty():
			output += "[color=gray]No ignored players[/color]"
		else:
			for pid in ignored:
				output += "  %s\n" % pid
	else:
		output += "[color=gray]Ignore system not available[/color]"
	
	return CommandResult.new(true, output, "")

func _cmd_report(args: String, player_id: String) -> CommandResult:
	# Require VIP level for abuse reports
	if not _has_permission(player_id, PermissionManager.Level.VIP if PermissionManager else 10):
		return CommandResult.new(false, "", "VIP membership required to submit reports.")
	
	var parts := args.split(" ", false, 1)
	if parts.size() < 2:
		return CommandResult.new(false, "", "Usage: report <player> <reason>")
	
	var target: Variant = parts[0].strip_edges()
	var reason := parts[1].strip_edges()
	
	# Use PlayerReporter
	if PlayerReporter:
		PlayerReporter.submit_report(player_id, PlayerReporter.ReportType.ABUSE, {
			"target": target,
			"reason": reason
		})
		return CommandResult.new(true, "Report submitted for %s. Thank you." % target, "")
	
	return CommandResult.new(false, "", "Report system not available")

func _cmd_bug(args: String, player_id: String) -> CommandResult:
	if args == "":
		return CommandResult.new(false, "", "Usage: bug <description>")
	
	var description := args.strip_edges()
	
	# Use PlayerReporter
	if PlayerReporter:
		PlayerReporter.submit_report(player_id, PlayerReporter.ReportType.BUG, {
			"description": description
		})
		return CommandResult.new(true, "Bug report submitted. Thank you!", "")
	
	return CommandResult.new(false, "", "Report system not available")

func _cmd_feedback(args: String, player_id: String) -> CommandResult:
	if args == "":
		return CommandResult.new(false, "", "Usage: feedback <message>")
	
	var message: Dictionary = args.strip_edges()
	
	# Use PlayerReporter
	if PlayerReporter:
		PlayerReporter.submit_report(player_id, PlayerReporter.ReportType.FEEDBACK, {
			"message": message
		})
		return CommandResult.new(true, "Feedback submitted. Thank you!", "")
	
	return CommandResult.new(false, "", "Feedback system not available")

func _format_player_info(info: Dictionary) -> String:
	var output := "[color=yellow]=== Player: %s ===[/color]\n" % info.get("id", "?")
	output += "[color=cyan]Level:[/color] %s\n" % info.get("level_name", "?")
	output += "[color=cyan]Online:[/color] %s\n" % ("Yes" if info.get("online", false) else "No")
	return output

## ============================================================================
## PERSISTENCE (for player customizations)
## ============================================================================

func _save_player_customization(player_id: String) -> void:
	var custom := _get_player_customization(player_id)
	var data: Dictionary = custom.to_dict()
	
	# In production, this would save to database
	# For now, just log
	GameLog.debug("PlayerShell: Saved customization for %s: %s" % [player_id, JSON.stringify(data)])
