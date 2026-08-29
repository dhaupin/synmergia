## SpawnService - Enemy/NPC spawn management
## Handles spawn points, respawn timers, spawn caps, and dynamic spawning
extends Node

# Spawn points organized by zone (zone_id -> [SpawnPoint])
var _spawn_points: Dictionary = {}

# Active spawn timers (spawn_point_id -> time_until_spawn)
var _spawn_timers: Dictionary = {}

# Spawned entities (spawn_point_id -> [entity_ids])
var _spawned_entities: Dictionary = {}

# World bosses (boss_id -> )
var _world_bosses: Dictionary = {}

# Spawn point schema
class SpawnPoint:
	var id: String
	var zone_id: String
	var position: Vector3
	var spawn_radius: float
	var enemy_template_id: String
	var enemy_data: EnemyData
	var species_id: String	# Links to Species for faction relationships
	var respawn_time: float	 # Base respawn time in seconds
	var min_enemies: int		 # Min spawned at this point
	var max_enemies: int		 # Max spawned at this point
	var current_count: int	 # Currently spawned
	var spawn_type: EnemyData.EnemyType
	var is_active: bool = true
	
	# Dynamic scaling
	var spawn_multiplier: float = 1.0	 # 1.0 = normal, 2.0 = double during events
	
	func _init(
		p_id: String,
		p_zone_id: String,
		p_position: Vector3,
		p_enemy_template: String,
	\tp_species_id: String = "",
		p_respawn: float = 60.0,
		p_min: int = 1,
		p_max: int = 1,
		p_type: EnemyData.EnemyType = EnemyData.EnemyType.NORMAL
	) -> void:
		id = p_id
		zone_id = p_zone_id
		position = p_position
		spawn_radius = 3.0
		enemy_template_id = p_enemy_template
	\tspecies_id = p_species_id
		respawn_time = p_respawn
		min_enemies = p_min
		max_enemies = p_max
		current_count = 0
		spawn_type = p_type
	
	func get_spawn_position() -> Vector3:
		var offset := Vector3(
			randf_range(-spawn_radius, spawn_radius),
			0,
			randf_range(-spawn_radius, spawn_radius)
		)
		return position + offset
	
	func should_spawn() -> bool:
		if not is_active:
			return false
		var effective_max = int(max_enemies * spawn_multiplier)
		return current_count < effective_max

## SpawnService-specific signals for spawn-point-aware listeners
## These complement the unified EventHub.entity_spawned with spawn-point context
signal spawn_point_registered(spawn_point: Dictionary)
signal enemy_spawned(entity, spawn_point_id: String, metadata: EventHub.SpawnMetadata)
signal enemy_despawned(entity, spawn_point_id: String, metadata: EventHub.SpawnMetadata)
signal boss_spawned(entity, boss_name: String, metadata: EventHub.SpawnMetadata)
signal npc_spawned(npc, npc_id: String, metadata: EventHub.SpawnMetadata)
signal spawn_point_cleared(spawn_point_id: String)

func _ready() -> void:
	GameLog.info("SpawnService: Ready")

## Register a spawn point
func register_spawn_point(
	zone_id: String,
	position: Vector3,
	enemy_template_id: String,
				species_id: String = "",
	respawn_time: float = 60.0,
	min_enemies: int = 1,
	max_enemies: int = 1,
	enemy_type: EnemyData.EnemyType = EnemyData.EnemyType.NORMAL
) -> String:
	var spawn_point_id = "spawn_%s_%d" % [zone_id, _spawn_timers.size()]
	
	var spawn_point := SpawnPoint.new(
		spawn_point_id,
		zone_id,
		position,
		enemy_template_id,
		species_id,
		respawn_time,
		min_enemies,
		max_enemies,
		enemy_type
	)
	
	# Load enemy data
	var data_service = DataService
	if data_service:
		spawn_point.enemy_data = data_service.get_enemy(enemy_template_id)
	
	if not _spawn_points.has(zone_id):
		_spawn_points[zone_id] = []
	_spawn_points[zone_id].append(spawn_point)
	_spawned_entities[spawn_point_id] = []
	
	spawn_point_registered.emit({
		"id": spawn_point_id,
		"zone_id": zone_id,
		"position": position,
		"enemy_template": enemy_template_id
	})
	
	GameLog.debug("SpawnService: Registered spawn point %s in zone %s" % [spawn_point_id, zone_id])
	return spawn_point_id

