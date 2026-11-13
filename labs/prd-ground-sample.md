# Scope: The `GroundSample` refactor (fusing the ground law)

> **Status:** SCOPED (2026-11-04). Stages 0-2 SHIPPED. This is the design +
> plan for the structural fix behind S1-S4 in `prd-clipmap.md` section 8.
> Related: `prd-clipmap.md` (the renderer + the slow-systems table),
> `prd-terrain.md` (the ground law), `prd-world.md` (the planet).

## 1. The problem, measured

Every public "ground at a direction" entry point in `terrain_gen.gd`
re-runs its neighbours. A single clipmap vertex asks for a height and a
skin; each of those internally re-reads the other, plus the water stack,
plus the climate stack. The caches absorb most of the repeats (a
measured **90.6% hit rate**), but a cache HIT still costs a key build +
lock + LRU probe (~2 us), and a MISS pays the full cold cost.

**Measured this round (fresh sector = cold miss):**

| law | cold | note |
|---|---|---|
| `terrain_height` | 245 us | the base field |
| `splat_skin` | 674 us | reads skin_classes + temperature + water surface + height + road |
| `vertex_color` | 720 us | the colour law |
| `climate_biome_id` | 318 us | reads height + water surface |
| `water_table_raw` | 167 us | two noise octaves + moisture + perch |
| `river_channel` | 111 us | the capsule sweep |

**Measured redundancy (instrumented `SectorCache`, partial clipmap build):**
675,904 cache lookups at a 90.6% hit rate. The overwhelming majority of
those lookups are the SAME quantized direction re-entering a different
sub-law (or the same sub-law) within one vertex derive. The dedup is
real but paid for one key-build at a time.

**The shape:** S1-S4 are one problem. `terrain_height`,
`climate_biome_id`, `hydro_water_surface`, `water_table_raw`,
`splat_skin`, `skin_classes`, `vertex_color` all derive from the same
handful of pure primitives at one direction:

```
_land_mass (noise)  ->  _natural_raw / _terrain_height_base  ->  carve (lake/river/road)  ->  terrain_height
water_table_raw     ->  hydro_water_surface (gates + carve read)
climate_temperature (reads height)
climate_moisture    (reads land + river_channel)
climate_biome_at    (reads height + surface + temp + moisture)
climate_biome_weights -> skin_classes -> splat_skin (reads temp, surface, height, road, crag)
_crag_noise
river_channel / river specs (reads base height only)
road_state_at (reads pre-road height)
```

## 2. The design: one `GroundSample`, one memo, field reads

Introduce a single value object -- `GroundSample` -- holding every
per-direction quantity the renderer, the walk law, and the biome law
need. Compute it ONCE per quantized direction and memoize the WHOLE
struct. Every existing public function becomes a thin field read:

```gdscript
class GroundSample:
    var height: float          # terrain_height (carved)
    var height_base: float     # _terrain_height_base
    var water_table: float     # water_table_raw
    var water_surface: float   # hydro_water_surface (-1e9 = none)
    var temperature: float
    var moisture: float
    var biome_id: int
    var biome_weights: Dictionary   # or a packed form
    var skin: Color            # skin_classes
    var crag: Vector4          # _crag_noise
    var river_channel: float
    var road_state: Vector3
    var sea: float
```

`ground_sample(dir, world_seed) -> GroundSample` builds all of them in
ONE pass, topologically ordered (primitives first, dependents read the
locals -- never re-call the public wrappers). The per-field caches
(`_height_cache`, `_temperature_cache`, `_water_surface_cache`,
`_skin_cache`, `_blend_cache`, `_crag_cache`, `_water_table_cache`,
`_carved_cache`, `_channel_cache`) collapse into ONE
`_ground_cache` keyed by the same sector law.

**Compatibility (the load-bearing constraint).** ~23 files call
`TerrainGen.terrain_height`, ~18 call `climate_biome_id`, plus
`splat_skin`/`vertex_color`/`hydro_water_surface`. The refactor MUST be
bit-identical: same numbers out, so every probe pin (ground_law_audit,
terrain_planet, determinism, starter_village, walk_mesh_gap) stays
green. The public functions stay; they just read the fused sample:

```gdscript
static func terrain_height(dir, seed) -> float:
    return ground_sample(dir, seed).height
```

The frame rule holds: `GroundSample` is an inner class (the
`RiverSpec`/`RoadSpec` pattern already in this file), no autoload, no
`class_name`.

## 3. Why this is the right shape (not a local patch)

- **One derivation, one memo.** A vertex costs ONE `ground_sample`
  call (one key build, one lock, one LRU probe) instead of the current
  ~8-12 lookups across height/color/surface/biome/temp/table. The
  measured 675,904 lookups should fall by roughly the fan-out factor.
