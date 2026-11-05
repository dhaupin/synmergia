## CoordinatorService - Cross-shard state and event coordination
##
## Phase 3+ extract: separates cross-shard coordination from
## per-shard Godot processes into a dedicated coordinator process.
## Implements HLC event routing, shard registry, player routing,
## and cross-shard state pointers for player-placed content.
##
## This service is a pure data-processing service. It does NOT
## depend on the Godot scene system. Extends Node only for
## autoload compatibility.
##
## Cross-shard event format (JSON):
##   {"event_type": str, "source_shard": str,
##    "source_entity_id": str, "payload": dict,
##    "hlc_timestamp": int}
##
## Cross-shard pointer format:
##   {house_id: {shard_id, coord_x, coord_y, coord_z,
##               owner, state_hash}}
##
## Autoload order: CoordinatorService must be listed BEFORE
## any service that references it in _ready (per AGENTS.md
## autoload ordering rules).

extends Node
const DictStore = preload("res://adapters/persistence/dict_store.gd")
const ShardBusRegistry = preload("res://core/mesh/shard_bus_registry.gd")
const MeshRole = preload("res://core/mesh/mesh_role.gd")

signal shard_registered(shard_id: String, info: Dictionary)
signal shard_unregistered(shard_id: String)
signal cross_shard_event_emitted(event: Dictionary)
signal player_shard_changed(player_id: String, from_shard: String, to_shard: String)
signal shard_status_changed(shard_id: String, status: String)

const _kv_prefix := "coordinator:"
## The one broadcast topic every shard subscribes to. publish() fans a
## message out to every OTHER subscriber, so one topic carries the whole
## mesh's cross-shard traffic without echo.
const BUS_TOPIC := "coordinator:events"
## Registry traffic rides its OWN topic so mesh bookkeeping never mixes
## with gameplay events on BUS_TOPIC (the tick consumes those as world
## events). Every container subscribes; a shard announces here and the
## coordinator ingests it -- this is what makes the registry span
## PROCESSES, not just one container's memory.
const MESH_TOPIC := "coordinator:mesh"
const MSG_REGISTER := "mesh_register"
const MSG_UNREGISTER := "mesh_unregister"
const _RATE_LIMIT_WINDOW_SEC: float = 1.0
const _RATE_LIMIT_MAX_QUERIES: int = 10
const _DEFAULT_MAX_PLAYERS_PER_SHARD: int = 5000
const _DEFAULT_SHARD_STATUS: String = "online"

## All active shard IDs and their configurations
var _shards: Dictionary = {}  # shard_id -> {name, player_count, status, info}

## Player -> shard_id mapping
var _player_shard_map: Dictionary = {}  # player_id -> shard_id

## Player presence tracking: player_id -> {shard_id, last_seen}
var _player_presence: Dictionary = {}  # player_id -> {shard_id, last_seen}

## Rate limit tracker for get_online_players: player_id -> [timestamps]
var _rate_limit_tracker: Dictionary = {}  # query_key -> [timestamps]

## Cross-shard pointers: pointer_type -> id -> {shard_id, coord_x, coord_y, coord_z, owner, state_hash}
var _cross_shard_pointers: Dictionary = {}  # pointer_type -> id -> data

## Event queue for pending cross-shard events awaiting dispatch
var _event_queue: Array = []

## Whether the coordinator is fully initialized
var _initialized: bool = false

## HLC logical clock counter (monotonically increasing)
var _hlc_counter: int = 0

## The cross-shard transport seam (Phase 1 of prd-shard-mesh.md). The
## registry seeds a MemoryShardBus; the mesh swaps in a RedisShardBus.
var _bus_registry = null
var _bus = null
var _bus_self_id: String = ""

## Runtime autoload lookup (script-mode-safe; bare identifiers fail to
## compile in --script mode where autoloads are not registered).
func _autoload(name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(name))

## The transport board. Lazily built so it is safe to call before _ready.
func bus_registry():
	if _bus_registry == null:
		_bus_registry = ShardBusRegistry.new()
	return _bus_registry