## Register spawn point from config
func register_spawn_point_from_config(config: Dictionary) -> String:
	return register_spawn_point(
		config.get("zone_id", ""),
		config.get("position", Vector3.ZERO),
		config.get("enemy_template_id", ""),
		config.get("respawn_time", 60.0),
		config.get("min_enemies", 1),
		config.get("max_enemies", 1),
		config.get("enemy_type", EnemyData.EnemyType.NORMAL)
	)

## Get spawn points for a zone
func get_zone_spawn_points(zone_id: String) -> Array:
	return _spawn_points.get(zone_id, [])

## Spawn enemy at a spawn point
func spawn_enemy(spawn_point_id: String) -> Variant:
	var spawn_point = _get_spawn_point(spawn_point_id)
	if spawn_point == null or not spawn_point.should_spawn():
		return null
	
	# Check proximity to players
	if _is_spawn_point_safe(spawn_point) == false:
		return null	 # Players too close, delay spawn
	
	# Create enemy entity
	var enemy = _create_enemy(spawn_point)
	if enemy == null:
		return null
	
	# Track spawned entity
	spawn_point.current_count += 1
	_spawned_entities[spawn_point_id].append(enemy.entity_id)
	
	# Create spawn metadata with position for zone notifications
	var metadata := EventHub.SpawnMetadata.enemy(
		enemy.display_name,
		spawn_point.zone_id,
		spawn_point.position,
		spawn_point_id,
		enemy.level
	)
	metadata.faction = enemy.faction
	
	# Apply elite/boss notification settings based on enemy type
	if spawn_point.spawn_type == EnemyData.EnemyType.ELITE:
		metadata = EventHub.SpawnMetadata.elite(
			enemy.display_name,
			spawn_point.zone_id,
			spawn_point.position,
			spawn_point_id,
			enemy.level
		)
	elif spawn_point.spawn_type == EnemyData.EnemyType.BOSS:
		metadata = EventHub.SpawnMetadata.boss(
			enemy.display_name,
			spawn_point.zone_id,
			spawn_point.position,
			enemy.level
		)
	
	# Register with EntityService (emits EventHub.entity_spawned with metadata)
	var entity_service = EntityService
	if entity_service:
		entity_service.register_entity(enemy, metadata)
	
	# Register with TargetingManager
	var targeting_manager = TargetingManager
	if targeting_manager:
		targeting_manager.register_targetable(
			enemy.entity_id,
			"enemy",
			enemy,
			enemy.display_name,
			spawn_point.get_spawn_position(),
			enemy.entity_type
		)
	
	# Position enemy
	enemy.global_position = spawn_point.get_spawn_position()
	
	# Add to zone
	var zone_manager = ZoneManager
	if zone_manager:
		var zone = zone_manager.get_zone(spawn_point.zone_id)
		if zone:
			zone_manager.entity_enter_zone(enemy, zone)
	
	# Emit service-specific signal with spawn point context
	enemy_spawned.emit(enemy, spawn_point_id, metadata)
	GameLog.debug("SpawnService: Spawned %s at %s" % [enemy.display_name, spawn_point_id])
	
	return enemy

## Spawn boss
func spawn_boss(
	boss_template_id: String,
	position: Vector3,
	zone_id: String,
	boss_name: String = "",
	alert_scopes: Array = []
) -> Variant:
	var data_service = DataService
	if data_service == null:
		return null
	
	var boss_data = data_service.get_enemy(boss_template_id)
	if boss_data == null:
		GameLog.warn("SpawnService: Boss template %s not found" % boss_template_id)
		return null
	
	var boss = SynmergiaEntity.new()
	boss.display_name = boss_name if boss_name != "" else boss_data.display_name
	boss.entity_type = SynmergiaEntity.EntityType.ENEMY
	boss.level = boss_data.level
	boss.faction = SynmergiaEntity.Relation.HOSTILE
	boss.faction_id = boss_data.faction
	
	# Apply stats from template
	boss.stats["strength"] = boss_data.strength
	boss.stats["agility"] = boss_data.agility
	boss.stats["intelligence"] = boss_data.intelligence
	boss.stats["vitality"] = boss_data.vitality
	
	boss.max_health = boss_data.health
	boss.current_health = boss_data.health
	
	# Create spawn metadata with notification settings
	var metadata := EventHub.SpawnMetadata.world_boss(boss.display_name, zone_id, position, boss.level)
	metadata.faction = boss.faction
	if alert_scopes.size() > 0:
		metadata.notification_enabled = true
		metadata.notification_scopes = alert_scopes
	
	# Register with EntityService (emits EventHub.entity_spawned with metadata)
	var entity_service = EntityService
	if entity_service:
		entity_service.register_entity(boss, metadata)
	
	# Register with TargetingManager
	var targeting_manager = TargetingManager
	if targeting_manager:
		targeting_manager.register_targetable(
			boss.entity_id,
			"enemy",
			boss,
			boss.display_name,
			position,
			boss.entity_type
		)
	
	boss.global_position = position
	_world_bosses[boss.entity_id] = boss
	
	# Add to zone
	var zone_manager = ZoneManager
	if zone_manager:
		var zone = zone_manager.get_zone(zone_id)
		if zone:
			zone_manager.entity_enter_zone(boss, zone)
	
	# Emit service-specific signal with spawn context
	boss_spawned.emit(boss, boss.display_name, metadata)
	GameLog.info("SpawnService: Spawned BOSS %s at %s" % [boss.display_name, str(position)])
	
	# Notification is now handled by NotificationService listening to EventHub.entity_spawned
	
	return boss

