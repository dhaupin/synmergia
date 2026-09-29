## GliderState - the S12 glider mechanic as a frame primitive
## (labs conventions: pure logic, no autoload, no class_name, co-located
## test). Realm-agnostic: both the radial globe body and planar room
## bodies drive it with their own up vector and altitude provider.
##
## Owner vision (prd-social-instances.md): jump off a height above X
## meters and the glider pops out -- automatically, or by pressing
## jump again mid-fall (a player setting). Works in ALL realms/zones.
##
## Mount rule (owner question: "if you jump a mount off a cliff lol"):
## the mount BAILS. The rider dismounts into freefall and the glider
## is usable from there; the mount despawns back to its whistle. A
## bond that dies at the bottom of a ravine is a broken promise -- so
## the mount never falls, and the player keeps the fall consequence.
## (Implementation lands with the mount-riding system; the constant
## lives here so the rule is decided once.)
extends RefCounted

enum State {
	GROUNDED,   ## on a surface; glider stowed
	FALLING,    ## airborne, glider not yet deployed
	GLIDING,    ## wing out: slow sink, pitch/thermal speed model
	STOWED_FALL ## player manually stowed mid-air; falls normally
}

## Deploy gate: falling above this height (meters) arms auto-deploy.
const DEPLOY_HEIGHT_METERS: float = 6.0
## Manual deploy grace: jump again within this window of falling to
## open the wing even below the height gate (small hops stay hops).
const MANUAL_DEPLOY_WINDOW_SECONDS: float = 4.0
## Glide model: sink speed while gliding (m/s), forward speed range
## between level flight and full dive.
const GLIDE_SINK_SPEED: float = 4.5
const GLIDE_SPEED_LEVEL: float = 7.0
const GLIDE_SPEED_DIVE: float = 16.0
## Thermal lift: updraft zones push back against sink (m/s).
const THERMAL_LIFT_MAX: float = 3.0
## The mount cliff answer.
const MOUNT_DISMOUNT_ON_FALL: bool = true

var state: int = State.GROUNDED
## Player setting: "auto" pops the wing at the height gate, "manual"
## requires the jump button again mid-fall. Fed in by PlayerConfig.
var deployment_mode: String = "auto"
## Seconds since the body left the ground (FALLING/STOWED_FALL only).
var fall_time: float = 0.0
## Last thermal strength the driver fed us (for diagnostics/UI).
var last_thermal: float = 0.0


func reset() -> void:
	state = State.GROUNDED
	fall_time = 0.0
	last_thermal = 0.0


## Driver hooks -----------------------------------------------------------

## The body just left the ground (jumped or walked off an edge).
func on_airborne() -> void:
	if state == State.GROUNDED:
		state = State.FALLING
		fall_time = 0.0


## The body touched a surface again (landed or wall-glued).
func on_grounded() -> void:
	reset()


## The player pressed jump again mid-air: manual deploy request.
func on_deploy_pressed() -> void:
	if state == State.FALLING and fall_time <= MANUAL_DEPLOY_WINDOW_SECONDS:
		state = State.GLIDING


## The player stowed the wing mid-air (same button, gliding).
func on_stow_pressed() -> void:
	if state == State.GLIDING:
		state = State.STOWED_FALL
		fall_time = 0.0


## Per-physics-tick update. altitude: meters above the nearest
## landing surface (radial height on the globe, -Y clearance in
## rooms). thermal: 0..1 updraft strength at this position.
## Returns the resulting state (drivers read it to apply physics).
func tick(delta: float, altitude: float, thermal: float = 0.0) -> int:
	last_thermal = thermal
	match state:
		State.GROUNDED:
			return state
		State.FALLING, State.STOWED_FALL:
			fall_time += delta
			# Auto deployment: high enough AND the setting says auto.
			if state == State.FALLING and deployment_mode == "auto" \
					and altitude >= DEPLOY_HEIGHT_METERS:
				state = State.GLIDING
				return state
			return state
		State.GLIDING:
			# Touch-down lands and resets.
			if altitude <= 0.5:
				reset()
				return state
			return state
	return state


## Vertical speed while gliding: sink minus thermal lift, never
## climbing above a gentle positive (a thermal floats, it does not
## launch).
func glide_vertical_speed(thermal: float = 0.0) -> float:
	var lift: float = minf(thermal * THERMAL_LIFT_MAX, THERMAL_LIFT_MAX)
	return GLIDE_SINK_SPEED - lift


## Forward speed while gliding: pitch from the driver (0 = level,
## 1 = full dive) maps onto the level/dive speed range.
func glide_forward_speed(dive_pitch: float = 0.0) -> float:
	var pitch: float = clampf(dive_pitch, 0.0, 1.0)
	return lerpf(GLIDE_SPEED_LEVEL, GLIDE_SPEED_DIVE, pitch)


## Should the wing have popped by now? (Driver diagnostic: auto mode
## and still falling above the gate after the grace = deploy next tick.)
func should_be_gliding(altitude: float) -> bool:
	return state == State.FALLING and deployment_mode == "auto" \
		and altitude >= DEPLOY_HEIGHT_METERS
