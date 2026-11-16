# Data / Engine Separation

> **Status:** ACTIVE 2026-11-16. The Fixer board, starter kits, Academy
> prices, housing economy, bout rewards, agent slots, payment SKUs and combat
> balance are extracted; the remaining ledger is a deliberate queue, not a
> rewrite mandate.
> The 2026-11-16 census passes add the world-event scheduler, royale storm
> ladder, container capacity drift, faction ranks, kill-streak rewards, chat
> channel metadata and party XP share below.
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
| Combat hit table and baseline regen | Base hit/dodge/parry/block curves, caps, block value and regen rates in `CombatMath` / `TickService`; `GameConfig.Combat` was a dead duplicate | **EXTRACTED** this pass: `data/balance/combat_balance.tres`; the services keep the roll/order and arithmetic |
| Royale storm ladder | Five hold/shrink/radius/damage phases, the minimum radius and storm defaults in `instance_contract.gd`; zones override only start and scale | **NEXT**: phases to a storm record; plan/lerp/damage math stays in the contract |
| Agent slot ladder | Sigil prices per seat | **EXTRACTED** this pass: `data/balance/agent_slots.tres` |
| Scope bands | Six verb band tables in `scope_band.gd` | LATER: combat tuning; extract with a schema when designers own it |
| Skill special-case ids | `debuff_taunt` / aggro-horn string checks in `skill.gd` | NEEDS DESIGN: replace with authored flags/tags, not a data file |
| Flywheel weights | Chaos weights and momentum constants | LATER: simulation tuning; frame may keep defaults |
| Village bout props | Hardcoded zone ids/colors and prop batches | LATER: world-content builder, not a service constant |
| Lobby copy and zone blurbs | `lobby_ui.gd` mode labels | LATER: presentation content, low risk |
| UI palette | `ui_styles.gd` colors | ENGINE unless a theme selector needs data |
| Payment SKU catalog | Two provider `SKUS` / `SKU_CATALOG` arrays | **EXTRACTED** this pass: `data/balance/payment_skus.tres`; providers keep their id mappings |
| Kill reward curve | XP/gold coefficients, grey spread, scale floor/cap | **NEXT**: balance record; formula stays in the service |
| Party XP share | `share_xp` hardcodes the 0.1 bonus; `GameConfig.Party` XP knobs are dead | NEEDS DESIGN: one owner; keep the split formula in the service |
| Container configuration and expansion costs | Three copies of the container rows (`container_schema.BASE_CONFIG`, `container_config_data.containers`, `container_configs.tres`), two cost ladders, and a parallel `GameConfig.Inventory` capacity set (20 base / 12 equipment / 98 bank) read by `InventoryComponent`, whose bank size is hardcoded 98 while the record says 24 / 16 / 100 | **NEXT**: one data record; settle the live capacity owner first, then make both read the same rows and remove the code copies |
| Sigil sink catalog | Nine `SINKS` rows with prices, grants and copy | **NEXT after design**: resolve the mount source mismatch first |
| Vault expansion | Slots/step, gold/slot, personal/guild caps | **NEXT**: base values and caps to data; 1.5x formula stays |
| World content placement | Globe batches/manifest, biome density/palette, arena covers | LATER: world-content schema, not balance |
| Presentation asset registries | Audio sound maps, icon fallbacks | LATER: asset routing; only if designers add content |
| Blacksmith repair pricing | Six `@export` defaults plus rarity multipliers | **NEXT**: repair record; forge chance record stays separate |
| Vendor price multipliers | Location type -> multiplier match; buy/sell fallbacks | **NEXT**: pricing record; per-NPC overrides stay |
| Revive and respawn policy | Service constants duplicate `GameConfig` (range 5 vs 10); two seven-row context tables for abuse and ability | NEEDS DESIGN: resolve owners, then one respawn-rules record |
| Ferry skiff fare | `DEFAULT_SKIFF_TICKET = 25` | SMALL: route/vehicle record if fares become per-route |
| Faction war terms | 10k declaration cost, 24h cooldown; cooldown duplicated in `GameConfig` | SMALL: faction balance record; declaration gate stays |
| Daily blessing tuning | +20% damage/heal/XP, +5 levels | SHIPPED: `data/balance/blessing_balance.tres`; earned-day gate stays in `SignService` |
| Weather event fallback catalog | Built-in `storm_pack` / `aurora_window` dictionaries duplicate `data/weather_events` | **NEXT**: one declared default or a refusal; remove the duplicate |
| World-event scheduler catalog | Three hardcoded scheduler rows in `world_service.gd`; the scheduler ignores the authored `data/events` family | **NEXT**: one event roster plus schedule fields; keep draw/lifetime in the service |
| Faction reputation ladder | Seven rank thresholds and labels; the service clamp disagrees with `GameConfig` bounds | NEEDS DESIGN: resolve the drift, then faction balance record |
| Kill-streak rewards | Thresholds, XP/gold coefficients and announce gate in `GameConfig.Respawn` | SMALL: death/kill-streak balance record |
| Chat channel metadata | Twelve-row name/range/colour/prefix table, mute labels, and a second five-row tab name/colour table in `chat_ui.gd` | LATER: presentation content; channel routing stays engine |

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
The 2026-11-16 census rows sit outside this numbered order: the world-event
scheduler is NEXT, the rest are SMALL/LATER or blocked on design.

