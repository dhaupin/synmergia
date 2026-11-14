## CombatComponent - Attack/skill execution
## Attached to entities that can fight
extends Node
class_name CombatComponent
# NOTE: AntiCheatService is an autoload; reference it directly.
# QoSService uses static shim methods (AGENTS.md allowlist); the const is required.
const QoSService = preload("res://core/autoload/qos_service.gd")
const Skill = preload("res://core/combat/skill.gd")
const Item = preload("res://core/schemas/item.gd")
const InventoryComponent = preload("res://core/components/inventory_component.gd")
const SkillSchema = preload("res://core/schemas/skill.gd")
const CharacterData := preload("res://core/schemas/character_data.gd")

## Runtime autoload lookups (script-mode-safe; the bare identifiers
## fail compile when autoloads are absent -- test_islands).
func _hub() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("EventHub")) if tree and tree.root else null

func _glog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

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
var _active_combat_time_accumulator: float = 0.0  # Only counts when actively using items
var _last_action_time: float = 0.0  # Time of last skill/attack
@export var durability_tick_interval: float = 60.0  # Apply durability loss every 60 seconds (1 minute)
@export var action_timeout: float = 5.0  # Stop counting active time after 5 seconds of no actions

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
var charge_progress: float = 0.0  # 0.0-1.0 charge level during channeling
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
		# Track charge progress for charge-based skills
		if cast_skill and cast_skill.charge_time_max > 0:
			var elapsed: float = cast_time_total - cast_time_remaining
			charge_progress = min(elapsed / cast_skill.charge_time_max, 1.0)
		if cast_time_remaining <= 0:
			_finish_cast()

	# Update channeling
	if is_channeling:
		_update_channeling(delta)

## Execute a skill. The component is the GATE + state machine (rate
## limit, anticheat, casting state, GCD). Costs and cooldowns are owned
## by skill.execute (consuming here as well double-spent), and
## hitbox-family skills route through CombatSystem so the sweep/combo/
## skill_executed path stays the single live one.
func execute_skill(skill: Skill, target = null, ground_pos: Vector3 = Vector3.ZERO) -> bool:
	if skill == null:
		return false
	# QoS: Rate limit combat actions
	var entity = get_parent()
	if entity and "entity_id" in entity and entity.entity_id != "":
		if not QoSService.rate_limit(entity.entity_id, "combat"):
			var gl := _glog()
			if gl:
				gl.debug("CombatComponent: Rate limited skill %s for %s" % [skill.skill_name, entity.entity_id])
			return false			# AntiCheat: Record combat action for analysis
			var tree := Engine.get_main_loop() as SceneTree
			var anti_cheat := tree.root.get_node_or_null(NodePath("AntiCheatService")) if tree and tree.root else null
			if anti_cheat:
				anti_cheat.record_action(entity.entity_id, "combat_skill", entity.global_position if ("global_position" in entity) else Vector3.ZERO)

	# Apply Skill Academy upgrade deltas (returns duplicated schema with bonuses applied)
	var upgraded_skill: Skill = _apply_skill_upgrade_deltas(skill, entity)

	if not _can_execute_skill(upgraded_skill):
		return false

	# Check GCD
	if gcd_remaining > 0:
		return false

	match upgraded_skill.skill_type:
		Skill.SkillType.MELEE, Skill.SkillType.RANGED, Skill.SkillType.GROUND_TARGETED, Skill.SkillType.TARGETED_AOE:
			# Hitbox family: CombatSystem owns costs, execution, the hitbox
			# sweep, skill_executed and combo tracking.
			var ground: Vector3 = ground_pos if (upgraded_skill.is_ground_targeted and ground_pos != Vector3.ZERO) else Vector3.ZERO
			var cs_tree := Engine.get_main_loop() as SceneTree
			var combat_system := cs_tree.root.get_node_or_null(NodePath("CombatSystem")) if cs_tree and cs_tree.root else null
			if combat_system == null or not combat_system.execute_skill(get_parent(), upgraded_skill, target, ground):
				return false
			gcd_remaining = gcd_duration
			skill_finished.emit(upgraded_skill)
			record_action()
			return true

		Skill.SkillType.CHANNEL:
			_start_cast(upgraded_skill, target)
			gcd_remaining = gcd_duration
			record_action()
			return true

		_:
			# INSTANT/SELF: skill.execute consumes + cooldowns + applies.
			upgraded_skill.execute(get_parent(), target, ground_pos)
			gcd_remaining = gcd_duration
			skill_finished.emit(upgraded_skill)
			_emit_skill_used(get_parent(), upgraded_skill, target)
			record_action()
			return true

