## GameTier - THE one five-rung tier scale for the whole game.
##
## Every "how good is this" ladder in Synmergia uses these five rungs,
## low to high: common, rare, epic, legendary, mythic. That covers skill
## upgrade tiers, item rarity, titles, and achievements -- one scale, so
## a "rare" item and a "rare" skill mean the same thing and read the same
## colour.
##
## HISTORY: this used to be two ladders that shared names but disagreed.
## The skill ladder was five rungs; Item.Rarity was SIX (it had an extra
## `uncommon` wedged between common and rare), and titles/achievements
## were FIVE but stopped at `legendary`. `uncommon` is gone -- the scale
## is five rungs everywhere.
##
## Canonical colours (the owner's spec):
##   common    grey
##   rare      blue
##   epic      purple
##   legendary orange
##   mythic    red
class_name GameTier
extends RefCounted

## Rung names, low to high. Index i is tier value i.
const NAMES: Array = ["common", "rare", "epic", "legendary", "mythic"]

## Rung name -> tier value (0..4).
const VALUES: Dictionary = {
	"common": 0, "rare": 1, "epic": 2, "legendary": 3, "mythic": 4
}

## Indexed by tier value; index 0 is common so `value` reads directly.
const DISPLAY: Array = ["Common", "Rare", "Epic", "Legendary", "Mythic"]
const ROMAN: Array = ["I", "II", "III", "IV", "V"]

## THE colours. Anything that paints a tier reads this.
const COLORS: Dictionary = {
	"common": Color(0.6, 0.6, 0.6),      # grey
	"rare": Color(0.3, 0.7, 1.0),        # blue
	"epic": Color(0.8, 0.3, 1.0),        # purple
	"legendary": Color(1.0, 0.6, 0.1),   # orange
	"mythic": Color(1.0, 0.2, 0.2),      # red
}

## Rung name -> skill upgrade level (1..5).
const LEVELS: Dictionary = {
	"common": 1, "rare": 2, "epic": 3, "legendary": 4, "mythic": 5
}

const MAX_VALUE: int = 4
const COUNT: int = 5

## Skill-upgrade book economy. Upgrade level 1..5 == tier value 0..4 + 1.
const BOOKS_PER_UPGRADE: int = 4

## Stat total required to reach each rung's upgrade level (0 = ungated).
## Skill upgrade levels 1..5 map to these thresholds.
const TIER_STAT_THRESHOLD: Dictionary = {
	"common": 0, "rare": 30, "epic": 60, "legendary": 90, "mythic": 120
}


## Tier value (0..4) for a rung name, or -1 when the name is not a rung.
static func value_of(tier: String) -> int:
	return int(VALUES.get(tier.to_lower(), -1))


## Rung name for a tier value, or "" when out of range.
static func name_of(value: int) -> String:
	return NAMES[value] if value >= 0 and value < NAMES.size() else ""


## True when `tier` names a real rung.
static func is_valid(tier: String) -> bool:
	return VALUES.has(tier.to_lower())


static func display(value: int) -> String:
	return DISPLAY[value] if value >= 0 and value < DISPLAY.size() else ""


static func roman(value: int) -> String:
	return ROMAN[value] if value >= 0 and value < ROMAN.size() else ""


## Canonical colour for a rung name (falls back to grey).
static func color(tier: String) -> Color:
	return COLORS.get(tier.to_lower(), COLORS["common"])


## Canonical colour for a tier value (falls back to grey).
static func color_of(value: int) -> Color:
	return COLORS.get(name_of(value), COLORS["common"])


## Stat total required to reach a rung (0 when unknown or ungated).
static func threshold(tier: String) -> int:
	return int(TIER_STAT_THRESHOLD.get(tier.to_lower(), 0))


## Clamp an arbitrary int to a valid tier value.
static func clamp_value(value: int) -> int:
	return clampi(value, 0, MAX_VALUE)


## Skill upgrade level (1..5) for a rung name, or 0 when not a rung.
static func level_of(tier: String) -> int:
	var v := value_of(tier)
	return v + 1 if v >= 0 else 0


## Rung name for a skill upgrade level (1..5), or "" when out of range.
static func tier_of_level(level: int) -> String:
	return name_of(level - 1)


## Roman numeral for a skill upgrade level (1..5), or "" when out of range.
static func roman_of_level(level: int) -> String:
	return roman(level - 1)
