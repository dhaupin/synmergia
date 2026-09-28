## ZoneManager - Zone state and transition management
## Handles zone transitions (seamless & instanced), population, and zone boundaries
extends Node
# QoSService uses static shim methods (AGENTS.md allowlist); the const is required.
const QoSService = preload("res://core/autoload/qos_service.gd")

const ZoneData = preload("res://core/schemas/zone_data.gd")
# Entity is not an autoload (class_name only). ZoneManager uses
# Entity.EntityType.X in entity classification, which requires
# Entity's class_name registered at parse time. Preload it here.
const Entity = preload("res://core/entities/entity.gd")
const DictStore = preload("res://adapters/persistence/dict_store.gd")
# SpatialFragmenter is a pure-function utility (class_name registered, no autoload).
# Preload the script resource rather than referencing the class_name to avoid
# any shadowing ambiguity and to keep the dependency explicit.
const SpatialFragmenterScript = preload("res://core/frame/geometry/spatial_fragmenter.gd")
# NSC-9 bridge: connects NSC-9 spatial codes -> SpatialFragmenter -> T3 pipeline.
const Nsc9BridgeScript = preload("res://core/frame/geometry/nsc9_bridge.gd")
# NSC-9 math utilities (pure function for axis/encoding).
const Nsc9Script = preload("res://core/frame/math/nsc9.gd")
# Fragmenter (data sharding via Knuth multiplicative hash).
const FragmenterScript = preload("res://core/frame/geometry/fragmenter.gd")
# T3 state tree for persistence.
const T3Script = preload("res://core/frame/kv/t3.gd")
const DefinitionTreeScript = preload("res://core/frame/kv/definition_tree.gd")

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

# Anti-storm guards: zone seams overlap, so without these the seamless
# detector flip-flops entities across boundaries every physics frame and
# re-probes denied entries thousands of times per run (log spam + errors).
const ENTRY_RETRY_MSEC := 2000
var _entry_denied_at: Dictionary = {}	# entity_id -> last denial ticks

# Seamless transition tracking
var _transition_zones: Dictionary = {}	# zone_id -> [transition_bounds]
var _seamless_enabled: bool = true

# --- Spatial Fragmenter Integration ---
# Cached SpatialFragmenter instance (pure utility, stateless)
var _spatial_fragmenter: SpatialFragmenterScript = null

# Zone spatial addresses (zone_id -> int spatial address)
var _zone_spatial_addresses: Dictionary = {}

# Fragmenter (data sharding via Knuth multiplicative hash)
var _fragmenter: FragmenterScript = null

# NSC-9 bridge instance (pure utility, stateless)
var _nsc9_bridge: Nsc9BridgeScript = null

var _zone_nsc9_codes: Dictionary = {}
var _zone_shards: Dictionary = {}
var _t3: Variant = null
var _definition_tree: Variant = null

signal zone_loaded(zone_data)
signal zone_unloaded(zone_id: String)
signal player_entered_zone(player, zone)
signal player_exited_zone(player, zone)
signal zone_population_changed(zone_id: String, count: int)

# Entity zone entry/exit signals (for all entity types)
signal entity_entered_zone(entity, zone)
signal entity_exited_zone(entity, zone)

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

## Physics process: check all entities for zone transitions
func _physics_process(delta: float) -> void:
	if not _seamless_enabled:
		return
	process_seamless_transitions()
	_detect_new_entity_zone_entries()

## Initialize SpatialFragmenter, Fragmenter, and NSC-9 bridge instances.
func _init_spatial_fragmenter() -> void:
	if SpatialFragmenterScript:
		_spatial_fragmenter = SpatialFragmenterScript.new()
		GameLog.debug("ZoneManager: SpatialFragmenter initialized")
	else:
		GameLog.warn("ZoneManager: SpatialFragmenterScript not available; spatial features disabled")

	if FragmenterScript:
		_fragmenter = FragmenterScript.new()
		GameLog.debug("ZoneManager: Fragmenter initialized")
	else:
		GameLog.warn("ZoneManager: FragmenterScript not available; state fragmenting disabled")

	if Nsc9BridgeScript:
		_nsc9_bridge = Nsc9BridgeScript.new()
		GameLog.debug("ZoneManager: NSC-9 bridge initialized")
	else:
		GameLog.warn("ZoneManager: Nsc9BridgeScript not available; NSC-9 pipeline disabled")

