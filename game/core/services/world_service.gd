## WorldService - World state and gateway management
## Coordinates zones, gateways, day/night cycle, and world events
extends Node

const DictStore = preload("res://adapters/persistence/dict_store.gd")
const WorldRegistryScript = preload("res://core/frame/srv/world_registry.gd")

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

# Event scheduler state
var _next_event_check: float = 0.0
var _event_check_interval: float = 30.0

# Gateway proximity cooldown (prevent signal spam)
var _gateway_cooldowns: Dictionary = {}  # player_id -> {gateway_id -> last_emit_time}
const _GATEWAY_COOLDOWN: float = 5.0  # 5 seconds between emissions

const _kv_prefix := "world:"
const _kv_events := "world:event:"

signal time_changed(time_of_day: String, hour: int)
signal day_changed(day_number: int)
signal gateway_activated(gateway_id: String, entity)
signal event_started(event_id: String, event_name: String)
signal event_ended(event_id: String, event_name: String)

# Gateway schema (renamed from GatewayData to avoid shadowing the
# global class_name GatewayData in core/schemas/gateway_data.gd)
class GatewayRecord:
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
	_load_gateways()
	_load_events()
	_setup_event_scheduler()

## Main tick loop - call every frame
func _process(delta: float) -> void:
	advance_time(delta)
	process_events(delta)
	_process_seamless_transitions()
	_check_gateway_proximity()
	_process_event_scheduler(delta)

## Initialize the world
func initialize_world() -> void:
	# Bind the canonical world's lattice seed BEFORE anything generates
	# from it (procedural chunks derive their content from world_seed).
	_bind_registry_seed()

	# Load all zones
	var zone_manager = ZoneManager
	if zone_manager:
		zone_manager.load_zones()

	# Load all factions
	var faction_manager = FactionManager
	if faction_manager:
		faction_manager.load_factions()

	# Spawn offering NPCs (NPCEntity with includes[])
	var spawn_service = SpawnService
	if spawn_service:
		spawn_service.spawn_all_offering_npcs()

	GameLog.info("WorldService: World initialized")

## Tick helper methods

## Setup event scheduler for periodic/random events
func _setup_event_scheduler() -> void:
	# Event templates define possible world events
	_event_templates = {
		"double_xp": {
			"name": "Double XP Weekend",
			"duration": 3600.0,  # 1 hour
			"min_interval": 7200.0,  # 2 hours between events
			"max_interval": 14400.0,  # 4 hours max
			"weight": 10,
			"time_restrictions": []  # Empty = any time
		},
		"double_loot": {
			"name": "Loot Festival",
			"duration": 1800.0,  # 30 minutes
			"min_interval": 10800.0,  # 3 hours
			"max_interval": 21600.0,  # 6 hours
			"weight": 5,
			"time_restrictions": []
		},
		"invasion": {
			"name": "Monster Invasion",
			"duration": 600.0,  # 10 minutes
			"min_interval": 1800.0,  # 30 minutes
			"max_interval": 3600.0,  # 1 hour
			"weight": 3,
			"time_restrictions": ["night"]
		}
	}
	
	# Initialize next event timers
	_next_event_check = 0.0
	_event_check_interval = 30.0  # Check every 30 seconds real-time

## Process seamless zone transitions via ZoneManager
func _process_seamless_transitions() -> void:
	var zone_manager = ZoneManager
	if zone_manager and zone_manager.has_method("process_seamless_transitions"):
		zone_manager.process_seamless_transitions()

## Check gateway proximity for all players and auto-trigger
func _check_gateway_proximity() -> void:
	var entity_service = EntityService
	if not entity_service:
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var players = entity_service.get_all_players()
	for player in players:
		if not is_instance_valid(player):
			continue
		
		var gateway = get_nearby_gateway(player)
		if gateway:
			# Check if player can use this gateway
			if gateway.can_use(player):
				# Cooldown check to prevent signal spam
				var player_id = player.entity_id
				var gateway_id = gateway.id
				var last_emit = _gateway_cooldowns.get(player_id, {}).get(gateway_id, 0.0)
				if current_time - last_emit >= _GATEWAY_COOLDOWN:
					if not _gateway_cooldowns.has(player_id):
						_gateway_cooldowns[player_id] = {}
					_gateway_cooldowns[player_id][gateway_id] = current_time
					# Emit signal for UI/player to respond, or auto-trigger based on design
					# For now, emit signal so UI can show prompt
					gateway_activated.emit(gateway_id, player)
					GameLog.debug("WorldService: Player %s near gateway %s" % [player.display_name, gateway_id])

