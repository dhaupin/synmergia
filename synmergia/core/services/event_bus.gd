## EventBus - Global signal hub for decoupled communication
## All services and components emit through here
class_name EventBus
extends Node

# Entity Events - UNIFIED SPAWN/DESPAWN
## entity_spawned: Emitted when any entity spawns, carries SpawnMetadata for notification routing
signal entity_spawned(entity: Entity, metadata: SpawnMetadata)
## entity_despawned: Emitted when any entity despawns, metadata contains spawn type for cleanup routing
signal entity_despawned(entity: Entity, metadata: SpawnMetadata)
## entity_died: Emitted when entity dies, killer info included for PvP tracking
signal entity_died(entity: Entity, killer: Entity, metadata: SpawnMetadata)
signal entity_health_changed(entity: Entity, current: int, maximum: int, delta: int)
signal entity_level_up(entity: Entity, new_level: int)

# Combat Events
signal skill_executed(caster: Entity, skill: Skill, targets: Array)
signal skill_hit(caster: Entity, target: Entity, skill: Skill, damage: int)
signal skill_missed(caster: Entity, skill: Skill, target: Entity)
signal damage_dealt(damager: Entity, target: Entity, amount: int, damage_type: String)
signal entity_interrupted(entity: Entity, skill: Skill)

# Buff/Effect Events
signal buff_applied(entity: Entity, buff: Buff, source: Entity)
signal buff_removed(entity: Entity, buff: Buff)
signal buff_refreshed(entity: Entity, buff: Buff)
signal debuff_applied(entity: Entity, debuff: StatusEffect, source: Entity)
signal aura_activated(entity: Entity, aura: AuraBuff)
signal aura_deactivated(entity: Entity, aura: AuraBuff)
signal dot_applied(entity: Entity, dot: DamageOverTime, source: Entity)
signal dot_ticked(entity: Entity, dot: DamageOverTime, damage: int)
signal effect_dispelled(entity: Entity, effect: StatusEffect, dispeller: Entity)

# Movement/Position Events
signal entity_entered_zone(entity: Entity, zone: ZoneData)
signal entity_exited_zone(entity: Entity, zone: ZoneData)
signal entity_teleported(entity: Entity, from: Vector3, to: Vector3)

# PvP Events
signal player_killed_player(killer: Entity, victim: Entity)
signal faction_hostility_changed(faction1: Faction, faction2: Faction)

# Resource Events
signal item_picked_up(entity: Entity, item: Item)
signal item_dropped(entity: Entity, item: Item)
signal gold_changed(entity: Entity, amount: int)
signal inventory_full(entity: Entity)

# Chat Events
signal chat_message(sender: Entity, channel: String, message: String)

# System Events
signal game_paused()
signal game_resumed()
signal server_shutdown()
signal server_started()

# Targeting Events
signal target_action_executed(source_id: String, target_id: String, action_id: String, success: bool)

# Objective Events (for ObjectiveManager integration)
signal objective_progress_updated(player_id: String, objective_id: String, progress: int, total: int)
signal objective_completed(player_id: String, objective_id: String)
signal objective_failed(player_id: String, objective_id: String)
signal objective_unlocked(player_id: String, objective_id: String)

# =============================================================================
# INNER CLASS: SpawnMetadata
# Unified metadata for entity spawn events
# =============================================================================

