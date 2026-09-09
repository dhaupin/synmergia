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
const _kv_prefix := "entity:"
var _entities: Dictionary = {}       # entity_id ->
var _players: Dictionary = {}        # player_id ->  (subset)
var _enemies: Dictionary = {}       # entity_id ->  (subset)
var _npcs: Dictionary = {}           # entity_id ->  (subset)
var _entity_metadata: Dictionary = {}  # entity_id -> SpawnMetadata

var _next_entity_id: int = 1

signal entity_registered(entity, metadata: SpawnMetadata)
signal entity_unregistered(entity, metadata: SpawnMetadata)
signal player_joined(player, metadata: SpawnMetadata)
signal player_left(player, metadata: SpawnMetadata)

func _ready() -> void:
	GameLog.info("EntityService: Ready")
	_load_entity_metadata()

## Register a new entity with spawn metadata
## Returns assigned entity_id
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

	# Track by type
	if entity.entity_type == Entity.EntityType.PLAYER:
		_players[entity_id] = entity
		player_joined.emit(entity, metadata)
	elif entity.entity_type == Entity.EntityType.ENEMY:
		_enemies[entity_id] = entity
	elif entity.entity_type == Entity.EntityType.NPC:
		_npcs[entity_id] = entity

	_persist_entity_metadata(entity_id)
	entity_registered.emit(entity, metadata)
	EventHub.entity_spawned.emit(entity, metadata)

	GameLog.debug("EntityService: Registered %s as %s (type: %s)" % [
		entity.display_name, entity_id, metadata.get_spawn_type_string()])
	return entity_id

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
	metadata.level = entity.level
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
	_entities.erase(entity_id)
	_players.erase(entity_id)
	_enemies.erase(entity_id)
	_npcs.erase(entity_id)
	_entity_metadata.erase(entity_id)

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
	for key in store.all_keys():
		if not key.begins_with(_kv_prefix):
			continue
		var entity_id := key.substr(_kv_prefix.length())
		var data := store.get(key)
		if data.is_empty():
			continue
		var metadata := _metadata_from_dict(data)
		metadata.entity_id = entity_id
		_entity_metadata[entity_id] = metadata

func _persist_entity_metadata(entity_id: String) -> void:
	var store := DictStore.new()
	var key := _kv_prefix + entity_id
	if not _entity_metadata.has(entity_id):
		store.erase(key)
		return
	var metadata: SpawnMetadata = _entity_metadata[entity_id]
	var data := _metadata_to_dict(metadata)
	if data.is_empty():
		store.erase(key)
	else:
		store.set(key, data)
