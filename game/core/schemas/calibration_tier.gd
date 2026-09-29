## CalibrationTier - the alignment substrate for the physics ladder
## (labs/prd-industry-labs.md, owner law: "the universe should align
## time, space, state irl" and "Linux epoch is/and should be aligned --
## that's the first thing I'd do in a physics engine").
##
## One tier per scale of construction (local/world/system/galaxy/
## universe). The tier DECLARES how that scale advances -- as DATA
## (.tres), so the OSS frame can be calibrated by anyone without
## touching code:
##
##   - fast tiers TICK (local combat physics at tick_hz),
##   - slow tiers EVALUATE (orbits/skies re-derived from the epoch --
##     evaluation has no drift because it has no integration),
##
## and EVERY tier aligns to the same source: the Linux epoch (unix
## seconds). SignService.sky_epoch_days() is unix/86400 -- the Concord
## calendar and the lattice already hang off it. The tier clock never
## replaces the epoch; it is an accuracy CONTRACT against it:
## max_drift_s is how far that scale's view may diverge from the
## epoch before a correction is mandatory, tick_horizon_s is how far
## a tick may run ahead, eval_period_s is the re-derivation cadence.
##
## Space anchors the same way: anchor names WHAT the tier is centered
## on ("world_center", "barycenter:<world_id>", "nsc9:<facility>"),
## so addressing and motion share one spine per scale. State follows:
## derives_state = true means the tier's state is a pure function
## (fold nothing); false means it replays the player-choice ledger.
##
## The Eve calibration thought: a planetary-scale game NEEDS universe
## scale -- the tiers exist so a game can RUN its construct at one
## tier while the ladder above it stays honest. Light-speed and
## big-bang velocity calibrations are declared, not consumed yet: the
## ladder is the reservation, the tiers are the spec.
extends Resource
class_name CalibrationTier

enum TierScale {
	LOCAL,     ## combat physics, movement: the 60 Hz tier
	WORLD,     ## weather, spawns, day cycle interior: the world heart
	SYSTEM,    ## orbits, transfer windows: the Concord clock tier
	GALAXY,    ## address-space stars (X2): the NSC-9 facility tier
	UNIVERSE,  ## slow ticks, ledger folds (X3): the civilization tier
}

## How this scale advances.
enum AdvanceMode {
	TICK,      ## integrate at tick_hz (fast tiers only)
	EVALUATE,  ## re-derive from the epoch (closed forms; no drift)
}

@export var id: String = ""
@export var display_name: String = ""
@export var scale: TierScale = TierScale.WORLD
@export var advance_mode: AdvanceMode = AdvanceMode.EVALUATE

## The alignment law. Only "unix" is valid today; the field exists so
## the contract is explicit in data (an OSS frame declares its epoch).
@export var epoch_source: String = "unix"

## TICK tiers: integration frequency (Hz). EVALUATE tiers: 0.
@export var tick_hz: float = 0.0

## TICK tiers: how far ahead of the epoch a tick may integrate (s)
## before it must re-align to the wall clock. EVALUATE tiers: 0.
@export var tick_horizon_s: float = 0.0

## EVALUATE tiers: re-derivation cadence (s); 0 = derive on every
## read (pure functions make that cheap -- the T2 theorem).
@export var eval_period_s: float = 0.0

## Accuracy contract: the maximum allowed divergence (s) between this
## tier's view of "now" and the epoch before correction is mandatory.
@export var max_drift_s: float = 0.0

## Space anchor: what this tier is centered on ("world_center",
## "barycenter:<world_id>", "nsc9:<facility>"). Addressing and motion
## share the spine per scale.
@export var anchor: String = "world_center"

## true: the tier's state is a pure function of (seed, epoch, anchor).
## false: the tier folds the player-choice ledger (X3) -- nothing
## stored that players did not choose, but what they chose is folded.
@export var derives_state: bool = true

## Worldbuilding notes (what this tier is FOR).
@export_multiline var lore: String = ""

## --- Cosmic constants (declared, consumed when the ladder reaches them) ----
## 0.0 = undeclared: the tier makes no cosmic claim. Declaring them in
## data (owner: "our calibration is speed of light and big bang
## velocity") reserves the seams WITHOUT spending premature precision
## -- the Knuth reconciliation, section 7.

## Speed of light in vacuum (m/s). SI exact: 299792458.0. Future
## consumers: inter-world communication lag (orbit_radius / c),
## telescope lookback on the galaxy tier, honest speed ceilings.
@export var light_speed_m_s: float = 0.0

## The big-bang velocity reservation: expansion rate H0 (km/s/Mpc).
## Future consumer: X3 cosmic fast-forward -- how the galaxy address
## space stretches over long epochs (the lattice grows because the
## universe says so, declared here rather than hard-coded).
@export var expansion_rate_h0_km_s_mpc: float = 0.0

## The origin: unix seconds of the big bang (0.0 = undeclared).
## Synmergia's is the FIRST COMMIT of its repo -- the universe began
## when the first line of its code was written; git is the fossil
## record. Consumers: cosmic_age_s and the light-cone horizon in
## world_registry (the outer limit, derived -- nothing stored).
@export var origin_unix: float = 0.0

## The Rest frame: the declared state of rest (the owner's trilateral
## calibration -- three intersecting icosahedral facilities define
## the reference, the way IRL astronomy anchors the sky to fixed
## quasars + the barycenter). Format: "nsc9:trilateral:<a>+<b>+<c>".
## DECLARED, not discovered: IRL has no center (every observer sits
## at the center of their own light cone); ours is wound.
@export var rest_frame: String = ""


## The tier's natural period (s): tick period for TICK tiers, eval
## cadence for EVALUATE tiers. Convenience for schedulers.
func period_s() -> float:
	return (1.0 / tick_hz if tick_hz > 0.0 else eval_period_s)
