# PRD: Scope Engine (Data-Driven Hierarchy)

> **For:** sub-agent implementation
> **Phase:** 1 (per `world-building-arch.md` §14)
> **Depends on:** `prd-t3-substrate.md` (for `walk` semantics), `prd-seed-schema.md` (for hierarchy node identity)
> **Unblocks:** rules engine, login flow (D029), frame authority (D030), open seed TTL (D032)

## 1. Introduction/Overview

The scope engine walks a hierarchy of scopes, manages the
active per-connection stack, and supports per-scope rule
overrides ("flips"). The hierarchy is **data-driven** —
defined in a `ScopeHierarchy.tres` resource, not hardcoded
in the class. This means other games on the frame can
define their own hierarchies (galaxy → sector → system →
planet → character, etc.) without changing the scope
engine code.

**Why this exists:** Per arch doc §4, the scope engine is
the frame's hierarchy walker. It's the substrate for
"world rules overpower the player if required" (§5.3) and
the "flip anything anywhere" machinery (§4.4). Hardcoding
the hierarchy would make the frame Synmergia-specific;
data-driven makes it reusable.

**Spec ref:**
[`world-building-arch.md`](./world-building-arch.md) §4
(The scope engine)

## 2. Goals

- ONE hierarchy Resource (`ScopeHierarchy.tres`) loaded at
  server startup
- ONE `Scope` class (in-memory representation of a node in
  the hierarchy)
- ONE `ScopeEngine` class (the walker, stack manager,
  flip handler)
- Per-connection stack (not global)
- "Flip" semantic: a scope can override a rule's resolution
  strategy
- Hierarchy validation at load time (no cycles, all
  parents exist, single root)
- Tests cover: default Synmergia hierarchy, custom
  hierarchies, deep hierarchies, walk order, push/pop
  correctness, flip application, invalid hierarchy rejection

## 3. User Stories

### US-001: ScopeHierarchy resource

**Description:** As a developer, I need a `ScopeHierarchy`
resource that defines the scope tree for a game, loaded
from a `.tres` file, so different games can have
different hierarchies.

**Acceptance Criteria:**
- [ ] `ScopeHierarchy` class exists in
  `labs/multi-iso/srv/scope_hierarchy.gd`, extends `Resource`