## Despawn a world boss
func despawn_boss(entity) -> void:
	if entity == null:
		return
	
	# Remove from world bosses
	_world_bosses.erase(entity.entity_id)
	
	# Remove from TargetingManager
	var targeting_manager = TargetingManager
	if targeting_manager:
		targeting_manager.unregister_targetable(entity.entity_id)
	
	# Remove from services
	var entity_service = EntityService
	if entity_service:
		entity_service.unregister_entity(entity)
	
	# Remove from world
	if is_instance_valid(entity):
		entity.queue_free()
	
	GameLog.info("SpawnService: Despawned boss %s" % entity.display_name)

## Spawn boss with server-wide alert (convenience method)
func spawn_world_boss(boss_template_id: String, position: Vector3, zone_id: String, boss_name: String = "") -> Variant:
	return spawn_boss(boss_template_id, position, zone_id, boss_name, [NotificationService.AlertScope.server_wide()])

## Spawn boss with zone + neighbors alert (convenience method)
func spawn_zone_boss(boss_template_id: String, position: Vector3, zone_id: String, boss_name: String = "", include_neighbors: bool = true) -> Variant:
	return spawn_boss(boss_template_id, position, zone_id, boss_name, [NotificationService.AlertScope.zone(zone_id, include_neighbors)])

## Spawn mini-boss with nearby alert only (convenience method)
func spawn_mini_boss(boss_template_id: String, position: Vector3, zone_id: String, boss_name: String = "", radius: float = 50.0) -> Variant:
	return spawn_boss(boss_template_id, position, zone_id, boss_name, [NotificationService.AlertScope.nearby(position, radius)])

## Despawn enemy
func despawn_enemy(entity) -> void:
	if entity == null:
		return
	
	# Find spawn point
	var spawn_point_id = _find_entity_spawn_point(entity.entity_id)
	var metadata: EventHub.SpawnMetadata = EntityService.get_entity_metadata(entity.entity_id) if EntityService else null
	
	if spawn_point_id != "":
		var spawn_point = _get_spawn_point(spawn_point_id)
		if spawn_point:
			spawn_point.current_count -= 1
			_spawned_entities[spawn_point_id].erase(entity.entity_id)
			
			# Start respawn timer
			_start_respawn_timer(spawn_point_id, spawn_point.respawn_time)
	
	# Emit service-specific despawn signal with metadata
	enemy_despawned.emit(entity, spawn_point_id, metadata)
	
	# Remove from TargetingManager
	var targeting_manager = TargetingManager
	if targeting_manager:
		targeting_manager.unregister_targetable(entity.entity_id)
	
	# Remove from services (emits EventHub.entity_despawned with metadata)
	var entity_service = EntityService
	if entity_service:
		entity_service.unregister_entity(entity, "spawn_despawn")
	
	# Remove from world
	if is_instance_valid(entity):
		entity.queue_free()

## Get spawn count for a zone
func get_zone_spawn_count(zone_id: String) -> int:
	var count = 0
	for spawn_point in _spawn_points.get(zone_id, []):
		count += spawn_point.current_count
	return count

## Get spawn cap for a zone
func get_zone_spawn_cap(zone_id: String) -> int:
	var cap = 0
	for spawn_point in _spawn_points.get(zone_id, []):
		cap += spawn_point.max_enemies
	return cap

