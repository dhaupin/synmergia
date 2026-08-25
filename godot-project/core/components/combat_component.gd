## CombatComponent - Attack/skill execution
## Attached to entities that can fight
class_name CombatComponent
extends Node

signal attack_started()
signal attack_finished()
signal skill_started(skill: Skill)
signal skill_finished(skill: Skill)
signal interrupted(skill: Skill, reason: String)
signal cast_started(skill: Skill)
signal cast_finished(skill: Skill)
signal channel_started(skill: Skill)
signal channel_updated(progress: float)
signal channel_ended(skill: Skill, completed: bool)

@export var attack_power: int = 10
@export var spell_power: int = 10
@export var crit_chance: float = 0.05  # 5%
@export var crit_multiplier: float = 1.5

# Global Cooldown
var gcd_remaining: float = 0.0
@export var gcd_duration: float = 1.0

# Casting state (interrupted by damage)
var is_casting: bool = false
var cast_skill: Skill = null
var cast_time_remaining: float = 0.0
var cast_time_total: float = 0.0
var _interrupt_resistance: float = 0.0  # Chance to resist interrupt

# Channeling state (progress-based, can be interrupted)
var is_channeling: bool = false
var channel_skill: Skill = null
var channel_time_remaining: float = 0.0
var channel_time_total: float = 0.0
var channel_tick_interval: float = 0.0
var _channel_ticks: int = 0

# Attack state
var is_attacking: bool = false
var attack_cooldown: float = 0.0

# Skill queue
var queued_skill: Skill = null
var _skill_queue_enabled: bool = true

func _ready() -> void:
	pass

func _physics_process(delta: float) -> void:
	# Update cooldowns
	if gcd_remaining > 0:
		gcd_remaining = max(0, gcd_remaining - delta)
	
	if attack_cooldown > 0:
		attack_cooldown = max(0, attack_cooldown - delta)
	
	# Update casting
	if is_casting:
		cast_time_remaining -= delta
		if cast_time_remaining <= 0:
			_finish_cast()
	
	# Update channeling
	if is_channeling:
		_update_channeling(delta)

## Execute a skill
func execute_skill(skill: Skill, target: Entity = null, ground_pos: Vector3 = Vector3.ZERO) -> bool:
	if not _can_execute_skill(skill):
		return false
	
	# Check GCD
	if gcd_remaining > 0:
		return false
	
	# Consume resources
	if not _consume_skill_costs(skill):
		return false
	
	# Start cooldown
	skill.remaining_cooldown = skill.cooldown
	
	# Start GCD
	gcd_remaining = gcd_duration
	
	# Execute based on skill type
	match skill.skill_type:
		Skill.SkillType.INSTANT, Skill.SkillType.SELF:
			skill.execute(get_parent(), target, ground_pos)
			skill_finished.emit(skill)
		
		Skill.SkillType.MELEE, Skill.SkillType.RANGED:
			_perform_attack(skill, target)
		
		Skill.SkillType.CHANNEL:
			_start_cast(skill, target)
		
		Skill.SkillType.GROUND_TARGETED, Skill.SkillType.TARGETED_AOE:
			skill.execute(get_parent(), target, ground_pos)
			skill_finished.emit(skill)
	
	EventBus.emit_skill_used(get_parent(), skill, target)
	return true

func _can_execute_skill(skill: Skill) -> bool:
	var entity: Entity = get_parent()
	
	# Check if casting
	if is_casting:
		return false
	
	# Check dead
	if entity.health_component and entity.health_component.is_dead():
		return false
	
	# Check can_cast on skill
	return skill.can_cast(entity)

func _consume_skill_costs(skill: Skill) -> bool:
	var entity: Entity = get_parent()
	
	if entity.current_mana < skill.mana_cost:
		return false
	if entity.current_stamina < skill.stamina_cost:
		return false
	
	entity.current_mana -= skill.mana_cost
	entity.current_stamina -= skill.stamina_cost
	
	return true

func _start_cast(skill: Skill, target: Entity) -> void:
	is_casting = true
	cast_skill = skill
	cast_time_remaining = skill.cast_time
	cast_started.emit(skill)

func _finish_cast() -> void:
	if cast_skill:
		cast_skill.execute(get_parent(), null)
		cast_finished.emit(cast_skill)
		skill_finished.emit(cast_skill)
	
	is_casting = false
	cast_skill = null
	cast_time_remaining = 0.0

