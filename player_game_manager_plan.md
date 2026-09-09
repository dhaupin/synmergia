# Adapter Wiring Plan: PlayerManager + GameManager

> Planning only. No code written. Generated 2026-09-09.
> Note: written to workspace root because /tmp writes are blocked by the
> project permission rule. Copy to /tmp/player_game_manager_plan.md after the
> session if the deliverable path is required.

## 0. Scope note: the files at hand are NOT the services described in AGENTS.md

`game/core/autoload/player_manager.gd` and `game/core/autoload/game_manager.gd` are
**client-side** singletons:

- `player_manager.gd` — the *local player's* stats, health, mana, stamina, gold,
  level, and `get_character_data()`/`load_character_data()`. It holds one
  `local_player` node. It is **not** a server-side registry of connected players.
- `game_manager.gd` — a **client** GameState machine (LOADING / LOGIN /
  MAIN_MENU / LOBBY / CHARACTER_SELECT / PLAYING / PAUSED) that switches scenes
  via `get_tree().change_scene_to_file(...)`.

AGENTS.md describes `PlayerManager` as "Connected player state, peer <-> player_id
mapping" and `GameManager` as "Overall game state, player management, world state"
— the **server-side** services. Those responsibilities live in other files:

| Responsibility | Actual home |
|---|---|
| peer <-> player_id mapping, connected players | `NetworkManager` (`connected_peers: Dictionary`, `_on_server_peer_connected/disconnected`) |
| session tokens | `LoginService` (`_current_session_token`, `_mint_session_token()`) |
| player registry / spawn metadata | `EntityService` (`_players`, `register_entity()`, `player_joined/left`) |
| online status (FriendsService needs it) | `FriendsService` (`_online_players`, `set_player_online/off`) |
| shard / server lifecycle | `ShardManager`, `ServerManager` |

**Recommendation:** wire the *server-side* services (`NetworkManager`,
`LoginService`, `EntityService`, `FriendsService`) to adapters. The two autoload
files at hand are correctly adapter-free today (they are client-only) and should
stay that way. Do **not** add persistence to `player_manager.gd` /
`game_manager.gd` directly — that would persist client-side cache, which is the
wrong layer.

The rest of this document plans the server-side wiring that the AGENTS.md
description refers to.

## 1. Current state summary

### 1.1 The two autoload files at hand (client-side — do NOT persist)

**`game/core/autoload/player_manager.gd`** (244 lines)
- Single `local_player: Node`, character stats (name/class/race/level/XP/gold),
  base_stats, health/mana/stamina.
- `get_character_data()` / `load_character_data()` — serialization helpers that
  already exist for loading a saved character into the local client.
- Signals: `health_changed`, `mana_changed`, `stamina_changed`,
  `experience_changed`, `level_up`, `died`, `stats_changed`.
- `_process()` regenerates stamina client-side.
- **No adapter usage.** Correct: this is client cache of the local character.
  Its data is *owned* by `InventoryService`, `QuestService`, `SkillAcademyService`,
  etc. on the server. The server-side `characters` table (migration
  `V20260907_001__init_accounts.sql`, §3.2 of prd-db.md) is the durable home.

**`game/core/autoload/game_manager.gd`** (202 lines)
- Client `GameState` enum: `LOADING, LOGIN, MAIN_MENU, LOBBY,
  CHARACTER_SELECT, PLAYING, PAUSED`.
- `change_state()`, `pause_game()`, `resume_game()`, `start_game()`, `end_game()`.
- `_handle_playing_state()` calls `_initialize_world_services()` (idempotent via
  `_world_initialized`), which talks to `WorldService`, `ShardManager`,
  `EntityService`.
- Emits `player_entered_world(player_id, character_data)` — the hook other
  services use.
- **No adapter usage.** Correct: this is a client scene-state machine. The
  server-side analogues are `ShardManager` / `ServerManager`.

### 1.2 The server-side services that actually match the AGENTS.md description

| Service | File | Current persistence | Notes |
|---|---|---|---|
| "PlayerManager" (connected players, peer<->id) | `game/core/autoload/network_manager.gd` | None — `connected_peers: Dictionary` | `_on_server_peer_connected/disconnected` maintain it |
| "PlayerManager" (session tokens) | `game/core/services/login_service.gd` | DictStore (`login:account:*`), see §2.3 | Already wired |
| "PlayerManager" (player registry) | `game/core/services/entity_service.gd` | DictStore (`entity:*` metadata) | Already wired (TASKS.md: "EntityService: persist entity metadata on spawn/despawn") |
| "GameManager" (online status) | `game/core/services/friends_service.gd` | None — `_online_players: Dictionary` | `set_player_online/off`, `is_online()` |
| "GameManager" (shard/server lifecycle) | `game/core/services/shard_manager.gd`, `server_manager.gd` | DictStore (ShardManager done per TASKS.md) | ShardManager wired; ServerManager TODO per prd-db §4 |

