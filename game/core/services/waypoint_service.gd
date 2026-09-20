## WaypointService - Player waypoint management system
## Allows players to create, manage, and navigate to waypoints
## Supports: Custom waypoints, Quest waypoints, Map integration, Minimap, Compass
extends Node
# QoSService uses static shim methods (AGENTS.md allowlist); the const is required.
const QoSService = preload("res://core/autoload/qos_service.gd")

# QoSService and NotificationService are autoloads. QoSService
# exposes a static facade (QoSService.rate_limit(...)), so a const
# preload here resolves to the class and the static methods still
# dispatch to the singleton at runtime -- no shadow. NotificationService
# is NOT preloaded: it is accessed bare as the singleton instance
# (NotificationService.notify(...)), which requires the autoload
# to be registered before this file compiles.
const DictStore = preload("res://adapters/persistence/dict_store.gd")

# Waypoint colors (preset options)
enum WaypointColor {
	RED,
	ORANGE,
	YELLOW,
	GREEN,
	BLUE,
	PURPLE,
	PINK,
	WHITE
}

# Waypoint icons
enum WaypointIcon {
	FLAG,       # Default flag
	STAR,       # Important location
	CHEST,      # Loot
	SKULL,      # Danger/enemy
	HOUSE,      # Town/safe zone
	CAVE,       # Dungeon/entrance
	QUEST,      # Quest objective
	PLAYER,     # Player location
	COMPASS,    # Direction
	CUSTOM      # User defined
}

# Limits
const MAX_WAYPOINTS_PER_PLAYER: int = 50
const MIN_WAYPOINT_NAME_LENGTH: int = 1
const MAX_WAYPOINT_NAME_LENGTH: int = 32

# Waypoint data structure
class Waypoint:
	var id: String
	var name: String
	var position: Vector3
	var zone_id: String
	var color: int = WaypointColor.BLUE
	var icon: int = WaypointIcon.FLAG
	var is_visible: bool = true
	var is_locked: bool = false
	var show_beacon: bool = true
	var is_quest_waypoint: bool = false
	var quest_id: String = ""
	var created_at: float
	var updated_at: float

	func _init(p_id: String = "", p_name: String = "", p_pos: Vector3 = Vector3.ZERO, p_zone: String = ""):
		id = p_id
		name = p_name
		position = p_pos
		zone_id = p_zone
		created_at = Time.get_unix_time_from_system()
		updated_at = created_at

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"position_x": position.x,
			"position_y": position.y,
			"position_z": position.z,
			"zone_id": zone_id,
			"color": color,
			"icon": icon,
			"is_visible": is_visible,
			"is_locked": is_locked,
			"show_beacon": show_beacon,
			"is_quest_waypoint": is_quest_waypoint,
			"quest_id": quest_id,
			"created_at": created_at,
			"updated_at": updated_at
		}

	static func from_dict(data: Dictionary) -> Waypoint:
		var wp := Waypoint.new()
		wp.id = data.get("id", "")
		wp.name = data.get("name", "")
		wp.position = Vector3(
			data.get("position_x", 0.0),
			data.get("position_y", 0.0),
			data.get("position_z", 0.0)
		)
		wp.zone_id = data.get("zone_id", "")
		wp.color = data.get("color", WaypointColor.BLUE)
		wp.icon = data.get("icon", WaypointIcon.FLAG)
		wp.is_visible = data.get("is_visible", true)
		wp.is_locked = data.get("is_locked", false)
		wp.show_beacon = data.get("show_beacon", true)
		wp.is_quest_waypoint = data.get("is_quest_waypoint", false)
		wp.quest_id = data.get("quest_id", "")
		wp.created_at = data.get("created_at", 0.0)
		wp.updated_at = data.get("updated_at", 0.0)
		return wp

# Player waypoints (player_id -> Array[Waypoint])
var _player_waypoints: Dictionary = {}
const _kv_prefix := "waypoint:player:"

# Active/target waypoint per player
var _active_waypoint: Dictionary = {}

# Config (BEACON_HEIGHT_OFFSET and WAYPOINT_RANGE_COMPLETE are
# defined here, not in the block above, because that block is the
# "public" constants and these are internal tuning values.)
const BEACON_HEIGHT_OFFSET: float = 50.0  # Height above waypoint for beacon
const WAYPOINT_RANGE_COMPLETE: float = 5.0  # Distance to complete waypoint

