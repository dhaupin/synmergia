## EntityService - Entity registry and management
##
## Tracks all active entities in the world with unified spawn/despawn via EventBus
extends Node

const Species = preload("res://core/schemas/species.gd")
const SpawnMetadata = preload("res://core/events/spawn_metadata.gd")
const Faction = preload("res://core/schemas/faction.gd")
# Entity is not an autoload (class_name only). EntityService uses
# `Entity.EntityType.X` in dispatch logic, which needs Entity's
# class_name registered at parse time. Preload it here.
const Entity = preload("res://core/entities/entity.gd")
const DictStore = preload("res://adapters/persistence/dict_store.gd")
# Spatial fragmenter (pure-function utility, class_name registered, no autoload).
const SpatialFragmenterScript = preload("res://core/frame/geometry/spatial_fragmenter.gd")
# Data sharding fragmenter (for fragment/weld of entity state).
const FragmenterScript = preload("res://core/frame/geometry/fragmenter.gd")
# T3 content-hash tree substrate (frame primitive, optional).
const T3Script = preload("res://core/frame/kv/t3.gd")
# NSC-9 bridge: connects NSC-9 spatial codes -> SpatialFragmenter -> T3 pipeline.
const Nsc9BridgeScript = preload("res://core/frame/geometry/nsc9_bridge.gd")
# NSC-9 math utilities (pure function for axis/encoding).
const Nsc9Script = preload("res://core/frame/math/nsc9.gd")
# Seed chain (frame primitive): canonical seed derivation (world-building.md
# sec. 18.8 Phase 0 item: seed field on all entity types).
const SeedChainScript = preload("res://core/frame/kv/seed_chain.gd")
const _kv_prefix := "entity:"
var _entities: Dictionary = {}       # entity_id ->
var _players: Dictionary = {}        # player_id ->  (subset)
var _enemies: Dictionary = {}       # entity_id ->  (subset)
var _npcs: Dictionary = {}           # entity_id ->  (subset)
var _entity_metadata: Dictionary = {}  # entity_id -> SpawnMetadata

var _next_entity_id: int = 1

# --- Spatial Fragmenter Integration (optional) ---
# Cached SpatialFragmenter instance (pure utility, stateless)
var _spatial_fragmenter: SpatialFragmenterScript = null
# Cached Fragmenter instance (for shard/weld of entity state)
var _fragmenter: FragmenterScript = null
# T3 content-hash tree instance for entity state storage (optional, lazy)
var _t3: Variant = null
# entity_id -> int spatial address
var _entity_spatial_addresses: Dictionary = {}
# entity_id -> int NSC-9 spatial code
var _entity_nsc9_codes: Dictionary = {}
# NSC-9 bridge instance (pure utility, stateless)
var _nsc9_bridge: Nsc9BridgeScript = null

signal entity_registered(entity, metadata: SpawnMetadata)
signal entity_unregistered(entity, metadata: SpawnMetadata)
signal player_joined(player, metadata: SpawnMetadata)
signal player_left(player, metadata: SpawnMetadata)
## Emitted when entity state is fragmented and stored in T3
signal entity_spatial_state_stored(entity_id: String, t3_hash: PackedByteArray)
## Emitted when entity state is reconstructed from T3
signal entity_spatial_state_restored(entity_id: String, state: Dictionary)

func _ready() -> void:
	GameLog.info("EntityService: Ready")
	_load_entity_metadata()
	_init_spatial_and_t3()

## Initialize SpatialFragmenter, Fragmenter, T3 instance, and NSC-9 bridge (optional).
## Graceful degradation: if any primitive is unavailable, spatial features
## are disabled but the rest of EntityService continues to function.
func _init_spatial_and_t3() -> void:
	if SpatialFragmenterScript:
		_spatial_fragmenter = SpatialFragmenterScript.new()
		GameLog.debug("EntityService: SpatialFragmenter initialized")
	else:
		GameLog.warn("EntityService: SpatialFragmenterScript not available; spatial features disabled")

	if FragmenterScript:
		_fragmenter = FragmenterScript.new()
		GameLog.debug("EntityService: Fragmenter initialized")
	else:
		GameLog.warn("EntityService: FragmenterScript not available; state fragmenting disabled")

	if T3Script:
		_t3 = T3Script.new()
		GameLog.debug("EntityService: T3 content-hash tree initialized")
	else:
		GameLog.warn("EntityService: T3Script not available; entity state persistence disabled")

	if Nsc9BridgeScript:
		_nsc9_bridge = Nsc9BridgeScript.new()
		GameLog.debug("EntityService: NSC-9 bridge initialized")
	else:
		GameLog.warn("EntityService: Nsc9BridgeScript not available; NSC-9 pipeline disabled")

