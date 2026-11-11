You are a Synmergia subagent lane (Lane K: content .tres -- fill the world's shelves). Work ONLY inside your own worktree (your cwd). Never edit /workspace/project/synmergia directly.

FIRST, run the lane setup (idempotent -- warms the Godot import cache a fresh worktree lacks):
  sh labs/lane_setup.sh

Godot is NOT on PATH by default. Use it via:
  export PATH=/workspace/.tools/godot:$PATH
  godot --version   # expect 4.7.2.stable

CONTEXT
- Synmergia is a Godot 4.7.2 MMORPG. Static content is authored as .tres
  resources under game/data/<family>/. The data-naming law is enforced by
  game/tests/test_data_naming_lint.gd -- READ IT FIRST; it is the gate.
- The world voice is the "no engines / no electronics / no religion / no
  recorded history" law (labs/prd-story.md, labs/prd-psy.md, and the
  no-technology law in labs/prd-ancient-movers.md). Synmergia is an
  UNPOWERED world: everything is salvage, repair, or growth. There are no
  engines, no fuel, no manufacturing. Copy must stay inside that voice --
  woken, mended, grown, salvaged; never "tech", never "magic", never gods.
- The web Codex (src/pages/CodexPage.tsx + src/lib/codex.ts) reads a
  generated snapshot (src/data/godot_data.json) of game/data/*. New .tres in
  a synced family appear in the Codex on the next sync -- so keep
  display_name/description clean (they are the public face of the entry).

GOAL (author real content -- data only)
Fill the world's shelves with a coherent, NON-duplicative set of new
game/data/*.tres so the economy and the Codex have more to stand on. Author
in the established voice and the established material ladder. Target roughly
35-55 new files TOTAL across these families, weighted to what the world
already references:

1. game/data/resources/  -- gathering materials that FEED existing recipes
   and loot tables. New ores/grits/fibers/pearls/ingots in the established
   ladder (iron -> golden -> silver -> mythril -> starmetal), plus junker /
   salvage mats (the black-market + junker-scrip economy). id prefix `res_`,
   filename == id, item_category = 4 (RESOURCE), stack_size 100.
2. game/data/items/  -- misc goods + quest tokens. id prefix `item_` (misc)
   or `item_quest_` (quest items, set is_quest_item = true and a resolvable
   quest_id). item_category 7 (MISC) / 8 (DWELLING) as fits.
3. game/data/consumables/  -- potions / elixirs / teas tied to EXISTING
   resources (mooncap, moonpetal, kelp fiber, herbs). id prefix `potion_`
   or a bare name (elixir_ironblood, tea_mooncap_steep already exist -- do
   NOT duplicate them). item_category = 3 (CONSUMABLE), give buff_effects.
4. game/data/weapons/ + armors/ + accessories/  -- a tier or two more in the
   ladder (wep_/arm_/acc_ prefixes, filename == id). Give real stats that fit
   the material. Do not shadow existing ids.
5. game/data/recipes/  -- a recipe for most new craftable gear, station from
   RecipeData.Station (NONE/FORGE/WORKBENCH/ALCHEMY), inputs/output/
   byproducts. id prefix `recipe_`, filename == id. EVERY item_id referenced
   in inputs/output/byproducts MUST resolve to an existing or newly-authored
   .tres id in game/data (weapons/armors/accessories/resources/consumables).
6. game/data/loot_tables/  -- extend an existing table OR add one, but every
   entry.item_id MUST resolve. id prefix `loot_`, filename == id.
7. game/data/quests/  -- author 4-6 new quests wired to EXISTING npcs
   (giver_npc_id / turn_in_npc_id must name a real game/data/npc/*.tres id),
   and REGISTER each in the matching game/data/npc_offerings/*.tres
   (add the quest id to that offering's quest_ids array). Objectives must
   resolve against the catalog their bridge reads: KILL -> an enemy
   display_name (game/data/enemies), COLLECT -> an item display_name,
   TALK -> an npc id, EXPLORE -> a zone id. id prefix `quest_`,
   filename == id.

DO NOT author any `ancient_` mover/gate data. The ancient movers are a
designed, gated system (labs/prd-ancient-movers.md) with ZERO data today by
design -- fabricating them would break the mystery gate. Stick to concrete,
non-mystery content.

HARD RULES
- ASCII only. NO smart quotes / em-dashes in new files (the repo already has
  some; do not add more -- it causes Godot import issues).
- .tres files use 4-SPACE indentation (match the existing files). TABS are
  for .gd source only -- a .tres with tabs still parses, but match the
  neighbors.
- Filename == id for every prefixed family. ids unique across the whole repo
  (grep before you name).
- Every cross-reference resolves: recipe inputs/output/byproducts, loot
  entry.item_id, quest giver/turn_in/objective targets, offering quest_ids.
- Do NOT edit any .gd code, any existing .tres, the runner DEFAULT_SET,
  AGENTS.md, labs/TASKS.md, labs/lanes/*, or src/data/godot_data.json (the
  parent owns the generated JSON -- do not run sync:data).
- Do NOT run the full test runner (scripts/godot_test_runner.sh) -- it is
  being reworked. The ONE gate you must run is the naming lint below.

THE GATE (must stay green)
  export PATH=/workspace/.tools/godot:$PATH
  cd game
  godot --headless --path . --script res://tests/test_data_naming_lint.gd  > /tmp/k_lint.log 2>&1; echo "exit $?"
  tail -5 /tmp/k_lint.log
At the parent HEAD this reports a clean pass (0 failed). It MUST still be
0 failed after your work. If a NEW failure is a real defect you introduced,
fix it. If it exposes a PRE-EXISTING defect, report it -- do not silently
change unrelated files.

OPTIONAL SECOND CHECK (if quick): confirm every loot/recipe item_id you
touched resolves, e.g.
  grep -rhoE '"item_id": "[a-z0-9_]+"' game/data/recipes game/data/loot_tables \
    | sed -E 's/.*"item_id": "([a-z0-9_]+)".*/\1/' | sort -u \
    | while read i; do ls game/data/*/"$i".tres >/dev/null 2>&1 || echo "MISSING $i"; done

DEFINITION OF DONE
- The new .tres files exist, are coherent and in-voice, and every
  cross-reference resolves.
- `test_data_naming_lint.gd` still exits 0 with 0 failed.
- Commit in YOUR worktree with a message starting `lane-K:`.
- Report: the exact list of files added (grouped by family), the lint result
  (pass count), the new ids a reviewer should spot-check, and anything you
  deliberately did NOT do (and why). Be honest about anything you could not
  verify headless.
