## EventBus - Global signal hub for decoupled communication
## All services and components emit through here
class_name EventBus
extends Node

# Entity Events
signal entity_spawned(entity: Entity)
signal entity_despawned(entity: Entity)
signal entity_died(entity: Entity, killer: Entity)
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

# Spawn Events
signal enemy_spawned(enemy: Entity, spawn_point: Vector3)
signal enemy_despawned(enemy: Entity)
signal boss_spawned(enemy: Entity, boss_name: String)

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
		_event_history.pop_front()

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
