## Skill - Definition for combat skills
## Can be instant, channeled, or ground-targeted
extends Resource
class_name Skill
const StatusEffect = preload("res://core/entities/status_effect.gd")
const SkillSchema = preload("res://core/schemas/skill.gd")
# CombatMath runs the MWo-style hit table (miss/dodge/parry/block/crit)
# inside calculate_damage; no cycle -- combat_math no longer preloads
# this file.
const CombatMath = preload("res://core/services/combat_math.gd")
# Entity is preloaded for EntityType constants (e.g. the heal-threat
# radius scan). Caster/target method params are deliberately untyped so
# PlayerController (a CharacterBody3D) can cast without an Entity cast.
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


## Build a runtime Skill from a SkillSchema resource (.tres in
## data/skills/). The .tres files load as SkillSchema; the combat
## pipeline (CombatSystem, attack state) runs on this class. Maps the
## shared fields by name, flattens the schema's effect dictionaries
## into the runtime damage/heal fields (the runtime class has no
## effects array), and translates enums BY NAME (the two TargetType
## enums have different orderings -- DEAD_ALLY exists only in the
## schema).
static func from_schema(s: SkillSchema) -> Skill:
	var sk: Skill = Skill.new()
	sk.skill_id = s.id
	sk.skill_name = s.display_name
	sk.description = s.description
	# SkillType: the first 8 members align (REVIVE is schema-only).
	var st_values: Array = SkillType.values()
	sk.skill_type = st_values[mini(int(s.skill_type), st_values.size() - 1)]
	# TargetType: translate by NAME; unknown names fall back to single.
	var tt_names: Array = SkillSchema.TargetType.keys()
	var tt_name: String = tt_names[int(s.target_type)] if int(s.target_type) < tt_names.size() else "SINGLE_ENEMY"
	sk.target_type = TargetType[tt_name] if TargetType.has(tt_name) else TargetType.SINGLE_ENEMY
	sk.is_ground_targeted = tt_name == "GROUND"
	sk.mana_cost = s.mana_cost
	sk.stamina_cost = s.stamina_cost
	sk.health_cost = s.health_cost
	sk.cooldown = s.cooldown
	sk.cast_time = s.cast_time
	sk.animation_duration = s.animation_duration
	sk.recovery_time = s.recovery_time
	sk.range = s.range
	sk.aoe_radius = s.aoe_radius
	sk.targeted_aoe_radius = s.targeted_aoe_radius
	sk.required_level = s.required_level
	sk.required_class = s.required_class
	sk.required_stance = s.required_stance
	sk.schema = s
	# Flatten effect dictionaries into runtime fields.
	for effect: Dictionary in s.effects:
		match str(effect.get("type", "")):
			"damage":
				sk.damage += int(effect.get("value", 0))
			"heal":
				sk.heal_amount += int(effect.get("value", 0))
			"stun", "root", "slow":
				sk.crowd_control_type = str(effect.get("type", ""))
				sk.crowd_control_duration = float(effect.get("duration", 0.0))
	return sk

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

## Heal threat: push threat onto the tables of in-combat enemies near
## the healed target. Silent no-op when EntityService is unavailable
## (parse-time) or no enemies are in combat nearby. Interest law is
## the shared helper (round 10).
const EntityInterest = preload("res://core/services/entity_interest.gd")

func _generate_heal_threat(healer, heal_amount: int) -> void:
	var es = _entity_service()
	if es == null or heal_amount <= 0:
		return
	var heal_pos: Vector3 = healer.global_position
	var nearby: Array = EntityInterest.query_interest(heal_pos, 20.0)
	for enemy in nearby:
		if not is_instance_valid(enemy):
			continue
		var ac = enemy.get("aggro_component")
		if ac != null and ac._is_in_combat:
			ac.record_heal_threat(healer, heal_amount)

func _entity_service():
	# Autoloads are unavailable at parse time; resolve via the scene tree.
	var ml = Engine.get_main_loop()
	if ml == null or not ml is SceneTree:
		return null
	return (ml as SceneTree).root.get_node_or_null("EntityService")

