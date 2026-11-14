## Skill - Definition for combat skills
## Can be instant, channeled, or ground-targeted
extends Resource
class_name Skill

## Tree-safe EventHub emit (script-mode-safe; mirrors the resolver idiom
## in entity.gd / kill_rewards.gd -- the bare identifier fails compile
## when autoloads are absent).
func _hub_emit(sig_name: String, args: Array) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var hub := tree.root.get_node_or_null(NodePath("EventHub")) if tree and tree.root else null
	if hub and hub.has_signal(sig_name):
		hub.emit_signal(sig_name, args) if args.is_empty() else hub.emit_signal("%s" % sig_name, args[0], args[1] if args.size() > 1 else null, args[2] if args.size() > 2 else null, args[3] if args.size() > 3 else null, args[4] if args.size() > 4 else null)

const StatusEffect = preload("res://core/entities/status_effect.gd")
const CcImmunity = preload("res://core/combat/cc_immunity.gd")
const ScopeBand = preload("res://core/combat/scope_band.gd")
const CharacterData = preload("res://core/schemas/character_data.gd")
const SkillSchema = preload("res://core/schemas/skill.gd")
# The data -> runtime status-effect join (a skill's effect_id names a
# data/status_effects/*.tres). Preloaded, not a class_name reference, so
# script-mode tests resolve it without the global registry.
const StatusEffectFactory = preload("res://core/combat/status_effect_factory.gd")
# CombatMath runs the MWo-style hit table (miss/dodge/parry/block/crit)
# inside calculate_damage; no cycle -- combat_math no longer preloads
# this file.
const CombatMath = preload("res://core/services/combat_math.gd")
# Entity is preloaded for EntityType constants (e.g. the heal-threat
# radius scan). Caster/target method params are deliberately untyped so
# the player body (a CharacterBody3D) can cast without an Entity cast.
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
# Movement penalty for a "slow" CC, as a fraction (0.3 == -30%). Authored on the
# effect entry's "value"; the default matches slow_common's -30%.
@export var crowd_control_slow_percent: float = 0.3

# Authored status effects (the schema's buff/debuff entries, kept whole so
# they resolve through StatusEffectFactory at cast time instead of being
# flattened to nothing). Each entry: {"type": "buff"/"debuff",
# "effect_id": "buff_haste", "duration": 10.0}.
@export var status_effects: Array[Dictionary] = []

# Defensive
@export var grants_shield: int = 0
@export var shield_duration: float = 10.0
@export var grants_invincibility: bool = false
@export var invincibility_duration: float = 0.0
# Utility effects (authored as "revive"/"cleanse" entries).
@export var is_revive: bool = false
@export var cleanses: bool = false
# Aggro control: a taunt force-locks enemies on the caster (AggroComponent.taunt).
@export var taunt_targets: bool = false
@export var taunt_duration: float = 4.0

