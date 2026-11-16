# Data / Engine Separation

> **Status:** ACTIVE 2026-11-15. The Fixer board, starter kits, Academy
> prices, housing economy, bout rewards, agent slots and payment SKUs are
> extracted; the remaining ledger is a deliberate queue, not a rewrite mandate.
>
> **Law it obeys:** [`data-authoring-baseline.md`](./data-authoring-baseline.md)
> sec 0 and the core/data boundary in [`AGENTS.md`](../AGENTS.md). This doc is
> the extraction ledger and the "leave it alone" list.

## 1. The line

`game/core/` owns **how**. `game/data/` owns **what**.

| Engine owns | Data owns |
|---|---|
| Schema shape (`@export` fields) and validation | Values that fill those fields |
| Services, algorithms, lifecycle, persistence | Catalogs, tiers, prices, item ids, spawn rosters, asset paths |
| Protocol and security limits | Authored content and tuning a designer can change |
| Generic loader paths and registries | The records those loaders resolve |
| Safe defaults that keep a missing record from crashing | The shipped record that overrides the default |
| UI toolkit and theme mechanics | Game-specific copy, icons and palettes when they are content |

The practical test stays the same: **if changing the value changes an
algorithm, a protocol, or a security rule, it stays in core. If a designer can
change it without changing behavior, it belongs in data.**

A default is not a second data table. A missing record may degrade to a
declared default or a named refusal, but a service must not carry a duplicate
catalog "just in case" the record is absent.

## 2. Deliberately engine-side

These are not extraction targets unless their ownership changes:

- **Cooldowns and rate limits.** Action throttles are protocol protection
  (`CooldownService`, QoS, anti-cheat). They stay code-owned.
- **Frame and network limits.** Packet sizes, reassembly caps, tick budgets,
  cache sizes and audit-log caps are infrastructure.
- **Schema defaults.** A field's default documents the contract; content
  overrides it. Moving the default into one `.tres` would make the schema
  depend on content.
- **Enum vocabulary and role identity.** `GameTier`, `StatId`,
  `CharacterClass.Role`, hitbox kinds and station enum ids are engine
  vocabulary; the records choose among them.
- **UI theme mechanics.** Control construction, focus behavior, layout and
  accessibility plumbing stay in UI code. Game-specific palettes and copy move
  only when a designer is expected to re-theme them.
- **Generic loader paths and id rules.** `DataService` owns `res://data/...`
  and the filename==id convention; records do not carry a second routing table.
- **Algorithm constants.** A clamp, a formula coefficient, a decay function
  or a security threshold is behavior, not content.

## 3. Extraction ledger

