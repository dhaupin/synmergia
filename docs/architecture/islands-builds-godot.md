# Islands + Builds for Synmergia (raw-dog Godot port of prestruct)

**Source pattern:** [github.com/dhaupin/prestruct](https://github.com/dhaupin/prestruct)
— React + Vite islands architecture, build-time static prerender with
client-side dynamic mounts.

**Why bother:** Prestruct's "raw dog" approach is exactly the kind of
unframework approach we need for Synmergia. The autoload-race problem we
just analyzed is partly a symptom of trying to make Godot's autoload system
do too much. Islands invert the dependency: the world runs without the UI,
and UI mounts on demand.

---

## The original pattern (3 things)

1. **Build-time static layer** — every route prerendered to HTML.
   Crawlers see content. No JS needed for the static parts.

2. **`<pre-island>` placeholders** — custom elements that get replaced
   by React components after hydration. Each one has a name + a load
   strategy.

3. **Three mount strategies:**
   - `eager` — mount on hydration
   - `visible` — IntersectionObserver, mount when scrolled in
   - `idle` — `requestIdleCallback`, mount during browser idle

**The "raw dog" part:** No framework, no SSR engine, no DI container.
One `prerender.js` reads your React app, renders to string, splices
placeholders, writes HTML. Done.

---

## Mapping to Godot / Synmergia

| Prestruct | Godot |
|-----------|-------|
| Static HTML route | `.tscn` scene file |
| `<pre-island>` | `IslandPlaceholder` (custom `Node` or `Control`) |
| React component | A `.gd` script + scene subtree |
| `mountIslands()` after hydration | `IslandManager._ready()` post-process |
| `eager` strategy | `add_child()` immediately |
| `visible` strategy | `visibility_changed` signal or viewport check |
| `idle` strategy | `Engine.get_idle_frames()` or low-priority queue |
| Build-time `prerender.js` | Export presets + `pck` packing |
| Fallback content inside placeholder | Children nodes of the placeholder |

---

## Concrete Godot design

### 1. `IslandPlaceholder` node

```gdscript
# res://ui/islands/island_placeholder.gd
class_name IslandPlaceholder
extends Node

@export var island_name: String      # e.g. "health_bar", "inventory"
@export var load_strategy: String    # "eager" | "visible" | "idle"
@export var island_scene: PackedScene # the actual UI scene to mount
```

Mark it as a custom type in the editor. Drop into any scene. Set the
three exports. Done.

### 2. `IslandRegistry` autoload (the *only* UI autoload)

```gdscript
# res://ui/islands/island_registry.gd
extends Node

# One preload per island — no class_name needed, no race
const HEALTH_BAR    = preload("res://ui/hud/health_bar.tscn")
const INVENTORY_PANEL = preload("res://ui/panels/inventory_panel.tscn")
const CHAT_BOX      = preload("res://ui/hud/chat_box.tscn")

const ISLANDS := {
    "health_bar": HEALTH_BAR,
    "inventory":  INVENTORY_PANEL,
    "chat":       CHAT_BOX,
}

func resolve(name: String) -> PackedScene:
    return ISLANDS.get(name)
```

This is THE autoload for UI. It only has `const` preloads — no methods
that depend on Entity, no class_name references to anything cascade-prone.

### 3. `IslandManager` autoload (mount orchestrator)

```gdscript
# res://ui/islands/island_manager.gd
extends Node

func mount_placeholders(root: Node) -> void:
    for placeholder in root.find_children("*", "IslandPlaceholder", true, false):
        var scene := IslandRegistry.resolve(placeholder.island_name)
        if scene == null:
            push_warning("Island not registered: %s" % placeholder.island_name)
            continue
        match placeholder.load_strategy:
            "eager":   _mount(placeholder, scene)
            "visible": _mount_when_visible(placeholder, scene)
            "idle":    _mount_when_idle(placeholder, scene)
```

Called once per scene transition. Idempotent (uses placeholder's own
flag to prevent double-mount).

### 4. Scene usage

```tscn
# res://zones/zone_tavern.tscn
[node name="World" type="Node3D" parent="."]
... static 3D scene ...

[node name="UI" type="CanvasLayer" parent="."]

[node name="HealthBar" type="Node" parent="UI"]
script = ExtResource("island_placeholder.gd")
island_name = "health_bar"
load_strategy = "eager"

[node name="ChatBox" type="Node" parent="UI"]
script = ExtResource("island_placeholder.gd")
island_name = "chat"
load_strategy = "visible"

[node name="Inventory" type="Node" parent="UI"]
script = ExtResource("island_placeholder.gd")
island_name = "inventory"
load_strategy = "idle"
```

The tavern scene loads. Static world renders. Eager islands mount
in `_ready()`. Visible island mounts when scrolled into view. Idle
island mounts during browser idle. Inventory panel pops in a few
hundred ms later, no jank.

---

## "Builds" — the build-time static layer

Prestruct's `prerender.js` produces static HTML. In Godot, the analog is:

- **Static zones** ship as `.tscn` files in the `pck` (or as a separate
  `data.pck` for content updates).
- **NPC dialogue, item DB, spawn tables** are `.tres` Resources,
  pre-built and shipped.
- **Patch pipeline:** rebuild the data `.pck` without touching the
  code `.pck` → clients download a 5MB delta instead of 200MB.

The island pattern is the **runtime** analog. Builds are the **content**
analog. Together: a static-content + dynamic-runtime game that doesn't
need autoload spaghetti.

---

## What this buys us for the autoload race

1. **The world doesn't need the UI.** If `IslandManager` autoload
   fails to parse, the 3D scene still loads. (Try this today: a
   cascading class_name failure in a UI panel currently prevents
   the whole game from booting.)

2. **UIs are pure scenes.** No `extends UIPanel` requires an autoload.
   Panels can `await IslandManager` if they need a service — async
   per service, no parse-time race.

3. **The class_name cascade shrinks dramatically.** Once UIs are
   islands, only services that genuinely need Entity/EnemyData/etc.
   in their parse-time signatures (and there are maybe 3-4 of those)
   have to fight the race. The other 20+ class_names only need to
   be visible to the island registry's `preload()` — which is
   statically resolved at parse time and never races.

---

## Migration cost

Realistic estimate for Synmergia:

- New: `IslandPlaceholder`, `IslandRegistry`, `IslandManager` (3 small files)
- New: per-island `.tscn` files (we have ~8 UI panels + 4 HUD widgets = 12)
- Edit: existing UI scripts to NOT `extends UIPanel` at the top-level
  scene; instead they're mounted by `IslandManager`
- Optional but recommended: collapse 30+ autoloads to 5-6 essentials
  (Bootstrap, GameLog, EventHub, IslandManager, NetworkManager)

Probably 2 focused sessions. First session: scaffold the 3 island
files + convert 1-2 panels as a POC. Second session: migrate the rest.

---

## When to skip this

If the existing UIPanel migration is "good enough" and the autoload
race is solvable with the shim approach from
`autoload-race-solutions.md`, you might not need islands. Islands
are the bigger refactor. They make sense if:

- You want the game to boot even if UI subsystems are broken
- You want hot-swap of UI panels (plugin system, mod support)
- You want to ship content-only patches without re-shipping the engine
- You want the 3D world to be playable without UI (spectator mode, headless server)

If only the first applies, just do the shim. Islands are a
structural change to how the engine boots.

---

## Verdict

**Yes, it bends.** The islands pattern is a near-perfect fit for the
Synmergia autoload race problem because it inverts the dependency:
the world doesn't depend on the UI, the UI depends on the world (via
async event listening, not parse-time references).

**Recommendation:** Do the shim first (cheap, fixes 22 cascades),
then evaluate islands as a Phase B or Phase C architectural change.
The two are complementary, not competing.

---

## Related

- `autoload-race-solutions.md` — the shim / Bootstrap approach
- `prestruct/AGENTS.md` — the React pattern in full
- `prestruct/init/src/islands.js` — the mount orchestrator source
- `prestruct/init/src/AppIslands.jsx` — the registry template
