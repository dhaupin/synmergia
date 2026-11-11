You are Lane H (RE-USED -- you authored the terrain spawn-ground fix last round;
it is harvested and live). This round is the MATH-FIRST, PERFORMANCE + WEB
EFFICIENCY pass on the terrain and rendering world.

Work ONLY inside your own worktree (your cwd). Never edit
/workspace/project/synmergia directly. Your worktree is already reset onto the
current staging HEAD (your terrain fix is in it).

FIRST, run the lane setup (idempotent):
  sh labs/lane_setup.sh

Godot is NOT on PATH by default:
  export PATH=/workspace/.tools/godot:$PATH
  godot --version   # expect 4.7.2.stable

CONTEXT -- THE DIRECTION
- Synmergia is a Godot 4.7.2 MMORPG on a 20 km procedural globe, browser-first
  (wasm) plus desktop. The terrain is a streamed icosahedral tile grid
  (game/scenes/worlds/globe_terrain_streamer.gd, ~186 KB) displaced by an
  ANALYTIC heightfield (game/scenes/worlds/terrain_gen.gd, ~120 KB). The walk
  surface and the draw mesh ride the SAME analytic law.
- THE WORLD IS MOVING TO MATH. The owner's steer: the analytic field is the
  truth; the mesh, the collision, and the physics should DERIVE from it with the
  least possible work, on the weakest target (a phone browser). "The math is good
  but we can do better" -- this lane pioneers that, and it is the reference OSS
  will study.
- Prior perf work (read it, do not re-derive): labs/prd-terrain.md and the perf
  ledger entries in labs/TASKS.md (search "ready-wall", "perf ledger",
  "Corner fusion", "SectorCache", "splat"). The last measured numbers:
  ready-wall ~1.9 s mount / 2.6 s dressing; hot build 9.35 s; sweep 32.5 s.

THE FUNCTIONAL GOAL (prove it, do not assert it)
Reduce the cost of building + maintaining the streamed world on the WEAKEST
target, WITHOUT changing the drawn surface or the walk law (a visual/behaviour
regression is a failure, not a tradeoff). Concretely, look for and fix:

1. REDUNDANT MATH. The heightfield / gradient / normal / slope is computed more
   than once per unique corner or per frame. Find the duplicate passes (the
   fused-sweep pattern is the precedent) and fuse them. Measure the call count
   before/after.

2. ALLOCATION CHURN. Per-frame Array/Dictionary/PackedVector3Array rebuilds,
   SurfaceTool churn, per-tile temp objects. The worker lanes are the hot path.
   Reduce steady-state allocation (reuse buffers where the law allows).

3. THE WEB CLIENT SPECIFICALLY. wasm has no threads by default and a tighter
   heap. Look at: the LOD schedule (does the near band over-tessellate on a
   phone?), the quantized-key math (Vector3 dict keys -- are they hash-heavy?),
   the number of tiles resident, and the per-tile triangle budget. Report the
   wasm-relevant knobs and the measured effect.

4. DETERMINISM + CRACKS. Any optimization must keep: (a) adjacent patches
   welding vertex-for-vertex (your last round's geodesic-midpoint law), and
   (b) seed-stable, byte-identical output for a given seed. Prove both with the
   existing probes.

MEASUREMENT (the receipt -- this is the deliverable, not vibes)
- Establish a BASELINE first, on your HEAD, with the existing probes:
    cd game
    godot --headless --path . --script res://tests/probe_terrain_planet.gd     > /tmp/h2_planet.log 2>&1; echo "exit $?"
    godot --headless --path . --script res://tests/probe_ground_law_audit.gd   > /tmp/h2_audit.log 2>&1; echo "exit $?"
    godot --headless --path . --script res://tests/probe_world_boot_speed.gd   > /tmp/h2_boot.log 2>&1; echo "exit $?"
    godot --headless --path . --script res://tests/probe_perf_budget.gd        > /tmp/h2_budget.log 2>&1; echo "exit $?"
  The perf-relevant probes already in the tree: probe_world_boot_speed,
  probe_perf_budget, bench_coldboot_wall, bench_coldboot_hose,
  probe_stream_flow_100m, probe_stream_continent_{a,b,c,d},
  test_terrain_determinism, test_lod_predictor. USE THEM -- they are the ledger.
  (probe_ground_law_audit prints a shutdown segfault AFTER its PASS line -- that
  is a teardown artifact, not a failure; read the PASS/FAIL lines.)
- Then measure AFTER each change. Report a small table: metric, before, after.
- If a metric cannot be measured headless, SAY SO -- do not claim a win you did
  not measure. (The honesty law: an unmeasured optimization is a hypothesis.)

GUARDRAILS
- Do NOT change the drawn surface height or the walk law. The probes' draw-vs-law
  deltas (the 6 m walk bound) must stay green.
- Do NOT change the visual palette / tint law unless it is purely a perf win with
  identical output.
- Keep tabs in .gd, ASCII only.
- Do NOT edit the runner DEFAULT_SET, AGENTS.md, labs/TASKS.md, labs/lanes/*, or
  src/data/godot_data.json.
- Do NOT run the full test runner (scripts/godot_test_runner.sh) -- reworked to
  parallel.

DEFINITION OF DONE
- A measured before/after table for every optimization (or an honest "no win,
  here is why" for the ones you tried and rejected).
- The existing terrain probes still PASS (draw-vs-law deltas within bound;
  spawn-ground truth holds).
- Any new receipt probe you add is registered in the runner DEFAULT_SET only if
  you also add it in the PARENT (you cannot -- so list it in your report for the
  parent to register).
- Commit in YOUR worktree with a message starting `lane-H2:`.
- Report: the baseline numbers, the after numbers, the changes, the probes run,
  and the knobs an OSS contributor should tune per target.

Co-authored-by: openhands <openhands@all-hands.dev>
