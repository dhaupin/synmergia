## Skill - Definition for combat skills
## Can be instant, channeled, or ground-targeted
extends Resource
class_name Skill
const StatusEffect = preload("res://core/entities/status_effect.gd")
const SkillSchema = preload("res://core/schemas/skill.gd")
# Entity is not an autoload (class_name only). Several method
# signatures here use `: Entity`, which requires Entity's class_name
# to be registered at parse time. Preloading it here guarantees that.
const Entity = preload("res://core/entities/entity.gd")


enum SkillType {
	MELEE,           # Close range attack
	RANGED,          # Projectile attack
	INSTANT,         # Instant effect
	GROUND_TARGETED, # AoE at target location
	TARGETED_AOE,    # AoE centered on target
	SELF,            # Affects self
	CHANNEL,         # Held to cast
	PROJECTILE_AOE   # Projectile that explodes on impact
}

enum TargetType {
	SINGLE_ENEMY,
	MULTIPLE_ENEMY,
	SELF,
	ALLY,
	GROUND,
	TARGETED_AOE,    # Target + nearby enemies
}

@export var skill_name: String = "Skill"
@export var skill_id: String = ""
@export var description: String = ""

# Classification
@export var skill_type: SkillType = SkillType.MELEE
@export var target_type: TargetType = TargetType.SINGLE_ENEMY

# Costs
@export var mana_cost: int = 0
@export var stamina_cost: float = 0.0
@export var health_cost: int = 0  # Some skills cost health

# Timing
@export var cast_time: float = 0.0  # 0 = instant
@export var cooldown: float = 0.0
@export var animation_duration: float = 0.4
@export var recovery_time: float = 0.0  # Recovery after attack

# Targeting
@export var range: float = 2.5  # Distance to target
@export var aoe_radius: float = 0.0  # 0 = single target
@export var is_ground_targeted: bool = false
@export var ground_target_range: float = 30.0  # Max distance for ground target

# Targeted AOE (hits target + splash around them)
@export var targeted_aoe_radius: float = 0.0  # Splash radius around target
@export var targeted_aoe_max_targets: int = 0  # 0 = unlimited
@export var targeted_aoe_los_required: bool = true  # Need line of sight to splash targets
@export var targeted_aoe_respects_geometry: bool = false  # Walls block splash

# Projectile AOE (explodes on impact)
@export var projectile_speed: float = 20.0  # Projectile travel speed
@export var projectile_piercing: bool = false  # Pierce through first target
@export var projectile_explosion_radius: float = 0.0  # Explosion AoE on impact

# Effects
@export var damage: int = 0
@export var damage_type: String = "physical"  # physical, magical, true
@export var is_dot: bool = false  # Damage over time
@export var dot_duration: float = 0.0
@export var dot_tick_rate: float = 1.0

# Crowd Control
@export var crowd_control_type: String = ""  # stun, root, slow, etc.
@export var crowd_control_duration: float = 0.0
@export var crowd_control_strength: float = 1.0

# Defensive
@export var grants_shield: int = 0
@export var grants_invincibility: bool = false
@export var invincibility_duration: float = 0.0

# Utility
@export var teleport_distance: float = 0.0
@export var movement_speed_mod: float = 0.0  # % movement speed buff
@export var movement_speed_duration: float = 0.0

# Movement during cast
@export var allow_movement: bool = true
@export var allow_jumping: bool = true
@export var allow_dodging: bool = true
@export var interrupt_on_move: bool = false  # Movement cancels skill

# Hitbox
@export var hitbox_size: float = 1.5  # Size of hitbox
@export var hitbox_offset: Vector3 = Vector3(0, 0, 1.5)  # Offset from player

# Animation
@export var animation_name: String = "strike"

# Combo
@export var combo_chain: Array[String] = []  # Skills that can follow this
@export var combo_window: float = 2.0  # Time window for combo

# Requirements
@export var required_level: int = 1
@export var required_class: String = ""  # Empty = all classes
@export var required_stance: String = ""  # e.g., "BattleStance"

# Visual
@export var vfx_projectile: String = ""
@export var vfx_impact: String = ""
@export var sfx_cast: String = ""
@export var sfx_impact: String = ""

# Skill Academy upgrade state
var upgrade_level: int = 0
var upgrade_unlocks: Array = []

# Heals
@export var heal_amount: int = 0
@export var hot_heal: int = 0
@export var hot_duration: float = 0.0
@export var hot_tick_rate: float = 1.0

# DoT
@export var dot_damage: int = 0

# Charge system (set charge_time_max > 0 to enable)
@export var charge_time_max: float = 0.0
@export var charge_damage_curve: String = "linear"

# Schema reference for upgrade lookups
var schema: SkillSchema = null

var remaining_cooldown: float = 0.0

func _init() -> void:
	if skill_id == "":
		skill_id = skill_name.to_lower().replace(" ", "_")

func can_cast(caster: Node) -> bool:
	# Check cooldown
	if remaining_cooldown > 0:
		return false
	
	# Check resources
	if "current_mana" in caster and caster.current_mana < mana_cost:
		return false
	if "current_stamina" in caster and caster.current_stamina < stamina_cost:
		return false
	if "current_health" in caster and caster.current_health < health_cost:
		return false
	
	# Check level
	if "level" in caster and caster.level < required_level:
		return false
	
	# Check class
	if required_class != "" and caster.get("character_class") != required_class:
		return false
	
	return true