## The active transport (the registry's default).
func bus():
	if _bus == null:
		_bus = bus_registry().get_default_bus()
	return _bus

## Point the coordinator at a bus and (re)subscribe its self topic. The
## transport is chosen by SHARD_BUS_BACKEND, which defaults to follow
## CACHE_BACKEND: "redis" builds a RedisShardBus and, if it connects,
## makes it the default; anything else (or a failed connect) keeps the
## seeded memory bus (dev/CI unchanged). The self id comes from
## ShardManager when present, else a process fallback, so a single-process
## boot still has a stable inbox key.
func _bind_bus() -> void:
	var want := OS.get_environment("SHARD_BUS_BACKEND")
	if want.is_empty():
		want = "redis" if OS.get_environment("CACHE_BACKEND") == "redis" else "memory"
	if want == "redis":
		var redis_script: GDScript = load("res://core/mesh/redis_shard_bus.gd")
		if redis_script != null and redis_script.can_instantiate():
			var rbus = redis_script.new()
			if rbus.open({}) == 0:
				bus_registry().register(rbus, true)
				_bus = rbus
			else:
				GameLog.warn("CoordinatorService: redis bus unavailable; using memory bus")
	var active = bus()
	if active == null:
		return
	# Phase 3: the self id is the container's MESH identity -- the
	# coordinator id for a coordinator, else the shard id -- so registry
	# traffic and gameplay events key off the same identity the registry
	# reports. MeshRole owns the law (env-only; dev falls back to shard_1).
	_bus_self_id = MeshRole.self_id()
	active.set_self_id(_bus_self_id)
	active.subscribe(BUS_TOPIC)
	active.subscribe(MESH_TOPIC)
	GameLog.info("CoordinatorService: Cross-shard bus = %s (self=%s, role=%s)" % [active.get_id(), _bus_self_id, MeshRole.resolve()])

## Get the current HLC timestamp (physical + logical)
func _get_hlc_timestamp() -> int:
	_hlc_counter += 1
	return Time.get_unix_time_from_system() * 1000 + _hlc_counter

## Returns the current HLC logical counter
func get_hlc_counter() -> int:
	return _hlc_counter

## === Initialization ===

func _ready() -> void:
	_load_state()
	# Defer past autoload order: CoordinatorService loads BEFORE ShardManager
	# in project.godot, so binding synchronously here would read a missing
	# node and always fall back to "shard_1". The deferred bind sees the real
	# shard id.
	_bind_bus.call_deferred()
	_initialized = true
	GameLog.info("CoordinatorService: Initialized with %d registered shards" % _shards.size())

## Persist coordinator state to DictStore
func _persist_state() -> void:
	var ds := DictStore.new()
	ds.set_kv(_kv_prefix + "shards", _shards)
	ds.set_kv(_kv_prefix + "player_shard_map", _player_shard_map)
	ds.set_kv(_kv_prefix + "player_presence", _player_presence)
	ds.set_kv(_kv_prefix + "cross_shard_pointers", _cross_shard_pointers)
	ds.set_kv(_kv_prefix + "hlc_counter", _hlc_counter)

func _load_state() -> void:
	var ds := DictStore.new()
	var shards_data: Variant = ds.get_kv(_kv_prefix + "shards")
	if shards_data is Dictionary:
		_shards = shards_data
	var psm_data: Variant = ds.get_kv(_kv_prefix + "player_shard_map")
	if psm_data is Dictionary:
		_player_shard_map = psm_data
	var pp_data: Variant = ds.get_kv(_kv_prefix + "player_presence")
	if pp_data is Dictionary:
		_player_presence = pp_data
	var csp_data: Variant = ds.get_kv(_kv_prefix + "cross_shard_pointers")
	if csp_data is Dictionary:
		_cross_shard_pointers = csp_data
	var hlc_data: Variant = ds.get_kv(_kv_prefix + "hlc_counter")
	if hlc_data is int:
		_hlc_counter = hlc_data
	GameLog.debug("CoordinatorService: Loaded state from persistence")

