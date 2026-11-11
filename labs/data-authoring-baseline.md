# Data Authoring Baseline

This is the written baseline for authoring static content in Synmergia.
Static content lives as `.tres` resources under `game/data/<family>/`. If
you are an outside contributor adding a weapon, a potion, a quest, or a
gathering material, follow this document. Every rule here is checkable and
the gate at the end enforces most of it.

The Godot project root is `game/`. All paths below are relative to it
(`res://` == `game/`). The live world is the spherical globe
(`game/scenes/worlds/globe_world.gd`); the planar world is retired.

The world voice is the no-technology law: Synmergia is unpowered.
Everything is salvage, repair, or growth. Copy says woken, mended, grown,
salvaged. It never says tech, never says magic, and never names gods. See
`labs/prd-story.md`, `labs/prd-psy.md`, and the no-technology law in
`labs/prd-ancient-movers.md`.

---

## 1. The file skeleton

Every `.tres` in `game/data/` has the same three-part shape: a header
line, one `[ext_resource]` line binding the schema, then one `[resource]`
block.

```
[gd_resource type="Resource" script_class="Item" load_steps=2 format=3]

[ext_resource type="Script" path="res://core/schemas/item.gd" id="1"]

[resource]
script = ExtResource("1")
id = "res_iron_ore"
display_name = "Iron Ore"
description = "Raw iron, veined with rust. The forge wants it."
icon_path = "res://icons/resources/ore_iron.png"
item_category = 4
rarity = 0
stack_size = 100
sell_price = 2
buy_price = 6
weight = 0.5
```

Rules for the skeleton:

- The header is `[gd_resource type="Resource" script_class="<Schema>"
  load_steps=2 format=3]`. `script_class` names the schema's `class_name`.
- `script = ExtResource("1")` is the **first field** in `[resource]`.
- Use **4-space indentation**, never tabs. Tabs are for `.gd` source only.
  A `.tres` with tabs still parses, but it breaks the house style and this
  corpus is uniform.
- ASCII only. No smart quotes (`'` U+2019), no em-dashes (`-` U+2014), no
  emoji. They cause Godot import failures.
- `load_steps` counts the `[ext_resource]` entries plus one. One schema
  binding is always `load_steps=2`.
- Do not put blank lines inside the `[resource]` body.
- LF line endings.

---

## 2. The id / filename law

The id in the file is the file's basename without `.tres`. Filename == id,
always, for every prefixed family.

| Family dir (`game/data/`) | id prefix | Example |
|---|---|---|
| `resources/` | `res_` | `res_iron_ore` |
| `items/` | `item_` (misc) / `item_quest_` (quest tokens) | `item_ancient_coin` |
| `weapons/` | `wep_` | `wep_iron_axe` |
| `armors/` | `arm_` | `arm_iron_mail_chest` |
| `accessories/` | `acc_` | `acc_ring_first_light` |
| `consumables/` | `potion_` or a bare name | `potion_health_small`, `elixir_ironblood` |
| `recipes/` | `recipe_` | `recipe_iron_axe` |
| `loot_tables/` | `loot_` | `loot_wolf` |
| `quests/` | `quest_` | `quest_wolves_hunt` |
| `npc/` | `npc_` | `npc_blacksmith_village` |
| `zones/` | `zone_` | `zone_starter_plains` |
| `factions/` | `faction_` | `faction_human` |
| `currencies/` | `currency_` | `currency_gold` |
| `mounts/` | `mount_` | `mount_plains_runner` |
| `vehicles/` | `veh_` | `veh_haven_ferry` |
| `content_packs/` | `pack_` | `pack_tide_season` |
| `hitbox_profiles/` | `hitbox_` | `hitbox_beast_medium` |
| `signs/` | `sign_` | `sign_the_awakening` |
| `acts/` | `act_` | `act_1_the_first_vault` |
| `mysteries/` | `mystery_` | `mystery_the_first_vault` |
| `gates/` | `gate_` | a ward gate |
| `enemies/` | bare id, file keeps `enemy_` prefix | id `wolf` in `enemy_wolf.tres` |

Other families (dialogues, dwellings, biomes, oceans, thermals,
world_bosses, worlds, roads, targets, events, guards, hordes,
movement_profiles, status_effects, species, classes, titles,
achievements, npc_offerings, gateways, containers, roots) use bare or
schema-prefixed ids. When in doubt, copy a neighbour in the same folder.

Ids are unique across the whole repo. Grep before you name:

```
grep -rn 'id = "your_new_id"' game/data
```

---

## 3. Schemas

Each family binds one schema from `game/core/schemas/`. The schema's
`@export` list is the full set of fields the family may set. Fields are
written in the **same order** the schema exports them.

