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


## AuraBuff - Toggle aura that affects nearby entities
## Continuous mana/stamina drain while active, AoE effects
class_name AuraBuff
extends Buff

enum AuraType {
	ALLY_BOOST,    # Positive effects to nearby allies
	ENEMY_DEBUFF,  # Negative effects to nearby enemies
	AREA_BUFF,     # Buff to self and allies in range
	AREA_DEBUFF    # Debuff to enemies in range
}

@export var aura_type: AuraType = AuraType.AREA_BUFF
@export var aura_radius: float = 10.0  # 3D sphere radius
@export var aura_respects_geometry: bool = false  # Walls block aura detection (false = goes through walls)

# Toggle cost (continuous drain while active)
@export var mana_drain_per_second: float = 5.0
@export var stamina_drain_per_second: float = 2.0

# AoE effects when active
@export var ally_damage_boost: float = 0.0      # +10% damage to allies
@export var ally_defense_boost: float = 0.0     # +10% defense to allies
@export var ally_health_regen: float = 0.0      # +5 HP/sec to allies
@export var ally_mana_regen: float = 0.0        # +2 MP/sec to allies

@export var enemy_damage_reduction: float = 0.0  # -10% damage from affected enemies
@export var enemy_slow_percent: float = 0.0      # -20% movement speed to enemies
@export var enemy_armor_reduction: float = 0.0   # -15% armor to affected enemies

# Self effects
@export var self_damage_boost: float = 0.0
@export var self_defense_boost: float = 0.0

var _drain_timer: Timer
var _effect_timer: Timer
var _is_toggled_on: bool = false
var _affected_allies: Array[Entity] = []
var _affected_enemies: Array[Entity] = []
var _physics_area: PhysicsArea  # 3D sphere detection

func _init() -> void:
	super._init()
	effect_type = EffectType.BUFF
	if buff_id == "":
		buff_id = buff_name.to_lower().replace(" ", "_") + "_aura"

## TOGGLE

func toggle(target_entity: Entity) -> bool:
	if _is_toggled_on:
		deactivate(target_entity)
		return false
	else:
		return activate(target_entity)

func activate(target_entity: Entity) -> bool:
	if _is_toggled_on:
		return true
	
	# Check initial resource
	if target_entity.current_mana < mana_cost:
		return false
	if target_entity.current_stamina < stamina_cost:
		return false
	
	# Pay activation cost
	target_entity.current_mana -= mana_cost
	target_entity.current_stamina -= stamina_cost
	
	_is_toggled_on = true
	target_entity = target_entity
	
	# Apply self effects
	_apply_self_effects(target_entity, true)
	
	# Start continuous drain timer
	_drain_timer = Timer.new()
	_drain_timer.one_shot = false
	_drain_timer.wait_time = 1.0
	_drain_timer.timeout.connect(_on_drain_tick)
	target_entity.add_child(_drain_timer)
	_drain_timer.start()
	
	# Start effect application timer
	_effect_timer = Timer.new()
	_effect_timer.one_shot = false
	_effect_timer.wait_time = 0.5  # Apply effects every 0.5s
	_effect_timer.timeout.connect(_on_effect_tick)
	target_entity.add_child(_effect_timer)
	_effect_timer.start()
	
	# Apply initial effects
	_update_aura_effects()
	
	return true

func deactivate(target_entity: Entity) -> void:
	if not _is_toggled_on:
		return
	
	_is_toggled_on = false
	
	# Stop timers
	if _drain_timer:
		_drain_timer.stop()
		_drain_timer.queue_free()
		_drain_timer = null
	
	if _effect_timer:
		_effect_timer.stop()
		_effect_timer.queue_free()
		_effect_timer = null
	
	# Remove self effects
	_apply_self_effects(target_entity, false)
	
	# Remove effects from affected entities
	_remove_effects_from_allies()
	_remove_effects_from_enemies()
	_affect_allies.clear()
	_affected_enemies.clear()

## DRAIN

func _on_drain_tick() -> void:
	if not _is_toggled_on or not target_entity or not is_instance_valid(target_entity):
		deactivate(target_entity)
		return
	
	# Check if entity has enough resources
	var can_continue := true
	
	if mana_drain_per_second > 0:
		target_entity.current_mana -= mana_drain_per_second
		if target_entity.current_mana < 0:
			target_entity.current_mana = 0
			can_continue = false
	
	if stamina_drain_per_second > 0:
		target_entity.current_stamina -= stamina_drain_per_second
		if target_entity.current_stamina < 0:
			target_entity.current_stamina = 0
			can_continue = false
	
	if not can_continue:
		deactivate(target_entity)

## AOE EFFECTS

func _on_effect_tick() -> void:
	if not _is_toggled_on:
		return
	_update_aura_effects()

func _update_aura_effects() -> void:
	if not target_entity or not is_instance_valid(target_entity):
		return
	
	# Find entities in range
	var entities_in_range := _get_entities_in_aura_range()
	
	var new_allies: Array[Entity] = []
	var new_enemies: Array[Entity] = []
	
	for entity in entities_in_range:
		if _is_ally(target_entity, entity):
			if not _affected_allies.has(entity):
				_apply_effects_to_ally(entity)
			new_allies.append(entity)
		elif _is_enemy(target_entity, entity):
			if not _affected_enemies.has(entity):
				_apply_effects_to_enemy(entity)
			new_enemies.append(entity)
	
	# Remove effects from entities that left range
	var left_allies = _affected_allies.duplicate()
	for ally in left_allies:
		if not new_allies.has(ally):
			_remove_effects_from_ally(ally)
	
	var left_enemies = _affected_enemies.duplicate()
	for enemy in left_enemies:
		if not new_enemies.has(enemy):
			_remove_effects_from_enemy(enemy)
	
	_affected_allies = new_allies
	_affected_enemies = new_enemies

