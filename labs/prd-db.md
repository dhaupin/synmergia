# Synmergia — Database & Persistence PRD

> **Status:** Draft — 2026-09-06
> **Updated:** 2026-09-07 - Full inventory
> **Purpose:** Master list of all database persistence requirements

---

## 1. Overview

This document tracks all data that requires database persistence.
It serves as the source of truth for DB schema design, migration planning,
and implementation tracking.

**Storage Layers:**
- **Postgres:** Primary persistence (accounts, characters, inventory, quests, guilds, etc.)
- **Redis:** Cache layer (sessions, tick cache, materialized intersections, spatial index)
- **In-Memory:** Runtime-only data (follow state, active cooldowns)

---

## 2. Services Requiring Persistence

| Service | Status | Postgres | Redis | In-Memory | Adapter | Priority |
|---------|--------|---------|-------|-----------|---------|----------|
| `AccountService` | ⚠️ TODO | `accounts`, `sessions` | Session tokens | - | `AccountStore` | P0 |
| `LoginService` | ⚠️ TODO | `accounts`, `sessions` | Session cache | - | `SessionStore` | P0 |
| `PlayerManager` | ⚠️ TODO | `characters` | Online status | - | `CharacterStore` | P0 |
| `InventoryService` | ⚠️ TODO | `inventories`, `equipment` | Item cache | - | `InventoryStore` | P0 |
| `QuestService` | ⚠️ TODO | `quests`, `quest_progress` | Quest cache | Active quests | `QuestStore` | P1 |
| `VaultService` | ⚠️ TODO | `vaults`, `guild_vaults`, `account_vaults` | Vault cache | - | `VaultStore` | P1 |
| `GuildService` | ⚠️ TODO | `guilds`, `guild_members`, `guild_ranks` | Guild roster | - | `GuildStore` | P1 |
| `FriendsService` | ⚠️ TODO | `friends`, `blocks` | Online status | - | `FriendsStore` | P2 |
| `PartyService` | ⚠️ TODO | `parties` | Party state | Active parties | `PartyStore` | P2 |
| `LootService` | ⚠️ TODO | `loot_history` | Loot table cache | Active loot | `LootStore` | P2 |
| `ChatService` | ⚠️ TODO | `chat_log` (optional) | - | - | `ChatStore` | P3 |
| `CommunityGovernance` | ⚠️ TODO | `votes`, `proposals` | Active votes | - | `GovernanceStore` | P2 |
| `FactionManager` | ⚠️ TODO | `factions`, `faction_relations` | Relations cache | Active wars | `FactionStore` | P2 |
| `FollowService` | ✅ Done | - | - | Runtime only | (none) | P3 |
| `WaypointService` | ⚠️ TODO | `player_waypoints` | - | Active waypoints | `WaypointStore` | P2 |
| `ZoneManager` | ⚠️ TODO | `zones` | Zone cache | Active zone | `ZoneStore` | P1 |
| `SpawnService` | ⚠️ TODO | `spawn_definitions` | Spawn timers | - | `SpawnStore` | P2 |
| `CooldownService` | ✅ Runtime | - | Cooldown cache | Active cooldowns | `CooldownStore` | P3 |
| `NotificationService` | ✅ Runtime | - | - | Notifications | (none) | P3 |
| `TradeService` | ⚠️ TODO | `trade_history` | Active trades | - | `TradeStore` | P2 |
| `BlacksmithService` | ⚠️ TODO | `crafting_recipes`, `crafting_history` | Recipe cache | - | `CraftingStore` | P2 |
| `SkillAcademyService` | ⚠️ TODO | `skills`, `player_skills` | Skill tree cache | - | `SkillStore` | P1 |
| `AchievementService` | ⚠️ TODO | `achievements`, `player_achievements` | Achievement cache | - | `AchievementStore` | P2 |
| `TitleService` | ⚠️ TODO | `titles`, `player_titles` | Title cache | - | `TitleStore` | P3 |
| `SecurityService` | ⚠️ TODO | `bans`, `mutes`, `security_log` | - | - | `SecurityStore` | P1 |
| `AntiCheatService` | ⚠️ TODO | `anticheat_events` | - | Active flags | `AntiCheatStore` | P2 |
| `AutoResponseService` | ⚠️ TODO | `auto_responses` | Response cache | - | `ResponseStore` | P3 |
| `SameAccountTransferService` | ⚠️ TODO | `transfers`, `transfer_history` | Transfer cooldowns | - | `TransferStore` | P2 |
| `EventHub` | ⚠️ TODO | - | Event subscriptions | - | (cache only) | P3 |
| `RespawnService` | ✅ Runtime | Respawn points | - | - | `RespawnStore` | P2 |
| `DeathFeatures` | ⚠️ TODO | `death_log` | - | - | `DeathLogStore` | P3 |
| `LootService` | ⚠️ TODO | `loot_tables`, `drop_rules` | Loot cache | - | `LootTableStore` | P2 |
| `CombatMath` | ✅ Runtime | - | Combat formulas | - | (none) | P3 |
| `FairnessService` | ⚠️ TODO | `fairness_metrics` | - | - | `MetricsStore` | P3 |
| `EntityService` | ⚠️ TODO | `entities` (persist NPC/objects) | Entity cache | Active entities | `EntityStore` | P1 |
| `WorldService` | ⚠️ TODO | `world_state` | Tick cache | - | `WorldStateStore` | P1 |
| `ShardManager` | ⚠️ TODO | `shards` | Shard status | Active shards | `ShardStore` | P1 |
| `ServerManager` | ⚠️ TODO | `servers` | Server status | - | `ServerStore` | P1 |
| `DataService` | ⚠️ TODO | `game_data` (templates) | Data cache | - | `GameDataStore` | P1 |
| `MatchmakingQoS` | ⚠️ TODO | `matchmaking_queue` | Queue state | Active queue | `MatchmakingStore` | P2 |
| `DialogService` | ⚠️ TODO | - | - | Active dialogue | `DialogueStateStore` | P2 |
| `ConnectorService` | ⚠️ TODO | `agent_connectors`, `agent_actions` | Online status | Active agents | `ConnectorStore` | P3 |
| `PlayerConfig` | ⚠️ TODO | `player_settings` | - | - | `PlayerConfigStore` | P2 |
| `PlayerLockService` | ⚠️ TODO | - | - | Active locks | (none) | P3 |
| `SlotService` | ⚠️ TODO | (uses `InventoryStore`, `VaultStore`, `TradeStore`) | - | Active slots | (composite) | P1 |
| `StarterKitService` | ⚠️ TODO | - | - | Static config | (none) | P3 |
| `VendorService` | ⚠️ TODO | `vendor_transactions` | Active stock | Active sessions | `TradeStore` | P2 |
| `ScreenshotService` | ⚠️ TODO | - | - | PNG file on disk | (filesystem) | P3 |

