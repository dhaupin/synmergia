## Buff - Temporary stat/effect modifiers
## One-time cost, duration-based enhancement
class_name Buff
extends StatusEffect

enum BuffType {
	STAT_BOOST,     # Increase stats temporarily
	HASTE,          # Movement/attack speed
	SHIELD,          # Absorb damage
	REGENERATION,    # Heal over time
	IMMUNITY,        # Negate specific effects
	DAMAGE_BUFF,     # Increase damage dealt
	DEFENSE_BUFF,   # Decrease damage taken
	RESISTANCE,      # Specific damage type resistance
}

enum Target {
	SELF,            # Only affects caster
	TARGET,          # Affects current target
	TEAM,            # Affects all party/guild members
}

@export var buff_name: String = "Buff"
@export var buff_id: String = ""
@export var buff_type: BuffType = BuffType.STAT_BOOST
@export var target: Target = Target.SELF

# Cost (one-time)
@export var mana_cost: int = 50
@export var stamina_cost: float = 0.0

# Duration (0 = permanent until cancelled)
@export var duration: float = 30.0

# Stat modifiers
@export var strength_bonus: int = 0
@export var agility_bonus: int = 0
@export var intelligence_bonus: int = 0
@export var vitality_bonus: int = 0
@export var endurance_bonus: int = 0
@export var wisdom_bonus: int = 0

# Combat modifiers
@export var damage_percent_bonus: float = 0.0  # +20% damage
@export var defense_percent_bonus: float = 0.0  # +10% defense
@export var attack_speed_percent: float = 0.0   # +15% attack speed
@export var movement_speed_percent: float = 0.0 # +10% movement
@export var health_regen_bonus: float = 0.0   # +5 HP/sec
@export var mana_regen_bonus: float = 0.0    # +2 MP/sec

# Shield
@export var shield_amount: int = 0  # Absorb this much damage

# Resistance
@export var physical_resistance: float = 0.0  # +20% physical resist
@export var magical_resistance: float = 0.0   # +20% magic resist

# Immunity
@export var immune_stun: bool = false
@export var immune_slow: bool = false
@export var immune_silence: bool = false
@export var immune_fear: bool = false

# Visual
@export var icon: String = ""
@export var vfx_cast: String = ""
@export var vfx_loop: String = ""

var stack_count: int = 1
var max_stacks: int = 1
var stack_bonus_per_stack: float = 0.0  # Additional % bonus per stack

var _shield_remaining: int = 0
var _timer: Timer

func _init() -> void:
	effect_type = EffectType.BUFF
	if buff_id == "":
		buff_id = buff_name.to_lower().replace(" ", "_")

## ACTIVATION

func apply(target_entity: Entity) -> bool:
	# Check resources
	if target_entity.current_mana < mana_cost:
		return false
	if target_entity.current_stamina < stamina_cost:
		return false
	
	target_entity.current_mana -= mana_cost
	target_entity.current_stamina -= stamina_cost
	
	# Set shield if applicable
	_shield_remaining = shield_amount * stack_count
	
	# Apply stat bonuses
	_apply_stat_bonuses(target_entity, true)
	
	# Start duration timer
	if duration > 0:
		_timer = Timer.new()
		_timer.one_shot = true
		_timer.timeout.connect(_on_duration_expired)
		target_entity.add_child(_timer)
		_timer.start(duration)
	
	# Start regen ticks
	if health_regen_bonus > 0 or mana_regen_bonus > 0:
		_start_regen_tick(target_entity)
	
	return true

func remove(target_entity: Entity) -> void:
	if _timer:
		_timer.stop()
		_timer.queue_free()
		_timer = null
	
	_apply_stat_bonuses(target_entity, false)
	target_entity.status_effects.erase(self)

func _on_duration_expired() -> void:
	if target_entity and is_instance_valid(target_entity):
		remove(target_entity)
	effect_expired.emit()

## STAT APPLICATION

func _apply_stat_bonuses(entity: Entity, applying: bool) -> void:
	var multiplier := stack_count if applying else 1
	var sign := 1 if applying else -1
	
	if strength_bonus != 0:
		entity.stats.strength += sign * strength_bonus * multiplier
	if agility_bonus != 0:
		entity.stats.agility += sign * agility_bonus * multiplier
	if intelligence_bonus != 0:
		entity.stats.intelligence += sign * intelligence_bonus * multiplier
	if vitality_bonus != 0:
		entity.stats.vitality += sign * vitality_bonus * multiplier
	if endurance_bonus != 0:
		entity.stats.endurance += sign * endurance_bonus * multiplier
	if wisdom_bonus != 0:
		entity.stats.wisdom += sign * wisdom_bonus * multiplier

## SHIELD

func absorb_damage(amount: int) -> int:
	if _shield_remaining <= 0:
		return amount
	
	var absorbed := min(_shield_remaining, amount)
	_shield_remaining -= absorbed
	return amount - absorbed

## REGENERATION

func _start_regen_tick(entity: Entity) -> void:
	var regen_timer := Timer.new()
	regen_timer.one_shot = false
	regen_timer.wait_time = 1.0
	regen_timer.timeout.connect(func(): _tick_regen(entity))
	entity.add_child(regen_timer)
	regen_timer.start()

func _tick_regen(entity: Entity) -> void:
	if health_regen_bonus > 0:
		entity.current_health = min(entity.max_health, entity.current_health + health_regen_bonus)
	if mana_regen_bonus > 0:
		entity.current_mana = min(entity.max_mana, entity.current_mana + mana_regen_bonus)

## STACKING

func can_stack() -> bool:
	return max_stacks > 1

func add_stack() -> void:
	if can_stack():
		stack_count = min(max_stacks, stack_count + 1)
		# Recalculate bonuses
		shield_amount += shield_amount * stack_bonus_per_stack
		shield_amount = int(shield_amount)
		stack_changed.emit(stack_count)

func get_buff_info() -> Dictionary:
	return {
		"name": buff_name,
		"type": BuffType.keys()[buff_type],
		"duration": duration,
		"stacks": stack_count,
		"shield": _shield_remaining
	}
