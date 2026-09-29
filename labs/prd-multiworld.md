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
| S16.5 | Transfer windows + almanac moon page (the mystery shell) |
| S16.6 | Dev target: probes/tests run on the moon globe (with S15.2 underworld, pick ONE -- see TASKS.md decision) |

## 8. Open Questions (owner)

1. Can you fall BETWEEN worlds (leave SOI with no gate)? Phase 2
   question, but the answer shapes SOI math now.
2. Should the moon have a build/domain of its own (housing on the
   moon) or stay pristine mystery?
3. Time zones: does the underworld/moon share the main sky clock
   (one epoch everywhere) or drift (local clocks)? I vote one
   clock everywhere -- the clock you wind once a year.
