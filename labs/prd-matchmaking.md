# PRD - Matchmaking (the fifth service)

> **Status:** ACTIVE (2026-11-14). Canonical for bout queues, assembly,
> gate entry and the QoS seam. Shared host, payout and teardown:
> [prd-bout-host.md](./prd-bout-host.md). Mode contracts:
> [duel](./prd-duel.md), [elimination](./prd-elimination.md),
> [team deathmatch](./prd-tdm.md), [royale](./prd-royale.md).

The fifth instance is not another arena. It is the matchmaker that feeds
the four modes. The build currently carries the word in two different
services, and only one of them is live:

1. **`LobbyService` is the matchmaker.** It owns the per-zone queues,
   party blocks, level-band widening, fill-to-parity, trial fallback,
   origin stones, the duel handshake and LFG. Every gate stone and the
   Bouts tab go through it.
2. **`MatchmakingQoS` is a dormant QoS prototype.** It classifies
   connection quality, stores latency/jitter/packet-loss samples and has
   a `get_matchmaking_group` latency bucket. It is **not** an autoload,
   has no caller in the live assembly path, and duplicates the rate-limit
   role already owned by the `QoSService` autoload.

There is no third queue assembler hidden in the tree, and this PRD does
not create one. A second queue would be a second truth about who is
waiting. The live authority stays `LobbyService`; `MatchmakingQoS` is a
candidate latency-policy seam, not a second matchmaker.

## Player promise

A stone is a door, not a loading screen. Walk up, see the mode and the
living queue, choose to wait or leave, and get carried in when the room
is ready. A party enters together or not at all. A solo player is never
silently fed to a premade without consenting to fill. If nobody comes,
the marshal's trial still gives the player a fight.

## The two books

| Book | Authority | State | Live callers |
|---|---|---|---|
| Bout queue and assembly | `game/core/services/lobby_service.gd` | Session-only | Gate stones, `LobbyUI` Bouts tab, duel accept, `BoutHostService` trial |
| Latency / connection policy | `game/core/services/matchmaking_qos.gd` (`class_name MatchmakingQoS`) | Dormant; not autoloaded | None in the live path; `backend_factory.gd` only labels the `"matchmaking_queue"` store |
| Rate limits | `game/core/autoload/qos_service.gd` (`QoSService`) | Live autoload | Queue joins, duel challenges, party and social actions |

`backend_factory.gd` mapping `"matchmaking_queue"` to `"MatchmakingQoS"` is
a storage-label map, not proof that the service is instantiated. A reader
must not treat that row as wiring.

## Mode matrix

| Player surface | Zone | Contract mode | Capacity | Gate | Queueable today |
|---|---|---|---|---|---|
| Duel (open world) | none | none | 2 | `/duel`, not a stone | No queue; consent handshake |
| Duel (lobby challenge) | chosen from `BOUT_ZONES` | zone's mode | zone | Lobby Duels tab | Yes, through the challenge book |
| Elimination | `zone_arena_coliseum` | `ELIMINATION` | 12 (1v1 to 6v6) | Coliseum stone | Yes |
| Team Deathmatch | `zone_arena_sandpit` | `TEAM_DEATHMATCH` | 12 (1v1 to 6v6) | Sandpit stone | Yes |
| Royale | `zone_royale_valley` | `ROYALE` | 30 (1v1 to 15v15 teams) | Valley stone | Yes; no launch gate |

The arena stones are authored in `game/entities/village_props.gd`
(`BOUT_STONES`) and built through `game/scenes/worlds/arena_gateway.gd`
with `queue_mode = true`. The Coliseum stone fronts duel and elimination
bouts; the Sandpit fronts TDM; the Valley fronts royale.

## Queue contract

One player is in at most one queue. A queue is a FIFO of **blocks**, not
individual players:

```
{
  player_ids: Array[String],
  party_id: String,
  level: int,
  joined_at: float,
  consent_fill: bool,
  origin_stone: Vector3
}
```

- `join_queue(player_id, level, zone_id, consent_fill, origin_stone, party_id)`
  is the only entry point. When `party_id` is omitted, the service resolves
  it from `PartyService`; a party member's queue call carries the whole
  roster as one atomic block.
- `leave_queue(player_id)` removes the containing block. A party member's
  leave removes the party's block, because the block is the unit.
- `queue_for(player_id)` is the reverse index used by presence, the gate
  and the UI.
- `queue_snapshot(zone_id)` exposes display-safe rows: leader, size, level,
  wait, fill consent and party id.
- Queue churn is rate-limited through `QoSService`'s `party` bucket.
- Party disband removes that party's queue block and LFG post.

## Assembly contract

`try_assemble(zone_id)` is a pure engine step with all-or-nothing booking:

1. The oldest block seeds team A.
2. The first band-compatible block seeds team B. Bands widen with the
   longer wait; a gulf pair never passes.
3. Consenting solo blocks top up the smaller team to parity.
4. Team size is capped by `zone.instance_capacity / 2`; party blocks stay
   atomic and skipped blocks keep their place.
5. `InstanceService` books every live entity. A capacity refusal leaves the
   queue untouched. Headless/probe assembly degrades to a bookkeeping id.
6. Per-player origin stones ride `bout_assembled` as the fifth argument and
   are stamped into the instance's `origin_stones`.