## === Shard Registry ===

## Register a shard with the coordinator. Called by each shard on boot.
func register_shard(shard_id: String, info: Dictionary) -> void:
	var shard_info := {
		"name": info.get("name", "Unnamed"),
		"player_count": 0,
		"status": _DEFAULT_SHARD_STATUS,
		"max_players": info.get("max_players", _DEFAULT_MAX_PLAYERS_PER_SHARD),
		"world_name": info.get("world_name", "Synmergia"),
		"is_primary": info.get("is_primary", false),
		"registered_at": Time.get_unix_time_from_system(),
		"info": info
	}
	_shards[shard_id] = shard_info
	shard_registered.emit(shard_id, shard_info)
	shard_status_changed.emit(shard_id, _DEFAULT_SHARD_STATUS)
	_persist_state()
	GameLog.info("CoordinatorService: Registered shard %s (%s)" % [shard_id, shard_info.name])

## Unregister a shard (e.g., on shutdown or failure)
func unregister_shard(shard_id: String) -> void:
	if not _shards.has(shard_id):
		return
	_shards.erase(shard_id)
	shard_unregistered.emit(shard_id)
	_persist_state()
	GameLog.info("CoordinatorService: Unregistered shard %s" % shard_id)

## === Cross-process mesh registry (Phase 3) ===

## Announce this shard's registration on the mesh topic so a coordinator
## in ANOTHER process ingests it. A no-op when the bus is unwired or this
## container IS the coordinator (the coordinator does not register as a
## shard). The local registry was already updated by register_shard(), so
## a standalone boot is unchanged.
func announce_self_to_mesh(shard_id: String, info: Dictionary) -> void:
	if MeshRole.is_coordinator():
		return
	var active = bus()
	if active == null:
		return
	active.publish(MESH_TOPIC, {
		"kind": MSG_REGISTER,
		"shard_id": shard_id,
		"info": info,
		"sent_at": Time.get_unix_time_from_system(),
	})

## Announce a shard's departure on the mesh topic.
func announce_unregister_to_mesh(shard_id: String) -> void:
	if MeshRole.is_coordinator():
		return
	var active = bus()
	if active == null:
		return
	active.publish(MESH_TOPIC, {
		"kind": MSG_UNREGISTER,
		"shard_id": shard_id,
		"sent_at": Time.get_unix_time_from_system(),
	})

## Drain the mesh topic and fold remote register/unregister mail into the
## local registry. This is the leg that makes the registry span PROCESSES:
## a shard's announce lands here and becomes a normal registry entry. It
## never re-publishes (no loop) and ignores its own mail (the bus already
## no-echoes a publisher). Safe to call before the bus binds (no-op).
func _ingest_mesh_mail() -> void:
	var active = bus()
	if active == null:
		return
	for msg in active.poll(MESH_TOPIC):
		if not (msg is Dictionary):
			continue
		var kind := str(msg.get("kind", ""))
		var sid := str(msg.get("shard_id", ""))
		if sid.is_empty() or sid == MeshRole.COORDINATOR_ID:
			continue
		match kind:
			MSG_REGISTER:
				var info: Dictionary = msg.get("info", {})
				_apply_remote_registration(sid, info)
			MSG_UNREGISTER:
				_apply_remote_unregistration(sid)
			_:
				pass

## Apply a remote shard registration without re-announcing (the coordinator
## side of announce_self_to_mesh). Idempotent: a repeat announce refreshes
## the entry rather than duplicating it.
func _apply_remote_registration(shard_id: String, info: Dictionary) -> void:
	var shard_info := {
		"name": info.get("name", "Unnamed"),
		"player_count": int(info.get("player_count", 0)),
		"status": str(info.get("status", _DEFAULT_SHARD_STATUS)),
		"max_players": info.get("max_players", _DEFAULT_MAX_PLAYERS_PER_SHARD),
		"world_name": info.get("world_name", "Synmergia"),
		"is_primary": info.get("is_primary", false),
		"registered_at": Time.get_unix_time_from_system(),
		"remote": true,
		"info": info,
	}
	_shards[shard_id] = shard_info
	shard_registered.emit(shard_id, shard_info)
	shard_status_changed.emit(shard_id, shard_info.status)
	_persist_state()
	GameLog.info("CoordinatorService: Ingested remote shard %s (%s)" % [shard_id, shard_info.name])

