## EntityService - Entity registry and management
## Tracks all active entities in the world with unified spawn/despawn via EventBus
extends Node

var _entities: Dictionary = {}       # entity_id -> 
var _players: Dictionary = {}        # player_id ->  (subset)
var _enemies: Dictionary = {}       # entity_id ->  (subset)
var _npcs: Dictionary = {}           # entity_id ->  (subset)
var _entity_metadata: Dictionary = {}  # entity_id -> EventHub.SpawnMetadata

var _next_entity_id: int = 1

signal entity_registered(entity, metadata: EventHub.SpawnMetadata)
signal entity_unregistered(entity, metadata: EventHub.SpawnMetadata)
signal player_joined(player, metadata: EventHub.SpawnMetadata)
signal player_left(player, metadata: EventHub.SpawnMetadata)

func _ready() -> void:
	GameLog.info("EntityService: Ready")

## Register a new entity with spawn metadata
## Returns assigned entity_id
func register_entity(entity, metadata: EventHub.SpawnMetadata = null, id_override: String = "") -> String:

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
	
	entity_registered.emit(entity, metadata)
	EventHub.entity_spawned.emit(entity, metadata)
	
	GameLog.debug("EntityService: Registered %s as %s (type: %s)" % [
		entity.display_name, entity_id, metadata.get_spawn_type_string()])
	return entity_id

## Create default metadata based on entity type
func _create_default_metadata(entity) -> EventHub.SpawnMetadata:
	var spawn_type := EventHub.SpawnMetadata.SpawnType.NORMAL
	
	match entity.entity_type:
		Entity.EntityType.PLAYER:
			spawn_type = EventHub.SpawnMetadata.SpawnType.NORMAL
		Entity.EntityType.ENEMY:
			spawn_type = EventHub.SpawnMetadata.SpawnType.NORMAL
		Entity.EntityType.NPC:
			spawn_type = EventHub.SpawnMetadata.SpawnType.NPC
		_:
			spawn_type = EventHub.SpawnMetadata.SpawnType.NORMAL
	
	var metadata := EventHub.SpawnMetadata.new(spawn_type, entity.display_name, "", entity.global_position)
	metadata.level = entity.level
	metadata.faction = entity.faction
	return metadata

## Get spawn metadata for an entity
func get_entity_metadata(entity_id: String) -> EventHub.SpawnMetadata:
	return _entity_metadata.get(entity_id)

## Unregister an entity and emit unified despawn event
func unregister_entity(entity, reason: String = "despawn") -> void:
	if not entity.entity_id:
		return
	
	var entity_id: String = entity.entity_id
	var was_player := _players.has(entity_id)
	
	# Get stored metadata for despawn event
	var metadata: EventHub.SpawnMetadata = _entity_metadata.get(entity_id)
	if metadata == null:
		metadata = _create_default_metadata(entity)
	metadata.notification_message = reason  # Reuse for despawn reason
	
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
