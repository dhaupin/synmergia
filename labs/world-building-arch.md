# Synmergia -- Systems Architecture

> **The bridge.** This doc sits between the spec
> ([`world-building.md`](./world-building.md),
> [`world-building-tick.md`](./world-building-tick.md),
> [`world-building-risks.md`](./world-building-risks.md)) and the
> code in `game/`, `game/core/frame/`, and `srv/`. The spec says
> *what* and *why*; this doc says *how* and *where*. Read the
> spec first.

> **Updated 2026-09-05:** Initial draft. The frame is the
> T3 substrate + scope engine + rules engine. The game is the
> schemas + data + services + UI. The substrate is engine-grade;
> the schemas are game-grade.

---

## 1. What this doc is (and is not)

**Is:**
- The frame architecture: the substrate + engines that make
  Synmergia reusable as an engine.
- The game instance: how the Synmergia MMORPG uses the frame.
- The migration: how the current code maps to the target.

**Is not:**
- A re-statement of the spec. Read `world-building.md` first.
- A code review. Read the source.

---

## 2. The dual goal

Synmergia is two things, and the architecture serves both:

1. **A working MMORPG** (concrete, the poc/mvp)
2. **A game engine** (abstract, "OSS-able", reusable frame)

The frame ships in `game/core/frame/`. Other games can copy the
frame and write their own schemas + data + services. The substrate
is engine-grade; the schemas are game-grade.

| Layer | Lives in | Purpose | Reusable? |
|---|---|---|---|
| Substrate (T3) | `game/core/frame/kv/t3.gd` | Generic content-hash tree | yes (engine) |
| Scope engine | `game/core/frame/srv/scope.gd` | Hierarchy walker + flip | yes (engine) |
| Rules engine | `game/core/frame/srv/rules_engine.gd` | Generic evaluator | yes (engine) |
| | Spatial layer | `game/core/frame/math/` | Icosahedral + NSC-9 (ported from vant axolotl) | DONE |
| | Geometry layer | `game/core/frame/geometry/` | Fragmenter, SpatialFragmenter, Nsc9Bridge (DONE) | DONE |
| Schemas | `game/data/roots/*_schema.tres` | Typed payloads per tree | game-specific |
| Trees | `game/data/roots/<scope>/*.tres` | Tree instances | game-specific |
| Services | `game/core/services/*.gd` | Game logic | game-specific |
| UI / scenes | `game/ui/*`, `game/scenes/*` | User-facing | game-specific |
| Tooling | `srv/` | Run, debug, backup | mixed |

---

## 3. The substrate: T3

A single GDScript class that implements the content-hash tree
primitive. T3 is the substrate every tree instance is built on.

### 3.1 The shape

```gdscript
# game/core/frame/kv/t3.gd
class_name T3
extends RefCounted

# A node in the tree: (path, hash, value_bytes, schema_ref)
# - path: slash-separated, e.g. "/shard_1/zone_5/player_42/inventory/sword_7"
# - hash: SHA-256 of (parent_hash, value_bytes, schema_id)
# - value_bytes: canonical encoding of the value (per schema)
# - schema_ref: pointer to the schema this node conforms to

func insert(path: String, value: Variant, schema: Resource) -> PackedByteArray:
    ...

func get(path: String) -> Variant:
    ...

func delete(path: String) -> bool:
    ...

func hash_subtree(path: String) -> PackedByteArray:
    ...

func diff(old_root: PackedByteArray, new_root: PackedByteArray) -> Array:
    # Returns: [(path, old_hash, new_hash, value_bytes_if_changed)]
    ...

func apply_diff(root: PackedByteArray, diff: Array) -> PackedByteArray:
    ...

func walk(scope: Scope, callback: Callable) -> void:
    ...
```

### 3.2 The contract

- **Determinism:** same path + same value + same schema = same
  hash. Always. (R004, R009  - " the two-platform determinism
  check, the "two clients see the same tree" gate.)
- **Verifiability:** given a hash and a value, anyone can
  verify the value hashes to the hash. No trusted third party.
- **Diffability:** given two roots, the diff is the minimal
  set of path changes. Same roots = empty diff. Different
  roots = finite diff. (D027, state-only diff.)
- **Syncability:** a diff from old to new is enough to
  reconstruct new from old. The diff IS the sync payload.

### 3.3 The schema

Each node carries a `schema_ref`. The schema is a Godot
`Resource` that describes:
- How to canonicalize the value (per-type
  `_to_canonical_bytes(value) -> PackedByteArray` method)
- How to validate the value (per-type
  `_validate(value) -> bool` method)
- How to display the value (per-type
  `_to_display(value) -> String` method)

Schemas are the typed payload. T3 is the untyped substrate.
The schema is what makes a tree "a seed tree" or "a state
tree" or "a rules tree."

### 3.4 Why one class, not many

We could have a `SeedTree` class, a `StateTree` class, a
`RulesTree` class. We don't. The substrate is generic; the
schema is the difference. This matches vant's `brain.js`
pattern: one class, mode-as-data.

The complexity users add lives in the schemas and engines
on top. T3 itself doesn't change.

---

## 4. The scope engine

The hierarchy walker. Knows how to walk a stack of scopes,
resolve overrides, and flip rules at scope boundaries.

### 4.1 The scope concept

A scope is a position in a hierarchy. For Synmergia:

```
world  ->  shard  ->  instance  ->  player
```

For another game on the same frame:

```
galaxy  ->  sector  ->  system  ->  planet  ->  character
realm  ->  region  ->  district  ->  character
```

The hierarchy is a tree. Each node in the hierarchy is a
scope. Each scope can have its own environment (sec. 6) and its
own rule overrides (sec. 5).

### 4.2 The scope class

```gdscript
# game/core/frame/srv/scope.gd
class_name Scope
extends RefCounted

var name: String
var parent: Scope               # null for root scope
var children: Array[Scope]
var rules_overrides: Dictionary # rule_id -> resolution strategy override
var environment: Environment    # the world environment for this scope

func walk(callback: Callable) -> void:
    # Walks self + descendants
    ...

func resolve(path: String, stack: Array[Scope]) -> Variant:
    # Walks the stack top -> bottom, returns first match
    ...

func flip(rule_id: String, resolution: String) -> void:
    # Sets a rule override at this scope
    ...
```

### 4.3 The stack

When a player is in a context, the active stack is the chain
from the player's scope up to the world scope:

```
[PlayerScope, InstanceScope, ShardScope, WorldScope]
```

The stack is what gets content-hashed for the seed derivation
(sec. 7.2). The scope engine walks the stack to resolve rules,
values, etc.

### 4.4 The "flip" semantic

A scope can declare an override for a rule. When the scope
engine resolves a rule at a position in the hierarchy, it
checks the scope for an override. If present, the override's
resolution strategy is used. Otherwise, the default is used.