## Compute a deterministic SpatialFragmenter address for an entity.
##
## Quantizes the entity's world position into 16-bit integer coordinates
## (quantum = 100 world units), derives depth from entity type/level, and
## maps the entity's faction to an icosahedral face code.
##
## Returns 0 if SpatialFragmenter is unavailable.
func _compute_spatial_address(entity) -> int:
	if _spatial_fragmenter == null:
		return 0

	var pos: Vector3 = entity.global_position if "global_position" in entity else Vector3.ZERO
	# Quantize to 100-unit cells to avoid floating-point seam cracks.
	var x: int = int(floor(pos.x / 100.0))
	var y: int = int(floor(pos.y / 100.0))
	var z: int = int(floor(pos.z / 100.0))

	# Depth: players sit at the coarsest level (0); NPCs/enemies subdivide
	# by level so higher-level entities occupy finer cells.
	var depth: int = 0
	if entity.entity_type == Entity.EntityType.PLAYER:
		depth = 0
	elif entity.entity_type in [Entity.EntityType.NPC, Entity.EntityType.ENEMY]:
		var lvl: int = int(entity.level) if "level" in entity else 1
		depth = clampi(lvl, 0, SpatialFragmenterScript.MAX_DEPTH)
	else:
		depth = 0

	# Face: derive from faction/team so allied entities cluster on the
	# same icosahedral face. Use team_id when set, else faction hash.
	var face: int = 0
	if "team_id" in entity and entity.team_id != 0:
		face = abs(entity.team_id) % 12
	elif "faction_id" in entity and entity.faction_id != "":
		face = abs(hash(entity.faction_id)) % 12
	elif "relation" in entity:
		face = int(entity.relation) % 12

	return _spatial_fragmenter.make_address(x, y, z, depth, face)

## Compute a deterministic NSC-9 code for an entity.
##
## Derives the NSC-9 spatial code from the entity's position
## (nearest icosahedral vertex -> spatial axis) and entity_id
## (deterministic sequence). Facility is derived from the entity's
## zone or entity_id hash.
## Returns -1 if NSC-9 bridge is unavailable or position is non-spatial.
func _compute_nsc9_code(entity) -> int:
	if _nsc9_bridge == null:
		return -1
	var entity_id: String = entity.entity_id if "entity_id" in entity else ""
	if entity_id == "":
		return -1
	var pos: Vector3 = entity.global_position if "global_position" in entity else Vector3.ZERO
	if pos == Vector3.ZERO:
		return -1

	# Derive facility from entity_id hash (0-999)
	var facility: int = abs(hash(entity_id)) % 1000

	# Derive spatial axis from nearest icosahedral vertex
	var lat: float = rad_to_deg(asin(clampf(pos.normalized().y, -1.0, 1.0)))
	var lon: float = rad_to_deg(atan2(pos.normalized().z, pos.normalized().x))
	var vertex: int = Nsc9Script.nearest_vertex(lat, lon)
	var axis: int = Nsc9Script.spatial_axis(vertex)

	# Derive sequence from entity_id hash (0-16M)
	var sequence: int = Nsc9Script.deterministic_seq(entity_id, "nsc9")

	return Nsc9Script.encode_int(facility, axis, sequence)

## Generate a deterministic T3 path for an entity's spatial fragment.
func _spatial_path_for_entity(entity_id: String, address: int) -> String:
	if _spatial_fragmenter == null:
		return "entity/%s" % entity_id
	return "entity/%s/%s" % [entity_id, _spatial_fragmenter.path_for_address(address)]

## Get the global T3 instance (creates on first access if T3Script is available).
func _get_t3() -> Variant:
	if _t3 != null:
		return _t3
	if T3Script:
		_t3 = T3Script.new()
		GameLog.debug("EntityService: Lazy-initialized T3 instance")
	return _t3

