## NotificationService - Player notification system
## Handles all player notifications: zone changes, achievements, combat, events, etc.
extends Node

const SpawnMetadata = preload("res://core/events/spawn_metadata.gd")
const DictStore = preload("res://adapters/persistence/dict_store.gd")
# Notification types
enum NotificationType {
	INFO,             # Informational messages
	SYSTEM,           # General system messages
	ZONE_CHANGE,      # Entered/exited zone
	DUNGEON,          # Dungeon entry/exit
	ACHIEVEMENT,      # Achievement unlocked
	LEVEL_UP,         # Level increased
	WORLD_EVENT,      # World event alerts
	FACTION,          # Faction-related notifications
	GUILD,            # Guild notifications
	COMBAT,           # Combat notifications (crit, dodge, etc.)
	ITEM,             # Item loot/drop
	GOLD,             # Gold changes
	QUEST,            # Quest progress/completion
	WARNING,          # Warnings/cautions
	ALERT,            # Important alerts requiring attention
	ERROR,            # Error messages
	CUSTOM            # Custom messages
}

# Notification priority (higher = more important)
enum Priority {
	LOW = 0,
	NORMAL = 1,
	HIGH = 2,
	CRITICAL = 3
}

# Notification display location
enum DisplayLocation {
	CHAT_LOG = 0,      # Scrolls in chat
	CENTER_SCREEN = 1,  # Large center text
	CORNER = 2,         # Corner toast notification
	FLOATING = 3,       # Floating 3D text (in world)
	BOTH = 4           # Chat + Center screen
}

# Sound effect types
enum SoundType { NONE, NOTIFICATION, ACHIEVEMENT, LEVEL_UP, WARNING, ERROR, DUNGEON_ENTER, DUNGEON_COMPLETE, COMBAT, DEATH, REVIVE_START, REVIVE_COMPLETE, SELF_REZ, INVINCIBILITY, KILL_STREAK }

# Alert scope - where to send the notification
class AlertScope:
	var position: Vector3 = Vector3.ZERO  # For NEARBY scope
	var radius: float = 50.0             # For NEARBY scope
	var zone_id: String = ""              # For ZONE scope
	var include_neighbors: bool = false   # For ZONE scope (include neighboring zones)
	var player_ids: Array[String] = []  # For CUSTOM scope
	var is_server_wide: bool = false     # For SERVER scope

	static func server_wide() -> AlertScope:
		var scope := AlertScope.new()
		scope.is_server_wide = true
		return scope

	static func zone(zone: String, neighbors: bool = false) -> AlertScope:
		var scope := AlertScope.new()
		scope.zone_id = zone
		scope.include_neighbors = neighbors
		return scope

	static func nearby(pos: Vector3, rad: float = 50.0) -> AlertScope:
		var scope := AlertScope.new()
		scope.position = pos
		scope.radius = rad
		return scope

	static func players(ids: Array[String]) -> AlertScope:
		var scope := AlertScope.new()
		scope.player_ids = ids
		return scope

# Pending notifications queue
var _notification_queue: Array[Dictionary] = []
var _max_queue_size: int = 50

# Active notifications by entity
var _entity_notifications: Dictionary = {}  # entity_id -> [notifications]

# Notification history per entity
var _notification_history: Dictionary = {}  # entity_id -> [notification dicts]
var _max_history: int = 100

const _kv_prefix := "notification:"

# Frame-level dispatcher: handles TTL dedupe of NotificationContext events
# before they hit the per-player queue. Owned here so it shares the autoload
# lifecycle but can be tested in isolation (see notification_dispatcher.gd).
const NotificationDispatcher = preload("res://core/notifications/notification_dispatcher.gd")
var _dispatcher: RefCounted = null

signal notification_sent(entity_id: String, notification: Dictionary)
signal notification_received(entity_id: String, notification: Dictionary)
signal notification_queued(entity_id: String, queue_size: int)

func _ready() -> void:
	GameLog.info("NotificationService: Ready")

	# Initialize the frame-level dispatcher (TTL dedupe of contexts).
	_dispatcher = NotificationDispatcher.new()

	# Listen to unified spawn events for automatic notifications
	if EventHub:
		EventHub.entity_spawned.connect(_on_entity_spawned)