## Process event scheduler - randomly trigger world events
func _process_event_scheduler(delta: float) -> void:
	_next_event_check += delta
	if _next_event_check < _event_check_interval:
		return
	
	_next_event_check = 0.0
	
	# Don't spawn new events if too many active
	if _active_events.size() >= 3:
		return
	
	# Check each template for potential trigger
	var current_time = get_time_of_day()
	for event_id in _event_templates:
		if is_event_active(event_id):
			continue
		
		var template = _event_templates[event_id]
		
		# Check time restrictions
		if template.time_restrictions.size() > 0:
			if current_time not in template.time_restrictions:
				continue
		
		# Random chance based on weight (weight out of 100)
		var chance = template.weight * 0.01  # 10% base for weight 10
		if randf() < chance:
			start_event(event_id, template.duration)
			break  # Only start one event per check cycle

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

	var gateway := GatewayRecord.new()
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
func get_gateway(gateway_id: String) -> GatewayRecord:
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

	# Enter destination zone. Lazy-load zone defs when the destination
	# is unknown (direct scene runs and headless boots skip
	# initialize_world, same on-demand pattern as world_playable).
	# Without this the player teleports but stays zone-less -- and the
	# seamless detector can re-claim them into an overlapping source
	# zone, bouncing them right back out of the dungeon.
	var dest_zone = zone_manager.get_zone(destination.zone_id)
	if dest_zone == null and zone_manager.has_method("load_zones"):
		zone_manager.load_zones()
		dest_zone = zone_manager.get_zone(destination.zone_id)
	if dest_zone:
		zone_manager.entity_enter_zone(entity, dest_zone)
	else:
		GameLog.warn("WorldService: gateway destination zone unknown: %s" % destination.zone_id)

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
func get_nearby_gateway(entity) -> GatewayRecord:
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
	_persist_events()

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
		_persist_events()

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

## Bind the canonical world's lattice seed at boot: WorldRegistry
## derives every world's 32-byte seed from the committed universe
## constant through the nesting path ("main" under the universe root)
## -- same bytes on every install, forever. The first 8 bytes become
## WorldService.world_seed, the domain input for procedural chunk
## generation (chunk content is DERIVED from it, never stored, so the
## committed constant reveals no content -- the S16.1 width law).
## Idempotent and failure-safe: a missing lattice leaves world_seed
## untouched.
func _bind_registry_seed() -> void:
	var registry = WorldRegistryScript.new()
	registry.load_worlds()
	var seed_bytes: PackedByteArray = registry.world_seed("main")
	if seed_bytes.size() < 8:
		GameLog.warn("WorldService: lattice seed unavailable; chunk domain seed unchanged")
		return
	var seed_int: int = seed_bytes.decode_s64(0)
	if world_seed == seed_int:
		return
	generate_world_from_seed(seed_int)

## Get seeded random value
func get_seeded_random(range_max: int) -> int:
	return randi() % range_max

## == Procedural chunks (Phase 6 prefetch target) ============================

## Chunk edge length for procedural generation. Must match TickService's
## CHUNK_SIZE; kept local so the world layer does not depend on the
## tick service.
const CHUNK_SIZE: int = 100
const _kv_chunks := "world:chunk:"

## Terrain-level biomes a chunk can roll. Item/enemy ids are the
## spawn and loot layers' concern, not the chunk's.
const CHUNK_BIOMES: Array[String] = ["plains", "forest", "rocky", "wetland"]

signal chunk_generated(chunk_key: String)

# Generated chunk records ("cx_cz" -> Dictionary), loaded lazily from
# the kv store so reboots never regenerate existing chunks.
var _chunks: Dictionary = {}
var _chunks_loaded: bool = false

