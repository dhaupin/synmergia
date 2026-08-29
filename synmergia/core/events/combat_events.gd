## CombatEvents - Domain events for combat actions
class_name CombatEvents
extends Node

# Skill events
signal skill_started(caster_id: String, skill_id: String, target_ids: Array)
signal skill_executed(caster_id: String, skill_id: String, target_ids: Array)
signal skill_completed(caster_id: String, skill_id: String, success: bool)
signal skill_interrupted(caster_id: String, skill_id: String, reason: String)
signal skill_cooldown_ready(caster_id: String, skill_id: String)

# Damage events
signal damage_dealt(attacker_id: String, target_id: String, damage: int, damage_type: String, critical: bool)
signal damage_taken(target_id: String, attacker_id: String, damage: int, damage_type: String)
signal damage_absorbed(target_id: String, amount: int, source: String)
signal damage_mitigated(target_id: String, amount: int, mitigation_type: String)

# Healing events
signal healing_dealt(caster_id: String, target_id: String, amount: int)
signal healing_taken(target_id: String, amount: int, source: String)

# Buff/debuff events
signal buff_applied(target_id: String, buff_id: String, source_id: String, duration: float)
signal buff_expired(target_id: String, buff_id: String)
signal buff_removed(target_id: String, buff_id: String, reason: String)
signal debuff_applied(target_id: String, debuff_id: String, source_id: String, duration: float)

# Combat state events
signal combat_started(entity_id: String, opponent_id: String)
signal combat_ended(entity_id: String, reason: String)

# Kill events
signal entity_killed(killer_id: String, victim_id: String, damage_type: String)
signal player_killed_player(killer_id: String, victim_id: String)

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
