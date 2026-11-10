# Lane C smoke test - world/data content audit + reference integrity (read-only)

Scope: `game/data/{quests,npc,npc_offerings,dialogues,zones,dwellings,loot_tables,
enemies,factions,gateways,guards,hordes,world_bosses,vehicles}`, audited 2026-11-10
against the LIVE spherical globe (`game/scenes/worlds/globe_world.gd`). No file
under `game/` was modified. The retired planar path
(`scenes/world_playable.{gd,tscn}` + `entities/player/player_controller.gd`,
deleted in commit `5e7416df`, per `labs/prd-planar-retirement.md:100`) is treated
as dead code; the question is which DATA it was the last reader of.

Lint result (point 4): `godot --headless --path game --script
res://tests/test_data_naming_lint.gd` -> **27 passed, 0 failed** (exit 0). Not a
defect. The lint does NOT cover every reference below (see section 3).

---

## 1. Data families referenced ONLY by the retired planar path, or by nothing at all

### 1a. THE SUNDERED-QUAY NPC CLUSTER (dead on the live globe)

The Shipwreck Quay slice is a self-consistent data island whose only live-world
consumer was the planar offering-NPC spawn. On the live globe it is never placed.

| File | Declared id | Live consumer found |
|------|-------------|---------------------|
| `data/npc/npc_ferryman_sundered.tres` | `npc_ferryman_sundered` | none outside the cluster + `tests/probe_shipwreck_quay.gd` |
| `data/npc/npc_salvor_wreck.tres` | `npc_salvor_wreck` | none outside the cluster + `tests/probe_shipwreck_quay.gd` |
| `data/dialogues/sundered_ferry_talk.tres` | `sundered_ferry_talk` | only `npc_ferryman_sundered.tres` |
| `data/dialogues/sundered_salvor_talk.tres` | `sundered_salvor_talk` | only `npc_salvor_wreck.tres` |
| `data/npc_offerings/ferry_dock_service.tres` | `ferry_dock_service` | only `npc_ferryman_sundered.tres` |
| `data/npc_offerings/ferry_passage_sundered.tres` | `ferry_passage_sundered` | only `npc_ferryman_sundered.tres` |
| `data/npc_offerings/salvor_stock.tres` | `salvor_stock` | only `npc_salvor_wreck.tres` |
| `data/npc_offerings/shoal_freight_quests.tres` | `shoal_freight_quests` | only the two sundered NPCs |
| `data/quests/quest_shoal_freight.tres` | `quest_shoal_freight` | offering + `item_sealed_crate.tres` (giver `npc_salvor_wreck`, turn-in `npc_ferryman_sundered`) |

Grep used (whole tree, sidecars excluded):

```
grep -rln -F '"npc_ferryman_sundered"' game/ --include="*.gd" --include="*.tres" --include="*.tscn"
  -> game/data/npc/npc_ferryman_sundered.tres
     game/data/dialogues/sundered_ferry_talk.tres
     game/data/quests/quest_shoal_freight.tres
     game/tests/probe_shipwreck_quay.gd
grep -rln -F '"npc_salvor_wreck"' ... -> the mirror set
```

Neither id appears in any live `.gd` or `.tscn` outside the probe. The only
placement path that ever existed is `SpawnService.spawn_all_offering_npcs()`
(`game/core/services/spawn_service.gd:1145`), reached from
`WorldService.initialize_world()` (`game/core/services/world_service.gd:116`),
reached from `GameManager._initialize_world_services()` (`game/core/autoload/game_manager.gd:165`).

**Empirical proof (realistic boot).** A temporary probe (deleted) drove the
production menu flow -- set `current_scene` to `character_select.tscn`, then
`GameManager.change_state(PLAYING)` -- and listed the live NPC roster after the
globe's boot waves settled:

```
LANEC2: live npc ids (17) = [npc_armory_capital, npc_banker_capital,
  npc_banker_village, npc_black_market_fixer, npc_blacksmith_capital,
  npc_blacksmith_village, npc_concord_herald, npc_elder_capital,
  npc_herbalist_capital, npc_herbalist_village, npc_jeweler_haven,
  npc_merchant_capital, npc_merchant_general, npc_skill_academy_capital,
  npc_skill_academy_village, npc_tidewright_fenwick, npc_village_elder]
```

