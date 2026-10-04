## StatusEffect - Unified buff/debuff/DoT/HoT/aura system
## Single base class for all temporary effects on entities
extends Resource
class_name StatusEffect

## The Entity class is resolved via preload + the global is_instance_of()
## function (NOT a method call: `target.is_instance_of(...)` is a
## Nonexistent-function runtime error on any Node). Entity's class_name
## is registered at parse time only when entity.gd has loaded first,
## which is not guaranteed for this file (it is preloaded by
## RegisterTypes, but other paths load it directly).
## is_instance_of(obj, Script) is the runtime equivalent of `is Entity`
## and needs no global class_name registration.
const EntityScript = preload("res://core/entities/entity.gd")


## Effect type classification
enum EffectType {
	BUFF,      # Positive effect
	DEBUFF,    # Negative effect
	NEUTRAL    # Neither positive nor negative
}

## Effect category for dispel mechanics
enum EffectCategory {
	MAGIC,      # General magic effects
	CURSE,      # Curses and hexes
	POISON,     # Poison and disease
	PHYSICAL,   # Physical debuffs
	HOLY,       # Holy/light effects
	SHADOW,     # Shadow/dark effects
	FIRE,       # Fire effects
	ICE,        # Frost effects
	LIGHTNING,  # Lightning effects
	ARCANE,     # Arcane effects
	BLEED,      # Bleeding effects
	STUN,       # Stun effects (not dispellable)
	FEAR,       # Fear effects
	CHARM       # Charm effects
}

## Stack behavior when effect is reapplied
enum StackBehavior {
	NONE,     # Cannot stack, refresh duration
	REFRESH,  # Reset duration, keep stacks
	ADD,      # Add stack count
	REPLACE   # Remove old, apply new
}

## Tick behavior for DOTs/HoTs
enum TickBehavior {
	INSTANT,      # One-time effect
	DURATION,     # Duration-based
	TICKED,       # Fixed number of ticks
	TOGGLE,       # Continuous while active (auras)
}

signal effect_expired
signal stack_changed(new_stacks: int)
signal tick_occurred(entity, amount: int, tick_type: String)

# Basic properties
@export var effect_id: String = ""
@export var effect_name: String = "Effect"
@export var description: String = ""
@export var icon_path: String = ""

# Classification
@export var effect_type: EffectType = EffectType.NEUTRAL
@export var effect_category: EffectCategory = EffectCategory.MAGIC
@export var tick_behavior: TickBehavior = TickBehavior.INSTANT

# Duration and stacking
## The setter keeps remaining_duration in sync: _init captures duration
## BEFORE callers (or .tres loads, which assign exported props after
## _init) set it, and apply_status_effect's is_expired() gate would
## otherwise reject every configured DURATION effect as already-dead
## (stale remaining_duration = 0.0).
@export var duration: float = 0.0:
	set(value):
		duration = value
		remaining_duration = value
@export var max_stacks: int = 1
@export var stack_behavior: StackBehavior = StackBehavior.NONE

# Tick settings (for TICKED behavior)
@export var tick_interval: float = 1.0
@export var total_ticks: int = 0  # 0 = infinite

# Stat modifiers
@export var strength_mod: int = 0
@export var agility_mod: int = 0
@export var intelligence_mod: int = 0
@export var vitality_mod: int = 0
@export var endurance_mod: int = 0
@export var wisdom_mod: int = 0

# Combat modifiers (multipliers)
@export var damage_multiplier: float = 0.0
@export var defense_multiplier: float = 0.0
@export var attack_speed_multiplier: float = 0.0
@export var movement_speed_multiplier: float = 0.0
@export var health_regen_mod: float = 0.0
@export var mana_regen_mod: float = 0.0

# Tick-based effects (DOTs/HoTs)
@export var tick_damage: int = 0
@export var tick_heal: int = 0
@export var tick_shield: int = 0

# Shield
@export var shield_amount: int = 0

# Resistance
@export var physical_resistance: float = 0.0
@export var magical_resistance: float = 0.0

# Crowd control
@export var can_move: bool = true
@export var can_cast: bool = true
@export var can_attack: bool = true
@export var is_invincible: bool = false

# Visibility/stealth
@export var make_invisible: bool = false
@export var break_on_damage: bool = false
@export var break_on_action: bool = false

# Aura-specific
@export var aura_radius: float = 0.0
@export var affects_allies: bool = false
@export var affects_enemies: bool = false
@export var mana_cost_per_second: float = 0.0

# Dispel settings
@export var is_dispellable: bool = true
@export var dispel_resist_chance: float = 0.0

# State
var current_stacks: int = 1
var remaining_duration: float = 0.0
var source: Node = null
var target: Node = null
var is_active: bool = false

# Internal state
var _timer: Timer
var _tick_count: int = 0
var _shield_remaining: int = 0
var _was_visible: bool = true

func _init() -> void:
	remaining_duration = duration
	if effect_id == "":
		effect_id = effect_name.to_lower().replace(" ", "_")

func apply(target_entity: Node) -> bool:
	if is_active:
		_handle_stacking()
		return true

	target = target_entity
	is_active = true
	_tick_count = 0
	_shield_remaining = shield_amount

	_apply_stat_modifiers(true)
	_apply_combat_modifiers(true)

	if make_invisible and is_instance_of(target, EntityScript):
		_was_visible = target.visible
		target.visible = false

	if shield_amount > 0:
		_shield_remaining = shield_amount * current_stacks

	match tick_behavior:
		TickBehavior.INSTANT:
			_apply_tick_effect()
		TickBehavior.DURATION:
			_start_duration_timer()
		TickBehavior.TICKED:
			_start_tick_timer()
		TickBehavior.TOGGLE:
			_start_toggle_timer()

	stack_changed.emit(current_stacks)
	return true

