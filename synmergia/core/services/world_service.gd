## WorldService - World state and gateway management
## Coordinates zones, gateways, day/night cycle, and world events
extends Node

# World time (in minutes, 0 = midnight)
var world_time_minutes: int = 0
var day_duration_minutes: int = 1440  # 24 hours real-time = 24 hours game-time

# Time multipliers for testing
var time_multiplier: float = 1.0

# Day/night cycle
var _current_time_of_day: String = "day"  # day, night, dawn, dusk

# Gateways (gateway_id -> GatewayData)
var _gateways: Dictionary = {}

# World events
var _active_events: Array[Dictionary] = []
var _event_templates: Dictionary = {}

# World seed for procedural generation
var world_seed: int = 0

signal time_changed(time_of_day: String, hour: int)
signal day_changed(day_number: int)
signal gateway_activated(gateway_id: String, entity)
signal event_started(event_id: String, event_name: String)
signal event_ended(event_id: String, event_name: String)

# Gateway schema
class GatewayData:
	var id: String
	var display_name: String
	var position: Vector3
	var radius: float = 5.0
	var from_zone_id: String
	var to_zone_id: String
	var to_position: Vector3
	var required_level: int = 1
	var required_faction: String = ""
	var required_quest: String = ""
	var is_locked: bool = false
	var unlock_requirement: String = ""
	var activation_radius: float = 3.0
	
	func can_use(entity) -> bool:
		if is_locked:
			return false
		if entity.level < required_level:
			return false
		if required_faction != "" and entity.faction_id != required_faction:
			return false
		return true
	
	func get_destination() -> Dictionary:
		return {
			"zone_id": to_zone_id,
			"position": to_position
		}

func _ready() -> void:
	GameLog.info("WorldService: Ready")

## Initialize the world
func initialize_world() -> void:
	# Load all zones
	var zone_manager = ZoneManager
	if zone_manager:
		zone_manager.load_zones()
	
	# Load all factions
	var faction_manager = FactionManager
	if faction_manager:
		faction_manager.load_factions()
	
	GameLog.info("WorldService: World initialized")

## Get current time of day string
func get_time_of_day() -> String:
	return _current_time_of_day

## Get current hour (0-23)
func get_current_hour() -> int:
	return (world_time_minutes / 60) % 24

## Get current day number (game day)
func get_current_day() -> int:
	return world_time_minutes / day_duration_minutes

## Set world time (for server start/load)
func set_world_time(minutes: int) -> void:
	world_time_minutes = clampi(minutes, 0, day_duration_minutes * 365)  # Cap at 1 year
	_update_time_of_day()

## Advance world time (call from _process)
func advance_time(delta: float) -> void:
	var old_day = get_current_day()
	world_time_minutes += int(delta * time_multiplier * 60.0 / 60.0)  # Convert to minutes
	
	# Cap at 1 year
	if world_time_minutes > day_duration_minutes * 365:
		world_time_minutes = day_duration_minutes * 365
	
	_update_time_of_day()
	
	var new_day = get_current_day()
	if new_day > old_day:
		day_changed.emit(new_day)

func _update_time_of_day() -> void:
	var hour = get_current_hour()
	var old_time = _current_time_of_day
	
	if hour >= 6 and hour < 8:
		_current_time_of_day = "dawn"
	elif hour >= 8 and hour < 18:
		_current_time_of_day = "day"
	elif hour >= 18 and hour < 20:
		_current_time_of_day = "dusk"
	else:
		_current_time_of_day = "night"
	
	if old_time != _current_time_of_day:
		time_changed.emit(_current_time_of_day, hour)

## Get daylight percentage (0.0 = midnight, 1.0 = noon)
func get_daylight_percentage() -> float:
	var hour = get_current_hour()
	var minute_in_hour = world_time_minutes % 60
	
	# Simple sine wave for daylight
	var day_minutes = hour * 60 + minute_in_hour
	var midday = 12 * 60  # 720 minutes
	
	var distance = abs(day_minutes - midday)
	var max_distance = 12 * 60  # 720 minutes
	
	return maxf(0.0, 1.0 - (float(distance) / float(max_distance)))

