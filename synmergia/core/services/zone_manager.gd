## ZoneManager - Zone state and transition management
## Tracks all zones, players per zone, and handles zone transitions
class_name ZoneManager
extends Node

# All loaded zones (zone_id -> zone_data)
var _zones: Dictionary = {}

# Players per zone (zone_id -> Array of player entities)
var _players_in_zone: Dictionary = {}

# Enemies per zone (zone_id -> Array of enemy entities)
var _enemies_in_zone: Dictionary = {}

# Instances (instance_id -> instance data)
var _instances: Dictionary = {}
var _next_instance_id: int = 1

# Current zone for each entity
var _entity_zones: Dictionary = {}  # entity_id -> zone_id

signal zone_loaded(zone_data: ZoneData)
signal zone_unloaded(zone_id: String)
signal player_entered_zone(player: Entity, zone: ZoneData)
signal player_exited_zone(player: Entity, zone: ZoneData)
signal zone_population_changed(zone_id: String, count: int)
signal instance_created(instance_id: String, zone_data: ZoneData)
signal instance_destroyed(instance_id: String)

func _ready() -> void:
	Logger.info("ZoneManager: Ready")

## Load all zones from data
func load_zones() -> void:
	var data_service = DataService
	if not data_service:
		Logger.warn("ZoneManager: DataService not available")
		return
	
	var zone_data_dict = data_service.get_all_zones()
	for zone_id in zone_data_dict:
		register_zone(zone_data_dict[zone_id])
	
	Logger.info("ZoneManager: Loaded %d zones" % _zones.size())

## Register a zone
func register_zone(zone_data: ZoneData) -> void:
	if zone_data == null:
		return
	
	_zones[zone_data.id] = zone_data
	_players_in_zone[zone_data.id] = []
	_enemies_in_zone[zone_data.id] = []
	
	zone_loaded.emit(zone_data)
	Logger.debug("ZoneManager: Registered zone %s" % zone_data.id)

## Get zone by ID
func get_zone(zone_id: String) -> ZoneData:
	return _zones.get(zone_id)

## Get all loaded zones
func get_all_zones() -> Array[ZoneData]:
	return _zones.values()

## Get players in a zone
func get_players_in_zone(zone_id: String) -> Array[Entity]:
	return _players_in_zone.get(zone_id, [])

## Get enemies in a zone
func get_enemies_in_zone(zone_id: String) -> Array[Entity]:
	return _enemies_in_zone.get(zone_id, [])

## Get zone population
func get_zone_population(zone_id: String) -> int:
	return _players_in_zone.get(zone_id, []).size()

## Get current zone for an entity
func get_entity_zone(entity: Entity) -> ZoneData:
	var zone_id = _entity_zones.get(entity.entity_id, "")
	if zone_id == "":
		return null
	return _zones.get(zone_id)

## Get current zone ID for an entity
func get_entity_zone_id(entity: Entity) -> String:
	return _entity_zones.get(entity.entity_id, "")

## Handle entity entering a zone
func entity_enter_zone(entity: Entity, zone: ZoneData) -> bool:
	if entity == null or zone == null:
		return false
	
	# Check entry requirements
	if not zone.can_enter(entity):
		Logger.debug("ZoneManager: %s cannot enter zone %s" % [entity.display_name, zone.id])
		return false
	
	# Remove from old zone
	var old_zone_id = _entity_zones.get(entity.entity_id, "")
	if old_zone_id != "":
		entity_exit_zone(entity)
	
	# Add to new zone
	_entity_zones[entity.entity_id] = zone.id
	
	if entity.entity_type == Entity.EntityType.PLAYER:
		_players_in_zone[zone.id].append(entity)
		player_entered_zone.emit(entity, zone)
		zone_population_changed.emit(zone.id, get_zone_population(zone.id))
	elif entity.entity_type == Entity.EntityType.ENEMY:
		_enemies_in_zone[zone.id].append(entity)
	
	EventBus.entity_entered_zone.emit(entity, zone)
	Logger.debug("ZoneManager: %s entered zone %s" % [entity.display_name, zone.id])
	return true