## Handle unified entity spawn event - auto-send notifications based on metadata
func _on_entity_spawned(entity_or_id, metadata: SpawnMetadata) -> void:
	if metadata == null or not metadata.notification_enabled:
		return

	# Build notification message
	var message: String
	match metadata.spawn_type:
		SpawnMetadata.SpawnType.WORLD_BOSS:
			message = "WORLD BOSS: %s has appeared in %s!" % [metadata.display_name, metadata.zone_id]
		SpawnMetadata.SpawnType.BOSS:
			message = "Boss %s has appeared!" % metadata.display_name
		SpawnMetadata.SpawnType.ELITE:
			message = "Elite enemy %s has appeared!" % metadata.display_name
		_:
			message = metadata.notification_message % [metadata.display_name, metadata.zone_id]

	# Determine notification settings from metadata
	var notif_type := NotificationType.WORLD_EVENT
	var priority := Priority.NORMAL
	match metadata.notification_priority:
		SpawnMetadata.NotificationPriority.LOW:
			priority = Priority.LOW
		SpawnMetadata.NotificationPriority.NORMAL:
			priority = Priority.NORMAL
		SpawnMetadata.NotificationPriority.HIGH:
			priority = Priority.HIGH
		SpawnMetadata.NotificationPriority.CRITICAL:
			priority = Priority.CRITICAL

	# Build extra data
	var data := {
		"spawn_type": metadata.get_spawn_type_string(),
		"zone_id": metadata.zone_id,
		"level": metadata.level
	}

	# Broadcast to configured scopes
	broadcast_alert(
		message,
		metadata.notification_scopes,
		notif_type,
		priority,
		DisplayLocation.CENTER_SCREEN,
		SoundType.NOTIFICATION,
		data
	)

	GameLog.info("NotificationService: Auto-broadcast spawn notification for %s" % metadata.display_name)

## Send a notification to a player
func send(
	entity_id: String,
	message: String,
	notif_type: NotificationType = NotificationType.SYSTEM,
	priority: Priority = Priority.NORMAL,
	location: DisplayLocation = DisplayLocation.CHAT_LOG,
	sound: SoundType = SoundType.NOTIFICATION,
	data: Dictionary = {}
) -> void:
	var notification := {
		"message": message,
		"type": notif_type,
		"priority": priority,
		"location": location,
		"sound": sound,
		"data": data,
		"timestamp": Time.get_ticks_msec(),
		"read": false
	}

	# Add to queue
	_notification_queue.append(notification)
	if _notification_queue.size() > _max_queue_size:
		_notification_queue.pop_at(0)

	# Track for entity
	if not _entity_notifications.has(entity_id):
		_entity_notifications[entity_id] = []
	_entity_notifications[entity_id].append(notification)

	# Add to history
	_add_to_history(entity_id, notification)
	_persist_notification_history(entity_id)

	notification_sent.emit(entity_id, notification)
	GameLog.debug("NotificationService: Sent to %s: %s" % [entity_id, message])

## Convenience alias for send() -- used by HUD/services that route a
## notification to a specific player by id. Accepts both enum values
## and raw ints (legacy callers pass ints from older enums).
func send_to_player(
	player_id: String,
	message: String,
	notif_type = NotificationType.SYSTEM,
	priority = Priority.NORMAL,
	location = DisplayLocation.CHAT_LOG,
	sound = SoundType.NOTIFICATION,
	data: Dictionary = {}
) -> void:
	var nt: int = _coerce_int(notif_type, NotificationType.SYSTEM)
	var pr: int = _coerce_int(priority, Priority.NORMAL)
	var loc: int = _coerce_int(location, DisplayLocation.CHAT_LOG)
	var snd: int = _coerce_int(sound, SoundType.NOTIFICATION)
	send(
		player_id,
		message,
		nt as NotificationType,
		pr as Priority,
		loc as DisplayLocation,
		snd as SoundType,
		data
	)

## Coerce Variant to int with fallback (handles legacy int callers).
static func _coerce_int(value, fallback: int) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	return fallback

## Broadcast notification to multiple scopes (server, zone, nearby, players)
## Can combine multiple scopes - e.g., server + zone, or zone + neighbors
##
## `scopes` is intentionally untyped (was `Array[AlertScope]`) so dynamic
## callers -- `notifier.call("broadcast_alert", ...)` from AppFirewall and
## tests -- can pass an array literal without tripping Godot 4.7.2's
## strict typed-array check. Each element is dispatched via
## `_get_players_for_scope(scope: AlertScope)`, which still validates at
## runtime via duck typing on `is_server_wide` / `zone_id` / etc.
func broadcast_alert(
	message: String,
	scopes: Array,
	notif_type: NotificationType = NotificationType.SYSTEM,
	priority: Priority = Priority.NORMAL,
	location: DisplayLocation = DisplayLocation.CENTER_SCREEN,
	sound: SoundType = SoundType.NOTIFICATION,
	data: Dictionary = {}
) -> void:
	var notified_players: Dictionary = {}  # entity_id -> true (avoid duplicates)

	for scope in scopes:
		var players_to_notify = _get_players_for_scope(scope)
		for player in players_to_notify:
			if not notified_players.has(player.entity_id):
				notified_players[player.entity_id] = true
				send(player.entity_id, message, notif_type, priority, location, sound, data)