### 1.3 Existing adapter patterns to follow

`LoginService` is the canonical template (already migrated per TASKS.md line 39):

```gdscript
const DictStore = preload("res://adapters/persistence/dict_store.gd")
const _kv_prefix := "login:account:"

func _load_accounts() -> void:
    var store := DictStore.new()
    if not store.has(_kv_prefix + "_init"):
        _store = {}
        return
    for key in store.all_keys():
        if key.begins_with(_kv_prefix) and key != _kv_prefix + "_init":
            var account_id := key.substr(_kv_prefix.length())
            var entry: Dictionary = store.get(key)
            if not entry.is_empty():
                _store[account_id] = entry

func _persist_account(account_id: String) -> void:
    var store := DictStore.new()
    var entry: Dictionary = _store.get(account_id, {})
    if entry.is_empty():
        store.erase(_kv_prefix + account_id)
    else:
        store.set(_kv_prefix + account_id, entry)
    if not store.has(_kv_prefix + "_init"):
        store.set(_kv_prefix + "_init", {"ts": Time.get_unix_time_from_system()})
```

`EntityService` follows the same shape with `_kv_prefix := "entity:"`.

## 2. PlayerManager (server-side: NetworkManager + LoginService + EntityService)

### 2.1 Session tokens — ALREADY PERSISTED, do not duplicate

`LoginService` already persists accounts via DictStore (`login:account:*`) and
mints `_current_session_token` in memory only. Per prd-db.md §8, the durable
session table (`sessions`, migration V20260907_001) is the audit trail; the hot
token cache belongs in Redis (`SessionStore`), 24h TTL.

**Recommendation: no change to PlayerManager for tokens.** The token itself is
ephemeral by design (client holds it, server validates). What IS worth
persisting is the *session record* (account_id, token_hash, expires_at, ip) —
that is LoginService/AccountService territory and already covered by the
migration. Do **not** add a second token store to PlayerManager; it would
duplicate `SessionStore` and create two sources of truth.

### 2.2 Peer <-> player_id mapping — CACHE ONLY (Redis), with a durable fallback

`NetworkManager.connected_peers` is process-local. It is correct to keep the hot
path in memory, but it has two problems for a multi-process / restart scenario:

1. On server restart, all peer mappings are lost; clients must reconnect.
2. Cross-process routing (if the orchestrator fans out to multiple Godot
   processes) cannot resolve a player_id to a peer without a shared registry.

**Recommended wiring: CacheWrapper (Redis), key `peer:{player_id}`.**

- Value: `{"peer_id": int, "ip": str, "joined": int, "server_id": str}`
- TTL: 0 (no expiry) while connected; deleted explicitly on disconnect.
- On `_on_server_peer_connected`: `cache.set("peer:%s" % player_id, {...})`
- On `_on_server_peer_disconnected`: `cache.delete("peer:%s" % player_id)`
- Lookup helper (used by AutoResponseService, AdminCommands, ServerManager —
  they all reimplement `_get_peer_for_player` today):

```gdscript
func _get_peer_for_player(player_id: String) -> int:
    if not CacheWrapper:
        return _peer_from_local(player_id)
    var entry: Dictionary = CacheWrapper.get("peer:%s" % player_id)
    if entry.is_empty():
        return _peer_from_local(player_id)
    var pid = entry.get("peer_id", -1)
    return pid if pid is int and pid > 0 else -1
```

This is a **cache**, not persistence. It is not in DictStore because it is not
durable — it is intentionally lost on disconnect and rebuilt from the live ENet
peer set. Redis is the right layer: fast, TTL-capable, cross-process.

**Durable fallback (optional, P2):** if the team wants reconnect-after-crash
without re-login, persist the last-known mapping in DictStore
(`pm:peer:{player_id}`) with a `crash_recovery: bool` flag, and reconcile against
the live peer set on boot. **Recommendation: skip for now.** It adds a
cross-process consistency hazard (stale peer_id after a crash) for a feature
that login already handles. See Risks.

### 2.3 Online status — CACHE ONLY (Redis), owned by FriendsService

