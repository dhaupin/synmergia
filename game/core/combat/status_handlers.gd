## StatusHandlers - Various status effect handlers
## Speed, stealth, immunity, damage over time
extends Node


## SpeedModifier - Adjusts movement speed
class_name SpeedModifier
extends StatusEffect

enum SpeedType {
	SLOW,       # Decrease speed
	HASTE,      # Increase speed
	ROOT,       # Complete movement stop
	SNARE       # Partial slow that doesn't stack
}

@export var speed_type: SpeedType = SpeedType.SLOW
@export var speed_percent: float = 0.0  # -50 = 50% slower, +30 = 30% faster
@export var flat_speed_change: float = 0.0  # Flat adjustment (higher priority)

var _original_move_speed: float = 0.0
var _original_sprint_speed: float = 0.0

func _init() -> void:
	effect_type = EffectType.DEBUFF if speed_type in [SpeedType.SLOW, SpeedType.ROOT, SpeedType.SNARE] else EffectType.BUFF

func apply(target: Entity) -> void:
	super.apply(target)

	# Store original speeds
	if target is PlayerController:
		_original_move_speed = target.move_speed
		_original_sprint_speed = target.sprint_speed
		_apply_speed_change(target)
	elif "move_speed" in target:
		_original_move_speed = target.move_speed

func remove(target: Entity) -> void:
	_revert_speed_change(target)
	super.remove(target)

func _apply_speed_change(target: Entity) -> void:
	match speed_type:
		SpeedType.ROOT:
			if target is PlayerController:
				target.move_speed = 0.0
				target.sprint_speed = 0.0
			target.stats.movement_speed_multiplier = 0.0

		SpeedType.SNARE:
			# Snare is a specific slow that should cancel other snares
			target.stats.movement_speed_multiplier = clamp(1.0 + speed_percent / 100.0, 0.0, 1.0)

		SpeedType.SLOW:
			target.stats.movement_speed_multiplier = clamp(1.0 + speed_percent / 100.0, 0.1, 2.0)

		SpeedType.HASTE:
			target.stats.movement_speed_multiplier = clamp(1.0 + speed_percent / 100.0, 0.1, 3.0)

	if flat_speed_change != 0.0 and target is PlayerController:
		target.move_speed = max(0.5, _original_move_speed + flat_speed_change)

func _revert_speed_change(target: Entity) -> void:
	target.stats.movement_speed_multiplier = 1.0
	if target is PlayerController:
		target.move_speed = _original_move_speed
		target.sprint_speed = _original_sprint_speed

## StealthHandler - Invisible/stealth system
class_name StealthHandler
extends StatusEffect

enum StealthType {
	INVISIBLE,   # Cannot be seen by enemies
	STEALTH,     # Can be seen by nearby enemies but not targeted
	VANISH       # Complete removal from aggro
}

@export var stealth_type: StealthType = StealthType.INVISIBLE
@export var break_on_damage: bool = true  # Taking damage breaks stealth
@export var break_on_action: bool = false  # Using skills breaks stealth
@export var detection_radius: float = 5.0  # How close enemy can detect (for STEALTH)
@export var reveal_cooldown: float = 0.0   # Seconds before can be reapplied

var _was_visible: bool = true

func _init() -> void:
	effect_type = EffectType.BUFF

func apply(target: Entity) -> void:
	super.apply(target)

	if target is PlayerController:
		_was_visible = target.visible
		_apply_stealth(target)

func remove(target: Entity) -> void:
	if target is PlayerController:
		_revert_stealth(target)
	super.remove(target)

func _apply_stealth(target: Entity) -> void:
	match stealth_type:
		StealthType.INVISIBLE:
			target.visible = false
			target.collision_layer = 0  # Can't be hit
			target.collision_mask = 0b0000100  # Only collides with world (not entities)

		StealthType.STEALTH:
			target.visible = true  # Still visible but
			target.collision_layer = 0b0000001  # Can be hit but not targeted
			# Targeting logic would be handled by the enemy AI

		StealthType.VANISH:
			target.visible = false
			target.collision_layer = 0
			target.collision_mask = 0b0000100
			# Would also need to clear aggro from enemies

func _revert_stealth(target: Entity) -> void:
	target.visible = _was_visible
	target.collision_layer = 0b0000001  # Default player layer
	target.collision_mask = 0b0000111

func is_stealthed() -> bool:
	return is_active

## Called when target takes damage (to break stealth)
func on_damaged(target: Entity, damage: int, source: Entity) -> void:
	if break_on_damage and is_active:
		remove(target)

## Called when target uses a skill (to break stealth)
func on_action(target: Entity) -> void:
	if break_on_action and is_active:
		remove(target)

## ImmunityHandler - Invincibility and immunities
class_name ImmunityHandler
extends StatusEffect

@export var invincible: bool = false          # Complete damage immunity
@export var immune_stun: bool = false
@export var immune_slow: bool = false
@export var immune_silence: bool = false       # Cannot be silenced
@export var immune_fear: bool = false
@export var immune_root: bool = false
@export var immune_knockback: bool = false
@export var immune_dot: bool = false           # Damage over time immunity
@export var immune_interrupt: bool = false     # Cannot have casts interrupted