## Get players matching a scope
func _get_players_for_scope(scope: AlertScope) -> Array:
	var results: Array = []
	var entity_service = EntityService
	if entity_service == null:
		return results

	var all_players = entity_service.get_all_players()

	if scope.is_server_wide:
		return all_players

	for player in all_players:
		var should_notify := false

		if scope.player_ids.size() > 0:
			# Custom player list
			should_notify = scope.player_ids.has(player.entity_id)

		elif scope.zone_id != "":
			# Zone-based
			var zone_manager = ZoneManager
			if zone_manager:
				var player_zone = zone_manager.get_entity_zone_id(player)
				should_notify = player_zone == scope.zone_id

				# Include neighbors if requested
				if should_notify == false and scope.include_neighbors:
					var neighbors = zone_manager.get_neighboring_zones(scope.zone_id)
					for neighbor in neighbors:
						if neighbor.id == player_zone:
							should_notify = true
							break

		elif scope.position != Vector3.ZERO:
			# Position-based (nearby)
			if is_instance_valid(player):
				should_notify = player.global_position.distance_to(scope.position) <= scope.radius

		if should_notify:
			results.append(player)

	return results

## Convenience: Server-wide alert
func broadcast_server(
	message: String,
	notif_type: NotificationType = NotificationType.SYSTEM,
	priority: Priority = Priority.HIGH,
	location: DisplayLocation = DisplayLocation.CENTER_SCREEN,
	sound: SoundType = SoundType.NOTIFICATION,
	data: Dictionary = {}
) -> void:
	broadcast_alert(message, [AlertScope.server_wide()], notif_type, priority, location, sound, data)

## Convenience: Zone alert (with optional neighbors)
func broadcast_zone(
	zone_id: String,
	message: String,
	notif_type: NotificationType = NotificationType.SYSTEM,
	priority: Priority = Priority.NORMAL,
	location: DisplayLocation = DisplayLocation.CHAT_LOG,
	sound: SoundType = SoundType.NOTIFICATION,
	include_neighbors: bool = false,
	data: Dictionary = {}
) -> void:
	broadcast_alert(message, [AlertScope.zone(zone_id, include_neighbors)], notif_type, priority, location, sound, data)

## Convenience: Nearby players alert
func broadcast_nearby(
	position: Vector3,
	radius: float,
	message: String,
	notif_type: NotificationType = NotificationType.SYSTEM,
	priority: Priority = Priority.NORMAL,
	location: DisplayLocation = DisplayLocation.CHAT_LOG,
	sound: SoundType = SoundType.NOTIFICATION,
	data: Dictionary = {}
) -> void:
	broadcast_alert(message, [AlertScope.nearby(position, radius)], notif_type, priority, location, sound, data)

## Convenience: Specific players
func broadcast_to_players(
	player_ids: Array[String],
	message: String,
	notif_type: NotificationType = NotificationType.SYSTEM,
	priority: Priority = Priority.NORMAL,
	location: DisplayLocation = DisplayLocation.CHAT_LOG,
	sound: SoundType = SoundType.NOTIFICATION,
	data: Dictionary = {}
) -> void:
	broadcast_alert(message, [AlertScope.players(player_ids)], notif_type, priority, location, sound, data)

## Combined example: Server + nearby zone
func broadcast_event_alert(
	message: String,
	event_zone_id: String,
	event_position: Vector3,
	radius: float = 100.0,
	notif_type: NotificationType = NotificationType.WORLD_EVENT,
	priority: Priority = Priority.HIGH
) -> void:
	var scopes: Array[AlertScope] = [
		AlertScope.server_wide(),
		AlertScope.zone(event_zone_id, true),
		AlertScope.nearby(event_position, radius)
	]
	broadcast_alert(message, scopes, notif_type, priority)

## --- Convenience Methods for Common Notifications ---

## Zone change notification
func notify_zone_change(entity_id: String, from_zone: String, to_zone: String) -> void:
	var message: String = "Entered %s" % to_zone
	send(entity_id, message, NotificationType.ZONE_CHANGE, Priority.NORMAL, DisplayLocation.BOTH, SoundType.NOTIFICATION, {
		"from_zone": from_zone,
		"to_zone": to_zone
	})

## Dungeon entry notification
func notify_dungeon_enter(entity_id: String, dungeon_name: String) -> void:
	var message: String = "Entering %s" % dungeon_name
	send(entity_id, message, NotificationType.DUNGEON, Priority.HIGH, DisplayLocation.CENTER_SCREEN, SoundType.DUNGEON_ENTER, {
		"dungeon_name": dungeon_name,
		"action": "enter"
	})