`npc_ferryman_sundered` and `npc_salvor_wreck` are absent. The boot log shows
why: `spawn_all_offering_npcs` spawned 19 NPCs (17 town + the two sundered)
during the `CharacterSelect -> PLAYING` transition, i.e. into the
`CharacterSelect` scene; `GameManager._handle_playing_state` then swapped the
scene to `globe_world.tscn`, and the offering NPCs were parented to the OLD
scene (`spawn_service.gd:1104`, `tree.current_scene`), so the swap freed them.
The globe then re-spawns its own roster (`globe_world.gd:1665 _build_town_npcs`,
17 NPCs). The two sundered NPCs are in neither globe batch
(`VILLAGE_NPC_BATCH` `globe_world.gd:1629`, `CAPITOL_NPC_BATCH` `:1648`), so
nothing places them on the planet. `zone_sundered_sea.tres` itself is live (the
terrain streamer and the barque read it), but its two authored NPCs are not.

Caveat recorded honestly: in a probe where `current_scene == null` (not the
production path), the offering NPCs parented to the tree root, survived the
globe load, and produced 36 live NPCs with 17 duplicate ids. That is a
test-harness artifact of skipping the menu scene, not a live double-spawn: the
real menu flow yields 17 unique NPCs (the run above). No duplicate-entity error
is emitted on the production path.

### 1b. NPCs with no `zone_id` world match (also never placed)

`npc_deep_warden` (`zone_id = zone_deep_root_camp`, `world_id != "main"`) is
deliberately skipped by `spawn_all_offering_npcs` (`spawn_service.gd:1195`) and
placed instead by the underworld scene (`globe_underworld.gd:825`). It is LIVE,
not orphan.

### 1c. ORPHAN NPC-OFFERING files (no `ref_id` from any NPC or dialogue)

Every NPC offering is referenced by `ref_id` inside an NPCData `includes[]`
(`npc_entity.gd:86`, `globe_player.gd:1867`). Four offering files are named by
no NPC and no dialogue:

| File | Declared id | Consumers (grep) |
|------|-------------|------------------|
| `data/npc_offerings/village_quests.tres` | `village_quests` | none (its `quest_ids` are inlined on the NPCs instead) |
| `data/npc_offerings/village_elder_dialogue.tres` | `village_elder_dialogue` | none (the elder inlines `dialogue_id`) |
| `data/npc_offerings/forge_service.tres` | `forge_service` | none outside `tests/probe_crafting_ui.gd` |
| `data/npc_offerings/workbench_service.tres` | `workbench_service` | none outside `tests/probe_crafting_ui.gd` |

Grep used: `grep -rlF '"<id>"' game/data/npc/ game/data/dialogues/ game/core/
game/scenes/ game/entities/ game/ui/` returned nothing for all four.

### 1d. ORPHAN dwelling item

`data/dwellings/dwel_wooden_chair.tres` (`id = dwel_wooden_chair`,
`item_category = 7` DWELLING) is referenced by nothing:

```
for d in dwel_anvil_iron dwel_cauldron_brew dwel_fireplace_stone dwel_forge_coal
         dwel_wooden_chair dwel_workbench_oak; do
  grep -rln -F "\"$d\"" game/ --include="*.gd" --include="*.tres" --include="*.tscn"
done
  dwel_anvil_iron      -> tests/probe_placeable_stations.gd
  dwel_cauldron_brew   -> tests/probe_placeable_stations.gd
  dwel_fireplace_stone -> tests/probe_placeable_stations.gd
  dwel_forge_coal      -> tests/probe_placeable_stations.gd
  dwel_wooden_chair    -> <none>
  dwel_workbench_oak   -> tests/probe_placeable_stations.gd
```

The other five are placed through `DwellingService.place_station`
(`dwelling_service.gd:255`, resolving via `DataService.get_item`
`:269`). `dwel_wooden_chair` has no station function and is never placed.

### 1e. ORPHAN loot table