class SpawnMetadata:
	## Spawn type classifications
	enum SpawnType {
		NORMAL = 0,      # Regular enemy spawn
		ELITE = 1,       # Elite enemy
		BOSS = 2,        # Boss enemy
		WORLD_BOSS = 3,  # World boss (global notification)
		NPC = 4,         # NPC spawn
		LOOT = 5,        # Loot drop spawn
		DWELLING = 6,    # Housing object spawn
		GATEWAY = 7,     # Teleport point spawn
	}

	## Notification priority levels
	enum NotificationPriority {
		LOW = 0,
		NORMAL = 1,
		HIGH = 2,
		CRITICAL = 3,
	}

	## Core spawn information
	var spawn_type: SpawnType = SpawnType.NORMAL
	var display_name: String = ""
	var entity_id: String = ""

	## Location information (required for radius notifications)
	var zone_id: String = ""
	var position: Vector3 = Vector3.ZERO

	## Notification configuration
	var notification_enabled: bool = false
	var notification_scopes: Array = []
	var notification_message: String = ""
	var notification_priority: NotificationPriority = NotificationPriority.NORMAL

	## Spawn context
	var spawn_point_id: String = ""
	var spawner_entity_id: String = ""  # For summoned minions
	var faction: int = 0
	var level: int = 1

	## Optional metadata
	var tags: Array[String] = []
	var quest_id: String = ""  # For quest-related spawns

	func _init(
		p_spawn_type: SpawnType = SpawnType.NORMAL,
		p_display_name: String = "",
		p_zone_id: String = "",
		p_position: Vector3 = Vector3.ZERO
	) -> void:
		spawn_type = p_spawn_type
		display_name = p_display_name
		zone_id = p_zone_id
		position = p_position

	## Create a normal enemy spawn (no notification)
	static func enemy(
		p_display_name: String,
		p_zone_id: String,
		p_position: Vector3,
		p_spawn_point_id: String = "",
		p_level: int = 1
	) -> SpawnMetadata:
		var m := SpawnMetadata.new(SpawnType.NORMAL, p_display_name, p_zone_id, p_position)
		m.spawn_point_id = p_spawn_point_id
		m.level = p_level
		return m

	## Create an elite enemy spawn (zone notification)
	static func elite(
		p_display_name: String,
		p_zone_id: String,
		p_position: Vector3,
		p_spawn_point_id: String = "",
		p_level: int = 1
	) -> SpawnMetadata:
		var m := SpawnMetadata.new(SpawnType.ELITE, p_display_name, p_zone_id, p_position)
		m.spawn_point_id = p_spawn_point_id
		m.level = p_level
		m.notification_enabled = true
		m.notification_scopes = [NotificationService.AlertScope.zone(p_zone_id, false)]
		m.notification_message = "Elite enemy %s has appeared!"
		m.notification_priority = NotificationPriority.NORMAL
		return m

	## Create a boss spawn (zone + neighbors notification)
	static func boss(
		p_display_name: String,
		p_zone_id: String,
		p_position: Vector3,
		p_level: int = 1
	) -> SpawnMetadata:
		var m := SpawnMetadata.new(SpawnType.BOSS, p_display_name, p_zone_id, p_position)
		m.level = p_level
		m.notification_enabled = true
		m.notification_scopes = [NotificationService.AlertScope.zone(p_zone_id, true)]
		m.notification_message = "Boss %s has appeared!"
		m.notification_priority = NotificationPriority.HIGH
		return m

	## Create a world boss spawn (server-wide notification)
	static func world_boss(
		p_display_name: String,
		p_zone_id: String,
		p_position: Vector3,
		p_level: int = 1
	) -> SpawnMetadata:
		var m := SpawnMetadata.new(SpawnType.WORLD_BOSS, p_display_name, p_zone_id, p_position)
		m.level = p_level
		m.notification_enabled = true
		m.notification_scopes = [NotificationService.AlertScope.server_wide()]
		m.notification_message = "WORLD BOSS: %s has appeared in %s!"
		m.notification_priority = NotificationPriority.CRITICAL
		return m

	## Create an NPC spawn (no notification)
	static func npc(
		p_display_name: String,
		p_zone_id: String,
		p_position: Vector3,
		p_npc_id: String = ""
	) -> SpawnMetadata:
		var m := SpawnMetadata.new(SpawnType.NPC, p_display_name, p_zone_id, p_position)
		m.entity_id = p_npc_id
		return m

	## Create a loot drop spawn
	static func loot(
		p_display_name: String,
		p_zone_id: String,
		p_position: Vector3,
		p_spawner_id: String = ""
	) -> SpawnMetadata:
		var m := SpawnMetadata.new(SpawnType.LOOT, p_display_name, p_zone_id, p_position)
		m.spawner_entity_id = p_spawner_id
		return m

	## Configure with explicit notification settings (fluent API)
	func with_notification(
		p_enabled: bool,
		p_scopes: Array,
		p_message: String,
		p_priority: NotificationPriority = NotificationPriority.NORMAL
	) -> SpawnMetadata:
		notification_enabled = p_enabled
		notification_scopes = p_scopes
		notification_message = p_message
		notification_priority = p_priority
		return self

	## Add spawn tags (fluent API)
	func with_tags(p_tags: Array[String]) -> SpawnMetadata:
		tags = p_tags
		return self

	## Link to a quest (fluent API)
	func for_quest(p_quest: String) -> SpawnMetadata:
		quest_id = p_quest
		return self

	## Get spawn type as readable string
	func get_spawn_type_string() -> String:
		match spawn_type:
			SpawnType.NORMAL: return "Normal"
			SpawnType.ELITE: return "Elite"
			SpawnType.BOSS: return "Boss"
			SpawnType.WORLD_BOSS: return "World Boss"
			SpawnType.NPC: return "NPC"
			SpawnType.LOOT: return "Loot"
			SpawnType.DWELLING: return "Dwelling"
			SpawnType.GATEWAY: return "Gateway"
			_: return "Unknown"

# =============================================================================
# INNER CLASS END
# =============================================================================

var _event_history: Array[Dictionary] = []
var _max_history: int = 1000

func _ready() -> void:
	pass  # Autoloaded singleton

## Log an event to history (for debugging/replays)
func log_event(event_name: String, data: Dictionary = {}) -> void:
	var entry := {
		"name": event_name,
		"data": data,
		"time": Time.get_ticks_msec()
	}
	_event_history.append(entry)
	
	# Trim history if needed
	if _event_history.size() > _max_history:
		_event_history.pop_at(0)

## Get recent events
func get_recent_events(count: int = 100) -> Array[Dictionary]:
	var start := max(0, _event_history.size() - count)
	return _event_history.slice(start)

## Clear event history
func clear_history() -> void:
	_event_history.clear()

## Helper methods for common patterns
func emit_skill_used(caster: Entity, skill: Skill, target: Entity = null) -> void:
	log_event("skill_used", {"caster": caster.name if caster else "", "skill": skill.skill_name if skill else "", "target": target.name if target else ""})
	skill_executed.emit(caster, skill, [target] if target else [])
