# Synmergia - Development Roadmap

> 3D Open World MMORPG inspired by RYL2 combat and Ultima Online depth
>
> PRD: See [prd-synmergia.md](./prd-synmergia.md) for full design specification

---

## Architecture Overview

**3-Layer Design:**
```
SERVICES (Autoloaded)     - GameService, CombatService, EntityService, EventBus
COMPONENTS (Attached)     - HealthComponent, CombatComponent, AuraComponent, etc.
DATA (Resource Files)     - skills/, items/, enemies/, classes/, species/, factions/, zones/
```

**Extension Pattern:** Drop a new .tres file in data/ folder = new content automatically discoverable.

---

## Vertical Slice Goal

A playable demo with basic combat, one region, one playable class, one species, and working enemy AI.

---

## Phase 0: Architecture Foundation (DOING NOW)

**PRD References:** Section 10 Technical Architecture

### 0.1 Service Layer
**Files:** `godot-project/core/services/`

- [ ] `event_bus.gd` - Global signal hub for decoupled events
- [ ] `data_service.gd` - Resource discovery and loading from data/
- [ ] `entity_service.gd` - Entity registry and management

### 0.2 Data Schemas (Base Classes)
**Files:** `godot-project/core/schemas/`

- [ ] `skill.gd` - Skill schema with effects array
- [ ] `item.gd` - Item schema (consumables, equipment, etc.)
- [ ] `enemy_data.gd` - Enemy template schema
- [ ] `character_class.gd` - Class definition schema
- [ ] `species.gd` - Species schema (NEW - stats, relations)
- [ ] `faction.gd` - Faction schema (NEW - PvP rules, relations)
- [ ] `zone_data.gd` - Zone definition schema

### 0.3 Component Layer
**Files:** `godot-project/core/components/`

- [ ] `health_component.gd` - HP management, death handling
- [ ] `combat_component.gd` - Attack/skill execution
- [ ] `aura_component.gd` - Aura/effect management
- [ ] `aggro_component.gd` - Threat/aggro tracking
- [ ] `inventory_component.gd` - Item management

### 0.4 AI System
**Files:** `godot-project/core/ai/`

- [ ] `enemy_ai.gd` - AI state machine (IDLE, PATROL, CHASE, COMBAT, FLEE, RETURN)

### 0.5 Example Data Files
**Files:** `godot-project/data/`

#### Equipment (data/weapons/, data/armors/, data/accessories/)
- [x] `weapons/wep_iron_sword.tres`
- [x] `weapons/wep_wooden_bow.tres`
- [x] `armors/arm_leather_chest.tres`

#### Consumables (data/consumables/)
- [x] `consumables/potion_health_small.tres`

#### Resources (data/resources/)
- [x] `resources/res_iron_ore.tres`

#### Dwellings (data/dwellings/)
- [x] `dwellings/dwel_wooden_chair.tres`
- [x] `dwellings/dwel_fireplace_stone.tres`

#### Events (data/events/)
- [x] `events/event_double_xp_weekend.tres`

#### Misc (data/misc/)
- [x] `misc/misc_ancient_coin.tres`

#### Core Data (data/skills/, data/enemies/, etc.)
- [x] `skills/skill_basic_attack.tres`
- [x] `enemies/enemy_slime.tres`
- [x] `classes/class_warrior.tres`
- [x] `species/species_human.tres`
- [x] `factions/faction_human.tres`
- [x] `zones/zone_starter_plains.tres`

---

## Phase 1: Core Combat Engine

**PRD References:** Section 3 Combat Systems, Section 3.6 Death & Resurrection

### 1.1 Projectile System [CRITICAL] - FLEXIBLE FOR ALL ENTITIES
**Files:** `godot-project/core/combat/projectile.gd`

#### Core Features
- [x] Base Projectile class with position, velocity, lifetime
- [x] Projectile collision detection (hitbox vs entities)
- [x] Projectile expiration (max range, time, out of bounds)
- [x] Explosion on impact for PROJECTILE_AOE skills
- [x] Visual VFX integration (scene loading)
- [x] Factory methods: create_arrow, create_fireball, create_magic_bolt

#### Owner Classification
- [x] ProjectileOwner enum: PLAYER_ONLY, ENEMY_ONLY, ALL
- [x] Source detection (is player vs enemy)
- [x] Bonus damage vs players/enemies configurable