| Family | Schema |
|---|---|
| `resources/`, `items/`, `weapons/`, `armors/`, `accessories/`, `consumables/`, `dwellings/` | `item.gd` |
| `recipes/` | `recipe_data.gd` |
| `loot_tables/` | `loot_table.gd` |
| `quests/` | `quest_data.gd` |
| `npc/` | `npc_data.gd` |
| `npc_offerings/` | `npc_offering.gd` |
| `enemies/` | `enemy_data.gd` |
| `zones/` | `zone_data.gd` |
| `factions/` | `faction.gd` |
| `currencies/` | `currency_data.gd` |
| `mounts/`, `gliders/` | `mount_data.gd` |
| `vehicles/` | `vehicle_data.gd` |
| `content_packs/` | `content_pack_data.gd` |
| `hitbox_profiles/` | `hitbox_profile.gd` |
| `signs/` | `sign_profile.gd` |
| `acts/` | `act_profile.gd` |
| `mysteries/` | `mystery_data.gd` |
| `status_effects/` | `status_effect_data.gd` |
| `dialogues/` | `dialogue_data.gd` |
| `biomes/` | `biome_band.gd` |
| `oceans/` | `ocean_volume.gd` |
| `thermals/` | `thermal_updraft.gd` |
| `weather_events/` | `weather_event_data.gd` |
| `world_bosses/` | `world_boss_data.gd` |
| `worlds/` | `world_data.gd` |
| `movement_profiles/` | `movement_profile.gd` |
| `targets/` | `target_schema.gd` |
| `roads/` | `road_data.gd` |
| `events/` | `event_data.gd` |
| `guards/` | `guard_data.gd` |

A field you set that the schema does not declare is a **phantom**: Godot
silently drops it on load (`resource.get("field")` returns `null`). A
field the schema declares that no file sets is **dead**. Both are bugs to
report; fix the phantom, and only set the dead field where it is clearly
meant to carry a value.

### Item families in detail (`item.gd`)

`item.gd` serves six item families. The `item_category` field picks the
family's meaning:

```
ItemCategory: 0 WEAPON, 1 ARMOR, 2 ACCESSORY, 3 CONSUMABLE,
              4 RESOURCE, 5 GEM, 6 EVENT, 7 DWELLING, 8 MISC,
              9 SKILL_BOOK
```

So a resource is `item_category = 4`, a consumable `= 3`, misc/quest
goods `= 8`, housing goods `= 7`. Set `is_quest_item = true` and a
resolvable `quest_id` on quest tokens.

Equipment slots (`EquipSlot`): `0 NONE, 1 HEAD, 2 CHEST, 3 LEGS, 4 FEET,
5 GLOVES, 6 SHOULDERS, 7 MAIN_HAND, 8 OFF_HAND, 9 RING_1, 10 RING_2,
11 NECKLACE, 12 CLOAK, 13 BELT`.

Weapon types (`WeaponType`): `0 NONE, 1 SWORD, 2 AXE, 3 MACE, 4 DAGGER,
5 BOW, 6 CROSSBOW, 7 STAFF, 8 WAND, 9 SPEAR, 10 SHIELD`. A weapon must
set a non-zero `weapon_type`.

Armor types (`ArmorType`): `0 NONE, 1 CLOTH, 2 LEATHER, 3 MAIL, 4 PLATE`.
An armor must set a non-zero `armor_type`.

Rarity (`Rarity`): `0 COMMON, 1 UNCOMMON, 2 RARE, 3 EPIC, 4 LEGENDARY,
5 MYTHIC`.

Purse law for items: `sell_price >= 0`, `buy_price >= 0`, and when
`buy_price > 0` then `sell_price < buy_price`. A `0 / 0` purse is legal
only for a quest item. Stack law: weapons and armors stack 1; resources
and consumables stack 2 or more; misc is free. Requirements stay inside
the item: `required_level <= item_level`.

### The material ladder

Resources climb a fixed ladder. Reuse these ids rather than inventing new
rungs:

- iron: `res_iron_ore` -> `res_iron_ingot` (plus `res_iron_grit`)
- golden: `res_ore_golden` -> `res_golden_ingot`
- silver: `res_ore_silver` -> `res_silver_ingot` (plus `res_silver_dust`)
- mythril: `res_ore_mythril` -> `res_mythril_ingot` (plus
  `res_mythril_shard`)
- starmetal: `res_ore_starmetal` -> `res_starmetal_ingot`
- organics and salvage: `res_timber`, `res_stone`, `res_slag`,
  `res_kelp_fiber`, `res_hemp_cord`, `res_sinew_thread`,
  `res_scale_plate`, `res_salvage_plate`, `res_conduit_wire`,
  `res_gloam_spore`, `res_shoal_pearl`, `res_abyss_pearl`

