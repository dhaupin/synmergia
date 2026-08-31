## EventHub - Unified event system interface
## Wraps all domain-specific event buses under one autoload
extends Node

## Forwarding signals for backward compatibility (maps to entity_events)
signal entity_spawned(entity, metadata: SpawnMetadata)
signal player_died(entity, killer)
signal entity_despawned(entity_id: String, reason: String)
signal entity_killed(entity_id: String, killer_id: String)
signal entity_targeted(target_id: String, source_id: String)

## Spawn metadata for entity lifecycle events
class SpawnMetadata:
	var spawn_type: int = 0
	var entity_id: String = ""
	var display_name: String = ""
	var zone_id: String = ""
	var position: Vector3 = Vector3.ZERO
	var spawner_entity_id: String = ""
	var spawn_point_id: String = ""
	var level: int = 1
	var tags: Array = []
	var quest_id: String = ""
	var notification_enabled: bool = false
	var notification_scopes: Array = []
	var notification_message: String = ""
	var notification_priority: int = 0
	
	enum SpawnType {
		NORMAL = 0,
		ELITE = 1,
		BOSS = 2,
		WORLD_BOSS = 3,
		NPC = 4,
		LOOT = 5,
		DWELLING = 6,
		GATEWAY = 7,
	}
	
	enum NotificationPriority {
		LOW = 0,
		NORMAL = 1,
		HIGH = 2,
		CRITICAL = 3,
	}
	
	func _init(p_type: int = 0, p_name: String = "", p_zone: String = "", p_pos: Vector3 = Vector3.ZERO):
		spawn_type = p_type
		display_name = p_name
		zone_id = p_zone
		position = p_pos
	
	func get_spawn_type_string() -> String:
		match spawn_type:
			0: return "Normal"
			1: return "Elite"
			2: return "Boss"
			3: return "World Boss"
			4: return "NPC"
			5: return "Loot"
			_: return "Unknown"

	# Factory methods used by SpawnService and others.
	static func enemy(p_name: String, p_zone: String, p_pos: Vector3, p_level: int = 1) -> SpawnMetadata:
		var m := SpawnMetadata.new(SpawnType.NORMAL, p_name, p_zone, p_pos)
		m.level = p_level
		m.notification_enabled = true
		return m

	static func elite(p_name: String, p_zone: String, p_pos: Vector3, p_level: int = 1) -> SpawnMetadata:
		var m := SpawnMetadata.new(SpawnType.ELITE, p_name, p_zone, p_pos)
		m.level = p_level
		m.notification_enabled = true
		m.notification_priority = NotificationPriority.HIGH
		return m

	static func boss(p_name: String, p_zone: String, p_pos: Vector3, p_level: int = 1) -> SpawnMetadata:
		var m := SpawnMetadata.new(SpawnType.BOSS, p_name, p_zone, p_pos)
		m.level = p_level
		m.notification_enabled = true
		m.notification_priority = NotificationPriority.HIGH
		return m

	static func world_boss(p_name: String, p_zone: String, p_pos: Vector3, p_level: int = 1) -> SpawnMetadata:
		var m := SpawnMetadata.new(SpawnType.WORLD_BOSS, p_name, p_zone, p_pos)
		m.level = p_level
		m.notification_enabled = true
		m.notification_priority = NotificationPriority.CRITICAL
		return m

## Domain-specific event buses (use these to emit/listen)
var entity
var combat
var inventory
var system

func _ready() -> void:
	# Load and instantiate domain event buses
	# Using load() to ensure classes are available
	var entity_class = load("res://core/events/entity_events.gd")
	var combat_class = load("res://core/events/combat_events.gd")
	var inventory_class = load("res://core/events/inventory_events.gd")
	var system_class = load("res://core/events/system_events.gd")
	
	entity = entity_class.new()
	combat = combat_class.new()
	inventory = inventory_class.new()
	system = system_class.new()
	
	add_child(entity)
	add_child(combat)
	add_child(inventory)
	add_child(system)
	
	# Forward entity_events to direct signals for backward compatibility
	entity.spawned.connect(_on_entity_spawned)
	entity.died.connect(_on_entity_died)
	
	GameLog.info("EventHub: Initialized")

func _on_entity_spawned(entity_id: String, zone_id: String, position: Vector3) -> void:
	entity_spawned.emit(entity_id, null)

func _on_entity_died(entity_id: String, killer_id: String, damage_type: String) -> void:
	player_died.emit(entity_id, killer_id)

## Get event summary for debugging
func get_summary() -> Dictionary:
	return {
		"entity_events": entity.get_event_count(),
		"combat_events": combat.get_event_count(),
		"inventory_events": inventory.get_event_count(),
		"system_events": system.get_event_count(),
	}

## Clear all event history
func clear_all_history() -> void:
	entity.clear_history()
	combat.clear_history()
	inventory.clear_history()
	system.clear_history()
