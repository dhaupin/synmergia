## StatusEffectFactory - StatusEffectData (.tres) -> runtime StatusEffect
##
## The data layer (core/schemas/status_effect_data.gd, data/status_effects/*.tres)
## and the runtime layer (core/entities/status_effect.gd) were never joined:
## nothing read StatusEffectData, so every authored buff/debuff was a display-only
## shell and get_status_effect() had no caller. This is that join.
##
## Skill/aura/item effects all flow through here: a skill's `effect_id` names a
## data/status_effects/*.tres, this maps its payload onto the runtime fields the
## entity's apply_status_effect law consumes, and the effect rides the existing
## timers/ticks/aura mirror unchanged.
##
## The two schemas are separate on purpose (data is authored; runtime is
## behaviour), so the mapping is explicit rather than a duck-typed copy.
extends RefCounted
class_name StatusEffectFactory

const StatusEffect = preload("res://core/entities/status_effect.gd")
const StatusEffectDataScript = preload("res://core/schemas/status_effect_data.gd")
const StatId = preload("res://core/schemas/stat_id.gd")
const CcImmunity = preload("res://core/combat/cc_immunity.gd")

## StatusEffectData.StatType name -> runtime stat export on StatusEffect.
const STAT_EXPORT := {
        "strength": "strength_mod",
        "agility": "agility_mod",
        "intelligence": "intelligence_mod",
        "vitality": "vitality_mod",
        "endurance": "endurance_mod",
        "wisdom": "wisdom_mod",
}

## StatusEffectData.StatType name -> runtime float multiplier export.
const MULT_EXPORT := {
        "damage": "damage_multiplier",
        "attack_power": "damage_multiplier",
        "spell_power": "damage_multiplier",
        "defense": "defense_multiplier",
        "resistance": "defense_multiplier",
        "armor": "armor_multiplier",
        "attack_speed": "attack_speed_multiplier",
        "haste": "attack_speed_multiplier",
        "movement_speed": "movement_speed_multiplier",
}

## StatusEffectData.StatType name -> runtime flat modifier export (regen,
## mitigation). Read by the damage/regen pipeline off the entity stats block.
const FLAT_EXPORT := {
        "health_regen": "health_regen_mod",
        "mana_regen": "mana_regen_mod",
        "damage_reduction": "damage_reduction",
        "damage_reflect": "damage_reflect",
}

## StatusEffectData.ControlType name -> runtime crowd-control fields.
const CONTROL := {
        "STUN": {"can_move": false, "can_cast": false, "can_attack": false},
        "ROOT": {"can_move": false},
        "SNARE": {"can_move": false},
        "SILENCE": {"can_cast": false},
        "FEAR": {"can_move": false, "can_cast": false},
        "INCAPACITATE": {"can_move": false, "can_cast": false, "can_attack": false},
        "KNOCKBACK": {"can_move": false},
}

const STEALTH := {
        "INVISIBLE": 1,
        "STEALTH": 2,
        "VANISH": 3,
}

## Build a runtime StatusEffect from a StatusEffectData resource. `duration_override`
## (seconds, > 0) lets a skill's own effect entry win over the template's default
## (the skill is the cast; the template is the shape). Returns null for a null
## input so callers can duck-type a miss.
static func from_data(data, duration_override: float = 0.0) -> StatusEffect:
        if data == null:
                return null

        var fx := StatusEffect.new()
        fx.effect_id = str(data.id)
        fx.effect_name = str(data.display_name)
        fx.description = str(data.description)
        fx.icon_path = str(data.icon_path)

        fx.effect_type = _effect_type(data)
        fx.effect_category = _category(data)

        var dur := duration_override if duration_override > 0.0 else float(data.duration)
        fx.duration = dur
        fx.max_stacks = maxi(1, int(data.max_stacks))
        fx.stack_behavior = _stack_behavior(data)
        fx.is_dispellable = bool(data.can_cleanse)

        # Stat mods: flat points on the stat exports, multipliers on the
        # combat-multiplier exports. Read by name so a typo'd key is inert,
        # matching the species stat_modifiers convention.
        for stat in data.stat_modifiers:
                var key := str(stat)
                var val := float(data.stat_modifiers[stat])
                if STAT_EXPORT.has(key):
                        fx.set(STAT_EXPORT[key], int(val))
                elif MULT_EXPORT.has(key):
                        fx.set(MULT_EXPORT[key], val)
                elif FLAT_EXPORT.has(key):
                        fx.set(FLAT_EXPORT[key], val)
        for stat2 in data.stat_multipliers:
                var key2 := str(stat2)
                if MULT_EXPORT.has(key2):
                        fx.set(MULT_EXPORT[key2], float(data.stat_multipliers[stat2]))
                elif FLAT_EXPORT.has(key2):
                        fx.set(FLAT_EXPORT[key2], float(data.stat_multipliers[stat2]))

        # First-class mitigation payloads: authored on the data's own fields,
        # not inside stat_modifiers. Clamped so authored data can never make a
        # body unkillable (immune_all is the one true immunity path).
        if float(data.damage_reduction) != 0.0:
                fx.damage_reduction = clampf(float(data.damage_reduction), 0.0, StatId.MAX_DAMAGE_REDUCTION)
        if float(data.damage_reflect) != 0.0:
                fx.damage_reflect = clampf(float(data.damage_reflect), 0.0, StatId.MAX_DAMAGE_REFLECT)
        # Flat per-second regen payloads (positive heals, negative suppresses).
        if float(data.health_regen) != 0.0:
                fx.health_regen_mod = float(data.health_regen)
        if float(data.mana_regen) != 0.0:
                fx.mana_regen_mod = float(data.mana_regen)

        _apply_speed(fx, data)

        # Health modifiers: HoT/DoT ride the tick path; the tick budget keeps a
        # ticked effect from ticking forever (total_ticks 0 is the runtime's
        # "infinite" sentinel).
        var tick := maxf(0.1, float(data.tick_interval))
        if int(data.damage_per_tick) > 0:
                fx.tick_damage = int(data.damage_per_tick)
                fx.tick_interval = tick
                fx.tick_behavior = StatusEffect.TickBehavior.TICKED
                fx.total_ticks = maxi(1, int(dur / tick)) if dur > 0.0 else 1
        elif int(data.heal_per_tick) > 0:
                fx.tick_heal = int(data.heal_per_tick)
                fx.tick_interval = tick
                fx.tick_behavior = StatusEffect.TickBehavior.TICKED
                fx.total_ticks = maxi(1, int(dur / tick)) if dur > 0.0 else 1
        elif dur > 0.0:
                # A duration effect with no tick expires on its own timer.
                fx.tick_behavior = StatusEffect.TickBehavior.DURATION

        # Shield, immunity, stealth.
        if int(data.shield_amount) > 0:
                fx.shield_amount = int(data.shield_amount)
        if bool(data.immune_all):
                fx.is_invincible = true
        # Immunity payload: translate the data's immune_* flags into the runtime
        # tag list the apply_status_effect gate reads. This is what makes an
        # authored "immune to stun" ward actually refuse a stun; before, the
        # flags were declared but nothing consulted them.
        fx.immune_all = bool(data.immune_all)
        for tag in CcImmunity.TAGS:
                if bool(data.grants_immunity_to(tag)):
                        fx.immune_tags.append(tag)
        _apply_stealth(fx, data)

        return fx

