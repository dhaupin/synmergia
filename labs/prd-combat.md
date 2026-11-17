# PRD: Canonical Combat - As-Built and Gap Ledger

> **Status:** PARTIAL (canonical lanes wired 2026-11-16; two-handed, wrist
> shields, enemy loadouts and min/max bands wired 2026-11-17; dual wield,
> weapon families and the physical/magical/healing weapon lanes wired
> 2026-11-17; the full five-rarity x level-band catalog is explicitly deferred
> in P1 below)
> **Law:** `game/core/schemas/stat_id.gd` is the vocabulary; `CombatMath` is the
> hit/mitigation authority; `EnemyData.apply_stats_to` and
> `Item.get_total_stats` are the seeding paths. Where this document and code
> disagree, code wins.
> **Related:** `labs/prd-blessings.md`, `labs/prd-bout-host.md`,
> `labs/data-authoring-baseline.md`.

## 1. What Is Shipped

| Piece | Truth |
| --- | --- |
| Weapon damage lanes | `Item.weapon_damage_type` selects what the authored min/max band feeds: `PHYSICAL` -> `get_attack_power()`, `MAGICAL` -> `get_spell_power()` (staves/wands), `HEALING` -> `get_healing_power()` (relics). `PlayerBase` and the shared `Entity` both roll through `InventoryComponent.get_main_hand_damage_roll(lane)` / `get_offhand_damage_roll(lane)`; `Item.get_damage_range()` sorts authored bounds, so a max below min cannot invert a roll. Broken weapons contribute 0, and a staff/wand's basic strike is tagged magical so its band rides spell power rather than the physical lane. |
| Weapon handedness | `Item.is_two_handed` is the authored hand identity. 85 hand weapons are now in the catalog: 51 two-handed, 34 one-handed. The one-handed set includes swords, light axes, the new warhammer, daggers, wands, the short lance and the oak reliquary; the two-handed set includes swords, greataxes, hammers/mauls, staves, bows, crossbows, spears, lances, scythes and the grand reliquary. `InventoryComponent._hand_layout_allows()` rejects a normal off-hand beside a two-handed main hand and rejects a two-handed item in the off hand. `from_dict` runs the same law on loaded saves. |
| Dual wield | `InventoryComponent.is_dual_wielding()` is true only when both hands hold unbroken one-handed non-shield weapons. A second one-hander auto-fills an empty off hand when the main hand is already a one-hander (`equip_item(slot, target_slot = -1)` also accepts an explicit hand). The no-shield posture pays 15% attack cadence and 6% to attack/spell/healing power, and the off hand adds half its band; the main and off hand both add their authored crit chance/damage. A shield replaces the off-hand weapon and closes the posture. |
| Weapon families | `WeaponType` keeps its original 0-10 values and appends `LANCE=11`, `SCYTHE=12`, `RELIC=13`. Representative records author both hand variants where legal: `wep_iron_greatsword` (2H sword), `wep_iron_greataxe` (2H axe), `wep_iron_warhammer` (1H hammer), `wep_iron_lance` / `wep_short_lance` (2H/1H lance), `wep_iron_scythe` (2H scythe), `wep_oak_reliquary` / `wep_grand_reliquary` (1H/2H healing relic). A 1H scythe and a 2H dagger/wand are deliberately illegal shapes, not missing variants. |
| Enemy damage band | `EnemyData.attack_damage_min/max` is the enemy body band (`attack_power` is the fallback). A spawn pipeline seeds the raw band on the stat block, or its level-scaled form when it is scaling the body; `Enemy.get_attack_power()` rolls the body band once and adds the equipped main-hand roll. Inverted authored bounds are normalized. |
| Skill damage band | A skill's `effects[]` damage entries may author `min`/`max`; `Skill.from_schema()` flattens them into runtime `damage_min/max` and keeps `damage` as the authored/display value. `Skill.get_damage_roll()` samples the summed band once per cast. All 25 direct-damage entries in the magical skill catalog now carry an 85%-115% band; physical/ranged skills stay deterministic because the weapon roll supplies their variance. |
| Crit on bands | Every band is sampled first, then `CombatMath.calculate_damage()` applies the one crit multiplier to that sample. Weapon, enemy-body and skill rolls all use the same terminal path; magical crit still reads the INT axis through `StatId.crit_axis_for`. |
| Weapon cadence | `Item.attack_speed` is a multiplier on the body's class/enemy cadence. `1.0` rides the default; `1.2` is 20% faster. The shared `Entity.get_attack_speed()` applies it after the `StatId` agility/class formula and clamps at `MAX_ATTACK_SPEED_MULT`; `EnemyAI` divides its template cooldown by that same cadence. |
| Weapon crit | `Item.crit_chance` / `crit_damage` are flat deltas added to the body's `StatId` crit delta. The shared `Entity.get_crit_chance()` / `get_crit_multiplier()` read the main hand and, while dual wielding, the off hand too, so enemies and future actors get the same weapon identity; broken weapons contribute 0. `CombatMath._weapon_crit_chance_delta()` adds the same weapon/off-hand crit to the INT magical and WIS healing axes, so a wand or relic's authored crit% actually lands. |
| Weapon data | All 92 weapon-directory records now carry `crit_chance` / `crit_damage`; the 85 hand weapons use `MAIN_HAND = 7`; the 7 weapon shields use `OFF_HAND = 8`. All 85 hand weapons author `is_two_handed`; all 7 weapon shields and 2 armor shields author `shield_type`. 24 staves/wands author `weapon_damage_type = MAGICAL`; the two reliquaries author `HEALING`; the rest default to `PHYSICAL`. Rogue weapons lean crit, DD/tank lanes lean cadence, and rarity/level add a little of both. |
| School resists | `StatId.DAMAGE_SCHOOLS` is physical, magical, fire, frost, lightning, poison, arcane, holy, shadow. Each school has a canonical `resist_*` flat stat, clamped by `MAX_RESIST = 0.90`. `CombatMath.calculate_mitigation(..., school_resist)` layers the ward after armor and flat reduction. |
| Resist seeding | `Item.damage_resists` folds into `get_total_stats()`; `EnemyData.damage_resists` seeds the same keys in `apply_stats_to`; `CharacterClass.damage_resists` folds in `PlayerBase._apply_class_crit_identity`; `StatusEffect.damage_resists` adds/removes through `_apply_combat_modifiers`. |
| Armor data | All 77 armor records now author `damage_resists` by armor type (cloth/leather/mail/plate), with a class-lane bonus and rarity/level scaling. Shields author physical/fire wards. |
| Enemy data | Thematic templates author per-school wards: Void Lord (shadow/arcane), Tidebound Ancient (frost/physical), Blight-Lizard (poison), Clockwork Saint (lightning/physical), Sporebound Matriarch (poison), Training Dummy (physical/fire). |
| Shield families | A shield is an `OFF_HAND` item with `weapon_type = SHIELD`; `Item.shield_type` selects `NORMAL` or `WRIST`. A normal shield is the one-handed weapon + shield posture and contributes `1.0` of the block lane; a wrist shield straps to the arm, is the only off-hand legal beside a two-handed main hand, and contributes `0.40` of the block chance and blocked value. `CombatMath._shield_block_scale()` is the one read; an off-hand orb/tome contributes none, and a broken shield contributes none. The seven weapon shields and two armor shields author `shield_type`; `wep_iron_wristguard` / `wep_starmetal_wristguard` are the first `WRIST` records, and the other seven are `NORMAL`. |
| Enemy loadouts | `EnemyData.equipment_ids` deep-copies catalog items through `Item.from_dict()` into the same `InventoryComponent` a player uses (no shared durability). Bandit equips an iron axe, leather chest and iron wristguard; the Clockwork Saint equips a two-handed guardian maul plus wristguard; the Tidebound Ancient equips the mythril halberd. Equipment armor joins physical mitigation, gear resists join the school wards, and gear stats (including weapon crit/cadence) reach the shared body getters. |
| Legacy save migration | `InventoryComponent.from_dict` moves a legacy non-shield weapon from off-hand 8 to main-hand 7, so characters saved before the slot correction keep their weapon. A full bag leaves the off-hand copy untouched rather than deleting it. |
| Movement speed | `CharacterClass.movement_speed_bonus` is a delta on the 1.0 movement multiplier and folds into the player stat block. Enemies already author `EnemyData.move_speed` and mounts already own their movement profile; both remain live. |
| Arena normalization | `InstanceContract.normalized_level` now retains 20% of the level gap instead of capping at 2x. A level 5 beside a 50 plays at 41-equivalent; a 30 beside a 60 plays at 54-equivalent; the reference fighter is never pulled down. |
| Arena retune | `ArenaInstance.set_fighter_level` / `spawn_fighter` / `remove_fighter` / AFK `kick_fighter` queue a coalesced `power_reference_ready` emission. `ArenaCombatBridge._apply_power` recomputes from each fighter's pre-bout snapshot, so a 60 joining lifts the room, a 60 leaving lowers it, and repeated retunes never compound. Departed fighters are restored immediately. |
| Player departure | `BoutHostService` listens for `EntityService.player_left` during a hosted bout and calls `room.remove_fighter(pid)`, dropping the departed fighter's level from the reference book and updating the host's participant list. A voluntary leave now retunes survivors exactly like an AFK kick. |

