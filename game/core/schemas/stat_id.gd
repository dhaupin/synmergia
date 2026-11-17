## StatId - THE one stat vocabulary for the whole game.
##
## Skills, weapons, armor, accessories, species, enemies and status
## effects all move the same numbers, but before this file each surface
## spelled them independently: the item schema documented `strength`
## and `health`, species used the six primaries, status effects had
## their own StatType enum, and the runtime read bare string keys off
## an entity's `stats` Dictionary with no registry to validate against.
## A typo anywhere was silently inert.
##
## This is the single source: the six primaries, the multiplicative
## combat deltas (defense/speed), and the additive combat deltas
## (damage_reduction / damage_reflect / regen). Authored data names a
## key from here; the runtime entity `stats` block is seeded from
## DEFAULTS; the damage pipeline reads the mitigation keys by name.
##
## Two shapes, deliberately:
##   PRIMARY   flat ints, base 10, spent on level-up (strength..wisdom)
##   MODIFIER  floats layered on a base -- MULT_KEYS on 1.0, the rest on 0.0
## A modifier key in MULT_KEYS is a DELTA added to the 1.0 base (a +20%
## haste is authored as 0.2), matching StatusEffect._apply_combat_modifiers.
extends RefCounted
class_name StatId

## The six primaries. Flat integers, base 10, raised by allocation.
const PRIMARY: Array = [
        "strength", "agility", "intelligence", "vitality", "endurance", "wisdom"
]

## Multiplicative combat deltas. Authored and stored as a DELTA on a 1.0
## base: +0.25 means "25% more", and the pipeline multiplies by (1.0 + delta).
const MULT_KEYS: Array = [
        "damage_multiplier",
        "defense_multiplier",
        "armor_multiplier",
        "movement_speed_multiplier",
        "attack_speed_multiplier",
        # The support lanes' two reach verbs. DD LENGTHENS (effect_duration_mult);
        # Bender AMPLIFIES (effect_power_mult). Both are deltas on 1.0.
        "effect_duration_mult",
        "effect_power_mult",
]

## Damage schools. The one vocabulary every armor, shield, enemy template,
## status effect and future system names a resistance against. `physical`
## and `magical` are the two broad lanes the old schema knew; the rest are
## typed schools so a fire ward can be a real, separate number.
const DAMAGE_SCHOOLS: Array = [
        "physical", "magical", "fire", "frost", "lightning",
        "poison", "arcane", "holy", "shadow",
]

## Authoring spellings that resolve to a canonical school. Legacy content
## used "magic"; keeping the alias here means old data still lands on the
## magical lane instead of silently becoming an unknown school.
const SCHOOL_ALIASES: Dictionary = {
        "magic": "magical",
        "phys": "physical",
}

## Canonical per-school resistance keys (`resist_fire`, ...). Stored as
## flat fractions (0.25 = 25%) and clamped at the damage pipeline.
const RESIST_KEYS: Array = [
        "resist_physical", "resist_magical", "resist_fire", "resist_frost",
        "resist_lightning", "resist_poison", "resist_arcane", "resist_holy",
        "resist_shadow",
]

## Additive combat deltas. Plain floats, base 0.0.
##   damage_reduction  fraction of incoming damage removed (0.0..0.9)
##   damage_reflect    fraction of damage dealt back to the attacker (0.0..1.0)
##   health_regen      flat HP per second
##   mana_regen        flat MP per second
##   stamina_regen     flat stamina per second
##   cooldown_reduction fraction shaved off every cooldown (0.0..0.5)
##   crit_chance       fraction added to the crit roll (0.05 base + agility).
##                     A flat delta so a buff/class base raises the crit rate
##                     directly, the same shape as cooldown_reduction.
##   crit_damage       fraction added to the crit multiplier (1.5 base). A
##                     +0.25 means a crit lands for 1.75x. Flat so the rogue's
##                     crit-damage climb stacks additively.
##   resist_*          per-school damage fractions, one canonical lane each.
##   block/dodge/parry/hit ratings are the combat-table ratings equipment
##                     and buffs move; they are flat points, not fractions.
const FLAT_KEYS: Array = [
        "damage_reduction",
        "damage_reflect",
        "health_regen",
        "mana_regen",
        "stamina_regen",
        "cooldown_reduction",
        "crit_chance",
        "crit_damage",
        "resist_physical",
        "resist_magical",
        "resist_fire",
        "resist_frost",
        "resist_lightning",
        "resist_poison",
        "resist_arcane",
        "resist_holy",
        "resist_shadow",
        "hit_rating",
        "dodge_rating",
        "parry_rating",
        "block_rating",
]