`FriendsService._online_players` is the single source of truth for
`is_online()`. prd-db.md §4b already defines the key:
`online_player:{character_id} -> {server_id, shard_id, zone_id}`.

**Recommended wiring: CacheWrapper (Redis).**

- `set_player_online`: `cache.set("online_player:%s" % player_id,
  {"online": true, "zone": zone_id, "server_id": ..., "last_update": now})`
- `set_player_offline`: `cache.set("online_player:%s" % player_id,
  {"online": false, "last_seen": now})` — or `cache.delete(...)` per the
  "Immediate expiry on disconnect" TTL strategy in prd-db §4b.
- `is_online`: read the cache; fall back to the in-memory `_online_players`
  dict for the local process.

**Ownership rule:** FriendsService owns the online status. NetworkManager emits
`peer_connected`/`peer_disconnected`; FriendsService listens and translates them
into online status. PlayerManager (i.e. NetworkManager) should **not** write
`online_player:*` directly — that would duplicate the write path.

### 2.4 What NOT to persist for PlayerManager and why

| Data | Verdict | Why |
|---|---|---|
| Session tokens (raw) | Never persist | Security risk; already hashed in `sessions` table |
| Live peer_id mapping | Cache only, not persist | Ephemeral; stale entries are worse than missing |
| In-memory `_failed_attempts` | Never persist | Rate-limit state; Redis `ratelimit:` key already covers this via QoSService |
| Local player stats (client `player_manager.gd`) | Never persist here | Owned by server `characters` table; persisting client cache creates two truths |

## 3. GameManager (server-side: FriendsService + ShardManager + ServerManager)

### 3.1 The client `game_manager.gd` — no persistence, by design

The client GameState machine is a UI-flow concern. Its states
(LOADING -> LOGIN -> MAIN_MENU -> LOBBY -> CHARACTER_SELECT -> PLAYING)
are derived from user actions and server responses, not from durable data.
Persisting them would couple the client to a specific server session and break
the "client reconnects to any server" contract.

**Recommendation: no adapter wiring for `game_manager.gd`.** If a future feature
needs the server to advertise a global phase (e.g. MAINTENANCE), that belongs
in `ServerManager` / `ShardManager` and is read by the client at connect time —
see §3.4.

### 3.2 Online status — the "GameManager-level" state FriendsService needs

The AGENTS.md question "What about online status? (FriendsService needs this)" is
the core GameManager-level concern. Answer: **it is already owned by
FriendsService**, and it should be backed by CacheWrapper (Redis), not
PersistenceStore.

Rationale for cache over persistence:
- Online status is the definition of ephemeral: prd-db §4b gives it
  "Immediate expiry on disconnect".
- It is read heavily (every friend list render, every social query) and written
  on two events (connect, disconnect). Cache is the right latency tier.
- The durable equivalent already exists: `characters.last_online` (migration
  V20260907_001, §3.2) is updated on disconnect by ServerManager. The cache and
  the column serve different readers (live social vs. profile history) and must
  not be confused.

**Recommended method signatures (FriendsService):**

```gdscript
func set_player_online(player_id: String, player_name: String, zone_id: String = "") -> void:
    _online_players[player_id] = { "name": player_name, "online": true, "zone": zone_id, "last_update": Time.get_unix_time_from_system() }
    if CacheWrapper:
        CacheWrapper.set("online_player:%s" % player_id, {
            "online": true, "zone": zone_id, "server_id": _local_server_id(),
            "last_update": Time.get_unix_time_from_system()
        })
    player_status_changed.emit(player_id, true)

func set_player_offline(player_id: String) -> void:
    if _online_players.has(player_id):
        _online_players[player_id].online = false
        _online_players[player_id].last_seen = Time.get_unix_time_from_system()
    if CacheWrapper:
        CacheWrapper.delete("online_player:%s" % player_id)   # immediate expiry
    player_status_changed.emit(player_id, false)

func is_online(player_id: String) -> bool:
    if CacheWrapper:
        var entry: Dictionary = CacheWrapper.get("online_player:%s" % player_id)
        if not entry.is_empty():
            return bool(entry.get("online", false))
    if _online_players.has(player_id):
        return bool(_online_players[player_id].get("online", false))
    return false
```

### 3.3 Shard / server lifecycle — ShardManager done, ServerManager TODO

