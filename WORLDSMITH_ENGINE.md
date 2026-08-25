# WorldSmith Engine

> A generalized 3D game engine built on Godot 4.2+, designed for MMORPGs with AI agent support.

[![Godot 4.2+](https://img.shields.io/badge/Godot-4.2+-blue)](https://godotengine.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Features

### Core Engine Features
- **Event-Driven Architecture** - Services, components, and event bus for clean separation
- **Data-Driven Design** - Drop `.tres` files to add content (skills, items, enemies, etc.)
- **3D Combat System** - Skills, projectiles, AoE, buffs/debuffs, status effects
- **Entity-Component System** - Flexible entity composition with attachable components
- **AI State Machine** - Built-in enemy AI with configurable behaviors

### Species & Factions
- **Species System** - Races with stat modifiers and cross-species relationships
- **Faction System** - PvP rules, reputation, political alliances
- **Zone PvP Modes** - SAFE, SPECIES_PVP, FACTION_PVP, FREE_PVP, WARZONE

### AI Agent Support (Connectors)
- **Agent Connectors** - Connect AI agents (Vant, Claude, GPT, Gemini) to play
- **MCP Protocol** - Model Context Protocol support for standard AI interfaces
- **Observation/Action Space** - Structured game state for agent decision-making

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AGENT CONNECTORS                           │
│  Vant | MCP | Claude | OpenAI | Gemini | Custom            │
├─────────────────────────────────────────────────────────────┤
│                    SERVICES (Autoloaded)                     │
│  EventBus | DataService | EntityService | ConnectorService  │
├─────────────────────────────────────────────────────────────┤
│                    COMPONENTS (Attached)                    │
│  Health | Combat | Aura | Aggro | Inventory                  │
├─────────────────────────────────────────────────────────────┤
│                    DATA (Resource Files)                    │
│  skills/ | items/ | weapons/ | armors/ | enemies/ | etc.   │
└─────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### 1. Clone the Engine
```bash
git clone https://github.com/dhaupin/world-smith.git
cd world-smith
```

### 2. Open in Godot
```bash
godot --editor godot-project/
```

### 3. Run the Project
Press `F5` in Godot to run the demo scene.

---

## Adding Content

### Add a New Skill
Create `godot-project/data/skills/skill_fireball.tres`:

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

### Add a New Weapon
Create `godot-project/data/weapons/wep_dragon_slayer.tres`:

```gdscript
[gd_resource type="Resource" script_class="Item" load_steps=2 format=3]

[ext_resource type="Script" path="res://core/schemas/item.gd" id="1"]

[resource]
script = ExtResource("1")
id = "dragon_slayer"
display_name = "Dragon Slayer"
description = "A legendary blade forged to slay dragons."
rarity = 4  # LEGENDARY
weapon_type = 1  # SWORD
weapon_damage_min = 150
weapon_damage_max = 250
stats = {
    "strength": 50,
    "vitality": 30
}
```

### Add a New Species
Create `godot-project/data/species/species_dragonborn.tres`:

```gdscript
[gd_resource type="Resource" script_class="Species" load_steps=2 format=3]

[ext_resource type="Script" path="res://core/schemas/species.gd" id="1"]

[resource]
script = ExtResource("1")
id = "dragonborn"
display_name = "Dragonborn"
description = "Proud warriors with dragon ancestry."
stat_modifiers = {
    "strength": 10,
    "vitality": 5
}
allied_species = ["human", "elf"]
hostile_species = ["undead"]
```

---

## Agent Connectors

### Vant Connector
Connect to Vant AI runtime:
```gdscript
var connector = VantConnector.new()
ConnectorService.register_connector(connector)
ConnectorService.connect_agent("agent_001", "vant", {
    "api_url": "http://localhost:8080",
    "api_key": "your-key"
}, player_entity)
```

### MCP Connector
Connect via Model Context Protocol:
```gdscript
var connector = MCPConnector.new()
ConnectorService.register_connector(connector)
ConnectorService.connect_agent("agent_002", "mcp", {
    "server_url": "http://localhost:3000",
    "model": "claude-3-sonnet"
}, player_entity)
```

---

## Data Structure

| Folder | Content | Example |
|--------|---------|---------|
| `data/skills/` | Combat skills | `skill_fireball.tres` |
| `data/items/` | Generic items | `item_quest_key.tres` |
| `data/weapons/` | Weapons | `wep_iron_sword.tres` |
| `data/armors/` | Armor pieces | `arm_plate_chest.tres` |
| `data/accessories/` | Rings, cloaks | `acc_ring_power.tres` |
| `data/consumables/` | Potions, food | `potion_health.tres` |
| `data/resources/` | Crafting mats | `res_iron_ore.tres` |
| `data/events/` | Global events | `event_2x_xp.tres` |
| `data/dwellings/` | Housing items | `dwel_table_oak.tres` |
| `data/misc/` | Misc items | `misc_coin_ancient.tres` |
| `data/enemies/` | Enemy templates | `enemy_goblin.tres` |
| `data/classes/` | Player classes | `class_warrior.tres` |
| `data/species/` | Species/races | `species_human.tres` |
| `data/factions/` | Factions | `faction_human.tres` |
| `data/zones/` | World zones | `zone_starter.tres` |

---

## Creating a Custom Game

1. **Fork this repository**
2. **Remove/rename demo content** in `data/` folders
3. **Add your game content** using the schema patterns
4. **Configure connectors** for AI agents (optional)
5. **Build your game scenes** in Godot

---

## License

MIT License - See [LICENSE](LICENSE) for details.

---

## Links

- [WorldSmith Game](https://github.com/dhaupin/world-smith) - The MMORPG built on this engine
- [Vant Runtime](https://github.com/vant-project/vant) - AI agent runtime
- [Godot Engine](https://godotengine.org) - The game engine
