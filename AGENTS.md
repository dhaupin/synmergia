# Synmergia - Developer Notes for AI Agents

## Project Overview

Synmergia is a Godot 4.2+ based MMORPG with an authoritative server architecture.
- **Language:** GDScript
- **Engine:** Godot 4.2+
- **Architecture:** Client + Authoritative Server

---

## Code Style Conventions

### Indentation
- **GDScript files (.gd)**: Use **tabs** (not spaces)
- Tab width: 4 characters visually
- `.editorconfig` is configured for automatic enforcement

### Naming Conventions
- Files: `snake_case.gd`
- Classes: `PascalCase`
- Signals: `entity_spawned`, `player_joined`, `target_acquired`
- Enums: `PascalCase.VALUE` (e.g., `Entity.EntityType.PLAYER`)
- Constants: `SCREAMING_SNAKE_CASE`

### Code Patterns
- **Inner classes** for related utilities:
  - `EventBus.SpawnMetadata`
  - `NotificationService.AlertScope`
  - `NotificationService.NotificationType`
- **Signal naming:** verb past tense (`entity_spawned`, `player_left`)
- **Factory methods** for complex object creation
- **Service singletons** via autoload

---

## Architecture

### Core Services (Autoloaded)

| Service | Purpose |
|---------|---------|
| `GameManager` | Overall game state, player management |
| `EntityService` | Track all entities (players, enemies, NPCs) |
| `SpawnService` | Enemy/NPC spawning with metadata |
| `EventBus` | Central event hub with unified entity signals |
| `NotificationService` | Player notifications and alerts |
| `TargetingManager` | Unified targeting system |
| `ZoneManager` | Zone transitions and state |
| `CombatMath` | Damage/effect calculations |
| `TradeService` | Item trading |
| `PartyService` | Party/raid management |
| `GuildService` | Guild management |
| `LootService` | Loot distribution |
| `ChatService` | Chat channels with range-based delivery |
| `InventoryService` | Player inventory management |
| `RespawnService` | Player respawn logic |
| `FactionManager` | Faction relationships and PvP modes |
| `AutoResponseService` | Admin alerts and moderation |
| `SecurityService` | Anti-cheat and rate limiting |

### Components (Attached to Entities)

| Component | Purpose |
|-----------|---------|
| `HealthComponent` | Health, death, respawn |
| `CombatComponent` | Combat state, skills, damage |
| `AuraComponent` | Buffs/debuffs |
| `AggroComponent` | Threat/aggro management |
| `InventoryComponent` | Item storage and equipment |

### Event Patterns

**Unified entity events carry `EventBus.SpawnMetadata`:**
```gdscript
# Signal signature:
entity_spawned.emit(entity: Entity, metadata: EventBus.SpawnMetadata)

# Handler must match:
func _on_entity_spawned(entity: Entity, metadata: EventBus.SpawnMetadata) -> void:
    pass
```

**WARNING:** Mismatched signal handlers cause runtime errors. Always verify signatures.

---

## Common Operations

### Creating Spawn Metadata
```gdscript
var metadata := EventBus.SpawnMetadata.world_boss("Dragon", "zone_1", position, 50)
```

### Accessing Enums
```gdscript
# SpawnMetadata types
var type := EventBus.SpawnMetadata.SpawnType.BOSS
var priority := EventBus.SpawnMetadata.NotificationPriority.CRITICAL

# Entity types
if target.entity_type == Entity.EntityType.PLAYER:
    pass

# Notification types
NotificationService.NotificationType.WARNING
NotificationService.NotificationType.ALERT
```

### Checking Item Tradeability
```gdscript
if TradeService.can_trade_item(item):
    # Item can be traded
```

### Sending Notifications
```gdscript
# To a specific player
NotificationService.send_to_player(player_id, "Hello!", NotificationService.NotificationType.INFO)

# Server-wide alert
NotificationService.broadcast_alert(
    "Server announcement!",
    [NotificationService.AlertScope.server_wide()],
    NotificationService.NotificationType.ALERT
)
```

### Getting Nearby Players (Chat Range)
```gdscript
# For SAY/YELL chat channels
var nearby_players := ChatService._get_players_in_channel_range(sender_id, ChatService.Channel.SAY)
```

### Range-Based Entity Queries
```gdscript
var nearby := EntityService.get_entities_in_radius(
    player.global_position,
    20.0,  # range
    Entity.EntityType.PLAYER
)
```

---

## File Organization

```
synmergia/
├── core/
│   ├── autoload/       # Global singletons (GameManager, NetworkManager)
│   ├── components/     # Entity components (Health, Combat, Inventory, etc.)
│   ├── entities/       # Base entity classes
│   ├── schemas/        # Data schemas (Item, TargetSchema, Skill, etc.)
│   ├── services/       # Game services (30+ services)
│   ├── targeting/      # Targeting system (TargetingManager)
│   └── ui/             # Core UI (UIManager)
├── entities/           # Entity types (Player, Enemy, NPC)
├── connectors/        # AI agent connectors
├── data/              # Game resources (.tres files)
│   ├── targets/        # Target schemas (6 schemas)
│   ├── enemies/         # Enemy templates
│   └── zones/           # Zone definitions
└── ui/                # User interface
    └── targeting/      # Target tooltip
```

---

## Data Schemas

### TargetSchema
Located in `data/targets/`. Defines targeting behavior per entity type:
- `target_player.tres`
- `target_enemy.tres`
- `target_npc.tres`
- `target_loot.tres`
- `target_dwelling.tres`
- `target_gateway.tres`

### EnemyData
Enemy templates with:
- `enemy_type`: NORMAL, ELITE, BOSS, WORLD_BOSS
- `level`, `health`, `attack_power`, `defense`

### Item
Items with:
- `soulbound`, `bind_on_pickup`, `bind_on_equip`
- `unique`, `stack_size`, `rarity`

---

## Important Patterns

### Null Checks for Services
Always check if a service exists before using:
```gdscript
if NotificationService:
    NotificationService.send_to_player(player_id, message)
```

### Instance Validation
Always validate entities before use:
```gdscript
if is_instance_valid(entity) and entity.entity_id != sender_id:
    # safe to use
```

### Signal Handler Matching
**CRITICAL:** Signal handlers MUST match the signal signature exactly:
```gdscript
# WRONG (will error at runtime):
func _on_entity_spawned(entity: Entity) -> void:
    pass

# CORRECT:
func _on_entity_spawned(entity: Entity, metadata: EventBus.SpawnMetadata) -> void:
    pass
```

---

## Testing

1. Open project in Godot 4.2+ editor
2. Press F5 to run
3. Check console for signal connection errors
4. Verify entity spawning and targeting

---

## Gotchas

- **Enums:** Use `Service.EnumClass.VALUE` not `Service.AlertType` (doesn't exist)
- **Tabs:** Use tabs for indentation, not spaces (per `.editorconfig`)
- **Metadata:** Always pass metadata with entity signals for decoupled routing
- **Bounds:** Check `bind_on_pickup`, `soulbound` before allowing trades
