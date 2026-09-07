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
| `StarterKitService` | New character starting equipment |

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
│   ├── scenes/                    # .tscn scenes (world, NPCs)
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
- `ui/components/dialog_ui.gd`
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

### NPC Scene Pattern
NPC entities use `scene_path` in NPCData to specify their `.tscn`:
```gdscript
# NPCData schema
@export var scene_path: String = ""  # Path to NPC .tscn scene

# SpawnService loads the scene and configures it:
if npc_data.scene_path:
    var packed := load(npc_data.scene_path) as PackedScene
    var entity := packed.instantiate() as NPCEntity
```

### Player Spawn Signal
Use `GameManager.player_entered_world` to trigger services when a player enters:
```gdscript
# Connect in your service:
GameManager.player_entered_world.connect(_on_player_entered)

func _on_player_entered(player_id: String, character_data) -> void:
    # Give starter items, initialize player state, etc.
```

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

## Autoloads and class_name

Autoloads are singleton services available globally. `class_name` registers a
script's type as a global identifier. **They look identical when you write
code but behave very differently.** Misuse causes silent runtime errors
(null instance, wrong method dispatch) that cascade through `_ready` and
look like parse errors elsewhere.

**The two rules:**

1. **Autoload name and `class_name` MUST NOT be the same string.** The
   autoload identifier shadows the class_name; you lose the ability to
   call `X.new()` or `extends X` reliably. One of them wins, the parser
   does not warn, and the loser silently does the wrong thing.

2. **Autoloads cannot be instantiated.** `X.new()` on an autoload
   identifier fails at runtime (autoloads are Nodes, not Scripts).
   To make a fresh instance, `load("res://path.gd").new()`.

### Naming

| Aspect | Rule | Example |
|--------|------|---------|
| Filename | `snake_case.gd` | `notification_service.gd` |
| Autoload name | `PascalCase` | `NotificationService` |
| `class_name` | Pick one of: omit it OR rename it differently from the autoload | `class_name NotifDispatcher` is OK; `class_name NotificationService` is NOT if `NotificationService` is also an autoload |

### When to add `class_name`

Add `class_name` when you need to:

- **Instantiate**: `var x := MyClass.new()` (the class is not an autoload)
- **Type-annotate a parameter or variable**: `func process(e: MyClass)`
- **Type-check at runtime**: `if node is MyClass`

Do **not** add `class_name` when the script is an autoload, unless you have
a concrete reason (see below). Autoloads are already globally accessible by
their autoload name; adding `class_name X` where X is also the autoload name
creates a shadow.

### The one case where `class_name` on an autoload is legitimate

If a file is an autoload AND is also extended by other classes (e.g.
`extends Entity` where `Entity` is an autoload), then `class_name Entity`
on the base script is needed so the parser can resolve the parent type
in the `extends` statement. But this is a **smell**: the script is doing
two things (base class + autoload singleton). If you find yourself here,
consider:

- **Option A**: Split. Make the base class its own file (no autoload),
  have the autoload be a small wrapper that `extends BaseClass` and adds
  the singleton state. Other code does `extends BaseClass` and
  `BaseClass.new()`. No shadow.
- **Option B**: Keep `class_name`, but use the autoload ONLY for the
  singleton globals (logger, registry, dispatcher) and never call
  `Entity.new()`. To spawn new entities, use a dedicated subclass
  (`class_name EnemyEntity extends Entity` in a separate file) or
  `load("res://core/entities/entity.gd").new()`.

The current code uses **Option B** for `Entity`: `class_name Entity`
in the autoload file, and `Entity.new()` is called from `spawn_service.gd`.
**This is a latent bug.** It works only by accident in current Godot
4.7.2 because `class_name` resolution beats the autoload identifier in
some code paths but not others. Do not add new code that relies on
`Entity.new()`. Use a subclass or `load(...).new()`.

### Accessing autoloads

```gdscript
# Correct: use the autoload name directly (it's already an instance)
NotificationService.notify(...)
QoSService.rate_limit(player_id, "combat")

# Correct: type-check via the autoload name (no class_name needed)
if node.get_parent() == GameManager:
    pass

# Correct: type-annotate a parameter using the autoload name
func process(svc: NotificationService) -> void:
    pass

# Wrong: trying to create a new instance of an autoload
var ns := NotificationService.new()  # FAILS at runtime

# Correct: instantiate a non-autoload class
var math := CombatMath.new()         # class_name CombatMath, no autoload
```

### Extending an autoload's script

```gdscript
# If the autoload file has class_name, this works:
extends Entity  # requires class_name Entity in entity.gd
class_name EnemyEntity

# If the autoload file does NOT have class_name, you must preload:
const EntityScript = preload("res://core/entities/entity.gd")
extends EntityScript
class_name EnemyEntity
```

Preload is more verbose but removes the shadowing risk. Prefer it when
the base script is an autoload.

### Autoload order

