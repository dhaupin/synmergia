## ThermalUpdraft - data-driven sky infrastructure (S12.5).
##
## Without engines, the sky needs roads. Two kinds:
##   THERMAL  - a standing updraft column: glide through it and the
##              sink bends toward float. The long-haul mechanic.
##   LAUNCHER - an ancient launch apparatus: dormant until awakened
##              (server effort / ritual -- the mystery beat), then
##              hurls anyone who steps in skyward so they can catch
##              a nearby thermal. The CODM totem, bent for Synmergia:
##              nobody places them; they wait in the lands.
##
## Schema: filename == id, "thermal_" prefix. Placed in
## data/thermals/ and resolved by ThermalService.
extends Resource
class_name ThermalUpdraft

enum Kind {
	THERMAL,   ## standing updraft column
	LAUNCHER,  ## ancient launch apparatus
}

enum Activation {
	ALWAYS,     ## active from boot
	RITUAL,     ## dormant until ThermalService.set_awake() flips it
}

@export var id: String = ""
@export var display_name: String = ""
@export var kind: Kind = Kind.THERMAL
@export var activation: Activation = Activation.ALWAYS
@export var zone_id: String = ""
## Which world owns the column ("" = the surface lands). Conjured
## globe realms hand out updrafts at world-local coordinates; the
## field keeps ownership explicit so a planar sampler and an
## underworld column can share one book without collision ambiguity.
@export var world_id: String = ""
## World-space center of the column/launch volume.
@export var position: Vector3 = Vector3.ZERO
## Radius of influence (m).
@export var radius: float = 12.0
## Top of the column above `position` (m) -- lift applies up to here.
@export var column_height: float = 120.0
## Strength 0..1: fraction of ThermalService.MAX_LIFT this updraft gives.
@export var strength: float = 0.6
## Launchers only: the upward speed they throw you at (m/s).
@export var launch_speed: float = 26.0
## The thermal this launcher feeds (id) -- the intended hop.
@export var feeds_thermal_id: String = ""
## Flavor: what the ancients built this for.
@export var lore: String = ""


## Ritual launchers sleep until ThermalService.awaken_launcher flips
## this (the service owns the book + persistence; the schema holds
## the truth the sampler reads).
var awakened: bool = false

## Is this updraft currently giving lift? (Ritual launchers sleep
## until awakened; thermals always breathe.)
func is_active() -> bool:
	if kind == Kind.LAUNCHER and activation == Activation.RITUAL:
		return awakened
	return true


## Sample the vertical speed contribution at a world position
## (0 when outside the column). Launchers inject a full launch burst
## at the base instead of a gradient.
func sample_vertical_speed(pos: Vector3, max_lift: float) -> float:
	if not is_active():
		return 0.0
	var flat: Vector2 = Vector2(pos.x - position.x, pos.z - position.z)
	if flat.length() > radius:
		return 0.0
	var height: float = pos.y - position.y
	if height < -2.0 or height > column_height:
		return 0.0
	if kind == Kind.LAUNCHER:
		# Launch burst: full throw at the base, decaying up the column.
		return launch_speed * maxf(0.25, 1.0 - height / maxf(column_height, 1.0))
	return max_lift * clampf(strength, 0.0, 1.0)
