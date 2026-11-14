# Initial World / Network / Sync Audit

> **ARCHIVED 2026-11-14.** Point-in-time pre-planning snapshot (authored
> 2026-09-05, last revised 2026-09-30). Kept for its audit method and early
> census, NOT as current state. For current code state read `AGENTS.md` and
> the receipts it cites; for the terrain path read `labs/prd-clipmap.md`.

> **Status:** Pre-planning reference. Captures the current state of
> the codebase before any planning-doc work begins. This is the
> "where we are today" snapshot. The actual design discussion
> happens in `/labs/world-building.md`.
>
> **Date:** 2026-09-05
>
> **Relocation note (2026-09-30):** the Julia orchestrator files
> cited below (`game/core/frame/srv/orchestrator.jl`, `server.jl`,
> `Project.toml`) now live at `srv/julia-bridge/` -- they are an
> HTTP bridge sidecar (sibling of pg-bridge/redis-bridge), not
> Godot frame primitives. Paths below are historical.
> **Phase:** Pre-vertical-slice. Codebase was rapid-filled with
> ideas and design angles; no consensus-pass has been run.

---

## 1. Project shape (top-down)

The repo splits into two parallel tracks:

- **`game/`** — the Godot 4.7.2 project. Shippable side. 30+
  autoloaded services, schema-based `.tres` content, services +
  components + EventHub scaffolding.
- **`labs/`** — root-level experiments that must not taint the
  Godot build. The home of the frame primitives (now consolidated
  into `game/core/frame/`), the Julia orchestrator,
  the Python prototype, Jolt playground, polyglot FFI sketches.

The four-layer architecture the PRD converges on:

```
Godot client  →  Multi-iso orchestrator  →  State tree (content-hash)  →  Postgres + cache
```

Each layer has stubs or partial impls. None is fully wired.

---

## 2. The world today — what is actually there

### 2.1 Zones (mostly real, partly stub)

- `ZoneData` schema (`game/core/schemas/zone_data.gd`) — `.tres`
  resource. Carries `id`, `display_name`, `pvp_mode`, level
  range, `allowed_factions` / `blocked_species`, `respawn_*`,
  `bounds: AABB`, `zone_center`, `zone_radius`, `ambient_*`,
  `has_weather` + `weather_type`, `spawn_points: Array[Vector3]`,
  `bind_point`, `npcs: Array[String]`, `loot_multiplier`,
  `xp_multiplier`, `is_instanced`, `instance_capacity`.
- 4 hand-authored zones in `data/zones/`:
  - `zone_starter_plains`
  - `zone_village_center`
  - `zone_forest_meadow`
  - `zone_dungeon_forest_depths`
- `ZoneManager` (548 lines,
  `game/core/services/zone_manager.gd`):
  - Loads zones via `DataService.get_all_zones()`.
  - Auto-registers zone **neighbors** by proximity (≤1500 units
    between `zone_center`).
  - Tracks `_players_in_zone`, `_enemies_in_zone`,
    `_entity_zones` per entity.
  - **Signals exist but no producer fires them** for
    `entity_entered_zone` — there's no per-frame AABB check
    on player position vs zone bounds. The detection loop is
    not implemented.
  - Supports OPEN_WORLD / INSTANCED / SEAMLESS_INST zone types
    with `_instances`, `_next_instance_id`, instance join/leave
    signals.
  - Seamless transitions: `seamless_transition_started/
    completed/cancelled` signals exist but the trigger logic
    is missing.

### 2.2 World service

- `WorldService` (`game/core/services/world_service.gd`):
  - Holds `world_time_minutes`, `day_duration_minutes`,
    `time_multiplier`, `_current_time_of_day`.
  - Tracks gateways (`GatewayRecord` inner class with `from/
    to_zone_id`, position, radius, level/faction/quest
    requirements, `is_locked`, `activation_radius`,
    `can_use()`).
  - World events: `_active_events`, `_event_templates`. Signals
    exist (`event_started`, `event_ended`) but the array
    stays empty.
  - **Day/night cycle, gateway activation, and world events
    have no producer logic.**
  - **Procedural world stub:**
    `generate_world_from_seed(seed_value: int)` — sets
    `world_seed`, calls `seed(seed_value)`, logs. No actual
    generation. `find_zone_path()` is a 2-hop direct path
    (no A*).
- 3 gateways in `data/gateways/`:
  - `ankh_village_shrine`
  - `dungeon_forest_depths_entrance`
  - `waypoint_village_center`

### 2.3 Spawn system (the most fleshed out)