# Signals
signal waypoint_created(player_id: String, waypoint: Dictionary)
signal waypoint_updated(player_id: String, waypoint: Dictionary)
signal waypoint_deleted(player_id: String, waypoint_id: String)
signal waypoint_activated(player_id: String, waypoint_id: String)
signal waypoint_deactivated(player_id: String, waypoint_id: String)
signal waypoint_reached(player_id: String, waypoint_id: String)
signal waypoints_cleared(player_id: String, count: int)

func _ready() -> void:
	GameLog.info("WaypointService: Ready")
	_load_waypoints()

## Create a new waypoint
func create_waypoint(player_id: String, name: String, position: Vector3, zone_id: String,
		color: int = WaypointColor.BLUE, icon: int = WaypointIcon.FLAG,
		is_quest: bool = false, quest_id: String = "") -> Dictionary:

	# QoS: Rate limit waypoint creation (prevent spam)
	if QoSService and not QoSService.rate_limit(player_id, "waypoint_create"):
		return {"success": false, "message": "Creating waypoints too fast"}

	# Sanitize and validate input
	name = _sanitize_name(name)

	# Validate position bounds (prevent far-teleport exploits)
	if not _is_valid_position(position):
		return {"success": false, "message": "Invalid position"}

	# Validate color/icon enums
	if not _is_valid_color(color):
		color = WaypointColor.BLUE
	if not _is_valid_icon(icon):
		icon = WaypointIcon.FLAG

	# Check limit
	var waypoints := get_waypoints(player_id)
	if waypoints.size() >= MAX_WAYPOINTS_PER_PLAYER:
		return {"success": false, "message": "Maximum waypoints reached (%d)" % MAX_WAYPOINTS_PER_PLAYER}

	# Create waypoint
	var wp := Waypoint.new(generate_id(), name, position, zone_id)
	wp.color = color
	wp.icon = icon
	wp.is_quest_waypoint = is_quest
	wp.quest_id = quest_id

	# Add to storage
	if not _player_waypoints.has(player_id):
		_player_waypoints[player_id] = []
	_player_waypoints[player_id].append(wp)
	_persist_waypoints(player_id)

	var wp_dict := wp.to_dict()
	waypoint_created.emit(player_id, wp_dict)
	_notify_player(player_id, "Waypoint '%s' created" % name)

	# Auto-activate if it's a quest waypoint
	if is_quest:
		activate_waypoint(player_id, wp.id)

	return {"success": true, "waypoint": wp_dict}

## Create waypoint at current player position
func create_waypoint_here(player_id: String, name: String) -> Dictionary:
	if not EntityService:
		return {"success": false, "message": "Cannot get player position"}

	var entity = EntityService.get_entity_by_id(player_id)
	if not entity or not is_instance_valid(entity):
		return {"success": false, "message": "Player not found"}

	var position: Vector3 = entity.global_position if entity.has("global_position") else Vector3.ZERO
	var zone_id: String = ZoneManager.get_current_zone_id() if ZoneManager else ""

	return create_waypoint(player_id, name, position, zone_id)

## Get all waypoints for a player
func get_waypoints(player_id: String) -> Array[Dictionary]:
	if not _player_waypoints.has(player_id):
		return []

	var result: Array[Dictionary] = []
	for wp in _player_waypoints[player_id]:
		result.append(wp.to_dict())
	return result

## Get waypoint by ID
func get_waypoint(player_id: String, waypoint_id: String) -> Dictionary:
	if not _player_waypoints.has(player_id):
		return {}

	for wp in _player_waypoints[player_id]:
		if wp.id == waypoint_id:
			return wp.to_dict()
	return {}