1. **Kill reward curve - NEXT.** `kill_rewards.gd` carries XP/gold per enemy
   level, per killer level, the grey spread and the scale floor/cap. Its own
   comment calls it one tunable table. Move those values to a balance record;
   keep the credit resolution, level-gap formula and grant path in the service.
   Receipt: resolve the record through `DataService`, compare the computed
   payout at representative level gaps, and prove a missing record refuses
   rather than paying zero or guessing.

2. **Container configuration and expansion costs - NEXT.** The container
   rows are copied three times: `container_schema.gd` (`BASE_CONFIG`),
   `container_config_data.gd` (`containers`), and the authored
   `data/containers/container_configs.tres`. The tier ladder is copied twice
   (`EXPANSION_COSTS` and `DEFAULT_EXPANSION_COSTS`), and
   `container_config_data.load_config()` silently falls back to its built-in
   copy when the record is missing. The `.tres` itself says expansion costs
   are fixed in code. Put the full container rows and tier costs in the
   existing record, remove both code config copies and the silent fallback,
   and keep slot limits/expansion behavior in the schema. Receipt: every
   container type reads the same authored rows and tier ladder; a missing or
   malformed record fails closed instead of using a second catalog. The
   mounted `InventoryComponent` is a fourth capacity surface: it reads
   `GameConfig.Inventory` (20 base slots, 12 equipment slots, 5 bags of 20,
   98 bank slots, 4 expansions) while the container record says 24 inventory,
   16 equipment and 100 bank slots. Its bank size and expansion step are
   hardcoded 98, and `GameConfig.Inventory.BANK_SLOTS` has no reader. Settle
   whether the mounted component or `SlotService` is the live capacity owner
   before extraction, then bind both to the same rows.

3. **Royale storm ladder - NEXT.** `instance_contract.gd` `STORM_PHASES`
   carries five rows of hold seconds, shrink seconds, radius ratio and damage
   per second, plus `MIN_STORM_RADIUS_M` and `DEFAULT_STORM_START_SECONDS`.
   `bout_rules()` already applies zone overrides for start and scale, so the
   missing piece is the phase ladder, not the contract defaults. Keep
   `storm_plan`, `storm_radius_at`, `storm_damage_at`, the true-zero final
   circle and the minimum-radius floor in the contract; move the phase rows
   to one storm record (or per-zone phases if maps diverge). Receipt: authored
   phases drive the plan, and a missing or malformed ladder refuses the bout
   instead of falling back to a second code ladder.

4. **Sigil sink catalog - NEXT after design.** `sigil_sink_service.gd`
   (`SINKS`) owns nine rows with sink ids, prices, grant quantities and flavor
   copy. The service keeps the debit/grant/refund gates that already exist;
   the rows belong in data. Do this only after resolving the known mismatch:
   the catalog prices mounts whose own data marks them `DROP`. One record, not
   a second code table.

