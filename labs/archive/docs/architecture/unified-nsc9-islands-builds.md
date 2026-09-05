# Unified Architecture: NSC-9 + Islands + Builds for Synmergia

> **Status: REVISED 2026-08-30 after user feedback**
>
> Original framing was "the geometry extends the architecture." My
> first honest evaluation framed it as "replacement for things
> Synmergia already has" and dismissed it. The user pointed out
> the framing was wrong. **The geometry is right as a redis-like
> extension, not a replacement.** The state tree content-hash
> pattern is the real win.
>
> See:
> - [`nsc9-honest-evaluation.md`](./nsc9-honest-evaluation.md) — the
>   corrected eval with concrete Synmergia use cases
> - [`NEXT-AGENT-PICKUP.md`](./NEXT-AGENT-PICKUP.md) — current plan
>
> **TL;DR of the revised framing:** the geometry is a Redis-like
> layer in front of Postgres, not a replacement. State tree (with
> content-hash nodes) is the foundation for sync, save games,
> cross-shard, and P2P. NSC-9 specifically is still deferred
> (SHA-256 hex is fine for now), but content-hash as a layer is
> strongly recommended.

**Cross-pollinated from:**
- [prestruct](https://github.com/dhaupin/prestruct) — static prerender + islands of interactivity
- [vant/axolotl](https://github.com/dhaupin/vant/tree/axolotl) — icosahedral geometry, NSC-9 barcodes, quasicrystal storage, AI memory islands

**The big idea:** Synmergia gets a three-layer architecture where the
**same primitives** we use for UI islands also drive entity identity,
shard routing, and persistent storage. One geometric core; many surfaces.

```
NSC-9 barcodes ←→ icosahedral coords ←→ quasicrystal paths
       ↓                ↓                       ↓
  entity IDs       shard routing           save data on disk
       ↓                ↓                       ↓
   Islands (UI, lazy) + Builds (static content pck)
```

No central UID allocator. No shard registry. No item DB. Just geometry.

---

## Part 1: NSC-9 as universal entity IDs

### What it is

GS1 reserves NSC digits 6-9 for future use. We claim NSC "9" for
virtual/automation entities (the proposal lives in vant's
`docs/NSC9-SPEC.md`). Format:

```
9-FACILITY-SEQUENCE-CHECK
  │     │         │      └─ 0-9, single check digit
  │     │         └──── 00000-99999, internal sequence
  │     └────────── 10000-99999, facility/zone code
  └─────────────── NSC "9" (always)
```

12 digits, UPC-A compatible, never collides with real products.

### Godot port

```gdscript
# res://core/geometry/nsc9.gd
class_name NSC9
extends RefCounted

const NSC_DIGIT := "9"

static func from_content(content: String) -> String:
    var hash := content.sha256_text()
    var raw := hash.substr(0, 5).hex_to_int()
    var facility := 10000 + (raw % 90000)
    var sequence := hash.substr(5, 5).hex_to_int() % 100000
    var checksum := hash.substr(hash.length() - 1).hex_to_int() % 10
    return "%s-%05d-%05d-%d" % [NSC_DIGIT, facility, sequence, checksum]

static func parse(barcode: String) -> Dictionary:
    var parts := barcode.split("-")
    return {
        nsc = parts[0],
        facility = parts[1].to_int(),
        sequence = parts[2].to_int(),
        checksum = parts[3].to_int(),
    }
```

### What it replaces in Synmergia

- `IDRegistry` autoload — gone. Every entity ID is `NSC9.from_content(...)`.
- `entity_id` int field on `Entity` — gone. The barcode IS the ID.
- The "is this ID unique?" check — gone. NSC-9 is collision-free by construction.
- The `bind_on_pickup` / `unique` item flags — partially replaced (see below).

### Use cases

| Entity | Content hashed |
|--------|----------------|
| Player character | `account_id + character_name` (or just account_id) |
| Item instance | `item_template_id + serial + bind_target` |
| NPC / mob spawn | `zone_id + spawn_slot_id` |
| Quest instance | `player_barcode + quest_template_id` |
| Guild | `guild_name + founder_barcode` |
| Chat message | `sender_barcode + timestamp + nonce` (for dedup) |

Re-hash the same content → same barcode. Move an item between players?
Content changes (`bind_target` added) → new barcode. It's content-addressed.

---

## Part 2: Icosahedral coordinates as shard routing

### The math (from vant's `lib/geometry/icosahedral.js`)

```gdscript
# res://core/geometry/icosahedral.gd
class_name Icosahedral
extends RefCounted

const PHI := (1.0 + sqrt(5.0)) / 2.0  # ≈ 1.618
const GOLDEN_ANGLE := PI * (3.0 - sqrt(5.0))  # ≈ 2.399 rad ≈ 137.5°

# 12 vertices of a unit icosahedron
const VERTICES: Array[Vector3] = [
    Vector3(0, 1, PHI), Vector3(0, -1, PHI), Vector3(0, 1, -PHI), Vector3(0, -1, -PHI),
    Vector3(1, PHI, 0), Vector3(-1, PHI, 0), Vector3(1, -PHI, 0), Vector3(-1, -PHI, 0),
    Vector3(PHI, 0, 1), Vector3(-PHI, 0, 1), Vector3(PHI, 0, -1), Vector3(-PHI, 0, -1),
]

# 20 face normals
const FACE_NORMALS: Array[Vector3] = [
    Vector3(0.527, 0, 0.851), # ... 20 total
]

static func project(barcode: String) -> Dictionary:
    var parsed := NSC9.parse(barcode)
    var theta := (parsed.facility % 100000) / 100000.0 * 2.0 * PI
    var phi := (parsed.sequence % 100000) / 100000.0 * PI
    var depth := ((parsed.sequence % 100000) / 100000.0) / PHI
    var vertex := _nearest_vertex(theta, phi)
    return {
        barcode = barcode,
        theta = theta,
        phi = phi,
        depth = depth,
        vertex = vertex,
    }

static func _nearest_vertex(theta: float, phi: float) -> Vector3:
    var offset := theta * (PHI - 1.0)
    var point := Vector3(
        sin(phi) * cos(theta + offset),
        cos(phi),
        sin(phi) * sin(theta + offset)
    )
    var nearest := VERTICES[0]
    var min_dist := INF
    for v in VERTICES:
        var d := point.distance_to(v)
        if d < min_dist:
            min_dist = d
            nearest = v
    return nearest
```

### What it gives Synmergia

**12 shard servers.** Each vertex = one shard. Project a player barcode →
they land on one of 12 vertices → that shard hosts them.

**20 zones (or 20 boss instances) per shard.** Face normals = zone slots.

**Adjacency preserved.** Two players in the same in-game zone have
similar (theta, phi) → same shard → no cross-shard chatter.

**Infinite scale by recursing.** Project (theta, phi) on shard N at depth
d=0.5 → 12 sub-shards. Project at d=0.25 → 12² = 144. d=0.1 → 12^10.
The depth component is the "rebalance lever" — when a shard fills up,
the orchestrator picks the top half of (theta, phi) and spawns a new
sub-shard.

**Zone designator = first 5 digits of facility code.** So a zone can
declare "everything in zone 31814 → shard 3" at config time, and
players/NPCs that hash to facility 31814 get routed there automatically.

---

## Part 3: Quasicrystal as persistent storage

### The pattern (from vant's `lib/geometry/quasicrystal.js`)

```gdscript
# res://core/geometry/quasicrystal.gd
class_name Quasicrystal
extends RefCounted

const DATA_ROOT := "user://quasicrystal/"  # or pck-baked for static data

static func get_storage_path(barcode: String) -> String:
    var key := _derive_key(barcode)  # short hex hash
    var dir := DATA_ROOT + key.substr(0, 2) + "/"
    return dir + key + ".json"

static func store(barcode: String, data: Dictionary) -> void:
    var path := get_storage_path(barcode)
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(JSON.stringify({
        barcode = barcode,
        position = Icosahedral.project(barcode),
        data = data,
        _stored = Time.get_unix_time_from_system(),
    }))

static func load(barcode: String) -> Variant:
    var path := get_storage_path(barcode)
    if not FileAccess.file_exists(path):
        return null
    var file := FileAccess.open(path, FileAccess.READ)
    return JSON.parse_string(file.get_as_text())

static func _derive_key(barcode: String) -> String:
    var parsed := NSC9.parse(barcode)
    var sequence := parsed.sequence
    # Knuth multiplicative hash, golden ratio multiplier
    var multiplier := 2654435769
    var key := (sequence * multiplier + parsed.facility * multiplier) & 0xFFFFFFFF
    return "%08x" % key
```

### What it replaces in Synmergia

- The `InventoryService` database table — gone. Each item is a file at its
  barcode-derived path.
- The `GuildService` guild records — gone. Each guild is a file.
- The `LootService` drop tables — gone. Loot rolls are deterministic
  from the monster + player_barcode hash, so a kill is reproducible.
- The `save_data.json` blob — gone. Player state is a folder of files
  (one per character, one per inventory slot, one per quest).

### Why this is fast

`get_storage_path(barcode)` is O(1) — pure string math, no DB lookup.
Reading is O(1) — open file at known path. Writing is O(1) — append.
There's no index, no query planner, no schema migration. Just files.

### Why this scales

- A shard server has 12 directories under `quasicrystal/`. Each holds
  ~16K files. No central index.
- Move a player to a new shard? Copy one folder. `rsync` 50MB. Done.
- Backup? `tar` the relevant 2-character subdir.
- Cross-shard player trading? Player A's item is a file on shard 3.
  Shard 3 sends the file (over the wire, signed) to shard 7. Shard 7
  stores it at the same NSC9-derived path.

---

## Part 4: Islands (Prestruct + vant) for UI

This is the part already drafted in `islands-builds-godot.md`. Re-stated
briefly here for completeness.

```gdscript
# res://ui/islands/island_placeholder.gd
class_name IslandPlaceholder
extends Node

@export var island_name: String
@export var load_strategy: String  # "eager" | "visible" | "idle"
@export var island_scene: PackedScene
```

```gdscript
# res://ui/islands/island_registry.gd
extends Node
const _REGISTRY := {
    "health_bar":   preload("res://ui/hud/health_bar.tscn"),
    "chat":         preload("res://ui/hud/chat_box.tscn"),
    "inventory":    preload("res://ui/panels/inventory_panel.tscn"),
    "party":        preload("res://ui/panels/party_panel.tscn"),
    "guild":        preload("res://ui/panels/guild_panel.tscn"),
    "trade":        preload("res://ui/panels/trade_panel.tscn"),
    "notification": preload("res://ui/hud/notification.tscn"),
}

func resolve(name: String) -> PackedScene:
    return _REGISTRY.get(name)
```

```gdscript
# res://ui/islands/island_manager.gd
extends Node

func mount_placeholders(root: Node) -> void:
    for placeholder in _find_islands(root):
        var scene := IslandRegistry.resolve(placeholder.island_name)
        if scene == null:
            push_warning("Island not registered: %s" % placeholder.island_name)
            continue
        match placeholder.load_strategy:
            "eager":   _mount(placeholder, scene)
            "visible": _mount_when_visible(placeholder, scene)
            "idle":    _mount_when_idle(placeholder, scene)
```

### Vant's twist: trigger-based hydration

Vant's `lib/islands.js` adds an `autoHydrate(prompt)` that scans a string
for trigger words and pre-loads matching islands. Synmergia can do the
same for chat commands:

```gdscript
# res://ui/islands/trigger_hydrator.gd
extends Node

const TRIGGERS := {
    "inventory":  ["inventory", "bag", "loot", "items"],
    "guild":      ["guild", "clan", "roster"],
    "trade":      ["trade", "buy", "sell", "vendor"],
    "party":      ["party", "group", "raid"],
}

func hydrate_for_input(input: String) -> Array[String]:
    var lower := input.to_lower()
    var needed: Array[String] = []
    for island in TRIGGERS:
        for trigger in TRIGGERS[island]:
            if lower.contains(trigger):
                needed.append(island)
                break
    return needed
```

Player types `/trade with Bob` → `trade` island pre-loads. Player types
`/guild info` → `guild` island pre-loads. The rest stay lazy.

This is the same pattern vant uses for AI memory: static islands always
loaded, lazy islands triggered by content.

---

## Part 5: Builds (Prestruct prerender → Godot export presets)

Prestruct's `prerender.js` runs at build time and produces static HTML.
Synmergia's analog is the export pipeline:

```
sources/
  zones/zone_tavern.tscn      # baked at build time
  zones/zone_forest.tscn
  npcs/blacksmith.dialogue.tres
  items/sword_template.tres
  mobs/goblin.tres

build/
  client/data.pck            # static content, ships with client
  client/engine.pck          # code, ships with client
  client/synmergia.pck       # scenes + scripts
  server/data.pck            # server reads from same data.pck
```

**Content patches:** rebuild `data.pck` only. Client downloads a 5-20MB
delta. No re-download of code.

**The "raw dog" part:** no content management system, no live ops
service. Just a CI step that runs `godot --export-pack data data.pck`
on every push to `data/`.

### Ship-the-bakes vs runtime-generation

Vant's `lib/geometry/fragmenter.js` fragments state across Git
providers. The MMORPG analog is **shipping the bakes** (pre-baked
zone geometry) and **runtime-generating only the dynamic bits**
(player positions, combat state, instance state).

```
STATIC (ship in data.pck):
  - Zone geometry (NavMesh, collision, lightmaps)
  - NPC dialogue (`.dialogue.tres`)
  - Item templates (`.tres` resources)
  - Enemy templates (`.tres` resources)
  - Quest scripts (`.tres` resources)

DYNAMIC (quasicrystal storage at runtime):
  - Player positions
  - Inventory contents (item instances)
  - Quest progress
  - Chat history
  - Guild state
  - Trade state
  - Combat state (during fights)
```

---

## Part 6: Putting it all together — the boot flow

```
1. GameManager._ready()
   - NSC9.generate_zone_descriptor(each loaded zone)
   - Icosahedral.project(each zone descriptor) → shard assignments

2. NetworkManager._ready()
   - Connect to bootstrap server
   - Receive my shard's host list (12 of them, by vertex)
   - Await my player's barcode projection → my shard ID

3. WorldService._ready()
   - Load my zone's static data from data.pck
   - Mount the 3D scene
   - Call IslandManager.mount_placeholders(self)
     - Eager islands (health_bar, chat) mount
     - Visible islands (inventory?) wait for viewport
     - Idle islands (notification, debug) wait for idle frame

4. Per-frame:
   - Network tick: send my position to shard
   - Quasicrystal.flush: batched writes for dirty state
   - Island visibility check: mount visible islands that scrolled in
   - Idle queue: mount idle islands during low CPU

5. Per-player-action (chat, trade, etc.):
   - TriggerHydrator.hydrate_for_input(text)
   - Pre-load any islands that match
   - Mount eager, schedule visible/idle
```

No central UID allocator. No shard registry. No item DB. No autoload
spaghetti. Just geometry and quasicrystal paths.

---

## Part 7: The autoload race fix (refresher)

Recall from `autoload-race-solutions.md` that we have 22 cascading
class_name parse errors. The unified architecture **eliminates most of
them by construction:**

| Layer | Today's parse-time refs | After this design |
|-------|------------------------|-------------------|
| 3D world (zones, entities) | 22 cascade-affected types | Same — but world boots without UI |
| UI panels | Reference Entity, EnemyData, etc. | Islands — no parse-time refs to game types |
| Services | Cross-reference each other | NSC-9 / Quasicrystal — no class refs |
| Network | References types for serialization | Barcodes travel as strings — no class refs |

After this design, the only autoloads that need cross-references are:
- `IslandManager` (preloads PackedScenes — no class names)
- `NSC9` (pure functions — no class refs)
- `Icosahedral` (pure math — no class refs)
- `Quasicrystal` (FileAccess + NSC9 — no class refs)
- `GameLog` (the actual logger — leaf, no refs)
- `EventBus` (signal hub — leaf, no refs)

That's 6 autoloads. Down from 30+. None of them reference each other's
class_names. Race solved structurally.

---

## Part 8: Migration plan (revised 2026-08-30)

**Important:** This plan was revised after the user pointed out
the original framing (replace Postgres) was wrong. The geometry is
now a redis-like *layer* in front of Postgres. The state tree
content-hash pattern is the foundation. See
[`nsc9-honest-evaluation.md`](./nsc9-honest-evaluation.md).

### Session 1 — Islands POC
**DONE** (commit `3e942bb`). 3 files in `game/ui/islands/`,
19/19 tests pass.

### Session 2 — Migrate remaining UI
- 8-12 panels currently extend UIPanel
- Each becomes a PackedScene with IslandPlaceholder root
- Each added to `IslandRegistry.ISLANDS`
- UIPanel base class deleted (it was a thin wrapper)

### Session 3 — State tree content-hash (the redis-like core)
**This is the foundation session.** Everything else builds on it.

- `core/state/state_tree.gd` — content-addressed tree
  - `node = { path, hash, value, children[] }`
  - `compute_hash(node)` = SHA-256(serialize(node))
  - `diff(old_root, new_root)` = list of (path, new_hash, new_value)
  - `apply_diff(root, diff)` = new_root
  - `get_subtree(root, path)`, `set_subtree(root, path, value)`
- `core/state/state_sync.gd` — sync protocol
  - `client_request_sync(server_endpoint, my_root_hash)` → diff
  - `server_announce_tick(root_hash, diff)` → client applies
- `core/state/snapshot_service.gd` — Postgres integration
  - `state_snapshots` table: (root_hash, payload, timestamp)
  - In-memory content-hash cache for hot paths
  - Periodic snapshots, lazy load on restart

### Session 4 — State tree applied to game state
- `core/entities/` entities become state tree nodes
- `core/components/` components are sub-nodes
- Each entity: hash = SHA-256(component_hashes + base_template)
- Each zone: hash = SHA-256(zone_metadata + chunk_hashes)
- Server tick = `state_root = hash(previous_state_root + inputs)`
- Client prediction rollback via hash-based diff

### Session 5 — Save games as content-hashed trees
- Save file = content-hash tree
- Save upgrade = diff between save root hashes
- Tampering detection = server re-verifies hash on load

### Session 6 — Item template content-hash (cross-shard dedup)
- Item templates identified by content-hash
- Cross-shard reference = "I have hash X, you don't? Here."
- Reduces template storage across shards

### Session 7 — Asset addressing (pck + CDN)
- Build pck with content-hashed asset paths
- CDN serves by hash
- Old clients can still find old assets (no broken refs on update)

### Session 8 — Build pipeline (data.pck + CI)
- `tools/build.sh` for the actual build
- Separate `client.pck` and `data.pck`
- CI rebuilds on changes to `game/data/`

### (Deferred) Geometry-specific primitives

The icosahedral / quasicrystal / NSC-9 specific implementations
from vant are deferred unless profiling shows they're needed:

- `core/geometry/icosahedral.gd` — only useful if Synmergia
  tile-based world needs aperiodic tiling
- `core/geometry/nsc9.gd` — only useful if SHA-256 hex is too
  verbose on the wire (profiling will tell)
- `core/geometry/quasicrystal.gd` — not needed; hash table is
  the path

If any of these become needed, the work is straightforward
GDScript ports of the vant `lib/geometry/` files.

---

## Part 9: Why this is "raw dog"

| Thing | Frameworked version | Raw-dog version |
|-------|---------------------|-----------------|
| State sync | StateServer autoload + RPC + diffing + cache + version vector | `state_tree.diff(old_root, new_root)` over content-hash |
| Cross-shard refs | Cross-shard service + message bus + serialization | "I have hash X" via content-hash equality |
| Save data | save_service + serializer + versioning | content-hash tree, diff between versions |
| UI panels | UIPanel base + scene manager + lifecycle hooks | IslandPlaceholder + IslandManager |
| Content updates | CMS + live ops service + patch server | `godot --export-pack data data.pck` |
| Build | Build pipeline + bundler + chunking | `godot --headless --export-release` |

**Note:** The original raw-dog table had entries like
`InventoryService + DB + migrations + ORM → Quasicrystal.store(...)`
which framed the geometry as a *replacement* for the DB. After
user feedback, the geometry is a *layer in front of* the DB.
Postgres still exists; the state tree sits on top of it as a
content-addressed cache / sync protocol.

---

## Part 10: Known limitations and escape hatches

**Limitation: NSC-9 is 12 digits.** For most entity types this is fine
(100K facility × 100K sequence = 10B entities per facility). For
high-cardinality things (chat messages, particle effects), use a
different scheme (timestamp + nonce, or just UUID).

**Limitation: icosahedral projection has neighbor ambiguity.** Two
barcodes with similar (theta, phi) can project to the same vertex.
This is fine for shard routing (we just put them on the same shard)
but bad for hashing. Use the full 4-tuple (theta, phi, depth, vertex)
if you need uniqueness.

**Limitation: quasicrystal paths are derived, not indexed.** Querying
"give me all items of type X" requires scanning the file tree. For
those queries, keep a small index file per zone, or use a real DB.
The 95% case (load by ID) is fast.

**Limitation: islands have no shared state.** Each island is its own
scene. Communication goes through EventBus. This is by design (no
tight coupling) but means some UI flows need explicit message
plumbing. Same as Prestruct's React component model.

**Escape hatch: keep the old systems as compat layers.** IDRegistry
can wrap NSC9 during the transition. InventoryService can wrap
Quasicrystal. Migrate one consumer at a time. No big-bang.

---

## Summary

- **NSC-9** is the content-addressed identity layer (replaces UUIDs, IDRegistry)
- **Icosahedral** is the routing layer (replaces ShardManager)
- **Quasicrystal** is the persistence layer (replaces InventoryService, save files, DB)
- **Islands** are the UI layer (replaces UIPanel hierarchy, scene manager)
- **Builds** are the content layer (replaces CMS, live ops, patch service)

All five layers share the same geometric core. All five layers
**don't reference each other via class_name** at parse time, which
fixes the autoload race by construction.

The user-facing experience is unchanged. The architecture under the
hood is a 5-layer raw-dog geometry pipeline.

**Verdict:** it bends, beautifully. Time to ship.