#### Advanced Projectile Types
- [x] HEAVY_SHOT - Slow, high damage (enemy grunt)
- [x] TRAP - Ground-targeted, triggered by proximity
- [x] BEAM - Instant beam
- [x] RICOCHET - Bounces between targets
- [x] CHAIN - Chains to nearby enemies (chain lightning)
- [x] HEALING_ORB - Homing healing projectile

#### Advanced Mechanics
- [x] Piercing (pass through N targets)
- [x] Homing behavior with trajectory change signal
- [x] Ricochet/bounce counting
- [x] Chain lightning with target tracking
- [x] Trap trigger radius and duration
- [x] Damage falloff from explosion center

### 1.2 Interrupt System [CRITICAL]
**Files:** `godot-project/core/components/combat_component.gd` (update)

- [x] Track channeling/casting skills per entity
- [x] Damage event triggers interrupt check
- [x] `can_interrupt` flag on skills
- [x] Interrupted -> cancel cast, partial resource cost (50%)
- [x] Interrupt resistance stat/buffs
- [x] Channel ticks for DOT-style channeling

### 1.3 Death and Respawn [CRITICAL] - FLEXIBLE SYSTEM
**Files:** `godot-project/core/components/health_component.gd`, `core/services/respawn_service.gd`, `core/schemas/ankh.gd`

#### Ankh System (UO-inspired)
- [x] Ankh schema with multiple types (SHARED, PERSONAL, GUILD, FACTION, NEUTRAL, BLESSED, CURSED, ARENA)
- [x] Ankh sizes (SMALL, MEDIUM, LARGE, COLOSSAL)
- [x] Coverage radius (players in range can bind)
- [x] Activation radius (must be close to activate)
- [x] Respawn modifiers (time multiplier, blessed duration, debuffs)
- [x] Zone/gateway linking
- [x] Level/faction/quest restrictions

#### Respawn Modes
- [x] TIMED - Standard timed respawn
- [x] ANKH - Respawn at bound ankh
- [x] REVIVE - Resurrected by another player
- [x] SELF_REVIVE - Item/spell self-resurrect
- [x] ARENA_TEAM - Arena team respawn with limits
- [x] CONTESTED - Fight for respawn
- [x] GATEWAY - Respawn at zone gateway
- [x] SAFE_ZONE - Safe area with invincibility

#### Revive Mechanics
- [x] Revive cast time (3 seconds)
- [x] Revive range check
- [x] Revive cooldown (30 seconds per healer)
- [x] Karma rewards (10 for friendly, bonus for cross-faction)
- [x] Context-aware abuse detection (varies by zone/mode)
- [x] Progress tracking during revive cast
- [x] Context-specific revive abilities

#### Context-Aware Revive System
**Abuse Thresholds (revives/hour):**
- [x] `open_world`: 30 (PVE forgiving)
- [x] `dungeon`: 20 (normal)
- [x] `raid`: 15 (expected deaths)
- [x] `pvp_zone`: 25 (medium)
- [x] `arena`: 100 (no limit)
- [x] `battleground`: 50 (forgiving)
- [x] `contested`: 10 (very strict)

**Ability Flags per Context:**
- [x] `open_world/dungeon/raid/battleground`: Full revive
- [x] `pvp_zone`: Limited revive others (50/hour)
- [x] `arena`: No self-revive
- [x] `contested`: Can't revive others (fight for res)

**Penalty System:**
- [x] Karma penalty varies by context
- [x] Temporary cooldown when flagged
- [x] Self-revive cooldown per context

#### PVP/Arena Modes
- [x] Limited resurrections per team
- [x] Contested respawn (fight to prevent enemy res)
- [x] Central ankh with safe zone
- [x] Invincibility duration on respawn (configurable)

#### Death State
- [x] Death state (no input, no damage)
- [x] Corpse entity (visual, lootable) - stubbed
- [x] Respawn timer (configurable per zone)
- [x] Respawn location selection (BIND_POINT, NEAR_CORPSE, CUSTOM)

---

## Phase 2: Combat Foundation

**PRD References:** Section 3.4 Stats & Attributes, Section 3.5 Health & Resource Display

### 2.1 Global Cooldown (GCD)
**Files:** `godot-project/core/components/combat_component.gd`

- [x] GCD duration (default 1.0s)
- [x] Skills add to GCD (optional per skill, `uses_gcd` flag)
- [x] GCD prevents skill queue
- [x] Skill queue methods (queue_skill, process_queued_skill)
- [x] `gcd_affects_movement` option

