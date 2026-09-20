# Session Scratch Pad

Persistent memory across resets for Synmergia development.

## Orchestration (Kilo Code Towns)

### Branching model
- `main`  -  shared integration branch. Always pull before starting.
- `labs/*`  -  experimental / docs work. Push here first.
- Feature branches: `kilo/<topic>` or `town/<topic>`. One branch per town.
- Never rebase `main` while another town is working. Use merge commits.

### Before you start a task
1. Pull latest `main`  -  check for parallel work.
2. Read the bottom of this file for recent completions.
3. Check `prd-db.md` section 2 + section 8 for service ownership.
4. Mark your task `in_progress` with your town name + timestamp.
5. If the task touches `game/` AND `labs/`, coordinate with both towns.

### Task ownership tags
- `[town:core]`  -  core services, autoloads, entities, login/seed flow
- `[town:frame]`  -  T3 substrate, seed chain, state tree, scope engine, geometry
- `[town:adapter]`  -  persistence/cache/memory adapters
- `[town:bridge]`  -  pg-bridge, redis-bridge, docker, backup scripts
- `[town:web]`  -  HUD, panels, portal, admin dashboard, WASM client
- `[town:docs]`  -  TASKS.md, world-building PRDs, arch specs
- `[town:test]`  -  lint, syntax, smoke, unit & integration tests

---

## PRD Roadmap & Implementation Status

### World Building PRD  -  Phase 1: KV Substrate & Canonical Trees (100% COMPLETE)
- [x] **T3 Substrate** (`game/core/frame/kv/t3.gd`)  -  Tiered, content-hashed Merkle-Patricia trie [town:frame]
- [x] **SeedSchema Resource** (`game/data/roots/seed_schema.gd`)  -  Two-orthogonal-axes canonical seed contract [town:core]
- [x] **StateSchema Resource** (`game/data/roots/state_schema.gd`)  -  Runtime state tree schema [town:core]
- [x] **Seed Tree & Recursive Derivation** (`game/core/frame/kv/seed_chain.gd`)  -  `derive_seed` HMAC chain [town:frame]
- [x] **State Tree** (`game/core/frame/kv/state_tree.gd`)  -  Content-hash state tree with diffing [town:frame]
- [x] **SeedReceipt Resource & Pipeline** (`game/core/schemas/seed_receipt.gd`, `login_service.gd`)  -  Signed receipt derivation [town:core]
- [x] **FrameService & Frame Authority** (`game/core/services/frame_service.gd`, `test_frame_authority.gd`)  -  Frame authority isolation [town:core]
- [x] **Critical Parameters & ShardParameters** (`game/core/services/shard_parameters.gd`, `shard_parameter_definition.gd`)  -  Critical parameter immediate vs 5-min coalesce writes [town:core]
- [x] **LRU Cache & Snapshot Store** (`game/core/frame/kv/lru_cache.gd`, `game/core/frame/db/snapshot_store.gd`)  -  In-memory caching and snapshotting [town:frame]
- [x] **Spatial Geometry (NSC-9 & Icosahedral)** (`game/core/frame/math/nsc9.gd`, `icosahedral.gd`)  -  Discrete spatial coordinate mapping [town:frame]
- [x] **Scope Engine** (`game/core/frame/srv/scope.gd`, `scope_hierarchy.gd`, `scope_engine.gd`)  -  Multi-brain hierarchical scope stack [town:frame]
- [x] **Manifest Backup & DR (D031)** (`srv/backup/manifest.sh`, `backup.sh`, `upload.sh`, `cold_tier.sh`, `purge.sh`, `restore.sh`, `README.md`)  -  3-tier backup pipeline with SHA-256 verification and cron schedules [town:bridge]
- [x] **Open Seed TTL & Registry (D032)** (`game/core/services/open_seed_registry.gd`, `game/core/schemas/instance_type_definition.gd`, `login_service.gd`, `dungeon.tres`, `arena.tres`, `raid.tres`)  -  Instance reconnect TTL tracking and state finalization [town:core]

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