## Read CharacterData.skill_upgrades for the entity and apply upgrade deltas
## to the skill's runtime parameters. Call before any skill execution.
## Duplicate the schema and apply upgrade deltas.
## Returns a copy of the skill with upgrade bonuses applied.
## The original schema (from .tres / DataService) is never mutated.
func _apply_skill_upgrade_deltas(schema, _entity) -> Skill:
	# schema may be a combat Skill built from a schema (Skill.from_schema)
	# or a SkillSchema itself; only upgrade-capable ones carry the
	# metadata, so every access below is duck-typed. The old Entity-typed
	# params threw on every the player body cast.
	if schema == null or not ("upgradable" in schema) or not schema.upgradable:
		return schema

	# Get upgrade level from CharacterData via GameManager
	var upgrade_level: int = 0
	var gm_tree := Engine.get_main_loop() as SceneTree
	var game_manager := gm_tree.root.get_node_or_null(NodePath("GameManager")) if gm_tree and gm_tree.root else null
	if game_manager and is_instance_valid(game_manager.selected_character_data):
		var cd = game_manager.selected_character_data
		if cd != null and "id" in schema and cd.has_method("get_skill_upgrade_level"):
			upgrade_level = cd.get_skill_upgrade_level(schema.id)
	if upgrade_level <= 0:
		return schema
	if not schema.has_method("get_upgrade_deltas"):
		return schema

	# Duplicate the schema so runtime modifications don't leak into the shared resource
	var skill: Skill = schema.duplicate()

	var deltas: Dictionary = schema.get_upgrade_deltas(upgrade_level)

	# Apply multipliers
	if deltas.has("damage_mult"):
		skill.damage = int(skill.damage * deltas["damage_mult"])
	if deltas.has("heal_mult"):
		skill.heal_amount = int(skill.heal_amount * deltas["heal_mult"])
	if deltas.has("range_mult"):
		skill.range *= deltas["range_mult"]
	if deltas.has("cooldown_mult"):
		skill.cooldown *= deltas["cooldown_mult"]
	if deltas.has("aoe_mult") and skill.aoe_radius > 0:
		skill.aoe_radius *= deltas["aoe_mult"]
	if deltas.has("duration_mult"):
		skill.dot_duration *= deltas["duration_mult"]
	if deltas.has("dot_mult"):
		skill.dot_damage = int(skill.dot_damage * deltas["dot_mult"])
	if deltas.has("hot_mult"):
		skill.hot_heal = int(skill.hot_heal * deltas["hot_mult"])
	if deltas.has("cost_mult"):
		skill.mana_cost = int(skill.mana_cost * deltas["cost_mult"])
		skill.stamina_cost *= deltas["cost_mult"]
	if deltas.has("cast_time_mult"):
		skill.cast_time *= deltas["cast_time_mult"]
	if deltas.has("charge_mult") and skill.charge_time_max > 0:
		skill.charge_time_max *= deltas["charge_mult"]
	if deltas.has("max_targets_mult") and skill.targeted_aoe_max_targets > 0:
		skill.targeted_aoe_max_targets = int(skill.targeted_aoe_max_targets * deltas["max_targets_mult"])

	# Process unlocks
	if schema.has_method("get_unlocks_at_level"):
		var unlocks: Array = schema.get_unlocks_at_level(upgrade_level)
		if not unlocks.is_empty():
			skill.upgrade_unlocks = unlocks

	# Cache upgrade level
	skill.upgrade_level = upgrade_level

	# Fold the scope bands (heal AoE at epic+, teleport reach/scope at
	# mythic) for this level. Sets runtime fields; idempotent.
	if skill.has_method("apply_scope_bands"):
		skill.apply_scope_bands()

	# Scale effect values in the effects array (schema's execute() reads effects[i].value)
	for i in range(skill.effects.size()):
		var eff: Dictionary = skill.effects[i]
		var eff_type: String = eff.get("type", "")
		if eff_type == "damage" and deltas.has("damage_mult"):
			var base_val: int = eff.get("value", 0)
			skill.effects[i]["value"] = int(base_val * deltas["damage_mult"])
		elif eff_type == "heal" and deltas.has("heal_mult"):
			var base_val: int = eff.get("value", 0)
			skill.effects[i]["value"] = int(base_val * deltas["heal_mult"])

	return skill