---

## 3. Schema Requirements

> **LOCKED 2026-09-07.** Sections 3.1–3.2 (`accounts`, `sessions`,
> `characters`) are frozen for the first migration
> `V20260907_001__init_accounts.sql`. The SQL mirrors these tables
> exactly (columns, types, indexes, CHECK constraints). No further
> edits to 3.1–3.2 without a NEW migration + this lock note being
> updated. §3.3 (`inventories`/`equipment`) stays open for migration
> 002 (InventoryService vertical slice).

### 3.1 Accounts & Authentication

```
Table: accounts
- id: UUID (PK)
- username: VARCHAR(32) UNIQUE
- email: VARCHAR(255) UNIQUE
- password_hash: VARCHAR(255)
- created_at: TIMESTAMP
- last_login: TIMESTAMP
- status: ENUM('active', 'banned', 'suspended')
- ban_reason: TEXT (nullable)
```

```
Table: sessions
- id: UUID (PK)
- account_id: UUID (FK → accounts)
- token: VARCHAR(512)
- created_at: TIMESTAMP
- expires_at: TIMESTAMP
- ip_address: VARCHAR(45)
```

### 3.2 Characters

```
Table: characters
- id: UUID (PK)
- account_id: UUID (FK → accounts)
- display_name: VARCHAR(32) UNIQUE
- species_id: VARCHAR(32)
- class_id: VARCHAR(32)
- level: INT DEFAULT 1
- experience: INT DEFAULT 0
- gold: BIGINT DEFAULT 0
- health: INT
- mana: INT
- position_x: FLOAT
- position_y: FLOAT
- position_z: FLOAT
- zone_id: VARCHAR(64)
- faction_id: VARCHAR(64)
- created_at: TIMESTAMP
- last_online: TIMESTAMP
- deleted_at: TIMESTAMP (soft delete)
```

### 3.3 Inventory & Items

```
Table: inventories
- id: UUID (PK)
- character_id: UUID (FK → characters)
- slot_index: INT
- item_id: VARCHAR(64)
- quantity: INT DEFAULT 1
- bound: BOOLEAN DEFAULT FALSE
- created_at: TIMESTAMP

Table: equipment
- id: UUID (PK)
- character_id: UUID (FK → characters)
- equip_slot: INT
- item_id: VARCHAR(64)
- item_data: JSONB (full item state)
- bound: BOOLEAN DEFAULT FALSE
```

### 3.4 Quests

```
Table: quests
- id: VARCHAR(64) (PK, quest template ID)
- title: VARCHAR(128)
- description: TEXT
- objectives: JSONB
- rewards: JSONB
- min_level: INT
- faction_required: VARCHAR(64)

Table: quest_progress
- id: UUID (PK)
- character_id: UUID (FK → characters)
- quest_id: VARCHAR(64) (FK → quests)
- status: ENUM('active', 'completed', 'failed', 'rewarded')
- objectives_progress: JSONB
- started_at: TIMESTAMP
- completed_at: TIMESTAMP (nullable)
```

### 3.5 Vaults (Bank)

```
Table: vaults
- id: UUID (PK)
- character_id: UUID (FK → characters)
- vault_type: ENUM('personal', 'guild', 'account')
- slot_index: INT
- item_id: VARCHAR(64)
- quantity: INT
- updated_at: TIMESTAMP

Table: guild_vaults
- id: UUID (PK)
- guild_id: UUID (FK → guilds)
- (same slots as personal vault)

Table: account_vaults
- id: UUID (PK)
- account_id: UUID (FK → accounts)
- (shared across all characters on account)
```

### 3.6 Guilds

```
Table: guilds
- id: UUID (PK)
- name: VARCHAR(64) UNIQUE
- leader_id: UUID (FK → characters)
- created_at: TIMESTAMP
- motd: TEXT
- emblem: VARCHAR(256)

Table: guild_members
- id: UUID (PK)
- guild_id: UUID (FK → guilds)
- character_id: UUID (FK → characters)
- rank: INT
- joined_at: TIMESTAMP

Table: guild_ranks
- id: UUID (PK)
- guild_id: UUID (FK → guilds)
- rank_index: INT
- name: VARCHAR(32)
- permissions: JSONB
```

### 3.7 Friends & Social

```
Table: friends
- id: UUID (PK)
- character_id: UUID (FK → characters)
- friend_id: UUID (FK → characters)
- status: ENUM('pending', 'accepted', 'blocked')
- created_at: TIMESTAMP

Table: blocks
- id: UUID (PK)
- character_id: UUID (FK → characters)
- blocked_id: UUID (FK → characters)
- created_at: TIMESTAMP
```

