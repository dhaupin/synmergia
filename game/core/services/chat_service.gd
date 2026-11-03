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
# Blessed sigil constants (prd-psy.md section 8): preload, not
# class_name (the GuardData lesson).
const BlessedMarkScript = preload("res://entities/blessed_mark.gd")
# Frame-level notification dispatch (typed-Kind pipeline).
# All chat-service-toasts are feedback to the sender about their own
# blocked/limited message (rate-limit, validation, restriction), so
# the Kind is SECURITY_BLOCKED uniformly.
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind
const ReportKind = preload("res://core/admin/player_reporter.gd")

## Runtime autoload lookups (script-mode-safe; the bare identifiers
## fail compile when autoloads are absent -- test_islands).
static func _glog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

static func _gconfig() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameConfig")) if tree and tree.root else null

static func _entity_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("EntityService")) if tree and tree.root else null

static func _player_m() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PlayerManager")) if tree and tree.root else null

static func _security_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("SecurityService")) if tree and tree.root else null

static func _party_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PartyService")) if tree and tree.root else null

static func _guild_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GuildService")) if tree and tree.root else null

static func _notify_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("NotificationService")) if tree and tree.root else null

static func _reporter() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PlayerReporter")) if tree and tree.root else null

static func _sign_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("SignService")) if tree and tree.root else null

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
	return text.replace("[", "[lb]")

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
## Runtime-resolved; resolved lazily (script-mode-safe).
var MAX_HISTORY_PER_CHANNEL: int = 30
@warning_ignore("unused_private_class_variable")

# Channel subscriptions (entity_id -> [channels])
var _subscriptions: Dictionary = {}

# Spam protection
var _player_last_message: Dictionary = {}	 # entity_id -> timestamp
const SPAM_COOLDOWN_MS: int = 500	 # Half second between messages
const SPAM_THRESHOLD: int = 5	 # Messages per time window
var MAX_MESSAGE_LENGTH: int = 200
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
	var gl := _glog()
	if gl:
		gl.info("ChatService: Ready")
	# Pull the real limits when GameConfig is live (script-mode fallbacks
	# above stay only when neither exists).
	var gc := _gconfig()
	if gc and gc.get("Chat") != null:
		MAX_HISTORY_PER_CHANNEL = gc.Chat.MAX_HISTORY_PER_CHANNEL
		MAX_MESSAGE_LENGTH = gc.Chat.MAX_MESSAGE_LENGTH

		# Initialize history for each channel (the VALUES -- iterating
		# the enum bare would key history by the enum NAMES ("SAY")
		# and int-keyed lookups would miss them).
	for channel in Channel.values():
		_chat_history[channel] = []

		# Load profanity filter words from config file
	_load_profanity_list()

	# Revive the KV persistence: the ignore book and per-player
	# settings did in-memory work for their whole life while the
	# _load_chat_state/_persist_* pair sat unwritten (the ignore list
	# evaporated every reboot). Load it once at boot.
	_load_chat_state()

## Open a whisper chat with a target player
func open_whisper(target_id: String) -> void:
	if not target_id.is_empty():
		# Store this as the last whisper target for reply functionality
		if _player_m():
			var sender_id := str(_player_m().get_local_player_id())
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
	var validation = _security_svc().validate_message(message, sender_id)
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
	_profanity_filter_enabled = _gconfig().Chat.PROFANITY_FILTER_ENABLED
	if not _profanity_filter_enabled:
		_glog().info("ChatService: Profanity filter disabled")
		return

	var file_path: String = _gconfig().Chat.PROFANITY_WORDS_FILE
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		# Try user:// path as fallback
		file_path = "user://config/profanity_words.txt"
		file = FileAccess.open(file_path, FileAccess.READ)

	if file == null:
		_glog().warn("ChatService: Profanity word list not found at %s (filter disabled)" % file_path)
		_profanity_list = []
		return

	_profanity_list = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue  # Skip empty lines and comments
		_profanity_list.append(line.to_lower())

	file.close()
	_glog().info("ChatService: Loaded %d profanity filter words" % _profanity_list.size())

