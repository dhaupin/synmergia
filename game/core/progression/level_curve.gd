## LevelCurve - THE PROGRESSION RATIO LAW.
##
## ONE FILE OWNS THE PLAYER LEVEL CAP AND THE XP CURVE. No .tres ever
## encodes the cap; raising the level cap for a seasonal content pack
## is bumping DEFAULT_CAP (or shipping a LEVEL_CAP env) plus the pack
## itself. The band-side content never bakes an absolute ceiling: the
## data-level receipt (test_level_curve.gd) refuses any zone/quest/
## gateway max_level value that re-bakes a content ceiling above the
## tutorial gates.
##
## THE CURVE'S TWO HALVES:
##   * Levels 1..BAND_LEVELS keep the SHIPPED geometric law untouched --
##     cost(l) = XP_BASE * GROWTH^(l-1). Every authored quest reward and
##     every author's mental model was built against this envelope; the
##     tutorial band must never move under their feet.
##   * Past the band the curve BREATHES: a soft per-level ratio
##     (BAND_STEP) anchored at the band-top cost. The old 1.5^n driven
##     forever astronomical total is the reason the world "ended" at
##     level 30; a soft ratio past the band keeps every later chapter
##     reachable by the world's own income (quests, kills) without
##     re-tuning a single reward tres. Chapter pacing is authored in
##     the CONTENT (10-level bands of quests/enemies per season), and
##     the curve stays a smooth wall behind them.
##
## CAP LAW:
##   max_level() is the ONE authority. LEVEL_CAP env overrides for
##   deployments/seasons (junk or < 2 falls back to DEFAULT_CAP, never
##   a boot failure). PlayerManager consults max_level() and grows its
##   next-level cost from level_cost(); nothing else in the repo may
##   hardcode the cap.

extends RefCounted
class_name LevelCurve

## XP cost of level 1 (and the seed of the shipped 1.5^n envelope).
const XP_BASE: int = 1000

## In-band per-level growth. SHIPPED LAW -- do not touch; quest reward
## authoring assumes this envelope for levels 1..BAND_LEVELS.
const GROWTH: float = 1.5

## Levels inside the untouched shipped band (1..10).
const BAND_LEVELS: int = 10

## Post-band per-level RATIO. The multiplier the user asked for: the
## curve past the band compounds by BAND_STEP instead of GROWTH, so
## level 60 costs the same relative effort as level 30 did when the
## content band was seeded. Tunable per season WITHOUT touching data.
const BAND_STEP: float = 1.03

## THE CAP. Seasonal content packs raise it (60 now, 100+ later);
## LEVEL_CAP env overrides at deploy time.
const DEFAULT_CAP: int = 60
const CAP_ENV: String = "LEVEL_CAP"

## -- PHASE 3.1 SHARD TUNING (the "event shard" lever) --------------------
## A shard-local progression override, applied by ShardTuning from a
## ShardParameter write. It is a LOCAL READ, never a shared write: the
## mesh's hashed identity stays uniform (prd-shard-mesh.md sec.3.1).
## ONE process runs ONE shard, so a single static override is correct.
## Absent an override (0 / 0.0) the curve is UNIFORM -- the default case
## is not negotiable.
static var _shard_cap_override: int = 0
static var _shard_xp_ratio_override: float = 0.0

## Apply a shard-local tuning override. cap < 2 or ratio <= 0 means
## "unset" for that half; both unset restores the uniform curve.
static func set_shard_tuning(cap: int, xp_ratio: float) -> void:
	_shard_cap_override = cap if cap >= 2 else 0
	_shard_xp_ratio_override = xp_ratio if xp_ratio > 0.0 else 0.0

## Drop any shard-local tuning; the curve returns to env/DEFAULT_CAP.
static func clear_shard_tuning() -> void:
	_shard_cap_override = 0
	_shard_xp_ratio_override = 0.0

## True when a shard-local tuning override is in force.
static func has_shard_tuning() -> bool:
	return _shard_cap_override >= 2 or _shard_xp_ratio_override > 0.0

## The effective post-band per-level ratio (BAND_STEP unless overridden).
static func effective_band_step() -> float:
	return _shard_xp_ratio_override if _shard_xp_ratio_override > 0.0 else BAND_STEP

## The one cap authority. Precedence: a shard-local override (Phase 3.1)
## wins, then a sane LEVEL_CAP env (deployment default), then DEFAULT_CAP.
static func max_level() -> int:
	if _shard_cap_override >= 2:
		return _shard_cap_override
	var env := OS.get_environment(CAP_ENV)
	if env != "":
		var n := int(env)
		if n >= 2:
			return n
	return DEFAULT_CAP

## XP cost to clear `level` (the experience_to_next_level value a
## freshly-leveled body of that level carries). Monotonic non-decreasing.
static func level_cost(level: int) -> int:
	if level <= 1:
		return XP_BASE
	var cost: float
	if level <= BAND_LEVELS:
		# SHIPPED LAW: the 1.5^n envelope the world was authored against.
		cost = float(XP_BASE) * pow(GROWTH, level - 1)
	else:
		# BREATHING BAND: soft ratio anchored at the band-top cost. The
		# ratio is BAND_STEP unless a Phase 3.1 shard override is in force.
		var band_top := float(XP_BASE) * pow(GROWTH, BAND_LEVELS - 1)
		cost = band_top * pow(effective_band_step(), level - BAND_LEVELS)
	return int(cost)

## Total XP to level from 1 through `level` inclusive (income planning
## for content packs; the receipt prints it for calibration).
static func cumulative_cost_to(level: int) -> int:
	var total := 0
	for l in range(1, level + 1):
		total += level_cost(l)
	return total