- `SpawnService` (`game/core/services/spawn_service.gd`):
  - `SpawnPoint` inner class with id, zone_id, position,
    spawn_radius, enemy_template_id, species_id, respawn_time,
    min/max enemies, current_count, spawn_type
    (NORMAL/ELITE/BOSS/WORLD_BOSS), `spawn_multiplier`,
    `is_active`, `should_spawn()`, `get_spawn_position()`.
  - Tracks spawn points, spawn timers, spawned entities, world
    bosses (Dict).
  - Uses spawn metadata (`SpawnMetadata` class in
    `game/core/events/spawn_metadata.gd`) with `SpawnType`
    enum and factory methods (`enemy`, `world_boss`, etc.).
  - This is the only world-adjacent system with real
    per-tick behavior.

### 2.4 The actual playable scene

- `game/scenes/world_playable.tscn`:
  - One `BoxShape3D` 200×0.5×200 green floor.
  - Player + 2 slimes + wolf + bandit placed at hard-coded
    Vector3 coordinates.
  - No terrain, no skybox, no procedurally generated mesh.
  - The "200km² world" is a 200m² green rectangle.

### 2.5 Procedural generation

- Pure stub.
- `WorldService.world_seed` field exists.
- `WorldService.generate_world_from_seed()` body is empty.
- No heightmap. No biome map. No chunking. No noise. No
  dungeon-room generator. No resource-node distribution
  algorithm.
- The `scale-200km2.md` doc sketches "procedural
  assimilation" as a future thing — not on disk.

---

## 3. The server / sync layer today

### 3.1 Network manager (stubs at the seams)

- `NetworkManager` (`game/core/autoload/network_manager.gd`):
  - ENet, port 10555, MAX_PLAYERS=100, tick_rate=20Hz.
  - `connection_state` enum (DISCONNECTED / CONNECTING /
    CONNECTED / SERVER).
  - `start_server()`, `_auto_start_server()` (driven by
    `START_MODE=prod|headless|server` env var).
  - `peer_connected.connect(_on_server_peer_connected)` —
    runs AppFirewall `can_connect(ip)` check.
  - **Tick loop body is empty:**
    `_process_server_ticks() -> pass`,
    `_process_world_update() -> pass`,
    `_broadcast_world_state() -> # stub`.
  - **Client `_receive_world_state(state: Dictionary)` is
    also a stub** (`# Client receives world state; pass`).
  - Signals `connected_to_server`, `connection_failed`,
    `peer_connected/disconnected`, `server_started/stopped`.

### 3.2 Server manager (real config, no execution)

- `ServerManager` (`game/core/services/server_manager.gd`):
  - `ServerState` enum (ONLINE / RESTARTING / MAINTENANCE /
    EMERGENCY).
  - Restart scheduling, maintenance messages, kick_player
    with the typed-Kind notification pipeline.
  - Real logic. Drives broadcast warnings to players.
    Not really "server execution" though — it's a
    meta-controller.

### 3.3 Shard manager (config only)

- `ShardManager` (`game/core/services/shard_manager.gd`):
  - Holds `shard_id`, `shard_name`, `is_primary`,
    `world_name`, `world_size_km2: 200.0`,
    `max_players_per_shard: 5000`.
  - `configure(config: Dictionary)` exists.
  - `start_server()` just sets status to `"online"` and
    emits the signal. No socket, no spawn of
    NetworkManager, nothing else.
  - Cross-shard arrays (`_connected_shards`, `_shard_info`)
    are empty. Meshing is a future thing.

### 3.4 Anti-cheat / security layer (real)

- `AppFirewall` (`game/core/utils/app_firewall.gd`),
  `SecurityMonitor`, `SecurityService`, `QoSService` —
  real, working. Connected to the typed-Kind notification
  pipeline. The firewall blocks IPs at connect-time, the
  monitor watches for exploits, security reports them,
  QoS rate-limits per-player / per-service. Not stubs.
- This is the most production-shaped subsystem in the
  game today.

---

## 4. The state tree (content-hash) is now implemented

These were the **FSM**, not the content-hash state tree.

### 4.1 The state dir is misleading

- `game/core/state/` contains:
  - `state.gd` — base FSM state (enter/exit/update/
    physics_update). Helper `transition_to()`.
  - `state_machine.gd` — generic FSM (idle/run/jump/fall).
- These are the **FSM**, not the content-hash state tree.
  Naming collision is going to bite us when we start
  implementing the real state tree.

### 4.2 The real state tree is referenced but missing

### 4.2 The content-hash state tree is implemented as T3