`data/loot_tables/loot_sky_crate_daily.tres` is read only by
`tests/probe_sky_crate.gd`. `grep -rn "loot_sky_crate_daily" game/` finds the
definition, the probe, and a `.godot` cache entry -- no live `.gd` reader. The
daily quest `quest_watch_the_sky.tres:17` grants `item_sky_crate_daily`
directly; nothing opens the crate through the table (the `Item` schema has no
`loot_table_id`/`open` field -- `grep -n "loot_table" game/core/schemas/item.gd`
is empty), so the table is authored but unwired.

### 1f. ORPHAN enemies (defined, loot-linked, but never spawned)

`EnemyData` templates are resolved by bare id via `DataService.get_enemy`
(`data_service.gd:394`) from: the globe wildlife batch (`globe_world.gd:115`
`GLOBE_ENEMY_BATCH`), hordes (`data/hordes/*.tres`), and world-boss schedules
(`data/world_bosses/*.tres`). Collecting every referenced bare id and diffing
against `data/enemies/`:

Actually SPAWNED (live): `wolf`, `thistle_boar`, `training_dummy` (globe
wildlife batch), `slime`/`bandit`/`troll_elite`/`void_lord` (horde configs),
`clockwork_saint`/`mossbound_herald`/`trench_sentinel` (world-boss schedules).

**No spawner anywhere**: `enemy_coast_pecker`, `enemy_field_hopper`,
`enemy_tusker_sow`, `enemy_salt_wretch`, `enemy_mirage_hound`,
`enemy_gull_nestmaw`, `enemy_gloam_polyp`, `enemy_gloam_whisp_moth`,
`enemy_depths_thornhide`, `enemy_drowned_custodian`, `enemy_tidebound_ancient`,
`enemy_rootmaw_brute`, `enemy_ledgewarden_construct`, plus `enemy_tidecursed_diver`
and `enemy_gloamwood_stalker`. The last two are named only by the seasonal pack's
`enemy_ids` (`data/content_packs/pack_tide_season.tres:10`), which is an
enable/disable GATE (`content_packs.gd:99` `pack_owning_enemy`), not a spawn
driver: `grep -rn "enemy_ids" game/ --include="*.gd"` (excluding tests) shows the
list is read only for gating and counts, never iterated to spawn. So all fifteen
have stat + loot authoring but no placement on any live map. Grep used:

```
grep -rn "coast_pecker|field_hopper|tusker_sow|salt_wretch|mirage_hound|
  gull_nestmaw|gloam_polyp|gloam_whisp|depths_thornhide|drowned_custodian|
  tidebound_ancient|rootmaw_brute|ledgewarden_construct" game/ --include="*.gd"
  -> (no output)
grep -rn "tidecursed_diver|gloamwood_stalker" game/ --include="*.gd" --include="*.tres"
  -> data/content_packs/pack_tide_season.tres (enemy_ids gate) + tests only
```

These are sea/meadow/deep enemies with full stat + loot authoring
(`loot_coast_bounty`, `loot_meadow_litter`, `loot_gloam_*`, `loot_sunken_salvage`,
`loot_trench_dream`, `loot_elite_ore`) but no placement on any live map. They
are candidates for the un-ported S14.7 "Sundered Sea content pass" noted in
`AGENTS.md`.

### 1g. Gateways referenced by nothing (still registered)

`WorldService._register_authored_gateways()` (`world_service.gd:857`) scans the
whole directory at boot, so every gateway is registered regardless of a literal
consumer. Three have no literal reference in live code/data:
`ankh_village_shrine` (gateway_type 0 = ANKH), `waypoint_nexus_central`,
`waypoint_shipwreck_quay` (only `tests/probe_shipwreck_quay.gd`).
`waypoint_island_dock` is referenced only by `veh_island_ferry.tres:21`, and
`veh_island_ferry` itself has no live `.gd` consumer (see 1h).

### 1h. ORPHAN vehicle

`data/vehicles/veh_island_ferry.tres` -- `grep -rln '"veh_island_ferry"' game/`
finds only its own file. The globe builds `veh_pans_ferry`
(`globe_world.gd:299`) and `veh_sundered_barque` (`:300`); `veh_haven_ferry`
is referenced only by tests. The island ferry is data-only.

