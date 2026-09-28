# Spherical World MVP — Execution PRD

> **Status: ACTIVE — night session 2026-09-27.** This is the execution
> record for "getting an actual world going" (spherical). It ties the
> design docs together for implementation and is the **pickup point if
> a session crashes or blows context.**
>
> Design authority stays where it lives:
> - `labs/world-building-spherical.md` — spherical design (coords, mesh, gaps §6)
> - `labs/prd-geometry.md` — addressing authority (NSC-9, icosahedral)
> - `labs/prd-world.md` — planet/instances topology (sec 2c, sec 5)
> - `labs/world-building.md` sec 1.6 — shape-is-a-parameter rule
> - `labs/prd-3d-pipeline.md` — asset + verification conventions

---

## 0. PICKUP PROTOCOL (read this first after any crash)

1. Read this file top to bottom. The wave table in sec 3 is the
   source of truth — checkboxes are facts, prose is context.
2. Read the latest entry in the session log (sec 4) and
   `labs/TASKS.md` "Open / next candidates".
3. Check ground truth in the worktree:
   `git log --oneline -5` and `git status -sb` — a wave's work is
   only DONE if its commit exists AND its checkbox is ticked here.
4. Re-verify before continuing any wave:
   `sh ./scripts/godot_test_runner.sh` (regression) and the CI lint
   gates (`tests/lint/test_lint_charset.gd`, `test_lint_syntax.gd`,
   `test_lint_autoload.gd`, `test_parse_check.gd` via the runner).
5. Do NOT re-litigate locked decisions (sec 2) mid-implementation.
   Change them in this file first, with the owner, or not at all.

---

## 1. Goal (one paragraph)

A player stands on a sphere. The data layer already knows the planet
(icosahedral + NSC-9 addressing is DONE in the frame); what is missing
is (a) the spherical math the gameplay layer needs (distance, bearing),
(b) the shape parameter that lets planar and spherical worlds coexist
under one codebase, and (c) proof that radial gravity and a curved
walkable surface work in-engine. This PRD lands (a)+(b) as shipped
primitives and (c) as a probe-verified standalone prototype — without
touching the existing playable world.

## 2. Locked decisions (owner, 2026-09-27)

1. **Planet radius 20 km for v1** (`prd.md` sec on planet scale).
   The S3 prototype globe uses **100 m** so curvature is visible and
   float precision is trivial. Floating origin is Phase C work, NOT
   this PRD.
2. **Map shape is a parameter** (`world-building.md` sec 1.6):
   `planar | spherical`, default `planar`. No hardcoded shape
   anywhere; addressing is `projection_fn(W, world.shape, resolution)`.
3. **Radial gravity is quarantined to the spherical ground path.**
   Instances (arena/duel/dungeon) stay planar AABB with vanilla -Y
   gravity per `prd-world.md` sec 2c. They do not join the icosahedral
   mesh.
4. **Instances / lobby contract is a separate future session.**
   Explicitly out of scope here.
5. **No resource packs.** The .glb naming registry + pck flow stays
   as is (prd-3d-pipeline sec 2).
6. **Blender MCP: not adopted.** The python generator pipeline +
   `model_export_lib.py` + in-engine probes remain the asset path.
7. **Every artifact is probe-verified** (headless script-mode tests;
   xvfb + pixel analysis for anything rendered) before its checkbox
   is ticked. Honest records: untick what regresses.

## 3. Waves

### S1 — spherical.gd frame primitive + tests
- [x] `game/core/frame/math/spherical.gd` (no autoload, no GameManager;
      static utility like Icosahedral): haversine distance, geodesic
      bearing, great-circle intermediate point, spherical_to_cartesian
      / cartesian_to_spherical, PLANET_RADIUS_METERS = 20000.0.
