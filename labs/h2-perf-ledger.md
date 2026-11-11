# Lane H2 -- terrain math-first performance ledger

Base commit: `5865031a` (lane-H2 round-6 briefs). Worktree repaired after an
infra 503 wiped it mid-run; all numbers below are re-measured on a clean tree.

## The functional goal (unchanged)

The streamed terrain mesh near spawn must match the analytic walk law
(`probe_walk_mesh_gap` PASS), the plaza must resolve within a tile, and the
spawn face must build at the demanded level. Guardrails: `probe_terrain_planet`
(43 checks), `probe_ground_law_audit` (draw-vs-law deltas within the 6 m walk
bound), `test_terrain_determinism` (byte-stable), `probe_world_boot_speed`.

## Metric table

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| perf_budget: full-detail patch build (hot) | 12.39 s (FAIL vs 10.0 s) | 6.6 s (PASS; 6.59-6.69 across runs) | -5.8 s (-47%) |
| perf_budget: planet subwalk (8 faces) | 38.9 s | 20.9 s | -18.0 s (-46%) |
| perf_budget: hot build | 12.39 / 6.54 s | 6.6 / 6.54 s | -5.8 s |
| boot_speed: ready-wall ms | 41 (old boot) | 41 | unchanged |
| planet: checks | 43 PASS | 43 PASS | unchanged |
| audit: anchor lvl7-cap delta | -0.23 m | -0.23 m | unchanged |
| audit: anchor lvl6-web delta | -0.72 m | -0.72 m | unchanged |
| walk_gap: worst abs gap | 0.52 m | 0.52 m | unchanged |
| determinism | byte-stable | byte-stable | unchanged |

Slice-by-slice (each committed separately; numbers are the perf_budget hot
patch build):

| Slice | Change | hot build | note |
|-------|--------|-----------|------|
| 0 | baseline | 12.39 s | FAIL vs 10.0 s |
| 1 | seed-constant memo (`_seed_salt`, `sea_level`) | 11.46 s | -7.5% |
| 2 | carved-height memo (`terrain_height_carved` default mode) | 7.66 s | -38% vs base, now PASS |
| 3 | sector_key packed-int key (was str(Vector3i)) | 7.19 s | -42% vs base |
| 4 | derive-local splat_skin memo (per unique corner) | 6.59 s | -47% vs base |

## Hot-path profile (counted, one level-6 patch build, before any fix)

Instrumented counters (temporary, reverted): a single level-6 face-17 build
called these pure laws:

| function | calls / build | pure in | note |
|----------|---------------|---------|------|
| `_seed_salt` | ~958,000 | seed + tag | no direction dependence; recomputed every call |
| `sea_level` | ~353,000 | seed | wraps `_seed_salt(seed,"sea")` |
| `terrain_height_carved` | ~207,000 | dir sector + seed | full carved law; only `_terrain_height_base` was memoized |
| `_hydro_gates` | ~213,000 | dir sector + seed | 2 noise octaves each; not memoized |
| `climate_moisture_field` | ~39,000 | dir sector + seed | not memoized |
| `_land_mass` | ~101,000 | dir sector + seed | not memoized |

Per-call micro-bench (before): `_seed_salt` 1.157 us, `sea_level` 1.154 us,
`terrain_height` warm 26.45 us / cold 95.83 us, `sector_key` 0.859 us.

## Slices

(each slice: change -> re-run probes -> fill After -> commit)

- SLICE 1 -- seed-constant memo (`_seed_salt`, `sea_level`).
- SLICE 2 -- carved-height memo (`terrain_height_carved` full mode).
- SLICE 3 -- sector_key packed-int key (was str(Vector3i); 2.1x cheaper key build).
- SLICE 4 -- derive-local `splat_skin` memo (per unique corner).

## Rejected slices (measured, then reverted -- recorded so they are not re-tried blind)

The build is now dominated by the SKIRT phase (~5.1 s of a ~6.9 s cold build;
the main tint/fusion derive is ~2.5 s, and a warm re-derive is only ~0.31 s --
the remaining cost is cold cache population, not repeated law math).

- SLICE 5 (REJECTED) -- `_land_mass` sector memo. `_land_mass` was still the
  biggest uncached law (~75k calls/build, 9.6 us each ~= 0.72 s), and all five
  call sites pass the same `"terrain"` salt, so it memoizes cleanly
  (value-equality probe `LAND-EQ n=2000 bad=0`). But the measured hot build
  did NOT move (6.59 -> 6.65/6.69 s, within run-to-run noise): the wall cost
  is the FIRST cold derive, and `_land_mass`'s ~0.72 s of *law time* is
  overlapped with the worker thread / dwarfed by the skirt. New cache + a
  salt-bytes helper for zero wall gain = not the smallest change, so reverted.

- SLICE 6 (REJECTED) -- dedup the corner-fusion neighbor sweep to unique
  corners. The fused sweep's own comment claims a raw-corner sweep is needed
  ("a corner whose own height was populated as an earlier corner's neighbor
  STILL owns its three slope-neighbors ... skipping the sweep for aliased
  corners leaves holes the build dies on"). Guarding the sweep under
  `dir_slope.has(kc)` is perf-neutral in measurement (fusion phase unchanged
  within noise) AND reintroduces exactly the aliasing hazard the comment
  warns about. Not worth the risk for no measured gain, so reverted.

Conclusion for the next lane: further law-math memoization has hit diminishing
returns. The remaining budget headroom (6.6 s vs the 10.0 s cap) is comfortable;
the next lever, if one is wanted, is the SKIRT phase (5.1 s) -- specifically
the per-border-edge taper probes and the `vertex_color` top-color read
(~30-77 us of the border loop), which are per-border-edge rather than
per-unique-corner. That work needs its own correctness proof for the taper
depth, so it is out of scope for this round.
