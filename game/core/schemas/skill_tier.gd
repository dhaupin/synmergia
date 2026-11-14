## SkillTier - the canonical skill-upgrade tier ladder.
##
## One source of truth for the `common -> mythic` rungs: their ordinal
## upgrade level (1..5), display label, roman numeral, and the stat-total
## threshold each rung gates on. The ladder used to be inlined in seven
## places (SkillAcademyService, DataService, GroundLootService,
## SkillBook, SkillAcademyUI, CharacterStatsUI, the integrity test) and
## two of them disagreed on the thresholds -- see TIER_STAT_THRESHOLD.
##
## DO NOT CONFUSE with Item.Rarity. That is a SIX-rung ladder (it adds
## UNCOMMON) shared by items, achievements, and titles. Skill tiers are
## FIVE rungs and are consumed by books, never by rarity rolls. They
## share a colour vocabulary and a few names, nothing else.
##
##   skill tier : common rare epic legendary mythic        (5, book-gated)
##   item rarity: common uncommon rare epic legendary mythic (6, roll-gated)
class_name SkillTier
extends RefCounted

## Rung names, low to high. Index i is upgrade level i+1.
const TIER_NAMES: Array = ["common", "rare", "epic", "legendary", "mythic"]

## Rung name -> upgrade level (1..5).
const TIER_LEVELS: Dictionary = {
        "common": 1, "rare": 2, "epic": 3, "legendary": 4, "mythic": 5
}

## Indexed by upgrade level; index 0 is unused so `level` reads directly.
const TIER_ROMAN: Array = ["", "I", "II", "III", "IV", "V"]
const TIER_DISPLAY: Array = ["", "Common", "Rare", "Epic", "Legendary", "Mythic"]

## Stat total required to reach each rung (0 = no gate). This is the ONE
## threshold table. Before this module the two UIs agreed on 0/30/60/90/120
## while skill.gd's own `upgrade_tiers` deltas said 30/60/90/120/150 -- an
## off-by-one that only stayed harmless because every `min_stat` was blank.
const TIER_STAT_THRESHOLD: Dictionary = {
        "common": 0, "rare": 30, "epic": 60, "legendary": 90, "mythic": 120
}

const MAX_LEVEL: int = 5
const BOOKS_PER_UPGRADE: int = 4


## Upgrade level (1..5) for a rung name, or 0 when the name is not a rung.
static func level_of(tier: String) -> int:
        return int(TIER_LEVELS.get(tier.to_lower(), 0))


## Rung name for an upgrade level, or "" when out of range.
static func name_of(level: int) -> String:
        return TIER_NAMES[level - 1] if level >= 1 and level <= MAX_LEVEL else ""


## True when `tier` names a real rung.
static func is_valid(tier: String) -> bool:
        return TIER_LEVELS.has(tier.to_lower())


static func roman(level: int) -> String:
        return TIER_ROMAN[level] if level >= 0 and level < TIER_ROMAN.size() else ""


static func display(level: int) -> String:
        return TIER_DISPLAY[level] if level >= 0 and level < TIER_DISPLAY.size() else ""


## Stat total required to reach `tier` (0 when unknown or ungated).
static func threshold(tier: String) -> int:
        return int(TIER_STAT_THRESHOLD.get(tier.to_lower(), 0))
