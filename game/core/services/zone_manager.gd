## ZoneManager - Zone state and transition management
## Handles zone transitions (seamless & instanced), population, and zone boundaries
extends Node

const ZoneData = preload("res://core/schemas/zone_data.gd")
const QoSService = preload("res://core/autoload/qos_service.gd")
# Entity is not an autoload (class_name only). ZoneManager uses
# Entity.EntityType.X in entity classification, which requires
# Entity's class_name registered at parse time. Preload it here.
const Entity = preload("res://core/entities/entity.gd")
const DictStore = preload("res://adapters/persistence/dict_store.gd")
# SpatialFragmenter is a pure-function utility (class_name registered, no autoload).
# Preload the script resource rather than referencing the class_name to avoid
# any shadowing ambiguity and to keep the dependency explicit.
const SpatialFragmenterScript = preload("res://core/frame/geometry/spatial_fragmenter.gd")

# Spatial quantization: world units collapsed into a single address cell.
# A quantum of 500 means coordinates within the same 500-unit cube share
# the same quantized coordinate.
const SPATIAL_QUANTUM: float = 500.0

# Zone types
enum ZoneType {
	OPEN_WORLD,		 # Seamless, players always in same world
	INSTANCED,		 # Separate instance (dungeon, raid)
	SEAMLESS_INST # Instance but seamless (no loading screen)
}

const _kv_prefix := "zone:"

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
var _entity_zones: Dictionary = {}	# entity_id -> zone_id

# Seamless transition tracking
var _transition_zones: Dictionary = {}	# zone_id -> [transition_bounds]
var _seamless_enabled: bool = true

# --- Spatial Fragmenter Integration ---
# Cached SpatialFragmenter instance (pure utility, stateless)
var _spatial_fragmenter: SpatialFragmenterScript = null

# Zone spatial addresses (zone_id -> int spatial address)
var _zone_spatial_addresses: Dictionary = {}

signal zone_loaded(zone_data)
signal zone_unloaded(zone_id: String)
signal player_entered_zone(player, zone)
signal player_exited_zone(player, zone)
signal zone_population_changed(zone_id: String, count: int)

# Seamless transition signals
signal seamless_transition_started(entity, from_zone, to_zone)
signal seamless_transition_completed(entity, to_zone)
signal seamless_transition_cancelled(entity, reason)

# Instance signals
signal instance_created(instance_id: String, zone_data)
signal instance_destroyed(instance_id: String)
signal instance_joined(player, instance_id)
signal instance_left(player, instance_id)

func _ready() -> void:
	GameLog.info("ZoneManager: Ready")
	_init_spatial_fragmenter()
	_load_zone_state()

## Initialize SpatialFragmenter instance
func _init_spatial_fragmenter() -> void:
	if SpatialFragmenterScript:
		_spatial_fragmenter = SpatialFragmenterScript.new()
		GameLog.debug("ZoneManager: SpatialFragmenter initialized")
	else:
		GameLog.warn("ZoneManager: SpatialFragmenterScript not available; spatial features disabled")

## Compute spatial depth based on zone radius
## Larger zones get lower depth (coarser granularity), smaller zones get higher depth
func _compute_zone_depth(radius: float) -> int:
	if radius <= 0.0:
		return 12
	# Simple linear depth calculation: larger zones get coarser granularity
	var depth: int = 24 - int(radius / 100.0)
	return clamp(depth, 0, 24)

## Compute deterministic face code from zone_id hash (0-11 for icosahedral faces)
func _compute_zone_face(zone_id: String) -> int:
	var hash: int = 0
	for i in range(zone_id.length()):
		hash = (hash * 31) + zone_id.unicode_at(i)
	return abs(hash) % 12

## Generate spatial address for a zone based on its center and radius
func _compute_spatial_address(zone) -> int:
	if _spatial_fragmenter == null or zone == null:
		return 0
	var x: int = int(zone.zone_center.x / SPATIAL_QUANTUM)
	var y: int = int(zone.zone_center.y / SPATIAL_QUANTUM)
	var z: int = int(zone.zone_center.z / SPATIAL_QUANTUM)
	var depth: int = _compute_zone_depth(zone.zone_radius)
	# Use a single face (0) for all zones to ensure they share the same spatial tree
	# for neighbor detection and seamless transitions
	var face: int = 0
	return _spatial_fragmenter.make_address(x, y, z, depth, face)


