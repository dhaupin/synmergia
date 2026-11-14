# PRD - Guilds

> **Status:** ACTIVE (2026-11-14). Canonical for the guild runtime.
> Territory ownership itself is specified in
> [`territory-system.md`](./territory-system.md); faction politics in
> [`prd-factions.md`](./prd-factions.md).

A guild is a player-run organization: a named roster with ranks and
permissions, a shared bank, optional multi-guild alliances, and the only
player-facing path to territory control. A guild is **not** a faction.
Factions are authored world powers (`faction_human`, `faction_akkan`,
`faction_synthetic`, `faction_neutral`); guilds are created at runtime and
persist under their own keys.

## As-built surface

`game/core/services/guild_service.gd` is the authority. It has no
`class_name`; autoload name is `GuildService`.

| Capability | Entry point | Notes |
|---|---|---|
| Create | `create_guild(name, tag, leader_id)` | Qos rate limit, name/tag validation, generated `guild_<tag>_<ticks>` id |
| Disband | `disband_guild(leader_id)` | Guildmaster only; leaves alliance first |
| Invite | `invite_player(inviter_id, target_id)` | 5-minute invite, `INVITE` permission |
| Apply / accept | `apply_to_guild`, `accept_application` | `INVITE` permission to accept |
| Invite response | `accept_guild_invite`, `decline_guild_invite` | invite id plus recipient check |
| Roster | `get_guild_roster`, `remove_member`, `leave_guild` | leader cannot be kicked |
| Rank | `change_rank`, `transfer_leadership` | promote/demote permission split |
| Bank | `deposit_gold`, `withdraw_gold`, `deposit_item`, `withdraw_item` | 98-slot Main tab, 100-row log cap |
| Notice / MOTD | `set_guild_notice`, `set_guild_motd` | `MANAGE_NOTICES` |
| Guild alliance | `create_alliance`, `invite_to_alliance`, `join_alliance`, `leave_alliance` | service-level multi-guild alliance |
| Territory | `claim_territory`, `get_guild_territories` | `MANAGE_GVG`; delegates state to `TerritoryService` |

The UI is `game/ui/social/guild_ui.gd`; guild chat is a `ChatService`
channel. There is no separate guild-management HTTP surface in the game
service.

## Ranks and permissions

`GuildRank`: `GUILDMASTER` (0), `OFFICER` (1), `MEMBER` (2), `RECRUIT` (3).

`Permission` is a bitmask: `INVITE` 1, `KICK` 2, `PROMOTE` 4, `DEMOTE` 8,
`EDIT_INFO` 16, `SET_RANK_PERMISSIONS` 32, `CREATE_ALLIANCE` 64,
`DISBAND_ALLIANCE` 128, `MANAGE_GVG` 256, `WITHDRAW_GOLD` 512,
`MANAGE_NOTICES` 1024.

Defaults: Guildmaster has every bit; Officer has invite, kick, promote,
demote and notices; Member can invite; Recruit has none. The permission map
is stored per guild in `rank_permissions`, so a guild can diverge from the
defaults without changing the enum.

`MANAGE_GVG` is the territory gate. It is also the only permission checked
by `/claim`; guild rank alone is not enough.

## Territory and GvG

The guild is the player-facing owner; the territory is the unit of control.

- `/claim [territory_id]` calls `GuildService.claim_territory`. With no
  argument, `ChatService` resolves the sender's current zone through
  `TerritoryService.for_zone`.
- A guild claim is written as influence **50** against the authored holder's
  usual **100**. It becomes a second claimant and marks the territory
  contested, but does not take the controller seat. Raising influence is a
  capture-rule decision, not a permission decision.
- `get_guild_territories(guild_id)` reads back the territories whose
  `controller.kind == GUILD` and `controller.id == guild_id`.
- Territory runtime state is durable under `territory:state:<id>`; see
  [`territory-system.md`](./territory-system.md).

**GvG war declarations do not exist.** The service and command surface
support a guild *claim* and a faction *war*, not a guild-vs-guild war
declaration. `prd.md` previously marked "Guild Wars" as implemented; that
was aspirational. A real GvG layer needs a guild war record, a stake, a
resolution rule, and a receipt before it can be called shipped.

## Persistence

The intended layout is:

| Key | Value |
|---|---|
| `guild:<guild_id>` | full guild dictionary (roster, ranks, bank, settings, notice, MOTD) |
| `guild:invite:<invite_id>` | pending invite row |

`GuildService.create_guild` writes `guild:<guild_id>` through `DictStore`.
`persist_all` exists for a bulk write. The live dictionaries remain the
source of truth while the process runs.

This area has **verified gaps**. They are recorded here so a future round
does not mistake the presence of a method for durable behavior:

- `_load_guilds` accepts only keys with at least three colon-separated
  parts (`parts.size() >= 3`) and reconstructs an id from parts 1 and 2.
  `create_guild` writes a two-part key (`guild:guild_...`), so that write is
  not read back by the current loader. Treat guild durability as open until
  a receipt covers create -> restart -> roster.
- Roster, rank, bank, notice and MOTD mutations do not call `_persist_guild`
  after creation. `persist_all` has no caller in the service tree.
- `_persist_invite` is defined but never called. Accept/decline/expire erase
  `guild:invite:<id>` rows that were never written. `persist_all` also keys
  pending invites by player id while the live dictionary is keyed by invite
  id.
- `remove_member` erases `{"id": target_id}` from `members`. That partial
  dictionary is not the stored member row (which also carries `rank` and
  `joined_at`), so the player->guild mapping is removed but the roster row
  may remain. This needs a focused receipt before roster management is
  described as durable.
- `_alliances` is in memory only. Faction-guild alliances live in
  `FactionManager` under `faction:alliance:<guild_id>`; these are two
  different alliance concepts and must not be conflated.

None of these gaps affect the territory overlay, which has its own
`DictStore` round-trip receipt and does not depend on guild persistence.

## Receipts

- `game/tests/test_territory_service.gd` covers the guild path end to end:
  a recruit without `MANAGE_GVG` is refused, a guild master's `/claim`
  succeeds, the 50-vs-100 contest behaves, and the claim survives a
  `TerritoryService` reload. It also covers the command surface.
- `game/tests/test_data_naming_lint.gd` validates faction and species
  references, including the absence of the retired `controlled_zones` field.
- There is no standalone `test_guild_service.gd`. The persistence and roster
  gaps above are read from the implementation, not certified by a test.

## Open decisions

1. Make guild state durable: define one key layout, persist every mutation,
   and add a create -> mutate -> reload receipt.
2. Decide whether `remove_member` should repair the roster or whether the
   roster is rebuilt from the player mapping. Do not leave both shapes.
3. Add a guild war record only when there is a stake, a resolution rule and
   a way to read the result. A `/gwar` command without those is a label.
4. Unify or explicitly separate guild alliances (`GuildService._alliances`)
   and faction-guild alliances (`FactionManager._guild_alliances`).
5. Decide who may spend guild gold: `WITHDRAW_GOLD` is defined but the
   current `withdraw_gold` path does not check it.