## Apply charge scaling: duplicate the skill and scale effects by charge level.
## charge_time_max defines the max charge window. charge_progress is 0.0-1.0.
## Tier 1 (0% charge) = 0.5x min, scales linearly to 1.0x at full charge.
## Returns a new Skill with scaled damage/heal values.
func _apply_charge_scaling(skill: Skill, charge_level: float) -> Skill:
	var scaled: Skill = skill.duplicate() if skill else null
	if not scaled:
		return skill

	# Scale effect values by charge level
	for i in range(scaled.effects.size()):
		var eff: Dictionary = scaled.effects[i]
		var eff_type: String = eff.get("type", "")
		if eff_type in ["damage", "heal"]:
			var base_val: int = eff.get("value", 0)
			var charge_mult: float = 0.5 + (charge_level * 0.5)
			var scaled_val: int = int(base_val * charge_mult)
			scaled.effects[i]["value"] = max(scaled_val, 1)  # minimum 1 on any charge

	# Store charge level on skill for any effect handlers that need it
	scaled.charge_level = charge_level

	return scaled

func _can_execute_skill(skill: Skill) -> bool:
	var entity = get_parent()

	# Check if casting
	if is_casting:
		return false

	# Check dead (duck-typed: Entity subclasses and the player body both
	# carry a health_component, but guard anyway)
	if "health_component" in entity and entity.health_component != null \
			and entity.health_component.has_method("is_dead") \
			and entity.health_component.is_dead():
		return false

	# SECURITY: Cannot cast skills if locked (trade, follow, etc)
	var lock_tree := Engine.get_main_loop() as SceneTree
	var player_lock := lock_tree.root.get_node_or_null(NodePath("PlayerLockService")) if lock_tree and lock_tree.root else null
	if player_lock and "entity_id" in entity and entity.entity_id != "" \
			and player_lock.are_skills_blocked(entity.entity_id):
		return false

	# Check can_cast on skill
	return skill.can_cast(entity)

func _start_cast(skill: Skill, target = null) -> void:
	is_casting = true
	cast_skill = skill
	cast_time_total = skill.cast_time
	cast_time_remaining = skill.cast_time
	charge_progress = 0.0
	cast_started.emit(skill)

func _finish_cast() -> void:
	if cast_skill:
		# Apply charge scaling to damage/heal effects if charge_time_max > 0
		var executed_skill: Skill = cast_skill
		if charge_progress > 0.0 and cast_skill.charge_time_max > 0:
			executed_skill = _apply_charge_scaling(cast_skill, charge_progress)
		executed_skill.execute(get_parent(), null)
		cast_finished.emit(executed_skill)
		skill_finished.emit(executed_skill)
		_emit_skill_used(get_parent(), executed_skill, null)

	is_casting = false
	cast_skill = null
	cast_time_remaining = 0.0
	charge_progress = 0.0

## Interrupt current casting/channeling
func interrupt() -> void:
	_interrupt_cast("manual")

## Interrupt check when taking damage
## Called by health_component when entity takes damage
func on_damage_taken(damage: int, source = null, damage_type: String = "physical") -> bool:
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
	var entity = get_parent()
	if "aura_component" in entity and entity.aura_component != null:
		# Check for interrupt immunity buffs
		for buff in entity.aura_component.get_all_buffs():
			if buff != null and "status_data" in buff and buff.status_data != null \
					and "immune_interrupt" in buff.status_data and buff.status_data.immune_interrupt:
				resistance = 1.0  # Full immunity
				break

	# Roll for resistance
	if randf() < resistance:
		# Resisted!
		var evt := _hub()
		if evt:
			evt.emit_signal("interrupt_resisted", entity, skill)
		return false

	# Interrupted!
	_interrupt_cast("damage")
	return true

func _interrupt_cast(reason: String) -> void:
	var skill: Skill = null

	if is_casting:
		skill = cast_skill
		# Partial resource cost (50%)
		var entity = get_parent()
		if "current_mana" in entity:
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
		var evt := _hub()
		if evt:
			evt.emit_signal("entity_interrupted", get_parent(), skill, reason)

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

	var entity = get_parent()
	var target = null

	# Get target from skill
	if channel_skill.target_type == Skill.TargetType.SELF:
		target = entity
	elif "target" in entity:
		target = entity.target

	if target and is_instance_valid(target):
		channel_skill.execute(entity, target)
		var evt := _hub()
		if evt:
			evt.emit_signal("channel_tick", entity, channel_skill)

func _finish_channel(completed: bool) -> void:
	var skill: Skill = channel_skill

	is_channeling = false
	channel_skill = null
	channel_time_remaining = 0.0
	_channel_ticks = 0

	if completed and skill:
		# Execute final effect
		var owner = get_parent()
		if "target" in owner:
			skill.execute(owner, owner.target)
		else:
			skill.execute(owner, null)

	channel_ended.emit(skill, completed)
	skill_finished.emit(skill)