### 3.8 Waypoints

```
Table: player_waypoints
- id: VARCHAR(64) (PK, format: wp_<timestamp>_<random>)
- character_id: UUID (FK → characters)
- name: VARCHAR(32)
- position_x: FLOAT
- position_y: FLOAT
- position_z: FLOAT
- zone_id: VARCHAR(64)
- color: INT (0-7: red, orange, yellow, green, blue, purple, pink, white)
- icon: INT (0-9: flag, star, chest, skull, house, cave, quest, player, compass, custom)
- is_visible: BOOLEAN DEFAULT TRUE
- is_locked: BOOLEAN DEFAULT FALSE
- show_beacon: BOOLEAN DEFAULT TRUE
- is_quest_waypoint: BOOLEAN DEFAULT FALSE
- quest_id: VARCHAR(64) (nullable, FK → quests)
- created_at: TIMESTAMP
- updated_at: TIMESTAMP

Indexes:
- UNIQUE (character_id, id)
- INDEX (character_id) — for loading player waypoints
- INDEX (quest_id) WHERE quest_id IS NOT NULL — for cleanup
```

Note: Quest waypoints are created/deleted dynamically and don't need persistence.
Player-created waypoints persist and are loaded on character login.

---

### 3.10 Respawn Points (Ankhs)

```sql
CREATE TABLE respawn_points (
    id              TEXT PRIMARY KEY,
    zone_id         TEXT NOT NULL REFERENCES zones(id),
    name            TEXT NOT NULL,
    position        VECTOR3 NOT NULL,
    faction_id      TEXT REFERENCES factions(id),
    bind_cost       INTEGER DEFAULT 0,
    cooldowns       JSONB DEFAULT '{}',
    enabled         BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_respawn_zone ON respawn_points(zone_id);
CREATE INDEX idx_respawn_faction ON respawn_points(faction_id) WHERE faction_id IS NOT NULL;
```

Mirrors `ankh.gd` (27 exports). Backing store: `RespawnStore`.
Hot reads go through Redis cache (player death to nearest ankh).

### 3.11 Dialogues

```sql
CREATE TABLE dialogues (
    id              TEXT PRIMARY KEY,
    npc_id          TEXT NOT NULL,
    root_node_id    INTEGER NOT NULL,
    nodes           JSONB NOT NULL,
    version         INTEGER NOT NULL DEFAULT 1,
    enabled         BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);
```

Templates in Postgres. Per-player state (current node, flags)
in `DialogueStateStore` (in-memory, per-session). Source:
`data/dialogues/*.tres` via `dialogue_data.gd`.

### 3.12 NPC Offerings (Vendor Stock)

```sql
CREATE TABLE npc_offerings (
    id              TEXT PRIMARY KEY,
    npc_id          TEXT NOT NULL,
    item_template_id TEXT NOT NULL,
    stock           INTEGER,
    restock_trigger TEXT,
    buy_price_mult  REAL DEFAULT 1.0,
    sell_price_mult REAL DEFAULT 1.0,
    enabled         BOOLEAN DEFAULT TRUE
);
```

Templates in `GameDataStore` (mirrors `data/npc_offerings/*.tres`).
Per-vendor current stock in `VendorStore` (Redis).

### 3.13 Container Configs

```sql
CREATE TABLE container_configs (
    id              TEXT PRIMARY KEY,
    base_slots      INTEGER NOT NULL,
    max_slots       INTEGER NOT NULL,
    slot_lock_behavior TEXT,
    enabled         BOOLEAN DEFAULT TRUE
);
```

Loaded from `data/containers/*.tres` via `SlotService`.
Pure reference data.

### 3.14 Target Schemas

```sql
CREATE TABLE target_schemas (
    id              TEXT PRIMARY KEY,
    entity_type     TEXT NOT NULL,
    priority        INTEGER NOT NULL,
    range_max       REAL,
    requires_los    BOOLEAN DEFAULT FALSE,
    enabled         BOOLEAN DEFAULT TRUE
);
```

Loaded from `data/targets/*.tres` via `target_schema.gd`.
Cached in `GameDataStore`.

### 3.15 Species (Races)

```sql
CREATE TABLE species (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    faction_id      TEXT REFERENCES factions(id),
    base_stats      JSONB NOT NULL,
    racial_traits   JSONB DEFAULT '[]',
    enabled         BOOLEAN DEFAULT TRUE
);
```

Loaded from `data/species/*.tres` via `species.gd`.

### 3.16 World Events

```sql
CREATE TABLE world_events (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    event_type      TEXT NOT NULL,
    duration_sec    INTEGER,
    conditions      JSONB DEFAULT '{}',
    effects         JSONB DEFAULT '[]',
    enabled         BOOLEAN DEFAULT TRUE
);

CREATE TABLE world_event_instances (
    instance_id     TEXT PRIMARY KEY,
    template_id     TEXT NOT NULL REFERENCES world_events(id),
    zone_id         TEXT REFERENCES zones(id),
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ends_at         TIMESTAMPTZ,
    state           JSONB DEFAULT '{}'
);
```

Templates in `GameDataStore`; active instances in
`WorldStateStore`. Mirrors `data/events/*.tres` via
`event_data.gd`.

### 3.17 Agent Connectors

```sql
CREATE TABLE agent_connectors (
    id              TEXT PRIMARY KEY,
    connector_type  TEXT NOT NULL,
    config          JSONB NOT NULL,
    permissions     JSONB DEFAULT '[]',
    audit_log       BOOLEAN DEFAULT TRUE,
    enabled         BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE agent_actions (
    id              BIGSERIAL PRIMARY KEY,
    agent_id        TEXT NOT NULL,
    connector_id    TEXT NOT NULL REFERENCES agent_connectors(id),
    action_type     TEXT NOT NULL,
    payload         JSONB NOT NULL,
    response        JSONB,
    approved_by     TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_agent_actions_agent ON agent_actions(agent_id, created_at DESC);
CREATE INDEX idx_agent_actions_type ON agent_actions(action_type);
```