## Filter profanity
func _filter_profanity(message: String) -> String:
	if not _profanity_filter_enabled or _profanity_list.is_empty():
		return message

	for word in _profanity_list:
		var regex := RegEx.new()
		regex.compile(word)
		var replacement: String = _gconfig().Chat.PROFANITY_REPLACEMENT_CHAR.repeat(word.length())
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
	var _ent_svc_check := _entity_svc()
	if not _ent_svc_check:
		_glog().warn("ChatService: _entity_svc() not available for range check")
		return []

		# Get sender entity
	var sender = _entity_svc().get_entity(sender_id)
	if not sender or not is_instance_valid(sender):
		_glog().warn("ChatService: Sender entity not found for range check: %s" % sender_id)
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

		# Get players within range (shared interest helper, round 10)
	var Interest = load("res://core/services/entity_interest.gd")
	var nearby_entities: Array = Interest.query_players(
	sender.global_position if sender is Node3D else Vector3.ZERO,
	channel_range
	)

		# Convert to player IDs, excluding sender
	var player_ids: Array[String] = []
	for entity in nearby_entities:
		if is_instance_valid(entity) and entity.entity_id != sender_id:
			player_ids.append(entity.entity_id)

	return player_ids

## Get all players in the same zone
func _get_players_in_same_zone(sender_id: String) -> Array[String]:
	var _ent_svc_check := _entity_svc()
	if not _ent_svc_check:
		return []

	var sender = _entity_svc().get_entity(sender_id)
	if not sender or not is_instance_valid(sender):
		return []

		# Get sender's zone from metadata
	var metadata: SpawnMetadata = _entity_svc().get_entity_metadata(sender_id)
	if not metadata or metadata.zone_id == "":
		_glog().debug("ChatService: No zone info for sender, returning empty range list")
		return []

		# Find all players in the same zone
	var all_players: Array = _entity_svc().get_all_players()
	var zone_players: Array[String] = []

	for player in all_players:
		if not is_instance_valid(player) or player.entity_id == sender_id:
			continue
		var player_metadata: SpawnMetadata = _entity_svc().get_entity_metadata(player.entity_id)
		if player_metadata and player_metadata.zone_id == metadata.zone_id:
			zone_players.append(player.entity_id)

	return zone_players

## Get party members
func _get_party_members(player_id: String) -> Array:
	if _party_svc() and _party_svc().is_in_party(player_id):
		return _party_svc().get_party_members(_party_svc().get_player_party(player_id).get("id", ""))
	return []

## Get guild members
func _get_guild_members(player_id: String) -> Array[String]:
	if _guild_svc() and _guild_svc().is_in_guild(player_id):
		return _guild_svc().get_guild_roster(_guild_svc().get_player_guild(player_id).get("id", ""))
	return []

## Send guild announcement (from guild system)
func send_guild_announcement(guild_id: String, message: String, sender_name: String = "Guild") -> void:
	if _guild_svc():
		var guild = _guild_svc().get_guild(guild_id)
		if not guild.is_empty():
			var roster: Array = _guild_svc().get_guild_roster(guild_id)
			var member_ids: Array[String] = []
			for member in roster:
				if member is Dictionary and "id" in member:
					member_ids.append(member["id"])
				elif member is String:
					member_ids.append(member)

			message_received.emit("GUILD", Channel.GUILD, message, member_ids)

## Get alliance members
func _get_alliance_members(player_id: String) -> Array[String]:
	if _guild_svc() and _guild_svc().is_in_guild(player_id):
		var guild: Dictionary = _guild_svc().get_player_guild(player_id)
		var alliance: Dictionary = _guild_svc().get_guild_alliance(guild.get("id", ""))
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
	_glog().debug("ChatService: [%s] %s: %s" % [channel_name, sender_id, message])

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
		"mute":
			return _cmd_mute(sender_id, args)
		"unmute":
			return _cmd_unmute(sender_id, args)
		"channels":
			return _cmd_channels(sender_id, args)
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
		"weather-event":
			return _cmd_weather_event(sender_id, args)
		"boss":
			return _cmd_boss(sender_id, args)
		"spawn":
			return _cmd_spawn(sender_id, args)

	return false

## Deliver a one-player system line (command feedback). Delegates to
## _notify_player (_notify_svc() typed pipeline) -- same path the
## other command feedback uses.
func _send_system_message(sender_id: String, message: String) -> void:
	_notify_player(sender_id, message)

## Sender's tracked zone id ("" when unknown/untracked). Shared by the
## admin spawn-side commands (/horde, /boss, /spawn).
func _sender_zone(sender_id: String) -> String:
	var zm = get_node_or_null(NodePath("/root/ZoneManager"))
	if zm == null or not zm.has_method("get_entity_zone_id"):
		return ""
	var es = get_node_or_null(NodePath("/root/_entity_svc()"))
	var pm = get_node_or_null(NodePath("/root/_player_m()"))
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

