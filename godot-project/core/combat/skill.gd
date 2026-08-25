## Skill - Definition for combat skills
## Can be instant, channeled, or ground-targeted
class_name Skill
extends Resource

enum SkillType {
	MELEE,          # Close range attack
	RANGED,          # Projectile attack
	INSTANT,         # Instant effect
	GROUND_TARGETED,  # AoE at target location
	SELF,            # Affects self
	CHANNEL          # Held to cast
}

enum TargetType {
	SINGLE_ENEMY,
	MULTIPLE_ENEMY,
	SELF,
	ALLY,
	GROUND
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

var remaining_cooldown: float = 0.0

func _init() -> void:
	if skill_id == "":
		skill_id = skill_name.to_lower().replace(" ", "_")

func can_cast(caster: Entity) -> bool:
	# Check cooldown
	if remaining_cooldown > 0:
		return false
	
	# Check resources
	if caster.current_mana < mana_cost:
		return false
	if caster.current_stamina < stamina_cost:
		return false
	if caster.current_health < health_cost:
		return false
	
	# Check level
	if caster.level < required_level:
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
	if caster.current_mana < mana_cost:
		return false
	if caster.current_stamina < stamina_cost:
		return false
	if caster.current_health < health_cost:
		return false
	
	caster.current_mana -= mana_cost
	caster.current_stamina -= stamina_cost
	caster.current_health -= health_cost
	
	return true

func calculate_damage(caster: Entity, target: Entity) -> int:
	var base_damage := damage
	
	# Apply caster's attack power
	if damage_type == "physical":
		base_damage += caster.get_attack_power()
	elif damage_type == "magical":
		base_damage += caster.get_spell_power()
	
	# Apply crit chance
	var crit_chance := caster.get_crit_chance()
	var is_crit := randf() < crit_chance
	if is_crit:
		base_damage = int(base_damage * caster.get_crit_multiplier())
	
	# Apply target's defense
	var defense := target.get_defense() if target else 0
	var reduction := float(defense) / (defense + 100.0)
	base_damage = int(base_damage * (1.0 - reduction))
	
	return max(1, base_damage)

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
	# Create DoT effect
	pass

func applyTeleport(caster: Entity, ground_position: Vector3) -> void:
	if ground_position != Vector3.ZERO:
		caster.global_position = ground_position
	else:
		# Teleport forward
		var forward := -caster.global_transform.basis.z
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
