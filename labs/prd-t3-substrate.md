# PRD: T3 Substrate (Generic Content-Hash Tree)

> **For:** sub-agent implementation
> **Phase:** 1 (per `world-building-arch.md` §14)
> **Depends on:** nothing
> **Unblocks:** SeedSchema, StateSchema, scope engine, rules engine

## 1. Introduction/Overview

T3 is the substrate every tree in Synmergia is built on. It
is a single GDScript class that implements the content-hash
tree primitive: insert, get, delete, hash_subtree, diff,
apply_diff, walk. T3 is the untyped substrate; schemas are
the typed payload. This matches the architecture in
[`world-building-arch.md`](./world-building-arch.md) §3 and
the vant `brain.js` single-class-with-mode-as-data pattern.

**Why this exists:** The frame and the game both need a
substrate for content-hash trees. Without it, the seed chain
(D025), state diff (D027), and rules engine (§5) have
nothing to build on.

## 2. Goals

- ONE GDScript class, generic payload (no per-tree types)
- 7 public methods: `insert`, `get`, `delete`, `hash_subtree`,
  `diff`, `apply_diff`, `walk`
- SHA-256 content hashing via `HashingContext`
- Path-based addressing (slash-separated)
- Schema is a `Resource` passed to `insert`; T3 stores the
  reference but doesn't interpret it
- Determinism: same path + value + schema = same hash
- Tests cover happy path + edge cases (empty tree, deep
  paths, deleted nodes, diff roundtrip)

## 3. User Stories

### US-001: T3 class with insert / get

**Description:** As a developer, I need to insert and
retrieve nodes from a T3 tree so I can build higher-level
trees on top.

**Acceptance Criteria:**
- [ ] `T3` class exists in `game/core/frame/kv/t3.gd`
- [ ] `insert(path: String, value: Variant, schema: Resource) -> PackedByteArray` returns the new node's hash (32 bytes)
- [ ] `get(path: String) -> Variant` returns the value, or `null`
- [ ] Same path + value + schema inserted twice → same hash
- [ ] Different values → different hashes
- [ ] Path is normalized (leading slash optional, trailing slash stripped)

### US-002: T3 hash_subtree

**Description:** As a developer, I need to hash a subtree
so I can compute a partial tree's fingerprint.

**Acceptance Criteria:**
- [ ] `hash_subtree(path: String) -> PackedByteArray` returns SHA-256 of `(parent_hash, value_bytes, schema_id)` for the node at `path`
- [ ] Empty subtree (no node at `path`) returns SHA-256 of the empty string
- [ ] `hash_subtree("/")` returns the tree's root hash
- [ ] After `insert`, the parent chain's `hash_subtree` reflects the new value

### US-003: T3 diff

**Description:** As a developer, I need to diff two trees
so I can sync clients efficiently (D027, state-only diff).

**Acceptance Criteria:**
- [ ] `diff(old_root: PackedByteArray, new_root: PackedByteArray) -> Array` returns `[(path, old_hash, new_hash, value_bytes_if_changed)]`
- [ ] Same roots → empty array
- [ ] Different roots → finite array of changes only
- [ ] `value_bytes_if_changed` is `null` when `new_hash` equals what the client already has
- [ ] Diff is deterministic: same old + new → same diff

### US-004: T3 apply_diff

**Description:** As a developer, I need to apply a diff to
reconstruct a new tree from an old one.

**Acceptance Criteria:**
- [ ] `apply_diff(root: PackedByteArray, diff: Array) -> PackedByteArray` returns the new root
- [ ] Roundtrip: `apply_diff(root_a, diff(root_a, root_b)) == root_b`
- [ ] Empty diff → unchanged root
- [ ] Diff with 1000 entries completes in < 100ms on a 10K-node tree (perf budget)

### US-005: T3 walk

**Description:** As a developer, I need to walk a subtree
with a callback so I can iterate over nodes.

**Acceptance Criteria:**
- [ ] `walk(scope_path: String, callback: Callable) -> void` invokes `callback(path, hash, value)` for each node under `scope_path`
- [ ] Walk order is deterministic (depth-first, pre-order)
- [ ] Empty subtree → callback never invoked
- [ ] Callback exceptions do not crash the walk; logged instead

### US-006: T3 delete

**Description:** As a developer, I need to delete a node
so I can clean up.

**Acceptance Criteria:**
- [ ] `delete(path: String) -> bool` returns `true` if the node existed, `false` otherwise
- [ ] After `delete`, `get(path)` returns `null`
- [ ] After `delete`, the parent's `hash_subtree` changes (the deletion propagates up)

## 4. Functional Requirements

