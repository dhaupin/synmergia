## NotificationService - Player notification system
## Handles all player notifications: zone changes, achievements, combat, events, etc.
class_name NotificationService
extends Node

# Notification types
enum NotificationType {
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
enum SoundType {
	NONE = 0
	NOTIFICATION = 1
	ACHIEVEMENT = 2
	LEVEL_UP = 3
	WARNING = 4
	ERROR = 5
	DUNGEON_ENTER = 6
	DUNGEON_COMPLETE = 7
	COMBAT = 8
}

# Pending notifications queue
var _notification_queue: Array[Dictionary] = []
var _max_queue_size: int = 50

# Active notifications by entity
var _entity_notifications: Dictionary = {}  # entity_id -> [notifications]

# Notification history per entity
var _notification_history: Dictionary = {}  # entity_id -> [notification dicts]
var _max_history: int = 100

signal notification_sent(entity_id: String, notification: Dictionary)
signal notification_received(entity_id: String, notification: Dictionary)
signal notification_queued(entity_id: String, queue_size: int)

func _ready() -> void:
	Logger.info("NotificationService: Ready")

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
		_notification_queue.pop_front()
	
	# Track for entity
	if not _entity_notifications.has(entity_id):
		_entity_notifications[entity_id] = []
	_entity_notifications[entity_id].append(notification)
	
	# Add to history
	_add_to_history(entity_id, notification)
	
	notification_sent.emit(entity_id, notification)
	Logger.debug("NotificationService: Sent to %s: %s" % [entity_id, message])

## Send notification to multiple entities
func broadcast(
	entity_ids: Array[String],
	message: String,
	notif_type: NotificationType = NotificationType.SYSTEM,
	priority: Priority = Priority.NORMAL,
	location: DisplayLocation = DisplayLocation.CHAT_LOG,
	sound: SoundType = SoundType.NOTIFICATION,
	data: Dictionary = {}
) -> void:
	for entity_id in entity_ids:
		send(entity_id, message, notif_type, priority, location, sound, data)

## Send notification to entire zone
func broadcast_zone(
	zone_id: String,
	message: String,
	notif_type: NotificationType = NotificationType.SYSTEM,
	priority: Priority = Priority.NORMAL,
	location: DisplayLocation = DisplayLocation.CHAT_LOG,
	sound: SoundType = SoundType.NOTIFICATION,
	data: Dictionary = {}
) -> void:
	var zone_manager = ZoneManager
	if zone_manager:
		var players = zone_manager.get_players_in_zone(zone_id)
		for player in players:
			send(player.entity_id, message, notif_type, priority, location, sound, data)

## Send notification to all online players
func broadcast_all(
	message: String,
	notif_type: NotificationType = NotificationType.SYSTEM,
	priority: Priority = Priority.NORMAL,
	location: DisplayLocation = DisplayLocation.CENTER_SCREEN,
	sound: SoundType = SoundType.NOTIFICATION,
	data: Dictionary = {}
) -> void:
	var entity_service = EntityService
	if entity_service:
		var players = entity_service.get_all_players()
		for player in players:
			send(player.entity_id, message, notif_type, priority, location, sound, data)

## Send notification to players near a position
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
	var entity_service = EntityService
	if entity_service:
		var players = entity_service.get_all_players()
		for player in players:
			if is_instance_valid(player) and player.global_position.distance_to(position) <= radius:
				send(player.entity_id, message, notif_type, priority, location, sound, data)

## --- Convenience Methods for Common Notifications ---

## Zone change notification
func notify_zone_change(entity_id: String, from_zone: String, to_zone: String) -> void:
	var message := "Entered %s" % to_zone
	send(entity_id, message, NotificationType.ZONE_CHANGE, Priority.NORMAL, DisplayLocation.BOTH, SoundType.NOTIFICATION, {
		"from_zone": from_zone,
		"to_zone": to_zone
	})

## Dungeon entry notification
func notify_dungeon_enter(entity_id: String, dungeon_name: String) -> void:
	var message := "Entering %s" % dungeon_name
	send(entity_id, message, NotificationType.DUNGEON, Priority.HIGH, DisplayLocation.CENTER_SCREEN, SoundType.DUNGEON_ENTER, {
		"dungeon_name": dungeon_name,
		"action": "enter"
	})

## Dungeon exit notification
func notify_dungeon_exit(entity_id: String, dungeon_name: String, completed: bool) -> void:
	var message := "Left %s" % dungeon_name
	if completed:
		message = "Completed %s!" % dungeon_name
	send(entity_id, message, NotificationType.DUNGEON, Priority.HIGH if completed else Priority.NORMAL, DisplayLocation.BOTH, SoundType.DUNGEON_COMPLETE if completed else SoundType.NONE, {
		"dungeon_name": dungeon_name,
		"action": "exit",
		"completed": completed
	})

## Level up notification
func notify_level_up(entity_id: String, new_level: int) -> void:
	var message := "Level Up! You are now level %d" % new_level
	send(entity_id, message, NotificationType.LEVEL_UP, Priority.HIGH, DisplayLocation.CENTER_SCREEN, SoundType.LEVEL_UP, {
		"new_level": new_level
	})

## Achievement notification
func notify_achievement(entity_id: String, achievement_name: String, description: String = "") -> void:
	var message := "Achievement Unlocked: %s" % achievement_name
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
	var message := "Looted: %s" % item_name
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
	var message := "%s%d Gold" % [prefix, amount]
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

## --- Utility Methods ---

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
func get_history(entity_id: String, limit: int = 20) -> Array[Dictionary]:
	if not _notification_history.has(entity_id):
		return []
	var history = _notification_history[entity_id]
	if limit > 0:
		return history.slice(max(0, history.size() - limit))
	return history

## Clear notifications for entity
func clear_notifications(entity_id: String) -> void:
	_entity_notifications.erase(entity_id)
	Logger.debug("NotificationService: Cleared notifications for %s" % entity_id)

## Get unread count
func get_unread_count(entity_id: String) -> int:
	return get_unread(entity_id).size()

## Remove entity (disconnect)
func remove_entity(entity_id: String) -> void:
	_entity_notifications.erase(entity_id)
	_notification_history.erase(entity_id)

func _add_to_history(entity_id: String, notification: Dictionary) -> void:
	if not _notification_history.has(entity_id):
		_notification_history[entity_id] = []
	_notification_history[entity_id].append(notification)
	
	# Trim history
	while _notification_history[entity_id].size() > _max_history:
		_notification_history[entity_id].pop_front()