# Utility
@export var required_role: int = -1  # CharacterClass.Role; -1 = any (class FAMILY gate)
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
# Scope bands: a heal becomes a friendly AoE from epic up; a teleport reaches
# further and eventually crosses scopes at mythic (ScopeBand owns the tables).
# The same opt-in also bands a GUARD (ally shield aura) and a CONTROL (AoE
# stun/taunt), so every "reach" verb rides one canonical flow.
@export var heal_aoe: bool = false
@export var heal_aoe_radius: float = 0.0
@export var heal_max_targets: int = 1  # 0 = unlimited
@export var teleport_scope: int = 0     # ScopeBand.LOCAL..PLANET
@export var guard_aoe: bool = false
@export var guard_radius: float = 0.0
@export var guard_max_targets: int = 1  # 0 = unlimited
@export var guard_duration_mult: float = 1.0
@export var control_aoe: bool = false
@export var control_radius: float = 0.0
@export var control_max_targets: int = 1  # 0 = unlimited
@export var control_duration_mult: float = 1.0
@export var scope_bands: bool = false   # opt in: fold the ScopeBand tables for this tier
## Opt in to the GUARD band (separate from scope_bands so a self buff is never
## fanned to the party): the shield pool + authored buffs cover allies as the
## tier climbs -- the tank's Hold.
@export var guard_band: bool = false
## Per-cast latch: the hitbox sweep fans a banded control over the ring ONCE
## (on the first landed hit), then stops re-sweeping for the rest of the cast.
## A fresh Skill instance is duplicated per cast, so the latch resets itself.
var _banded_fx_done: bool = false

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
	sk.required_role = int(s.required_role)
	sk.scope_bands = bool(s.scope_bands)
	sk.guard_band = bool(s.guard_band)
	sk.required_stance = s.required_stance
	sk.schema = s
	# Flatten effect dictionaries into runtime fields. THIS is the one effect
	# vocabulary for the game: every type an authored .tres may use is handled
	# here, so an unknown type is a lint-gate miss, never a silent no-op.
	for effect: Dictionary in s.effects:
		match str(effect.get("type", "")):
			"damage":
				sk.damage += int(effect.get("value", 0))
			"heal":
				sk.heal_amount += int(effect.get("value", 0))
			"stun", "root", "slow":
				sk.crowd_control_type = str(effect.get("type", ""))
				sk.crowd_control_duration = float(effect.get("duration", 0.0))
				# A slow's authored "value" is its percent penalty
				# (20 == -20%); keep the magnitude so the runtime effect
				# can actually slow the body.
				if effect.has("value"):
					sk.crowd_control_slow_percent = clampf(absf(float(effect.get("value"))) / 100.0, 0.0, 1.0)
			"buff", "debuff":
				# Keep the authored entry whole; it resolves through
				# StatusEffectFactory at cast time (effect_id ->
				# data/status_effects/*.tres).
				sk.status_effects.append(effect.duplicate())
				# A taunt is aggro control, not a stat debuff: flag it so
				# execute() force-locks enemies (AggroComponent.taunt). The
				# aggro-horn payloads mean the same thing.
				var fxid := str(effect.get("effect_id", ""))
				if fxid == "debuff_taunt" or fxid == "debuff_aggro_horn" or fxid == "buff_aggro_horn":
					sk.taunt_targets = true
					sk.taunt_duration = maxf(sk.taunt_duration, float(effect.get("duration", 0.0)))
			"shield":
				# A self-shield pool that soaks damage before health
				# (Entity._absorb_with_shields); it rides the status stack so
				# it expires on its own clock.
				sk.grants_shield += int(effect.get("value", 0))
				sk.shield_duration = maxf(sk.shield_duration, float(effect.get("duration", 0.0)))
			"damage_over_time":
				# A ticked debuff on the target (kill credit to the caster).
				sk.is_dot = true
				sk.dot_damage += int(effect.get("value", 0))
				sk.dot_duration = maxf(sk.dot_duration, float(effect.get("duration", 0.0)))
				if effect.has("tick_interval"):
					sk.dot_tick_rate = float(effect.get("tick_interval"))
			"hot":
				# A ticked heal on the caster or ally target.
				sk.hot_heal += int(effect.get("value", 0))
				sk.hot_duration = maxf(sk.hot_duration, float(effect.get("duration", 0.0)))
				if effect.has("tick_interval"):
					sk.hot_tick_rate = float(effect.get("tick_interval"))
			"revive":
				# Dead-ally resurrection, routed through RespawnService
				# (applyRevive).
				sk.is_revive = true
			"cleanse":
				# Strips debuffs from the caster/ally target
				# (AuraComponent.cleanse owns the strip).
				sk.cleanses = true
			"teleport":
				# A blink/gap-closer (Bender-only via required_role). The value is the
				# distance in metres when no ground point is given; a GROUND-targeted
				# cast teleports to the aim point instead (applyTeleport).
				sk.teleport_distance = maxf(sk.teleport_distance, float(effect.get("value", 0.0)))
	return sk

func _init() -> void:
	if skill_id == "":
		skill_id = skill_name.to_lower().replace(" ", "_")

