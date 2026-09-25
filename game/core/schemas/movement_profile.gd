## MovementProfile -- data-driven movement parameters (Movement Design
## System, rando-batch 4 follow-up). One profile per archetype so walk/
## run/sprint/jump feel is CONSISTENT across all players, enemies, NPCs,
## and mounts: nothing hard-codes speeds, gravity, or friction in code.
##
## Layering (later wins, all optional):
##   1. profile .tres base values
##   2. species.speed_modifier (Entity stats)
##   3. mount/vehicle speed_multiplier (when mounted)
##   4. buff/debuff movement modifiers (AuraComponent)
##
## .tres files live in data/movement_profiles/ and are consumed via
## DataService. Profiles are pure data: no behavior lives here.
extends Resource
class_name MovementProfile

enum LocomotionClass {
	HUMANOID,   # players, humanoid NPCs -- walk/run/sprint/jump/crouch
	QUADRUPED,  # four-legged creatures -- faster, no crouch, grounded
	AERIAL,     # flying mounts -- gravity optional, hover + glide
	AQUATIC,    # swimmers -- buoyancy replaces gravity underwater
	MECHANICAL  # machines/vehicles -- instant accel, no stamina
}

@export var id: String = ""
@export var display_name: String = "Movement Profile"

## Which locomotion class this profile drives (drives state machine hooks).
@export var locomotion_class: LocomotionClass = LocomotionClass.HUMANOID

# -- Ground speeds (meters/second) ------------------------------------------
@export var walk_speed: float = 5.0
@export var run_speed: float = 7.5
@export var sprint_speed: float = 10.0
@export var crouch_speed: float = 2.0
@export var swim_speed: float = 3.0

# -- Air / vertical ----------------------------------------------------------
@export var jump_force: float = 10.0
@export var gravity_force: float = 20.0
## Terminal fall speed clamp (m/s). Prevents tunneling on long drops.
@export var terminal_fall_speed: float = 55.0
## 0..1 -- how much speed is retained each second mid-air. 1.0 = no drag.
@export var air_control: float = 1.0

# -- Feel: accel/decel (m/s^2). Low = floaty, high = snappy. ----------------
@export var ground_acceleration: float = 40.0
@export var ground_deceleration: float = 50.0
@export var air_acceleration: float = 12.0
## 0..1 -- how much outward momentum is scrubbed when changing direction.
@export var turn_grip: float = 0.85

# -- Costs & limits ----------------------------------------------------------
## 0 disables stamina costs entirely (enemies, mechanical).
@export var sprint_stamina_cost: float = 8.0
@export var dodge_force: float = 4.5
## Multiplier applied to walk/run speeds while moving backwards.
@export var backward_speed_multiplier: float = 0.6

# -- Instancing flags (server-authoritative gameplay tuning) ----------------
## If false, this profile never jumps (guards, most enemies).
@export var allow_jump: bool = true
## If false, crouch input is ignored (quadrupeds, mechanical).
@export var allow_crouch: bool = true
## If false, profile never sprints (ambient NPCs keep immersion).
@export var allow_sprint: bool = true


## Resolve the effective ground speed for a stance + context.
## stance: "walk" | "run" | "sprint" | "crouch"
## NOTE: `match` is a statement in GDScript, not an expression -- do not
## fold this back into `var base: float = match stance:` (parse error).
func get_ground_speed(stance: String, moving_backwards: bool = false) -> float:
	var base: float = walk_speed
	match stance:
		"walk":
			base = walk_speed
		"run":
			base = run_speed
		"sprint":
			base = sprint_speed
		"crouch":
			base = crouch_speed
	if moving_backwards:
		base *= backward_speed_multiplier
	return base


## Convert to the legacy stat block so existing consumers
## (species.speed_modifier layering) keep working unchanged.
func to_stats() -> Dictionary:
	return {
		"movement_speed_multiplier": 1.0,
		"walk_speed": walk_speed,
		"run_speed": run_speed,
		"sprint_speed": sprint_speed,
		"jump_force": jump_force,
		"gravity_force": gravity_force,
	}