## Gateway management

## Register a gateway
func register_gateway(config: Dictionary) -> String:
	var gateway_id = "gateway_%s_to_%s" % [config.get("from_zone", ""), config.get("to_zone", "")]
	
	var gateway := GatewayData.new()
	gateway.id = gateway_id
	gateway.display_name = config.get("display_name", "Gateway")
	gateway.position = config.get("position", Vector3.ZERO)
	gateway.from_zone_id = config.get("from_zone", "")
	gateway.to_zone_id = config.get("to_zone", "")
	gateway.to_position = config.get("to_position", Vector3.ZERO)
	gateway.required_level = config.get("required_level", 1)
	gateway.required_faction = config.get("required_faction", "")
	gateway.required_quest = config.get("required_quest", "")
	gateway.is_locked = config.get("is_locked", false)
	gateway.unlock_requirement = config.get("unlock_requirement", "")
	gateway.radius = config.get("radius", 5.0)
	gateway.activation_radius = config.get("activation_radius", 3.0)
	
	_gateways[gateway_id] = gateway
	GameLog.debug("WorldService: Registered gateway %s" % gateway_id)
	return gateway_id

## Get gateway by ID
func get_gateway(gateway_id: String) -> GatewayData:
	return _gateways.get(gateway_id)

## Get all gateways in a zone
func get_zone_gateways(zone_id: String) -> Array:
	var results: Array = []
	for gateway in _gateways.values():
		if gateway.from_zone_id == zone_id:
			results.append(gateway)
	return results

## Get gateways at position
func get_gateways_at_position(position: Vector3, radius: float = 10.0) -> Array:
	var results: Array = []
	for gateway in _gateways.values():
		if gateway.position.distance_to(position) <= radius + gateway.radius:
			results.append(gateway)
	return results

## Use a gateway
func use_gateway(gateway_id: String, entity) -> Dictionary:
	var gateway = _gateways.get(gateway_id)
	if gateway == null:
		return {}
	
	if not gateway.can_use(entity):
		GameLog.debug("WorldService: %s cannot use gateway %s" % [entity.display_name, gateway_id])
		return {}
	
	# Exit current zone
	var zone_manager = ZoneManager
	if zone_manager:
		zone_manager.entity_exit_zone(entity)
	
	# Move to destination
	var destination = gateway.get_destination()
	entity.global_position = destination.position
	
	# Enter destination zone
	var dest_zone = zone_manager.get_zone(destination.zone_id)
	if dest_zone:
		zone_manager.entity_enter_zone(entity, dest_zone)
	
	gateway_activated.emit(gateway_id, entity)
	EventHub.entity_teleported.emit(entity, gateway.position, destination.position)
	
	GameLog.debug("WorldService: %s used gateway %s to %s" % [entity.display_name, gateway_id, destination.zone_id])
	return destination

## Lock/unlock gateway
func set_gateway_locked(gateway_id: String, locked: bool) -> void:
	var gateway = _gateways.get(gateway_id)
	if gateway:
		gateway.is_locked = locked
		GameLog.info("WorldService: Gateway %s %s" % [gateway_id, "locked" if locked else "unlocked"])

## Check gateway proximity and return usable gateways
func get_nearby_gateway(entity) -> GatewayData:
	var zone_manager = ZoneManager
	if zone_manager == null:
		return null
	
	var zone_id = zone_manager.get_entity_zone_id(entity)
	var gateways = get_zone_gateways(zone_id)
	
	for gateway in gateways:
		if gateway.position.distance_to(entity.global_position) <= gateway.activation_radius:
			if gateway.can_use(entity):
				return gateway
	
	return null

## World events

