# PRD - Elimination (Haven Coliseum)

> **Status:** ACTIVE (2026-11-14). Canonical for the ELIMINATION mode and
> the Haven Coliseum. Shared host, lobby and payout law:
> [prd-bout-host.md](./prd-bout-host.md). Social layer:
> [prd-social-instances.md](./prd-social-instances.md). Duel verb:
> [prd-duel.md](./prd-duel.md).

Elimination is the default bout mode: two teams, one life each, last team
standing. The Coliseum is its authored home. A 1v1 Coliseum bout is the room
the lobby-duel handshake uses when the Coliseum is the chosen zone; it is
**not** the open-world `/duel` path.

## Player promise

One life. No respawn, no kill target, no clock to hide behind. When your team
is gone, the bout is over. The format is legible from the first clash: the
center is clean sand, the colonnade is where a disengage buys line-of-sight.

The clock is a draw backstop, not a second win condition. Squatting pays
nobody.

## Fiction lock

The Coliseum is "the reclaimed arena at Haven's edge. Six species fought
their wars here once; now it hosts duels under one unbroken sky." The zone
data is the copy source; do not replace it with a generic "arena" voice.

The old law is one life. The room's geometry carries the same idea: a
perimeter ring of tall pillars leaves the opening clash a clean center, while
the rim gives a losing team a place to break sight and reset. The Coliseum is
civic, not sacred; no faith language and no Concord blessing belongs in its
copy.

"Full loot on the sand" is in the current zone description. The loot law is
not settled by the mode; see [Known gaps](#known-gaps).

## As-built contract

| Setting | Value | Source |
|---|---|---|
| Zone | `zone_arena_coliseum` ("Haven Coliseum") | `game/data/zones/zone_arena_coliseum.tres` |
| Mode | `InstanceMode.ELIMINATION` (0) | `instance_contract.gd` |
| Capacity | 12 (full 6v6) | zone data |
| Entry deadline | 60 s | zone override |
| Respawn | Not allowed | `bout_rules()` |
| Kill target | None; ignored | `bout_rules()` |
| Spawn shield | None | `bout_rules()` |
| Time limit | 600 s (contract default) | no zone override |
| Room | 120 m square, planar -Y gravity | room builder |
| Cover | 8 tall pillars (3 x 7 x 3) on a perimeter/diagonal ring | `ELIM_COVER_LAYOUT` |
| Palette | Desert sand floor, stone wall, light pillar tint | `_mode_env` |
| PvP mode | `FREE_PVP` (3) | zone data |

The zone data does not write `instance_mode`; ELIMINATION is the schema
default. That works, but an explicit field would make the data easier to
audit.

## Bout flow

1. **Assembly.** LobbyService builds two equal-size teams from party blocks
   and consenting solo fill. A bout can be 1v1 through 6v6; party blocks stay
   atomic. Level bands and capped power normalization apply before the room
   starts.
2. **Seat.** BoutHostService creates the room, seats every participant as a
   linked fighter (player entity id == fighter id), and carries origin
   stones for the return trip. No loaner loadout.
3. **Start.** The room starts after the zone entry deadline (60 s, with the
   probe/tool override). `bout_started` carries the resolved rules; the room
   is LOCKED to new entrants.
4. **Death.** `ArenaCombatBridge` routes `CombatSystem.entity_died` into the
   room. A shielded fighter cannot be eliminated; elimination has no shield.
   The victim is marked dead, `fighter_down` fires, streaks are booked, and
   the room checks whether only one team still has a living fighter.
5. **End.** Last team standing wins. If the 600 s clock expires first, the
   room ends in a draw (`winner_team = -1`). Every fighter receives a return
   map to their origin stone; the host pays out and frees the room.
6. **AFK.** The room uses the contract default 90 s kick window (no zone
   override). A kicked fighter is booked as a departure and sent home.

## Payout

`BoutHostService` owns the generic bout ledger:

| Result | Reward |
|---|---|
| Winner, per member | 120 XP + 25 gold |
| Loser, per member | 40 XP |
| Draw, per member | 40 XP |

Kill-streak achievements are credited from the room's best streak per
fighter. There is no elimination-specific title, ladder or champion
achievement. The trial bout is a separate reduced-payout lesson; see
[prd-bout-host.md](./prd-bout-host.md).

## Trial bout

The marshal's trial uses this same elimination room with two entity-free
dummy fighters, a 4 s fast start, no AFK sweep and a 300 s cap. It pays 40 XP
+ 10 gold on a win and 15 XP on a loss, and credits `quest_arena_trial` plus
`trial_by_fire`. The trial is a retention path, not a bracket.

## Known gaps

1. **No dedicated in-bout scoreboard.** The room exposes team scores and
   alive counts to probes, but the HUD does not render a Coliseum score or
   survivor count. Players infer the state from the fight and the end toast.
2. **No round or ladder format.** The Glad Ring's best-of-five rounds and
   break clock are design only ([prd-monetization.md](./prd-monetization.md)
   sec. 26). A Coliseum bout is a single life.
3. **No champion title or seasonal record.** The only mode-adjacent title is
   `title_last_light` for royale. Elimination wins feed no dedicated title.
4. **Loot is unresolved.** The zone description says "full loot on the sand"
   and `pvp_mode = FREE_PVP`; `DeathFeatures` has a full-loot path, but
   `prd.md` sec. 9.2 still records item-drop mechanics as not done and no
   arena receipt exercises an actual drop. Do not treat the description as a
   verified promise.
5. **No spectator UI.** The room and ScopeService have a spectate path;
   the Lobby action remains greyed.
6. **No explicit mode field.** The zone relies on the schema default. Add
   `instance_mode = 0` when touching the data so a future default change
   cannot silently retune the Coliseum.
7. **Start copy is mode-aware (fixed 2026-11-14).** Elimination keeps "Last
   team standing"; TDM and royale now get their own start lines.
8. **No class, role or team-size preference.** Assembly decides the shape;
   the player chooses a zone, not a bracket.

## Receipts

| Receipt | Covers |
|---|---|
| `game/tests/test_instance_contract.gd` | Zone data, default mode, rules, capacity, entry deadline. In `DEFAULT_SET`. |
| `game/tests/probe_arena_instance.gd` | Room build, planar landing, elimination wipe and winner, cover pattern, center clearance. In `DEFAULT_SET`. |
| `game/tests/probe_arena_bridge.gd` | Bridged death routing, power normalization, shield refusal, elimination winner. In `DEFAULT_SET`. |
| `game/tests/probe_bout_host.gd` | Hosted assembly, linked seats, payout, return. In `DEFAULT_SET`. |
| `game/tests/probe_bout_flow.gd` | Bout flow and return seam. In `DEFAULT_SET`. |
| `game/tests/probe_trial_bout.gd` | Trial room, dummies, reduced payout, quest/achievement credit. In `DEFAULT_SET`. |

## Open decisions

1. Does the Coliseum keep full loot, or does an instanced bout suppress
   player loot the way the honor duel does?
2. Is the 1v1 Coliseum bout officially a "duel", or only a two-seat
   elimination? The lobby-duel handshake currently uses it as the latter.
3. Does elimination need a visible scoreboard and survivor count before it
   can be called a complete mode?
4. Should a draw pay only consolation XP, or should the clock produce a
   different result (sudden death, arena shrink, no draw)?
5. Is there a champion/title/ladder track, or is the mode deliberately
   reward-flat outside the generic bout purse?
