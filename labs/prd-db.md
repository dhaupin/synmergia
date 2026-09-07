# Synmergia — Database & Persistence PRD

> **Status:** Draft — 2026-09-06
> **Purpose:** Master list of all database persistence requirements

---

## 1. Overview

This document tracks all data that requires database persistence.
It serves as the source of truth for DB schema design, migration planning,
and implementation tracking.

---

## 2. Services Requiring Persistence

| Service | Status | Tables/Collections | Priority |
|---------|--------|-------------------|----------|
| `AccountService` | ⚠️ TODO | `accounts` | P0 |
| `LoginService` | ⚠️ TODO | `accounts`, `sessions` | P0 |
| `PlayerManager` | ⚠️ TODO | `characters` | P0 |
| `InventoryService` | ⚠️ TODO | `inventories`, `equipment` | P0 |
| `QuestService` | ⚠️ TODO | `quests`, `quest_progress` | P1 |
| `VaultService` | ⚠️ TODO | `vaults`, `guild_vaults`, `account_vaults` | P1 |
| `GuildService` | ⚠️ TODO | `guilds`, `guild_members`, `guild_ranks` | P1 |
| `FriendsService` | ⚠️ TODO | `friends`, `blocks` | P2 |
| `PartyService` | ⚠️ TODO | `parties` | P2 |
| `LootService` | ⚠️ TODO | `loot_history` | P2 |
| `ChatService` | ⚠️ TODO | `chat_log` (optional, for moderation) | P3 |
| `CommunityGovernance` | ⚠️ TODO | `votes`, `proposals` | P2 |

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

---

## 5. Future Considerations

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