func register_entity(entity, metadata: SpawnMetadata = null, id_override: String = "") -> String:
	# SECURITY: Prevent duplicate entity IDs
	if id_override != "" and _entities.has(id_override):
		GameLog.error("EntityService ID %s already exists" % id_override)
		return ""

	# Create default metadata if not provided
	if metadata == null:
		metadata = _create_default_metadata(entity)

	var entity_id: String

	if id_override != "":
		entity_id = id_override
	else:
		entity_id = "entity_%d" % _next_entity_id
		_next_entity_id += 1

	entity.entity_id = entity_id
	_entities[entity_id] = entity

	# Store metadata for despawn
	metadata.entity_id = entity_id
	metadata.display_name = entity.display_name
	_entity_metadata[entity_id] = metadata

	# --- SPATIAL INTEGRATION ---
	# Generate spatial address for the entity (if SpatialFragmenter available)
	var spatial_address: int = _compute_spatial_address(entity)
	if spatial_address != 0:
		_entity_spatial_addresses[entity_id] = spatial_address
		GameLog.debug("EntityService: Generated spatial address for entity %s (0x%08x)" % [entity_id, spatial_address])

	# Generate NSC-9 code for the entity (if NSC-9 bridge available)
	var nsc9_code: int = _compute_nsc9_code(entity)
	if nsc9_code != -1:
		_entity_nsc9_codes[entity_id] = nsc9_code
		GameLog.debug("EntityService: Generated NSC-9 code for entity %s (0x%08x)" % [entity_id, nsc9_code])
		# Note: NSC-9 code can be stored in metadata for later retrieval
		metadata.nsc9_code = nsc9_code

	# Assign the per-entity seed (world-building.md sec. 18.8). Derived
	# deterministically from the owning player's frame seed (or the entity
	# id when no frame exists) through the canonical seed chain.
	if "seed" in entity:
		entity.seed = _derive_entity_seed(entity_id, entity)
	else:
		GameLog.warn("EntityService: entity type %s has no seed field; skipping seed assignment" % entity.get_class())

	# Store entity state in T3 (optional)
	var t3_hash: PackedByteArray = store_entity_state_in_t3(entity_id)
	if t3_hash.size() > 0:
		entity_spatial_state_stored.emit(entity_id, t3_hash)

	# Track by type
	if entity.entity_type == Entity.EntityType.PLAYER:
		_players[entity_id] = entity
		player_joined.emit(entity, metadata)
	elif entity.entity_type == Entity.EntityType.ENEMY:
		_enemies[entity_id] = entity
	elif entity.entity_type == Entity.EntityType.NPC:
		_npcs[entity_id] = entity

	_persist_entity_metadata(entity_id)
	# Mirror into CombatSystem's registry: hitbox sweeps iterate ONLY
	# entities registered here, so skipping this left every melee/AoE
	# attack hitting nothing (empty registered_entities). Tolerate
	# duplicates (re-registration overwrites via dictionary key).
	if CombatSystem:
		CombatSystem.register_entity(entity)
	entity_registered.emit(entity, metadata)
	EventHub.entity_spawned.emit(entity, metadata)

	GameLog.debug("EntityService: Registered %s as %s (type: %s)" % [
		entity.display_name, entity_id, metadata.get_spawn_type_string()])
	return entity_id

## Derive the deterministic per-entity seed (world-building.md sec. 18.8:
## "Add seed column / field to all entity types"). The seed-chain stack is
## [frame_seed]; with no owning player frame the entity_id bytes stand in
## for the frame seed so derivation stays deterministic across logins.
## Returns the hex-encoded 32-byte seed, or "" if the entity has no field.
func _derive_entity_seed(entity_id: String, entity) -> String:
	if entity == null or not "seed" in entity:
		return ""
	var frame_seed := PackedByteArray()
	if entity.entity_type == Entity.EntityType.PLAYER and FrameService:
		frame_seed = FrameService.get_frame_seed(entity_id)
	if frame_seed.is_empty():
		frame_seed = entity_id.to_utf8_buffer()
	var stack: Array[PackedByteArray] = [frame_seed]
	var derived: PackedByteArray = SeedChainScript.derive_seed(stack, "/entity/%s" % entity_id)
	if derived.is_empty():
		return ""
	return SeedChainScript.seed_hash(derived)

