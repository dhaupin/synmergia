# Synmergia - Development Roadmap

> 3D Open World MMORPG inspired by RYL2 combat and Ultima Online depth
>
> PRD: See [labs/prd.md](./labs/prd.md) for full design specification

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
- [x] Trade between characters on same account

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


## Security Fixes (2026-08-25)

**Commit:** `e199e40` - Critical security exploits patched

### inventory_service.gd
- Added input validation (empty strings, null checks)
- Added same-account check for self-transfer
- Added item ownership verification (source_item != item)
- Added gold amount validation (amount <= 0)
- Enhanced logging for security events

### inventory_component.gd
- `add_gold()` now rejects negative/zero amounts
- `set_gold()` uses maxi() for int safety
- `_try_stack_item()` now updates weight when stacking items

### fairness_service.gd
- `_check_rate()` now appends to original action_list (was appending to filtered copy)
- `_get_action_rate()` fixed to count from action arrays instead of int field

### party_service.gd
- Added `_process()` to auto-cleanup expired invites

### trade_service.gd
- `cancel_trade()` now refunds items and gold to original inventories
- Added `_refund_trade_items()` helper function

## Security Fixes (2026-08-25) - Additional

**Commit:** Additional security patches applied

### chat_service.gd
- Added `MAX_MESSAGE_LENGTH` constant (default 500 characters)
- Messages are now truncated to max length before processing

### party_service.gd
- Updated `MAX_PARTY_SIZE` from 5 to 6 players
- Updated `MAX_PARTY_ROSTER_SIZE` from 20 to 30 for raids
- Added empty party check in `share_xp()` to prevent division by zero

### entity_service.gd
- Added duplicate entity ID check in `register_entity()` - returns empty string if ID already exists

### trade_service.gd
- Added `transfer_success` check before marking trade as COMPLETED
- Trade state is now set to FAILED if transfer fails
- Added `trade_failed` signal emission on failure

### ROADMAP.md - Future Work
- [ ] **Profanity Filter Enhancement** - Current word-list approach may be flagged by GitHub
  - Consider: External API-based filtering, community moderation, or configurable blocklist

---

## Phase Z: Defensive Architecture (2026-08-25)

**Core Principle: Defense in Depth - Layered protection across all systems**

### Z.1 QoSService (Priority 1)
**Files:** `core/autoload/qos_service.gd`

Quality of Service infrastructure for traffic control and resource protection.

#### Rate Limiter
Token bucket algorithm for per-player action throttling.
- `rate_limit(player_id, action_type, max_per_second)` → bool
- Per-action-type tracking (movement, combat, chat, etc.)
- Configurable limits via `GameConfig.QoS.RateLimits.*`

#### Throttler
Global action limits to prevent server overload.
- `throttle(scope, action_type, max_per_second)` → bool
- Scopes: "global", "per_zone", "per_party"
- Queue system for deferred processing

#### Bulkhead
Isolate failure domains - one service failing shouldn't cascade.
- `bulkhead_execute(service_name, callback)` → Variant
- Separate thread pools per service category
- Automatic failover behavior

#### Debouncer
Coalesce rapid repeated calls into single action.
- `debounce(key, callback, delay_ms)` → void
- Used for: UI events, auto-save, typing indicators
- Cancel previous pending call on new call

#### Config Settings (`game_config.gd`)
```
QoS.RateLimits.MAX_MOVEMENT_PER_SECOND: 20
QoS.RateLimits.MAX_COMBAT_ACTIONS_PER_SECOND: 5
QoS.RateLimits.MAX_CHAT_PER_MINUTE: 10
QoS.RateLimits.MAX_TRADE_PER_MINUTE: 5
QoS.RateLimits.MAX_PARTY_PER_MINUTE: 3
QoS.RateLimits.MAX_WHISPER_PER_MINUTE: 20
QoS.Bulkhead.MAX_CONCURRENT_GLOBAL: 100
QoS.Bulkhead.MAX_CONCURRENT_PER_SERVICE: 25
QoS.Debounce.DEFAULT_DELAY_MS: 300
```

