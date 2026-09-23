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

## Spawn-to-combat vertical slice (2026-09-20)

Goal: make every previously built system (threat, taunt, heal aggro,
grudge memory, leash decay, persistent memory) reachable through actual
play. The loop is now live end-to-end.

### The loop as shipped
- PlayerController._ready creates a HealthComponent and exposes the full
  Entity duck-typed combat surface (entity_type/display_name/level/stats/
  take_damage/heal/get_attack_power/get_defense/get_crit_*/is_dead/
  faction/relation/team_id).
- world_playable.gd is now the playable scene controller: registers the
  player with EntityService (id player_1) + fixes the TargetingManager
  ""-id registration, attaches EnemyAI to every scene enemy with ranges
  from EnemyData, and bridges EventHub.damage_dealt into DamageNumbers +
  CombatLog (creates a DamageNumbers layer if the scene lacks one).
- SpawnService._create_enemy now spawns the real Enemy class (with
  HealthComponent + AggroComponent created on demand), attaches an
  EnemyAI configured from EnemyData ranges, and parents the enemy into
  the scene tree so _physics_process/AI actually run.

### Latent production bugs found by wiring the loop (all fixed)
- skill.gd: Entity-typed caster/target params would reject
  PlayerController (a CharacterBody3D) at runtime -- all combat-relevant
  signatures untyped (execute/calculate_damage/calculate_healing/
  consume_resources/apply*/create_*_effect).
- AggroComponent + EnemyAI: same Entity-typed params holding a
  PlayerController target -> untyped; repaired the misindented,
  unreachable stealth-validation block in _is_valid_target.
- Entity.faction did not exist while is_enemy() reads it -> added a
  faction alias (getter/setter over `relation`, cannot disagree).