- See `labs/world-building-arch.md` for the live frame architecture
  (replaces archived docs in `labs/archive/docs/architecture/`).
- `labs/prd.md` §10.6
- `labs/README.md`
- **Implemented.** `game/core/frame/kv/t3.gd` provides the
  T3 state tree (content-hash). See `tests/test_t3.gd`. The
  Postgres `state_snapshots` schema and
  `diff()` / `apply_diff()` / `re_root()` are frame primitives
  to be extracted to the snapshot-store module in `frame/db/`.
- The conceptual contract from the docs:
  - Every node has a `hash` (SHA-256 of serialized value).
  - `diff(old_root, new_root) -> List[(path, new_hash,
- The conceptual contract from the docs:
  - Every node has a `hash` (SHA-256 of serialized value).
  - `diff(old_root, new_root) -> List[(path, new_hash,
    value)]`.
  - `apply_diff(root, diff) -> new_root`.
  - Server tick = re-rooting the tree with new state.
  - Client sync = `apply_diff(my_root, server_diff) ->
    new_root`.

---

## 5. The frame services layer (consolidated)

### 5.1 Julia side (real)

- `game/core/frame/srv/orchestrator.jl`:
  - NSC-9 encoding/decoding (`9-AAA-BBB-CCCCCC`).
  - Axis constants: `spatial_axis(v)`, `faction_axis(f)`,
    `social_axis(s)`, `game_axis(g)` plus temporal
    sub-axes `TEMPORAL_YEAR/SEASON/MONTH/HOUR` (200/201/
    202/203).
  - Set-intersection per query. `register!`, `unregister!`,
    `intersect`, etc.
- `game/core/frame/srv/server.jl`:
  - HTTP API: `/register` (POST), `/spatial/:v`,
    `/faction/:f`, `/social/:s`, `/intersect` (POST),
    `/stats`, `/health`.
- Python prototype `iso_math.py` validated perf: 100K
  entities × 3-axis intersection ≈ 40µs.

### 5.2 GDScript bridge (thin)

The multi-iso orchestrator is now the `frame` layer at
`game/core/frame/srv/`. GDScript services interact through
`FrameService` (autoload, `game/core/autoload/frame_service.gd`)
which wraps `frame_client.gd` (local RulesEngine fallback) or
forwards to the HTTP endpoint.

- `FrameService` (`game/core/services/frame_service.gd`):
  - `@export var julia_server_url: String =
    "http://julia:8080"` and `local_server_url`.
  - `register_entity(entity_id, spatial_vertex,
    faction_id, social_group, game_class, birth_year)`.
  - `query_spatial(vertex)`, `query_faction(faction_id)`,
    `query_social(group)`.
  - `intersect(axes, vertex_lists)` — multi-axis query.
  - HTTPRequest + request_id queue pattern.
  - **No projection logic on the GDScript side.** The
    Godot game doesn't compute vertex coords; the caller
    has to pass them in. Nothing in the game currently
    passes them in.
  - **No materialized intersection cache (LRU).**
  - **No LOD pyramid.**
  - **No Markov predictor.**

### 5.3 Axes reserved (from the docs)

- `001-099` spatial
- `100-199` factional
- `200-299` temporal (year, season, month, hour, … —
  sub-axes, sequence holds the value)
- `300-399` social
- `400-499` game-specific
- `500-999` free

---

## 6. Autoload graph (the cascade)

From `game/project.godot`:

```
RegisterTypes, GameLog, GameConfig,
QoSService, GameManager, NetworkManager,
PlayerManager, InputManager,
SecurityMonitor, WebhookManager
```

Plus domain services registered at runtime via singletons
inside the scene. The autoload-race problem is discussed in `labs/world-building-arch.md`
and `AGENTS.md` §Autoloads and class_name. The pattern of resolving
cross-service references in `_ready()` via `call_deferred()` has been
applied across services. The 22 cascade failures are mostly resolved
(remaining: `QoSPingService` → `DebugOverlay` ordering).

---

## 7. What is production-shaped vs. design-shaped

| Subsystem | Status | On disk |
|---|---|---|
| Anti-cheat / firewall / QoS | Production-shaped | ✅ |
| Notification → toast pipeline | Production-shaped | ✅ |
| Loot tables | Production-shaped | ✅ |
| SpawnService | Real, per-tick | ✅ |
| EventHub / EntityService | Real, simple | ✅ |
| ZoneManager | Half-real (data + neighbors, no detection) | ✅ |
| NetworkManager | Skeleton + ENet | ✅ |
| ServerManager | Real | ✅ |
| ShardManager | Config only | ✅ |
| WorldService | Stub | ✅ |
| Map / terrain / heightmap | None | ❌ |
| Procedural generation | None | ❌ |
| State tree (content-hash) | T3 implemented (`frame/kv/t3.gd`) | ✅ |
| Materialized intersection cache | `frame/srv/scope_engine.gd` (axis query) | ⚠️ |
| LOD pyramid | Planned (see `world-building-lod.md`) | ❌ |
| Markov predictor | Planned (see `world-building-lod.md`) | ❌ |
| Sync protocol (diff RPC) | `frame/kv/t3.gd` (conceptual) | ⚠️ |
| Client prediction | None | ❌ |
| Interest management / AOI | `frame/srv/scope_engine.gd` (LOD scoping) | ⚠️ |
| Snapshot store / Postgres | Planned for `frame/db/` | ❌ |

---

## 8. Open seams (where planning has to commit)

These are the gaps between what the docs promise and what
the code does. They are the design questions the planning
doc (`world-building.md`) needs to resolve:

1. **Coordinate system & map shape.** Planar (square/circle)
   vs spherical (planet). Both?
2. **World unit / chunk.** Meters? Quasicrystal cells?
   icosahedral vertices? 12-vertex icosahedron as the
   spatial axis?
3. **Seed scope.** Per-server-shard, per-player-instance,
   per-zone, per-chunk?
4. **What gets generated vs hand-authored.** Zones,
   terrain, dungeons, loot, NPCs, quests, world events,
   resource nodes?
5. **When does generation run.** Seed-time (once) vs
   LOD-promotion-time (on demand) vs per-tick?
6. **Where the content-hash state tree lives.** Single
   tree per process? Per shard? Per player region?
7. **Sync diff encoding.** JSON? `var_to_bytes`?
   Custom binary? Per-axis diffs?
8. **Multi-iso axes for THIS game.** Which ones do we
   actually project to and use? Spatial is obvious;
   what else? Factional? Social? Temporal at what
   granularity?
9. **Instance scoping.** Per-player, per-party,
   per-guild, per-faction, per-zone — how does the
   seed scope interact with instance scope?
10. **Godot browser deployment.** web export (HTML5/
    wasm). What server-side capabilities (no ENet raw
    sockets — WebSocket transport instead).
11. **Authority boundaries.** What's authoritative on
    server vs client? Where does prediction live?

---

## 9. Key files (read these before planning)

| File | Why |
|---|---|
| `labs/prd.md` §10 | Technical architecture commitment |
| `labs/world-building-arch.md` | Live frame architecture (T3, scope, rules, geometry) |
| `labs/world-building-risks.md` | The operating companion: risks, decisions, numbers, glossary |
| `labs/world-building-research.md` | The research companion: §21 experimental angles, deep dives |
| `labs/world-building-tick.md` | The tick model discussion: 6 phases, flywheel, postmortem |
| `labs/README.md` | `/labs/` convention |
| `game/core/frame/srv/rules_engine.gd` | Where rules engine lives |
| `game/core/frame/srv/scope.gd` | Scope hierarchy in code |
| `game/core/frame/kv/t3.gd` | State tree (T3 content-hash) |
| `game/core/frame/math/` | NSC-9, icosahedral |
| `game/core/services/world_service.gd` | World state, gateways, day/night |
| `game/core/services/spawn_service.gd` | Spawning (the most fleshed out) |
| `game/core/utils/frame_client.gd` | GDScript → frame bridge (local fallback) |
| `game/core/schemas/zone_data.gd` | Zone schema |
| `game/core/events/spawn_metadata.gd` | Spawn metadata + factory |
| `game/core/state/state.gd` + `state_machine.gd` | FSM (NOT the state tree) |
| `game/core/frame/srv/orchestrator.jl` | The Julia orchestrator |
| `game/core/frame/srv/server.jl` | The Julia HTTP API |
| `game/core/frame/prototype/FINDINGS.md` | Performance numbers |

---

## 10. What this audit is NOT

This document does not propose solutions. It is a
snapshot of:

- What code exists.
- What code is stubbed.
- What code is described in docs but not on disk.
- Where the design seams are.

The actual design choices — coordinate systems, seed
scopes, generation timing, sync protocols, runtime
tier breakdown, authority boundaries, etc. — live in
`/labs/world-building.md` (the plan),
`/labs/world-building-research.md` (research companion
for the §21 experimental angles),
`/labs/world-building-risks.md` (the operating
companion: risks, decisions, numbers, glossary), and
`/labs/world-building-tick.md` (the tick model
discussion: 6 phases, flywheel, postmortem).