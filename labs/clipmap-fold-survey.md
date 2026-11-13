# Clipmap-Fold Survey + Removal Candidates

> **Status:** SCOPED 2026-11-04. The clipmap is the SOLE terrain renderer
> (prd-clipmap sec 11a steps 1-5 DONE, `globe_terrain_streamer.gd` deleted).
> This doc answers two questions the owner asked:
> **(A)** what is still OFF the clipmap / provider path and should fold into it,
> **(B)** what is now dead and can be removed.
>
> Every claim below was read from the tree at `6871eb51` (staging). Counts are
> "references outside the file itself" -- a bare symbol grep, so a `class_name`
> used by another script is caught, not just a `preload` path.

---

## Part A -- Clipmap-fold candidates (still off the provider path)

The clipmap + `GroundProvider` + `PropLayer` trio is the render law. These
still build geometry by hand or read the retired streamer's shape. Ranked by
value.

### A1. `globe_world` shell + water + pad still speak "streamer" (HIGH) -- FOLDED

`game/scenes/worlds/globe_world.gd` was the last big consumer of streamer-shaped
names even though the object it holds is a `GlobeClipmap`:

- `var streamer` -- the clipmap instance was stored under the OLD name;
  ~40 call sites (`streamer.update`, `streamer.terrain_h`, `streamer.world_seed`,
  `streamer.walk_surface_h`, ...). The clipmap exposes every one of these as a
  parity shim (see A3), so the rename was mechanical but wide.
- `_setup_streamer()` -- actually built the clipmap. Name was a lie.
- `STREAMER_TILE_LIFT` -- the clipmap already declares its own `TILE_LIFT = 0.52`
  (globe_clipmap.gd L49); `globe_moon` / `globe_underworld` both name theirs
  `TILE_LIFT`. Only `globe_world` kept the `STREAMER_` prefix.
- `_build_water()` -- see A2 (now declaration-driven).
- `_exit_tree()` called `streamer.async_shutdown()`; the clipmap keeps an
  `async_shutdown` for teardown -- fine, just the name.

**FOLDED (2026-11-04).** The handle is `clipmap` (public, because ~32
probes/tests read it via `get("clipmap")`; the sibling worlds keep their
private `_clipmap` -- a deliberate divergence, the handle is the scene's
public API), `_setup_streamer` -> `_setup_clipmap`, `STREAMER_TILE_LIFT` ->
`TILE_LIFT`. The ~39 external `get("streamer")` / `.streamer` call sites were
renamed too, plus local `streamer` vars in the touched probes. Historical
"the legacy icosa streamer was retired" comments were kept (they name a real
retired thing); only live-code references changed.

Receipts (all green, no script errors): `probe_clipmap` ALL PASS,
`probe_terrain_planet` 28/0, `probe_globe_world` / `probe_underworld` 44 /
`probe_starter_village` / `probe_world_boot_speed` / `probe_ground_law_audit` /
`probe_stream_flow_100m` / `probe_ancient_loop` exit 0,
`test_globe_wildlife` 23/0, naming lint 49/0.

### A2. Main-world ocean is hand-built; the other worlds are declaration-driven (HIGH) -- FOLDED

`globe_world._build_water()` painted a `SphereMesh` at the sea line -- a single
opaque shell with a hardcoded material. The moon and underworld instead read an
`OceanVolume` declaration and draw via the shared `WaterKit`
(`core/world/water_kit.gd`):
- `globe_underworld` uses `WaterKit.build_pool` for the cistern + lava lake;
- `globe_moon` draws the crater inland sea through the clipmap standing-water
  sheet (provider `water_surface`) + `WaterKit`.

The main world already HAS the declaration: `data/oceans/ocean_sundered_sea.tres`
(`waterline_is_radial`, `max_depth 60`, currents, fog) -- read today only by
`OceanService` for swim physics, NOT by the renderer. So the visible ocean and
the swim law were two separate laws on the main world (the moon/underworld
already unified theirs).