func _perform_attack(skill: Skill, target = null) -> void:
	attack_started.emit()

	# Calculate damage
	var base_damage := attack_power
	var is_crit: bool = randf() < crit_chance
	var damage := base_damage

	if is_crit:
		damage = int(damage * crit_multiplier)

	# Apply damage (duck-typed: take_damage first, HealthComponent fallback)
	if target and is_instance_valid(target):
		if target.has_method("take_damage"):
			target.take_damage(damage, get_parent())
		elif "health_component" in target and target.health_component != null:
			target.health_component.take_damage(damage, get_parent())

	attack_cooldown = 1.0 / skill.cast_time if skill.cast_time > 0 else 1.0
	skill_finished.emit(skill)
	record_action()

## Emit the EventHub skill_executed event (caster_id, skill_id, targets).
## The old EventHub.emit_skill_used() did not exist -- every non-hitbox
## cast crashed on it.
func _emit_skill_used(entity, skill: Skill, target) -> void:
	var caster_id: String = str(entity.entity_id) if (entity != null and "entity_id" in entity) else ""
	var target_ids: Array = []
	if target != null and "entity_id" in target and target.entity_id != "":
		target_ids.append(str(target.entity_id))
	var evt := _hub()
	if evt:
		evt.emit_signal("skill_executed", caster_id, skill.skill_id, target_ids)

## Basic auto-attack
func auto_attack(target, damage: int) -> void:
	if attack_cooldown > 0:
		return

	var is_crit := randf() < crit_chance
	var final_damage := damage

	if is_crit:
		final_damage = int(damage * crit_multiplier)

	if target and is_instance_valid(target):
		if target.has_method("take_damage"):
			target.take_damage(final_damage, get_parent())
		elif "health_component" in target and target.health_component != null:
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
	var evt := _hub()
	if evt:
		evt.emit_signal("entity_entered_combat", get_parent())

func _exit_combat() -> void:
	if not in_combat:
		return

	in_combat = false
	combat_start_time = 0
	_current_mana_regen_multiplier = mana_regen_rest

	combat_exited.emit()
	var evt := _hub()
	if evt:
		evt.emit_signal("entity_exited_combat", get_parent())

## Called when entity deals or takes damage
func on_damage_dealt(damage: int, target = null, damage_type: String = "physical") -> void:
	_last_damage_time = Time.get_ticks_msec()
	if not in_combat:
		_enter_combat()

func on_damage_taken_global(damage: int, source = null, damage_type: String = "physical") -> void:
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

	if skill.cooldown > 0 and skill.get_cooldown_remaining() > 0:
		return false

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
		var skill: Skill = queued_skill
		queued_skill = null
		# Execute queued skill
		execute_skill(skill)

## Process durability decay during combat
func _process(delta: float) -> void:
	if not in_combat:
		return

	# Accumulate combat time
	_combat_time_accumulator += delta

	# Track active combat time (only when using items)
	var time_since_action := _combat_time_accumulator - _last_action_time
	if time_since_action < action_timeout:
		_active_combat_time_accumulator += delta

	# Apply durability loss every tick interval using ACTIVE combat time
	if _active_combat_time_accumulator >= durability_tick_interval:
		var active_minutes := _active_combat_time_accumulator / 60.0
		_apply_durability_loss(active_minutes)
		_active_combat_time_accumulator = 0.0

## Record an action (skill/attack used) - resets active combat timer
func record_action() -> void:
	_last_action_time = _combat_time_accumulator

## Apply durability loss to all equipped items
func _apply_durability_loss(combat_minutes: float) -> void:
	var entity = get_parent()
	if not entity or not ("inventory_component" in entity) or entity.inventory_component == null:
		return

	var total_loss := 0
	var inventory = entity.inventory_component

	# Apply to each equipped item
	# EquipSlot lives on Item (the schema), not on InventoryComponent --
	# the old InventoryComponent.EquipSlot read was a parse error.
	for slot in Item.EquipSlot.values():
		var item: Item = inventory.get_equipped_item(slot)
		if item and item.max_durability > 0:
			var loss := item.apply_combat_durability_loss(combat_minutes)
			total_loss += loss

			if loss > 0:
				var gl := _glog()
				if gl:
					gl.debug("CombatComponent: %s lost %d durability on %s" % [entity.name, loss, item.display_name])

			# Check if item broke
			if item.is_broken():
				item_broken.emit(item.id)
				var gl := _glog()
				if gl:
					gl.warn("CombatComponent: %s's %s broke!" % [entity.name, item.display_name])

	if total_loss > 0:
		durability_tick.emit(total_loss)