### Z.2 CircuitBreaker
**Files:** `core/utils/circuit_breaker.gd`

Reusable circuit breaker pattern for protecting fallible operations.

#### States
- `CLOSED`: Normal operation, calls pass through
- `OPEN`: Fail-fast mode, calls rejected immediately
- `HALF_OPEN`: Probe mode, limited calls allowed

#### Parameters
- `failure_threshold`: Number of failures before opening (default: 5)
- `recovery_timeout`: Seconds before attempting half-open (default: 30)
- `success_threshold`: Successes needed to close (default: 3)

#### Usage
```gdscript
var breaker := CircuitBreaker.new("external_api", 5, 30.0)
var result = await breaker.execute(my_function)
```

### Z.3 RecursionGuard
**Files:** `core/utils/recursion_guard.gd`

Prevents stack overflow from unbounded recursion.

#### Features
- Maximum depth tracking
- Per-context depth limits
- Call stack introspection
- Automatic depth reset

#### Usage
```gdscript
var guard := RecursionGuard.new(max_depth: 100)
if not guard.enter("process_tree"):
    return  # Prevent infinite recursion
# ... do work
guard.exit("process_tree")
```

### Z.4 SecurityService
**Files:** `core/autoload/security_service.gd`

Input validation, anti-abuse, and permission management.

