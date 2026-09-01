# Synmergia

An open-world MMORPG built with Godot 4.7.2, inspired by RYL2 combat and Ultima Online depth. Built on a reusable **frame** (multi-iso orchestrator + content-hash state tree) that can be extracted to its own project.

> **Game:** A 3D open-world MMORPG with RYL2-style action combat and UO-style economy, housing, and depth.
> **Frame:** A multi-iso orchestrator + state tree that any state-heavy multiplayer game can build on. See [`labs/`](./labs/).

[![Godot 4.7.2](https://img.shields.io/badge/Godot-4.7.2-blue)](https://godotengine.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Status: Pre-vertical-slice](https://img.shields.io/badge/Status-Pre--vertical--slice-orange)]()

## Features

### Core Game Features
- **Event-Driven Architecture** - Services, components, and event bus for clean separation
- **Data-Driven Design** - Drop `.tres` files to add content (skills, items, enemies, etc.)
- **3D Combat System** - Skills, projectiles, AoE, buffs/debuffs, status effects
- **Entity-Component System** - Flexible entity composition with attachable components
- **Targeting System** - Data-driven targeting with configurable schemas
- **Notification → Toast Pipeline** - `NotificationService` routes every event through `TooltipManager.show_toast()` in the `HudLayer`. QoS, security, firewall, and auto-response all use the same channel. 47/47 smoke tests green.
- **UI Islands** - Each panel is a PackedScene with `IslandPlaceholder` root. Mounted by `IslandManager` from a static `IslandRegistry`. 19/19 POC tests passing.

### Social & Community
- **Friends System** - Friends list, requests, block/ignore with QoS protection
- **Party System** - Party management, invites, loot rules, XP sharing
- **Guild System** - Guilds with ranks, permissions, bank, alliances
- **Trading** - Item/currency trading with safety confirmations
- **Community Governance** - Player voting, moderator progression, reputation
- **Context Menus** - Right-click and touch-long-press interaction menus

### Species & Factions
- **Species System** - Races with stat modifiers and cross-species relationships
- **Faction System** - PvP rules, reputation, political alliances
- **Zone PvP Modes** - SAFE, SPECIES_PVP, FACTION_PVP, FREE_PVP, WARZONE

### AI Agent Support (Connectors)
- **Agent Connectors** - Connect AI agents (Vant, Claude, GPT, Gemini) to play
- **MCP Protocol** - Model Context Protocol support for standard AI interfaces
- **Observation/Action Space** - Structured game state for agent decision-making

### The Frame (experimental, in `/labs/`)
- **Multi-iso orchestrator** - Multi-dimensional state queries: spatial ∩ factional ∩ temporal ∩ social. Materialized intersection tables make hot queries O(1).
- **Content-hash state tree** - Every node is SHA-256-hashed. Server tick = re-rooting. Client sync = diff between hashes.
- **LOD pyramid** - 4 levels of detail. Inactive regions serialize and unload.
- **Predictive prefetch** - Markov over player transitions pre-loads regions before arrival.
- **Frame extraction** - The frame is designed to lift out of Synmergia and into its own project. The game becomes the example consumer.

## Tech Stack

- **Engine:** Godot 4.7.2 (MIT License)
- **Language:** GDScript
- **Platforms:** Android, iOS, PC
- **Architecture:** Client + Authoritative Server + Multi-iso orchestrator + Content-hash state tree
- **Persistence:** Postgres (snapshots) + in-memory LRU (intersection cache)

## Architecture

The stack is five layers. The first three are the game (in
`synmergia/`). The bottom two are the frame (in `/labs/`).

```
┌─────────────────────────────────────────────────────────────┐
│              AGENT CONNECTORS (in synmergia/connectors)     │
│  Vant | MCP | Claude | OpenAI | Gemini | Custom            │
├─────────────────────────────────────────────────────────────┤
│              UI ISLANDS (in synmergia/ui/islands)           │
│  Each panel = PackedScene with IslandPlaceholder root      │
│  Mounted by IslandManager from static IslandRegistry       │
├─────────────────────────────────────────────────────────────┤
│              SERVICES (in synmergia/core/services)          │
│  GameManager | EntityService | EventBus | TargetingMgr    │
│  NotificationService | ZoneManager | TradeService | etc.   │
├─────────────────────────────────────────────────────────────┤
│              COMPONENTS (in synmergia/core/components)      │
│  HealthComponent | CombatComponent | AuraComponent          │
│  AggroComponent | InventoryComponent                        │
├─────────────────────────────────────────────────────────────┤
│              DATA (in synmergia/data, .tres files)          │
│  skills/ | items/ | enemies/ | zones/ | targets/            │
├─────────────────────────────────────────────────────────────┤
│              MULTI-ISO ORCHESTRATOR (in labs/multi-iso)    │
│  Spatial ∩ Faction ∩ Temporal ∩ Social axes                │
│  Materialized intersection tables (LRU cache)               │
│  LOD pyramid + predictive prefetch (Markov)                 │
├─────────────────────────────────────────────────────────────┤
│              STATE TREE (in labs/multi-iso/kv)              │
│  Content-hash nodes | diff/apply | server tick = re-root   │
│  LRU cache | LRU intersection cache                         │
├─────────────────────────────────────────────────────────────┤
│              DURABLE STORAGE (Postgres + CDN)               │
│  state_snapshots (root hashes) | state (entities)           │
│  asset pcks by content-hash | migrations                   │
└─────────────────────────────────────────────────────────────┘
```

The game lives in the top three layers. The frame lives in the
bottom two. When the frame extracts, it takes the bottom two
layers with it.

## Project Structure

The repo has two top-level areas: the game (`synmergia/`) and
the frame (`labs/`). The game is the Godot project. The frame
is experimental work that could extract to its own repo.

```
.
├── synmergia/                  # the Godot 4.7.2 project
│   ├── core/
│   │   ├── autoload/           # Global singletons (GameManager, NetworkManager)
│   │   ├── components/         # Entity components (Health, Combat, Inventory, etc.)
│   │   ├── community/          # Community governance
│   │   ├── entities/           # Base entity classes
│   │   ├── schemas/            # Data schemas (Item, TargetSchema, Skill, etc.)
│   │   ├── services/           # Game services (30+ services)
│   │   ├── targeting/          # Targeting system (TargetingManager)
│   │   └── ui/                 # Core UI (UIManager)
│   ├── entities/               # Entity types (Player, Enemy, NPC)
│   ├── connectors/             # AI agent connectors (Vant, MCP, Claude, GPT)
│   ├── data/                   # Game resources (.tres files)
│   │   ├── targets/            # 6 target schemas
│   │   ├── enemies/            # Enemy templates
│   │   ├── zones/              # Zone definitions
│   │   ├── skills/             # Skill templates
│   │   ├── items/              # Item templates
│   │   ├── classes/            # Player classes
│   │   ├── species/            # Races
│   │   └── factions/           # Factions
│   ├── ui/                     # User interface
│   │   ├── admin/              # Admin dashboard
│   │   ├── community/          # Voting UI
│   │   ├── components/         # Common UI (UIStyles, ActionMenu, TooltipManager)
│   │   ├── islands/            # ⭐ UI Islands POC (PackedScene per panel)
│   │   ├── menus/              # Game menus
│   │   ├── social/             # Friends, Guild, Party, Trade UI
│   │   └── targeting/          # Target tooltip
│   └── tests/                  # Smoke tests (19/19 islands tests passing)
│
├── labs/                       # ⭐ Experimental work, root-level
│   ├── README.md               # the /labs/ convention
│   ├── prd.md                  # the modernized product spec
│   └── multi-iso/              # the multi-iso frame work (planned, see docs)
│       ├── math/               # NSC-9, icosahedral, quasicrystal (B-1)
│       ├── kv/                 # LRU, content_hash, state_tree (A-3)
│       ├── srv/                # markov, predictor, composite_table, LOD (B-6,7,8)
│       └── db/                 # snapshot_store, migrations (A-3)
│
├── docs/
│   └── architecture/           # Architecture design docs
│       ├── NEXT-AGENT-PICKUP.md         # survival guide for the next session
│       ├── multi-iso-frame.md           # Part 1: the multi-iso pattern
│       ├── multi-iso-lod-prediction.md  # Part 2: LOD + materialized + prediction
│       ├── labs-organization.md         # the /labs/ convention (long form)
│       ├── nsc9-honest-evaluation.md    # why geometry is a layer, not a replacement
│       ├── islands-builds-godot.md      # the Islands POC design
│       ├── unified-nsc9-islands-builds.md  # the original exploration
│       └── autoload-race-solutions.md   # the 4 candidate fixes
│
├── tools/
│   └── godot/                  # Godot editor / export helpers
│
├── ROADMAP.md                  # implementation tracker (1682 lines)
├── AGENTS.md                   # developer notes for AI agents
└── README.md                   # this file
```

The Godot project root is `synmergia/`. Open that folder in the
Godot editor. The `labs/` and `docs/` directories are outside
the project so they don't taint the stable build with
experimental work.

## Getting Started

### Prerequisites

- Godot 4.7.2 ([godotengine.org](https://godotengine.org))
- Android SDK (for mobile builds)

### Running the Project

1. Clone the repository
```bash
git clone https://github.com/dhaupin/synmergia.git
cd synmergia
```

2. Open in Godot 4.7.2
```bash
godot --editor synmergia/
```

3. Press F5 to run

### Building

#### Android
1. Go to Project > Export
2. Select Android preset
3. Click Export

#### Server
```bash
godot --headless --server --path res://
```

## Adding Content

### Add a New Skill
Create `synmergia/data/skills/skill_fireball.tres`:

```gdscript
[gd_resource type="Resource" script_class="Skill" load_steps=2 format=3]

[ext_resource type="Script" path="res://core/schemas/skill.gd" id="1"]

[resource]
script = ExtResource("1")
id = "fireball"
display_name = "Fireball"
description = "Hurls a ball of fire at enemies."
skill_type = 1  # RANGED
mana_cost = 30
damage = 100
range = 25.0
```

### Add a New Enemy
Create `synmergia/data/enemies/enemy_goblin.tres`:

```gdscript
[gd_resource type="Resource" script_class="EnemyData" load_steps=2 format=3]

[ext_resource type="Script" path="res://core/schemas/enemy.gd" id="1"]

[resource]
script = ExtResource("1")
id = "goblin"
display_name = "Goblin"
enemy_type = 0  # NORMAL
level = 5
health = 100
attack_power = 15
```

### Add a New Target Schema
Create `synmergia/data/targets/target_custom.tres` for targeting behavior:

```gdscript
[gd_resource type="Resource" script_class="TargetSchema" load_steps=2 format=3]

[ext_resource type="Script" path="res://core/schemas/target_schema.gd" id="1"]

[resource]
script = ExtResource("1")
id = "custom_target"
target_type = "enemy"
highlight_color = Color(1.0, 0.5, 0.0)  # Orange
show_health_bar = true
show_level = true
```

## Testing

Smoke tests live next to the code in `synmergia/tests/`. Each is a
`SceneTree` script that runs with `tools/godot --headless` and
prints a per-test pass/fail line plus a final summary.

```bash
# from the repo root
./tools/godot --headless --path synmergia --script res://tests/test_notification_toast.gd
./tools/godot --headless --path synmergia --script res://tests/test_hud_integration.gd
./tools/godot --headless --path synmergia --script res://tests/test_login_flow.gd
./tools/godot --headless --path synmergia --script res://tests/test_auto_response_signals.gd
```

| Test | Covers |
|------|--------|
| `test_notification_toast.gd` | NotificationService → TooltipManager.show_toast() end-to-end; RecursionGuard + CircuitBreaker integration. 11/11 |
| `test_hud_integration.gd` | HudIntegrator handlers, NotificationService → CombatLog round-trip. 7/7 |
| `test_login_flow.gd` | Account + login + character flow. 21/21 |
| `test_auto_response_signals.gd` | AutoResponseService `action_taken` / `player_warned` signals and ActionType enum. 8/8 |

Total: **47/47 green** as of 2026-09-01.

> **Note:** `--script` mode does not pre-load autoloads, so tests
> resolve them via `root.get_node_or_null("NotificationService")`
> rather than the global identifier. Pattern is shown in
> `AGENTS.md § Common Operations`.

## Data Structure

| Folder | Content | Example |
|--------|---------|---------|
| `data/skills/` | Combat skills | `skill_fireball.tres` |
| `data/items/` | Items | `item_health_potion.tres` |
| `data/enemies/` | Enemy templates | `enemy_goblin.tres` |
| `data/zones/` | World zones | `zone_forest.tres` |
| `data/targets/` | Targeting schemas | `target_enemy.tres` |
| `data/classes/` | Player classes | `class_warrior.tres` |
| `data/species/` | Species/races | `species_human.tres` |
| `data/factions/` | Factions | `faction_human.tres` |

## Services

Core services (autoloaded singletons):

| Service | Purpose |
|---------|---------|
| `GameManager` | Overall game state, player management |
| `EntityService` | Track all entities (players, enemies, NPCs) |
| `SpawnService` | Enemy/NPC spawning with metadata |
| `EventBus` | Central event hub |
| `NotificationService` | Player notifications and alerts |
| `TargetingManager` | Unified targeting system |
| `ZoneManager` | Zone transitions and state |
| `CombatMath` | Damage/effect calculations |
| `TradeService` | Item trading |
| `PartyService` | Party/raid management |
| `GuildService` | Guild management |
| `LootService` | Loot distribution |
| `ChatService` | Chat channels with range-based delivery |

## Agent Connectors

### MCP Connector
```gdscript
var connector = MCPConnector.new()
ConnectorService.register_connector(connector)
ConnectorService.connect_agent("agent_001", "mcp", {
    "server_url": "http://localhost:3000",
    "model": "claude-3-sonnet"
}, player_entity)
```

## Documentation

The full design space is twelve documents. They split into four
buckets:

**Product**
- [PRD](./labs/prd.md) — the modernized product spec, with the frame appendix

**Architecture** (in `docs/architecture/`)
- [multi-iso-frame.md](./docs/architecture/multi-iso-frame.md) — Part 1: the orchestrator pattern
- [multi-iso-lod-prediction.md](./docs/architecture/multi-iso-lod-prediction.md) — Part 2: LOD + materialized + prediction
- [grail-path.md](./docs/architecture/grail-path.md) — the pre-materialized orchestration contract (the read = lookup commitment)
- [vant-lift.md](./docs/architecture/vant-lift.md) — the lift manifest: 9 vant libs → multi-iso frame primitives
- [security.md](./docs/architecture/security.md) — 7 defense layers; recursion guard is the foundation; agent framework threat model
- [ui-framework.md](./docs/architecture/ui-framework.md) — the reactive bridge: AxisQuery + UIAction; one framework for humans + agents
- [scale-200km2.md](./docs/architecture/scale-200km2.md) — 8 innovations for the 200km² world (LOD pyramid, predictive prefetch, state diff sync, …)
- [nsc9-honest-evaluation.md](./docs/architecture/nsc9-honest-evaluation.md) — why geometry is a layer, not a replacement
- [labs-organization.md](./docs/architecture/labs-organization.md) — the `/labs/` convention (long form)

**UI & Build** (in `docs/architecture/`)
- [islands-builds-godot.md](./docs/architecture/islands-builds-godot.md) — the Islands POC design
- [unified-nsc9-islands-builds.md](./docs/architecture/unified-nsc9-islands-builds.md) — the original exploration
- [autoload-race-solutions.md](./docs/architecture/autoload-race-solutions.md) — the 4 candidate fixes for the cascade

**Operations** (root-level)
- [NEXT-AGENT-PICKUP.md](./docs/architecture/NEXT-AGENT-PICKUP.md) — survival guide for the next session
- [ROADMAP.md](./ROADMAP.md) — implementation tracker (1682 lines)
- [`labs/AUDIT.md.legacy`](./labs/AUDIT.md.legacy) — old session log (legacy, frozen 2026-08-30)
- [AGENTS.md](./AGENTS.md) — developer notes for AI agents (code conventions)

**Start here:** the [NEXT-AGENT-PICKUP](./docs/architecture/NEXT-AGENT-PICKUP.md) doc is the
entry point. It has a key-files table and a Track A / Track B
plan.

## Status

**Current phase:** Pre-vertical-slice.

- ✅ Phase 0: Foundation (services, components, .tres, AGENTS.md)
- ✅ Phase 0.5: UI modernization + Islands POC (19/19 tests)
- 🔄 Phase 0.6: Cleanup (parse errors, lint, helper rename)
- 📋 Phase 1: State tree + Track A foundation (NEXT)
- 📋 Phase 4: Track B (multi-iso frame research, parallel)

See [ROADMAP.md](./ROADMAP.md) and [labs/prd.md §13](./labs/prd.md#13-phases--milestones)
for the full breakdown.

## License

MIT License - See [LICENSE](LICENSE) for details.