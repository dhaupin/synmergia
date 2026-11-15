# Data / Engine Separation

> **Status:** ACTIVE 2026-11-15. The Fixer board, starter kits, Academy
> prices, housing economy, bout rewards and agent slots are extracted; the
> remaining ledger is a deliberate queue, not a rewrite mandate.
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

## 10. Next-pass rule

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
