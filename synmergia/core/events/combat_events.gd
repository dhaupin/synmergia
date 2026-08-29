## CombatEvents - Domain events for combat actions
## Skills, damage, buffs/debuffs, and combat state changes
class_name CombatEvents
extends BaseEventBus

# Skill events
signal skill_started(caster_id: String, skill_id: String, target_ids: Array[String])
signal skill_executed(caster_id: String, skill_id: String, target_ids: Array[String])
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
signal buff_refreshed(target_id: String, buff_id: String, new_duration: float)

signal debuff_applied(target_id: String, debuff_id: String, source_id: String, duration: float)
signal debuff_expired(target_id: String, debuff_id: String)
signal debuff_removed(target_id: String, debuff_id: String, reason: String)

# DOT/HOT events
signal dot_ticked(target_id: String, dot_id: String, damage: int)
signal hot_ticked(target_id: String, hot_id: String, healing: int)

# Aura events
signal aura_applied(entity_id: String, aura_id: String, source_id: String)
signal aura_removed(entity_id: String, aura_id: String, reason: String)
signal aura_expired(entity_id: String, aura_id: String)

# Combat state events
signal combat_started(entity_id: String, opponent_id: String)
signal combat_ended(entity_id: String, reason: String)
signal combat_entered(entity_id: String)
signal combat_exited(entity_id: String)

# Kill events
signal entity_killed(killer_id: String, victim_id: String, damage_type: String)
signal player_killed_player(killer_id: String, victim_id: String)

# Interruption events
signal action_interrupted(entity_id: String, action_id: String, reason: String)
signal action_blocked(target_id: String, attacker_id: String, action_id: String)
signal action_dodged(target_id: String, attacker_id: String, action_id: String)
signal action_missed(attacker_id: String, target_id: String, action_id: String)

# Combat math result events
signal dodge_roll(attacker_id: String, target_id: String, roll: float, threshold: float, result: bool)
signal crit_roll(attacker_id: String, roll: float, crit_chance: float, result: bool)
signal hit_roll(attacker_id: String, target_id: String, roll: float, defense: float, result: bool)

## Emit skill executed event
func emit_skill_executed(caster_id: String, skill_id: String, target_ids: Array) -> void:
	_log_event("skill_executed", {"caster_id": caster_id, "skill_id": skill_id})
	skill_executed.emit(caster_id, skill_id, target_ids)

## Emit damage dealt event
func emit_damage_dealt(attacker_id: String, target_id: String, damage: int, damage_type: String, critical: bool = false) -> void:
	_log_event("damage_dealt", {"attacker_id": attacker_id, "target_id": target_id, "damage": damage})
	damage_dealt.emit(attacker_id, target_id, damage, damage_type, critical)

## Emit entity killed event
func emit_entity_killed(killer_id: String, victim_id: String, damage_type: String = "") -> void:
	_log_event("entity_killed", {"killer_id": killer_id, "victim_id": victim_id})
	entity_killed.emit(killer_id, victim_id, damage_type)

## Emit buff applied event
func emit_buff_applied(target_id: String, buff_id: String, source_id: String, duration: float = 0) -> void:
	_log_event("buff_applied", {"target_id": target_id, "buff_id": buff_id})
	buff_applied.emit(target_id, buff_id, source_id, duration)

## Emit healing dealt event
func emit_healing_dealt(caster_id: String, target_id: String, amount: int) -> void:
	_log_event("healing_dealt", {"caster_id": caster_id, "target_id": target_id, "amount": amount})
	healing_dealt.emit(caster_id, target_id, amount)