- [ ] `@export var nodes: Array[ScopeNode]` where each
  `ScopeNode` has: `name: String`, `parent_name: String`
  (empty for root), `environment_path: String` (path to
  the scope's environment `.tres`), `rules_overrides:
  Dictionary` (rule_id -> resolution_strategy)
- [ ] The resource can be saved to `.tres` and loaded
- [ ] At load time, the engine validates: single root,
  no cycles, all parents exist, all environment paths
  resolve
- [ ] Invalid hierarchy → server fails to start with a
  clear error message naming the bad node

### US-002: Default Synmergia hierarchy

**Description:** As a developer, I need a default
`scope_hierarchy.tres` for Synmergia defining
`world → shard → instance → player`, so the game works
out of the box.

**Acceptance Criteria:**
- [ ] One `.tres` at
  `game/data/roots/world/scope_hierarchy.tres`
- [ ] Defines 4 node types: `world` (root), `shard`,
  `instance`, `player`
- [ ] `shard` parent is `world`; `instance` parent is
  `shard`; `player` parent is `instance`
- [ ] Each node's `environment_path` points to a stub
  `.tres` in `game/data/roots/<scope>/environment.tres`
- [ ] File loads without errors in the Godot editor
- [ ] Loads at server startup without errors

### US-003: Scope class (in-memory node)

**Description:** As a developer, I need an in-memory
`Scope` class representing one node in the hierarchy, so
the engine can walk and manipulate the scope tree.

**Acceptance Criteria:**
- [ ] `Scope` class exists in
  `labs/multi-iso/srv/scope.gd`, extends `RefCounted`
- [ ] Fields: `name: String`, `parent: Scope` (null for
  root), `children: Array[Scope]`,
  `rules_overrides: Dictionary`, `environment_path: String`
- [ ] Method: `walk(callback: Callable) -> void` invokes
  `callback(self)` for self + all descendants, depth-first
  pre-order
- [ ] Method: `find(name: String) -> Scope` returns the
  descendant with that name, or null
- [ ] Method: `flip(rule_id: String, resolution: String)
  -> void` sets a rule override
- [ ] No autoload, no class_name (per AGENTS.md: frame
  primitives are liftable)

### US-004: ScopeEngine class (walker + stack)

**Description:** As a developer, I need a `ScopeEngine`
class that loads a `ScopeHierarchy`, builds the in-memory
scope tree, and manages per-connection stacks.

**Acceptance Criteria:**
- [ ] `ScopeEngine` class exists in
  `labs/multi-iso/srv/scope_engine.gd`, extends `RefCounted`
- [ ] `func load_hierarchy(path: String) -> bool` loads
  and validates a `.tres`, returns false on invalid
- [ ] `func get_root() -> Scope` returns the root scope
- [ ] `func get_scope(name: String) -> Scope` returns the
  scope with that name
- [ ] Per-connection stack: `func push(player_id: String,
  scope_name: String) -> bool` adds to a per-player stack
- [ ] `func pop(player_id: String) -> bool` removes from
  the per-player stack
- [ ] `func get_stack(player_id: String) -> Array[Scope]`
  returns the player's active stack
- [ ] `func resolve_rule(player_id: String, rule_id:
  String, default_resolution: String) -> String` walks
  the stack bottom→top, returns the first non-empty
  override, or the default
- [ ] No autoload, no class_name

### US-005: Push/pop per connection

**Description:** As a developer, I need per-connection
stacks so two players in different contexts don't share
stack state.

**Acceptance Criteria:**
- [ ] Stacks are keyed by `player_id` (a String)
- [ ] `push` returns false if the scope name doesn't
  exist in the hierarchy
- [ ] `pop` returns false if the stack is empty
- [ ] `get_stack` returns an empty array for an unknown
  player_id (not an error)
- [ ] Stacks are stored in a `Dictionary` inside the
  engine, not a global variable

### US-006: Flip semantic (per-scope rule override)

**Description:** As a developer, I need a scope to flip
a rule's resolution strategy, so a "PvP zone" can flip
"can_pvp" to bottom-wins, overriding the player's
top-wins preference.

**Acceptance Criteria:**
- [ ] `Scope.flip(rule_id, resolution)` sets
  `rules_overrides[rule_id] = resolution`
- [ ] `ScopeEngine.resolve_rule` walks the stack from
  root to the player's current scope, returning the first
  override found
- [ ] If no override found, returns the
  `default_resolution` parameter
- [ ] Resolution strings are constants: `"TOP_WINS"`,
  `"BOTTOM_WINS"`, `"PREDICATE_GATED"`,
  `"ALL_WINS_WITH_EFFECT"` (matches the rules engine
  per arch doc §5.1)
- [ ] Tests: PvP zone flips `can_pvp` to BOTTOM_WINS,
  player in the zone → world rule wins; player outside
  the zone → player's setting wins

### US-007: Hierarchy validation at load

**Description:** As a developer, I need the engine to
reject invalid hierarchies at load time, so we don't
discover the bug at runtime.

**Acceptance Criteria:**
- [ ] Single root: exactly one node with empty
  `parent_name`
- [ ] No cycles: walking from any node via `parent` must
  terminate at root
- [ ] All parents exist: every `parent_name` references
  a node in the same `.tres`
- [ ] All environment paths resolve: each `environment_path`
  must point to a file that exists (relative to the
  `scope_hierarchy.tres` location)
- [ ] On any failure, `load_hierarchy` returns false and
  the server logs the specific validation error
- [ ] Tests: cycle, missing parent, multiple roots, bad
  environment path → all rejected

## 4. Functional Requirements

- **FR-1:** Three GDScript classes: `ScopeHierarchy`
  (Resource), `Scope` (RefCounted), `ScopeEngine`
  (RefCounted)
- **FR-2:** Files: `labs/multi-iso/srv/scope_hierarchy.gd`,
  `scope.gd`, `scope_engine.gd`
- **FR-3:** One default `.tres` at
  `game/data/roots/world/scope_hierarchy.tres`
- **FR-4:** Hierarchy is loaded once at server startup;
  the in-memory tree is built once
- **FR-5:** Per-connection stacks, keyed by `player_id`
- **FR-6:** Flip semantic: per-scope rule override, stack
  walk root→current, first non-empty wins
- **FR-7:** Hierarchy validation at load time
- **FR-8:** NO autoload, NO class_name on any of the three
  classes (per AGENTS.md: frame primitives are liftable)
- **FR-9:** NO dependency on autoloads or game services

## 5. Non-Goals (Out of Scope)

- NO hardcoded hierarchy (the hierarchy is data)
- NO multi-hierarchy support (one hierarchy per process;
  multi-hierarchy is a v2 concern)
- NO runtime hierarchy editing (the `.tres` is loaded at
  startup; runtime edits are a v2 concern)
- NO network sync of hierarchy changes (the `.tres` is
  server-source-of-truth; clients receive their stack as
  part of login)
- NO icosahedral address binding (out of scope; that's
  the spatial layer, Phase 4 per arch doc §11.4)

## 6. Design Considerations

- **Why data-driven:** Other games on the frame have
  different hierarchies. Hardcoding Synmergia's
  `world → shard → instance → player` would make the
  frame Synmergia-specific. Data-driven makes the frame
  reusable.
- **Default hierarchy:** A `scope_hierarchy.tres` ships
  with Synmergia at
  `game/data/roots/world/scope_hierarchy.tres`, defining
  `world → shard → instance → player`. Other games ship
  their own.
- **Hierarchy validation:** the engine validates the
  hierarchy at load time (no cycles, all parents exist,
  single root). Invalid `.tres` → server fails to start.
- **Scope naming:** scope names are strings (e.g.,
  `"world"`, `"shard_1"`). They form the path in the
  active stack.
- **Resolution strategies:** the four strategies
  (TOP_WINS, BOTTOM_WINS, PREDICATE_GATED,
  ALL_WINS_WITH_EFFECT) are constants shared with the
  rules engine. The scope engine doesn't define them
  itself; it consumes them.
- **Per-connection stack storage:** in-memory `Dictionary`
  on the engine. Persistence is the world's concern.

## 7. Technical Considerations

- **Godot 4.7.2** required (uses `Array[Resource]`,
  `Dictionary`, `Resource`, `RefCounted`).
- **Tests:** co-located in
  `labs/multi-iso/srv/test_scope_engine.gd`.
- **No external dependencies** beyond Godot stdlib.
- **Performance budget:** `resolve_rule` should complete
  in < 1µs (stack walk of 4 scopes). `load_hierarchy`
  should complete in < 100ms (validate + build tree).
- **Vant lineage:** vant's `brain.js:1510-1900` (multibrain
  stack) is the prototype. The scope engine is a port +
  extension (adds override/flip semantics, data-driven
  hierarchy). File header: `## Ported from vant axolotl
  lib/brain.js`.

## 8. Success Metrics

- All 7 user stories have passing tests (≥ 30 assertions)
- Default Synmergia hierarchy `.tres` loads cleanly
- Custom 5-level hierarchy (e.g., galaxy → sector →
  system → planet → character) loads cleanly
- PvP zone flip test passes: BOTTOM_WINS in zone, TOP_WINS
  outside
- One commit, pushed to main
- `labs/world-building-arch.md` §13 component map status
  updated: scope engine from `TODO` to `DONE`

## 9. Open Questions

1. **Scope identity:** is `player_id` the right key for
   the per-connection stack, or should it be the WebSocket
   peer ID? My read: `player_id` (character-scoped), the
   network layer maps peer_id ↔ player_id.
2. **Stack persistence:** should the stack survive a
   player logout? My read: no — logout clears the stack
   (or it's GC'd by the 5-min open seed TTL per D032).
3. **Multiple roots:** is "single root" the right
   constraint, or should the engine support multiple
   disconnected hierarchies? My read: single root for v1
   (simpler); multi-root is a v2 concern.

## 10. Definition of Done

- [ ] All 3 classes implemented and pushed to main
- [ ] Default `scope_hierarchy.tres` ships with Synmergia
- [ ] Tests co-located, all green
- [ ] No new dependencies on autoloads or game services
- [ ] File headers include vant lineage credit
- [ ] `labs/world-building-arch.md` §13 component map
  status updated
- [ ] Single commit, conventional message format
- [ ] Smoke test: load default hierarchy, push 4 scopes,
  resolve rule with a flip, verify result
