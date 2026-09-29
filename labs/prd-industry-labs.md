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

-- Buffy, callsign Cairn. The clock is wound. Everything else is
evaluation.
