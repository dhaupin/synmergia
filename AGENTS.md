# Synmergia - Developer Notes for AI Agents

> **Purpose:** This file is a **stable reference** for AI agents
> working on Synmergia. It documents code conventions, architecture,
> and patterns that don't change frequently.
>
> **What this file is NOT:** An operational log, debugging status,
> or session history.

> **Updated 2026-09-05:** Restructured to be a stable reference.
> Removed session logs, parse error status, and other rotting content.

---

## Project Overview

Synmergia is a Godot 4.7.2 based MMORPG with an authoritative
server architecture. The architecture has four layers:
**Godot client → Multi-iso orchestrator → State tree
(content-hash) → Postgres + cache**. The orchestrator and
state tree are the **frame**; they live in `/labs/` and can
extract to their own project.

- **Language:** GDScript
- **Engine:** Godot 4.7.2
- **Architecture:** Client + Authoritative Server + Multi-iso orchestrator + State tree
- **Game root:** `game/` (open this in the Godot editor)
- **Frame root:** `labs/` (experimental, root-level, NOT in Godot project)

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
  - `CommunityGovernance.Vote`
  - `CommunityGovernance.ModeratorProgression`
- **Signal naming:** verb past tense (`entity_spawned`, `player_left`)
- **Factory methods** for complex object creation
- **Service singletons** via autoload
- **Frame primitives** in `/labs/`: NO autoload, NO `class_name`, NO GameManager dependency

### Working with Code

**File Editing:**
- Shell commands and heredocs can be problematic to edit programmatically — prefer direct file edits when possible
- Pay close attention to indentation (GDScript uses tabs, not spaces)
- Always check for unclosed braces, parentheses, and quotes

**Code Standards:**
- Use **tabs** for indentation in GDScript files — `.editorconfig` enforces this
- **No UTF-8 special characters** in the codebase — they cause Godot import issues
- Use `TODO` comments for incomplete work or stubs
- Avoid legacy code, wrappers, and aliases — use current methods when available

**Implementation:**
- Wire and integrate features as you go — look for other code that could benefit from the same wiring
- **Work to completion** — avoid leaving code in a half-baked or non-functional state
- Use existing architecture, methodology, and systems — don't reinvent patterns or go rogue
- The system should function as a **cohesive unit**, not a scattered collection of unrelated pieces

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
| `FriendsService` | Friends list, requests, block/ignore |
| `QoSService` | Latency and rate limiting |
| `CommunityGovernance` | Voting, moderator progression |
| `BlacksmithService` | Item crafting/upgrading |

### Components (Attached to Entities)

| Component | Purpose |
|-----------|---------|
| `HealthComponent` | Health, death, respawn |
| `CombatComponent` | Combat state, skills, damage |
| `AuraComponent` | Buffs/debuffs |
| `AggroComponent` | Threat/aggro management |
| `InventoryComponent` | Item storage and equipment |

### UI Components

| Component | Purpose |
|-----------|---------|
| `UIStyles` | Common styling, colors, fonts |
| `UIPanel` | Base panel class with overlay |
| `ActionMenu` | Context menus (mouse/touch) |
| `TooltipManager` | Unified tooltip system |
| `MenuManager` | HUD management |
| `InventoryUI` | Player inventory grid |
| `BuffBar` | Buff/debuff display |
| `GuildUI` | Guild management |
| `PartyUI` | Party management |
| `TradeUI` | Item trading interface |

---

## Event Patterns

**Unified entity events carry `EventBus.SpawnMetadata`:**
```gdscript
# Signal signature:
entity_spawned.emit(entity: Entity, metadata: EventBus.SpawnMetadata)

# Handler must match:
func _on_entity_spawned(entity: Entity, metadata: EventBus.SpawnMetadata) -> void:
    pass
```

> **WARNING:** Mismatched signal handlers cause runtime errors. Always verify signatures.

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

### Sending Notifications

Use the **typed-Kind pipeline** (`NotificationService.notify()`) for
all service-level toasts. The frame handles dedupe, type-mapping, and
priority automatically based on the kind.

```gdscript
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

# To a specific player
NotificationService.notify(
    NotifKind.ITEM_ADDED,
    "Picked up Sword of Truth",
    "InventoryService",                       # source_service label
    "inv_add:%s:%s" % [player_id, item_id], # dedupe key (5s window)
    {"item_id": item_id, "rarity": "epic"},
    player_id                                 # recipient
)

# Server-wide / admin scope (recipient = "")
NotificationService.notify(
    NotifKind.ADMIN_ALERT,
    "RecursionGuard exceeded depth 16",
    "AppFirewall",
    "fw:%s" % message.hash(),
    {"context": "agent_tool_call", "depth": 16}
)
```

> **Don't** call `NotificationService.send_to_player()` directly for
> new code — that's the legacy path. Use `notify()` instead.

### Notification → Toast Pipeline
Every service-level event ends up in a toast panel in `HudLayer`:

```
Service → NotificationService.notify() → NotificationDispatcher → TooltipManager.show_toast()
```