## Dungeon exit notification
func notify_dungeon_exit(entity_id: String, dungeon_name: String, completed: bool) -> void:
	var message: String = "Left %s" % dungeon_name
	if completed:
		message = "Completed %s!" % dungeon_name
	send(entity_id, message, NotificationType.DUNGEON, Priority.HIGH if completed else Priority.NORMAL, DisplayLocation.BOTH, SoundType.DUNGEON_COMPLETE if completed else SoundType.NONE, {
		"dungeon_name": dungeon_name,
		"action": "exit",
		"completed": completed
	})

## Level up notification
func notify_level_up(entity_id: String, new_level: int) -> void:
	var message: String = "Level Up! You are now level %d" % new_level
	send(entity_id, message, NotificationType.LEVEL_UP, Priority.HIGH, DisplayLocation.CENTER_SCREEN, SoundType.LEVEL_UP, {
		"new_level": new_level
	})

	# Special message at level 10: signature unlock
	if new_level == 10:
		send(entity_id, "Level 10! Visit the Skill Academy to choose your Signature ability. First selection is FREE!", NotificationType.ACHIEVEMENT, Priority.HIGH, DisplayLocation.CENTER_SCREEN, SoundType.ACHIEVEMENT, {
			"unlock_type": "signature",
			"academy_location": "capital"
		})

## Achievement notification
func notify_achievement(entity_id: String, achievement_name: String, description: String = "") -> void:
	var message: String = "Achievement Unlocked: %s" % achievement_name
	if description != "":
		message += "\n%s" % description
	send(entity_id, message, NotificationType.ACHIEVEMENT, Priority.HIGH, DisplayLocation.CENTER_SCREEN, SoundType.ACHIEVEMENT, {
		"achievement_name": achievement_name,
		"description": description
	})

## World event notification
func notify_world_event(entity_id: String, event_name: String, message: String) -> void:
	send(entity_id, message, NotificationType.WORLD_EVENT, Priority.HIGH, DisplayLocation.CENTER_SCREEN, SoundType.NOTIFICATION, {
		"event_name": event_name
	})

## Faction notification
func notify_faction(entity_id: String, faction_name: String, message: String) -> void:
	send(entity_id, message, NotificationType.FACTION, Priority.NORMAL, DisplayLocation.CHAT_LOG, SoundType.NOTIFICATION, {
		"faction_name": faction_name
	})

## Combat notification (crit, dodge, etc.)
func notify_combat(entity_id: String, combat_type: String, message: String, is_positive: bool = true) -> void:
	var priority := Priority.LOW
	var location := DisplayLocation.FLOATING
	var sound := SoundType.COMBAT

	match combat_type:
		"CRITICAL_HIT":
			message = "CRITICAL! " + message
			priority = Priority.NORMAL
		"DODGE":
			message = "Dodged!"
			priority = Priority.LOW
		"PARRY":
			message = "Parried!"
			priority = Priority.LOW
		"BLOCK":
			message = "Blocked!"
			priority = Priority.LOW
		"KILL":
			message = message + " defeated!"
			priority = Priority.NORMAL
		"DEATH":
			message = "You have been defeated..."
			priority = Priority.HIGH

	send(entity_id, message, NotificationType.COMBAT, priority, location, sound, {
		"combat_type": combat_type,
		"is_positive": is_positive
	})

## Item loot notification
func notify_item_loot(entity_id: String, item_name: String, rarity: String = "common") -> void:
	var message: String = "Looted: %s" % item_name
	var priority := Priority.NORMAL
	var sound := SoundType.NOTIFICATION

	match rarity.to_lower():
		"rare":
			message = "[Rare] " + message
			priority = Priority.HIGH
		"epic":
			message = "[Epic] " + message
			priority = Priority.HIGH
		"legendary":
			message = "[LEGENDARY] " + message
			priority = Priority.CRITICAL

	send(entity_id, message, NotificationType.ITEM, priority, DisplayLocation.CHAT_LOG, sound, {
		"item_name": item_name,
		"rarity": rarity
	})

## Gold change notification
func notify_gold_change(entity_id: String, amount: int, reason: String = "") -> void:
	var prefix := "+" if amount > 0 else ""
	var message: String = "%s%d Gold" % [prefix, amount]
	if reason != "":
		message += " (%s)" % reason
	send(entity_id, message, NotificationType.GOLD, Priority.LOW, DisplayLocation.CHAT_LOG, SoundType.NONE, {
		"amount": amount,
		"reason": reason
	})

## Warning notification
func notify_warning(entity_id: String, message: String) -> void:
	send(entity_id, message, NotificationType.WARNING, Priority.HIGH, DisplayLocation.CENTER_SCREEN, SoundType.WARNING, {})

## Error notification
func notify_error(entity_id: String, message: String) -> void:
	send(entity_id, message, NotificationType.ERROR, Priority.HIGH, DisplayLocation.CHAT_LOG, SoundType.ERROR, {})

