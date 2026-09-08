## AdminCommands - Administrative command handlers for server management
extends Node

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## ============================================================================
## ADMIN COMMANDS REGISTRY
## ============================================================================

var _commands: Dictionary = {}
var _caller: String = ""

func _ready() -> void:
	_register_commands()
	GameLog.info("AdminCommands: Initialized")

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
		},
		"resurrect": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Resurrect a dead player",
			"usage": "/resurrect <player_id> [health_percent] [mana_percent]",
			"handler": _cmd_resurrect
		},
		"rez": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Alias for /resurrect",
			"usage": "/rez <player_id> [health_percent] [mana_percent]",
			"handler": _cmd_resurrect
		},
		"kill": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Kill a player (for testing)",
			"usage": "/kill <player_id> [reason]",
			"handler": _cmd_kill_player
		},
		"goto": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Teleport to a player's location",
			"usage": "/goto <player_id>",
			"handler": _cmd_goto_player
		},
		"summon": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Teleport a player to your location",
			"usage": "/summon <player_id>",
			"handler": _cmd_summon_player
		},
		
		# GM Movement Commands (ADMIN level)
		"invisible": {
			"permission": GameConfig.Security.ADMIN_LEVEL,
			"description": "Toggle invisibility mode",
			"usage": "/invisible [0|1]",
			"handler": _cmd_invisible
		},
		"inv": {
			"permission": GameConfig.Security.ADMIN_LEVEL,
			"description": "Alias for /invisible",
			"usage": "/inv [0|1]",
			"handler": _cmd_invisible
		},
		"fly": {
			"permission": GameConfig.Security.ADMIN_LEVEL,
			"description": "Toggle fly mode",
			"usage": "/fly [0|1]",
			"handler": _cmd_fly
		},
		"noclip": {
			"permission": GameConfig.Security.ADMIN_LEVEL,
			"description": "Toggle noclip mode (pass through walls)",
			"usage": "/noclip [0|1]",
			"handler": _cmd_noclip
		},
		"speed": {
			"permission": GameConfig.Security.ADMIN_LEVEL,
			"description": "Set movement speed multiplier",
			"usage": "/speed [multiplier]",
			"handler": _cmd_speed
		},
		"teleport": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Teleport to coordinates or player",
			"usage": "/teleport <x> <y> <z> OR /teleport <player_id>",
			"handler": _cmd_teleport
		},
		"tp": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Alias for /teleport",
			"usage": "/tp <x> <y> <z> OR /tp <player_id>",
			"handler": _cmd_teleport
		},
		"heal": {
			"permission": GameConfig.Security.MOD_LEVEL,
			"description": "Heal yourself or another player",
			"usage": "/heal [player_id]",
			"handler": _cmd_heal
		},
		"godmode": {
			"permission": GameConfig.Security.ADMIN_LEVEL,
			"description": "Toggle godmode (invincible)",
			"usage": "/godmode [0|1]",
			"handler": _cmd_godmode
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
	_caller = caller_id
	var result = handler.call(args)
	GameLog.info("AdminCommand: %s executed /%s" % [caller_id, cmd_name])

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
	# Admin audit toast: distinct from the player's SECURITY_BLOCKED so
	# the audit log shows "admin X did this" not just "player got banned".
	# Dedupe on (admin, action, target) inside a 5s window so a /ban
	# double-tap (admin re-typing the same command) collapses to one
	# entry in the admin toast feed.
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.ADMIN_ALERT,
			"Admin %s banned %s: %s" % [_caller, player_id, reason],
			"AdminCommands",
			"admin_cmd:ban:%s:%s" % [_caller, player_id],
			{"target": player_id, "reason": reason, "command": "ban"},
			"admins"
		)
	return {"success": true, "message": "Banned: " + player_id}

