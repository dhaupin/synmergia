## ScopeBand - THE one ladder that turns a skill's upgrade TIER into a REACH.
##
## The upgrade ladder (common -> mythic, GameTier) already scaled numbers
## (damage_mult, range_mult, ...). What it could not express is a skill that
## changes KIND as it climbs: a heal that is single-target until it becomes a
## party-wide AoE, or a blink that is a short hop until it folds you across a
## world. That is a BAND, not a multiplier -- so it lives here, one table per
## verb, keyed by upgrade level (0 = base, 1..5 = the GameTier rungs).
##
## The owner's law: heal bands go AoE at epic and lose their target cap at the
## top; teleport bands climb from "someone has to be close" to cross-scope
## (instance -> world -> planet) at mythic. A class identity (Bender blinks,
## healer mends) is enforced separately by required_role; this file only
## answers "how far does this tier reach".
##
## Pure and autoload-free (const-preloaded like CombatMath / CcImmunity) so
## script-mode probes resolve it without a scene tree.
class_name ScopeBand
extends RefCounted

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

static func _level(upgrade_level: int) -> int:
        return clampi(upgrade_level, 0, MAX_LEVEL)

## The heal band at an upgrade level. Always a valid dictionary.
static func heal_band(upgrade_level: int) -> Dictionary:
        return HEAL_BANDS[_level(upgrade_level)]

## The teleport band at an upgrade level. Always a valid dictionary.
static func teleport_band(upgrade_level: int) -> Dictionary:
        return TELEPORT_BANDS[_level(upgrade_level)]

## True when a heal at this level is a friendly AoE (epic and up).
static func heal_is_aoe(upgrade_level: int) -> bool:
        return bool(heal_band(upgrade_level).get("aoe", false))

## The friendly cap for a heal at this level; 0 means unlimited.
static func heal_max_targets(upgrade_level: int) -> int:
        return int(heal_band(upgrade_level).get("max_targets", 1))

## The sweep radius a heal band grants (the skill's own larger aoe_radius wins).
static func heal_radius(upgrade_level: int) -> float:
        return float(heal_band(upgrade_level).get("radius", 0.0))

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
