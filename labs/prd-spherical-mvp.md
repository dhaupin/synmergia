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

0. **Instance modes are contract-level (2026-09-28).**
   ELIMINATION / TEAM_DEATHMATCH / ROYALE live in
   InstanceContract + ZoneData.instance_mode BEFORE S10 wiring;
   the bout controller is written against bout_rules(), never a
   hardcoded mode. Arena cap 12 (full 6v6); party size flat 6;
   duels = public + private instances.
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

### Wave A — the globe is live for humans (2026-09-28)
- [x] `project.godot` gains a `[synmergia]` section with
      `world/shape="spherical"` -- the shipped default. LESSON:
      project.godot comments are `;` not `#` (a `#` comment inside a
      section silently breaks the next key's parse).
- [x] `test_world_shape.gd` asserts the project default IS spherical
      (flipping back must be a conscious, test-flagged decision).
- [x] `play_driver.gd` pins planar explicitly -- it verifies the
      CLASSIC world and stays honest about that. xvfb-verified.
- [x] `globe_driver.gd` unchanged -- it now exercises the SHIPPED
      path (no runtime flip needed, kept for explicitness).

### S7 — seeded chunk content + walk-over (2026-09-28)
- [x] `scenes/worlds/terrain_gen.gd` -- SeedChain-driven per-face
      rock content: `SeedChain.derive_seed([world_seed],
      "terrain/rocks_v1/face/<id>")`, 32 bytes folded to an RNG seed,
      2-5 rocks per face, pure function of (world seed, face id,
      RULESET_VERSION). World seed from `synmergia/world/seed`.
- [x] Determinism tests (`test_terrain_determinism.gd`): order
      independence (interleaved vs sorted derive identical), seed/face
      sensitivity, all-faces 2-5 rocks, provider continuity via
      REFINEMENT RATIO (max step delta halves when step halves -- a
      fixed threshold is the wrong instrument for steep-but-continuous
      caps; test-caught).
- [x] Streamer spawns rocks per loaded patch (parented to the patch;
      unload is free). VISUAL-ONLY on purpose: colliders duplicate
      the walk-over authority and stall movement via slide friction
      (test-caught lesson; colliders may return on a separate layer
      for raycasts).
- [x] Walk-over: `globe_player.snap_height_provider` -- exact
      smoothstep cap height (never lerped; a lagged lift lets the
      body intersect and stall, test-caught lesson), MAX across
      overlapping caps (max of continuous is continuous; first-match
      return jumps, test-caught lesson). Rock top geometry matches
      the provider (ROCK_EMBED + R*scale).
- [x] Regression: globe probe 12/12 (250 m walk restored over rocky
      terrain, curvature 1.32), stream probe 9/9 with rocks.

### S8 — planet_radius config + 20 km scale probe (2026-09-28)
- [x] `project.godot` `[synmergia]` gains `planet_radius=100.0` (the
      100 m prototype stays the shipped default; 20000 is the v1
      planet scale from locked decision 1). `globe_island.gd` reads
      it in `_ready` (PLANET_RADIUS_SETTING); SHELL_RADIUS const is
      replaced by `planet_radius` everywhere; probe_globe_island and
      probe_terrain_stream consume `_globe.planet_radius`.
- [x] `globe_player.gd` gains `snap_enabled: bool = true` -- an
      additive diagnostic (default true = zero behavior change) that
      lets the probe separate snap interaction from raw contact
      physics.
- [x] `tests/probe_planet_scale_20km.gd` (11 asserts, exit 0):
      Stage A control (100 m walk 30.1 m, glued), Stage B 20 km
      snap-ON (spawn radius 20001.0 m exact, walk 0.14 m / 8 s,
      glued), Stage C 20 km snap-OFF (walk 0.02 m, radial speed
      0.00, stays near shell), Stage D face resolution at 20 km.
      Bounded frame caps; single quit; globes freed between stages.
- [x] **20 km WALK STALL -- FIXED (floating origin + surface pad).**
      Root cause PROVEN by isolation experiments (tmp experiment,
      deleted after the verdict): the stall is the BODY's own
      world-transform magnitude, not the collider. A body at |r| = 200
      with planet_radius = 20000 walks freely on a perfect local floor
      (29.7 m); the same floor at |r| = 20001 walks 0.03 m. Collider
      locality alone does NOT fix it, and a trimesh built in
      world-space coords (|v| ~ 20000) is worse: physics import of
      huge-magnitude triangle soup degenerates (ray/shape queries see
      NOTHING, bodies fall through). The fix:
      1. Floating-origin rebase. Planet-bound content (shell, patches,
         markers, pad) lives under `world_root`; the PLAYER stays a
         direct child of the scene. Past `SHIFT_RADIUS = 1500` m
         (inside the measured free-walk threshold: <2 km free, 5 km
         degraded, 10 km dead), `_maybe_shift_world()` translates the
         planet by -player_offset AND teleports the player by the
         same delta. Both move; relative pose is identical and every
         float32 magnitude is small. A world-only shift is NOT
         enough: the killer is the body's magnitude, and with snap
         off the body is stranded mid-air above the moved surface.
      2. Planet-relative math end to end. `planet_center` on the
         scene and the player; `globe_player.planet_up()` /
         `planet_distance()` replace global-origin math; the snap
         target, glue check, streamer face addressing (update() takes
         the planet-relative position), and the rock-top provider
         (now takes a world POSITION and derives its own direction)
         all read from the planet center. Planet-relative coordinates
         are shift-invariant.
      3. Planet-scale ground = ONE re-anchored surface pad. Above
         `PLANAR_SHELL_MAX_R = 2000` the megasphere SphereShape
         collider is disabled and a single StaticBody with a fixed
         curved-disc trimesh (local coords <= 64 m, rings dipped by
         the exact spherical sagitta, backface_collision on) is
         re-anchored under the player every physics frame (the scene
         node processes before its player child) and after every
         rebase. The proven primitive: small local collider,
         meter-scale coordinates, dynamic anchor.
      4. Walk surface: R + TILE_LIFT + SKIN (0.52 + 1.0) ONLY at
         planet scale. At prototype scale the collision shell IS the
         surface (lift 0) -- streamed tiles are visual-only there and
         the player keeps real shell contact (probe_globe_island
         radial rest |v_rad| = 0.01; applying the lift at 100 m
         masked contact as free-fall, test-caught).
      5. Streamer patches are planet-relative children of world_root
         with LOCAL vertices (node position = face center * tile_r);
         the per-patch trimesh collider machinery was REMOVED
         (face-local coords are still ~10 km at 20 km radius and the
         pad carries physics). `face_for_position` grew an optional
         `planet_center` arg (default ZERO; existing callers
         unchanged).
      Probe flipped to the fix (25 asserts, exit 0): Stage B spawn
      r = 20001.52 exact, snap-ON walks 30.08 m (arc 29.3 m); Stage C
      snap-OFF walks 30.08 m with |v_r| = 0.000 (the old stall
      tripwire); Stage D forces a rebase (teleport 1600 m): exactly
      one more shift, body re-lands at the gap between the shifted
      planet-center radius and the walk surface (~64 m; asserted
      structurally |body_r| = |c| - walk_r), still glued, streaming
      holds 4 patches, walks 10 m post-shift, no runaway loop; Stage
      E face resolution. The honest walk metric is ARC distance
      measured FROM THE PLANET CENTER (from the world origin a 10 m
      walk post-rebase swings the direction by ~9 deg -- the body
      sits only ~64 m from the origin after a rebase). Rebase counts
      assert as DELTAS: the spawn itself (20 km out) triggers the
      first rebase on frame 1.
- [x] Regression registered: probe_planet_scale_20km in DEFAULT_SET
      -- regression 24/24 + lint quartet green on the fixed tree.
      Commit + push via Changes panel (owner).

### S9 — instances/lobby contract (2026-09-28)
The "separate future session" of locked decision 4. Locked decision
3 governs: instances stay planar AABB with vanilla -Y gravity; they
do not join the icosahedral mesh.
- [x] `game/core/schemas/instance_contract.gd`: the contract as
      constants + pure functions -- GRAVITY_FORCE 20.0, UP_DIRECTION
      +Y (planar, never radial), DEFAULT_ENTRY_DEADLINE 20 s,
      LobbyState enum (OPEN/FULL/LOCKED/CLOSED), `gravity_contract()`
      (what every instance scene must set on its bodies),
      `entry_deadline(zone)` (ZoneData override wins),
      `lobby_state_for(instance_data, started)` and
      `party_fits(instance_data, party_size, started)` (pure functions
      of ZoneManager's instance dict shape, so probes and future
      lobby UI agree with the service). No autoload, no class_name
      collision (static helper, preloaded by the service).
- [x] `ZoneData.instance_entry_deadline: float = 0.0` (0 = shared
      default) -- the per-zone lobby deadline override.
- [x] `game/core/services/instance_service.gd` (autoload):
      the front door over ZoneManager's lifecycle. `get_contract`
      (planar gravity + capacity + deadline per zone),
      `join_instance` / `join_party_instance` (capacity-checked
      join; FULL returns capacity_ok=false so the caller queues --
      NEVER silently opens a second instance for the same base
      zone), `live_instance_id` (party routing via ZoneManager,
      test seam `_force_instance`), `get_lobby_state`,
      `refresh_registry` (script-mode boots load zones late).
- [x] ZoneManager capacity fix: `add_to_instance` now enforces
      `instance_capacity` (0 = unlimited) at the single chokepoint;
      previously `can_enter_instance` checked capacity but no join
      path called it. All callers get the same enforcement.
- [x] Arena ZoneData `game/data/zones/zone_arena_coliseum.tres`
      (zone_ prefix == filename == id): FREE_PVP, capacity 12
      (raised from 8 per locked decision 4 -- full 6v6 parties),
      is_instanced, deadline override 60 s, two spawn points.
- [x] Probe `game/tests/test_instance_contract.gd` (40 asserts,
      exit 0, registered in DEFAULT_SET): contract constants,
      lobby-state derivation incl. LOCKED-beats-FULL and unlimited
      capacity, arena data shape, real-autoload service flow --
      solo join routes to the live instance, 8 seats fill, the 9th
      queues (capacity_ok=false, no phantom instance), lobby
      OPEN -> FULL, forced-seam routing, per-zone contract, 45 s
      override beats the 20 s default.
- [x] Regression 25/25 (incl. this probe in DEFAULT_SET) + lint
      quartet green; commit + push via Changes panel (owner).

### S9+ — instance mode system (contract layer, pre-S10)
Locked decision 4 (owner, 2026-09-28): arena capacity 12 = full
6v6; party size stays flat 6 (no level scaling); duels use PUBLIC +
PRIVATE instances (the one-live-instance rule is public-only).
- [x] `InstanceContract.InstanceMode` enum: ELIMINATION (one life,
      last team standing), TEAM_DEATHMATCH (respawn + spawn shield,
      first team to the kill target), ROYALE (reserved). Mode baked
      in BEFORE S10 so later modes never retrofit the controller.
- [x] `InstanceContract.bout_rules(zone)` pure function: one dict
      ({mode, respawn_allowed, kill_target, time_limit_seconds,
      spawn_shield_seconds}) for every mode; contract defaults
      (kill 25 / 600 s / 4 s shield) with per-zone overrides.
- [x] ZoneData exports: instance_mode, instance_kill_target,
      instance_time_limit, instance_spawn_shield (0 = default).
- [x] Modes on disk: `zone_arena_sandpit.tres` (TEAM_DEATHMATCH,
      kill 20, 8 min, 4 s shield, cap 12) and
      `zone_royale_valley.tres` (ROYALE reserved, 30 seats, 15 min,
      level 10, fog). Coliseum stays ELIMINATION.
- [x] Probe extended: 52 asserts -- mode enum, per-zone bout_rules
      derivations for all three modes, null-zone elimination
      default; lint 24/24.

### S10 — arena wiring (mode-agnostic)
- [x] Arena trigger at Haven's edge: `arena_gateway.gd` Area3D built
      into globe_island under world_root (shift-invariant, east of
      spawn), fires InstanceService.join_instance /
      join_party_instance once per entry (dedupe inside the volume,
      re-arm on exit); party roster read via PartyService.
      get_player_party / get_party_members; solo degrade on failure.
- [x] Lobby moment: typed toast through NotificationService.notify
      (ZONE_CHANGED kind, dedupe key per entity+instance): OPEN
      state + entry deadline, or the FULL refusal line.
- [x] Planar instance scene `scenes/instances/arena_instance.gd`
      (+ arena_fighter.gd): code-built room (floor + 4 perimeter
      walls, 120 m), spawns at the zone's spawn_points (one per
      team), fighters land under Contract.GRAVITY_FORCE planar -Y;
      rules from bout_rules() -- NO hardcoded mode in the scene.