5. **Vault expansion - NEXT.** `vault_service.gd` owns slots per step, gold
   per slot and the personal/guild caps. Move the base values and caps to a
   vault balance record; keep the exponential 1.5x curve and the 10M cap in
   the service because they are algorithm behavior. Receipt: the service
   computes costs from the record and a missing record refuses expansion.

6. **World content placement - LATER, separate track.** `globe_world.gd`
   carries enemy/guard/NPC batches, gate/plot placements and the content
   manifest; `underworld_provider.gd`, `moon_provider.gd` and
   `terrain_provider.gd` carry biome density/palette tables; `arena_instance.gd`
   carries cover layouts. This is authored world content, not a balance record.
   It needs one world-content schema and a record per world/arena; do not fold
   it into `balance/`. The ledger's village bout props row is a subset.

7. **Presentation asset registries - LATER.** `audio_service.gd` maps sound
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
- **Revive and respawn policy - NEEDS DESIGN.** `respawn_service.gd` and
  `GameConfig.Respawn` carry overlapping revive constants, and the ranges
  disagree: the service uses 5.0 while `GameConfig` says 10.0. The service
  also owns two seven-row context tables: `_abuse_configs` (per-hour
  thresholds, karma penalties, cooldowns) and `_ability_configs` (who may
  revive, self-revive limits and cooldowns) for `open_world`, `dungeon`,
  `raid`, `pvp_zone`, `arena`, `battleground` and `contested`. These are one
  policy surface, not just stray constants, and no focused test covers
  `set_context`, the ability gates or the abuse thresholds. Pick one owner
  and one set of values first; if designers own it, ship one respawn-rules
  record keyed by context and keep the state machine, cooldown book and
  gates in the service.
- **Ferry skiff fare - SMALL.** `DEFAULT_SKIFF_TICKET = 25` is the only fare
  value, and the dock UI reads it from the service. Extract only when fares
  become per-route or per-vehicle; a single constant does not earn a record.
- **Faction war terms - SMALL.** `WAR_DECLARATION_COST = 10000` and a 24h
  cooldown; the cooldown is duplicated in `GameConfig`. Move the terms to a
  faction balance record once faction diplomacy gets a real tuning pass; keep
  the declaration gate and war state machine in the service.
- **Daily blessing tuning - SHIPPED.** The multipliers and effective-level
  bonus now live in `data/balance/blessing_balance.tres`
  (`BlessingBalanceData`). `SignService` keeps the wheel and earned-day gate;
  its `BLESSED_*` accessors read the record, so damage, heal, XP and level
  tuning cannot drift back into service constants.
- **Weather event fallback catalog - NEXT.** `weather_event_service.gd`
  carries `_builtin_storm_pack()` and `_builtin_aurora_window()` dictionaries
  that duplicate the shipped `data/weather_events/*.tres` rows almost exactly.
  This is the duplicate fallback catalog the ledger forbids, not a schema
  default. Decide whether an empty catalog is a hard refusal or one minimal
  declared default, remove the other copy, and add a missing-data receipt.

### 2026-11-16 census: scheduler, faction, death, chat

A second census pass looked for authored tables still living in services. The
four rows added above are recorded here, not extracted. The world-event
scheduler is the first of them that should get a schema; the other three are
lower value or blocked on a design decision.

- **World-event scheduler catalog - NEXT.** `world_service.gd`
  `_setup_event_scheduler()` owns three rows (`double_xp`, `double_loot`,
  `invasion`) with display names, durations, min/max intervals, weights and
  time-of-day restrictions. The scheduler never reads `data/events/`;
  `EventService` reads that family for modifiers. `_apply_event_effects()`
  then keys behavior off the literal ids, and the first two effects are
  stubs. That is a second event catalog and a second dispatch vocabulary.
  The service should keep the weighted draw, active lifetime, persistence and
  effect application; data should own the roster and schedule fields. Reuse
  `EventData` (adding duration/weight/min_interval/max_interval/
  time_restrictions) or one schedule record referencing event ids; do not keep
  both lists. Receipt: resolve the authored roster, draw an authored event
  without code changes, and prove an empty or malformed roster schedules
  nothing.