#### InputValidator
- Player name sanitization (length, characters, profanity)
- Chat message sanitization (XSS prevention, length limits)
- Command argument parsing and validation
- SQL injection prevention (though Godot doesn't use SQL directly)

#### SpamDetector
- Message frequency tracking
- Content similarity analysis (Levenshtein distance)
- Pattern recognition for spam bots
- Configurable thresholds

#### PermissionGate
- Role-based access control (RBAC)
- Permission flags per action
- Channel-specific permissions
- Escalation management

### Z.5 AppFirewall
**Files:** `core/autoload/app_firewall.gd`

Centralized validation layer for all incoming data.

#### PacketValidator
- Structure validation (required fields, types)
- Size limits (max packet size, max array length)
- Range validation (numeric bounds)
- Sanitization on ingress

#### AnomalyDetector
- Statistical anomaly detection
- Behavioral pattern analysis
- Threshold-based alerting
- Blacklist/greylist management

#### Banhammer
- Temporary ban management (duration-based)
- Permanent ban registry
- Ban appeal tracking
- Auto-ban rules for severe violations

### Z.6 Integration Points

Services to wire with QoSService:
- `party_service.gd` → rate_limit("invite"), throttle("party_create")
- `chat_service.gd` → rate_limit("send_message"), debounce("typing_indicator")
- `trade_service.gd` → rate_limit("trade_request")
- `fairness_service.gd` → rate_limit("all_actions"), throttle("global")
- `inventory_service.gd` → rate_limit("item_actions")

Services to wrap with CircuitBreaker:
- `inventory_service.gd` → External item lookups
- `data_service.gd` → Resource loading
- `network_manager.gd` → Connection operations

Services to add RecursionGuard:
- `entity_service.gd` → `get_all_entities_recursive()`
- `zone_manager.gd` → `get_neighbor_zones_recursive()`
- `aura_component.gd` → Effect application chains

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

## Future: Automated Exploit Response

**Status:** Implemented (disabled by default)

### Overview
Automatically respond to exploit detections based on configurable thresholds. Can mute, kick, or ban players without admin intervention.

### Configuration (`game_config.gd`)
```gdscript
class AutoResponse:
    ## Master switch
    const ENABLED: bool = false
    
    ## Spam: Auto-mute duration
    const SPAM_MUTE_DURATION: int = 300  # 5 minutes
    
    ## Global: Auto-kick after N total exploit detections
    const AUTO_KICK_THRESHOLD: int = 3
    
    ## Speed Hack: Auto-ban settings
    const AUTO_BAN_SPEEDHACK: bool = false
    const SPEEDHACK_CONFIRMATIONS_REQUIRED: int = 3
    
    ## Teleport Hack: Auto-ban settings
    const AUTO_BAN_TELEPORTHACK: bool = false
    const TELEPORTHACK_CONFIRMATIONS_REQUIRED: int = 2
    
    ## Item Duplication: Auto-ban settings
    const AUTO_BAN_ITEM_DUPLICATION: bool = false
    const ITEM_DUP_CONFIRMATIONS_REQUIRED: int = 2
    
    ## Notifications
    const NOTIFY_ADMINS: bool = true
    const NOTIFY_DISCORD: bool = false
```

### Response Flow
```
Exploit Detected
       ↓
Track Confirmation Count
       ↓
   ┌───────────────────────────────────────┐
   │ Exploit Type    │ Threshold │ Action  │
   ├───────────────────────────────────────┤
   │ spam            │ 1         │ Warn    │
   │ spam            │ 2+        │ Mute    │
   │ speed_hack      │ 3 (cfg)   │ Ban*    │
   │ teleport_hack   │ 2 (cfg)   │ Ban*    │
   │ item_duplication│ 2 (cfg)   │ Ban*    │
   │ ANY (total)     │ 3 (cfg)   │ Kick    │
   └───────────────────────────────────────┘
   * Only if AUTO_BAN_* is true
```

### Tuning Recommendations

#### Conservative (Low False Positive)
```
ENABLED = true
AUTO_KICK_THRESHOLD = 5
AUTO_BAN_SPEEDHACK = false
SPEEDHACK_CONFIRMATIONS_REQUIRED = 5
# Admins review manually
```

#### Moderate (Balanced)
```
ENABLED = true
AUTO_KICK_THRESHOLD = 3
AUTO_BAN_SPEEDHACK = true
SPEEDHACK_CONFIRMATIONS_REQUIRED = 3
AUTO_BAN_TELEPORTHACK = true
TELEPORTHACK_CONFIRMATIONS_REQUIRED = 2
```

#### Aggressive (High Security)
```
ENABLED = true
AUTO_KICK_THRESHOLD = 2
AUTO_BAN_SPEEDHACK = true
SPEEDHACK_CONFIRMATIONS_REQUIRED = 2
AUTO_BAN_TELEPORTHACK = true
TELEPORTHACK_CONFIRMATIONS_REQUIRED = 1
AUTO_BAN_ITEM_DUPLICATION = true
ITEM_DUP_CONFIRMATIONS_REQUIRED = 1
```

### Implementation Status
- `AutoResponseService` created and autoloaded
- Connected to `SecurityService.exploit_detected`
- Config class added to `GameConfig`
- **Disabled by default** - enable in config when ready

### Future Enhancements
- [ ] Graduated responses (warn → mute → kick → ban)
- [ ] Time-based forgiveness (reset counts after X minutes clean)
- [ ] Trust score integration (higher trust = more lenient)
- [ ] Discord webhook for auto-bans
- [ ] Admin override for flagged players

---

## Future: Database Considerations (Persistence)

**Status:** Not Started - Architecture Discussion Needed

### Overview
Security, firewall, and rate-limiting data is currently in-memory only. For production, this needs persistence.

### Data That Needs Persistence

#### Firewall Data
```
banned_players:     player_id → {reason, banned_by, timestamp, expires?}
blocked_ips:         ip → {reason, blocked_until}
flagged_ips:         ip → {flags, count, last_activity}
connection_counts:   ip → count
```

#### Security Data
```
restricted_players:  player_id → {action_type, expires, reason}
player_trust:        player_id → trust_score (FairnessService)
exploit_log:         player_id → [{type, details, timestamp}]
```

#### QoS/Rate Limit Data
```
rate_limit_buckets:  player_id → {action_type → {count, window_start}}
```

#### Admin/Permission Data
```
player_permissions:  player_id → permission_level (VIP, MOD, ADMIN, OWNER)
audit_log:          [{admin_id, action, target, timestamp, success, details}]
admin_session_log:  [{admin_id, action, timestamp, ip}]
```

#### Player Reporting Data
```
player_reports:     report_id → {type, reporter, target, subject, description, status, priority}
abuse_reports:     target_id → [report_ids]
report_votes:       report_id → {voter_id: upvote/downvote}
```

### Database Schema Options

#### Option 1: Simple Key-Value (Redis)
```json
{
  "banned:player123": {"reason": "hacking", "by": "admin1"},
  "blocked:192.168.1.1": {"until": 1724500000},
  "trust:player456": 0.85
}
```
- Pros: Fast, simple, TTL support
- Cons: No complex queries

#### Option 2: SQL Tables
```sql
CREATE TABLE bans (
    id SERIAL PRIMARY KEY,
    player_id VARCHAR(64) NOT NULL,
    reason TEXT,
    banned_by VARCHAR(64),
    created_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP,
    UNIQUE(player_id)
);

CREATE TABLE exploit_logs (
    id SERIAL PRIMARY KEY,
    player_id VARCHAR(64) NOT NULL,
    exploit_type VARCHAR(64),
    details JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE ip_blocks (
    ip VARCHAR(45) PRIMARY KEY,
    reason TEXT,
    blocked_until TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);
```
- Pros: Queryable, relationships, backupable
- Cons: Slower than Redis for high-frequency reads

#### Option 3: Hybrid (Both)
- Redis for active data (current bans, rate limits)
- SQL for audit logs (exploit history, admin actions)

### Config Options
```gdscript
# game_config.gd
class Database:
    ## Persistence mode
    enum PersistenceMode { NONE, REDIS, SQL, HYBRID }
    const PERSISTENCE_MODE: PersistenceMode = PersistenceMode.NONE
    
    ## Redis config
    const REDIS_HOST: String = "localhost"
    const REDIS_PORT: int = 6379
    
    ## SQL config
    const SQL_HOST: String = "localhost"
    const SQL_DATABASE: String = "synmergia"
    
    ## Persistence intervals
    const SYNC_INTERVAL_SECONDS: int = 60  # How often to persist to DB
```

### Implementation Notes
1. Start with in-memory only (current state)
2. Add interface layer for persistence
3. Implement Redis first (simpler for rate limiting)
4. Add SQL for audit logs (compliance, admin queries)

### Permission & Audit Persistence (TODO)
- [x] Unified PermissionManager (core/admin/permission_manager.gd)
  - Combined from PermissionSystem + PermissionManager
  - Global: PLAYER, VIP, MOD, ADMIN, OWNER
  - Party: MEMBER, OFFICER, LEADER
  - Guild: RECRUIT, MEMBER, OFFICER, GUILD_MASTER
  - Faction: INITIATE, MEMBER, VETERAN, COMMANDER, LEADER
  - Audit logging with timestamps, IPs, success/failure
  - Rate limiting for admin commands
  - Admin actions: mute, kick, ban, restrict, lookup
  - get_player_summary() for complete permission info
- [ ] Connect PermissionManager to database
- [ ] Store player permission levels persistently
- [ ] Persist audit log entries to database
- [ ] Add admin session logging with IP tracking
- [ ] Implement permission inheritance/group system
- [ ] Add "report admin abuse" feature for players

### Player Reporting System (TODO)
- [x] PlayerReporter class implemented (core/admin/player_reporter.gd)
- [ ] Add database persistence for reports
- [ ] Implement report voting system (community moderation)
- [ ] Add report categories: Bug, Abuse, Feedback, Suggestion, Exploit
- [ ] Connect urgent_report signal to Discord webhook
- [ ] Add report status notifications to reporters
- [ ] Implement automated report resolution for duplicates

### Player Shell Customization (TODO)
- [ ] Persist player aliases and macros to database
- [ ] Add macro variables: `$player`, `$target`, `$time`
- [ ] Implement command aliases (shortcuts)
- [ ] Add UI theme customization
- [ ] Export/import customization presets

### Targeting & Interaction System (IN PROGRESS)

**Design Principles:**
- Single source of truth via TargetingManager autoload
- Data-driven via `data/targets/target_*.tres` schemas
- EventBus for decoupled entity registration
- Schema caching/memoization for performance
- Permission-based action execution via PermissionManager

#### Core Architecture (core/targeting/, core/input/)

- [x] **TargetingManager** - Unified targeting system (autoload)
  - `core/targeting/targeting_manager.gd`
  - Single target state with history
  - Action execution (social, moderation, admin, interaction)
  - 3D highlight management
  - EventBus integration for entity registration
  - Schema caching with lazy loading

- [x] **InteractionLayer** - Platform abstraction (core/input/interaction_layer.gd)
  - TAP, LONG_PRESS, DRAG, DOUBLE_TAP, SWIPE, HOVER
  - Auto-detect: Desktop, Mobile, Gamepad
  - Platform-aware button sizes
  - Registered as autoload

- [ ] **TargetTooltip** - Generic tooltip (ui/targeting/target_tooltip.gd)
  - Wire to TargetingManager signals
  - Add action buttons from schema
  - Integrate ObjectiveManager for objective display

- [ ] **3D Target Highlight** - Visual indicator
  - Create highlight node management
  - Add to 3D world scene
  - Color per entity type from schema

#### Target Schemas (data/targets/*.tres)

- [x] target_player.tres - Player targeting config
- [x] target_enemy.tres - Enemy targeting config
- [x] target_npc.tres - NPC targeting config
- [x] target_loot.tres - Loot targeting config
- [x] target_gateway.tres - Gateway/teleport config
- [x] target_dwelling.tres - Housing object config
- [ ] target_custom_*.tres - Modder-extensible schemas

#### Schema Design (core/schemas/target_schema.gd)

- [x] TargetSchema - Base schema class
  - entity_type mapping (PLAYER, ENEMY, NPC, etc.)
  - interaction_mode (HOVER, CLICK, PROXIMITY)
  - selection_mode (SINGLE, MULTI, RADIAL)
  - highlight_color and highlight_size
  - available_actions array
  - tooltip configuration

#### Integration Phases

**Phase 1: Foundation** ✅ DONE
- [x] Create TargetingManager autoload
- [x] Create TargetSchema base class
- [x] Create data/targets/ directory with 6 schemas
- [x] Register TargetingManager in project.godot
- [x] Add targeting signals to EventBus
- [x] Delete legacy files (player_target_*.gd, targeting_system.gd)

**Phase 2: Raycast & Input Integration** ✅ DONE
- [x] Add raycast methods to TargetingManager
  - `raycast_from_camera(screen_pos, camera)`
  - `raycast_from_mouse(camera)`
  - `raycast_from_touch(touch_pos, camera)`
  - `raycast_from_center(camera)`
  - `get_target_in_direction(origin, direction, max_distance)`
  - `_get_active_camera()` helper
- [x] Wire PlayerController → TargetingManager
  - Click-to-target via `_unhandled_input`
  - Tab cycling uses `TargetingManager.cycle_target()`
  - Right-click context menu support
  - Touch targeting via InteractionLayer signals
- [x] Connect InteractionLayer to PlayerController
  - `tap` → `_on_interaction_tap` → `_handle_left_click`
  - `double_tap` → quick target nearest
  - `long_press` → context menu
  - `action_triggered` → target_next, target_prev, cancel

**Phase 3: Tooltip System** ✅ DONE
- [x] Wire TargetTooltip to TargetingManager signals
  - `target_acquired` → shows tooltip with fade animation
  - `target_cleared` → hides tooltip (unless sticky)
  - `target_updated` → refreshes tooltip data
- [x] Dynamic action buttons from schema (`available_actions`)
- [x] QoS rate limiting on action execution
- [x] Permission checks for sensitive actions
- [x] Entity-type-specific status display (HP, online status, etc.)
- [x] Sticky/pinned mode with visual feedback
- [x] Touch-friendly draggable interface

**Phase 4: 3D Highlight** ✅ DONE
- [x] 3D highlight management in TargetingManager
  - `_update_3d_highlight()` - Updates highlight for new target
  - `_create_or_update_highlight_mesh()` - Creates glowing ring mesh
  - `_create_ring_mesh()` - Procedural ring geometry
  - `_start_highlight_pulse()` - Pulsing glow animation
  - `_hide_3d_highlight()` - Hides when target cleared
- [x] Color-coded by entity type (from schema `highlight_color`)
- [x] Configurable pulse animation via `set_highlight_pulse()`
- [x] Layer management for rendering control

**Phase 5: Permission Integration** ✅ DONE
- [x] TargetTooltip action buttons check `PermissionManager.has_permission()`
- [x] Sensitive actions require `target_<action>` permission
- [x] Rate limiting via `QoSService.rate_limit()` on all actions
- [x] EventBus integration for action logging

**Phase 6: Cleanup**
- [x] Delete core/player_target_system.gd
- [x] Delete core/player_target_controller.gd
- [x] Delete core/player_target_highlight.gd
- [x] Delete core/targeting/targeting_system.gd
- [x] Delete ui/player/player_target_tooltip.gd

**Phase 7: Entity Spawn Integration** ✅ DONE
- [x] SpawnService registers enemies with TargetingManager on spawn
- [x] SpawnService registers bosses with TargetingManager on spawn
- [x] SpawnService registers NPCs with TargetingManager on spawn
- [x] SpawnService unregisters from TargetingManager on despawn
- [x] Added `update_targetable_position()` for moving entities
- [x] Added `update_targetable_node()` for node reference updates

**Phase 8: UI Integration** ✅ DONE
- [x] Created UIManager singleton (core/ui/ui_manager.gd)
- [x] Registered UIManager as autoload in project.godot
- [x] UIManager instantiates TargetTooltip on game start
- [x] TargetTooltip connects to TargetingManager signals
- [x] Fixed signal handler signatures (TargetInfo vs String)
- [x] UIManager shows/hides UI based on game state

### Webhook Connector System (TODO)
- [x] WebhookBase abstract connector (connectors/webhook/webhook_base.gd)
- [x] DiscordWebhook connector (connectors/webhook/discord_webhook.gd)
- [x] WebhookManager auto-load (core/autoload/webhook_manager.gd)
- [x] Connect to PermissionManager.admin_action signal
- [x] Connect to PlayerReporter.urgent_report signal
- [x] Connect to CommunityGovernance signals
- [ ] Add Slack webhook connector
- [ ] Add generic HTTP webhook connector
- [ ] Store webhook URLs in database/config

### Player Reporting System (TODO)
- [x] PlayerReporter class implemented (core/admin/player_reporter.gd)
- [x] ReportDialog UI with rate limiting (ui/player/report_dialog.gd)
- [ ] Add database persistence for reports
- [ ] Implement report voting system (community moderation)
- [ ] Add report categories: Bug, Abuse, Feedback, Suggestion, Exploit
- [ ] Connect urgent_report signal to Discord webhook
- [ ] Add report status notifications to reporters
- [ ] Implement automated report resolution for duplicates
- [ ] Add CAPTCHA for report submission (prevent flooding)
- [ ] Integrate form security with SecurityService

### Form Security & Anti-Abuse (TODO)
- [ ] CAPTCHA integration (hCaptcha/reCAPTCHA) for reports
- [ ] Rate limiting per player (via SecurityService)
- [ ] Content filtering/sanitization
- [ ] Spam detection patterns
- [ ] Report cooldown enforcement (client + server)
- [ ] Max reports per hour/day limits
- [ ] Input validation (XSS prevention)
- [ ] Audit logging for all form submissions

### Community Governance & Voting (DONE)
- [x] CommunityGovernance class implemented (core/community/community_governance.gd)
- [x] Persist votes to database
- [x] Persist player vote history
- [x] Implement vote reputation system
- [x] Connect report validation votes to PlayerReporter
- [x] Add feature suggestion voting
- [x] Add UI for voting interface
- [x] Implement community moderator role progression (10-level system)

### Friends & Social System (DONE)
- [x] Friends list storage (friendships table)
- [x] Friend requests system
- [x] Online status tracking
- [x] Block/ignore list persistence
- [x] Social graph analysis for recommendations

---

## Unified Spawn/Notification Architecture ✅

**Status:** Implemented - 2026-08-27

### Overview
Consolidated spawn and notification systems into a unified pattern using `EventBus.SpawnMetadata` (inner class) for decoupled event routing.

### Architecture

```
SpawnService.spawn_*()
    │
    ├── Creates EventBus.SpawnMetadata (spawn_type, zone, position, notification_config)
    │
    ├── EntityService.register_entity(entity, metadata)
    │       │
    │       └── EventBus.entity_spawned.emit(entity, metadata)
    │               │
    │               ├── NotificationService._on_entity_spawned()
    │               │       └── Auto-broadcasts based on metadata.notification_enabled
    │               │
    │               ├── MinimapManager._on_entity_spawned()
    │               │       └── Adds boss markers based on spawn_type
    │               │
    │               ├── QuestManager._on_entity_spawned()
    │               │       └── Updates kill counters based on spawn_type
    │               │
    │               └── ChatService._on_entity_spawned()
    │                       └── Posts to chat channels based on spawn_type
    │
    └── Service-specific signal (spawn_point context)
            └── SpawnService.enemy_spawned.emit(entity, spawn_point_id, metadata)
```

### SpawnMetadata (Inner Class of EventBus)
**Location:** `synmergia/core/services/event_bus.gd` (lines 67-249)

```gdscript
# Access via: EventBus.SpawnMetadata.world_boss(...)
# or: EventBus.SpawnMetadata.SpawnType.WORLD_BOSS
# or: EventBus.SpawnMetadata.NotificationPriority.CRITICAL

class SpawnMetadata:
    # Core info
    spawn_type: SpawnType  # NORMAL, ELITE, BOSS, WORLD_BOSS, NPC, LOOT, etc.
    display_name: String
    entity_id: String
    zone_id: String
    position: Vector3      # Required for radius-based notifications
    
    # Notification config
    notification_enabled: bool
    notification_scopes: Array[AlertScope]  # server_wide, zone, nearby, players
    notification_message: String
    notification_priority: NotificationPriority
    
    # Context
    spawn_point_id: String
    spawner_entity_id: String  # For summoned minions
    faction: int
    level: int
    tags: Array[String]
    quest_id: String
```

### Factory Methods

```gdscript
# Normal enemy - no notification
EventBus.SpawnMetadata.enemy(display_name, zone_id, position, spawn_point_id, level)

# Elite - zone notification
EventBus.SpawnMetadata.elite(display_name, zone_id, position, spawn_point_id, level)
# Result: notification_enabled=true, scopes=[zone(zone_id)], priority=NORMAL

# Boss - zone + neighbors notification
EventBus.SpawnMetadata.boss(display_name, zone_id, position, level)
# Result: notification_enabled=true, scopes=[zone(zone_id, true)], priority=HIGH

# World Boss - server-wide notification
EventBus.SpawnMetadata.world_boss(display_name, zone_id, position, level)
# Result: notification_enabled=true, scopes=[server_wide()], priority=CRITICAL
```

### EventBus Signals

```gdscript
# Unified entity events (all carry EventBus.SpawnMetadata)
signal entity_spawned(entity: Entity, metadata: EventBus.SpawnMetadata)
signal entity_despawned(entity: Entity, metadata: EventBus.SpawnMetadata)
signal entity_died(entity: Entity, killer: Entity, metadata: EventBus.SpawnMetadata)

# Removed redundant signals:
# ❌ enemy_spawned(enemy, spawn_point) - replaced by entity_spawned + enemy_spawned service signal
# ❌ boss_spawned(enemy, boss_name) - replaced by entity_spawned with metadata
# ❌ enemy_despawned(enemy) - replaced by entity_despawned with metadata
```

### Benefits

1. **Decoupled** - SpawnService doesn't call NotificationService directly
2. **Position data** - Available for radius-based notifications
3. **Extensible** - Any entity type can have notifications
4. **Self-documenting** - Metadata structure is explicit
5. **Testable** - Can unit test metadata creation independently
6. **Consistent** - Inner class pattern matches existing `AlertScope` in NotificationService

### Design Notes

- **Inner class pattern** matches existing codebase conventions (e.g., `AlertScope` in NotificationService)
- **Factory methods** provide clean instantiation with sensible defaults
- **Fluent API** for optional configuration (`.with_tags()`, `.for_quest()`)

### Files Changed

```
D   synmergia/core/schemas/spawn_metadata.gd    # Removed (moved to inner class)
M   synmergia/core/services/event_bus.gd         # Added SpawnMetadata inner class + unified signals
M   synmergia/core/services/entity_service.gd   # Uses EventBus.SpawnMetadata
M   synmergia/core/services/spawn_service.gd     # Uses EventBus.SpawnMetadata
M   synmergia/core/services/notification_service.gd  # Uses EventBus.SpawnMetadata
```

---

## Future: Discord/Webhook Alerts for Security

**Status:** Not Started - For Discussion

### Overview
Send security alerts to Discord when critical exploits are detected.

### Implementation Options

1. **Webhook-only (Simple)**
   - Add `DISCORD_WEBHOOK_URL` secret
   - POST JSON to webhook on critical exploit
   - No bot required

2. **Bot Token (Rich)**
   - Add `DISCORD_BOT_TOKEN` secret
   - Post to specific channel
   - Can @mention moderators

### Alert Types
- `speed_hack` - Player moving too fast
- `teleport_hack` - Instant position change
- `item_duplication` - Suspicious item creation
- `ban_triggered` - Player banned
- `connection_blocked` - IP blocked by firewall

### Example Alert
```
🚨 SECURITY: Player xyz123 detected speed_hack
   Speed: 1250 units/sec (max: 500)
   Location: (123, 45, 678)
   Time: 2026-08-25 03:15:00
```

### Configuration
```gdscript
# game_config.gd
class Discord:
    const WEBHOOK_URL: String = ""  # Set via environment
    const BOT_TOKEN: String = ""     # Alternative
    const ALERT_CHANNEL: String = "security-alerts"
    const MENTION_MODS: bool = true
```

---

## Completed: 2026-08-27

### Core TODOs Cleared

| Feature | File | Implementation |
|---------|------|----------------|
| Per-team arena respawn tracking | `core/schemas/ankh.gd` | `_team_respawn_counts` dictionary |
| Party-based team assignment | `core/services/respawn_service.gd` | `_get_arena_team()` queries PartyService |
| Gateway-based respawn | `core/services/respawn_service.gd` | `_get_nearest_gateway()` distance calculation |
| Guild invite system | `core/services/guild_service.gd` | `_pending_guild_invites` + signals |
| Alliance invite system | `core/services/guild_service.gd` | `_pending_alliance_invites` + signals |
| Enemy stealth detection | `core/ai/enemy_ai.gd` | `_is_valid_target()` checks `see_stealth` |
| Enemy loot table rolling | `core/schemas/enemy_data.gd` | `roll_loot()` loads LootTable |

### Architecture Updates

- **RespawnService** now integrates with PartyService for team-based arena respawns
- **GuildService** now tracks invite lifecycle with sent/accepted/declined/expired signals
- **Ankh Schema** supports per-team respawn counting for arena modes
- **EnemyAI** respects stealth status with configurable `see_stealth` detection

---

Last updated: 2026-08-27