var _damage_absorbed: int = 0

func _init() -> void:
	effect_type = EffectType.BUFF
	if invincible:
		duration = 0  # Permanent until removed

func apply(target: Entity) -> void:
	super.apply(target)
	_apply_immunities(target)

func remove(target: Entity) -> void:
	_revert_immunities(target)
	super.remove(target)

func _apply_immunities(target: Entity) -> void:
	if invincible:
		target.stats.damage_multiplier = 0.0  # All damage dealt is 0
		target.collision_layer = 0  # Cannot be hit

func _revert_immunities(target: Entity) -> void:
	target.stats.damage_multiplier = 1.0
	target.collision_layer = 0b0000001

## Check if target is immune to a specific effect
func is_immune_to(effect: String) -> bool:
	match effect.to_lower():
		"stun": return immune_stun
		"slow": return immune_slow
		"silence": return immune_silence
		"fear": return immune_fear
		"root": return immune_root
		"knockback": return immune_knockback
		"dot", "damage_over_time": return immune_dot
		"interrupt": return immune_interrupt
	return false

## Handle incoming damage (returns actual damage after immunity check)
func on_damage(target: Entity, damage: int, damage_type: String = "") -> int:
	if invincible:
		_damage_absorbed += damage
		return 0
	return damage

## DamageOverTime - Poison, burn, negative aura damage
class_name DamageOverTime
extends StatusEffect

enum DotType {
	POISON,      # Stacks, nature damage
	BURN,        # Fire damage, can refresh
	BLEED,       # Physical damage, ticks faster
	CORRUPTION,  # Shadow damage, cannot be cleansed
	DECAY,       # Absolute damage, ignores resistances
	MARK         # Damage mark, detonates on expire
}

@export var dot_type: DotType = DotType.POISON
@export var damage_per_tick: int = 10
@export var tick_interval: float = 1.0
@export var total_ticks: int = 5
@export var damage_type: String = "physical"  # physical, magical, true
@export var stacks: bool = false              # Can stack?
@export var max_stacks: int = 5
@export var can_cleanse: bool = true          # Can be removed by cleanse effects
@export var detonate_damage: int = 0          # Explodes at end for extra damage

var _current_ticks: int = 0
var _timer: Timer
var _current_stacks: int = 1
var _mark_ready_to_detonate: bool = false

func _init() -> void:
	effect_type = EffectType.DEBUFF
	duration = tick_interval * total_ticks

func apply(target: Entity) -> void:
	super.apply(target)
	_start_dot(target)

func remove(target: Entity) -> void:
	_stop_dot()
	if dot_type == DotType.MARK and _mark_ready_to_detonate and detonate_damage > 0:
		_detonate(target)
	super.remove(target)

func _start_dot(target: Entity) -> void:
	_current_ticks = 0
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = tick_interval
	_timer.timeout.connect(_on_tick)
	target.add_child(_timer)
	_timer.start()

func _stop_dot() -> void:
	if _timer:
		_timer.stop()
		_timer.queue_free()
		_timer = null

func _on_tick() -> void:
	if not is_active or not target or not is_instance_valid(target):
		_stop_dot()
		return

	_current_ticks += 1

	var actual_damage := _calculate_damage()
	_apply_damage(target, actual_damage)

	if dot_type == DotType.MARK:
		_mark_ready_to_detonate = true

	if _current_ticks >= total_ticks:
		if detonate_damage > 0 and dot_type != DotType.MARK:
			_apply_damage(target, detonate_damage)
		effect_expired.emit()
		_stop_dot()

func _calculate_damage() -> int:
	var dmg := damage_per_tick
	if stacks:
		dmg *= _current_stacks

	match damage_type.to_lower():
		"physical":
			return target.take_damage(dmg)
		"magical":
			return target.take_damage(dmg)  # Would factor in magic resist
		"true":
			target.current_health -= dmg
			return dmg
	return dmg

func _apply_damage(target: Entity, amount: int) -> void:
	match damage_type.to_lower():
		"physical":
			target.take_damage(amount)
		"magical":
			target.take_magical_damage(amount)  # Requires magical damage method
		"true":
			target.current_health -= amount
			target.health_changed.emit(target.current_health, target.max_health)
			if target.current_health <= 0:
				target.die(null)

func _detonate(target: Entity) -> void:
	if detonate_damage > 0:
		_apply_damage(target, detonate_damage)

func add_stack() -> void:
	if stacks and _current_stacks < max_stacks:
		_current_stacks += 1
		stack_changed.emit(_current_stacks)

func get_dot_info() -> Dictionary:
	return {
		"type": DotType.keys()[dot_type],
		"damage_per_tick": damage_per_tick,
		"ticks_remaining": total_ticks - _current_ticks,
		"stacks": _current_stacks if stacks else 1,
		"total_damage": damage_per_tick * total_ticks * (_current_stacks if stacks else 1)
	}
