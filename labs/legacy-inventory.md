# Legacy inventory -- things to migrate, port, or remove

**Status:** ACTIVE (2026-11-04). A running census of legacy / superseded /
dormant systems found during the perf-bridges round. Each entry names the
verdict (KEEP / MIGRATE / PORT / REMOVE) and the reason. This is a
tracking doc, not a log -- update the verdict as work lands.

The owner's ask: *"If you found legacy systems let's note them so we can
migrate, port, remove."*

---

## A. The retired renderer: `globe_terrain_streamer`

**Verdict: MIGRATE (comments only) -- the code is already gone.**

The icosa-face-patch LOD terrain renderer was DELETED (commit `0e27c6ce`,
"world: delete globe_terrain_streamer -- the clipmap is the sole terrain
path"). `GlobeClipmap` (`scenes/worlds/globe_clipmap.gd`) is the sole
terrain renderer now; `globe_world`, `globe_moon`, `globe_underworld`
each mount a clipmap.

**Residue:** 82 comment references to "streamer" across 24 files, all
prose (zero symbol/code references -- verified: `grep` for non-comment
`streamer` returns 0). They read as if the streamer still exists, which
is exactly the kind of drift that misleads the next reader. Worst
offenders:

| File | refs |
|------|------|
| `scenes/worlds/globe_clipmap.gd` | 21 |
| `core/world/prop_layer.gd` | 13 |
| `scenes/worlds/terrain_gen.gd` | 11 |
| `scenes/worlds/terrain_provider.gd` | 7 |
| `entities/starter_village.gd` | 3 |

**Action:** a comments-only sweep replacing "the streamer" -> "the
clipmap" where the sentence means the live renderer, and "the legacy
streamer" -> "the retired streamer" where it refers to history. No code
change. Low priority, no runtime effect.

---

## B. The isoc / icosahedral addressing system

**Verdict: KEEP -- it is the addressing layer, not a renderer.**

The owner noted: *"Iso/streamer rendering planet should be superseded by
clipmask. There is still isoc addressing system active tho."* Confirmed:
the RENDERING is clipmap; the ADDRESSING is still icosahedral, on purpose.
`globe_clipmap.gd` header: *"Addressing stays icosahedral; only the drawn
mesh changes."*

Two distinct addressing stacks, both LIVE:

1. **NSC-9 spatial codes** (`core/frame/math/nsc9.gd`,
   `core/frame/geometry/nsc9_bridge.gd`, `spatial_fragmenter.gd`).
   Live consumers:
   - `EntityService._compute_nsc9_code` -> `_entity_nsc9_codes` (read by
     `get_entity_nsc9_code`).
   - `ZoneManager._compute_nsc9_code` -> `_zone_nsc9_codes` (read at
     `get_zone_nsc9_code`).
   - `WorldService._nsc9_spatial_path` -> `spatial_fragmenter.find_common_ancestor`
     for cross-zone spatial adjacency.
   - `LODManager` chunk keys (`make_address`/`generate_key`).
   - `star_cells.gd`, `folded_shell.gd` (frame primitives, tested).
   **Action:** none. Do NOT remove; it is wired and tested
   (`test_nsc9`, `test_nsc9_bridge`, `test_spatial_fragmenter`,
   `test_star_cells`, `test_folded_shell`).

2. **Icosahedral face addressing** (`core/frame/math/icosahedral_faces.gd`,
   `icosahedral.gd`). Live consumers: the clipmap's face/vertex queries,
   `terrain_gen` (face seeds, species), `prop_layer` (chunk addressing).
   **Action:** none. This is the spatial frame the clipmap samples on.

---

## C. Dormant / stub subsystems

| System | State | Verdict |
|--------|-------|---------|
| `srv/julia-bridge/presolve.jl` | Evaluates a Concord year x all worlds in parallel and prints JSON, but **no consumer** -- only the parity/bridge receipts mention it. | **PORT** (Facet 2): emit a data artifact the frame validates. |
| `core/services/multi_iso_service.gd` | Autoload, `enabled=true`; degrades to empty when no sidecar answers. Its one real consumer is `EntityService.entity_registered`. | **KEEP** -- now live and wired (this round). |
| `RedisShardBus` / `RedisStore` | Fully implemented (43 methods) but the dev path defaults to memory; nothing sets `SHARD_BUS_BACKEND=redis`. | **MIGRATE** (Facet 4): wire into dev so the cross-process bus runs. |

---

## D. Dead artifacts / scratch (untracked or orphaned)

| Artifact | State | Verdict |
|----------|-------|---------|
| `game/dev2/` (9 diag scripts: `budget_diag`, `cap_diag`, `color_diag`, `grade_diag*`, `w5_diag*`) | Untracked, referenced by nothing in `game/`. Ad-hoc grade/diag scratch. | **REMOVE** (or move to `dev_temp/probes/` if any still earn their keep). |
| `game/dev2_grade.gd.uid` | Orphan `.uid` -- no `dev2_grade.gd` source exists. | **REMOVE** (engine-generated for a deleted file). |
| `game/staging_notes_2026_10_14.md` | A stray session note committed at the game root. | **MIGRATE** into `labs/TASKS_ARCHIVE.md` or remove. |

---

## E. Notes for the next agent

- The "streamer" wording is the single biggest source of legacy confusion
  in the terrain path. When you touch `globe_clipmap.gd` / `prop_layer.gd` /
  `terrain_gen.gd`, fix the wording in the lines you touch.
- The `install_terrain_backend(Callable)` seam (`terrain_gen.gd:715`) is
  the plug point for the Julia terrain backend (Facet 1). `backend_sundered.gd`
  is the worked example of composing over `_natural_raw`.
- NSC-9 is NOT dead. The 244 grep hits are real live addressing, not
  residue -- do not "clean it up."