- **Faction reputation ladder - NEEDS DESIGN (drift first).**
  `faction_manager.gd` `get_reputation_rank()` hardcodes seven thresholds
  (9000/6000/3000/1000/0/-999/-3000) and their labels. The same service clamps
  reputation to `-10000..10000`, while `GameConfig.FactionConfig` declares
  `MIN_REPUTATION = -100` / `MAX_REPUTATION = 100` and is not read here. That
  is drift, not a clean extract. Pick one bounds owner and one value; if
  designers tune ranks, put the ladder in the faction balance record with the
  war terms. Keep the reputation mutation and rank-transition toast in the
  service. Receipt: rank labels and clamp agree with the record, and a missing
  or malformed ladder refuses to invent a rank.

- **Kill-streak rewards - SMALL.** `GameConfig.Respawn` owns
  `KILL_STREAK_THRESHOLDS = [3, 5, 10, 25, 50]`,
  `KILL_STREAK_XP_MULTIPLIER = 0.1`, `KILL_STREAK_GOLD_BONUS = 10` and the
  announcement threshold; `death_features.gd` is the only reader. A threshold
  ladder plus coefficients is one kill-streak balance record, not four
  unrelated numbers. Move it when death tuning gets a design pass; keep the
  streak state, kill credit and grant path in the service. Receipt:
  thresholds and computed bonus match the record; a missing record disables
  the bonus rather than inventing a ladder. The adjacent griefing threshold,
  window and protection duration are anti-harassment policy, not part of this
  ladder; leave them engine-side unless product wants them authorable.

- **Chat channel metadata - LATER.** `chat_service.gd` `_channel_info` is a
  twelve-row `Channel`-keyed table of display name, range, colour and prefix;
  `MUTE_LABELS` repeats the readable names. Channel ids, send/receive gates,
  history caps and spam cooldowns are protocol and stay in core. The labels,
  colours, prefixes and say/yell reach are content a designer can re-theme.
  Extract only if chat presentation becomes authorable; otherwise this is the
  same call as the UI palette and lobby copy. Before extracting anything,
  resolve the config drift: `GameConfig.Chat.MESSAGE_COOLDOWN` (2s) and
  `MAX_WHISPERS_PER_MINUTE` (20) have no readers, while the live spam gate is
  `SPAM_COOLDOWN_MS = 500` with `SPAM_THRESHOLD = 5`.

### 2026-11-16 census: follow-up

- **Party XP share - NEEDS DESIGN (drift first).** `party_service.gd`
  `share_xp()` hardcodes `1.0 + (member_count - 1) * 0.1` for the party
  bonus. `GameConfig.Party.XP_BONUS_PER_MEMBER` carries the same 0.1 but has
  zero readers, and `XP_LEVEL_DIFF_THRESHOLD` / `XP_PENALTY_MAX` are dead
  too. The level-gap curve actually lives in `kill_rewards._level_scale`
  (`GREY_LEVEL_SPREAD`). Pick one owner for party XP before extracting:
  either the record owns the bonus and level-gap terms, or the service does
  and the dead config goes. Keep the split arithmetic and grant path in the
  service. Receipt: the split matches the record and a missing record
  refuses the bonus rather than inventing a second coefficient.

Checked and not promoted in this pass:

- `horde_event_service.gd` is already data-driven through `HordeData`; the
  remaining `KILL_WEIGHT`, spawn batching and wave grace are algorithm.
- `ride_service.gd` `get_shop_catalog()` builds mount rows from mount records;
  it carries no literal price ladder.
- `container_schema.gd` / `container_config_data.gd` remain the queued
  duplicate-ladder item; this pass did not touch it.
- `GameTier.TIER_STAT_THRESHOLD` is the canonical tier vocabulary/stat gate
  and stays out of scope; `guild_service.gd` rank permissions and
  `matchmaking_qos.gd` latency bands are authorization/protocol.
- `achievement_listeners.gd` is signal wiring, not one catalog: the
  achievement `target_type` vocabulary is handled across several services,
  so there is no single table to move yet. Revisit only if achievement
  triggers become authored rules.

`GameConfig` is intentionally not a single extraction target. It is a broad
runtime configuration surface with protocol, security and gameplay values; a
future audit should split it by owner, not move the file into one `.tres`.

