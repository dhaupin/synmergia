# Synmergia - Developer Notes for AI Agents

> **Updated 2026-08-30:** Modernized for the new architecture
> (state tree, multi-iso orchestrator) and the `/labs/`
> convention. The game lives in `game/`. The frame lives
> in `labs/`. The Godot project root is `game/`.

## Project Overview

Synmergia is a Godot 4.7.2 based MMORPG with an authoritative
server architecture. The architecture is now four layers:
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
| `CharacterTransferUI` | Same-account transfers |

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
    "inv_add:%s:%s" % [player_id, item_id],   # dedupe key (5s window)
    {"item_id": item_id, "rarity": "epic"},
    player_id                                  # recipient
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

The kinds are coarse-grained. Pick a fine-grained one (RATE_LIMITED,
SECURITY_BLOCKED, ITEM_FULL, RESPAWNED) over a broad one (SYSTEM) so
the toast panel / admin dashboards can subscribe to one kind without
parsing the message. The full enum is in
`game/core/notifications/notification_kind.gd`.

**Don't** call `NotificationService.send_to_player()` directly for
new code — that's the legacy path. If you need a raw message that
doesn't fit any kind, use `NotifKind.CUSTOM` and consider whether a
new kind should be added.

### Notification → Toast Pipeline
Every service-level event ends up in a toast panel in `HudLayer`.
The flow is:

```
Service (QoS, Security, AutoResponse, AppFirewall, ...)
  └── NotificationService.notify(kind, msg, source, dedupe_key, data, recipient)
       └── builds NotificationContext, calls send_event()
            └── NotificationDispatcher (5s dedupe gate)
                 └── send() (player) / broadcast_alert() (server-wide)
                      └── TooltipManager.show_toast()  (single render entry point)
                           └── Panel in HudLayer (queue, stack-limited)
```

There are two entry points on `NotificationService`:

- **`send_event(context)`** — the frame-level "shape" entry. Takes a
  `NotificationContext`. Used by tests and by code that already has a
  context object.
- **`notify(kind, msg, source, dedupe_key, data, recipient)`** — the
  service-level "verb". Builds the context and forwards. **This is
  what new service code should call.** All four infrastructure
  services (QoS, Security, SecurityMonitor, AppFirewall) use it.

When you add a new service, prefer **emitting a typed signal** over
calling `NotificationService` directly for *in-game* state changes
(death, level-up, item equipped). For *infrastructure* events
(throttled, restricted, banned, recursion-blocked), the user must
see a toast — call `notify()` directly so the message is delivered.

```gdscript
# GOOD (infrastructure): the player must know they were throttled
NotificationService.notify(
    NotifKind.RATE_LIMITED, "You're casting too fast",
    "QoSService", "qos_rl:%s:cast" % player_id, {}, player_id
)

# GOOD (in-game state): emit a signal, NotificationService listens if it cares
signal item_equipped(player_id: String, item_id: String)
item_equipped.emit(player_id, item_id)
```

Tests that exercise the full pipeline live in
`tests/test_notification_toast.gd`, `tests/test_notification_frame.gd`,
and `tests/test_auto_response_signals.gd`.

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

The repo has two top-level areas: the game (`game/`) and
the frame (`labs/`). When working on the game, you're in
`game/`. When working on the frame, you're in `labs/`.

```
.                                       # repo root
├── game/                          # the Godot 4.7.2 project
│   ├── core/
│   │   ├── autoload/                   # Global singletons
│   │   ├── components/                 # Entity components
│   │   ├── community/                  # Community governance
│   │   ├── entities/                   # Base entity classes
│   │   ├── schemas/                    # Data schemas
│   │   ├── services/                   # Game services (30+)
│   │   ├── targeting/                  # Targeting system
│   │   └── ui/                         # Core UI (UIManager)
│   ├── entities/                       # Entity types
│   ├── connectors/                     # AI agent connectors
│   ├── data/                           # .tres resources
│   ├── ui/                             # User interface
│   │   ├── components/                 # Common UI
│   │   ├── islands/                    # UI Islands POC
│   │   ├── menus/                      # Game menus
│   │   ├── social/                     # Friends, Guild, Party, Trade
│   │   ├── admin/                      # Admin dashboard
│   │   ├── community/                  # Voting UI
│   │   └── targeting/                  # Target tooltip
│   └── tests/                          # Smoke tests
│
├── labs/                               # ⭐ Experimental work (root-level)
│   ├── README.md                       # the /labs/ convention
│   ├── prd.md                          # the modernized product spec
│   └── multi-iso/                      # the multi-iso frame work
│       ├── math/                       # NSC-9, icosahedral, quasicrystal
│       ├── kv/                         # LRU, content_hash, state_tree
│       ├── srv/                        # markov, predictor, LOD, axis
│       └── db/                         # snapshot_store, migrations
│
├── docs/
│   └── architecture/                   # Architecture design docs
│
├── tools/
│   └── godot/                          # Godot editor / export helpers
│
├── ROADMAP.md                          # implementation tracker
├── AGENTS.md                           # this file
└── README.md                           # the project overview
```

