RESUME -- your last run died on an infra 503 (OpenAIError: Service Temporarily
Unavailable) mid-investigation. NOTHING of yours was committed last run, so this
round we commit EARLY and OFTEN so a crash cannot lose the work.

STEP 0 (do this first): get to a clean, known base.
  git status --short          # expect nothing or only stray temp files
  git stash -u 2>/dev/null || true   # park any stray edits from the crashed run
  git log --oneline -1        # record the base hash in your report
  rm -f game/tests/tmp_h2_*.gd   # drop any temp probe the crash left behind
  (If `git status` shows real edits you want to keep, inspect them first -- but
  the crashed run committed nothing, so a clean base is almost certainly right.)

Same goal as the brief above (lane-H2: the math-first terrain performance pass),
but run it in SMALL, COMMITTED, MEASURED slices:

SLICE 0 (do this first, then commit): establish the baseline numbers.
  cd game
  godot --headless --path . --script res://tests/probe_world_boot_speed.gd  > /tmp/h2_boot.log 2>&1; echo "exit $?"
  godot --headless --path . --script res://tests/probe_perf_budget.gd       > /tmp/h2_budget.log 2>&1; echo "exit $?"
  godot --headless --path . --script res://tests/probe_terrain_planet.gd    > /tmp/h2_planet.log 2>&1; echo "exit $?"
  godot --headless --path . --script res://tests/probe_ground_law_audit.gd  > /tmp/h2_audit.log 2>&1; echo "exit $?"
  Record the numbers in a file `labs/h2-perf-ledger.md` (metric | before | after
  columns, after left blank for now). COMMIT that file immediately:
  git add labs/h2-perf-ledger.md && git commit -m "lane-H2: baseline perf ledger"

SLICE 1..N: for EACH optimization, one at a time:
  a) make the change,
  b) re-run the probes, fill the "after" column,
  c) confirm the guardrails (spawn-ground truth + draw-vs-law deltas within the
     6 m bound + test_terrain_determinism still byte-stable),
  d) COMMIT with a `lane-H2:` message describing the one change + its numbers.
  If a change does NOT beat the baseline, REVERT it and record "rejected, why"
  in the ledger -- do not keep an unmeasured or losing change.

Priority order (highest expected win first -- but MEASURE, do not assume):
  1. Redundant heightfield/gradient/slope math on the worker lanes -- fuse
     duplicate passes (the Corner-fusion/SectorCache precedent).
  2. Allocation churn in the per-tile build (SurfaceTool, temp Array/Dictionary,
     PackedVector3Array rebuilds) -- reuse buffers where the law allows.
  3. Web/wasm LOD + budget knobs (resident tiles, near-band tessellation,
     quantized-key hashing cost).
  4. Anything else the numbers point at.

RULES (unchanged): tabs in .gd, ASCII only; do NOT edit the runner DEFAULT_SET,
AGENTS.md, labs/TASKS.md, labs/lanes/*, src/data/godot_data.json; do NOT run the
full runner. Do NOT change the drawn surface height or the walk law.

DONE = at least ONE committed, measured win (or an honest "measured, no win, here
is the evidence"), the ledger filled, guardrails green, and a final report with
the before/after table. Commit incrementally so a crash never loses a slice.

Co-authored-by: openhands <openhands@all-hands.dev>
