# Session Scratch Pad

Wipe and reuse each session. This file is mine to use as
persistent memory across resets.

## Orchestration (Kilo Code Towns)

### Branching model
- `main` — shared integration branch. Always pull before starting.
- `labs/*` — experimental / docs work. Push here first.
- Feature branches: `kilo/<topic>` or `town/<topic>`. One branch per town.
- Never rebase `main` while another town is working. Use merge commits.

### Before you start a task
1. `git pull origin main` — check for parallel work.
2. Read the bottom of this file for recent completions.
3. Check `prd-db.md` section 2 + section 8 for service ownership.
4. Mark your task `in_progress` with your town name + timestamp.
5. If the task touches `game/` AND `labs/`, coordinate with both towns.

### Task ownership tags
Use these in the task list:
- `[town:core]` — core services, autoloads, entities
- `[town:adapter]` — persistence/cache/memory adapters
- `[town:bridge]` — pg-bridge, redis-bridge, docker
- `[town:ui]` — HUD, panels, targeting, social
- `[town:docs]` — TASKS.md, prd-db.md, DEPLOY.md
- `[town:test]` — lint, smoke, adapter tests

### Merge rules
- Push to your branch, open PR, wait for CI (lint + parse check).
- Do not force-push to `main`.
- If merge conflicts: ask in town channel, do not resolve silently.
- After merge: update `## Recently Completed (2026-09-09)

- [x] Created game/adapters/persistence/dict_store.gd (RefCounted KV wrapper)
- [x] Created game/adapters/cache/cache_wrapper.gd (CacheStore wrapper)
- [x] Created game/adapters/memory_layer/memory_wrapper.gd (MemoryStore wrapper)
- [x] LoginService: replaced user://accounts.json with DictStore
- [x] PlayerConfig: replaced ConfigFile with DictStore  
- [x] AccountService: added DictStore persistence for accounts/characters
- [x] SecurityService: persist player restrictions (bans/mutes)
- [x] WaypointService: persist player waypoints across restarts
- [x] FollowService: persist active follows per player
- [x] VaultService: persist personal/guild/account vaults
- [x] PartyService: persist parties and pending invites
- [x] TitleService: persist unlocked player titles
- [x] QuestService: persist player quest progress
- [x] AchievementService: persist unlocked player achievements
- [x] GuildService: persist guild state and invites
- [x] TradeService: persist completed trade history
- [x] ShardManager: persist shard info
- [x] LootService: persist player loot history
- [x] CooldownService: migrated to CacheWrapper with TTL expiration
- [x] FactionManager: persist factions, reputations, alliances
- [x] AntiCheatService: persist suspicion scores and bans
- [x] DeathFeatures: persist death stats and kill streaks
- [x] RespawnService: persist karma per entity
- [x] ChatService: persist ignored lists and player settings
- [x] AutoResponseService: persist exploit counts
- [x] PlayerLockService: persist lock state
- [x] VendorService: persist buyback items
- [x] SkillAcademyService: persist skill progression
- [x] WorldService: persist gateway definitions
- [x] FairnessService: persist trust scores and session data
- [x] ConnectorService: persist connected agent registrations
- [x] SameAccountTransferService: persist transfer stats
- [x] MatchmakingQoS: persist latency/quality/packet loss data
- [x] DictStore enhanced with TTL, batch ops, sweep_expired
- [x] CacheWrapper created for CacheStore with TTL support
- [x] MemoryWrapper created for MemoryStore access
- [x] Migration V20260909_001__init_kv.sql created
- [x] Adapter tests: test_dict_store, test_dict_store_ttl, test_service_integration, test_adapter_e2e
- [x] Bridge tests pass: pg-bridge 12/12, redis-bridge 20/20
- [x] Branch kilo/festive-ribbon-wav pushed to origin
## Architecture Plans for Remaining Heavy Services

### Context
- 29 light services already wired to DictStore/CacheWrapper/MemoryWrapper
- These 7 services need more architectural thought before wiring

---

### 1. InventoryService [town:core] [town:adapter]

**Current state:** `_player_inventories: Dictionary = {}` (player_id -> InventoryComponent)
- InventoryComponent has `_inventory: Array = []` (Item objects) and `_equipment: Dictionary = {}`
- Items are complex objects (Item class with stats, bind status, durability, etc.)

**Challenges:**
- Items are objects, not dicts — need serialization layer
- Inventory changes are frequent (add/remove/swap on every loot/trade)
- Equipment is small (16 slots) but linked to item instances

**Recommended architecture:**
- Add `to_dict()` / `from_dict()` to Item class (if not exists)
- Add `to_dict()` / `from_dict()` to InventoryComponent
- Persist full inventory snapshot per player: `inventory:player:<id>` -> serialized inventory array
- Persist equipment separately or include in inventory snapshot
- Use DictStore for persistence
- On load: deserialize items and re-hydrate InventoryComponent
- Write-through on every mutation (already doing in-memory, just add persist)

**Key decisions needed:**
- Snapshot vs delta? → Snapshot (simpler, inventory is small)
- Include equipment in snapshot or separate? → Include (atomic)

---

### 2. ZoneManager [town:core] [town:adapter]

**Current state:** `_zones`, `_players_in_zone`, `_enemies_in_zone`, `_instances`, `_entity_zones`, `_transition_zones`

**Challenges:**
- Zone definitions are static data (from ZoneData .tres)
- Runtime tracking (players/enemies in zone) is highly dynamic
- Multi-shard instances need cross-process awareness

**Recommended architecture:**
- **Zone definitions**: persist to DictStore like WorldService gateways (`zone:<id>`)
- **Runtime tracking**: keep in-memory only, backed by MemoryStore for cross-shard awareness
- **Instances**: persist active instances to DictStore (`zone:instance:<id>`)
- **Entity zones**: ephemeral — rebuilt from EntityService on zone transition
- Use CacheStore for hot zone lookups if needed

**Key decisions needed:**
- How often to snapshot instance state? → On instance create/destroy + periodic timer
- Cross-shard entity tracking? → MemoryStore with TTL (players leave zones eventually)

---

### 3. EntityService [town:core] [town:adapter]

**Current state:** `_entities`, `_players`, `_enemies`, `_npcs`, `_entity_metadata`

**Challenges:**
- Entity positions update every tick (60+ times/sec)
- Cannot persist on every update
- Need fast lookup by id, type, zone

**Recommended architecture:**
- **Live state**: in-memory only (current position, HP, state machine)
- **Entity metadata**: persist to DictStore on spawn/despawn (`entity:<id>`)
  - Includes: entity_type, owner_id, base_stats, spawn_metadata
- **Spawn registry**: persist spawn definitions to DictStore (already in SpawnService)
- Use CacheStore for hot entity lookups (entity_id -> metadata) with TTL
- On server start: load all entity metadata from DictStore, rebuild in-memory registry
- On spawn: persist metadata, cache in Redis
- On despawn: update metadata (last seen position), keep in store

**Key decisions needed:**
- Persist position on despawn or periodically? → On despawn + every 5 min for players
- Entity metadata schema? → Reuse SpawnMetadata where possible

---

### 4. PlayerManager [town:core] [town:adapter]

**Current state:** Manages connected players, peer ↔ player_id mapping, session tokens

**Challenges:**
- Session state is ephemeral (player connects/disconnects)
- Session tokens already handled by LoginService
- Peer mapping is runtime-only

**Recommended architecture:**
- **No persistence needed** — this is pure session state
- Players re-register on login via LoginService
- Session tokens already in LoginService DictStore
- If cross-process needed: use CacheStore with short TTL for peer mappings
- Keep in-memory for performance

**Key decisions needed:**
- Cross-shard player lookup? → CacheStore with TTL=session_length

---

### 5. GameManager [town:core] [town:adapter]

**Current state:** Main game state machine, player management, world state

**Challenges:**
- Very complex, many signals and state transitions
- Much of its state is derived from other services
- Direct persistence would create tight coupling

**Recommended architecture:**
- **Minimal direct persistence** — let each service own its state
- Persist only high-level game settings (phase, settings) to DictStore
- GameManager should query other services for current state (EntityService, ZoneManager, etc.)
- If needed: use CacheStore for computed aggregates (online count, server status)

**Key decisions needed:**
- Should GameManager be the "source of truth" for anything? → No, delegate to services
- Persist game phase/state? → Yes, for crash recovery

---

### 6. NotificationService [town:core] [town:adapter]

**Current state:** `_notification_queue`, `_entity_notifications`, `_notification_history`

**Challenges:**
- Live queue is ephemeral (toasts that appear and disappear)
- History is useful for offline players
- Deduplication keys need TTL

**Recommended architecture:**
- **Live queue**: in-memory only, ephemeral
- **Entity notifications**: persist last N per player to DictStore (`notification:<player_id>`)
  - Array of notification dicts, trimmed to max_history
- **Dedupe cache**: use CacheStore with TTL for dedupe keys
- On player login: load notification history, show missed notifications
- On notify(): persist to history, emit signal for live toast

**Key decisions needed:**
- How many notifications to persist per player? → Configurable, default 50
- Dedupe window? → Already handled by NotificationDispatcher

---

### 7. DataService [town:core] [town:adapter]

**Current state:** Loads static .tres files (items, enemies, skills, etc.) into memory

**Challenges:**
- .tres files are already cached by Godot's resource system
- 200+ .tres files across 18 schemas
- Content updates require server restart (or live reload)

**Recommended architecture:**
- **Primary**: keep .tres loading as-is (fast, Godot-native)
- **Cache layer**: build Redis cache for hot lookups (item_id -> Item data)
  - Populate on first access, TTL = very long (content rarely changes)
  - Reduces repeated .tres parsing across shards
- **Content versioning**: add schema version to cache keys, invalidate on update
- If moving to Postgres: create `game_data` table with JSONB columns per schema
  - But this is a large migration — defer to later phase

**Key decisions needed:**
- Redis cache worth it? → Profile first; .tres loading is already fast
- Live content updates? → Not needed for initial wiring

---

## Execution Plan

### Phase 1: Medium-complexity services (sub-agent friendly)
1. `NotificationService` — persist notification history
2. `WorldService` — already done (gateways), add active events
3. `MatchmakingQoS` — already done
4. `SameAccountTransferService` — already done

### Phase 2: Complex services (need manual review)
5. `InventoryService` — item serialization + snapshot
6. `ZoneManager` — zone definitions + instance state
7. `EntityService` — metadata + spawn registry

### Phase 3: Session/ephemeral services (minimal wiring)
8. `PlayerManager` — no persistence needed
9. `GameManager` — minimal settings only
10. `DataService` — .tres cache optional

### Next sub-agent targets
- InventoryService (after Item serialization confirmed)
- ZoneManager (zone definitions)
- EntityService (spawn metadata persistence)

