You are Lane K (RE-USED -- you authored the 57-file content fill last round; it
is harvested and live). This round is the CLEANUP + BASELINE pass: make the data
layer a clean, consistent, parseable example the open-source world can model on.

Work ONLY inside your own worktree (your cwd). Never edit
/workspace/project/synmergia directly. Your worktree is already reset onto the
current staging HEAD (the harvested content is in it).

FIRST, run the lane setup (idempotent):
  sh labs/lane_setup.sh

Godot is NOT on PATH by default:
  export PATH=/workspace/.tools/godot:$PATH
  godot --version   # expect 4.7.2.stable

CONTEXT
- Synmergia is a Godot 4.7.2 MMORPG. Static content is authored as .tres under
  game/data/<family>/. There are ~722 .tres across 47 families today.
- The data-naming law is game/tests/test_data_naming_lint.gd -- READ IT FIRST.
  It is the gate. At your HEAD it reports "30 passed, 0 failed".
- THE REPO IS GOING OPEN SOURCE. Your headline deliverable is not a pile of
  edits -- it is the BASELINE: the written, checkable rules + the clean example
  set that an outside contributor copies. Data hygiene is the first thing a
  contributor touches, so it is the first thing that must be exemplary.

GOAL -- button up the data layer completely, and write the baseline
1. SYNTAX + FORMAT PARITY. Every .tres must be:
   - `[gd_resource type="Resource" script_class="X" load_steps=2 format=3]`
   - 4-SPACE indent (never tabs), ASCII only (no smart quotes, em-dashes, emoji)
   - `script = ExtResource("1")` as the first field in `[resource]`
   - fields in the SAME ORDER as the schema exports them
   Find every file that drifts and fix it. Report the count of files fixed.

2. SCHEMA CONFORMANCE + DEAD/PHANTOM FIELD AUDIT. For each family:
   - read its schema in game/core/schemas/*.gd (the @export list)
   - find any field DECLARED in the schema but set in NO .tres of that family
     (a DEAD field -- either every file forgot it, or the schema is stale)
   - find any field SET in a .tres that the schema does NOT declare (a PHANTOM
     field -- it will silently drop on load)
   This is a REPORT (counts + the exact ids), not a mass edit -- fixing a dead
   field across 40 files is a judgement call, so surface it and fix only the
   unambiguous ones (a phantom field is always a bug: fix it or the schema).

3. FILL-INS -- finish the last new content, only where the world REFERENCES it.
   Do NOT invent new ids for their own sake. Author a .tres only when something
   live points at a name that resolves to nothing (a dangling ref), e.g.:
   - a class -> skill ref with no skill file
   - a loot_table entry.item_id with no item
   - a recipe input/output/byproduct with no item
   - a quest objective target with no matching display_name
   Author the minimum set to close real dangling refs, in voice and on the
   material ladder. Report each one you close (and each you deliberately leave).

4. CONSISTENCY + PARITY SWEEP. Report (and fix the safe ones):
   - display_name / description present on every user-facing .tres
   - rarity / item_level / required_level within sane bands for the tier
   - icon_path resolves to a real file (the lint checks some of these -- extend
     the check to any family it misses and report what it would have caught)
   - buy_price / sell_price sane relative to rarity (flag outliers)
   - a family that has a `_prefix` convention but a stray file that breaks it

5. INTEROP -- the web Codex reads a generated snapshot. Confirm your changes do
   not break the sync: run `npm run sync:data` in your worktree (the parent owns
   src/data/godot_data.json -- do NOT commit the regenerated JSON; just confirm
   the sync exits 0 and the category counts are unchanged-or-higher). Report the
   before/after counts for any family you touched.

6. THE BASELINE DOC (the headline deliverable): write
   `labs/data-authoring-baseline.md` -- a tight, example-led guide a stranger can
   follow to author a correct .tres: the file skeleton, the indent/ASCII/format
   rules, the id/filename law per family, the cross-reference rules, the schema
   list, and the gate command. It must be ACCURATE against this tree (cite the
   real file paths). This is what OSS contributors will be pointed at.

HARD RULES
- ASCII only. No smart quotes / em-dashes / emoji in any file you touch.
- .tres use 4-SPACE indent. .gd source uses TABS.
- Filename == id for every prefixed family. ids unique across the repo.
- Every cross-reference resolves.
- Do NOT edit .gd CODE (schemas are read-only to you -- report, do not change
  a schema), the runner DEFAULT_SET, AGENTS.md, labs/TASKS.md, labs/lanes/*, or
  src/data/godot_data.json.
- Do NOT run the full test runner (scripts/godot_test_runner.sh) -- it is being
  reworked to parallel.

THE GATE (must stay green)
  export PATH=/workspace/.tools/godot:$PATH
  cd game
  godot --headless --path . --script res://tests/test_data_naming_lint.gd > /tmp/k2_lint.log 2>&1; echo "exit $?"
  tail -3 /tmp/k2_lint.log
It MUST still report 0 failed. If your work exposes a PRE-EXISTING defect, report
it -- do not silently change unrelated files.

DEFINITION OF DONE
- Format/syntax parity achieved (or the exact remaining drift listed with why).
- Dead/phantom field audit reported with counts + ids.
- Dangling refs closed (or listed).
- `labs/data-authoring-baseline.md` written and accurate.
- `test_data_naming_lint.gd` exits 0, 0 failed.
- Commit in YOUR worktree with a message starting `lane-K2:`.
- Report: files fixed by category, the audit findings, the baseline doc path,
  the lint result, and anything you deliberately did NOT do (and why).

Co-authored-by: openhands <openhands@all-hands.dev>