- **Cold cost pays once.** A cold vertex currently derives height,
  then re-derives the water stack to get the surface, then re-derives
  climate for the biome, then re-derives all of it again for the skin.
  The fused pass derives each primitive exactly once.
- **The cache-invalidation law simplifies.** Today the backend
  install/uninstall clears SEVEN caches (lines 684-705). One fused
  cache = one `clear()`.
- **It makes S1-S4, S5 fall out for free.** S5 (clipmap keys height and
  color separately) disappears: the clipmap asks for ONE sample.
- **No new public surface.** Callers are unchanged; only the internals
  fuse. That is what keeps the blast radius small.

## 4. The plan (staged, each stage bit-identical + gated)

Each stage must pass `probe_ground_law_audit`, `probe_terrain_planet`,
`test_terrain_determinism`, `probe_starter_village`, `probe_clipmap`
before the next starts. Numbers are re-measured at each stage.

1. **Stage 0 -- the bit-identical baseline harness.** A new probe
   `probe_ground_sample.gd` that, for N random directions, records the
   CURRENT public-function outputs (height, surface, biome id, skin,
   temp, table, crag) and asserts the fused `ground_sample` matches
   them EXACTLY. This is the refactor's safety net; it lands first and
   stays green through every stage.
2. **Stage 1 -- introduce `GroundSample` + `ground_sample()`** WITHOUT
   rewiring callers. It computes the fused struct (calling the existing
   sub-laws internally, so trivially bit-identical), memoizes it, and
   is exercised ONLY by the Stage-0 probe. No production path changes.
3. **Stage 2 -- rewire the internals.** `terrain_height`,
   `climate_biome_id`, `hydro_water_surface`, `splat_skin`,
   `skin_classes`, `water_table_raw`, `vertex_color`,
   `climate_temperature` become field reads off `ground_sample`. The
   sub-law bodies move INTO the fused builder (private), preserving
   exact arithmetic order so the floats are bit-identical.
4. **Stage 3 -- collapse the caches.** Delete the per-field caches;
   route everything through `_ground_cache`. One `clear()` on
   install/uninstall. Re-run the invalidate-cache probes.
5. **Stage 4 -- rewire the renderers.** The clipmap drops its private
   `_memo_h`/`_memo_col` (it asks `ground_sample` once per vertex and
   reads `.height` + `.skin`); the streamer likewise. Re-measure the
   clipmap cold build + the lookup count; expect a large drop.
6. **Stage 5 -- the S4 bounding early-out** (independent, small):
   `river_channel` skips specs whose nearest endpoint is farther than
   the river's angular radius before the segment loop.

Stages 1-3 are the core; 4-5 are the payoff. If any stage can't hold
bit-identical, STOP and reassess -- the determinism pins are the law.

## 5. Risks + mitigations

| risk | mitigation |
|---|---|
| Float drift from reordered arithmetic | The Stage-0 probe pins EXACT equality (not epsilon). Preserve the exact call order + operation order when moving bodies into the fused builder. |
| A sub-law has a mode flag (`terrain_height_carved` takes `""`/`_raw`/`_noroad`) | The fused sample is the DEFAULT (`""`) path only; the special modes stay as separate functions (they are the pre-road/raw readers the river/road builders need -- a documented cycle-break). |
| Thread safety | `ground_sample` uses the same mutex-guarded `SectorCache`; the fused entry is written atomically like today. |
| Cache invalidation on backend install | One fused `clear()` replaces seven -- verify with `probe_sundered_backend` (the backend install path). |
| Blast radius (23 callers) | The public signatures do NOT change; only bodies. The Stage-0 probe + the determinism battery cover the surface. |
| Memory | One struct per sector instead of ~8 scalars across 8 caches -- net LOWER (the struct is a superset, so per-sector memory rises, but the number of cached sectors is the same and the per-cache LRU overheads collapse). Measure with `SectorCache.size()` before/after. |

## 6. Acceptance

- `probe_ground_sample.gd` exits 0 with EXACT equality across the
  battery (bit-identical refactor).
- `probe_ground_law_audit`, `probe_terrain_planet`,
  `test_terrain_determinism`, `probe_starter_village`, `probe_clipmap`,
  `probe_sundered_backend`, `probe_world_shape_ground` all still PASS.
- The instrumented lookup count for the same clipmap build drops
  substantially (report before/after); the clipmap cold build is
  re-measured and does not regress.
- Naming lint + autoload audit green.

## 6a. Measured result (Stages 0-2, 2026-11-04)

Cold cost is unchanged (the fusion does not reduce cold derivation --
it is the same laws once). The win is the WARM path, which is 90.4% of
all ground-law calls in a clipmap build:

| call | OLD warm | NEW warm | speedup |
|---|---|---|---|
| `splat_skin` | 30.6 us | 11.3 us | 2.7x |
| `vertex_color` | 76.1 us | 14.4 us | 5.3x |
| `climate_biome_weights` | 81.8 us | 5.9 us | 13.9x |

(The OLD numbers are the pre-refactor `terrain_gen` at `9e1f2f26`,
measured side-by-side; NEW is the fused path.) The win comes from one
`ground_sample` memo probe per call replacing the old fan-out of ~6-12
individual memo probes (each a key build + mutex + LRU probe).

**Honest caveat:** the raw `SectorCache.get_value` COUNT barely moved
(675,904 -> 666,579) because most of those lookups are the COLD
first-visit derivation of the shared sub-primitives, not warm
re-derives. The win is per-warm-call latency, not lookup count. A
further reduction would need the Stage-3 cache collapse (which removes
the redundant parallel caches, not the cold derivations).

## 6b. Stages

- **Stage 0 SHIPPED** -- `probe_ground_sample.gd`, the bit-identical
  safety net (EXACT equality across 246 dirs).
- **Stage 1 SHIPPED** -- `GroundSample` + `_build_ground_sample()` +
  `ground_sample()`, memoized in `_ground_cache`.
- **Stage 2 SHIPPED** -- the derived laws (`climate_biome_id`,
  `climate_biome_weights`, `skin_classes`, `vertex_color`,
  `splat_skin`) read the fused sample; the pure helpers
  (`_biome_weights_from`, `_skin_from`) let the builder use them without
  recursion. All bit-identical (probe + every gate green).
- **Stage 3 SHIPPED (partial, honest)** -- the only cache left holding a
  redundant derived value was `_skin_cache`, orphaned by Stage 2's rewire
  (`skin_classes` now reads `ground_sample().skin`), with ZERO readers
  left -- removed. The remaining per-field memos are NOT redundant: they
  are the primitives' own cold-derivation layer, and each is still read
  directly by a non-fused caller, so folding them into `_ground_cache`
  would either recurse (the fused builder calls them) or force those
  callers through the fused sample they do not need. Full inventory:
  `_height_cache` (setter + external readers), `_crag_cache` (feeds
  `_crag_noise`), `_temperature_cache` / `_water_table_cache` /
  `_water_surface_cache` / `_blend_cache` / `_channel_cache` / `_carved_cache`
  (primitive setter+getter pairs), `_ground_cache` (the fused sample).
  Collapsing further is a behavior-preserving but non-trivial relayout
  with no measurable win; deferred, documented here.
- **Stage 4 SHIPPED** -- the clipmap dropped its private `_memo_h` /
  `_memo_col` (and the now-dead `SectorCache` preload + `MEMO_MAX`);
  `_memo_height` reads `TerrainGen.ground_sample(dir).height` and
  `_memo_color` reads `TerrainGen.splat_skin_from(gs, seed, gs.height,
  0.2)`. One `ground_sample` per vertex serves BOTH the height and the
  colour. The public `splat_skin` is now a thin wrapper over the pure
  `splat_skin_from(sample, ...)`. Measured: clipmap-build lookups
  666,579 -> 651,390 and hit rate 90.4% -> 91.7% (the fused cache
  replaces two parallel clipmap caches).
- **Stage 5 SHIPPED** -- the S4 `river_channel` bounding early-out.
  `RiverSpec` grew `bound_ang` (the widest per-vertex radius over the
  path -- the estuary mouth -- padded by the slerp midpoint bulge + a
  float hair), computed once at spec build. Both river scans
  (`river_channel`, `river_flow_at`) reject a whole spec with
  `_river_spec_far(d, spec)` (farther than `bound_ang` from EVERY path
  point). The reject is EXACT: any hit implies a path point within
  `bound_ang`. Measured: `river_channel` COLD 146.1 -> 38.9 us (3.8x);
  the probe grew a "reject never covers a hit" leg (10 checks).

## 7. Open questions (for the owner)

1. **How far to fuse?** Full (all eight fields) vs a smaller
   "render sample" (height + water surface + biome + skin). Full is
   cleaner but touches the walk law; smaller keeps the walk law
   separate. Recommendation: full, since the walk law reads the same
   primitives anyway.
2. **`Dictionary` vs packed weights.** `biome_weights`/`skin` are
   `Dictionary`/`Color` today. Keep them (compatible) or pack into a
   fixed array? Recommendation: keep as-is in Stage 1-3 (bit-identical
   is the priority), consider packing later.
3. **When.** This is a `terrain_gen.gd` refactor -- it should land on a
   quiet tree, not alongside a content lane. Recommendation: its own
   round, as the parent lane (no subagent), since it touches the shared
   law.