## Generate one world chunk's content.
## Deterministic by law: content derives ONLY from world_seed + chunk
## coordinates through SeedChain.derive_seed (the frame's folded
## SHA-256 derivation) -- never from global RNG state -- so the same
## chunk regenerates identically on every server and every reboot.
## Already-generated chunks return as-is (the Phase 6 prefetch may ask
## for the same chunk repeatedly); records persist under
## world:chunk:<key> so reboots load instead of regenerate.
func generate_chunk(chunk_key: String) -> Dictionary:
	var coords := _parse_chunk_key(chunk_key)
	if coords.is_empty():
		return {}
	if not _chunks_loaded:
		_load_chunks()
	if _chunks.has(chunk_key):
		return _chunks[chunk_key]
	var record := _build_chunk_record(coords[0], coords[1], chunk_key)
	_chunks[chunk_key] = record
	_persist_chunk(chunk_key, record)
	chunk_generated.emit(chunk_key)
	GameLog.debug("WorldService: generated chunk %s (%s)" % [chunk_key, str(record.get("biome", "?"))])
	return record

## Fetch a generated chunk WITHOUT generating it ({} when unknown).
func get_chunk(chunk_key: String) -> Dictionary:
	if not _chunks_loaded:
		_load_chunks()
	var chunk: Variant = _chunks.get(chunk_key, {})
	if chunk is Dictionary:
		return chunk
	return {}

func is_chunk_generated(chunk_key: String) -> bool:
	if not _chunks_loaded:
		_load_chunks()
	return _chunks.has(chunk_key)

func generated_chunk_count() -> int:
	if not _chunks_loaded:
		_load_chunks()
	return _chunks.size()

## Parse "cx_cz" into [cx, cz]; [] when the key is not a chunk key.
func _parse_chunk_key(chunk_key: String) -> Array:
	var parts := chunk_key.split("_")
	if parts.size() != 2:
		return []
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return []
	return [int(parts[0]), int(parts[1])]

## Build the chunk record. Every roll comes from one RNG seeded with
## the SeedChain-derived chunk seed, so the record is a pure function
## of (world_seed, cx, cz).
func _build_chunk_record(cx: int, cz: int, chunk_key: String) -> Dictionary:
	var chunk_seed := _chunk_seed_bytes(cx, cz)
	var rng := RandomNumberGenerator.new()
	rng.seed = chunk_seed.decode_u64(0)

	var biome: String = CHUNK_BIOMES[rng.randi() % CHUNK_BIOMES.size()]
	var elevation: int = rng.randi_range(0, 255)

	var resources: Array = []
	var resource_count: int = rng.randi_range(0, 4)
	for _i in range(resource_count):
		resources.append({
			"kind": ["ore", "herb", "wood"][rng.randi() % 3],
			"x": _chunk_local(rng, cx),
			"z": _chunk_local(rng, cz),
		})


	var spawn_hints: Array = []
	var pack_count: int = rng.randi_range(0, 2)
	for _i in range(pack_count):
		spawn_hints.append({
			"pack_size": rng.randi_range(1, 3),
			"x": _chunk_local(rng, cx),
			"z": _chunk_local(rng, cz),
		})

	return {
		"chunk_key": chunk_key,
		"cx": cx,
		"cz": cz,
		"biome": biome,
		"elevation": elevation,
		"resources": resources,
		"spawn_hints": spawn_hints,
		"seed": chunk_seed.hex_encode(),
		"world_seed": world_seed,
	}

## Snap a world position to the millimeter grid. Positions only ever
## carry millimeter precision, and short decimal forms round-trip
## exactly through the store's JSON encoding -- long float64 reprs lose
## the last bit, which made a reboot-loaded chunk differ from a freshly
## generated one under record equality.
func _snap_mm(v: float) -> float:
	return float(round(v * 1000.0)) / 1000.0

## A world-space position inside the chunk (chunk origin + local offset).
func _chunk_local(rng: RandomNumberGenerator, origin: int) -> float:
	return _snap_mm(float(origin * CHUNK_SIZE) + rng.randf_range(0.0, float(CHUNK_SIZE)))