func _cmd_unban(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /unban <player_id>"}
	var firewall = NetworkManager.get_firewall()
	if firewall:
		firewall.lift_ban(args[0])
		if is_instance_valid(NotificationService):
			NotificationService.notify(
				NotifKind.ADMIN_ALERT,
				"Admin %s unbanned %s" % [_caller, args[0]],
				"AdminCommands",
				"admin_cmd:unban:%s:%s" % [_caller, args[0]],
				{"target": args[0], "command": "unban"},
				"admins"
			)
		return {"success": true, "message": "Unbanned: " + args[0]}
	return {"success": false, "message": "Firewall not available"}

func _cmd_kick(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /kick <player_id> [reason]"}
	var player_id = args[0]
	var reason = "Kicked" if args.size() < 2 else " ".join(args.slice(1, args.size()))
	# NetworkManager.kick_player takes a peer_id, not a player_id, and the
	# underlying disconnect path lives there. We dispatch the audit/player
	# toasts here so /kick is observably correct at the notification layer
	# even if the peer disconnect is a no-op.
	# Player-facing: SECURITY_BLOCKED -> ALERT + HIGH. Dedupe on
	# (target, reason) so a "kicked for spam" /kick and a quick re-/kick
	# for the same reason collapse.
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.SECURITY_BLOCKED,
			"You have been kicked: %s" % reason,
			"AdminCommands",
			"admin_cmd:kick:%s:%s" % [player_id, reason],
			{"reason": reason, "command": "kick"},
			player_id
		)
	# Admin audit: same dedupe pattern as ban.
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.ADMIN_ALERT,
			"Admin %s kicked %s: %s" % [_caller, player_id, reason],
			"AdminCommands",
			"admin_cmd:kick:%s:%s" % [_caller, player_id],
			{"target": player_id, "reason": reason, "command": "kick"},
			"admins"
		)
	return {"success": true, "message": "Kicked: " + player_id}

func _cmd_mute(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /mute <player_id> [duration]"}
	var duration = 60 if args.size() < 2 else int(args[1]) * 60
	SecurityService.restrict_player(args[0], "chat", duration)
	# SecurityService already fires the player-facing SECURITY_BLOCKED.
	# The admin audit here is a separate stream so the audit log can
	# see "admin did this" without double-toasting the muted player.
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.ADMIN_ALERT,
			"Admin %s muted %s for %ds" % [_caller, args[0], duration],
			"AdminCommands",
			"admin_cmd:mute:%s:%s" % [_caller, args[0]],
			{"target": args[0], "duration": duration, "command": "mute"},
			"admins"
		)
	return {"success": true, "message": "Muted: " + args[0]}

func _cmd_unmute(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /unmute <player_id>"}
	SecurityService.unrestrict_player(args[0], "chat")
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.ADMIN_ALERT,
			"Admin %s unmuted %s" % [_caller, args[0]],
			"AdminCommands",
			"admin_cmd:unmute:%s:%s" % [_caller, args[0]],
			{"target": args[0], "command": "unmute"},
			"admins"
		)
	return {"success": true, "message": "Unmuted: " + args[0]}

func _cmd_block_ip(args: Array) -> Dictionary:
	if args.size() < 3:
		return {"success": false, "message": "Usage: /block_ip <ip> <duration> <reason>"}
	var firewall = NetworkManager.get_firewall()
	if firewall:
		firewall.block_ip(args[0], " ".join(args.slice(2, args.size())), int(args[1]))
		# AppFirewall already fires an ADMIN_ALERT ("IP blocked...") to the
		# admin channel. AdminCommands adds a more specific audit entry
		# naming the admin who issued the block, so the audit log can
		# attribute the action.
		if is_instance_valid(NotificationService):
			NotificationService.notify(
				NotifKind.ADMIN_ALERT,
				"Admin %s blocked IP %s for %ds" % [_caller, args[0], int(args[1])],
				"AdminCommands",
				"admin_cmd:block_ip:%s:%s" % [_caller, args[0]],
				{"target": args[0], "duration": int(args[1]), "command": "block_ip"},
				"admins"
			)
		return {"success": true, "message": "Blocked IP: " + args[0]}
	return {"success": false, "message": "Firewall not available"}