## The WeatherEventService lookup: a root-level service node when one
## is armed (test harnesses, headless boots) — else the world scene's
## scoped child "WeatherEvents" (the WorldPlayable convention, same
## dual path HudIntegrator.get_weather_event_service() uses). Chat
## lives outside the world scene, so the scene-scoped lookup is the
## only one that hits in a live world.
func _find_weather_event_service() -> Node:
	var svc := get_node_or_null(NodePath("/root/WeatherEventService"))
	if svc != null:
		return svc
	var tree := get_tree()
	var scene_root: Node = tree.current_scene if tree != null else null
	if scene_root != null:
		return scene_root.get_node_or_null("WeatherEvents")
	return null

## Command: /weather-event [config_id] [zone_id]
## Sun-to-sword admin surface: bare lists the armed weather event
## configs (the .tres law catalog), an id force-fires it NOW through
## WeatherEventService.force_fire — the exact same _actions pipeline a
## real spark/band trigger runs (cooldown bypassed, never a second
## law). zone_id (optional) overrides the config's zone convention;
## without one, the config's own zone_ids/starter-plains default
## applies — the same authority a real trigger has.
## WeatherEventService registers after ChatService: lazy.
## Permission: admins (PermissionManager.Level.ADMIN) only.
func _cmd_weather_event(sender_id: String, args: Array) -> bool:
	var we = _find_weather_event_service()
	if we == null:
		return false
	if not _require_admin(sender_id, "weather-event"):
		return true
	if args.is_empty():
		var list: Array = we.list_configs() if we.has_method("list_configs") else []
		if list.is_empty():
			_send_system_message(sender_id, "[weather-event] No weather event configs armed.")
			return true
		var parts: Array = []
		for cfg in list:
			parts.append(str(cfg.get("id", "?")))
		_send_system_message(sender_id, "[weather-event] Armed configs: %s" % ", ".join(parts))
		return true
	var event_id := str(args[0])
	# Optional zone override: args[1] when present, else the sender's
	# tracked zone ("" keeps the config's own convention).
	var zone_override: String = ""
	if args.size() > 1:
		zone_override = str(args[1])
	else:
		zone_override = _sender_zone(sender_id)
	var fired: String = we.force_fire(event_id, zone_override) if we.has_method("force_fire") else ""
	if fired == "":
		var list: Array = we.list_configs() if we.has_method("list_configs") else []
		var names: Array = []
		for cfg in list:
			names.append(str(cfg.get("id", "?")))
		_send_system_message(sender_id, "[weather-event] Unknown config '%s'. Available: %s" % [event_id, ", ".join(names)])
		return true
	_send_system_message(sender_id, "[weather-event] Fired %s." % fired)
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
	var nf := _notify_svc()
	match alert:
		"world":
			metadata_type = SpawnMetadata.SpawnType.WORLD_BOSS
			if nf: scopes = [nf.AlertScope.server_wide()]
		"none":
			metadata_type = SpawnMetadata.BOSS_SILENT  # no spawn announcement
		_:
			alert = "zone"
			if nf: scopes = [nf.AlertScope.zone(zone_id, true)]
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
	var _ent_svc_check := _entity_svc()
	if not _ent_svc_check:
		return ""

	var name_lower := player_name.to_lower()
	var all_players: Array = _entity_svc().get_all_players()

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

## Command: Ignore (rides the ignore-book API so the command, the
## panel, and the persistence hit the exact same law).
func _cmd_ignore(sender_id: String, args: Array) -> bool:
	if args.is_empty():
		send_system_message(sender_id, "Usage: /ignore <player>")
		return true
	var result: Dictionary = ignore_player(sender_id, str(args[0]))
	send_system_message(sender_id, str(result.get("message", "")))
	return bool(result.get("success", false))

## Command: Unignore
func _cmd_unignore(sender_id: String, args: Array) -> bool:
	if args.is_empty():
		send_system_message(sender_id, "Usage: /unignore <player>")
		return true
	var result: Dictionary = unignore_player(sender_id, str(args[0]))
	send_system_message(sender_id, str(result.get("message", "")))
	return bool(result.get("success", false))