## Get the spatial address for a zone by ID.
## Returns 0 if SpatialFragmenter is unavailable or the zone does not exist.
func get_zone_spatial_address(zone_id: String) -> int:
	if _spatial_fragmenter == null:
		return 0
	var zone = _zones.get(zone_id)
	if zone == null:
		return 0

	var cached: int = _zone_spatial_addresses.get(zone_id, 0)
	if cached != 0:
		return cached

	var address: int = _compute_spatial_address(zone)
	if address != 0:
		_zone_spatial_addresses[zone_id] = address
		return address
	return 0


## Load all zones from data
func load_zones() -> void:
	var data_service = DataService
	if not data_service:
		GameLog.warn("ZoneManager: DataService not available")
		return

	var zone_data_dict = data_service.get_all_zones()
	for zone_id in zone_data_dict:
		register_zone(zone_data_dict[zone_id])

	GameLog.info("ZoneManager: Loaded %d zones" % _zones.size())

	# Auto-register zone neighbors based on proximity
	auto_register_zone_neighbors()

## Register a zone
func register_zone(zone_data) -> bool:
	if zone_data == null:
		return false

	# Defense in depth: Check for duplicate zone ID
	if _zones.has(zone_data.id):
		GameLog.error("ZoneManager: Duplicate zone ID '%s' - cannot register" % zone_data.id)
		return false

	_zones[zone_data.id] = zone_data
	_players_in_zone[zone_data.id] = []
	_enemies_in_zone[zone_data.id] = []

	# Generate spatial address for the zone (graceful degradation if SpatialFragmenter unavailable)
	var spatial_addr: int = _compute_spatial_address(zone_data)
	if spatial_addr != 0:
		_zone_spatial_addresses[zone_data.id] = spatial_addr
		if _spatial_fragmenter:
			GameLog.debug("ZoneManager: Generated spatial address for zone %s (key: %s)" % [zone_data.id, _spatial_fragmenter.generate_key(spatial_addr)])

	_persist_zone(zone_data.id)

	zone_loaded.emit(zone_data)
	GameLog.debug("ZoneManager: Registered zone %s" % zone_data.id)
	return true

## Auto-register zone neighbors based on proximity
func auto_register_zone_neighbors(max_distance: float = 1500.0) -> void:
	var zones_array: Array = _zones.values()
	var registered_count: int = 0

	for i in range(zones_array.size()):
		var zone1 = zones_array[i]
		for j in range(i + 1, zones_array.size()):
			var zone2 = zones_array[j]

			# Calculate distance between zone centers
			var distance: float = zone1.zone_center.distance_to(zone2.zone_center)
			var combined_radius: float = zone1.zone_radius + zone2.zone_radius

			# Spatial proximity check using SpatialFragmenter if available
			var is_spatial_neighbor = false
			if _spatial_fragmenter != null:
				var addr1: int = get_zone_spatial_address(zone1.id)
				var addr2: int = get_zone_spatial_address(zone2.id)
				if addr1 != 0 and addr2 != 0:
					# Zones are spatially adjacent if they share a common ancestor
					# at a depth that indicates proximity (lower depth = larger region)
					var ancestor: int = _spatial_fragmenter.find_common_ancestor([addr1, addr2])
					if ancestor != 0:
						var ancestor_depth: int = _spatial_fragmenter.get_depth(ancestor)
						is_spatial_neighbor = ancestor_depth <= 16

			# If zones overlap or are close enough, register as neighbors
			if distance <= max_distance or is_spatial_neighbor:
				register_zone_neighbors(zone1.id, zone2.id)
				registered_count += 1

	GameLog.info("ZoneManager: Auto-registered %d zone neighbor connections" % registered_count)

func get_all_zones() -> Array:
	return _zones.values()

## Get zone by ID
func get_zone(zone_id: String) -> ZoneData:
	return _zones.get(zone_id)

## Get players in a zone
func get_players_in_zone(zone_id: String) -> Array:
	return _players_in_zone.get(zone_id, [])

## Get enemies in a zone
func get_enemies_in_zone(zone_id: String) -> Array:
	return _enemies_in_zone.get(zone_id, [])

## Get zone population
func get_zone_population(zone_id: String) -> int:
	return _players_in_zone.get(zone_id, []).size()

