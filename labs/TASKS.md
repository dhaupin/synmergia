# Session Scratch Pad

Persistent memory across resets for Synmergia development.

## Orchestration (Kilo Code Towns)

### Branching model
- `main` — shared integration branch. Always pull before starting.
- `labs/*` — experimental / docs work. Push here first.
- Feature branches: `kilo/<topic>` or `town/<topic>`. One branch per town.
- Never rebase `main` while another town is working. Use merge commits.

### Before you start a task
1. Pull latest `main` — check for parallel work.
2. Read the bottom of this file for recent completions.
3. Check `prd-db.md` section 2 + section 8 for service ownership.
4. Mark your task `in_progress` with your town name + timestamp.
5. If the task touches `game/` AND `labs/`, coordinate with both towns.

### Task ownership tags
- `[town:core]` — core services, autoloads, entities, login/seed flow
- `[town:frame]` — T3 substrate, seed chain, state tree, scope engine, geometry
- `[town:adapter]` — persistence/cache/memory adapters
- `[town:bridge]` — pg-bridge, redis-bridge, docker, backup scripts
- `[town:web]` — HUD, panels, portal, admin dashboard, WASM client
- `[town:docs]` — TASKS.md, world-building PRDs, arch specs
- `[town:test]` — lint, syntax, smoke, unit & integration tests

---

## PRD Roadmap & Implementation Status

### World Building PRD — Phase 1: KV Substrate & Canonical Trees (100% COMPLETE)
- [x] **T3 Substrate** (`labs/multi-iso/kv/t3.gd`) — Tiered, content-hashed Merkle-Patricia trie [town:frame]
- [x] **SeedSchema Resource** (`game/data/roots/seed_schema.gd`) — Two-orthogonal-axes canonical seed contract [town:core]
- [x] **StateSchema Resource** (`game/data/roots/state_schema.gd`) — Runtime state tree schema [town:core]
- [x] **Seed Tree & Recursive Derivation** (`labs/multi-iso/kv/seed_chain.gd`) — `derive_seed` HMAC chain [town:frame]
- [x] **State Tree** (`labs/multi-iso/kv/state_tree.gd`) — Content-hash state tree with diffing [town:frame]
- [x] **SeedReceipt Resource & Pipeline** (`game/core/schemas/seed_receipt.gd`, `login_service.gd`) — Signed receipt derivation [town:core]
- [x] **FrameService & Frame Authority** (`game/core/services/frame_service.gd`, `test_frame_authority.gd`) — Frame authority isolation [town:core]
- [x] **Critical Parameters & ShardParameters** (`game/core/services/shard_parameters.gd`, `shard_parameter_definition.gd`) — Critical parameter immediate vs 5-min coalesce writes [town:core]
- [x] **LRU Cache & Snapshot Store** (`labs/multi-iso/kv/lru_cache.gd`, `labs/multi-iso/db/snapshot_store.gd`) — In-memory caching and snapshotting [town:frame]
- [x] **Spatial Geometry (NSC-9 & Icosahedral)** (`labs/multi-iso/math/nsc9.gd`, `icosahedral.gd`) — Discrete spatial coordinate mapping [town:frame]
- [x] **Scope Engine** (`labs/multi-iso/srv/scope.gd`, `scope_hierarchy.gd`, `scope_engine.gd`) — Multi-brain hierarchical scope stack [town:frame]
- [x] **Manifest Backup & DR (D031)** (`srv/backup/manifest.sh`, `backup.sh`, `upload.sh`, `cold_tier.sh`, `purge.sh`, `restore.sh`, `README.md`) — 3-tier backup pipeline with SHA-256 verification and cron schedules [town:bridge]
- [x] **Open Seed TTL & Registry (D032)** (`game/core/services/open_seed_registry.gd`, `game/core/schemas/instance_type_definition.gd`, `login_service.gd`, `dungeon.tres`, `arena.tres`, `raid.tres`) — Instance reconnect TTL tracking and state finalization [town:core]