Runtime session state in `ConnectorService._connected_agents`
(in-memory). Durable audit trail in `ConnectorStore` (Postgres).

### 3.18 Player Settings

```sql
CREATE TABLE player_settings (
    account_id      TEXT NOT NULL REFERENCES accounts(id),
    scope           TEXT NOT NULL,
    character_id    TEXT,
    key             TEXT NOT NULL,
    value           JSONB NOT NULL,
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (account_id, scope, character_id, key)
);
```

Replaces `user://*.cfg` files in `player_config.gd` and the
duplicated `user://characters.json` writes in
`character_select.gd` + `lobby.gd`. Backing: `PlayerConfigStore`.

### 3.19 Existing "Persistence" to Migrate

Hand-rolled persistence that predates the adapter layer. To
be replaced when their stores land:

| File | Path | Replaced by |
|------|------|-------------|
| `login_service.gd:24` | `user://accounts.json` | `AccountStore` + `SessionStore` |
| `player_config.gd:24-26` | `user://account_settings.cfg`, `user://settings/char_*.cfg`, `user://global_settings.cfg` | `PlayerConfigStore` |
| `character_select.gd:167` + `lobby.gd:185` | `user://characters.json` (duplicated) | `CharacterStore` |
| `chat_service.gd:194-213` + `game_config.gd:221` | `user://config/profanity_words.txt` | `GameDataStore` |
| `logger.gd:18` | `user://logs/game.log` | Stay on disk (not adapter-layer) |

### 3.20 Reference Data Inventory (`data/*.tres`)

`game/data/` has 26 subdirs containing ~200 `.tres` files
across 18 schemas. These are the source of truth that get
seeded into `GameDataStore` at boot:

- achievements (8) / titles (9) / skills (8) / classes (22)
- armors (1) / weapons (2) / consumables (2) / resources (1) / misc (1)
- buffs (1) / status_effects (62)
- containers (3) / dialogues (2) / dwellings (2) / enemies (5) / events (1)
- factions (4) / gateways (3) / loot_tables (3) / npc (2) / npcs (9)
- npc_offerings (9) / quests (4) / species (3) / targets (6) / zones (4)

Schemas average 20-50 `@export` fields each. Migration plan:
one-shot `data/.tres -> Postgres` loader that uses
`ResourceSaver` to read each .tres and `INSERT ... ON CONFLICT
DO UPDATE` into the appropriate table. Idempotent, safe to
re-run.

---

## 4. TODO Items (by service)

### QuestService
- [ ] `load_quests()` — Load character quests from DB
- [ ] `_sync_quests_to_db()` — Persist quest progress
- [ ] `accept_quest()` — Insert to quest_progress
- [ ] `complete_quest()` — Update status + timestamp

### VaultService
- [ ] `_sync_vault()` — Persist vault changes
- [ ] `load_personal_vault()` — Load on character login
- [ ] `load_guild_vault()` — Load guild vault (with permission check)
- [ ] `load_account_vault()` — Load shared account vault

### ServerManager
- [ ] Wire disconnect handling to DB (mark offline)
- [ ] `on_player_disconnect()` — Persist position, inventory state

### InventoryService
- [ ] `save_inventory()` — Periodic saves
- [ ] `load_inventory()` — On player login
- [ ] Transaction handling for item moves

### SameAccountTransferService
- [ ] Persist transfer history for cooldown tracking
- [ ] Cross-character item migration tracking

### PlayerManager
- [ ] Save character position on zone change
- [ ] Save character stats on level up
- [ ] Character deletion (soft delete)

### WaypointService
- [ ] `save_waypoints()` — Persist player waypoints to DB
- [ ] `load_waypoints()` — Load on character login
- [ ] `delete_waypoint()` — Remove from DB
- [ ] `update_waypoint()` — Update in DB
- [ ] Quest cleanup: Remove waypoints when quest is abandoned
- [ ] Sync on character logout/disconnect

---

## 4b. Redis Cache Schema

Per world-building.md §12:
- **Tick cache:** Current game state for fast reads
- **Materialized intersections:** `(vertex, faction, time_bucket)` entries
- **Session state:** Online players, active connections
- **Spatial index:** NSC-9 + icosahedral geo-cache

```
# Redis Key Patterns

# Session & Auth
session:{account_id} → {token, expires_at, server_id}
online_player:{character_id} → {server_id, shard_id, zone_id}

# Spatial (Geo-cache per world-building.md)
geo:nsc9:{cell_x}:{cell_y}:{cell_z} → [entity_ids]
geo:zone:{zone_id} → {lat_min, lon_min, lat_max, lon_max}

# Tick cache
tick:{shard_id}:{tick_num} → {state_hash, timestamp}

# Materialized intersections (faction conflicts)
intersection:{vertex_id}:{faction_a}:{faction_b} → {time_bucket, intensity}

# Rate limiting
ratelimit:{player_id}:{action} → {count, window_start}

# Cooldown cache
cooldown:{player_id}:{action} → {expires_at}
```

### Redis TTL Strategy
- Session tokens: 24h (with refresh)
- Online status: Immediate expiry on disconnect
- Tick cache: 1-5 min (circular buffer)
- Rate limits: Action-specific window
- Geo-cache: 10 min with background refresh

### Caching Layer
- Redis for session data, online status, cooldowns
- LRU cache for frequently accessed data (guild rosters, quest definitions)

