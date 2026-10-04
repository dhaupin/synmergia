## Buff - Temporary stat/effect modifiers
## One-time cost, duration-based enhancement
extends StatusEffect

class_name Buff
const PhysicsArea = preload("res://core/combat/physics_area.gd")
## Named collision bits (round 10): data/physics_layers/ LayerProfile.
const Layers = preload("res://core/schemas/layer_profile.gd")


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

@export var buff_type: BuffType = BuffType.STAT_BOOST
@export var target_rule: Target = Target.SELF

# Cost (one-time)
@export var mana_cost: int = 50
@export var stamina_cost: float = 0.0

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

# Shield (base StatusEffect owns shield_amount/_shield_remaining; this
# export feeds them through the buff's stack multiplier)
@export var shield_amount_export: int = 0  # Absorb this much damage

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
var stack_bonus_per_stack: float = 0.0  # Additional % bonus per stack

func _init() -> void:
	effect_type = EffectType.BUFF
	if effect_id == "":
		effect_id = effect_name.to_lower().replace(" ", "_")

## ACTIVATION

func apply(target_entity: Node) -> bool:
	var entity := target_entity as Entity
	if entity == null:
		return false
	# Check resources
	if entity.current_mana < mana_cost:
		return false
	if entity.current_stamina < stamina_cost:
		return false

	entity.current_mana -= mana_cost
	entity.current_stamina -= stamina_cost

	# Set shield if applicable
	_shield_remaining = shield_amount_export * stack_count

	# Apply stat bonuses
	_apply_stat_bonuses(entity, true)

	# Start duration timer
	if duration > 0:
		_timer = Timer.new()
		_timer.one_shot = true
		_timer.timeout.connect(_on_duration_expired)
		entity.add_child(_timer)
		_timer.start(duration)

	# Start regen ticks
	if health_regen_bonus > 0 or mana_regen_bonus > 0:
		_start_regen_tick(entity)

	return true

func remove(target_entity: Node) -> void:
	var entity := target_entity as Entity
	if _timer:
		_timer.stop()
		_timer.queue_free()
		_timer = null

	if entity != null:
		_apply_stat_bonuses(entity, false)
		if entity.status_effects.has(self):
			entity.status_effects.erase(self)

func _on_duration_expired() -> void:
	if target and is_instance_valid(target):
		remove(target)
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

	var absorbed: int = min(_shield_remaining, amount)
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
		"name": effect_name,
		"type": BuffType.keys()[buff_type],
		"duration": duration,
		"stacks": stack_count,
		"shield": _shield_remaining
	}