- [x] `game/core/frame/math/test_spherical.gd` co-located, SceneTree
      pattern, known-answer checks (equator degree ~111.32 km,
      north bearing 0 deg, haversine symmetry, coordinate round-trips).
      NOTE: test loads via `load("res://...")`, NOT the bare class_name
      -- fresh class_names are invisible to script mode until an
      editor import pass (GuardData lesson). Runner note: co-located
      frame tests run as `frame/<rel>` names (runner resolves them).
- [x] Test green headless (7/7 check groups incl. Icosahedral
      convention cross-check); awaiting commit.

### S2 — shape parameter + first wiring
- [x] World shape surfaced as config (default `planar`) without
      breaking existing planar worlds (`core/frame/math/world_shape.gd`,
      project setting `synmergia/world/shape`).
- [x] WaypointService consumes Spherical haversine/bearing for
      distance/bearing when shape is spherical; planar path unchanged
      (shape-gated). NEW: `get_bearing_to_active()` (planar north =
      -Z, matching ui/components/compass.gd).
- [x] Regression set still green (16/16 pre-existing at S2 close).

### S3 — globe island prototype (radial gravity proof)
- [x] `game/scenes/worlds/globe_island.tscn` (+ `.gd` root) +
      `game/entities/globe_player.gd`: `up_direction =
      global_position.normalized()` per physics frame, gravity along
      -up, camera basis Basis(east, up, -north) tracks local up,
      north = pole tangent (pole fallback per spherical PRD 5.3).
- [x] `game/tests/probe_globe_island.gd`: 12/12 -- spawn glue,
      radial normal, 250 m walk (250.1), glue + no radial drift
      after walk, curvature ratio 1.31 (predicted chord 191 m),
      camera-up dot 1.000, live Icosahedral cell + neighbors + sweep.
- [x] xvfb screenshot + pixel verification: stage1 spawn (1710
      unique colors, pole marker + sun), stage2/3 post-walk (sky
      over sphere; 326 colors; traversal moved player away from
      markers). frame_post_draw awaited before capture.
- [x] Standalone: NO edits to world_playable.tscn, main menu, or
      live services beyond S2's shape-gated math.

### S5 — terrain streaming (2026-09-28)
- [x] `core/frame/math/icosahedral_faces.gd` — the 20 spherical-
      triangle face REGIONS: min-chord edge construction (30 edges,
      each edge + its exactly-2 common edge-neighbors), outward
      winding, Voronoi-exact point->face (argmax dot with face
      center), neighbors-by-shared-edge. Test: `test_icosahedral_faces.gd`
      6/6 groups (counts/degree, adjacency symmetry, 30 edges x 2
      faces, vertex/center resolution, 2000-dir partition coverage,
      12 verts x 5 incidence). LESSON: the golden-rectangle vertex
      set forms spurious equilateral triples at chord 2.0 -- anchor
      triangles to the MINIMUM chord (a naive mutual-equal filter
      yields 42 faces).
- [x] `scenes/worlds/globe_terrain_streamer.gd` — patch meshes per
      face (spherical midpoint subdivision, ~7 m tile edge = level 4,
      256 tris/patch), active set = current face + 3 neighbors
      (steady state 4 patches / 1024 tris), load/unload signals,
      deterministic per-face tints, tiles lifted +0.52 above the
      sphere visual. Scene wired via stream_terrain (per-frame update
      from the player).
- [x] `tests/probe_terrain_stream.gd` 9/9 headless AND rendered:
      initial 4-patch set, border crossing at 41.9 m swaps stale
      patches, steady state holds 4, all-20-face sweep at 4-patch
      steady state. xvfb stages pixel-verified (1624/1938 unique
      colors vs 326 for the flat-tint shell -- patch tints visible).
- [x] Regression 20/20 with both new tests in DEFAULT_SET; lint
      quartet re-run on final tree.

### S6 — full-flow spherical world driver (2026-09-28)
- [x] GameManager `_handle_playing_state` branches on the S2 shape
      knob: planar (default) -> world_playable.tscn, spherical ->
      `scenes/worlds/globe_island.tscn`. The parameter is now
      load-bearing; planar default keeps every existing flow intact.