func execute(caster: Entity, target: Entity = null, ground_position: Vector3 = Vector3.ZERO) -> Dictionary:
	var result := {
		"success": false,
		"damage_dealt": 0,
		"effects_applied": [],
		"targets_hit": []
	}
	
	# Consume resources
	if not consume_resources(caster):
		return result
	
	# Start cooldown
	remaining_cooldown = cooldown
	
	# Calculate damage
	if damage > 0:
		var actual_damage := calculate_damage(caster, target)
		result.damage_dealt = actual_damage
		
		if target:
			target.take_damage(actual_damage, caster)
			result.targets_hit.append(target)
	
	# Apply healing
	if heal_amount > 0:
		var actual_heal := calculate_healing(caster)
		result.heal_amount = actual_heal
		
		if target:
			target.heal(actual_heal)
		else:
			caster.heal(actual_heal)
	
	# Apply heal-over-time (HoT)
	if hot_heal > 0 and hot_duration > 0:
		var hot := StatusEffect.new()
		hot.effect_id = skill_id + "_hot"
		hot.effect_name = skill_name + " HoT"
		hot.effect_type = StatusEffect.EffectType.BUFF
		hot.tick_behavior = StatusEffect.TickBehavior.TICKED
		hot.tick_interval = hot_tick_rate if hot_tick_rate > 0 else 1.0
		hot.duration = hot_duration
		hot.tick_heal = hot_heal
		
		if target:
			target.apply_status_effect(hot)
		else:
			caster.apply_status_effect(hot)
	
	# Apply crowd control
	if crowd_control_type != "":
		applyCrowdControl(caster, target, ground_position)
	
	# Apply other effects
	if grants_shield > 0:
		applyShield(caster)
	
	if grants_invincibility:
		applyInvincibility(caster)
	
	if is_dot:
		applyDoT(caster, target)
	
	if teleport_distance > 0:
		applyTeleport(caster, ground_position)
	
	result.success = true
	return result

func consume_resources(caster: Entity) -> bool:
	if "current_mana" in caster and caster.current_mana < mana_cost:
		return false
	if "current_stamina" in caster and caster.current_stamina < stamina_cost:
		return false
	if "current_health" in caster and caster.current_health < health_cost:
		return false
	
	caster.current_mana -= mana_cost
	caster.current_stamina -= stamina_cost
	caster.current_health -= health_cost
	
	return true

func calculate_damage(caster: Entity, target: Entity) -> int:
	var base_damage := damage
	
	# Apply caster's attack power based on damage type
	if damage_type == "physical":
		base_damage += caster.get_attack_power()
	elif damage_type == "magical":
		base_damage += caster.get_spell_power()
	
	# Apply crit chance
	var crit_chance: float = caster.get_crit_chance()
	var is_crit: bool = randf() < crit_chance
	if is_crit:
		base_damage = int(base_damage * caster.get_crit_multiplier())
	
	# Apply target's defense
	var defense: float = target.get_defense() if target else 0
	var reduction: float = float(defense) / (defense + 100.0)
	base_damage = int(base_damage * (1.0 - reduction))
	
	return max(1, base_damage)

func calculate_healing(caster: Entity) -> int:
	var base_heal := heal_amount
	
	# Apply caster's healing power (WIS-based)
	base_heal += caster.get_healing_power()
	
	return base_heal

func applyCrowdControl(caster: Entity, target: Entity, _ground_position: Vector3) -> void:
	# Apply CC effect based on type
	match crowd_control_type:
		"stun":
			target.apply_status_effect(create_stun_effect(caster))
		"root":
			target.apply_status_effect(create_root_effect(caster))
		"slow":
			target.apply_status_effect(create_slow_effect(caster))

func applyShield(caster: Entity) -> void:
	# Create shield buff
	pass

func applyInvincibility(caster: Entity) -> void:
	# Create invincibility buff
	pass

func applyDoT(caster: Entity, target: Entity) -> void:
	if target == null:
		return
	
	var dot := StatusEffect.new()
	dot.effect_id = skill_id + "_dot"
	dot.effect_name = skill_name + " DoT"
	dot.effect_type = StatusEffect.EffectType.DEBUFF
	dot.effect_category = StatusEffect.EffectCategory.POISON
	dot.tick_behavior = StatusEffect.TickBehavior.TICKED
	dot.tick_interval = dot_tick_rate if dot_tick_rate > 0 else 1.0
	dot.duration = dot_duration
	dot.tick_damage = dot_damage
	
	target.apply_status_effect(dot)

func applyTeleport(caster: Entity, ground_position: Vector3) -> void:
	if ground_position != Vector3.ZERO:
		caster.global_position = ground_position
	else:
		# Teleport forward
		var forward: Vector3 = -caster.global_transform.basis.z
		forward.y = 0
		caster.global_position += forward * teleport_distance

func create_stun_effect(_caster: Entity) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.effect_name = "Stunned"
	effect.effect_type = StatusEffect.EffectType.DEBUFF
	effect.duration = crowd_control_duration
	return effect

func create_root_effect(_caster: Entity) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.effect_name = "Rooted"
	effect.effect_type = StatusEffect.EffectType.DEBUFF
	effect.duration = crowd_control_duration
	return effect

func create_slow_effect(_caster: Entity) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.effect_name = "Slowed"
	effect.effect_type = StatusEffect.EffectType.DEBUFF
	effect.duration = crowd_control_duration
	return effect

func _physics_process(delta: float) -> void:
	if remaining_cooldown > 0:
		remaining_cooldown = max(0, remaining_cooldown - delta)

func get_cooldown_remaining() -> float:
	return remaining_cooldown

func get_cooldown_percent() -> float:
	if cooldown == 0:
		return 1.0
	return 1.0 - (remaining_cooldown / cooldown)
