# PRD: The Ocean Layer - Swimming, Water, and Vessels (S14)

> **Status:** DESIGN (pre-implementation)
> **Law:** `labs/prd-psy.md` (no religion anywhere in this doc), locked
> decisions in `AGENTS.md`, spherical-world truths in
> `labs/prd-spherical-mvp.md`.
> **Naming:** water volumes are `ocean_` prefixed data ids, like
> thermals and hitboxes are data. The Movement Design System keeps
> owning speeds.

## 1. The Owner Vision (2026-09-29)

"With flying, we have multiple heights upward. We need to mimic the
layering to heights downward, respecting clip of the land. You got it,
swimming. While we are here ... we should design the ocean, boats,
vehicles, ferries, hovercraft whatever, then set up the system for
swimming in the movement system (+Anticheat), the physics of
underwater, a new accessory class for 'breathers' ... Underwater
mounts (like an octopus). Let's make this world traversible."

The vertical story so far: ground (S3-S8), thermals + gliders up
(S12/S12.5). S14 is the mirror below the waterline. It is NOT one
feature: it is a layer stack, and the layer stack is the point --
every layer below the surface is content, traversal, or economy on
its own.

## 2. Water Is Data (the volume model)

Water is a first-class data resource, exactly like ThermalUpdraft:
the renderer paints it, the physics reads it, the anticheat reads it,
and nobody hardcodes a coastline.

### OceanVolume schema (`data/oceans/`, `ocean_` prefix, filename == id)

```
@export var id: String = "ocean_haven_shelf"
@export var display_name: String = "The Haven Shelf"
@export var surface_height: float = 0.0        # waterline (world Y)
@export var floor_provider: String = ""        # "" = planet shell; else TerrainService channel
@export var max_depth: float = 60.0            # below surface: swim -> squeeze -> crush
@export var current_direction: Vector3 = ...   # drift (m/s), currents are weather for water
@export var current_strength: float = 0.0
@export var pressure_per_meter: float = 0.1    # the depth tax (see 4)
@export var salinity: float = 1.0              # 0 = the dead lakes; future: buoyancy flavor
@export var ambient_fog: Color / density      # the look, per volume
@export var ambient_sounds: Array[String]      # AudioService names
```

