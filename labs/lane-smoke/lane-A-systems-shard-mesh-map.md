# Lane A smoke test -- shard-mesh inventory

> **Scope:** a read-only inventory of the shard-mesh system as it exists on
> this branch. Grounded in files I actually read. No game/ code was
> modified, no tests were run, nothing was committed.
>
> **Source of truth:** `labs/prd-shard-mesh.md` (the design note).
> **Date:** 2026-11-06.

## 1. The phase list (from the design note)

The note's "Phased path" (sec. 4) lists six phases:

| Phase | Title | Note's status claim |
|-------|-------|---------------------|
| Phase 0 | Shard identity + shared state | "this PR" |
| Phase 1 | Cross-shard bus | "this PR" |
| Phase 2 | Edge transport | shipped (websocket + nginx) |
| Phase 3 | Topology (coordinator + N shards) | "(SHIPPED)" |
| Phase 3.1 | Edge proxy + per-shard tuning | "(SHIPPED)" |
| Phase 3.2 | Per-shard content packs | "(SHIPPED)" |

The note also records a transport decision (sec. 3): Option B
(WebSocket server + nginx L7) for the edge, with Option A (ENet + L4)
retained for native clients.

Sec. 5 lists explicit out-of-scope items: real HA Postgres/Redis, and the
dormant Julia `multi-iso` orchestrator.

## 2. File map (phase -> files that exist)

Every phase below has an implementation I could locate and read.

### Phase 0 -- Shard identity + shared state

| Concern | File (read) | Evidence |
|---------|-------------|----------|
| Env -> identity -> `configure()` | `game/core/services/shard_manager.gd` | `_apply_env_config()` reads `SHARD_ID`, `SHARD_NAME`, `IS_PRIMARY`, `WORLD_SIZE_KM2`, `MAX_PLAYERS_PER_SHARD` (lines 71-93) |
| Register with coordinator | `game/core/services/shard_manager.gd` | `_register_with_coordinator()` -> `announce_self_to_mesh()` (lines 106-123) |
| Registry persistence | `game/core/services/coordinator_service.gd` | `register_shard` / `_persist_state` / `_load_state` (lines 159-207) |
| The `"default"` store fix | `game/adapters/backend_factory.gd` | `boot_defaults()` registers `"default"` explicitly (comment at 208-213: `reg.register_persistence("default", ...)`) |
| Per-shard parameter store (autoload) | `game/core/services/shard_parameters.gd` | `get_param` (83), `set_param` (110), `param_applied` signal (20) |
| Compose shared state + identity | `docker-compose.yml` | lines 44-74 set `EDGE_TRANSPORT`, `STORAGE_BACKEND`/`CACHE_BACKEND`, bridge URLs, `SHARD_ID`/`SHARD_NAME` |
| Receipt | `game/tests/test_shard_mesh_identity.gd` | exists |

### Phase 1 -- Cross-shard bus

| Concern | File (read) | Evidence |
|---------|-------------|----------|
| Bus contract | `game/core/mesh/shard_bus.gd` | `class_name ShardBus`; `subscribe`/`publish`/`poll`, no-echo fan-out, `MAX_DRAIN` |
| Plugin board | `game/core/mesh/shard_bus_registry.gd` | `class_name ShardBusRegistry`; `register(bus, make_default)` replaces by id; seeds `MemoryShardBus` in `_init` |
| Default transport | `game/core/mesh/memory_shard_bus.gd` | `class_name`-less `extends shard_bus.gd`; shared `MemoryCacheStore` |
| Cross-process transport | `game/core/mesh/redis_shard_bus.gd` | `extends shard_bus.gd`; opens a `RedisStore` from `REDIS_BRIDGE_URL` |
| Coordinator wiring | `game/core/services/coordinator_service.gd` | `bus_registry()` (93), `_bind_bus()` (111, `SHARD_BUS_BACKEND` default follows `CACHE_BACKEND`), `BUS_TOPIC` (40), `_publish_event` (415), `_drain_bus` (424), `get_pending_events` (439) |
| Cache primitives the bus uses | `game/adapters/cache/{cache_store,memory_cache_store,redis_store}.gd` | `sadd`/`srem`/`smembers`/`rpush`/`lpop` all present |
| Receipt | `game/tests/test_shard_bus.gd` | exists |

### Phase 2 -- Edge transport

| Concern | File (read) | Evidence |
|---------|-------------|----------|
| Transport selection | `game/core/autoload/network_manager.gd` | `EDGE_TRANSPORT` consts (28-30), `_resolve_edge_transport()` (131; enet default, `ws`/`wss` aliases), `_make_server_peer()` (145; `ENetMultiplayerPeer` / `WebSocketMultiplayerPeer`) |
| nginx `ip_hash` + upstream expansion | `srv/docker/entrypoint.sh` | `_setup_nginx()` (46-73) expands a comma/space `GODOT_UPSTREAM` into `server` lines |
| Compose passthrough | `docker-compose.yml` | `EDGE_TRANSPORT` (44-47), `GODOT_UPSTREAM` on the edge service |
| Receipt | `game/tests/test_edge_transport.gd` | exists |

### Phase 3 -- Topology