## Quest notification
func notify_quest(entity_id: String, quest_name: String, action: String, message: String) -> void:
	send(entity_id, message, NotificationType.QUEST, Priority.NORMAL, DisplayLocation.CHAT_LOG, SoundType.NOTIFICATION, {
		"quest_name": quest_name,
		"action": action  # "started", "completed", "failed", "progress"
	})

## ============================================================================
## DEATH & RESPAWN NOTIFICATIONS
## ============================================================================

## Death notification - sent to the dead player
func notify_death(entity_id: String, killer_name: String = "", killer_type: String = "monster") -> void:
	var message: String
	var priority: Priority = Priority.HIGH
	var sound: SoundType = SoundType.DEATH

	if killer_name != "":
		match killer_type:
			"player", "pvp":
				message = "You have been slain by %s" % killer_name
				priority = Priority.HIGH
				sound = SoundType.WARNING
			_:
				message = "You have been defeated by %s" % killer_name
	else:
		message = "You have died"

	send(entity_id, message, NotificationType.SYSTEM, priority, DisplayLocation.CENTER_SCREEN, sound, {
		"killer_name": killer_name,
		"killer_type": killer_type
	})

## Party member death notification
func notify_party_member_died(entity_id: String, dead_player_name: String, killer_name: String = "") -> void:
	var message: String
	if killer_name != "":
		message = " %s has been slain by %s" % [dead_player_name, killer_name]
	else:
		message = " %s has died" % dead_player_name

	send(entity_id, message, NotificationType.COMBAT, Priority.NORMAL, DisplayLocation.CHAT_LOG, SoundType.WARNING, {
		"player_name": dead_player_name,
		"killer_name": killer_name
	})

## Revive started notification - to the target being revived
func notify_revive_started(target_id: String, healer_name: String) -> void:
	send(target_id, "%s is reviving you... Stay still!" % healer_name, NotificationType.SYSTEM, Priority.NORMAL,
		DisplayLocation.BOTH, SoundType.NOTIFICATION, {
		"healer_name": healer_name,
		"action": "revive_started"
	})

## Revive completed notification
func notify_revive_completed(target_id: String, healer_name: String) -> void:
	send(target_id, "You have been resurrected by %s!" % healer_name, NotificationType.SYSTEM, Priority.HIGH,
		DisplayLocation.BOTH, SoundType.ACHIEVEMENT, {
		"healer_name": healer_name,
		"action": "revive_completed"
	})
	# Also notify the healer
	send_to_player_name(healer_name, "You have resurrected %s!" % target_id, NotificationType.SYSTEM, Priority.NORMAL,
		DisplayLocation.CHAT_LOG, SoundType.NOTIFICATION, {
		"target_id": target_id,
		"action": "revive_completed"
	})

## Revive failed/interrupted notification
func notify_revive_failed(target_id: String, reason: String = "The revival was interrupted") -> void:
	send(target_id, "Revival failed: %s" % reason, NotificationType.WARNING, Priority.NORMAL,
		DisplayLocation.CHAT_LOG, SoundType.WARNING, {
		"reason": reason
	})

## Self-resurrection notification
func notify_self_resurrect(entity_id: String, item_name: String = "Soul Gem") -> void:
	send(entity_id, "You have self-resurrected using %s!" % item_name, NotificationType.SYSTEM, Priority.HIGH,
		DisplayLocation.BOTH, SoundType.SELF_REZ, {
		"item_name": item_name,
		"action": "self_resurrect"
	})

## Respawn at ankh notification
func notify_respawn_ankh(entity_id: String, ankh_name: String) -> void:
	send(entity_id, "Respawning at %s..." % ankh_name, NotificationType.SYSTEM, Priority.NORMAL,
		DisplayLocation.CHAT_LOG, SoundType.NONE, {
		"ankh_name": ankh_name,
		"method": "ankh"
	})

## Respawn timer notification
func notify_respawn_timer(entity_id: String, seconds_remaining: int) -> void:
	if seconds_remaining <= 5:
		send(entity_id, "Respawning in %d..." % seconds_remaining, NotificationType.SYSTEM, Priority.LOW,
			DisplayLocation.CENTER_SCREEN, SoundType.NOTIFICATION, {
			"seconds": seconds_remaining
		})

## Corpse expiring soon warning
func notify_corpse_expiring(entity_id: String, seconds_remaining: int) -> void:
	send(entity_id, " Your corpse will disappear in %d seconds!" % seconds_remaining, NotificationType.WARNING, Priority.NORMAL,
		DisplayLocation.CHAT_LOG, SoundType.WARNING, {
		"seconds": seconds_remaining
	})

