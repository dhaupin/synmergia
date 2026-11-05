# PRD: Shard Mesh (multi-container deployment)

> **For:** sub-agent implementation
> **Phase:** 1 -> 4 (per `world-building-arch.md` sec.11)
> **Depends on:** `prd-db.md` (adapter layer), `world-building-arch.md` sec.11 (deployment topology)
> **Unblocks:** the "4-5 dockers acting as one" deployment intent

## 1. Introduction/Overview

The original architecture intent is a mesh: several
`synmergia` server processes ("shards") running as separate
containers, coordinated by a shared registry, backed by shared
Postgres + Redis, presented to players as one world.

Today the codebase ships **Phase 1** (one Godot process, all
services autoloaded, in-process frame primitives). The shard
layer is *scaffolded* -- `ShardManager`, `CoordinatorService`,
`ShardParameters`, and the adapter bridges all exist -- but
nothing wires them for multi-container operation. This note is
the intent-vs-reality audit, the transport decision, and the
phased path to close the gap.

**Why this exists:** a Docker audit (PR #50 follow-up) asked
whether the image can run the dev env AND the game server as a
*shard*. Answer: the image runs a dev env and a single server;
it cannot run as a mesh shard without the work below.

## 2. Intent vs reality

| Concern | Intent (arch doc) | Reality today |
|---|---|---|
| Shard identity | Each container a distinct shard (`SHARD_ID`) | No env read; every process is `shard_1`/"Alpha" |
| Shared state | Postgres + Redis across shards | Engine defaults to `memory`; compose sets no backend; bridges default to `sqlite`/`inmemory` |
| Cross-shard bus | Coordinator routes events | `CoordinatorService` is in-process only, zero transport |
| Orchestrator | Julia `multi-iso` orchestrator | `MultiIsoService` DORMANT (not autoload, zero call sites); `julia-bridge/` has no compose service |
| Transport | Proxyable to an LB | ENet **UDP** server; no WebSocket *server*; nginx cannot front it |
| Scaling | N shards behind an LB | 5 fixed host port binds block `--scale`; nginx hardcodes one upstream |

### 2.1 The boot path today

`NetworkManager._ready` (game/core/autoload/network_manager.gd:107)
reads `START_MODE`; for `prod|headless|server` it calls
`_auto_start_server(GODOT_PORT or 9876)`. That is the whole
server boot. No shard identity, no coordinator registration, no
backend choice beyond what the env happens to carry.

### 2.2 Env surface the engine actually reads

Only these env vars are consumed anywhere in `game/`:

```
START_MODE  GODOT_PORT  STORAGE_BACKEND  CACHE_BACKEND
PG_BRIDGE_URL  REDIS_BRIDGE_URL
WEBHOOK_BRIDGE_URL  WEBHOOK_TRANSPORT_TIMEOUT_MS
PAYMENT_WEBHOOK_PROVIDER  ASYNC_MESH  VISTA_EYE_H  SYNMERGIA_SCAN_SEED
GODOT_PROBE_XVFB
```

There is **no** `SHARD_ID`, `SHARD_NAME`, `IS_PRIMARY`, or
`COORDINATOR_URL`. Compose sets `POSTGRES_*`/`REDIS_*` for the
bridge containers, but the *game* container never receives the
bridge URLs, so the adapters never leave memory.

### 2.3 The silent one: `DictStore` "default"

`ShardManager._load_shards` / `_persist_shard` and
`CoordinatorService._persist_state` write through
`DictStore.new()` with the default store name `"default"`.
`BackendFactory.boot_defaults()` registers every name in
`STORE_MANIFEST` -- but `"default"` is **not in that manifest**,
and `AdapterRegistry.get_persistence("default")` returns null.
`DictStore._ensure_store` then falls back to a *process-local*
`MemoryPersistenceStore`. So even with `STORAGE_BACKEND=postgres`,
shard and coordinator registries stay per-process and evaporate
on restart. This is a correctness bug for the mesh, independent
of the transport question.

## 3. The transport fork (decision required)

The mesh's transport decides everything downstream. Two options:

**Option A -- ENet (UDP) + L4 load balancer.**
Keep `ENetMultiplayerPeer`. Front the shards with an L4 (UDP)
proxy or per-shard address + a routing/redirect tier. Pros:
no engine change to the hot path; ENet is already the client
protocol. Cons: nginx (L7) cannot front it; sticky routing is
on us; browser clients cannot use raw UDP.

**Option B -- WebSocket server + nginx upgrade.**
Add a `WebSocketServer` in the engine (Godot 4 supports
`WebSocketMultiplayerPeer.create_server`). nginx proxies
`/ws/` with `Upgrade`/`Connection` headers. Pros: one L7 entry,
works for native + browser clients, standard LB. Cons: engine
work; WS overhead vs ENet.

**Recommendation:** Option B for the *edge* (nginx-fronted,
browser-capable), with Option A retained for native clients
that want ENet directly. The immediate slice below (identity +
shared state) is transport-agnostic and should land first --
it makes shards *distinct* and *persistent*, which both options
need.

## 4. Phased path

### Phase 0 -- Shard identity + shared state (this PR)

- **Identity:** read `SHARD_ID`/`SHARD_NAME`/`IS_PRIMARY`/
  `WORLD_SIZE_KM2`/`MAX_PLAYERS_PER_SHARD` at boot and call
  `ShardManager.configure()`; register with `CoordinatorService`.
- **Shared state:** register the `"default"` store in
  `BackendFactory`; set `STORAGE_BACKEND`/`CACHE_BACKEND` +
  bridge URLs in compose; install `psycopg`/`redis` in the image;
  run bridges on real backends.

Outcome: shards are distinct and persistent. Still single-node
for routing, but the foundation both transport options require.

### Phase 1 -- Cross-shard bus (this PR)

Give `CoordinatorService` a real transport (Redis pub/sub is the
natural fit -- Redis is already a compose service). Extract the
coordinator to its own process if contention warrants.

Shipped: the transport is a **swappable seam** (`game/core/mesh/`),
mirroring the payment-provider plugin law. `ShardBus` is the contract
(`subscribe`/`publish`/`poll`); `ShardBusRegistry` is the plugin board
(re-registering an id replaces it; `make_default` re-points), seeded
with `MemoryShardBus` so dev/CI are unchanged. `RedisShardBus` is the
cross-process transport over the redis-bridge sidecar.

The mailbox protocol: each bus instance has a self id (its shard id),
`publish(topic, message)` drops a JSON copy into the per-(subscriber,
topic) inbox list of every OTHER subscriber (the no-echo law), and
`poll(topic)` drains the self inbox. `CoordinatorService` publishes on
every `emit_cross_shard_event` and drains remote mail inside
`get_pending_events`, so remote events ride the same exactly-once path
as local emits. Transport selection is `SHARD_BUS_BACKEND`, defaulting
to follow `CACHE_BACKEND`; a failed Redis connect falls back to the
memory bus rather than failing the boot.

Outcome: separate shard processes can exchange cross-shard events. The
edge (LB + sticky routing) is still Phase 2.

### Phase 2 -- Edge transport

Pick Option A or B above; wire the LB/nginx and sticky routing.

### Phase 3 -- Topology

A `coordinator` service + N `shard` services (unique `SHARD_ID`,
no fixed host ports) over shared Postgres/Redis. Compose example:

```yaml
services:
  coordinator:
    image: synmergia
    environment:
      START_MODE: coordinator
      REDIS_BRIDGE_URL: http://redis-bridge:8080
  shard:
    image: synmergia
    environment:
      START_MODE: headless
      SHARD_ID: ${SHARD_ID}
      STORAGE_BACKEND: postgres
      CACHE_BACKEND: redis
      PG_BRIDGE_URL: http://pg-bridge:8080
      REDIS_BRIDGE_URL: http://redis-bridge:8080
    deploy:
      replicas: 4
```

## 5. Out of scope (this note)

- The edge transport implementation itself (Phase 2).
- Real HA Postgres/Redis (deployment concern).
- The dormant Julia orchestrator (separate `prd-multiworld.md`
  and `world-building-arch.md` sec.11.2 deferral).

## 6. Acceptance for Phase 0

- A container booted with `SHARD_ID=shard_2` reports `shard_2`
  as its identity (not `shard_1`).
- Two containers with different `SHARD_ID` both register with the
  coordinator and see each other in the registry.
- With `STORAGE_BACKEND=postgres`, shard/coordinator registries
  survive a process restart.
- Defaults are unchanged: no `SHARD_ID` -> `shard_1`; no backend
  env -> `memory` (dev/CI stay green).

## 7. Acceptance for Phase 1

- Two `ShardBus` instances with different self ids exchange a
  published message; the publisher does not receive its own fan-out.
- Re-registering a bus id on the registry replaces it, and
  `make_default` re-points the default.
- An event emitted on one `CoordinatorService` instance arrives in a
  second instance's `get_pending_events`.
- `SHARD_BUS_BACKEND=redis` with no reachable bridge falls back to the
  memory bus (boot never fails on a missing sidecar).
- Defaults are unchanged: no `SHARD_BUS_BACKEND` + no
  `CACHE_BACKEND=redis` -> the memory bus (dev/CI stay green).

Receipt: `game/tests/test_shard_bus.gd` (17 legs).
