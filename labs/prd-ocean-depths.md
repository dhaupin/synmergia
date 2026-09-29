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