func remove(target_entity: Node) -> void:
	if not is_active:
		return

	_apply_stat_modifiers(false)
	_apply_combat_modifiers(false)

	if make_invisible and is_instance_of(target, EntityScript):
		target.visible = _was_visible

	_stop_timers()
	is_active = false
	target = null

func _handle_stacking() -> void:
	match stack_behavior:
		StackBehavior.REFRESH:
			remaining_duration = duration
			if _timer:
				_timer.start(duration)
		StackBehavior.ADD:
			current_stacks = mini(max_stacks, current_stacks + 1)
			stack_changed.emit(current_stacks)
		StackBehavior.REPLACE:
			_apply_stat_modifiers(false)
			_apply_combat_modifiers(false)
			current_stacks = 1
			_apply_stat_modifiers(true)
			_apply_combat_modifiers(true)

func _apply_stat_modifiers(adding: bool) -> void:
	if not target or not is_instance_of(target, EntityScript):
		return

	var sign: int = 1 if adding else -1
	var mult: int = current_stacks if adding else 1
	var entity = target as EntityScript

	if strength_mod != 0:
		entity.stats.strength += sign * strength_mod * mult
	if agility_mod != 0:
		entity.stats.agility += sign * agility_mod * mult
	if intelligence_mod != 0:
		entity.stats.intelligence += sign * intelligence_mod * mult
	if vitality_mod != 0:
		entity.stats.vitality += sign * vitality_mod * mult
	if endurance_mod != 0:
		entity.stats.endurance += sign * endurance_mod * mult
	if wisdom_mod != 0:
		entity.stats.wisdom += sign * wisdom_mod * mult

func _apply_combat_modifiers(adding: bool) -> void:
	if not target or not "stats" in target:
		return

	var sign: int = 1 if adding else -1
	var entity = target

	if damage_multiplier != 0 and "damage_multiplier" in entity.stats:
		entity.stats.damage_multiplier += sign * damage_multiplier * current_stacks
	if defense_multiplier != 0 and "defense_multiplier" in entity.stats:
		entity.stats.defense_multiplier += sign * defense_multiplier * current_stacks
	if movement_speed_multiplier != 0 and "movement_speed_multiplier" in entity.stats:
		entity.stats.movement_speed_multiplier += sign * movement_speed_multiplier * current_stacks

func _start_duration_timer() -> void:
	if duration <= 0:
		return
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_duration_expired)
	target.add_child(_timer)
	_timer.start(duration)
	remaining_duration = duration

func _start_tick_timer() -> void:
	if tick_interval <= 0:
		return
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = tick_interval
	_timer.timeout.connect(_on_tick)
	target.add_child(_timer)
	_timer.start(tick_interval)

func _start_toggle_timer() -> void:
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = tick_interval if tick_interval > 0 else 1.0
	_timer.timeout.connect(_on_tick)
	target.add_child(_timer)
	_timer.start()

func _stop_timers() -> void:
	if _timer:
		_timer.stop()
		_timer.queue_free()
		_timer = null

func _on_duration_expired() -> void:
	effect_expired.emit()
	_expire()

func _on_tick() -> void:
	if not is_active or not target or not is_instance_valid(target):
		_stop_timers()
		return

	_tick_count += 1
	_apply_tick_effect()
	tick_occurred.emit(target, tick_damage if tick_damage > 0 else tick_heal,
		"DAMAGE" if tick_damage > 0 else "HEAL")

	if total_ticks > 0 and _tick_count >= total_ticks:
		effect_expired.emit()
		_expire()

func _apply_tick_effect() -> void:
	if not target or not is_instance_valid(target):
		return

	if tick_damage > 0 and is_instance_of(target, EntityScript):
		target.current_health = maxi(0, target.current_health - tick_damage * current_stacks)
		target.health_changed.emit(target.current_health, target.max_health)

	if tick_heal > 0 and is_instance_of(target, EntityScript):
		target.current_health = mini(target.max_health, target.current_health + tick_heal * current_stacks)
		target.health_changed.emit(target.current_health, target.max_health)

	if tick_shield > 0:
		_shield_remaining += tick_shield * current_stacks

func _expire() -> void:
	if is_active and target:
		remove(target)

func absorb_damage(amount: int) -> int:
	if _shield_remaining <= 0:
		return amount
	var absorbed: int = mini(_shield_remaining, amount)
	_shield_remaining -= absorbed
	return amount - absorbed

func is_expired() -> bool:
	return remaining_duration <= 0 and duration > 0

func get_stacks() -> int:
	return current_stacks

func get_remaining_duration() -> float:
	return remaining_duration if is_active else 0.0

func is_permanent() -> bool:
	return duration == 0.0

func get_info() -> Dictionary:
	return {
		"id": effect_id,
		"name": effect_name,
		"type": EffectType.keys()[effect_type],
		"category": EffectCategory.keys()[effect_category],
		"duration": duration,
		"remaining": get_remaining_duration(),
		"stacks": current_stacks,
		"max_stacks": max_stacks,
		"is_active": is_active
	}

func on_damaged() -> void:
	if break_on_damage and is_active:
		_expire()

func on_action() -> void:
	if break_on_action and is_active:
		_expire()