## 2. Canonical Rules

1. **One vocabulary.** A stat is spelled by a `StatId` key and authored in a
   schema's `@export` surface plus a `.tres`. No service invents a second
   `fire_resist` / `block_chance` spelling.
2. **Weapons ride the body by default.** A weapon's `attack_speed` is a
   multiplier, not an absolute attacks-per-second value. `1.0` means "use the
   class/enemy cadence"; only an authored override changes it.
3. **Damage is rolled, then mitigated, then crit.** The weapon, enemy-body or
   skill band is sampled once per swing/cast; the crit multiplier lands on that
   sample; armor, flat reduction, then the school ward reduce the result. The
   result never drops below 1 for a landed hit.
4. **Shields are armor you hold, in two families.** A normal shield is the
   one-handed posture and opens the full block lane; a wrist shield is the only
   off-hand legal beside a two-handed weapon and opens 40% of it. Block chance
   is still the `CombatBalanceData` formula, not a second hardcoded table.
5. **Dual wield is a two-one-hander, no-shield posture.** Both hands carry an
   unbroken one-handed non-shield weapon. The trade is 15% cadence and a 6%
   power lift, plus half the off-hand band and both weapons' crit identity;
   any shield in the off hand replaces the off-hand weapon and ends the
   posture. Two-handers never dual wield and still reject a non-wrist off hand.
