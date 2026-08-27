# Synmergia

An open-world MMORPG built with Godot 4.2+, inspired by RYL2 combat and Ultima Online depth.

> **Engine:** A generalized 3D game engine designed for MMORPGs with AI agent support.

[![Godot 4.2+](https://img.shields.io/badge/Godot-4.2+-blue)](https://godotengine.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Features

### Core Engine Features
- **Event-Driven Architecture** - Services, components, and event bus for clean separation
- **Data-Driven Design** - Drop `.tres` files to add content (skills, items, enemies, etc.)
- **3D Combat System** - Skills, projectiles, AoE, buffs/debuffs, status effects
- **Entity-Component System** - Flexible entity composition with attachable components
- **Targeting System** - Data-driven targeting with configurable schemas

### Species & Factions
- **Species System** - Races with stat modifiers and cross-species relationships
- **Faction System** - PvP rules, reputation, political alliances
- **Zone PvP Modes** - SAFE, SPECIES_PVP, FACTION_PVP, FREE_PVP, WARZONE

### AI Agent Support (Connectors)
- **Agent Connectors** - Connect AI agents (Vant, Claude, GPT, Gemini) to play
- **MCP Protocol** - Model Context Protocol support for standard AI interfaces
- **Observation/Action Space** - Structured game state for agent decision-making

## Tech Stack

- **Engine:** Godot 4.2+ (MIT License)
- **Language:** GDScript
- **Platforms:** Android, iOS, PC
- **Architecture:** Client + Authoritative Server

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AGENT CONNECTORS                           │
│  Vant | MCP | Claude | OpenAI | Gemini | Custom            │
├─────────────────────────────────────────────────────────────┤
│                    SERVICES (Autoloaded)                     │
│  EntityService | SpawnService | EventBus | TargetingMgr    │
│  NotificationService | ZoneManager | TradeService | etc.   │
├─────────────────────────────────────────────────────────────┤
│                    COMPONENTS (Attached)                    │
│  HealthComponent | CombatComponent | AuraComponent          │
│  AggroComponent | InventoryComponent                        │
├─────────────────────────────────────────────────────────────┤
│                    DATA (Resource Files)                    │
│  skills/ | items/ | enemies/ | zones/ | targets/            │
└─────────────────────────────────────────────────────────────┘
```

## Project Structure

```
synmergia/
├── core/
│   ├── autoload/       # Global singletons (GameManager, NetworkManager)
│   ├── components/     # Entity components (Health, Combat, Inventory, etc.)
│   ├── schemas/        # Data schemas (Item, TargetSchema, Skill, etc.)
│   ├── services/       # Game services (30+ services)
│   ├── targeting/      # Targeting system (TargetingManager)
│   └── ui/             # Core UI (UIManager)
├── entities/           # Entity types (Player, Enemy, NPC)
├── connectors/        # AI agent connectors
├── data/              # Game resources (.tres files)
│   ├── targets/        # Target schemas for targeting system
│   ├── enemies/        # Enemy templates
│   └── zones/          # Zone definitions
└── ui/                # User interface
    └── targeting/      # Target tooltip and UI
```

## Getting Started

### Prerequisites

- Godot 4.2+ ([godotengine.org](https://godotengine.org))
- Android SDK (for mobile builds)

### Running the Project

1. Clone the repository
```bash
git clone https://github.com/dhaupin/synmergia.git
cd synmergia
```

2. Open in Godot 4.2+
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

- [PRD](./prd-synmergia.md) - Full product requirements
- [ROADMAP](./ROADMAP.md) - Development roadmap
- [AGENTS](./AGENTS.md) - Developer notes for AI agents

## License

MIT License - See [LICENSE](LICENSE) for details.