### 2.2 Combat State Tracking
**Files:** `godot-project/core/components/combat_component.gd`

- [x] `in_combat` flag per entity
- [x] Out-of-combat timer (default 10s no damage)
- [x] Mana regen rate changes (combat vs rest multipliers)
- [x] Stamina regen rate changes
- [x] Combat enter/exit signals
- [x] Force exit combat (for zone changes)
- [x] Combat duration tracking

### 2.3 Hit Calculation (Miss/Evade/Block/Dodge)
**Files:** `godot-project/core/services/combat_math.gd`

- [x] Hit chance calculation (level scaling)
- [x] Miss, Evade, Dodge calculations
- [x] Block (partial damage reduction)
- [x] Parry (counter-attack chance)
- [x] Crush (boss bonus vs low level)
- [x] Magic resistance
- [x] Crit avoidance
- [x] Combat rating system (hit, crit, dodge, parry, block ratings)
- [x] `calculate_hit()` and `calculate_magic_hit()` functions

### 2.4 Dispel/Cleanse System
**Files:** `godot-project/core/components/aura_component.gd`, `core/entities/status_effect.gd`

- [x] Effect categories (MAGIC, CURSE, POISON, PHYSICAL, HOLY, SHADOW, FIRE, ICE, LIGHTNING, ARCANE, BLEED, STUN, FEAR, CHARM)
- [x] `dispel_magic()` - dispel magic/curse/poison
- [x] `dispel_curses()` - dispel curses only
- [x] `dispel_poison()` - dispel poison only
- [x] `cleanse()` - removes poison/disease/curse
- [x] `dispel_all()` - removes all dispellable
- [x] Special categories (BLEED, STUN, FEAR, CHARM) need specific dispel
- [x] `is_dispellable` flag on effects
- [x] `dispel_resist_chance` for boss mechanics
- [x] `get_dispel_info()` for UI

---

## Phase 3: World - Species, Factions, Zones

**PRD References:** Section 4 World & Exploration, Section 8 PvP Systems

### 3.1 Species System ✅
**Files:** `synmergia/core/schemas/species.gd`

#### Core Features
- [x] Species schema with stat_modifiers
- [x] allied_species / hostile_species arrays
- [x] Species-faction binding
- [x] home_zone, home_faction defaults
- [x] Stat calculation helpers
- [x] Visual customization options (skin, hair, eyes)

#### Entity Integration
- [x] Add species_id to Entity base class
- [x] Apply species stat modifiers on entity creation
- [ ] Species-based model loading

### 3.2 Faction System ✅
**Files:** `synmergia/core/schemas/faction.gd`, `synmergia/core/services/faction_manager.gd`

#### Core Features
- [x] FactionType: SPECIES, POLITICAL, PvP_RULE, REPUTATION
- [x] PvP rule overrides (PEACEFUL until level, HUNTED always PvP)
- [x] relations dictionary (ALLIED, NEUTRAL, HOSTILE)
- [x] Faction reputation tracking
- [x] `can_pvp_with()`, `can_attack_target()` checks
- [x] Territory control (controlled_zones)

#### FactionManager Service ✅
- [x] FactionManager singleton (autoload)
- [x] Load all factions from data
- [x] War declaration system with cooldowns
- [x] Player reputation tracking
- [x] Guild faction alliances
- [ ] Cross-faction party restrictions

### 3.3 Zone System ✅
**Files:** `synmergia/core/schemas/zone_data.gd`, `synmergia/core/services/zone_manager.gd`

#### Core Features
- [x] Zone PvP modes: SAFE, SPECIES_PVP, FACTION_PVP, FREE_PVP, WARZONE
- [x] Zone entry requirements (level, faction, species)
- [x] Zone bounds (AABB, circular)
- [x] Bind points and spawn points
- [x] `can_enter()`, `can_pvp()`, `contains_position()`

#### ZoneManager Service ✅
- [x] Track active players per zone
- [x] Zone transition handling
- [x] Instance management (dungeons, raids)
- [x] Zone-specific loot/XP multipliers
- [x] Party instance creation/joining

#### Seamless World Support ✅
- [x] Seamless transitions (no loading between zones)
- [x] Zone neighbor registration
- [x] `process_seamless_transitions()` for boundary detection
- [x] Seamless instance support (instances without loading)
- [x] Party-based instance creation