## defer_target_effects: hitbox-family casts pass true -- the hitbox
## sweep (_apply_hit -> _apply_skill_effects) owns DoT/CC/teleport on
## LANDED hits only (a stunned target must not eat CC off a dodged
## swing). Without it, every landed hit double-applied the effects
## (once here at cast, once per hit).
func execute(caster, target = null, ground_position: Vector3 = Vector3.ZERO, defer_target_effects: bool = false) -> Dictionary:
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
			if CombatMath.is_whiff(int(_last_hit_result.get("hit_result", CombatMath.HitResult.HIT))):
				# Miss/dodge/parry/immune: no damage, no on-hit effects, no
				# take_damage(0) (Enemy's armor floor would chip 1). The HUD
				# learns about it through hit_resolved.
				result.whiff = true
				EventHub.hit_resolved.emit(caster, target, _last_hit_result, self, 0)
			else:
				target.take_damage(actual_damage, caster, damage_type, _last_was_crit)
				result.targets_hit.append(target)
				EventHub.hit_resolved.emit(caster, target, _last_hit_result, self, actual_damage)

	# Apply healing
	if heal_amount > 0:
		var actual_heal := calculate_healing(caster)
		result.heal_amount = actual_heal

		if target:
			target.heal(actual_heal)
		else:
			caster.heal(actual_heal)

		# Heal threat: healing in combat draws enemy attention. Notify
		# every nearby enemy in combat so their tables add threat on the
		# healer (classic healer-aggro; AggroComponent scales by factor).
		_generate_heal_threat(caster, actual_heal)

	# Apply heal-over-time (HoT). Target-side: deferred on hitbox casts
	# (self-HoT with no target still applies at cast).
	if hot_heal > 0 and hot_duration > 0 and (not defer_target_effects or target == null):
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

	# Apply crowd control (deferred on hitbox casts: landed hits only)
	if crowd_control_type != "" and not defer_target_effects:
		applyCrowdControl(caster, target, ground_position)

	# Apply other effects
	if grants_shield > 0:
		applyShield(caster)

	if grants_invincibility:
		applyInvincibility(caster)

	if is_dot and not defer_target_effects:
		applyDoT(caster, target)

	if teleport_distance > 0 and not defer_target_effects:
		applyTeleport(caster, ground_position)

	result.success = true
	return result

func consume_resources(caster) -> bool:
	if "current_mana" in caster and caster.current_mana < mana_cost:
		return false
	if "current_stamina" in caster and caster.current_stamina < stamina_cost:
		return false
	if "current_health" in caster and caster.current_health < health_cost:
		return false

	# Duck-typed writes: PlayerController carries mana but no stamina;
	# test stubs may carry neither.
	if mana_cost > 0 and "current_mana" in caster:
		caster.current_mana -= mana_cost
	if stamina_cost > 0 and "current_stamina" in caster:
		caster.current_stamina -= stamina_cost
	if health_cost > 0 and "current_health" in caster:
		caster.current_health -= health_cost

	return true

## Hit-table roll + hit-aware damage for one swing. The full result is
## cached in _last_hit_result (fresh per calculate_damage call) so
## callers can ride it onto the damage event: DamageNumbers floats, the
## combat log, and the dodge/parry/block/crit toasts all style off it
## without re-rolling. _last_was_crit remains for existing readers.
var _last_was_crit: bool = false
var _last_hit_result: Dictionary = {}

func calculate_damage(caster, target) -> int:
	var base_damage := damage

	# Apply caster's attack power based on damage type
	if damage_type == "physical":
		base_damage += caster.get_attack_power()
	elif damage_type == "magical":
		base_damage += caster.get_spell_power()

	# The MWo-style single-roll combat table: miss -> dodge -> parry ->
	# block -> crit -> hit in one randf(). Defensive chances come from
	# the TARGET's stats; duck-typed so bare-Entity and PlayerController
	# targets both roll. Miss-family outcomes return 0 and the callers
	# skip take_damage entirely (Enemy's armor floor would chip 1).
	var outcome := CombatMath.calculate_hit(caster, target, self)
	_last_hit_result = outcome
	var final_damage := CombatMath.calculate_damage(base_damage, outcome)
	_last_was_crit = bool(outcome.get("is_crit", false))

	return final_damage