The autoload list in `project.godot` is the load and `_ready` order. Top
to bottom. If autoload A's `_ready` calls a method on autoload B, then
A must be listed **after** B. Get this wrong and you get:

```
Attempt to call function 'X' on a null instance
```

This error is misleading. It points to the *caller* (A) but the *cause*
is the *callee* (B) not being ready. Walking the call stack backward
often reveals the real problem.

To check autoload order:

```bash
awk '/^\[autoload\]/{flag=1; next} /^\[/{flag=0} flag' game/project.godot \
  | grep -oP '^\w+(?==)'
```

To detect forward references (autoload using another that comes later
in the list), scan each autoload's source for bare references to other
autoload names. A reference like `GameManager.foo` in `QoSService.gd`
is a forward reference if `GameManager` is listed after `QoSService`
in the autoload list.

### Cycles

Three flavors of cycle, all silent:

1. **`_ready` cycle**: A._ready() calls B.method(), B._ready() calls
   A.method(). Both fail with null instance. No "circular dependency"
   diagnostic. Fix: defer the cross-service calls with
   `call_deferred()` or `await get_tree().process_frame`.

2. **Preload cycle**: A preloads B, B preloads A. Parse error in both
   files. The error message names both, but the root cause is the
   cycle, not the parse error. Fix: extract a third file C that both A
   and B depend on, or use `load()` (runtime) instead of `preload()`
   (parse-time) for one of the references.

3. **Autoload name cycle**: A's autoload entry references B (via direct
   call in `_ready`), B's references A. Same null instance error as
   case 1. Fix: same as case 1.

### When you cannot `extends` an autoload

You cannot use an autoload as the parent class in `extends`. The autoload
is a singleton instance, not a script type. If you need to extend the
script that backs an autoload, you must give that script a `class_name`
(no name collision with the autoload) or preload it.

### Self-recovery playbook (when in a loop)

If the project won't load and you're seeing a cascade of errors:

1. **Stop and identify the FIRST parse error.** Godot reports many
   files failed; usually one is the root cause and the rest are
   downstream. Read the error list top to bottom.

2. **For each candidate root file, check**:
   - Does the file have `class_name X` where X is also an autoload?
     Remove the `class_name` or rename the autoload.
   - Is the file trying `X.new()` where X is an autoload? Use
     `load("res://path.gd").new()` or refactor to a subclass.
   - Does the file extend an autoload's script? Add `class_name` to
     the parent (no collision) or use `preload(...).new()`.
   - Does the file reference an autoload that comes LATER in
     `project.godot`? Move the reference to `call_deferred` or move
     the autoload up in the list.
   - Is the file using a reserved keyword as a variable name
     (`class_name`, `signal`, `func`)? Rename it.
   - Mixed indentation (tabs vs spaces)? Run `cat -A file.gd` to see
     the actual whitespace; pick one and stick to it.
   - `Resource.get("key", default)` parse error? In 4.7.2, default
     args to `Resource.get` were removed. Use `if resource.has(key)`
     guard or `resource.get(key, null)`.
   - Type inference on ternary (`var x := a if cond else b`)? Add
     explicit type: `var x: T = a if cond else b`.

3. **If the file itself is unrecoverable**, do NOT delete the
   business logic as a first resort. Instead:
   - `git stash` to save the working file
   - Reduce the file to: `## Header\nextends Node\nconst Deps = preload(...)`
   - Verify the rest of the project loads
   - Restore the file piece by piece (or use `git checkout HEAD~1 -- file`)
     to find which lines reintroduce the error

4. **Last resort: gut the file.** Only acceptable if (a) the file is
   not on the critical path for the boot sequence, (b) you've checked
   that no other file preloads it, and (c) you record the deletion
   in the commit message with `BREAKING:` so a future agent can
   restore it from history. The pattern:
   ```
   ## OldName - what it did
   ## One-line summary of what was lost
   extends Node
   const Dep = preload("res://path.gd")
   ```
   This is a 3-line stub that does not cascade.

5. **If a stub was created, file a follow-up** to restore the
   implementation. The git history (`git log --all -- path/to/file.gd`)
   has every prior version.

### Diagnostic commands

```bash
# List autoloads in order
awk '/^\[autoload\]/{flag=1; next} /^\[/{flag=0} flag' game/project.godot \
  | grep -oP '^\w+(?==)'

# Find class_name collisions with autoloads
awk '/^\[autoload\]/{flag=1; next} /^\[/{flag=0} flag' game/project.godot \
  | grep -oP '^\w+(?==)' | sort -u \
  | while read a; do
      grep -lP "^\s*class_name\s+${a}\s*$" game/ -r --include="*.gd"
    done

# Find .new() calls on autoload names
# (autoloads are PascalCase; bare class_names are also PascalCase; this
#  returns all .new() calls; manually filter for autoloads)
grep -rEn "\b[A-Z]\w+\.new\(\)" game/ --include="*.gd"

# Find tabs vs spaces in a file
cat -A game/path/to/file.gd | head -5  # ^I = tab, $ = end of line
```