### 3.4 Spawn System ✅
**Files:** `synmergia/core/services/spawn_service.gd`

#### Spawn Point Configuration
- [x] Spawn point schema with:
  - Position (Vector3)
  - Spawn radius
  - Enemy template to spawn
  - Respawn timer (base)
  - Min/max enemies at point

#### Spawn Logic
- [x] Respawn timers per spawn point
- [x] Spawn caps per area/zone
- [x] Spawn proximity checks (not too close to players)
- [x] Dynamic spawn scaling (more enemies during events)
- [ ] Spawn patterns (patrol routes, stationary, random)

#### Spawn Types
- [x] Regular enemies
- [x] Elite/boss spawns
- [x] World bosses
- [x] Event spawns (via spawn_multiplier)

### 3.5 World Service ✅
**Files:** `synmergia/core/services/world_service.gd`

#### World State
- [x] WorldService singleton (autoload)
- [x] Track all zones and entities
- [x] Zone loading/unloading
- [x] Time of day / day-night cycle
- [x] World events system

#### Gateway System
- [x] Gateway between zones
- [x] Gateway activation (proximity + interaction)
- [x] Gateway transitions
- [x] Ankh placement at gateways (respawn system integration)

#### Procedural World
- [ ] Zone generation templates
- [ ] Seed-based world generation
- [ ] Region connectivity

### 3.6 Shard/Multi-Server Support ✅ (NEW)
**Files:** `synmergia/core/services/shard_manager.gd`

#### ShardManager Service
- [x] Shard ID and name configuration
- [x] World size configuration (default 200 km²)
- [x] Player count tracking per shard
- [x] Max players per shard (soft cap)
- [x] Server status (online/maintenance/full)

#### Cross-Shard Support
- [x] Connected shards tracking
- [x] Cross-shard transfer eligibility check
- [x] World coordinate offset for shard-based worlds
- [x] Shard config generation for admin tools

### World Design Decisions
- **Scale:** Massive (~200+ km²), bigger than RYL2, room for housing
- **Dungeons:** Support both open-world AND instanced (flexible)
- **Transitions:** Seamless for open world, seamless preferred for instances
- **Server:** Single shard ideal, multi-shard supported with meshing

### 3.7 Zones & Dungeons (TODO)
**TODO:** Define zones, dungeons, and world structure

#### Zone Types
- [ ] Starter zones (1-20, safe)
- [ ] Mid-level zones (20-50)
- [ ] High-level zones (50+)
- [ ] PvP zones (various levels)
- [ ] Dungeons (instanced)
- [ ] Raids (large instanced)
- [ ] World bosses (open-world elites)

#### Dungeon Types
- [ ] Solo dungeons (story, learning)
- [ ] Group dungeons (5-man)
- [ ] Raid dungeons (10-40 man)
- [ ] World dungeons (open-world, server-wide)

#### Special Areas
- [ ] Housing districts (player-built areas)
- [ ] Crafting zones (resources, workshops)
- [ ] Arena/Battlegrounds (PvP)
- [ ] Sky islands
- [ ] Underworld
- [ ] Dimensional planes

---

### 3.8 Player Notifications ✅
**Files:** `synmergia/core/services/notification_service.gd`

#### Notification System
- [x] NotificationService singleton (autoload)
- [x] NotificationType enum (SYSTEM, ZONE_CHANGE, DUNGEON, ACHIEVEMENT, etc.)
- [x] Priority levels (LOW, NORMAL, HIGH, CRITICAL)
- [x] DisplayLocation (CHAT_LOG, CENTER_SCREEN, CORNER, FLOATING)
- [x] Sound types for different events

#### Notification Types
- [x] Zone entry/exit notifications (integrated with ZoneManager)
- [x] Dungeon entry/exit notifications
- [x] Achievement unlocked
- [x] Level up announcements
- [x] World event alerts
- [x] Faction/guild notifications
- [x] Combat notifications (crit, dodge, etc.)
- [x] Item loot notifications (with rarity)
- [x] Gold change notifications
- [x] Quest notifications
- [x] Warning/error messages

#### Notification Methods
- [x] send() - Send to single entity
- [x] broadcast() - Send to multiple entities
- [x] broadcast_zone() - Send to all players in zone
- [x] broadcast_all() - Send to all online players
- [x] get_unread() - Get unread notifications
- [x] get_history() - Get notification history

