# PRD - Duels

> **Status:** ACTIVE (2026-11-14). Canonical for consensual 1v1 play.
> Shared bout runtime: [prd-bout-host.md](./prd-bout-host.md). Lobby and
> social surfaces: [prd-social-instances.md](./prd-social-instances.md).
> Designed overlays only: [prd-monetization.md](./prd-monetization.md)
> secs. 25-26 (Grudge Book, Glad Ring); none of that is built here.

A duel is a fight two players agree to. It is not a zone, a queue, a loot
rule, or a free-for-all flag. The word currently names **two different
surfaces in the live build**, and they do not share a challenge book:

1. the open-world **honor duel** (`DuelService`, `/duel`), and
2. the instanced **lobby duel** (`LobbyService` handshake, then
   `BoutHostService`).

This document records both. It does not pretend they are one system.

## Player promise

A duel is a consent boundary. Nobody is pulled into one, nobody loses their
gear to one, and the result is a witnessed fact rather than an ambush. The
loser can queue again; the winner gets the name, not the loser's inventory.

The fiction and the current instanced path diverge on the last point. See
[Known gaps](#known-gaps).

## Fiction lock

The duel is Haven's oldest civil form: a challenge spoken in the open, not a
hunt. The loser keeps their gear; no karma changes hands. The Coliseum's own
data calls the place "duels under one unbroken sky"; the open road is the
other witness.

The duel is **civic, not sacred**. No faith language, no Concord rite, no
blessing of the winner. The arena and the road are institutions of the
living, not a religion.

The designed Grudge Book and Glad Ring add spectators, pledges and rounds
around this consent boundary. They do not change the duel itself: same
arena ladder, same consent, base rates. They are design seats, not current
mechanics.

## Surface 1 - the open-world honor duel

`game/core/services/duel_service.gd` is the authority. It has no
`class_name`; the autoload is `DuelService`.

| Step | Live behavior |
|---|---|
| Challenge | `/duel <player>`; the target is resolved by display name. `challenge_duel` stores a pending challenge. |
| Answer | `/accept`, `/decline`; accepting uses the newest pending challenge for the answerer. `/concede` ends a live duel. |
| Timeout | 30 seconds. An expired challenge toasts both players. |
| Range | The duel breaks if the two live players move more than 60 m apart (`out_of_range`). |
| State | One **active** duel per player. Pending challenges are not globally capped; a re-challenge of the same pair replaces the old one. |
| Death | `DuelService` stamps `_duel_death` on both fighters. `DeathFeatures` resolves the duel before it reads the flag, then suppresses loot, karma loss and the griefing record. |
| Reward | None. No XP, gold, title, achievement or recent-players entry. Only `duel_started` / `duel_ended` toasts and signals. |

The open-world duel is **not instanced**. The players stay wherever they
were; the 60 m range check is the only arena boundary. It is also the only
duel path wired to `/duel` in chat.

## Surface 2 - the instanced lobby duel

`LobbyService.challenge_duel(from_id, to_id, zone_id)` is the challenge
book used by `LobbyUI`'s Duels tab and by the Recent Rivals **Rematch**
button. It is a separate book from `DuelService`.

| Step | Live behavior |
|---|---|
| Challenge | Lobby UI sends a player id and a selected bout zone. One pending challenge per player, in either direction. |
| Timeout | 60 seconds. |
| Throttle | The challenge rides the QoS `whisper` bucket. |
| Accept | Both players are appended to the selected zone's queue as two solo blocks with `consent_fill = false`, then `try_assemble(zone_id)` runs immediately. |
| Room | `BoutHostService` hosts the assembled room. Seats bind the live players; no loaner loadout. |
| Mode | There is no `DUEL` mode. The **zone's** `InstanceMode` decides: Coliseum gives 1v1 elimination, Sandpit gives 1v1 team deathmatch (first to 20), and the Sundered Valley gives 1v1 royale. |
| Privacy | Not private. The two blocks enter the public zone queue; `try_assemble` can use other waiting blocks, so the handshake is not a private-instance guarantee. |
| Reward | The generic bout payout, not a duel-specific purse. The bout is recorded in Recent Rivals; Rematch comes back through this same surface. |

The old S9/S11 plan (see [prd-spherical-mvp.md](./prd-spherical-mvp.md))
called for a private instance with both parties and an explicit fill flag.
That private-instance exception is **not implemented** in the live path.

## The two books do not meet

- `DuelService` and `LobbyService` have separate pending challenges, separate
  ids, separate timeouts (30 s vs 60 s) and separate signals.
- A player can have an open-world challenge pending and a lobby challenge
  pending at the same time. Neither service sees the other.
- `/duel` always goes to the open-world honor duel. The Lobby UI never calls
  `DuelService`.
- The Lobby challenge can put a "duel" into any zone in `LobbyUI.BOUT_ZONES`,
  including the Sandpit and the Sundered Valley. The zone's mode wins; the
  result may not be one life.
- Rematch is a lobby-duel action. It does not create an open-world duel.

## Shared consent and combat law

Both surfaces are consensual. Both use the player's real class, gear, build
and stats. Neither creates a loaner form. Bouts use the shared laws in
[prd-bout-host.md](./prd-bout-host.md): live-entity seats, capped power
normalization, origin-stone returns, AFK backstop and the generic payout.

The open-world path has no power normalization, level band, instance clock or
AFK sweep. It is two players and the road.

## Known gaps

1. **Split authority.** There is no single duel record. A future design must
   either unify the books or make the two verbs deliberately different names
   (for example "honor duel" and "arena challenge") in UI and chat.
2. **No private duel instance.** The lobby handshake appends to the public
   queue. The one-live-instance rule is not excepted, and another waiting
   block can join the assembly.
3. **No dedicated duel contract.** A lobby duel's rules are whatever zone the
   challenger picked. Sandpit and Sundered Valley challenges are not
   one-life duels.
4. **Loot contradiction.** The open-world path explicitly drops nothing and
   suppresses karma. The instanced path sets no `_duel_death` flag, so it
   inherits the arena zone's PvP law; the Coliseum description advertises
   full loot. These cannot both be the duel promise.
5. **No open-world result record or reward.** Only toasts. No XP, gold,
   title, recent-rival entry or rematch from the honor-duel path.
6. **No spectator surface for the open-world duel.** Instanced spectate has a
   service-level permission path, but its Lobby UI action is still greyed.
7. **No rounds, wagers, pledges or announcements.** The Grudge Book and Glad
   Ring remain design seats in the monetization PRD.
8. **No dedicated duel HUD.** The Lobby tab shows pending challenges and
   recent rivals; the open-world path is toast-only.

## Receipts

| Receipt | Covers |
|---|---|
| `game/tests/test_duel_service.gd` | Open-world challenge/accept, decline, no-pending, re-challenge, death resolution, concede, range break, helpers. Standalone; not in `DEFAULT_SET`. |
| `game/tests/probe_lobby_service.gd` | Lobby challenge, one-pending rule, expiry, accept -> assembly. In `DEFAULT_SET`. |
| `game/tests/probe_bout_host.gd` | Hosted bout loop, linked fighters, duel QoS, payout and return. In `DEFAULT_SET`. |
| `game/tests/probe_recent_players.gd` | Recent-rival record and Rematch. In `DEFAULT_SET`. |
| `game/tests/probe_arena_instance.gd` | The 1v1 elimination room that the Coliseum duel uses. In `DEFAULT_SET`. |
| `game/tests/probe_arena_bridge.gd` | Death routing and shield conduct through `CombatSystem`. In `DEFAULT_SET`. |

## Open decisions

1. Is the duel one authority or two named verbs? If two, which one owns
   "duel" in player copy?
2. Does an accepted duel get a private room, or is a public assembly with
   possible fill acceptable? The S9/S11 decision said private; the code does
   not.
3. Does an instanced duel inherit the zone's loot law, or does every duel
   set the no-drop/no-karma flag? The Coliseum's "full loot" description
   must be reconciled either way.
4. Are Sandpit TDM and Sundered Valley royale valid duel zones, or should the
   Duels tab force an elimination zone?
5. Does an open-world duel earn anything (XP, a record, a rematch line), or
   is it deliberately rewardless?
6. Which target identity is canonical: display name (`/duel`) or player id
   (Lobby UI)?
7. Do the Grudge Book and Glad Ring build on the lobby duel or on a new
   unified authority? The design assumes consent paths and recent-rival
   records, not the current split.