## The chunk's derivation seed: SeedChain folds the world seed bytes
## with the chunk path. Same world seed + coords -> same 32-byte seed.
## When the frame boot wires WorldRegistry's per-world seed through
## generate_world_from_seed, every chunk re-derives deterministically.
func _chunk_seed_bytes(cx: int, cz: int) -> PackedByteArray:
	var SeedChainScript = load("res://core/frame/kv/seed_chain.gd")
	var world_bytes := PackedByteArray()
	world_bytes.resize(8)
	world_bytes.encode_s64(0, world_seed)
	var stack: Array[PackedByteArray] = [world_bytes]
	return SeedChainScript.derive_seed(stack, "chunk/%d/%d" % [cx, cz])

func _load_chunks() -> void:
	_chunks = {}
	_chunks_loaded = true
	var store := DictStore.new()
	for key in store.all_keys():
		if key.begins_with(_kv_chunks):
			var chunk_key: String = key.substr(_kv_chunks.length())
			var loaded: Variant = store.get_kv(key)
			if loaded is Dictionary and not loaded.is_empty():
				_chunks[chunk_key] = _normalize_chunk_record(loaded)

## JSON round-trips (the store's native encoding) turn ints into floats,
## so a record read back after a reboot would be type-different from a
## freshly generated one (int 41 vs float 41.0) -- unstable for
## consumers and for record equality. Normalize the integer fields on
## load so both paths are identical.
func _normalize_chunk_record(record: Dictionary) -> Dictionary:
	if record.has("cx"):
		record["cx"] = int(record["cx"])
	if record.has("cz"):
		record["cz"] = int(record["cz"])
	if record.has("elevation"):
		record["elevation"] = int(record["elevation"])
	if record.has("world_seed"):
		record["world_seed"] = int(record["world_seed"])
	for list_key in ["resources", "spawn_hints"]:
		var arr: Variant = record.get(list_key, [])
		if arr is Array:
			for item in arr:
				if item is Dictionary:
					if item.has("x"):
						item["x"] = _snap_mm(float(item["x"]))
					if item.has("z"):
						item["z"] = _snap_mm(float(item["z"]))
					if list_key == "spawn_hints" and item.has("pack_size"):
						item["pack_size"] = int(item["pack_size"])
	return record

func _persist_chunk(chunk_key: String, record: Dictionary) -> void:
	var store := DictStore.new()
	store.set_kv(_kv_chunks + chunk_key, record)

## Find path between zones using ZoneManager neighbor graph (BFS) or NSC-9 spatial adjacency.
## Returns array of zone IDs representing the path, or empty array if no path found.
func find_zone_path(from_zone_id: String, to_zone_id: String) -> Array[String]:
	if from_zone_id == to_zone_id:
		return [from_zone_id]

	var zone_manager = ZoneManager
	if zone_manager == null:
		GameLog.warn("WorldService: ZoneManager not available for pathfinding")
		return []

	# Check for direct gateway connection first
	var gateways = get_zone_gateways(from_zone_id)
	for gateway in gateways:
		if gateway.to_zone_id == to_zone_id:
			return [from_zone_id, to_zone_id]

	# Use ZoneManager's registered neighbor graph (BFS)
	var path: Array[String] = _bfs_zone_path(zone_manager, from_zone_id, to_zone_id)
	if not path.is_empty():
		return path

	# Fallback: NSC-9 spatial adjacency via SpatialFragmenter
	path = _nsc9_spatial_path(zone_manager, from_zone_id, to_zone_id)
	if not path.is_empty():
		return path

	# No path found
	GameLog.debug("WorldService: No zone path found from %s to %s" % [from_zone_id, to_zone_id])
	return []


## BFS pathfinding on ZoneManager's registered neighbor graph
func _bfs_zone_path(zone_manager, from_zone_id: String, to_zone_id: String) -> Array[String]:
	var visited: Dictionary = {}
	var queue: Array = [[from_zone_id]]  # Queue of paths
	visited[from_zone_id] = true

	while not queue.is_empty():
		var current_path: Array[String] = queue.pop_at(0)
		var current_id: String = current_path[-1]

		if current_id == to_zone_id:
			return current_path

		var neighbors: Array = zone_manager.get_neighboring_zones(current_id)
		for neighbor in neighbors:
			var neighbor_id: String = neighbor.id
			if not visited.has(neighbor_id):
				visited[neighbor_id] = true
				var new_path: Array[String] = current_path.duplicate()
				new_path.append(neighbor_id)
				queue.append(new_path)

	return []