- [x] Bout controller: start_bout -> LOCKED semantics,
      report_death attribution (killer team scores; victim's team
      loses a life), ELIMINATION last-team-standing win,
      TEAM_DEATHMATCH respawn loop (zone respawn_timer + contract
      spawn shield blocks kills while active) + kill_target win,
      bout_started / bout_ended / fighter_down signals ready for
      S11 duels. Globe <-> instance scene swap stays in GameManager
      flow (headless skips scenes; the room is data+logic, probed
      headless).
- [x] Probes: probe_arena_instance.gd 24/24 (room build from zone
      data, planar landing, elimination winner, TDM shield-blocks-
      kill + kill target exactly 20) and probe_arena_trigger.gd
      14/14 (entry fires join, dedupe, re-arm, 12-of-13 capacity
      enforcement at the trigger, no phantom instance). Both in
      DEFAULT_SET.
- [x] Regression 27/27 + lint quartet green (three-globe-probe
      regression caught the := load() type-inference parse error
      within one run -- fixed with an explicit Area3D type).

### S11 — duels + matchmaking (bout assembly)
Locked S11 goals (owner, 2026-09-28): one bout-assembly path shared
by manual duels and solo matchmaking; the fill flag bridges them.
Locked S11 decisions (owner, 2026-09-28, second round -- the lobby
conversation):
1. **The lobby is CANONICAL.** One panel (LobbyUI, L key; Bouts /
   Duels / LFG tabs) over one engine (LobbyService). Open-world play
   is first class: grinding crews, horde raids, dungeon delves, and
   hunting parties advertise through the same LFG book as arena
   queues -- the lobby ties PartyService, duels, matchmaking, and
   LFG/LFM into one place.