7. The queue consumes the assembled blocks and emits `bout_assembled`.
   `BoutHostService` creates the room, seats linked fighters, starts after
   the entry deadline, pays out and returns everyone.

Queue of one: after `TRIAL_PATIENCE_SECONDS` (45 s), the block is popped
and `trial_fallback_due` lets `BoutHostService` fabricate the marshal's
trial room. Nobody waits forever in an empty hour.

## Gate and UI surface

- Walk-in on a queue stone calls `ArenaGateway._enqueue_at_stone`, passing
  the stone position as the origin. The body trigger is deduped separately
  from the queue, so leaving the queue while still standing in the stone
  does not strand the player.
- The stone's action menu is `View Gate`, `Queue for Bout`, `Leave Queue`,
  `Check Lobby`. `View Gate` opens the Lobby on the Bouts tab with that
  stone's zone selected and its mode blurb visible.
- The Lobby panel is the canonical surface: `L` opens Bouts / Duels / LFG /
  People. Bouts shows the mode selector, fill consent, queue status and the
  live queue feed.
- `Check Lobby` remains the generic panel entry; `View Gate` is the
  zone-focused entry.
- There is no separate stone panel. The focused Bouts tab is the gate UI
  until a panel proves it needs its own scene.

## QoS seam

Today only rate limiting touches matchmaking. Latency is not an input to
assembly: the assembler never reads RTT, jitter or packet loss, and
`MatchmakingQoS.get_matchmaking_group` has no caller.

The refresh law is:

- `QoSService` stays the only rate-limit and connection-quality autoload.
- `MatchmakingQoS` must not become a second queue. It may only become a
  latency advisor after a server-fed RTT source exists and its lifecycle is
  explicit.
- If no such source lands, retire `MatchmakingQoS` and keep the latency
  bucket idea in this PRD as a future seam. Do not instantiate it just to
  make the backend map look wired.

## Known gaps

1. **No latency input.** Assembly is level-band and consent only. A player
   on a 400 ms link can be paired with a 40 ms premade.
2. **Dormant QoS prototype.** `MatchmakingQoS` is not autoloaded and has no
   caller. Its scope-stack test keeps it compiling, not alive.
3. **Duel authority is split.** `DuelService` (open-world `/duel`) and
   `LobbyService` (instanced challenge) have separate books and timeouts.
   The lobby handshake also uses the chosen zone's mode, which may be TDM or
   royale rather than one-life elimination.
4. **No ready check.** Assembly starts after the zone deadline; there is no
   "accept" moment for a player who walked away from the keyboard.
5. **No queue cap or backpressure.** A large party can seed a block larger
   than a small zone's team cap; the assembler then waits rather than
   refusing the entry at queue time.
6. **Royale has no launch gate.** The zone copy says reserved, but the
   stone and Bouts tab accept entrants. The mode is shipped but not formally
   launched.
7. **No role, class or team-size preference.** The queue chooses a zone,
   not a bracket or a role.
8. **The gate UI is the lobby, not a local stone panel.** That is a
   deliberate first pass; a dedicated panel remains an open UX decision.
9. **The TDM start toast is generic.** `BoutHostService` announces "Last
   team standing" for every mode, which is wrong for first-to-twenty.
10. **No in-bout scoreboard.** Elimination and TDM expose scores to probes,
    but the HUD does not render them.

## Refresh plan

| Phase | Work | State |
|---|---|---|
| 1 | Make the signal carry origin stones, resolve party blocks at the service boundary, focus the lobby from a gate, surface the mode blurb | Landed with this PRD |
| 2 | Decide `MatchmakingQoS`: retire it into `QoSService` or feed it real RTT and use it as an advisory only | Open |
| 3 | Add queue-time validation: zone level gate, party-vs-team-cap check, optional ready check | Open |
| 4 | Close mode readiness: TDM start copy, scoreboards, royale launch gate, duel private-room decision | Open |
| 5 | Add a dedicated stone panel only if the focused Bouts tab is insufficient in play | Open |

## Receipts

| Receipt | Covers |
|---|---|
| `game/tests/probe_lobby_service.gd` | Bands, fill, party blocks, snapshots, duels, LFG, disband |
| `game/tests/probe_bout_host.gd` | Assembly to hosted room, linked seats, payout, return |
| `game/tests/probe_trial_bout.gd` | Aging queue to marshal's trial |
| `game/tests/probe_social_presence.gd` | Presence's queued state |
| `game/tests/test_interaction_pipeline.gd` | Gate targetable and action-menu reachability |
| `game/tests/test_instance_contract.gd` | Mode, capacity, entry deadline and bout rules |

## Open decisions

1. Is `MatchmakingQoS` retired, or promoted to a latency advisor once a
   server-fed RTT source exists?
2. Does the queue need an explicit ready check before the room seats
   fighters, or is the entry deadline enough?
3. Does a party block use the leader's level, the highest member's level, or
   an average for band matching? The current block stores one level.
4. Should the lobby duel force an elimination zone and a private room, or
   keep using the public zone queue?
5. Is the focused Bouts tab an acceptable gate UI, or does each stone need
   its own local panel?
6. Should the royale stone stay open while the zone copy says reserved, or
   gain a season/queue gate first?
7. Is royale a two-team mode by design, or a true 30-player free-for-all?
   The current winner and payout are team-based.