### World Building PRD  -  Phase 2: Rules Engine & World Integration
- [x] **Rules Engine** (`game/core/frame/srv/rules_engine.gd`, `rules_schema.gd`)  -  Gating rules and multi-scope rule resolution [town:frame]
- [x] **Definition Tree** (`game/core/frame/kv/definition_tree.gd`, `definition_schema.gd`)  -  Static data catalog in T3 [town:frame]
- [x] **Consolidate 4 Core Services into Rules Engine**: QoS, Security, AppFirewall, AutoResponse [town:core]
- [x] **Frame Extract** (`srv/frame/`)  -  Frame HTTP bridge container with FrameClient GDScript [town:bridge]### World Building PRD - Phase 3 & 4
- [x] **Account Rollup (D028)** (`game/core/services/account_rollup.gd`)  -  Account-level state aggregation across characters [town:core]  -  verified 2026-09-20: implemented and wired into LoginService (rebuild_rollup_static) and AccountService (on_character_linked / on_character_unlinked)
- [x] **Vant Fragmenter** (`game/core/frame/geometry/fragmenter.gd`)  -  stateless data sharding via Knuth hash (lattice keys) [town:frame]  -  spec: `labs/prd-geometry.md` (created 2026-09-17)
- [x] **Spatial Geometry Fragmenter** (`game/core/frame/geometry/spatial_fragmenter.gd`)  -  deterministic sub-cell addressing, quantized bounding volumes, 64-bit address encoding, depth-limited subdivision [town:frame]  -  spec: `labs/prd-spatial-geometry.md` (created 2026-09-17)
- [x] **Geometry Integration Bridge**  -  NSC-9  ->  SpatialFragmenter  ->  T3 wiring pattern, service-level integration, cross-layer tests [town:frame]  -  spec: `labs/prd-geometry.md` sec. 6K, sec. 9 (implemented via `Nsc9Bridge` in `game/core/frame/geometry/nsc9_bridge.gd`, NSC-9 methods in `spatial_fragmenter.gd`, tests in `test_spatial_fragmenter.gd`)

---

## Recently Completed (2026-09-15)

- [x] **Manifest Backup Pipeline (D031)**: Created `srv/backup/manifest.sh`, `backup.sh`, `upload.sh`, `cold_tier.sh`, `purge.sh`, `restore.sh`, `README.md` (with limitations documentation per US-007), and verified full test suite in `test_backup.sh` [town:bridge]
- [x] **Open Seed TTL & Registry (D032)**: Created `OpenSeedRegistry` autoload service, `InstanceTypeDefinition` schema, instance type `.tres` records (`dungeon`, `arena`, `raid`), integrated 5-minute reconnect TTL in `LoginService.build_seed_receipt`, and passed 8/8 unit tests in `test_open_seed_ttl.gd` [town:core]
- [x] **World Building Arch Update**: Marked D031 and D032 as DONE in `labs/world-building-arch.md` sec. 13 component map [town:docs]
- [x] **FrameService Fix**: Fixed syntax typo `_func` -> `func` in `FrameEnv._init` [town:core]
- [x] **QC Gap Analysis & Syntax Verification**: Verified 0 parse/syntax errors across all `.gd` files in `game/` and `labs/` [town:test]

## Recently Completed (2026-09-16)  -  Docs Refresh

- [x] **Geometry PRD integration**: Updated `labs/prd-geometry.md` to include the spatial geometry fragmenter, NSC-9  ->  SpatialFragmenter  ->  T3 integration bridge, cross-layer success metrics, and open questions [town:docs]
- [x] **World-building architecture update**: Added geometry integration bridge section (sec. 13.1), updated component map and migration roadmap [town:docs]
- [x] **TASKS.md update**: Added geometry integration bridge milestone [town:docs]