## Command: Muted
func _cmd_muted(sender_id: String, args: Array) -> bool:
	var muted: Array = get_ignored_players(sender_id)
	if muted.is_empty():
		send_system_message(sender_id, "You are not ignoring anyone")
	else:
		send_system_message(sender_id, "Ignored: %s" % ", ".join(muted))
	var channels := get_muted_channels(sender_id)
	if not channels.is_empty():
		send_system_message(sender_id, "Muted channels: %s" % ", ".join(channels))
	return true

## Command: Mute a channel (receive-side; /mute Trade hides Trade's
## incoming lines). Same law as the panel: both ride set_channel_muted.
func _cmd_mute(sender_id: String, args: Array) -> bool:
	return _mute_command(sender_id, args, true)

## Command: Unmute a channel
func _cmd_unmute(sender_id: String, args: Array) -> bool:
	return _mute_command(sender_id, args, false)

func _mute_command(sender_id: String, args: Array, muted: bool) -> bool:
	if args.is_empty():
		send_system_message(sender_id, "Usage: /%s <channel>  (see %s)" % ["mute" if muted else "unmute", "/channels"])
		return true
	var channel := channel_by_name(str(args[0]))
	if channel < 0:
		send_system_message(sender_id, "Unknown channel: %s (try %s)" % [str(args[0]), "/channels"])
		return true
	var result: Dictionary = set_channel_muted(sender_id, channel, muted)
	send_system_message(sender_id, str(result.get("message", "")))
	return bool(result.get("success", false))

## Command: Channels -- the mute state board (every channel with its
## hidden/shown verdict + the System protection called out).
func _cmd_channels(sender_id: String, args: Array) -> bool:
	var muted: Array = get_muted_channels(sender_id)
	var lines: Array = []
	for channel in Channel.values():
		if channel == Channel.WHISPER:
			continue
		var label := get_channel_name(channel)
		if channel == Channel.SYSTEM:
			label += " (always shown)"
		elif muted.has(label):
			label += " [MUTED]"
		lines.append(label)
	send_system_message(sender_id, "Channels: %s" % ", ".join(lines))
	send_system_message(sender_id, "Toggle with /mute <channel> or /unmute <channel>")
	return true

