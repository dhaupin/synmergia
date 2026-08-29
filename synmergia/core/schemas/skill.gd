## Skill - Combat skill definition
## Base schema for all skills (spells, attacks, abilities)
class_name Skill
extends Resource

enum SkillType {
	MELEE,
	RANGED,
	INSTANT,
	GROUND_TARGETED,
	TARGETED_AOE,
	SELF,
	CHANNEL,
	PROJECTILE_AOE,
	REVIVE  # Resurrect a dead ally
}

enum TargetType {
	SINGLE_ENEMY,
	MULTIPLE_ENEMY,
	SELF,
	ALLY,
	DEAD_ALLY,  # Target dead allies for revive
	GROUND,
	TARGETED_AOE
}

@export var id: String = ""
@export var display_name: String = "Skill"
@export var description: String = ""
@export var icon_path: String = ""

# Classification
@export var skill_type: SkillType = SkillType.MELEE
@export var target_type: TargetType = TargetType.SINGLE_ENEMY

# Costs
@export var mana_cost: int = 0
@export var stamina_cost: float = 0.0
@export var health_cost: int = 0
@export var cooldown: float = 0.0

# Timing
@export var cast_time: float = 0.0  # 0 = instant
@export var animation_duration: float = 0.4
@export var recovery_time: float = 0.0
@export var can_interrupt: bool = true  # Can be interrupted by damage
@export var uses_gcd: bool = true       # Triggers global cooldown

# Targeting
@export var range: float = 2.5
@export var aoe_radius: float = 0.0
@export var targeted_aoe_radius: float = 0.0
@export var max_targets: int = 0  # 0 = unlimited

# Effects (array of EffectData dictionaries)
@export var effects: Array[Dictionary] = []

# Requirements
@export var required_level: int = 1
@export var required_class: String = ""  # Empty = all classes
@export var required_stance: String = ""

# Visual/Audio
@export var vfx_cast: String = ""
@export var vfx_impact: String = ""
@export var sfx_cast: String = ""
@export var sfx_impact: String = ""

var remaining_cooldown: float = 0.0

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Check if entity can cast this skill
func can_cast(caster: SynmergiaEntity) -> bool:
	if remaining_cooldown > 0:
		return false
	if caster.current_mana < mana_cost:
		return false
	if caster.current_stamina < stamina_cost:
		return false
	if caster.current_health < health_cost:
		return false
	if caster.level < required_level:
		return false
	return true

## Execute the skill
func execute(caster: SynmergiaEntity, target: SynmergiaEntity = null, ground_pos: Vector3 = Vector3.ZERO) -> Dictionary:
	var result := {
		"success": false,
		"damage_dealt": 0,
		"effects_applied": [],
		"targets_hit": []
	}
	
	if not can_cast(caster):
		return result
	
	# Consume resources
	_consume_resources(caster)
	
	# Start cooldown
	remaining_cooldown = cooldown
	
	# Apply effects
	_apply_effects(caster, target, ground_pos, result)
	
	result["success"] = true
	return result

func _consume_resources(caster: SynmergiaEntity) -> void:
	caster.current_mana -= mana_cost
	caster.current_stamina -= stamina_cost
	caster.current_health -= health_cost

func _apply_effects(caster: SynmergiaEntity, target: SynmergiaEntity, ground_pos: Vector3, result: Dictionary) -> void:
	for effect in effects:
		match effect.get("type", ""):
			"damage":
				var dmg := effect.get("value", 0) as int
				if target:
					target.take_damage(dmg, caster)
					result["targets_hit"].append(target)
					result["damage_dealt"] += dmg
			"heal":
				var amount := effect.get("value", 0) as int
				if caster:
					caster.heal(amount)
			"revive":
				# Handle revive effect
				var success := _apply_revive(caster, target, effect, result)
				if success:
					result["targets_hit"].append(target)
			"buff":
				# Apply buff from effect data
				pass
			"debuff":
				# Apply debuff to target
				pass

## Apply revive effect
func _apply_revive(caster: SynmergiaEntity, target: SynmergiaEntity, effect: Dictionary, result: Dictionary) -> bool:
	if not target or not caster:
		return false
	
	# Check if target is actually dead
	if not target.health_component or not target.health_component.is_dead():
		result["failure_reason"] = "Target is not dead"
		return false
	
	# Check range if specified
	if range > 0:
		var distance := caster.global_position.distance_to(target.global_position)
		if distance > range:
			result["failure_reason"] = "Target out of range"
			return false
	
	# Use RespawnService to perform the revive
	var context: String = effect.get("context", "open_world")
	if RespawnService:
		# Start the revival process
		var success := RespawnService.start_revival(caster, target, context)
		if success:
			result["revive_started"] = true
			return true
		else:
			result["failure_reason"] = "Revive failed (abuse detection or restrictions)"
			return false
	
	# Fallback if no RespawnService
	result["failure_reason"] = "Revive system not available"
	return false

func _physics_process(delta: float) -> void:
	if remaining_cooldown > 0:
		remaining_cooldown = max(0, remaining_cooldown - delta)

func get_cooldown_remaining() -> float:
	return remaining_cooldown

## Find dead allies within range (for revive skills)
static func find_dead_allies(caster: SynmergiaEntity, max_range: float) -> Array[SynmergiaEntity]:
	var dead_allies: Array[SynmergiaEntity] = []
	
	if not caster or not caster.health_component:
		return dead_allies
	
	var caster_pos := caster.global_position
	
	# Get all entities in range from EntityService
	var nearby_entities := EntityService.get_entities_in_radius(caster_pos, max_range)
	
	for entity in nearby_entities:
		# Skip self
		if entity == caster:
			continue
		
		# Check if it's a dead ally (same team/faction, dead)
		if entity.health_component and entity.health_component.is_dead():
			# Check if ally (same team or friendly)
			if _is_ally(caster, entity):
				dead_allies.append(entity)
	
	return dead_allies

## Check if two entities are allies
static func _is_ally(entity_a: SynmergiaEntity, entity_b: SynmergiaEntity) -> bool:
	# Same entity
	if entity_a == entity_b:
		return true
	
	# Check party
	if entity_a.has("party_id") and entity_b.has("party_id"):
		if entity_a.party_id != "" and entity_a.party_id == entity_b.party_id:
			return true
	
	# Check guild
	if entity_a.has("guild_id") and entity_b.has("guild_id"):
		if entity_a.guild_id != "" and entity_a.guild_id == entity_b.guild_id:
			return true
	
	# Check faction (friendly)
	if entity_a.has("faction_id") and entity_b.has("faction_id"):
		if entity_a.faction_id == entity_b.faction_id:
			return true
	
	# Check team (for PvP)
	if entity_a.has("team_id") and entity_b.has("team_id"):
		if entity_a.team_id == entity_b.team_id:
			return true
	
	return false

func get_info() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"type": SkillType.keys()[skill_type],
		"mana_cost": mana_cost,
		"cooldown": cooldown,
		"range": range
	}