const MODIFIER: Array = MULT_KEYS + FLAT_KEYS

## Every valid stat key, primaries first.
const ALL: Array = PRIMARY + MODIFIER

## Canonical default for a key: primaries start at 10, multipliers at 1.0,
## flat deltas at 0.0. A key absent from here is not a stat.
const DEFAULTS: Dictionary = {
        "strength": 10,
        "agility": 10,
        "intelligence": 10,
        "vitality": 10,
        "endurance": 10,
        "wisdom": 10,
        "damage_multiplier": 1.0,
        "defense_multiplier": 1.0,
        "armor_multiplier": 1.0,
        "movement_speed_multiplier": 1.0,
        "attack_speed_multiplier": 1.0,
        "damage_reduction": 0.0,
        "damage_reflect": 0.0,
        "health_regen": 0.0,
        "mana_regen": 0.0,
        "stamina_regen": 0.0,
        "cooldown_reduction": 0.0,
        "crit_chance": 0.0,
        "crit_damage": 0.0,
        "resist_physical": 0.0,
        "resist_magical": 0.0,
        "resist_fire": 0.0,
        "resist_frost": 0.0,
        "resist_lightning": 0.0,
        "resist_poison": 0.0,
        "resist_arcane": 0.0,
        "resist_holy": 0.0,
        "resist_shadow": 0.0,
        "hit_rating": 0.0,
        "dodge_rating": 0.0,
        "parry_rating": 0.0,
        "block_rating": 0.0,
        "effect_duration_mult": 1.0,
        "effect_power_mult": 1.0,
}

## The crit roll's baseline chance (before agility and any crit_chance delta).
## THE one home for it: Entity / the player body / CombatMath all read it here
## so the three can never drift. A ranger class raises its own crit by seeding
## a positive crit_chance delta, not by editing this constant.
const BASE_CRIT_CHANCE: float = 0.05

## The crit multiplier's baseline (1.5x before any crit_damage delta).
const BASE_CRIT_DAMAGE: float = 1.5

## Agility's contribution to crit chance, per point. The ranger identity leans
## on this; it stays here next to the base so the accessors are one formula.
const CRIT_PER_AGILITY: float = 0.003

## The caster axes' crit contribution per point. A magical skill crits off INT
## (a mage's crit climbs with the stat its damage scales on); a heal crits off
## WIS (a healer's crit is restoration power, not damage). Both are the caster
## twins of CRIT_PER_AGILITY -- a caster's crit is real but leaner per point
## than a rogue's, and neither is free. CombatMath.crit_axis_for picks the axis.
const CRIT_PER_INTELLIGENCE: float = 0.005
const CRIT_PER_WISDOM: float = 0.003

## --- Attack speed (the rogue / party buff axis) --------------------------
## Attack speed is ONE multiplier (base 1.0) that fans out to four effects:
## it raises hit rate, shortens cooldowns, speeds DoT/HoT ticks, and only
## SLIGHTLY lifts movement (the rogue's axis is attack speed, not raw speed).
## These are the one set of coefficients every consumer reads.
const AGILITY_PER_ATTACK_SPEED: float = 0.01   # +1% attack speed per agility
const MAX_ATTACK_SPEED_MULT: float = 2.5       # ceiling: haste cannot run away
## Each +100% attack speed adds this much hit chance (a haste helps you land).
const HIT_PER_ATTACK_SPEED: float = 0.15
## Each +100% attack speed shaves this much cooldown (folded into CDR, still
## under MAX_COOLDOWN_REDUCTION).
const CDR_PER_ATTACK_SPEED: float = 0.50
## A haste's movement lift is only this fraction of its attack-speed lift, so
## a +20% haste is +20% attack speed but +6% movement -- "slightly faster".
const HASTE_MOVE_FRACTION: float = 0.30

