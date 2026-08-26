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
signal combat_entered()
signal combat_exited()
signal gcd_triggered(duration: float)
signal durability_tick(total_loss: int)  # Emitted each minute of combat
signal item_broken(item_id: String)  # Emitted when an item reaches 0 durability

@export var attack_power: int = 10
@export var spell_power: int = 10
@export var crit_chance: float = 0.05  # 5%
@export var crit_multiplier: float = 1.5

# Global Cooldown (GCD)
var gcd_remaining: float = 0.0
@export var gcd_duration: float = 1.0
@export var gcd_affects_movement: bool = false  # Some games lock movement during GCD

# Combat State
var in_combat: bool = false
var combat_start_time: int = 0
@export var out_of_combat_time: float = 10.0  # Seconds after last damage to exit combat

# Durability Decay Tracking
var _combat_time_accumulator: float = 0.0  # Accumulates combat time in seconds
@export var durability_tick_interval: float = 60.0  # Apply durability loss every 60 seconds (1 minute)

# Mana Regen
@export var mana_regen_combat: float = 1.0    # Multiplier during combat
@export var mana_regen_rest: float = 5.0     # Multiplier while resting
var _current_mana_regen_multiplier: float = 1.0

# Stamina Regen
@export var stamina_regen_combat: float = 0.2
@export var stamina_regen_rest: float = 1.0

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
	
	# Update combat state
	_update_combat_state(delta)
	
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

## Trigger GCD (called when using a skill)
func trigger_gcd(skill: Skill = null) -> void:
	if skill and not skill.uses_gcd:
		return
	
	gcd_remaining = gcd_duration
	gcd_triggered.emit(gcd_duration)

## Combat state management
var _last_damage_time: int = 0

func _update_combat_state(delta: float) -> void:
	var entity: Entity = get_parent()
	
	# Check if should enter combat (took/Dealt damage recently)
	var now := Time.get_ticks_msec()
	
	# Enter combat
	if not in_combat and (now - _last_damage_time < 1000):  # Damage in last second
		_enter_combat()
	
	# Exit combat (OOC timer)
	if in_combat:
		var time_since_damage := (now - _last_damage_time) / 1000.0
		if time_since_damage >= out_of_combat_time:
			_exit_combat()

func _enter_combat() -> void:
	if in_combat:
		return
	
	in_combat = true
	combat_start_time = Time.get_ticks_msec()
	_current_mana_regen_multiplier = mana_regen_combat
	
	combat_entered.emit()
	EventBus.entity_entered_combat.emit(get_parent())

func _exit_combat() -> void:
	if not in_combat:
		return
	
	in_combat = false
	combat_start_time = 0
	_current_mana_regen_multiplier = mana_regen_rest
	
	combat_exited.emit()
	EventBus.entity_exited_combat.emit(get_parent())

## Called when entity deals or takes damage
func on_damage_dealt(damage: int, target: Entity, damage_type: String) -> void:
	_last_damage_time = Time.get_ticks_msec()
	if not in_combat:
		_enter_combat()

func on_damage_taken_global(damage: int, source: Entity, damage_type: String) -> void:
	_last_damage_time = Time.get_ticks_msec()
	if not in_combat:
		_enter_combat()

## Get combat duration
func get_combat_duration() -> float:
	if not in_combat:
		return 0.0
	return (Time.get_ticks_msec() - combat_start_time) / 1000.0

## Get current mana regen multiplier
func get_mana_regen_multiplier() -> float:
	return _current_mana_regen_multiplier

## Get stamina regen multiplier
func get_stamina_regen_multiplier() -> float:
	if in_combat:
		return stamina_regen_combat
	return stamina_regen_rest

## Force exit combat (e.g., zone change)
func force_exit_combat() -> void:
	_last_damage_time = 0
	_exit_combat()

## Check if can use skill (GCD + cooldown check)
func can_use_skill(skill: Skill) -> bool:
	if is_gcd_active():
		return false
	
	if skill.cooldown > 0:
		# TODO: Check skill cooldown
		pass
	
	return true

## Queue a skill for when GCD expires
func queue_skill(skill: Skill) -> bool:
	if not _skill_queue_enabled:
		return false
	
	if not can_use_skill(skill):
		return false
	
	queued_skill = skill
	return true

## Cancel queued skill
func cancel_queued_skill() -> void:
	queued_skill = null

## Get queued skill
func get_queued_skill() -> Skill:
	return queued_skill

## Process queued skill (call when GCD expires)
func process_queued_skill() -> void:
	if queued_skill and not is_gcd_active():
		var skill := queued_skill
		queued_skill = null
		# Execute queued skill
		execute_skill(skill)

## Process durability decay during combat
func _process(delta: float) -> void:
	if not in_combat:
		return
	
	# Accumulate combat time
	_combat_time_accumulator += delta
	
	# Apply durability loss every tick interval
	if _combat_time_accumulator >= durability_tick_interval:
		var combat_minutes := _combat_time_accumulator / 60.0
		_apply_durability_loss(combat_minutes)
		_combat_time_accumulator = 0.0

## Apply durability loss to all equipped items
func _apply_durability_loss(combat_minutes: float) -> void:
	var entity: Entity = get_parent()
	if not entity or not entity.inventory_component:
		return
	
	var total_loss := 0
	var inventory: InventoryComponent = entity.inventory_component
	
	# Apply to each equipped item
	for slot in InventoryComponent.EquipSlot.values():
		var item: Item = inventory.get_equipped_item(slot)
		if item and item.max_durability > 0:
			var loss := item.apply_combat_durability_loss(combat_minutes)
			total_loss += loss
			
			if loss > 0:
				Logger.debug("CombatComponent: %s lost %d durability on %s" % [entity.name, loss, item.display_name])
			
			# Check if item broke
			if item.is_broken():
				item_broken.emit(item.id)
				Logger.warn("CombatComponent: %s's %s broke!" % [entity.name, item.display_name])
	
	if total_loss > 0:
		durability_tick.emit(total_loss)