Example: a "PvP zone" instance scope flips the rules-tree's
normal top-wins to bottom-wins for the `can_pvp` rule. In
the PvP zone, the world's `no_PvP` rule overrides the
player's `I_want_PvP` setting. Outside the PvP zone, the
player's setting wins.

This is the "games can flip anything anywhere" machinery.
A hardcore-mode character flips the rules for death penalty.
A no-build zone flips the rules for placement. A VIP
subscription flips the rules for inventory size.

---

## 5. The rules engine + rules tree

The new piece. A generic evaluator that takes
`(action, context, rules_tree)  ->  decision`.

### 5.1 The rules tree

A rules tree is an instance of T3 with a `RulesSchema`
payload. Each node in the rules tree is a rule. A rule has:

| Field | Type | Purpose |
|---|---|---|
| `rule_id` | String | unique identifier |
| `resolution` | enum | TOP_WINS / BOTTOM_WINS / PREDICATE_GATED / ALL_WINS_WITH_EFFECT |
| `predicate` | Callable | for PREDICATE_GATED and ALL_WINS_WITH_EFFECT |
| `default_allow` | bool | fallback when no scope override |

### 5.2 The rules engine

```gdscript
# game/core/frame/srv/rules_engine.gd
class_name RulesEngine
extends RefCounted

var _rules_tree: T3
var _scope_engine: ScopeEngine

func register_rule(rule_id: String, resolution: String,
                   predicate: Callable, default_allow: bool) -> void:
    ...

func evaluate(action: String, context: Dictionary,
              stack: Array[Scope]) -> Dictionary:
    # Returns: {allow, reason, modified_action, applied_rules}
    ...
```

### 5.3 The mitigation pattern

The current 5 infrastructure services (QoS, Security,
SecurityMonitor, AppFirewall, AutoResponse) each have their
own decision logic. With the rules engine, they become thin
wrappers that emit rule_requests:

```
OLD:
  QoS: "is this within rate limit?" (own logic)
  Security: "is this an exploit?" (own logic)
  SecurityMonitor: "is this suspicious?" (own logic)
  AppFirewall: "is this peer/IP allowed?" (own logic)
  AutoResponse: "what action to take?" (own logic)

NEW:
  QoS: emits rule_request("rate_limit", {player, action, count})
  Rules engine evaluates, returns decision
  QoS acts on decision
```

Each rule in the rules tree declares its resolution strategy
(sec. 5.1). The "A/B/C/D" stack-direction question is now
per-rule, not per-system. The game developer picks the
semantics that fit each rule.

> **Phase note:** the rules engine is a **Phase 2** deliverable.
> Phase 1 is just T3 + scope + the two canonical trees. The
> rules engine is the second wave; it consolidates the existing
> 5 services' decision logic.

---

## 6. The world environment

The runtime container for a scope. Holds N trees (seed, state,
rules, etc.) and knows which scope it belongs to.

### 6.1 The environment class

```gdscript
# game/core/frame/srv/environment.gd
class_name Environment
extends RefCounted

var scope: Scope
var trees: Dictionary  # tree_name -> T3 instance

func get_tree(name: String) -> T3:
    ...

func add_tree(name: String, tree: T3) -> void:
    ...

func tick(delta: float) -> void:
    # Runs each tree's per-tick work
    ...
```

### 6.2 The trees per environment

Each environment has:
- A seed tree (sec. 7)  - " canonical, recursive, deterministic
- A state tree (sec. 8)  - " canonical, runtime
- A rules tree (sec. 5)  - " the gating rules
- ...any other tree the game wants (sec. 9)

For Synmergia's poc/mvp:

| Scope | Trees |
|---|---|
| `world_env` | world seed tree, world state tree, world rules tree |
| `shard_env` ([U+0413] - N) | shard seed tree, shard state tree, shard rules tree |
| `instance_env` ([U+0413] - N) | instance seed tree, instance state tree, instance rules tree |
| `player_env` ([U+0413] - N) | player seed tree, player state tree, player rules tree |

The data for each tree instance lives in `game/data/roots/`:

```
game/data/roots/
[U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] world/
[U+0432]"[U+04EE]   [U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] seed.tres
[U+0432]"[U+04EE]   [U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] state.tres
[U+0432]"[U+04EE]   [U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496] rules.tres
[U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] shard_001/
[U+0432]"[U+04EE]   [U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] seed.tres
[U+0432]"[U+04EE]   [U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] state.tres
[U+0432]"[U+04EE]   [U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496] rules.tres
[U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] instance_abc/
[U+0432]"[U+04EE]   [U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496] ...
[U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496] player_xyz/
    [U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496] ...
```

### 6.3 The TTL

A scope environment can have a TTL. When the TTL expires, the
environment is GC'd. The scope's state is finalized: locked
seeds are committed, open seeds are released, state is
snapshotted.

For `open + instance` (dungeon run, arena match): the
environment's TTL is **5 minutes after the last player leaves**
(D032). Reconnect within the window restores the environment
and its `open` seed.

For `frame + X` (dream, tutorial, jail cell): the environment
is GC'd at frame end. The seed is not preserved.

