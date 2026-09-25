## ChatService - Chat channels and messaging
## Handles all chat channels, filters, commands, and channel permissions
extends Node
# QoSService uses static shim methods (AGENTS.md allowlist); the const is required.
const QoSService = preload("res://core/autoload/qos_service.gd")
const CharacterData = preload("res://core/schemas/character_data.gd")
const DictStore = preload("res://adapters/persistence/dict_store.gd")

const SpawnMetadata = preload("res://core/events/spawn_metadata.gd")
# Entity is not an autoload (class_name only). ChatService uses
# Entity.EntityType.X in range checks, which requires Entity's
# class_name registered at parse time. Preload it here.
const Entity = preload("res://core/entities/entity.gd")
# Frame-level notification dispatch (typed-Kind pipeline).
# All chat-service-toasts are feedback to the sender about their own
# blocked/limited message (rate-limit, validation, restriction), so
# the Kind is SECURITY_BLOCKED uniformly.
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

# Chat channels
enum Channel {
				SAY = 0,					# Local say
				WHISPER = 1,			# Private message
				YELL = 2,					# Large radius shout
				ZONE = 3,					# Zone-wide chat
				GLOBAL = 4,				# Server-wide chat
				PARTY = 5,				# Party chat
				GUILD = 6,				# Guild chat
				ALLIANCE = 7,			# Alliance chat
				TRADE = 8,				# Trade channel
				SYSTEM = 9,				# System messages
				COMBAT = 10,			# Combat log
				EMOTE = 11				# Emotes
}


## BBCode escape for user-supplied content.
static func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")

# Channel info
var _channel_info: Dictionary = {
				Channel.SAY: {"name": "Say", "range": 20.0, "color": "#FFFFFF", "prefix": ""},
				Channel.WHISPER: {"name": "Whisper", "range": 0.0, "color": "#FF99FF", "prefix": "From"},
				Channel.YELL: {"name": "Yell", "range": 100.0, "color": "#FFFF00", "prefix": ""},
				Channel.ZONE: {"name": "Zone", "range": 0.0, "color": "#00FF00", "prefix": ""},
				Channel.GLOBAL: {"name": "Global", "range": 0.0, "color": "#00FFFF", "prefix": ""},
				Channel.PARTY: {"name": "Party", "range": 0.0, "color": "#00FF88", "prefix": "[Party]"},
				Channel.GUILD: {"name": "Guild", "range": 0.0, "color": "#FFAA00", "prefix": "[Guild]"},
				Channel.ALLIANCE: {"name": "Alliance", "range": 0.0, "color": "#FF8800", "prefix": "[Alliance]"},
				Channel.TRADE: {"name": "Trade", "range": 0.0, "color": "#FFFF88", "prefix": "[Trade]"},
				Channel.SYSTEM: {"name": "System", "range": 0.0, "color": "#FF0000", "prefix": "[System]"},
				Channel.COMBAT: {"name": "Combat", "range": 0.0, "color": "#FF4444", "prefix": ""},
				Channel.EMOTE: {"name": "Emote", "range": 20.0, "color": "#FFAAFF", "prefix": ""}
}

# Player chat settings (entity_id -> settings)
var _player_settings: Dictionary = {}

# Player ignored list (entity_id -> [ignored_ids])
var _ignored_players: Dictionary = {}

# Chat history (limited per channel)
var _chat_history: Dictionary = {}
const MAX_HISTORY_PER_CHANNEL: int = GameConfig.Chat.MAX_HISTORY_PER_CHANNEL

# Channel subscriptions (entity_id -> [channels])
var _subscriptions: Dictionary = {}

# Spam protection
var _player_last_message: Dictionary = {}	 # entity_id -> timestamp
const SPAM_COOLDOWN_MS: int = 500	 # Half second between messages
const SPAM_THRESHOLD: int = 5	 # Messages per time window
const MAX_MESSAGE_LENGTH: int = GameConfig.Chat.MAX_MESSAGE_LENGTH
var _spam_count: Dictionary = {}	# entity_id -> count

# Whisper tracking (sender_id -> last whisper target entity_id)
var _player_last_whisper: Dictionary = {}

# Profanity filter - loaded from config file at runtime
var _profanity_list: Array = []
var _profanity_filter_enabled: bool = true

signal message_received(sender_id: String, channel: Channel, message: String, targets: Array)
signal channel_joined(entity_id: String, channel: Channel)
signal channel_left(entity_id: String, channel: Channel)
signal player_chat_ignored(ignorer_id: String, ignored_id: String)
signal player_chat_unignored(ignorer_id: String, ignored_id: String)
signal channel_settings_changed(entity_id: String, channel: Channel)

const _kv_ignored := "chat:ignored:"
const _kv_player_settings := "chat:settings:"

func _ready() -> void:
	GameLog.info("ChatService: Ready")

		# Initialize history for each channel
	for channel in Channel:
		_chat_history[channel] = []

		# Load profanity filter words from config file
	_load_profanity_list()

## Open a whisper chat with a target player
func open_whisper(target_id: String) -> void:
	if not target_id.is_empty():
		# Store this as the last whisper target for reply functionality
		if PlayerManager:
			var sender_id := str(PlayerManager.get_local_player_id())
			if not sender_id.is_empty():
				_player_last_whisper[sender_id] = target_id
		# Emit signal so UI can focus on whisper input
		whisper_opened.emit(target_id)

signal whisper_opened(target_id: String)