### World Building PRD - Phase 5 (2026-09-17): NSC-9 Integration Bridge
- [x] **NSC-9 Bridge Module** (`game/core/frame/geometry/nsc9_bridge.gd`)  -  `Nsc9Bridge` class (RefCounted, NOT autoload): `nsc9_to_address()`, `address_to_t3_path()`, `nsc9_to_t3_path()`, `store_nsc9_state()`, `store_nsc9_fragmented()`, `restore_nsc9_fragmented()`, `query_nsc9_face()`, `query_nsc9_region()`, `is_spatial_nsc9()`, `entity_spatial_to_face()` [town:frame]
- [x] **Bridge integration tests** (`game/core/frame/geometry/test_nsc9_bridge.gd`)  -  9 test cases covering full pipeline (NSC-9 -> address -> T3 path, store/query, deterministic hash, fragmented store/restore, face query, non-spatial rejection, is_spatial, entity_spatial_to_face) [town:test]
- [x] **EntityService NSC-9 wiring** (`game/core/services/entity_service.gd`)  -  `_nsc9_bridge` initialized in `_init_spatial_and_t3()`, `_compute_nsc9_code()` derives codes from position + entity_id via `Nsc9.nearest_vertex()`/`Nsc9.spatial_axis()`, `_entity_nsc9_codes` dict caches codes, `metadata.nsc9_code` set on registration [town:core]
- [x] **ZoneManager NSC-9 wiring** (`game/core/services/zone_manager.gd`)  -  `_nsc9_bridge` initialized in `_init_spatial_fragmenter()`, `_compute_nsc9_code()` for zones, `get_zone_nsc9_code()` and `get_zone_nsc9_t3_path()` public helpers [town:core]
- [x] **Bridge code review + fixes** (2 commits): fixed duplicate `decode_int(code: int)` syntax, removed bloat (duplicate `_axis_to_face`, `_nsc9_code_to_face`, 1-liner wrappers), re-added `address_to_t3_path`/`nsc9_to_t3_path`/`query_nsc9_region` for test coverage, fixed duplicate `Nsc9BridgeScript` preload in entity_service.gd [town:frame]
- [x] **Docs refresh**: `labs/prd-geometry.md` sec. 6K + sec. 9 updated, `labs/prd-spatial-geometry.md` open questions 1-3 marked RESOLVED, `labs/TASKS.md` bridge milestone detailed [town:docs]

- [x] **RulesEngine Consolidation**: Refactored QoSService (`matchmaking_qos.gd`), SecurityService (`security_service.gd`), AppFirewall (`app_firewall.gd`), AutoResponseService (`auto_response_service.gd`) to use RulesEngine for all decision logic [town:core]

## Phases 0-4 Integration Audit (2026-09-20) [town:test]

Scope: world-building.md sec. 18 phase definitions vs. actual code + wiring.

- [x] **Inventory & existence check**: all frame primitives present (`core/frame/{kv,srv,math,geometry,db}` with co-located tests); AccountRollup exists and is wired (TASKS.md was stale); 73 autoloads registered in valid order.
- [x] **Preload integrity sweep**: zero missing `res://` script paths repo-wide; scene ext_resources resolve; no dangling refs to the renamed `state_machine.gd`.
- [x] **Uncommitted syntax-fix pass verified and preserved**: stale `res://labs/` preloads -> `res://core/frame/`, `ScopeNode` inner-class fix, self-preload shadow fixes, memory-store SQL parser fix, `frame_client.gd` rewrite (tabs, RefCounted-safe HTTPRequest, local fallback). All validated.
- [x] **FIXED: docker-compose `frame` service** pointed at nonexistent `srv/frame/Dockerfile` (broke `--profile dev/prod` builds). Removed; extraction remains deferred per world-building-arch.md sec. 11.2.
- [x] **FIXED: Phase 0 item "seed field on all entity types"** was never done. Added `Entity.seed` and deterministic derivation in `EntityService.register_entity` via `SeedChain.derive_seed` (`/entity/<id>` path, frame seed as stack base).
- [x] **Docs corrected**: D028 marked DONE in world-building-arch.md (roadmap sec. 14 + component map); Frame Extract entries corrected above; Definition Tree noted as Phase 3 candidate (implemented + tested, no game consumers yet).
- [x] **Known deferred (by design, not broken)**: Coordinator process + edge shards (Phase 3/4 infra); Vant icosahedral ports; `srv/frame/` HTTP bridge; world seed on entities (per-player frame seeds only; world seed is Phase 5).
- [x] **Verification limits**: no Godot binary or Docker in this environment; headless test suite could not be run. Static checks (paths, tabs, UTF-8, autoload order, class_name/ autoload collisions, signal-handler signatures on audited paths) all pass.
- [x] **Frame Extract to Container (CORRECTED 2026-09-20)**: `srv/frame/` was never committed (confirmed absent from disk and git history). FrameClient (`game/core/utils/frame_client.gd`) exists with circuit breaker + local RulesEngine fallback and is the active integration point; rules/Scope/T3 evaluate in-process per world-building-arch.md sec. 11.2. HTTP bridge extraction remains deferred.
- [x] **Docker Compose Integration (CORRECTED 2026-09-20)**: The `frame` service block referenced the nonexistent `srv/frame/Dockerfile` and broke `docker compose --profile dev/prod up --build`; it has been removed with an explanatory comment.