func can_cast(caster: Node) -> bool:
	# Check cooldown
	if remaining_cooldown > 0:
		return false

	# Crowd control: a stunned/silenced caster cannot cast (status effects
	# carry can_cast == false). Duck-typed on the body's status_effects.
	if "status_effects" in caster:
		for effect in caster.status_effects:
			if effect.has_method("allows_casting") and not effect.allows_casting():
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

	# Check role (class FAMILY). Teleport is Bender-only, so a skill can gate
	# on Role.BENDER rather than naming one class -- all three family classes
	# (Seer/Temporalist/Overclocker) share the role and qualify.
	if required_role >= 0:
		var cid := str(caster.get("character_class"))
		if not CharacterData.class_has_role(cid, required_role):
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
		"heal_amount": 0,
		"heal_targets": 0,
		"guard_targets": 0,
		"control_targets": 0,
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
				_hub_emit("hit_resolved", [caster, target, _last_hit_result, self, 0])
			else:
				target.take_damage(actual_damage, caster, damage_type, _last_was_crit)
				result.targets_hit.append(target)
				_hub_emit("hit_resolved", [caster, target, _last_hit_result, self, actual_damage])

	# Apply healing. From the epic band up the heal is a friendly AoE
	# (apply_banded_heal sweeps allies; single-target keeps the old shape).
	if heal_amount > 0:
		var actual_heal := calculate_healing(caster)
		result.heal_amount = actual_heal
		result.heal_targets = apply_banded_heal(caster, target, actual_heal)

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

	# Apply crowd control (deferred on hitbox casts: landed hits only). When
	# the control verb is banded, the sweep owns the ring AND the CC debuff
	# entries (an AoE stun must hit every hostile in reach, not one target).
	var banded_control := scope_bands and control_aoe and _has_control_payload()
	if (crowd_control_type != "" or taunt_targets) and not defer_target_effects:
		if banded_control:
			result.control_targets = apply_banded_control(caster, target, ground_position)
		else:
			applyCrowdControl(caster, target, ground_position)

	# Authored BUFFS are self/ally effects. A hitbox cast defers them to the
	# sweep (landed hits only, unless there is no target -- a self-buff still
	# lands at cast). The guard band owns them when it fans them to the party
	# (apply_banded_guard below), so they are not applied twice.
	if not status_effects.is_empty() and not has_guard_payload() and (not defer_target_effects or target == null):
		apply_buff_entries(caster, target)
	# Authored DEBUFFS are offense: a hitbox cast defers them to the sweep
	# (landed hits only), and a banded control fans them to the whole ring.
	if not status_effects.is_empty() and not defer_target_effects and not banded_control:
		apply_debuff_entries(caster, target)

	# The guard (shield pool + authored buffs) fans to allies when the guard
	# band is on, else the shield pool lands on the caster alone. A guard is
	# ally-support, not offense, so it never waits on a landed hit -- it lands
	# the moment the skill is cast (a tank alone still shields the party).
	if has_guard_payload():
		result.guard_targets = apply_banded_guard(caster, target, grants_shield)
	elif grants_shield > 0:
		applyShield(caster)

	if grants_invincibility:
		applyInvincibility(caster)

	if is_dot and not defer_target_effects:
		applyDoT(caster, target)
	if is_revive and not defer_target_effects:
		applyRevive(caster, target)

	if cleanses and not defer_target_effects:
		applyCleanse(caster)

	if taunt_targets and not defer_target_effects and not banded_control:
		applyTaunt(caster)

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

	# Duck-typed writes: the player body carries mana but no stamina;
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

	# Status-effect damage multiplier (buff/debuff deltas on a 1.0 base,
	# e.g. Battle Cry). Duck-typed: bare Entities and the player body both
	# carry the stats block.
	if "stats" in caster:
		base_damage = int(float(base_damage) * float(caster.stats.get("damage_multiplier", 1.0)))

	# The MWo-style single-roll combat table: miss -> dodge -> parry ->
	# block -> crit -> hit in one randf(). Defensive chances come from
	# the TARGET's stats; duck-typed so bare-Entity and the player body
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

## Resolve each authored buff/debuff entry through StatusEffectFactory and
## apply it on the right body: a buff on the caster (self) or an ally
## target, a debuff on the enemy target. An unknown effect_id degrades to a
## quiet no-op (the lint gate is what keeps refs honest, not a cast crash).
func applyStatusEffects(caster, target) -> void:
	apply_buff_entries(caster, target)
	apply_debuff_entries(caster, target)

## Apply the authored BUFF entries to one body (the caster by default, or the
## ally target). Split out so the banded guard sweep can reuse it per ally --
## one buff vocabulary, two callers.
func apply_buff_entries(caster, target) -> void:
	var body = target if (target != null and target.has_method("apply_status_effect")) else caster
	_apply_entries_of_kind(body, caster, "buff")

