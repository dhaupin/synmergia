# PRD: Multiworld - Space Travel, Relational Worlds, and the Universe Frame (S16)

> **Status:** DESIGN (pre-implementation)
> **Law:** prd-psy (no religion; the sky is machinery, and the
> machinery is allowed to be mysterious without being divine).
> Owner vision 2026-09-29: "space travel is required ... Relational
> math between worlds, traveling to other planets. The planets would
> be just another globe, with the sky rendered as the other planet,
> similar to underworld. Like if synmergia had a moon, it's a new
> mystery TBA." And the thesis: "Let's design, mathematically, very
> efficiently, like a clock you wind once a year, the universe if we
> need it."

## 1. The Thesis (why this PRD exists)

Every world is a globe; every globe is a seed; every seed is a
derivation from ONE universe seed. The frame already has the parts:

- SeedChain: HMAC domain derivation (universe -> world -> zone ->
  patch). One wind, infinite worlds, zero stored coordinates.
- NSC-9: discrete spatial addressing per globe.
- T3 state tree: content-addressed world state, namespaced by world.
- Movement/hitbox data systems: bodies and volumes as data.

What multiworld adds is the RELATIONAL MATH between roots, and the
transit that respects it. The design rule is the clock rule:
deterministic where possible, stored only where players choose.

## 2. The Lattice (relational math between worlds)

### 2.1 World Registry (derived, not authored)

```
universe_seed (the one constant)
  -> world:main      = HMAC(universe_seed, "world:main")
  -> world:underworld = HMAC(universe_seed, "world:underworld")
  -> world:moon       = HMAC(universe_seed, "world:moon")
```

Each world declares (data, `worlds/` dir, `world_` prefix):

```
@export var id: String = "world_moon"
@export var parent_world: String = ""          # "" = root lattice node
@export var radius_m: float = 1200.0           # small globes are fine
@export var gravity_force: float = 6.0         # the moon is light
@export var orbit: Dictionary = {}             # relational placement (2.2)
```

### 2.2 Orbital Placement (pure functions, no simulation)

Bodies hold their geometry with pure relational math: a world's
center relative to its parent is

```
rel(r, epoch) = orbit_axis rotated by (2pi * epoch / orbit_period)
              * orbit_radius + orbit_phase
```

- Epochs come from the sky clock (SignService day index) -- the
  same clock that moves the sun moves the moon. ONE time truth.
- No live N-body: orbits are CLOSED FORM. The clock you wind once
  a year. "Where is the moon" is a function call, not a simulation.
- Tidal phase (see 4) derives from the same epoch -- tides, sky
  moods, and moon gates all read one clock.

### 2.3 Transfer Windows (the mystery-friendly mechanic)

Because orbits are closed form, transfer windows are computable
YEARS ahead: windows are epochs where source->target delta-v
(even a fantasy version: "wind favorability") passes a threshold.
The first moon gate opens on the first window after the mystery
unlocks. The ancient launchers (S12.5) are the same technology at
planetary scale -- the sky roads were always a transit system.

## 3. Travel (how a player moves between roots)

Phase 1: **The Moon Gate** -- a sealed structure (AncientDoor
pattern reprise) that, when the mystery is solved, scene-swaps the
player to `world_moon`'s globe. ScopeService already owns
scope swaps (globe|bout|spectate); add `world:<id>` scopes.
The swap is the SAME seam as scene swap/bout return -- one more
scope, not a new architecture.