func _get_t3() -> Variant:
	if _t3 != null: return _t3
	if T3Script: _t3 = T3Script.new()
	return _t3

## Lazy DefinitionTree (frame definition tree, arch §9) for world-config mirroring.
func _get_definition_tree() -> Variant:
	if _definition_tree != null: return _definition_tree
	if DefinitionTreeScript: _definition_tree = DefinitionTreeScript.new()
	return _definition_tree

## Public accessor for SpatialFragmenter (for cross-service spatial queries)
func get_spatial_fragmenter():
	return _spatial_fragmenter

## Public accessor for NSC-9 bridge
func get_nsc9_bridge():
	return _nsc9_bridge

## Shard zone world state using lattice keys for distributed storage.
## Returns Array[Dictionary] with shard, data, size, checksum, and lattice_key.
func _shard_zone_world(zone_id: String, world_state: Dictionary) -> Array[Dictionary]:
	if _fragmenter == null:
		return []
	var sequence: int = zone_id.hash()
	var keys: Array[String] = _fragmenter.derive_lattice_keys(sequence, 5)
	var fragments: Array[Dictionary] = _fragmenter.fragment(world_state, 5)
	for i in range(fragments.size()):
		fragments[i]["lattice_key"] = keys[i] if i < keys.size() else ""
	return fragments

## Restore zone world state from fragments.
## Returns the reconstructed world state dictionary.
func _restore_zone_world(zone_id: String, fragments: Array[Dictionary]) -> Dictionary:
	if _fragmenter == null:
		return {}
	var welded: String = _fragmenter.weld(fragments)
	if welded == "":
		return {}
	var parsed: Variant = JSON.parse_string(welded)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

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

## Compute a deterministic NSC-9 code for a zone.
func _compute_nsc9_code(zone_id: String, zone_center: Vector3) -> int:
	if _nsc9_bridge == null:
		return -1
	if zone_center == Vector3.ZERO:
		return -1

	# Facility: deterministic from zone_id hash (0-999)
	var facility: int = abs(hash(zone_id)) % 1000

	# Axis: nearest icosahedral vertex from zone center
	var lat: float = rad_to_deg(asin(clampf(zone_center.normalized().y, -1.0, 1.0)))
	var lon: float = rad_to_deg(atan2(zone_center.normalized().z, zone_center.normalized().x))
	var vertex: int = Nsc9Script.nearest_vertex(lat, lon)
	var axis: int = Nsc9Script.spatial_axis(vertex)

	# Sequence: deterministic from zone_id hash (0-16M)
	var sequence: int = abs(hash(zone_id + ":nsc9")) % 1_000_000

	return Nsc9Script.encode_int(facility, axis, sequence)

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

	var zone_data_list: Array = data_service.get_all_zones()
	for zone_data in zone_data_list:
		register_zone(zone_data)

	GameLog.info("ZoneManager: Loaded %d zones" % _zones.size())

	# Mirror zone definitions into the frame definition tree (arch §9:
	# definition tree holds world config -- zones, npcs, loot tables, ...)
	var def_tree = _get_definition_tree()
	if def_tree:
		var mirrored := 0
		for zone_data in zone_data_list:
			if zone_data == null or zone_data.id == "":
				continue
			var def_data := {
				"display_name": zone_data.display_name,
				"pvp_mode": str(zone_data.pvp_mode),
				"level_requirement": zone_data.level_requirement,
				"zone_radius": zone_data.zone_radius,
			}
			def_tree.insert_def("definitions/zones/%s" % zone_data.id, "zone", zone_data.id, def_data)
			mirrored += 1
		GameLog.info("ZoneManager: Mirrored %d zone definitions into definition tree" % mirrored)

	# Auto-register zone neighbors based on proximity
	auto_register_zone_neighbors()


