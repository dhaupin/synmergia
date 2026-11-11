You are Lane K (RE-USED -- you authored the 57-file content fill and the
417-file data baseline in the last two rounds; both are harvested and live).
This round CLOSES the baseline: resolve every PHANTOM field in game/data into a
clean, documented, consistent shape an open-source contributor can model on.
The repo is now public -- this is the baseline the world reads.

FIRST, run the lane setup (idempotent -- warms the Godot import cache a fresh
worktree lacks): sh labs/lane_setup.sh

STEP 0 (get to a clean, current base -- your worktree may be stale):
  git fetch origin 2>/dev/null || true
  git reset --hard origin/staging
  git log --oneline -1        # record the base hash in your report
  git status --short          # expect clean

CONTEXT
- Synmergia is a Godot 4.7.2 MMORPG (GDScript). Static content is authored as
  .tres under game/data/<family>/, each binding one schema from
  game/core/schemas/.
- You wrote labs/data-authoring-baseline.md (321 lines) -- READ IT FIRST. Its
  sec 3 states the law: a field you set that the schema does not declare is a
  PHANTOM; a field the schema declares that no file sets is DEAD. Both are bugs
  to report; fix the phantom, and only set a dead field where it is clearly
  correct.
- Last round you REPORTED (did not fix, correctly) the phantom set: the NPC
  trio (`npc_type` x17, `shop_title` x16, `services` x7 in game/data/npc/),
  `guards.description` x2, `containers.expansion_tiers` x1.

THE TASK: make game/data phantom-clean, honestly.
1. Build the AUTHORITATIVE phantom list: for each .tres family, diff the SET
   fields against the schema's @export fields (a phantom = set but not
   declared). Report the full list with counts.
2. For EACH phantom decide ONE of:
   a) The data intends a real feature the schema lacks -> ADD the @export field
      to the schema IN SCHEMA-EXPORT-ORDER with a sane default, and WIRE a real
      consumer if one is obviously needed. A declared field with no reader is
      wallpaper (the repo's no-void law) -- prefer removal if no consumer is
      real.
   b) The data line is vestigial -> REMOVE the phantom line from every file.
   Do NOT guess silently: record each decision + why in the baseline doc.
   GUIDANCE (verify, do not trust): npc_type/shop_title/services look like a
   merchant-NPC intent (npc_type 2=armory / 3=blacksmith; shop_title = the
   shop's name). There IS a BlacksmithNPC (game/core/entities/blacksmith_npc.gd)
   that builds a dict with "npc_type": 3. If you declare these, give them a real
   reader (the NPC tooltip / shop surface) or prefer removal. Choose the
   SMALLEST honest change.
3. (Stretch) Add a phantom-detector to the lint (game/tests/
   test_data_naming_lint.gd or a new fast receipt) that FAILS on a
   set-but-undeclared field, so the baseline stays clean. Keep it fast +
   deterministic.
4. Update labs/data-authoring-baseline.md with the resolved decisions and the
   "no phantoms" gate.

RULES: tabs in .gd, ASCII only; do NOT edit scripts/godot_test_runner.sh,
AGENTS.md, labs/TASKS.md, labs/lanes/*, src/data/godot_data.json; run only your
targeted gates. Commit EARLY and OFTEN (a crash must not lose work); message prefix
`lane-K3:`.

DONE = game/data phantom-clean (or every remaining one justified in the doc),
the naming lint green, the baseline doc updated, and a report with the
before/after phantom counts + each decision.

Co-authored-by: openhands <openhands@all-hands.dev>
