# Lane C smoke test - item data naming + reference integrity (read-only)

Scope: `game/data/items/` (8 `.tres` files), read on 2026-11-06. No `game/`
data or code was modified.

## 1. File inventory and id prefixes

| File | Declared `id` | Prefix |
|------|---------------|--------|
| `item_ancient_coin.tres` | `item_ancient_coin` | `item_` |
| `item_quest_gull_feather_seal.tres` | `item_quest_gull_feather_seal` | `item_quest_` |
| `item_quest_sealed_writ.tres` | `item_quest_sealed_writ` | `item_quest_` |
| `item_scrap_lumber.tres` | `item_scrap_lumber` | `item_` |
| `item_sealed_crate.tres` | `item_sealed_crate` | `item_` |
| `item_skiff_ticket.tres` | `item_skiff_ticket` | `item_` |
| `item_soulbind_ticket.tres` | `item_soulbind_ticket` | `item_` |
| `item_strait_charm.tres` | `item_strait_charm` | `item_` |

**File count: 8.**

Prefixes observed: `item_` (6 files) and `item_quest_` (2 files). Both
are documented styles in `AGENTS.md` ("Misc items (data/items) | `item_`
prefix" and "Quest items | `item_quest_` prefix"). Note the quest items
live in `game/data/items/`, not a separate folder; the `item_quest_`
prefix is what marks them (`is_quest_item = true` is set in both).

## 2. Filename == id check

All 8 filenames equal their declared `id` value. **Zero violations.**

## 3. Reference spot-checks

Item fields that carry another id (`quest_id`, `icon_path`) were checked,
plus the reverse direction (loot tables that name these items).

### quest_id (3 declared)

| Item | `quest_id` | Target file | Result |
|------|-----------|-------------|--------|
| `item_quest_gull_feather_seal` | `quest_wolves_hunt` | `game/data/quests/quest_wolves_hunt.tres` | exists |
| `item_quest_sealed_writ` | `quest_herb_gathering` | `game/data/quests/quest_herb_gathering.tres` | exists |
| `item_sealed_crate` | `quest_shoal_freight` | `game/data/quests/quest_shoal_freight.tres` | exists |

**No dangling quest references.**

### icon_path (8 declared)

All 8 `icon_path` values resolve to a real file under `game/icons/items/`
(`coin_ancient.png`, `seal_feather.png`, `sealed_writ.png`,
`scrap_lumber.png`, `sealed_crate.png`, `skiff_ticket.png`,
`ticket_soulbind.png`, `strait_charm.png`). **Zero missing icons.**

### Reverse refs (loot tables naming these items)

`game/data/loot_tables/*.tres` reference `item_ancient_coin` in 7 tables
(`loot_black_market_depths`, `loot_black_market_tide`, `loot_coast_bounty`,
`loot_sky_crate_daily`, `loot_slime`, `loot_wolf`, `loot_bandit`). All
resolve to the file that exists. The other 7 items are referenced from
quest/vendor/service code, not loot tables.

## 4. Findings

- **filename != id violations: none.**
- **Dangling references: none.** Every `quest_id` and every `icon_path`
  declared in `game/data/items/` points at something that exists.

### Soft observations (not violations, no fix applied)

- **Semantic mismatch on 2 quest items.** `item_quest_gull_feather_seal`
  declares `quest_id = "quest_wolves_hunt"`, but that quest's only
  objective is KILL `"Wolf"` (count 10) - the seal is not a quest
  objective target. `item_quest_sealed_writ` declares
  `quest_id = "quest_herb_gathering"`, whose COLLECT objective targets
  `"Moonpetal Flower"`, not the writ. `item_sealed_crate` is the one that
  lines up: `quest_shoal_freight` COLLECTs `"Sealed Crate"`, matching its
  `display_name`. The `quest_id` field only asserts an owning quest, and
  all three owning quests exist, so this is a data-semantics question for
  the designers - not a broken reference.
- **One item is unreferenced by any other data/code file:**
  `item_quest_gull_feather_seal` (0 hits outside its own `.tres`). It may
  be intended content not yet wired to a quest, or a leftover. Left as-is;
  read-only audit.

## Method

- Listed `game/data/items/` and dumped all 8 `.tres` files.
- Compared each file's `id` field against its filename.
- Resolved each declared `quest_id` against `game/data/quests/*.tres`.
- Resolved each `icon_path` against the filesystem.
- Cross-checked loot-table `item_id` entries for a reverse reference.
- `game/core/schemas/item.gd` was read to confirm `quest_id` is the
  owning-quest field (line 123: `@export var quest_id: String = ""`).

No files under `game/` were modified; no tests were run.