## Corpse looted by another player
func notify_corpse_looted_victim(entity_id: String, looter_name: String, item_name: String = "") -> void:
	var message: String = "%s has looted your corpse" % looter_name
	if item_name != "":
		message += ": %s" % item_name
	send(entity_id, message, NotificationType.ITEM, Priority.LOW, DisplayLocation.CHAT_LOG, SoundType.NONE, {
		"looter_name": looter_name,
		"item_name": item_name
	})

## Cannot loot notification
func notify_cannot_loot(entity_id: String, reason: String) -> void:
	send(entity_id, "Cannot loot: %s" % reason, NotificationType.WARNING, Priority.LOW,
		DisplayLocation.CHAT_LOG, SoundType.NONE, {
		"reason": reason
	})

## Ankh bound notification
func notify_ankh_bound(entity_id: String, ankh_name: String) -> void:
	send(entity_id, " Bound to %s" % ankh_name, NotificationType.SYSTEM, Priority.NORMAL,
		DisplayLocation.CHAT_LOG, SoundType.NOTIFICATION, {
		"ankh_name": ankh_name
	})

## Cannot bind to ankh notification
func notify_cannot_bind_ankh(entity_id: String, reason: String) -> void:
	send(entity_id, "Cannot bind to ankh: %s" % reason, NotificationType.WARNING, Priority.NORMAL,
		DisplayLocation.CHAT_LOG, SoundType.WARNING, {
		"reason": reason
	})

## PvP kill feed notification
func notify_pvp_kill(killer_name: String, victim_name: String, zone_name: String = "") -> void:
	var message: String = "%s defeated %s" % [killer_name, victim_name]
	if zone_name != "":
		message += " in %s" % zone_name

	# Broadcast to nearby players
	var scope := AlertScope.new()
	scope.is_server_wide = GameConfig.Social.BROADCAST_PVP_KILLS if GameConfig and GameConfig.Social else false
	broadcast_alert(message, [scope], NotificationType.COMBAT, Priority.NORMAL, DisplayLocation.CHAT_LOG, SoundType.WARNING, {
		"killer_name": killer_name,
		"victim_name": victim_name,
		"zone_name": zone_name,
		"type": "pvp_kill"
	})

## Revive abuse detected warning
func notify_revive_abuse_warning(entity_id: String, context: String) -> void:
	send(entity_id, " Revive abuse detected in %s. Further abuse will result in karma loss." % context,
		NotificationType.WARNING, Priority.HIGH, DisplayLocation.CENTER_SCREEN, SoundType.WARNING, {
		"context": context,
		"type": "abuse_warning"
	})

## Invincibility gained notification
func notify_invincibility_gained(entity_id: String, duration: float, reason: String = "") -> void:
	var message: String = " Invincible for %.0f seconds" % duration
	if reason == "respawn":
		message = " Respawn protection: %s" % message
	elif reason == "griefing_protection":
		message = " Griefing protection active"
	send(entity_id, message, NotificationType.SYSTEM, Priority.NORMAL,
		DisplayLocation.CENTER_SCREEN, SoundType.INVINCIBILITY, {
		"duration": duration,
		"reason": reason
	})

## Invincibility lost notification
func notify_invincibility_lost(entity_id: String, reason: String = "") -> void:
	var message: String = " Invincibility ended"
	if reason == "expired":
		message = " Respawn protection has worn off"
	send(entity_id, message, NotificationType.WARNING, Priority.NORMAL,
		DisplayLocation.CHAT_LOG, SoundType.WARNING, {
		"reason": reason
	})

## Kill streak notification
func notify_kill_streak(entity_id: String, streak: int, xp_bonus: int, gold_bonus: int) -> void:
	var emojis: Array[String] = ["", "", "", "", ""]
	var idx := mini(streak / 5, emojis.size() - 1)
	var emoji: String = emojis[idx]
	var message: String = "%s Kill streak %d! +%d XP, +%d gold" % [emoji, streak, xp_bonus, gold_bonus]
	send(entity_id, message, NotificationType.COMBAT, Priority.HIGH,
		DisplayLocation.BOTH, SoundType.KILL_STREAK, {
		"streak": streak,
		"xp_bonus": xp_bonus,
		"gold_bonus": gold_bonus
	})

## Griefing protection notification
func notify_griefing_protection(entity_id: String, duration: float) -> void:
	send(entity_id, " Griefing protection activated for %.0f seconds!" % duration,
		NotificationType.WARNING, Priority.HIGH, DisplayLocation.CENTER_SCREEN, SoundType.INVINCIBILITY, {
		"duration": duration,
		"type": "griefing_protection"
	})

## ============================================================================
## UTILITY METHODS
## ============================================================================

