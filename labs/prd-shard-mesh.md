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
  edge:                            # Phase 3.1: the ONE client entry
    build: .
    profiles: [mesh]
    ports:
      - "${EDGE_HTTP_PORT:-8088}:80"
      - "${EDGE_HTTPS_PORT:-8443}:443"
    environment:
      - START_MODE=edge            # nginx only; no Godot, no game port
      - GODOT_UPSTREAM=shard:9000  # expanded to ip_hash upstream servers
```

Each shard has no fixed host ports (the mesh is addressed by service
name), so replicas never collide; `--scale shard=N` gives N shards. The
`edge` service is the single client entry, sticky-routing to the shards.

### Phase 3.1 -- Edge proxy + per-shard tuning (SHIPPED)

**The edge proxy.** Phase 2 shipped the websocket transport and the
`ip_hash` upstream block; Phase 3.1 adds the container that USES it.
`START_MODE=edge` boots nginx only (no Godot, no game port of its own)
and fronts the shard replicas with sticky routing, so a WebSocket
upgrade and the client's follow-up requests land on the SAME shard. The
`mesh` compose profile gains an `edge` service publishing
`${EDGE_HTTP_PORT:-8088}`/`${EDGE_HTTPS_PORT:-8443}` and passing
`GODOT_UPSTREAM` (default `shard:9000`); the entrypoint's existing
`_setup_nginx` expands the list into upstream `server` lines. One entry
into the mesh, standard L7, browser-capable.

**The tuning lever.** The mesh's default is interchangeable shards, but
the endgame is shards that are NOT interchangeable ON PURPOSE -- an event
shard, a hardcore shard with a lower cap, a seasonal shard with a raised
one. The hook is `ShardParameters` (autoload, D033), a per-`shard_id`
parameter store with data-driven `ShardParameterDefinition` .tres.

Shipped:

- `ShardParameters.get_param(shard_id, name)` -- the read accessor the
  note flagged as missing. It returns the applied state-tree value, else
  the definition's `default_value`, else null. (The write path lands in
  the shard state tree; a local read must see it without touching shared
  state.)
- Two parameter definitions: `level_cap_override` (int, critical) and
  `xp_ratio_override` (float, critical). Critical so an operator's write
  is immediately effective AND immediately readable.
- `LevelCurve` gains a shard-aware read: `set_shard_tuning(cap, ratio)`
  / `clear_shard_tuning()` / `has_shard_tuning()`. `max_level()`
  precedence is shard override -> `LEVEL_CAP` env -> `DEFAULT_CAP`;
  `level_cost()` compounds the post-band ratio through
  `effective_band_step()`. The in-band (1..10) law is untouched.
- `ShardTuning` (`game/core/progression/shard_tuning.gd`) is the
  resolver: `apply(shard_id, sp)` folds the shard's overrides into the
  curve. `ShardManager` calls it at boot and re-applies on
  `param_applied` for a tuning param of its own shard, so a running
  shard's numbers can flip without a reboot.

**The operator surface.** The lever shipped with a data path but no
handle; `/shardparam` (admin-only, `ChatService`) closes that:

- `/shardparam` -- the state board: one line per known shard
  (`ShardManager.mesh_shards()`: itself + connected, deduped), each
  showing the effective cap/ratio and whether a local override is in
  force.
- `/shardparam <shard_id>` -- one shard's tuning numbers.
- `/shardparam <shard_id> <cap> [ratio]` -- set the cap (>= 2) and/or
  the post-band XP ratio (>= 0), then the local curve re-reads through
  the `param_applied` listener (no explicit re-apply needed; the lever
  is local, so a non-local shard's curve is untouched).
- `/shardparam <shard_id> reset` -- drop the overrides (uniform curve).
- Absurd values (cap < 2, negative ratio) are refused by name with the
  prior value intact.

**Two honesty rules, both enforced by the receipt:**

1. **Uniform by default.** Absent an override every shard runs the same
   curve (`DEFAULT_CAP`, `BAND_STEP`). A cap-only override leaves the
   ratio alone; a ratio-only override leaves the cap alone.
2. **Local, never shared.** An override is a *read* on one process; it
   never leaks into cross-shard identity or the mesh's hashed state. The
   receipt resolves a second shard and proves it stays uniform.

**What stays out of scope:** a shard's curve override must not leak into
cross-shard identity. Shared-state values that the mesh hashes (Phase 0)
are world-truth and stay uniform; tuning is a *local read*, never a
*shared write*.

### Phase 3.2 -- Per-shard content packs (SHIPPED)

**The second lever.** Phase 3.1 raised and lowered the CURVE per shard.
Phase 3.2 turns whole CONTENT BUNDLES on and off per shard through the
SAME lever -- `ShardParameters` -- so an event shard can close a season,
a hardcore shard can drop a reward lane, and the shared mesh identity
stays uniform.

Shipped:

- `ContentPackData` (`game/core/schemas/content_pack_data.gd`): a named
  bundle of `enemy_ids` + `quest_ids`; `missing_refs(ds)` reports ids
  that name no content (the phantom-SKU guard).
- `ContentPacks` (`game/core/mesh/content_packs.gd`): the resolver.
  `load_packs()` scans `data/content_packs/*.tres`; `disabled_set()` /
  `is_pack_disabled()` parse the shard's `disabled_content_packs`
  ShardParameter (comma-separated); `enemy_enabled()` / `quest_enabled()`
  are the gate predicates; `local_*_enabled()` resolve the LOCAL shard
  from the tree; `board()` feeds the operator view.
- A new critical parameter definition `disabled_content_packs` (string,
  default `""`). Critical so an operator's write is immediately effective
  and immediately readable -- same contract as the tuning params.
- One pack authored: `pack_tide_season` (the Sundered Sea's band-40/50/60
  income lane -- `tidecursed_diver`, `gloamwood_stalker`,
  `trench_sentinel` + `quest_tide_salvage`, `quest_sentinel_wake`,
  `quest_deep_toll`, `quest_gloamwood_ledger`).

**The gates.** A disabled pack hides its content on every real route:

- `QuestService` -- `_get_available_quest_ids`, `get_available_quests`
  (the offered roster), and `check_quest_availability` (the accept gate,
  which refuses by name: "Content pack disabled on this shard").
- `SpawnService` -- `spawn_enemy_direct`, `spawn_boss`, and `_create_enemy`
  (the spawn-point path).
- `HordeEventService` -- `_produce_mob` (the wave-mob path; the wave
  boss also rides `spawn_boss`).

An id owned by NO pack is always allowed, so a typo never silently
removes content.

**The operator surface.** `/contentpack` (admin-only, `ChatService`):

- `/contentpack` -- the board: one line per pack for the LOCAL shard.
- `/contentpack <pack_id>` -- one pack's state + owned-id counts.
- `/contentpack <pack_id> enable|disable` -- toggle the pack on THIS
  shard through the ShardParameters lever.

**Mesh visibility.** `/mesh` (admin-only) reports the container's mesh
identity read-only: role + self id (`MeshRole`), the shard registry
(`CoordinatorService.get_all_shard_ids()`), and the active bus
(`get_default_bus_id()` / `get_display_name()`). No writes.

**Two honesty rules, both enforced by the receipt:**

1. **Uniform by default.** Absent a disable every pack is enabled.
2. **Local, never shared.** A disable is a *read* on one process; the
   receipt resolves a second shard and proves it stays uniform.

## 5. Out of scope (this note)

- Real HA Postgres/Redis (deployment concern).
- The dormant Julia orchestrator (separate `prd-multiworld.md`
  and `world-building-arch.md` sec.11.2 deferral).
- **Per-shard tuning** is now WIRED (Phase 3.1 above) for the curve/cap
  surface. It remains a LOCAL read only; any tuning value that must be
  shared is a different (harder) problem and a different note.

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

## 10. Acceptance for Phase 3.1

- `START_MODE=edge` boots nginx only (no Godot, no game port) and
  fronts the shards with the `ip_hash` upstream; the `mesh` compose
  profile defines an `edge` service passing `GODOT_UPSTREAM`.
- `ShardParameters.get_param(shard_id, name)` returns the applied
  state-tree value, else the definition `default_value`, else null.
- The two tuning definitions load (`level_cap_override` int,
  `xp_ratio_override` float), both critical.
- Uniform by default: absent an override `max_level()` is `DEFAULT_CAP`
  and the post-band ratio is `BAND_STEP`.
- A cap override sets `max_level()` and leaves the in-band law and the
  ratio untouched; a ratio override compounds the post-band cost and
  leaves the cap at `DEFAULT_CAP`.
- A shard override outranks the `LEVEL_CAP` env.
- The override is LOCAL: resolving a second, override-free shard
  returns the uniform curve.
- An absurd cap (< 2) or a negative ratio is ignored (uniform).
- Clearing the override restores the uniform curve.

Operator surface (`/shardparam`):

- A non-admin sender is refused; the write does not land.
- An admin set lands the cap and the local curve re-reads it live (the
  `param_applied` signal path fires for the write).
- The read view and the state board report the numbers.
- The set is LOCAL: a second shard stays uniform.
- An absurd cap is refused by name with the prior value intact.
- Reset restores `DEFAULT_CAP` and clears `has_shard_tuning()`.

Receipts: `game/tests/test_shard_tuning.gd` (38 legs) +
`game/tests/test_shard_tuning_admin.gd` (22 legs).

## 11. Acceptance for Phase 3.2

- The pack data loads and every owned id resolves DataService truth
  (no phantom SKUs); the `pack_` prefix + filename==id rule holds.
- Uniform by default: absent a disable every pack is enabled.
- A disabled pack hides its quests from the offered roster AND the
  accept gate (refused by name), and its enemies from every spawn route
  (`spawn_enemy_direct`, `spawn_boss`, the spawn-point path, horde mobs).
- An id owned by NO pack is unaffected by any disable.
- The gate is LOCAL: a second shard stays uniform.

Operator surface (`/contentpack`):

- A non-admin sender is refused; the write does not land.
- An admin disable lands on the local shard and is readable immediately
  (the critical-param contract); enable clears it.
- The board lists every pack; the read view reports state + counts.
- An unknown pack id is refused by name.

Mesh visibility (`/mesh`):

- A non-admin sender is refused.
- An admin report names role + self id (matching `MeshRole`), the
  registry (matching `CoordinatorService.get_all_shard_ids()`), and the
  active bus (`get_display_name()`).
- The report is read-only (the registry is unchanged after it).

Receipts: `game/tests/test_content_packs.gd` (35 legs) +
`game/tests/test_mesh_command.gd` (11 legs).

## 12. Agent seats on the mesh (hosted executors)

The agent control layer (`labs/prd-agent-play.md`) meets the mesh here: an
agent's **seat** and an agent's **executor** are different things.

- **The seat is server-side and shard-owned.** A seat is a body in the
  world: the character, its position, its party membership, its purse. It
  lives on a shard like any player's, and the turn law (one local seat at a
  time) is a per-process fact.
- **The executor is wherever the agent runs.** An agent may be a browser tab
  on the human's machine, a vant install on their laptop, an OpenHands
  sandbox, or a **hosted runner** on the operator's infra. The door does not
  care where the brain lives; it only sees `observe`/`act` traffic.
- **Hosted executors are a later lane.** "Run my agents for me" (so a human's
  agents keep playing while their laptop is closed) is a paid-capability
  question, and it belongs to the mesh: a hosted executor is a container the
  mesh schedules, bound to the same account, driving the same door. Nothing
  here ships it; this section records that the shape is a mesh concern, not a
  client concern.
- **The binding is account-scoped, not shard-scoped.** Agent slots
  (`AgentRoster`) belong to the account; a seat lands on whichever shard the
  account's characters are on. A mesh-wide roster read is a Phase-4 item
  (the account's slot ledger would ride the shared state tree like every
  other cross-shard fact).

Open question recorded, not answered: whether a hosted executor is billed as
a slot (the account's slot ladder) or as its own hosting meter. The slot
ladder is the access floor; hosting is the compute. Keep them separable until
the mesh lane picks it up.