## Phases 0-4 Integration Audit - HEADLESS TEST EXECUTION (2026-09-20) [town:test]

Continuation of the audit above. Godot 4.7.2 binary installed in the sandbox
(`/tmp/Godot_v4.7.2-stable_linux.x86_64`); the full test battery is now
executable. Result: **57/57 test files exit 0** (was: 25/40 with 63 runtime
errors). Production bugs found and fixed, in order of severity:

### Production bugs fixed
- [x] **markov.gd hex chunk keys** [town:frame]: `_chunk_key_to_offset` used
  `int("0x"+s)` (decimal-only) so every chunk with a hex letter (a-f)
  collapsed to offset (0,0) -> predictions garbage past x=9. Now `hex_to_int()`.
- [x] **markov.gd prediction model** [town:frame]: absolute-only
  P(next|chunk) cannot exceed ~50% on any revisited path and 0% on straight
  lines (N021 requires 70%). Added velocity-conditioned transition table
  P(next|chunk, arrival delta) with graceful fallback to the PRD baseline
  row, momentum tie-break, and cold-start momentum. Accuracy now
  straight 99.9% / patrol 99.6% / oscillation 98.9%.
- [x] **memory_persistence_store.gd SQL engine** [town:adapter]: (1) base-table
  parse block indented inside `if join_pos` after `continue` (dead code);
  (2) `_parse_from_with_joins` re-searched "FROM" in text past FROM ->
  every SELECT returned []; (3) "first letter after SELECT" skipped `*` ->
  all projections empty; (4) table name greedily ate `WHERE ...`; (5)
  UPDATE sliced WHERE param indices against global $N -> parameterized
  UPDATE matched nothing. All fixed; SELECT/UPDATE/DELETE/tx now correct.
- [x] **memory_persistence_store.gd KV batch API** [town:adapter]:
  `set_many`/`get_many`/`delete_many` were base-class stubs -> DictStore
  writes silently vanished. Implemented on the `kv` table per prd-db.md.
- [x] **dict_store.gd read/batch paths** [town:adapter]: reads now use the
  portable KV batch API (not per-backend SQL dialect), `set_batch` serializes
  exactly like `set_value` (raw dicts previously stored unparseable).
- [x] **open_seed_registry instance types missing** [town:core]: PRD
  open-seed-ttl US-004 requires `.tres` per instance type; the directory
  `data/roots/world/instance_types/` never existed so every TTL fell back
  to 300s (arena could never have its shorter window). Added
  `dungeon.tres` (300s), `arena.tres` (180s), `raid.tres` (300s).
- [x] **server_manager.gd** [town:core]: emitted nonexistent
  `EventHub.server_shutdown`; now `EventHub.system.server_stopping`.
- [x] **tick_service.gd `_should_step_entity`** [town:core]: Dictionary
  `.has()` on Node3D entities (109x/tick errors); now the `in` operator.
- [x] **entity_service.gd `_create_default_metadata`** [town:core]: direct
  `.faction`/`.level` access on NPCEntity (property is `faction_id`);
  guarded with `in` checks.
- [x] **targeting_manager.gd entity handlers** [town:core]: `.has()`/`get(k,d)`
  on entity Nodes; rewritten with `in` guards, spawn/despawn/died.
- [x] **backend_factory.gd / migration_runner.gd** [town:adapter]: bare
  `GameLog` fallback in scripts load()ed by --script tests; print fallback.