### Storage & Persistence Layer (PRD-DB) (100% COMPLETE)
- [x] Storage Adapters (`DictStore`, `CacheWrapper`, `MemoryWrapper`, `AdapterRegistry`, `BackendFactory`) [town:adapter]
- [x] 35+ game services migrated to pluggable adapter persistence [town:core]
- [x] Sidecar bridges (`srv/pg-bridge`, `srv/redis-bridge`) with test coverage [town:bridge]

### Web Client & Admin Portal (PRD-WEB) (100% COMPLETE)
- [x] Web Portal P0: COOP/COEP isolation headers, /web static serve plugin, packaging script [town:web]
- [x] Web Portal P1: Godot static data bridge, Godot WASM client embed, multi-tab Admin Dashboard [town:web]
- [x] CI/Docker workflow audit & quota-safe GitHub action [town:test]

---

## In Progress & Next Phase Milestones

### World Building PRD — Phase 2: Rules Engine & World Integration
- [x] **Rules Engine** (`labs/multi-iso/srv/rules_engine.gd`, `rules_schema.gd`) — Gating rules and multi-scope rule resolution [town:frame]
- [x] **Definition Tree** (`labs/multi-iso/kv/definition_tree.gd`, `definition_schema.gd`) — Static data catalog in T3 [town:frame]
- [x] **Consolidate 4 Core Services into Rules Engine**: QoS, Security, AppFirewall, AutoResponse [town:core]
- [x] **Frame Extract** (`srv/frame/`) — Frame HTTP bridge container with FrameClient GDScript [town:bridge]

### World Building PRD — Phase 3 & 4
- [ ] **Account Rollup (D028)** (`game/core/services/account_rollup.gd`) — Account-level state aggregation across characters [town:core]
- [ ] **Vant Fragmenter** (`labs/multi-iso/geometry/fragmenter.gd`) — Procedural cell decomposition [town:frame]

---

## Recently Completed (2026-09-15)

- [x] **Manifest Backup Pipeline (D031)**: Created `srv/backup/manifest.sh`, `backup.sh`, `upload.sh`, `cold_tier.sh`, `purge.sh`, `restore.sh`, `README.md` (with limitations documentation per US-007), and verified full test suite in `test_backup.sh` [town:bridge]
- [x] **Open Seed TTL & Registry (D032)**: Created `OpenSeedRegistry` autoload service, `InstanceTypeDefinition` schema, instance type `.tres` records (`dungeon`, `arena`, `raid`), integrated 5-minute reconnect TTL in `LoginService.build_seed_receipt`, and passed 8/8 unit tests in `test_open_seed_ttl.gd` [town:core]
- [x] **World Building Arch Update**: Marked D031 and D032 as DONE in `labs/world-building-arch.md` §13 component map [town:docs]
- [x] **FrameService Fix**: Fixed syntax typo `_func` -> `func` in `FrameEnv._init` [town:core]
- [x] **QC Gap Analysis & Syntax Verification**: Verified 0 parse/syntax errors across all `.gd` files in `game/` and `labs/` [town:test]

## Recently Completed (2026-09-15) — Phase 2

- [x] **RulesEngine Consolidation**: Refactored QoSService (`matchmaking_qos.gd`), SecurityService (`security_service.gd`), AppFirewall (`app_firewall.gd`), AutoResponseService (`auto_response_service.gd`) to use RulesEngine for all decision logic [town:core]
- [x] **Frame Extract to Container**: Created `srv/frame/` with Dockerfile, docker-compose.yml, FastAPI bridge server (`frame_server.py`), GDScript FrameClient (`game/core/utils/frame_client.gd`) with circuit breaker and local fallback [town:bridge]
- [x] **Docker Compose Integration**: Added `frame` service to main `docker-compose.yml` with health checks, dependencies on postgres/redis [town:bridge]