When adding a new service:
- For **in-game state changes** (death, level-up, item equipped): emit a typed signal
- For **infrastructure events** (throttled, restricted, banned): call `notify()` so the player sees a toast

```gdscript
# GOOD (infrastructure): player must see the toast
NotificationService.notify(NotifKind.RATE_LIMITED, "You're casting too fast", "QoSService", ...)

# GOOD (in-game state): emit a signal
signal item_equipped(player_id: String, item_id: String)
item_equipped.emit(player_id, item_id)
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
.
├── game/                          # the Godot 4.7.2 project
│   ├── core/
│   │   ├── autoload/              # Global singletons
│   │   ├── components/            # Entity components
│   │   ├── community/             # Community governance
│   │   ├── entities/              # Base entity classes
│   │   ├── schemas/               # Data schemas
│   │   ├── services/              # Game services (30+)
│   │   ├── targeting/             # Targeting system
│   │   └── ui/                   # Core UI
│   ├── entities/                  # Entity types
│   ├── connectors/                # AI agent connectors
│   ├── data/                      # .tres resources
│   ├── ui/                        # User interface
│   └── tests/                     # Smoke tests
│
├── labs/                          # Frame + design docs
│   ├── prd.md                     # Product requirements
│   ├── world-building*.md         # World/architecture docs
│   └── multi-iso/                 # Frame primitives
│       ├── math/                  # NSC-9, icosahedral
│       ├── kv/                    # LRU, state_tree
│       ├── srv/                   # Markov, LOD, axis
│       └── db/                    # snapshot_store
│
├── srv/                           # Deployment configs (docker, certs)
├── ROADMAP.md                     # Implementation tracker
└── README.md                      # Project overview
```

The Godot project root is `game/`. The `labs/` directory is outside
the project so it doesn't taint the stable build with experimental work.

---

## Data Schemas

### TargetSchema (`data/targets/`)
- `target_player.tres`, `target_enemy.tres`, `target_npc.tres`
- `target_loot.tres`, `target_dwelling.tres`, `target_gateway.tres`

### EnemyData
- `enemy_type`: NORMAL, ELITE, BOSS, WORLD_BOSS
- `level`, `health`, `attack_power`, `defense`

### Item
- `soulbound`, `bind_on_pickup`, `bind_on_equip`
- `unique`, `stack_size`, `rarity`

### GM Classes
Three admin-only classes hidden from normal character selection:
- `gm_akkan`, `gm_human`, `gm_synthetic`
- All have `role = 0` (Role.GM)

GM visibility: `[GM]` prefix in chat, gold name color, `⭐ GAME MASTER` badge in tooltip.

---

## Labs Conventions

The `/labs/` directory is for experimental primitives that could
extract to the multi-iso frame. Different rules apply:

| Rule | Game (`game/`) | Frame (`labs/`) |
|------|-----------------|-----------------|
| Autoload | ✅ Yes | ❌ No |
| `class_name` | ✅ Yes | ❌ No |
| GameManager dep | ✅ Yes | ❌ No |
| Tests | Smoke tests | Co-located |

### Frame Primitive Rules
1. Each primitive is its own `.gd` file
2. Tests are co-located: `nsc9.gd` + `test_nsc9.gd`
3. No autoload, no `class_name`, no GameManager dependency
4. New code goes here first. The game consumes from here.

### Frame Contents
| Subdirectory | Contains | Examples |
|--------------|----------|----------|
| `labs/multi-iso/math/` | Pure functions. No state. | NSC-9 encoding, icosahedral projection |
| `labs/multi-iso/kv/` | In-memory data structures | LRU cache, content-hash, state tree |
| `labs/multi-iso/srv/` | Service logic | Markov chain, predictor, LOD manager |
| `labs/multi-iso/db/` | Database integration | snapshot_store, migrations |

See [`labs/README.md`](./labs/README.md) for the full conventions.

---

## Security: BBCode XSS

All `RichTextLabel` nodes have `bbcode_enabled = true`. User-supplied
strings embedded in BBCode format strings are a potential injection vector.

**Pattern to avoid:**
```gdscript
"[color=%s]%s[/color]" % [color, user_string]   # DANGEROUS
```

**The fix:** Replace `[` and `]` with full-width equivalents:
```gdscript
static func _esc(text: String) -> String:
    return text.replace("[", "［").replace("]", "］")
```

**Files with this pattern:**
- `core/services/chat_service.gd`
- `ui/components/combat_log.gd`
- `ui/components/chat_ui.gd`
- `ui/admin/admin_dashboard.gd`
- `core/admin/player_shell.gd`
- `core/autoload/logger.gd`
- `core/services/qos_service.gd`
- `core/services/security_service.gd`

When adding new `RichTextLabel` BBCode with user input, always pass it through `_esc()` first.

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