| System | Hardcoded today | Decision |
|---|---|---|
| Underdeck Fixer roll board | `BlackMarketService.ROLLS`, currency id, tier prices, LootTable paths | **EXTRACTED** this pass: `data/balance/black_market.tres` |
| Starter kits | Role -> item ids and starting gold tables | **EXTRACTED** this pass: `data/balance/starter_kits.tres` |
| Skill Academy economy | Book price, respec base and per-point costs | **EXTRACTED** this pass: `data/balance/academy_balance.tres` |
| Housing economy | Plot price, guard/ankh costs, default house tier, no-data house fallback | **EXTRACTED** this pass: `data/balance/housing_balance.tres`; tier costs already data |
| Bout rewards | XP and gold for bout/trial/royale | **EXTRACTED** this pass: `data/balance/bout_rewards.tres` |
| Agent slot ladder | Sigil prices per seat | **EXTRACTED** this pass: `data/balance/agent_slots.tres` |
| Scope bands | Six verb band tables in `scope_band.gd` | LATER: combat tuning; extract with a schema when designers own it |
| Skill special-case ids | `debuff_taunt` / aggro-horn string checks in `skill.gd` | NEEDS DESIGN: replace with authored flags/tags, not a data file |
| Flywheel weights | Chaos weights and momentum constants | LATER: simulation tuning; frame may keep defaults |
| Village bout props | Hardcoded zone ids/colors and prop batches | LATER: world-content builder, not a service constant |
| Lobby copy and zone blurbs | `lobby_ui.gd` mode labels | LATER: presentation content, low risk |
| UI palette | `ui_styles.gd` colors | ENGINE unless a theme selector needs data |
| Payment SKU catalog | Two provider `SKUS` / `SKU_CATALOG` arrays | **EXTRACTED** this pass: `data/balance/payment_skus.tres`; providers keep their id mappings |
| Kill reward curve | XP/gold coefficients, grey spread, scale floor/cap | **NEXT**: balance record; formula stays in the service |
| Container expansion costs | Two code copies of the tier ladder; `container_configs.tres` says costs are code-fixed | **NEXT**: one data table; remove both duplicates |
| Sigil sink catalog | Nine `SINKS` rows with prices, grants and copy | **NEXT after design**: resolve the mount source mismatch first |
| Vault expansion | Slots/step, gold/slot, personal/guild caps | **NEXT**: base values and caps to data; 1.5x formula stays |
| World content placement | Globe batches/manifest, biome density/palette, arena covers | LATER: world-content schema, not balance |
| Presentation asset registries | Audio sound maps, icon fallbacks | LATER: asset routing; only if designers add content |
| Blacksmith repair pricing | Six `@export` defaults plus rarity multipliers | **NEXT**: repair record; forge chance record stays separate |
| Vendor price multipliers | Location type -> multiplier match; buy/sell fallbacks | **NEXT**: pricing record; per-NPC overrides stay |
| Revive tuning | Service constants duplicate `GameConfig`; ranges disagree (5 vs 10) | NEEDS DESIGN: one owner, then extract after the drift is resolved |
| Ferry skiff fare | `DEFAULT_SKIFF_TICKET = 25` | SMALL: route/vehicle record if fares become per-route |
| Faction war terms | 10k declaration cost, 24h cooldown; cooldown duplicated in `GameConfig` | SMALL: faction balance record; declaration gate stays |
| Daily blessing tuning | +20% might, +5 levels | SMALL: blessing balance record; earned-day gate stays |
| Weather event fallback catalog | Built-in `storm_pack` / `aurora_window` dictionaries duplicate `data/weather_events` | **NEXT**: one declared default or a refusal; remove the duplicate |

The ledger is intentionally shallow. Do not promote a row to "do it now" just
because the value is numeric; the question is ownership, not type.

## 4. First slice: the Fixer's board

`BlackMarketService` still owns:

- the weighted draw and rarity boost application;
- the debit, grant, and refund ledger;
- the rate gate and the refusal messages.

`game/data/balance/black_market.tres` owns:

- the board id and currency id;
- each roll's `roll_id`, label, sigil price, LootTable path and rarity boost.

`DataService` registers `data/balance/` by id, so the service asks for
`black_market` instead of carrying a literal array. A missing or malformed
board returns a named refusal; there is no duplicate board fallback.

The receipt is `game/tests/test_black_market_gamble.gd`: it now proves the
service board matches the data record, that every pool path comes from that
record, and that every entry resolves through `DataService`.

## 5. Second slice: starter kits

`StarterKitService` still owns:

- the fresh-confirm / saved-progress gate;
- the inventory-ready defer and the one-kit-per-character guard;
- the item construction and the gold grant.

`game/data/balance/starter_kits.tres` owns:

- the role -> item-id table;
- the role -> starting-gold table.

A missing or malformed record refuses the grant instead of falling back to a
role-0 kit. The receipt is `game/tests/test_character_fresh_kit.gd`: it asserts
the record resolves through `DataService` and that roles 0, 2 and 4 carry the
expected data.

## 6. Third slice: the Skill Academy

`SkillAcademyService` still owns:

- the book catalog and purchase gate;
- the skill/stat respec flow and its gold removal;
- the readable failure reasons.

`game/data/balance/academy_balance.tres` owns:

- the common book price;
- the skill-respec base and per-point costs;
- the stat-respec base and per-point costs.

A missing record makes the price reads fail closed instead of selling books or
respecs for free. The receipt is `game/tests/test_skill_academy_live.gd`: it
compares the service prices, book cost, and both respec formulas against the
record.

## 7. Fourth slice: housing

`HousingService` still owns:

- plot registration and purchase gates;
- placement validation, guard/ankh spawning and refunds;
- house construction and spawn failure handling.