func _apply_remote_unregistration(shard_id: String) -> void:
	if not _shards.has(shard_id):
		return
	_shards.erase(shard_id)
	shard_unregistered.emit(shard_id)
	_persist_state()
	GameLog.info("CoordinatorService: Remote shard %s left the mesh" % shard_id)

## Update a shard's player count and status
func update_shard_info(shard_id: String, player_count: int = -1, status: String = "") -> void:
	if not _shards.has(shard_id):
		return
	if player_count >= 0:
		_shards[shard_id].player_count = player_count
	if status != "":
		_shards[shard_id].status = status
		shard_status_changed.emit(shard_id, status)
	_persist_state()

## Get shard info by ID. Returns {name, player_count, status, ...}
## Ingests remote mesh mail first so a cross-process registration is
## visible the moment anyone asks (no background poller needed).
func get_shard_info(shard_id: String) -> Dictionary:
	_ingest_mesh_mail()
	return _shards.get(shard_id, {})

## Get all registered shard IDs
func get_all_shard_ids() -> Array[String]:
	_ingest_mesh_mail()
	return _shards.keys()

## Get all shard info as a Dictionary
func get_all_shards() -> Dictionary:
	_ingest_mesh_mail()
	return _shards.duplicate()

## Check if a shard is registered and online
func is_shard_online(shard_id: String) -> bool:
	if not _shards.has(shard_id):
		return false
	return _shards[shard_id].status == "online"

## === Player Routing ===

## Return the shard_id for a given player_id
func get_shard_for_player(player_id: String) -> String:
	return _player_shard_map.get(player_id, "")

## Assign a player to a shard (called on login/character select)
func assign_player_to_shard(player_id: String, shard_id: String) -> void:
	var old_shard: String = _player_shard_map.get(player_id, "")
	_player_shard_map[player_id] = shard_id
	_player_presence[player_id] = {
		"shard_id": shard_id,
		"last_seen": Time.get_unix_time_from_system()
	}
	if old_shard != "" and old_shard != shard_id:
		player_shard_changed.emit(player_id, old_shard, shard_id)
		emit_cross_shard_event(
			"player_migration",
			old_shard,
			{"player_id": player_id, "target_shard": shard_id},
			_get_hlc_timestamp()
		)
	if _shards.has(shard_id):
		_shards[shard_id].player_count += 1
		update_shard_info(shard_id, _shards[shard_id].player_count)
	if old_shard != "" and old_shard != shard_id and _shards.has(old_shard):
		var old_count: int = _shards[old_shard].player_count
		_shards[old_shard].player_count = max(0, old_count - 1)
		update_shard_info(old_shard, _shards[old_shard].player_count)
	_persist_state()
	GameLog.debug("CoordinatorService: Assigned player %s to shard %s" % [player_id, shard_id])

## Remove a player from their shard assignment (called on logout)
func remove_player_from_shard(player_id: String) -> void:
	var shard_id: String = _player_shard_map.get(player_id, "")
	if shard_id == "":
		return
	_player_shard_map.erase(player_id)
	_player_presence.erase(player_id)
	if _shards.has(shard_id):
		var count: int = _shards[shard_id].player_count
		_shards[shard_id].player_count = max(0, count - 1)
		update_shard_info(shard_id, _shards[shard_id].player_count)
	_persist_state()
	GameLog.debug("CoordinatorService: Removed player %s from shard %s" % [player_id, shard_id])

