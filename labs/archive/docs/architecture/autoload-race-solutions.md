# Autoload race / class_name cascade — design notes

**Problem:** In Godot 4.x, scripts that use `class_name` types as type annotations
(without preloading them) hit parse-time races. The class registration table is
built lazily, but script parsing is synchronous. Result:
`Parse Error: Could not find type "X" in the current scope` cascades across
multiple files.

**Current State (2026-09-05):** 68+ parse errors when loading the project due to
type resolution failures. Root cause: files using type annotations like
`var _inventory: InventoryComponent = null` without first adding
`const InventoryComponent = preload("...")` to force the dependent script to load.

**Affected types (verified):**
- `Item` — used in 13+ files without preload
- `InventoryComponent` — used in 13+ files without preload
- Likely `Entity`, `NPCEntity`, and others (cascading from the above)

**Affected files (verified):**
```
game/ui/components/blacksmith_ui.gd
game/ui/components/bank_ui.gd
game/ui/components/skill_academy_ui.gd
game/ui/components/character_panel.gd
game/ui/social/trade_ui.gd
game/ui/social/guild_ui.gd
game/ui/social/party_ui.gd
game/ui/social/friends_list.gd
game/ui/social/character_transfer_ui.gd
game/ui/community/voting_ui.gd
game/ui/admin/admin_dashboard.gd
game/core/admin/admin_catalog.gd
game/core/services/death_features.gd
```

These don't break "Main menu loaded" but pollute the log and indicate real
fragility — if one of the cascade's missing types is in a hot path at scene
load, the project crashes silently.

---

## The four options

### 1. Strict manifest (no autoload list)

- Replace the `[autoload]` section with ONE autoload: `Bootstrap`.
- `Bootstrap` reads a `.gd` const map listing every service in dependency order and `add_child()`s each one.
- Each service script is a `Node` subclass; some get `class_name` for IDE.
- Pro: deterministic, no race, no surprises.
- Con: developers have to look at the manifest to know what exists. Loses the nice "autoload dropdown" in project settings.

### 2. Lazy / deferred init

- Keep all autoloads. Each one starts with `var ready := false` and sets it true at end of `_ready()`.
- Consumers `await Service.ready` before first use.
- Pro: no static parse race (script is parsed standalone — only the call fails, not the parse).
- Con: every consumer is async; easy to forget an `await`; hides init bugs.
- Best for: services that genuinely need cross-dependency ordering but not for class types in parameter signatures.

### 3. Async orchestrator (signal-based)

- One `Orchestrator` autoload holds a DAG of dependencies.
- Each service emits `service_ready(name)` when `_ready()` completes.
- Pro: keeps Godot autoload pattern, adds a clear init contract.
- Con: **does not actually fix the parse-time race** — signals only help at runtime.

### 4. Preloader frame (no class_name, all const)

- Strip `class_name` from every script. Define a single `preloader.gd` with all preloads.
- Consumers use `Preloader.Entity` instead of `Entity`.
- Pro: 100% deterministic.
- Con: ugly, no IDE autocomplete on the global name.


## Recommended: **Two-Step Preload Fix**

### Step 1: Add preload declarations to affected files (QUICK FIX)

Every file that uses a `class_name` type in a type annotation must first preload that type:

```gdscript
# BEFORE (broken):
extends UIPanel
var _inventory: InventoryComponent = null

# AFTER (works):
extends UIPanel
const InventoryComponent = preload("res://core/components/inventory_component.gd")
var _inventory: InventoryComponent = null
```

The `preload()` forces the script to load at parse time, guaranteeing the `class_name` is registered before it is used as a type annotation.

### Step 2: Bootstrap + manifest (OPTIONAL, if Step 1 insufficient)

If Step 1 does not fully resolve the cascades, collapse autoloads into a single Bootstrap:

```gdscript
extends Node
const SERVICES := [
    preload("res://core/autoload/logger.gd"),
    preload("res://core/events/event_hub.gd"),
    preload("res://core/services/entity_service.gd"),
]

func _ready() -> void:
    for script in SERVICES:
        var node := script.new()
        node.name = script.get_global_name()
        add_child(node)
        set(script.get_global_name(), node)
```

**Tradeoffs:**
- Step 1: Low risk, clear scope, preserves all existing patterns
- Step 2: Loses IDE autoload discovery, requires manifest maintenance

**Migration cost:**
- Step 1: 1-2 hours to add preloads to 13+ files
- Step 2: 4-6 hours to build bootstrap + refactor 30+ autoloads


## Migration Plan (2026-09-05)

### Phase 1: Step 1 — Add preloads (IN PROGRESS)
1. Add `const Item = preload("...")` to files using `Item` type
2. Add `const InventoryComponent = preload("...")` to files using `InventoryComponent` type
3. Add any other missing preloads (Entity, etc.)
4. Verify with: `godot --check-only` and test suite
5. Expected result: 68 parse errors -> 0

### Phase 2: Step 2 — Bootstrap (DEFERRED)
Only if Phase 1 does not fully resolve cascades.

### Verification
Run after Phase 1:
```bash
godot --headless --path synmergia --script res://tests/test_hud_integration.gd
```
Expected: 0 parse errors, all tests pass.