## Check if zone is at spawn cap
func is_zone_at_cap(zone_id: String) -> bool:
	return get_zone_spawn_count(zone_id) >= get_zone_spawn_cap(zone_id)

## Set spawn multiplier (for events)
func set_spawn_multiplier(zone_id: String, multiplier: float) -> void:
	for spawn_point in _spawn_points.get(zone_id, []):
		spawn_point.spawn_multiplier = multiplier
	GameLog.info("SpawnService: Set spawn multiplier to %.1f for zone %s" % [multiplier, zone_id])

## Clear all spawns in a zone
func clear_zone_spawns(zone_id: String) -> void:
	for spawn_point in _spawn_points.get(zone_id, []):
		_clear_spawn_point(spawn_point)
	GameLog.info("SpawnService: Cleared all spawns in zone %s" % zone_id)

## Enable/disable spawn point
func set_spawn_point_active(spawn_point_id: String, active: bool) -> void:
	var spawn_point = _get_spawn_point(spawn_point_id)
	if spawn_point:
		spawn_point.is_active = active
		if not active:
			_spawn_timers.erase(spawn_point_id)

## Force spawn all spawn points in a zone
func force_spawn_zone(zone_id: String) -> int:
	var spawned = 0
	for spawn_point in _spawn_points.get(zone_id, []):
		while spawn_point.should_spawn():
			var enemy = spawn_enemy(spawn_point.id)
			if enemy == null:
				break
			spawned += 1
	return spawned

## Process spawn timers (call from _process)
func process_spawns(delta: float) -> void:
	var timers_to_remove: Array[String] = []
	
	for spawn_point_id in _spawn_timers:
		_spawn_timers[spawn_point_id] -= delta
		if _spawn_timers[spawn_point_id] <= 0:
			spawn_enemy(spawn_point_id)
			timers_to_remove.append(spawn_point_id)
	
	for spawn_point_id in timers_to_remove:
		_spawn_timers.erase(spawn_point_id)

# --- Private methods ---

func _get_spawn_point(spawn_point_id: String) -> SpawnPoint:
	for spawn_point_array in _spawn_points.values():
		for sp in spawn_point_array:
			if sp.id == spawn_point_id:
				return sp
	return null

func _find_entity_spawn_point(entity_id: String) -> String:
	for spawn_point_id in _spawned_entities:
		if _spawned_entities[spawn_point_id].has(entity_id):
			return spawn_point_id
	return ""

func _is_spawn_point_safe(spawn_point: SpawnPoint) -> bool:
	var zone_manager = ZoneManager
	if zone_manager == null:
		return true	 # No zone manager, assume safe
	
	var players = zone_manager.get_players_in_zone(spawn_point.zone_id)
	var safe_distance := spawn_point.spawn_radius + 30.0	# 30 units buffer
	
	for player in players:
		if spawn_point.position.distance_to(player.global_position) < safe_distance:
			return false
	return true

func _start_respawn_timer(spawn_point_id: String, respawn_time: float) -> void:
	_spawn_timers[spawn_point_id] = respawn_time

func _clear_spawn_point(spawn_point: SpawnPoint) -> void:
	var entities = _spawned_entities.get(spawn_point.id, [])
	for entity_id in entities:
		var entity_service = EntityService
		if entity_service:
			var entity = entity_service.get_entity(entity_id)
			if entity and is_instance_valid(entity):
				entity.queue_free()
	
	_spawned_entities[spawn_point.id].clear()
	spawn_point.current_count = 0
	_spawn_timers.erase(spawn_point.id)
	spawn_point_cleared.emit(spawn_point.id)

func _create_enemy(spawn_point: SpawnPoint) -> Variant:
	if spawn_point.enemy_data == null:
		GameLog.warn("SpawnService: No enemy data for template %s" % spawn_point.enemy_template_id)
		return null
	
	var enemy = SynmergiaEntity.new()
	enemy.display_name = spawn_point.enemy_data.display_name
	enemy.entity_type = SynmergiaEntity.EntityType.ENEMY
	enemy.level = spawn_point.enemy_data.level
	enemy.faction = SynmergiaEntity.Relation.HOSTILE
	enemy.faction_id = spawn_point.enemy_data.faction
	
	# Apply species if set
	var effective_species_id := spawn_point.species_id if spawn_point.species_id != "" else spawn_point.enemy_data.species_id
	if effective_species_id != "":
		var data_service = DataService
		if data_service:
			var species = data_service.get_species(effective_species_id)
			if species:
				enemy.apply_species(species)
	
	# Apply stats from template
	enemy.stats["strength"] = spawn_point.enemy_data.strength
	enemy.stats["agility"] = spawn_point.enemy_data.agility
	enemy.stats["intelligence"] = spawn_point.enemy_data.intelligence
	enemy.stats["vitality"] = spawn_point.enemy_data.vitality
	
	enemy.max_health = spawn_point.enemy_data.health
	enemy.current_health = spawn_point.enemy_data.health
	
	return enemy