- Enemy.take_damage: set the dead flag via health_component._is_dead so
  the AI death gate works; emits damage_dealt + EventHub.damage_dealt
  (mirrors HealthComponent's player-side event) for the HUD bridge.
- Enemy death previously never unregistered from EntityService ->
  despawned_from_world() now calls unregister_entity on death.
- EnemyAI._perform_attack used nonexistent entity.attack_power ->
  get_attack_power(); target-death check tested the ENEMY's health
  instead of the target's -> now checks _target, routes through
  on_target_death (kill memory) -- which nothing ever called.
- EnemyAI._match_state_behavior wrote entity.move_speed on Enemy (no
  such property, runtime error every state change) -> speed application
  split into _match_state_speed guarded by "move_speed" in entity.
- PlayerManager.set_local_player used player.has(...) (nonexistent on
  Object) -> `in` operator.
- HealthComponent.take_damage crashed on owners without
  combat_component/inventory_component (PlayerController/Enemy) ->
  guarded duck-typed access.
- SpawnMetadata: dynamic fields (nsc9_code/faction/spatial_address/
  seed) assigned by services crashed in 4.7.2 -> declared explicitly.
- damage_numbers.gd: C-style ternary + six Variant-inference parse
  errors under 4.7.2 strictness + void reverse() call -> fixed; file
  now compiles clean.### Verification
- NEW tests/test_combat_loop.gd: 31 assertions -- spawn->AI attach->
registration->aggro acquire->combat->threat table populated->player
takes damage->threat switching->taunt->threat modifiers->death->
unregistration. Green across 3 consecutive runs (deterministic).
- Regression: aggro, ai_memory, friends_social, zone_def_tree, login,
e2e, notification x2, hud, open_seed_ttl, entity_autoload,
autoload_audit, islands, auto_response, frame battery
(t3/state_tree/lru/definition/memory/social/seed_chain/rules/scope/
nsc9), adapters (memory/dict), lint x5 -- all green.

## XP/gold kill-reward hook + full-boot fixes (2026-09-20)

Commit fec5e83. Closes the reward half of the spawn-to-combat loop.

### Kill rewards (core/services/kill_rewards.gd)
- Kill-credit resolution: direct killer -> threat-table owner (tank
  keeps credit when DPS lands the last hit; heal threat pays out).
  Creditless kills (fall damage, despawn) emit nothing.
- EnemyData.xp_reward/gold_min/gold_max drive payouts; deterministic
  level-based fallback when no data. Level-difference scaling with
  grey-kill floor (0.1 at 8+ levels up) and 5x lowbie cap.
- Party split via PartyService.share_xp; offline shares logged.
- Grants via duck-typed add_experience/add_gold on the node, mirrored
  into PlayerManager (HUD XP bar + level read from it).
- EventHub.kill_rewarded broadcast; world_playable HUD bridge logs the
  kill to CombatLog and floats +XP/+gold over the local player.
- player_controller gained the progression surface (experience, gold,
  level-up curve mirroring PlayerManager, full restore on level up).

### Full-boot runtime fixes found while verifying (committed together)
- project.godot: comment lines inside [autoload] corrupted a node
  name (QoSService registered as "#ServicesQoSService"). Comments and
  blank lines removed; test_notification_frame now resolves the real
  name with the stale name as fallback.
- UI: nonexistent accessible_name/accessible_description Control
  properties removed (menu_manager, ui_styles + callers); MenuManager
  debug panel call_deferred targeted the panel instead of self and
  resolved "Panel" on the wrong node; duplicate add_child of
  net_refresh_btn.
- corpse.gd: typed _owner/_killer params rejected PlayerController;
  has() on Objects/Resources -> "in" operators; untyped setup().
- death_features: unguarded entity.inventory_component access.
- notification_service: "" notification_message crashed %-format in
  the default branch.
- event_hub: accessibility + corpse lifecycle signals declared.
- Cleanup: 11 probe_*.tscn bisect artifacts + tests/probe_bisect.gd
  removed (world_playable debug leftovers, probe_a.tscn referenced
  nonexistent scene).

### Verification
- NEW tests/test_kill_rewards.gd: 21 PASS (credit resolution,
  threat-table fallback, EnemyData vs fallback rewards, level
  scaling, grants, PlayerManager mirror, signal payload).
- Regression green: aggro 33, combat_loop 31, ai_memory 10, e2e 40,
  login 21, friends_social 19, zone_def_tree 14, notification
  frame/toast/hud, lint x4. Full boot (--quit-after) clean.

## Ankh + quest kill objectives + loot pickup flow (2026-09-20)

Three systems built as one loop: kills advance quests, kills drop
loot, loot lands in a (finally existing) player inventory, and the
ankh anchors death/respawn into the world.

### Ankh placed and wired (was 100% orphaned)
- core/schemas/ankh.gd had never been instantiated anywhere. Placed
  in world_playable.tscn at (4, 0.9, 4) with a glowing marker mesh
  (CylinderMesh placeholder + OmniLight) as "Haven Plaza Ankh".
- Fixed duck-typing bugs in the schema: player.level/faction_id/
  guild_rank direct access crashed on PlayerController (CharacterBody3D
  with different props); bind while dead guard now tolerates stubs
  without health_component; bind_player now also sets the health
  component bind position (its timer respawns to _bind_position).
- FIXED RespawnService.get_available_respawn_modes: `not
  config.ankh_required` INVERTED the gate -- the ANKH option was
  hidden exactly when a player HAD bound an ankh. Also can_bind() on
  a bound ankh re-checked the bind cooldown (60s), always blocking
  the respawn offer after a fresh bind; mode offer no longer
  re-runs can_bind.
- Player interacts (E/F/gamepad A): nearest ground drop pickup first,
  else ankh bind within activation_radius. Bind toasts via
  NotificationService.notify_ankh_bound.

### Player inventory (did not exist)
- No InventoryComponent was ever created for the local player -- loot
  had nowhere to land. PlayerController._ready now creates one,
  registers it with InventoryService (keyed by entity_id), and
  InventoryComponent gained set_owner_id/get_owner_id.

### GroundLootService (new autoload, ground_loot_service.gd)
- create_drop(position, items, options): resolves {item_id, quantity}
  dicts via DataService.get_item into per-drop Item instances
  (duplicate(true), stack preserved); unknown ids skipped with a warn.
- Sources: enemy deaths (Enemy._on_died now creates a real drop from
  its LootTable roll -- previously rolls only logged), chests
  (create_container_drop, 3x linger), quest rewards
  (create_reward_drop, owner-locked, never despawns), PvP deaths.
- Owner-lock loot window: pvp_drop owner_id claims first
  owner_lock_fraction of the lifetime (FULL_LOOT_OWNER_LOCK = 0.25);
  rewards are owner-only forever. Others get the toast, not the loot.
- Pickup: try_pickup(player) routes through InventoryService ->
  InventoryComponent.add_item (full-bag partial pickup keeps the
  remainder on the ground); currency rides along via duck-typed
  add_gold. Despawn sweep in _process. Ground-dropped copies are
  removed from the source inventory (ground copy is the only copy).
- EventHub: ground_loot_spawned/picked_up/despawned signals added
  (plus item_dropped, which InventoryComponent was already emitting
  into a nonexistent hub signal).

### PvP/duel drop rules (DeathFeatures)
- _on_player_died now calls _drop_player_loot with mode resolution:
  duel meta flag -> nothing drops; WARZONE/FREE_PVP zones -> full
  loot (equipment via clear_equipment_slot + all bag slots removed
  and scattered within DROP_SCATTER_RADIUS); SAFE/other PvP and PvE
  deaths -> no equipment drop. Victim gets a loss toast.
- Player-killer detection is duck-typed (entity_id + no
  loot_table_id) instead of `is PlayerController`, matching the
  kill_rewards convention; apply_death_penalties is_pvp uses it too.
- InventoryComponent.clear_equipment_slot added (drops equipment
  without routing it back to the bag).

### Quest kill objectives (update_quest_progress had ZERO callers)
- QuestService._ready connects EventHub.kill_rewarded ->
  _on_kill_rewarded_for_quest: advances ObjectiveType.KILL objectives
  matching the entity's display_name, for the credit holder
  (rewards.player_id = direct killer or threat-table owner, same
  semantics as XP) and for every party member in the shared
  party_distribution.
- world_playable auto-accepts quest_wolves_hunt (the elder's quest)
  so the loop is live in the playable scene; combat log shows
  objective progress + QUEST COMPLETE.

### Tests
- NEW tests/test_ground_loot.gd (17 PASS): drop creation/resolution,
  unknown-id skip, pickup gating (inventory/range/owner-lock), pickup
  into real InventoryComponent with currency, reward drops, despawn
  sweep, ankh bind + cooldown + dead-block + respawn-mode offer,
  kill-objective bridge (single + party shared, wrong-target
  rejection), drop-mode resolution (PvE/duel/zone).
- Regression green: kill_rewards 21, aggro 33, combat_loop 31,
  ai_memory 10, e2e 40, login 21, friends 19, zone_def_tree 14,
  notification frame 26/toast, hud, lint x4. Clean full boot.

## Auto-loot, delegation, drop visuals, duels, guards (2026-09-21)

Five systems in one pass, all data-driven and wired into the
playable scene. Guards are the big one: an NPC/ENEMY hybrid whose
hostility is PER-PLAYER, not global.

### Auto-loot (walk-over pickup)
- Settings panel already had an auto_loot toggle (PlayerConfig
  account setting, default off). PlayerController now polls the
  nearest drop each physics tick when the setting is on and runs
  the same try_pickup path as the E key (deduped per drop).
- Respect delegation: auto-pickup is blocked by the same gates as
  manual pickup (owner-lock, party rules) -- no looting around
  round-robin.

### LootRulesService (delegation + smart routing)
- NEW core/services/loot_rules_service.gd. evaluate_pickup()
  gates every GroundLootService pickup:
  - Party rules via PartyService.set_loot_rule: FFA (default),
    ROUND_ROBIN (pointer advances ONLY on a real pickup by the
    designated member -- attempts do not consume the rotation;
    credit player always loots as a deadlock breaker), LEADER
    (leader-only), MASTER_LOOTER.
  - Smart class routing: single-class-usable drops route to the
    one party member who can use them, regardless of rule.
  - Guild lock: guild-owner-flagged drops restrict to same guild.
  - Karma gate: negative-karma players cannot loot reward drops.
  - Block reasons are recorded on the drop and shown in the HUD
    pickup prompt ("reserved for <name>", "leader only", etc).
- /lootrule <ffa|round|leader|master> chat command (party leader
  only). Enemy drops stamp loot_credit_player_id (same resolution
  as XP: direct killer or threat-table owner) so party rules have
  a stable attribution.

### 3D drop visuals + minimap markers
- NEW ui/components/loot_drop_visual.gd: rotating coin mesh +
  billboard label listing items colored by rarity (Item.Rarity
  palette). GroundLootService attaches it to every 3D drop
  (null-safe for script tests), freed with the drop.
- Minimap gains MARKER_LOOT (gold diamond, pulse-scale) upserted
  on ground_loot_spawned and removed on ground_loot_removed;
  world_playable wires the signals to the minimap node.

### DuelService (challenge flow)
- NEW core/services/duel_service.gd + /duel, /accept, /decline,
  /concede chat commands. challenge_duel -> pending -> accept
  stamps BOTH participants with the _duel_death meta flag; Death
  Features resolve the duel on death (winner announcement, flag
  cleared, no drops, no karma, no griefing record).
- Range + level-delta validation, pending replacement, 60s
  expiry, disconnect/concede cleanup. DeathFeatures duel-kill
  path skips equipment drops AND karma entirely.

### Guard system (NPC/ENEMY hybrid, per-player hostility)
- NEW core/schemas/guard_data.gd (Resource): watch_triggers
  (ENTERED_ZONE, ENTERED_RADIUS, ATTACKED, ATTACKED_FACTION,
  WANTED_LEVEL, CUSTOM), protection radius/zone/faction, aggro
  duration (permanent grudge default), share radius, stats.
- NEW core/ai/guard_ai.gd extends EnemyAI: mark_criminal()
  flips hostility for ONE player (immediate full-aggrave memory
  at weight 10, exempt from decay via has_criminal_grudge()),
  report_offense() shares the crime with every guard in
  share_radius (the "other guards attack too" path wired into
  DeathFeatures griefing records). _is_valid_target() overrides
  EnemyAI so non-offenders are never engaged even though the
  global relation stays FRIENDLY (EntityService.is_enemy reads
  the global relation -- flipping it would make guards enemies
  for everyone).
- NEW entities/guard.gd extends Enemy: stays in the enemies
  group for targeting but is skipped by _setup_enemies
  (guards get GuardAI, not EnemyAI) and configured from
  GuardData via configure_from_guard_data().
- data/guards/guard_town.tres + two guards in world_playable.tscn
  (Haven Plaza). Boot log: 2 guards active, watch armed.

### Script-mode preload lesson (AGENTS.md-worthy)
- `--script` test mode fails to resolve bare autoload identifiers
  when the const-preload chain pulls an autoload script BEFORE the
  registry is built (newer autoload referencing older via
  GroundLootService -> LootRulesService etc). Fix: runtime
  get_node_or_null("/root/Name") lookups for forward edges in
  GroundLootService/ChatService/DeathFeatures/LootRulesService,
  and tests preload via load() inside _initialize (probe-proven
  pattern; committed services keep bare refs where the edge is
  backward).

### Latent bugs fixed along the way
- entity_killed declared 2 string args but was emitted with 3
  object args (an error at EVERY kill emit); declared to match
  emission. DeathFeatures streak handler now matches the real
  signature (streaks never recorded before).
- Two pre-existing glued signal connects in DeathFeatures
  (double-fire on every death) untangled.
- HUD integrator: ALL signal connects now guarded with
  is_connected checks (test double-bind errors: 0).
- QuestUI/TitleUI refresh-before-build null crashes guarded.

### Tests
- NEW test_loot_rules.gd 30/30: FFA default, round-robin advance
  only on real pickup, leader/master gates, class routing,
  guild lock, karma gate, HUD reason stamping.
- NEW test_duel_service.gd 28/28: challenge/accept/decline,
  flag stamping, no-loot death resolution, concede, range
  break, pending replacement.
- NEW test_guard_system.gd 31/31: trigger evaluation, per-player
  hostility (non-offender never engaged), immediate full grudge,
  permanent memory (survives decay passes), watch sharing across
  guards, stats from GuardData.
- Regression green: ground_loot, kill_rewards, aggro, hud (7/7,
  zero double-connects). Full scene boot clean.

## PlacementAccess + housing + ankh scoping + spaced guards (2026-09-21)

The common-interface pass: guards, ankhs and dwellings now share ONE
ownership-scope vocabulary, so house guards, guild-hall ankhs and
faction halls all resolve "who may use this" the same way.

### PlacementAccess (core/schemas/placement_access.gd)
- NEW shared Resource: scope WORLD/PERSONAL/GUILD/FACTION + owner,
  guild_id, faction_id, allowed_ids, deny_ids. Resolution order:
  deny (beats everything, even WORLD) -> owner -> allowed -> scope
  match -> denied. Builders personal()/guild()/faction()/world().
- class_name PlacementAccess (schema convention). NOTE: the enum is
  AccessScope, not Scope -- the frame's core/frame/srv/scope.gd owns
  the global class name Scope. Builders type -> Resource and
  self-load() because a brand-new class_name is missing from the
  global class cache until an editor import pass (GuardData lesson,
  fixed at the source this time).

### Ankh revisit (guild/faction halls + the latent faction bug)
- FIXED: can_bind read player.faction, which no Entity has -- the
  faction check could NEVER pass. Now reads faction_id (fallback
  faction).
- GUILD ankhs check required_guild_id (which guild) before the rank
  check; rank 0 = any rank. New describe_bind_denial() returns the
  reason (level_low/faction/not_allowed/guild/...); can_bind
  delegates to it so gates and prompts can never drift.
- New access field (PlacementAccess) evaluates on top of type checks;
  bind denials surface as a toast from the player's E-interact
  instead of failing silently.

### DwellingService (plots + purchase + placement)
- NEW core/services/dwelling_service.gd (autoload). register_plot ->
  purchase_plot (50k demo price, one plot per player, gold via the
  duck-typed `gold` property) -> place_house_guard (250k, the dream)
  / place_personal_ankh (100k). One guard + one ankh per plot.
- Placed guards: GuardData.house_guard + access stamp +
  attach_guard_ai; registered with EntityService like scene guards.
- Placed ankhs: PERSONAL type + access stamp, bindable by owner (and
  allowed ids) only.
- Chat: /buyplot /placeguard /placeankh /plotinfo (nearest-plot
  resolution; lazy DwellingService lookup from ChatService).
- Test seams: register_test_plot, set_service_override,
  clear_test_state.

### Guards: PERSONAL duty enforced + spaced test guards
- GuardData gains access (PlacementAccess). GuardAI._is_valid_target:
  owner/allowed players are NEVER targets (home is safe even if the
  owner is wanted elsewhere); scope != WORLD means anyone who cannot
  access the plot is an intruder and a valid target. WORLD-scope
  stamps are skipped so town guards still fight.
- world_playable now has 4 guards: the two plaza guards (shared
  watch_haven_plaza) + GateGuardA/B at the east gate on an INDEPENDENT
  watch_haven_gate (data/guards/guard_gate.tres, TRESPASS trigger,
  own post position) -- grudge lists do not leak between watches.
- Guild-hall ankh (purple, rank >= 1, northwest) and faction-hall
  ankh (amber, faction 'town', southeast) placed for in-world testing.
- Demo plot registered at the merchant (-5,-5): /buyplot ->
  /placeguard to play the 250k scenario.

### Tests
- NEW test_placement_system.gd 54/54: all four scopes + deny
  precedence, ankh personal/guild/faction binding (incl. the
  faction_id regression), plot lookup/purchase flows (insufficient
  gold, repurchase, one-per-player), placement costs/ownership
  (250k/100k exact), placed guard duty/ownership/AI wiring, placed
  ankh scope stamping, and GuardAI personal targeting (intruder
  valid, owner/friend never, town guards unaffected by WORLD stamps).
- Regression green: guard 31, ground_loot 17, kill_rewards 21,
  loot_rules 30, duel 28, aggro 33, e2e, login, friends_social_tree,
  notif frame/toast/chat, hud. Full scene boot clean (4 guards,
  DwellingService ready, plot registered, zero double-connects).

## Non-headless wiring pass: visuals + showcase driver (2026-09-21)

Wired the placement systems into the playable scene for REAL rendering
mode (xvfb-run + Godot binary, not --headless) and ran an in-game tour
that exercises everything end to end.

### In-world visuals (world_playable.tscn)
- Guards were invisible untargetable Node3Ds. All 4 guards now carry
  capsule mesh + hitbox (blue guard material); gate posts flank the
  gate pair; the demo plot has a translucent gold beacon disc + post
  at the merchant.

### Showcase driver (world_playable.gd, SYNMERGIA_SHOWCASE=1)
- Env-gated coroutine (inert in normal play): teleports the player
  through start -> plaza guards -> plaza ankh BIND -> demo plot
  (/plotinfo /buyplot /plotinfo) -> guild ankh DENIED -> faction ankh
  DENIED -> /placeguard on the owned plot -> gate guards. Dev
  screenshots at every stop into captures/screenshots/.
- Full run: bind OK, plot purchased for 50k, guild/faction denials
  surface with reasons, house guard placed, 8 screenshots, ZERO
  script errors in rendering mode.

### Bugs only full mode could find
- InventoryComponent.apply_durability_loss DID NOT EXIST --
  DeathFeatures called it on every player death (3 runtime errors per
  death in full mode; headless tests never died). Implemented:
  percent-based, equipped first then bag, ceil so items lose >= 1,
  returns total points lost.
- ChatService.send_message rejected commands when the SAY-radius
  audience was EMPTY -- a solo player could never run /buyplot, /duel,
  /lootrule at all. Commands now bypass the audience check.
- Ankh bind-while-dead check bypassed describe_bind_denial (empty
  reason in prompts). Dead check now lives in _is_player_dead (health
  component -> is_dead() -> current_health, stub-tolerant) and the
  "dead" reason flows through describe_bind_denial.
- HealthComponent.revive_in_place() added (lightweight in-place
  revive used by the driver; RespawnService still owns full flow).

### Verification
- Non-headless boot (xvfb): clean, falls back to GL3 gracefully.
- Showcase: every checkpoint green (see above), screenshots
  100-140KB real frames, zero SCRIPT ERRORs.
- Regression: placement 54, guard 31, ground_loot 17, e2e, chat
  migration, hud -- all pass after the chat/ankh/inventory fixes.

### 2026-09-21 Live onboarding chain GREEN + pushed to main [town:core][town:test]

**Session goal:** finish the stopped session's pending fixes and get the
live onboarding chain passing end-to-end. Commit `8359bcd` on main.

#### Fixed (all found by running the real scene, not unit stubs)
- **EventHub 22 missing signals declared** (entity/zone_entered_zone,
  ground_loot_*, aura_*, achievement_*, targeting/aoe). Was 800+
  "Signal not found" errors per run; live boot now logs ZERO script
  errors.
- **ZoneData 4.7.2 gotchas:** `minimap.gd` called `.has()` on ZoneData
  Resources (not a Resource method) and 2-arg `Resource.get()`.
  Also `_map_size` fed a Vector3 `.size`. `hud_services.gd:677` same
  get() gotcha + wrong property (`zone_name` vs `display_name`).
- **faction duck-typing:** `zone_data.can_enter/can_pvp` read
  `entity.faction_id` unguarded; PlayerController only had
  `faction: int`. PlayerController now exposes `faction_id` and zone
  reads are guarded.
- **kill_rewards payload bug (real integration bug):** `award_kill`
  omitted `player_id`/`credit_source` from the emitted rewards dict;
  `QuestService._on_kill_rewarded_for_quest` reads
  `rewards.get("player_id")` -- so quest kill objectives NEVER
  advanced on real kills (headless tests passed only because they
  emitted the signal by hand with the key present).
- **inventory tree-safety:** `InventoryComponent.add_item` called
  `get_node_or_null("/root/SecurityService")` which hard-errors when
  the component is outside the tree -> silently ate items. Added
  `_resolve_service` (self-or-tree, is_instance_valid guard).
- **ground_loot script-mode compiles:** bare `EventHub`/
  `DataService`/`NotificationService` refs broke script-mode parse
  (autoload edge). Runtime lookups per the documented pattern.
- **world_playable.tscn:** removed stale scene-level
  `display_name = "Grey Wolf"`; `Enemy._load_from_data` makes EnemyData
  the single source of truth and the wolf quest targets "Wolf".
- **corpse.gd:** same `.has()`-on-object gotcha fixed.
- **PlayerController entity_id race:** int fallback
  `str(player_id)` registered the player as "1"; now falls back to the
  stable `LOCAL_PLAYER_ID` constant.

#### New tests
- `game/tests/test_onboarding_live.gd` -- 19 assertions, runs the REAL
  chain in the real scene: boot -> player registered ->
  `notify_player_entered_world` -> ob_wake fires -> cast skill ->
  ob_first_skill -> kill wolf via KillRewards award path ->
  first_blood + ob_first_kill -> quest wolves_hunt completes ->
  "Achievement"/"Quest" toasts on `notification_sent`.
  Deterministic handling of the spawn-camp reality: the level-3 wolf
  kills the idle level-1 player at ~frame 33 (real gameplay finding --
  aggro range reaches player spawn), so the test revives + freezes AI
  for its verification window.
- `test_ground_loot.gd` repaired: un-awaited async test ran after
  quit (stale FAIL lines); despawn test is now clock-tolerant
  (engine timer vs wall-clock despawn_at drift under xvfb).

#### Verification
- test_onboarding_live 19/19, test_ground_loot 42/42 (3x, stable),
  test_kill_rewards 21/21, test_notification_frame 26/26,
  test_login_flow 21/21, test_entity_autoload 8/8,
  test_autoload_audit 2/2. Islands suite: 19 passed, same 20
  script-errors as HEAD (pre-existing, verified via git stash run --
  not a regression).
- Live boot: 0 script errors (was 800+).

#### Open items noticed on the way
- Wolf spawn-camps the player spawn (aggro reach vs spawn distance).
  Consider a spawn-safe radius or lowering level-3 wolf aggro near
  player spawn. Gameplay-level decision, not a bug.
- Islands suite emits 20 bare-autoload script-mode compile errors
  (action_bar, minimap, target_frame, etc.) -- same runtime-lookup
  pattern would clean them, batched work.

### 2026-09-21 (later) Spawn sanctuary + zone-storm fix [town:core][town:test]

Follow-up from the same live-session findings. Commits on main.

#### 1. Wolf spawn-camping fixed systemically (spawn sanctuary)
- The scene wolf (level 3, 7.8u from spawn, 10u aggro) killed the idle
  level-1 player at ~frame 33. Repositioning alone cannot fix this:
  EnemyAI patrols 5-15u from spawn, so it can wander back onto the
  spawn. Fixed in the AI instead:
  - `EnemyAI._is_target_in_spawn_sanctuary()`: no FRESH aggro on
    targets within 12u of any zone spawn_points/bind_point (duck-typed
    ZoneManager lookup; absent manager = no sanctuary, tests fine).
  - GRUDGE EXEMPTION: a player who damaged the enemy first is still
    chased inside the sanctuary (no combat shield).
  - ORDERING BUG fixed while wiring this: `on_damaged` used to engage
    BEFORE remembering the attacker; now remembers first, so justified
    counter-chases work.
- Live test asserts survival: "player alive + full health after idle
  boot window". No more revive/freeze hack for the wolf.

#### 2. Real bug found under it: typed-param throws on player hits
- `EnemyAI.on_damaged(source: Entity)` THROWS at runtime when the
  attacker is the live player (PlayerController is a CharacterBody3D,
  not an Entity subclass). Every real player hit silently died before
  threat + grudge recording. Untyped the param in enemy_ai and
  guard_ai (guard_ai had the same bug class). Enemy.take_damage gate
  widened to duck-typed `entity_id in source` for threat/grudge.
- Proved end-to-end: attack slime via take_damage -> grudge
  `_known_threats["player_1"] = 1.0` -> `_check_for_targets()` returns
  the player despite sanctuary.

#### 3. Zone transition storm killed (thousands of errors/run)
Live runs spammed ~954 seamless transitions + ~3272 entry denials +
out-of-bounds errors per 90-frame run. Causes and fixes in
zone_manager.gd:
- Shipped zone data is four CONCENTRIC discs around the origin, so
  neighbors always "contain" each other's members -> boundary
  flip-flop every physics frame. `check_seamless_transition` now:
  current zone HOLDS its members while inside (boot assignments
  stick, level-gated inner zones entered explicitly); on exit, the
  strongest claimant wins (level_requirement desc, radius asc) via
  `_zone_claims_better`. Boot assignment at origin = starter_plains.
- Double-removal in perform_seamless_transition (`erase` +
  `remove_at(find(entity))` -> index -1 error per transition):
  single Array.erase now.
- Entry-denial cooldown (2s): untracked entities were re-probed every
  frame; a persistent denial (e.g. level 10 dungeon gate) logged
  thousands of times.
- Double `entity_entered_zone` emit in the spatial detector removed.
- Result: 0 transitions, ~62 denials (one per entity then cooldown),
  0 index errors. GODOT ENGINE LOG BLOAT ALSO EXPLAINED: two disk-full
  events this session came from these runs (19GB engine logs in
  minutes). If disk fills again: purge
  ~/.local/share/godot/app_userdata/Synmergia/logs/godot*.log.

#### Verification
- test_onboarding_live: 26/26 (3 runs, deterministic). Includes
  sanctuary holds, grudge recorded via REAL take_damage path, grudge
  overrides sanctuary (no shield). Storm counters: 0.
- Regression: kill_rewards 21, ground_loot 42, notification_frame 26,
  login_flow 21, entity_autoload 8, autoload_audit 2, guard_system 31,
  placement_system 54, islands 19 (same 20 pre-existing script-mode
  compile notes as HEAD baseline).
- Live boot: 0 SCRIPT ERROR.
- Note: player entity_type is an int mirror (1 == EntityType.PLAYER);
  is_enemy/threat paths verified against it.

#### Open
- islands suite bare-autoload script-mode compiles (unchanged, batched
  work, baseline documented).
- Zone data is concentric discs sharing one center; real region shapes
  would make the overlap resolver's "strongest claimant" rule barely
  needed. Fine for now: the hold-current rule is correct either way.

---

## Session 2026-09-22 (touch HUD live-run completion)

### Context
Continuation of the touch HUD gameplay pass: crouch-touch routing, ATK
swallowed during Land, edit-mode 0px drag, then the full live battery.

### Fixes landed this session
- **P5 battery race:** the ATK-hold check sampled the state machine
  once; under xvfb the press/check/release can all land in one chunky
  frame and the parsed action takes effect the next frame, so the
  sample read Idle. test_touch_live now polls the state machine every
  frame during the hold window (`_p5_window_open` / `_saw_attack_state`)
  and asserts Attack was observed at some point. Comment continuation
  line also fixed (`--` on its own line was a parse error).
- **Camera swipe tuning:** observed 0.48 rad per 80px flick = 440 deg
  per full-screen swipe at 2.0x. Dropped to 1.5x in world_playable
  `_setup_touch_hud` -> 0.36 rad/flick, ~330 deg/full swipe. Matches
  mouse-look feel.

### Verification
- test_touch_live (xvfb, real render + synthetic touches): **17/17**.
  Stick drag/Run, auto-sprint (7.5 u/s), sprint->Slide, slide-jump
  (vy 3.0), ATK hold-to-repeat + Attack state observed, camera yaw
  0.360 rad/flick, Crouch hold, edit-mode drag (67px) + PlayerConfig
  layout persist + reset.
- Regression (headless, exit-code green): state_schema, hud_integration,
  notification_frame, combat_loop, e2e_flow, autoload_audit,
  parse_check, login_flow.

### Feel constants now shipped
- camera look: `cam.orbit(delta_px * rotation_speed(0.003) * 1.5)`
- stick radius 80px half-extent, auto-sprint at full deflection
- slide friction/duration unchanged from prior tuning pass

---

## Session 2026-09-22 (splash-to-play journey + camera settings wiring)

### Answer to "do we need sensitivity settings?"
They already existed in the Settings panel but were DEAD - saved to
PlayerConfig and never read by anything. Now wired end-to-end:
- ThirdPersonCamera reads camera_rotation_speed (0.5..3.0 multiplier,
  1.0 default), invert_x_axis, invert_y_axis from PlayerConfig at
  _ready and live via setting_changed.
- Mouse orbit fixed: legacy `rel * rotation_speed * 60.0` was 30x
  hotter than the touch path (0.18 rad/px). Now both paths share the
  same rad/px scale (rotation_speed * sensitivity), so the slider
  governs both identically.
- Touch bridge (world_playable) scales by cam.sensitivity too, so the
  slider works for mobile swipes.
- Settings panel sliders/toggles now hydrate from saved PlayerConfig
  values on open (a saved 2.5 sensitivity used to render as 1.0).
- Known gap, NOT wired: camera_fov slider saves but nothing applies
  it (default fov is set from the node, no PlayerConfig read). Left
  for a follow-up; listed in "Open".

### New journey test: test_splash_to_play.gd (xvfb, real boot)
Drives the actual player path: main_menu scene (project main scene) ->
[Play] -> character_select -> F5 auto-select -> F6 play ->
GameManager.PLAYING -> world_playable. Checkpoints (14):
menu scene current, Play enabled, char select reached + state,
world loaded + state PLAYING, player node, EntityService entities
(11), camera rig, HudLayer, touch HUD alive, sensitivity round-trip
(PlayerConfig 2.5 -> live cam.sensitivity 2.5), touch-look bridge
emits, movement input still works after the journey (state Run).

### Bugs the journey found and fixed
- character_data.gd is_gm_class(): String class_id compared to int
  Role enum -> runtime error every world entry for non-GM chars.
  Now resolves strings via DataService, accepts CharacterClass/Role
  int/String.
- main_menu_bar.gd _check_permissions(): read `.id` but
  CharacterData exposes `character_id` -> error on every world entry.
  Guarded with `in` check.
- Both errors fired on EVERY splash-to-play run (every player, every
  boot). Fixed + verified zero SCRIPT ERROR in journey output.

### Verification
- test_splash_to_play: 14/14 (xvfb, zero script errors).
- test_touch_live: 17/17 (camera tuning unaffected; sensitivity
  default path identical feel).
- Regression headless green: state_schema, hud_integration,
  notification_frame, combat_loop, e2e_flow, autoload_audit,
  parse_check, login_flow, achievement_flow.

### Open (next session candidates)
- camera_fov + camera_smoothing + camera_distance sliders still
  unwired (same treatment as rotation_speed: apply in
  ThirdPersonCamera._apply_user_settings).
- Settings panel dropdowns do not hydrate saved values yet.

---

## Session 2026-09-22 (vertical-slice UI alive: 33/33 + pushed) [town:web][town:test]

Commit `3826d8c` on main. Continued from a crashed session (its
uncommitted trade-panel / dialog-service / hotkey work was reviewed,
verified, and shipped).

### The last UI-alive failure and its real root cause
- Symptom: "ESC preserves panel below" saw ["skill_academy"]
  instead of ["inventory"].
- Root cause 1 (production bug): SkillAcademyUI and AdminDashboard
  override UIPanel._ready() WITHOUT calling super(). UIPanel._ready
  sets visible = false; these two booted VISIBLE. First toggle then
  *closed* them, leaving stale _open_panels entries (tracker appended
  on open, erased only via _close_panel/panel_closed). Found with an
  env-gated MM_TRACE (open/close/visibility/stack tracing).
- Root cause 2 (test bug): _c_esc_stack pressed I, then
  _c_esc_no_panels_pauses pressed I again -> the second press
  TOGGLED inventory closed before C opened. Also a str_replace
  mid-edit left a duplicated KEY_C press in the test (two real
  deliveries, verified via event instance-ids -- not an engine bug).

### Fixes shipped
- super._ready() added to skill_academy_ui; admin_dashboard boots
  visible = false (custom _ready kept, double _setup_panel avoided).
- ESC/pause untangled in game_manager._input: if panels are open, do
  nothing (HudHotkeys closes top via unhandled-input); else pause.
- Trade panel: real MenuManager panel + fixed trade_ui
  (get_local_player_id() did not exist, item-picker dialog crashed,
  confirm_trade coroutines now awaited). Idle state text for no
  active session; HudServices populates on trade_started.
- Debug hotkeys F5/F6 removed from login/lobby/character_select
  (headless tests drive buttons; TAB focus cycling kept).
- DialogService singleton() converges onto the autoload (split brain:
  UI bound to a second instance's signals, dialogue_started never
  arrived). Dialogue signal pipeline verified live in the test.
- world_playable re-keys the player inventory when entity_id flips
  from fallback to the real character id after _ready.
- blacksmith set_inventory/open_with_context; menu_manager feeds
  panels their inventory; ui_panel focuses the container (not the X
  button that swallowed hotkeys); skill_academy toggle/is_open real.

### Verification
- test_ui_alive (NEW): 33/33 -- 11 panels hotkey open/close, trade +
  inventory via menu bar (mobile path), ESC LIFO, target frame flow,
  live dialog signal -> DialogUI visible.
- touch_live 17/17, splash_to_play 14/14 (xvfb, zero script errors).
- Headless regression exit-0: notification_frame, hud_integration,
  combat_loop, e2e_flow, kill_rewards, ground_loot, login_flow,
  aggro, loot_rules, duel, guard, placement, onboarding_live,
  autoload_audit, entity_autoload, parse_check, lint battery.
- Live boot: 0 SCRIPT ERROR.

### Ops note (important for future sessions)
Disk filled to 100% during this session: zombie Godot processes from
CRASHED earlier sessions held open handles to deleted 12-13 GB logs
(/tmp/out_test_*.txt, ~/.local/share/godot/.../godot.log), and stale
Xvfb sessions from days prior lingered. Runs then died mid-flight and
looked like flaky tests. Recovery: pkill -f Godot; rm /tmp/out_*.txt
/tmp/sanc*.log; freed 20 GB. If runs hang: check `df -h /` and
`ps aux | grep -i godot` FIRST.

### Open (vertical slice, next candidates)
- WebInputBridge/web HUD not exercised by this battery (browser
  client path).
- camera_fov/camera_smoothing/camera_distance sliders (carried over).
- Settings dropdowns do not hydrate saved values (carried over).
- ShopUI/DialogUI are reachable via HUD/hotkeys but have no NPC
  interaction entry points wired to them in world_playable yet
  (ActionMenu exists; NPC data has no shop/dialog assignment).

### [town:core] 2026-09-22 NPC interaction pipeline live (vert slice item closed)
Closed the "ShopUI/DialogUI have no NPC interaction entry points in
world_playable" gap. The whole chain works in-world now:
world scene NPCs (Elder/Merchant) registered with EntityService +
TargetingManager via new `_setup_offering_npcs()`; context-menu /
[E] actions route to real content: talk -> DialogService.start_dialogue
-> DialogUI; quest -> Quests panel; trade -> ShopUI.open_for_offering
(vendor offering, per-NPC pricing); loot -> LootService.pickup_loot /
GroundLootService.try_pickup; gateway -> WorldService.use_gateway.
Inline NPC includes ({type: dialogue|vendor|quest|bank|service}) are now
dispatched by NPCEntity (ref-based offering path untouched). Test:
`tests/test_interaction_pipeline.gd` boots main_menu -> world and drives
the real context handlers: 16/16 PASS (xvfb).

Root causes fixed this session:
1. UIPanel subclasses ShopUI + ActionMenu never built their base "Panel"
   node (UIPanel._setup_panel() is a no-op stub; subclasses must build
   it, see dialog_ui.gd). get_panel() was null, so all panel content
   bailed: shop grid/tabs/gold dead, NPC menu showed zero items.
   Both now override _setup_panel().
2. VendorService.singleton() called `_instance._ready()` but the script
   defines no _ready (crashed every shop open). Removed; stock state
   stays lazy via ensure_stock().
3. VendorService._get_items_by_categories assigned
   DataService.get_all_items() (Array) to a Dictionary var.
4. icon_resolver._prop used res.has(key) -- Resource has no has()
   method; every icon lookup script-errored and returned null instead
   of its default ("res://<null>" loads, Nil-to-int category crash).
   Fixed to `key in res`.
5. ShopUI proximity auto-close used the 5m default while vendors are
   reachable by tap-target from further out: shop flashed open then
   closed ("Moved too far") at the common trade range. Threshold is
   now 12m for shops.

Regression battery after fixes (xvfb): ui_alive 33/33,
interaction_pipeline 16/16, splash_to_play 14/14, ground_loot 42/42,
hud_integration ALL PASSED, notification_toast ALL PASSED. Zero SCRIPT
ERROR in run logs.

### [town:core] 2026-09-22b Settings live: camera sliders wired + dropdown hydration + SettingsPanel boot fix
Closed two carried-over vert-slice items and found a third on the way:

1. SettingsPanel never built UIPanel's base "Panel" node (same bug
   family as ShopUI/ActionMenu last session). Scene-placed in
   hud_layer.tscn with only a script, its _ready ran _setup_ui() on a
   null panel: 0 tabs, 0 controls -- the Esc settings screen rendered
   an empty overlay. Now overrides _setup_panel() (98 controls build).
2. Settings dropdowns (camera_mode, language, auto-accept, profile
   visibility, ...) hardcoded the default index. They hydrate the saved
   PlayerConfig value at build now, same as sliders/toggles already did.
   Legacy string values ("language": "en") are coerced to option index
   on load and persisted back as clean ints.
3. PlayerConfig.set_account_setting crashed with "Invalid operands
   'String' and 'int' in operator '!='" on the first dropdown change
   against a string default. Compare is now type-aware (numeric vs
   numeric via float, same-type direct, cross-type = changed).
4. ThirdPersonCamera consumed only camera_rotation_speed/invert axes;
   the fov/distance/smoothing sliders saved values the camera ignored.
   It now applies camera_fov (base FOV), camera_distance (zoom start +
   max_distance widened so a saved 30 is reachable), and
   camera_smoothing (on=12.0 / off=4.0 follow smoothness) both at boot
   and live via PlayerConfig.setting_changed.
5. player_config defaults gained "camera_fov": 90 and "camera_mode": 0
   (the Controls tab wrote camera_mode but no default existed).

Test: tests/test_settings_camera.gd (xvfb) -- hydrate camera_mode +
language on a REAL hud_layer.tscn instance, round-trip
save->reload->restored, camera boot application + live
setting_changed updates: 14/14 PASS.

Regression (xvfb, zero new script errors): ui_alive 33/33,
interaction_pipeline 16/16, splash_to_play 14/14, ground_loot 42/42
(one pre-existing stub SCRIPT ERROR in the ankh dead-player test,
confirmed identical on parent commit, does not affect results),
hud_integration 7 OK.

### [town:core] 2026-09-22 — UIPanel dead-panel audit: 9 panels revived + phantom-API fix
- Audit of every `extends UIPanel` subclass found 9 that never built their base
  "Panel" node (action_bar, bank_ui, quest_ui, title_ui, faction_ui,
  achievement_ui, quick_access_bar, character_panel, loading_ui) — same root
  cause as the ShopUI/ActionMenu/SettingsPanel family fixed earlier: they
  relied on `UIPanel._setup_panel()`, a no-op stub.
- Fix: central heal in `UIPanel._ready()` — after subclass `_setup_panel()`,
  if `get_panel()` is still null, `_setup_base_panel()` builds the canonical
  Panel > Main(VBox) shape. No per-panel boilerplate.
- Bugs surfaced once panels started executing their bodies (all previously
  dead code paths):
  - PlayerManager.get_local_player_id() was a phantom API (~30 call sites in
    bank_ui, character_panel, hud_integrator, follow_manager, compass,
    waypoint_ui, chat_ui, chat_service). Added it to PlayerManager
    (duck-types local_player.entity_id, same pattern as TitleService).
  - TextureProgressBar Godot-3 property names in cooldown spirals:
    under_texture/progress_texture/radial_mode/initial_angle/radial_fill ->
    texture_under/texture_progress/fill_mode/radial_initial_angle/
    radial_fill_degrees (action_bar, quick_access_bar).
  - character_panel `for tab in Tab:` iterated enum NAME strings -> broke
    "TabContent_%d" naming and _show_tab int lookups; now Tab.values().
  - action_bar update_accessibility_settings double-looped a flat _slots
    array (iterate Object crash); flattened.
  - quest_ui Button.text_alignment (G3) -> alignment (G4).
  - faction_ui Resource.get(key, default) two-arg calls -> _field() helper
    (4.7.2 removed the default arg; AGENTS.md rule).
- Verification: audit script instantiates all 9 panels -> 9/9 alive, zero
  SCRIPT ERROR. Regression battery: ui_alive 33/33, interaction_pipeline
  16/16, settings_camera 14/14, splash_to_play 14/14 — all zero script
  errors now (previous runs carried QuestUI/FactionUI noise).

### [town:core] 2026-09-22 — WebInputBridge/browser HUD path: contract fixed + boot repaired
- Answered the panel-audit questions with receipts: all 24 panels reachable
  via main menu bar (hamburger, 48dp touch targets) AND hotkeys (desktop);
  touch stack verified (emulate_touch_from_mouse, virtual joystick,
  long-press in interaction_layer + action_menu); UIStyles canonical in
  panels (menu bar has its own scoped _get_color fallback).
- Surveyed the web path: WebInputBridge autoload was a receiver with no
  working transmitter. web/shared/input.js existed but the two halves
  disagreed on the event contract, so nothing actually worked:
  - keys: JS sent keyCode in `x`, bridge read `data` -> keyboard 100% dead
  - wheel: JS sent +/-1, bridge mapped 1 -> MOUSE_BUTTON_RIGHT (right-
    clicking on scroll); no release distinction
  - touch end sent (0,0); no DPR scaling (mis-aimed taps at any zoom);
    256-slot ring silently overwrote itself on overflow; stuck keys on
    tab blur; no modifier flags; no unicode (chat typing impossible)
- Fixed web_input_bridge.gd (rewritten clean): contract doc header,
  wheel 3/4 mapping, stateless wheel (no synthetic release double-firing
  camera zoom), key events x=keyCode/y=mods(1 s,2 c,4 a)/data=unicode,
  touch coords on all phases, keycode fallthrough -> KEY_UNKNOWN.
- Rewrote web/shared/input.js to the same contract: DPR-aware coords,
  wheel 3/4, touch end carries last position, modifier bitmask, unicode
  payload (chat-ready), OS-repeat suppression, browser-combo passthrough
  (ctrl/meta), safe overflow drop, blur releases all held keys/buttons/
  touches, touchcancel handled.
- Rewrote web/index.html boot: old code called a fabricated Engine API
  (`new Engine({module, wasm, memory})` + `.start()`) that never existed,
  so the web client could never start. Now uses the real generated-shell
  pattern (Engine.getMissingFeatures + startGame + onProgress progress
  bar + failure notices). Capture layer deliberately NOT auto-initialized:
  Godot web delivers input natively; wrappers opt in via init() (avoids
  double-delivery). experimentalVK on (soft keyboard for chat).
- export_presets.cfg: html/experimental_virtual_keyboard=true (both Web
  presets).
- Tests: new game/tests/test_web_input_bridge.gd (18 checks: wheel,
  touch, keys+mods+unicode, gamepad, stateless wheel, unknown fallback)
  ALL PASS headless; node vm contract test for input.js (13 checks:
  DPR scaling, wheel, touch coords, key/mods/unicode, repeat
  suppression, combo passthrough, blur release) ALL PASS. No web export
  templates in sandbox -> live browser e2e pending a full export.
- Regression: ui_alive 33/33, interaction_pipeline 16/16, zero script
  errors.

### [town:core] 2026-09-23 — Web CI repair: timeout kill fixed, wasm path enabled
- User asked "CI should export wasm right? check it": every run of
  web-ci.yml was being cancelled by its own timeout-minutes: 3 — step
  timestamps show "Fast Syntax Check" ran 3m07s then died. Root cause:
  `godot --check-only` (no --script) boots the whole game headless, and a
  fresh CI checkout has no .godot/ import cache, so the boot re-imported
  the entire project and blew the budget. Workflow cached the Godot
  binary but not the import cache.
- Fixed .github/workflows/web-ci.yml:
  - Cache game/.godot/ keyed on engine version + game content
    (restore-keys fallback), making warm runs fast and cold runs possible
  - timeout-minutes 3 -> 10 (covers cold import)
  - `godot --import` as the explicit incremental import/resource gate
    (replaces the boot-the-game "syntax check")
  - PCK export on every push (the prd-web.md 3.3 "PCK-Only Workflow"
    promised but never implemented): --export-pack "Web" ../web/game.pck
  - Full wasm export path repaired: template tpz flattening (tpz puts
    files under templates/, Godot needs them directly in
    4.7.2.stable/), templates now cached, `--export` (removed in Godot 4)
    -> `--export-release`; runs on PR + dispatch (+ force_export input)
  - Artifact upload now always-on with explicit file list
- Verified locally: --export-pack "Web" succeeds (game.pck 2.6MB ->
  8.1MB — tracked pck was 3 days stale, missing all of this week's UI
  fixes); test_parse_check 11/11 on the fresh build.
- Still true: sandbox has no web export templates, so the first live
  wasm export happens in CI on the next PR/dispatch.

### [town:core] 2026-09-23 — First wasm bundle green; Node 24 action bump
- User ran workflow_dispatch (force_export): run 35805783246 succeeded
  1m39s. All steps green incl. first-ever full wasm export. Templates
  cache populated (1204MB, key godot-web-templates-4.7.2); total cache
  usage 1.28GB / free 10GB — no storage cost, 7-day access-based expiry
  kept warm by push runs.
- Artifact verified by download: game.wasm 38MB (\0asm magic header
  valid), game.js 308K, game.pck 4.7M, html + audio worklets + icon.
  14.3MB compressed artifact.
- Note: sandbox gh dispatch still 403 (Freebuff app lacks actions:write);
  user clicked Run workflow manually. Fine per PRD (dispatch is manual
  anyway).
- Bumped actions to Node 24 targets (clears the Node 20 deprecation
  warning): checkout v4 -> v7, cache v4 -> v6, upload-artifact v4 -> v7.