## Definition-tree lookup for a zone (mirror of the ZoneData world config).
func get_zone_def(zone_id: String) -> Dictionary:
	var def_tree = _get_definition_tree()
	if def_tree == null:
		return {}
	return def_tree.get_def("definitions/zones/%s" % zone_id)

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

	# Generate NSC-9 code for the zone (for T3 pipeline)
	var nsc9_code: int = _compute_nsc9_code(zone_data.id, zone_data.zone_center)
	_zone_nsc9_codes[zone_data.id] = nsc9_code
	if nsc9_code != -1:
		GameLog.debug("ZoneManager: Generated NSC-9 code for zone %s (0x%08x)" % [zone_data.id, nsc9_code])

	# Shard zone world for distributed storage
	var world_state := {"id": zone_data.id, "display_name": zone_data.display_name, "zone_center": zone_data.zone_center, "zone_radius": zone_data.zone_radius, "is_instanced": zone_data.is_instanced, "level_requirement": zone_data.level_requirement}
	_zone_shards[zone_data.id] = _shard_zone_world(zone_data.id, world_state)

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

## Auto-register zone neighbors based on spatial proximity
## Uses SpatialFragmenter as primary mechanism; falls back to Euclidean distance if unavailable.
func auto_register_zone_neighbors(max_distance: float = -1.0) -> void:
	var zones_array: Array = _zones.values()
	var registered_count: int = 0

	for i in range(zones_array.size()):
		var zone1 = zones_array[i]
		for j in range(i + 1, zones_array.size()):
			var zone2 = zones_array[j]

			var should_register: bool = false

			# Primary: SpatialFragmenter proximity check
			if _spatial_fragmenter != null:
				var addr1: int = get_zone_spatial_address(zone1.id)
				var addr2: int = get_zone_spatial_address(zone2.id)
				if addr1 != 0 and addr2 != 0:
					# Zones are neighbors if they share a common ancestor at a depth
					# indicating proximity. Lower depth = larger region = more distant.
					# We use ancestor depth threshold derived from zone radii.
					var ancestor: int = _spatial_fragmenter.find_common_ancestor([addr1, addr2])
					if ancestor != 0:
						var ancestor_depth: int = _spatial_fragmenter.get_depth(ancestor)
						# Threshold: zones with larger radii get lower depth (coarser).
						# Combine both zones' computed depths for a fair threshold.
						var depth1: int = _compute_zone_depth(zone1.zone_radius)
						var depth2: int = _compute_zone_depth(zone2.zone_radius)
						var threshold_depth: int = maxi(depth1, depth2)
						should_register = ancestor_depth <= threshold_depth

			# Fallback: Euclidean distance (only if SpatialFragmenter unavailable or inconclusive)
			if not should_register:
				var fallback_distance: float = max_distance
				if fallback_distance < 0.0:
					# Derive from zone radii: combined radius + buffer
					fallback_distance = zone1.zone_radius + zone2.zone_radius + 200.0
				var distance: float = zone1.zone_center.distance_to(zone2.zone_center)
				should_register = distance <= fallback_distance

			if should_register:
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

## Get the NSC-9 code for a zone by ID.
## Returns -1 if the NSC-9 bridge is unavailable or the zone does not exist.
func get_zone_nsc9_code(zone_id: String) -> int:
	if _nsc9_bridge == null:
		return -1
	var zone = _zones.get(zone_id)
	if zone == null:
		return -1
	# Check cache first
	var cached_code: int = _zone_nsc9_codes.get(zone_id)
	if cached_code != -1:
		return cached_code
	return _compute_nsc9_code(zone_id, zone.zone_center)

## Get the T3 path for a zone's NSC-9 spatial fragment.
## Returns "" if the NSC-9 bridge is unavailable or the code is non-spatial.
func get_zone_nsc9_t3_path(zone_id: String) -> String:
	if _nsc9_bridge == null:
		return ""
	var code: int = get_zone_nsc9_code(zone_id)
	if code == -1:
		return ""
	return _nsc9_bridge.nsc9_to_t3_path(code)

