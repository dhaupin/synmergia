# PRD: Canonical Combat - As-Built and Gap Ledger

> **Status:** PARTIAL (canonical lanes wired 2026-11-16; gaps below are real,
> not hypothetical)
> **Law:** `game/core/schemas/stat_id.gd` is the vocabulary; `CombatMath` is the
> hit/mitigation authority; `EnemyData.apply_stats_to` and
> `Item.get_total_stats` are the seeding paths. Where this document and code
> disagree, code wins.
> **Related:** `labs/prd-blessings.md`, `labs/prd-bout-host.md`,
> `labs/data-authoring-baseline.md`.

## 1. What Is Shipped

| Piece | Truth |
| --- | --- |
| Weapon damage band | `PlayerBase.get_attack_power()` rolls `randi_range(min, max)` on every swing. `Item.get_damage_range()` sorts authored bounds, so a max below min (or min above max) cannot invert a roll. Broken weapons contribute 0. |
| Weapon cadence | `Item.attack_speed` is a multiplier on the body's class/enemy cadence. `1.0` rides the default; `1.2` is 20% faster. `PlayerBase.get_attack_speed()` applies it after the `StatId` agility/class formula and clamps at `MAX_ATTACK_SPEED_MULT`. |
| Weapon crit | `Item.crit_chance` / `crit_damage` are flat deltas added to the body's `StatId` crit delta. `PlayerBase.get_crit_chance()` / `get_crit_multiplier()` read the main hand; broken weapons contribute 0. Magical and heal crits still use their INT/WIS axes. |
| Weapon data | All 82 weapon records now carry `crit_chance` / `crit_damage`; the 77 hand weapons were corrected from `equip_slot = 8` (off hand) to `MAIN_HAND = 7`; the 5 shields remain `OFF_HAND = 8`. Rogue weapons lean crit, DD/tank lanes lean cadence, and rarity/level add a little of both. |
| School resists | `StatId.DAMAGE_SCHOOLS` is physical, magical, fire, frost, lightning, poison, arcane, holy, shadow. Each school has a canonical `resist_*` flat stat, clamped by `MAX_RESIST = 0.90`. `CombatMath.calculate_mitigation(..., school_resist)` layers the ward after armor and flat reduction. |
| Resist seeding | `Item.damage_resists` folds into `get_total_stats()`; `EnemyData.damage_resists` seeds the same keys in `apply_stats_to`; `CharacterClass.damage_resists` folds in `PlayerBase._apply_class_crit_identity`; `StatusEffect.damage_resists` adds/removes through `_apply_combat_modifiers`. |
| Armor data | All 77 armor records now author `damage_resists` by armor type (cloth/leather/mail/plate), with a class-lane bonus and rarity/level scaling. Shields author physical/fire wards. |
| Enemy data | Thematic templates author per-school wards: Void Lord (shadow/arcane), Tidebound Ancient (frost/physical), Blight-Lizard (poison), Clockwork Saint (lightning/physical), Sporebound Matriarch (poison), Training Dummy (physical/fire). |
| Shield system | A shield is an `OFF_HAND` item with `weapon_type = SHIELD`; `CombatMath._has_shield` now requires that type (an off-hand orb/tome is not a shield) and a broken shield stops blocking. Shields carry `armor_value`, `block_rating`, and `damage_resists`. `arm_shield_iron_wall` / `arm_shield_haven_wall` were corrected from shoulders to off hand; Haven Wall's dead `stats.armor`/`block_chance` became `armor_value = 14` / `block_rating = 21.6`. |
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
3. **Damage is rolled, then mitigated.** The weapon band is sampled once per
   swing; armor, flat reduction, then the school ward reduce that sample. The
   result never drops below 1 for a landed hit.
4. **Shields are armor you hold.** An off-hand shield contributes armor,
   block rating, and wards; a non-shield off hand contributes none of the block
   lane. Block chance is still the `CombatBalanceData` formula, not a second
   hardcoded table.
5. **Arena power is bout-local and reference-relative.** The highest current
   level in the room is the reference; every lower fighter gets a normalized
   stat book derived from its pre-bout snapshot. Real stats are restored at bout
   end or on departure.
6. **A stronger fighter keeps the edge.** Normalization pulls lower levels
   close but never to parity; 20% of the gap survives by design.

## 3. Gaps

### P0 - Shield behavior is still shallow

The canonical item lane is live, but these are not:

- Directional/facing blocks, guard arcs, and shield-facing visuals.
- Block stamina cost, guard break, stagger, and shield durability loss.
- Shield-specific skills (bash, wall, reflect) reading the shield's block
  rating/ward rather than a generic off-hand.
- Two-handed weapons, dual wield, and shield-plus-weapon legality. Every hand
  weapon is now `MAIN_HAND`; nothing prevents a main-hand weapon plus shield
  from being equipped together (which is intended for sword-and-board), but
  nothing enforces a two-handed exception either.

### P1 - Enemy and class defense lanes are thin

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
- Generic weapons with `required_class = ""` have no role lean; their cadence
  and crit come from type/rarity/level only.
- `attack_speed` still carries a legacy "attacks per second" comment in some
  tooling/UI. The runtime treats it as a multiplier; the label should be
  corrected wherever it is shown to players.
- Weapon damage is rolled inside `get_attack_power()`. A caller that invokes
  that accessor twice for one swing would roll twice; today the basic-attack
  path reads it once, but future multi-hit skills should cache the roll for the
  swing.

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

- `game/tests/test_equipment_power.gd` - random weapon band, inverted bounds,
  weapon cadence/crit, armor resists, shield block lane, broken gear.
- `game/tests/test_combat_resists.gd` - school vocabulary, damage pipeline,
  EnemyData seeding, status-effect wards, class movement/wards, gear data.
- `game/tests/test_instance_contract.gd` - 5 vs 50 -> 41, 30 vs 60 -> 54, gap
  retention extremes.
- `game/tests/probe_arena_bridge.gd` - live retune when the reference changes
  and restoration when a fighter leaves.
- `game/tests/probe_bout_host.gd` - the production `player_left` path drops the
  departed fighter's level and participant seat from a hosted bout.
- `game/tests/test_attack_speed.gd` / `test_crit_system.gd` - class cadence and
  crit lanes still pass through the shared formulas.