#### Integration
- [x] ZoneManager integrates notifications for seamless transitions
- [x] Dungeon entry/exit notification methods available

---

## Phase 4: Loot and Items

**PRD References:** Section 6 Economy & Crafting

### 4.1 Achievement System (TODO)
**TODO:** Achievement tracking and rewards

#### Achievement Types
- [ ] Kill achievements (kill X enemies, kill X bosses)
- [ ] Collect achievements (gather X resources, collect X items)
- [ ] Exploration achievements (visit X zones, discover hidden areas)
- [ ] Combat achievements (win X duels, survive X deaths)
- [ ] Social achievements (join guild, make X friends, trade X times)
- [ ] Crafting achievements (craft X items, reach artisan level)
- [ ] Progression achievements (reach level X, complete X dungeons)

#### Achievement Features
- [ ] Achievement definition schema
- [ ] AchievementService for tracking
- [ ] Unlock notifications (integrated with NotificationService)
- [ ] Achievement categories/tiers
- [ ] Reward system (titles, items, cosmetics)
- [ ] Progress tracking

### 4.2 Leveling & XP System (TODO)
**TODO:** Experience points and character leveling

#### XP Sources
- [ ] Kill XP (enemies, bosses)
- [ ] Quest XP (story quests, daily quests)
- [ ] Exploration XP (discovering zones, landmarks)
- [ ] Crafting XP (successful crafts)
- [ ] Event XP (double XP weekends)

#### Level Features
- [ ] XP calculation and storage
- [ ] Level up notifications (integrated with NotificationService)
- [ ] Stat gains per level
- [ ] Level caps and soft caps
- [ ] Level sync in PvP zones

### 4.3 Loot System
**Files:** `godot-project/core/schemas/loot_table.gd`, `loot_service.gd`

- [x] Loot tables per enemy type
- [x] Drop rates (common, rare, epic)
- [x] Gold/currency drops
- [x] Auto-loot vs manual loot

### 4.3 Equipment System
**Files:** `godot-project/core/schemas/item.gd`, `inventory_component.gd`

- [x] Equipment slots (head, chest, weapon, etc.)
- [x] Item stats (primary, secondary, tertiary)
- [x] Stat calculations with equipment
- [x] Gear score/item level

### 4.4 Trade System
**Files:** `godot-project/core/services/trade_service.gd`

- [x] Trade request system (send/accept/decline)
- [x] Trade window UI (helpers, signals)
- [x] Item slots for trade
- [x] Gold/currency trade
- [x] Trade confirmation (both must confirm)
- [x] Trade cancellation
- [x] Trade notifications (request, complete, cancelled)
- [x] Trade history/log
- [x] Trade restrictions (bind-on-pickup items, level requirements)

#### Trade Safety
- [x] Anti-scam measures (trade confirmation countdown)
- [x] Trade cooldown timers
- [x] Blocked item types (soulbound, quest items)
- [ ] Trade between characters on same account

### 4.5 Inventory System
**Files:** `godot-project/core/components/inventory_component.gd`

- [x] Inventory slots management
- [x] Stack limits
- [x] Sort/arrange functionality
- [x] Bag expansion
- [x] Bank/storage (off-character storage)
- [x] Item pickup/drop
- [x] Item destruction/selling

---

## Infrastructure Gaps (Technical Debt)

### Add species_id to EnemyData
**Files:** `godot-project/core/schemas/enemy_data.gd`, `spawn_service.gd`

- [x] Add `species_id: String` export variable
- [x] Update spawn logic to use species for faction relationships

### Auto-register Zone Neighbors
**Files:** `godot-project/core/services/zone_manager.gd`

- [x] On zone load, check for nearby zones based on position
- [x] Auto-register neighbors for seamless transitions
- [x] Add method to get all connected zones (for alerts)

### Add PartyService
**Files:** `godot-project/core/services/party_service.gd`

- [x] Party creation/deletion
- [x] Invite system (request/accept/decline)
- [x] Party member list
- [x] Party loot rules (free-for-all, round-robin, master looter)
- [x] Party XP sharing
- [x] Party chat channel (via ChatService)
- [x] Party notifications (joined, left, kicked)

### Add GuildService
**Files:** `godot-project/core/services/guild_service.gd`

