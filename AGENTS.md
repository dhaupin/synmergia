# Synmergia Agent Memory

## Project Overview
Synmergia is a Godot-based MMO game server implementation in GDScript.

## Code Style Conventions

### Indentation
- **GDScript files (.gd)**: Use **tabs** (not spaces)
- Godot's default uses tabs for accessibility
- Tab width: 4 characters visually
- `.editorconfig` is configured for automatic enforcement

### Code Patterns
- Inner classes for related utilities (e.g., `EventBus.SpawnMetadata`, `NotificationService.AlertScope`)
- Signal naming: `entity_spawned`, `player_joined`, etc.
- Factory methods for complex object creation
- Service singletons via autoload

## Architecture Notes

### Core Services
- `EntityService`: Tracks all entities (players, enemies, NPCs)
- `SpawnService`: Spawns enemies with `SpawnMetadata`
- `NotificationService`: Player notifications and alerts
- `EventBus`: Central event hub with unified entity signals
- `TargetingManager`: Handles targeting with data-driven schemas

### Event Patterns
- Unified entity events carry `EventBus.SpawnMetadata` for decoupled routing
- Signal handlers must match signature: `func _on_event(entity: Entity, metadata: EventBus.SpawnMetadata)`

## File Organization
```
synmergia/
├── core/
│   ├── autoload/       # Global singletons (GameManager, NetworkManager, etc.)
│   ├── components/     # Entity components (Health, Combat, Inventory, etc.)
│   ├── schemas/        # Data schemas (Item, TargetSchema, etc.)
│   └── services/       # Game services
├── entities/           # Entity types (Player, Enemy, NPC)
└── ui/                 # UI components
```

## Common Operations

### Creating Spawn Metadata
```gdscript
var metadata := EventBus.SpawnMetadata.world_boss("Dragon", "zone_1", position, 50)
```

### Accessing Enums
```gdscript
var priority := EventBus.SpawnMetadata.NotificationPriority.CRITICAL
var type := EventBus.SpawnMetadata.SpawnType.BOSS
```

### Checking Item Tradeability
```gdscript
if TradeService.can_trade_item(item):
    # allow trade
```

## Testing
- Run Godot editor with project to test
- Check signal connections match handler signatures