## Update player presence timestamp
func update_player_presence(player_id: String, shard_id: String) -> void:
	_player_presence[player_id] = {
		"shard_id": shard_id,
		"last_seen": Time.get_unix_time_from_system()
	}
	_player_shard_map[player_id] = shard_id
	if _shards.has(shard_id):
		update_shard_info(shard_id, _shards[shard_id].player_count)

## === Cross-Shard Event Routing ===

## Emit a cross-shard event with HLC timestamp.
## Format: {"event_type": str, "source_shard": str,
##          "source_entity_id": str, "payload": dict, "hlc_timestamp": int}
func emit_cross_shard_event(event_type: String, source_shard: String, payload: Dictionary, hlc_ts: int, source_entity_id: String = "") -> void:
	var event := {
		"event_type": event_type,
		"source_shard": source_shard,
		"source_entity_id": source_entity_id,
		"payload": payload,
		"hlc_timestamp": hlc_ts
	}
	_event_queue.append(event)
	cross_shard_event_emitted.emit(event)
	# Phase 1: fan the event out to every OTHER shard on the bus. The
	# publisher's own queue already holds it (no-echo), so the local tick
	# and the peers each process it exactly once.
	_publish_event(event)
	GameLog.debug("CoordinatorService: Cross-shard event %s from %s (hlc=%d)" % [event_type, source_shard, hlc_ts])
	_persist_state()

## Publish one event onto the bus topic (a no-op when the bus is unwired).
func _publish_event(event: Dictionary) -> void:
	var active = bus()
	if active == null:
		return
	active.publish(BUS_TOPIC, event)

## Drain events other shards published, appending them to the pending
## queue. Called before every get_pending_events so remote mail rides the
## same exactly-once path as local emits.
func _drain_bus() -> void:
	var active = bus()
	if active == null:
		return
	for msg in active.poll(BUS_TOPIC):
		if msg is Dictionary and msg.has("event_type"):
			_event_queue.append(msg)
			cross_shard_event_emitted.emit(msg)

## Emit a cross-shard event with auto-incremented HLC timestamp
func emit_cross_shard_event_auto(event_type: String, source_shard: String, payload: Dictionary, source_entity_id: String = "") -> void:
	var hlc_ts := _get_hlc_timestamp()
	emit_cross_shard_event(event_type, source_shard, payload, hlc_ts, source_entity_id)

## Get all pending events in the queue (local emits + drained remote mail)
func get_pending_events() -> Array:
	_drain_bus()
	return _event_queue.duplicate()

## Clear processed events from the queue
func clear_processed_events() -> void:
	_event_queue.clear()

## Route a cross-shard event to target shards
func route_event(event: Dictionary) -> void:
	var event_type: String = event.get("event_type", "")
	match event_type:
		"heartbeat":
			_pass_heartbeat(event)
		"leader_election":
			_pass_leader_election(event)
		"world_boss_spawn":
			_pass_world_boss_spawn(event)
		"season_change":
			_pass_season_change(event)
		"player_migration":
			_pass_player_migration(event)
		"guild_update":
			_pass_guild_update(event)
		"auction_update":
			_pass_auction_update(event)
		_:
			GameLog.warn("CoordinatorService: Unknown event type %s" % event_type)

func _pass_heartbeat(event: Dictionary) -> void:
	var source_shard: String = event.get("source_shard", "")
	for shard_id in _shards.keys():
		if shard_id != source_shard:
			emit_cross_shard_event("heartbeat_ack", source_shard, {"target_shard": shard_id, "source": source_shard}, _get_hlc_timestamp())

func _pass_leader_election(event: Dictionary) -> void:
	for shard_id in _shards.keys():
		emit_cross_shard_event("leader_election_propagate", event.get("source_shard", ""), event.get("payload", {}), _get_hlc_timestamp())

func _pass_world_boss_spawn(event: Dictionary) -> void:
	emit_cross_shard_event("world_boss_update", event.get("source_shard", ""), event.get("payload", {}), _get_hlc_timestamp())