Still explicitly out of scope: cooldowns and rate limits, the status-effect
control maps, `StatId`/`GameTier` vocabulary, schema defaults and the UI island
registry. They are behavior, protocol or routing, not content.

### 2026-11-16 census: third pass (instances, containers, chat)

A third sweep looked at instance contracts, inventory/container capacity and
the remaining presentation tables. It adds one NEXT candidate and strengthens
two queued rows; nothing was extracted.

- **Royale storm ladder - NEXT.** `instance_contract.gd` owns the five-phase
  storm table (hold/shrink/radius ratio/damage) and the 5 m minimum circle,
  while `arena_instance.gd` consumes it through `storm_plan()` and the pure
  radius/damage helpers. `ZoneData` already owns start and scale; the ladder
  itself has no per-zone override, so every royale map shares one code table.
  This is the highest-value new extraction because changing hold times, circle
  sizes or damage changes the bout's primary clock, yet all five rows are
  literals. See queue item 3 for the receipt.

- **Container capacity drift - NEXT (owner first).** The queued container row
  now has a fourth live capacity surface. `InventoryComponent` reads
  `GameConfig.Inventory` for 20 base slots, 12 equipment slots, 5 bags of 20
  and a 98-slot bank with four 98-slot expansions.
  `container_config_data.gd` and the authored `.tres` say 24 inventory,
  16 equipment and 100 bank slots (max 120/16/400). `InventoryComponent`
  hardcodes its bank size and expansion step at 98, so
  `GameConfig.Inventory.BANK_SLOTS` and `BANK_EXPANSION_SIZE` are dead values
  beside a live hardcode. This is not just a UI ladder: the mounted component
  and the authored rows describe the same container family with different
  bases, equipment counts and expansion shapes. Resolve the owner before
  extracting.

- **Chat presentation duplicate - LATER.** `chat_ui.gd`
  `_create_channel_tabs()` carries its own five-row name/colour table for
  Say/Zone/Party/Guild/Whisper. The names and most colours repeat
  `ChatService._channel_info` (Say uses `UIStyles.COLORS.text_primary`
  instead of `#FFFFFF`). This is already a duplicate presentation catalog, so
  a future chat metadata record must replace both. Channel routing and the
  spam gate remain engine-side.

Checked and not promoted in this pass:

- `loot_rules_service.gd` owns policy enums and delegation arithmetic, not a
  catalog; free-for-all/round-robin/leader/master routing stays engine-side.
- `floating_name.gd` `KINDS`, `damage_numbers.gd` `SCHOOL_COLORS` and the
  minimap layer toggles are presentation theme, the same call as the UI
  palette.
- `instance_contract.gd` gravity, kill target, time limit and spawn shield are
  contract/schema defaults already overridable per zone; do not promote them
  just because they are numeric.

### 2026-11-16 follow-up: combat balance

`GameConfig.Combat` and `CombatComponent`'s dormant direct-attack methods and
crit/regen exports are deleted. The live hit table is still `CombatMath`; it
now resolves `data/balance/combat_balance.tres` through `DataService` for hit,
dodge, parry, block and block value. `TickService` reads the record's health and
mana regen rates. `StatId` remains the crit vocabulary/formula owner, and class
and enemy `.tres` records still own per-actor crit values.

The record's schema defaults are the declared fallback when the record is
missing or malformed; the services do not carry a second literal table.
Receipts: `test_combat_balance` (record validity, DataService/TickService
resolution and the tuning seam), `test_hit_table` (record-backed table), plus
`test_crit_system`, `test_combat_loop` and `test_data_naming_lint`.

The follow-up pass closed the last live hit-table literal
(`hit_level_penalty_cap`, 0.30), deleted the unused
`calculate_crit_chance` / `calculate_magic_hit` / `get_rating_per_percent`
helpers and their dead rating fields, and made two authored fields reach
their consumers: `EnemyData.attack_speed` now configures
`EnemyAI.attack_cooldown` through `EnemyAI.configure_from_data`, and
`ComboTracker` reads `Skill.combo_window` instead of a duplicate constant.
Regen ownership and armor mitigation remain decision items, not record
fields yet.

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