## Send a message
func send_message(sender_id: String, channel: Channel, message: String, target_id: String = "") -> bool:
		# Security: Check channel-specific restrictions
	var restriction_msg := _get_channel_restriction_message(sender_id, channel)
	if restriction_msg != "":
		_notify_player(sender_id, restriction_msg)
		return false

		# QoS: Rate limit chat messages (player is already notified by QoSService)
	var action_type = "chat" if channel != Channel.WHISPER else "whisper"
	if not QoSService.rate_limit(sender_id, action_type):
		return false

		# Security: Validate message content
	var validation := SecurityService.validate_message(message, sender_id)
	if not validation.valid:
		_notify_player(sender_id, "Message blocked: %s" % validation.reason)
		return false
	message = validation.sanitized

		# Truncate message to max length
	if message.length() > MAX_MESSAGE_LENGTH:
		message = message.substr(0, MAX_MESSAGE_LENGTH)

		# Spam check
	if not _check_spam(sender_id):
		_notify_player(sender_id, "Slow down! You are sending messages too fast.")
		return false

		# Check if ignored
	if channel == Channel.WHISPER and target_id != "":
		if _is_ignored(target_id, sender_id):
			return false

		# Filter profanity
	message = _filter_profanity(message)

		# Commands bypass the audience check: a solo player in an empty
		# zone must still be able to run /buyplot or /duel.
	var is_command := message.begins_with("/")
	var targets: Array = _get_channel_targets(sender_id, channel, target_id)

	if targets.is_empty() and not is_command:
		return false

	if not is_command:
			# Create chat message
		var chat_message := {
		"id": "msg_%d" % Time.get_ticks_msec(),
		"sender_id": sender_id,
		"channel": channel,
		"message": message,
		"timestamp": Time.get_unix_time_from_system(),
		"target_id": target_id
		}

			# Store in history
		_add_to_history(channel, chat_message)

			# Emit signal
		message_received.emit(sender_id, channel, message, targets)

		# Route to appropriate handler
	_route_message(sender_id, channel, message, targets, target_id)

	return true

## Check for spam
func _check_spam(entity_id: String) -> bool:
	var now: int = Time.get_ticks_msec()
	var last: int = _player_last_message.get(entity_id, 0)

		# Reset if cooldown passed
	if now - last > SPAM_COOLDOWN_MS:
		_spam_count[entity_id] = 0

	_player_last_message[entity_id] = now
	_spam_count[entity_id] = _spam_count.get(entity_id, 0) + 1

	return _spam_count[entity_id] <= SPAM_THRESHOLD * 10	# Allow burst

## Load profanity word list from file
func _load_profanity_list() -> void:
	_profanity_filter_enabled = GameConfig.Chat.PROFANITY_FILTER_ENABLED
	if not _profanity_filter_enabled:
		GameLog.info("ChatService: Profanity filter disabled")
		return

	var file_path := GameConfig.Chat.PROFANITY_WORDS_FILE
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		# Try user:// path as fallback
		file_path = "user://config/profanity_words.txt"
		file = FileAccess.open(file_path, FileAccess.READ)

	if file == null:
		GameLog.warn("ChatService: Profanity word list not found at %s (filter disabled)" % file_path)
		_profanity_list = []
		return

	_profanity_list = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue  # Skip empty lines and comments
		_profanity_list.append(line.to_lower())

	file.close()
	GameLog.info("ChatService: Loaded %d profanity filter words" % _profanity_list.size())

## Filter profanity
func _filter_profanity(message: String) -> String:
	if not _profanity_filter_enabled or _profanity_list.is_empty():
		return message

	for word in _profanity_list:
		var regex := RegEx.new()
		regex.compile(word)
		var replacement := GameConfig.Chat.PROFANITY_REPLACEMENT_CHAR.repeat(word.length())
		message = regex.sub(message, replacement, true)
	return message

## Get targets for channel
func _get_channel_targets(sender_id: String, channel: Channel, target_id: String) -> Array:
	match channel:
		Channel.SAY, Channel.YELL, Channel.ZONE:
		# Return players in range or zone
			return _get_players_in_channel_range(sender_id, channel)
		Channel.WHISPER:
			return [target_id] if target_id != "" else []
		Channel.PARTY:
			return _get_party_members(sender_id)
		Channel.GUILD:
			return _get_guild_members(sender_id)
		Channel.ALLIANCE:
			return _get_alliance_members(sender_id)
		Channel.GLOBAL, Channel.TRADE:
			return []	 # Handled server-side
		Channel.SYSTEM:
			return []	 # System messages don't route
	return []

## Get players in range
func _get_players_in_channel_range(sender_id: String, channel: Channel) -> Array:
	if not EntityService:
		GameLog.warn("ChatService: EntityService not available for range check")
		return []

		# Get sender entity
	var sender = EntityService.get_entity(sender_id)
	if not sender or not is_instance_valid(sender):
		GameLog.warn("ChatService: Sender entity not found for range check: %s" % sender_id)
		return []

		# Get range from channel config
	var channel_range: float = 0.0
	match channel:
		Channel.SAY:
			channel_range = 20.0
		Channel.YELL:
			channel_range = 100.0
		Channel.EMOTE:
			channel_range = 20.0
		Channel.ZONE:
		# Zone-wide = no range limit, return all players in zone
			return _get_players_in_same_zone(sender_id)

	if channel_range <= 0:
		return []

		# Get players within range
	var nearby_entities := EntityService.get_entities_in_radius(
	sender.global_position if sender is Node3D else Vector3.ZERO,
	channel_range,
	Entity.EntityType.PLAYER
	)

		# Convert to player IDs, excluding sender
	var player_ids: Array[String] = []
	for entity in nearby_entities:
		if is_instance_valid(entity) and entity.entity_id != sender_id:
			player_ids.append(entity.entity_id)

	return player_ids

## Get all players in the same zone
func _get_players_in_same_zone(sender_id: String) -> Array[String]:
	if not EntityService:
		return []

	var sender = EntityService.get_entity(sender_id)
	if not sender or not is_instance_valid(sender):
		return []

		# Get sender's zone from metadata
	var metadata: SpawnMetadata = EntityService.get_entity_metadata(sender_id)
	if not metadata or metadata.zone_id == "":
		GameLog.debug("ChatService: No zone info for sender, returning empty range list")
		return []

		# Find all players in the same zone
	var all_players := EntityService.get_all_players()
	var zone_players: Array[String] = []

	for player in all_players:
		if not is_instance_valid(player) or player.entity_id == sender_id:
			continue
		var player_metadata: SpawnMetadata = EntityService.get_entity_metadata(player.entity_id)
		if player_metadata and player_metadata.zone_id == metadata.zone_id:
			zone_players.append(player.entity_id)

	return zone_players