Gear follows the same metal rungs: copper -> iron -> silver -> golden ->
mythril -> starmetal. A `wep_`/`arm_`/`acc_` id names its rung.

---

## 4. Cross-reference rules

Every reference you write must resolve to a real `.tres` id. The gate
checks these; so does `game/tests/test_item_catalog.gd`.

- **Recipe** (`recipe_data.gd`): `station` is `0 NONE` (hand-craft), `1
  FORGE`, `2 WORKBENCH`, `3 ALCHEMY`. Every `item_id` in `inputs`,
  `output`, and `byproducts` must resolve to an item id. A crafted mount
  (a glider) is a legal output: it resolves in `data/gliders/`.

```
inputs = [{"item_id": "res_iron_ingot", "qty": 3}, {"item_id": "res_timber", "qty": 1}]
output = {"item_id": "wep_iron_axe", "qty": 1}
byproducts = [{"item_id": "res_slag", "qty": 1}]
```

- **Loot table** (`loot_table.gd`): every `entries[].item_id` must
  resolve. Skill-book ids of the form `book_<skill_id>_<tier>` are legal
  even though no file exists: `GroundLootService` expands them at runtime.

- **Quest** (`quest_data.gd`): `giver_npc_id` and `turn_in_npc_id` must
  name a real `data/npc/` id. `next_quest_id`, `previous_quest_id`, and
  `required_quests[]` must name real quest ids. Each objective's `target`
  must resolve against the catalog its credit bridge reads:

  | Objective type | target resolves against |
  |---|---|
  | 0 `KILL` | an enemy `display_name` in `data/enemies/` |
  | 1 `COLLECT` | an item `display_name` |
  | 4 `EXPLORE` | a `data/zones/` id |
  | 5 `TALK` | a `data/npc/` id |
  | 11 `RECORD_INSIGHT` | the literal `sky_insight` |
  | 12 `SWIM` | a `data/oceans/` id |
  | 13 `GLIDE` | the literal `glide_distance` |

  Objective dicts are inline:

  ```
  objectives = [{"id": "kill_wolves", "type": 0, "target": "Wolf", "count": 5}]
  ```

  KILL targets a display name, not an id. Register the quest in the
  matching `data/npc_offerings/*.tres` by adding its id to that offering's
  `quest_ids` array, and reference that offering from the NPC's
  `includes[]` so the quest board can reach it.

- **Offering** (`npc_offering.gd`): `catalog_items[].item_id` and
  `quest_ids[]` must resolve.

---

## 5. The gate

Run the data-naming lint. It is the law.

```
export PATH=/workspace/.tools/godot:$PATH
cd game
godot --headless --path . --script res://tests/test_data_naming_lint.gd
```

It must print `DATA NAMING LINT: 30 passed, 0 failed` and exit 0. The
lint covers prefix + filename==id for the prefixed families, enemy id
style, NPC `zone_id` refs, quest chain + giver/turn_in refs, quest
objective catalogs, offering `quest_ids`, dialogue `npc_id` refs, zone
NPC rosters, gateway refs, currency/mount/vehicle/pack prefixes,
mount/vehicle currency+faction+route refs, quest-item `quest_id` refs,
misc `item_` prefix, `model_path`/`scene_path` refs, hitbox profile refs
and species fairness, sky signs, acts, mysteries, and class skill refs.

The second gate is the item catalog:

```
godot --headless --path . --script res://tests/test_item_catalog.gd
```

It must print `ITEM CATALOG: 10 passed, 0 failed`. It covers the five item
families' identity + prefix law, the authored-words law (every item has a
`display_name` and `description`), icon convention (`res://icons/...`),
the purse law, the stack law, and the recipe bill.

Do not run `scripts/godot_test_runner.sh`; it is being reworked to run in
parallel.

---

## 6. Interop with the web Codex

The web Codex reads a generated snapshot of `game/data/*`. Regenerate it
with:

```
npm run sync:data
```

The snapshot lands at `src/data/godot_data.json`. That file is generated;
do not hand-edit it and do not commit a local regeneration. New `.tres`
in a synced family appear in the Codex on the next sync, so keep
`display_name` and `description` clean: they are the public face of the
entry.

---

## 7. Checklist before you open a PR

1. Filename == id; the id carries the family prefix; the id is unique.
2. Header matches the skeleton; `script = ExtResource("1")` is first.
3. 4-space indent, ASCII only, no interior blank lines, LF endings.
4. Fields are in schema export order; no phantom fields.
5. Every cross-reference resolves (recipe items, loot entries, quest
   giver/turn_in/objectives, offering quest_ids).
6. Copy is in the no-technology voice.
7. `test_data_naming_lint.gd` is 30 / 0 and `test_item_catalog.gd` is
   10 / 0.