func calculate_healing(caster) -> int:
	var base_heal := heal_amount

	# Apply caster's healing power (WIS-based)
	base_heal += caster.get_healing_power()

	# Daily Class Blessing (prd-psy.md section 8): the blessed class
	# heals +20% for the day. Duck-typed + late-resolved so script-mode
	# tests and bare Entities (never blessed) pass through clean.
	if caster != null and "character_class" in caster:
		var cid := str(caster.get("character_class"))
		if not cid.is_empty():
			var ml := Engine.get_main_loop()
			if ml != null and (ml is SceneTree):
				var svc = (ml as SceneTree).root.get_node_or_null("SignService")
				if svc != null and svc.has_method("is_class_blessed") and svc.is_class_blessed(cid):
					base_heal = int(float(base_heal) * float(svc.BLESSED_DAMAGE_MULTIPLIER))

	return base_heal

func applyCrowdControl(caster, target, _ground_position: Vector3) -> void:
	# Self/ground casts and non-StatusEffect families have no CC target.
	if target == null or not target.has_method("apply_status_effect"):
		return
	# Apply CC effect based on type
	match crowd_control_type:
		"stun":
			target.apply_status_effect(create_stun_effect(caster))
		"root":
			target.apply_status_effect(create_root_effect(caster))
		"slow":
			target.apply_status_effect(create_slow_effect(caster))

func applyShield(caster) -> void:
	# Create shield buff
	pass

func applyInvincibility(caster) -> void:
	# Create invincibility buff
	pass

func applyDoT(caster, target) -> void:
	if target == null or not target.has_method("apply_status_effect"):
		return
	if dot_damage <= 0 or dot_duration <= 0:
		return

	var dot := StatusEffect.new()
	dot.effect_id = skill_id + "_dot"
	dot.effect_name = skill_name + " DoT"
	dot.effect_type = StatusEffect.EffectType.DEBUFF
	dot.effect_category = StatusEffect.EffectCategory.POISON
	dot.tick_behavior = StatusEffect.TickBehavior.TICKED
	dot.tick_interval = dot_tick_rate if dot_tick_rate > 0 else 1.0
	dot.duration = dot_duration
	# Self-expire after the tick budget: a TICKED effect with
	# total_ticks = 0 is infinite by contract, and the tick janitor only
	# wall-clocks DURATION/TICKED behavior -- without a budget a DoT
	# would tick forever.
	dot.total_ticks = maxi(1, int(dot.duration / dot.tick_interval))
	dot.tick_damage = dot_damage
	# Kill attribution: the tick path routes through the target's
	# take_damage with this source, so a killing tick pays XP/loot/quest
	# credit to the CASTER (the old source-less effect paid nobody).
	dot.source = caster

	target.apply_status_effect(dot)

func applyTeleport(caster, ground_position: Vector3) -> void:
	if ground_position != Vector3.ZERO:
		caster.global_position = ground_position
	else:
		# Teleport forward
		var forward: Vector3 = -caster.global_transform.basis.z
		forward.y = 0
		caster.global_position += forward * teleport_distance

func create_stun_effect(_caster) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.effect_name = "Stunned"
	effect.effect_type = StatusEffect.EffectType.DEBUFF
	effect.duration = crowd_control_duration
	# DURATION behavior: the effect's own timer + the tick janitor own
	# expiry. Without it (INSTANT default) nothing ever advances or
	# sweeps the CC -- a stun would stick forever.
	effect.tick_behavior = StatusEffect.TickBehavior.DURATION
	return effect

func create_root_effect(_caster) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.effect_name = "Rooted"
	effect.effect_type = StatusEffect.EffectType.DEBUFF
	effect.duration = crowd_control_duration
	# DURATION behavior: the effect's own timer + the tick janitor own
	# expiry. Without it (INSTANT default) nothing ever advances or
	# sweeps the CC -- a stun would stick forever.
	effect.tick_behavior = StatusEffect.TickBehavior.DURATION
	return effect

func create_slow_effect(_caster) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.effect_name = "Slowed"
	effect.effect_type = StatusEffect.EffectType.DEBUFF
	effect.duration = crowd_control_duration
	# DURATION behavior: the effect's own timer + the tick janitor own
	# expiry. Without it (INSTANT default) nothing ever advances or
	# sweeps the CC -- a stun would stick forever.
	effect.tick_behavior = StatusEffect.TickBehavior.DURATION
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