## Send notification to a player by their name
func send_to_player_name(player_name: String, message: String, notif_type: NotificationType = NotificationType.SYSTEM,
		priority: Priority = Priority.NORMAL, location: DisplayLocation = DisplayLocation.CHAT_LOG,
		sound: SoundType = SoundType.NOTIFICATION, data: Dictionary = {}) -> bool:
	var entity_service = EntityService
	if entity_service == null:
		GameLog.warn("NotificationService: Cannot find player by name - EntityService not available")
		return false

	var players = entity_service.get_all_players()
	for player in players:
		if player.has("display_name") and player.display_name == player_name:
			send(player.entity_id, message, notif_type, priority, location, sound, data)
			return true

	GameLog.debug("NotificationService: Player not found: %s" % player_name)
	return false

## Get unread notifications for entity
func get_unread(entity_id: String) -> Array[Dictionary]:
	if not _entity_notifications.has(entity_id):
		return []
	return _entity_notifications[entity_id].filter(func(n): return not n.get("read", false))

## Mark notification as read
func mark_read(entity_id: String, index: int) -> void:
	if _entity_notifications.has(entity_id) and index < _entity_notifications[entity_id].size():
		_entity_notifications[entity_id][index]["read"] = true

## Get notification history for entity
func get_history(entity_id: String, limit: int = 20) -> Array:
	if not _notification_history.has(entity_id):
		return []
	var history = _notification_history[entity_id]
	if limit > 0:
		return history.slice(max(0, history.size() - limit))
	return history

## Clear notifications for entity
func clear_notifications(entity_id: String) -> void:
	_entity_notifications.erase(entity_id)
	GameLog.debug("NotificationService: Cleared notifications for %s" % entity_id)

## Get unread count
func get_unread_count(entity_id: String) -> int:
	return get_unread(entity_id).size()

## Remove entity (disconnect)
func remove_entity(entity_id: String) -> void:
	_entity_notifications.erase(entity_id)
	_notification_history.erase(entity_id)

func _load_notification_history() -> void:
	var store := DictStore.new()
	var keys := store.all_keys()
	for key in keys:
		if key.begins_with(_kv_prefix):
			var entity_id := key.substr(_kv_prefix.length())
			var data := store.get(key)
			if data is Array and not data.is_empty():
				_notification_history[entity_id] = data

func _persist_notification_history(entity_id: String) -> void:
	var store := DictStore.new()
	if _notification_history.has(entity_id) and not _notification_history[entity_id].is_empty():
		store.set(_kv_prefix + entity_id, _notification_history[entity_id])
	else:
		store.erase(_kv_prefix + entity_id)

func _add_to_history(entity_id: String, notification: Dictionary) -> void:
	if not _notification_history.has(entity_id):
		_notification_history[entity_id] = []
	_notification_history[entity_id].append(notification)

	# Trim history
	while _notification_history[entity_id].size() > _max_history:
		_notification_history[entity_id].pop_at(0)

# ============================================================================
# FRAME-LEVEL ENTRY POINT
# ============================================================================
#
# send_event(ctx) is the single dispatch shape every game service should use
# to surface something to a player (or to admins). It runs the context through
# the TTL dedupe gate (see notification_dispatcher.gd), maps the NotifKind
# to a NotificationType/Priority/DisplayLocation, and forwards to send()
# (player scope) or broadcast_alert() (server-wide / admin scope).
#
# Returns true if the context was delivered, false if it was dropped by dedupe
# or had no resolvable recipient.

