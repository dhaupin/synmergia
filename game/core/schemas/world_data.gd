## WorldData - one node of the multiworld lattice (S16.1).
##
## Every reachable world is a globe; every globe derives from ONE
## universe seed. A WorldData is a DECLARATION of physics and place in
## the lattice, never of content: terrain, zones, and history derive
## from the world's own seed (prd-multiworld.md sec 2).
##
## Data id conventions: filename == id, `world_` prefix
## (data/worlds/world_main.tres). Frame-adjacent schema like ZoneData.
extends Resource
class_name WorldData

enum WorldKind {
	MAIN,        ## the production planet (players live here)
	SUBWORLD,    ## planet-in-planet (the underworld: offline mystery layer)
	CELESTIAL,   ## another globe in the sky (the moon: dev target + base)
}

enum OfflineState {
	ONLINE,      ## player travel permitted (gates/scopes active)
	OFFLINE,     ## NO player path in (the underworld: comes later)
	DEV_ONLY,    ## probes/tests boot here; never shown to players
}

@export var id: String = ""
@export var display_name: String = ""
@export var kind: WorldKind = WorldKind.MAIN
@export var offline: OfflineState = OfflineState.ONLINE

## Lattice placement: "" = root node (the universe has exactly one
## root: world_main). Subworlds and celestial bodies name their
## primary; the registry derives their seeds through the parent.
@export var parent_world: String = ""

## Globe physics (mirror of the Movement/Instance contract values the
## globe scene consumes). Radius in meters; gravity m/s^2.
@export var radius_m: float = 20000.0
@export var gravity_force: float = 20.0

## Atmosphere: gliders need air (S16.4 hard rule -- the wing is a
## wing, not a magic carpet). False on the moon.
@export var has_atmosphere: bool = true

## Closed-form orbital placement (prd-multiworld sec 2.2). Empty
## radius/period = fixed placement (no orbit math applies). The orbit
## is a FUNCTION of the sky-clock epoch (SignService day index): no
## N-body simulation, ever. period_days in sky days; phase_rad is the
## epoch-0 angular offset; inclination_rad tilts the orbital plane.
@export var orbit_radius_m: float = 0.0
@export var orbit_period_days: float = 0.0
@export var orbit_phase_rad: float = 0.0
@export var orbit_inclination_rad: float = 0.0

## Spin period in sky days. 0 = tidally locked (the parent hangs over
## one meridian forever -- real Luna's condition, and the moon's
## default: where your base lands decides whether home ever rises).
## A positive value beats against the orbit and the parent rises and
## sets on the synodic schedule (WorldRegistry.parent_beat_period_days).
@export var spin_period_days: float = 0.0

## Worldbuilding flavor (what the almanac says about this place).
@export_multiline var lore: String = ""

## TERRAIN BACKEND (the heightfield-source seam, terrain_gen.gd):
## which AUTHORED backend legally reshapes this world's raw land, if
## any. Empty = the natural analytic law (the home world as geology
## made it). Data-driven so authored terrain is a DECLARATION on the
## world, not a code install in the boot. The globe scene resolves
## the id to a backend class at ready and installs it through the
## seam (sculpt/guarantee laws stay law-native on top; the seed law
## keys everything, so the same declaration is the same world).
@export var terrain_backend_id: String = ""


## Derivation path for this world's seed, under the universe root.
## Pure function: the registry feeds it to SeedChain.derive_seed as
## the path segment (domains never collide because paths nest:
## "world:main" vs "world:underworld" vs "world:moon/subworld:x").
func seed_path() -> String:
	var path := "world:" + id
	if parent_world != "":
		path = "world:" + parent_world + "/subworld:" + id
	return path


## Can a player ever stand here? (Gates, scopes and UI all read this
## before anything else -- the underworld's door simply does not
## exist while OFFLINE.)
func is_enterable() -> bool:
	return offline == OfflineState.ONLINE


## Does the glider deploy in this world? (No atmosphere = the wing
## stays stowed; the moon reads alien because falling is honest.)
func allows_gliding() -> bool:
	return has_atmosphere
