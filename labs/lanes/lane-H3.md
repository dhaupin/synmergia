You are Lane H (RE-USED -- you authored the terrain spawn-ground fix and the
-47% math-first perf pass; both are harvested and live). This round is the
terrain CORRECTNESS round: fix the documented OPEN DEFECT (b), the face-16
vertex-mesh corruption. A correct, deterministic mesh matters more than speed.

FIRST, run the lane setup (idempotent -- warms the Godot import cache a fresh
worktree lacks): sh labs/lane_setup.sh

STEP 0 (get to a clean, current base -- your worktree may be stale):
  git fetch origin 2>/dev/null || true
  git reset --hard origin/staging
  git log --oneline -1        # record the base hash in your report
  git status --short          # expect clean

CONTEXT (the defect, verbatim from labs/TASKS.md ~9537)
- The spawn direction sits ON a 5-face icosa vertex: face_for_direction(spawn)
  = 16 but face_for_position(spawn) = 18 (the HUD's own mesh:f16 tag names the
  player face).
- Face 16's patch verts read ~2791.66 m MEAN off-law at BOTH levels (corner
  samples drawn_h -4569.3 / -2065.3 / -2067.4 vs law -3/-4/-8 m).
- The lvl-6 spawn-face (18) patch drifts +8.95/-9.25 m (the web player's own
  lane), and 2 km east legs enter face-16 territory and read +18.7/+34.4 or no
  law-containable land tile.
- The corner-derivation LAW itself is EXACT (face 18 lvl-7 surface-0 law-delta
  0.00; faces 14/6 coarse 0.00) and BOTH corruption signatures are byte-
  identical across reruns (determinism holds; the warm ring preserves the
  product), so the fill error is IN the face-16 / lvl-6 vertex pass.
- The prior round's own lead: hook `_mesh_cache_stash` / `_mesh_cache_stock` /
  `_hot_reload` / `_apply_derived_mesh` with per-build transform + first-corner
  prints to catch the corrupt lane red-handed.

THE TASK
1. REPRODUCE deterministically: run the ground-law audit + a small probe that
   builds the face-16 patch and prints, per build: the face id, the patch
   transform (origin/basis/scale), the first few corner (dir -> drawn_h vs law)
   rows, and the cache path taken (stash/stock/hot-reload/derive). Commit the
   probe (tests/tmp_* is fine for scratch; keep the real receipt if you add one).
2. DIAGNOSE the exact corruption: is it a wrong transform (scale/rotation), a
   vertex index/paren mapping (the face_for_direction vs face_for_position
   paren law named in TASKS ~9568), a stale warm-ring entry, or a straddle
   where the patch's corners fall on the wrong side of a 5-face vertex seam?
   State the root cause in one sentence with the evidence.
3. FIX it -- the smallest honest change that makes the drawn mesh match the walk
   law on face 16 (and the lvl-6 spawn face) WITHOUT changing the walk law or
   the analytic field values. If the fix is a seam/owner rule (which face owns a
   vertex), keep it deterministic.
4. GUARDRAILS (all must hold after): probe_ground_law_audit ALL PASS with the
   face-16 anchors now within the 6 m walk bound; probe_terrain_planet 43 checks
   PASS; test_terrain_determinism byte-stable; probe_walk_mesh_gap PASS;
   probe_perf_budget still PASS (do not regress your -47%).

RULES: tabs in .gd, ASCII only; do NOT edit scripts/godot_test_runner.sh,
AGENTS.md, labs/TASKS.md, labs/lanes/*, src/data/godot_data.json; do NOT run the
full runner. Do NOT change the walk law or any analytic field VALUE -- only the
mesh fill/transform. Commit EARLY and OFTEN; message prefix `lane-H3:`.

DONE = the face-16 / lvl-6 corruption fixed (or an honest "root-caused, here is
the exact cause + the blocked fix"), guardrails green, and a report with the
before/after anchor numbers.

Co-authored-by: openhands <openhands@all-hands.dev>