| Concern | File (read) | Evidence |
|---------|-------------|----------|
| The role law | `game/core/mesh/mesh_role.gd` | `class_name MeshRole`; `resolve()`, `self_id()`, `shard_id()`, `autoshard_enabled()` |
| Mesh topic + cross-process registry | `game/core/services/coordinator_service.gd` | `MESH_TOPIC` (46), `announce_self_to_mesh` (222), `announce_unregister_to_mesh` (236), `_ingest_mesh_mail` (253), `_apply_remote_registration` (276), ingest-on-read in `get_all_shard_ids`/`get_all_shards`/`get_shard_info` (316-327) |
| Coordinator never registers as a shard | `game/core/services/shard_manager.gd` | `_register_with_coordinator()` early-returns for `MeshRole.is_coordinator()` (107) |
| Topology | `docker-compose.yml` | `coordinator:` (202), `shard:` (234), both `profiles: [mesh]` |
| Coordinator boot mode | `srv/docker/entrypoint.sh` | `START_MODE=coordinator` branch (264) |
| Receipt | `game/tests/test_shard_mesh_topology.gd` | exists |

### Phase 3.1 -- Edge proxy + per-shard tuning

| Concern | File (read) | Evidence |
|---------|-------------|----------|
| Read accessor | `game/core/services/shard_parameters.gd` | `get_param(shard_id, param_name)` (83) |
| Tuning definitions | `game/data/roots/world/parameters/level_cap_override.tres`, `.../xp_ratio_override.tres` | both `critical = true`; int / float |
| Curve integration | `game/core/progression/level_curve.gd` | `set_shard_tuning` (68), `clear_shard_tuning` (73), `has_shard_tuning` (78), `max_level()` precedence (87) |
| Resolver | `game/core/progression/shard_tuning.gd` | `class_name ShardTuning`; `apply(shard_id, sp)`, `tuning_param_names()` |
| Boot + live re-apply | `game/core/services/shard_manager.gd` | `_apply_shard_tuning` (42), `_connect_tuning_listener` (52), `_on_tuning_param_applied` (59) |
| Operator surface | `game/core/services/chat_service.gd` | `/shardparam` dispatch (525) + `_cmd_shardparam` (872) |
| Edge container | `docker-compose.yml`, `srv/docker/entrypoint.sh` | `edge:` (273), `START_MODE=edge` branch (282) |
| Receipts | `game/tests/test_shard_tuning.gd`, `game/tests/test_shard_tuning_admin.gd` | exist |

### Phase 3.2 -- Per-shard content packs

| Concern | File (read) | Evidence |
|---------|-------------|----------|
| Pack schema | `game/core/schemas/content_pack_data.gd` | `class_name ContentPackData`; `enemy_ids`/`quest_ids`, `missing_refs(ds)` |
| Resolver + gates | `game/core/mesh/content_packs.gd` | `class_name ContentPacks`; `load_packs`, `disabled_set`, `enemy_enabled`/`quest_enabled`, `local_*_enabled`, `board()` |
| Disable parameter | `game/data/roots/world/parameters/disabled_content_packs.tres` | string, `critical = true`, default `""` |
| Authored pack | `game/data/content_packs/pack_tide_season.tres` | `pack_tide_season`; 3 enemies + 4 quests |
| Gate -- quests | `game/core/services/quest_service.gd` | `preload` (10); `local_quest_enabled` at 364, 413, 456 |
| Gate -- spawns | `game/core/services/spawn_service.gd` | `preload` (22); `local_enemy_enabled` at 544, 718, 1015 |
| Gate -- horde mobs | `game/core/services/horde_event_service.gd` | `preload` (35); `local_enemy_enabled` at 442 |
| Operator surfaces | `game/core/services/chat_service.gd` | `/contentpack` (527) and `/mesh` (530) |
| Receipts | `game/tests/test_content_packs.gd`, `game/tests/test_mesh_command.gd` | exist |

## 3. Phases with no implementation found

None. All six phases (0, 1, 2, 3, 3.1, 3.2) have a locatable implementation
plus at least one receipt file. This audit ran only its targeted gates; the
parent runs the full suite, so "implemented" means the symbols and files exist
as read, not that the tests pass.

## 4. Out-of-scope items (no implementation, as designed)

- **HA Postgres/Redis** -- a deployment concern; no code expected.
- **The dormant Julia `multi-iso` orchestrator** -- `game/core/services/multi_iso_service.gd`
  exists (header: "Bridge to the Julia multi-iso orchestrator"), but it is
  **not** in `project.godot`'s `[autoload]` section, so it is dormant exactly
  as the note's sec. 2 table says ("`MultiIsoService` DORMANT"). The note
  defers it to `prd-multiworld.md` / `world-building-arch.md` sec. 11.2.

## 5. Confidence and open questions

- **High confidence** on the file map: each row cites a symbol or line I read.
- **Not verified:** I did not execute any receipt, so the note's pass counts
  (e.g. "17 legs", "38 legs") are taken as written, not reproduced.
- **Minor naming note (not a defect):** several mesh files carry a
  `class_name` (`MeshRole`, `ShardBus`, `ShardBusRegistry`, `ContentPacks`,
  `ShardTuning`, `ContentPackData`) and none of those names collide with an
  autoload, so they do not trip the autoload/`class_name` shadow rule.
  `ShardManager`, `CoordinatorService`, and `ShardParameters` are autoloads
  and do **not** declare `class_name`.
- **Unclear / worth a follow-up:** the note's Phase 0 table says every
  process was `shard_1`/"Alpha"; I confirmed `MeshRole.shard_id()` still
  returns `shard_1` when no env is set, which is the intended dev default.
  I did not trace whether `ShardManager._load_shards`/`_persist_shard` still
  write through the `"default"` `DictStore` name or the new registration; the
  fix in `backend_factory.gd` registers `"default"`, so the store resolves,
  but the exact read/write path in `shard_manager.gd` was not read line by
  line.
