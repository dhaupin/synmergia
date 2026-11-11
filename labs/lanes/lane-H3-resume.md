RESUME -- your last run died on the infra 503 (OpenAIError: Service
Temporarily Unavailable) at 10:46:59. NOTHING of yours was committed, but your
worktree still holds your two UNCOMMITTED probe edits (probe_ground_law_audit.gd
+ probe_terrain_planet.gd) -- KEEP them and COMMIT EARLY AND OFTEN this round so
a crash cannot lose the work.

You are Lane H (RE-USED). This is the terrain CORRECTNESS round: the face-16
"vertex-mesh corruption" defect. You had already made a major reframe before the
crash -- start from it, do not re-derive:

YOUR REFRAME (from your own uncommitted probe comment)
- The spawn direction (lat 0 / lon 0 = (1,0,0)) is the MIDPOINT of the icosa
  EDGE between icosa vertices 8 and 10 -- NOT a "five-face icosahedral vertex".
- That edge is shared by exactly TWO faces: 16 and 18 (neighbours). Both mappers
  return 16 there (an exact dot tie, broken to the lower index by the argmax's
  strict `>`), so NO face is "wrong".
- Therefore the old ~2791.66 m face-16 "corruption" was very likely a
  DETACHED-SKIP MEASUREMENT ARTIFACT -- the probe read an out-of-tree/detached
  patch instead of the live streamed one. You added a DETACHED-SKIPS counter and
  a planet-wide MESH-LAW SWEEP (every active face's drawn main-surface verts vs
  the analytic law) to test exactly this.

FIRST:
  sh labs/lane_setup.sh
  git fetch origin 2>/dev/null || true
  git log --oneline -1        # record the base hash
  git status --short          # your 2 probe edits should still be here

THEN (finish the round):
1. Run your mesh-law sweep (probe_terrain_planet) and the ground-law audit
   (probe_ground_law_audit) with the drain fence you added. If every active
   face's verts ride the law (worst dev ~0, 0 bad) and the spawn-face anchors
   are now within the walk bound, the defect is a MEASUREMENT ARTIFACT --
   CLOSE it as such, honestly.
2. If the sweep lights up a face, that is the REAL corruption -- root-cause and
   fix the mesh fill/transform only (never the walk law, never an analytic
   field VALUE).
3. Commit EARLY (each step). Prefix `lane-H3:`.
4. Update labs/TASKS.md's OPEN DEFECT (b) entry with the resolution (artifact
   vs real fix) -- the parent will reconcile.

GUARDRAILS (must hold): probe_ground_law_audit ALL PASS; probe_terrain_planet
all checks PASS; test_terrain_determinism byte-stable; probe_walk_mesh_gap PASS;
probe_perf_budget still PASS.

RULES: tabs in .gd, ASCII only; do NOT edit scripts/godot_test_runner.sh,
AGENTS.md, labs/lanes/*, src/data/godot_data.json; do NOT run the full runner.
Do NOT change the walk law or any analytic field VALUE.

DONE = the face-16 defect resolved (artifact closed with evidence, or real fix),
guardrails green, TASKS note updated, and a report with before/after numbers.

Co-authored-by: openhands <openhands@all-hands.dev>