**Layering mirrors the sky.** Thermals are volumes you pass through;
oceans are volumes with a surface you cross. `sample_depth(pos)`
returns meters below the waterline (negative above water, mirroring
ThermalService.sample's sign discipline). One sampler, three readers:
physics, renderer, anticheat. Truth lives ON the resource.

**Terrain respect (owner: "respecting clip of the land"):** the
ocean shell is the planet shell minus a carve-out; `sample_depth`
clamps to the floor so you can never swim through rock. The floor is
read from the same radial geometry the globe walk uses -- one
distance-to-center call, no second collision world.

## 3. Swimming in the Movement System

### MovementProfile gets an aquatic class

The Movement Design System already owns locomotion
(`data/movement_profiles/`, AERIAL exists for the glider). Add:

```
LOCOMOTION_CLASS.SWIM
movement_swim.tres:  walk 2.6 / sprint 4.8 m/s surface, 3.4 m/s
                     underwater, dive 5.5 m/s (down-pitch),
                     gravity 1.2 (nearly neutral), jump_force 0,
                     terminal_fall_speed 3.0 (sinking when idle)
```

Anticheat reads the SAME profile the feel does: a swimmer's hard
limits derive from `movement_swim.tres` via the existing
`set_movement_limits` path, with water-specific maxima (see 6).

### The state machine (globe_player, planar-agnostic)

Surface states: `WADING` (ankle-deep, walk slowdown), `SURFACE_SWIM`
(head above waterline; stamina-taxed sprint), and below:
`SUBMERGED` (full swim), `SQUEEZE` (below max_depth - grace:
pressure damage ramps, vision closes), `CRUSH` (below max_depth:
hp drain fast; this is the ocean saying no).

Transitions are all functions of `sample_depth(pos)` and the body's
radial up. The glider deploys OFF (water is not air); mount rules
hand off per 7.

**Buoyancy:** neutral at rest (idle sinks at terminal 3.0 m/s --
you must swim to stay, which makes drowning honest). Space/toward-
surface input swims up at dive speed; the existing planar branch
and the radial branch both consume the same vertical-speed model.

## 4. Underwater Physics (the honest part)

- **Drag:** velocity decays toward `current_direction * strength`
  (currents push; a swimmer fights them, a ferry uses them).
- **Pressure (the depth tax):** below `max_depth - grace` the
  body accrues pressure damage per second scaled by
  `pressure_per_meter`; breathers (5) extend BOTH grace depth and
  air time. The ocean has teeth like the storm has teeth -- but
  they are optional teeth: you choose to go deep.
- **Air clock:** a per-body breath meter (default 45 s, breather
  accessories multiply). Running out converts to drowning damage;
  surfacing resets. The meter is the tension mechanic; pressure is
  the depth mechanic. Two clocks, one honest ocean.
- **Light:** fog density ramps with depth (OceanVolume.ambient_fog);
  below 60% depth the world goes to murk. Sound: AudioService gets
  water-name WAVs (muffle filter is a stretch goal, not a promise).

## 5. The Breather (new accessory class)

Accessories are `acc_` prefixed (conventions locked). New
`AccessoryClass.BREATHER`:

```
acc_breather_reed        starter: air x2, grace +2 m   (crafted)
acc_breather_lungshell   mid: air x4, grace +8 m       (deep drop)
acc_breather_abyss_pearl endgame: air x8, grace +20 m, current immunity (the mystery drop)
```

Reagent `res_abyss_pearl` exists only below max_depth - grace --
the ocean's own loot hook, the reason anyone goes deep. Breathers
do NOT touch swim speed (MovementProfile owns speed; gear owns
air) -- the two systems stay orthogonal, or stacking becomes soup.

## 6. Anticheat Hooks (S14 additions to the ticket/limit model)

- **`set_aquatic_active(player_id, bool)`** -- the water twin of
  `set_glide_active`: while SUBMERGED, limits swap to the swim
  maxima (speed 6.5, launch 0, fall 3.0 x multipliers). A "swimming"
  player moving at 20 m/s is a hack, not a fish.
- **Dive tickets:** mirroring launch tickets, `grant_launch_grace`
  (rename: `grant_vector_grace`) with a NEGATIVE speed legalizes the
  entry plunge (falling off a boat at sail speed); horizontal stays
  hard-checked. Same whitelist discipline as the launcher.
- **Stat clamp:** swim-distance accrual (if we ever track swim
  achievements) rides the existing per-tick clamp; no new farm vector.
- **Current drift exemption:** currents move bodies passively; the
  validator ignores current-only displacement via the volume's
  declared current vector (server-side truth again).

## 7. Underwater Mounts

The octopus is the flag mount. Mount rules inherit the S12 cliff
rule (MOUNT_DISMOUNT_ON_FALL generalized: MOUNT_DISMOUNT_ON_SUBMERGE
for land mounts -- the horse bails to the whistle at the waterline,
the rider keeps swimming). Water mounts:

```
mount_reef_glider    octopus: jet propulsion bursts, grabby, 7 m/s, ignores currents
mount_pearl_ray      manta: fast steady 9 m/s, shallow diver (grace +6)
mount_trench_wyrm    endgame leviathan-class: crush-rated (max_depth +30), terrifying
```

Water mounts share the HitboxProfile system (new `hitbox_swimmer_*`
profiles) and are the only bodies rated for the SQUEEZE band without
a breather.

## 8. Ocean Design (the world side)

Start with ONE real ocean and the dead lakes:

- **The Sundered Sea** (west of Haven): a real shelf -- reef gardens
  at 10-20 m (starter swim content, the reed breather's depth), a
  kelp forest at 30-40 m (pearl drop band), a trench at 55-60 m
  (the mystery; the pearl ray's home). Currents run a loop; the
  loop is the ferry lane.
- **The Dead Lakes** (salinity 0): swimmable, no currents, nothing
  lives there, the lore remembers why (prd-psy-safe copy).
- **Ferries** (S14.5, needs vehicles): scheduled surface vessels
  Haven <-> Far Shore; riding a ferry is the no-swim crossing for
  low levels; ferries are also the oPvP window (classic risk/reward).

## 9. Vehicles (vessels, the traversal economy)

Phase 1 (S14.5): **Ferries** -- scripted, scheduled, server-owned
paths between ports (veh_ data ids per conventions; ferry = moving
safe zone with a deck; the deck is an instance-like scope riding a
path). Phase 2 (S15+): **Player boats** -- hovercraft/raft tier
crafted at a dockyard (new station), one seat + cargo, ownable like
dwellings. Phase 3: **deepwater hulls** (crush-rated, pearl-lock).

Vehicles reuse the bout physics contract: PLANAR deck gravity,
radial world outside -- a ferry is a small instance that happens
to move.

### The ferry honesty law (owner question, 2026-09-29: "are they
real time, like you ride them, or like a gate?")

**Both, honestly labeled.** Three crossing tiers on one route:

1. **The real ferry (ride it).** A server-owned vessel on a
   schedule: a deck scope riding a path (the bout physics
   contract -- planar deck, radial world). The crossing is REAL
   TIME and that is the point: the Sundered Sea crossing is ~8
   minutes at ferry speed, and those minutes are CONTENT -- other
   passengers, the oPvP window, the sky changing overhead (the
   Concord clock makes the ride's sky a function of when you
   sail). Fitted with benches (seats), the crew lore, and the
   wake. The ferry is not a loading screen; it is a moving room.
2. **The chartered skiff (fast, priced).** For players who have
   crossed before: an NPC-piloted small boat that rides the same
   path at ~2.5x speed (~3 minutes), ticket-priced (the gold
   sink). Still real time -- you see the crossing go by -- but you
   are not socializing it.
3. **The established wake (the gate tier).** Once a ferry route
   has run N crossings (or a player has ridden it M times), the
   route's PORTS unlock a warp option at the dock: "the wake is
   known." This is the honest teleport: you are paying (gold or
   the ride history) for ROUTINE. First crossings are never
   skippable -- the world makes you ride the sea at least once.

This mirrors the Concord's own law: the sky is a clock you can
read, so a scheduled boat is trustworthy -- and the almanac gets a
sailing page (when the next ferry leaves) exactly like the moon
page. Rivers later reuse the current data + the same three tiers
at smaller scale (rowboat ferry across a river bend).

## 10. Implementation Order

| Slice | Content | Gate |
|-------|---------|------|
| S14.1 | OceanVolume schema + service (sample_depth) + surface detection -- SHIPPED (see sec 12) | probe_ocean 27 |
| S14.2 | Swim movement class + state machine + air clock + pressure | probe_swim 14+ |
| S14.3 | Anticheat aquatic limits + dive tickets + current exemption | extend probe_ocean |
| S14.4 | Breathable accessories + abyss pearl economy | lint + data refs |
| S14.5 | Ferries (veh_ data, port-to-port schedule, deck scope) | probe_ferry |
| S14.6 | Water mounts + hitbox profiles | probe_water_mounts |
| S14.7 | The Sundered Sea content pass (reef/kelp/trench) | world probe |

Every slice keeps the regression DEFAULT_SET green; the ocean never
touches bout physics (the arena has no ocean -- the SUndered Valley
is landlocked, and that is canon now).

## 11. Open Questions (owner)

1. Drowning death: normal respawn, or corpse-sink recovery (dive
   to your body to recover gear)?
2. Should currents power small watermill dwellings (economy hook)?
3. Ferries: free, ticket-priced (gold sink), or faction-gated?

## 12. S14.1 as built (2026-09-29) + the moon lore lock

**The Watched Stone (lore decision, owner-approved).** Moon lore
options A+B adopted: the moon is where the world works on itself --
the builders (the ancients, the devs) come and go as the sky
aligns, the regolith workshop is canonically where Synmergia is
maintained ("whatever they are working on, they always come through
for us"), and the address observatory idea reserves the star-cell
endgame. In a world without religion this is the faith-shaped hole
the builders fill. The dev hatch is PERMANENT and never lore-gated;
the world_moon.tres lore and the gate's arrival line carry it.

**Water as data, shipped.** `core/schemas/ocean_volume.gd` (schema,
filename == id, `ocean_` prefix) + `core/services/ocean_service.gd`
(autoload, NO class_name) + `data/oceans/*.tres`:

- **Sign discipline** (the ThermalService mirror): sample_depth < 0
  = meters ABOVE the waterline, >= 0 = meters below.
- **Pressure depth is the water ABOVE the body.** 23 m of water
  over a body 1 m above the floor is 23 m pressure depth. The rock
  does not reduce depth; it REFUSES: a body pushed inside the stone
  reads the -1 no-water sentinel (the rock is not water).
- **Two honest floor models** on one schema: WORLD-SHELL (radial
  sphere -- ready for a true globe-wrapped scene) and LOCAL pool
  (rock plane at floor_y -- the honest geometry for a playable
  dish/shelf). Both shipped volumes are LOCAL: the Haven Shelf
  (60 m, currents 0.4 m/s -- the ferry lane) and the **Builder's
  Pool** (24 m tame crater water on the moon: no current, no
  pressure -- the dev workshop's test water, S14.2's first swimmer).
- **One sampler, three readers**: physics/renderer/anticheat all
  call OceanService; band_for maps depth+breather grace to
  DRY/WADING/SUBMERGED/SQUEEZE/CRUSH. The breather law: grace
  DEEPENS the squeeze line (50 -> 58 with grace 8 on a 60 m
  volume); CRUSH never moves (gear extends the swim, not the
  stone's patience).
- **Specificity rule**: overlapping claims resolve to the TIGHTER
  horizontal reach (the 40 m crater dish beats a broad shelf
  column); volumes that do not overlap in XZ do not fight at all.

`probe_ocean.gd` (27 checks, in DEFAULT_SET) holds the law set:
sign law, stone-sentinel, band ladder + breather direction,
current truth, specificity, and the Builder's Pool on the Watched
Stone. Lessons: the probe caught a BACKWARDS squeeze formula (more
grace made squeeze start shallower), a depth/column conflation,
and a str_replace line-glue that commented out the entire clamp
block -- all before any swimmer existed.

## 13. S14.2-S14.4 as built (2026-09-29): swim, anticheat, gear, sailing

**The swim class (S14.2).** `core/frame/srv/swim_state.gd` is the
glider's below-water twin: DRY/WADING (1.2 m)/SURFACE_SWIM (the
top meter breathes)/SUBMERGED/SQUEEZE/CRUSH, a 45 s breath clock,
and a pressure pool that accrues only when the volume taxes
(`pressure_per_meter > 0` -- the tame pool is tame by
declaration). The rock sentinel (-1) reads DRY: no breath spent,
no clocks. `movement_swim.tres` (AQUATIC class 3, swim 3.4 m/s,
no jump, gentle gravity) makes the feel data. OceanService.
tick_swimmer drives it and returns {state, depth, band, current,
breath, pressure, drowning_s} in one call.

**Aquatic anticheat (S14.3).** While `_aquatic_limits` holds a
body, validate_movement judges it by the SWIM maxima (speeds x
the standard multipliers), never the humanoid's. The current is
SERVER TRUTH: `set_current_drift` stamps the OceanVolume's
declared vector, and `_legal_under_current` resolves the body's
horizontal velocity onto it -- the parallel component is passive
water, the perpendicular is the swimmer's own effort and stays
hard-checked; parallel <= 0 (upstream) earns nothing. A zero
current erases the stamp (still water judges again). DIVE
TICKETS mirror the launch tickets (30 m/s ceiling, 3 s,
prune-on-read) and forgive ONLY the downward plunge past the swim
terminal -- the boat-fall entry; horizontal and absurd-vertical
checks never yield. unregister_player clears all three books.

**The breather (S14.4).** Gear owns air; the MovementProfile owns
speed (orthogonal or soup). Item gains AccessoryType.BREATHER +
breath_multiplier/squeeze_grace_m; the Hollow Reed (x2, +2 m) and
the Lungshell (x4, +8 m) sit on the NECKLACE slot;
`OceanService.breather_for(player_id)` resolves through
InventoryService to {mult, grace_m} (default {1.0, 0.0} when
anything is missing). The grace deepens the squeeze line and the
multiplier feeds set_breath_capacity -- CRUSH never moves (gear
extends the swim, not the stone's patience). THE ONE-DERIVATION
LAW (learned by probe): the PRIMITIVE applies the grace
(squeeze_eff); band_for applies the same grace -- service and
state can never disagree about where squeeze starts.

**The sailing page (sec 9 honesty law, delivered).** VehicleData
gains ferries_per_day / first_departure_hour / crossing_hours: a
closed-form schedule evaluated off the Concord epoch (the same
one-clock-read discipline as the moon) -- no timetable table is
stored, so chart and dock cannot disagree. veh_haven_ferry
declares 8 cast-offs/day, first at 06:00, a 30-min crossing.
SkyAlmanacUI's sailing page shows the route, the crossing in
minutes, the next cast-off (Day N, h into the day, hours out,
with a departing-now window), and the wake law line ("The first
ride always takes the water. After that, the wake remembers
you."). `_sail_ferries` reads the vehicle declarations directly:
the almanac is a chart, not a service; the FerryService (S14.5)
will honor the same math.

## 14. S14.5 as built (2026-09-30): the ferry is a moving room

**The schedule is ONE primitive.** `core/frame/srv/ferry_schedule.gd`
(pure, no autoload, co-located test) is the closed-form law:
departure_hours / next_departure / crossing_in_progress off the
Concord epoch. The almanac page and FerryService BOTH call it --
a disagreement between chart and dock is now structurally
impossible (the S14.5 cleanup: the page used to keep its own
private departure math). THE CAST-OFF INSTANT BELONGS TO THE
BOARDING WINDOW: crossing_in_progress starts strictly after the
departure hour, so "boarding" and "at sea" can never both be
true at 09:00 (the probe caught the boundary claiming both).

**The tiers (prd sec 9, honest).** FerryService (autoload, NO
class_name, registered after OceanService): board_ferry is FREE
and refuses outside the boarding window ("the boat has sailed");
an empty boat stays tied up (the crew waits for a manifest);
arrival records the wake and notifies each rider (ZONE_CHANGED).
The chartered skiff is 2.5x (SKIFF_SPEED_MULT), ticket-priced
through InventoryService.remove_gold (the gold sink), and the
WAKE LAW refuses a rider with zero recorded rides -- first
crossings are never skippable. The wake ledger persists one
DictStore key per player (the WaypointService idiom) and
survives reboots; wake_is_known at 3 rides is the dock-warp
tier's gate (UI later).

**The manifest is session truth.** A rider who logs out misses
the boat; an EMPTIED DOCK releases its claimed sailing slot (no
phantom sailings), but a boat at sea sails on. The v0 path
contract: positions are the ports (the deck is virtual; ride
time and schedule are honest already -- ride motion is S14.6+).
The driver is a 1 s timer (the SignService idiom); abandon_riding
is the logout seam until a roster signal exists (there is none
yet -- InventoryService.unregister_inventory is equally
uncalled).

`probe_ferry.gd` (25 checks, in DEFAULT_SET) + `test_ferry_schedule.gd`
(11 checks, co-located, in DEFAULT_SET). The probe caught: the
cast-off boundary ambiguity, the phantom sailing after a full
desertion, and (in the schedule test) three of my own wrong
hand-derivations -- the primitive was right every time.

## 15. S14.6 as built (2026-10-05): water mounts are rated bodies

**The schema.** MountData gains the aquatic half: `swim_speed` (m/s
underwater cruise -- the speed truth for a swimmer;
`speed_multiplier` stays the land/air story), `squeeze_grace_m`
(deepens the squeeze line), `crush_depth_bonus_m` (the BODY's crush
rating), `current_immune`, `hitbox_profile_id` (water mounts share
the HitboxProfile system), and `is_swimmer()` (kind AQUATIC AND a
real cruise -- the kind alone is not enough; the speed is what the
anticheat stamps). MountKind.AQUATIC was pre-declared; the data now
honors it.

**The three mounts.** `mount_reef_glider` (octopus, 7 m/s,
current_immune -- the sea does not carry it), `mount_pearl_ray`
(manta, 9 m/s, squeeze grace +6 -- the shallow diver), and
`mount_trench_wyrm` (8 m/s, crush_depth_bonus_m 30 -- the only body
the deep stone has made room for). Hitbox profiles
`hitbox_swimmer_medium` (octopus + ray) and `hitbox_swimmer_large`
(wyrm) join the HitboxProfile family.

**The laws (one derivation, extended).** `MOUNT_DISMOUNT_ON_SUBMERGE`
lands in swim_state as MOUNT_DISMOUNT_ON_FALL's water twin: land
mounts bail at the waterline (allowed DRY/WADING only -- ankle-deep
riding is honest, body-in-water riding is not), water mounts ride
every band and their reach is the rating's job, never a second
gate. The grace law extends cleanly: gear grace (breather + mount
squeeze_grace_m) SUMS into the squeeze line; the crush bonus moves
CRUSH and only a rated body's bonus can -- the stone bends for
rated bodies, never for equipment. `band_for` and `tick` both grew
a `crush_bonus_m` parameter in the same shape as S14.4's grace law.

**The anticheat needs nothing new.** `set_aquatic_limits` already
takes per-body maxima (the caller stamps the mount's cruise), and
current immunity is a stamping rule: `OceanService.effective_current
(pos, current_immune)` is the one seam -- the anticheat stamp reads
THIS, never `current_at`, and a zero stamp erases the
passive-drift forgiveness (the existing still-water law).

**THE BUG THE PROBE CAUGHT (the round's lesson).** My first
"fish" check failed for a boring reason (the validator's
SPEED_LIMIT_MULTIPLIER of 2.5 makes the ray's ceiling 22.5 m/s -- a
20 m/s body is legal; the honest hacker swims 30). The REAL catch
was deeper: writing the gear-grace-vs-crush assert exposed that
`tick` and `band_for` DISAGREED whenever gear grace pushed the
squeeze line past max_depth (tick checked squeeze before crush, so
62 m at grace 20 read SUBMERGED while band_for said CRUSH -- latent
since S14.4 because no test had grace that large). Fixed by checking
CRUSH first in tick (the band_for order); the probe now pins both
sides of the law: gear never buys crush, ratings do.

`probe_water_mounts.gd` (30 checks, in DEFAULT_SET) + the mount-law
section (G) in the co-located `test_swim_state.gd`. The ocean family
is green: probe_ocean, probe_swim, probe_ferry, test_ferry_schedule,
data lint, movement profiles -- the ocean still never touches bout
physics.