## Get party members
func _get_party_members(player_id: String) -> Array:
	if PartyService and PartyService.is_in_party(player_id):
		return PartyService.get_party_members(PartyService.get_player_party(player_id).get("id", ""))
	return []

## Get guild members
func _get_guild_members(player_id: String) -> Array[String]:
	if GuildService and GuildService.is_in_guild(player_id):
		return GuildService.get_guild_roster(GuildService.get_player_guild(player_id).get("id", ""))
	return []

## Send guild announcement (from guild system)
func send_guild_announcement(guild_id: String, message: String, sender_name: String = "Guild") -> void:
	if GuildService:
		var guild := GuildService.get_guild(guild_id)
		if not guild.is_empty():
			var roster: Array = GuildService.get_guild_roster(guild_id)
			var member_ids: Array[String] = []
			for member in roster:
				if member is Dictionary and "id" in member:
					member_ids.append(member["id"])
				elif member is String:
					member_ids.append(member)

			message_received.emit("GUILD", Channel.GUILD, message, member_ids)

## Get alliance members
func _get_alliance_members(player_id: String) -> Array[String]:
	if GuildService and GuildService.is_in_guild(player_id):
		var guild := GuildService.get_player_guild(player_id)
		var alliance := GuildService.get_guild_alliance(guild.get("id", ""))
		return alliance.get("guild_ids", [])
	return []

## Route message to handlers
func _route_message(sender_id: String, channel: Channel, message: String, targets: Array, target_id: String) -> void:
		# Check for commands
	if message.begins_with("/"):
		_handle_command(sender_id, channel, message.substr(1), target_id)
		return

		# Log chat
	var channel_name: String = _channel_info[channel]["name"]
	GameLog.debug("ChatService: [%s] %s: %s" % [channel_name, sender_id, message])

## Handle chat commands
func _handle_command(sender_id: String, channel: Channel, command: String, target_id: String) -> bool:
	var parts := command.split(" ")
	var cmd := parts[0].to_lower()
	var args := parts.slice(1, parts.size())

	match cmd:
		"w", "whisper", "tell":
			return _cmd_whisper(sender_id, args)
		"r", "reply":
			return _cmd_reply(sender_id, args)
		"s", "say":
			return send_message(sender_id, Channel.SAY, " ".join(args))
		"y", "yell":
			return send_message(sender_id, Channel.YELL, " ".join(args))
		"p", "party":
			return send_message(sender_id, Channel.PARTY, " ".join(args))
		"g", "guild":
			return send_message(sender_id, Channel.GUILD, " ".join(args))
		"a", "alliance":
			return send_message(sender_id, Channel.ALLIANCE, " ".join(args))
		"t", "trade":
			return send_message(sender_id, Channel.TRADE, " ".join(args))
		"emote", "me", "e":
			return _cmd_emote(sender_id, args)
		"ignore":
			return _cmd_ignore(sender_id, args)
		"unignore":
			return _cmd_unignore(sender_id, args)
		"muted":
			return _cmd_muted(sender_id, args)
		"report":
			return _cmd_report(sender_id, args)
		"bug":
			return _cmd_bug(sender_id, args)
		"feedback":
			return _cmd_feedback(sender_id, args)
		"suggest":
			return _cmd_suggest(sender_id, args)
		"duel":
			return _cmd_duel(sender_id, args)
		"accept":
			return _cmd_duel_accept(sender_id)
		"decline":
			return _cmd_duel_decline(sender_id)
		"concede":
			return _cmd_duel_concede(sender_id)
		"lootrule":
			return _cmd_loot_rule(sender_id, args)
		"buyplot":
			return _cmd_dwelling(sender_id, "buyplot", args)
		"placeguard":
			return _cmd_dwelling(sender_id, "placeguard", args)
		"placeankh":
			return _cmd_dwelling(sender_id, "placeankh", args)
		"dismissguard":
			return _cmd_dwelling(sender_id, "dismissguard", args)
		"buildhouse":
			return _cmd_dwelling(sender_id, "buildhouse", args)
		"plotinfo":
			return _cmd_dwelling(sender_id, "plotinfo", args)
		"horde":
			return _cmd_horde(sender_id, args)
		"boss":
			return _cmd_boss(sender_id, args)
		"spawn":
			return _cmd_spawn(sender_id, args)

	return false

## Deliver a one-player system line (command feedback). Delegates to
## _notify_player (NotificationService typed pipeline) -- same path the
## other command feedback uses.
func _send_system_message(sender_id: String, message: String) -> void:
	_notify_player(sender_id, message)

## Sender's tracked zone id ("" when unknown/untracked). Shared by the
## admin spawn-side commands (/horde, /boss, /spawn).
func _sender_zone(sender_id: String) -> String:
	var zm = get_node_or_null(NodePath("/root/ZoneManager"))
	if zm == null or not zm.has_method("get_entity_zone_id"):
		return ""
	var es = get_node_or_null(NodePath("/root/EntityService"))
	var pm = get_node_or_null(NodePath("/root/PlayerManager"))
	var player = null
	if es != null and pm != null and pm.has_method("get_local_player_id"):
		player = es.get_entity(pm.get_local_player_id())
	if player == null:
		return ""
	return str(zm.get_entity_zone_id(player))

## Admin gate for spawn-side commands. Sends the denial line; true when
## the sender may proceed.
func _require_admin(sender_id: String, command: String) -> bool:
	var perm = get_node_or_null(NodePath("/root/PermissionManager"))
	if perm == null or not perm.has_method("is_admin") or not perm.is_admin(sender_id):
		_send_system_message(sender_id, "[%s] Admin permission required." % command)
		return false
	return true