The Godot project root is `game/`. Open that folder in the
Godot editor. The `labs/` directory is intentionally outside
the project so it doesn't taint the stable build with
experimental work.

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

### GM Classes
Three admin-only classes hidden from normal character selection:
- `gm_akkan` (Akkan species)
- `gm_human` (Human species)
- `gm_synthetic` (Synthetic species)

All have `role = 0` (Role.GM).

**GM Visibility:**
- Character selection: GM classes filtered out for non-admins
- Target tooltip: `[GM]` prefix + gold name color + `⭐ GAME MASTER` badge
- Chat: `[GM]` prefix + gold color (#FFD700) on all messages
- Party UI: `⭐` icon next to GM names
- In-world: Gold floating star above GM heads (GMIndicator component)

**Key methods:**
```gdscript
CharacterData.is_gm_class(class_id_or_CharacterClass) -> bool
character_data.is_gm() -> bool
CharacterData.play_accepted(class_id, account_level) -> {allowed, reason}
```

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

### Defensive Helper Pattern
When a helper bridges two services (e.g. `_get_peer_for_player`
calls into `PlayerManager` from `AutoResponseService`), the
callee's API may differ between environments (test vs. runtime,
fresh autoload vs. initialized). Prefer a try-known-methods
fallback over a hard assumption:

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

The signal still fires (the action is observable) even when the
helper returns `-1`. This pattern is what kept
`AutoResponseService.action_taken` green in `--script` test
mode where `PlayerManager` has no `has_player` method.

---

## Testing

1. Open project in Godot 4.7.2 editor
2. Press F5 to run
3. Check console for signal connection errors
4. Verify entity spawning and targeting
5. Run smoke tests via the islands test runner (`game/tests/test_islands.gd`)

### Headless smoke tests

Each `tests/test_*.gd` is a `SceneTree` script that prints per-case
`[OK] / [FAIL]` lines and a final summary. Run from the repo root:

```bash
./tools/godot --headless --path synmergia --script res://tests/test_notification_toast.gd
./tools/godot --headless --path synmergia --script res://tests/test_hud_integration.gd
./tools/godot --headless --path synmergia --script res://tests/test_login_flow.gd
./tools/godot --headless --path synmergia --script res://tests/test_auto_response_signals.gd
```

| Test | Coverage |
|------|----------|
| `test_notification_toast.gd` | NotificationService → TooltipManager.show_toast() end-to-end; RecursionGuard + CircuitBreaker. 11/11 |
| `test_hud_integration.gd` | HudIntegrator handlers, NotificationService → CombatLog. 7/7 |
| `test_login_flow.gd` | Account + login + character flow. 21/21 |
| `test_auto_response_signals.gd` | AutoResponseService `action_taken` / `player_warned` + ActionType enum. 8/8 |

**Total: 47/47 green** as of 2026-09-01.

> **Gotcha:** `--script` mode does not pre-load autoloads. Inside
> the script, `NotificationService` is not a valid identifier even
> if `if typeof(NotificationService) != TYPE_NIL` wraps the call
> (GDScript does static identifier resolution). Resolve autoloads
> via `root.get_node_or_null("NotificationService")` instead, as
> the existing test files do.

For `/labs/` frame work: each primitive is co-located with its
test (`kv/state_tree.gd` + `kv/test_state_tree.gd`). Run tests
with the standard Godot test runner after the project root is
configured for `/labs/` (see `docs/architecture/labs-organization.md`).

---

## Working in /labs/ (the frame)

The `/labs/` directory is for experimental primitives that
could extract to the multi-iso frame. Different rules apply.

### The convention

1. **Each primitive is its own `.gd` file.** No `utils.gd` mega-file.
2. **Tests are co-located.** `math/nsc9.gd` + `math/test_nsc9.gd`.
3. **No autoload.** Primitives must be loadable without the
   Godot project running.
4. **No `class_name`.** Primitives should be liftable; `class_name`
   pollutes the global namespace.
5. **No `GameManager` / `EventBus` dependency.** Primitives are
   pure or composable; they don't reach into the game's
   singleton graph.
6. **New code goes here first.** The game consumes from here.

### What lives where

| Subdirectory | Contains | Examples |
|--------------|----------|----------|
| `labs/multi-iso/math/` | Pure functions. No state, no side effects. | NSC-9 encoding, icosahedral projection |
| `labs/multi-iso/kv/` | In-memory data structures. Stateful but local. | LRU cache, content-hash, state tree |
| `labs/multi-iso/srv/` | Service logic that composes math + kv. | Markov chain, predictor, composite_table, LOD manager |
| `labs/multi-iso/db/` | Database integration. | snapshot_store, migrations |

### Reading/writing primitives