## Start a world event
func start_event(event_id: String, duration_seconds: float, message: String = "") -> void:
	if _active_events.any(func(e): return e.get("id") == event_id):
		return  # Already active
	
	var event := {
		"id": event_id,
		"name": event_id,
		"duration": duration_seconds,
		"remaining": duration_seconds,
		"started_at": Time.get_ticks_msec()
	}
	
	_active_events.append(event)
	
	# Apply event effects
	_apply_event_effects(event_id, true)
	
	event_started.emit(event_id, event_id)
	GameLog.info("WorldService: Event started: %s" % event_id)
	
	# Notify players
	var notification_service = NotificationService
	if notification_service:
		if message == "":
			message = "WORLD EVENT: %s has begun!" % event_id
		notification_service.broadcast_server(
			message,
			NotificationService.NotificationType.WORLD_EVENT,
			NotificationService.Priority.HIGH,
			NotificationService.DisplayLocation.CENTER_SCREEN,
			NotificationService.SoundType.NOTIFICATION,
			{"event_id": event_id, "duration": duration_seconds}
		)

## End an event
func end_event(event_id: String, message: String = "") -> void:
	var event_index = _active_events.find(_active_events.filter(func(e): return e.get("id") == event_id).pop_at(0))
	if event_index >= 0:
		var event = _active_events[event_index]
		_active_events.remove_at(event_index)
		
		# Remove event effects
		_apply_event_effects(event_id, false)
		
		event_ended.emit(event_id, event.get("name", event_id))
		GameLog.info("WorldService: Event ended: %s" % event_id)
		
		# Notify players
		var notification_service = NotificationService
		if notification_service:
			if message == "":
				message = "WORLD EVENT: %s has ended." % event_id
			notification_service.broadcast_server(
				message,
				NotificationService.NotificationType.WORLD_EVENT,
				NotificationService.Priority.NORMAL,
				NotificationService.DisplayLocation.CENTER_SCREEN,
				NotificationService.SoundType.NOTIFICATION,
				{"event_id": event_id}
			)

## Check if event is active
func is_event_active(event_id: String) -> bool:
	return _active_events.any(func(e): return e.get("id") == event_id)

## Process events (call from _process)
func process_events(delta: float) -> void:
	var events_to_end: Array[String] = []
	
	for event in _active_events:
		event["remaining"] -= delta
		if event["remaining"] <= 0:
			events_to_end.append(event["id"])
	
	for event_id in events_to_end:
		end_event(event_id)

## Get active events
func get_active_events() -> Array[Dictionary]:
	return _active_events

func _apply_event_effects(event_id: String, is_start: bool) -> void:
	# Event-specific effects
	match event_id:
		"double_xp":
			# Could modify XP multipliers
			pass
		"double_loot":
			# Could modify loot multipliers
			pass
		"invasion":
			# Could spawn more enemies
			var spawn_service = SpawnService
			if spawn_service:
				for zone_id in spawn_service._spawn_points:
					spawn_service.set_spawn_multiplier(zone_id, 2.0 if is_start else 1.0)

## Procedural world (seed-based)

## Generate world from seed
func generate_world_from_seed(seed_value: int) -> void:
	world_seed = seed_value
	seed(seed_value)
	GameLog.info("WorldService: Generating world from seed %d" % seed_value)
	# Zone generation would happen here
	# For now, we assume zones are pre-defined

## Get seeded random value
func get_seeded_random(range_max: int) -> int:
	return randi() % range_max

## Find path between zones (simplified)
func find_zone_path(from_zone_id: String, to_zone_id: String) -> Array[String]:
	# Simple direct path for now
	# Could implement A* or similar for complex routing
	if from_zone_id == to_zone_id:
		return [from_zone_id]
	
	# Check for direct gateway connection
	var gateways = get_zone_gateways(from_zone_id)
	for gateway in gateways:
		if gateway.to_zone_id == to_zone_id:
			return [from_zone_id, to_zone_id]
	
	# Return direct path (would need pathfinding for complex world)
	return [from_zone_id, to_zone_id]