## Ceilings the pipeline clamps to, so authored data cannot make a body
## unkillable or a reflect loop unbounded. A school resistance is one of
## those ceilings: even a full ward leaves a 10% chip lane.
const MAX_DAMAGE_REDUCTION: float = 0.90
const MAX_DAMAGE_REFLECT: float = 1.00
const MAX_RESIST: float = 0.90
## Cooldowns may be shaved by at most half; a longer buff cannot zero them.
const MAX_COOLDOWN_REDUCTION: float = 0.50
## Crit chance is capped below 1.0 so a stacked crit buff still misses the
## crit segment when the defender's avoidance eats the roll; crit damage is
## capped so a crit cannot one-shot a raid boss.
const MAX_CRIT_CHANCE: float = 1.00
const MAX_CRIT_DAMAGE: float = 5.00
## Support reach caps, so an amplifier can never double a heal or a buff.
const MAX_EFFECT_DURATION_MULT: float = 2.0
const MAX_EFFECT_POWER_MULT: float = 2.0

## The damage school a reflected hit carries. The pipeline skips reflect
## for this school, which is what breaks a reflect ping-pong between two
## barriers.
const REFLECT_SCHOOL: String = "reflected"


## True when `key` is a real stat (primary or modifier).
static func is_valid(key: String) -> bool:
        return DEFAULTS.has(key)


## Canonical school name for an authored damage type. Unknown schools stay
## unknown ("") rather than guessing a lane, so future/typed damage that has
## no ward authored simply takes no resistance.
static func canonical_school(school: String) -> String:
        var key := school.to_lower().strip_edges()
        key = str(SCHOOL_ALIASES.get(key, key))
        return key if key in DAMAGE_SCHOOLS else ""


## The stat key a school's resistance lives under, or "" for an unknown
## school. `fire` -> `resist_fire`; `magic` -> `resist_magical`.
static func resist_key_for(school: String) -> String:
        var canonical := canonical_school(school)
        return "resist_%s" % canonical if canonical != "" else ""


## A defender's clamped resistance to one school, read from its stat block.
## THE one read used by the damage pipeline for players, enemies and any
## future body with a `stats` dictionary.
static func school_resist_of(stats: Dictionary, school: String) -> float:
        var key := resist_key_for(school)
        if key == "":
                return 0.0
        return clampf(float(stats.get(key, 0.0)), 0.0, MAX_RESIST)


static func is_primary(key: String) -> bool:
        return key in PRIMARY


static func is_modifier(key: String) -> bool:
        return key in MODIFIER


## True for the multiplicative deltas (1.0 base), false for flat ones.
static func is_multiplicative(key: String) -> bool:
        return key in MULT_KEYS


## Canonical default for a key, or 0.0 when the key is not a stat (callers
## that must not silently accept a typo test is_valid first).
static func default_of(key: String) -> float:
        return float(DEFAULTS.get(key, 0.0))


## A fresh entity `stats` block: every primary at 10, every multiplier at
## 1.0, every flat delta at 0.0. Both the Entity base and the player body
## seed from this so the two can never drift.
static func base_block() -> Dictionary:
        return DEFAULTS.duplicate()


## The crit chance a body rolls, from its base + agility + crit_chance delta.
## THE one formula: Entity.get_crit_chance, the player body, and CombatMath's
## fallback all read it, so a buff on `crit_chance` actually lands (the old
## per-body accessors hardcoded the base and shadowed the stat block).
static func crit_chance_of(agility: float, crit_chance_delta: float) -> float:
        return crit_chance_on_axis("agility", agility, crit_chance_delta)