## Update a waypoint
func update_waypoint(player_id: String, waypoint_id: String, updates: Dictionary) -> Dictionary:
	if not _player_waypoints.has(player_id):
		return {"success": false, "message": "No waypoints found"}

	var wp: Waypoint = null
	for w in _player_waypoints[player_id]:
		if w.id == waypoint_id:
			wp = w
			break

	if not wp:
		return {"success": false, "message": "Waypoint not found"}

	# Cannot modify quest waypoints (except visibility)
	if wp.is_quest_waypoint and not updates.has("is_visible"):
		return {"success": false, "message": "Cannot modify quest waypoint"}

	# Apply updates with validation
	if updates.has("name"):
		wp.name = _sanitize_name(str(updates.name))

	if updates.has("color"):
		var color_val: int = int(updates.color) if updates.color is int or updates.color is String else -1
		if _is_valid_color(color_val):
			wp.color = color_val

	if updates.has("icon"):
		var icon_val: int = int(updates.icon) if updates.icon is int or updates.icon is String else -1
		if _is_valid_icon(icon_val):
			wp.icon = icon_val

	if updates.has("is_visible"):
		wp.is_visible = bool(updates.is_visible)

	if updates.has("is_locked"):
		# Cannot lock/unlock quest waypoints
		if not wp.is_quest_waypoint:
			wp.is_locked = bool(updates.is_locked)

	if updates.has("show_beacon"):
		wp.show_beacon = bool(updates.show_beacon)

	wp.updated_at = Time.get_unix_time_from_system()

	var wp_dict := wp.to_dict()
	waypoint_updated.emit(player_id, wp_dict)
	_persist_waypoints(player_id)

	return {"success": true, "waypoint": wp_dict}

## Delete a waypoint
func delete_waypoint(player_id: String, waypoint_id: String) -> Dictionary:
	# Sanitize inputs
	waypoint_id = str(waypoint_id)

	if not _player_waypoints.has(player_id):
		return {"success": false, "message": "No waypoints found"}

	if waypoint_id.is_empty():
		return {"success": false, "message": "Invalid waypoint ID"}

	var wp: Waypoint = null
	var index: int = -1
	for i in range(_player_waypoints[player_id].size()):
		if _player_waypoints[player_id][i].id == waypoint_id:
			wp = _player_waypoints[player_id][i]
			index = i
			break

	if not wp:
		return {"success": false, "message": "Waypoint not found"}

	# Cannot delete locked or quest waypoints
	if wp.is_locked:
		return {"success": false, "message": "Cannot delete locked waypoint"}

	if wp.is_quest_waypoint:
		return {"success": false, "message": "Cannot delete quest waypoint"}

	# Deactivate if active
	if _active_waypoint.get(player_id, "") == waypoint_id:
		deactivate_waypoint(player_id)

	_player_waypoints[player_id].remove_at(index)
	waypoint_deleted.emit(player_id, waypoint_id)
	_notify_player(player_id, "Waypoint deleted")
	_persist_waypoints(player_id)

	return {"success": true}

## Delete all non-locked waypoints
func clear_waypoints(player_id: String, include_quest: bool = false) -> int:
	if not _player_waypoints.has(player_id):
		return 0

	var to_remove: Array = []
	for wp in _player_waypoints[player_id]:
		if not wp.is_locked:
			if include_quest or not wp.is_quest_waypoint:
				to_remove.append(wp.id)

	var count := 0
	for wp_id in to_remove:
		# Deactivate if active
		if _active_waypoint.get(player_id, "") == wp_id:
			deactivate_waypoint(player_id)

		# Find and remove
		for i in range(_player_waypoints[player_id].size()):
			if _player_waypoints[player_id][i].id == wp_id:
				_player_waypoints[player_id].remove_at(i)
				waypoint_deleted.emit(player_id, wp_id)
				count += 1
				break

	if count > 0:
		waypoints_cleared.emit(player_id, count)
		_notify_player(player_id, "Deleted %d waypoints" % count)

	return count

## Activate a waypoint (sets as target)
func activate_waypoint(player_id: String, waypoint_id: String) -> Dictionary:
	if not _player_waypoints.has(player_id):
		return {"success": false, "message": "No waypoints found"}

	var wp: Waypoint = null
	for w in _player_waypoints[player_id]:
		if w.id == waypoint_id:
			wp = w
			break

	if not wp:
		return {"success": false, "message": "Waypoint not found"}

	# Deactivate previous
	var old_id: String = _active_waypoint.get(player_id, "")
	if old_id != "" and old_id != waypoint_id:
		waypoint_deactivated.emit(player_id, old_id)

	_active_waypoint[player_id] = waypoint_id
	waypoint_activated.emit(player_id, waypoint_id)

	return {"success": true, "waypoint": wp.to_dict()}