## NSC-9 spatial pathfinding: find path through zones sharing spatial ancestry
func _nsc9_spatial_path(zone_manager, from_zone_id: String, to_zone_id: String) -> Array[String]:
	# Get spatial addresses for both zones
	var from_addr: int = zone_manager.get_zone_spatial_address(from_zone_id)
	var to_addr: int = zone_manager.get_zone_spatial_address(to_zone_id)
	if from_addr == 0 or to_addr == 0:
		return []

	# Get the spatial fragmenter instance (via a public method if needed)
	# We'll access it via the bridge which is also available
	var spatial_fragmenter = null
	if zone_manager.has_method("get_spatial_fragmenter"):
		spatial_fragmenter = zone_manager.get_spatial_fragmenter()
	elif zone_manager.has_method("_get_spatial_fragmenter"):
		spatial_fragmenter = zone_manager._get_spatial_fragmenter()
	
	if spatial_fragmenter == null:
		return []

	# Check if they share a common ancestor (spatially connected)
	var common_ancestor: int = spatial_fragmenter.find_common_ancestor([from_addr, to_addr])
	if common_ancestor == 0:
		return []

	# Find intermediate zones that bridge the spatial path
	# We look for zones whose addresses are ancestors/descendants of the common ancestor
	var candidate_zones: Array[String] = []
	var all_zones: Array = zone_manager.get_all_zones()
	for zone in all_zones:
		if zone.id == from_zone_id or zone.id == to_zone_id:
			continue
		if zone.is_instanced:
			continue
		
		var zone_addr: int = zone_manager.get_zone_spatial_address(zone.id)
		if zone_addr == 0:
			continue
		
		# Zone is on the spatial path if it's an ancestor of from or to,
		# or a descendant of the common ancestor
		if spatial_fragmenter.is_ancestor(zone_addr, from_addr) or spatial_fragmenter.is_ancestor(zone_addr, to_addr) or \
			spatial_fragmenter.is_ancestor(common_ancestor, zone_addr):
			candidate_zones.append(zone.id)

	# Simple greedy path: from -> candidates (sorted by depth) -> to
	if candidate_zones.is_empty():
		# Direct spatial connection
		return [from_zone_id, to_zone_id]

	# Sort candidates by depth (shallowest first = larger regions first)
	candidate_zones.sort_custom(func(a_id, b_id):
		var a_addr = zone_manager.get_zone_spatial_address(a_id)
		var b_addr = zone_manager.get_zone_spatial_address(b_id)
		var a_depth = spatial_fragmenter.get_depth(a_addr)
		var b_depth = spatial_fragmenter.get_depth(b_addr)
		return a_depth < b_depth
	)

	var path: Array[String] = [from_zone_id]
	for candidate_id in candidate_zones:
		path.append(candidate_id)
	path.append(to_zone_id)

	return path

## == Persistence ============================================================

func _load_gateways() -> void:
	var store := DictStore.new()
	_gateways = {}
	for key in store.all_keys():
		if key.begins_with(_kv_prefix + "gateway:"):
			var gateway_id = key.substr(_kv_prefix.length() + 8)
			_gateways[gateway_id] = store.get_kv(key)

func _persist_gateway(gateway_id: String) -> void:
	var store := DictStore.new()
	if _gateways.has(gateway_id):
		store.set_kv(_kv_prefix + "gateway:" + gateway_id, _gateways[gateway_id])
	else:
		store.erase(_kv_prefix + "gateway:" + gateway_id)

func _load_events() -> void:
	var store := DictStore.new()
	_active_events = []
	for key in store.all_keys():
		if key.begins_with(_kv_events):
			var loaded = store.get_kv(key)
			if loaded is Array:
				for ev in loaded:
					_active_events.append(ev)

func _persist_events() -> void:
	var store := DictStore.new()
	if _active_events.is_empty():
		store.erase(_kv_events + "active")
	else:
		store.set_kv(_kv_events + "active", _active_events)