## Get current zone for an entity
func get_entity_zone(entity) -> ZoneData:
	var zone_id = _entity_zones.get(entity.entity_id, "")
	if zone_id == "":
		return null
	return _zones.get(zone_id)

## Get current zone ID for an entity
func get_entity_zone_id(entity) -> String:
	return _entity_zones.get(entity.entity_id, "")

## Get spatial fragment metadata for a zone
func get_zone_spatial_fragment(zone_id: String) -> Dictionary:
	if _spatial_fragmenter == null:
		return {}
	var address: int = get_zone_spatial_address(zone_id)
	if address == 0:
		return {}
	var zone = _zones.get(zone_id)
	if zone == null:
		return {}
	var key: String = _spatial_fragmenter.generate_key(address)
	var bbox: Dictionary = _spatial_fragmenter.get_bounding_box(address)
	return {
		"zone_id": zone_id,
		"address": address,
		"key": key,
		"bbox": bbox,
		"depth": _spatial_fragmenter.get_depth(address),
		"face": _spatial_fragmenter.get_face(address)
	}

## Handle entity entering a zone
func entity_enter_zone(entity, zone) -> bool:
	if entity == null or zone == null:
		return false

	# Check entry requirements
	if not zone.can_enter(entity):
		GameLog.debug("ZoneManager: %s cannot enter zone %s" % [entity.display_name, zone.id])
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

	EventHub.entity_entered_zone.emit(entity, zone)
	GameLog.debug("ZoneManager: %s entered zone %s" % [entity.display_name, zone.id])
	return true

## Handle entity exiting a zone
func entity_exit_zone(entity) -> bool:
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
		EventHub.entity_exited_zone.emit(entity, zone)

	GameLog.debug("ZoneManager: %s exited zone %s" % [entity.display_name, zone_id])
	return true

## Check if entity can enter a zone
func can_enter_zone(entity, zone_id: String) -> bool:
	var zone = _zones.get(zone_id)
	if zone == null:
		return false
	return zone.can_enter(entity)

## Check if PvP is allowed between two entities in current zone
func can_pvp(entity1, entity2) -> bool:
	var zone_id = _entity_zones.get(entity1.entity_id, "")
	if zone_id == "":
		return false

	var zone = _zones.get(zone_id)
	if zone == null:
		return false

	return zone.can_pvp(entity1, entity2)

## Create an instance (dungeon, etc.)
func create_instance(base_zone_id: String, owner_id: String = "") -> String:
	# QoS: Rate limit instance creation
	if owner_id != "" and not QoSService.rate_limit(owner_id, "instance"):
		GameLog.debug("ZoneManager: Rate limited instance creation for %s" % owner_id)
		return ""

	var base_zone = _zones.get(base_zone_id)
	if base_zone == null:
		GameLog.warn("ZoneManager: Cannot create instance, base zone %s not found" % base_zone_id)
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
	_persist_instances()

	instance_created.emit(instance_id, instance_data.zone_data)
	GameLog.info("ZoneManager: Created instance %s from %s" % [instance_id, base_zone_id])
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
	_persist_instances()

	instance_destroyed.emit(instance_id)
	GameLog.info("ZoneManager: Destroyed instance %s" % instance_id)
	return true

## Get instance data
func get_instance(instance_id: String) -> Dictionary:
	return _instances.get(instance_id, {})

## Add entity to instance
func add_to_instance(entity, instance_id: String) -> bool:
	if not _instances.has(instance_id):
		return false

	var instance_data = _instances[instance_id]
	instance_data.players.append(entity)

	# Switch entity to instance zone
	return entity_enter_zone(entity, instance_data.zone_data)

## Get nearby zones (for gateway system)
func get_nearby_zones(from_zone_id: String, max_distance: float = 1000.0) -> Array:
	var results: Array = []
	var from_zone = _zones.get(from_zone_id)
	if from_zone == null:
		return results

	for zone_id in _zones:
		var zone = _zones[zone_id]
		if zone_id == from_zone_id or zone.is_instanced:
			continue

		var distance: float = from_zone.zone_center.distance_to(zone.zone_center)
		if distance <= max_distance:
			results.append(zone)

	return results

## Get zones by PvP mode
func get_zones_by_pvp_mode(pvp_mode) -> Array:
	var results: Array = []
	for zone in _zones.values():
		if zone.pvp_mode == pvp_mode:
			results.append(zone)
	return results

