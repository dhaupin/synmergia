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

## Scene swap + spectate (SHIPPED 2026-09-28)

The swap is a SCOPE SWAP, not a scene reload: the player node
reparents between scopes and one flag flips. Both gravity truths
stay load-bearing.

- **ScopeService** (autoload): enter_room_scope (reparent under the
  room root + planar_mode on), exit_to_globe (back + planar_mode
  off, radial math resumes verbatim), enter_spectate_scope (same
  room, spectate scope string). The pre-swap parent is remembered
  as an ESCAPE hatch: the room-closed safety net physically
  rescues players from a queue_free'd room (a freed room must
  never take the player with it -- this was the crash the
  regression caught). Registry: "globe" | "bout:<id>" |
  "spectate:<id>".
- **globe_player.planar_mode**: inside a room, radial math yields
  to the planar contract (world-up, -Y at GRAVITY_FORCE, camera-
  relative move intent). Locked decision 3 still holds: the globe
  path is untouched when the flag is off. globe_player also gained
  an entity_id (ScopeService resolves the local body by it).
- **Spectate permissions** (LobbyService.request_spectate): friend
  of a fighter -> allowed (reason: friend); same party -> allowed
  (reason: party); everyone else refused -- no public casting of
  private bouts. ArenaInstance.spectators is the room book; the
  return map and payout/streak/recent paths carry fighters only.
- **BoutTeleportService drives the swaps**: assembly reparents the
  team into the room scope before positioning; the return map
  exits the scope before the world move. ZoneManager's zone-entry
  debug log no longer crashes on bodies without display_name.

probe_scene_swap 14/14 (DEFAULT_SET): reparent + flag flips both
ways, planar gravity math, permission matrix (friend/party/
stranger/none), spectator room book, room-close rescue.

## Implementation order (when we pick this up)

**STATUS 2026-09-28 (next session): items 1, 2 (partial), 4 SHIPPED.**

- [x] 1. Recent players ring buffer + Rematch -- SHIPPED
  (RecentPlayersService, LobbyUI Duels tab, probe 12/12).
- [x] 2. Friend presence + actions -- SHIPPED: LobbyService
  get_presence/get_friend_presence join the books (online, zone,
  party+size, queue zone, live bout instance, instance zone);
  LobbyUI People tab (4th tab) renders presence rows with
  Join-queue / Ask-to-join / Spectate (greyed) actions;
  petition_party routes the leader->petitioner consent path.
- [x] 4. Dungeon-finder post type -- SHIPPED: LfgKind enum
  (PARTY/DUNGEON/RAID) in the ONE book; post_lfg kind arg;
  list_lfg kind_filter; solo posters auto-form their party on the
  first petition; LobbyUI posts carry the kind for row styling.
- [x] 3. InstanceService as the shared front door for dungeon/raid
  joins -- SHIPPED (2026-09-28, next session): zone_kind taxonomy
  (bout/dungeon/open; discriminator = horde_config_id -- arenas
  never declare one, so instance_mode cannot separate them since
  ELIMINATION is schema value 0); join_dungeon runs the SAME
  contract checks (capacity via party_fits, QoS attribution) then
  opens a SESSION BOOK. Backstops (owner point 1 generalized):
  AFK sweep (contract 90 s / instance_afk_kick override) returns
  idlers to the dungeon bind; DWELL sweep (instance_time_limit > 0)
  returns the whole party and closes the session. Roster seats are
  freed on return (ZoneManager has no removal API -- the front door
  owns the bookkeeping) so returned seats are never burned against
  capacity. note_instance_activity is the AFK ledger for fight
  code. HordeEventService untouched -- the horde loop sits ON TOP
  of the door (it keys off zone entry). Gloamwood Depths tres got
  instance_time_limit 3600 (1 h dwell cap). probe
  probe_dungeon_front_door 19/19 in DEFAULT_SET.
- [ ] Spectate permissions model; recent-players privacy UI; loot-
  mode griefing rules -- open, recorded above.

Original order (for reference):