2. **Stones in towns are the lobby's doors; teleports complete the
   trip.** Players queue by proximity to a gateway stone (arena_gateway
   queue_mode), the bout teleports the assembled teams in, and EVERY
   ending (win, loss, AFK kick) returns fighters to the stone they
   queued at -- origin_stones round trip, no post-match stranding.
3. **AFK kick.** Idle longer than the zone's kick window (contract
   default 90 s, instance_afk_kick override, 0 = off) and the bout
   books your departure and sends you to your stone. ROYALE rooms
   skip the sweep (drop pacing is the mode's own tension).
4. **Every teleport into a bout scatters** (initial spawns, TDM
   respawns, ROYALE drops): contract scatter_spawn golden-angle ring,
   first member exact, radius scaling with roster (no stacking).
5. **Level bands + capped power normalization.** Matchmaking pairs
   within a level band (base 10) that widens with wait (halves the
   distance after 30 s); absolute gulfs (5 vs 60) never auto-assemble.
   When a pairing does happen with consent (duel or fill), the
   fighter's level normalizes toward the reference CAPPED at ratio 2
   -- a lvl 5 next to a 60 plays at 10, never at 60 -- via bout-local
   buffs only; real stats never change.
Status: LobbyService + LobbyUI + contract primitives + stone queue
path SHIPPED (probes 45 + 34 + contract 63). Still open: combat-bridge
shield + power-scale enforcement, scene-flow teleport listener,
ROYALE drop scatter wiring.
- [ ] Spawn-shield combat enforcement (fire-and-you-lose-it): the
      combat bridge calls ArenaFighter.break_shield() on any
      SELF-INITIATED action (attack, skill cast, potion, self-buff);
      received effects (team aura, aoe heal, buffs from others)
      never break it. Fighter-side + contract doc DONE (S10+).
- [ ] Bout assembly engine: `assemble_bout(zone, teams)` -- the one
      function that seats parties/individuals into teams against
      bout_rules capacity and starts the private instance.
- [ ] Duel consent handshake: challenge (/duel or party-leader to
      party-leader) via the PartyService pending-invite pattern
      (60 s timeout, sent/accepted/declined/expired signals); accept
      = assemble_bout with both parties; PRIVATE instance (the
      explicit exception to the public one-live-instance rule);
      LOCKED on start.
- [ ] Solo matchmaking: unmatched players queue per zone+mode; the
      engine groups them into fair teams (level-proximity first,
      then FIFO) and auto-assembles when a bout is fillable -- duel
      is just a manual, consented assembly through the same path.
- [ ] Fill-to-parity flag: during the challenge/accept phase, the
      outnumbered party can consent to matchmaking fill (e.g. a 6
      vs 4 duel becomes 6v6 with 2 queue players). Consent is per
      accept, surfaced in the handshake UI; fills consume the queue.
- [ ] Bout flow on ELIMINATION: entity_died attribution -> last
      team standing -> winner via TitleService reward; losers
      returned to bind point.
- [ ] TEAM_DEATHMATCH bout on the sandpit rides the same controller
      via bout_rules: respawn + shield (with the break rule above),
      score to kill_target. Sandpit widened to 220 m with 8
      deterministic cover rocks (line-of-sight leverage). Elimination
      rooms carry their OWN pattern (2026-09-28 owner request): an
      8-pillar perimeter ring -- cardinal columns at 0.78 of half,
      diagonals at 0.55 -- that keeps the duel CENTER clean sand
      while breaking line-of-sight near the rim; tall 3x7x3 pillars,
      lighter tint, visually distinct from TDM slabs.
- [ ] Probe: handshake accept creates one private instance with
      both parties, bout resolves a winner; solo queue assembles a
      fair TDM bout; fill flag completes a 6v4 challenge.

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

- **2026-09-28 (S10 session)** -- arena wiring SHIPPED: mode layer
  (InstanceMode + bout_rules + three zones on disk), planar instance
  room + fighter bodies, gateway trigger on the globe, lobby toasts.
  Two test-caught lessons: (1) probe arithmetic -- seat/fill counts
  must be recounted after every fixture change (two rounds of
  14-vs-13 style off-by-ones); (2) := load() type inference still
  bites in code-built scenes; annotate the var (Area3D). TDM sync-
  revive probe pattern: simulate respawns to test controller
  accounting without waiting the zone timer. Next: S11 duels on
  ELIMINATION.
- **2026-09-28 (S8 fix session)** -- 20 km walk stall FIXED via
  floating origin + a re-anchored surface pad. Root cause proven by
  margin experiments: the BODY's own world-transform magnitude
  (walks freely at |r| = 200 on a local floor even with
  planet_radius = 20000; 0.03 m at |r| = 20001), NOT the collider;
  world-space trimeshes at |v| ~ 20000 are degenerate for physics
  import entirely. Ship shape: globe_island world_root +
  _maybe_shift_world (planet AND player move by the same delta),
  planet_center threading through player/streamer/rock provider,
  one curved-disc surface pad re-anchored every physics frame at
  planet scale (megasphere disabled > 2000 m), streamer patches
  vertex-local under world_root. Probe flipped to the fix (25/25
  incl. a forced-rebase stage); regression 24/24 + lint quartet.
  Lessons: (1) a floating-origin rebase must teleport the BODY too;
  (2) at planet scale one dynamically anchored small collider beats
  per-face colliders (face-local coords are still ~10 km); (3) the
  prototype walk surface stays the shell -- the tile lift only
  applies where the pad carries physics. Next: S9 instances/lobby
  contract.
- **2026-09-28 (S8 session)** — planet_radius config wired end to
  end; 20 km probe built with a control/stall/isolation experiment.
  Two lessons recorded for future sessions: (1) a rebase-drift
  measurement must compare against a REBASED frame, not the walk
  start -- the crashed session's "0.14 m float32 escape" was walked
  distance mislabeled; (2) hypothesis-driven probes need the
  negative control (snap OFF) BEFORE the verdict is written -- the
  control overturned the snap theory in one run. Open verdict: 20 km
  walk stall is physics-contact precision, not snap, not transform.
  Next: S9 instances/lobby contract, or the 20 km stall fix.
- **2026-09-27 (night)** — Session opened. PRD written; S1 starting.
  Context: phases 1-5 substrate all COMPLETE (TASKS.md); this PRD
  covers the unclaimed gap between "addressing math exists" and "a
  player stands on a curve". Commit hashes appended as waves land.
- **2026-09-28 (part 3)** — Wave A (globe SHIPPED as the default
  world; [synmergia] project section, `;`-comment lesson, planar
  pinned in play_driver) + S7 (SeedChain rocks, walk-over provider,
  three test-caught lessons: min-chord faces needed it, max-union
  caps, exact-not-lerped lift, colliders-vs-provider double
  authority). Determinism test uses refinement ratios.
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