## Apply the authored DEBUFF entries to the enemy target. Debuffs are offense
## and never ride a guard sweep.
func apply_debuff_entries(caster, target) -> void:
	if target == null or not target.has_method("apply_status_effect"):
		return
	_apply_entries_of_kind(target, caster, "debuff")

func _apply_entries_of_kind(body, caster, kind: String, duration_mult: float = 1.0) -> void:
	if body == null or not body.has_method("apply_status_effect"):
		return
	for entry in status_effects:
		if str(entry.get("type", "")) != kind:
			continue
		var entry_dur := float(entry.get("duration", 0.0)) * maxf(duration_mult, 0.0)
		var fx := StatusEffectFactory.from_id(str(entry.get("effect_id", "")), entry_dur)
		if fx == null:
			continue
		fx.source = caster
		body.apply_status_effect(fx)

## True when this skill carries a guard payload AND opts into the guard band
## (a shield pool or authored buffs, fanned to allies). A skill that only
## opts into scope_bands (a heal) is not a guard.
func has_guard_payload() -> bool:
	if not guard_band:
		return false
	if grants_shield > 0:
		return true
	for entry in status_effects:
		if str(entry.get("type", "")) == "buff":
			return true
	return false

## True when this skill carries ANY control payload: a typed CC (stun/root/
## slow) or an authored control entry (stun_common/slow_common/taunt). This is
## the set the banded control sweep fans out, and the set a hitbox cast defers
## to the sweep.
func _has_control_payload() -> bool:
	return crowd_control_type != "" or _has_cc_entry() or taunt_targets

## True when this skill's authored debuff entries include a control (stun /
## root / slow / taunt) -- the CC set the banded control sweep fans out to
## every hostile in reach.
func _has_cc_entry() -> bool:
	for entry in status_effects:
		if str(entry.get("type", "")) != "debuff":
			continue
		if is_control_effect_id(str(entry.get("effect_id", ""))):
			return true
	return false

## The one control vocabulary: does this authored effect_id name a control?
## Shared by from_schema (taunt flag) and the banded control sweep so the
## definition lives once.
static func is_control_effect_id(effect_id: String) -> bool:
	var id := effect_id.to_lower()
	return (id.begins_with("stun") or id.begins_with("root") or id.begins_with("slow")
		or id.begins_with("debuff_taunt") or id.begins_with("buff_aggro_horn")
		or id.begins_with("debuff_aggro_horn") or id.begins_with("knockback")
		or id.begins_with("debuff_silence") or id.begins_with("debuff_fear"))

func applyShield(caster) -> void:
	if grants_shield <= 0 or caster == null or not caster.has_method("apply_status_effect"):
		return
	var fx := StatusEffect.new()
	fx.effect_id = skill_id + "_shield"
	fx.effect_name = skill_name + " Shield"
	fx.effect_type = StatusEffect.EffectType.BUFF
	fx.tick_behavior = StatusEffect.TickBehavior.DURATION
	fx.duration = shield_duration
	fx.shield_amount = grants_shield
	fx.source = caster
	caster.apply_status_effect(fx)

## Force every enemy near the caster to target it (tank grab). The aggro
## table owns the lock (AggroComponent.taunt); the authored debuff_taunt
## entry rides along on the status stack for the buff-bar icon. Silent
## no-op when EntityService is unavailable (parse-time) or nothing is in
## range -- same degradation law as _generate_heal_threat.
func applyTaunt(caster, duration_mult: float = 1.0) -> void:
	var es = _entity_service()
	if es == null or caster == null or not ("global_position" in caster):
		return
	var radius := aoe_radius if aoe_radius > 0.0 else 8.0
	# A banded taunt reaches as far as its control ring, so the aggro sweep and
	# the debuff fan-out never disagree on who is pulled.
	if control_radius > 0.0:
		radius = maxf(radius, control_radius)
	var duration_ms := int(maxf(taunt_duration, 0.0) * maxf(duration_mult, 0.0) * 1000.0)
	for enemy in EntityInterest.query_interest(caster.global_position, radius, [caster]):
		if not is_instance_valid(enemy):
			continue
		# Only enemies hold an aggro table worth locking.
		if "entity_type" in enemy and enemy.entity_type != Entity.EntityType.ENEMY:
			continue
		var ac = enemy.get("aggro_component")
		if ac != null and ac.has_method("taunt"):
			ac.taunt(caster, duration_ms)

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

