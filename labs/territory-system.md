# Territory System

> **Status:** ACTIVE (2026-11-14). The schema, service, data, map label,
> guild claim path and faction-war contest path are shipped. Player-facing
> war/claim commands and persistence of runtime claims are not.

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
| Guilds | `GuildService.claim_territory(guild_id, player_id, territory_id)` gates on `MANAGE_GVG` |
| Wars | `FactionManager.declare_war(..., territory_id)` contests; `end_war` resolves by influence |
| Map | `WorldMap._on_zone_loaded` shows `zone_label` in the zone banner |
| Hordes / bosses / events | They keep their `zone_id` anchor; `for_zone` resolves the territory for rewards, defense or notifications. No duplicated ownership field |
| Data gates | `test_territory_service` validates refs and exercises every consumer; `test_data_naming_lint` rejects undeclared `controlled_zones` |

## Current limits

- Runtime claims/wars are in memory, like `FactionManager._active_wars`.
  A reboot returns to the authored controller. Persist through
  `DictStore` before player-run claims become authoritative.
- There is no player-facing `/claim` or `/war` command yet; the service and
  permission path exist, the command surface does not.
- `horde_ids` / `boss_ids` / `event_ids` are validated links, not mechanics.
  Do not invent a capture rule without a content decision.

## Receipts

- `game/tests/test_territory_service.gd` - 24 checks: catalog refs, unique
  zone index, map label, guild permission, war contest/resolution, dead
  faction field.
- `scripts/godot_test_runner.sh` - both tests are in `DEFAULT_SET`.
