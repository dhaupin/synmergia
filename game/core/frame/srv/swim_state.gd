## SwimState - the S14.2 water state machine as a frame primitive
## (labs conventions: pure logic, no autoload, no class_name, co-located
## test). The below-the-waterline mirror of GliderState: same shape,
## same discipline, one driver per realm.
##
## Owner vision (prd-ocean-depths.md sec 3): the ocean is a LAYER
## STACK -- WADING at the ankles, SURFACE_SWIM with your head up,
## SUBMERGED full swim, SQUEEZE as pressure ramps, and CRUSH where
## the ocean says no. Transitions are all functions of the sampler's
## depth and the body's up vector; the glider deploys OFF (water is
## not air -- the S16.4 vacuum gate's twin rule).
##
## Two honest clocks (prd sec 4): the BREATH meter is the tension
## mechanic (45 s under; surfacing resets; breathers multiply), and
## PRESSURE is the depth mechanic (accrues per second in SQUEEZE,
## scaled by the volume's pressure_per_meter). Breath drowning and
## pressure damage are separate pools -- the driver applies them to
## health as it sees fit (drowning converts, pressure bleeds).
##
## Buoyancy: near-neutral gravity from the movement profile; idle
## bodies sink at the terminal speed (you must swim to stay, which
## makes drowning honest).
extends RefCounted

enum State {
	DRY,          ## above the waterline (sampler says so)
	WADING,       ## ankle-deep: walk slowdown, breath refills, no swim
	SURFACE_SWIM, ## head above water: breath refills, stamina sprint
	SUBMERGED,    ## full swim: breath DRAINS
	SQUEEZE,      ## below the squeeze line: breath drains, pressure ramps
	CRUSH,        ## below max_depth: fast drain + heavy pressure
}

## The breath clock (prd sec 4): seconds of air an unbreathered body
## has. Breath accessories (S14.4) multiply this via the grace param
## below -- gear owns air, the profile owns speed (orthogonal or
## stacking becomes soup).
const BREATH_SECONDS: float = 45.0
## Pressure damage per second at the SQUEEZE line, scaled linearly
## deeper by the volume's pressure_per_meter (the driver multiplies).
const PRESSURE_BASE_DPS: float = 2.0
## CRUSH: the fast-drain multiplier on both clocks (the ocean saying
## no -- prd sec 3). Brutal but escapable: swim up.
const CRUSH_DRAIN_MULTIPLIER: float = 4.0
## Wading threshold (m): mirrors OceanVolume.band_for's ankle band.
const WADING_DEPTH_M: float = 1.2

var state: int = State.DRY
## Breath remaining (seconds). 0 = drowning: the driver converts to
## damage per second of continued submersion.
var breath: float = BREATH_SECONDS
## Pressure accrued in the SQUEEZE/CRUSH bands (the depth tax, a
## pool the driver drains into damage; surfacing does NOT reset it
## -- pressure eases off gradually, see release()).
var pressure: float = 0.0
## Drowning accrual (seconds past breath=0 while submerged). The
## driver converts this to damage.
var drowning_s: float = 0.0
## The body must surface to reset the breath clock. True while the
## last tick was in a refilling state (DRY/WADING/SURFACE_SWIM).
var surfaced_last_tick: bool = false


func reset() -> void:
	state = State.DRY
	breath = BREATH_SECONDS
	pressure = 0.0
	drowning_s = 0.0
	surfaced_last_tick = false