## Spawn a Blacksmith NPC at a position
func spawn_blacksmith(
		zone_id: String,
		position: Vector3,
		npc_data_id: String = ""
) -> BlacksmithNPC:
		var blacksmith := BlacksmithNPC.new()
		
		# Load NPC data if provided
		var data_service = DataService
		if data_service and npc_data_id != "":
			var npc_data: NPCData = data_service.get_npc(npc_data_id)
			if npc_data:
				blacksmith.apply_data(npc_data)
		else:
			# Default values if no data provided
			blacksmith.display_name = "Blacksmith"
		
		blacksmith.entity_type = SynmergiaEntity.EntityType.NPC
		blacksmith.faction = SynmergiaEntity.Relation.FRIENDLY
		
		# Register with EntityService
		var entity_service = EntityService
		if entity_service:
			entity_service.register_entity(blacksmith)
		
		# Register with TargetingManager
		var targeting_manager = TargetingManager
		if targeting_manager:
			targeting_manager.register_targetable(
				blacksmith.entity_id,
				"npc",
				blacksmith,
				blacksmith.display_name,
				position,
				blacksmith.entity_type
			)
		
		# Position NPC
		blacksmith.global_position = position
		
		# Add to zone
		var zone_manager = ZoneManager
		if zone_manager:
			var zone = zone_manager.get_zone(zone_id)
			if zone:
				zone_manager.entity_enter_zone(blacksmith, zone)
		
		GameLog.info("SpawnService: Spawned Blacksmith '%s' at (%s) in zone %s" % [blacksmith.display_name, position, zone_id])
		# Note: EventHub.entity_spawned is already emitted by EntityService.register_entity()
		
		return blacksmith

## Spawn all blacksmiths for a zone (called during zone load)
func spawn_zone_blacksmiths(zone_id: String, zone_data: ZoneData) -> Array[BlacksmithNPC]:
		var blacksmiths: Array[BlacksmithNPC] = []
		
		# Check zone NPCs list for blacksmith entries
		if zone_data.npcs.size() > 0:
			for npc_id in zone_data.npcs:
				if npc_id.begins_with("blacksmith_"):
					var spawn_pos := zone_data.bind_point if zone_data.bind_point != Vector3.ZERO else zone_data.zone_center
					spawn_pos += Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))	 # Random offset
					var blacksmith := spawn_blacksmith(zone_id, spawn_pos, npc_id)
					if blacksmith:
						blacksmiths.append(blacksmith)
		
		# Auto-spawn in safe zones if no blacksmith defined
		if blacksmiths.is_empty() and zone_data.pvp_mode == ZoneData.PvPZoneMode.SAFE:
			var spawn_pos := zone_data.bind_point if zone_data.bind_point != Vector3.ZERO else zone_data.zone_center
			# Determine default NPC based on zone type
			var default_npc_id := "blacksmith_town_default"
			if zone_id.begins_with("outpost_"):
				default_npc_id = "blacksmith_outpost_default"
			elif zone_id.begins_with("village_") or zone_id.begins_with("hamlet_"):
				default_npc_id = "blacksmith_village_default"
			elif zone_id.begins_with("capital_"):
				default_npc_id = "blacksmith_capital_default"
			
			var blacksmith := spawn_blacksmith(zone_id, spawn_pos, default_npc_id)
			if blacksmith:
				blacksmiths.append(blacksmith)
		
		return blacksmiths

## Despawn an NPC
func despawn_npc(entity) -> void:
	if entity == null:
		return
	
	# Remove from TargetingManager
	var targeting_manager = TargetingManager
	if targeting_manager:
		targeting_manager.unregister_targetable(entity.entity_id)
	
	# Remove from services
	var entity_service = EntityService
	if entity_service:
		entity_service.unregister_entity(entity)
	
	# Remove from world
	if is_instance_valid(entity):
		entity.queue_free()
	
	GameLog.info("SpawnService: Despawned NPC %s" % entity.display_name)
