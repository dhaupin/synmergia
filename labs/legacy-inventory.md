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

**Residue:** 79 comment references to "streamer" in live `game/*.gd`
(2026-11-14 recount), all prose -- zero symbol/code references.
The legal/script residue is gone; only the wording sweep (B4 in
`clipmap-fold-survey.md`) remains. They read as if the streamer still exists, which
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
| `srv/julia-bridge/presolve.jl` | Parity oracle for `test_julia_parity` (frame math). Its prop sibling `prop_presolve.jl` emits `data/presolve/props_main.txt`, consumed at boot by `PresolveProps` -> `TerrainGen.install_presolve`. | **KEEP** (oracle); prop presolve **DONE** (2026-11-14). |
| `core/services/multi_iso_service.gd` | Autoload, `enabled=true`; degrades to empty when no sidecar answers. Its one real consumer is `EntityService.entity_registered`. | **KEEP** -- now live and wired (this round). |
| `RedisShardBus` / `RedisStore` | Fully implemented (43 methods) but the dev path defaults to memory; nothing sets `SHARD_BUS_BACKEND=redis`. | **MIGRATE** (Facet 4): wire into dev so the cross-process bus runs. |

---

## D. Dead artifacts / scratch (untracked or orphaned)

| Artifact | State | Verdict |
|----------|-------|---------|
| `game/dev2/` (9 diag scripts) | Referenced by nothing; ad-hoc grade/diag scratch. | **REMOVED 2026-11-14** (`git rm`; history keeps them). |
| `game/dev2_grade.gd.uid` | Orphan `.uid` for a source that no longer exists. | **REMOVED 2026-11-14.** |
| `game/staging_notes_2026_10_14.md` | Stray session note at the game root. | **DONE 2026-11-14:** migrated verbatim into `TASKS_ARCHIVE.md`, file removed. |
| `game/debug/` (9 scans) | Old general diagnostics, zero code refs. | **MOVED 2026-11-14** to `game/tools/diagnostics/` (canonical, with a README run guide); `.uid` siblings cleared. |
| `game/dev_temp/probes/` (13) | Receipt-bearing world probes (`wilds_probe`, `cistern_probe`, `render_audit`, ...). | **KEEP** for now: they assert shipped builds and are cited as receipts; not CI, not dead. |

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

## F. Endpoint census (2026-11-14)

Every `srv/` service was checked against its in-engine consumer. No dead HTTP
endpoint remains in `game/`:

| Sidecar | Consumer | Verdict |
|---------|----------|---------|
| `srv/pg-bridge` | `adapters/persistence/postgres_store.gd` via `PG_BRIDGE_URL` | KEEP |
| `srv/redis-bridge` | `adapters/cache/redis_store.gd` via `REDIS_BRIDGE_URL`; shard bus opt-in (`SHARD_BUS_BACKEND=redis`) | KEEP (dev default still memory -- documented, not dead) |
| `srv/webhook-bridge` | `core/economy/webhook_transport.gd` + `network_manager.gd` poller | KEEP |
| `srv/julia-bridge` | `core/services/multi_iso_service.gd` (autoload, `enabled=true`) | KEEP; prop presolve artifacts are consumed at boot, `presolve.jl` is a test oracle |
| `srv/backup` | deployment scripts/docs, not game code | KEEP |

Also verified comment-only (no live symbol references anywhere in `game/*.gd`):
`world_playable` (45), `player_controller` (11), `EventBus` (6),
`LODManager` (3). These are history in prose, not breakage -- sweep them when
touching the file, never with a blind rename.

## G. Tooling note (2026-11-14)

`dhaupin/gamestruct` is a Node semantic-tree/bridge library (the agent door:
one tree, human + agent lanes, HTTP/MCP bindings) -- **not** a host for Godot
probes. Godot diagnostics therefore live in-repo at `game/tools/diagnostics/`
(general scans) and `game/dev_temp/probes/` (receipt-bearing world probes).
Do not move `.tscn`/`.tres`-dependent probes out of the Godot project: they
load `res://` resources and need the engine.

Planar note: the planar world shape is retired for the open world, but
**instanced rooms (arenas, coliseums, the sandpit) still use planar geometry**,
so `world_map`'s planar fallback constants and the planar instance scenes are
supported, not residue.