Phase 2: **Player flight between roots** is the long-arc version
of the same seam (leave one globe's SOI, arrive in the next).
Phase 1 ships first because it proves the relational math without
building a flight simulator.

Transit fog: between worlds, the sky of the ORIGIN fades and the
sky of the DESTINATION fades in (both are rendered globes; the
underworld proved the interior-sky trick, the moon proves the
exterior one). The destination planet IS the sky you approach.

## 4. The Moon (the mystery, TBA by design)

- world_moon: radius ~1.2 km, gravity 6 m/s^2 (jump arcs get
  dreamlike; movement profile `movement_lunar.tres`), no
  atmosphere (gliders do NOT deploy -- the wing needs air; this
  is a hard physics rule that makes the moon read alien), regolith
  terrain, earthrise over the horizon every orbit (closed form,
  like everything else).
- The moon is ALSO the open-source playground: low gravity, tiny
  globe, zero production risk -- the best possible demo of the
  frame (my pick for the dev target, see 7).
- Lore: the moon watches. The Skyward Concord almanac already
  tracks the sky; the almanac gets a moon page that has been
  blank since forever, and the blank page is the mystery hook.

## 5. State and Persistence

- Per-world T3 roots: `world:<id>` namespace; snapshots per world;
  cross-world player state (position = world_id + NSC-9 address)
  in the session book. A player is ALWAYS in exactly one world.
- The frame's claims we should be able to make after S16:
  deterministic world derivation from one seed; closed-form
  celestial relation; O(1) world lookup; content-addressed
  cross-world refs.

## 6. Compute Thesis (the owner's "weird shit" clause)

The bet underneath: most MMO compute is spent simulating things
players cannot perceive. The frame's answer is derivation: a
planet, an orbit, a tide, a seed -- all functions of (seed, epoch),
never stored, always recomputable. If the frame ever hits its
compute ceiling, the answer is more derivation, not more servers.
The moon will be the proof: an entire reachable world that costs
one HMAC and a camera trick to exist.

## 7. Implementation Order

| Slice | Content |
|-------|---------|
| S16.1 | WorldData schema + registry (derived seeds) + per-world T3 namespacing |
| S16.2 | Closed-form orbit math + epoch clock integration (frame/math, co-located tests) |
| S16.3 | ScopeService world scopes + Moon Gate scene swap (offline door first) |
| S16.4 | world_moon minimal globe (lunar movement profile, no-atmosphere glider rule, earthrise) |
| S16.5 | Transfer windows + almanac moon page (the mystery shell) -- SHIPPED: the gate honors the sky (7a08b09) and the almanac moon page reads the same math (sec 9, the chart-and-stone law) |
| S16.6 | Dev target: probes/tests run on the moon globe -- SHIPPED: the moon globe CONJURES at gate transit (scenes/worlds/globe_moon.gd), the placed gate carries the dev_hatch, default gates stay sealed; see sec 9 + TASKS.md |

## 8. Open Questions (owner)

1. Can you fall BETWEEN worlds (leave SOI with no gate)? Phase 2
   question, but the answer shapes SOI math now.
2. Should the moon have a build/domain of its own (housing on the
   moon) or stay pristine mystery?
3. Time zones: does the underworld/moon share the main sky clock
   (one epoch everywhere) or drift (local clocks)? I vote one
   clock everywhere -- the clock you wind once a year.

## 9. How the Ladder Works (orientation for new hands)

Everything S16 shipped lives in five files plus one data
folder. Read them in this order and the whole lattice falls out:

1. **`game/data/worlds/*.tres`** -- the DECLARATIONS. Each file is
   one WorldData: id, parent (lattice placement), physics
   (radius/gravity/atmosphere), orbit (radius/period/phase/tilt,
   all closed form), spin, and an OfflineState (ONLINE / OFFLINE /
   DEV_ONLY). Adding a world is adding a .tres. No code.
2. **`core/frame/srv/world_registry.gd`** -- the RELATIONS. Loads
   the declarations; derives every world's seed from the one
   universe constant through its nesting path
   (SeedChain.derive_seed); and answers every spatial question as
   a PURE FUNCTION of the Concord epoch: orbit_position,
   window_favorability, next_transfer_window, parent_sky_direction
   (earthrise), parent_beat_period_days, cosmic_age_s,
   observable_radius_m. Nothing here simulates; everything here
   evaluates.
3. **`core/frame/srv/sign_service.gd`** -- the CLOCK. One epoch:
   sky_epoch_days() = unix/86400. Orbits, calendars, and the
   horizon all hang off it. The sky clock IS the Linux epoch --
   the alignment is the point.
4. **`core/schemas/calibration_tier.gd` + `data/calibration/`** --
   the SCALES. Five tiers declare how each scale of the universe
   advances (fast tiers TICK at hz, slow tiers EVALUATE on a
   cadence) and where each scale's constants live (c and H0 only
   on the universe tier; premature precision is the only evil).
