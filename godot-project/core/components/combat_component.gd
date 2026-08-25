## CombatComponent - Attack/skill execution
## Attached to entities that can fight
class_name CombatComponent
extends Node

signal attack_started()
signal attack_finished()
signal skill_started(skill: Skill)
signal skill_finished(skill: Skill)
signal interrupted(skill: Skill)
signal cast_started(skill: Skill)
signal cast_finished(skill: Skill)

@export var attack_power: int = 10
@export var spell_power: int = 10
@export var crit_chance: float = 0.05  # 5%
@export var crit_multiplier: float = 1.5

# Global Cooldown
var gcd_remaining: float = 0.0
@export var gcd_duration: float = 1.0

# Casting state
var is_casting: bool = false
var cast_skill: Skill = null
var cast_time_remaining: float = 0.0

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

## Interrupt current casting
func interrupt() -> void:
	if is_casting:
		interrupted.emit(cast_skill)
		EventBus.entity_interrupted.emit(get_parent(), cast_skill)
		is_casting = false
		cast_skill = null
		cast_time_remaining = 0.0

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