`game/data/balance/housing_balance.tres` owns:

- the default plot price;
- the house-guard and personal-ankh prices;
- the default house tier id.

The demo globe plot no longer carries its own price literal, and an unknown
house tier is refused rather than raising a built-in fallback cottage. The
receipts are `game/tests/test_house_catalog.gd` (data record, tier cost,
unknown-tier refusal) and `game/tests/test_placement_system.gd` (guard/ankh
charges read from the record).

## 8. Fifth slice: bout rewards

`BoutHostService` still owns:

- who wins, draws and loses;
- the XP/gold grant and the toast copy;
- trial dummy setup and achievement/quest credit.

`game/data/balance/bout_rewards.tres` owns the win, consolation, trial
and royale amounts. A missing record refuses every payout instead of
paying zero or guessing. The receipts are `probe_bout_host.gd` and
`probe_trial_bout.gd`: both resolve the record through `DataService`,
assert the host holds that same record, and compute their expected
payout from it.

## 9. Sixth slice: agent slots

`AgentRoster` still owns:

- the free floor and the design cap;
- the one-time debit/grant gate and persistence;
- the refusal reasons.

`game/data/balance/agent_slots.tres` owns the sigil price per paid seat.
A missing record refuses an unlock with `agent slot pricing unavailable`
rather than granting a free seat. The receipt is
`game/tests/test_agent_roster.gd`: it resolves the record and walks the
whole ladder using the authored prices.

## 10. Seventh slice: payment SKUs

`ManualPaymentProvider` and `WebhookPaymentProvider` still own:

- which SKU ids their processor sells (the provider mapping);
- checkout state, order binding, fulfillment and webhook verification;
- the refusal paths.

`game/data/balance/payment_skus.tres` owns every product row: sku id,
display name, sigil amount and price label. Both providers resolve their
mapped slices through `DataService.get_payment_sku_catalog()`. A missing,
malformed or partially mapped record returns no catalog and checkout
refuses with `Payment catalog unavailable`; there is no code fallback.
The receipt is `game/tests/test_payment_skus.gd`: it proves both providers
resolve the six shared rows, keep their existing products and amounts,
still refuse an unknown SKU, and fail closed when the record is removed.

## 11. Ranked candidate queue (not yet extracted)

The 2026-11-15 sweep added these to the ledger so the next pass starts here,
not from a fresh grep. Rank is value/risk, not a promise to extract all of
them. The two skill lanes are already issue #102 and are not repeated here.

1. **Kill reward curve - NEXT.** `kill_rewards.gd` carries XP/gold per enemy
   level, per killer level, the grey spread and the scale floor/cap. Its own
   comment calls it one tunable table. Move those values to a balance record;
   keep the credit resolution, level-gap formula and grant path in the service.
   Receipt: resolve the record through `DataService`, compare the computed
   payout at representative level gaps, and prove a missing record refuses
   rather than paying zero or guessing.

2. **Container expansion costs - NEXT.** The ladder is duplicated in
   `container_schema.gd` (`EXPANSION_COSTS`) and
   `container_config_data.gd` (`DEFAULT_EXPANSION_COSTS`), while
   `data/containers/container_configs.tres` says expansion costs are fixed in
   code. Put the tier costs in the existing container config record, remove
   both code copies, and keep slot limits/expansion behavior in the schema.
   Receipt: every container type reads the same authored tier ladder and a
   malformed record fails closed.

3. **Sigil sink catalog - NEXT after design.** `sigil_sink_service.gd`
   (`SINKS`) owns nine rows with sink ids, prices, grant quantities and flavor
   copy. The service keeps the debit/grant/refund gates that already exist;
   the rows belong in data. Do this only after resolving the known mismatch:
   the catalog prices mounts whose own data marks them `DROP`. One record, not
   a second code table.

4. **Vault expansion - NEXT.** `vault_service.gd` owns slots per step, gold
   per slot and the personal/guild caps. Move the base values and caps to a
   vault balance record; keep the exponential 1.5x curve and the 10M cap in
   the service because they are algorithm behavior. Receipt: the service
   computes costs from the record and a missing record refuses expansion.

