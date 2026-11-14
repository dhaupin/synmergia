# PRD - Royale (The Sundered Valley)

> **Status:** ACTIVE (2026-11-14). Canonical for the ROYALE mode and the
> Sundered Valley. The mode is mechanically wired and probed, but the zone
> still presents itself as reserved. Shared host, lobby and payout law:
> [prd-bout-host.md](./prd-bout-host.md). Social layer:
> [prd-social-instances.md](./prd-social-instances.md). Designed spectator
> overlays: [prd-monetization.md](./prd-monetization.md) secs. 25-26.

Royale is the valley bout: a sky drop, a closing fog wall, and one surviving
team. The current runtime assembles **two teams**, not thirty free-for-all
solo players. The "thirty enter and one walks out" copy is the valley's
fiction; the code's winner is a team. That distinction is load-bearing.

## Player promise

You drop from the sky, glide into the valley, and the safe ground gets
smaller until it is gone. The fog is the clock. Loot and fights are the
middle; the Last Light is the end. The 15-minute draw clock is a backstop,
not the intended finish: the final phase closes to a true zero circle.

The drop and storm are real mechanics, not a cinematic. The Last Light is a
title and an achievement; the purse pays placement, survival and kills.

## Fiction lock

The Sundered Valley is "a rift-scarred valley kept sealed since the last
war." The zone copy: the marshals dream of bouts where thirty enter and one
walks out; the bounds themselves will close in; the valley is reserved for a
future season.

The closing wall is **ancient wind made into a rule**, not a cosmetic fog.
The final phase has no quarter: no safe circle, no camper's point. The valley
remembers the first Last Light; later wins empty it again.

The valley is civic and martial, not sacred. No faith language belongs in the
storm, the title or the queue copy. "Last Light" is the bout's name, not a
blessing.

## As-built contract

| Setting | Value | Source |
|---|---|---|
| Zone | `zone_royale_valley` ("The Sundered Valley") | `game/data/zones/zone_royale_valley.tres` |
| Mode | `InstanceMode.ROYALE` (2) | zone data |
| Capacity | 30 | zone data |
| Entry deadline | 90 s | zone override |
| Time limit | 900 s (15 min draw backstop) | zone override |
| Storm start | 45 s after bout start | zone override |
| Storm scale | 1.0 authored | zone data (not yet read by the room; see gaps) |
| Respawn | Not allowed | `bout_rules()` |
| Room | 400 m square, planar -Y gravity | zone radius 400 -> 400 m room |
| Weather | `fog` | zone data |
| PvP mode | `FREE_PVP` (3) | zone data |
| Level gate | 10 | zone data |

## The drop

At `start_bout`, every fighter is thrown into the sky over a wide
golden-angle ring around the room center:

- height = 0.8 x room half; at the valley's 400 m room this is 160 m;
- ring radius = 0.35 x room half (70 m), widened to at least 0.45 m per
  fighter so 30 drops never stack;
- velocity is zeroed; the room arms `movement_glider` on each body;
- the glider machine is the same `GliderState` primitive used on the globe,
  including its 6 m deploy gate and 4.5 m/s sink;
- the room's fighter bodies do **not** carry a horizontal steering input
  today. The drop is auto-winged; steering is a controls seam.

The drop is exempt from the AFK sweep. The valley's own pacing is the
tension, not an idle timer.

## The closing fog

The storm arms 45 s after `start_bout`. It is wall-relative: `STORM_PHASES`
starts at arm time, not at bout start.

| Phase | Hold | Shrink | End radius (x half) | Damage |
|---|---|---|---|---|
| 1 | 60 s | 30 s | 0.65 | 1 dps |
| 2 | 45 s | 30 s | 0.40 | 2 dps |
| 3 | 30 s | 30 s | 0.22 | 4 dps |
| 4 | 30 s | 45 s | 0.10 | 7 dps |
| 5 | 20 s | 30 s | 0.00 (no quarter) | 10 dps |

The total ladder is 350 s; with the 45 s calm, the wall finishes around 395
s. A positive end radius is floored at `MIN_STORM_RADIUS_M` (5 m); the final
zero is a true zero, not the floor.

Outside the safe radius, each living fighter takes the phase's damage on a
1 s cadence. The damage is routed through `ArenaCombatBridge` to the live
entity. A lethal fog hit is credited to the last team still standing, never
to the fog itself; a non-lethal bite is fog-attributed. This is the
anti-fog-squat rule.