func _get_entities_in_aura_range() -> Array[Entity]:
	var entities: Array[Entity] = []
	
	if not target_entity or not is_instance_valid(target_entity):
		return entities
	
	# Use 3D sphere detection with optional LOS blocking
	var blocking_mode := PhysicsArea.BlockingMode.NONE
	if aura_respects_geometry:
		blocking_mode = PhysicsArea.BlockingMode.WALLS_ONLY
	
	var target_pos := target_entity.global_position
	
	# Direct sphere query for entities in range
	var space_state := target_entity.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = aura_radius
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, target_pos)
	query.collision_mask = 0b0000001  # Entities layer
	
	var results := space_state.intersect_shape(query, 100)
	
	for result in results:
		var entity = result["collider"]
		if entity is Entity and entity != target_entity:
			# If respecting geometry, check line of sight
			if aura_respects_geometry:
				var entity_pos := entity.global_position + Vector3(0, 1.0, 0)
				var caster_pos := target_pos + Vector3(0, 1.5, 0)
				var los_query := PhysicsRayQueryParameters3D.create(caster_pos, entity_pos)
				los_query.collision_mask = 0b0000010  # Walls layer
				var los_result := space_state.intersect_ray(los_query)
				if not los_result.is_empty():
					continue  # Blocked by wall
			entities.append(entity)
	
	return entities

func _is_ally(source: Entity, target: Entity) -> bool:
	# Check if target is an ally (same party/guild, or friendly NPC)
	# For now, simplified: if target has team_id and matches
	if source.team_id != 0 and source.team_id == target.team_id:
		return true
	# Player is always ally to friendly NPCs
	if target.entity_type == EntityType.NPC and target.faction == Faction.FRIENDLY:
		return true
	return false

func _is_enemy(source: Entity, target: Entity) -> bool:
	# Check if target is an enemy
	if source.team_id != 0 and source.team_id != target.team_id:
		return true
	if target.entity_type == EntityType.ENEMY:
		return true
	if target.entity_type == EntityType.NPC and target.faction == Faction.HOSTILE:
		return true
	return false

## EFFECT APPLICATION

func _apply_self_effects(entity: Entity, applying: bool) -> void:
	var sign := 1 if applying else -1
	
	if self_damage_boost != 0:
		entity.stats.damage_multiplier += sign * self_damage_boost
	
	if self_defense_boost != 0:
		entity.stats.defense_multiplier += sign * self_defense_boost

func _apply_effects_to_ally(ally: Entity) -> void:
	if ally_damage_boost != 0:
		ally.stats.damage_multiplier += ally_damage_boost
	if ally_defense_boost != 0:
		ally.stats.defense_multiplier += ally_defense_boost
	if ally_health_regen > 0:
		ally.current_health = min(ally.max_health, ally.current_health + ally_health_regen)
	if ally_mana_regen > 0:
		ally.current_mana = min(ally.max_mana, ally.current_mana + ally_mana_regen)

func _remove_effects_from_ally(ally: Entity) -> void:
	if not is_instance_valid(ally):
		return
	if ally_damage_boost != 0:
		ally.stats.damage_multiplier -= ally_damage_boost
	if ally_defense_boost != 0:
		ally.stats.defense_multiplier -= ally_defense_boost

func _apply_effects_to_enemy(enemy: Entity) -> void:
	if enemy_damage_reduction != 0:
		enemy.stats.damage_multiplier -= enemy_damage_reduction
	if enemy_slow_percent != 0:
		enemy.stats.movement_speed_multiplier -= enemy_slow_percent
	if enemy_armor_reduction != 0:
		enemy.stats.armor_multiplier -= enemy_armor_reduction

func _remove_effects_from_enemy(enemy: Entity) -> void:
	if not is_instance_valid(enemy):
		return
	if enemy_damage_reduction != 0:
		enemy.stats.damage_multiplier += enemy_damage_reduction
	if enemy_slow_percent != 0:
		enemy.stats.movement_speed_multiplier += enemy_slow_percent
	if enemy_armor_reduction != 0:
		enemy.stats.armor_multiplier += enemy_armor_reduction

func _remove_effects_from_allies() -> void:
	for ally in _affected_allies:
		if is_instance_valid(ally):
			_remove_effects_from_ally(ally)

func _remove_effects_from_enemies() -> void:
	for enemy in _affected_enemies:
		if is_instance_valid(enemy):
			_remove_effects_from_enemy(enemy)

## INFO

func is_active() -> bool:
	return _is_toggled_on

func get_aura_info() -> Dictionary:
	return {
		"name": buff_name,
		"type": AuraType.keys()[aura_type],
		"active": _is_toggled_on,
		"radius": aura_radius,
		"mana_drain": mana_drain_per_second,
		"stamina_drain": stamina_drain_per_second,
		"affected_allies": _affected_allies.size(),
		"affected_enemies": _affected_enemies.size()
	}

func remove(target_entity: Entity) -> void:
	deactivate(target_entity)
	super.remove(target_entity)