### Event Sourcing
- Consider event sourcing for inventory/transaction history
- Enables rollback, audit trails, fraud detection

### Migration Strategy
- All schema changes require migrations
- Use versioned migrations (like Flyway/Liquibase)
- Never delete columns in production (deprecate and hide)

---

## 5. Adapter Layer Architecture

**The problem.** This PRD lists 45+ services that need DB /
cache / memory access. If each service rolls its own
Postgres / Redis / dict calls, we get 45+ different
connection pools, 45+ error-handling strategies, and 45+
things to change when we swap a backend.

**The solution.** One place to put these calls. Every service
depends on a **Store** (a typed interface). The Store is
backed by an **adapter** that talks to Postgres / Redis /
memory. Adding a new backend = adding one adapter file.
Swapping a backend for tests = registering a different
adapter in dev mode. Services never know which backend
they're on.

**Terminology.**

- **Layer** = which *kind* of storage (persistence, cache,
  memory). See §5.3.
- **Store** = the typed service-facing interface. Services
  hold a `Store` reference; they never hold a `Postgres` or
  `Redis` reference.
- **Adapter** = the concrete implementation that talks to a
  specific backend (e.g., `PostgresPersistenceStore`,
  `RedisCacheStore`).
- **Registry** = the autoload that maps store names to
  adapters. See §5.2.
- **Transport** = the *mechanism* Godot uses to talk to the
  backend. Three options, see §10. (This is NOT the same
  as "what language/backend"; you can have HTTP transport
  to Postgres, GDExtension transport to Postgres, etc.)

### 5.1 Directory layout

```
game/adapters/
  persistence/                  # durable (Postgres now, ClickHouse later)
    persistence_store.gd        # base interface
    postgres_store.gd           # HTTP-to-Postgres via pg-bridge sidecar
    memory_persistence_store.gd # in-memory (tests + dev)
  cache/                        # fast KV (Redis now, Memcached later)
    cache_store.gd              # base interface
    redis_store.gd              # HTTP-to-Redis via redis-bridge sidecar
    memory_cache_store.gd
  memory_layer/                 # process-local runtime state
    memory_store.gd             # thin wrapper over Godot Dict/Array
  migrations/                   # versioned SQL, applied at boot
    V<YYYYMMDD>_<seq>__<name>.sql
    _seed/                      # idempotent reference data
  registry.gd                   # autoload, name -> adapter lookup

# Tests live alongside the rest of the project's tests:
game/tests/
  adapters/                     # adapter-layer tests
    test_persistence_store.gd
    test_cache_store.gd
    test_memory_store.gd
  test_login_flow.gd
  ...
```

The directory lives at `game/adapters/` so it's part of the
Godot project (resolved by `res://`). The base interfaces
live at the top level of each subdir; concrete backends in
their own subdir.

### 5.2 Registration

Services don't `new()` adapters. They resolve through a
registry, like the existing service singletons:

```gdscript
# game/adapters/registry.gd (singleton)
extends Node

var _persistence: Dictionary = {}  # name -> PersistenceStore
var _cache: Dictionary = {}        # name -> CacheStore
var _memory: Dictionary = {}       # name -> MemoryStore

func register_persistence(name: String, store: PersistenceStore) -> void
func get_persistence(name: String) -> PersistenceStore

func register_cache(name: String, store: CacheStore) -> void
func get_cache(name: String) -> CacheStore

func register_memory(name: String, store: MemoryStore) -> void
func get_memory(name: String) -> MemoryStore
```

Boot sequence:

1. `AdapterRegistry` autoload instantiates
2. Env-driven backend selection reads `STORAGE_BACKEND`,
   `CACHE_BACKEND` (defaults: `postgres`, `redis`)
3. For each registered store name in the boot manifest, the
   corresponding backend is instantiated and registered
4. Services can then call `AdapterRegistry.get_persistence("accounts")`
   and get whichever backend is live

### 5.3 Why three layers, not one

- **Persistence** = durable, ACID, queries. Use for anything
  that survives a restart: accounts, characters, inventory,
  guilds, audit logs, world snapshots.
- **Cache** = fast KV, TTL, pub/sub. Use for ephemeral
  state with bounded lifetime: sessions, online status,
  cooldowns, rate limits, materialized intersections.
- **Memory** = process-local, no cross-process. Use for
  transient runtime state that doesn't need durability:
  active cooldowns in this tick, current frame's AOI set,
  follow targets. Already Godot's `Dictionary`, wrapped
  so the interface matches.

Some data lives in **two layers**: the durable source of
truth in Postgres, a hot copy in Redis (with TTL), and a
process-local copy in memory. The convention is: **write
through the persistence adapter**, **read from cache or
memory**, **invalidate the cache when persistence changes**.
This is the "read = lookup, write = command" pattern from
`world-building.md` §1.4.

---

## 6. Adapter Contracts

### 6.1 `PersistenceStore` (base interface)

Every store that talks to a durable backend implements this.
Backends (Postgres, SQLite, in-memory) provide their own
impl. Services depend on the interface only.

```gdscript
# game/adapters/persistence/persistence_store.gd
class_name PersistenceStore
extends RefCounted

# --- Connection lifecycle ---

func connect(config: Dictionary) -> int            # returns 0 on ok
func close() -> void
func healthy() -> bool                             # cheap health check

# --- Query API ---

# Parameterized query. Returns Array[Dictionary].
# Each row is a Dict keyed by column name.
func query(sql: String, params: Array = []) -> Array

# Single-row convenience. Returns Dictionary or null.
func query_one(sql: String, params: Array = []) -> Dictionary

# Execute (INSERT / UPDATE / DELETE). Returns rows affected.
func execute(sql: String, params: Array = []) -> int

# --- Transactions ---

func begin() -> int                                 # returns tx id
func commit(tx_id: int) -> int                      # 0 on ok
func rollback(tx_id: int) -> int                    # 0 on ok

# --- Bulk / streaming ---

func insert_many(table: String, rows: Array, columns: Array) -> int
func execute_batch(statements: Array) -> int       # multi-statement script
```