5. **`core/services/scope_service.gd`** -- the SEAM. The player is
   reparented between roots (bout rooms, and now world roots).
   The entry law is enforced HERE: is_enterable() gates every
   world swap; force=true is the DEV_ONLY probe hatch. A player is
   always in exactly one world; world_of(player_id) is the truth.

The gate (`entities/moon_gate.gd`) and the sky
(`entities/parent_sky.gd`) are consumers: the gate reads the law
and animates its three honest states; the sky disc evaluates the
parent's direction every frame on the epoch. Neither stores
anything.

Storage follows the same law: per-world T3 roots live in the
`world:<id>` namespace; content is stored ONCE in FoldedShell
cells (`core/frame/kv/t3.gd`, `folded_shell.gd`) and re-claimed
by every path that needs it; stars exist at NSC-9 addresses
because their derived bytes say so (`core/frame/srv/star_cells.gd`)
-- one sky, many claimants.

Test map: `game/tests/probe_world_lattice.gd` (sections A-H: the
whole lattice law live), `game/tests/probe_calibration.gd` (the
tiers + the epoch + the horizon), co-located frame tests
(`core/frame/srv/test_world_lattice.gd`, `core/frame/kv/*`), and
`scripts/godot_test_runner.sh` DEFAULT_SET wires them all. If you
change the lattice and one probe fails, the probe name tells you
which law you bent.

### The dev flip (S16.6, how it works)

The moon is the dev target: dev work and probes boot there so the
main world stays clean. Mechanism, in order of authority:

1. `world_moon.tres` keeps `offline = 2` (DEV_ONLY). The LATTICE
   still says the moon is not a player world -- the flip does not
   change the declaration, it changes WHO may knock.
2. `entities/moon_gate.gd` grew `dev_hatch` (default false). A
   hatched gate lifts a DEV_ONLY destination to open FOR ITSELF
   (law state 2, prompt "Step through"); OFFLINE worlds (the
   underworld) refuse for everyone -- the hatch cannot open
   doorless worlds. The placed gate in world_playable opts in.
3. At transit the hatched gate CONJURES the destination:
   `scenes/worlds/globe_moon.gd` instantiates, registers
   `world_root_moon`, reads its radius from the declaration
   (1.2 km), hangs earthrise (ParentSky), and stands a return
   Earthward Gate. The visitor adopts lunar law (gravity from
   WorldData, wing stowed by the vacuum gate) and lands on the
   regolith facing the home meridian.
4. The swap itself rides the SAME ScopeService seam with
   force=true (the service's law hatch) -- one seam, no new
   transport. The conjured globe folds back into derivation when
   its last visitor leaves; the next transit re-derives it
   identically (the seed never forgot).

Default gates still prove the sealed law (probe section G): the
mystery shell stands for anyone without the hatch.

### The moon page (S16.5, the chart-and-stone law)

The almanac's moon page (SkyAlmanacUI, between the sky rows and
the Chronicle) fills the blank page with the SAME closed-form math
the Moon Gate reads: `orbit_position` (where the pale stone
stands), `window_favorability` (how aligned the sky is, colored by
regime), `next_transfer_window` at the Gate's threshold (Day N,
how many days out). One derivation, two readers -- the chart and
the stone can never disagree, and the probe asserts it (section J:
same favorability, same next window, same epoch, to 1e-7). The
page reads the moon's own declaration for its lore line, which is
the mystery hook: the page has been blank since the first dawn;
now it tells you when to go fill it. When a player solves the
moon's mystery (future slice), this page is where the answer
lands -- the chart already knows the way.