- [x] **UI widget fixes** [town:web]: combat_log `RARITY_COLORS.rarity_legendary`
  (crashed _setup_ui) + null-guarded `clear()`; character_panel Item-schema
  fields (Resource.get(k,d) removal), missing `_refresh_equipment_display`,
  typed loops; shop_ui `InventoryService.get_gold` (no .singleton()); hud
  invite handlers now pass sender id (`invite_player(my_id, target)`).
- [x] **inventory_ui.gd** [town:web]: Python-ism `func _on_inventory_changed(...)`
  broke parse; explicit dual-signal signature.
- [x] **scope_node.gd** [town:frame]: `class_name` before `extends` (lint).

### Test-harness bugs fixed (tests were silently vacuous or hanging)
- [x] `_init()` vs `_initialize()`: test_open_seed_ttl, test_lod_predictor,
  frame tests ran before autoload registration (or before their own setup).
- [x] Missing `quit()` made test_notification_toast / test_autoload_scope
  tick forever (the "hung command" at the audit start).
- [x] `SceneTree._ready` does not exist (test_autoload_scope).
- [x] Double `_ready()` on HudLayer tripped its static-instance guard and
  queue_free()d the HUD; headless HUDs must pre-create widget children
  (CombatLog/TooltipManager) before add_child, as hud_layer.tscn does.
- [x] Lambda captures by value; wall-clock lookups in simulated-clock tests
  (open_seed_ttl). Registry awaits one frame for autoload _ready.

### Final state (all exit 0)
- Frame battery: kv (lru/definition/seed_chain/state_tree/t3), srv
  (rules/scope), math (icosahedral/nsc9), geometry (fragmenter/spatial/
  nsc9_bridge), db (snapshot_store).
- Adapters: parse, registry, dict_store(+ttl), memory, persistence, cache,
  integration (7/7), e2e.
- Smoke: e2e_flow (40 OK), login_flow (21 OK), hud_integration (7 OK),
  notification_toast (9 OK), notification_frame, notif migrations x4,
  islands, open_seed_ttl (19 PASS), lod_predictor (15 OK), critical_params
  (41 PASS), account_rollup, respawn, base/base2, entity_autoload,
  autoload_audit, eh, path, preload, seed/state schema, parse_check, lint
  x5 (syntax/indent/charset/autoload/general).
- Residual SCRIPT ERRORs in some logs are the documented --script-mode
  autoload-identifier noise (files compile fine under full boot).

## Phase 3 completion: memory tree + social tree (2026-09-20)

Goal: close the last open Phase 3 roadmap item and wire the orphaned
definition tree into a real consumer.

### New frame primitives (core/frame/kv/, arch doc §9)
- `memory_tree.gd` + `memory_schema.gd` -- AI agent memory over T3
  (kinds: observation/event/relationship/goal/fact, weighted).
  API: insert/update/get/delete_memory, list_memories, list_by_kind,
  agent_root_hash, root_hash, diff/apply_diff, clear.
- `social_tree.gd` + `social_schema.gd` -- player relationships over T3
  (rels: friend/guild/party/rival/mentor). API: insert/get/delete_edge,
  list_edges, list_by_rel, list_related_ids, player_root_hash,
  root_hash, diff/apply_diff, clear.
- Co-located tests: `test_memory_tree.gd` (24 PASS),
  `test_social_tree.gd` (25 PASS). Both follow the definition-tree
  test conventions (full-tree root_hash() for diff; T3 diff resolves
  only same-instance snapshot history, and paths are normalized
  without leading slash).

### Definition tree wired (was orphaned)
- `zone_manager.gd` now mirrors every loaded ZoneData into the frame
  definition tree under `definitions/zones/<id>` (def_type "zone"),
  via a lazy `_get_definition_tree()`. New accessor
  `get_zone_def(zone_id)` for frame-side world-config reads.
- New smoke test `tests/test_zone_def_tree.gd` (14 PASS) verifies
  mirroring, path layout, and accessor behavior.

### Docs
- `labs/world-building-arch.md` roadmap: memory+social tree
  PENDING -> DONE (NPC-AI/FriendsService wiring noted as follow-up);
  frame extract DONE -> DEFERRED in-process (FrameClient), matching
  the corrected TASKS.md note from 2026-09-19.