- [x] `tests/test_world_shape.gd` (default planar / spherical flip /
      garbage fallback incl. casing).
- [x] `tests/globe_driver.gd` -- the REAL flow on the sphere: menu ->
      character select (species/class handlers) -> Play -> GlobeIsland
      via the shape branch; walk via the real input map; HUD panel
      over the live world; ground-truth radial error 0.001 m at the
      shell. Rendered-only (self-skips headless honestly, since
      GameManager skips world scenes without a render context).
      Pixel-verified 6 stages (menu 21653 colors -> globe 61%
      green ground -> walked -> panel).
- [x] Regression 22/22 (adds test_world_shape + globe_driver to
      DEFAULT_SET); lint quartet green on final tree.

### S4 — records + gates
- [x] Tick the honestly-done boxes in `world-building-spherical.md`
      sec 6.1 (haversine, bearing, position->cell); leave map/UI boxes
      UNticked.
- [x] `labs/TASKS.md` session entry (files listed; hashes to append
      at commit time).
- [ ] CI lint gates + regression green -- regression 18/18 LOCAL
      (incl. new `frame/math/test_spherical` + `probe_globe_island`
      in DEFAULT_SET; runner now resolves co-located frame tests);
      lint quartet re-run pending on final tree. Commits + push via
      Changes panel (owner).

## 4. Session log (append-only, newest first)

- **2026-09-27 (night)** — Session opened. PRD written; S1 starting.
  Context: phases 1-5 substrate all COMPLETE (TASKS.md); this PRD
  covers the unclaimed gap between "addressing math exists" and "a
  player stands on a curve". Commit hashes appended as waves land.
- **2026-09-28 (same day, part 2)** — S6 (full-flow driver) DONE:
  shape knob now picks the world scene (planar default intact);
  globe_driver walks the real menu->select->Play->globe flow with
  pixel verification (radial err 0.001 m). Regression 22/22.
  Next candidates: chunk geometry follows SeedChain rules
  (deterministic per-face content), floating origin for the 20 km
  planet, instances/lobby contract PRD.
- **2026-09-28** — S5 (terrain streaming) DONE, commit 6b2f42d is
  the S1-S4 baseline. Faces primitive + streamer + probe 9/9,
  regression 20/20. Streaming is VISUAL-ONLY (sphere StaticBody
  stays the physics truth; tiles sag <6 cm below it at prototype
  scale). Next candidates: chunk geometry follows SeedChain rules
  (deterministic per-face content), full-flow menu->globe driver,
  floating origin for the 20 km planet.
- **2026-09-27 (night, same session)** — S1+S2+S3 DONE: 12/12 probe
  asserts headless AND rendered (xvfb), pixel-verified stages,
  regression 18/18 with the two new tests in DEFAULT_SET. S4 docs
  ticks done; commit+push pending (owner/Changes panel). Pickup
  remains sec 0.

## 5. Non-goals (this PRD)

Floating origin rebase, chunk streaming/LOD for spherical terrain,
minimap/world-map/globe UI, compass UI, zone-boundary walk-over
triggers, instances + lobby contract, ocean/boats, atmosphere/horizon
fog, multiplayer mechanics. Each is a follow-up PRD.

## 6. Conventions binding this work

- Frame primitives: no autoload, no GameManager dep, tabs, ASCII
  (AGENTS.md). `extends` before `class_name`. Ternaries need explicit
  types. `Resource.get` takes ONE arg.
- Tests: SceneTree pattern, `_initialize()` for autoload resolution
  if needed, exit 0/1. Runner: `sh ./scripts/godot_test_runner.sh`.
- Verification trick (rendered scenes): xvfb-run + /tmp screenshots
  + PIL mean-RGB/bbox analysis (see play_driver.gd history).