### Defensive Helper Pattern
When a helper bridges two services, prefer try-known-methods fallback:
```gdscript
func _get_peer_for_player(player_id: String) -> int:
    if PlayerManager == null:
        return -1
    for method_name in ["get_player_info", "get_player", "find_player"]:
        if PlayerManager.has_method(method_name):
            var result = PlayerManager.call(method_name, player_id)
            if result is Dictionary:
                var info: Dictionary = result
                var peer_id = info.get("peer_id", -1)
                if peer_id is int and peer_id > 0:
                    return peer_id
    return -1
```

### Godot GDScript Rules
- **`extends` must precede `class_name`** when both are present
- **Mixed indentation is fatal:** Once a file uses tabs, every subsequent line must use tabs
- **Inner class methods cannot call outer class methods** without qualification
- **`extends Control` for scene-instantiated UIs:** Use `extends Control` + manual stubs for UIPanel methods

---

## Testing

Smoke tests live in `game/tests/`. Run with Godot headless:

```bash
cd game
godot --headless --path . --script res://tests/test_notification_toast.gd
godot --headless --path . --script res://tests/test_hud_integration.gd
godot --headless --path . --script res://tests/test_login_flow.gd
godot --headless --path . --script res://tests/test_auto_response_signals.gd
```

Or run all tests via Docker (see [DEPLOY.md](./DEPLOY.md)):

```bash
docker run --rm -e START_MODE=test synmergia
```

| Test | Coverage |
|------|----------|
| `test_notification_frame.gd` | NotificationService frame (context, kind, dedupe) |
| `test_notification_toast.gd` | NotificationService → TooltipManager.show_toast() end-to-end |
| `test_hud_integration.gd` | HudIntegrator handlers, NotificationService → CombatLog |
| `test_login_flow.gd` | Account + login + character flow |
| `test_auto_response_signals.gd` | AutoResponseService signals and ActionType enum |
| `test_islands.gd` | Core island logic (island_poc.gd) |
| `test_e2e_flow.gd` | End-to-end account flow |
| `test_notif_migration_*.gd` | Notification migration tests |

> **Note:** `--script` mode does not pre-load autoloads. Resolve them via
> `root.get_node_or_null("NotificationService")` rather than the bare identifier.

---

## Key Godot Rules

1. **Entity autoload is REQUIRED:** Entity must be in `[autoload]` section BEFORE RegisterTypes
2. **Use `load()` for runtime class instantiation** when ClassName is the same file:
   ```gdscript
   # Instead of:
   var book := SkillBook.new()
   
   # Use:
   var script := load("res://core/schemas/skill_book.gd")
   var book = script.new()
   ```

---

## GDScript 4 Gotchas

Common mistakes agents make with GDScript:

```gdscript
# Scene instantiation — use instantiate(), NOT .instance()
var instance := preload("res://scene.tscn").instantiate()  # ✓
var instance := preload("res://scene.tscn").instance()     # ✗ (Godot 3)

# Script instantiation — use load(), NOT preload() with class_name
var book := load("res://schemas/SkillBook.gd").new()  # ✓
var book := preload("res://schemas/SkillBook.gd").new()  # ✗ (loads at parse time)

# Node removal — use queue_free(), NOT free()
instance.queue_free()  # ✓ (safe, deferred)
instance.free()        # ✗ (can break children cleanup)

# Null checks — always validate with is_instance_valid()
if node != null and is_instance_valid(node):  # ✓
if node != null:                              # ✗ (stale references)

# String formatting — use f-strings
var msg := f"Hello {name}"       # ✓ (Godot 4+)
var msg := "Hello %s" % name     # ✗ (outdated)
```

---

## Autoloads

Autoloads are singleton services available globally. The naming convention is:

| Aspect | Rule | Example |
|--------|------|---------|
| Filename | `snake_case.gd` | `notification_service.gd` |
| Autoload name | `PascalCase` | `NotificationService` |
| class_name | Optional (some autoloads have it) | `QoSService` has it |

### Accessing Autoloads

```gdscript
# Correct: use the autoload name directly (it's already an instance)
NotificationService.notify(...)
QoSService.rate_limit(player_id, "combat")

# Wrong: trying to create a new instance
var ns := NotificationService.new()  # ✗ FAILS - autoloads are not classes
```

### When to Use class_name

Only add `class_name` for classes you need to instantiate or type-check:

```gdscript
# GOOD: class_name for a utility class you instantiate
class_name CombatMath
func calculate_damage() -> float:
    return base_damage * multiplier

# Usage:
var math := CombatMath.new()
var dmg := math.calculate_damage()

# GOOD: class_name for type checking
class_name AchievementService
func process_achievement(service: AchievementService) -> void:
    pass

# Some autoloads DO have class_name (needed for identifier resolution)
# Just don't try to .new() them — they're already instantiated
```

### Key Rules

1. **Autoloads are singletons** — accessed by name, never instantiated
2. **Autoloads may need `class_name`** — some code uses the autoload name as a type identifier (e.g., `if service is QoSService`)
3. **`class_name` only for classes you `new()` or use for typing**
4. **Filename ≠ class name** — `notification_service.gd` has autoload `NotificationService`, not `NotificationServiceService`