func applyRevive(caster, target) -> void:
	if not is_revive or target == null or caster == null:
		return
	var ml: Variant = Engine.get_main_loop()
	if not (ml is SceneTree) or (ml as SceneTree).root == null:
		return
	var respawn_svc := (ml as SceneTree).root.get_node_or_null("RespawnService")
	if respawn_svc != null and respawn_svc.has_method("start_revival"):
		respawn_svc.start_revival(caster, target, "open_world")

## Strip the caster's debuffs (AuraComponent.cleanse owns the strip; a body
## without an aura component has nothing to strip).
func applyCleanse(caster) -> void:
	if not cleanses or caster == null:
		return
	var aura: Node = caster.get_node_or_null("AuraComponent") if caster is Node else null
	if aura != null and aura.has_method("cleanse"):
		aura.cleanse(caster)

## Fold the ScopeBand tables into this skill's runtime fields for its
## current upgrade_level. Idempotent (it SETS, never accumulates), so it is
## safe to call after the academy deltas land. A heal that authors its own
## larger aoe_radius keeps it; the band only ever widens reach.
##
## Each verb folds only for a skill that actually carries it, so a taunt never
## inherits a heal's radius and a heal never inherits a stun's ring. Adding a
## new verb means one table in ScopeBand and one branch here -- the callers do
## not change.
func apply_scope_bands() -> void:
	# Heal banding is opt-in (scope_bands): only a heal authored as a banded
	# mend grows into a friendly AoE. A lifesteal/drain rider stays single.
	if scope_bands and heal_amount > 0:
		var hb: Dictionary = ScopeBand.heal_band(upgrade_level)
		heal_aoe = bool(hb.get("aoe", false))
		heal_max_targets = int(hb.get("max_targets", 1))
		heal_aoe_radius = maxf(float(hb.get("radius", 0.0)), aoe_radius)
		if heal_aoe and heal_aoe_radius > aoe_radius:
			aoe_radius = heal_aoe_radius
	elif heal_amount > 0 and aoe_radius > 0.0:
		# An authored ring is inherently an AoE mend, so it must not inherit
		# the single-target cap (1). Uncapped unless a band says otherwise.
		heal_max_targets = 0
	# Control: only a skill that actually controls (a CC type or a stun/root/
	# slow/taunt entry) fans a ring. The radius also feeds aoe_radius so a
	# HITBOX control (combat_system's sweep reads aoe_radius) matches a
	# non-hitbox one.
	if scope_bands and (crowd_control_type != "" or _has_cc_entry()):
		var cb: Dictionary = ScopeBand.control_band(upgrade_level)
		control_aoe = bool(cb.get("aoe", false))
		control_max_targets = int(cb.get("max_targets", 1))
		control_radius = float(cb.get("radius", 0.0))
		control_duration_mult = float(cb.get("duration_mult", 1.0))
		if control_aoe and control_radius > aoe_radius:
			aoe_radius = control_radius
	# Guard: the ally shield aura widens and covers the party as it climbs. A
	# separate opt-in (guard_band) so a self damage buff is never fanned out.
	if guard_band and has_guard_payload():
		var gb: Dictionary = ScopeBand.guard_band(upgrade_level)
		guard_aoe = bool(gb.get("aoe", false))
		guard_max_targets = int(gb.get("max_targets", 1))
		guard_radius = float(gb.get("radius", 0.0))
		guard_duration_mult = float(gb.get("duration_mult", 1.0))
	# A teleport bands by nature; the reach climbs and eventually crosses
	# scopes. At base (0) the skill's own authored distance governs.
	if teleport_distance > 0.0:
		var tb: Dictionary = ScopeBand.teleport_band(upgrade_level)
		teleport_scope = int(tb.get("scope", ScopeBand.LOCAL))
		var band_range := float(tb.get("range_m", 0.0))
		if band_range > 0.0:
			teleport_distance = maxf(teleport_distance, band_range)