## Get the cached shard fragments for a zone.
## Returns empty array if not sharded or zone does not exist.
func get_zone_shards(zone_id: String) -> Array[Dictionary]:
	return _zone_shards.get(zone_id, [])

## Handle entity entering a zone
func entity_enter_zone(entity, zone) -> bool:
	if entity == null or zone == null:
		return false

	# Denial cooldown: untracked entities are re-probed every physics
	# frame by the seamless detector, so a persistent denial (level gate,
	# blocked faction/species) would spam this path thousands of times
	# per run. Back off per entity before re-testing the gate.
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - int(_entry_denied_at.get(entity.entity_id, -1000000)) < ENTRY_RETRY_MSEC:
		return false

	# Check entry requirements
	if not zone.can_enter(entity):
		_entry_denied_at[entity.entity_id] = now_ms
		GameLog.debug("ZoneManager: %s cannot enter zone %s" % [entity.display_name, zone.id])
		return false
	_entry_denied_at.erase(entity.entity_id)

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
	entity_entered_zone.emit(entity, zone)
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
		entity_exited_zone.emit(entity, zone)

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

## Add entity to instance. Capacity gate (S9): instance_capacity 0 =
## unlimited; otherwise the join is refused when full. One chokepoint
## so every caller (InstanceService lobby joins, direct party joins)
## gets the same enforcement.
func add_to_instance(entity, instance_id: String) -> bool:
	if not _instances.has(instance_id):
		return false

	var instance_data = _instances[instance_id]
	var max_capacity: int = 0
	var zdata = instance_data.get("zone_data")
	if zdata != null and "instance_capacity" in zdata:
		max_capacity = int(zdata.instance_capacity)
	if max_capacity > 0 and instance_data.get("players", []).size() >= max_capacity:
		GameLog.debug("ZoneManager: Instance %s is full (%d/%d)" % \
			[instance_id, instance_data.get("players", []).size(), max_capacity])
		return false

	instance_data.players.append(entity)

	# Switch entity to instance zone
	return entity_enter_zone(entity, instance_data.zone_data)

## Get nearby zones using spatial proximity (SpatialFragmenter primary, Euclidean fallback)
func get_nearby_zones(from_zone_id: String, max_distance: float = -1.0) -> Array:
	var results: Array = []
	var from_zone = _zones.get(from_zone_id)
	if from_zone == null:
		return results

	# Primary: Use SpatialFragmenter to find spatially adjacent zones
	if _spatial_fragmenter != null:
		var from_addr: int = get_zone_spatial_address(from_zone_id)
		if from_addr != 0:
			var from_depth: int = _spatial_fragmenter.get_depth(from_addr)
			# Use the zone's computed depth as the search threshold
			# Subdivide one level deeper to find immediate neighbors
			var search_depth: int = mini(from_depth + 2, _spatial_fragmenter.MAX_DEPTH)
			
			# Get bounding box of the from_zone's spatial address
			var from_bbox: Dictionary = _spatial_fragmenter.get_bounding_box(from_addr)
			
			for zone_id in _zones:
				var zone = _zones[zone_id]
				if zone_id == from_zone_id or zone.is_instanced:
					continue
				
				var zone_addr: int = get_zone_spatial_address(zone_id)
				if zone_addr == 0:
					continue
				
				# Check if zones share a common ancestor at search_depth or lower
				var ancestor: int = _spatial_fragmenter.find_common_ancestor([from_addr, zone_addr])
				if ancestor != 0:
					var ancestor_depth: int = _spatial_fragmenter.get_depth(ancestor)
					if ancestor_depth <= search_depth:
						results.append(zone)
						continue
				
				# Also check bounding box overlap for zones at similar depth
				var zone_bbox: Dictionary = _spatial_fragmenter.get_bounding_box(zone_addr)
				if _bboxes_overlap(from_bbox, zone_bbox):
					results.append(zone)
					continue

	# Fallback: Euclidean distance (only if SpatialFragmenter unavailable or no results)
	if results.is_empty() or _spatial_fragmenter == null:
		var fallback_distance: float = max_distance
		if fallback_distance < 0.0:
			fallback_distance = from_zone.zone_radius + 500.0  # Derived default
		
		for zone_id in _zones:
			var zone = _zones[zone_id]
			if zone_id == from_zone_id or zone.is_instanced:
				continue
			
			# Avoid duplicates from spatial search
			if results.has(zone):
				continue
				
			var distance: float = from_zone.zone_center.distance_to(zone.zone_center)
			if distance <= fallback_distance:
				results.append(zone)

	return results