## Deactivate current waypoint
func deactivate_waypoint(player_id: String) -> void:
	var old_id: String = _active_waypoint.get(player_id, "")
	if old_id != "":
		_active_waypoint.erase(player_id)
		waypoint_deactivated.emit(player_id, old_id)

## Get active waypoint for player
func get_active_waypoint(player_id: String) -> Dictionary:
	var waypoint_id: String = _active_waypoint.get(player_id, "")
	if waypoint_id == "":
		return {}
	return get_waypoint(player_id, waypoint_id)

## Get distance to active waypoint
func get_distance_to_active(player_id: String) -> float:
	var wp_dict := get_active_waypoint(player_id)
	if wp_dict.is_empty():
		return -1.0

	if not EntityService:
		return -1.0

	var entity = EntityService.get_entity_by_id(player_id)
	if not entity or not is_instance_valid(entity):
		return -1.0

	var player_pos: Vector3 = entity.global_position if entity.has("global_position") else Vector3.ZERO
	var wp_pos: Vector3 = Vector3(wp_dict.get("position_x", 0.0), wp_dict.get("position_y", 0.0), wp_dict.get("position_z", 0.0))

	return player_pos.distance_to(wp_pos)

## Check if player reached active waypoint
func check_waypoint_reached(player_id: String) -> bool:
	var wp_dict := get_active_waypoint(player_id)
	if wp_dict.is_empty():
		return false

	var distance := get_distance_to_active(player_id)
	if distance >= 0 and distance <= WAYPOINT_RANGE_COMPLETE:
		waypoint_reached.emit(player_id, wp_dict.id)
		return true

	return false

## Process: Check for waypoint proximity
func _process(delta: float) -> void:
	# Check all players with active waypoints
	for player_id in _active_waypoint.keys():
		check_waypoint_reached(player_id)

## Quest integration: Create waypoint for quest
func create_quest_waypoint(player_id: String, quest_id: String, name: String,
		position: Vector3, zone_id: String, icon: int = WaypointIcon.QUEST) -> Dictionary:
	return create_waypoint(player_id, name, position, zone_id,
		WaypointColor.ORANGE, icon, true, quest_id)

## Quest integration: Remove quest waypoints
func remove_quest_waypoints(player_id: String, quest_id: String) -> void:
	if not _player_waypoints.has(player_id):
		return

	var to_remove: Array = []
	for wp in _player_waypoints[player_id]:
		if wp.is_quest_waypoint and wp.quest_id == quest_id:
			to_remove.append(wp)

	for wp in to_remove:
		var index: int = _player_waypoints[player_id].find(wp)
		if index >= 0:
			# Deactivate if active
			if _active_waypoint.get(player_id, "") == wp.id:
				deactivate_waypoint(player_id)
			_player_waypoints[player_id].remove_at(index)
			waypoint_deleted.emit(player_id, wp.id)

## Get color value for UI
static func get_color_value(color: int) -> Color:
	match color:
		WaypointColor.RED:    return Color(1.0, 0.3, 0.3)
		WaypointColor.ORANGE: return Color(1.0, 0.6, 0.2)
		WaypointColor.YELLOW: return Color(1.0, 0.9, 0.3)
		WaypointColor.GREEN:  return Color(0.3, 1.0, 0.3)
		WaypointColor.BLUE:   return Color(0.3, 0.6, 1.0)
		WaypointColor.PURPLE: return Color(0.8, 0.3, 1.0)
		WaypointColor.PINK:   return Color(1.0, 0.4, 0.7)
		WaypointColor.WHITE:  return Color(1.0, 1.0, 1.0)
		_: return Color(0.3, 0.6, 1.0)

## Get icon string for UI
static func get_icon_string(icon: int) -> String:
	match icon:
		WaypointIcon.FLAG:   return ""
		WaypointIcon.STAR:   return ""
		WaypointIcon.CHEST:  return ""
		WaypointIcon.SKULL:  return ""
		WaypointIcon.HOUSE:  return ""
		WaypointIcon.CAVE:   return ""
		WaypointIcon.QUEST:  return ""
		WaypointIcon.PLAYER: return ""
		WaypointIcon.COMPASS: return ""
		WaypointIcon.CUSTOM: return ""
		_: return ""

