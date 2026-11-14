# PRD - Team Deathmatch (Haven Sandpit)

> **Status:** ACTIVE (2026-11-14). Canonical for the TEAM_DEATHMATCH mode
> and the Haven Sandpit. Shared host, lobby and payout law:
> [prd-bout-host.md](./prd-bout-host.md). Social layer:
> [prd-social-instances.md](./prd-social-instances.md).

Team Deathmatch is the Sandpit's lesson: falling is not the end, but the
shield is a courtesy you lose the moment you swing. Two teams race to twenty
kills inside an eight-minute clock.

## Player promise

You will die and come back. The fight is about pressure and trades, not one
perfect life. The spawn shield gives you a breath; attacking, casting,
drinking or self-buffing gives it up. First team to twenty wins. If the clock
runs out, the marshal pays the lesson and calls it a draw.

## Fiction lock

The Sandpit is "the training pit beside the Coliseum, widened for real
bouts." Its own copy: two parties enter behind rock cover; the first to
twenty kills takes the sand; falls never end a bout; you rise under the
marshals' shield, but swing once and it is gone.

That is the whole fiction. The Sandpit is a working pit, not a sacred ground
and not a blood sport. The marshals are teaching the mode, not consecrating
it. No faith language belongs in the copy.

The zone carries `pvp_mode = FREE_PVP`, but the description promises the
shield and the score, not loot. The loot question is open; see
[Known gaps](#known-gaps).

## As-built contract

| Setting | Value | Source |
|---|---|---|
| Zone | `zone_arena_sandpit` ("Haven Sandpit") | `game/data/zones/zone_arena_sandpit.tres` |
| Mode | `InstanceMode.TEAM_DEATHMATCH` (1) | zone data |
| Capacity | 12 (full 6v6) | zone data |
| Entry deadline | 60 s | zone override |
| Kill target | 20 | zone override |
| Time limit | 480 s (8 min) | zone override |
| Spawn shield | 4 s | zone override |
| Respawn timer | 5 s | zone `respawn_timer` |
| AFK kick | 90 s (contract default) | no zone override |
| Room | 220 m square, planar -Y gravity | room builder |
| Cover | 8 low slabs (6 x 5 x 3) in the midfield/flank layout | `COVER_LAYOUT` |
| Palette | Olive steppe floor, warm sand slabs | `_mode_env` |
| PvP mode | `FREE_PVP` (3) | zone data |

## Bout flow

1. **Assembly.** Two equal-size teams from party blocks and consenting solo
   fill. The mode supports 1v1 through 6v6; there is no separate team-size
   selector. Level bands and capped power normalization apply.
2. **Seat.** BoutHostService links the live player entities into the room
   and carries origin stones. No loaner loadout.
3. **Start.** The room locks after the 60 s entry deadline and starts the
   bout with the resolved rules. Initial fighters receive the 4 s spawn
   shield.
4. **Death.** A shielded victim's death is refused. A self-initiated action
   breaks the shield through `ArenaCombatBridge.notify_action`. Once the
   shield is down, a death books one kill for the killer's team, eliminates
   the victim's body, and schedules a respawn after the zone's 5 s timer.
5. **Respawn.** The victim returns at the team spawn with the 4 s shield
   re-applied. The respawn position scatters so bodies do not stack.
6. **Win.** The first team to 20 kills ends the bout. At 480 s the room ends
   in a draw (`winner_team = -1`). The return map sends every fighter to
   their origin stone.
7. **AFK.** The default 90 s kick window applies. A kicked fighter is booked
   as a departure and returned home.

## Payout

| Result | Reward |
|---|---|
| Winner, per member | 120 XP + 25 gold |
| Loser, per member | 40 XP |
| Draw, per member | 40 XP |

The room's kill book feeds kill-streak achievements. There is no
TDM-specific title, per-kill purse or score achievement.

## Cover and movement

The room is 220 m square, sized from the zone radius. Eight deterministic
low slabs break sightlines without turning the pit into a maze. The layout
keeps the `|z| > 0.6` spawn lanes clear and places two midfield stones on the
`z = 0` lane for flanking. Cover is symmetric and identical for both teams.
Planar gravity is the instance contract; radial globe movement never applies
inside the room.

## Known gaps

1. **No in-bout scoreboard.** The room exposes `score_for(team)` and the
   kill target, but the HUD has no TDM score display. Players track the race
   by kills and the final toast.
2. **The start toast is wrong for TDM.** BoutHostService says "The bout
   begins. Last team standing." for every mode. TDM is first-to-twenty, not
   last-team-standing.
3. **No TDM title or ladder.** Generic bout payout only; kill-streak
   achievements are the only progression hook.
4. **Loot is inherited, not designed.** `pvp_mode = FREE_PVP` means the
   shared death path can resolve a full-loot drop, while the Sandpit copy
   only promises the shield and the score. No TDM receipt covers loot.
5. **No team-size or role preference.** Assembly decides 1v1 through 6v6;
   a solo player cannot ask for a full 6v6 or a specific role.
6. **No per-kill payout or MVP credit.** `kill_counts` exists for the streak
   and royale ledgers, but the generic TDM payout does not use it.
7. **No spectator UI.** The room/ScopeService path exists; the Lobby action
   is greyed.
8. **No explicit spawn-protection UX.** The shield is a rule and a state;
   this document does not promise a dedicated shield VFX.

## Receipts

| Receipt | Covers |
|---|---|
| `game/tests/test_instance_contract.gd` | Sandpit mode, kill target 20, 480 s, 4 s shield. In `DEFAULT_SET`. |
| `game/tests/probe_arena_instance.gd` | TDM room, cover count/size, initial shield, shield break, respawn accounting, exact 20-kill win. In `DEFAULT_SET`. |
| `game/tests/probe_arena_bridge.gd` | Bridged kill, shield refusal, score credit, power normalization. In `DEFAULT_SET`. |
| `game/tests/probe_bout_host.gd` | Hosted assembly, linked seats, payout, return. In `DEFAULT_SET`. |
| `game/tests/probe_bout_flow.gd` | Bout flow and return seam. In `DEFAULT_SET`. |

## Open decisions

1. Does TDM keep full loot, or does every instanced bout suppress player
   loot? The Sandpit's copy does not promise it.
2. Should the mode expose a live scoreboard and shield timer, or is the
   chat/toast surface enough?
3. Is the 20-kill target fixed for the Sandpit, or should a bout length be
   selectable at the queue?
4. Does TDM need per-kill XP/gold or an MVP line, or is the flat winner/loser
   purse the intended economy?
5. Should the Duels tab allow a 1v1 TDM challenge, or should duel challenges
   force elimination?