## Handle entity exiting a zone
func entity_exit_zone(entity: Entity) -> bool:
	var zone_id = _entity_zones.get(entity.entity_id, "")
	if zone_id == "":
		return false
	
	var zone = _zones.get(zone_id)
	_entity_zones.erase(entity.entity_id)
	
	if entity.entity_type == Entity.EntityType.PLAYER:
		_players_in_zone[zone_id].erase(entity)
		if zone:
			player_exited_zone.emit(entity, zone)
		zone_population_changed.emit(zone_id, get_zone_population(zone_id))
	elif entity.entity_type == Entity.EntityType.ENEMY:
		_enemies_in_zone[zone_id].erase(entity)
	
	if zone:
		EventBus.entity_exited_zone.emit(entity, zone)
	
	Logger.debug("ZoneManager: %s exited zone %s" % [entity.display_name, zone_id])
	return true

## Check if entity can enter a zone
func can_enter_zone(entity: Entity, zone_id: String) -> bool:
	var zone = _zones.get(zone_id)
	if zone == null:
		return false
	return zone.can_enter(entity)

## Check if PvP is allowed between two entities in current zone
func can_pvp(entity1: Entity, entity2: Entity) -> bool:
	var zone_id = _entity_zones.get(entity1.entity_id, "")
	if zone_id == "":
		return false
	
	var zone = _zones.get(zone_id)
	if zone == null:
		return false
	
	return zone.can_pvp(entity1, entity2)

## Create an instance (dungeon, etc.)
func create_instance(base_zone_id: String, owner_id: String = "") -> String:
	var base_zone = _zones.get(base_zone_id)
	if base_zone == null:
		Logger.warn("ZoneManager: Cannot create instance, base zone %s not found" % base_zone_id)
		return ""
	
	var instance_id = "instance_%d" % _next_instance_id
	_next_instance_id += 1
	
	var instance_data := {
		"instance_id": instance_id,
		"base_zone_id": base_zone_id,
		"owner_id": owner_id,
		"zone_data": base_zone.duplicate(true),
		"players": [],
		"enemies": [],
		"created_at": Time.get_ticks_msec()
	}
	
	# Set instance properties
	instance_data.zone_data.id = instance_id
	instance_data.zone_data.is_instanced = true
	
	_instances[instance_id] = instance_data
	register_zone(instance_data.zone_data)
	
	instance_created.emit(instance_id, instance_data.zone_data)
	Logger.info("ZoneManager: Created instance %s from %s" % [instance_id, base_zone_id])
	return instance_id

## Destroy an instance
func destroy_instance(instance_id: String) -> bool:
	if not _instances.has(instance_id):
		return false
	
	var instance_data = _instances[instance_id]
	
	# Remove all entities from instance
	var instance_zone = _zones.get(instance_id)
	if instance_zone:
		# Note: This should trigger proper exit handling
		instance_data.players.clear()
		instance_data.enemies.clear()
	
	_instances.erase(instance_id)
	_zones.erase(instance_id)
	_players_in_zone.erase(instance_id)
	_enemies_in_zone.erase(instance_id)
	
	instance_destroyed.emit(instance_id)
	Logger.info("ZoneManager: Destroyed instance %s" % instance_id)
	return true

## Get instance data
func get_instance(instance_id: String) -> Dictionary:
	return _instances.get(instance_id, {})

## Add entity to instance
func add_to_instance(entity: Entity, instance_id: String) -> bool:
	if not _instances.has(instance_id):
		return false
	
	var instance_data = _instances[instance_id]
	instance_data.players.append(entity)
	
	# Switch entity to instance zone
	return entity_enter_zone(entity, instance_data.zone_data)

## Get nearby zones (for gateway system)
func get_nearby_zones(from_zone_id: String, max_distance: float = 1000.0) -> Array[ZoneData]:
	var results: Array[ZoneData] = []
	var from_zone = _zones.get(from_zone_id)
	if from_zone == null:
		return results
	
	for zone_id in _zones:
		var zone = _zones[zone_id]
		if zone_id == from_zone_id or zone.is_instanced:
			continue
		
		var distance := from_zone.zone_center.distance_to(zone.zone_center)
		if distance <= max_distance:
			results.append(zone)
	
	return results

## Get zones by PvP mode
func get_zones_by_pvp_mode(pvp_mode: ZoneData.PvPZoneMode) -> Array[ZoneData]:
	var results: Array[ZoneData] = []
	for zone in _zones.values():
		if zone.pvp_mode == pvp_mode:
			results.append(zone)
	return results

## Get zones for level range
func get_zones_for_level(level: int) -> Array[ZoneData]:
	var results: Array[ZoneData] = []
	for zone in _zones.values():
		if zone.is_instanced:
			continue
		if level >= zone.level_requirement and (zone.max_level <= 0 or level <= zone.max_level):
			results.append(zone)
	return results