## Command: /boss <template_id> [zone_id] [name...] [world|zone|none]
## Standalone boss spawn outside any horde: open-world world bosses on
## a timer, dungeon bosses on instance init, scripted set pieces.
## Goes through SpawnService.spawn_boss (the shared boss pipeline:
## tree parenting, enemy_data for kill credit + projection, targeting,
## KillRewards on death).
##   alert mode (default zone):
##     world -> WORLD_BOSS metadata + server-wide announcement
##     zone  -> BOSS metadata, zone(+neighbors) announcement
##     none  -> no spawn notification (quiet admin testing)
## The name is multi-word: every arg after zone_id up to the trailing
## alert token joins with spaces ("boss void_lord haven Mr Void world").
## The trailing token is only consumed when it is exactly world/zone/
## none, so plain starts keep their full name.
## Permission: admins (PermissionManager.Level.ADMIN) only.
func _cmd_boss(sender_id: String, args: Array) -> bool:
	var ss = get_node_or_null(NodePath("/root/SpawnService"))
	if ss == null or not ss.has_method("spawn_boss"):
		return false
	# /boss schedule ... -> timed world-boss schedule surface.
	if not args.is_empty() and str(args[0]).to_lower() == "schedule":
		return _cmd_boss_schedule(sender_id, args.slice(1))
	if not _require_admin(sender_id, "boss"):
		return true
	if args.is_empty() or str(args[0]).strip_edges() == "":
		_send_system_message(sender_id, "[boss] Usage: /boss <template_id> [zone_id] [name] [world|zone|none]")
		return true
	var template_id := str(args[0]).strip_edges()
	var zone_id := str(args[1]).strip_edges() if args.size() > 1 else _sender_zone(sender_id)
	if zone_id.is_empty():
		_send_system_message(sender_id, "[boss] No zone resolved (stand in one or pass zone_id).")
		return true
	# Trailing alert token: the LAST arg, when it is exactly world|zone|
	# none, is the alert mode; everything between zone_id and it joins
	# into the boss name (multi-word names without quote parsing).
	var alert := "zone"
	var name_end := args.size()
	if args.size() > 2:
		var last := str(args[args.size() - 1]).strip_edges().to_lower()
		if last == "world" or last == "zone" or last == "none":
			alert = last
			name_end = args.size() - 1
	var name_parts: Array = []
	for i in range(2, name_end):
		name_parts.append(str(args[i]).strip_edges())
	var boss_name := " ".join(name_parts)
	var metadata_type: int = SpawnMetadata.SpawnType.BOSS
	var scopes: Array = []
	match alert:
		"world":
			metadata_type = SpawnMetadata.SpawnType.WORLD_BOSS
			scopes = [NotificationService.AlertScope.server_wide()]
		"none":
			metadata_type = SpawnMetadata.BOSS_SILENT  # no spawn announcement
		_:
			alert = "zone"
			scopes = [NotificationService.AlertScope.zone(zone_id, true)]
	var boss = ss.spawn_boss(template_id, _zone_spawn_pos(zone_id), zone_id, boss_name, scopes, metadata_type)
	if boss == null:
		_send_system_message(sender_id, "[boss] Unknown template '%s'." % template_id)
		return true
	_send_system_message(sender_id, "[boss] Spawned %s in %s (alert=%s)." % [
		boss.display_name, zone_id, alert])
	return true

## Zone-center spawn position for admin commands (Vector3.ZERO when the
## zone data is unknown -- spawn_boss/spawn_enemy_direct tolerate it).
func _zone_spawn_pos(zone_id: String) -> Vector3:
	var zm = get_node_or_null(NodePath("/root/ZoneManager"))
	if zm == null or not zm.has_method("get_zone"):
		return Vector3.ZERO
	var zone = zm.get_zone(zone_id)
	if zone == null:
		return Vector3.ZERO
	var center: Vector3 = zone.zone_center if "zone_center" in zone else Vector3.ZERO
	return center

## /boss schedule [list|info <id>|run <id>|stop <id>|start <id>]
## Admin surface for the timed world-boss schedules SpawnService loads
## from data/world_bosses/. List shows phase + countdown; run forces a
## spawn now (post-kill downtime stays honest: respawn counts from
## death); stop/start manage the loop at runtime.
func _cmd_boss_schedule(sender_id: String, args: Array) -> bool:
	var ss = get_node_or_null(NodePath("/root/SpawnService"))
	if ss == null or not ss.has_method("start_world_boss_schedule"):
		return false
	if not _require_admin(sender_id, "boss schedule"):
		return true
	var sub := str(args[0]).to_lower() if not args.is_empty() else "list"
	var ids: Array = ss.get_world_boss_schedule_ids()
	match sub:
		"list":
			if ids.is_empty():
				_send_system_message(sender_id, "[boss schedule] No schedules loaded.")
				return true
			for sid in ids:
				var st: Dictionary = ss.get_world_boss_schedule_status(str(sid))
				if st.is_empty():
					continue
				var when: String
				if str(st.get("state", "")) == "live":
					when = "UP NOW"
				else:
					var left := float(st.get("time_left", 0.0))
					when = "in %d:%02d" % [int(left) / 60, int(left) % 60]
				_send_system_message(sender_id, "[boss schedule] %s: %s (%s, every %ds) - %s" % [
					str(sid), str(st.get("display_name", str(sid))),
					str(st.get("zone_id", "?")),
					int(st.get("interval_seconds", 0.0)), when])
			return true
		"info":
			if args.size() < 2:
				_send_system_message(sender_id, "[boss schedule] Usage: /boss schedule info <id>")
				return true
			var sid := str(args[1])
			var st: Dictionary = ss.get_world_boss_schedule_status(sid)
			if st.is_empty():
				_send_system_message(sender_id, "[boss schedule] Unknown schedule '%s'. Available: %s" % [sid, ", ".join(PackedStringArray(ids))])
				return true
			_send_system_message(sender_id, "[boss schedule] %s -> template=%s zone=%s interval=%ds announce=%s state=%s" % [
				str(st.get("schedule_id", sid)), str(st.get("boss_template_id", "")),
				str(st.get("zone_id", "")), int(st.get("interval_seconds", 0.0)),
				str(bool(st.get("announce", true))), str(st.get("state", ""))])
			return true
		"run":
			if args.size() < 2:
				_send_system_message(sender_id, "[boss schedule] Usage: /boss schedule run <id>")
				return true
			var sid := str(args[1])
			if not ids.has(sid):
				_send_system_message(sender_id, "[boss schedule] Unknown schedule '%s'." % sid)
				return true
			var boss = ss.run_world_boss_schedule_now(sid)
			if boss == null:
				_send_system_message(sender_id, "[boss schedule] '%s' failed to spawn (already up, or zone/template lost)." % sid)
				return true
			_send_system_message(sender_id, "[boss schedule] '%s' spawned now." % sid)
			return true
		"stop":
			if args.size() < 2:
				_send_system_message(sender_id, "[boss schedule] Usage: /boss schedule stop <id>")
				return true
			var sid := str(args[1])
			if not ids.has(sid):
				_send_system_message(sender_id, "[boss schedule] Unknown schedule '%s'." % sid)
				return true
			ss.stop_world_boss_schedule(sid, "stopped by admin")
			_send_system_message(sender_id, "[boss schedule] '%s' stopped." % sid)
			return true
		"start":
			if args.size() < 2:
				_send_system_message(sender_id, "[boss schedule] Usage: /boss schedule start <id>")
				return true
			var sid := str(args[1])
			if ids.has(sid):
				_send_system_message(sender_id, "[boss schedule] '%s' is already running." % sid)
				return true
			# Reload the .tres by convention path (same convention the
			# boot scan and HordeDataResolver use).
			var res: Resource = load("res://data/world_bosses/world_boss_%s.tres" % sid)
			if res == null or not res.has_method("to_config"):
				_send_system_message(sender_id, "[boss schedule] No config found for '%s' (data/world_bosses/world_boss_%s.tres)." % [sid, sid])
				return true
			# Resource.get(key, default) lost its default arg in 4.7.2
			# strictness: fall back to the requested id when the .tres
			# does not carry one (same fallback DataService uses).
			var res_id := str(res.get("id"))
			if res_id.is_empty():
				res_id = sid
			var start_id: String = ss.start_world_boss_schedule(res_id, res.to_config())
			if start_id == "":
				_send_system_message(sender_id, "[boss schedule] Failed to start '%s' (bad config or unknown template)." % sid)
				return true
			_send_system_message(sender_id, "[boss schedule] '%s' started." % sid)
			return true
		_:
			_send_system_message(sender_id, "[boss schedule] Usage: /boss schedule [list|info|run|stop|start] [id]")
			return true

