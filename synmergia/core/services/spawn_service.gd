## SpawnService - Enemy/NPC spawn management
## Handles spawn points, respawn timers, spawn caps, and dynamic spawning
class_name SpawnService
extends Node

# Spawn points organized by zone (zone_id -> [SpawnPoint])
var _spawn_points: Dictionary = {}

# Active spawn timers (spawn_point_id -> time_until_spawn)
var _spawn_timers: Dictionary = {}

# Spawned entities (spawn_point_id -> [entity_ids])
var _spawned_entities: Dictionary = {}

# World bosses (boss_id -> Entity)
var _world_bosses: Dictionary = {}

# Spawn point schema
class SpawnPoint:
	var id: String
	var zone_id: String
	var position: Vector3
	var spawn_radius: float
	var enemy_template_id: String
	var enemy_data: EnemyData
	var species_id: String  # Links to Species for faction relationships
	var respawn_time: float  # Base respawn time in seconds
	var min_enemies: int     # Min spawned at this point
	var max_enemies: int     # Max spawned at this point
	var current_count: int   # Currently spawned
	var spawn_type: EnemyData.EnemyType
	var is_active: bool = true
	
	# Dynamic scaling
	var spawn_multiplier: float = 1.0  # 1.0 = normal, 2.0 = double during events
	
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

signal spawn_point_registered(spawn_point: Dictionary)
signal enemy_spawned(entity: Entity, spawn_point_id: String)
signal enemy_despawned(entity: Entity, spawn_point_id: String)
signal boss_spawned(entity: Entity, boss_name: String)
signal spawn_point_cleared(spawn_point_id: String)

func _ready() -> void:
	Logger.info("SpawnService: Ready")

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
	
	Logger.debug("SpawnService: Registered spawn point %s in zone %s" % [spawn_point_id, zone_id])
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
func spawn_enemy(spawn_point_id: String) -> Entity:
	var spawn_point = _get_spawn_point(spawn_point_id)
	if spawn_point == null or not spawn_point.should_spawn():
		return null
	
	# Check proximity to players
	if _is_spawn_point_safe(spawn_point) == false:
		return null  # Players too close, delay spawn
	
	# Create enemy entity
	var enemy = _create_enemy(spawn_point)
	if enemy == null:
		return null
	
	# Track spawned entity
	spawn_point.current_count += 1
	_spawned_entities[spawn_point_id].append(enemy.entity_id)
	
	# Register with EntityService
	var entity_service = EntityService
	if entity_service:
		entity_service.register_entity(enemy)
	
	# Position enemy
	enemy.global_position = spawn_point.get_spawn_position()
	
	# Add to zone
	var zone_manager = ZoneManager
	if zone_manager:
		var zone = zone_manager.get_zone(spawn_point.zone_id)
		if zone:
			zone_manager.entity_enter_zone(enemy, zone)
	
	enemy_spawned.emit(enemy, spawn_point_id)
	EventBus.enemy_spawned.emit(enemy, spawn_point.position)
	Logger.debug("SpawnService: Spawned %s at %s" % [enemy.display_name, spawn_point_id])
	
	return enemy

## Spawn boss
func spawn_boss(
	boss_template_id: String,
	position: Vector3,
	zone_id: String,
	boss_name: String = "",
	alert_scopes: Array[NotificationService.AlertScope] = []
) -> Entity:
	var data_service = DataService
	if data_service == null:
		return null
	
	var boss_data = data_service.get_enemy(boss_template_id)
	if boss_data == null:
		Logger.warn("SpawnService: Boss template %s not found" % boss_template_id)
		return null
	
	var boss = Entity.new()
	boss.display_name = boss_name if boss_name != "" else boss_data.display_name
	boss.entity_type = Entity.EntityType.ENEMY
	boss.level = boss_data.level
	boss.faction = Entity.Faction.HOSTILE
	boss.faction_id = boss_data.faction
	
	# Apply stats from template
	boss.stats["strength"] = boss_data.strength
	boss.stats["agility"] = boss_data.agility
	boss.stats["intelligence"] = boss_data.intelligence
	boss.stats["vitality"] = boss_data.vitality
	
	boss.max_health = boss_data.health
	boss.current_health = boss_data.health
	
	# Register
	var entity_service = EntityService
	if entity_service:
		entity_service.register_entity(boss)
	
	boss.global_position = position
	_world_bosses[boss.entity_id] = boss
	
	# Add to zone
	var zone_manager = ZoneManager
	var zone = null
	if zone_manager:
		zone = zone_manager.get_zone(zone_id)
		if zone:
			zone_manager.entity_enter_zone(boss, zone)
	
	boss_spawned.emit(boss, boss.display_name)
	EventBus.boss_spawned.emit(boss, boss.display_name)
	Logger.info("SpawnService: Spawned BOSS %s at %s" % [boss.display_name, str(position)])
	
	# Send alert based on scopes
	if alert_scopes.size() > 0:
		var notification_service = NotificationService
		if notification_service and zone:
			var message = "WORLD BOSS: %s has appeared in %s!" % [boss.display_name, zone.display_name]
			notification_service.broadcast_alert(
				message,
				alert_scopes,
				NotificationService.NotificationType.WORLD_EVENT,
				NotificationService.Priority.HIGH,
				NotificationService.DisplayLocation.CENTER_SCREEN,
				NotificationService.SoundType.NOTIFICATION,
				{"boss_name": boss.display_name, "zone_id": zone.id}
			)
	
	return boss