## Create default metadata based on entity type
func _create_default_metadata(entity) -> SpawnMetadata:
	var spawn_type := SpawnMetadata.SpawnType.NORMAL

	match entity.entity_type:
		Entity.EntityType.PLAYER:
			spawn_type = SpawnMetadata.SpawnType.NORMAL
		Entity.EntityType.ENEMY:
			spawn_type = SpawnMetadata.SpawnType.NORMAL
		Entity.EntityType.NPC:
			spawn_type = SpawnMetadata.SpawnType.NPC
		_:
			spawn_type = SpawnMetadata.SpawnType.NORMAL

	var metadata := SpawnMetadata.new(spawn_type, entity.display_name, "", entity.global_position)
	if "level" in entity:
		metadata.level = entity.level
	if "faction" in entity:
		metadata.faction = entity.faction
	return metadata

## Get spawn metadata for an entity
func get_entity_metadata(entity_id: String) -> SpawnMetadata:
	return _entity_metadata.get(entity_id)

## Unregister an entity and emit unified despawn event
func unregister_entity(entity, reason: String = "despawn") -> void:
	if not entity.entity_id:
		return

	var entity_id: String = entity.entity_id
	var was_player := _players.has(entity_id)

	# Get stored metadata for despawn event
	var metadata: SpawnMetadata = _entity_metadata.get(entity_id)
	if metadata == null:
		metadata = _create_default_metadata(entity)
	metadata.notification_message = reason  # Reuse for despawn reason

	_persist_entity_metadata(entity_id)
	# Keep the combat registry in sync for BOTH combatant families
	# (Entity subclasses and the PlayerController CharacterBody3D). The
	# old is_alive() gate skipped the player, leaving a stale entry that
	# kept eating hitbox sweeps after disconnect/despawn.
	if CombatSystem:
		CombatSystem.unregister_entity(entity)
	_entities.erase(entity_id)
	_players.erase(entity_id)
	_enemies.erase(entity_id)
	_npcs.erase(entity_id)
	_entity_metadata.erase(entity_id)
	_entity_spatial_addresses.erase(entity_id)
	# Clean up T3 state for this entity (optional)
	_clean_up_entity_t3_state(entity_id)

	entity_unregistered.emit(entity, metadata)
	EventHub.entity_despawned.emit(entity, metadata)

	if was_player:
		player_left.emit(entity, metadata)

	GameLog.debug("EntityService: Unregistered %s (reason: %s)" % [entity_id, reason])

## Unregister by entity ID
func unregister_by_id(entity_id: String, reason: String = "despawn") -> void:
	var entity = get_entity(entity_id)
	if entity:
		unregister_entity(entity, reason)

## Get entity by ID
func get_entity(entity_id: String) -> Variant:
	return _entities.get(entity_id)

## Get all entities
func get_all_entities() -> Array:
	return _entities.values()

## Get all players
func get_all_players() -> Array:
	return _players.values()

## Get all enemies
func get_all_enemies() -> Array:
	return _enemies.values()

## Get all NPCs
func get_all_npcs() -> Array:
	return _npcs.values()

## Get entities in radius (3D sphere)
func get_entities_in_radius(origin: Vector3, radius: float, entity_type: Entity.EntityType = Entity.EntityType.NPC) -> Array:
	var results: Array = []
	var target_dict: Dictionary

	match entity_type:
		Entity.EntityType.PLAYER:
			target_dict = _players
		Entity.EntityType.ENEMY:
			target_dict = _enemies
		Entity.EntityType.NPC:
			target_dict = _npcs
		_:
			target_dict = _entities

	for entity in target_dict.values():
		if not is_instance_valid(entity):
			continue
		if entity.global_position.distance_to(origin) <= radius:
			results.append(entity)

	return results