## Generate unique ID
func generate_id() -> String:
	return "wp_%s_%d" % [Time.get_unix_time_from_system(), randi() % 10000]

## Save waypoints (for persistence)
func save_waypoints(player_id: String) -> Dictionary:
	if not _player_waypoints.has(player_id):
		return {"waypoints": []}

	var data: Array = []
	for wp in _player_waypoints[player_id]:
		if not wp.is_quest_waypoint:  # Don't save quest waypoints
			data.append(wp.to_dict())

	return {"waypoints": data}

## Load waypoints (from persistence)
func load_waypoints(player_id: String, data: Dictionary) -> void:
	_player_waypoints[player_id] = []

	var waypoints: Array = data.get("waypoints", [])
	for wp_data in waypoints:
		var wp := Waypoint.from_dict(wp_data)
		_player_waypoints[player_id].append(wp)

## Helper: Notify player
func _notify_player(player_id: String, message: String) -> void:
	if NotificationService:
		NotificationService.notify(
			NotificationService.NotificationType.INFO,
			message,
			"WaypointService",
			"waypoint:%s:%d" % [player_id, message.hash()],
			{},
			player_id
		)

## Security: Sanitize waypoint name (prevent XSS, injection)
func _sanitize_name(name: String) -> String:
	# Truncate to max length
	if name.length() > MAX_WAYPOINT_NAME_LENGTH:
		name = name.substr(0, MAX_WAYPOINT_NAME_LENGTH)

	if name.is_empty():
		name = "Waypoint %d" % int(Time.get_unix_time_from_system())

	# Remove dangerous characters (BBCode injection prevention)
	name = name.replace("[", "(").replace("]", ")")
	name = name.replace("<", "(").replace(">", ")")

	# Strip control characters
	name = name.strip_edges(true, true)

	# Prevent empty or whitespace-only names
	if name.is_empty() or name.strip_edges().is_empty():
		name = "Waypoint %d" % int(Time.get_unix_time_from_system())

	return name

## Security: Validate position bounds
func _is_valid_position(position: Vector3) -> bool:
	# Check for NaN or infinity
	if not position.is_finite():
		return false

	# Check world bounds (prevent teleport exploits)
	const MAX_COORD: float = 100000.0
	if abs(position.x) > MAX_COORD or abs(position.y) > MAX_COORD or abs(position.z) > MAX_COORD:
		return false

	return true

## Security: Validate color enum
func _is_valid_color(color: int) -> bool:
	return color >= 0 and color < WaypointColor.size()

## Security: Validate icon enum
func _is_valid_icon(icon: int) -> bool:
	return icon >= 0 and icon < WaypointIcon.size()

func _load_waypoints() -> void:
	var store := DictStore.new()
	var keys: Array = store.all_keys()
	var waypoint_keys: Array = []
	for key in keys:
		if key.begins_with(_kv_prefix):
			waypoint_keys.append(key)
	
	if not waypoint_keys.is_empty():
		var results: Dictionary = store.get_many(waypoint_keys)
		for key in waypoint_keys:
			var player_id: String = key.substr(_kv_prefix.length())
			var data: Array = results.get(key, [])
			if data is Array:
				var waypoints: Array = []
				for wp_data in data:
					if wp_data is Dictionary:
						waypoints.append(Waypoint.from_dict(wp_data))
				if not waypoints.is_empty():
					_player_waypoints[player_id] = waypoints

func _persist_waypoints(player_id: String) -> void:
	var store := DictStore.new()
	if _player_waypoints.has(player_id):
		var data: Array = []
		for wp in _player_waypoints[player_id]:
			data.append(wp.to_dict())
		store.set_kv(_kv_prefix + player_id, data)
	else:
		store.erase(_kv_prefix + player_id)


func persist_all_waypoints() -> void:
	var store := DictStore.new()
	var entries: Dictionary = {}
	for player_id in _player_waypoints.keys():
		var data: Array = []
		for wp in _player_waypoints[player_id]:
			data.append(wp.to_dict())
		entries[_kv_prefix + player_id] = data
	if not entries.is_empty():
		store.set_batch(entries)