## Spawn boss with server-wide alert (convenience method)
func spawn_world_boss(boss_template_id: String, position: Vector3, zone_id: String, boss_name: String = "") -> Entity:
	return spawn_boss(boss_template_id, position, zone_id, boss_name, [NotificationService.AlertScope.server_wide()])

## Spawn boss with zone + neighbors alert (convenience method)
func spawn_zone_boss(boss_template_id: String, position: Vector3, zone_id: String, boss_name: String = "", include_neighbors: bool = true) -> Entity:
	return spawn_boss(boss_template_id, position, zone_id, boss_name, [NotificationService.AlertScope.zone(zone_id, include_neighbors)])

## Spawn mini-boss with nearby alert only (convenience method)
func spawn_mini_boss(boss_template_id: String, position: Vector3, zone_id: String, boss_name: String = "", radius: float = 50.0) -> Entity:
	return spawn_boss(boss_template_id, position, zone_id, boss_name, [NotificationService.AlertScope.nearby(position, radius)])

## Despawn enemy
func despawn_enemy(entity: Entity) -> void:
	if entity == null:
		return
	
	# Find spawn point
	var spawn_point_id = _find_entity_spawn_point(entity.entity_id)
	if spawn_point_id != "":
		var spawn_point = _get_spawn_point(spawn_point_id)
		if spawn_point:
			spawn_point.current_count -= 1
			_spawned_entities[spawn_point_id].erase(entity.entity_id)
			
			# Start respawn timer
			_start_respawn_timer(spawn_point_id, spawn_point.respawn_time)
		
		enemy_despawned.emit(entity, spawn_point_id)
		EventBus.enemy_despawned.emit(entity)
	
	# Remove from services
	var entity_service = EntityService
	if entity_service:
		entity_service.unregister_entity(entity)
	
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
	Logger.info("SpawnService: Set spawn multiplier to %.1f for zone %s" % [multiplier, zone_id])

## Clear all spawns in a zone
func clear_zone_spawns(zone_id: String) -> void:
	for spawn_point in _spawn_points.get(zone_id, []):
		_clear_spawn_point(spawn_point)
	Logger.info("SpawnService: Cleared all spawns in zone %s" % zone_id)

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
		return true  # No zone manager, assume safe
	
	var players = zone_manager.get_players_in_zone(spawn_point.zone_id)
	var safe_distance := spawn_point.spawn_radius + 30.0  # 30 units buffer
	
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

func _create_enemy(spawn_point: SpawnPoint) -> Entity:
	if spawn_point.enemy_data == null:
		Logger.warn("SpawnService: No enemy data for template %s" % spawn_point.enemy_template_id)
		return null
	
	var enemy = Entity.new()
	enemy.display_name = spawn_point.enemy_data.display_name
	enemy.entity_type = Entity.EntityType.ENEMY
	enemy.level = spawn_point.enemy_data.level
	enemy.faction = Entity.Faction.HOSTILE
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
		name: String = "Blacksmith",
		location_type: BlacksmithNPC.LocationType = BlacksmithNPC.LocationType.TOWN
) -> BlacksmithNPC:
		var blacksmith := BlacksmithNPC.new()
		blacksmith.npc_name = name
		blacksmith.display_name = name
		blacksmith.location_type = location_type
		blacksmith.entity_type = Entity.EntityType.NPC
		blacksmith.faction = Entity.Faction.FRIENDLY
		
		# Register with EntityService
		var entity_service = EntityService
		if entity_service:
			entity_service.register_entity(blacksmith)
		
		# Position NPC
		blacksmith.global_position = position
		
		# Add to zone
		var zone_manager = ZoneManager
		if zone_manager:
			var zone = zone_manager.get_zone(zone_id)
			if zone:
				zone_manager.entity_enter_zone(blacksmith, zone)
		
		Logger.info("SpawnService: Spawned Blacksmith '%s' at (%s) in zone %s" % [name, position, zone_id])
		EventBus.npc_spawned.emit(blacksmith, zone_id)
		
		return blacksmith

## Spawn all blacksmiths for a zone (called during zone load)
func spawn_zone_blacksmiths(zone_id: String, zone_data: ZoneData) -> Array[BlacksmithNPC]:
		var blacksmiths: Array[BlacksmithNPC] = []
		
		# Check zone NPCs list for blacksmith entries
		if zone_data.npcs.size() > 0:
			for npc_id in zone_data.npcs:
				if npc_id.begins_with("blacksmith_"):
					var location := BlacksmithNPC.LocationType.TOWN
					if zone_id.begins_with("outpost_"):
						location = BlacksmithNPC.LocationType.OUTPOST
					elif zone_id.begins_with("village_") or zone_id.begins_with("hamlet_"):
						location = BlacksmithNPC.LocationType.VILLAGE
					elif zone_id.begins_with("capital_"):
						location = BlacksmithNPC.LocationType.CAPITAL
					
					var spawn_pos := zone_data.bind_point if zone_data.bind_point != Vector3.ZERO else zone_data.zone_center
					var blacksmith := spawn_blacksmith(zone_id, spawn_pos, npc_id, location)
					if blacksmith:
						blacksmiths.append(blacksmith)
		
		# Auto-spawn in safe zones if no blacksmith defined
		if blacksmiths.is_empty() and zone_data.pvp_mode == ZoneData.PvPZoneMode.SAFE:
			var spawn_pos := zone_data.bind_point if zone_data.bind_point != Vector3.ZERO else zone_data.zone_center
			var blacksmith := spawn_blacksmith(zone_id, spawn_pos, "Blacksmith", BlacksmithNPC.LocationType.TOWN)
			if blacksmith:
				blacksmiths.append(blacksmith)
		
		return blacksmiths
