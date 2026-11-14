# PRD - Factions and War

> **Status:** ACTIVE (2026-11-14). Canonical for authored factions, faction
> relations, reputation and the war lifecycle. Territory ownership and its
> guild claim path are specified in
> [`territory-system.md`](./territory-system.md); guild organization in
> [`prd-guild.md`](./prd-guild.md).

A faction is an authored world power with a species tie, PvP rule, fixed
relations and a reputation track. A guild is a player organization. The two
meet at territory stakes and optional guild-faction alliances, but they are
not the same record and must not be merged into one `controlled_zones` list.

## Authored factions

Data lives in `game/data/factions/*.tres` and is loaded by
`DataService.load_factions()` into `Faction` resources
(`game/core/schemas/faction.gd`). `WorldService.initialize_world()` calls
`FactionManager.load_factions()` after zone loading.

| Id | Display | Species | Type | PvP rule | Authored relations |
|---|---|---|---|---|---|
| `faction_human` | Human Alliance | `human` | `SPECIES` (0) | `DEFAULT` | Akkan hostile (2), Synthetic allied (0), Neutral neutral (1) |
| `faction_akkan` | Akkan Horde | `akkan` | `SPECIES` (0) | `DEFAULT` | Human hostile (2), Synthetic allied (0), Neutral neutral (1) |
| `faction_synthetic` | Synthetic Collective | `synthetic` | `POLITICAL` (1) | `PEACEFUL` (1) | Human allied (0), Akkan allied (0), Neutral neutral (1) |
| `faction_neutral` | Neutral | none | `PVP_RULE` (2) | `PEACEFUL` (1), until level 20 | none |

Relations use `Faction.Relation`: `ALLIED` 0, `NEUTRAL` 1, `HOSTILE` 2.
`Faction.get_relation` checks explicit relations, then returns `NEUTRAL`.
`FactionManager.get_relation` checks a live war first, then the authored
relation. `test_data_naming_lint` enforces that faction relations resolve
and are symmetric, and that species home zones and stat modifiers are real.

## Runtime model

`game/core/services/faction_manager.gd` is the authority. It has no
`class_name`; autoload name is `FactionManager`.

| State | Shape | Authority |
|---|---|---|
| Factions | `_factions: {faction_id: Faction}` | Authored `.tres`; runtime relation edits are in memory |
| Reputation | `_player_reputations: {player_id: {faction_id: int}}` | Runtime, clamped -10000..10000 |
| Wars | `_active_wars: {faction_a: {faction_b: war_data}}` | Runtime, bidirectional pair |
| War cooldowns | `_war_cooldowns: {faction_id: ticks_msec}` | Runtime |
| Guild-faction alliances | `_guild_alliances: {guild_id: [faction_id]}` | Runtime plus `faction:alliance:<guild_id>` writes |

War data carries `started_at`, `started_by` and `declarations`. The pair is
written both directions so lookup does not depend on argument order.

## Reputation

`modify_reputation(player_id, faction_id, delta)` clamps to
-10000..10000 and emits `reputation_changed`. Rank names are thresholds:

| Minimum | Rank |
|---|---|
| 9000 | Exalted |
| 6000 | Revered |
| 3000 | Honored |
| 1000 | Friendly |
| 0 | Neutral |
| -999 | Unfriendly |
| -3000 | Hostile |
| below -3000 | Hated |

A rank transition emits `FACTION_REP_CHANGED`; ordinary point changes do not
toast. `QuestService` is a current caller of `modify_reputation`.

## War lifecycle

1. A caller invokes `FactionManager.declare_war(a, b, attacker_id,
   territory_id)`. Both factions must exist, neither may be on the 24-hour
   cooldown, and the pair must not already be at war.
2. The manager writes both directions of `_active_wars`, sets the
   attacker's cooldown, writes `HOSTILE` on both resources, emits
   `war_declared` and sends a `FACTION_CHANGED` notification.
3. If `territory_id` is non-empty, `TerritoryService.contest` records
   `war:<a>:<b>` as the territory's `active_war_id` and adds both factions
   as claimants.
4. `end_war(a, b)` removes both war rows, resets both relations to
   `NEUTRAL`, emits `war_ended` / peace notification, and calls
   `TerritoryService.resolve_war_between(a, b)`. The strongest claimant
   keeps the controller seat; the loser's claim is released.

The player command surface is:

| Command | Who | Effect |
|---|---|---|
| `/war` / `/war status` | everyone | lists territories with a live `active_war_id` |
| `/war declare <a> <b> [territory_id]` | admin only | `declare_war` with an optional stake |
| `/war end <a> <b>` | admin only | `end_war` and territory resolution |

The admin gate is `PermissionManager.is_admin`. There is no faction
leader/election model, so player-declared faction wars are intentionally
closed. Guild `/claim` is the player-facing control verb today.

## Known gaps

These are implementation facts, recorded so a future PRD round does not
mistake declared constants for shipped mechanics:

- **Wars are not durable.** `_active_wars` and `_war_cooldowns` are memory
  only. `_persist_faction` is defined but never called. A restart loses
  active wars and cooldowns while `territory:state:<id>` may still carry an
  `active_war_id`; that is an orphan state that needs a reconciliation pass.
- **The 10,000 gold war cost is not enforced.** `WAR_DECLARATION_COST` is
  defined but has no reader, and `declare_war` / `/war declare` take no
  purse argument. `prd.md` previously marked the cost as implemented.
- **Reputation writes are not persisted.** `_load_factions` knows how to
  read `faction:rep:<player_id>`, but `modify_reputation` and
  `set_reputation` never call `_persist_reputation`. Reputation resets on
  restart.
- **Guild-faction alliance breaks are not persisted.** `form_alliance`
  writes `faction:alliance:<guild_id>`; `break_alliance` erases the live
  list but does not call `_persist_alliances`, so a broken alliance can
  return after reload.
- **War end does not restore the authored relation.** `end_war` sets both
  sides to `NEUTRAL`. Human and Akkan are authored `HOSTILE`; after one war
  ends, that baseline is gone for the process lifetime unless something
  re-applies authored data. Decide whether peace means neutral or
  "return to baseline" before opening player-declared wars.
- **`Faction._war_timers` is unused.** The manager owns cooldowns; do not
  add a second timer path.
- **Guild and faction alliances are separate.** `GuildService._alliances`
  is a multi-guild alliance; `FactionManager._guild_alliances` is a
  guild-to-faction relationship. They share the word "alliance", not a
  record.

## Receipts

- `game/tests/test_territory_service.gd`: 31 checks, including `/war`
  status readability, non-admin refusal, admin declare, territory contest,
  recorded war id, survival across a `TerritoryService` reload, `/war end`,
  and peace keeping the strongest claim.
- `game/tests/test_data_naming_lint.gd`: faction relation symmetry, species
  and zone references, retired `controlled_zones` absence.
- `game/tests/test_presolve_props.gd` and `test_map_landmark_wiring.gd`
  cover adjacent world/data paths, not faction runtime.

## Open decisions

1. Add faction leadership before opening `/war declare` to players. A
   permission bit is not a mandate.
2. Persist wars and cooldowns, or explicitly make them session-scoped and
   reconcile territory `active_war_id` on boot.
3. Charge `WAR_DECLARATION_COST` from a defined purse, or delete the
   constant. Do not leave a price in the PRD that no code collects.
4. Restore authored relations on peace, or change the authored baseline so
   `NEUTRAL` is truthful.
5. Persist reputation mutations and faction-guild alliance breaks.
