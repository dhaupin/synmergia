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

### 3.1 Species System
**Files:** `godot-project/core/schemas/species.gd`

- [ ] Species schema with stat_modifiers
- [ ] allied_species / hostile_species arrays
- [ ] Species-faction binding
- [ ] home_zone, home_faction defaults

### 3.2 Faction System
**Files:** `godot-project/core/schemas/faction.gd`

- [ ] FactionType: SPECIES, POLITICAL, PvP_RULE, REPUTATION
- [ ] PvP rule overrides (PEACEFUL until level, HUNTED always PvP)
- [ ] relations dictionary (ALLIED, NEUTRAL, HOSTILE)
- [ ] Faction reputation tracking

### 3.3 Zone PvP Rules
**Files:** `godot-project/core/schemas/zone_data.gd`

- [ ] Zone PvP modes: SAFE, SPECIES_PVP, FACTION_PVP, FREE_PVP, WARZONE
- [ ] Zone entry requirements (level, faction, species)
- [ ] Zone transitions/loading

### 3.4 Spawn System
**Files:** `godot-project/core/services/spawn_service.gd`

- [ ] Spawn points for enemies
- [ ] Respawn timers per spawn point
- [ ] Spawn caps per area

---

## Phase 4: Loot and Items

**PRD References:** Section 6 Economy & Crafting

### 4.1 Loot System
**Files:** `godot-project/core/schemas/loot_table.gd`

- [ ] Loot tables per enemy type
- [ ] Drop rates (common, rare, epic)
- [ ] Gold/currency drops
- [ ] Auto-loot vs manual loot

### 4.2 Equipment System
**Files:** `godot-project/core/schemas/item.gd`, inventory_component

- [ ] Equipment slots (head, chest, weapon, etc.)
- [ ] Item stats (primary, secondary, tertiary)
- [ ] Stat calculations with equipment
- [ ] Gear score/item level

---

## Phase 5: Player Progression

**PRD References:** Section 5 Player Systems

### 5.1 Leveling and XP
**Files:** `godot-project/core/services/xp_service.gd`

- [ ] XP gain on kill
- [ ] Level up stats increase
- [ ] XP curve formula
- [ ] Level cap (60 per PRD)

### 5.2 Class System
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