## Get closest entity to position
func get_closest_entity(origin: Vector3, entity_type: Entity.EntityType = Entity.EntityType.NPC, max_distance: float = -1.0) -> Variant:
	var target_dict: Dictionary

	match entity_type:
		Entity.EntityType.PLAYER:
			target_dict = _players
		Entity.EntityType.ENEMY:
			target_dict = _enemies
		Entity.EntityType.NPC:
			target_dict = _npcs
		_:
			target_dict = _entities

	var closest = null
	var closest_dist: float = -1.0

	for entity in target_dict.values():
		if not is_instance_valid(entity):
			continue
		var dist: float = entity.global_position.distance_to(origin)
		if dist < closest_dist or closest_dist < 0:
			if max_distance < 0 or dist <= max_distance:
				closest = entity
				closest_dist = dist

	return closest

## Get entities by faction
func get_entities_by_faction(faction: Faction) -> Array:
	var results: Array = []
	for entity in _entities.values():
		if not is_instance_valid(entity):
			continue
		if entity.faction == faction:
			results.append(entity)
	return results

## Get entities by species
func get_entities_by_species(species_id: String) -> Array:
	var results: Array = []
	for entity in _entities.values():
		if not is_instance_valid(entity):
			continue
		if "species_id" in entity and entity.species_id == species_id:
			results.append(entity)
	return results

## Check if entity is ally of another
func is_ally(entity1, entity2) -> bool:
	# Same team
	if entity1.team_id != 0 and entity1.team_id == entity2.team_id:
		return true

	# Same faction
	if entity1.faction == entity2.faction:
		return true

	# Check species alliance
	if "species" in entity1 and "species" in entity2:
		var species1: Species = entity1.species
		var species2: Species = entity2.species
		if species1 and species2:
			if species1.allied_species.has(species2.id):
				return true

	return false

## Check if entity is enemy of another
func is_enemy(entity1, entity2) -> bool:
	# Different teams (if teams are set)
	if entity1.team_id != 0 and entity2.team_id != 0:
		if entity1.team_id != entity2.team_id:
			return true

	# Hostile factions
	if entity1.faction == Faction.HOSTILE or entity2.faction == Faction.HOSTILE:
		return true

	# Check species hostility
	if "species" in entity1 and "species" in entity2:
		var species1: Species = entity1.species
		var species2: Species = entity2.species
		if species1 and species2:
			if species1.hostile_species.has(species2.id):
				return true

	return false

## Get entity count
func get_entity_count() -> int:
	return _entities.size()

func get_player_count() -> int:
	return _players.size()

func get_enemy_count() -> int:
	return _enemies.size()

func get_npc_count() -> int:
	return _npcs.size()

## Clear all entities (for server reset)
func clear_all() -> void:
	var entities_to_remove = _entities.values()
	_entities.clear()
	_players.clear()
	_enemies.clear()
	_npcs.clear()

	for entity in entities_to_remove:
		if is_instance_valid(entity):
			entity.queue_free()

	_next_entity_id = 1
	GameLog.info("EntityService: Cleared all entities")

func _metadata_to_dict(metadata: SpawnMetadata) -> Dictionary:
	return {
		"spawn_type": metadata.spawn_type,
		"entity_id": metadata.entity_id,
		"display_name": metadata.display_name,
		"zone_id": metadata.zone_id,
		"position_x": metadata.position.x,
		"position_y": metadata.position.y,
		"position_z": metadata.position.z,
		"spawner_entity_id": metadata.spawner_entity_id,
		"spawn_point_id": metadata.spawn_point_id,
		"level": metadata.level,
		"tags": metadata.tags,
		"quest_id": metadata.quest_id,
		"notification_enabled": metadata.notification_enabled,
		"notification_scopes": metadata.notification_scopes,
		"notification_message": metadata.notification_message,
		"notification_priority": metadata.notification_priority,
	}

func _metadata_from_dict(data: Dictionary) -> SpawnMetadata:
	var metadata := SpawnMetadata.new()
	metadata.spawn_type = data.get("spawn_type", 0)
	metadata.entity_id = data.get("entity_id", "")
	metadata.display_name = data.get("display_name", "")
	metadata.zone_id = data.get("zone_id", "")
	metadata.position = Vector3(
		data.get("position_x", 0.0),
		data.get("position_y", 0.0),
		data.get("position_z", 0.0)
	)
	metadata.spawner_entity_id = data.get("spawner_entity_id", "")
	metadata.spawn_point_id = data.get("spawn_point_id", "")
	metadata.level = data.get("level", 1)
	metadata.tags = data.get("tags", [])
	metadata.quest_id = data.get("quest_id", "")
	metadata.notification_enabled = data.get("notification_enabled", false)
	metadata.notification_scopes = data.get("notification_scopes", [])
	metadata.notification_message = data.get("notification_message", "")
	metadata.notification_priority = data.get("notification_priority", 0)
	return metadata

