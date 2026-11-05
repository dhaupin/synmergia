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

**Decision: Option B (WebSocket server + nginx L7).** Option A (ENet
+ L4) is retained for native clients that want UDP directly, but the
*edge* is websocket: one nginx entry, browser-capable, standard LB.

Shipped: `NetworkManager` selects the server transport from
`EDGE_TRANSPORT` (`enet` default, `websocket`; aliases `ws`/`wss`,
case-insensitive; unknown values fall back to `enet` with a warn).
`_make_server_peer(port)` builds the matching `MultiplayerPeer` --
`ENetMultiplayerPeer.create_server` or
`WebSocketMultiplayerPeer.create_server` -- and `start_server` /
`connect_to_server` ride it unchanged. The client path already spoke
websocket for browser builds; a mesh now routes native clients there
too, so one L7 entry serves both.

nginx: the `upstream godot` block carries `ip_hash` (sticky routing,
so a websocket upgrade and the client's follow-up requests land on the
same shard). `GODOT_UPSTREAM` is now a comma/space list; the entrypoint
expands it into one `server` line per shard. A single-container deploy
passes one host and is byte-identical to before.

Outcome: a client reaches a shard behind nginx over websocket with
session affinity. Topology (coordinator + N shards) is Phase 3.

### Phase 3 -- Topology (SHIPPED)

A `coordinator` service + N `shard` services (unique `SHARD_ID`,
no fixed host ports) over shared Postgres/Redis.

**The role law (`game/core/mesh/mesh_role.gd`).** ONE file owns what a
container is, resolved from env only and totally (an unset/unknown combo
falls back to `standalone`, so a dev boot is unchanged):

| Env | Role |
|-----|------|
| `START_MODE=coordinator` | `coordinator` |
| `SHARD_ID` set, or `START_MODE` in prod/headless/server | `shard` |
| otherwise | `standalone` |

`MeshRole.self_id()` is the mesh identity: the coordinator id for a
coordinator, else the shard id. `MeshRole.shard_id()`: an explicit
`SHARD_ID` wins; `MESH_AUTOSHARD` with `SHARD_ID` unset derives a
sanitized id from `HOSTNAME` (so `docker compose --scale shard=N` needs
no per-replica id); neither -> `shard_1` (the dev default).

**The cross-process registry.** The Phase 1 bus carries a second topic,
`coordinator:mesh`, so mesh bookkeeping never mixes with gameplay events
on `coordinator:events`. A shard announces its registration
(`announce_self_to_mesh`) on that topic; any coordinator -- in ANOTHER
process -- ingests it (`_ingest_mesh_mail`) and folds it into the normal
registry. The registry reads (`get_all_shard_ids` / `get_all_shards` /
`get_shard_info`) ingest first, so a cross-process shard is visible the
moment anyone asks. Ingest never re-publishes (no loop) and the bus
already no-echoes a publisher. The coordinator does NOT register as a
shard (announce is a no-op for it).

**The coordinator role** boots Godot headless but serves NO game port
(entrypoint `coordinator` mode; it is not a shard). It still starts the
shared-state bridges so the registry (Postgres) and bus (Redis) are live.

**Compose topology** (`docker-compose.yml`, opt-in `mesh` profile --
dev/prod/headless stay single-node):

```bash
docker compose --profile mesh up --build --scale shard=4
```

```yaml
services:
  coordinator:
    build: .
    profiles: [mesh]
    environment:
      - START_MODE=coordinator
      - STORAGE_BACKEND=postgres
      - CACHE_BACKEND=redis
      - PG_BRIDGE_URL=http://127.0.0.1:8080
      - REDIS_BRIDGE_URL=http://127.0.0.1:8081
      - POSTGRES_HOST=postgres
      - REDIS_HOST=redis
  shard:
    build: .
    profiles: [mesh]
    environment:
      - START_MODE=headless
      - MESH_AUTOSHARD=true        # unique id per replica (no fixed ports)
      - EDGE_TRANSPORT=websocket   # nginx-frontable, sticky-routed
      - STORAGE_BACKEND=postgres
      - CACHE_BACKEND=redis
      - POSTGRES_HOST=postgres
      - REDIS_HOST=redis
```

Each shard has no fixed host ports (the mesh is addressed by service
name), so replicas never collide; `--scale shard=N` gives N shards.### Phase 3.1 -- Per-shard tuning (the "event shard" lever, future)