6. **A weapon band has one lane.** Physical bands feed attack power, magical
   bands feed spell power, healing bands feed healing power. The same min/max
   roll law and the same terminal crit multiplier apply in all three lanes;
   the lane changes which body power the roll feeds, not whether it varies.
7. **Arena power is bout-local and reference-relative.** The highest current
   level in the room is the reference; every lower fighter gets a normalized
   stat book derived from its pre-bout snapshot. Real stats are restored at bout
   end or on departure.
8. **A stronger fighter keeps the edge.** Normalization pulls lower levels
   close but never to parity; 20% of the gap survives by design.

## 3. Gaps

### P0 - Shield behavior is still shallow

The canonical item lane, both shield families and the two-handed hand law are
live, but these are not:

- Directional/facing blocks, guard arcs, arm-attachment visuals, and distinct
  wrist/maul animations.
- Block stamina cost, guard break, stagger, and shield durability loss. A
  wrist shield is weaker only through `shield_type`; it has no separate
  attachment slot, weight, or failure state.
- Shield-specific skills (bash, wall, reflect) reading the shield's block
  rating/ward rather than a generic off-hand.
- Weapon-set swapping. Dual wield itself is live, but there is no one-key swap
  between a two-handed weapon and a one-handed weapon + normal shield, and no
  saved off-hand loadout to restore after a swap.
- The equip UI exposes `can_equip_in_slot()` as a predicate, but not every
  inventory row renders the wrist/2H reason; a refused equip can still look
  available until clicked.

### P1 - Enemy loadouts and class defense lanes are thin

- Only bandit, Clockwork Saint and Tidebound Ancient author `equipment_ids`.
  The rest of the roster still fights with template armor/resists only. A
  deliberate content pass should decide which elites/bosses carry shields,
  two-handed weapons, or armor without changing their authored health.
- Equipped enemy gear does not enter the loot table: killing the bandit does
  not drop its iron axe or wristguard. Gear durability is per-instance, but
  there is no enemy repair/replacement loop and no `equipment_ids` weight.
- Enemy gear vitality does not expand the template health pool:
  `Enemy._calculate_max_resources()` deliberately preserves authored health,
  so armor vitality is currently a stat on the body rather than a bigger HP
  bar. Armor value, school wards and weapon damage do land.
- `EnemyData.armor` / `resistance` remain a single physical/magical pair; the
  new school wards sit on top. A fully school-split enemy armor curve is not
  authored.
- Only six enemy templates author `damage_resists`; the rest inherit 0. That is
  deliberate for now (no false wards), but the roster needs a content pass.
