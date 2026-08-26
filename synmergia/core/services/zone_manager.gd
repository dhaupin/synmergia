## ZoneManager - Zone state and transition management
## Handles zone transitions (seamless & instanced), population, and zone boundaries
class_name ZoneManager
extends Node

# Zone types
enum ZoneType {
	OPEN_WORLD,    # Seamless, players always in same world
	INSTANCED,     # Separate instance (dungeon, raid)
	SEAMLESS_INST # Instance but seamless (no loading screen)
}

# All loaded zones (zone_id -> zone_data)
var _zones: Dictionary = {}

# Players per zone (zone_id -> Array of player entities)
var _players_in_zone: Dictionary = {}

# Enemies per zone (zone_id -> Array of enemy entities)
var _enemies_in_zone: Dictionary = {}

# Instances (instance_id -> instance data)
var _instances: Dictionary = {}
var _next_instance_id: int = 1

# Zone transitions for seamless world (zone_id -> [connected_zone_ids])
var _zone_neighbors: Dictionary = {}

# Current zone for each entity
var _entity_zones: Dictionary = {}  # entity_id -> zone_id

# Seamless transition tracking
var _transition_zones: Dictionary = {}  # zone_id -> [transition_bounds]
var _seamless_enabled: bool = true

signal zone_loaded(zone_data: ZoneData)
signal zone_unloaded(zone_id: String)
signal player_entered_zone(player: Entity, zone: ZoneData)
signal player_exited_zone(player: Entity, zone: ZoneData)
signal zone_population_changed(zone_id: String, count: int)

# Seamless transition signals
signal seamless_transition_started(entity: Entity, from_zone: ZoneData, to_zone: ZoneData)
signal seamless_transition_completed(entity: Entity, to_zone: ZoneData)
signal seamless_transition_cancelled(entity: Entity, reason: String)

# Instance signals
signal instance_created(instance_id: String, zone_data: ZoneData)
signal instance_destroyed(instance_id: String)
signal instance_joined(player: Entity, instance_id: String)
signal instance_left(player: Entity, instance_id: String)

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

	# Auto-register zone neighbors based on proximity
	auto_register_zone_neighbors()

## Register a zone
func register_zone(zone_data: ZoneData) -> void:
	if zone_data == null:
		return
	
	_zones[zone_data.id] = zone_data
	_players_in_zone[zone_data.id] = []
	_enemies_in_zone[zone_data.id] = []
	
	zone_loaded.emit(zone_data)
	Logger.debug("ZoneManager: Registered zone %s" % zone_data.id)

## Auto-register zone neighbors based on proximity
func auto_register_zone_neighbors(max_distance: float = 1500.0) -> void:
        var zones_array: Array[ZoneData] = _zones.values()
        var registered_count: int = 0
        
        for i in range(zones_array.size()):
                var zone1: ZoneData = zones_array[i]
                for j in range(i + 1, zones_array.size()):
                        var zone2: ZoneData = zones_array[j]
                        
                        # Calculate distance between zone centers
                        var distance := zone1.zone_center.distance_to(zone2.zone_center)
                        var combined_radius := zone1.zone_radius + zone2.zone_radius
                        
                        # If zones overlap or are close enough, register as neighbors
                        if distance <= max_distance:
                                register_zone_neighbors(zone1.id, zone2.id)
                                registered_count += 1
        
        Logger.info("ZoneManager: Auto-registered %d zone neighbor connections" % registered_count)

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

# --- Seamless World Support ---

## Enable/disable seamless transitions
func set_seamless_enabled(enabled: bool) -> void:
	_seamless_enabled = enabled
	Logger.info("ZoneManager: Seamless transitions %s" % ("enabled" if enabled else "disabled"))

## Register zones as neighbors (for seamless transitions)
func register_zone_neighbors(zone1_id: String, zone2_id: String) -> void:
	if not _zone_neighbors.has(zone1_id):
		_zone_neighbors[zone1_id] = []
	if not _zone_neighbors.has(zone2_id):
		_zone_neighbors[zone2_id] = []
	
	if not _zone_neighbors[zone1_id].has(zone2_id):
		_zone_neighbors[zone1_id].append(zone2_id)
	if not _zone_neighbors[zone2_id].has(zone1_id):
		_zone_neighbors[zone2_id].append(zone1_id)
	
	Logger.debug("ZoneManager: Registered neighbors: %s <-> %s" % [zone1_id, zone2_id])

## Get neighboring zones
func get_neighboring_zones(zone_id: String) -> Array[ZoneData]:
	var results: Array[ZoneData] = []
	var neighbor_ids = _zone_neighbors.get(zone_id, [])
	for neighbor_id in neighbor_ids:
		var zone = _zones.get(neighbor_id)
		if zone:
			results.append(zone)
	return results

## Check if seamless transition should occur
func check_seamless_transition(entity: Entity) -> ZoneData:
	if not _seamless_enabled:
		return null
	
	var current_zone_id = _entity_zones.get(entity.entity_id, "")
	if current_zone_id == "":
		return null
	
	var current_zone = _zones.get(current_zone_id)
	if current_zone == null:
		return null
	
	# Check if entity crossed zone boundary
	var neighbors = get_neighboring_zones(current_zone_id)
	for neighbor in neighbors:
		if neighbor.contains_position(entity.global_position):
			return neighbor
	
	return null