## The crit chance on a named caster AXIS: base + axis_value * the axis rate +
## the crit_chance delta. A magical skill rides "intelligence", a heal rides
## "wisdom", a weapon strike rides "agility" (the default). THE one caster-crit
## formula, so a mage/healer crit and a rogue crit are the same shape with a
## different per-point rate. An unknown axis falls back to agility.
static func crit_chance_on_axis(axis: String, axis_value: float,
                crit_chance_delta: float) -> float:
        var per_point := CRIT_PER_AGILITY
        if axis == "intelligence":
                per_point = CRIT_PER_INTELLIGENCE
        elif axis == "wisdom":
                per_point = CRIT_PER_WISDOM
        return clampf(
                BASE_CRIT_CHANCE + axis_value * per_point + crit_chance_delta,
                0.0, MAX_CRIT_CHANCE)


## The primary stat a crit AXIS rides, for a skill's damage school and its kind.
## A magical skill crits off INT; a heal off WIS; anything else off agility.
## THE one axis chooser, so the damage path and the heal path cannot disagree
## about which stat makes a crit climb. `is_heal` wins over the school, because
## a heal is a heal whatever school its effect carries.
static func crit_axis_for(damage_type: String, is_heal: bool) -> String:
        if is_heal:
                return "wisdom"
        if damage_type == "magical":
                return "intelligence"
        return "agility"


## The crit multiplier a body lands, from the 1.5 base + crit_damage delta.
static func crit_damage_of(crit_damage_delta: float) -> float:
        return clampf(BASE_CRIT_DAMAGE + crit_damage_delta, 1.0, MAX_CRIT_DAMAGE)


## The one stamina pool size formula: 100 + 5 per endurance. Entity,
## PlayerBase and the PlayerManager mirror all read this, so a pool ceiling
## cannot drift between an NPC and either player body.
static func max_stamina_for_endurance(endurance: float) -> float:
        return 100.0 + endurance * 5.0


## The attack-speed multiplier a body swings at: the 1.0 base + agility + the
## attack_speed_multiplier stat delta (a haste). THE one formula, so a haste
## buff, an agility climb, and a bare stub all resolve the same number.
static func attack_speed_of(agility: float, attack_speed_delta: float) -> float:
        return clampf(
                1.0 + agility * AGILITY_PER_ATTACK_SPEED + attack_speed_delta,
                0.1, MAX_ATTACK_SPEED_MULT)


## The hit-chance bonus a haste grants, on top of the level/rating hit curve.
static func hit_bonus_for_attack_speed(attack_speed: float) -> float:
        return maxf(0.0, attack_speed - 1.0) * HIT_PER_ATTACK_SPEED


## The extra cooldown reduction a haste grants, folded into the flat CDR the
## skill path already clamps to MAX_COOLDOWN_REDUCTION.
static func cdr_for_attack_speed(attack_speed: float) -> float:
        return maxf(0.0, attack_speed - 1.0) * CDR_PER_ATTACK_SPEED


## The DoT/HoT tick-rate multiplier: a haste ticks faster by the same factor
## (interval is divided by it), capped so a tick cannot run away.
static func dot_rate_for_attack_speed(attack_speed: float) -> float:
        return clampf(attack_speed, 0.25, MAX_ATTACK_SPEED_MULT)

## Clamp an authored reduction/reflect fraction into its safe band.
static func clamp_fraction(key: String, value: float) -> float:
        if key == "damage_reduction":
                return clampf(value, 0.0, MAX_DAMAGE_REDUCTION)
        if key == "damage_reflect":
                return clampf(value, 0.0, MAX_DAMAGE_REFLECT)
        if key == "cooldown_reduction":
                return clampf(value, 0.0, MAX_COOLDOWN_REDUCTION)
        if key == "crit_chance":
                return clampf(value, 0.0, MAX_CRIT_CHANCE)
        if key == "crit_damage":
                return clampf(value, 0.0, MAX_CRIT_DAMAGE)
        return value


## Clamp a multiplicative delta key (1.0 base) into its safe band. An unknown
## key passes through untouched, so the helper is safe on any stat name.
static func clamp_multiplier(key: String, value: float) -> float:
        if key == "effect_duration_mult":
                return clampf(value, 0.0, MAX_EFFECT_DURATION_MULT)
        if key == "effect_power_mult":
                return clampf(value, 0.0, MAX_EFFECT_POWER_MULT)
        return value