- Every class authors exactly one innate ward lane (`damage_resists` one key).
  `defense_multiplier` / `armor_multiplier` are still unauthored on classes, so
  the "missing Defs" gap from the class-lane audit remains.
- NPCs, agents and future non-Enemy actors inherit the `stats` block and can
  read wards, but no NPC template authors any yet.

### P1 - Weapon data identity needs a design pass

- The generated crit/cadence values are a first pass: base weapon-type identity
  plus role/rarity/level. Named weapons (raid drops, quest rewards) should get
  hand-authored overrides where their fantasy differs from the formula.
- The catalog now has 85 hand weapons (51 two-handed, 34 one-handed), but it is
  still not a complete family tree. Missing families are thrown weapons
  (javelins, throwing axes/daggers), fist/gauntlet weapons, a one-handed spear
  distinct from the short lance, off-hand-only parrying blades/foci, and an
  unarmed/martial-arts lane. `SCYTHE` is intentionally two-handed only; `DAGGER`
  and `WAND` are intentionally one-handed only.
- The appended families (`LANCE`, `SCYTHE`, `RELIC`) currently top out below
  level 60: the short/iron lances are L11/L9, the iron scythe L12, and the
  oak/grand reliquaries L6/L12. They have no L60 capstone and no full rarity
  ladder; `test_zenith_capstone` still covers the original `WeaponType` 1..10
  only, deliberately.
- Dual wield is structurally live, but only the shared weapon rows are tuned.
  Named dual-wield pairs, off-hand-specific skills, and per-class off-hand
  identities (rogue dagger + dagger, healer relic + relic, battle-mage
  wand + sword) still need authored content.
- Generic weapons with `required_class = ""` have no role lean; their cadence
  and crit come from type/rarity/level only.
- `attack_speed` still carries a legacy "attacks per second" comment in some
  tooling/UI. The runtime treats it as a multiplier; the label should be
  corrected wherever it is shown to players.
- Weapon damage is rolled inside `get_attack_power()` / `get_spell_power()` /
  `get_healing_power()`. A caller that invokes an accessor twice for one swing
  would roll twice; today the basic-attack path reads it once, but future
  multi-hit skills should cache the roll for the swing.

### P1 - Full five-rarity x level-band catalog is deferred

The user request explicitly defers the complete catalog until the combat system
is ironed out. The target matrix is:

- **Rarities:** Common, Rare, Epic, Legendary, Mythic (0-4).
- **Level bands:** 1-10, 11-20, 21-30, 31-40, 41-50, 51-60.
- **Weapon families:** every legal hand variant of sword, axe, hammer/mace,
  dagger, bow, crossbow, staff, wand, spear, lance, scythe and relic (plus
  thrown/fist once those families exist).
- **Armor families:** every armor slot/type pair (cloth, leather, mail, plate)
  in each band, not just the current high-tier rows.
- **Shield families:** normal and wrist shields in each band, with block rating,
  armor value and wards scaling by rarity rather than only by item level.

Acceptance for that content pass:

1. Every family x rarity x band cell has one authored record (or an explicit
   "not legal in this shape" ledger row, e.g. 1H scythe / 2H dagger).
2. Buy-price ladders stay banded and monotonic inside each family.
3. Drop tables, vendors, recipes and icons resolve for every new id; a catalog
   row with no acquisition path is not shipped.
4. `test_item_catalog`, `test_data_naming_lint` and a new matrix-coverage receipt
   pass; the new L60 records join `test_zenith_capstone` once the three appended
   families have capstones.
5. The generated `src/data/godot_data.json` is refreshed and the client build
   reads the new records without a second data shape.

Current coverage is nowhere near that matrix: 42 of 85 hand weapons are Mythic,
19 Epic, 15 Common, 6 Legendary and only 3 Rare; the weapon directory has no
full band sweep. This is a content-authoring task, not a runtime gap.

### P2 - Arena normalization edges

- `power_scale` is intentionally uncapped after the 2x cap was removed. A level
  1 beside a 60 gets a 48x stat multiplier (48-equivalent). Matchmaking bands
  still keep that pairing out unless the normalized-power consent path is used,
  but the arena UI should surface the effective level so the boost is legible.
- Combat deaths do not retune the room; only level changes, joins, voluntary
  removals, and AFK kicks do. Whether a dead reference should stop lifting the
  survivors is a design decision, not an oversight.
- The displayed character sheet does not show bout-local normalized stats or
  effective level yet.