## Per-physics-tick update. depth: the sampler's signed depth (m,
## negative above the waterline); squeeze_line/max_depth: the
## volume's declared bands (m); pressure_per_meter: the volume's
## depth tax; breather_grace_m: total breather grace (S14.4).
## Returns the resulting state (drivers read it to apply physics:
## band speeds, buoyancy, damage).
func tick(delta: float, depth: float, squeeze_line: float, max_depth: float, pressure_per_meter: float = 0.0, breather_grace_m: float = 0.0) -> int:
	var prev := state
	var refilling := false
	# The breather's grace (S14.4) deepens the squeeze line -- the
	# free-swim band extends toward the rock, CRUSH never moves. The
	# service passes the raw line; the primitive owns the grace so
	# every caller's banding agrees with band_for's.
	var squeeze_eff := squeeze_line + maxf(breather_grace_m, 0.0)
	if depth < 0.0:
		state = State.DRY
	elif depth <= WADING_DEPTH_M:
		state = State.WADING
	elif depth < squeeze_eff:
		state = State.SUBMERGED
	elif depth < max_depth:
		state = State.SQUEEZE
	else:
		state = State.CRUSH

	# SURFACE_SWIM: submerged band but head near the surface -- the
	# top meter of the swim band lets you breathe (swim up and the
	# clock stops). Wading also refills.
	if state == State.SUBMERGED and depth <= WADING_DEPTH_M + 1.0:
		state = State.SURFACE_SWIM
	# The no-water sentinel (inside the rock) reads as DRY: the rock
	# is not water, no breath is spent, no pressure accrues.
	if depth == -1.0:
		state = State.DRY

	match state:
		State.DRY, State.WADING, State.SURFACE_SWIM:
			refilling = true
			breath = BREATH_SECONDS
			drowning_s = 0.0
			# Pressure eases off gradually (the body decompresses):
			# 2x the accrued rate, never below zero.
			pressure = maxf(pressure - PRESSURE_BASE_DPS * 2.0 * delta, 0.0)
		State.SUBMERGED:
			breath -= delta
			if breath < 0.0:
				drowning_s += delta
		State.SQUEEZE:
			breath -= delta
			if breath < 0.0:
				drowning_s += delta
			# The bite is the VOLUME's choice: the rate is the volume's
			# per-meter tax scaled by depth past the squeeze line, plus
			# the base DPS only when the volume taxes at all (a tame
			# pool declares pressure_per_meter 0 -- the workshop is
			# kind; the sea is not).
			if pressure_per_meter > 0.0:
				pressure += (PRESSURE_BASE_DPS + pressure_per_meter * (depth - squeeze_eff)) * delta
		State.CRUSH:
			breath -= CRUSH_DRAIN_MULTIPLIER * delta
			if breath < 0.0:
				drowning_s += delta
			if pressure_per_meter > 0.0:
				pressure += (PRESSURE_BASE_DPS + pressure_per_meter * (depth - squeeze_eff)) * CRUSH_DRAIN_MULTIPLIER * delta
	surfaced_last_tick = refilling
	if prev != State.DRY and state == State.DRY and depth == -1.0:
		pass  # rock entry: state jumps are the sampler's truth
	return state


## Full breath (breathers multiply the CLOCK, not the state machine):
## an S14.4 breather with air x4 feeds breath = BREATH_SECONDS * 4
## through set_breath_capacity at equip time.
func set_breath_capacity(multiplier: float) -> void:
	breath = clampf(breath * multiplier, 0.0, BREATH_SECONDS * multiplier)


## Is the body currently drowning (breath gone, still under)?
func is_drowning() -> bool:
	return breath <= 0.0 and (state == State.SUBMERGED or state == State.SQUEEZE or state == State.CRUSH)


## Should the glider deploy here? NEVER in water (water is not air;
## the twin of the S16.4 vacuum rule -- the wing needs air both ways).
func allows_glider() -> bool:
	return state == State.DRY


## Which swim speed applies (m/s): the driver reads the profile for
## the numbers, the state for WHICH row. Sprint is surface-only feel;
## the squeeze band slows you (drag the pressure makes honest).
func swim_speed_scale() -> float:
	match state:
		State.WADING:
			return 0.55
		State.SURFACE_SWIM:
			return 0.85
		State.SUBMERGED:
			return 1.0
		State.SQUEEZE:
			return 0.7
		State.CRUSH:
			return 0.45
	return 1.0