## Get zones for level range
func get_zones_for_level(level: int) -> Array:
	var results: Array = []
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
	GameLog.info("ZoneManager: Seamless transitions %s" % ("enabled" if enabled else "disabled"))

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

	GameLog.debug("ZoneManager: Registered neighbors: %s <-> %s" % [zone1_id, zone2_id])

## Get neighboring zones
func get_neighboring_zones(zone_id: String) -> Array:
	var results: Array = []
	var neighbor_ids = _zone_neighbors.get(zone_id, [])
	for neighbor_id in neighbor_ids:
		var zone = _zones.get(neighbor_id)
		if zone:
			results.append(zone)
	return results

## Get all connected zones (BFS traversal for alerts)
func get_all_connected_zones(zone_id: String, max_depth: int = 100) -> Array:
	var visited: Dictionary = {}
	var results: Array = []
	var queue: Array = [zone_id]
	var depth: int = 0

	while not queue.is_empty() and depth < max_depth:
		var level_size := queue.size()
		for _i in range(level_size):
			var current_id: String = queue.pop_at(0)
			if visited.has(current_id):
				continue
			visited[current_id] = true

			var zone = _zones.get(current_id)
			if zone:
				results.append(zone)

			# Add neighbors to queue
			var neighbor_ids: Array = _zone_neighbors.get(current_id, [])
			for neighbor_id in neighbor_ids:
				if not visited.has(neighbor_id):
					queue.append(neighbor_id)
		depth += 1

	GameLog.debug("ZoneManager: Found %d connected zones from %s (depth: %d)" % [results.size(), zone_id, depth])
	return results

## Get all player IDs in connected zones (for global alerts)
func get_all_players_in_connected_zones(zone_id: String) -> Array[String]:
	var connected_zones := get_all_connected_zones(zone_id)
	var player_ids: Array[String] = []

	for zone in connected_zones:
		var players: Array = _players_in_zone.get(zone.id, [])
		for player in players:
			if "entity_id" in player:
				player_ids.append(player.entity_id)

	return player_ids

## Check if seamless transition should occur
func check_seamless_transition(entity) -> ZoneData:
	if not _seamless_enabled:
		return null

	var current_zone_id = _entity_zones.get(entity.entity_id, "")
	if current_zone_id == "":
		return null

	var current_zone = _zones.get(current_zone_id)
	if current_zone == null:
		return null

	# Check if entity crossed zone boundary using registered neighbors
	var neighbors = get_neighboring_zones(current_zone_id)
	for neighbor in neighbors:
		if neighbor.contains_position(entity.global_position):
			return neighbor

	# Spatial fragmenter-based transition detection
	# If SpatialFragmenter is available, check if the entity's position maps
	# to a spatial fragment that belongs to another zone (even if the neighbor
	# relationship was not yet registered)
	if _spatial_fragmenter != null:
		var current_addr: int = get_zone_spatial_address(current_zone_id)
		if current_addr != 0:
			var pos := entity.global_position
			var current_face: int = _spatial_fragmenter.get_face(current_addr)
			var current_depth: int = _spatial_fragmenter.get_depth(current_addr)
			# Use a deeper depth for the entity's position to detect movement
			# within the zone's spatial region
			var entity_depth: int = mini(current_depth + 4, _spatial_fragmenter.MAX_DEPTH)
			var entity_addr: int = _spatial_fragmenter.make_address(
				int(pos.x / SPATIAL_QUANTUM),
				int(pos.y / SPATIAL_QUANTUM),
				int(pos.z / SPATIAL_QUANTUM),
				entity_depth,
				current_face
			)
			if entity_addr != current_addr:
				# Entity has moved to a different spatial fragment.
				# Check if any other zone's address is an ancestor of this address.
				for zone_id in _zones:
					if zone_id == current_zone_id:
						continue
					var zone_addr: int = get_zone_spatial_address(zone_id)
					if zone_addr != 0 and _spatial_fragmenter.is_ancestor(zone_addr, entity_addr):
						var zone = _zones.get(zone_id)
						if zone and zone.contains_position(pos):
							return zone

	return null