---

## 2. Which live globe systems READ each data family

| Family | Loader (file:line) | Live consumer (file:line) |
|--------|--------------------|---------------------------|
| `data/zones` | `DataService.load_zones` `data_service.gd:204` via `_scan_directory` `:120` | `ZoneManager.load_zones` `zone_manager.gd:257`; read by `WorldService.initialize_world` `world_service.gd:106` |
| `data/npc` | `DataService.load_npcs` `data_service.gd:230` | `SpawnService.spawn_all_offering_npcs` `spawn_service.gd:1145`; globe rosters `globe_world.gd:1629/1648/1665`; `globe_underworld.gd:825` |
| `data/npc_offerings` | not scanned by DataService; loaded on demand | `npc_entity._load_offering` `npc_entity.gd:96`; `globe_player._open_npc_quests` `globe_player.gd:1867`; `VendorService` |
| `data/dialogues` | `DialogService._load_dialogues` `dialog_service.gd:113` | `DialogService.start_dialogue` `:129`; called from `globe_player.gd:1844` |
| `data/quests` | `DataService.load_quests` `data_service.gd:326` | `QuestService.get_all_quests`/`get_available_quests` `quest_service.gd:388`; `accept_quest` `:506`; UI `quest_ui.gd:205/395` |
| `data/dwellings` | `DataService.load_dwellings` `data_service.gd:218` (merged into `_items`) | `DwellingService.place_station` `dwelling_service.gd:255` (via `DataService.get_item` `:269`); globe plot `globe_world.gd:1146` |
| `data/loot_tables` | `LootTableResolver.load_table` `loot_table_resolver.gd:16` (`LOOT_DIR` `:13`) | `EnemyData` loot roll `enemy_data.gd:148/159`; `black_market_service.gd:50/57` |
| `data/enemies` | `DataService.load_enemies` `data_service.gd:184` | `DataService.get_enemy` `:394`; `globe_world._spawn_globe_enemy` `globe_world.gd:1805`; `SpawnService` `spawn_service.gd:270`; hordes `horde_event_service.gd:438` |
| `data/factions` | `DataService.load_factions` `data_service.gd:199` | `FactionManager.load_factions` `faction_manager.gd:66` |
| `data/gateways` | `DataService.load_gateways` `data_service.gd:357` | `WorldService._register_authored_gateways` `world_service.gd:857`; `DataService.get_gateway` `:602`; minimap `minimap.gd:636`; world map `world_map.gd:899` |
| `data/guards` | not scanned; loaded on demand | `globe_world._build_globe_guards` `globe_world.gd:1009` (`load("res://data/guards/%s.tres")` `:1018`) |
| `data/hordes` | `DataService.load_hordes` `data_service.gd:362`; `HordeDataResolver.load_config` `horde_data_resolver.gd:16` | `HordeEventService` `horde_event_service.gd:246`; weather `weather_event_service.gd:120` |
| `data/world_bosses` | `SpawnService.load_world_boss_schedules` `spawn_service.gd:171` | timed schedules `spawn_service.gd:195` |
| `data/vehicles` | `DataService.load_vehicles` `data_service.gd:254` | `player_base.gd:411`; globe builds pans ferry + sundered barque `globe_world.gd:299/300` |

---

## 3. Cross-file references that do NOT resolve (dangling)

Two dangling ids, both zone references with no matching
`game/data/zones/<id>.tres` (verified: `ls game/data/zones | grep -iE
"dark|human"` -> NONE):

| Referencing file:line | Dangling id | Field |
|-----------------------|-------------|-------|
| `data/species/species_akkan.tres:21` | `dark_highlands` | `home_zone` |
| `data/factions/faction_akkan.tres:25` | `dark_highlands` | `controlled_zones` |
| `data/factions/faction_human.tres:25` | `human_territory` | `controlled_zones` (second entry; `zone_starter_plains` resolves) |