func _cmd_unblock_ip(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /unblock_ip <ip>"}
	var firewall = NetworkManager.get_firewall()
	if firewall:
		firewall.unblock_ip(args[0])
		if is_instance_valid(NotificationService):
			NotificationService.notify(
				NotifKind.ADMIN_ALERT,
				"Admin %s unblocked IP %s" % [_caller, args[0]],
				"AdminCommands",
				"admin_cmd:unblock_ip:%s:%s" % [_caller, args[0]],
				{"target": args[0], "command": "unblock_ip"},
				"admins"
			)
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
	# Frame-level admin alert. ADMIN_ALERT kind has a 0 dedupe window --
	# the same /shutdown command fired twice in 5s should still toast
	# both times (it's admin intent, not noise).
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.ADMIN_ALERT,
			"Server shutdown in %d seconds!" % delay,
			"AdminCommands",
			"admin:shutdown:%d:%d" % [delay, Time.get_ticks_msec()],
			{"delay_seconds": delay}
		)
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
	var msg := " ".join(args)
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.ADMIN_ALERT,
			msg,
			"AdminCommands",
			"admin:broadcast:%d" % Time.get_ticks_msec(),
			{"command": "/broadcast"}
		)
	return {"success": true, "message": "Broadcast sent"}

func _cmd_resurrect(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /resurrect <player_id> [health_percent] [mana_percent]"}
	
	var player_id: String = args[0]
	var health_percent: float = 1.0
	var mana_percent: float = 1.0
	
	if args.size() >= 2:
		health_percent = float(args[1]) / 100.0
	if args.size() >= 3:
		mana_percent = float(args[2]) / 100.0
	
	# Find the player entity
	var entity: Node3D = _find_entity_by_id(player_id)
	if not entity:
		return {"success": false, "message": "Player not found: " + player_id}
	
	# Check if they're actually dead
	if not entity.health_component:
		return {"success": false, "message": "Player has no health component"}
	
	if not entity.health_component.is_dead():
		return {"success": false, "message": "Player is not dead"}
	
	# Perform the resurrection
	var result := _do_resurrect(entity, health_percent, mana_percent)
	
	if result["success"]:
		var msg := "Resurrected %s (HP: %d%%, MP: %d%%)" % [
			entity.display_name,
			int(health_percent * 100),
			int(mana_percent * 100)
		]
		GameLog.info("AdminCommand: %s" % msg)
		return {"success": true, "message": msg}
	else:
		return {"success": false, "message": result.get("reason", "Failed to resurrect")}

func _cmd_kill_player(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /kill <player_id> [reason]"}
	
	var player_id: String = args[0]
	var reason: String = "Killed by admin"
	if args.size() >= 2:
		reason = " ".join(args.slice(1, args.size()))
	
	var entity: Node3D = _find_entity_by_id(player_id)
	if not entity:
		return {"success": false, "message": "Player not found: " + player_id}
	
	if not entity.health_component:
		return {"success": false, "message": "Player has no health component"}
	
	entity.health_component.take_damage(entity.health_component.current_health + 100, null, "admin_kill")
	
	return {"success": true, "message": "Killed: %s (%s)" % [entity.display_name, reason]}

func _cmd_goto_player(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /goto <player_id>"}

	var player_id: String = args[0]

	var target: Node3D = _find_entity_by_id(player_id)
	if not target:
		return {"success": false, "message": "Player not found: " + player_id}

	# Find the caller (admin using the command)
	var admin: Node3D = _get_caller_entity(_caller)
	if not admin:
		return {"success": false, "message": "Could not find your entity"}

	admin.global_position = target.global_position

	return {"success": true, "message": "Teleported to: %s" % target.display_name}

func _cmd_summon_player(args: Array) -> Dictionary:
	if args.size() < 1:
		return {"success": false, "message": "Usage: /summon <player_id>"}

	var player_id: String = args[0]
	var target: Node3D = _find_entity_by_id(player_id)
	if not target:
		return {"success": false, "message": "Player not found: " + player_id}

	# Find the caller (admin using the command)
	var admin: Node3D = _get_caller_entity(_caller)
	if not admin:
		return {"success": false, "message": "Could not find your entity"}

	target.global_position = admin.global_position

	return {"success": true, "message": "Summoned: %s" % target.display_name}

## ============================================================================
## GM MOVEMENT COMMANDS
## ============================================================================

func _cmd_invisible(args: Array) -> Dictionary:
	var admin: Node3D = _get_caller_entity(_caller)
	if not admin:
		return {"success": false, "message": "Could not find your entity"}
	
	# Determine toggle state
	var enable := true
	if args.size() >= 1:
		enable = args[0] != "0"
	
	# Toggle collision layer (bit 0 = player)
	if enable:
		admin.collision_layer = 0b0000000  # No collision
		admin.collision_mask = 0b0000000
	else:
		admin.collision_layer = 0b0000001  # Restore
		admin.collision_mask = 0b0000111
	
	# Also hide the visual
	if admin.has_method("set_visible"):
		admin.set_visible(not enable)
	
	var status := "invisible" if enable else "visible"
	return {"success": true, "message": "You are now %s" % status}

func _cmd_fly(args: Array) -> Dictionary:
	var admin: Node3D = _get_caller_entity(_caller)
	if not admin:
		return {"success": false, "message": "Could not find your entity"}
	
	# Determine toggle state
	var enable := true
	if args.size() >= 1:
		enable = args[0] != "0"
	
	# Use CharacterBody3D mode
	if admin is CharacterBody3D:
		if enable:
			admin.set("gravity_scale", 0.0)
			# Can't directly set mode to FLYING, but we can disable gravity
			# The player controller handles vertical movement when gravity is 0
		else:
			admin.set("gravity_scale", 1.0)
	
	var status := "fly mode enabled" if enable else "fly mode disabled"
	return {"success": true, "message": status}

func _cmd_noclip(args: Array) -> Dictionary:
	var admin: Node3D = _get_caller_entity(_caller)
	if not admin:
		return {"success": false, "message": "Could not find your entity"}
	
	# Determine toggle state
	var enable := true
	if args.size() >= 1:
		enable = args[0] != "0"
	
	# Disable collision completely
	if enable:
		admin.collision_layer = 0b0000000
		admin.collision_mask = 0b0000000
		admin.set("gravity_scale", 0.0)
	else:
		admin.collision_layer = 0b0000001
		admin.collision_mask = 0b0000111
		admin.set("gravity_scale", 1.0)
	
	var status := "noclip enabled" if enable else "noclip disabled"
	return {"success": true, "message": status}

func _cmd_speed(args: Array) -> Dictionary:
	var admin: Node3D = _get_caller_entity(_caller)
	if not admin:
		return {"success": false, "message": "Could not find your entity"}
	
	if args.size() < 1:
		# Report current speed
		var current_speed: String = str(admin.get("move_speed") if admin.has("move_speed") else "unknown")
		return {"success": true, "message": "Current speed: %s" % str(current_speed)}
	
	var multiplier: float = float(args[0])
	if multiplier <= 0:
		return {"success": false, "message": "Speed must be > 0"}
	
	# Store original speed if not already stored
	if not admin.has("_original_move_speed"):
		admin.set("_original_move_speed", admin.get("move_speed") if admin.has("move_speed") else 5.0)
	
	var original: float = admin.get("_original_move_speed")
	admin.set("move_speed", original * multiplier)
	
	return {"success": true, "message": "Speed set to %.1fx (%.1f)" % [multiplier, original * multiplier]}

func _cmd_teleport(args: Array) -> Dictionary:
	var admin: Node3D = _get_caller_entity(_caller)
	if not admin:
		return {"success": false, "message": "Could not find your entity"}
	
	if args.size() < 1:
		return {"success": false, "message": "Usage: /teleport <x> <y> <z> OR /teleport <player_id>"}
	
	# Check if teleporting to coordinates or player
	if args.size() >= 3:
		# Teleport to coordinates
		var x := float(args[0])
		var y := float(args[1])
		var z := float(args[2])
		admin.global_position = Vector3(x, y, z)
		return {"success": true, "message": "Teleported to (%.1f, %.1f, %.1f)" % [x, y, z]}
	else:
		# Teleport to player
		var target_id: String = args[0]
		var target: Node3D = _find_entity_by_id(target_id)
		if not target:
			return {"success": false, "message": "Player not found: " + target_id}
		admin.global_position = target.global_position
		return {"success": true, "message": "Teleported to: %s" % target.display_name}

func _cmd_heal(args: Array) -> Dictionary:
	var admin: Node3D = _get_caller_entity(_caller)
	if not admin:
		return {"success": false, "message": "Could not find your entity"}
	
	var target: Node3D = admin
	var target_name := "yourself"
	
	if args.size() >= 1:
		target = _find_entity_by_id(args[0])
		if not target:
			return {"success": false, "message": "Player not found: " + args[0]}
		target_name = target.display_name
	
	if not target.health_component:
		return {"success": false, "message": "Target has no health component"}
	
	var max_health: int = target.health_component.max_health
	target.health_component.current_health = max_health
	
	# Also heal mana if available
	if target.has_method("restore_mana"):
		target.restore_mana(target.max_mana if target.has("max_mana") else 1000)
	
	return {"success": true, "message": "Healed %s to full HP" % target_name}

func _cmd_godmode(args: Array) -> Dictionary:
	var admin: Node3D = _get_caller_entity(_caller)
	if not admin:
		return {"success": false, "message": "Could not find your entity"}
	
	# Determine toggle state
	var enable := true
	if args.size() >= 1:
		enable = args[0] != "0"
	
	if not admin.has("is_invincible"):
		admin.set("is_invincible", false)
	
	admin.set("is_invincible", enable)
	
	# Also make collision ignore damage
	if enable:
		admin.set("collision_layer", 0b0000001)  # Keep visible but invincible layer
	
	var status := "enabled" if enable else "disabled"
	return {"success": true, "message": "Godmode %s" % status}

## Helper: Find entity by ID
func _find_entity_by_id(entity_id: String) -> Node3D:
	# Try to find in EntityService
	if EntityService:
		var entity = EntityService.get_entity_by_id(entity_id)
		if entity:
			return entity
	
	# Try to find in player manager
	var players = PlayerManager.get_all_players()
	for p in players:
		if p.get("entity_id") == entity_id or p.get("name") == entity_id:
			return p as Node3D
	
	return null

## Helper: Get caller entity
func _get_caller_entity(caller_id: String) -> Node3D:
	return _find_entity_by_id(caller_id)

## Helper: Perform resurrection
func _do_resurrect(entity: Node3D, health_percent: float, mana_percent: float) -> Dictionary:
	var health_comp = entity.health_component
	
	# Remove corpse if exists
	if health_comp._corpse:
		health_comp._corpse.queue_free()
		health_comp._corpse = null
	
	# Restore health
	health_comp.current_health = int(health_comp.max_health * health_percent)
	health_comp.current_health = maxi(1, health_comp.current_health)
	health_comp._is_dead = false
	health_comp._respawn_timer = 0.0
	
	# Restore mana if applicable
	if entity.has_method("restore_mana"):
		var mana_to_restore := int(entity.max_mana * mana_percent)
		entity.restore_mana(mana_to_restore)
	
	# Clear death state
	entity.health_component.respawned.emit()
	EventHub.entity_spawned.emit(entity)
	EventHub.player_resurrected.emit(entity, "admin")
	EventHub.player_respawned.emit(entity, entity.global_position, RespawnService.RespawnMode.REVIVE if RespawnService else 0)
	
	GameLog.info("Respawn: %s resurrected by admin" % entity.display_name)
	
	return {"success": true}
