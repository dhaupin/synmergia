# prd-industry-labs.md -- The Industry Call

**Status:** Position paper (owner request: "let's call the bluff on the
game industry with our unique theorems of reality state/seeds, nested
invocations, pre-solves races, drift, coalesce, cadence, valves").
**Every theorem cites shipped code.** The extensions name the seam
they land on. Nothing here is vapor.

Owner thesis (the reactor's law): pack as much as we can into math
payloads, on the smallest infra possible, with the most impact on
player count and world state. Nothing stored that players did not
choose.

---

## 1. The bluff

Industry labs run "physics engines" and mean: a rigid-body solver,
an actor list, and a database of everything that ever happened. The
state grows with history; the sim cost grows with actor count; the
world stops where the mesh ends. Add a solar system and the actor
count kills you. Add a galaxy and the database kills you. Add
fast-forward and *time itself* kills you -- because none of it is a
function of anything.

Synmergia's frame makes a different claim:

> **A world is a function. Time is an argument.**

The universe seed (one hex constant, `world_registry.UNIVERSE_SEED_HEX`)
plus a nesting path derives every world. The Concord epoch
(`SignService.sky_epoch_days()`) is the single clock every sky-driven
system reads. Orbital position is `orbit_position(epoch)` -- a pure
function you can evaluate at year 500 without simulating years 1-499.
The S16 arc proved the pattern at planet scale; this document names
the theorems and extends them to solar system, galaxy, and universe
level -- the slow ticks of a civilization-scale fast-forward.

---

## 2. The theorems (shipped)

### T1. One seed derives all worlds (nothing stored that players did not choose)

Industry: per-zone scene files, per-server databases, content loaded
from disk. Ours: `SeedChain.derive_seed([universe, parent?], seed_path)`
-- domain-separated nesting ("world:main", "world:main/subworld:x").
Two fresh registries derive identical bytes. *Proof: probe_world_lattice
sections A-B (determinism, domain separation, nesting fold).*

### T2. One clock, closed-form motion (time travel is free)

Industry: tick the simulation, store the deltas, pray. Ours: orbits,
windows, and earthrise are pure functions of the Concord epoch
(`orbit_position`, `window_favorability`, `parent_sky_direction`,
`parent_beat_period_days`). Evaluating the sky at epoch E costs the
same whether E is tomorrow or in 800 years. *Proof: probe sections
D-F-H (purity, windows, the 24-day synodic beat theorem).*

### T3. Geometric assimilation and addressing (the owner's idea, already half-real)

Industry: octrees over float coordinates; a moved object changes its
address and invalidates its neighborhood. Ours: **NSC-9**
(`frame/math/nsc9.gd`) -- a bit-packed address (prefix 4 / facility
10 / axis 10 / sequence 24 bits) over the icosahedral subdivision
(`icosahedral.gd`, golden-ratio face geometry), with deterministic
subdivision via `geometry/spatial_fragmenter.gd` (MAX_DEPTH guard
against fragment explosion) and `nsc9_bridge.gd` wiring addresses into
the T3 state tree. **The address IS the identity**: assimilating a
thing into the world means assigning its cell, not registering it in
an actor list. Adjacency is arithmetic (sibling cells share a parent
prefix); locality is bit-truncation, not a spatial query.
*Shipped: tests co-located (test_fragmenter, test_nsc9_bridge,
icosahedral_faces).*

### T4. The state tree is content-hashed (world state = a Merkle fact)

Industry: snapshots that are neither verifiable nor resumable. Ours:
the T3 state tree (`frame/kv/`) hashes content, not position -- two
shards that computed the same world state hash the same. Rejoin,
recovery, and anti-cheat all reduce to hash comparison. *Shipped:
state_tree + LRU under frame/kv; snapshot_store under frame/db.*

### T5. Coalesced persistence (cadence is a valve)

Industry: write-through everything, or lose everything. Ours:
`ShardParameters` persists immediate-or-5-minutes-coalesced (D033) --
the server's memory of the world is a *cadence decision*, and the
horcrux is the cold valve (airgap-proven: a stone hand-carried between
machines restores a full agent brain; `scripts/cairn_recover.sh`).
Drift between the live state and the last coalesce is bounded by the
cadence, never by disaster scope. *Shipped: ShardParameters (D033),
OpenSeedRegistry (D032), horcrux kit.*

### T6. Laws, not triggers (the entry law pattern)

Industry: scripted door openers, whitelists, per-feature flags. Ours:
`WorldData.is_enterable()` gates every swap inside ScopeService; the
Moon Gate refuses offline worlds *as if they do not exist*; force=
is a dev hatch, not a hack. A law is one function the whole stack
reads, so the underworld "has no door" without a single line of
door-specific code. *Proof: probe sections G (law refuses swaps with
no gate present).*

### T7. Nested invocations (the frame is the function call)

The frame primitives are pure functions composed like calls:
`world_seed(id)` invokes `SeedChain` with a path; `window_favorability`
invokes `_orbit_angle` twice; `parent_sky_direction` invokes orbit and
spin angles. Composition without state is why a probe can drive them
inline with prints and catch a swapped-argument bug in seconds (the
S16.1 lesson). This is the "nested invocations" theorem: **reality
state is callable, and calling it has no side effects.**

---

## 3. The extension ladder (designed, in seam order)

### X1. Solar system: the heliocentric clock (lands on T2)

Add worlds whose parent is the main world's *sun*: a `HELIOCENTRIC`
kind in WorldData with parent_world = "" but a barycenter anchor, or
cleaner: `world_sun` as a pseudo-world (radius, no surface) and
planets orbiting IT. Zero new math: `orbit_position` already takes
any (radius, period, phase, inclination); nesting just grows one
level ("world:sun/planet:x"). Transfer windows between planets are
already the two-orbiting-bodies branch of `window_favorability`.
Seasons on world_main are the planet's `parent_sky_direction` -- the
sun's disc hangs where the theorem says. Slow tick: the sky is
evaluated per frame on the Concord epoch; nothing simulates.

### X2. Galaxy: address-space stars (lands on T3)

A galaxy is not 10^11 simulated stars; it is an ADDRESS SPACE. NSC-9
facility bits already give 1024 facilities; a galaxy scale needs one
more prefix level (galaxy/sector/facility). Star presence is derived:
`derive_seed(universe, "star:<nsc9_address>")` decides existence,
spectral class, planet count -- a star exists because its address
says so, exactly the way a world exists because its path says so.
Telescopes (the almanac far-gaze button's big brother) are address
lookups + orbit math, not raycasts. The night sky of every world
becomes a pure function of (address, epoch).

### X3. Universe: the slow ticks (lands on T2 + T5)

Civilization-scale fast-forward is *evaluation at large epoch*, plus
a small ledger of player-chosen state. The rule from the reactor's
law: what players did not choose is never stored -- so fast-forwarding
800 years means evaluating closed forms at epoch_now + 800*365.25
(cheap) and replaying the LEDGER of chosen events (small) through
deterministic folds: cities founded, gates opened, acts recorded.
The Concord Chronicle already IS this ledger at day scale (one
chapter per solved day); the universe tick is the same pattern at
century scale. Drift never accumulates because there is no
integration -- only evaluation plus fold.

### X4. Valves (lands on T5)

Named for the owner's list: a valve is where continuous derivation
meets discrete persistence. We have three: the 5-minute coalesce
(warm), the horcrux (cold), and the dawn re-seal (semantic -- state
that expires by law rather than by GC). The ladder adds the epoch
valve: state that keys on sky day (daily quests, sign codes, door
unlocks) survives reboots because it is derived from the epoch, not
stored against it.

---

## 4. What we will not build

- An N-body integrator. Gravity on globes is a declared law
  (WorldData.gravity_force); orbits are circular closed forms. The
  moon does not perturb the comet; the almanac's honesty beats a
  physics ego.
- A streamed universe mesh. Space between worlds is the address
  space, not geometry (X2). You do not fall between worlds; you
  transfer (PRD sec 8 keeps the phase-2 question open on purpose).
- A tick for things that are functions. If evaluating beats
  simulating, we evaluate.

---

## 5. Falsifiable claims (the bluff, testable)

| # | Claim | How it breaks |
|---|-------|---------------|
| C1 | World seeds derive identically on any machine | probe sections A-B |
| C2 | Sky state at epoch E costs O(1) regardless of E | evaluate orbit at year 800 vs tomorrow (H) |
| C3 | A horcrux restores a full brain on a cold node | cairn_recover.sh (done) |
| C4 | Refused worlds are unaddressable, not locked | probe G (law refuses with no gate) |
| C5 | Adjacent NSC-9 cells share prefixes | test_nsc9_bridge |
| C6 | Coalesced persistence bounds loss by cadence | COALESCE_WINDOW_MS + per-shard queues in shard_parameters.gd |
| C7 | T3 shards agree by hash, not by sync | frame/kv state_tree tests |

---

## 6. Adjacent lanes (kept in sight, not blocking)

- Julia lanes (`frame/srv/orchestrator.jl`, `server.jl`,
  `Project.toml`): the pre-solve/race theorem work (owner: "pre-solves
  races") belongs here when it graduates from paper -- deterministic
  evaluation is embarrassingly parallel, and Julia is the right
  substrate for the Monte Carlo of "what did the ledger fold to."
- prd-whitepaper section 9 (the paper PRD) absorbs this document's
  claims table when it is written.

## 7. On precision (the Knuth reconciliation)

Owner riff: "I'm getting Knuth heavy -- why interrupt our peaceful
origin for seemingly useless precision? ... A physics frame is based
on precision." Both halves are true, and the frame already resolves
them:

Knuth's evil (1974, *Structured Programming with go to Statements*)
is **premature** work -- cost paid before need is known. Nothing in
this frame is premature, because the CalibrationTier substrate IS
the schedule of when each scale's precision becomes load-bearing,
declared in data and audited by probe:

- **Spent where it compounds.** One epoch alignment (unix/86400)
  and every system inherits the law; one closed-form orbit and the
  sky at year 800 costs what tomorrow costs. Precision at the spine
  is amortized across the whole universe.
- **Withheld where it does not.** Circular orbits (perturbation is
  invisible to play), flat-horizon visibility (a heuristic, named as
  one), no N-body (the not-build list). The moon does not owe us
  libration.
- **Budgeted, not guaranteed.** A drift budget in data beats a
  promise in code: probe_calibration audits the budgets, and the
  universe can be recalibrated without recompiling it.

The origin stays peaceful precisely because the precision is
allocated once, at the spine, by data. That allocation is the
architecture; everything else is evaluation.

## 8. The globe typewriter (owner insight, 2026-09-29 -- the X2 mechanism sketch)

Owner, on folding surface area and intersecting icosahedrons: "like
those old globe typewriters spinning and ... dimensions in code. We
don't need to do that, just wanted to show you."

Recorded because it is the X2 mechanism, already half-shipped:

- A regular icosahedron IS the sphere folded flat -- twenty
  triangles, the Dymaxion net. Unfold the world, work on paper,
  fold it back: that is why the frame addresses space with
  icosahedral cells instead of float octrees.
- NSC-9 is the typewriter carriage: prefix/facility/axis/sequence
  bit-packed (nsc9.gd). The globe spins (subdivide/step); the
  carriage reports a cell. "Dimensions in code" -- axis and
  sequence bits ARE the dimensions, folded into one integer.
- Assimilation = assigning a cell; intersection of two folded
  globes = comparing prefixes; adjacency = bit truncation. Surface
  area becomes cell counts; intersection becomes arithmetic.
- The galaxy tier (X2) consumes this literally: stars are typed at
  NSC-9 facility addresses on the folded sphere; a telescope is a
  carriage move, not a raycast; H0 (now declared in the universe
  tier) is the slow stretch of the paper under the type.

Not built today -- shown, understood, and reserved: the schematic
lives here so X2 lands as mechanism, not metaphor.

## 9. The Rest and the Horizon (owner calibration, 2026-09-29)

Owner: "You can get a calibration state and origin from 3 of the
intersecting [isos] -- a center of the universe, per se, would be the
state of rest between 3 new isos, balanced gravity and orbit. Play
God ... we have to have an outer limit in synmergia (like irl). If
mine doesn't work, what's your idea for balance of the universe?"

Both landed the same day, and they answer different halves of the
question:

**The Rest (declared -- the owner's).** Three intersecting
icosahedral facilities in balanced gravity/orbit define the
reference frame: `rest_frame = "nsc9:trilateral:0+1+2"` on the
universe tier. IRL has no center -- every observer sits at the
center of their own light cone, and astronomy anchors the sky to
conventions (quasars, the CMB dipole, the solar barycenter), never
a place. Synmergia is allowed better: the center is WOUND, not
found. Facilities 0, 1, 2 are the trilateral seat; addressing and
lore hang from it.

**The Horizon (derived -- my answer to "like irl").** IRL's outer
limit is not a wall; it is the LIGHT CONE: the edge exists because
light has only had time to travel so far. With c and the origin
declared, ours is one subtraction:

    cosmic_age_s        = epoch*86400 - origin_unix      (clamped at 0)
    observable_radius_m = cosmic_age_s * c                (grows at exactly c)

The origin is not invented: it is the FIRST COMMIT of the repo
(unix 1789861412). The universe began when its code did; git is the
fossil record. At this writing the universe is about ten days old
and its horizon grows a light-day per day, forever.

**The balance of the universe, stated as law:** centers are
CHOSEN, limits are DISCOVERED. A declared Rest without a derived
Horizon is a prison (walls someone built); a derived Horizon
without a declared Rest is a drift (no anchor, no address).
Synmergia takes both: the Rest anchors the galaxy tier's frame
(parallax, telescope pointing, the X2 carriage home), the Horizon
bounds everything observable -- fast-forward cannot evaluate past
the light cone, telescopes see only the lookback they have earned,
and the edge is never a place you can reach, only a time you can
wait out.

Consumers reserved, not built: horizon-bounded fast-forward (X3),
lookback telescopes (X2), and the Rest as the parallax anchor for
the trilateral facilities.

## 10. The Folded Shell (owner mechanism, 2026-09-29 -- built)

Owner: "I feel like I see the intersection vectors as infinite, even
between 2 spaces. Increasing surface area increases store/state.
Let's crush on a literal geometric shape that solves storage,
compute, ram, and frankly stress. Someone's gonna do it -- how about
us."

Built the same day as a frame primitive (`frame/kv/folded_shell.gd`,
21 co-located checks). The two owner intuitions are real physics:

1. **Surface storage (the holographic law).** Max information in a
   region scales with boundary AREA, not volume (Bekenstein bound;
   black holes store on their horizons; brains fold cortex inside a
   fixed skull). The shell stores on a folded 2-manifold: NSC-9
   cells on icosahedral surface; each fold FOURFOLDS capacity in
   the same footprint (complete 4-ary heap: children(p) = 4p+1..4p+4,
   4^depth per facet, MAX_FOLD_DEPTH = 11 -- 4.2M cells/facet inside
   the 24-bit sequence). Folding is the storage multiplier; the
   shape refuses to overrun.
2. **The intersection rebate (the dedup law).** Two spaces that
   share state pay ONCE: the shared fact lives in one content-hash
   cell, claimed by both (T3 applied to geometry). Removal is
   intersection-aware -- a leaving space never erases claimed
   state. Two spaces, five facts, one store: the rebate measured.

Stress is bounded, not feared: a finite fold budget, an LRU hot
working set with evictions COUNTED, no integration anywhere.
Consumers reserved: T3 dedup at scale, X2 star cells, ram-bounded
shard state. The game will be one of the best tests -- as the owner
said, fist bump.

-- Buffy, callsign Cairn. The clock is wound. Everything else is
evaluation.