`home_zone` IS consumed live: `character_select.gd:128` sets
`data.zone_id = selected_species.home_zone`, so an Akkan character carries a
`zone_id` naming no zone. `controlled_zones` is exported by
`faction.gd:62` and serialized at `:119`, but no live `.gd` reads it (grep
`controlled_zones` outside tests returns only the schema). These are the only
dangling data references found; every other cross-file ref checked resolves:

- NPC `zone_id` -> zone files: all resolve.
- NPC `includes[].dialogue_id` -> dialogue files: all resolve.
- NPC `includes[].ref_id` (offering type) -> offering files: all resolve.
- Dialogue `npc_id` -> npc files: all resolve.
- Quest `giver_npc_id` / `turn_in_npc_id` -> npc files: all resolve.
- Quest `previous_quest_id` / chain refs -> quest files: all resolve.
- Gateway `source_zone_id` / `destination_zone_id` -> zone files: all resolve.
- World-boss `zone_id` -> zone files: all resolve.
- Offering `quest_ids` -> quest files: all resolve.
- Species/NPC/enemy/mount `hitbox_profile` refs: covered by the lint (27/0).

The data-naming lint (`test_data_naming_lint.gd`) does NOT check `home_zone`
(grep `home_zone` in the lint -> no match) nor `controlled_zones`, which is why
the dangling pair above passes 27/0.

---

## 4. Lint pass count

Command (after the one-time import step described in the lane brief):

```
godot --headless --path game --script res://tests/test_data_naming_lint.gd
--- DATA NAMING LINT: 27 passed, 0 failed ---   (exit 0)
```

**27/0 -- not a defect.** (The script prints its verdict at
`test_data_naming_lint.gd:44`.)

---

## Top findings

1. **The Sundered-quay NPC cluster is dead on the live globe** (section 1a):
   `npc_ferryman_sundered`, `npc_salvor_wreck`, their two dialogues, four
   offerings, and `quest_shoal_freight` are placed by nothing on the planet. The
   offering-NPC spawner parents them into the menu scene, which the globe load
   then frees (proved empirically: 17 live NPCs, neither sundered id present).
2. **Two dangling zone references** (section 3): `dark_highlands`
   (`species_akkan.tres:21`, `faction_akkan.tres:25`) and `human_territory`
   (`faction_human.tres:25`) name no zone file. `home_zone` reaches a live
   consumer (`character_select.gd:128`); the lint does not cover either field.
3. **Fifteen authored enemies have no spawner** (section 1f) -- the un-ported
   sea/meadow/deep roster; plus orphan data files
   `dwel_wooden_chair`, `loot_sky_crate_daily`, `veh_island_ferry`, and the four
   unreferenced offerings (sections 1c--1e, 1h).

## Method

- Enumerated every `.tres` in the audited families; dumped each `id` and each
  reference field.
- For each id, ran `grep -rln -F '"<id>"' game/ --include=*.{gd,tres,tscn}`
  excluding the file's own definition and `.godot/` sidecars; recorded the
  consumer set verbatim.
- Resolved every zone/npc/quest/dialogue/offering reference by testing for the
  matching file under `game/data/<family>/`.
- Read the live loaders/consumers listed in section 2 to attribute each family.
- Booted the production menu flow headless with a temporary probe (since
  deleted) to list the live NPC roster; ran the naming lint for the pass count.

No file under `game/` was modified; no `game/` data or code was changed.

---

## Addendum (parent, post-harvest)

The ONE dangling reference that a LIVE code path consumes -- species `home_zone`
-- is FIXED. `character_select._on_play_pressed` now resolves the species home
zone against the zone catalog and falls back to the spawn zone
(`zone_starter_plains`), so an Akkan character is created carrying a REAL zone
id instead of the phantom `dark_highlands`. Receipt
`tests/test_character_select_zone.gd` 9/0 (a real zone resolves, the phantom
does not, every species lands on a real zone, the Akkan creation path lands on
the fallback). The faction `controlled_zones` phantoms (`dark_highlands`,
`human_territory`) are LEFT AS AUTHORED: no live `.gd` reads `controlled_zones`,
so they are inert lore, not a live dead end -- the audit above is the record.