func _load_entity_metadata() -> void:
	var store := DictStore.new()
	_entity_metadata = {}
	var keys: Array = store.all_keys()
	var meta_keys: Array = []
	for key in keys:
		if key.begins_with(_kv_prefix):
			meta_keys.append(key)
	
	if not meta_keys.is_empty():
		var results: Dictionary = store.get_many(meta_keys)
		for key in meta_keys:
			var entity_id: String = key.substr(_kv_prefix.length())
			var data: Dictionary = results.get(key, {})
			if data.is_empty():
				continue
			var metadata := _metadata_from_dict(data)
			metadata.entity_id = entity_id
			_entity_metadata[entity_id] = metadata

func _persist_entity_metadata(entity_id: String) -> void:
	var store := DictStore.new()
	var key: String = _kv_prefix + entity_id
	if not _entity_metadata.has(entity_id):
		store.erase(key)
		return
	var metadata: SpawnMetadata = _entity_metadata[entity_id]
	var data := _metadata_to_dict(metadata)
	if data.is_empty():
		store.erase(key)
	else:
		store.set_kv(key, data)


func persist_all_metadata() -> void:
	var store := DictStore.new()
	var entries: Dictionary = {}
	for entity_id in _entity_metadata.keys():
		var key: String = _kv_prefix + entity_id
		var metadata: SpawnMetadata = _entity_metadata[entity_id]
		var data := _metadata_to_dict(metadata)
		if not data.is_empty():
			entries[key] = data
	if not entries.is_empty():
		store.set_batch(entries)


## Fragments entity state and stores it in the T3 content-hash tree.
## Returns the T3 hash of the stored node, or empty PackedByteArray if unavailable.
func store_entity_state_in_t3(entity_id: String) -> PackedByteArray:
	if _t3 == null:
		_t3 = _get_t3()
	if _t3 == null:
		return PackedByteArray()
	if _spatial_fragmenter == null:
		return PackedByteArray()
	if _fragmenter == null:
		return PackedByteArray()

	var entity = _entities.get(entity_id)
	if entity == null:
		return PackedByteArray()

	var address: int = _entity_spatial_addresses.get(entity_id, 0)
	if address == 0:
		address = _compute_spatial_address(entity)
		if address == 0:
			return PackedByteArray()
		_entity_spatial_addresses[entity_id] = address

	var path: String = _spatial_path_for_entity(entity_id, address)

	# Build entity state snapshot
	var state := {
		"entity_id": entity_id,
		"display_name": entity.display_name,
		"entity_type": entity.entity_type,
		"level": entity.level if "level" in entity else 1,
		"faction": entity.faction if "faction" in entity else "",
		"position_x": entity.global_position.x if "global_position" in entity else 0.0,
		"position_y": entity.global_position.y if "global_position" in entity else 0.0,
		"position_z": entity.global_position.z if "global_position" in entity else 0.0,
		"health": entity.health if "health" in entity else 0,
		"max_health": entity.max_health if "max_health" in entity else 0,
		"timestamp": Time.get_unix_time_from_system()
	}

	# Fragment the state data
	var fragments: Array = _fragmenter.fragment(state, 5)
	if fragments.is_empty():
		return PackedByteArray()

	# Store each fragment as a separate T3 node under the entity path
	var root_hash: PackedByteArray = PackedByteArray()
	for i in range(fragments.size()):
		var frag: Dictionary = fragments[i]
		var frag_path: String = "%s/frag_%d" % [path, i]
		var metadata: Dictionary = {
			"fragment_index": i,
			"total_fragments": fragments.size(),
			"checksum": frag.get("checksum", 0),
			"size": frag.get("size", 0),
			"data": frag.get("data", "")
		}
		var frag_hash: PackedByteArray = _spatial_fragmenter.store_fragment_in_t3(_t3, frag_path, address, metadata)
		if frag_hash.size() > 0:
			root_hash = frag_hash

	GameLog.debug("EntityService: Stored spatial state for entity %s at %s (hash: %s)" % [entity_id, path, root_hash.hex_encode()])
	return root_hash