## Heal the caster (and, from the epic band up, every friendly in reach).
## Returns the number of bodies healed. A single-target heal keeps the old
## behaviour: the named target if any, else the caster.
func apply_banded_heal(caster, target, amount: int) -> int:
	if amount <= 0 or caster == null:
		return 0
	# A heal is an AoE when the band grants it (opt-in, epic+) OR the skill
	# authors its own aoe_radius (a nova/redistribute is inherently a ring).
	var is_aoe := heal_aoe or aoe_radius > 0.0
	if not is_aoe:
		var single = target if target != null else caster
		if single != null and single.has_method("heal"):
			single.heal(amount)
			return 1
		return 0
	# Friendly AoE: sweep the band radius around the caster. Enemies are never
	# mended, and the cap (0 = unlimited) trims the sweep. An authored ring is
	# uncapped even if apply_scope_bands() never ran (defensive: the cap must
	# not depend on call order).
	var cap := heal_max_targets
	if aoe_radius > 0.0 and not heal_aoe and cap <= 1:
		cap = 0
	var radius := maxf(heal_aoe_radius, aoe_radius)
	var origin: Vector3 = caster.global_position
	var healed := 0
	var candidates: Array = []
	var seen := {}
	if target != null and target.has_method("heal"):
		candidates.append(target)
		seen[target.get_instance_id()] = true
	for body in EntityInterest.query_interest(origin, radius, [caster]):
		if not _is_friendly(caster, body):
			continue
		if seen.has(body.get_instance_id()):
			continue
		seen[body.get_instance_id()] = true
		candidates.append(body)
	for body in candidates:
		if cap > 0 and healed >= cap:
			break
		if not is_instance_valid(body) or not body.has_method("heal"):
			continue
		body.heal(amount)
		healed += 1
	if healed == 0 and caster.has_method("heal"):
		caster.heal(amount)
		healed = 1
	return healed

## Guard the caster (and, from the epic band up, every friendly in reach) with
## the skill's guard payload: the shield pool (grants_shield) plus every
## authored buff entry (a fortify/reflect aura). Returns the number of bodies
## guarded. The shield rides a StatusEffect whose duration is scaled by the
## guard band; the buffs keep their authored durations.
func apply_banded_guard(caster, target, amount: int) -> int:
	if caster == null or not caster.has_method("apply_status_effect"):
		return 0
	var dur := maxf(shield_duration, 0.0) * maxf(guard_duration_mult, 1.0)
	var radius := maxf(guard_radius, aoe_radius)
	# The named ally target (if any) plus the friendly ring; self always leads.
	var bodies: Array = [caster]
	var seen := {caster.get_instance_id(): true}
	if target != null and target != caster and _is_friendly(caster, target):
		bodies.append(target)
		seen[target.get_instance_id()] = true
	if guard_aoe:
		for body in EntityInterest.query_interest(caster.global_position, radius, [caster]):
			if seen.has(body.get_instance_id()):
				continue
			if not _is_friendly(caster, body):
				continue
			seen[body.get_instance_id()] = true
			bodies.append(body)
	var cap := guard_max_targets if guard_aoe else 1
	var guarded := 0
	for body in bodies:
		if cap > 0 and guarded >= cap:
			break
		if not is_instance_valid(body) or not body.has_method("apply_status_effect"):
			continue
		if amount > 0:
			var fx := StatusEffect.new()
			fx.effect_id = skill_id + "_guard"
			fx.effect_name = skill_name + " Guard"
			fx.effect_type = StatusEffect.EffectType.BUFF
			fx.tick_behavior = StatusEffect.TickBehavior.DURATION
			fx.duration = dur
			fx.shield_amount = amount
			fx.source = caster
			body.apply_status_effect(fx)
		# The authored buff payload (a fortify/reflect aura) lands on each body
		# in the guard set, not just the caster, its duration scaled by the band.
		_apply_entries_of_kind(body, caster, "buff", guard_duration_mult)
		guarded += 1
	return guarded

