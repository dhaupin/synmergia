RESUME -- your last run died on the infra 503 (OpenAIError: Service
Temporarily Unavailable) at 10:47:23. NOTHING was committed, but your worktree
is CLEAN (you had only done recon). COMMIT EARLY AND OFTEN this round so a crash
cannot lose the work.

You are Lane L (RE-USED): content .tres -- fill the world's gear shelves. The
repo is OPEN SOURCE; the content is the world an outside contributor reads.

FIRST:
  sh labs/lane_setup.sh
  git fetch origin 2>/dev/null || true
  git log --oneline -1        # record the base hash
  git status --short          # expect clean

RE-READ your brief labs/lanes/lane-L.md -- it is unchanged. The verified gaps:
1. ZERO class-locked gear: all 21 classes (game/data/classes/) exist, but EVERY
   equipment .tres sets required_class = "". Author signature class gear (one
   weapon + one armor per PLAYABLE class; exclude the 3 gm_* classes).
2. Missing enum items: no CROSSBOW (WeaponType 6), no WAND (8), no BRACELET
   (AccessoryType 3). Add >=1 each (or report which are intentionally absent).
3. Sparse item_level bands above 18 -> a coherent progression curve, each band
   with a real SOURCE (offering/loot).

NOTE (new since your last run -- another lane harvested + the parent fixed
things): the data baseline is now PHANTOM-CLEAN and the loot tables are guarded
by tests/test_loot_table_integrity.gd -- do NOT reintroduce a phantom field, and
if you add a loot table make sure every entry item_id resolves and currency goes
in currency_drops (not entries).

WIRE it (D): new items reachable through a real vendor offering
(game/data/npc_offerings/*.tres; type "vendor", sell_categories is item_category
int) or a loot table. Verify a class-locked item is actually purchasable -- if
the by_category vendor cannot sell a class-locked item, add a dedicated class
offering .tres or report the wiring gap honestly.

RULES: tabs in .gd, ASCII only, schema-export field order, filename == id,
category prefix ids (wep_/arm_/acc_), NO phantom fields. Do NOT edit
scripts/godot_test_runner.sh, AGENTS.md, labs/TASKS.md, labs/lanes/*,
src/data/godot_data.json; do NOT run the full runner. Commit EARLY. Prefix
`lane-L:`.

GUARDRAILS (green at the end): test_data_naming_lint 30+/0; test_item_catalog
pass; a load probe proving every new .tres loads + its id resolves.

DONE = the three gaps closed (or each honestly scoped), guardrails green, and a
report with files added + coverage before/after + how each item is reachable.

Co-authored-by: openhands <openhands@all-hands.dev>