## Interrupt current casting/channeling
func interrupt() -> void:
	_interrupt_cast("manual")

## Interrupt check when taking damage
## Called by health_component when entity takes damage
func on_damage_taken(damage: int, source: Entity, damage_type: String) -> bool:
	# Can only interrupt if casting or channeling
	if not is_casting and not is_channeling:
		return false
	
	# Check if skill is interruptible
	var skill: Skill = cast_skill if is_casting else channel_skill
	if skill == null:
		return false
	
	if not skill.can_interrupt:
		return false
	
	# Check interrupt resistance (base + buffs)
	var resistance := _interrupt_resistance
	var entity: Entity = get_parent()
	if entity.aura_component:
		# TODO: Check for interrupt resistance buffs
		pass
	
	# Roll for resistance
	if randf() < resistance:
		# Resisted!
		EventBus.interrupt_resisted.emit(entity, skill)
		return false
	
	# Interrupted!
	_interrupt_cast("damage")
	return true

func _interrupt_cast(reason: String) -> void:
	var skill: Skill = null
	
	if is_casting:
		skill = cast_skill
		# Partial resource cost (50%)
		var entity: Entity = get_parent()
		entity.current_mana = int(entity.current_mana + skill.mana_cost * 0.5)
		is_casting = false
		cast_skill = null
		cast_time_remaining = 0.0
	elif is_channeling:
		skill = channel_skill
		is_channeling = false
		channel_skill = null
		channel_time_remaining = 0.0
	
	if skill:
		interrupted.emit(skill, reason)
		EventBus.entity_interrupted.emit(get_parent(), skill, reason)

## Check if can be interrupted
func can_be_interrupted() -> bool:
	return is_casting or is_channeling

## Update channeling
func _update_channeling(delta: float) -> void:
	channel_time_remaining -= delta
	
	var progress: float = 1.0 - (channel_time_remaining / channel_time_total)
	channel_updated.emit(progress)
	
	# Channel ticks
	if channel_tick_interval > 0:
		var ticks_elapsed := int((channel_time_total - channel_time_remaining) / channel_tick_interval)
		if ticks_elapsed > _channel_ticks:
			for i in range(_channel_ticks, ticks_elapsed):
				_execute_channel_tick()
			_channel_ticks = ticks_elapsed
	
	# Channel complete?
	if channel_time_remaining <= 0:
		_finish_channel(true)

func _execute_channel_tick() -> void:
	if channel_skill == null:
		return
	
	var entity: Entity = get_parent()
	var target: Entity = null
	
	# Get target from skill
	if channel_skill.target_type == Skill.TargetType.SELF:
		target = entity
	else:
		target = entity.target
	
	if target and is_instance_valid(target):
		channel_skill.execute(entity, target)
		EventBus.channel_tick.emit(entity, channel_skill)

func _finish_channel(completed: bool) -> void:
	var skill := channel_skill
	
	is_channeling = false
	channel_skill = null
	channel_time_remaining = 0.0
	_channel_ticks = 0
	
	if completed and skill:
		# Execute final effect
		skill.execute(get_parent(), get_parent().target)
	
	channel_ended.emit(skill, completed)
	skill_finished.emit(skill)

func _perform_attack(skill: Skill, target: Entity) -> void:
	attack_started.emit()
	
	# Calculate damage
	var base_damage := attack_power
	var is_crit := randf() < crit_chance
	var damage := base_damage
	
	if is_crit:
		damage = int(damage * crit_multiplier)
	
	# Apply damage
	if target and is_instance_valid(target):
		target.health_component.take_damage(damage, get_parent())
	
	attack_cooldown = 1.0 / skill.cast_time if skill.cast_time > 0 else 1.0
	skill_finished.emit(skill)

## Basic auto-attack
func auto_attack(target: Entity, damage: int) -> void:
	if attack_cooldown > 0:
		return
	
	var is_crit := randf() < crit_chance
	var final_damage := damage
	
	if is_crit:
		final_damage = int(damage * crit_multiplier)
	
	if target and is_instance_valid(target):
		target.health_component.take_damage(final_damage, get_parent())

## Check if GCD is active
func is_gcd_active() -> bool:
	return gcd_remaining > 0

## Get GCD remaining
func get_gcd_remaining() -> float:
	return gcd_remaining
