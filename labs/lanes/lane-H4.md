You are a Synmergia subagent lane (Lane H: terrain -- RE-USED for the floating-structure rendering fix). Work ONLY inside your own worktree (your cwd). Never edit /workspace/project/synmergia directly.

FIRST, run the lane setup (idempotent -- warms the Godot import cache a fresh worktree lacks, and links the gamestruct dep):
  sh labs/lane_setup.sh

Godot is NOT on PATH. Use it via:
  export PATH=/workspace/.tools/godot:$PATH
  godot --version   # expect 4.7.2.stable

CONTEXT
- Synmergia is a Godot 4.7.2 MMORPG. The world is a 20 km sphere; the ground is an analytic heightfield law `TerrainGen.terrain_height(dir, seed)` in game/scenes/worlds/terrain_gen.gd. The streamer game/scenes/worlds/globe_terrain_streamer.gd renders it as LOD patches (each icosa face -> a MeshInstance3D built at a LOD level). The walk pad AND every authored structure ride the ANALYTIC law; the RENDERED mesh is a DISCRETE LOD sample of the same law.
- THE BUG (the owner's live report, verbatim): "houses float, they settle closer to the ground as you approach, jumpy in bands."
- THE DIAGNOSIS (already measured by the parent -- trust these numbers, but re-verify if useful): the mesh VERTICES sit ON the law (uniform +0.52 m = TILE_LIFT -- invisible), but the flat TRIANGLES span BELOW it between vertices. Measured mid-triangle (centroid) chord sag vs the analytic law on the home continent: **level-5 faces -23.4 m / -87.3 m; level-7 faces -120.3 m / -149.4 m**. The walk pad + structures ride the law, so on those triangles the ground DRAWS below where you stand -> a house seated on the law reads as FLOATING above the drawn ground. The "jumpy in bands" is the LOD level flip: a face rides `base` (level 7) inside the near band, else `LOD_FLOOR_LEVEL` (5); as you approach, the face flips 5 -> 7 and the sag snaps from ~-87 m to ~-23 m, so the visible gap closes in discrete BANDS (hysteresis + LOD_FAR_TICKS make it pop, not glide).
- This is a MESH-RESOLUTION problem on the steepest ground, NOT a walk-law bug. Do NOT change the walk law (the player must keep standing on the analytic law -- probe_ground_law_audit pins that).

TASK
Fix the floating-structure rendering so authored structures (the starter village + capitol monolith: game/entities/starter_village.gd, game/entities/village_props.gd, game/entities/capitol_monolith.gd; seated in game/scenes/worlds/globe_world.gd) sit on the DRAWN surface the player sees, and the visible gap closes SMOOTHLY as you approach (no band pops).

Candidate approaches (pick by MEASUREMENT; keep the triangle budget sane):
  (a) LOCAL ANALYTIC GROUND PATCH: build/keep a high-resolution patch (or a small dedicated mesh) under the local player + near structures that follows the analytic law exactly, so what the player sees underfoot IS the law. (This also helps the walk feel.) This is likely the best fit given the streaming architecture.
  (b) LOCAL REFINEMENT on steep slopes: refine the mesh where the chord sag exceeds a bound (e.g. > 4 m), so the drawn surface tracks the law where it matters.
  (c) SEAT structures on the DRAWN mesh (read the containing triangle's interpolated height) instead of the analytic law. CAVEAT: the player must still stand on the analytic law, so if you do this the mesh must meet the law near the structure (or the player floats/sinks). Only pick this if it is clean.
  (d) Raise the far floor / near base -- likely too costly (the floor dropped to 5 for triangle budget); only if measurement says it is cheap.
Deliverable: no visible floating at the boot village/capitol, and the gap closes smoothly (no band pop) on approach. Report the before/after chord-sag numbers.

CONSTRAINTS (avoid file collisions with the parent lane)
- The PARENT owns game/scenes/worlds/terrain_gen.gd this round (it is adding polar landmasses + a floating-island field). Do NOT edit terrain_gen.gd -- read it freely.
- Do NOT edit game/data/worlds/*.tres, labs/TASKS.md, AGENTS.md, labs/lanes/*, or the runner DEFAULT_SET.
- YOUR files: game/scenes/worlds/globe_terrain_streamer.gd, game/scenes/worlds/globe_world.gd, game/entities/*.gd (structure seating), and a NEW probe game/tests/probe_<name>.gd.

THE GATE (must stay green)
  export PATH=/workspace/.tools/godot:$PATH
  cd game
  godot --headless --path . --script res://tests/probe_ground_law_audit.gd > /tmp/h4_audit.log 2>&1; echo "exit $?"; tail -5 /tmp/h4_audit.log
  godot --headless --path . --script res://tests/probe_starter_village.gd > /tmp/h4_village.log 2>&1; echo "exit $?"; tail -5 /tmp/h4_village.log
Write a NEW probe (game/tests/probe_<name>.gd) that measures the mid-triangle chord sag at the boot + on the approach, asserts it stays under a tight bound, and (if you changed seating) asserts structures sit within a small tolerance of the DRAWN surface. It MUST exit 0. Model it on game/tests/probe_ground_law_audit.gd (drain the derive lane before quitting -- the shutdown-fence law).

DEFINITION OF DONE
- The float is fixed (structures sit on the drawn ground; the gap closes smoothly).
- probe_ground_law_audit + probe_starter_village still ALL PASS; your new probe exits 0.
- Perf sane: report patch_count() / mesh_lane_stats() before/after.
- Commit in YOUR worktree with a message starting `lane-H4:`.
- Report: what you changed + why, the before/after chord-sag numbers, the probe results, and anything you could NOT verify headless. Be honest.
