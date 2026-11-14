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

## Additive combat deltas. Plain floats, base 0.0.
##   damage_reduction  fraction of incoming damage removed (0.0..0.9)
##   damage_reflect    fraction of damage dealt back to the attacker (0.0..1.0)
##   health_regen      flat HP per second
##   mana_regen        flat MP per second
##   cooldown_reduction fraction shaved off every cooldown (0.0..0.5)
const FLAT_KEYS: Array = [
        "damage_reduction",
        "damage_reflect",
        "health_regen",
        "mana_regen",
        "cooldown_reduction",
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
        "cooldown_reduction": 0.0,
        "effect_duration_mult": 1.0,
        "effect_power_mult": 1.0,
}

## Ceilings the pipeline clamps to, so authored data cannot make a body
## unkillable or a reflect loop unbounded.
const MAX_DAMAGE_REDUCTION: float = 0.90
const MAX_DAMAGE_REFLECT: float = 1.00
## Cooldowns may be shaved by at most half; a longer buff cannot zero them.
const MAX_COOLDOWN_REDUCTION: float = 0.50
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


## Clamp an authored reduction/reflect fraction into its safe band.
static func clamp_fraction(key: String, value: float) -> float:
        if key == "damage_reduction":
                return clampf(value, 0.0, MAX_DAMAGE_REDUCTION)
        if key == "damage_reflect":
                return clampf(value, 0.0, MAX_DAMAGE_REFLECT)
        if key == "cooldown_reduction":
                return clampf(value, 0.0, MAX_COOLDOWN_REDUCTION)
        return value


## Clamp a multiplicative delta key (1.0 base) into its safe band. An unknown
## key passes through untouched, so the helper is safe on any stat name.
static func clamp_multiplier(key: String, value: float) -> float:
        if key == "effect_duration_mult":
                return clampf(value, 0.0, MAX_EFFECT_DURATION_MULT)
        if key == "effect_power_mult":
                return clampf(value, 0.0, MAX_EFFECT_POWER_MULT)
        return value