func _pass_season_change(event: Dictionary) -> void:
	emit_cross_shard_event("season_update", event.get("source_shard", ""), event.get("payload", {}), _get_hlc_timestamp())

func _pass_player_migration(event: Dictionary) -> void:
	var player_id: String = event.get("payload", {}).get("player_id", "")
	var target_shard: String = event.get("payload", {}).get("target_shard", "")
	if target_shard != "" and target_shard in _shards:
		assign_player_to_shard(player_id, target_shard)

func _pass_guild_update(event: Dictionary) -> void:
	for shard_id in _shards.keys():
		if shard_id != event.get("source_shard", ""):
			emit_cross_shard_event("guild_sync", event.get("source_shard", ""), event.get("payload", {}), _get_hlc_timestamp())

func _pass_auction_update(event: Dictionary) -> void:
	for shard_id in _shards.keys():
		if shard_id != event.get("source_shard", ""):
			emit_cross_shard_event("auction_sync", event.get("source_shard", ""), event.get("payload", {}), _get_hlc_timestamp())

## === Cross-Shard State Pointers ===

## Register a cross-shard pointer for player-placed content.
## pointer_type: "house", "anchor", "guild_hall", etc.
## id: unique identifier for the content
## data: {shard_id, coord_x, coord_y, coord_z, owner, state_hash}
func register_cross_shard_pointer(pointer_type: String, id: String, data: Dictionary) -> void:
	if not _cross_shard_pointers.has(pointer_type):
		_cross_shard_pointers[pointer_type] = {}
	_cross_shard_pointers[pointer_type][id] = {
		"shard_id": data.get("shard_id", ""),
		"coord_x": data.get("coord_x", 0.0),
		"coord_y": data.get("coord_y", 0.0),
		"coord_z": data.get("coord_z", 0.0),
		"owner": data.get("owner", ""),
		"state_hash": data.get("state_hash", "")
	}
	_persist_state()
	GameLog.debug("CoordinatorService: Registered %s pointer %s on shard %s" % [pointer_type, id, data.get("shard_id", "")])

## Remove a cross-shard pointer
func remove_cross_shard_pointer(pointer_type: String, id: String) -> void:
	if _cross_shard_pointers.has(pointer_type) and _cross_shard_pointers[pointer_type].has(id):
		_cross_shard_pointers[pointer_type].erase(id)
		_persist_state()

## Get a cross-shard pointer by type and ID.
## Returns {shard_id, coord_x, coord_y, coord_z, owner, state_hash} or empty dict
func get_cross_shard_pointer(pointer_type: String, id: String) -> Dictionary:
	if _cross_shard_pointers.has(pointer_type) and _cross_shard_pointers[pointer_type].has(id):
		return _cross_shard_pointers[pointer_type][id]
	return {}

## Get all pointers of a given type
func get_pointers_by_type(pointer_type: String) -> Dictionary:
	if _cross_shard_pointers.has(pointer_type):
		return _cross_shard_pointers[pointer_type].duplicate()
	return {}

## Update the state_hash of a cross-shard pointer (for conflict detection)
func update_pointer_state_hash(pointer_type: String, id: String, new_hash: String) -> void:
	if _cross_shard_pointers.has(pointer_type) and _cross_shard_pointers[pointer_type].has(id):
		_cross_shard_pointers[pointer_type][id].state_hash = new_hash
		_persist_state()

## === Cross-Shard Player Presence ===