### P2 - Damage-band coverage

- Magical direct-damage entries are fully ranged (25/25), but physical/ranged
  skills remain single-value by design. A physical skill that wants a band
  can author `min`/`max` on its effect entry; no data does yet because the
  weapon roll already supplies variance.
- Damage-over-time effects still author a single `value`; only direct `damage`
  entries flatten into the runtime band. A ranged DoT needs its own schema
  decision, not a silent reuse of `damage_min/max`.
- `EnemyData.attack_damage_min/max` is authored as an 85%-115% body band around
  the old `attack_power` for all 31 templates. That is a balance first pass;
  bosses with a two-handed loadout now add the weapon roll on top of that
  authored body band, so their live swing is wider than the template number.
- The displayed character sheet still shows a single damage number for a
  weapon band; it does not show min-max, the enemy's body band, or the
  dual-wield off-hand half-band. The inventory row also does not preview the
  auto-off-hand placement before the click.
- The healing lane has only the two reliquary records and no relic-specific
  heal/HoT skills yet. `get_healing_power()` feeds any healing skill, but the
  authored content that makes a relic a full healer identity is still thin.

### P2 - Resist coverage

- Damage schools exist for frost/poison/shadow, but current skill/data damage
  schools are mostly physical/magical/fire/holy/lightning/arcane. Frost/poison/
  shadow content should be authored before those wards matter in play.
- `true` damage and `reflected` damage are not schools; they bypass the ward
  lane by design. A future unresistable school needs an explicit design entry,
  not a string that silently falls through.
- `HealthComponent` still uses `get_magic_resistance()` as the armor pool for
  magical hits; school wards layer after it. If magical armor and magical resist
  should be one number, that is a separate consolidation.

### P2 - Movement speed

- Class movement values are a first pass (rogue +6%, bender +4%, DD +2%, healer
  +1%, tank -4%). They need playtesting against mount profiles and arena
  normalization.
- `movement_speed_multiplier` is read directly with no clamp; a stacked slow can
  reach zero and a haste can outrun the camera. The attack-speed lane has a
  ceiling; movement should get an explicit floor/ceiling in `StatId`.
- Mounts already own a movement profile; there is no shared "effective movement
  speed" tooltip that explains class + mount + status effect + terrain.

## 4. Receipts

- `game/tests/test_damage_ranges.gd` - 18 checks: enemy body band, inverted
  bounds, enemy main-hand addition, magical skill band, live Fireball data,
  crit on weapon/enemy/skill rolls, forced-crit `Skill.calculate_damage`, and
  bandit/Clockwork Saint two-handed + wrist loadouts.
- `game/tests/test_equipment_power.gd` - 37 checks: random weapon band,
  inverted bounds, weapon cadence/crit, armor resists, shield block lane,
  two-handed + normal shield rejection, two-handed + wrist acceptance,
  loaded-save hand migration, broken gear.
- `game/tests/test_dual_wield.gd` - 49 checks: auto off-hand placement, no
  shield lane, 15% cadence + 6% power + half off-hand band, both weapons' crit,
  shield closes the posture, two-hander rejects an off-hand one-hander,
  staff/wand magical power and crit, relic healing power and crit, saved
  dual-wield and illegal 1H+2H load migration, and every `WeaponType` 1..13 has
  an authored record plus both legal lance/relic hand variants and the 2H
  scythe.
- `game/tests/test_combat_resists.gd` - school vocabulary, damage pipeline,
  EnemyData seeding, status-effect wards, class movement/wards, gear data.
- `game/tests/test_instance_contract.gd` - 5 vs 50 -> 41, 30 vs 60 -> 54, gap
  retention extremes.
- `game/tests/probe_arena_bridge.gd` - live retune when the reference changes
  and restoration when a fighter leaves.
- `game/tests/probe_bout_host.gd` - the production `player_left` path drops the
  departed fighter's level and participant seat from a hosted bout.
- `game/tests/test_attack_speed.gd` / `test_crit_system.gd` - class cadence and
  crit lanes still pass through the shared formulas (22/22 and 36/36).
- `game/tests/test_data_naming_lint.gd` / `test_item_catalog.gd` - 72/72 data
  lint and 12/12 catalog laws after the new two-handed, wrist, dual-wield and
  weapon-family data.
- `game/tests/test_character_fresh_kit.gd` - starter-kit item copy through
  `Item.from_dict()` (run after the new schema fields).
