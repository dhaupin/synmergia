# Social layer around instances (owner points 4 + 5, 2026-09-28)

> Owner point 6: the S12+ parked items (real glider mechanic, ROYALE
> bounds-shrink, visual scene swap, payout depth) come AFTER this.

## 4. Friends + party + lobby, seamless

The rule: **presence is ambient, action is one click.** The social
surfaces should answer "what are my people doing" without being
asked, and every answer should carry its action.

- **Friend presence**: FriendsService knows the roster; LobbyService
  knows queues; ArenaRoomService knows live rooms; InstanceService
  knows instance membership. Presence = a join of those books. A
  friend line shows: online, queued (zone/mode), in a live bout
  (room id), party id, dungeon/raid zone. Ambiguity ("in an
  instance" without which) is a bug, not a simplification.
- **Join from presence**: a friend queued at a zone shows "Join
  queue" (same zone queue, party-consent rules). A friend in a
  party with open seats shows "Ask to join" (routes through the
  existing LFG petition -> PartyService invite path). A friend in a
  live bout shows "Spectate" (parked until spectating exists --
  show it greyed with a tooltip, never hidden).
- **Invite from the other side**: PartyUI gains "invite from
  friends" (existing) AND "invite from recent players" (new, below).
  Party invites stay rate-limited (QoS party bucket).
- **Recent players** (the heated-rival list): ArenaRoomService
  already knows every fighter that shared a room with you. On
  bout_ended, the host records a RECENT_PLAYERS entry per
  participant: {other_fighter_ids, zone, mode, result, when, your
  result vs them}. Capped ring buffer per player (last ~20),
  persisted through the adapter layer. Surfaced as a LobbyUI tab
  section under Duels: "Recent bouts" -> one-click **Rematch**
  (sends the duel challenge with the same zone/mode) or **Add
  friend**. Rematch is the whole point: the heated unknown rival
  becomes one click.
- **Security note**: recent-player entries are ids + metadata only;
  no chat, no location beyond zone, nothing actionable without an
  existing consent path (duel accept, party invite accept).

## 5. Dungeon / raid / horde cohesion

What arenas need from them, what they need from arenas, and what
must be ALIGNED because both are instances on one lobby:

- **Shared lifecycle**: dungeons/raids/hordes already route through
  ZoneManager instances; InstanceService is the contract front door
  for arenas only. ALIGN: make dungeon/raid joins flow through
  InstanceService too (same capacity checks, same QoS attribution,
  same lobby_state semantics) so "one live instance" rules and
  capacity refusals behave identically everywhere.
- **Shared BoutHost shape**: the host pattern (spawn room, seat,
  start deadline, payout/teardown) generalizes. A future
  DungeonHostService should reuse the book shape, the QoS seams,
  and the teleport service rather than reinventing them. The
  round-trip origin-stone pattern applies to dungeons too (wipe ->
  return to stone, no stranding).
- **What arenas need from horde/raid**: nothing mechanical yet --
  but the horde wave pacing (HordeEventService) is the model for
  ROYALE's bounds-shrink pacing. Steal the phase-timer shape.
- **What dungeons/raids need from arenas**: the AFK kick + time
  limit backstop (a dungeon party squatting in a boss room is the
  same runtime problem), the AFK ledger (notify_action), and the
  scatter-spawn primitive for party teleports into boss rooms.
- **Lobby is canonical for both**: the LFG book already lists
  open-world crews; dungeon-finder-style posts (mode: dungeon,
  role needs) should be the SAME book with a type field, not a
  second system. One panel, one engine, more row types.

## Security review (owner point 3) -- DONE this pass

- Queue churn: rate-limited (QoS party bucket) -- shipped.
- Duel challenge spam: rate-limited (QoS whisper bucket) -- shipped.
- Instance creation churn: owner attribution wired, the previously
  dead 0.05/s limit now binds per requester -- shipped.
- AntiCheat glide limits (owner point for the glider groundwork) --
  shipped earlier this session.
- Coverage already in place: invite timeouts (60 s), one-pending
  duel per player, party invite rate limits, AppFirewall recursion
  guards, BBCode escaping rules.
- Open (recorded, not built): spectate permissions model; recent-
  players privacy option ("hide me from recent lists"); dungeon/
  raid loot-mode griefing rules when they share the lobby.

## Implementation order (when we pick this up)

1. Recent players ring buffer + Rematch button (smallest, highest
   delight).
2. Friend presence join in FriendsService/LobbyUI.
3. InstanceService as the shared front door for dungeon/raid joins.
4. Dungeon-finder post type in the LFG book.