The `StormBar` HUD widget receives the phase count, radius, phase advances
and fog bites through `ArenaRoomService`. There is no separate royale
scoreboard, alive counter or placement panel.

## Win, death and return

- No respawn. A dead fighter is out.
- The last team with a living fighter wins. If the 900 s clock runs out
  first, the bout is a draw (`winner_team = -1`).
- Every fighter gets a return map to their origin stone; the room lifts the
  storm and frees itself.
- The AFK sweep is skipped for the whole royale room.

## Payout and markers

`BoutHostService._pay_royale` owns the ledger:

| Result | Reward |
|---|---|
| Last Light, per member | 250 XP + 60 gold + 12 XP per full minute survived + 25 XP per kill + 400 XP if it is the player's first royale win |
| Everyone else | 30 XP + 12 XP per full minute survived + 25 XP per kill |
| Draw | The generic draw path (40 XP per member) |

The first win tracks `royale_win`, unlocks `royale_first_win`, and carries
`title_last_light` ("The Last Light"). `royale_survival` and
`royale_kill` feed the survivor/streak achievements. Kill streaks also feed
the shared `kill_streak` achievements.

## Launch state

The mode is functionally playable: the zone is in `LobbyUI.BOUT_ZONES`, the
royale queue stone exists, `BoutHostService` hosts and pays, and the storm
and drop have receipts. But:

- the zone description still says "Reserved for a future season";
- there is no schedule, season flag or queue gate that enforces "reserved";
- `prd-spherical-mvp.md` still calls ROYALE "reserved".

Treat it as **shipped but not formally launched**. Do not announce a season
until the queue gate and launch copy exist.

## Known gaps

1. **The winner is a team, not a sole survivor.** `try_assemble` builds two
   equal teams (max 15v15 at capacity 30) and `_pay_royale` pays every member
   of `winner_team`. The "thirty enter and one walks out" copy is not the
   current rule. A true 30-player free-for-all would need a different
   assembly and winner model.
2. **No launch gate.** The zone says reserved; the queue accepts entrants.
   A season flag, schedule or closed stone must exist before the copy and the
   behavior agree.
3. **`instance_storm_scale` is authored but unread.** `bout_rules` returns
   the value and `probe_royale_storm` asserts its presence, but
   `arena_instance._arm_storm` always builds the default phase ladder. A
   non-1.0 scale currently does nothing.
4. **No placement or alive-count HUD.** `StormBar` shows the wall; there is
   no "X remain", placement line or end-of-bout ladder.
5. **No glider steering in the room.** The drop arms the wing and sinks
   correctly; the fighter body has no horizontal input seam, so the player
   cannot choose a landing spot beyond the scatter.
6. **No spectator UI.** The scope/permission path exists; the Lobby action
   is greyed.
7. **No loot design.** The zone is `FREE_PVP`; the shared death path can
   produce a full-loot drop, but no royale receipt or copy settles whether
   the valley is a looting mode.
8. **No season, map or schedule.** The valley is one room and one storm
   ladder. The designed Glad Ring/Made Bout overlays are not connected to
   royale.

## Receipts

| Receipt | Covers |
|---|---|
| `game/tests/probe_royale_storm.gd` | Storm math, zone rules, arming, phase damage, true-zero final circle, fog kill credit, glider drop, anticheat launch tickets, StormBar relay. In `DEFAULT_SET`. |
| `game/tests/probe_bout_flow.gd` | ROYALE drop scatter and bout flow. In `DEFAULT_SET`. |
| `game/tests/probe_arena_instance.gd` | Royale room stays bare/rust palette; mode rules load. In `DEFAULT_SET`. |
| `game/tests/probe_glider.gd` | The planar room drop uses the same glider machine as the globe. In `DEFAULT_SET`. |
| `game/tests/probe_bout_host.gd` | Hosted bout loop and generic payout/return; royale ledger is not separately exercised there. In `DEFAULT_SET`. |

## Open decisions

1. Is royale a team bout (current code) or a solo free-for-all (current
   fiction)? If solo, how do parties enter and how is the winner modeled?
2. Is the valley launched by a season gate, a schedule, or simply by changing
   the "reserved" copy?
3. Does a non-1.0 `instance_storm_scale` need to work, or should the field be
   removed until a caller exists?
4. Does royale inherit the zone's full-loot law, or suppress player loot like
   the honor duel?
5. Does the drop need horizontal glider steering before launch, or is the
   scatter landing the intended v1?
6. Does the mode need a placement/alive HUD and a post-bout ladder before it
   can carry a season?