## Perform seamless transition
func perform_seamless_transition(entity, to_zone) -> bool:
	if to_zone == null:
		return false

	var from_zone = _zones.get(_entity_zones.get(entity.entity_id, ""))
	if from_zone == null:
		return false

	# SECURITY: Cancel any active locks on teleport
	if entity.entity_id and PlayerLockService:
		PlayerLockService.cancel_on_teleport(entity.entity_id)
		# Also cancel follow
		if FollowService:
			FollowService.cancel_all_for_player(entity.entity_id)

	# Emit start signal
	seamless_transition_started.emit(entity, from_zone, to_zone)

	# Exit current zone
	_entity_zones.erase(entity.entity_id)
	_players_in_zone[from_zone.id].erase(entity)
	_players_in_zone[from_zone.id].remove_at(_players_in_zone[from_zone.id].find(entity))
	player_exited_zone.emit(entity, from_zone)
	EventHub.entity_exited_zone.emit(entity, from_zone)

	# Enter new zone
	_entity_zones[entity.entity_id] = to_zone.id
	if not _players_in_zone.has(to_zone.id):
		_players_in_zone[to_zone.id] = []
	_players_in_zone[to_zone.id].append(entity)
	player_entered_zone.emit(entity, to_zone)
	EventHub.entity_entered_zone.emit(entity, to_zone)

	# Send notification
	_notify_zone_change(entity, from_zone, to_zone)

	# Emit completion
	seamless_transition_completed.emit(entity, to_zone)
	GameLog.debug("ZoneManager: %s seamless transitioned %s -> %s" % [entity.display_name, from_zone.id, to_zone.id])
	return true

func _notify_zone_change(entity, from_zone, to_zone) -> void:
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
func can_enter_instance(entity, instance_id: String) -> bool:
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
func notify_dungeon_enter(entity, zone_name: String) -> void:
	if entity.entity_type == Entity.EntityType.PLAYER:
		var notification_service = NotificationService
		if notification_service:
			notification_service.notify_dungeon_enter(entity.entity_id, zone_name)

func notify_dungeon_exit(entity, zone_name: String, completed: bool) -> void:
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

func _load_zone_state() -> void:
	_load_zones()
	_load_instances()

func _load_zones() -> void:
	var store = DictStore.new()
	var keys = store.all_keys()
	for key in keys:
		if key.begins_with(_kv_prefix + "def:"):
			var zone_id = key.substr(_kv_prefix.length() + 4)
			var data = store.get_kv(key)
			if not data.is_empty():
				var zone_data := ZoneData.new()
				zone_data.id = data.get("id", "")
				zone_data.display_name = data.get("display_name", "Unknown Zone")
				zone_data.description = data.get("description", "")
				var pvp_key = data.get("pvp_mode", "SAFE")
				for pvp_name in ZoneData.PvPZoneMode.keys():
					if pvp_name == pvp_key:
						zone_data.pvp_mode = ZoneData.PvPZoneMode[pvp_name]
						break
				zone_data.level_requirement = data.get("level_requirement", 1)
				zone_data.max_level = data.get("max_level", 999)
				zone_data.allowed_factions = data.get("allowed_factions", [])
				zone_data.blocked_sactions = data.get("blocked_sactions", [])
				zone_data.blocked_species = data.get("blocked_species", [])
				zone_data.respawn_at_bind = data.get("respawn_at_bind", true)
				zone_data.respawn_timer = data.get("respawn_timer", 10.0)
				zone_data.zone_radius = data.get("zone_radius", 500.0)
				zone_data.is_instanced = data.get("is_instanced", false)
				zone_data.instance_capacity = data.get("instance_capacity", 0)
				var center_data = data.get("zone_center", {"x": 0, "y": 0, "z": 0})
				zone_data.zone_center = Vector3(center_data.get("x", 0), center_data.get("y", 0), center_data.get("z", 0))
				# Restore spatial address from persisted data if available
				if data.has("spatial_address") and data["spatial_address"] != 0:
					_zone_spatial_addresses[zone_id] = data["spatial_address"]
				_zones[zone_id] = zone_data
				_players_in_zone[zone_id] = []
				_enemies_in_zone[zone_id] = []