5. **World content placement - LATER, separate track.** `globe_world.gd`
   carries enemy/guard/NPC batches, gate/plot placements and the content
   manifest; `underworld_provider.gd`, `moon_provider.gd` and
   `terrain_provider.gd` carry biome density/palette tables; `arena_instance.gd`
   carries cover layouts. This is authored world content, not a balance record.
   It needs one world-content schema and a record per world/arena; do not fold
   it into `balance/`. The ledger's village bout props row is a subset.

6. **Presentation asset registries - LATER.** `audio_service.gd` maps sound
   names to WAV paths; `icon_resolver.gd` maps categories to fallback icons.
   These are engine asset routing today. Move them only when designers are
   expected to add or replace sounds/icons without touching code; otherwise
   they are correctly engine-side.

### Additional finds from the same sweep

- **Blacksmith repair pricing - NEXT.** `blacksmith_service.gd` still owns
  six `@export` defaults (`base_repair_cost_per_durability`, weapon/armor/
  accessory multipliers, bulk threshold/discount) and a hardcoded rarity
  multiplier ladder (1.25/1.5/2/3). The existing `forge_balance.tres` owns the
  UPGRADE gamble, not repair pricing. Add a repair-pricing record; keep the
  repair eligibility gate and arithmetic in the service.
- **Vendor price multipliers - NEXT.** `vendor_service.gd` hardcodes the
  location ladder (town 1.0, outpost 1.25, village 0.9, dungeon 2.0, capital
  1.5) and fallback buy/sell multipliers. Item prices and per-NPC
  `buy_multiplier`/`sell_multiplier` are already data. Move the global pricing
  table to data; keep the per-offering and per-NPC overrides in their records.
- **Revive tuning - NEEDS DESIGN.** `respawn_service.gd` and
  `GameConfig.Respawn` carry overlapping revive constants, and the ranges
  disagree: the service uses 5.0 while `GameConfig` says 10.0. Pick one owner
  and one value before extracting. This is a drift bug first, a data slice
  second.
- **Ferry skiff fare - SMALL.** `DEFAULT_SKIFF_TICKET = 25` is the only fare
  value, and the dock UI reads it from the service. Extract only when fares
  become per-route or per-vehicle; a single constant does not earn a record.
- **Faction war terms - SMALL.** `WAR_DECLARATION_COST = 10000` and a 24h
  cooldown; the cooldown is duplicated in `GameConfig`. Move the terms to a
  faction balance record once faction diplomacy gets a real tuning pass; keep
  the declaration gate and war state machine in the service.
- **Daily blessing tuning - SMALL.** `BLESSED_DAMAGE_MULTIPLIER = 1.2` and
  `BLESSED_LEVEL_BONUS = 5` are the blessing's whole balance. They are
  candidates only if the sky blessing becomes a designer-tuned system; the
  earned-day/wheel gate must stay in `SignService`.
- **Weather event fallback catalog - NEXT.** `weather_event_service.gd`
  carries `_builtin_storm_pack()` and `_builtin_aurora_window()` dictionaries
  that duplicate the shipped `data/weather_events/*.tres` rows almost exactly.
  This is the duplicate fallback catalog the ledger forbids, not a schema
  default. Decide whether an empty catalog is a hard refusal or one minimal
  declared default, remove the other copy, and add a missing-data receipt.

`GameConfig` is intentionally not a single extraction target. It is a broad
runtime configuration surface with protocol, security and gameplay values; a
future audit should split it by owner, not move the file into one `.tres`.

Still explicitly out of scope: cooldowns and rate limits, the status-effect
control maps, `StatId`/`GameTier` vocabulary, schema defaults and the UI island
registry. They are behavior, protocol or routing, not content.

## 12. Next-pass rule

One pass = one domain, one schema, one record, one receipt.

1. Name the owner: service behavior or designer content.
2. Add the `@export` shape to `game/core/schemas/`.
3. Add the record under the matching `game/data/` family.
4. Resolve it through `DataService`; remove the duplicate literal table.
5. Extend the existing receipt or add one focused test.
6. Update this ledger.

Do not build a generic "all balance" god record. A record earns its schema by
having one owner and one reader; a bag of unrelated numbers is harder to
validate than the constants it replaced.