## Command: /spawn <template_id> [count] [zone_id] [level]
## On-demand normal-enemy spawns (admin events, playtesting). Uses
## SpawnService.spawn_enemy_direct: full Enemy pipeline (template
## stats, AI, registration) with no spawn-point bookkeeping. Count is
## capped at MAX_ADMIN_SPAWN so a typo cannot flood a zone; enemies
## ring the zone center like horde waves do.
## Permission: admins (PermissionManager.Level.ADMIN) only.
const MAX_ADMIN_SPAWN := 24

func _cmd_spawn(sender_id: String, args: Array) -> bool:
	var ss = get_node_or_null(NodePath("/root/SpawnService"))
	if ss == null or not ss.has_method("spawn_enemy_direct"):
		return false
	if not _require_admin(sender_id, "spawn"):
		return true
	if args.is_empty() or str(args[0]).strip_edges() == "":
		_send_system_message(sender_id, "[spawn] Usage: /spawn <template_id> [count] [zone_id] [level]")
		return true
	var template_id := str(args[0]).strip_edges()
	var count := clampi(int(str(args[1])) if args.size() > 1 else 1, 1, MAX_ADMIN_SPAWN)
	var zone_id := str(args[2]).strip_edges() if args.size() > 2 else _sender_zone(sender_id)
	if zone_id.is_empty():
		_send_system_message(sender_id, "[spawn] No zone resolved (stand in one or pass zone_id).")
		return true
	var level := clampi(int(str(args[3])) if args.size() > 3 else 0, 0, 100)
	var zm = get_node_or_null(NodePath("/root/ZoneManager"))
	var center: Vector3 = Vector3.ZERO
	var radius := 40.0
	if zm != null and zm.has_method("get_zone"):
		var zone = zm.get_zone(zone_id)
		if zone != null:
			center = zone.zone_center if "zone_center" in zone else Vector3.ZERO
			var zr := float(zone.zone_radius) if "zone_radius" in zone else 0.0
			if zr > 10.0:
				radius = minf(zr * 0.6, 60.0)
	var spawned := 0
	for i in range(count):
		# Anti-stack: hex-ring spread for multi-spawns; a light jitter for
		# repeated single spawns so they never land pixel-on-pixel.
		var pos: Vector3
		if count > 1:
			var angle := TAU * float(i) / float(count)
			pos = center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		else:
			var jitter_angle := randf() * TAU
			pos = center + Vector3(cos(jitter_angle), 0.0, sin(jitter_angle)) * randf_range(0.5, minf(radius, 3.0))
		if ss.spawn_enemy_direct(template_id, pos, zone_id, level) != null:
			spawned += 1
	if spawned == 0:
		_send_system_message(sender_id, "[spawn] Unknown template '%s'." % template_id)
		return true
	_send_system_message(sender_id, "[spawn] Spawned %d/%d %s in %s%s." % [
		spawned, count, template_id, zone_id,
		" (level %d)" % level if level > 0 else ""])
	return true