- `ShardManager` is already persisted via DictStore per TASKS.md line 52.
- `ServerManager` is listed as TODO in prd-db §4 ("Wire disconnect handling to
  DB (mark offline)", "on_player_disconnect() — Persist position, inventory
  state") and §8 maps it to `ServerStore` (Postgres + Redis cache).

**Recommendation for ServerManager: PersistenceStore (DictStore), key
`server:{server_id}`.** Value: `{server_id, host, port, state, started_at,
player_count, shard_id}`. Write on `start_server()` / `stop_server()` and on
player count changes; read on boot to rebuild the registry. This is durable
infrastructure state that must survive a process restart.

### 3.4 Game phase (lobby / playing / maintenance) — CACHE ONLY, optional

The AGENTS.md question "Game phase (lobby, playing, maintenance)?" has two
readers:

1. **Client** — `game_manager.gd` derives this from its own state machine; no
   persistence needed (§3.1).
2. **Server** — a global phase (e.g. MAINTENANCE) that gates connections.

If the server phase feature is built, the right home is **CacheWrapper (Redis)**,
key `server:phase`, value `{phase: "lobby"|"playing"|"maintenance", set_by,
set_at, message}`. Reasons:
- It is a single global value read on every connect check — cache latency is
  correct.
- It changes rarely and is operator-set — no audit requirement that demands
  Postgres.
- It must be visible across all server processes — Redis is the only layer that
  provides that today.

**Recommendation: do not build server-phase persistence yet.** No code path
currently reads a global phase; adding a store for a not-yet-existing feature is
premature. Revisit when `LoginService` needs to reject connections with a
maintenance message. See Risks.

### 3.5 What NOT to persist for GameManager and why

| Data | Verdict | Why |
|---|---|---|
| Client GameState (LOADING/PLAYING/...) | Never persist | Client UI flow; derived from user + server, not durable |
| `selected_character_data` (client) | Never persist | Transient handoff between character_select and world |
| `_world_initialized` (client flag) | Never persist | Process-local idempotency guard |
| Live online status | Cache only | Ephemeral by design; durable twin is `characters.last_online` |
| Global server phase | Cache only, deferred | Operator-set, cross-process, read-heavy — but feature not built yet |

## 4. Recommended wiring summary

| Service (server-side) | Adapter | Store name | Key pattern | Writes on | Reads on |
|---|---|---|---|---|---|
| NetworkManager (peer<->id) | CacheWrapper | `peer` | `peer:{player_id}` | peer_connected / peer_disconnected | `_get_peer_for_player()` |
| LoginService (session tokens) | Already done (DictStore) | `login:account` | `login:account:{id}` | register / login | `_load_accounts()` |
| EntityService (player registry) | Already done (DictStore) | `entity` | `entity:{id}` | register_entity / unregister | `_load_entity_metadata()` |
| FriendsService (online status) | CacheWrapper | `online_player` | `online_player:{character_id}` | set_player_online / set_player_offline | is_online() / get_online_friends() |
| ServerManager (server lifecycle) | DictStore | `server` | `server:{server_id}` | start_server / stop_server | boot registry rebuild |
| ShardManager | Already done (DictStore) | (existing) | (existing) | (existing) | (existing) |
| Client `player_manager.gd` | **None** | — | — | — | — |
| Client `game_manager.gd` | **None** | — | — | — | — |

**Method signatures for new persistence methods** (only the ones not already wired):

```gdscript
# game/core/autoload/network_manager.gd
const CacheWrapper = preload("res://adapters/cache/cache_wrapper.gd")

func _on_server_peer_connected(id: int) -> void:
    # ... existing firewall + connected_peers logic ...
    if CacheWrapper:
        CacheWrapper.set("peer:%s" % ("peer_%d" % id), {
            "peer_id": id,
            "ip": ip,
            "joined": Time.get_ticks_msec(),
            "server_id": _local_server_id()
        })

func _on_server_peer_disconnected(id: int) -> void:
    # ... existing cleanup ...
    if CacheWrapper:
        CacheWrapper.delete("peer:%s" % ("peer_%d" % id))

func _get_peer_for_player(player_id: String) -> int:
    if CacheWrapper:
        var entry: Dictionary = CacheWrapper.get("peer:%s" % player_id)
        if not entry.is_empty():
            var pid = entry.get("peer_id", -1)
            if pid is int and pid > 0:
                return pid
    # fall back to local process state
    for peer_id in connected_peers:
        if "peer_%d" % peer_id == player_id:
            return int(peer_id)
    return -1
```

```gdscript
# game/core/services/friends_service.gd
const CacheWrapper = preload("res://adapters/cache/cache_wrapper.gd")

func set_player_online(player_id: String, player_name: String, zone_id: String = "") -> void:
    # ... existing _online_players update + emit ...
    if CacheWrapper:
        CacheWrapper.set("online_player:%s" % player_id, {
            "online": true, "zone": zone_id, "server_id": _local_server_id(),
            "last_update": Time.get_unix_time_from_system()
        })

func set_player_offline(player_id: String) -> void:
    # ... existing _online_players update + emit ...
    if CacheWrapper:
        CacheWrapper.delete("online_player:%s" % player_id)

func is_online(player_id: String) -> bool:
    if CacheWrapper:
        var entry: Dictionary = CacheWrapper.get("online_player:%s" % player_id)
        if not entry.is_empty():
            return bool(entry.get("online", false))
    if _online_players.has(player_id):
        return bool(_online_players[player_id].get("online", false))
    return false
```

All three wrappers (`DictStore`, `CacheWrapper`, `MemoryWrapper`) follow the
same defensive pattern: `if X:` guards before use, because in `--script` test
mode and first-boot scenarios the registry may not be populated. This matches
the existing `LoginService` / `EntityService` style and the AGENTS.md
"Null Checks for Services" rule.

## 5. Risks and open questions

### 5.1 Risks

1. **Stale peer mappings in Redis (if the durable fallback is built).**
   If a Godot process crashes without cleaning `peer:{id}`, the next server
   boots with a mapping pointing to a dead peer_id. Any code that trusts the
   cache without re-validating against the live ENet peer set will route to a
   ghost. **Mitigation:** always fall back to `_peer_from_local()` and treat
   Redis as a hint, never as truth. This is why the durable fallback is
   recommended **against** in §2.2.

2. **Online status divergence between cache and `characters.last_online`.**
   If FriendsService writes `online_player:*` and ServerManager writes
   `last_online` on the same disconnect event but one path fails (e.g. Redis
   down), the two records disagree. Callers must not assume consistency between
   them — document which reader to use for which purpose (cache = "who is online
   right now", column = "when was this character last seen").

3. **Autoload order for the new CacheWrapper dependency.**
   NetworkManager and FriendsService both gain a `CacheWrapper` dependency.
   CacheWrapper resolves the registry lazily (`get_tree().root.get_node_or_null(
   "AdapterRegistry")`), so it does not create a hard autoload-order
   requirement — but if either service calls it in `_ready()`, the registry
   must already exist. `AdapterRegistry` is listed before both in
   `project.godot` (verified: `AdapterRegistry` precedes `NetworkManager` and
   `FriendsService`). No change needed; verify after any project.godot edit.

4. **Redis-down degradation.**
   All three new cache writes (`peer:*`, `online_player:*`) degrade to
   in-memory state if Redis is unreachable, because the wrappers fall back to
   `MemoryCacheStore` and the services keep their existing `Dictionary` fields.
   This is the intended behavior, but it means cross-process routing silently
   stops working in that mode — log it.

5. **Ownership confusion on `online_player:*`.**
   Both NetworkManager (it knows about peers) and FriendsService (it owns
   online status) are tempting writers. The plan assigns ownership to
   FriendsService explicitly. If another service needs to write it, route
   through `FriendsService.set_player_online/off` to keep one write path.

### 5.2 Open questions

1. **Should `peer:{id}` be shared with the orchestrator?** If the
   multi-iso orchestrator routes RPCs across Godot processes, it needs the
   peer mapping too. The Redis key makes this trivial (any process can read
   it), but the write path must be defined — does only the owning process
   write, or does the orchestrator maintain its own? Not decided here.

2. **Do we need crash-recovery for peer mappings?** See §2.2. Requires a
   DictStore fallback + reconciliation logic. Deferred because login already
   covers re-authentication.

3. **Is `server:phase` (maintenance mode) needed now?** See §3.4. No code
   path reads it yet. Revisit when `LoginService` needs to reject connections.

4. **Should online status be a Redis hash instead of a plain key?** The
   prd-db §4b spec uses `online_player:{character_id}` as a plain key. If
   friends lists need "give me all online players in zone X", a
   `zone:{zone_id}` set (sadd/smembers) would be needed on top. Not
   implemented by any caller yet — add when the first "who's in this zone"
   query lands.

5. **Does the client `game_manager.gd` need a server-driven phase?** Today it
   hard-codes the state machine. If the server introduces MAINTENANCE, the
   client must learn it at connect time (likely via the login handshake), not
   from a persisted value. Out of scope for this plan.