- [x] Guild creation/deletion
- [x] Guild roster
- [x] Guild ranks/permissions
- [x] Guild chat (via ChatService)
- [x] Guild bank (shared storage)
- [x] Guild recruiting (applications)
- [x] Guild alliance system
- [x] Guild notifications

### Add ChatService
**Files:** `godot-project/core/services/chat_service.gd`

- [x] Chat channels (Global, Zone, Whisper, Party, Guild, Trade, System)
- [x] Channel permissions
- [x] Chat filtering (profanity, spam)
- [x] Chat history
- [x] Chat commands (/whisper, /party, etc.)

---

## Phase 8: Launch Readiness

### Enable CI/CD Pipeline
**Files:** `.github/workflows/godot-ci.yml.disabled`

> ⚠️ CI is currently disabled to conserve GitHub Actions minutes (free tier: 2,000 min/month).
> Re-enable when a playable slice exists.

- [ ] Move `godot-ci.yml.disabled` → `godot-ci.yml`
- [ ] Add `export_presets.cfg` with export templates
- [ ] Configure build matrix (Linux, Windows, macOS, Android, Server)
- [ ] Add automated tests
- [ ] Set up artifact publishing

---

## Phase 5: Player Progression

**PRD References:** Section 5 Player Systems

### 5.1 Class System
**Files:** `godot-project/core/schemas/character_class.gd`

- [ ] Class definitions (Warrior, Mage, Rogue, etc.)
- [ ] Class-specific base stats
- [ ] Class skill trees

---

## File Structure Overview

```
godot-project/
├── core/
│   ├── services/               # Autoloaded services
│   │   ├── event_bus.gd        # Global signal hub
│   │   ├── data_service.gd     # Resource loading
│   │   ├── entity_service.gd  # Entity registry
│   │   ├── connector_service.gd # AI agent connectors
│   │   ├── combat_service.gd
│   │   ├── spawn_service.gd
│   │   └── xp_service.gd
│   ├── schemas/                # Base classes for data (.tres files)
│   │   ├── skill.gd
│   │   ├── item.gd
│   │   ├── enemy_data.gd
│   │   ├── character_class.gd
│   │   ├── species.gd
│   │   ├── faction.gd
│   │   ├── zone_data.gd
│   │   ├── event_data.gd      # Global events
│   │   ├── dwelling_data.gd  # Housing items
│   │   ├── agent_connector.gd # AI connector base
│   │   └── agent_action.gd    # Agent action data
│   ├── components/             # Entity components
│   │   ├── health_component.gd
│   │   ├── combat_component.gd
│   │   ├── aura_component.gd
│   │   ├── aggro_component.gd
│   │   └── inventory_component.gd
│   └── ai/
│       └── enemy_ai.gd
├── connectors/                 # AI Agent Connectors (NEW)
│   ├── vant/                  # Vant runtime connector
│   ├── mcp/                   # Model Context Protocol
│   ├── claude/                # Anthropic Claude
│   ├── openai/               # OpenAI GPT
│   └── gemini/               # Google Gemini
├── data/                       # Resource files (drop .tres = add content)
│   ├── skills/
│   ├── items/
│   ├── weapons/
│   ├── armors/
│   ├── accessories/
│   ├── consumables/
│   ├── resources/
│   ├── events/
│   ├── dwellings/
│   ├── misc/
│   ├── enemies/
│   ├── classes/
│   ├── species/
│   ├── factions/
│   └── zones/
└── entities/
    ├── player/
    │   ├── player_controller.gd
    │   ├── states/
    │   └── camera/
    └── enemies/
        └── enemy_controller.gd
```

---

## Phase X: Agent Connectors (NEW)

**PRD References:** AI Agent Support, Multiplayer Extensions

### X.1 Connector Framework
**Files:** `godot-project/core/schemas/agent_connector.gd`, `agent_action.gd`

- [x] AgentConnector base class with observation/action space
- [x] AgentAction data class
- [ ] Connector discovery and loading
- [ ] Hot-reload connectors

### X.2 Connector Implementations
**Files:** `godot-project/connectors/`

- [x] VantConnector - Vant runtime connector
- [x] MCPConnector - Model Context Protocol
- [ ] ClaudeConnector - Anthropic Claude
- [ ] OpenAIConnector - GPT-4/GPT-4o
- [ ] GeminiConnector - Google Gemini
- [ ] CustomConnector - Base for custom implementations