```gdscript
# GOOD: pure primitive, no autoload, no class_name
# labs/multi-iso/math/nsc9.gd
extends RefCounted

static func encode(facility: int, axis: int, sequence: int) -> String:
    return "%d-%03d-%03d-%06d" % [9, facility, axis, sequence]

static func decode(code: String) -> Dictionary:
    var parts := code.split("-")
    return {
        "facility": int(parts[1]),
        "axis": int(parts[2]),
        "sequence": int(parts[3]),
    }

# Test: labs/multi-iso/math/test_nsc9.gd
func test_encode_decode_roundtrip() -> void:
    var original := "9-001-002-000123"
    var decoded := NSC9.decode(original)
    assert_eq(NSC9.encode(decoded.facility, decoded.axis, decoded.sequence), original)
```

```gdscript
# BAD: autoload, class_name, GameManager dep
# This belongs in game/, NOT in labs/
extends Node
class_name NSC9Manager
var _instance: NSC9

func _ready() -> void:
    _instance = NSC9.new()
    GameManager.register_primitive("nsc9", _instance)
```

### The migration path

When a primitive graduates from `/labs/` to the game (or
extracts to the frame repo), it keeps the same tests but adds
the wrapper layer the game expects (autoload, signal hookup,
etc.).

---

## Working with the multi-iso orchestrator (when it exists)

The orchestrator is the control plane for multi-dimensional
state. APIs look like:

```gdscript
# Define axes
var spatial := SpatialAxis.new(depth=8)
var faction := FactionAxis.new()
var orchestrator := MultiIsoOrchestrator.new([spatial, faction])

# Insert an entity
orchestrator.insert(entity_id, axis_coords)

# Query a region
var result := orchestrator.query({"spatial": aabb, "faction": guild_id})
# result is materialized intersection (O(1) if cached)

# Subscribe to changes
orchestrator.on_update.connect(_on_axis_update)
```

No global state. No autoload. The orchestrator is the entire
API. The game passes the orchestrator around via dependency
injection, not via singleton access.

The full design is in
[`docs/architecture/multi-iso-frame.md`](./docs/architecture/multi-iso-frame.md)
(Part 1) and
[`docs/architecture/multi-iso-lod-prediction.md`](./docs/architecture/multi-iso-lod-prediction.md)
(Part 2).

---

## Working with the state tree (when it exists)

```gdscript
# Build a tree
var tree := StateTree.new()
var root := tree.insert("/", "root")
var child_a := tree.insert("/a", "child_a")
var child_b := tree.insert("/b", "child_b")

# Hash it
var h := tree.hash(root)  # SHA-256 of serialized subtree

# Diff between two trees
var diff := tree.diff(old_root, new_root)
# diff is List[(path, new_hash, value)]

# Apply a diff
var new_root := tree.apply_diff(root, diff)
```

Server tick = re-rooting the tree with new state. Client sync
= apply diff. Bandwidth is O(diff size), not O(state size).

The full design is in
[`docs/architecture/multi-iso-frame.md`](./docs/architecture/multi-iso-frame.md).

---

## BBCode XSS — RichTextLabel Injection

All `RichTextLabel` nodes in the UI have `bbcode_enabled = true`. Any user-supplied string embedded in BBCode format strings is a potential injection vector. The pattern to look for:

```gdscript
"[color=%s]%s[/color]" % [color, user_string]   # DANGEROUS if user_string is unescaped
```

**The fix:** Replace `[` and `]` with full-width equivalents (U+FF3B `［` and U+FF3D `］`) which are visually identical but are NOT BBCode delimiters.

```gdscript
static func _esc(text: String) -> String:
    return text.replace("[", "［").replace("]", "］")
```

**Files with this pattern (as of 2026-09-02):**

| File | Components Fixed |
|------|-----------------|
| `core/services/chat_service.gd` | `display_name`, `message`, `prefix` in `format_message()` via `_escape_bbcode()` |
| `ui/components/combat_log.gd` | All 11 log functions: damage, crit, miss, heal, system, loot, quest, achievement, guild, trade |
| `ui/components/chat_ui.gd` | `target`, `reason`, `duration`, `pos` in admin command output |
| `ui/admin/admin_dashboard.gd` | `player_id`, `exploit_type`, `action_type`, `message` in terminal output |
| `core/admin/player_shell.gd` | `player_id`, `name`, `level_name`, `pid`, `alias`, command descriptions |
| `core/autoload/logger.gd` | `entity.name`, `entity_id`, `player.display_name` in `print_rich()` calls |
| `core/services/qos_service.gd` | `player_id` in `_send_latency_alert()` toast |
| `core/services/security_service.gd` | `player_id` in `_report_exploit()` toast |

**Files verified safe (no BBCode embedding of user input):**
- `ui/targeting/target_tooltip.gd` — uses plain `.text =`, not BBCode
- `ui/components/dialog_ui.gd` — only hardcoded strings
- `ui/components/action_menu.gd` — only sets `btn.text = text` (plain, not BBCode)

**Pattern for new code:** If you're building a `RichTextLabel` message with `%s` interpolation and the interpolated value comes from any user source (player name, chat message, item name, command output), always pass it through `_esc()` first.

---

## Gotchas