const NotificationContext = preload("res://core/notifications/notification_context.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

func send_event(ctx) -> bool:
	if ctx == null:
		return false
	if _dispatcher == null:
		# Defensive: autoload may be in a partial state during early init
		# or in --script test mode. Defer to a fresh dispatcher so callers
		# never get a Null call.
	_dispatcher = NotificationDispatcher.new()

	_load_notification_history()
	if not _dispatcher.should_deliver(ctx):
		return false

	var notif_type: int = _notif_type_for_kind(ctx.kind)
	var priority: int = _priority_for_kind(ctx.kind)
	# HIGH+ kinds render in the center of the screen; everything else is a
	# corner toast (the show_toast() entry point in TooltipManager).
	var location: int = DisplayLocation.CENTER_SCREEN if priority >= Priority.HIGH else DisplayLocation.CORNER

	var data: Dictionary = ctx.data.duplicate()
	data["kind"] = ctx.kind
	data["source_service"] = ctx.source_service
	if ctx.dedupe_key != "":
		data["dedupe_key"] = ctx.dedupe_key

	# player_id == "" means broadcast (server-wide or admin scope). Otherwise
	# the target is that one player.
	if ctx.player_id == "":
		broadcast_alert(
			ctx.message,
			[AlertScope.server_wide()],
			notif_type
		)
		# Also emit the typed signal so listeners (admin UI, audit) can hook
		# without parsing the message.
		notification_received.emit("", {
			"message": ctx.message,
			"type": notif_type,
			"kind": ctx.kind,
			"source_service": ctx.source_service,
			"data": data,
		})
		return true
	else:
		send(
			ctx.player_id,
			ctx.message,
			notif_type,
			priority,
			location,
			SoundType.NOTIFICATION,
			data
		)
		return true


# ---------------------------------------------------------------------------
# Service-level convenience: notify(...)
#
# Most call sites (QoS, Security, Faction, Inventory, ...) don't care about
# the NotificationContext shape -- they just want to fire a typed notification
# and let the frame dedupe, type-map, and route. notify() builds the context
# for them and forwards to send_event().
#
# This is the "verb" of the notification pipeline. send_event() is the
# "shape" -- kept as the frame entry point for tests and for callers that
# already have a context. New code should prefer notify().
# ---------------------------------------------------------------------------

## Fire a typed notification through the frame.
##
## `kind`        : int from NotifKind (e.g. NotifKind.RATE_LIMITED)
## `message`     : the visible toast text
## `source_service`: string label for the caller ("QoSService",
##                  "SecurityService", "AppFirewall", ...)
## `dedupe_key`  : stable key for the 5s dedupe window. Pass "" to disable
##                 dedupe for this context (e.g. one-shot admin alerts).
## `data`        : optional payload dict (routed to listeners verbatim)
## `recipient`   : player_id, or "" for server-wide broadcast. Defaults to "".
##
## Returns true if delivered, false if dedupe-dropped or invalid.
func notify(
	kind: int,
	message: String,
	source_service: String,
	dedupe_key: String = "",
	data: Dictionary = {},
	recipient: String = ""
) -> bool:
	var ctx
	if recipient == "":
		ctx = NotificationContext.broadcast(kind, message, source_service, data, dedupe_key)
	else:
		ctx = NotificationContext.for_player(recipient, kind, message, source_service, data, dedupe_key)
	return send_event(ctx)


# Map a NotifKind to the legacy NotificationType so the existing render
# pipeline (toast / chat / center screen) keeps working without changes.
func _notif_type_for_kind(kind: int) -> int:
	match kind:
		NotifKind.RESPAWNED, NotifKind.RESPAWN_FAILED, NotifKind.RESPAWN_PENALTY_APPLIED:
			return NotificationType.SYSTEM
		NotifKind.ITEM_ADDED, NotifKind.ITEM_REMOVED:
			return NotificationType.ITEM
		NotifKind.ITEM_FULL, NotifKind.ITEM_SOULBOUND_REJECT, NotifKind.ITEM_TRADE_REJECT:
			return NotificationType.WARNING
		NotifKind.FACTION_CHANGED, NotifKind.FACTION_REP_CHANGED, NotifKind.FACTION_PVP_MODE_CHANGED:
			return NotificationType.FACTION
		NotifKind.QUEST_ACCEPTED, NotifKind.QUEST_UPDATED, NotifKind.QUEST_COMPLETED, \
		NotifKind.QUEST_FAILED, NotifKind.QUEST_TURNED_IN, NotifKind.QUEST_REWARDED:
			return NotificationType.QUEST
		NotifKind.SECURITY_WARNING:
			return NotificationType.WARNING
		NotifKind.SECURITY_BLOCKED, NotifKind.ADMIN_ALERT, NotifKind.PLAYER_WARNED, NotifKind.AUTO_ACTION:
			return NotificationType.ALERT
		NotifKind.QOS_DEGRADED, NotifKind.THROTTLED, NotifKind.RATE_LIMITED, NotifKind.CIRCUIT_OPEN:
			return NotificationType.WARNING
		NotifKind.QOS_RECOVERED:
			return NotificationType.INFO
		_:
			return NotificationType.SYSTEM


func _priority_for_kind(kind: int) -> int:
	match kind:
		NotifKind.SECURITY_BLOCKED, NotifKind.ADMIN_ALERT, NotifKind.AUTO_ACTION, \
		NotifKind.RESPAWN_FAILED, NotifKind.ITEM_SOULBOUND_REJECT, NotifKind.CIRCUIT_OPEN:
			return Priority.HIGH
		NotifKind.PLAYER_WARNED, NotifKind.ITEM_FULL, NotifKind.ITEM_TRADE_REJECT, \
		NotifKind.QOS_DEGRADED, NotifKind.RATE_LIMITED, NotifKind.RESPAWN_PENALTY_APPLIED, \
		NotifKind.FACTION_PVP_MODE_CHANGED:
			return Priority.NORMAL
		_:
			return Priority.LOW


## Public hook for tests / admin "clear toasts" command. Resets the dedupe
## gate so the next context with a given key is always delivered.
func reset_dedupe() -> void:
	if _dispatcher:
		_dispatcher.reset()


## Read-only view into the dedupe state. Used by tests; may be wired to a
## future debug overlay.
func dedupe_tracked_count() -> int:
	if _dispatcher:
		return _dispatcher.tracked_count()
	return 0
