You are a Synmergia subagent lane (Lane H: terrain -- the spawn-ground truth). Work ONLY inside your own worktree (your cwd). Never edit /workspace/project/synmergia directly.

FIRST, run the lane setup (idempotent -- warms the Godot import cache a fresh worktree lacks):
  sh labs/lane_setup.sh

Godot is NOT on PATH by default. Use it via:
  export PATH=/workspace/.tools/godot:$PATH
  godot --version   # expect 4.7.2.stable

CONTEXT
- Synmergia is a Godot 4.7.2 MMORPG on a 20 km procedural globe. The terrain is a
  streamed icosahedral tile grid (`game/scenes/worlds/globe_terrain_streamer.gd`,
  ~3900 lines). Each icosa face is a patch of subdivided triangles displaced by an
  ANALYTIC heightfield (`TerrainGen.terrain_height(dir, seed)` in
  `game/scenes/worlds/terrain_gen.gd`). The player WALK surface rides the SAME
  analytic law; the MESH must match it.
- The player SPAWNS on a FIVE-FACE ICOSAHEDRAL VERTEX: SPAWN is lat 0 / lon 0
  (`globe_world.gd: SPAWN_LAT_DEG/SPAWN_LON_DEG`), which is the canonical icosa
  vertex (1,0,0). `face_for_direction(spawn)` = 16 but `face_for_position(spawn)`
  = 18 (a vertex tie -- see the reader's MISSDEBUG note). This matters: the spawn
  direction is FAR from every face CENTER, so any "distance to face center" law
  treats the spawn as remote.
- Patch nodes carry `mi.position = face_center * (radius + TILE_LIFT)`; surface-0
  verts are LOCAL to that node (world = xf * vert). The reader below proves this.

THE FUNCTIONAL GOAL (this is what "done" means -- NOT probe-green for its own sake)
The player must spawn standing ON solid, visible ground that MATCHES the walk law:
the streamed mesh near spawn must resolve the plaza (SPAWN_HEIGHT 28.0 m) within a
tile, and the spawn face must not be stuck at a coarse boot placeholder. The user
reports the world "looks buggy" in play -- the ground underfoot is the complaint.

THE EVIDENCE (reproduce it yourself first; these are REAL at the parent HEAD)
Run, from the worktree root (game/):
  export PATH=/workspace/.tools/godot:$PATH
  cd game
  godot --headless --path . --script res://tests/probe_terrain_planet.gd  > /tmp/h_planet.log 2>&1; echo "exit $?"
  godot --headless --path . --script res://tests/probe_ground_law_audit.gd > /tmp/h_audit.log 2>&1; echo "exit $?"
  godot --headless --path . --script res://tests/probe_walk_mesh_gap.gd    > /tmp/h_gap.log 2>&1;   echo "exit $?"

Current results at HEAD:
- probe_walk_mesh_gap: PASS (worst |gap| 0.52 m). The walk law == the analytic law.
- probe_terrain_planet: FAILS 4 checks:
    FAIL mesh: spawn plaza is RESOLVED (nearest vert lift 91.47 m == SPAWN_HEIGHT 28.0)
    FAIL mesh: boot horizon is flat plaza (0 verts within 360 m)
    FAIL lod: spawn face rides the base level (3)          # base = _level_for_edge() = 7
    FAIL lod: near faces hold base level (0 of 3)
- probe_ground_law_audit: FAILS 2 checks (the face-16 CORRUPTION is ALREADY FIXED --
  the land surface reads "s0 law-delta 0.00" on EVERY face; do NOT chase the old
  -4.5 km crumple, it is gone):
    FAIL: ANCHOR lvl7-cap: no land tile contained the near-vertex anchor
    FAIL: ANCHOR lvl6-web: no land tile contained the near-vertex anchor
- Teardown noise (`Nonexistent function '_emit_water_tri'`, `get_ticks_msec on null`,
  `Thread destroyed without its completion realized`) is DOCUMENTED AS LEGAL: it is a
  worker-thread derive still running when the process quits (see labs/TASKS.md
  ~line 9411). Do NOT chase it; it is not the bug.

ROOT-CAUSE HYPOTHESES TO TEST (start here, do not guess-and-rewrite)
1. The spawn face is stuck at BOOT_PLACEHOLDER_LEVEL (3). Read
   `_boot_edge_drops` (streamer ~line 312), `_boot_mount_window`, `_boot_first_mount`,
   and the boot mount block (~line 400-410). The boot placeholder is meant to be
   PROMOTED on the next tick -- check whether `_lod_enforce` / `_demanded_level`
   ever asks for the base level for a face whose CENTER is far from the player
   direction (the spawn-vertex case). `_demanded_level` (line 557) returns `base`
   only when `center_ang <= reach + band_in`; on a vertex tie the spawn face may
   never satisfy that, so it sits at floor/placeholder forever.
2. The mesh near spawn has NO verts within 360 m and the nearest vert is 91.47 m
   off. That says the loaded patch near the spawn is COARSE (a coarse patch's verts
   are ~hundreds of m apart) -- consistent with #1. Confirm the patch in
   `_patches[face_for_direction(spawn)]` is at level 3, not 7.
3. The reader's anchor gap (`probe_ground_law_audit._mesh_at`, ~line 62-235): it
   scans every in-tree patch for a containing LAND tri near the anchor dir. If no
   face's patch covers the near-vertex anchor at the demanded level, that is the
   SAME root cause (#1) -- the covering face never built at full detail. The reader
   may ALSO need a fix (it is NOT in the runner DEFAULT_SET today; see below).

RULES
- Fix the ROOT CAUSE in `game/scenes/worlds/globe_terrain_streamer.gd` (and
  `game/scenes/worlds/globe_world.gd` ONLY if the spawn/build path is the cause).
  Prefer the smallest change that makes the spawn ground resolve.
- A probe check that is STALE (asserts an expectation the vertex-spawn reality
  contradicts) may be corrected -- but SAY SO in your report, and only after you
  have proven the FUNCTIONAL goal is met (mesh resolves the plaza + walk law match).
  Do NOT weaken a check to make it pass.
- ASCII only. Tabs for indentation in .gd files (mixed indentation is a parse error).
- Keep `probe_walk_mesh_gap` PASSING (it is the walk==law oracle).
- Do NOT edit shared files: scripts/godot_test_runner.sh (DEFAULT_SET), AGENTS.md,
  labs/TASKS.md, labs/lanes/*. The parent owns those.

OWNED FILES (yours): game/scenes/worlds/globe_terrain_streamer.gd,
game/scenes/worlds/globe_world.gd, game/tests/probe_terrain_planet.gd,
game/tests/probe_ground_law_audit.gd. Touch nothing else.

DEFINITION OF DONE
- You can state the ROOT CAUSE in one sentence (with the code line that proves it).
- The spawn ground resolves: mesh near spawn matches the walk law (plaza height),
  and the spawn face builds at the demanded detail level (not the boot placeholder).
- Evidence: paste the before/after of the 4 `probe_terrain_planet` lines and the 2
  `probe_ground_law_audit` anchor lines; `probe_walk_mesh_gap` still PASS.
- Commit in YOUR worktree with a message starting `lane-H:`.
- Report: root cause, the fix (file:line), the before/after probe output, what you
  did NOT change and why, and any remaining limitation (be honest about what you
  could not verify headless -- you cannot inspect a render).
