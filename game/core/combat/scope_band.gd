## ScopeBand - THE one ladder that turns a skill's upgrade TIER into a REACH.
##
## The upgrade ladder (common -> mythic, GameTier) already scaled numbers
## (damage_mult, range_mult, ...). What it could not express is a skill that
## changes KIND as it climbs: a heal that is single-target until it becomes a
## party-wide AoE, a blink that is a short hop until it folds you across a
## world, a guard aura that grows to cover the raid. That is a BAND, not a
## multiplier -- so it lives here, one table per VERB, keyed by upgrade level
## (0 = base, 1..5 = the GameTier rungs).
##
## This is the canonical reach vocabulary. A new skill does not invent its own
## scaling: it declares which verb it rides (heal / guard / control / teleport),
## opts in with `scope_bands`, and Skill.apply_scope_bands folds the matching
## table for its current tier. Adding a future verb means adding one table here
## plus one `case` in Skill.apply_scope_bands -- nothing else changes.
##
## The owner's laws:
##   * heal bands go AoE at epic and lose their target cap at the top.
##   * teleport bands climb from "someone has to be close" to cross-scope
##     (instance -> world -> planet) at mythic.
##   * guard bands widen the aura and lift the ally cap (the tank's Hold).
##   * control bands widen the AoE stun/taunt and lengthen it (the tank's grab).
## A class identity (Bender blinks, healer mends, tank holds) is enforced
## separately by required_role; this file only answers "how far does this tier
## reach".
##
## Pure and autoload-free (const-preloaded like CombatMath / CcImmunity) so
## script-mode probes resolve it without a scene tree.
extends RefCounted
class_name ScopeBand

## Scope a reach can cross. LOCAL never leaves the current world root; the
## higher rungs name the boundary a mythic-tier verb may step over.
const LOCAL: int = 0
const INSTANCE: int = 1
const WORLD: int = 2
const PLANET: int = 3

const SCOPE_NAMES: Array[String] = ["local", "instance", "world", "planet"]

## Upgrade level is clamped into 0..5 (base + the five GameTier rungs), so a
## garbage level falls back to base rather than indexing off the table.
const MAX_LEVEL: int = 5

## The verb families a band can describe. A skill rides exactly one for its
## reach; the runtime reads the matching table through `band_for`.
const VERB_HEAL: String = "heal"
const VERB_GUARD: String = "guard"
const VERB_CONTROL: String = "control"
const VERB_TELEPORT: String = "teleport"
const VERB_RALLY: String = "rally"

## --- Heal bands ---------------------------------------------------------
## A heal is single-target at base/rare and a friendly AoE from epic up
## (owner: "aoe bands at upgrades epic and higher, all friendlies healed, no
## limit at high tier"). `max_targets` 0 means NO cap. `radius` is the sweep
## the band grants when the skill authors no larger aoe_radius of its own.
const HEAL_BANDS: Array[Dictionary] = [
        {"aoe": false, "radius": 0.0, "max_targets": 1},    # 0 base
        {"aoe": false, "radius": 0.0, "max_targets": 1},    # 1 common
        {"aoe": false, "radius": 0.0, "max_targets": 1},    # 2 rare
        {"aoe": true, "radius": 8.0, "max_targets": 0},     # 3 epic
        {"aoe": true, "radius": 14.0, "max_targets": 0},    # 4 legendary
        {"aoe": true, "radius": 24.0, "max_targets": 0},    # 5 mythic
]

## --- Guard bands (the tank's Hold) --------------------------------------
## A guard is a shield aura on the caster that widens and eventually covers
## the whole party. `max_targets` 0 means NO cap; `duration_mult` scales the
## authored shield duration with the tier. Self-only until the epic band,
## matching the heal law exactly so the two ally verbs (mend, hold) read the
## same -- a tank's Hold and a healer's mend come online at the same rung.
const GUARD_BANDS: Array[Dictionary] = [
        {"aoe": false, "radius": 0.0, "max_targets": 1, "duration_mult": 1.0},   # 0 base
        {"aoe": false, "radius": 0.0, "max_targets": 1, "duration_mult": 1.0},   # 1 common
        {"aoe": false, "radius": 0.0, "max_targets": 1, "duration_mult": 1.05},  # 2 rare
        {"aoe": true, "radius": 10.0, "max_targets": 4, "duration_mult": 1.15},  # 3 epic
        {"aoe": true, "radius": 14.0, "max_targets": 0, "duration_mult": 1.3},   # 4 legendary
        {"aoe": true, "radius": 20.0, "max_targets": 0, "duration_mult": 1.5},   # 5 mythic
]

