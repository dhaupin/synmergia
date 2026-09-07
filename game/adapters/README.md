# Adapter Layer

The typed layer between game services and storage backends.
Every service that needs DB / cache / memory goes through
here. No service holds a `Postgres` or `Redis` reference; they
hold a typed `Store` interface, resolved by name from
`AdapterRegistry`.

Source of truth for the architecture: `labs/prd-db.md`
sections 5-10. This file is the developer guide for the
actual code.

## Layout

```
game/adapters/
  persistence/
    persistence_store.gd        # interface (class_name)
    memory_persistence_store.gd # in-memory SQL shim
    postgres_store.gd           # HTTP-to-Postgres via pg-bridge
  cache/
    cache_store.gd              # interface (class_name)
    memory_cache_store.gd       # in-memory KV
    redis_store.gd              # HTTP-to-Redis via redis-bridge
  memory_layer/
    memory_store.gd             # process-local (no TTL, no IPC)
  migrations/                   # versioned SQL (held until schemas locked)
  registry.gd                   # autoload, name -> store
  backend_factory.gd            # autoload, env-driven backend selection
  README.md                     # this file

game/tests/adapters/            # adapter-layer tests
  test_persistence_store.gd
  test_cache_store.gd
  test_memory_store.gd
  test_registry.gd
  test_adapter_integration.gd
```

## Interfaces (the contracts)

Three base classes, one per storage kind. They live in the
subdirs and have global `class_name` so any file can reference
them.

- **`PersistenceStore`** - durable, ACID, queries. Services
  depend on this for anything that survives restart.
- **`CacheStore`** - fast KV, TTL, pub/sub. Sessions, online
  status, rate limits, materialized intersections.
- **`MemoryStore`** - process-local, no cross-process. Active
  cooldowns, AOI sets, follow targets. Already a thin wrapper
  over Godot's `Dictionary`.

See `persistence_store.gd`, `cache_store.gd`, `memory_store.gd`
for the full method surface.

## Backends (concrete impls)

| Backend | Layer | Status |
|---------|-------|--------|
| `MemoryPersistenceStore` | persistence | complete, used for tests + dev/offline |
| `MemoryCacheStore` | cache | complete, used for tests + dev/offline |
| `MemoryStore` | memory | complete, always in-process |
| `PostgresStore` | persistence | wire protocol complete, awaits `pg-bridge` sidecar |
| `RedisStore` | cache | wire protocol complete, awaits `redis-bridge` sidecar |

The HTTP-backed stores will work as soon as their sidecar
services exist. Until then, `BackendFactory` falls back to
memory and logs a warning.

## Registry (autoload)

`AdapterRegistry` is a global autoload (see `project.godot`).
Services resolve stores by name:

```gdscript
var accounts := AdapterRegistry.get_persistence("accounts")
var row: Dictionary = accounts.query_one(
    "SELECT * FROM accounts WHERE username = $1",
    [username]
)

var sessions := AdapterRegistry.get_cache("sessions")
sessions.set("session:%s" % token, account_id, 86400)

var cooldowns := AdapterRegistry.get_memory("cooldowns")
cooldowns.set("plr_%s:fireball" % player_id, expires_at)
```

Returns `null` if the name isn't registered. Always null-check
in early-boot paths.

## Backend selection (env-driven)

`BackendFactory` (autoload) reads:

- `STORAGE_BACKEND` = `memory` (default) | `postgres`
- `CACHE_BACKEND`   = `memory` (default) | `redis`
- `PG_BRIDGE_URL`   = `http://pg-bridge:8080` (if postgres)
- `REDIS_BRIDGE_URL` = `http://redis-bridge:8081` (if redis)

At `_ready()`, it walks `STORE_MANIFEST` and registers each
named store with the appropriate backing. Failed connect
(e.g. unreachable sidecar) falls back to memory + warning.

## Store manifest

See `backend_factory.gd` for the full mapping. The 60+ stores
are categorized:

- **Persistence** (Postgres when live, memory for dev):
  accounts, characters, inventories, equipment, vaults,
  guilds, friends, parties, loot_history, loot_tables,
  chat_log, votes, factions, waypoints, zones, spawns,
  trade_history, recipes, skills, achievements, titles,
  bans, mutes, security_log, anticheat_events,
  auto_responses, transfers, respawn_points, death_log,
  metrics, entities, world_state, world_events, shards,
  servers, game_data, matchmaking_queue, dialogues,
  agent_connectors, agent_actions, player_settings,
  npc_offerings, container_configs, target_schemas,
  species
- **Cache** (Redis when live, memory for dev): online_status,
  rate_limits, cooldowns, session_cache, item_cache,
  guild_cache, zone_cache, event_subscriptions
- **Memory** (always in-memory): active_loot, active_follows,
  active_wars, active_revives, active_waypoints,
  active_trades, active_locks, active_dialogue,
  anti_cheat_profiles, connected_agents

## Wire protocol (for sidecar implementers)

`pg-bridge` and `redis-bridge` are small HTTP services that
proxy to the real backend. Wire format is documented in the
header comment of each `*_store.gd` file. Both run in
docker-compose alongside Postgres and Redis.

If you need to swap backends, the adapter interface doesn't
change, only the adapter file. The registry swap is one
env var.

## Tests

All tests run with Godot headless and follow the project's
existing test pattern (`extends SceneTree` + `_initialize()`).

```bash
cd game
godot --headless --path . --script res://tests/adapters/test_persistence_store.gd
godot --headless --path . --script res://tests/adapters/test_cache_store.gd
godot --headless --path . --script res://tests/adapters/test_memory_store.gd
godot --headless --path . --script res://tests/adapters/test_registry.gd
godot --headless --path . --script res://tests/adapters/test_adapter_integration.gd
```

The integration test exercises the full path: a fake login
service uses the stores end-to-end (account register, login,
session TTL, rate limit, logout). It's the proof-of-concept
template for wiring real services.

## Adding a new store

1. Pick which layer it belongs in (persistence / cache / memory)
2. Add the name to `STORE_MANIFEST` in `backend_factory.gd`
   with the consumer service(s) in a comment
3. If persistence/cache, the auto-registered store will use
   the same backend as the others (one `MemoryPersistenceStore`
   instance, one `PostgresStore`, etc.). Services share.
4. If memory, a new `MemoryStore` is auto-created per name.
5. Test the new store at `game/tests/adapters/`

## Migrations

`game/adapters/migrations/` is reserved for versioned SQL
files. The migration runner is held per the user note
2026-09-07 (schemas in `labs/prd-db.md` section 3 are not yet
locked). Naming convention: `V<YYYYMMDD>_<seq>__<name>.sql`.
