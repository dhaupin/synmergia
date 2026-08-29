## EntityEvents - Domain events for entity lifecycle
## All entity spawn, despawn, death, and movement events
class_name EntityEvents
extends BaseEventBus

# Entity lifecycle events (using string IDs for decoupling)
signal spawned(entity_id: String, zone_id: String, position: Vector3)
signal despawned(entity_id: String, reason: String)
signal died(entity_id: String, killer_id: String, damage_type: String)
signal resurrected(entity_id: String, source: String)

# Movement/position events
signal moved(entity_id: String, from: Vector3, to: Vector3)
signal teleported(entity_id: String, from: Vector3, to: Vector3, zone_from: String, zone_to: String)
signal entered_zone(entity_id: String, zone_id: String)
signal exited_zone(entity_id: String, zone_id: String)

# Health/resource events
signal health_changed(entity_id: String, current: int, maximum: int, delta: int)
signal mana_changed(entity_id: String, current: int, maximum: int, delta: int)
signal stamina_changed(entity_id: String, current: int, maximum: int, delta: int)

# Level/XP events
signal level_up(entity_id: String, new_level: int, old_level: int)
signal xp_gained(entity_id: String, amount: int, source: String)

# Stats events
signal stat_changed(entity_id: String, stat_name: String, value: int, delta: int)
signal buff_added(entity_id: String, buff_id: String, source_id: String)
signal buff_removed(entity_id: String, buff_id: String, reason: String)
signal buff_refreshed(entity_id: String, buff_id: String)

# State events
signal state_changed(entity_id: String, old_state: String, new_state: String)
signal target_changed(entity_id: String, old_target_id: String, new_target_id: String)

# Spawn metadata helpers
class SpawnContext:
	var entity_id: String
	var zone_id: String
	var position: Vector3
	var spawner_id: String = ""
	var level: int = 1
	var display_name: String = ""
	
	func _init(p_entity_id: String, p_zone_id: String, p_position: Vector3):
		entity_id = p_entity_id
		zone_id = p_zone_id
		position = p_position

## Emit spawn event
func emit_spawned(ctx: SpawnContext) -> void:
	_log_event("spawned", {"entity_id": ctx.entity_id, "zone_id": ctx.zone_id})
	spawned.emit(ctx.entity_id, ctx.zone_id, ctx.position)

## Emit death event
func emit_died(entity_id: String, killer_id: String, damage_type: String = "") -> void:
	_log_event("died", {"entity_id": entity_id, "killer_id": killer_id})
	died.emit(entity_id, killer_id, damage_type)

## Emit movement event
func emit_moved(entity_id: String, from: Vector3, to: Vector3) -> void:
	_log_event("moved", {"entity_id": entity_id})
	moved.emit(entity_id, from, to)

## Emit zone change event
func emit_entered_zone(entity_id: String, zone_id: String) -> void:
	_log_event("entered_zone", {"entity_id": entity_id, "zone_id": zone_id})
	entered_zone.emit(entity_id, zone_id)

## Emit teleport event
func emit_teleported(entity_id: String, from: Vector3, to: Vector3, zone_from: String, zone_to: String) -> void:
	_log_event("teleported", {"entity_id": entity_id, "zone_from": zone_from, "zone_to": zone_to})
	teleported.emit(entity_id, from, to, zone_from, zone_to)

## Emit health change event
func emit_health_changed(entity_id: String, current: int, maximum: int) -> void:
	var delta := current - (current + maximum)  # Approximate
	_log_event("health_changed", {"entity_id": entity_id, "current": current})
	health_changed.emit(entity_id, current, maximum, delta)

## Emit level up event
func emit_level_up(entity_id: String, new_level: int, old_level: int) -> void:
	_log_event("level_up", {"entity_id": entity_id, "new_level": new_level})
	level_up.emit(entity_id, new_level, old_level)