## --- Control bands (the tank's grab) ------------------------------------
## A control (stun/root/slow/taunt) sweeps hostiles in a ring. `radius` is the
## band sweep when the skill authors none; `duration_mult` lengthens the
## authored CC. Unlike the ally verbs, control is a ring from the FIRST tier --
## "the one who stuns" is the tank's identity, not a late reward -- and widens
## to a full lockdown at mythic.
const CONTROL_BANDS: Array[Dictionary] = [
        {"aoe": false, "radius": 0.0, "max_targets": 1, "duration_mult": 1.0},   # 0 base
        {"aoe": true, "radius": 4.0, "max_targets": 2, "duration_mult": 1.0},    # 1 common
        {"aoe": true, "radius": 5.0, "max_targets": 3, "duration_mult": 1.1},    # 2 rare
        {"aoe": true, "radius": 6.0, "max_targets": 4, "duration_mult": 1.2},    # 3 epic
        {"aoe": true, "radius": 8.0, "max_targets": 0, "duration_mult": 1.35},   # 4 legendary
        {"aoe": true, "radius": 12.0, "max_targets": 0, "duration_mult": 1.5},   # 5 mythic
]

## --- Rally bands (the DD's Charge) --------------------------------------
## A rally is the DD's party-wide buff (damage / cooldown / regen), modeled on
## the tank's Hold: it lands on the caster at base and fans to the party from
## the epic band up, the SAME rung the mend and the hold come online. DD's reach
## verb is LENGTHEN (effect_duration_mult), carried by the same band table.
const RALLY_BANDS: Array[Dictionary] = [
        {"aoe": false, "radius": 0.0, "max_targets": 1, "duration_mult": 1.0},   # 0 base
        {"aoe": false, "radius": 0.0, "max_targets": 1, "duration_mult": 1.0},   # 1 common
        {"aoe": false, "radius": 0.0, "max_targets": 1, "duration_mult": 1.1},   # 2 rare
        {"aoe": true, "radius": 10.0, "max_targets": 4, "duration_mult": 1.2},   # 3 epic
        {"aoe": true, "radius": 14.0, "max_targets": 0, "duration_mult": 1.35},  # 4 legendary
        {"aoe": true, "radius": 20.0, "max_targets": 0, "duration_mult": 1.5},   # 5 mythic
]

## --- Teleport bands -----------------------------------------------------
## Reach in metres when the cast names no ground point, plus the scope the
## band may cross. Legendary is a ~10 km fold; mythic is the cross-scope one
## (instance -> world -> planet).
const TELEPORT_BANDS: Array[Dictionary] = [
        {"range_m": 0.0, "scope": LOCAL},        # 0 base (authored value governs)
        {"range_m": 25.0, "scope": LOCAL},       # 1 common
        {"range_m": 100.0, "scope": LOCAL},      # 2 rare
        {"range_m": 500.0, "scope": LOCAL},      # 3 epic
        {"range_m": 10000.0, "scope": LOCAL},    # 4 legendary (~10 km)
        {"range_m": 50000.0, "scope": PLANET},   # 5 mythic (cross-scope)
]

## The table for a verb family. Unknown verbs fall back to the control table
## (the most conservative reach) so a typo degrades to base, never to nothing.
static func table_for(verb: String) -> Array:
        match verb:
                VERB_HEAL:
                        return HEAL_BANDS
                VERB_GUARD:
                        return GUARD_BANDS
                VERB_TELEPORT:
                        return TELEPORT_BANDS
                VERB_RALLY:
                        return RALLY_BANDS
                _:
                        return CONTROL_BANDS

static func _level(upgrade_level: int) -> int:
        return clampi(upgrade_level, 0, MAX_LEVEL)

## The band for any verb at an upgrade level. Always a valid dictionary, so a
## new verb can be wired without a null guard.
static func band_for(verb: String, upgrade_level: int) -> Dictionary:
        return table_for(verb)[_level(upgrade_level)]