## Helper: Check if two bounding boxes overlap
func _bboxes_overlap(bbox1: Dictionary, bbox2: Dictionary) -> bool:
	if bbox1.is_empty() or bbox2.is_empty():
		return false
	return (bbox1.min_x <= bbox2.max_x and bbox1.max_x >= bbox2.min_x and
		bbox1.min_y <= bbox2.max_y and bbox1.max_y >= bbox2.min_y and
		bbox1.min_z <= bbox2.max_z and bbox1.max_z >= bbox2.min_z)

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

	# Overlap resolution (anti flip-flop storm): shipped zone regions
	# overlap heavily (concentric discs around the origin), so several
	# zones claim the same position and the losers used to re-claim the
	# entity every physics frame -- thousands of exit/enter transitions
	# and entry denials per run.
	#
	# Deterministic rule: the CURRENT zone holds its members while they
	# remain inside it (boot/portal assignments stick; level-gated inner
	# regions are entered explicitly, never auto-claimed). When the
	# entity exits the current zone, the strongest other claimant wins:
	# higher level_requirement first (dangerous inner regions override),
	# then smaller zone_radius (more specific region). No claimant means
	# the entity leaves the tracked set until the entry detector finds it.
	# Out-of-tree entities (scene teardown race) have no valid position:
	# treat them as fully outside so the tracker drops them.
	if entity is Node3D and not entity.is_inside_tree():
		return null
	var entity_pos: Vector3 = entity.global_position
	if current_zone.contains_position(entity_pos):
		return null

	var best_zone: ZoneData = null
	for zone in _zones.values():
		if zone.is_instanced or zone.id == current_zone_id:
			continue
		if not zone.contains_position(entity_pos):
			continue
		if best_zone == null or _zone_claims_better(zone, best_zone):
			best_zone = zone
	if best_zone != null and not best_zone.can_enter(entity):
		return null  # gate denied: stay untracked rather than flip-flopping
	return best_zone

	# Spatial fragmenter-based transition detection
	# If SpatialFragmenter is available, check if the entity's position maps
	# to a spatial fragment that belongs to another zone (even if the neighbor
	# relationship was not yet registered)
	if _spatial_fragmenter != null:
		var current_addr: int = get_zone_spatial_address(current_zone_id)
		if current_addr != 0:
			var pos: Vector3 = entity.global_position
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

## Claim comparison: does zone a outrank zone b for overlap resolution?
func _zone_claims_better(a: ZoneData, b: ZoneData) -> bool:
	if a.level_requirement != b.level_requirement:
		return a.level_requirement > b.level_requirement
	return a.zone_radius < b.zone_radius

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

	# Exit current zone (Array.erase is the single removal; the old code
	# also called remove_at(find(entity)), which computed -1 and raised an
	# out-of-bounds error on every single transition).
	_entity_zones.erase(entity.entity_id)
	_players_in_zone[from_zone.id].erase(entity)
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

## Process all entities for seamless transitions (call from _physics_process)
func process_seamless_transitions() -> void:
	for entity_id in _entity_zones:
		var entity_service = EntityService
		if entity_service:
			var entity = entity_service.get_entity(entity_id)
			if entity and is_instance_valid(entity):
				var new_zone = check_seamless_transition(entity)
				if new_zone:
					perform_seamless_transition(entity, new_zone)

