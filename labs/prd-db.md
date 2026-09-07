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

| Service | Status | Postgres | Redis | In-Memory | Priority |
|---------|--------|---------|-------|-----------|----------|
| `AccountService` | ⚠️ TODO | `accounts`, `sessions` | Session tokens | - | P0 |
| `LoginService` | ⚠️ TODO | `accounts`, `sessions` | Session cache | - | P0 |
| `PlayerManager` | ⚠️ TODO | `characters` | Online status | - | P0 |
| `InventoryService` | ⚠️ TODO | `inventories`, `equipment` | Item cache | - | P0 |
| `QuestService` | ⚠️ TODO | `quests`, `quest_progress` | Quest cache | Active quests | P1 |
| `VaultService` | ⚠️ TODO | `vaults`, `guild_vaults`, `account_vaults` | Vault cache | - | P1 |
| `GuildService` | ⚠️ TODO | `guilds`, `guild_members`, `guild_ranks` | Guild roster | - | P1 |
| `FriendsService` | ⚠️ TODO | `friends`, `blocks` | Online status | - | P2 |
| `PartyService` | ⚠️ TODO | `parties` | Party state | Active parties | P2 |
| `LootService` | ⚠️ TODO | `loot_history` | Loot table cache | Active loot | P2 |
| `ChatService` | ⚠️ TODO | `chat_log` (optional) | - | - | P3 |
| `CommunityGovernance` | ⚠️ TODO | `votes`, `proposals` | Active votes | - | P2 |
| `FactionManager` | ⚠️ TODO | `factions`, `faction_relations` | Relations cache | Active wars | P2 |
| `FollowService` | ✅ Done | - | - | Runtime only | P3 |
| `WaypointService` | ⚠️ TODO | `player_waypoints` | - | Active waypoints | P2 |
| `ZoneManager` | ⚠️ TODO | `zones` | Zone cache | Active zone | P1 |
| `SpawnService` | ⚠️ TODO | `spawn_definitions` | Spawn timers | - | P2 |
| `CooldownService` | ✅ Runtime | - | Cooldown cache | Active cooldowns | P3 |
| `NotificationService` | ✅ Runtime | - | - | Notifications | P3 |
| `TradeService` | ⚠️ TODO | `trade_history` | Active trades | - | P2 |
| `BlacksmithService` | ⚠️ TODO | `crafting_recipes`, `crafting_history` | Recipe cache | - | P2 |
| `SkillAcademyService` | ⚠️ TODO | `skills`, `player_skills` | Skill tree cache | - | P1 |
| `AchievementService` | ⚠️ TODO | `achievements`, `player_achievements` | Achievement cache | - | P2 |
| `TitleService` | ⚠️ TODO | `titles`, `player_titles` | Title cache | - | P3 |
| `SecurityService` | ⚠️ TODO | `bans`, `mutes`, `security_log` | - | - | P1 |
| `AntiCheatService` | ⚠️ TODO | `anticheat_events` | - | Active flags | P2 |
| `AutoResponseService` | ⚠️ TODO | `auto_responses` | Response cache | - | P3 |
| `SameAccountTransferService` | ⚠️ TODO | `transfers`, `transfer_history` | Transfer cooldowns | - | P2 |
| `EventHub` | ⚠️ TODO | - | Event subscriptions | - | P3 |
| `RespawnService` | ✅ Runtime | Respawn points | - | - | P2 |
| `DeathFeatures` | ⚠️ TODO | `death_log` | - | - | P3 |
| `LootService` | ⚠️ TODO | `loot_tables`, `drop_rules` | Loot cache | - | P2 |
| `CombatMath` | ✅ Runtime | - | Combat formulas | - | P3 |
| `FairnessService` | ⚠️ TODO | `fairness_metrics` | - | - | P3 |
| `EntityService` | ⚠️ TODO | `entities` (persist NPC/objects) | Entity cache | Active entities | P1 |
| `WorldService` | ⚠️ TODO | `world_state` | Tick cache | - | P1 |
| `ShardManager` | ⚠️ TODO | `shards` | Shard status | Active shards | P1 |
| `ServerManager` | ⚠️ TODO | `servers` | Server status | - | P1 |
| `DataService` | ⚠️ TODO | `game_data` (templates) | Data cache | - | P1 |
| `MatchmakingQoS` | ⚠️ TODO | `matchmaking_queue` | Queue state | Active queue | P2 |

---

## 3. Schema Requirements

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

Per world-building.md �12:
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

## 6. Open Questions

- [ ] Do we need full chat log persistence for moderation?
- [ ] Should we store loot history for RNG verification?
- [ ] Player housing data (furniture, placement)?
- [ ] Achievement progress persistence?
- [ ] Cross-server character transfer support?
- [ ] Position storage format: Vector3 or lat/lon?
- [ ] Spherical world: Coordinate conversion implementation