func _persist_zone(zone_id: String) -> void:
	if not _zones.has(zone_id):
		return
	var zone_data = _zones[zone_id]
	var center = zone_data.zone_center
	var data := {
		"id": zone_data.id,
		"display_name": zone_data.display_name,
		"description": zone_data.description,
		"pvp_mode": ZoneData.PvPZoneMode.keys()[zone_data.pvp_mode],
		"level_requirement": zone_data.level_requirement,
		"max_level": zone_data.max_level,
		"allowed_factions": zone_data.allowed_factions,
		"blocked_sactions": zone_data.blocked_sactions,
		"blocked_species": zone_data.blocked_species,
		"respawn_at_bind": zone_data.respawn_at_bind,
		"respawn_timer": zone_data.respawn_timer,
		"zone_center": {"x": center.x, "y": center.y, "z": center.z},
		"zone_radius": zone_data.zone_radius,
		"is_instanced": zone_data.is_instanced,
		"instance_capacity": zone_data.instance_capacity
	}
	# Persist spatial address if available
	var spatial_addr: int = _zone_spatial_addresses.get(zone_id, 0)
	if spatial_addr != 0:
		data["spatial_address"] = spatial_addr
	var store = DictStore.new()
	store.set_kv(_kv_prefix + "def:" + zone_id, data)

func _load_instances() -> void:
	var store = DictStore.new()
	var keys = store.all_keys()
	_instances.clear()
	for key in keys:
		if key.begins_with(_kv_prefix + "instance:"):
			var instance_id = key.substr(_kv_prefix.length() + 9)
			var data = store.get_kv(key)
			if not data.is_empty():
				_instances[instance_id] = data
	var max_id := 0
	for instance_id in _instances:
		var suffix = instance_id.substr(9)
		if suffix.is_valid_int():
			var num = suffix.to_int()
			if num >= max_id:
				max_id = num + 1
	_next_instance_id = max_id

func _persist_instances() -> void:
	var store = DictStore.new()
	if _instances.is_empty():
		store.erase(_kv_prefix + "instances")
	else:
		var serializable := {}
		for instance_id in _instances:
			var instance_data = _instances[instance_id]
			var result: Dictionary = instance_data.duplicate(true)
			var zone_data = result.get("zone_data")
			if zone_data is ZoneData:
				result["zone_data"] = _serialize_zone_data(zone_data)
			serializable[instance_id] = result
		store.set_kv(_kv_prefix + "instances", serializable)

func _serialize_zone_data(zone_data: ZoneData) -> Dictionary:
	var center = zone_data.zone_center
	return {
		"id": zone_data.id,
		"display_name": zone_data.display_name,
		"description": zone_data.description,
		"pvp_mode": ZoneData.PvPZoneMode.keys()[zone_data.pvp_mode],
		"level_requirement": zone_data.level_requirement,
		"max_level": zone_data.max_level,
		"allowed_factions": zone_data.allowed_factions,
		"blocked_sactions": zone_data.blocked_sactions,
		"blocked_species": zone_data.blocked_species,
		"respawn_at_bind": zone_data.respawn_at_bind,
		"respawn_timer": zone_data.respawn_timer,
		"zone_center": {"x": center.x, "y": center.y, "z": center.z},
		"zone_radius": zone_data.zone_radius,
		"is_instanced": zone_data.is_instanced,
		"instance_capacity": zone_data.instance_capacity
	}

func _deserialize_zone_data(data: Dictionary) -> ZoneData:
	var zone_data := ZoneData.new()
	zone_data.id = data.get("id", "")
	zone_data.display_name = data.get("display_name", "Unknown Zone")
	zone_data.description = data.get("description", "")
	var pvp_key = data.get("pvp_mode", "SAFE")
	for pvp_name in ZoneData.PvPZoneMode.keys():
		if pvp_name == pvp_key:
			zone_data.pvp_mode = ZoneData.PvPZoneMode[pvp_name]
			break
	zone_data.level_requirement = data.get("level_requirement", 1)
	zone_data.max_level = data.get("max_level", 999)
	zone_data.allowed_factions = data.get("allowed_factions", [])
	zone_data.blocked_sactions = data.get("blocked_sactions", [])
	zone_data.blocked_species = data.get("blocked_species", [])
	zone_data.respawn_at_bind = data.get("respawn_at_bind", true)
	zone_data.respawn_timer = data.get("respawn_timer", 10.0)
	zone_data.zone_radius = data.get("zone_radius", 500.0)
	zone_data.is_instanced = data.get("is_instanced", false)
	zone_data.instance_capacity = data.get("instance_capacity", 0)
	var center_data = data.get("zone_center", {"x": 0, "y": 0, "z": 0})
	zone_data.zone_center = Vector3(center_data.get("x", 0), center_data.get("y", 0), center_data.get("z", 0))
	return zone_data