### Verification
- Full frame battery (14 suites: kv/srv/math/geometry) OK.
- Lint battery (5 suites) OK -- includes charset + tabs on new files.

## Trees made load-bearing: NPC memory + FriendsService social mirror (2026-09-20)

### EnemyAI remembers players (memory tree)
- `core/ai/enemy_ai.gd` now owns a MemoryTree at
  `memory/enemies/<entity_id>`. `remember()` writes weighted event
  memories (attacked/killed); `_update_known_threats()` keeps the top
  16 by recency in `_known_threats` (player_id -> weight).
- Targeting bias: `_check_for_targets()` prefers valid targets with
  the highest remembered threat weight (grudge aggro) before falling
  back to first-valid. Kills are remembered at weight 1.5, hits at 1.0.
- Fixed two pre-existing parse bugs surfaced by --check-only:
  `StatusEffectData.EffectType.BUFF` -> `.STEALTH` (BUFF never existed
  in the enum) and Variant inference on `entity.attack_power`.
- New `tests/test_ai_memory.gd` (10 PASS).

### FriendsService backed by the social tree
- `core/services/friends_service.gd` lazily instantiates a SocialTree
  and mirrors every friend/block/ignore mutation into
  `social/<player_id>/{friend,rival}/<other_id>` (`_mirror_edge`),
  including reciprocal friend removal. In-memory dicts remain the hot
  path; the tree is the durable frame-side view (same pattern as the
  ZoneManager definition mirror).
- New tree-backed accessors: `get_social_friend_ids()`,
  `get_social_edge_count()`, and `verify_social_mirror()` (sync
  report between memory dicts and tree).
- New `tests/test_friends_social_tree.gd` (19 PASS).

### Verification
- Frame battery + integration suites + login/e2e + lint all green.

## Full aggro system wired (2026-09-20)

### Threat table becomes real (AggroComponent)
- Fixed `transfer_threat_to` (checked `has_method("aggro_component")`
  on a property -- always false) and `_decay_threat` (erased dict keys
  mid-iteration; now collects then erases).
- New capabilities: `taunt(tank, duration, sticky_threat)` tank grab
  with force-locked target + sticky threat (no snap-back on expiry),
  `taunt_resist` for bosses, `add_damage_threat` (per-type threat
  modifiers for tank kits / enrage), `record_heal_threat`
  (healer threat at 0.5x default), `scale_threat` (percentage aggro
  dumps / feign death), negative-amount dumps floor at 0.
- Taunt timing is delta-driven (testable, pause-respecting).

### Damage/heal flows now generate threat
- EventHub: added the missing `damage_dealt` signal that
  `health_component.take_damage` was already emitting (latent runtime
  error on every player damage event).
- `Enemy.take_damage` now feeds the enemy's own threat table AND calls
  `ai.on_damaged(source)` (grudge memory + engagement were previously
  unreachable -- nothing ever called them).
- `Enemy._ready` attaches an AggroComponent (component was 100%
  orphaned before -- never instantiated anywhere).
- `skill.gd` heal path generates heal threat on all in-combat enemies
  within 20m of the heal.

### EnemyAI: threat-driven switching + forgiveness + persistence
- COMBAT state now follows `get_highest_threat_target()`; taunts hold
  the lock. Damage threat recorded onto both combatant tables.
- RETURN arrival decays all grudges by 0.5 (weights below 0.25 are
  forgotten) -- leash now grants forgiveness, repeated offenders stay hot.
- Memory persists via shared DictStore KV (`frame:enemy_memory:*`),
  restored on `_ready`, re-saved every 30s and on tree exit. Grudges
  survive restarts.

### Systemic fix: DictStore shared fallback
- `_ensure_store` created a per-instance memory fallback, silently
  isolating every DictStore writer (permission_manager, faction_manager,
  skill_academy, loot_service, zone state...). All instances now share
  one static fallback backend until an AdapterRegistry is bound.

### Tests
- New `tests/test_aggro_system.gd` (33 PASS): switching, taunt
  lock/expiry/resist, dumps, heal threat, modifiers, transfer fix,
  decay, grudge decay, persistence.
