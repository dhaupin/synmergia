extends Resource
class_name MountData

## Data-driven mount. The world forbids engines, so all mounts are
## creatures: ground beasts, sky birds, aquatic swimmers. Speed is a
## multiplier over the player's walk speed; faction-gated mounts carry
## a faction_id + favor currency cost for the vendor path.

enum MountKind {
	GROUND,
	FLYING,
	AQUATIC,
	SPACE
}

enum MountSource {
	DROP,
	QUEST,
	VENDOR,
	FACTION,
	EVENT,
	GM
}

@export var id: String = ""
@export var display_name: String = "Mount"
@export var description: String = ""
@export var icon_path: String = ""
@export var model_path: String = ""

@export var kind: MountKind = MountKind.GROUND

## Movement multiplier over base player speed. 1.0 = no benefit.
## Flying above ~2.2 and aquatic above ~1.8 should be rare/late-game.
@export var speed_multiplier: float = 1.3

## Mount stamina: the beast's own pool, separate from the rider's. Sprinting
## and climbing while mounted spend this pool (the rider's is not taxed
## twice); a rested mount refills it. Authored per mount -- a pack beast
## carries more than a courser.
@export var stamina: int = 100
## Fraction of max stamina restored per second while the mount is out. The
## MountData is the tuning surface; RideService owns the clock.
@export var stamina_regen_pct_per_sec: float = 0.02

## Movement Design System profile override. Empty = derived from kind
## (GROUND -> movement_quadruped, FLYING -> movement_aerial, AQUATIC ->
## movement_aquatic) via DataService.get_mount_movement_profile() --
## the single resolution path, no fallbacks in consumers.
@export var movement_profile_id: String = ""

## Character level required to ride.
@export var required_level: int = 1

## Faction gate: empty = anyone may ride once owned.
@export var faction_id: String = ""

## Acquisition
@export var source: MountSource = MountSource.DROP
## Cost in CurrencyData units (gold per_unit when currency_id is "").
@export var currency_id: String = ""
@export var cost: int = 0
## Where a DROP/QUEST source resolves (loot table id or quest id).
@export var source_ref: String = ""

## Soulbound mounts cannot be traded once bound.
@export var soulbound: bool = true

# S14.6 aquatic mounts (prd-ocean-depths.md sec 7): water mounts are
# rated BODIES for the squeeze band without a breather; land mounts
# bail at the waterline (swim_state.MOUNT_DISMOUNT_ON_SUBMERGE). The
# speed truth for a swimmer is swim_speed (m/s underwater cruise);
# speed_multiplier stays the land/air story.
@export var swim_speed: float = 0.0          # m/s underwater; 0 = cannot swim
@export var squeeze_grace_m: float = 0.0     # deepens the squeeze line (pearl_ray +6)
@export var crush_depth_bonus_m: float = 0.0 # the BODY's crush rating (trench_wyrm +30; gear never moves crush)
@export var current_immune: bool = false     # reef_glider swims its own vector; the sea does not carry it
@export var hitbox_profile_id: String = ""   # water mounts share the HitboxProfile system

## True when this mount can carry a rider underwater (kind AQUATIC
## with a real cruise speed -- the AQUATIC kind alone is not enough;
## the speed is what the anticheat stamps).
func is_swimmer() -> bool:
	return kind == MountKind.AQUATIC and swim_speed > 0.0


## The cliff law (glider_state.MOUNT_DISMOUNT_ON_FALL, decided in S12,
## wired by the riding layer): only GROUND mounts can be jumped off a
## cliff, so only they bail. Sky mounts fly -- falling IS their job;
## swimmers swim; space is space. A bond that dies at the bottom of a
## ravine is a broken promise, so the mount never falls: the rider
## dismounts into freefall and the mount returns to its whistle.
func bails_on_fall() -> bool:
	return kind == MountKind.GROUND

## Flavor: saddle color / harness accent for the renderer.
@export var tint: Color = Color(1, 1, 1, 1)
