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
	PROJECTILE_AOE
}

enum TargetType {
	SINGLE_ENEMY,
	MULTIPLE_ENEMY,
	SELF,
	ALLY,
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
func can_cast(caster: Entity) -> bool:
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
func execute(caster: Entity, target: Entity = null, ground_pos: Vector3 = Vector3.ZERO) -> Dictionary:
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

func _consume_resources(caster: Entity) -> void:
	caster.current_mana -= mana_cost
	caster.current_stamina -= stamina_cost
	caster.current_health -= health_cost

func _apply_effects(caster: Entity, target: Entity, ground_pos: Vector3, result: Dictionary) -> void:
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
			"buff":
				# Apply buff from effect data
				pass
			"debuff":
				# Apply debuff to target
				pass

func _physics_process(delta: float) -> void:
	if remaining_cooldown > 0:
		remaining_cooldown = max(0, remaining_cooldown - delta)

func get_cooldown_remaining() -> float:
	return remaining_cooldown

func get_info() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"type": SkillType.keys()[skill_type],
		"mana_cost": mana_cost,
		"cooldown": cooldown,
		"range": range
	}