## The heal band at an upgrade level. Always a valid dictionary.
static func heal_band(upgrade_level: int) -> Dictionary:
        return HEAL_BANDS[_level(upgrade_level)]

## The guard band at an upgrade level. Always a valid dictionary.
static func guard_band(upgrade_level: int) -> Dictionary:
        return GUARD_BANDS[_level(upgrade_level)]

## The control band at an upgrade level. Always a valid dictionary.
static func control_band(upgrade_level: int) -> Dictionary:
        return CONTROL_BANDS[_level(upgrade_level)]

## The teleport band at an upgrade level. Always a valid dictionary.
static func teleport_band(upgrade_level: int) -> Dictionary:
        return TELEPORT_BANDS[_level(upgrade_level)]

## The rally band at an upgrade level. Always a valid dictionary.
static func rally_band(upgrade_level: int) -> Dictionary:
        return RALLY_BANDS[_level(upgrade_level)]

## True when a verb at this level sweeps a ring (epic-and-up for heal/guard/
## rally, common-and-up for control).
static func is_aoe(verb: String, upgrade_level: int) -> bool:
        return bool(band_for(verb, upgrade_level).get("aoe", false))

## The sweep radius a band grants (the skill's own larger aoe_radius wins).
static func radius(verb: String, upgrade_level: int) -> float:
        return float(band_for(verb, upgrade_level).get("radius", 0.0))

## The ally/enemy cap a band grants; 0 means unlimited.
static func max_targets(verb: String, upgrade_level: int) -> int:
        return int(band_for(verb, upgrade_level).get("max_targets", 1))

## True when a heal at this level is a friendly AoE (epic and up).
static func heal_is_aoe(upgrade_level: int) -> bool:
        return is_aoe(VERB_HEAL, upgrade_level)

## The friendly cap for a heal at this level; 0 means unlimited.
static func heal_max_targets(upgrade_level: int) -> int:
        return max_targets(VERB_HEAL, upgrade_level)

## The sweep radius a heal band grants (the skill's own larger aoe_radius wins).
static func heal_radius(upgrade_level: int) -> float:
        return radius(VERB_HEAL, upgrade_level)

## True when a guard at this level sweeps allies (rare and up).
static func guard_is_aoe(upgrade_level: int) -> bool:
        return is_aoe(VERB_GUARD, upgrade_level)

## The ally cap for a guard at this level; 0 means unlimited.
static func guard_max_targets(upgrade_level: int) -> int:
        return max_targets(VERB_GUARD, upgrade_level)

## The sweep radius a guard band grants.
static func guard_radius(upgrade_level: int) -> float:
        return radius(VERB_GUARD, upgrade_level)

## The shield-duration multiplier a guard band grants.
static func guard_duration_mult(upgrade_level: int) -> float:
        return float(guard_band(upgrade_level).get("duration_mult", 1.0))

## True when a control at this level sweeps hostiles (rare and up).
static func control_is_aoe(upgrade_level: int) -> bool:
        return is_aoe(VERB_CONTROL, upgrade_level)

## The hostile cap for a control at this level; 0 means unlimited.
static func control_max_targets(upgrade_level: int) -> int:
        return max_targets(VERB_CONTROL, upgrade_level)

## The sweep radius a control band grants.
static func control_radius(upgrade_level: int) -> float:
        return radius(VERB_CONTROL, upgrade_level)

## The CC-duration multiplier a control band grants.
static func control_duration_mult(upgrade_level: int) -> float:
        return float(control_band(upgrade_level).get("duration_mult", 1.0))

## The metre reach of a teleport at this level (0 at base: the skill's own
## authored value governs there).
static func teleport_range(upgrade_level: int) -> float:
        return float(teleport_band(upgrade_level).get("range_m", 0.0))

## The scope boundary a teleport at this level may cross.
static func teleport_scope(upgrade_level: int) -> int:
        return int(teleport_band(upgrade_level).get("scope", LOCAL))

## True when a teleport at this level may leave the current world (mythic).
static func teleport_crosses_scope(upgrade_level: int) -> bool:
        return teleport_scope(upgrade_level) > LOCAL

## Human-readable scope name ("local"/"instance"/"world"/"planet").
static func scope_name(scope: int) -> String:
        return SCOPE_NAMES[scope] if scope >= 0 and scope < SCOPE_NAMES.size() else "local"