**FOLDED (2026-11-04).** The whole-sphere sea is structurally a SHELL, not a
per-direction sheet: the clipmap's standing-water sheet only draws its ~5 km
drawn reach, so it can never represent a body that wraps the globe (that reach
limit is exactly why the sea-line guard at `globe_clipmap.gd` L763 exists --
the sheet must never try). The honest fold, then, was NOT to delete the shell
but to make it DECLARATION-DRIVEN:
- `OceanVolume` gained a surface-look section (`surface_color`,
  `surface_roughness`, `surface_metallic`) -- renderer-read, physics-ignored,
  defaults = the shipped shell look;
- `ocean_sundered_sea.tres` carries that look explicitly (the `.tres` is the
  source of truth);
- `WaterKit` gained `build_sea_shell(parent, sea_radius, volume, style)` -- the
  THIRD geometry class (local disc / per-direction sheet / global shell), so
  every visible water body reads ONE `OceanVolume`;
- `globe_world._build_water` now resolves `ocean_sundered_sea` through the
  `OceanService` autoload (script-mode-safe) and calls `build_sea_shell`; the
  hand-built `SphereMesh` + hardcoded material are gone. The waterline radius
  is unchanged (`planet_radius + STREAMER_TILE_LIFT + sea`), which the probe
  now cross-checks against the swim law's own `OceanService.sea_surface_radius`
  -- ONE waterline, drawn and swimmable.