### X.3 Connector Service
**Files:** `godot-project/core/services/connector_service.gd`

- [x] ConnectorService - Manages all connectors
- [ ] Agent session management
- [ ] Action execution pipeline
- [ ] Observation broadcasting

### X.4 Agent Training/Modes
- [ ] Self-play mode (agents vs agents)
- [ ] Human vs Agent mode
- [ ] Agent tournament scoring
- [ ] Replay/observation tools

---

## Phase Y: Fairness & Anti-Cheat (NEW)

**Core Principle: Humans and Agents are EQUALS**

### Y.1 Agent Species/Faction
**Files:** `data/species/species_synthetic.tres`, `data/factions/faction_agent_collective.tres`

- [x] Synthetic species - AI agent playable race
- [x] Agent Collective faction
- [x] `is_agent_controllable` / `is_human_controllable` flags in Species schema

### Y.2 FairnessService
**Files:** `core/services/fairness_service.gd`

- [x] Equal rate limiting for humans AND agents
- [x] Trust/reputation system (0.0 to 1.0)
- [x] Consensus voting for contested actions
- [x] Marathon session debuffs (6+ hours = penalties)
- [x] Trust decay for inactive players
- [x] Fairness violation reporting

### Y.3 AntiCheatService
**Files:** `core/services/anticheat_service.gd`

- [x] Perfect timing detection (macro detection)
- [x] Movement prediction analysis (bot pathing)
- [x] Response time variance (humans are inconsistent)
- [x] Idle pattern analysis (humans take breaks)
- [x] Action rate consistency detection
- [x] Suspicion scoring (0.0 to 1.0)
- [x] Player flagging and banning
- [x] Agent penalty modifier (fairness pass for known patterns)

### Y.4 QoSService
**Files:** `core/services/qos_service.gd`

- [x] Latency measurement and classification
- [x] Connection quality (EXCELLENT/GOOD/FAIR/POOR/BAD)
- [x] Packet loss monitoring
- [x] Jitter calculation
- [x] Latency-based throttling
- [x] Fair matchmaking groups
- [x] Interpolation delay compensation

### Y.5 ControllerType Enum
**Files:** `core/entities/entity.gd`

- [x] `Entity.ControllerType.HUMAN` - Real human player
- [x] `Entity.ControllerType.AGENT` - AI agent
- [x] `Entity.ControllerType.NPC` - Scripted NPC
- [x] `Entity.ControllerType.HOSTILE_AI` - Enemy AI
- [x] `connector_id` - Links agents to their connector

### Y.6 Identified Gaps (Future Work)
**Status: Design Phase**

- [ ] **Input Source Verification** - How to verify "real" human input vs AI-simulated?
  - Challenge: Humans use keyboards/mice, but these can be scripted
  - Options: Hardware attestation, behavioral biometrics, CAPTCHA integration
  
- [ ] **Proof of Attention/Work** - CAPTCHA-like challenges for suspicious patterns
  - Periodic human-verification checkpoints
  - Proof-of-work puzzles for high-value actions
  - Anomaly-triggered challenges
  
- [ ] **Mirror Matching** - Option to queue only vs same controller type
  - `matchmaking.prefer_controller_type` setting
  - Agent-only queues for testing
  - Human-only queues for competitive integrity
  
- [ ] **Agent Sandbox** - Separate agent vs agent matchmaking pools
  - Train agents against agents without affecting human economy
  - Separate loot/XPSinks for agent-only sessions
  - Bot arena/gym environment
  
- [ ] **Exploit Reporting System** - Community-driven anti-cheat
  - In-game `/report` command for exploits
  - Bounty system for verified exploit reports
  - Public exploit ledger (post-fix)

- [ ] **Hardware Fingerprinting** - Detect multi-boxing, VPN abuse
  - Link accounts by hardware ID
  - Detect VPN/proxy usage patterns
  - IP-based clustering analysis

---

## Quick Stats

| Category | TODO | In Progress |
|----------|------|-------------|
| Services | 7 | 0 |
| Schemas | 8 | 0 |
| Components | 5 | 0 |
| AI | 1 | 0 |
| Data Files | 7 | 0 |
| Combat | 3 | 0 |
| **Total** | ~31 | 0 |

---

## Legend

- NEW = New architecture layer
- TODO = Not started
- CRITICAL = Must have for vertical slice

---

Last updated: 2026-08-25