## Look up a data/status_effects/*.tres by id via DataService and build it.
## Returns null (and the caller no-ops) when the id is unknown -- a dangling
## skill ref must degrade quietly, not crash a cast.
static func from_id(effect_id: String, duration_override: float = 0.0) -> StatusEffect:
        if effect_id.is_empty():
                return null
        var ds := _data_service()
        if ds == null or not ds.has_method("get_status_effect"):
                return null
        var data = ds.get_status_effect(effect_id)
        if data == null:
                return null
        return from_data(data, duration_override)

static func _data_service() -> Node:
        var ml := Engine.get_main_loop()
        if ml == null or not (ml is SceneTree):
                return null
        return (ml as SceneTree).root.get_node_or_null(NodePath("DataService"))

static func _effect_type(data) -> int:
        # StatusEffectData.EffectCategory: BUFF=0, DEBUFF=1, NEUTRAL=2 maps onto
        # StatusEffect.EffectType: BUFF=0, DEBUFF=1, NEUTRAL=2.
        match int(data.category):
                0:
                        return StatusEffect.EffectType.BUFF
                1:
                        return StatusEffect.EffectType.DEBUFF
                _:
                        return StatusEffect.EffectType.NEUTRAL

static func _category(data) -> int:
        # The two category enums are unrelated (data's is BUFF/DEBUFF/NEUTRAL,
        # runtime's is a school list). Route control effects to STUN, everything
        # else to MAGIC -- the only split any dispel reader cares about today.
        if int(data.effect_type) == int(StatusEffectDataScript.EffectType.CONTROL):
                return StatusEffect.EffectCategory.STUN
        return StatusEffect.EffectCategory.MAGIC

static func _stack_behavior(data) -> int:
        match str(data.stack_behavior):
                "add":
                        return StatusEffect.StackBehavior.ADD
                "replace":
                        return StatusEffect.StackBehavior.REPLACE
                "refresh":
                        return StatusEffect.StackBehavior.REFRESH
        return StatusEffect.StackBehavior.NONE

static func _apply_speed(fx: StatusEffect, data) -> void:
        # Control effects carry their flags through control_type.
        if int(data.effect_type) == int(StatusEffectDataScript.EffectType.CONTROL):
                _apply_control(fx, data)
        # speed_percent is the magnitude of a named speed_type (haste positive,
        # slow/snare negative).
        var pct := float(data.speed_percent)
        if pct == 0.0:
                return
        # The runtime multiplier fields are additive deltas on a 1.0 base
        # (StatusEffect._apply_combat_modifiers does `stats.x += field`), so a
        # +20% haste is stored as 0.2, not 1.2.
        var delta := pct / 100.0
        match str(data.speed_type):
                "haste":
                        fx.attack_speed_multiplier = delta
                        fx.movement_speed_multiplier = delta
                "slow", "snare":
                        fx.movement_speed_multiplier = delta
                "root":
                        fx.can_move = false

static func _apply_control(fx: StatusEffect, data) -> void:
        var names: Array = StatusEffectDataScript.ControlType.keys()
        var idx := int(data.control_type)
        if idx < 0 or idx >= names.size():
                return
        var control_name := str(names[idx])
        var flags: Dictionary = CONTROL.get(control_name, {})
        for key in flags:
                fx.set(key, bool(flags[key]))
        # Stamp the canonical tag so an immune body's apply_status_effect gate
        # can refuse this control. A tag with no flags (unknown name) is left
        # empty rather than guessed.
        fx.cc_tag = CcImmunity.tag_for_control(control_name)

static func _apply_stealth(fx: StatusEffect, data) -> void:
        var size: int = StatusEffectDataScript.StealthType.size()
        var idx := int(data.stealth_type)
        if idx <= 0 or idx >= size:
                return
        var st := str(StatusEffectDataScript.StealthType.keys()[idx])
        fx.make_invisible = st == "INVISIBLE" or st == "VANISH"
        fx.break_on_damage = bool(data.break_on_damage)
        fx.break_on_action = bool(data.break_on_action)