### 6.2 `CacheStore` (base interface)

```gdscript
# game/adapters/cache/cache_store.gd
class_name CacheStore
extends RefCounted

func connect(config: Dictionary) -> int
func close() -> void
func healthy() -> bool

# --- Basic KV ---

func get(key: String) -> Variant                    # null if missing
func set(key: String, value: Variant, ttl_sec: int = 0) -> int
func set_nx(key: String, value: Variant, ttl_sec: int = 0) -> bool
func delete(key: String) -> int                     # 1 if deleted, 0 if absent
func exists(key: String) -> bool
func expire(key: String, ttl_sec: int) -> int       # 0 = no TTL change, -1 = missing

# --- Atomic counters / rate limits ---

func incr(key: String) -> int                       # creates at 0 if missing
func incr_by(key: String, by: int) -> int
func incr_with_ttl(key: String, ttl_sec: int) -> int  # create + TTL in one call

# --- Hashes (per-object fields) ---

func hset(key: String, field: String, value: Variant) -> int
func hget(key: String, field: String) -> Variant
func hget_all(key: String) -> Dictionary
func hdel(key: String, field: String) -> int

# --- Sets (collections) ---

func sadd(key: String, member: String) -> int
func srem(key: String, member: String) -> int
func smembers(key: String) -> Array
func sismember(key: String, member: String) -> bool

# --- Lists (queues / recent-N) ---

func lpush(key: String, value: Variant) -> int
func rpush(key: String, value: Variant) -> int
func lpop(key: String) -> Variant
func lrange(key: String, start: int, stop: int) -> Array
func llen(key: String) -> int

# --- Pub/sub (for EventHub, anti-cheat fan-out) ---

func publish(channel: String, message: Variant) -> int
# (subscription handled by a separate subscriber; not all
# backends support this, see §7.3)

# --- Lua / script execution (atomic multi-op) ---

func eval(script: String, keys: Array, args: Array) -> Variant
```

### 6.3 `MemoryStore` (base interface)

```gdscript
# game/adapters/memory_layer/memory_store.gd
class_name MemoryStore
extends RefCounted

# Thin wrapper over Godot's Dictionary. Provides the same
# interface shape as CacheStore (without TTL; TTL is
# enforced by the caller or by the next-tick GC pass).

func get(key: String) -> Variant
func set(key: String, value: Variant) -> void
func delete(key: String) -> int
func exists(key: String) -> bool

# Plus hash / set / list subset that matters for runtime:
func hset(key: String, field: String, value: Variant) -> int
func hget(key: String, field: String) -> Variant
func sadd(key: String, member: String) -> int
func smembers(key: String) -> Array
```

Memory stores are intentionally minimal. Anything that needs
TTL or cross-process state belongs in cache.

---

## 7. Backend Implementations

### 7.1 Postgres (`postgres_store.gd`)

The Postgres impl talks to a **sidecar HTTP service**, not
directly to Postgres. Godot has no native Postgres client
in stock 4.7.2, and shelling out to `psql` per query is a
non-starter for production latency.

The sidecar is one of (decided later, see §10):

- A thin Go / Rust / Julia HTTP-to-Postgres bridge (e.g.,
  PostgREST, our own Julia service extending `MultiIsoService`)
- A GDExtension C++ binding against `libpq`

For v1, assume the sidecar is a small `pg-bridge` service
that exposes:

```
POST /query        { sql, params }  -> { rows: [...] }
POST /execute      { sql, params }  -> { affected: N }
POST /tx/begin                       -> { tx_id }
POST /tx/commit    { tx_id }         -> { ok }
POST /tx/rollback  { tx_id }         -> { ok }
POST /insert_many  { table, rows }   -> { affected: N }
GET  /health                         -> { ok, version }
```

Config (from `.env`):

```
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=synmergia
POSTGRES_USER=synmergia
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
PG_BRIDGE_URL=http://pg-bridge:8080
```

Connection pool: the adapter holds N HTTP clients
(HTTPRequest with `request_id` correlation). Default N=8.
Pool sizing is per-process.

### 7.2 Redis (`redis_store.gd`)

Same shape: talk to a sidecar that exposes Redis
operations. `redis_store.gd` mirrors `cache_store.gd`
1-to-1.

```
GET  /get?key=...            -> value
POST /set                    { key, value, ttl }
POST /incr                   { key, by }
POST /hset                   { key, field, value }
POST /publish                { channel, message }
POST /eval                   { script, keys, args }
GET  /health                 -> { ok, version }
```

Pub/sub: subscribe path is a long-lived WebSocket / SSE
connection. The adapter spawns one subscriber goroutine
per channel group (max N concurrent groups).

Config (from `.env`):

```
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_DB=0
REDIS_BRIDGE_URL=http://redis-bridge:8080
```

### 7.3 In-memory (`memory_persistence_store.gd`, `memory_cache_store.gd`)

Implement the interfaces using Godot's `Dictionary` and
`Array`. Used in three cases:

1. **Tests** — no Postgres / Redis container needed; the
   in-memory adapter makes tests fast and deterministic.
2. **Dev / offline mode** — `LoginService` currently writes
   to `user://accounts.json`; the in-memory adapter is the
   migration target so the same code path works on- and
   offline.
3. **First-boot** — before Postgres is reachable, the
   registry can boot with memory adapters and log a warning
   that data won't persist across restart.

