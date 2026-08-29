## EntityEvents - Domain events for entity lifecycle
class_name EntityEvents
extends Node

# Entity lifecycle events (using string IDs for decoupling)
signal spawned(entity_id: String, zone_id: String, position: Vector3)
signal despawned(entity_id: String, reason: String)
signal died(entity_id: String, killer_id: String, damage_type: String)
signal resurrected(entity_id: String, source: String)

# Movement/position events
signal moved(entity_id: String, from_pos: Vector3, to_pos: Vector3)
signal teleported(entity_id: String, from_pos: Vector3, to_pos: Vector3, zone_from: String, zone_to: String)
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

# Event history
var _history: Array = []
const MAX_HISTORY := 1000

func _log_event(name: String, data: Dictionary = {}) -> void:
_history.append({"name": name, "data": data, "time": Time.get_ticks_msec()})
if _history.size() > MAX_HISTORY:
_history.pop_front()

func get_event_count() -> int:
return _history.size()

func clear_history() -> void:
_history.clear()
