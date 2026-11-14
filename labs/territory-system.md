# Territory System

> **Status:** ACTIVE (2026-11-14). The schema, service, data, map label,
> `/claim` guild command, `/war` status + admin declare/end, and the
> DictStore runtime overlay are shipped. Player-declared faction wars are
> still gated: factions have no leader model yet. Guild organization is
> specified in [`prd-guild.md`](./prd-guild.md); faction politics in
> [`prd-factions.md`](./prd-factions.md). Player housing plots are a
> separate ownership layer ([`prd-housing.md`](./prd-housing.md)); a plot
> is not a `TerritoryData` and `/claim` must not touch one.

## Why an overlay

`ZoneData` is geography: bounds, entry gates, respawn, PvP mode. A territory
is the thing factions and guilds actually hold, and it may group several
zones. Putting `controller_id` on `ZoneData` would make ownership static and
duplicate it per zone; putting `controlled_zones` on a faction made it a
dead array (its only reader was a naming lint).

So ownership has one home: `TerritoryData` + `TerritoryService`. A zone
belongs to at most one territory; overlapping *claims* live in
`claimants`, not in overlapping zone lists.

## Data contract

`game/core/schemas/territory_data.gd`, files in
`game/data/territories/terr_<name>.tres`:

| Field | Meaning |
|---|---|
| `id` | `terr_` id; filename == id |
| `zone_ids` | ZoneData ids grouped here; every ref must resolve |
| `controller` / `controller_id` | Resolved holder (`NONE`, `FACTION`, `GUILD`) |
| `claimants` | `{kind, id, influence, since}` records; contest history |
| `active_war_id` | Set while a faction war is fought over it |
| `capture_rule` | `SIEGE`, `PVP_KILL`, `BOSS`, `EVENT`; content chooses the verb |
| `horde_ids`, `boss_ids`, `event_ids` | Optional catalog links; never zone ownership |
| `pvp_mode_override` | `-1` inherits the zone mode |

`is_contested()` is derived: a live war or more than one claimant. It is not
stored, so it cannot drift from the claim records.

## Runtime

`TerritoryService` (autoload, no `class_name`) owns the registry:

- `for_zone(zone_id)` / `zone_label(zone_id, fallback)` for the map.
- `territories_for_faction(id)` / `territories_for_guild(id)`.
- `claim(territory_id, kind, owner_id, influence)`; a stronger claim takes
  the controller seat.
- `contest(territory_id, war_id, faction_a, faction_b)` from
  `FactionManager.declare_war(..., territory_id)`.
- `resolve_war` / `resolve_war_between`; peace keeps only the winner's claim.
- `release(territory_id)` for an unclaim.

`reload()` rebuilds from `DataService.load_territories()`. Duplicate
territory ids and zones claimed by two territories are refused, not
silently shadowed.

## Wiring

| System | Path |
|---|---|
| Factions | `FactionData.controlled_zones` is gone; the three authored claims moved to `terr_starter_plains`, `terr_dark_highlands`, `terr_nexus_central` |
| Guilds | `GuildService.claim_territory(guild_id, player_id, territory_id)` gates on `MANAGE_GVG`; `/claim [territory_id]` is the player surface (bare uses the current zone) |
| Wars | `FactionManager.declare_war(..., territory_id)` contests; `end_war` resolves by influence. `/war` lists status for everyone; `/war declare|end` is admin-only |
| Map | `WorldMap._on_zone_loaded` shows `zone_label` in the zone banner |
| Hordes / bosses / events | They keep their `zone_id` anchor; `for_zone` resolves the territory for rewards, defense or notifications. No duplicated ownership field |
| Persistence | `TerritoryService` saves controller, claimants and `active_war_id` under `territory:state:<id>`; `reload()` re-applies the overlay over the immutable authored copy |
| Data gates | `test_territory_service` validates refs and exercises every consumer; `test_data_naming_lint` rejects undeclared `controlled_zones` |

## Commands

| Command | Who | Result |
|---|---|---|
| `/claim [territory_id]` | guild member with `MANAGE_GVG` | stakes a claim; a 50-influence claim marks a 100-influence holder contested but does not unseat it |
| `/war` / `/war status` | everyone | lists territories with a live `active_war_id` |
| `/war declare <a> <b> [territory_id]` | admin | `FactionManager.declare_war`; the territory becomes the stake |
| `/war end <a> <b>` | admin | ends the war and resolves every contested territory by influence |

`TerritoryService.clear_persisted(id)` resets one territory's runtime
overlay; `clear_persisted()` resets all of them. Authored data is never
mutated: registration deep-copies the `DataService` resource.

## Current limits

- Player-declared **faction** wars are not open yet: factions have no
  leader/election model, so `/war declare` is admin-only. Guild `/claim` is
  the player-facing control verb.
- A guild claim sets influence 50 against a typical authored holder's 100;
  it contests the territory but cannot flip the controller until a capture
  rule raises influence. That is deliberate, not a missing check.
- `horde_ids` / `boss_ids` / `event_ids` are validated links, not mechanics.
  Do not invent a capture rule without a content decision.

## Receipts

- `game/tests/test_territory_service.gd` - 31 checks: catalog refs, unique
  zone index, map label, guild permission, `/claim`, DictStore reload,
  `/war` status/deny/declare/end, dead faction field.
- `scripts/godot_test_runner.sh` - both tests are in `DEFAULT_SET`.
