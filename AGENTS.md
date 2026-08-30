# Synmergia - Developer Notes for AI Agents

> **Updated 2026-08-30:** Modernized for the new architecture
> (state tree, multi-iso orchestrator) and the `/labs/`
> convention. The game lives in `synmergia/`. The frame lives
> in `labs/`. The Godot project root is `synmergia/`.

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
- **Game root:** `synmergia/` (open this in the Godot editor)
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

The repo has two top-level areas: the game (`synmergia/`) and
the frame (`labs/`). When working on the game, you're in
`synmergia/`. When working on the frame, you're in `labs/`.

```
.                                       # repo root
├── synmergia/                          # the Godot 4.7.2 project
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

The Godot project root is `synmergia/`. Open that folder in the
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

---

## Testing

1. Open project in Godot 4.7.2 editor
2. Press F5 to run
3. Check console for signal connection errors
4. Verify entity spawning and targeting
5. Run smoke tests via the islands test runner (`synmergia/tests/test_islands.gd`)

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
# This belongs in synmergia/, NOT in labs/
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

## Gotchas

- **Enums:** Use `Service.EnumClass.VALUE` not `Service.AlertType` (doesn't exist)
- **Tabs:** Use tabs for indentation, not spaces (per `.editorconfig`)
- **Metadata:** Always pass metadata with entity signals for decoupled routing
- **Bounds:** Check `bind_on_pickup`, `soulbound` before allowing trades
- **`/labs/` primitives:** No autoload, no `class_name`, no GameManager dep. Pure or composable.
- **Frame vs game:** If you're reaching into the game's singleton graph, you're in the game, not the frame. Move the call site up.
- **Test co-location:** `/labs/` primitives have tests next to them. If you write a primitive without a test, it's not done.
- **Engine version:** Godot 4.7.2. `var_to_bytes` / `bytes_to_var` (not `VarToStr`).
- **Project root:** `synmergia/` is the Godot project. `labs/` and `docs/` are outside.

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
  `synmergia/core/schemas/` and `/data/*` are NOT to be
  refactored without explicit user direction. Everything
  else is fair game.

- **AUDIT.md moved to `labs/AUDIT.md.legacy`** (frozen).
  Live session log is at `synmergia/AUDIT.md.session-log`
  (still inside the project for now).

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
