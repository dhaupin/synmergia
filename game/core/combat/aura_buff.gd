## AuraBuff - Toggle aura that affects nearby entities
## Continuous mana/stamina drain while active, AoE effects.
## Extracted from buff.gd (round 27): a second class_name in that file
## is a GDScript parse error ("Unexpected class_name in class body"),
## which left the whole buff/effect stack unparseable and dormant.
## The body's undefined references were repaired in the move:
## target_entity -> target (the base StatusEffect field), the phantom
## Faction enum -> Entity.Relation, and the one-time activation costs
## are declared exports instead of undeclared identifiers.
extends Buff

class_name AuraBuff

enum AuraType {
	ALLY_BOOST,    # Positive effects to nearby allies
	ENEMY_DEBUFF,  # Negative effects to nearby enemies
	AREA_BUFF,     # Buff to self and allies in range
	AREA_DEBUFF    # Debuff to enemies in range
}

@export var aura_type: AuraType = AuraType.AREA_BUFF
@export var aura_respects_geometry: bool = false  # Walls block aura detection (false = goes through walls)

# One-time activation cost (paid on toggle-on). Base StatusEffect
# already exports aura_radius; Buff already owns the cost exports.
@export var aura_cost_mana: float = 10.0
@export var aura_cost_stamina: float = 5.0

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
var _affected_allies: Array = []
var _affected_enemies: Array = []
var _physics_area: PhysicsArea  # 3D sphere detection


func _init() -> void:
	super._init()
	effect_type = EffectType.BUFF
	if effect_id == "":
		effect_id = effect_name.to_lower().replace(" ", "_") + "_aura"

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
	if target_entity.current_mana < aura_cost_mana:
		return false
	if target_entity.current_stamina < aura_cost_stamina:
		return false

	# Pay activation cost
	target_entity.current_mana -= aura_cost_mana
	target_entity.current_stamina -= aura_cost_stamina

	_is_toggled_on = true

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
	_affected_allies.clear()
	_affected_enemies.clear()

## DRAIN

func _on_drain_tick() -> void:
	if not _is_toggled_on or not target or not is_instance_valid(target):
		if target and is_instance_valid(target):
			deactivate(target)
		return

	# Check if entity has enough resources
	var can_continue := true

	if mana_drain_per_second > 0:
		target.current_mana -= mana_drain_per_second
		if target.current_mana < 0:
			target.current_mana = 0
			can_continue = false

	if stamina_drain_per_second > 0:
		target.current_stamina -= stamina_drain_per_second
		if target.current_stamina < 0:
			target.current_stamina = 0
			can_continue = false

	if not can_continue:
		deactivate(target)

## AOE EFFECTS

func _on_effect_tick() -> void:
	if not _is_toggled_on:
		return
	_update_aura_effects()

func _update_aura_effects() -> void:
	if not target or not is_instance_valid(target):
		return

	# Find entities in range
	var entities_in_range := _get_entities_in_aura_range()

	var new_allies: Array = []
	var new_enemies: Array = []

	for entity in entities_in_range:
		if _is_ally(target, entity):
			if not _affected_allies.has(entity):
				_apply_effects_to_ally(entity)
			new_allies.append(entity)
		elif _is_enemy(target, entity):
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

func _get_entities_in_aura_range() -> Array:
	var entities: Array = []

	if not target or not is_instance_valid(target):
		return entities

	# Use 3D sphere detection with optional LOS blocking
	var blocking_mode := PhysicsArea.BlockingMode.NONE
	if aura_respects_geometry:
		blocking_mode = PhysicsArea.BlockingMode.WALLS_ONLY

	var target_pos: Vector3 = target.global_position

	# Direct sphere query for entities in range
	var space_state: PhysicsDirectSpaceState3D = target.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = aura_radius
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, target_pos)
	query.collision_mask = Layers.layer_bit("entity")  # Entities layer

	var results: Array = space_state.intersect_shape(query, 100)

	for result in results:
		var entity = result["collider"]
		if entity is Entity and entity != target:
			# If respecting geometry, check line of sight
			if aura_respects_geometry:
				var entity_pos: Vector3 = entity.global_position + Vector3(0, 1.0, 0)
				var caster_pos: Vector3 = target_pos + Vector3(0, 1.5, 0)
				var los_query := PhysicsRayQueryParameters3D.create(caster_pos, entity_pos)
				los_query.collision_mask = Layers.layer_bit("solid")  # Walls layer
				var los_result: Dictionary = space_state.intersect_ray(los_query)
				if not los_result.is_empty():
					continue  # Blocked by wall
			entities.append(entity)

	return entities

func _is_ally(source: Entity, target: Entity) -> bool:
	# Ally law: shared team, or a friendly-dispositioned NPC.
	if source.team_id != 0 and source.team_id == target.team_id:
		return true
	if target.entity_type == Entity.EntityType.NPC and target.relation == Entity.Relation.FRIENDLY:
		return true
	return false

func _is_enemy(source: Entity, target: Entity) -> bool:
	if source.team_id != 0 and target.team_id != 0 and source.team_id != target.team_id:
		return true
	if target.entity_type == Entity.EntityType.ENEMY:
		return true
	if target.entity_type == Entity.EntityType.NPC and target.relation == Entity.Relation.HOSTILE:
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

func is_toggled_on() -> bool:
	return _is_toggled_on

func get_aura_info() -> Dictionary:
	return {
		"name": effect_name,
		"type": AuraType.keys()[aura_type],
		"active": _is_toggled_on,
		"radius": aura_radius,
		"mana_drain": mana_drain_per_second,
		"stamina_drain": stamina_drain_per_second,
		"affected_allies": _affected_allies.size(),
		"affected_enemies": _affected_enemies.size()
	}

func remove(target_entity: Node) -> void:
	deactivate(target_entity as Entity)
	super.remove(target_entity)