## Detect new entities entering zones (not yet tracked in _entity_zones)
func _detect_new_entity_zone_entries() -> void:
	var entity_service = EntityService
	if not entity_service:
		return

	# Get all entities from EntityService
	var all_entities: Array = entity_service.get_all_entities()
	if all_entities.is_empty():
		return

	# Use SpatialFragmenter for efficient spatial queries if available
	if _spatial_fragmenter != null:
		_detect_zone_entries_spatial(all_entities)
	else:
		_detect_zone_entries_fallback(all_entities)

## Detect zone entries using SpatialFragmenter spatial indexing
func _detect_zone_entries_spatial(entities: Array) -> void:
	# Build a map of zone spatial addresses for quick lookup
	var zone_addresses: Dictionary = {}
	for zone_id in _zones:
		var addr: int = get_zone_spatial_address(zone_id)
		if addr != 0:
			zone_addresses[zone_id] = addr

	if zone_addresses.is_empty():
		_detect_zone_entries_fallback(entities)
		return

	for entity in entities:
		if not entity or not is_instance_valid(entity):
			continue
		if not entity.entity_id:
			continue

		# Skip entities already tracked in a zone
		if _entity_zones.has(entity.entity_id):
			continue

		# Entities torn out of the tree (scene change, despawn race) still
		# sit in the registry for a frame or two; global_position on them
		# throws "!is_inside_tree()" engine errors every physics tick and
		# once segfaulted the engine during a PLAYING -> MAIN_MENU change.
		if entity is Node3D and not entity.is_inside_tree():
			continue

		# Compute entity's spatial address at a deeper depth than zones
		var pos: Vector3 = entity.global_position
		var found_zone: ZoneData = null

		# Check each zone - compute entity address at zone's depth + 4
		for zone_id in zone_addresses:
			var zone_addr: int = zone_addresses[zone_id]
			var zone_depth: int = _spatial_fragmenter.get_depth(zone_addr)
			var zone_face: int = _spatial_fragmenter.get_face(zone_addr)
			
			# Use deeper depth for entity to be a descendant of zone
			var entity_depth: int = mini(zone_depth + 4, _spatial_fragmenter.MAX_DEPTH)
			var entity_addr: int = _spatial_fragmenter.make_address(
				int(pos.x / SPATIAL_QUANTUM),
				int(pos.y / SPATIAL_QUANTUM),
				int(pos.z / SPATIAL_QUANTUM),
				entity_depth,
				zone_face
			)

			if entity_addr != 0 and _spatial_fragmenter.is_ancestor(zone_addr, entity_addr):
				var zone = _zones.get(zone_id)
				if zone and zone.contains_position(pos):
					found_zone = zone
					break

		if found_zone:
			entity_enter_zone(entity, found_zone)  # emits entity_entered_zone itself

## Fallback zone entry detection using Euclidean distance
func _detect_zone_entries_fallback(entities: Array) -> void:
	for entity in entities:
		if not entity or not is_instance_valid(entity):
			continue
		if not entity.entity_id:
			continue
		# Same out-of-tree guard as the spatial path (scene teardown race).
		if entity is Node3D and not entity.is_inside_tree():
			continue

		# Skip entities already tracked in a zone
		if _entity_zones.has(entity.entity_id):
			continue

		var pos: Vector3 = entity.global_position
		var best_zone: ZoneData = null
		var best_distance: float = INF

		# Check all non-instanced zones
		for zone in _zones.values():
			if zone.is_instanced:
				continue
			if zone.contains_position(pos):
				var dist: float = pos.distance_to(zone.zone_center)
				if dist < best_distance:
					best_distance = dist
					best_zone = zone

		if best_zone:
			entity_enter_zone(entity, best_zone)
			entity_entered_zone.emit(entity, best_zone)

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

	# Create new instance for party. The leader is the owner of
	# record: instance-creation QoS binds per requester (S12).
	var instance_id = create_instance(base_zone_id, party_leader_id)
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