## Command: /horde [<config_id>|status|stop] [zone_id] [alert]
## Live trigger for data-driven horde events (data/hordes/*.tres).
##   /horde                      - lists available configs
##   /horde trollmoot            - start trollmoot in the sender's zone
##   /horde trollmoot westwoods  - start in an explicit zone
##   /horde trollmoot westwoods alert - boss waves announce zone+neighbors
##                                 (open-world events: town sieges)
##   /horde status               - horde status in the sender's zone
##   /horde stop                 - stop the horde in the sender's zone
## Permission: admins (PermissionManager.Level.ADMIN) only; the event
## broadcasts zone-wide notifications and moves world state, so a
## random player cannot spam it.
func _cmd_horde(sender_id: String, args: Array) -> bool:
	var horde = get_node_or_null(NodePath("/root/HordeEventService"))
	if horde == null:
		return false
	if not _require_admin(sender_id, "horde"):
		return true
	var sender_zone := _sender_zone(sender_id)

	var sub := str(args[0]).to_lower() if not args.is_empty() else ""
	match sub:
		"":
			# List available configs.
			var names: Array = horde.list_configs() if horde.has_method("list_configs") else []
			if names.is_empty():
				_send_system_message(sender_id, "[horde] No horde configs found in data/hordes/.")
			else:
				_send_system_message(sender_id, "[horde] Configs: %s" % ", ".join(names))
			return true
		"status":
			if sender_zone == "":
				_send_system_message(sender_id, "[horde] You are not in a tracked zone.")
				return true
			var active: String = horde.active_horde_in_zone(sender_zone) if horde.has_method("active_horde_in_zone") else ""
			if active == "":
				_send_system_message(sender_id, "[horde] No active horde in %s." % sender_zone)
			else:
				var st: Dictionary = horde.get_horde_status(active)
				_send_system_message(sender_id, "[horde] %s: wave %d/%d, %d remain, state=%s" % [
					active, int(st.get("wave_number", 0)), int(st.get("waves", 0)),
					int(st.get("remaining", 0)), str(st.get("state", ""))])
			return true
		"stop":
			if sender_zone == "":
				_send_system_message(sender_id, "[horde] You are not in a tracked zone.")
				return true
			var active: String = horde.active_horde_in_zone(sender_zone) if horde.has_method("active_horde_in_zone") else ""
			if active == "":
				_send_system_message(sender_id, "[horde] No active horde in %s." % sender_zone)
				return true
			horde.stop_horde(active, "stopped by %s" % sender_id)
			_send_system_message(sender_id, "[horde] Stopped %s." % active)
			return true
		_:
			# Start: /horde <config_id> [zone_id] [alert]
			var config_id := str(args[0])
			var zone_arg := str(args[1]) if args.size() > 1 else sender_zone
			if zone_arg.is_empty():
				_send_system_message(sender_id, "[horde] No zone resolved (stand in one or pass zone_id).")
				return true
			# "alert" as the third arg flips the open-world announcement
			# mode (boss waves announce zone+neighbors). Plain starts keep
			# the config's own bosses_alert value.
			var overrides: Dictionary = {}
			if args.size() > 2 and str(args[2]).to_lower() == "alert":
				overrides["bosses_alert"] = true
			if not horde.has_method("start_horde_from_config"):
				return false
			var horde_id: String = horde.start_horde_from_config(config_id, zone_arg, overrides)
			if horde_id == "":
				var names: Array = horde.list_configs() if horde.has_method("list_configs") else []
				_send_system_message(sender_id, "[horde] Unknown config '%s'. Available: %s" % [config_id, ", ".join(names)])
				return true
			_send_system_message(sender_id, "[horde] Started %s in %s." % [horde_id, zone_arg])
			return true
	return false

## Command: /buyplot /placeguard /placeankh /dismissguard /buildhouse /plotinfo
## DwellingService is registered after ChatService: lazy resolution.
func _cmd_dwelling(sender_id: String, command: String, args: Array) -> bool:
	var ds = get_node_or_null(NodePath("/root/DwellingService"))
	if ds != null and ds.has_method("handle_dwelling_command"):
		return ds.handle_dwelling_command(sender_id, command, args)
	return false

## Command: /lootrule <ffa|round|leader|master>
## LootRulesService is registered after ChatService: lazy resolution.
func _cmd_loot_rule(sender_id: String, args: Array) -> bool:
	var lr = get_node_or_null(NodePath("/root/LootRulesService"))
	if lr != null and lr.has_method("handle_loot_rule_command"):
		return lr.handle_loot_rule_command(sender_id, str(args[0]) if not args.is_empty() else "")
	return false

## Command: /duel <player>
## DuelService is registered after ChatService; bare forward
## identifiers poison script-mode compilation, so resolve lazily.
func _duel_svc():
	return get_node_or_null(NodePath("/root/DuelService"))

func _cmd_duel(sender_id: String, args: Array) -> bool:
	if args.is_empty():
		return false
	var target_id := _find_player_id_by_name(str(args[0]))
	if target_id == "" or target_id == sender_id:
		return false
	var duel = _duel_svc()
	if duel != null:
		duel.challenge_duel(sender_id, target_id)
		return true
	return false

func _cmd_duel_accept(sender_id: String) -> bool:
	var duel = _duel_svc()
	if duel != null:
		duel.accept_duel(sender_id)
		return true
	return false

func _cmd_duel_decline(sender_id: String) -> bool:
	var duel = _duel_svc()
	if duel != null:
		duel.decline_duel(sender_id)
		return true
	return false

func _cmd_duel_concede(sender_id: String) -> bool:
	var duel = _duel_svc()
	if duel != null:
		return duel.concede_duel(sender_id)
	return false

## Command: Whisper

## Find player ID by name (case-insensitive partial match)
func _find_player_id_by_name(player_name: String) -> String:
	if not EntityService:
		return ""

	var name_lower := player_name.to_lower()
	var all_players := EntityService.get_all_players()

	for player in all_players:
		if not is_instance_valid(player):
			continue
		var player_name_str: String = player.name if "name" in player else ""
		if player_name_str.to_lower() == name_lower:
			return player.entity_id

	# Try partial match
	for player in all_players:
		if not is_instance_valid(player):
			continue
		var player_name_str: String = player.name if "name" in player else ""
		if player_name_str.to_lower().find(name_lower) >= 0:
			return player.entity_id

	return ""
func _cmd_whisper(sender_id: String, args: Array) -> bool:
	if args.size() < 2:
		send_system_message(sender_id, "Usage: /w <player> <message>")
		return false

	var target: String = args[0]
	var message: String = " ".join(args.slice(1, args.size()))

		# Look up player by name
	var target_id := _find_player_id_by_name(target)
	if target_id == "":
		send_system_message(sender_id, "Player not found: " + target)
		return false

		# Track last whisper target
	_player_last_whisper[sender_id] = target_id

	return send_message(sender_id, Channel.WHISPER, message, target_id)