The mesh's whole point is that shards are interchangeable -- but
the interesting endgame is the opposite: **shards that are NOT
interchangeable, on purpose.** Event shards, 100x PvP shards, a
hardcore shard with a lower cap, a seasonal shard with a raised
one. Each spun up with its own numbers, each still riding the same
identity + shared-state + bus + edge we already shipped.

The hook already exists: `ShardParameters` (autoload, D033) is a
per-`shard_id` parameter store with data-driven definitions in
`data/roots/world/parameters/*.tres` and a critical/non-critical
apply contract. It is the natural home for shard-local tuning
values -- it was built for exactly this ("boss_defeated",
"respawn_rate_modifier", "season_active", "world_event_active").

**The shape when we wire it:**

- A shard-local **progression override** parameter, e.g.
  `level_cap_override` (int) and `xp_ratio_override` (float),
  declared as `ShardParameterDefinition` .tres alongside the
  existing four.
- `LevelCurve.max_level()` / `LevelCurve.level_cost()` gain a
  shard-aware read: env (`LEVEL_CAP`) stays the deployment
  default; a shard parameter overrides it for that `shard_id`
  only. No `.tres` content pack changes -- the same law, read
  through one more layer.
- Because the cap/curve is already one authority
  (`game/core/progression/level_curve.gd`), this is a *read-path*
  change, not a data sweep: every consumer that goes through
  `LevelCurve` inherits the shard's numbers for free.

**Two honesty rules for whoever wires it:**

1. **Uniform by default.** Absent an override, every shard runs
   the same curve -- normal shards stay in sync (the requirement
   above is not negotiable for the default case).
2. **`ShardParameters` has no read accessor today.** It has
   `set_param` / `get_definition` / pending-queue reads, but no
   `get_param(shard_id, name)` returning the effective value;
   the write path lands in the shard state tree. Wiring the
   override means adding that read (state-tree lookup with the
   definition's `default_value` fallback) -- small, but it is
   new surface, not a call that exists.

**What stays out of scope:** a shard's curve override must not
leak into cross-shard identity. Shared-state values that the
mesh hashes (Phase 0) are world-truth and stay uniform; tuning
is a *local read*, never a *shared write*. If a shard's numbers
ever need to be shared, that is a different (harder) problem and
a different note.

## 5. Out of scope (this note)

- Real HA Postgres/Redis (deployment concern).
- The dormant Julia orchestrator (separate `prd-multiworld.md`
  and `world-building-arch.md` sec.11.2 deferral).
- **Per-shard tuning** (Phase 3.1 above) -- the curve/cap surface
  is deliberately uniform across the mesh for now; the
  `ShardParameters` hook exists but is not wired.

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

## 8. Acceptance for Phase 2

- No `EDGE_TRANSPORT` -> `enet` (dev/CI byte-identical).
- `EDGE_TRANSPORT=websocket` (and the `ws`/`wss` aliases, any case)
  selects the websocket server transport.
- An empty `EDGE_TRANSPORT` -> `enet`; an unknown value -> `enet`
  (honest fallback, never a boot failure).
- `_make_server_peer` builds an `ENetMultiplayerPeer` for enet and a
  `WebSocketMultiplayerPeer` for websocket; the websocket peer binds
  (reaches `CONNECTION_CONNECTED`) -- the Option B capability.
- `get_connection_info()` reports the selected `edge_transport`.
- nginx carries `ip_hash` on the `godot` upstream, and the entrypoint
  expands a comma/space `GODOT_UPSTREAM` list into one `server` line
  per shard (single host == the previous config).

Receipt: `game/tests/test_edge_transport.gd` (14 legs).

## 9. Acceptance for Phase 3

- `MeshRole.resolve()`: coordinator / shard / standalone from the env,
  with an unknown mode falling back safely.
- `MeshRole.self_id()` is the coordinator id for a coordinator, the
  shard id otherwise.
- `MeshRole.shard_id()`: explicit `SHARD_ID` wins; `MESH_AUTOSHARD`
  derives a sanitized id from `HOSTNAME`; neither -> `shard_1`.
- A shard announces on the mesh topic and a SEPARATE coordinator
  instance ingests it -- the registry spans processes.
- A repeat announce is idempotent (one entry, refreshed).
- A departure announce removes the shard from the registry.
- The coordinator does not register itself as a shard, and a coordinator container running ShardManager does not plant a phantom default shard into the registry.
- Defaults unchanged: no mesh env -> the single-node boot.

Receipt: `game/tests/test_shard_mesh_topology.gd` (20 legs).