- **FR-1:** One GDScript class `T3` in `game/core/frame/kv/t3.gd`, extends `RefCounted`
- **FR-2:** Uses `HashingContext.sha256()` for content hashing
- **FR-3:** Node structure: `(path, hash, value_bytes, schema_ref)`
- **FR-4:** Path addressing is slash-separated; normalize on insert (strip leading/trailing slashes, collapse `//` to `/`)
- **FR-5:** Schema is a `Resource` (any Godot Resource)
- **FR-6:** Public methods only: `insert`, `get`, `delete`, `hash_subtree`, `diff`, `apply_diff`, `walk`
- **FR-7:** NO autoload, NO `class_name` (per AGENTS.md: frame primitives are liftable)
- **FR-8:** NO dependency on `GameManager`, `EventBus`, or any autoloaded service
- **FR-9:** All public methods have docstrings with the per-method contract

## 5. Non-Goals (Out of Scope)

- NO per-tree types (no `SeedTree`, `StateTree` classes — schemas differentiate)
- NO schema interpretation (T3 doesn't know what a schema does; it just stores the reference)
- NO persistence (T3 is in-memory; persistence is the world's concern)
- NO networking (T3 doesn't sync; the world does)
- NO concurrency (T3 is single-threaded; concurrency is the world's concern)
- NO transaction log (T3 doesn't have undo; the world snapshots if it needs to)
- NO TTL or GC (T3 doesn't expire nodes; the world does)
- NO scope engine integration (the `walk(scope_path, callback)` parameter is a string path, not a Scope class)

## 6. Design Considerations

- **Memory model:** T3 holds nodes in a flat `Dictionary` keyed by normalized path. No linked tree in memory; the path IS the structure. Simpler than a linked tree, faster for small-to-medium trees, may need restructuring for huge trees (10K+ nodes).
- **Hash function:** SHA-256 via `HashingContext`. Fast enough for typical use; if profiling shows it as a bottleneck, consider Blake3.
- **Determinism guarantee:** relies on the schema's `_to_canonical_bytes()` being deterministic. T3 doesn't enforce this; it's a contract.
- **Comparison with vant:** vant's `brain.js` is one class with mode-as-data. T3 is the same pattern. The frame ports vant's patterns, not its types.

## 7. Technical Considerations

- **Godot 4.7.2** required (uses `HashingContext.sha256()`, `PackedByteArray`, `RefCounted`).
- **Tests:** co-located in `game/core/frame/kv/test_t3.gd`. Run with `./tools/godot --headless --script res://test_t3.gd` after the project root is configured for `/labs/` (per `docs/architecture/labs-organization.md`).
- **No external dependencies** beyond Godot stdlib.
- **Performance budget:** `insert` / `get` / `hash_subtree` should complete in < 1ms for trees up to 1K nodes on a typical dev machine. Diff for 1K-node tree with 10 changes should complete in < 10ms.

## 8. Success Metrics

- All 7 public methods implemented
- All 6 user stories have passing tests (≥ 30 assertions total)
- One commit, pushed to main
- `labs/world-building-arch.md` §13 component map status updated: T3 substrate from `TODO` to `DONE`

## 9. Open Questions

1. **Memory model:** flat Dictionary vs linked tree. Flat is chosen for v1; revisit if profiling shows the wrong call.
2. **Hash function:** SHA-256 vs Blake3. SHA-256 is the conservative choice; Blake3 is faster but newer.
3. **Diff format:** per-tree or generic? Generic chosen for v1; per-tree custom diff is a future optimization.
4. **Path normalization:** case-sensitive, whitespace-sensitive, etc. Conservative: literal strings, normalize only slashes.

## 10. Definition of Done

- [ ] T3 class implemented and pushed to main
- [ ] Tests co-located, all green
- [ ] No new dependencies on autoloads or game services
- [ ] File header includes "## Ported from vant axolotl lib/cache.js" credit (if applicable — `cache.js` is the closest vant analog; confirm during implementation)
- [ ] `labs/world-building-arch.md` §13 component map status updated
- [ ] Single commit, conventional message format
- [ ] Smoke test passes: a 3-node tree, insert, get, hash, diff, apply_diff, walk

---

## 11. Decisions applied (2026-09-05)

Answers from the planning session that affect this PRD:

- **Schema evolution (option a — auto-upgrade on load):**
  T3 doesn't need to know about schema versions; the
  schema's `_init()` (or a Godot lifecycle hook) handles
  version transitions. T3 just stores and hashes. The
  schema upgrade is the schema's concern.

- **Memory model:** flat `Dictionary` keyed by path. The
  arch doc §18.1 says "revisit if profiling shows the
  wrong call." v1 ships flat; v2 may switch to a linked
  tree.

- **Hash function:** SHA-256 (arch doc §18.1 revisit
  trigger = profiling). v1 is SHA-256; v2 may be Blake3.

- **Vant lineage:** confirm `cache.js` is the right
  vant analog during implementation. If not, drop the
  credit; if yes, include it.