## Command: Reply
func _cmd_reply(sender_id: String, args: Array) -> bool:
	var last_target_id: String = _player_last_whisper.get(sender_id, "")
	if last_target_id == "":
		send_system_message(sender_id, "No one to reply to. Use /w <player> first.")
		return false

	var message: String = " ".join(args)
	return send_message(sender_id, Channel.WHISPER, message, last_target_id)

## Command: Emote
func _cmd_emote(sender_id: String, args: Array) -> bool:
	var emote := " ".join(args)
	return send_message(sender_id, Channel.EMOTE, emote)

## Command: Ignore
func _cmd_ignore(sender_id: String, args: Array) -> bool:
	if args.is_empty():
		return false

	var target: String = args[0]

	if not _ignored_players		.has(sender_id):
		_ignored_players[sender_id] = []

	if not _ignored_players[sender_id]		.has(target):
		_ignored_players[sender_id].append(target)
		player_chat_ignored.emit(sender_id, target)
		send_system_message(sender_id, "Ignored %s" % target)

	return true

## Command: Unignore
func _cmd_unignore(sender_id: String, args: Array) -> bool:
	if args.is_empty():
		return false

	var target: String = args[0]

	if _ignored_players		.has(sender_id) and _ignored_players[sender_id]		.has(target):
		_ignored_players[sender_id].erase(target)
		player_chat_unignored.emit(sender_id, target)
		send_system_message(sender_id, "Stopped ignoring %s" % target)

	return true

## Command: Muted
func _cmd_muted(sender_id: String, args: Array) -> bool:
	var muted: Array = _ignored_players.get(sender_id, [])
	if muted.is_empty():
		send_system_message(sender_id, "You are not ignoring anyone")
	else:
		send_system_message(sender_id, "Ignored: %s" % ", ".join(muted))
	return true

## Command: Report player abuse
func _cmd_report(sender_id: String, args: Array) -> bool:
	if args.size() < 2:
		send_system_message(sender_id, "Usage: /report <player> <reason>")
		send_system_message(sender_id, "Reports are reviewed by moderators. For bugs, use /bug")
		return true

	var target: String = args[0]
	var reason := " ".join(args.slice(1, args.size()))

	if PlayerReporter:
		var result := PlayerReporter.submit_report(sender_id, PlayerReporter.ReportType.ABUSE, {
			"target": target,
			"reason": reason
		})
		if result.success:
			send_system_message(sender_id, "Report submitted. Thank you for helping keep the community safe.")
		else:
			send_system_message(sender_id, "Failed to submit report: %s" % result.message)
	else:
		send_system_message(sender_id, "Report system not available. Please try again later.")

	return true

## Command: Report bug
func _cmd_bug(sender_id: String, args: Array) -> bool:
	if args.is_empty():
		send_system_message(sender_id, "Usage: /bug <description>")
		send_system_message(sender_id, "Describe the bug clearly: what happened, what you expected, steps to reproduce.")
		return true

	var description := " ".join(args)

	if PlayerReporter:
		var result := PlayerReporter.submit_report(sender_id, PlayerReporter.ReportType.BUG, {
			"description": description
		})
		if result.success:
			send_system_message(sender_id, "Bug report submitted. Thank you!")
		else:
			send_system_message(sender_id, "Failed to submit bug report: %s" % result.message)
	else:
		send_system_message(sender_id, "Bug report system not available. Please try again later.")

	return true

## Command: Send feedback
func _cmd_feedback(sender_id: String, args: Array) -> bool:
	if args.is_empty():
		send_system_message(sender_id, "Usage: /feedback <message>")
		send_system_message(sender_id, "Share your thoughts, suggestions, or concerns.")
		return true

	var message: String = " ".join(args)

	if PlayerReporter:
		var result := PlayerReporter.submit_report(sender_id, PlayerReporter.ReportType.FEEDBACK, {
			"message": message
		})
		if result.success:
			send_system_message(sender_id, "Feedback submitted. Thank you for your input!")
		else:
			send_system_message(sender_id, "Failed to submit feedback: %s" % result.message)
	else:
		send_system_message(sender_id, "Feedback system not available. Please try again later.")

	return true

## Command: Suggest feature
func _cmd_suggest(sender_id: String, args: Array) -> bool:
	if args.is_empty():
		send_system_message(sender_id, "Usage: /suggest <idea>")
		send_system_message(sender_id, "Share your feature ideas with the community.")
		return true

	var suggestion := " ".join(args)

	if PlayerReporter:
		var result := PlayerReporter.submit_report(sender_id, PlayerReporter.ReportType.SUGGESTION, {
			"suggestion": suggestion
		})
		if result.success:
			send_system_message(sender_id, "Suggestion submitted! The community can vote on it.")
		else:
			send_system_message(sender_id, "Failed to submit suggestion: %s" % result.message)
	else:
		send_system_message(sender_id, "Suggestion system not available. Please try again later.")

	return true

## Check if player is ignored
func _is_ignored(ignorer_id: String, ignored_id: String) -> bool:
	var ignored: Array = _ignored_players.get(ignorer_id, [])
	return ignored		.has(ignored_id)

## Send system message
func send_system_message(target_id: String, message: String) -> void:
	var chat_message := {
	"id": "msg_%d" % Time.get_ticks_msec(),
	"sender_id": "SYSTEM",
	"channel": Channel.SYSTEM,
	"message": message,
	"timestamp": Time.get_unix_time_from_system(),
	"target_id": target_id
	}

	message_received.emit("SYSTEM", Channel.SYSTEM, message, [target_id])

## Add to chat history
func _add_to_history(channel: Channel, message: Dictionary) -> void:
	if not _chat_history		.has(channel):
		_chat_history[channel] = []

	_chat_history[channel].append(message)

		# Trim history
	while _chat_history[channel].size() > MAX_HISTORY_PER_CHANNEL:
		_chat_history[channel].pop_at(0)

## Get chat history
func get_channel_history(channel: Channel, limit: int = 20) -> Array:
	var history: Array = _chat_history.get(channel, [])
	return history.slice(max(0, history.size() - limit), history.size())