## Perform seamless transition
func perform_seamless_transition(entity: Entity, to_zone: ZoneData) -> bool:
	if to_zone == null:
		return false
	
	var from_zone = _zones.get(_entity_zones.get(entity.entity_id, ""))
	if from_zone == null:
		return false
	
	# Emit start signal
	seamless_transition_started.emit(entity, from_zone, to_zone)
	
	# Exit current zone
	_entity_zones.erase(entity.entity_id)
	_players_in_zone[from_zone.id].erase(entity)
	_players_in_zone[from_zone.id].remove_at(_players_in_zone[from_zone.id].find(entity))
	player_exited_zone.emit(entity, from_zone)
	EventBus.entity_exited_zone.emit(entity, from_zone)
	
	# Enter new zone
	_entity_zones[entity.entity_id] = to_zone.id
	if not _players_in_zone.has(to_zone.id):
		_players_in_zone[to_zone.id] = []
	_players_in_zone[to_zone.id].append(entity)
	player_entered_zone.emit(entity, to_zone)
	EventBus.entity_entered_zone.emit(entity, to_zone)
	
	# Send notification
	_notify_zone_change(entity, from_zone, to_zone)
	
	# Emit completion
	seamless_transition_completed.emit(entity, to_zone)
	Logger.debug("ZoneManager: %s seamless transitioned %s -> %s" % [entity.display_name, from_zone.id, to_zone.id])
	return true

func _notify_zone_change(entity: Entity, from_zone: ZoneData, to_zone: ZoneData) -> void:
	var notification_service = NotificationService
	if notification_service and entity.entity_type == Entity.EntityType.PLAYER:
		notification_service.notify_zone_change(entity.entity_id, from_zone.id, to_zone.id)

## Process all entities for seamless transitions (call from _process)
func process_seamless_transitions() -> void:
	for entity_id in _entity_zones:
		var entity_service = EntityService
		if entity_service:
			var entity = entity_service.get_entity(entity_id)
			if entity and is_instance_valid(entity):
				var new_zone = check_seamless_transition(entity)
				if new_zone:
					perform_seamless_transition(entity, new_zone)

## Get zone type
func get_zone_type(zone_id: String) -> ZoneType:
	var zone = _zones.get(zone_id)
	if zone == null:
		return ZoneType.OPEN_WORLD
	
	if zone.is_instanced:
		return ZoneType.INSTANCED
	return ZoneType.OPEN_WORLD

## Create seamless instance (no loading screen)
func create_seamless_instance(base_zone_id: String, party_ids: Array[String] = []) -> String:
	# Seamless instance = instanced but players transition without loading
	var instance_id = create_instance(base_zone_id)
	if instance_id != "":
		var instance_data = _instances.get(instance_id, {})
		instance_data["seamless"] = true
	return instance_id

## Check if entity can enter instance
func can_enter_instance(entity: Entity, instance_id: String) -> bool:
	var instance_data = _instances.get(instance_id, {})
	if instance_data.is_empty():
		return false
	
	# Check capacity
	var max_capacity = instance_data.get("zone_data", {}).get("instance_capacity", 0)
	if max_capacity > 0:
		var current_count = instance_data.get("players", []).size()
		if current_count >= max_capacity:
			return false
	
	# Check entry requirements
	var zone = instance_data.get("zone_data")
	if zone and not zone.can_enter(entity):
		return false
	
	return true

## Auto-assign to party instance or create new
func get_or_create_party_instance(base_zone_id: String, party_leader_id: String, party_ids: Array[String]) -> String:
	# Check if party already has an instance
	var existing_instance = _find_party_instance(base_zone_id, party_ids)
	if existing_instance != "":
		return existing_instance
	
	# Create new instance for party
	var instance_id = create_instance(base_zone_id)
	if instance_id != "":
		var instance_data = _instances.get(instance_id, {})
		instance_data["party_id"] = party_leader_id
		instance_data["party_members"] = party_ids.duplicate()
	
	return instance_id

## Notify dungeon entry/exit
func notify_dungeon_enter(entity: Entity, zone_name: String) -> void:
	if entity.entity_type == Entity.EntityType.PLAYER:
		var notification_service = NotificationService
		if notification_service:
			notification_service.notify_dungeon_enter(entity.entity_id, zone_name)

func notify_dungeon_exit(entity: Entity, zone_name: String, completed: bool) -> void:
	if entity.entity_type == Entity.EntityType.PLAYER:
		var notification_service = NotificationService
		if notification_service:
			notification_service.notify_dungeon_exit(entity.entity_id, zone_name, completed)

func _find_party_instance(base_zone_id: String, party_ids: Array[String]) -> String:
	for instance_id in _instances:
		var instance_data = _instances[instance_id]
		if instance_data.get("base_zone_id") != base_zone_id:
			continue
		
		var members = instance_data.get("party_members", [])
		for party_id in party_ids:
			if members.has(party_id):
				return instance_id
	return ""