For `locked + X` (world map, shard terrain, player's house):
the environment has no TTL. It lives as long as the world lives.

### 6.4 Manifest storage (D031)

The `WorldManifest` is the durable storage for all `locked`
seeds and the world-level configuration. Backup policy:

- **Primary:** Postgres `world_manifest` table (1 read replica)
- **Daily snapshot:** `s3://synmergia-backups/manifest/<date>.json.gz`
- **Cold tier:** 30-day retention

Recovery: `manifest --restore --from <date>` rebuilds state
to that snapshot. **All player state < date is lost.** This
is the price of the recursive model: lose the manifest, lose
the world. (D031  - " to be decided when we hit Phase 1 infra.)

---

## 7. The seed tree (canonical instance)

The first canonical tree. Recursive, deterministic,
content-hashed. (Spec sec. 4, D025-D026.)

### 7.1 The SeedSchema

```gdscript
# game/data/roots/seed_schema.tres (or core/schemas/seed_schema.gd)
class_name SeedSchema
extends Resource

@export var seed_type: String         # "locked" | "open" | "frame"
@export var visibility_scope: String  # "world" | "shard" | "instance" | "player"

func _to_canonical_bytes(value: Dictionary) -> PackedByteArray:
    # Canonical encoding: type + scope + path + parameters
    ...

func _validate(value: Dictionary) -> bool:
    ...
```

### 7.2 The derivation

```gdscript
# game/core/frame/kv/seed_chain.gd
static func derive_seed(stack: Array[PackedByteArray],
                        path: String) -> PackedByteArray:
    var acc := path.to_utf8_buffer()
    for layer_seed in stack:  # player  ->  shard  ->  world
        acc = HashingContext.sha256(layer_seed + acc)
    return acc
```

The stack is `[player_seed, shard_seed, world_seed]` (top to
bottom). The derivation is bottom-up: world_seed folds first,
shard folds on top, player folds on top. The world rules
overpower the player only when the player has no specific
override (top-wins on lookup; bottom-most non-empty value).

### 7.3 The roots storage

The seed tree's data lives in `game/data/roots/<scope>/seed.tres`.
Each scope's seed tree is an independent T3 instance.

### 7.4 The critical parameters (D033)

Shard parameters can be flagged `critical: bool`. Critical
parameters bypass the 5-min coalesce window (D024) and go
through immediately. Default criticality:

| Parameter | Critical? |
|---|---|
| `boss_defeated` | yes |
| `respawn_rate_modifier` | no |
| `season_active` | yes |
| `world_event_active` | no |

---

## 8. The state tree (canonical instance)

The second canonical tree. Runtime, mutable, content-hashed.
(Spec sec. 5, D027.)

### 8.1 The StateSchema

```gdscript
# game/data/roots/state_schema.tres
class_name StateSchema
extends Resource

@export var type: String  # "position" | "inventory" | "health" | ...

func _to_canonical_bytes(value: Dictionary) -> PackedByteArray:
    ...

func _validate(value: Dictionary) -> bool:
    ...
```

### 8.2 The diff format (D027)

State-only diff. Each diff entry is:

| Field | Type | Always present? |
|---|---|---|
| `path` | String | yes |
| `old_hash` | PackedByteArray | yes (null if new node) |
| `new_hash` | PackedByteArray | yes |
| `value_bytes` | PackedByteArray | only if `new_hash` differs from what client has |

A client receiving a diff applies it to its local state tree
root. If the new root hash matches the server's, sync is
complete. If not, the client requests the full subtree.

### 8.3 The roots storage

The state tree's data lives in
`game/data/roots/<scope>/state.tres`.

---

## 9. Other trees

Added as needed. Each is an instance of T3 with its own
schema.

For Synmergia's poc/mvp, candidate other trees:
- **Definition tree:** world config (zones, NPCs, loot tables,
  quests, dialogues)
- **Memory tree:** AI agent memory (NPC AI, player helpers)
- **Social tree:** player relationships (friends, guild, party)

For other games on the frame, any tree the game wants. The
substrate is generic; the schemas are typed. The complexity
lives in the schemas.

---

## 10. Data flow

A tick, end-to-end:

1. **Client  ->  server:** `cmd` over WebSocket.
2. **Server parse:** `network_manager.gd` parses, validates,
   queues. (Spec sec. 11.)
3. **Tick loop** in `tick.gd`:
   a. Walk the active scope stack
      (player  ->  instance  ->  shard  ->  world).
   b. For each `cmd`:
      - Apply to the appropriate tree (state, seed, etc.).
      - The rules engine evaluates the `cmd` against the
        rules tree (Phase 2+).
      - Allowed `cmd`s mutate the trees.
   c. Compute the diff per tree (T3::diff).
   d. Filter the diff by visibility scope (D026).
   e. Emit the diff to the appropriate clients.
4. **Server  ->  client:** diff over WebSocket. Client applies
   the diff, verifies the root hash, requests resync if
   mismatch.

A full description of the tick model is in
[`world-building-tick.md`](./world-building-tick.md).

---

## 11. Process topology

### 11.1 Today (Phase 2+)

```
[U+0432]"[U+04A2][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0497]
[U+0432]"[U+04EE] docker-compose                               [U+0432]"[U+04EE]
[U+0432]"[U+04EE]                                              [U+0432]"[U+04EE]
[U+0432]"[U+04EE]  synmergia (Godot, all autoloads, frame      [U+0432]"[U+04EE]
[U+0432]"[U+04EE]  primitives at game/core/frame/)            [U+0432]"[U+04EE]
[U+0432]"[U+04EE]  postgres                                    [U+0432]"[U+04EE]
[U+0432]"[U+04EE]  redis                                       [U+0432]"[U+04EE]
[U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+04B3]
```

One Godot process. All services autoloaded. Frame primitives
are consolidated at `game/core/frame/` (math, kv, srv, db).

### 11.2 Phase 2: Frame Primitives Consolidation [U+2705] COMPLETE

Frame primitives were consolidated directly into `game/core/frame/` (math, kv, srv, db) instead of extracting to a separate `srv/frame/` container. The `FrameClient` in `game/core/utils/frame_client.gd` provides a local fallback RulesEngine/Scope/T3 when the frame HTTP bridge is unavailable. Full HTTP bridge extraction to `srv/frame/` is deferred (see Open Questions).

### 11.3 Phase 3 (coordinator extract)

```
[U+0432]"[U+04A2][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0497]
[U+0432]"[U+04EE]  synmergia (per shard)                       [U+0432]"[U+04EE]
[U+0432]"[U+04EE]  coordinator (HA-pair in prod)               [U+0432]"[U+04EE]
[U+0432]"[U+04EE]  postgres (HA)                               [U+0432]"[U+04EE]
[U+0432]"[U+04EE]  redis                                       [U+0432]"[U+04EE]
[U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+04B3]
```

Coordinator becomes its own process. Postgres HA. Cross-
shard events go through the coordinator.

### 11.4 Phase 4 (edge shards)

```
[U+0432]"[U+04A2][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0497]
[U+0432]"[U+04EE]  synmergia-world-shard-1..N                  [U+0432]"[U+04EE]
[U+0432]"[U+04EE]  edge-shard-region-X-1..M (regional cache)   [U+0432]"[U+04EE]
[U+0432]"[U+04EE]  coordinator (HA-pair)                       [U+0432]"[U+04EE]
[U+0432]"[U+04EE]  postgres (HA)                               [U+0432]"[U+04EE]
[U+0432]"[U+04EE]  redis (HA)                                  [U+0432]"[U+04EE]
[U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+0496][U+0432]"[U+04B3]
```

Edge shards for low-latency regional cache. (Spec sec. 11.11,
research doc sec. 2.)

---

## 12. `srv/` layout

The multipurpose room. Definitions, setups, tooling.

```
srv/
[U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] docker/                # mode dispatcher, certbot, healthcheck
[U+0432]"[U+04EE]   [U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] entrypoint.sh
[U+0432]"[U+04EE]   [U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] test-headless.sh
[U+0432]"[U+04EE]   [U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496] README.md
[U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] http/                  # route definitions, request/response schemas
[U+0432]"[U+04EE]   [U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] routes/
[U+0432]"[U+04EE]   [U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496] schemas/
[U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] seed/                  # seed data, fixture players, test worlds
[U+0432]"[U+04EE]   [U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] fixtures/
[U+0432]"[U+04EE]   [U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496] generators/
[U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] tools/                 # scripts, debug commands, ops utilities
[U+0432]"[U+04EE]   [U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] tick/
[U+0432]"[U+04EE]   [U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] diff/
[U+0432]"[U+04EE]   [U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496] debug/
[U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] backup/                # manifest backup, recovery (D031)
[U+0432]"[U+04EE]   [U+0432]"[U+04A3][U+0432]"[U+0496][U+0432]"[U+0496] backup.sh
[U+0432]"[U+04EE]   [U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496] restore.sh
[U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496] migration/             # schema migrations, godot project version migrations
    [U+0432]""[U+0432]"[U+0496][U+0432]"[U+0496] *.sql
```

`labs/` routes for providers reference the consolidated frame at `game/core/frame/`. The frame was not extracted to a separate project; it remains embedded in the Godot project. `game/data/roots/` is permanent  -  it holds the actual game data.

---

## 13. Component map (spec  ->  code)

| Spec concept | Spec ref | Current code | Target code | Status |
|---|---|---|---|---|
| T3 substrate | this doc sec. 3 | `game/core/frame/kv/t3.gd` | `game/core/frame/kv/t3.gd` | DONE |
| Scope engine | this doc sec. 4 | `game/core/frame/srv/scope_hierarchy.gd`, `game/core/frame/srv/scope.gd`, `game/core/frame/srv/scope_engine.gd` | `game/core/frame/srv/scope.gd` | DONE |
| Rules engine | this doc sec. 5 | `game/core/frame/srv/rules_engine.gd`, `game/core/frame/srv/rules_schema.gd` | `game/core/frame/srv/rules_engine.gd`, `game/core/frame/srv/rules_schema.gd` | DONE |
| Definition tree | this doc sec. 9 | `game/core/frame/kv/definition_tree.gd`, `game/core/frame/kv/definition_schema.gd` | `game/core/frame/kv/definition_tree.gd`, `game/core/frame/kv/definition_schema.gd` | DONE |
| SeedSchema Resource | this doc sec. 7, spec sec. 4 | none | `game/data/roots/seed_schema.gd` | DONE |
| StateSchema Resource | this doc sec. 8, spec sec. 5 | none | `game/data/roots/state_schema.gd` | DONE |
| Seed tree (canonical) | this doc sec. 7, spec sec. 4 | `game/core/frame/kv/seed_chain.gd` | `game/core/frame/kv/seed_chain.gd` | DONE |
| State tree (canonical) | this doc sec. 8, spec sec. 5 | `game/core/frame/kv/state_tree.gd` | `game/core/frame/kv/state_tree.gd` | DONE |
| Recursive seed derivation | spec sec. 4.2, D025 | `game/core/frame/kv/seed_chain.gd::derive_seed` | `seed_chain.gd::derive_seed` | DONE |
| Seed tree test | prd-seed-schema sec. US-005 | none | `game/data/roots/test_seed_schema.gd` | DONE |
| State tree test | prd-state-schema sec. US-005 | none | `game/data/roots/test_state_schema.gd` | DONE |
| Seed tree (tests) | prd-seed-schema sec. US-005 | `game/core/frame/kv/test_seed_chain.gd` | `game/core/frame/kv/test_seed_chain.gd` | DONE |
| State tree (tests) | prd-state-schema sec. US-005 | `game/core/frame/kv/test_state_tree.gd` | `game/core/frame/kv/test_state_tree.gd` | DONE |
| SeedReceipt Resource | prd-login-seed-chain sec. US-001 | none | `game/core/schemas/seed_receipt.gd` | DONE |
| SeedReceipt test | prd-login-seed-chain sec. US-001 | none | `game/core/schemas/test_seed_receipt.gd` | DONE |
| FrameService | prd-frame-authority sec. US-001 | `game/core/services/frame_service.gd` | `game/core/services/frame_service.gd` | DONE |
| Frame authority test | prd-frame-authority sec. US-005 | none | `game/tests/test_frame_authority.gd` | DONE |
| ShardParameterDefinition | prd-critical-params sec. US-001 | none | `game/core/schemas/shard_parameter_definition.gd` | DONE |
| ShardParameters autoload | prd-critical-params sec. US-002 | none | `game/core/services/shard_parameters.gd` | DONE |
| Critical params test | prd-critical-params sec. US-006 | none | `game/tests/test_critical_params.gd` | DONE |
| Param .tres samples (4) | prd-critical-params sec. US-006 | none | `game/data/roots/world/parameters/` | DONE |
| Two-orthogonal-axes (D026) | spec sec. 4.1 | none | `SeedSchema` payload | DONE |
| State-only diff (D027) | spec sec. 5.6, D027 | none | `T3::diff` | DONE |
| LRU cache | vant `lib/cache.js` | `game/core/frame/kv/lru_cache.gd` | `game/core/frame/kv/lru_cache.gd` | DONE |
| Snapshot store | content-hash state tree | `game/core/frame/db/snapshot_store.gd` | `game/core/frame/db/snapshot_store.gd` | DONE |
| Manifest SPOF (D031) | this doc sec. 6.4 | none | `srv/backup/manifest.sh`, `backup.sh`, `restore.sh` | DONE |
| Open seed TTL (D032) | this doc sec. 6.3, spec sec. 4.8 | none | `game/core/services/open_seed_registry.gd`, `game/core/schemas/instance_type_definition.gd` | DONE |
| Login seed chain (D029) | validation sec. 1 | none | `core/services/login_service.gd` (build_seed_receipt), `core/schemas/seed_receipt.gd` | DONE |
| Frame seed authority (D030) | validation sec. 2 | none | `core/services/frame_service.gd` | DONE |
| Critical params (D033) | this doc sec. 7.4, spec sec. 4.8 | none | `core/services/shard_parameters.gd`, `core/schemas/shard_parameter_definition.gd` | DONE |
| Account rollup (D028) | spec sec. 9.18, D028 | none | `core/services/account_rollup.gd` | DONE |
| Vant multibrain stack | vant `brain.js:1510-1900` | `game/core/frame/srv/scope.gd`, `game/core/frame/srv/scope_engine.gd` | `game/core/frame/srv/scope.gd` (port) | DONE |
| NSC-9 barcode format | vant `geometry/nsc9.js` | `game/core/frame/math/nsc9.gd` + `test_nsc9.gd` | `game/core/frame/math/nsc9.gd` + `test_nsc9.gd` | DONE |
| Icosahedral projection | vant `geometry/icosahedral.js` | `game/core/frame/math/icosahedral.gd` + `test_icosahedral.gd` | `game/core/frame/math/icosahedral.gd` + `test_icosahedral.gd` | DONE |
| Vant fragmenter | [prd-geometry.md](./prd-geometry.md) sec. US-001 | `game/core/frame/geometry/fragmenter.gd` | `game/core/frame/geometry/fragmenter.gd` | DONE |
| Spatial geometry fragmenter | `prd-spatial-geometry.md` sec. US-001 | `game/core/frame/geometry/spatial_fragmenter.gd` | `game/core/frame/geometry/spatial_fragmenter.gd` | DONE |
| Geometry integration bridge | `prd-geometry.md` sec. 6K | NSC-9  ->  SpatialFragmenter  ->  T3 wiring | `Nsc9Bridge` in `game/core/frame/geometry/nsc9_bridge.gd`, wired into EntityService + ZoneManager | DONE |

---

### 13.1 Geometry Layer Integration Pattern

The geometry layer connects via pure function calls from services. No autoloads, no global state. Services import via `class_name` and instantiate locally.

**Integration chain:**
```
NSC-9 code (nsc9.gd)  ->  Nsc9Bridge  ->  SpatialFragmenter address  ->  [T3 state tree]
                                              v 
                                     Fragmenter.data fragment  ->  [Storage adapter]
```

**Nsc9Bridge** (`game/core/frame/geometry/nsc9_bridge.gd`) is the unified integration point. 10 methods:
- `nsc9_to_address(code, depth)` — NSC-9 -> SpatialFragmenter address (facility->x, axis->face, sequence->y/z)
- `address_to_t3_path(address)` — Address -> T3 path string
- `nsc9_to_t3_path(code, depth)` — NSC-9 code -> T3 path (convenience)
- `store_nsc9_state(t3, nsc9_code, state, depth, metadata)` — Store entity state in T3
- `store_nsc9_fragmented(t3, nsc9_code, state, fragmenter, depth)` — Fragment + store in T3
- `restore_nsc9_fragmented(t3, nsc9_code, fragmenter, depth)` — Restore fragmented state from T3
- `query_nsc9_region(t3, nsc9_code, depth)` — Query fragments in region
- `query_nsc9_vertex(t3, nsc9_code)` — Query all fragments on a face
- `is_spatial_nsc9(code)` — Check if code has spatial axis (1-12)
- `entity_spatial_to_vertex(facility, vertex)` — Entity spatial -> face code

**Recommended wiring:**
1. Services needing spatial addresses call `Nsc9Bridge.nsc9_to_address()` directly
2. Services needing spatial state in T3 call `Nsc9Bridge.store_nsc9_state()` or `store_nsc9_fragmented()`
3. Services needing data shards call `Fragmenter.fragment()` directly
4. NSC-9 -> face conversion is handled by `SpatialFragmenter.nsc9_code_to_vertex()` (1-12 -> 0-11)

**Service-level integration:**
- **EntityService**: `_nsc9_bridge` initialized in `_init_spatial_and_t3()`, caches NSC-9 codes per entity in `_entity_nsc9_codes`, sets `metadata.nsc9_code` on registration
- **ZoneManager**: `_nsc9_bridge` initialized in `_init_spatial_fragmenter()`, derives NSC-9 codes per zone via `_compute_nsc9_code()`, exposes `get_zone_nsc9_code(zone_id)` and `get_zone_nsc9_t3_path(zone_id)`

**File locations:**
- `game/core/frame/geometry/fragmenter.gd`  -  Aperiodic data fragmenter (Vant port)
- `game/core/frame/geometry/spatial_fragmenter.gd`  -  Spatial geometry fragmenter
- `game/core/frame/geometry/nsc9_bridge.gd`  -  NSC-9 -> SpatialFragmenter -> T3 bridge
- `game/core/frame/geometry/test_nsc9_bridge.gd`  -  Bridge integration tests (9 test cases)
- `game/core/frame/geometry/test_fragmenter.gd`  -  Fragmenter tests
- `game/core/frame/geometry/test_spatial_fragmenter.gd`  -  Spatial fragmenter tests
- `game/core/frame/math/nsc9.gd`  -  NSC-9 barcode encoding (spatial axis source)
- `game/core/frame/math/icosahedral.gd`  -  Icosahedral projection (face source)
- `game/core/frame/kv/t3.gd`  -  Content-hash tree substrate (spatial state storage)
- `game/core/frame/kv/state_tree.gd`  -  State tree wrapper (spatial state persistence)

**Axis reservation:**
- 001-099: spatial axis (icosahedral vertices 1-12)
- 100-199: factional axes
- 200-299: temporal sub-axes
- 300-399: social axes
- 400-499: game-specific axes
- 500-999: free

---

## 14. Migration roadmap

| Phase | Deliverable | Risk | Owner | Status |
|---|---|---|---|---|
| 1 | T3 substrate (`t3.gd` + tests) | low | frame team | DONE |
| 1 | SeedSchema + seed tree instance | low | frame team | DONE |
| 1 | StateSchema + state tree instance | low | frame team | DONE |
| 1 | Scope engine (basic, no flip) | low | frame team | DONE |
| 1 | Login seed chain (D029) | med | login team | DONE |
| 1 | Frame seed authority (D030) | med | game team | DONE |
| 1 | Critical params (D033) | low | game team | DONE |
| 1 | Open seed TTL (D032) | low | game team | DONE |
| 1 | Manifest backup (D031) | low | infra team | DONE |
| 1 | `srv/backup/`, `srv/tools/`, `srv/seed/` scaffolding | low | infra team | DONE |
| 2 | Rules engine | med | infra team | DONE |
| 2 | Refactor 5 services to use rules engine | med | infra team | DONE |
| 2 | Definition tree (world config) | low | game team | DONE |
| 2 | Frame extract to separate container | high | infra team | DEFERRED (in-process; FrameClient is the integration point -- see TASKS.md 2026-09-19) |
| 3 | Coordinator process | high | infra team | PENDING |
| 3 | Account rollup (D028) | med | anticheat team | DONE |
| 3 | Memory tree + social tree | low | game team | DONE (primitives + game wiring: EnemyAI memory/grudges, FriendsService social mirror) |
| 3 | Geometry layer: fragmenter, spatial fragmenter, NSC-9 bridge | med | frame team | DONE |
| 3.x | Geometry integration: EntityService + ZoneManager wired to Nsc9Bridge | med | frame team | DONE |
| 4 | Edge shards | high | infra team | PENDING |
| 4 | Vant fragmenter implementation | med | frame team | DONE |
| 4 | Vant icosahedral ports | med | frame team | PENDING |
| 4 | Quasicrystal extension (optional) | med | frame team | PENDING |
| 4 | Other trees (game-specific) as needed | low | game team | PENDING |

---

## 15. Open questions

For the user to resolve when the time comes:

1. **T3 instance per scope or shared?** Each scope has its own
   T3 instance, or one global T3 with scope-prefixed paths?
   My read: per-scope. Easier to reason, easier to GC.
   **Status (2026-09-05):** pending. T3 PRD leaves this
   open (one class, instances are owned by callers).

2. **Schema discovery.** How does T3 know which schema applies
   to a path? Conventions (e.g., `*/inventory/*` uses
   `InventorySchema`)? Or explicit declaration per node? My
   read: conventions + a `schema_registry.tres` for overrides.
   **Status (2026-09-05):** pending. Schemas are passed
   explicitly to T3.insert() in v1 (no convention);
   the registry is a v2 enhancement.

3. **Scope hierarchy configurability.** Is the hierarchy
   (world  ->  shard  ->  instance  ->  player) baked into the game,
   or is it data? My read: baked for now, data in Phase 4+.
   **Status (2026-09-05):** RESOLVED. Data-driven via
   `ScopeHierarchy.tres`. The hierarchy is a Resource,
   not hardcoded. Other games on the frame define their
   own. See `prd-scope-engine.md`.

4. **Rules tree mutation at runtime.** Can a player flip their
   own rules? (E.g., "I want hardcore mode.") Or is the
   rules tree admin-only? My read: per-player rules yes, per-
   world rules admin-only.
   **Status (2026-09-05):** pending. Not in the Phase 1
   PRD queue; deferred to Phase 2 with the rules engine.

5. **Multi-iso FFI (deferred).** The frame was consolidated to `game/core/frame/` within the Godot project rather than extracted to a separate service. Cross-language FFI (Julia/C++) for hot paths remains a Phase 4+ exploration (see `labs/polyglot-ffi/`).

6. **Vant sync.** As we port vant's patterns, do we push our
   changes back to vant, or fork? My read: contribute back,
   keep the projects in sync.
   **Status (2026-09-05):** pending. Documented in section
   16 (Borrowed from vant). Sync mechanism TBD.

7. **Manifest backup format.** Is the manifest a single .tres
   or partitioned per scope? My read: single manifest,
   partitioned storage. (See D031.)
   **Status (2026-09-05):** RESOLVED. Single manifest
   (one Postgres table), 3-tier backup (Postgres + S3
   - cold). See `prd-manifest-backup.md`.

### Fragmenter wiring patterns (Vant fragmenter integration)

The Vant fragmenter is wired into game services as a pure,
stateless primitive. Each service owns its own `Fragmenter`
instance (never an autoload) and uses lattice keys derived from
a sequence integer to shard data deterministically.

**EntityService - inventory shard (per-entity data):**

```gdscript
# EntityService.gd - inventory shard pattern
func _init_spatial_and_t3() -> void:
    # Per-service instance, NOT an autoload
    _fragmenter := Fragmenter.new()

func _shard_entity_state(entity_id: String, state: Dictionary) -> Array[Dictionary]:
    # Derive lattice keys from a stable entity sequence
    var sequence: int = entity_id.hash()
    var keys: Array[String] = _fragmenter.derive_lattice_keys(sequence, 5)

    # Split entity state into 5 XOR-spread fragments
    var fragments: Array[Dictionary] = _fragmenter.fragment(state, 5)

    # Attach lattice key to each fragment for deterministic retrieval
    for i in range(fragments.size()):
        fragments[i]["lattice_key"] = keys[i] if i < keys.size() else ""

    return fragments

func _restore_entity_state(entity_id: String, fragments: Array[Dictionary]) -> Dictionary:
    # Weld fragments back in shard order
    var welded: String = _fragmenter.weld(fragments)
    var state: Variant = JSON.parse_string(welded)
    return state
```

**ZoneManager - world shard (per-zone data):**

```gdscript
# ZoneManager.gd - world shard pattern
func _init_spatial_fragmenter() -> void:
    # Per-service instance, NOT an autoload
    _fragmenter := Fragmenter.new()

func _shard_zone_world(zone_id: String, world_state: Dictionary) -> Array[Dictionary]:
    # Derive lattice keys from zone sequence
    var sequence: int = zone_id.hash()
    var keys: Array[String] = _fragmenter.derive_lattice_keys(sequence, 5)

    # Split world state into 5 XOR-spread fragments
    var fragments: Array[Dictionary] = _fragmenter.fragment(world_state, 5)

    # Attach lattice key to each fragment for deterministic retrieval
    for i in range(fragments.size()):
        fragments[i]["lattice_key"] = keys[i] if i < keys.size() else ""

    return fragments

func _restore_zone_world(zone_id: String, fragments: Array[Dictionary]) -> Dictionary:
    # Weld fragments back in shard order
    var welded: String = _fragmenter.weld(fragments)
    var world_state: Variant = JSON.parse_string(welded)
    return world_state
```

**Fragment contract:**
- `fragment(data, num_fragments)` returns `Array[Dictionary]` with
  `shard` (int), `data` (base64 String), `size` (int), `checksum`
  (int) - each fragment is XOR-spread with its shard key
- `weld(fragments)` sorts by shard, verifies checksum, reverses XOR
  spreading, concatenates and returns the UTF-8 string
- Lattice keys from `derive_lattice_keys` are used as storage
  addresses (`vfragment-{key}-{shard}.json` naming)

**Status (2026-09-17):** DONE - EntityService and ZoneManager use the Vant fragmenter pattern for shard/world state. EntityService T3 restore and NSC-9 Bridge restore bugs fixed (`result.get("metadata")` instead of `result.get("value")`). See `labs/prd-geometry.md` sec. US-001 to US-003.

### Questions answered in 2026-09-05 session (not in original list)

These were raised in the planning session, not in the
original OQ list, but resolved:

- **A. Existing `core/state/` (FSMs).** Should the new
  state tree coexist with the old FSM code, or replace
  it? RESOLVED: replace. The old `core/state/state.gd`
  and `state_machine.gd` are deprecated. FSM migrates
  to the new architecture as `behavior_state` nodes in
  the state tree.

- **B. Schema evolution.** When a schema gains a new
  field, how do existing `.tres` files migrate?
  RESOLVED: option (a), auto-upgrade on load. Godot's
  default pattern; each schema has a `version: int`
  field and `_upgrade_vN_to_vM()` methods.

- **C. Empty world bootstrap.** How does the first
  server run create the world env? RESOLVED:
  fixture-driven. `game/data/roots/world/*.tres` exist
  from day one, server loads them on startup. Server
  fails fast if files are missing.

- **D. Open seed TTL semantics.** When does the
  5-min reconnect window start? RESOLVED: at last
  character logout (not at instance creation). Per
  D032.

- **E. Login flow scope.** Is the login flow per-
  account or per-character? RESOLVED: per-character.
  Seeds are character-scoped, login is per-character.

---

## 16. Borrowed from vant

This architecture borrows from
[vant](https://github.com/dhaupin/vant/tree/axolotl) (axolotl
branch), the user's sibling repo. Specifically:

- **Multibrain stack pattern** (vant `lib/brain.js:1510-1900`)
   ->  scope engine (sec. 4). Vant's brain stack with push/pop/
  current is the prototype for our scope stack. We extend it
  with: typed scopes (player, shard, etc.), explicit override
  semantics, and the "flip" mechanism (sec. 4.4).

- **Geometric addressing** (vant `lib/geometry/icosahedral.js`, `tilings.js`, `quasicrystal.js`, `fragmenter.js`)  ->  spatial
   layer. The icosahedral projection is the candidate for world
   chunk addressing; the Penrose P3 tiling is the candidate for
   region distribution; the fragmenter (Knuth multiplicative hash,
   `LATTICE_MULTIPLIER = floor(phi * 2^32) = 2654435769`) is the
   candidate for shard partitioning. The NSC-9  ->  SpatialFragmenter
   ->  T3 bridge (`Nsc9Bridge` in `game/core/frame/geometry/nsc9_bridge.gd`)
   completes the integration; NSC-9 axes 1-12 map to faces 0-11
   via `SpatialFragmenter.nsc9_code_to_vertex()`.

   In Phase 3.x the fragmenter, spatial fragmenter, and NSC-9 bridge
   are implemented and wired into EntityService + ZoneManager.
   See `labs/prd-geometry.md`.

- **Single class, schema-as-data** (vant `lib/brain.js` overall)
   ->  T3 substrate (sec. 3). Vant's brain is one class with mode-
   as-data. T3 is the same pattern for content-hash trees.

- **Content hashing** (vant `lib/quasicrystal.js` overall)  ->  SHA-256
   hash chain in T3. Vant's quasicrystal uses barcode projection;
   we use SHA-256 because we need cryptographic tamper-evidence,
   not just deterministic projection.

Each `game/core/frame/X/Y.gd` file has a
`## Ported from vant axolotl lib/path/X.js` header. As we
improve the ports, we push the changes back to vant. This is
a sibling-repo relationship, not a fork. The stub
`connectors/vant/vant_connector.gd` (game side) is the
runtime bridge for agent sessions; the static port lives
in `game/core/frame/`.

---

## 17. Versioning

This doc is part of the spec. Updates to the doc require a
spec review (per AGENTS.md). Doc-state is tracked at the
bottom of each related doc.

Last updated: 2026-09-16
Sections: 17
Decisions referenced: D025-D033 (D029-D033 are new in this doc)
Open questions: 7

---

## 18. Design rationale and rejected alternatives

The doc above is the *what*. This section is the *why*  - 
the alternatives considered, the rejected options, and the
reasoning. Future agents reading the spec need this to
understand which choices were deliberate and which could
be revisited.

### 18.1 Substrate: single class, schema-as-data

**Considered:**
- Single GDScript class with generic payload
- Protocol/interface, multiple specialized classes
- Three classes (`SeedTree`, `StateTree`, `RulesTree`)

**Picked:** Single class, schema-as-data.

**Why:** Matches vant's `brain.js` pattern (one class,
mode-as-data). "We have been complex enough"  -  the user
flagged this explicitly. Users add their own complexity on
top via schemas; the substrate doesn't need to anticipate it.

**Revisit if:** the substrate becomes a bottleneck (e.g.,
schema dispatch is too slow). Then consider a JIT-style
specialization per schema.

### 18.2 Tree type count: 2 canonical + N

**Considered:**
- 4 fixed trees (seed, state, world, rules)
- 2 canonical (seed, state) + N others (added as needed)
- 1 generic "tree of trees" (no canonical instances)

**Picked:** 2 canonical + N.

**Why:** The "world tree" was a category error  -  world is a
*scope*, not a *tree type*. "World environment" is the
container; inside it are the world's seed tree, state tree,
rules tree, etc. The 4-tree frame was wrong; the 2+N frame
is correct.

**Revisit if:** a game on the frame needs a fixed tree
contract (e.g., a third canonical tree emerges from use).
Until then, N is open.

### 18.3 Stack direction: per-rule via the rules engine

**Considered (4 options):**
- **A. Top-wins (vant default).** Player at top, world at
  bottom, first match wins. Player can override anything.
- **B. World-wins-strict.** World at top, player at bottom.
  World is the first check; player can only do what world
  allows.
- **C. Two-stack, two-semantics.** Settings stack
  (player-wins) and rules stack (world-wins) per node.
- **D. World-rules are pre-checks (predicate layer).**
  Settings inherit normally, world is a predicate gate.

**Picked:** Per-rule resolution via the rules engine. The
A/B/C/D question dissolves when rules are data  -  each rule
in the rules tree declares its resolution strategy, and the
game developer picks the semantics that fit each rule.

**Why:** "World rules overpower the player if required" is
per-rule, not per-system. Some rules should be top-wins
(player's house can be anywhere they want); others should be
bottom-wins (no-PvP zones); others predicate-gated (boss
defeat must check the world predicate). One answer for all
rules was wrong.

**Revisit if:** the rules engine becomes a bottleneck or
the resolution-strategy API proves insufficient. Then
consider making resolution a callable on the schema.

### 18.4 World environment (not "world tree")

**Considered:** "world tree," "world runtime," "world scope,"
"context," "realm," "domain," "frame," "world environment."

**Picked:** "World environment" (or just "environment,"
"scope").

**Why:** "World tree" was a misnomer  -  the world has trees
inside it, the world is not itself a tree. "Runtime" is
overloaded with the project meaning. "Frame" is the project's
name. "Environment" is descriptive: it's the runtime
container at a given scope, holding N trees.

**Revisit if:** a clearer term emerges from use. The current
term is functional, not beautiful.

### 18.5 Data dir: `data/roots/`

**Considered:** `data/trees/`, `data/sources/`, `data/stores/`,
`data/registries/`, `data/scopes/`, `data/worlds/`,
`data/contexts/`, `data/frames/`, `data/models/`.

**Picked:** `data/roots/`.

**Why:** Each tree's data file is its **root hash**  -  the
top-of-tree content-hash. The data file is the canonical
reference to the whole tree. "Trees" was the obvious name
but it conflates the concept (a tree is a data structure)
with the storage (a tree is a .tres file). "Roots"
disambiguates: the data is the root, the structure is the
tree.

**Revisit if:** vant's `models/` layout proves cleaner (each
tree is a directory, not a single file). That's a v2
discussion.

### 18.6 Vant adoption: heavy

**Considered:**
- **Light:** just chunk path encoding + AOI neighborhoods.
- **Medium:** above + shard fragmentation + Penrose tiling.
- **Heavy:** above + full multibrain + full quasicrystal.

**Picked:** Heavy. Follow vant schemas and positions; if we
have opinions, push them up to vant.

**Why:** Vant is a sibling repo by the same author. The
user wants full integration: "It's our project too." The
static port lives in `game/core/frame/`; the runtime bridge
is the existing `connectors/vant/vant_connector.gd` stub.
We push our improvements back to vant; vant reciprocates.

**Revisit if:** vant's API churns in a direction that
doesn't fit. Then we can fork or abstract.

### 18.7 Rules engine: Phase 2

**Considered:** Phase 1 (with everything), Phase 2 (after
the canonical trees).

**Picked:** Phase 2.

**Why:** Phase 1 should be minimal  -  T3 substrate + scope
engine + the two canonical trees. The rules engine is a
consolidation of the existing 5 infrastructure services'
decision logic; it doesn't have to exist before the
canonical trees are built. Shipping Phase 1 first gives us
a substrate to test the rules engine against.

**Revisit if:** the 5 services become a maintenance
nightmare before Phase 2 starts. Then pull rules-engine
work forward.

### 18.8 Per-scope-type TTL

**Considered:**
- No TTL (keep everything forever)
- Uniform 5 min on all environments
- Per-scope-type TTL (5 min for open+instance, none for
  locked, frame-end for frame)

**Picked:** Per-scope-type.

**Why:** Matches the seed-type x visibility-scope taxonomy
from spec sec. 4. Locked environments (world map, shard terrain,
player's house) are durable  -  no TTL. Open environments
(dungeon run, arena match) are ephemeral  -  5 min after the
last player leaves. Frame environments (dream, tutorial,
jail cell) are one-shot  -  GC'd at frame end. One size
doesn't fit.

**Revisit if:** frame environments prove useful across
sessions (e.g., persistent dreams). Then add a
"frame_persistence" config.

### 18.9 The "flip" semantic

**Considered:**
- A single global rules resolution
- A per-rule resolution strategy
- A per-scope override of a per-rule resolution

**Picked:** Per-scope override of a per-rule resolution.

**Why:** "Games can flip anything anywhere" requires
three-level control: the rule defines its default
resolution, the scope can flip that resolution, and the
instance can override the scope's flip. A PvP zone is a
scope; the no-PvP rule is a rule; the flip is the scope
saying "in this zone, the no-PvP rule is bottom-wins
instead of top-wins." Three levels.

**Revisit if:** three levels proves too complex. Then
collapse to two (rule-level + scope-level, no instance-
level override).

### 18.10 The 5 new decision IDs (D029-D033)

**Considered:** Keep the validation gaps in the validation
list, fold them into the spec as decisions, defer them to
later.

**Picked:** Fold into the spec as new decisions.

**Why:** Each gap is a load-bearing interface contract
(login flow, frame authority, manifest backup, open seed
TTL, param criticality). They need decision IDs so the
implementation phase has a target. Without IDs, they remain
"open questions" forever.

**Revisit if:** a decision turns out to be wrong in
implementation. Then update the D### entry in
`world-building-risks.md` sec. 2.

### 18.11 Manifest backup: multi-tier

**Considered:**
- No backup (rely on Postgres replication only)
- Single daily snapshot
- Multi-tier (Postgres + S3 + cold storage)

**Picked:** Multi-tier.

**Why:** The recursive seed-state model means *every*
locked seed derives from `world_seed` in the manifest. Lose
the manifest = lose the world map, every shard's terrain,
every player's house. This is the single biggest SPOF in
the architecture. Multi-tier is the minimum acceptable
insurance.

**Revisit if:** the S3 tier proves unreliable or too
expensive. Then add a fourth tier (e.g., IPFS pin) or
collapse to two tiers (Postgres + local snapshot).

### 18.12 The split: frame in `labs/`, game in `game/`

**Considered:**
- All in `game/` (single Godot project)
- All in `labs/` (frame-first)
- Frame in `labs/`, game in `game/` (split)

**Picked:** Frame in `game/core/frame/`, game in `game/`.

**Why:** The frame can extract to its own repo (per
AGENTS.md). The labs convention is the explicit statement
of that. Putting T3 + scope + rules in `game/core/frame/`
makes the extraction path obvious. Putting the schemas +
data + services in `game/` keeps the game-specific code in
the Godot project.

**Revisit if:** the frame and game need to share code that
isn't a schema. Then either (a) move the shared code to
`game/core/frame/` and import it from the game, or (b)
introduce a `shared/` directory at the repo root.

---

## 19. The conversation behind this doc

This doc was produced in a brainstorm session on
2026-09-05. The conversation went through several
reframes before settling on the architecture above:

1. **Started from the validation list** (5 Tier-1 issues
   from the previous session's QC of the seed-state
   recursion spec). The first attempt at the new doc
   was a "bridge" between the spec and the code.

2. **The 4-tree reframe.** The user proposed "seed, state,
   world, and rules" trees as a fixed set. The doc briefly
   had a 4-tree table. The user caught the error: "world
   tree" was a poorly chosen word. World is a scope, not a
   tree. "World environment" is the container; inside it
   are the world's seed tree, state tree, rules tree, etc.
   The 4-tree frame became 2 canonical + N.

3. **The 4 stack-direction options (A/B/C/D).** A long
   discussion about how to resolve conflicts between
   world, shard, and player overrides. Options A through D
   were considered. The user said: "this is a question we
   should decide with more discussion. It flips the whole
   realms." The reframing: the A/B/C/D question dissolves
   when rules are data. The rules engine handles the
   choice per rule.

4. **The "rules engine mitigator."** The user identified
   that the existing 5 infrastructure services (QoS,
   Security, SecurityMonitor, AppFirewall, AutoResponse)
   each have their own decision logic. The rules engine
   consolidates them. This is the new piece.

5. **The vant connection.** The user pointed to vant's
   `lib/geometry/` and `lib/brain.js` as relevant prior
   art. Multibrain stack  ->  scope engine. Icosahedral /
   Penrose / fragmenter  ->  spatial layer + shard
   partitioning. Single class, schema-as-data  ->  T3
   substrate. Heavy adoption was picked.

6. **The dual goal.** The user clarified: "The goal of
   synmergia is to a) make a poc/mvp game, but also b)
   offer a clear abstraction between totally flexible/
   powerful frame and totally flexible/powerful schema and
   data potentials for others making their own games." The
   doc is the *frame*; the game is one instance.

7. **The data dir naming.** The user said "Trees might not
   be the best name, let's call them data/{something else}
   instead." Options considered: sources, stores,
   registries, scopes, roots. Picked: `data/roots/` (each
   tree's data file is its root hash).

8. **The push.** Final commit: `fc9e4e7` on main, with
   the arch doc + cross-refs in the existing trio.

This is a working document, not gospel. Future sessions
should feel free to revisit any of the 12 design decisions
in sec. 18 if implementation proves them wrong. The doc is the
*current* understanding; the code is the *eventual* truth.

---

## 20. Versioning (updated)

This doc is part of the spec. Updates to the doc require a
spec review (per AGENTS.md). Doc-state is tracked at the
bottom of each related doc.

Last updated: 2026-09-16
Sections: 20
Decisions referenced: D025-D033 (D029-D033 are new in this doc)
Open questions: 7
Design decisions recorded: 12 (in sec. 18)