`memory_persistence_store.gd` simulates the query API by
maintaining tables as `Dictionary[String, Array]`. For v1
it supports a useful subset (SELECT/INSERT/UPDATE/DELETE
on a single table, WHERE on equality). Don't try to make
it a full SQL engine, it's a stub for tests.

### 7.4 Backends we may add later

| Backend | When | Why |
|---------|------|-----|
| ClickHouse | Phase 6+ | Analytics (player behavior, economy trends). Cheaper than Postgres for OLAP. |
| Memcached | If Redis is overkill | When we don't need pub/sub or hashes. |
| S3 | Phase 5+ | World snapshots, manifests. Currently in `prd-manifest-backup.md`. |
| NATS / Kafka | If we add cross-service events | Replaces Redis pub/sub for fan-out. |
| **Connectors (MCP / Vant / Webhook)** | Parallel track | Live in `game/connectors/` today. Not adapter-layer (no DB/cache needs) but have heavy config + audit. See §11 question. |

Adding any of these is a new file under `game/adapters/`
(or `game/connectors/`) plus a registration entry. No
service changes.

---

## 8. Service to Store Wiring

This is the concrete map from §2's services to the named
stores. Each row says: which store the service uses, and
which backend is the live one. The "Backend" column is
default; overrideable via env at boot.

| Store | Used by | Backend (default) | Notes |
|-------|---------|-------------------|-------|
| `AccountStore` | `AccountService` | Postgres | Durable accounts. |
| `SessionStore` | `LoginService`, `AccountService` | Redis | Tokens + 24h TTL. |
| `CharacterStore` | `PlayerManager` | Postgres | Positions, stats. |
| `InventoryStore` | `InventoryService` | Postgres + Redis cache | Hot path = Redis, durable = Postgres. |
| `QuestStore` | `QuestService` | Postgres + memory cache | Active quests in memory for fast ticks. |
| `VaultStore` | `VaultService` | Postgres | Vaults rarely read; no cache. |
| `GuildStore` | `GuildService` | Postgres + Redis cache | Roster hot; definitions cold. |
| `FriendsStore` | `FriendsService` | Postgres + Redis cache | Online status in Redis. |
| `PartyStore` | `PartyService` | Postgres + memory cache | Active party in memory; roster in PG. |
| `LootStore` | `LootService` | Postgres + Redis cache | History in PG; active loot in memory. |
| `LootTableStore` | `LootService` | Postgres + Redis cache | Templates; rare writes. |
| `ChatStore` | `ChatService` | Postgres (optional) | TBD per §11. |
| `GovernanceStore` | `CommunityGovernance` | Postgres + Redis cache | Active votes in cache. |
| `FactionStore` | `FactionManager` | Postgres + Redis cache | Relations cached. |
| `WaypointStore` | `WaypointService` | Postgres | Personal; no cross-player reads. |
| `ZoneStore` | `ZoneManager` | Memory + Redis cache | Definitions cached. |
| `SpawnStore` | `SpawnService` | Postgres + Redis cache | Templates + timers. |
| `CooldownStore` | `CooldownService` | Redis + memory | Hot path = memory; durable = Redis. |
| `TradeStore` | `TradeService` | Postgres | Trade history. |
| `CraftingStore` | `BlacksmithService` | Postgres + Redis cache | Recipes cached. |
| `SkillStore` | `SkillAcademyService` | Postgres + Redis cache | Tree cached. |
| `AchievementStore` | `AchievementService` | Postgres + Redis cache | Definitions cached. |
| `TitleStore` | `TitleService` | Postgres + Redis cache | Definitions cached. |
| `SecurityStore` | `SecurityService` | Postgres | Bans, mutes, security_log. |
| `AntiCheatStore` | `AntiCheatService` | Postgres + memory | Active flags in memory. |
| `ResponseStore` | `AutoResponseService` | Postgres + Redis cache | Templates cached. |
| `TransferStore` | `SameAccountTransferService` | Postgres | History. |
| `RespawnStore` | `RespawnService` | Postgres + Redis cache | Respawn points + active revives. |
| `DeathLogStore` | `DeathFeatures` | Postgres | Append-only. |
| `MetricsStore` | `FairnessService` | Postgres + ClickHouse (future) | Rollups. |
| `EntityStore` | `EntityService` | Postgres + Redis cache | NPC persistence + entity cache. |
| `WorldStateStore` | `WorldService` | Postgres + Redis cache | Tick cache. |
| `ShardStore` | `ShardManager` | Postgres + Redis cache | Shard status. |
| `ServerStore` | `ServerManager` | Postgres + Redis cache | Server status. |
| `GameDataStore` | `DataService` | Postgres + Redis cache | Templates hot. Reference data inventory in §3.20. |
| `MatchmakingStore` | `MatchmakingQoS` | Postgres + Redis cache | Queue state in Redis. |
| `DialogueStateStore` | `DialogService` | Memory only | Per-session node pointer. Templates in `GameDataStore`. |
| `ConnectorStore` | `ConnectorService` | Postgres | Connector config + agent action audit log. |
| `PlayerConfigStore` | `PlayerConfig` | Postgres + Redis cache | Replaces `user://*.cfg` + `user://characters.json` files. |
| `VendorStore` | `VendorService` | Redis + memory | Active stock per NPC. Restock triggers in config. |
| `WorldEventStore` | `WorldService` | Postgres + Redis cache | Active instances cached. Templates in `GameDataStore`. |

Composite / non-store services (not adapter-layer):

- `EventHub` uses **cache only** (Redis pub/sub). No
  durable requirement for events.
- `NotificationService` has **no adapter**, it's pure
  runtime state already.