## Reconstructs entity state from T3 content-hash tree.
## Returns the reconstructed state dictionary, or empty Dictionary if unavailable.
func restore_entity_state_from_t3(entity_id: String) -> Dictionary:
	if _t3 == null:
		_t3 = _get_t3()
	if _t3 == null:
		return {}
	if _spatial_fragmenter == null:
		return {}
	if _fragmenter == null:
		return {}

	var address: int = _entity_spatial_addresses.get(entity_id, 0)
	if address == 0:
		var entity = _entities.get(entity_id)
		if entity == null:
			return {}
		address = _compute_spatial_address(entity)
		if address == 0:
			return {}
		_entity_spatial_addresses[entity_id] = address

	var path: String = _spatial_path_for_entity(entity_id, address)

	# Query T3 for all fragments under this path
	var results: Array[Dictionary] = _spatial_fragmenter.query_spatial_tree(_t3, path)
	if results.is_empty():
		GameLog.debug("EntityService: No spatial fragments found for entity %s at %s" % [entity_id, path])
		return {}

	# Collect fragment data from T3 metadata
	var fragment_data: Array = []
	for result in results:
		var metadata: Dictionary = result.get("metadata", {})
		if metadata.is_empty():
			continue
		var frag_idx: int = metadata.get("fragment_index", 0)
		fragment_data.append({
			"shard": frag_idx,
			"data": metadata.get("data", "")
		})

	var welded: String = _fragmenter.weld(fragment_data)
	if welded == "":
		return {}

	var parsed: Variant = JSON.parse_string(welded)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}

	GameLog.debug("EntityService: Restored spatial state for entity %s from %s" % [entity_id, path])
	entity_spatial_state_restored.emit(entity_id, parsed)
	return parsed


## Shard entity state using lattice keys for distributed storage.
## Returns Array[Dictionary] with shard, data, size, checksum, and lattice_key.
func _shard_entity_state(entity_id: String, state: Dictionary) -> Array[Dictionary]:
	if _fragmenter == null:
		return []
	var sequence: int = entity_id.hash()
	var keys: Array[String] = _fragmenter.derive_lattice_keys(sequence, 5)
	var fragments: Array[Dictionary] = _fragmenter.fragment(state, 5)
	for i in range(fragments.size()):
		fragments[i]["lattice_key"] = keys[i] if i < keys.size() else ""
	return fragments

## Restore entity state from fragments.
## Returns the reconstructed state dictionary.
func _restore_entity_state(entity_id: String, fragments: Array[Dictionary]) -> Dictionary:
	if _fragmenter == null:
		return {}
	var welded: String = _fragmenter.weld(fragments)
	if welded == "":
		return {}
	var parsed: Variant = JSON.parse_string(welded)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


## Cleans up T3 state for an entity (called on unregister).
func _clean_up_entity_t3_state(entity_id: String) -> void:
	if _t3 == null or _spatial_fragmenter == null:
		return

	var address: int = _entity_spatial_addresses.get(entity_id, 0)
	if address == 0:
		return

	var path: String = _spatial_path_for_entity(entity_id, address)

	# Delete all fragments under this entity's path
	var results: Array[Dictionary] = _spatial_fragmenter.query_spatial_tree(_t3, path)
	for result in results:
		var node_path: String = result.get("path", "")
		if node_path != "":
			var command := {
				"type": "delete",
				"path": node_path
			}
			if TickService:
				TickService.queue_state_command(command)
			else:
				# Fallback for tests/early boot
				_t3.delete(node_path)

	GameLog.debug("EntityService: Cleaned up T3 state for entity %s at %s" % [entity_id, path])

## Public API: Restores entity state from T3 and emits signal.
func restore_entity_state(entity_id: String) -> Dictionary:
	var parsed: Dictionary = restore_entity_state_from_t3(entity_id)
	entity_spatial_state_restored.emit(entity_id, parsed)
	return parsed

## Public API: Gets the NSC-9 spatial code for an entity from the cache.
func get_entity_nsc9_code(entity_id: String) -> int:
	if _nsc9_bridge == null:
		return -1
	return _entity_nsc9_codes.get(entity_id, -1)