Receipt: `probe_terrain_planet` gained two legs (shell paints the declaration's
surface look; shell radius == the swim law's sea radius). Red-by-name verified:
forcing a wrong `albedo` override in the builder turns the look leg RED, and
reverting restores green. The clipmap sheet's sea-line guard is untouched
(still correct: the shell owns the sea, the sheet owns rivers/high ponds).

### A3. Streamer-compat shims in `globe_clipmap.gd` (MEDIUM)

`globe_clipmap.gd` keeps a block of "streamer parity" methods so old callers
and probes did not break: `pending_derive()`, `_mesh_pending()`,
`_prop_pending()`, `mesh_lane_stats()`, `is_loaded()`, `active_faces()`,
`triangle_count()`, `visible_patch_count()`, `world_seed`, `current_face`
(L363-405 "public reads (streamer parity)"). These are honest API, but their
NAMES are streamer lore.

Real consumers today: `globe_world` (legit -- A1), and three probes/tests --
`bench_coldboot_hose` (drains `pending_derive`/`_prop_pending`/`mesh_lane_stats`),
`probe_prop_density` (`pending_derive`), `probe_walk_mesh_gap` (`pending_derive`),
`probe_starter_village` (`_mesh_pending`).

**Fold:** once A1 renames the caller, rename these to clipmap-native terms
(`pending_jobs()`, `prop_pending()`, `lane_stats()`) and update the 4 probes.
Low value on its own -- do it WITH A1 so the churn is one pass.

### A4. `penrose` ground backend + chart-LOD overlay (MEDIUM -- decision)

Two Penrose paths remain:
- `backend_penrose.gd` (`class_name TerrainBackendPenrose`): an authored
  heightfield backend installed via `terrain_gen.install_terrain_backend`. It
  is NOT referenced by any world (`world_main.tres` declares
  `terrain_backend_id = "sundered"`; the moon/underworld use their own
  providers). Its only reader is `probe_backend_penrose.gd`, which is NOT in
  the runner DEFAULT_SET. **Zero live consumers.**
- The chart-LOD overlay (`penrose_chart_adapter.gd` + `penrose_chart_lod.gd` +
  `penrose_mesh_builder.gd`), wired in `globe_world._setup_chart_lod`, gated
  OFF by default (`chart_overlays_on = false`, L618) -- "redundant decoration
  beside the Penrose ground backend."

**Decision needed:** keep the Penrose ground backend as a dormant alternate
authored terrain (then keep `probe_backend_penrose` in the runner so it does
not rot), or remove it as an unused experiment. If the overlay stays OFF by
default forever, it is a candidate for removal too.

### A5. Hand-built prop builders (LOW -- by design)

`village_props.gd` (404), `starter_village.gd` (251), `pans_monolith.gd` (134),
`capitol_monolith.gd` (245), `ferry_vessel.gd` (356), and
`arena_instance.gd` (824) build geometry with raw `MeshInstance3D`/`*Mesh.new()`.
These are AUTHORED placements (a village, a monolith, a ship), not streamed
flora -- `PropLayer` is for the seeded scatter, `instance_prop_kit.gd` already
covers sealed rooms (arena calls it, arena_instance.gd L791). **These are NOT
fold candidates** -- they are the correct authored layer. Listing them so they
are not mistaken for debt.

---

## Part B -- Deprecated / removal candidates (verified dead)

Each was checked for references OUTSIDE its own file (path AND bare symbol).
"refs=0" means nothing in `game/**/*.gd|*.tscn` mentions it.

### B1. Verified dead -- safe to delete (HIGH confidence)

| File | Lines | refs | Notes |
|---|---|---|---|
| `game/core/_user.gd` | 6 | 0 | scratch; only preloads `_test.gd`, both dead |
| `game/core/_test.gd` | 4 | 0 | `class_name TestClass`, only read by `_user.gd` |
| `game/dev2_grade.gd` | 0 | 0 | empty file, tracked |
| `game/core/entities/entity_test.gd` | 16 | 0 | `class_name SynmergiaEntity` (name-squats nothing, but unused) |
| `game/core/entities/blacksmith_npc.gd` | 19 | 0 | `class_name BlacksmithNPC`; NPCs spawn via `npc_entity.gd` |
| `game/core/entities/skill_academy_npc.gd` | 22 | 0 | `class_name SkillAcademyNPC`; unused |
| `game/entities/npcs/bank_npc.gd` | 39 | 0 | `class_name BankNPC`; unused |
| `game/entities/player/components/gm_indicator.gd` | 94 | 0 | `class_name GMIndicator`; unused |
| `game/ui/components/name_plate.gd` | 229 | 0 | `class_name NamePlate`; the LIVE nameplate is `entities/floating_name.gd` (Label3D). Only "NamePlate" mentions are two stale comments in `hud_integrator.gd` |
| `game/core/admin/admin_catalog.gd` | 310 | 0 | `class_name AdminCatalog`; admin UI is `ui/admin/admin_dashboard.gd` |
| `game/core/admin/player_shell.gd` | 606 | 0 | `class_name PlayerShell`; no caller |
| `game/core/utils/frame_client.gd` | 402 | 0 | HTTP client for `srv/frame/` (which does not exist); local fallback never invoked |
| `game/core/services/multi_iso_service.gd` | 191 | 0 | bridge to the Julia orchestrator; not an autoload, no caller |
| `game/core/services/fairness_service.gd` | 258 | 0* | `class_name FairnessService`; *only mention is a string label in `adapters/backend_factory.gd:97` ("fairness_metrics": "FairnessService") -- a comment/label map, not a call |
| `game/adapters/memory_layer/memory_wrapper.gd` | 44 | 0 | `class_name MemoryWrapper`; `memory_store.gd` is the live one |
| `game/core/frame/math/bench_penrose.gd` | 69 | 0 | bench harness, no runner entry |

Subtotal: ~2,300 lines. **Caution before deleting:** `class_name` globals
register in the editor's script-class cache; deleting the file is enough, but
grep the runner DEFAULT_SET and `tests/` first (done -- none reference these).

### B2. Verified dead -- but tied to a DECISION

- `game/scenes/worlds/backend_penrose.gd` (191) + `game/tests/probe_backend_penrose.gd`
  -- see A4. Delete together, or keep + add the probe to the runner.
- `game/debug/*.gd` (9 files, `git ls-files game/debug`) -- dev scans
  (`geo_probe`, `land_scan`, `river_find`, `vista_scan`, ...). refs=0 in
  `game/**`; not in the runner. The repo already has `dev_temp/probes/` +
  `dev2/` for this purpose. Candidate to drop the whole `game/debug/` dir, or
  move the still-useful ones into `dev_temp/probes/`.
- `game/dev2/*.gd` (9 files) + `game/dev_temp/probes/*.gd` (13 files) -- 2,834
  lines total, all refs=0, not in the runner. These are hand-run diagnostics
  (prd-clipmap sec 11a step 4 says several were retargeted to `PropLayer`).
  **Do not blind-delete** -- `dev_temp/probes/wilds_probe.gd` and
  `cistern_probe.gd` are cited as receipts in AGENTS.md; the rest may still be
  run by hand. Treat as "keep but out of CI," or archive to `labs/`.

### B3. NOT dead -- do not delete (corrected from the earlier survey)

These were flagged as orphan/dead in the prior session notes but are LIVE:

- `core/schemas/{vehicle_data,currency_data,forge_balance_data,road_data,container_config_data,container_schema,spawn_table_data}.gd`
  -- each has real `.tres` data files and real readers (`ferry_service`,
  `inventory_component`, `premium_shop_service`, `ride_service`,
  `blacksmith_service`, `slot_service`, `zone_spawner`, `terrain_gen`,
  `globe_player`, `data_service`). KEEP.
- `core/admin/admin_shell.gd` -- used by `admin_dashboard`, `chat_ui`,
  `security_service`, `qos_service`. KEEP.
- `srv/julia-bridge`, `srv/*-bridge` -- referenced by docs (`prd-shard-mesh`,
  `prd-industry-labs`) and `functions/`; the Julia bridge backs
  `multi_iso_service` (B1). Remove only if the multi-iso orchestrator is
  retired wholesale.

### B4. Streamer naming remnants in otherwise-live files (rename, not delete)

`streamer` appears ONLY in comments in these live files -- a rename/naming
cleanup, not a deletion: `terrain_provider.gd` (7 mentions), `terrain_gen.gd`
(11), `ground_provider.gd` (1), `prop_layer.gd` (11), `zone_spawner.gd` (1),
`respawn_service.gd` (1), `spawn_table_data.gd` (1), and `globe_clipmap.gd`
(15+ "the streamer's X" comments). A "streamer -> clipmap" comment sweep would
retire the last of the lore.

### B5. Orphan `.uid` files (engine noise)

`*.uid` are gitignored (`.gitignore` L8) and untracked (0 tracked), but stale
ones sit on disk for deleted sources: `probe_meshcache_ram.gd.uid`,
`probe_mesh_bytes_ring.gd.uid`, `probe_stash_handoff.gd.uid`,
`bench_meshcache_v8.gd.uid`, `probe_ringfill_ram.gd.uid` (all under
`game/tests/`). Harmless (Godot regenerates), but a `git clean` of the local
`.godot`/uid cache is the fix. No action in git.

---

## Part C -- Other open items spotted

- **TODO/FIXME:** only ONE real marker in non-test game code
  (`server_manager.gd:298`, a resolved-TODO comment). The codebase is clean.
- **`world_map.gd` planar leftovers:** `_world_size = Vector2(8192, 8192)`
  ("8km x 8km world", L78) feeds only the planar fallback `_screen_to_world`;
  the live path is `_spherical_from_screen` (correct inverse of
  `lat_lon_to_uv`). Safe to keep as the planar-shape fallback, or drop with the
  planar shape (project.godot pins `world/shape="spherical"`).
- **`world_playable` / `player_controller`:** both DELETED; only comments
  remain (10 files reference them in "ported from world_playable" notes).
  Comment-only debt.

---

## Recommended order

1. ~~A1 + A3 (rename `streamer` -> `clipmap` in `globe_world` + the clipmap
   parity shims)~~ **A1 DONE 2026-11-04** -- handle/`_setup_clipmap`/`TILE_LIFT`
   renamed (+ all external callers). **A3 still open** (the clipmap's
   streamer-parity shims; do it as its own pass now).
2. **B1** (delete the 16 verified-dead files, ~2,300 lines) -- zero risk.
3. ~~A2 (main-world ocean from the `OceanVolume` declaration)~~ **DONE
   2026-11-04** -- the sea shell is declaration-driven through `WaterKit`
   (see A2 above); no shell deletion (a whole-sphere sea is structurally a
   shell, not a sheet).
4. **B2** (decide on `backend_penrose`, `game/debug/`, `dev2`/`dev_temp`).
5. **B4** (comment sweep) -- cosmetic, do last.