## Apply crowd control to the named target (and, from the rare band up, every
## hostile in reach). Returns the number of bodies controlled. A single-target
## control keeps the old shape: only the named target is affected.
func apply_banded_control(caster, target, ground_position: Vector3) -> int:
	if crowd_control_type == "" and not taunt_targets:
		return 0
	var radius := maxf(control_radius, aoe_radius)
	var bodies: Array = []
	var seen := {}
	if target != null and target.has_method("apply_status_effect"):
		bodies.append(target)
		seen[target.get_instance_id()] = true
	if control_aoe:
		for body in EntityInterest.query_interest(caster.global_position, radius, [caster]):
			if seen.has(body.get_instance_id()):
				continue
			if not is_instance_valid(body):
				continue
			# Control only lands on hostiles (an AoE stun must never freeze allies).
			if "entity_type" in body and body.entity_type != Entity.EntityType.ENEMY:
				continue
			seen[body.get_instance_id()] = true
			bodies.append(body)
	var cap := control_max_targets if control_aoe else 1
	var controlled := 0
	for body in bodies:
		if cap > 0 and controlled >= cap:
			break
		if not is_instance_valid(body) or not body.has_method("apply_status_effect"):
			continue
		if crowd_control_type != "":
			var cc_fx = null
			match crowd_control_type:
				"stun":
					cc_fx = create_stun_effect(caster)
				"root":
					cc_fx = create_root_effect(caster)
				"slow":
					cc_fx = create_slow_effect(caster)
			if cc_fx != null:
				# The band lengthens the control as it widens.
				cc_fx.duration = cc_fx.duration * maxf(control_duration_mult, 0.0)
				body.apply_status_effect(cc_fx)
		# The authored debuff entries (stun_common, slow_common, taunt...) ride
		# the same fan-out so every hostile in the ring gets the full control.
		_apply_entries_of_kind(body, caster, "debuff", control_duration_mult)
		controlled += 1
	if taunt_targets:
		applyTaunt(caster, control_duration_mult)
	return controlled

## A body the caster's banded heal may mend: not hostile, and the same
## relation as the caster when both declare one.
static func _is_friendly(caster, body) -> bool:
	if body == caster or not is_instance_valid(body):
		return true
	var c_rel = caster.get("relation") if "relation" in caster else null
	var b_rel = body.get("relation") if "relation" in body else null
	if b_rel != null and int(b_rel) == 1:  # Entity.Relation.HOSTILE
		return false
	if c_rel != null and b_rel != null:
		return int(c_rel) == int(b_rel)
	return true

func create_stun_effect(_caster) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.effect_name = "Stunned"
	effect.effect_type = StatusEffect.EffectType.DEBUFF
	effect.effect_category = StatusEffect.EffectCategory.STUN
	effect.duration = crowd_control_duration
	# The gating flags ARE the stun: Skill.can_cast reads allows_casting and
	# globe_player._can_move reads allows_movement, so without these the
	# authored "stun" was an inert buff-bar icon.
	effect.can_move = false
	effect.can_cast = false
	effect.can_attack = false
	effect.cc_tag = CcImmunity.STUN
	# DURATION behavior: the effect's own timer + the tick janitor own
	# expiry. Without it (INSTANT default) nothing ever advances or
	# sweeps the CC -- a stun would stick forever.
	effect.tick_behavior = StatusEffect.TickBehavior.DURATION
	return effect

func create_root_effect(_caster) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.effect_name = "Rooted"
	effect.effect_type = StatusEffect.EffectType.DEBUFF
	effect.effect_category = StatusEffect.EffectCategory.STUN
	effect.duration = crowd_control_duration
	effect.can_move = false
	effect.cc_tag = CcImmunity.ROOT
	# DURATION behavior: the effect's own timer + the tick janitor own
	# expiry. Without it (INSTANT default) nothing ever advances or
	# sweeps the CC -- a stun would stick forever.
	effect.tick_behavior = StatusEffect.TickBehavior.DURATION
	return effect

func create_slow_effect(_caster) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.effect_name = "Slowed"
	effect.effect_type = StatusEffect.EffectType.DEBUFF
	effect.effect_category = StatusEffect.EffectCategory.STUN
	effect.duration = crowd_control_duration
	# A slow is a movement penalty, not a hold: the runtime multiplier field
	# is an additive delta on a 1.0 base (StatusEffect._apply_combat_modifiers).
	effect.movement_speed_multiplier = -crowd_control_slow_percent
	effect.cc_tag = CcImmunity.SLOW
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