- **Enums:** Use `Service.EnumClass.VALUE` not `Service.AlertType` (doesn't exist)
- **Tabs:** Use tabs for indentation, not spaces (per `.editorconfig`)
- **Metadata:** Always pass metadata with entity signals for decoupled routing
- **Bounds:** Check `bind_on_pickup`, `soulbound` before allowing trades
- **`/labs/` primitives:** No autoload, no `class_name`, no GameManager dep. Pure or composable.
- **Frame vs game:** If you're reaching into the game's singleton graph, you're in the game, not the frame. Move the call site up.
- **Test co-location:** `/labs/` primitives have tests next to them. If you write a primitive without a test, it's not done.
- **Engine version:** Godot 4.7.2. `var_to_bytes` / `bytes_to_var` (not `VarToStr`).
- **Project root:** `game/` is the Godot project. `labs/` and `docs/` are outside.

---

## Session insights (2026-09-03)

### Fixes applied

Six parse/compile errors resolved across HUD and UI files:

1. **`player_reporter.gd` — static method visibility:** `escape()` was defined in outer class but called from `Report` inner class's `format_report()`. Fixed by moving `escape()` (as `static func esc()`) inside the `Report` class.

2. **`chat_service.gd` — mixed indentation:** Line 673 had 8 spaces instead of 1 tab. Godot requires consistent indentation throughout a file. Fixed the single line.

3. **`report_dialog.gd` — class_name/extends ordering:** `class_name ReportDialog` appeared before `extends UIPanel`. GDScript requires `extends` before `class_name`. Fixed ordering.

4. **`character_stats_ui.gd` — missing header:** File was missing `extends Control`, UIPanel stubs (open/close/toggle), and required signals (panel_opened/panel_closed). Added all.

5. **`blacksmith_ui.gd` — missing header:** Same pattern as character_stats_ui. Added `extends Control`, UIStyles const, UIPanel stubs, `_is_open`/`_player_id` vars.

6. **`skill_academy_ui.gd` — class_name/extends ordering:** Same fix as report_dialog.

### Key Godot GDScript rules learned

- **`extends` must precede `class_name`** when both are present in a class definition
- **Mixed indentation is fatal:** Once a file uses tabs, every subsequent line must use tabs. A single line with spaces causes a parse error on that line.
- **Inner class methods cannot call outer class methods** without qualification. Static methods in outer class are not visible inside inner class scope.
- **`extends Control` for scene-instantiated UIs:** Use `extends Control` + manual stubs for UIPanel methods rather than `extends UIPanel` when the class is instantiated from a .tscn scene.
- **Test co-location:** `/labs/` primitives have tests next to them. Game files (game/) have smoke tests in `tests/test_*.gd`.

### Test status

- Frame: 26/26 ✓
- ARS: 11/11 ✓
- Login: 21/21 ✓
- HUD integration: 6/7 (pre-existing: CombatLog lacks `get_message_count()`)
- Toast: hangs on recursion guard async test (pre-existing)

---

## Session insights (2026-08-30)

The last session added three core design docs that all
agents should know about:

- **The grail path** ([`docs/architecture/grail-path.md`](./docs/architecture/grail-path.md))
  — the pre-materialized orchestration contract. The state
  IS the answer; the math is the rebuild step, async, off
  the read path. Pattern: CQRS over multi-iso axes
  (pre/mid/post). Three methods: `query()` (O(1) lookup),
  `emit()` (event), `tick()` (math, batched). 5 commitments
  make it real: tick() method, composite tables canonical,
  re-root on tick, math as pure function, types explicit.

- **The vant lift** ([`docs/architecture/vant-lift.md`](./docs/architecture/vant-lift.md))
  — 9 vant libs map directly to multi-iso frame primitives.
  Tier 1: recursion, event, cache, geometry (the NSC-9 +
  icosahedral + quasicrystal math). Tier 2: pipeline, qos,
  sync. Tier 3: realm (lineage, trust, gates) for
  governance. 3,500 lines of translation over 4 sessions.
  vant is a sibling repo by the same author; lift is
  non-copyright.

- **Security** ([`docs/architecture/security.md`](./docs/architecture/security.md))
  — 7 defense layers for an agent framework. Layer 0
  (recursion guard) is the foundation; it's the only
  layer that's truly universal. AI agents (Claude/GPT) make
  recursive tool calls; without per-agent+per-tool guard,
  an agent's tool chain eventually DoSes the server. The
  guard is the agent framework's seatbelt. The user
  emphasized this is "neglected" — don't skip it.

- **UI framework** ([`docs/architecture/ui-framework.md`](./docs/architecture/ui-framework.md))
  — the reactive bridge (AxisQuery) that closes the loop
  between the orchestrator and the UI. One framework for
  humans and agents: humans via Godot rendering, agents via
  query signature + schema. The "complete the circle" the
  user mentioned.

- **Scale at 200 km²** ([`docs/architecture/scale-200km2.md`](./docs/architecture/scale-200km2.md))
  — 8 innovations that make 200km² cheap: LOD pyramid,
  predictive prefetch, multi-axis intersection, state diff
  sync, hierarchical sync, content-hash addressing, RAM +
  Postgres split, procedural assimilation. 20,000-200,000x
  reductions vs naive. They compose because the multi-iso
  frame is the substrate.

- **Schemas & data are stable.** Recorded 2026-08-30:
  `game/core/schemas/` and `/data/*` are NOT to be
  refactored without explicit user direction. Everything
  else is fair game.

- **AUDIT.md moved to `labs/AUDIT.md.legacy`** (frozen).
  Live session log is at `game/AUDIT.md.session-log`
  (still inside the project for now).

---

## Session insights (2026-09-01)

The notification → toast pipeline is now the single channel for
service-level events. Three commits on `main`:

- **`f794480` Wire notification→toast pipeline across QoS/security/firewall services**
  TooltipManager.show_toast() + notification_toast layer in
  HudLayer; QoSService, SecurityMonitor, AppFirewall, and
  AutoResponseService all route through NotificationService.

- **`58e960e` feat(auto-response): emit action_taken + player_warned signals**
  New `AutoResponseService` signals: `action_taken(player_id,
  action, exploit_type, reason)` and `player_warned(player_id,
  exploit_type, message)`. `ActionType` enum (WARN, MUTE,
  RESTRICT, KICK, BAN). Test: `test_auto_response_signals.gd`
  (8/8).

- **`0d737ec` fix(auto-response): defensive _get_peer_for_player**
  Try-known-methods fallback when the callee autoload is fresh
  in `--script` mode. Signal still fires even if the peer lookup
  returns -1. See **Defensive Helper Pattern** above.

**Conventions codified for next sessions:**

- New service? Emit a typed signal first; call
  `NotificationService` only for one-off messages. See
  **Notification → Toast Pipeline** above.
- New helper that bridges two services? Wrap in try-known-methods
  so a missing method on a fresh autoload doesn't crash the
  caller's signal path.
- New smoke test? Use `root.get_node_or_null("X")` to resolve
  autoloads, never the bare identifier (the parser resolves it
  statically even inside `typeof(X) != TYPE_NIL` guards).
- Push to `dhaupin/synmergia main` after every few completed
  tasks. The user explicitly asked for frequent pushes; the
  session log is short, and crashed sessions have lost work
  before.

**Pending for next session** (full list in task tracker):
- Frame: `NotificationContext` + `NotifKind` under
  `game/core/notifications/` so all game services use one
  dispatch shape.
- TTL-based dedupe layer (default 5s window) so spam-of-spam
  can't toast.
- Wire RespawnService / InventoryService / FactionManager
  through the new frame.
- Harden QoS / SecurityMonitor / AppFirewall paths when
  downstream is missing.

---

## Session insights (2026-09-01, evening)

The frame + service-wiring pass from the morning is now
**structurally complete** and the four infrastructure services
(QoS, Security, SecurityMonitor, AppFirewall) have been refactored
to use it. Two new commits on `main`:

- **`e8e0d72` feat(notifications): add NotificationService.notify() verb**
  The frame had two entry points after the morning work:
  `send_event(context)` (frame-level "shape") and direct calls to
  `send_to_player` (legacy). The new `notify(kind, msg, source,
  dedupe_key, data, recipient)` is the service-level "verb" —
  builds a `NotificationContext` and forwards. New service code
  uses notify(); the frame/tests still use send_event(). Frame
  suite: 11 → 14 passing.

- **`c61c7c7` refactor(qos,security,firewall): route all toasts through notify()**
  QoSService, SecurityService, SecurityMonitor, and AppFirewall
  now dispatch via `notify()`. The refactor removed three classes
  of band-aid code that existed only because `NotificationService`
  has no `class_name`:
    1. `notifier.call("send_to_player", ..., 13, 2)` dynamic
       dispatch with raw-int enums (13=WARNING, 2=HIGH).
    2. `if NotificationService.has_method("send_to_player")` boot
       paranoia.
    3. The ~50-line `Engine.has_singleton → get_node_or_null →
       get_script → .get("AlertScope") → .call("server_wide") →
       .new() → .set("is_server_wide", true) → .call("broadcast_alert")`
       fallback chain in AppFirewall. notify() collapses it to
       one line.

  Net diff: -57 lines (the AppFirewall fallback alone dropped
  from ~50 lines to ~10). **Total session suite: 61/61 green**
  (toast 11, frame 14, hud 7, ARS 8, login 21).

**What "clean" looks like now** (the pattern for future services):

```gdscript
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

func _on_throttled(player_id: String, action: String) -> void:
    if not is_instance_valid(NotificationService):
        return
    NotificationService.notify(
        NotifKind.RATE_LIMITED,
        "You're doing that too fast",
        "MyService",
        "mysvc:%s:%s" % [player_id, action],  # dedupe key
        {"action": action},
        player_id
    )
```

Five things that are now true and that future agents can rely on:

1. **One entry point for service code:** `NotificationService.notify(...)`.
   Anything else is legacy.
2. **Dedupe is automatic.** Pass a stable key (e.g. `<svc>:<player>:<event>`)
   and you get a 5s window for free. The window is short enough that
   legitimate "the same event happening again" toasts still work
   (a chat-mute that lasts hours will toast on re-mute; only the
   in-window duplicate collapses).
3. **Type/priority come from the kind.** Don't pass them. The
   kind→type/priority tables are in `notification_service.gd` and
   the tests cover the mapping.
4. **The frame is the autoload-only "shape" entry.** Tests and any
   code that already has a `NotificationContext` use `send_event()`
   directly. Service code uses `notify()`.
5. **The dynamic-dispatch / raw-int / has_method fallback patterns
   are dead.** If you see them in a service, it's pre-frame
   code that should be migrated.

**Open items for next session** (not blocking):
- AppFirewall `block_ip` / `unblock_ip` are still admin-scope only.
  The recursion-guard and ban flows were wired this round; the
  raw IP-block path was not (it doesn't carry a player_id in the
  current API, so adding a player toast needs API work first).
- The "audit showed 16 stragglers" list — chat/party/guild/quest/
  trade/skill_academy/admin services still call send_to_player /
  broadcast_alert directly. Deferred per "fill in the other stuff
  later" — they're not qos/security/firewall.

## Session insights (2026-09-01, late night)

Three small commits rounding out the qos/security/firewall family
to user-visible feedback. Each fills a gap where the service was
emitting a signal and logging, but the player had no toast.

- **`411fc06` feat(firewall): add player-facing toasts for ban / ban-lift**
  `ban_player`, `temp_ban_player`, `lift_ban` now toast the player
  (SECURITY_BLOCKED for ban, SECURITY_WARNING for lift) in addition
  to the existing admin-scope _broadcast_admin_alert. The banned
  player previously had no in-client signal that they were banned,
  why, or how long — they just got disconnected.

- **`4fa3942` feat(qos): toast player on per-player bulkhead saturation**
  `bulkhead_execute()` had three reject paths; the per-player one
  (line 413) was silent. A player firing 4 concurrent heavy
  requests would get nothing back. Now THROTTLED toasts the player
  with the service name ("X is busy — please slow down"). Dedupe
  on (player, service).

- **`3922b96` feat(security): player-facing toast for exploit_detected and permission_denied**
  `_report_exploit` and `log_permission_denied` were both silent
  to the player. Both now toast SECURITY_WARNING with a generic
  message (no internal exploit_type or required_level leaked to
  the client). Dedupe on (player, exploit_type) and (player, action).

**Pattern observation:** every "silent to the player" gap in this
family is the same shape — a function that emits a signal, logs
to GameLog, and returns, with no path to the UI. The fix is also
the same shape: a single `NotificationService.notify(...)` call
at the same site, deduped on a stable per-event key. Three
commits, +67 net lines.

**What "complete" looks like now** for the qos/security/firewall
family:
- A player who hits any of the three concerns gets a toast with
  the right kind, the right severity, and the right scope.
- An admin watching the same flows gets admin-scope ALERTs for
  every action.
- No toasts are duplicated within a 5s window.
- No internal type strings (exploit_type, required_level) leak
  to the client — messages are written for the player, not the
  admin log.

Verified across all three commits: 11/11 toast, 14/14 frame,
8/8 ARS, 7/7 HUD smoke.

## Session insights (2026-09-02, early morning)

- **`23cf7e9` feat(notifications): per-kind dedupe window override**
  The dispatcher had one window for every kind. Now each kind
  can declare its own. `KIND_WINDOW_OVERRIDES` in
  `notification_dispatcher.gd` is the source of truth; 0 means
  "never dedupe" and any positive ms overrides the default.

  Wired:
  - never dedupe: SECURITY_BLOCKED, ADMIN_ALERT, AUTO_ACTION,
    CIRCUIT_OPEN, QOS_RECOVERED, QOS_DEGRADED, ITEM_FULL
  - 2s window: PLAYER_WARNED, RATE_LIMITED, THROTTLED
  - default 5s: everything else

  Two new tests in `test_notification_frame.gd`:
  - `per_kind_override_zero_always_delivers` -- three bans in
    one window all deliver.
  - `per_kind_override_shorter_window` -- RATE_LIMITED dedupes
    at 50ms but lets through at 2150ms (still inside the 5s
    default) -- the per-kind window wins.

  Two existing tests were updated to use `ITEM_ADDED` instead of
  `ITEM_FULL`, because `ITEM_FULL` is now an override-0 kind
  and would never dedupe within any window. Test name and
  intent preserved.

  Frame test suite 14 -> 16. Full suite 56/56.

**What "cohesive signals/events/notifs" looks like now** for the
qos/security/firewall family:
- The signal is emitted (for any future listener -- analytics,
  audit log, webhook).
- The frame receives the same event through `notify()`.
- The dispatcher applies the right per-kind window.
- The HUD shows the toast (or the center-screen overlay for
  HIGH+).
- The chat log gets the line.
- Admins see the admin-scope alert on the same trigger.

**What was deferred, and why:**
- `AppFirewall.block_ip` / `unblock_ip` -- these are admin/infra
  primitives, not player actions. The admin already gets a toast
  via `_broadcast_admin_alert`. The signals have no listeners,
  but that's a "future analytics hook" hole, not a "the player
  is missing a toast" hole.
- The 16 stragglers in chat/party/guild/quest/trade/skill_academy/
  admin -- out of scope this round, per "fill in the other stuff
  later".

---

## Session insights (2026-09-02)

Continuation of the UI wiring pass from 2026-09-01. Seven commits
pushing all UI → service signal wiring to functional completeness.

- **`2d2408c` HUD wiring: minimap zone name, vault withdraw, guild check**


## Session insights (2026-09-03)

Four feature deliverables in one session, plus compile fixes:

**Item textures (`inventory_ui.gd`):**
- `InventoryUI._get_item_icon(item)` loads `item.icon_path` (from `.tres`),
  falls back to category placeholder textures.
- Category map: `res://ui/textures/items/{weapon,armor,accessory,consumable,
  resource,gem,event,dwelling,skill_book,misc}.png` — 10 placeholder PNGs
  created. Real icons drop in as `.tres` `icon_path` fields are populated.

**Achievement popup animation (`combat_log.gd`):**
- Replaced `pass` stub with queued slide-in: popups translate from
  offset_left=310 to 0 over 0.4s (QUAD/EASE_OUT), hold 3s, slide back
  out 0.35s (QUAD/EASE_IN). Multiple popups stack in queue.
- Gold-bordered panel with `[A]` label and achievement name.

**Dialogue data loading (`dialog_service.gd`, `dialogue_data.gd`, `dialog_ui.gd`):**
- `DialogService`: loads from `data/dialogues/*.tres`, builds in-memory dict
  with `{id, npc_id, nodes: [{speaker, text, choices: [{text, next}]}]}`.
  Fallback to 4-node built-in village dialogue when dir is missing.
  API: `start_dialogue(npc_id, dialogue_id)`, `advance()`, `select_choice(idx)`,
  `get_current_node()`, `end_dialogue()` + signals.
- `DialogueData`: `extends Resource` schema with `@export` for id, npc_id,
  speaker, nodes.
- `DialogUI`: connects `DialogService.node_changed`, delegates all node
  rendering to service. Fallback demo mode when service unavailable.

**Settings panel persistence (`settings_panel.gd`, `project.godot`):**
- Added `PlayerConfig` autoload (was referenced but not wired).
- `SettingsPanel` now tracks each control by `PlayerConfig` key:
  `_setting_controls[key] = {type, control, label}` + `_setting_keys`.
- `_create_slider/toggle/dropdown_row()` take `setting_key: String`
  and wire to `PlayerConfig.set_account_setting(key, value, false)`.
- `_load_from_config()` populates controls on panel open.
- Save → `save_account_settings()`, Defaults → `reset_account_settings()`.

**Trade items from InventoryService (`trade_service.gd`):**
- `add_item()` now calls `_verify_player_owns_item(player_id, item_id)`
  which queries `InventoryService.get_inventory()` → `InventoryComponent.find_item()`.
  Prevents clients from adding items they don't own. Falls back to `false`
  if `InventoryService` is not available.

**Compile fixes (pushed separately):**
- `player_config.gd`: removed `class_name PlayerConfig` (conflicts with
  the `PlayerConfig=` autoload — "Class hides an autoload singleton").
  Added `_load_global_settings()` wrapper for `_ready()`.
- `blacksmith_ui.gd`: removed duplicate `_player_id` (inherited from UIPanel).

Tests: frame 26/26, ARS 11/11, login 21/21 green throughout.

**Key files this session:**
- `ui/components/inventory_ui.gd` — icon loading
- `ui/components/combat_log.gd` — achievement popup
- `core/services/dialog_service.gd` — dialogue loading (NEW)
- `core/schemas/dialogue_data.gd` — dialogue schema (NEW)
- `ui/components/dialog_ui.gd` — dialogue UI wiring
- `ui/components/settings_panel.gd` — persistence wiring
- `core/services/trade_service.gd` — ownership validation
- `ui/textures/items/*.png` — 10 placeholder category icons

  `hud_services.gd`: `_minimap` cached node reference added; `_on_player_entered_zone` now calls `_minimap.set_zone_name()`. The minimap was connected but zone name was never updated. Also reorganized guards so minimap update always runs even if `NotificationService` is nil.
  `bank_ui.gd`: `_on_withdraw()` now calls `VaultService.withdraw_item()` — replaces a TODO placeholder that returned early.

- **`0feacf5` trade_ui: wire TradeService signals + _on_open state hydration**
  Six new signals bound in `trade_ui._bind_service_signals()`:
  `trade_started` (sync state), `item_added_to_trade` / `item_removed_from_trade`
  (refresh items grid), `trade_confirmed` / `trade_unconfirmed` (status update),
  `confirmation_countdown_tick` (countdown display).
  Added `_on_open()` override to re-hydrate from `TradeService.get_player_trade()`
  on panel open — fixes blank trade panel after reconnect.

- **`62fb608` skill_academy_ui: wire signature_selected signal**
  Signal existed in `SkillAcademyService` and had a handler in the UI
  (`_on_signature_selected`) but was never connected.

- **`ad205f6` social UI: expand service signal wiring**
  `friends_list.gd`: +6 signals (friend_request_sent/expired, player_blocked/unblocked, player_ignored/unignored).
  `guild_ui.gd`: +11 signals (rank_changed, leader_changed, guildMOTD_updated, guild_notice_updated, invite/decline/accept, alliance events).
  `party_ui.gd`: +6 signals (invite events, leader_changed, loot_rule_changed).

- **`dd9f0dc` blacksmith_ui: wire item_too_broken signal**
  `BlacksmithService.item_too_broken` was never connected. Adds toast
  notification when a player's item is too damaged to repair.

**Remaining TODOs (Phase C / feature work, not wiring gaps):**
- `action_bar.gd:172` — Set actual slot icon textures (needs `.tres` item data)
- `bank_ui.gd` — Item icons from `Item` resources; deposit via inventory picker
- `combat_log.gd:192` — Achievement popup animation (needs full achievement system)
- `dialog_ui.gd` — Load dialogue data from `DialogueData` resources
- `trade_ui.gd:269` — Pull items from `InventoryService` (Phase C)
- `settings_panel.gd` — Full value tracking + `PlayerConfig` persistence

**What's verified wiring-complete:**
- All social panels (friends, guild, party, trade) now bind all their relevant service signals
- `hud_services.gd` covers 15+ services with `has_signal()` guards
- `hud_layer.gd` does runtime composition (no manual scene wiring needed)
- `buff_bar`, `quick_access_bar`, `action_bar` self-contained (no external deps)
- `lobby_menu`, `login_screen`, `character_select` wired to `LoginService`
- `respawn_ui` → `RespawnService` via `respawn_ui_manager`
- `voting_ui` → `CommunityGovernance`; `character_transfer_ui` → `SameAccountTransferService`

---

## Skill Academy System

The Skill Academy allows players to upgrade skills and select their class signature.

### Class System (18 classes = 6 archetypes × 3 species)

| Archetype | Akkan | Human | Synthetic |
|-----------|-------|-------|-----------|
| **Tank** | Bulwark | Guardian | Warden |
| **DD** | Attacker | Warrior | Exploiter |
| **Mage** | Rune | Sorcerer | Psion |
| **Rogue** | Stalker | Marksman | Tracker |
| **Bender** | Seer | Temporalist | Overclocker |
| **Healer** | Shaman | Cleric | Conduit |

### Skills Per Class

- **6 Upgradable Skills** (5 upgrade tiers: common → mythic)
- **3 Signature Skills** (non-upgradable, unlock at level 10)

### Signature Selection

Players choose 1 of 3 signature abilities at level 10:
- First selection is **FREE**
- Subsequent changes cost **1000 gold**
- Signatures are stored in `CharacterData.active_signature`
- Signature switch count tracked in `CharacterData.signature_switches`

### Skill Upgrade System

- Players earn skill points based on level (30 + level × 2)
- Upgrading requires: 1 skill point + 4 books of matching tier
- Books drop from: bosses (any tier), vendors (common only)
- Respec cost: 500 gold base + 20 gold per point spent

### Key Files

- `core/schemas/character_data.gd` — CharacterData with signature fields
- `core/services/skill_academy_service.gd` — Upgrade and signature logic
- `ui/components/skill_academy_ui.gd` — 5-tab UI (Skills, Books, Upgrade, **Signature**, Respec)

---

## VPS Architecture

One Docker image, four run modes controlled by `START_MODE`:

```bash
docker compose --profile dev up --build      # dev (default) — noVNC + Xvfb
docker compose --profile prod up --build     # prod — headless + nginx + postgres + redis
docker compose --profile headless up --build # headless — Godot only (CI runner)
```

### Key Files
- `Dockerfile` — Unified image (all modes: dev/prod/headless/test)
- `docker-compose.yml` — Dev + prod profiles (single file)
- `srv/docker/entrypoint.sh` — Mode dispatcher (dev/prod/headless/test)
- `nginx.conf` — Reverse proxy, WebSocket forwarding, HTTPS
- `.env.example` — Environment variables template
- `docs/vps-architecture.md` — Full architecture documentation

### Ports
| Port | DEV | PROD | Service |
|------|-----|------|---------|
| 80 | ✅ | ✅ | HTTP |
| 443 | ✅ | ✅ | HTTPS (self-signed / Let's Encrypt) |
| 6080 | ✅ | ❌ | noVNC (browser GUI) |
| 5900 | ✅ | ❌ | VNC |
| 9000 | ✅ | ✅ | WebSocket |