- `PlayerLockService` is **in-memory only** (`MemoryStore`).
- `StarterKitService` uses **static consts**, no store.
- `ScreenshotService` writes to **filesystem**, not adapter.
- `SlotService` is a **composite** of `InventoryStore`,
  `VaultStore`, and `TradeStore`. No own adapter.

---

## 9. Migrations

### 9.1 Layout

```
game/adapters/migrations/
  V<YYYYMMDD>_<seq>__<name>.sql
  _seed/                        # idempotent seeds (zones, items)
    zones.sql
    items.sql
```

Filename format: `V<YYYYMMDD>_<seq>__<name>.sql`. The
underscore-double-underscore separator matches Flyway /
Liquibase convention so existing tooling recognizes it.

### 9.2 Application

At server boot, the migration runner:

1. Reads all `V*.sql` files in order
2. Connects to Postgres via the `PersistenceStore`
3. Creates `schema_migrations(version, applied_at)` if absent
4. Applies any version not in the table, in order
5. Each migration runs in a transaction; failure rolls back

Migrations are **blocking at boot**. If a migration fails,
the server doesn't start. This is intentional, running on
a stale schema is worse than refusing to boot. (Override
flag `MIGRATIONS_SKIP=1` exists for dev.)

**Hold per user note 2026-09-07:** first migration is
deferred until the schemas in §3 are locked. We're not
writing `V20260907_001__init.sql` yet.

### 9.3 Versioning rules

- New migrations are **append-only**. Never edit a
  migration that's been applied to any environment.
- Deprecate columns, don't drop them. (`ALTER TABLE ... ADD
  COLUMN deprecated_at TIMESTAMP NULL`)
- Rename: add new column, dual-write for a release,
  migrate readers, then drop old.
- Long-running migrations (>10s expected) need to be split
  or run async with a feature flag.

### 9.4 Seeds

`_seed/` holds idempotent reference data: zones, item
templates, NPC definitions, skill definitions. Re-runnable
on every boot. Uses `INSERT ... ON CONFLICT DO UPDATE`
(Postgres upsert).

The `data/*.tres` -> Postgres loader (mentioned in §3.20)
lives here too: one-shot, idempotent, re-runnable.

---

## 10. Transport Mechanism: Godot to Backend

**Scope of this section.** "Transport" here means the
*mechanism* the Godot process uses to reach a backend. It
is NOT about which language the backend is written in, NOR
about which backend (Postgres, Redis, etc.) you're talking
to. The same Godot code can use the same transport to
reach any backend that exposes the right wire protocol.

For example: HTTP sidecar is a transport; it can carry
Postgres queries OR Redis commands. GDExtension is a
transport; in theory it could carry either. The choice
of transport is independent of the choice of backend.

**Status:** Decision needed before Postgres adapter ships.

Stock Godot 4.7.2 has no native Postgres or Redis client.
Three options:

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **HTTP sidecar** | Reuses existing `MultiIsoService` pattern; trivial to deploy; one language per backend. | Adds latency hop; another service to operate. | **Default for v1.** Same pattern as the Julia orchestrator. |
| **GDExtension (C++)** | Zero hop latency; in-process. | Heavy build pipeline; pinned to one Godot version; C++ maintenance cost. | Phase 4+ if perf demands. |
| **`OS.execute` shell out** | Zero code. | Terrible latency; subprocess overhead; unmanageable under load. | Rejected. |

### 10.1 Default: HTTP sidecars

- `pg-bridge`: ~200-line Go or Rust service. Exposes the
  endpoints in §7.1. Lives in `srv/pg-bridge/`.
- `redis-bridge`: similar. Lives in `srv/redis-bridge/`.
  Pub/sub via SSE / WebSocket.

Both run in the docker-compose alongside Postgres / Redis.
Both have health endpoints, Prometheus metrics, and graceful
shutdown.

### 10.2 Migration path

If perf demands in-process:

1. Profile the HTTP hop with a real load test (Phase 4+)
2. If hot enough to matter, swap to GDExtension
3. The adapter interface doesn't change, only the backend
   implementation

This is the "future-proof" promise of the adapter layer:
backend swap is a one-file change.

### 10.3 What is *not* transport

These often get conflated with transport but they're a
different concern:

- **Connector choice** (MCP / Vant / Webhook): these are
  outbound calls to *external* services, not backends.
  Live in `game/connectors/`. See §7.4 and §11.
- **MultiIsoService**: HTTP to the Julia orchestrator.
  Same HTTP transport pattern, but the Julia service is
  the *application server* (multi-iso coordinator), not a
  database.

---

## 11. Open Questions

- [ ] Do we need full chat log persistence for moderation?
- [ ] Should we store loot history for RNG verification?
- [ ] Player housing data (furniture, placement)?
- [ ] Achievement progress persistence?
- [ ] Cross-server character transfer support?
- [ ] Position storage format: Vector3 or lat/lon?
- [ ] Spherical world: Coordinate conversion implementation
- [ ] Godot to backend transport mechanism (HTTP sidecar vs GDExtension) — see §10
- [ ] Connectors (MCP / Vant / Webhook) — own adapter family or part of `game/adapters/`?
      Current: live in `game/connectors/`, no DB/cache needs but a lot of config + audit. See §7.4.
- [ ] Adapter registration timing (eager at boot vs lazy on first use)
- [ ] First migration is held until schemas in §3 are locked (per user 2026-09-07)

- [ ] Do we need full chat log persistence for moderation?
- [ ] Should we store loot history for RNG verification?
- [ ] Player housing data (furniture, placement)?
- [ ] Achievement progress persistence?
- [ ] Cross-server character transfer support?
- [ ] Position storage format: Vector3 or lat/lon?
- [ ] Spherical world: Coordinate conversion implementation
