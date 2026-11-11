You are a Synmergia subagent lane (Lane L: content .tres -- fill the world's
remaining shelves). Work ONLY inside your own worktree (your cwd). Never edit
/workspace/project/synmergia directly. The repo is now OPEN SOURCE; the content
you author is the world an outside contributor reads.

FIRST, run the lane setup (idempotent -- warms the Godot import cache a fresh
worktree lacks, and links the gamestruct dep): sh labs/lane_setup.sh

STEP 0 (clean, current base):
  git fetch origin 2>/dev/null || true
  git reset --hard origin/staging
  git log --oneline -1        # record the base hash in your report
  git status --short          # expect clean

CONTEXT
- Synmergia is a Godot 4.7.2 MMORPG (GDScript). Static content is authored as
  .tres under game/data/<family>/, each binding one schema from
  game/core/schemas/. READ labs/data-authoring-baseline.md FIRST -- it is the
  written authoring law (file skeleton, schema-export field order, id naming,
  the no-phantom rule, the no-technology copy voice). The baseline was just
  closed (zero phantoms) -- do NOT reintroduce any.
- The live world is the spherical globe; the planar world is retired.
- No-technology copy law: Synmergia is unpowered -- say woken / mended / grown /
  salvaged; never tech, never magic, never gods. ASCII only (no em-dash / smart
  quotes -- the K2 round normalized the corpus; keep it ASCII).

THE GAP (verified on staging -- build on it, do not trust blindly)
1. ZERO class-locked gear. There are 21 classes in game/data/classes/
   (6 human, 6 akkan, 6 synthetic, 3 GM), but EVERY equipment .tres sets
   `required_class = ""`. Author signature gear so the world has class identity.
2. Missing enum values in game/data/weapons|armors|accessories: no CROSSBOW
   (WeaponType 6), no WAND (8), no BRACELET (AccessoryType 3). Give each enum
   value at least one item (or report which are intentionally absent).
3. Sparse level bands above item_level 18 (a couple of outliers at 40/55). The
   mid/high tiers have no coherent progression.

THE TASK
A. CLASS GEAR: for each PLAYABLE class (exclude the 3 GM classes), author at
   least one signature weapon and one signature armor piece with
   `required_class` = the class id, an item_level/rarity that fits the class's
   tier, and honest class-flavored copy. Keep the stat blocks consistent with
   neighbours in the same family.
B. MISSING TYPES: add >=1 item for CROSSBOW, WAND, and BRACELET (and any other
   enum value with zero items you find), with correct weapon_type/armor_type/
   accessory_type + equip_slot.
C. LEVEL BANDS: extend the equipment curve so item_level bands above 18 are
   continuous, each band having a real SOURCE (the armory/general-store
   offerings sell by category, so new items auto-appear; verify a class-locked
   item is actually purchasable -- if the by_category vendor cannot sell a
   class-locked item, either add a dedicated class offering .tres or report the
   wiring gap honestly). Higher tiers should also ride a loot_table where that
   is the natural source.
D. WIRE it: new items reachable through a real vendor offering or loot table
   (not orphaned files). Follow the existing offering shape
   (game/data/npc_offerings/*.tres) and loot shape (game/data/loot_tables/).

RULES
- tabs in .gd, ASCII only, schema-export field order, filename == id, category
  prefix ids (wep_/arm_/acc_), NO phantom fields.
- Do NOT edit scripts/godot_test_runner.sh, AGENTS.md, labs/TASKS.md,
  labs/lanes/*, src/data/godot_data.json; run only your targeted gates.
- Commit EARLY and OFTEN (a crash must not lose work); message prefix `lane-L:`.

GUARDRAILS (must be green at the end)
- `godot --headless --path game --script res://tests/test_data_naming_lint.gd`
  -> 30+ passed, 0 failed (it checks refs; your new files must resolve).
- `godot --headless --path game --script res://tests/test_item_catalog.gd`
  -> pass.
- A load probe proving every new .tres loads and its id resolves.

DONE = the three gaps closed (or each honestly scoped + reported), guardrails
green, and a report with the exact files added, the class/type/level coverage
before vs after, and how each new item is reachable in-game.

Co-authored-by: openhands <openhands@all-hands.dev>