## Subscribe to channel
func subscribe_to_channel(entity_id: String, channel: Channel) -> void:
	if not _subscriptions		.has(entity_id):
		_subscriptions[entity_id] = []

	if not _subscriptions[entity_id]		.has(channel):
		_subscriptions[entity_id].append(channel)
		channel_joined.emit(entity_id, channel)

## Unsubscribe from channel
func unsubscribe_from_channel(entity_id: String, channel: Channel) -> void:
	if _subscriptions		.has(entity_id):
		_subscriptions[entity_id].erase(channel)
		channel_left.emit(entity_id, channel)

## Check if subscribed
func is_subscribed(entity_id: String, channel: Channel) -> bool:
	return _subscriptions.get(entity_id, [])		.has(channel)

## Get channel info
func get_channel_info(channel: Channel) -> Dictionary:
	return _channel_info.get(channel, {})

## Get channel name
func get_channel_name(channel: Channel) -> String:
	return _channel_info.get(channel, {}).get("name", "Unknown")

## Get channel color
func get_channel_color(channel: Channel) -> String:
	return _channel_info.get(channel, {}).get("color", "#FFFFFF")

## Format message for display
func format_message(sender_id: String, channel: Channel, message: String, sender_name: String = "") -> String:
	var info := get_channel_info(channel)
	var prefix: String = info.get("prefix", "")
	var color: String = info.get("color", "#FFFFFF")

	# Check if sender is a GM
	var is_gm: bool = false
	if sender_id != "":
		var entity = EntityService.get_entity(sender_id) if EntityService else null
		if entity:
			var char_data = entity.get("character_data") if entity else null
			if char_data:
				if char_data		.has("is_gm"):
					is_gm = char_data.is_gm()
				elif char_data		.has("class_id"):
					is_gm = CharacterData.is_gm_class(char_data.get("class_id"))

	# Add GM indicator to name
	var display_name: String = sender_name
	if is_gm:
		display_name = "[GM] " + sender_name
		color = "#FFD700"  # Gold color for GM messages

	# Escape brackets so player messages and names cannot inject BBCode markup.
	var safe_name := _escape_bbcode(display_name)
	var safe_message := _escape_bbcode(message)
	var safe_prefix := _escape_bbcode(prefix)
	if channel == Channel.WHISPER:
		return "[color=%s]%s %s:[/color] %s" % [color, safe_prefix, safe_name, safe_message]
	elif channel == Channel.EMOTE:
		return "[color=%s]*%s %s*[/color]" % [color, safe_name, safe_message]
	elif prefix != "":
		return "[color=%s]%s[/color] [color=#FFFFFF]%s:[/color] %s" % [color, safe_prefix, safe_name, safe_message]
	else:
		return "[color=%s]%s:[/color] %s" % [color, safe_name, safe_message]

## ============================================================================
## PLAYER NOTIFICATIONS
## ============================================================================

## Check if player is restricted from a chat channel
## Returns "" if allowed, or error message if restricted
func _get_channel_restriction_message(player_id: String, channel: Channel) -> String:
	match channel:
		Channel.SAY, Channel.YELL, Channel.ZONE, Channel.GLOBAL, Channel.TRADE, Channel.COMBAT, Channel.EMOTE:
		# General chat channels - check "chat" restriction
			if SecurityService.is_restricted(player_id, "chat"):
				return "You are muted and cannot send messages."

		Channel.WHISPER:
		# Whisper channel - check "chat" restriction
			if SecurityService.is_restricted(player_id, "chat"):
				return "You are muted and cannot send whispers."

		Channel.PARTY:
		# Party chat - check party restriction
			if SecurityService.is_restricted(player_id, "party"):
				return "You are restricted from party chat."
			if SecurityService.is_restricted(player_id, "chat"):
				return "You are muted and cannot send party messages."

		Channel.GUILD:
		# Guild chat - check guild restriction
			if SecurityService.is_restricted(player_id, "guild"):
				return "You are restricted from guild chat."
			if SecurityService.is_restricted(player_id, "chat"):
				return "You are muted and cannot send guild messages."

		Channel.ALLIANCE:
		# Alliance chat - check guild restriction (alliance uses guild perms)
			if SecurityService.is_restricted(player_id, "guild"):
				return "You are restricted from alliance chat."
			if SecurityService.is_restricted(player_id, "chat"):
				return "You are muted and cannot send alliance messages."

		Channel.SYSTEM:
		# System messages are read-only
			return "Cannot send to system channel."

	return ""	 # No restriction

## Send notification to player
func _notify_player(player_id: String, message: String) -> void:
	# Frame-level dispatch. The three call sites (restriction, validation
	# block, rate-limit) are all chat-send feedback, so the kind is
	# SECURITY_BLOCKED. The dispatcher's KIND_WINDOW_OVERRIDES table
	# disables dedupe for SECURITY_BLOCKED (rate-limit feedback must
	# always show), so we don't pass a per-call dedupe_key -- the
	# kind-level policy wins regardless.
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.SECURITY_BLOCKED,
			message,
			"ChatService",
			"",
			{"player_id": player_id},
			player_id
		)
	GameLog.debug("ChatService: Notified %s: %s" % [player_id, message])

## == Persistence ============================================================

func _load_chat_state() -> void:
	var store := DictStore.new()
	_ignored_players = {}
	_player_settings = {}
	for key in store.all_keys():
		if key.begins_with(_kv_ignored):
			var ignorer_id = key.substr(_kv_ignored.length())
			_ignored_players[ignorer_id] = store.get_value(key)
		elif key.begins_with(_kv_player_settings):
			var player_id = key.substr(_kv_player_settings.length())
			_player_settings[player_id] = store.get_value(key)

func _persist_ignored(ignorer_id: String) -> void:
	var store := DictStore.new()
	if _ignored_players		.has(ignorer_id):
		store.set_value(_kv_ignored + ignorer_id, _ignored_players[ignorer_id])
	else:
		store.erase(_kv_ignored + ignorer_id)

func _persist_player_settings(player_id: String) -> void:
	var store := DictStore.new()
	if _player_settings		.has(player_id):
		store.set_value(_kv_player_settings + player_id, _player_settings[player_id])
	else:
		store.erase(_kv_player_settings + player_id)