## Get online players for a shard. Returns {player_id: true, ...}
## Rate-limited to _RATE_LIMIT_MAX_QUERIES per _RATE_LIMIT_WINDOW_SEC per query_key
func get_online_players(shard_id: String = "") -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var result: Dictionary = {}

	if shard_id == "":
		# Return all online players
		for player_id in _player_presence.keys():
			var presence: Dictionary = _player_presence[player_id]
			if presence is Dictionary and presence.has("shard_id"):
				result[player_id] = true
		return result

	# Rate limit check
	var query_key := "players:%s" % shard_id
	if not _rate_limit_tracker.has(query_key):
		_rate_limit_tracker[query_key] = []
	var timestamps: Array = _rate_limit_tracker[query_key]
	# Remove old timestamps
	var filtered := []
	for ts in timestamps:
		if now - ts < _RATE_LIMIT_WINDOW_SEC:
			filtered.append(ts)
	_rate_limit_tracker[query_key] = filtered

	if filtered.size() >= _RATE_LIMIT_MAX_QUERIES:
		GameLog.warn("CoordinatorService: Rate limit exceeded for get_online_players on %s" % shard_id)
		return {}

	filtered.append(now)
	_rate_limit_tracker[query_key] = filtered

	# Build result
	for player_id in _player_presence.keys():
		var presence: Dictionary = _player_presence[player_id]
		if presence is Dictionary and presence.get("shard_id") == shard_id:
			result[player_id] = true

	return result

## Get the shard_id where a player currently is
func get_player_shard(player_id: String) -> String:
	return _player_shard_map.get(player_id, "")

## Get player presence info including last_seen timestamp
func get_player_presence(player_id: String) -> Dictionary:
	return _player_presence.get(player_id, {})

## Get last-seen timestamp for a player
func get_player_last_seen(player_id: String) -> int:
	var presence: Dictionary = _player_presence.get(player_id, {})
	if presence is Dictionary and presence.has("last_seen"):
		return presence["last_seen"]
	return 0

## === Guild/Faction Shared State ===

## Get shared guild data across all shards
func get_guild_state(guild_id: String) -> Dictionary:
	var ds := DictStore.new()
	var data: Variant = ds.get_kv("coordinator:guild:%s" % guild_id)
	if data is Dictionary:
		return data
	return {}

## Set shared guild state across all shards
func set_guild_state(guild_id: String, state: Dictionary) -> void:
	var ds := DictStore.new()
	ds.set_kv("coordinator:guild:%s" % guild_id, state)
	emit_cross_shard_event_auto("guild_update", "", {"guild_id": guild_id, "state": state})
	GameLog.debug("CoordinatorService: Updated guild %s state" % guild_id)

## === Auction House / Market Shared State ===

## Get auction listing by ID
func get_auction_listing(auction_id: String) -> Dictionary:
	var ds := DictStore.new()
	var data: Variant = ds.get_kv("coordinator:auction:%s" % auction_id)
	if data is Dictionary:
		return data
	return {}

## Set auction listing state
func set_auction_listing(auction_id: String, listing: Dictionary) -> void:
	var ds := DictStore.new()
	ds.set_kv("coordinator:auction:%s" % auction_id, listing)
	emit_cross_shard_event_auto("auction_update", "", {"auction_id": auction_id, "listing": listing})
	GameLog.debug("CoordinatorService: Updated auction %s" % auction_id)

## Get all active auction listings
func get_active_auctions() -> Array:
	var ds := DictStore.new()
	var keys: Array = ds.all_keys()
	var listings: Array = []
	for key in keys:
		if key.begins_with("coordinator:auction:"):
			var data: Variant = ds.get_kv(key)
			if data is Dictionary:
				listings.append(data)
	return listings

## === Serialization / Debug ===

## Get a summary of coordinator state for debugging
func get_summary() -> Dictionary:
	return {
		"initialized": _initialized,
		"shard_count": _shards.size(),
		"player_count": _player_shard_map.size(),
		"pointer_types": _cross_shard_pointers.keys(),
		"pending_events": _event_queue.size(),
		"hlc_counter": _hlc_counter,
		"shards": _shards.duplicate()
	}

## Export coordinator state as JSON-compatible Dictionary
func to_dict() -> Dictionary:
	return {
		"shards": _shards.duplicate(),
		"player_shard_map": _player_shard_map.duplicate(),
		"player_presence": _player_presence.duplicate(),
		"cross_shard_pointers": _cross_shard_pointers.duplicate(),
		"hlc_counter": _hlc_counter,
		"event_queue_size": _event_queue.size()
	}
