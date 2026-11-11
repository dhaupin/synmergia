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
| perf_budget: full-detail patch build (hot) | 12.39 s (FAIL vs 10.0 s) | | |
| perf_budget: planet subwalk (8 faces) | 38.9 s | | |
| perf_budget: hot build | 12.39 / 6.54 s | | |
| boot_speed: ready-wall ms | 41 (old boot) | | |
| planet: checks | 43 PASS | | |
| audit: anchor lvl7-cap delta | -0.23 m | | |
| audit: anchor lvl6-web delta | -0.72 m | | |
| walk_gap: worst abs gap | 0.52 m | | |
| determinism | byte-stable | | |

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
- SLICE 3 -- sector_key seed-hex memo.
