extends Resource
class_name MountData

## Data-driven mount. The world forbids engines, so all mounts are
## creatures: ground beasts, sky birds, aquatic swimmers. Speed is a
## multiplier over the player's walk speed; faction-gated mounts carry
## a faction_id + favor currency cost for the vendor path.

enum MountKind {
	GROUND,
	FLYING,
	AQUATIC
}

enum MountSource {
	DROP,
	QUEST,
	VENDOR,
	FACTION,
	EVENT
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

## Flavor: saddle color / harness accent for the renderer.
@export var tint: Color = Color(1, 1, 1, 1)
