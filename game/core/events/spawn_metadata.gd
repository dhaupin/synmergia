## SpawnMetadata - Type definition for entity spawn events
extends RefCounted
class_name SpawnMetadata

const __SpawnMetadata__ = preload("res://core/events/spawn_metadata.gd")
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

# Dynamic fields attached by services (EntityService, SpawnService) and
# read by consumers. Declared explicitly so 4.7.2's strict property
# assignment doesn't reject them on a Resource/RefCounted base.
var nsc9_code: int = -1
var spatial_address: int = 0
var faction: int = 0
var seed: int = 0

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
	var m := __SpawnMetadata__.new(SpawnType.NORMAL, p_name, p_zone, p_pos)
	m.level = p_level
	m.notification_enabled = true
	return m

static func elite(p_name: String, p_zone: String, p_pos: Vector3, p_level: int = 1) -> SpawnMetadata:
	var m := __SpawnMetadata__.new(SpawnType.ELITE, p_name, p_zone, p_pos)
	m.level = p_level
	m.notification_enabled = true
	m.notification_priority = NotificationPriority.HIGH
	return m

static func boss(p_name: String, p_zone: String, p_pos: Vector3, p_level: int = 1) -> SpawnMetadata:
	var m := __SpawnMetadata__.new(SpawnType.BOSS, p_name, p_zone, p_pos)
	m.level = p_level
	m.notification_enabled = true
	m.notification_priority = NotificationPriority.HIGH
	return m

static func world_boss(p_name: String, p_zone: String, p_pos: Vector3, p_level: int = 1) -> SpawnMetadata:
	var m := __SpawnMetadata__.new(SpawnType.WORLD_BOSS, p_name, p_zone, p_pos)
	m.level = p_level
	m.notification_enabled = true
	m.notification_priority = NotificationPriority.CRITICAL
	return m
