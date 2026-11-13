# prd-perf-bridges -- the Julia / Redis / bridge performance round

**Status:** ACTIVE (2026-11-04). Tracker + design for the "where else can
we leverage Julia, Redis, or any bridge" round. Each facet lands with a
MEASURED baseline and a MEASURED result; the numbers live in this file.

**Sibling:** the vant-side report is `dhaupin/vant#379`. The vant Julia
connector and this repo's `srv/julia-bridge/` are two different
architectures solving the same "don't pay JIT per call" problem; the
transferable parts (index-not-scan, stateful eval, serialized evals) are
in that issue.

---

## 0. The decisive law (why most "add Julia" ideas are wrong)

A Julia HTTP sidecar round-trip is **~ms**; an in-process GDScript call is
**~us**. Julia only wins when:

- **(a) the per-call compute is much larger than the round-trip** — i.e.
  a single call does a *batch* (one call, N items), or
- **(b) the work is offline** — pre-solved, no latency budget.

The orchestrator round proved this: its 181x→269x win came from
**replacing a per-entity scan-and-parse with one inverted index** (a
batched, O(1)-lookup shape), NOT from "Julia is faster." Port the
**algorithm**, not the transport.

**Ruled out by the law:** per-frame combat / movement / tick logic, and
anything with a small per-call payload (the round-trip dominates).

## 1. Facets

| # | Facet | Shape | Status |
|---|-------|-------|--------|
| 1 | Terrain heightfield presolve (Julia batch + frame validation) | (b) offline/batch | DONE |
| 2 | Wire the presolve tier to a real consumer | (b) offline | DONE |
| 3 | Prop-layer chunk bucketing offline | (b) offline | TODO |
| 4 | Wire the redis shard bus into dev | transport | TODO |

---

## Facet 1 -- Terrain heightfield presolve

**The law.** `TerrainGen.terrain_height(dir, seed)` is a pure function of
`(unit_dir, seed_bytes)` — exactly the shape Julia crushes. The seam
already exists: `install_terrain_backend(Callable)` (terrain_gen.gd),
with `backend_sundered.gd` composing over `_natural_raw`.

**The win.** The frame derives terrain height per vertex, thousands of
times per mesh build, with every sub-law (noise, land mass, climate,
hydro) re-deriving in GDScript. A Julia batch that evaluates a whole
face's directions in one call pays the round-trip ONCE for the batch.

**The contract (frame stays authoritative).** Julia emits heights; the
GDScript frame VALIDATES them against its own law before install (the
same parity discipline as `test_julia_parity.gd`). A backend install is
opt-in; the default analytic law is untouched.

**Baseline (measure first).** Time `TerrainGen.terrain_height` over a
known set of directions (e.g. a full icosahedral face's worth), GDScript
vs Julia batch. Record both.

## Facet 2 -- presolve tier consumer

`presolve.jl` already evaluates a Concord year × all worlds in parallel
and prints JSON, but **nothing consumes it**. Make it emit a data
artifact the frame validates (a `.json`/`.tres` the frame re-derives a
sample of and asserts equal). Closes the "designed, half-built, zero
consumers" gap.

## Facet 3 -- prop-layer chunk bucketing

`prop_layer._bucket_face_content` / `_chunk_rng` scatter rocks, boulders,
trees, details per face with the SAME seed discipline as terrain. Same
pure-`(seed, face)` shape → same offline-batch treatment.

## Facet 4 -- redis shard bus in dev

`RedisStore` (43 methods) + `RedisShardBus` are fully implemented but the
default backend is memory and nothing sets `SHARD_BUS_BACKEND=redis` /
`REDIS_BRIDGE_URL` in dev, so the redis path runs only under
`test_adapter_http_transport`. Wire it into the dev path so the
cross-process bus is exercised. Pays off for genuine multi-process shard
deployments (mailboxes that survive process boundaries).

---

## Receipts (one per facet, committed alongside)

- `game/tests/test_julia_terrain.gd` — parity + timing (Facet 1)
- `game/tests/test_julia_presolve.gd` — artifact validation (Facet 2)
- `game/tests/test_julia_prop_batch.gd` — parity + timing (Facet 3)
- `game/tests/test_redis_shard_bus.gd` — bus round-trip (Facet 4)

## Measurement ledger (fill as each facet lands)

| Facet | Baseline | Julia | Speedup | Parity |
|-------|----------|-------|---------|--------|
| 1 terrain | 520,895 us (20k raw heights) | 8,807 us | **59.1x** | max err 1.2e-5 m |
| 2 presolve | 1,345 us (3 worlds x 365 days) | 35 us | **38.4x** | seeds exact; orbit/fav <= float32 eps |
| 3 props | _pending_ | _pending_ | _pending_ | _pending_ |
| 4 redis | _pending_ | _pending_ | _pending_ | _pending_ |

### Facet 1 -- measured 2026-11-04

Workload: 20,000 Fibonacci-sphere directions, seed `saltcrown-isle-4`
(`73616c7463726f776e2d69736c652d34`), the raw analytic field
(`TerrainGen._natural_raw` vs `TerrainMath.natural_raw`).

- GDScript raw: **520,895 us** (26.0 us/height)
- Julia raw: **8,807 us** (0.44 us/height) -> **59.1x**
- The clipmap's PUBLIC call (`terrain_height`, raw + hydro carve + road)
  is **1,436,695 us** for the same batch (71.8 us/height) -- the raw law
  is only ~36% of what the clipmap pays per vertex; the carve is the rest.

Parity: the two height VECTORS agree to **max err 1.2e-5 m** across the
anchor set (GDScript Vector3 is float32; Julia is float64), and the
batch sums agree to 0.08 m over 20,000 points. Same discipline as
`test_julia_parity.gd`.

### Facet 2 -- measured 2026-11-04

Workload: the S16.1 lattice (`main`, `moon`, `underworld`) evaluated
forward over a 365-sky-day year -- `orbit_position` +
`window_favorability(moon)` per world per day (1095 evals), the shape
`presolve.jl` exists to crush.

- GDScript (`WorldRegistry`): **1,345 us**
- Julia (`worldmath.jl`): **35 us** -> **38.4x**

Parity: seeds match EXACTLY (byte math); orbit/favorability match to
float32 precision (frame `Vector3` is float32, Julia float64); the two
accumulators agree to 7e-6 over the year. Same discipline as
`test_julia_parity.gd`.

**Consumer (closes the "designed, zero consumers" gap).** The batch
driver is `srv/julia-bridge/world_batch.jl` (the JSON-free sibling of
`presolve.jl`; the pre-solve math is stdlib-only, so the batch runs
even where the JSON/HTTP pkgimages cannot build -- see the note below).
It emits `WORLD`/`EPOCH`/`END` text records, and
`game/tests/test_julia_presolve.gd` re-derives a sample of them against
`WorldRegistry` and asserts equality, exactly as
`test_julia_terrain.gd` does for terrain.

**Environment note (2026-11-04).** This container's Julia install
(1.11.1) segfaults when compiling a pkgimage for ANY registered package
(`using JSON`, `using HTTP`, even `Pkg.add`); stdlib-only modules
(`worldmath.jl`, `terrainmath.jl`) run fine. The `--compiled-modules=no`
flag is the workaround. `world_batch.jl`/`terrain_batch.jl` are
deliberately dependency-free so the offline tier does not depend on the
broken pkgimage path.