## Command: Report player abuse
func _cmd_report(sender_id: String, args: Array) -> bool:
	if args.size() < 2:
		send_system_message(sender_id, "Usage: /report <player> <reason>")
		send_system_message(sender_id, "Reports are reviewed by moderators. For bugs, use /bug")
		return true

	var target: String = args[0]
	var reason := " ".join(args.slice(1, args.size()))

	if _reporter():
		var result = _reporter().submit_report(sender_id, ReportKind.ReportType.ABUSE, {
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

	if _reporter():
		var result = _reporter().submit_report(sender_id, ReportKind.ReportType.BUG, {
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

	if _reporter():
		var result = _reporter().submit_report(sender_id, ReportKind.ReportType.FEEDBACK, {
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

	if _reporter():
		var result = _reporter().submit_report(sender_id, ReportKind.ReportType.SUGGESTION, {
			"suggestion": suggestion
		})
		if result.success:
			send_system_message(sender_id, "Suggestion submitted! The community can vote on it.")
		else:
			send_system_message(sender_id, "Failed to submit suggestion: %s" % result.message)
	else:
		send_system_message(sender_id, "Suggestion system not available. Please try again later.")

	return true

## ============================================================================
## IGNORE BOOK API (the consumer round's service half)
## ============================================================================

## Ignore a player by display name. The entry stores the NAME (the
## /ignore command's original contract), so the book handles senders
## that resolve online and offline. Self-ignore is refused. Returns
## {"success", "message", "target"}.
func ignore_player(ignorer_id: String, target_name: String) -> Dictionary:
	var target := str(target_name).strip_edges()
	if target.is_empty():
		return {"success": false, "message": "No player named"}
	if ignorer_id != "" and target == ignorer_id:
		return {"success": false, "message": "You cannot ignore yourself"}
	if target == "SYSTEM":
		return {"success": false, "message": "System messages are always shown"}
	if not _ignored_players.has(ignorer_id):
		_ignored_players[ignorer_id] = []
	if _ignored_players[ignorer_id].has(target):
		return {"success": false, "message": "Already ignoring %s" % target}
	_ignored_players[ignorer_id].append(target)
	_persist_ignored(ignorer_id)
	player_chat_ignored.emit(ignorer_id, target)
	return {"success": true, "message": "Ignored %s" % target, "target": target}

## Unignore a player (mirrors ignore_player; erasing the last entry
## clears the persisted key entirely).
func unignore_player(ignorer_id: String, target_name: String) -> Dictionary:
	var target := str(target_name).strip_edges()
	if target.is_empty() or not _ignored_players.has(ignorer_id) or not _ignored_players[ignorer_id].has(target):
		return {"success": false, "message": "Not ignoring %s" % target}
	_ignored_players[ignorer_id].erase(target)
	_persist_ignored(ignorer_id)
	player_chat_unignored.emit(ignorer_id, target)
	return {"success": true, "message": "Stopped ignoring %s" % target, "target": target}

## The persisted ignore list (names), for the book's UI.
func get_ignored_players(ignorer_id: String) -> Array:
	return _ignored_players.get(ignorer_id, [])

## The display-filter truth both chat surfaces consult: sender blocked
## by the local ignore list, by id (the list may hold ids) or by best
## known display name. System lines and servers never filter.
func is_ignored_sender(ignorer_id: String, sender_id: String) -> bool:
	if sender_id.is_empty() or sender_id == "SYSTEM" or ignorer_id.is_empty():
		return false
	if _is_ignored(ignorer_id, sender_id):
		return true
	var sender_name := _sender_display_name(sender_id)
	if sender_name.is_empty():
		return false
	for entry in _ignored_players.get(ignorer_id, []):
		if str(entry).to_lower() == sender_name.to_lower():
			return true
	return false

## Best-known display name for a sender id ("" when unresolvable --
## the entity-service lookup is a runtime path, the bare identifier
## is the known script-mode false-fail).
func _sender_display_name(sender_id: String) -> String:
	var ess := _entity_svc()
	if ess == null or not ess.has_method("get_entity"):
		return ""
	var entity = ess.get_entity(sender_id)
	if entity == null or not is_instance_valid(entity):
		return ""
	var char_data = entity.get("character_data") if "character_data" in entity else null
	if char_data != null and "player_name" in char_data:
		return str(char_data.player_name)
	return str(entity.name) if "name" in entity else ""

## Check if player is ignored
func _is_ignored(ignorer_id: String, ignored_id: String) -> bool:
	var ignored: Array = _ignored_players.get(ignorer_id, [])
	return ignored		.has(ignored_id)

## ============================================================================
## PER-CHANNEL MUTE (the channel_settings_changed owner)
## ============================================================================
## Mute = a RECEIVE-side filter: the viewer hides a channel's incoming
## lines in their own chat view (their own sends are untouched --
## this is a personal volume knob, not a broadcast policy). The mute
## list rides _player_settings (born-dead until this round; keyed by
## channel display names so the KV round-trip stays string-stable)
## and every real change emits channel_settings_changed. System
## stays unmuteable: its lines are the game's error and announcement
## voice, and blocking it would blind your own feedback.

static func _mute_record(channel: Channel) -> String:
	# Static needs a lazy _channel_info path; use the enum name (the
	# same string the info dict keys it under).
	var enum_name := str(Channel.keys()[channel])
	# "SAY" -> "Say" capitalization is owned by the info dict; the
	# record key just needs to be stable per channel.
	return enum_name

func _muted_channel_list(viewer_id: String) -> Array:
	var settings: Variant = _player_settings.get(viewer_id)
	if settings == null:
		settings = {}
		_player_settings[viewer_id] = settings
	var list: Variant = settings.get("muted_channels")
	if list == null or not (list is Array):
		list = []
		settings["muted_channels"] = list
	return list

## Set (or clear) a channel mute for one viewer. Returns
## {"success", "message", "muted"}; refusals carry named causes
## (protected channel, duplicate) -- no silent no-ops, no fake emits.
func set_channel_muted(viewer_id: String, channel: Channel, muted: bool) -> Dictionary:
	if channel == Channel.SYSTEM:
		return {"success": false, "message": "System messages cannot be muted", "muted": false}
	var list := _muted_channel_list(viewer_id)
	var record := _mute_record(channel)
	if muted and list.has(record):
		return {"success": false, "message": "%s is already muted" % _mute_label(channel), "muted": true}
	if not muted and not list.has(record):
		return {"success": false, "message": "%s is not muted" % _mute_label(channel), "muted": false}
	if muted:
		list.append(record)
	else:
		list.erase(record)
	_persist_player_settings(viewer_id)
	channel_settings_changed.emit(viewer_id, channel)
	return {"success": true, "message": "%s %s" % [_mute_label(channel), "muted" if muted else "unmuted"], "muted": muted}

## The display-filter truth both chat surfaces consult: does this
## viewer hide that channel's incoming lines?
func is_channel_muted(viewer_id: String, channel: Channel) -> bool:
	var list: Variant = _player_settings.get(viewer_id, {}).get("muted_channels", [])
	return list.has(_mute_record(channel))

## The muted channel labels, for command feedback and panels.
func get_muted_channels(viewer_id: String) -> Array:
	var out: Array = []
	for record in _muted_channel_list(viewer_id):
		out.append(MUTE_LABELS.get(record, record))
	return out

static func _mute_label(channel: Channel) -> String:
	var record := _mute_record(channel)
	return MUTE_LABELS.get(record, record)

## Record key -> display label (kept here so callers never re-derive
## the capitalization).
const MUTE_LABELS := {
	"SAY": "Say", "WHISPER": "Whisper", "YELL": "Yell", "ZONE": "Zone",
	"GLOBAL": "Global", "PARTY": "Party", "GUILD": "Guild",
	"ALLIANCE": "Alliance", "TRADE": "Trade", "COMBAT": "Combat", "EMOTE": "Emote"
}

## Resolve a channel by its display name (case-insensitive) or enum
## key, for the slash commands. Returns -1 when unknown.
func channel_by_name(name: String) -> int:
	var wanted := str(name).to_lower().strip_edges()
	for channel in Channel.values():
		if _mute_record(channel).to_lower() == wanted or MUTE_LABELS.get(_mute_record(channel), "").to_lower() == wanted:
			return channel
	return -1

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
	var is_blessed: bool = false
	if sender_id != "":
		var entity = _entity_svc().get_entity(sender_id) if _entity_svc() else null
		if entity:
			var char_data = entity.get("character_data") if entity else null
			if char_data:
				if char_data		.has("is_gm"):
					is_gm = char_data.is_gm()
				elif char_data		.has("class_id"):
					is_gm = CharacterData.is_gm_class(char_data.get("class_id"))
			# The sky's favor (prd-psy.md section 8): the wheel's chosen
			# class chats with the (*) sigil in sky-cyan. Never on GM
			# lines -- staff gold and the sky's palette do not mix.
			if not is_gm and "character_class" in entity \
					and _sign_svc() != null \
					and _sign_svc().has_method("is_class_blessed"):
				is_blessed = _sign_svc().is_class_blessed(str(entity.character_class))

	# Add GM indicator to name
	var display_name: String = sender_name
	if is_gm:
		display_name = "[GM] " + sender_name
		color = "#FFD700"  # Gold color for GM messages
	elif is_blessed:
		display_name = "%s %s" % [BlessedMarkScript.CHAT_SIGIL, sender_name]
		color = BlessedMarkScript.CHAT_COLOR  # Sky-cyan for the wheel's pick

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
			if _security_svc().is_restricted(player_id, "chat"):
				return "You are muted and cannot send messages."

		Channel.WHISPER:
		# Whisper channel - check "chat" restriction
			if _security_svc().is_restricted(player_id, "chat"):
				return "You are muted and cannot send whispers."

		Channel.PARTY:
		# Party chat - check party restriction
			if _security_svc().is_restricted(player_id, "party"):
				return "You are restricted from party chat."
			if _security_svc().is_restricted(player_id, "chat"):
				return "You are muted and cannot send party messages."

		Channel.GUILD:
		# Guild chat - check guild restriction
			if _security_svc().is_restricted(player_id, "guild"):
				return "You are restricted from guild chat."
			if _security_svc().is_restricted(player_id, "chat"):
				return "You are muted and cannot send guild messages."

		Channel.ALLIANCE:
		# Alliance chat - check guild restriction (alliance uses guild perms)
			if _security_svc().is_restricted(player_id, "guild"):
				return "You are restricted from alliance chat."
			if _security_svc().is_restricted(player_id, "chat"):
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
	var _nf := _notify_svc()
	if is_instance_valid(_nf):
		_notify_svc().notify(
			NotifKind.SECURITY_BLOCKED,
			message,
			"ChatService",
			"",
			{"player_id": player_id},
			player_id
		)
	_glog().debug("ChatService: Notified %s: %s" % [player_id, message])

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
