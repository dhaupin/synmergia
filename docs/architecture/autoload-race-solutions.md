# Autoload race / class_name cascade — design notes

**Problem:** In Godot 4.x, autoload scripts that reference `class_name` types (or
class_named scripts that reference autoloads) hit parse-time races. The class
registration table is built lazily, but script parsing is synchronous. Result:
`Parse Error: Could not find type "X" in the current scope` cascades across
dozens of files.

We have 22 such cascades in Synmergia (ActionMenu, Ankh, BlacksmithNPC, …). They
don't break "Main menu loaded" but they pollute the log and indicate real
fragility — if one of the cascade's missing types is in a hot path at scene
load, the project crashes silently.

---

## The four options

### 1. Strict manifest (no autoload list)

- Replace the `[autoload]` section with ONE autoload: `Bootstrap`.
- `Bootstrap` reads a `bootstrap.tres` (or `.gd` const map) listing every
  service in dependency order and `add_child()`s each one to itself.
- Each service script is a `Node` subclass; some get `class_name` for IDE.
- Pro: deterministic, no race, no surprises.
- Con: developers have to look at the manifest to know what exists. Loses the
  nice "autoload dropdown" in project settings.

### 2. Lazy / deferred init

- Keep all autoloads. Each one starts with `var ready := false` and sets it
  true at end of `_ready()`.
- Consumers `await Service.ready` before first use. Methods that need other
  services `await _ensure_deps()` at the top.
- Pro: no static parse race (script is parsed standalone, even if it
  references an autoload that's not yet ready — only the *call* fails).
- Con: every consumer is async; easy to forget an `await`; hides init bugs.
- Best for: services that genuinely need cross-dependency ordering but not
  for class types in parameter signatures (the parser doesn't care about
  await — it cares about the type existing at parse time).

### 3. Async orchestrator (signal-based)

- One `Orchestrator` autoload holds a DAG: `services := { "EntityService":
  ["EventHub", "GameLog"], ... }`.
- Each service has a uniform `_post_ready()` that emits `service_ready(name)`.
- Orchestrator fires events when a service's deps are all `ready`.
- Pro: keeps Godot's autoload pattern, adds a clear init contract.
- Con: **doesn't actually fix the parse-time race** — the script still needs
  the type to exist when it's parsed. Signals only help at runtime.

### 4. Preloader frame (no class_name, all const)

- Strip `class_name` from every script. Define a single `preloader.gd`:
  ```gdscript
  const Entity = preload("res://core/entities/entity.gd")
  const EnemyData = preload("res://core/schemas/enemy_data.gd")
  # …200+ lines…
  ```
- Consumers use `Preloader.Entity` instead of `Entity`.
- Pro: 100% deterministic. Parser sees the const, knows the type, done.
- Con: ugly, no IDE autocomplete on the global name, every consumer has to
  import the preloader.

---

## Recommended: **Hybrid (manifest + shims)**

Combines the strengths of 1 and 2 without their worst parts:

```
[autoload]
Bootstrap="*res://core/bootstrap.gd"     # ONLY ONE autoload

# All other services are NOT autoloads.
# They are children of Bootstrap, added in dependency order.
```

**`core/bootstrap.tres`** (Resource listing services in order):
```tres
[gd_resource type="Resource" format=3]
[resource]
script_order = Array[Resource]([
  preload("res://core/autoload/logger.gd"),         # GameLog
  preload("res://core/events/event_hub.gd"),        # EventHub
  preload("res://core/services/entity_service.gd"), # EntityService
  preload("res://core/services/zone_manager.gd"),   # ZoneManager
  ...
])
```

**`core/bootstrap.gd`** (one autoload):
```gdscript
extends Node
const MANIFEST := preload("res://core/bootstrap.tres")

func _ready() -> void:
    for script in MANIFEST.script_order:
        var node := script.new()
        node.name = script.get_global_name()  # or a friendly name
        add_child(node)
        set(script.get_global_name(), node)  # register as property for `get_node()`
```

**Static shim layer** for class_name in the consumer scripts that need it
(e.g., when an event signature uses `Entity.SpawnMetadata`):
```gdscript
# core/type_shims.gd
const Entity = preload("res://core/entities/entity.gd")
const EnemyData = preload("res://core/schemas/enemy_data.gd")
const Faction = preload("res://core/schemas/faction.gd")
const Species = preload("res://core/schemas/species.gd")
# …etc
```
Then consumers do `TypeShims.Entity` instead of `Entity`. Or — better — we
keep the `class_name` declarations for IDE autocomplete AND add the
preload as a const, with the convention "always reference the const, never
the bare class_name in cross-file signatures."

**Tradeoffs accepted:**
- One autoload entry in project.godot instead of 30+. (downside: less
  discoverable in the editor, but the manifest is one file to look at)
- Service scripts are still `extends Node` with `class_name` for IDE.
- Static type signatures in event signals use `TypeShims.X` not `X`.
- Initial bootstrap is synchronous; services that genuinely need async
  startup (e.g., Database, Network) can still defer inside their own
  `_ready()`.

**Migration cost:** ~30 autoload lines to one line + one manifest file + one
shim file + a `preload()` sweep in 5–10 signal-bearing files. Probably 1
session of focused work.

---

## When to pick the others

- **Option 2 (lazy/await):** Pick if you want to keep the autoload list as-is
  AND you're willing to make every consumer async. Not great for hot-path
  event signals.
- **Option 3 (orchestrator):** Pick as a *supplement* to any of these. It's
  the runtime-initialization story; it doesn't solve parse order on its own.
- **Option 4 (preloader only):** Pick if you have < 50 types and don't mind
  ugly imports. Not realistic for a 30-service game.

---

## Next step for Synmergia

The `pending` item "static shims for autoloads with class_name" is exactly
the shim layer above. So:

1. Build `core/type_shims.gd` with `preload()` const aliases for all
   ~22 cascade-affected types.
2. Sweep the event signal signatures and signal-emit sites to use
   `TypeShims.X` (preserving the runtime type).
3. Optional: collapse the 30+ autoloads into a Bootstrap + manifest.
   Defer until shim step is proven to close the cascade.
