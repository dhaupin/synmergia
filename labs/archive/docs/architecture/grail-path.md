# The Grail Path — Pre-Materialized Orchestration

> **TL;DR:** Don't iterate. Don't compute. **Look up.** The
> state IS the answer. The math is the rebuild step, async,
> batched, off the read path.

**Author:** drafted 2026-08-30 after a late-night insight
session. The user named this "the grail path" because it's
the design where we stop spending CPU on cycles, calcs, and
checking, and instead spend CPU on keeping the state
*pre-known*.

---

## The principle

For any query, the **pre-state** is a partition of the world
that already contains the answer. Look it up. Return.

Math happens only at the **write boundary** (when the world
changes), to update the pre-state. The read path is free.

| Phase | What | Where | Cost |
|-------|------|-------|------|
| **Pre** | Materialized intersections, axis-partitioned | `composite_table.gd` + LRU | O(1) lookup |
| **Mid** | Event log, axis updates, transitions | `event_hub.gd` | O(1) emit |
| **Post** | Re-rooted tree, refreshed intersections | `state_tree.gd` on tick | O(changed) |

The pattern is **CQRS** (Command Query Responsibility
Segregation) over multi-iso axes. Reads are projections over
materialized state. Writes are commands that re-derive the
projections.

---

## Math path vs grail path (side by side)

### Example 1: "Who can I attack here?"

**Math path (10K entities, per player, per frame):**
```gdscript
var result = []
for e in EntityService.get_all():
    if in_range(self, e) and is_hostile(self.guild, e.guild):
        result.append(e)
return result
```
**Cost:** O(N) per query. N² across all players.

**Grail path (O(1) on materialized):**
```gdscript
# Pre-state has the answer.
var allies := orchestrator.query({"party": player.party_id})
var hostiles := orchestrator.query({
    "zone": player.zone,
    "guild": faction_manager.hostile_to(player.guild),
})
return list_xor([allies], [hostiles])
```
**Cost:** O(1) on axis-partitioned tables. Linear in result size.

### Example 2: "Loot in this chest"

**Math path:**
```gdscript
var chest := chest_repo.get(chest_id)
return chest.loot_table.roll(rng)
```
**Cost:** IO + RNG. The math runs every open.

**Grail path:**
```gdscript
# The chest's loot is a snapshot in pre-state.
# If the chest is unopened since last update, the answer is
# "same as last time" — a pointer, not a computation.
return state.get("chests:" + chest_id + ":loot")
```
**Cost:** O(1) hash lookup. Zero math.

### Example 3: "Where will the player be in 5 seconds?"

**Math path:**
```gdscript
# Sample N possible futures, average them.
var futures := []
for i in 64:
    futures.append(player.predict(t + 5.0, rng.fork(i)))
return futures.average()
```
**Cost:** N physics steps. Per player. Per frame. Per UI.

**Grail path:**
```gdscript
# The Markov predictor's output is materialized on the
# server tick. The client just reads.
return state.get("predict:" + player_id + ":at:" + tick + 5)
```
**Cost:** O(1) lookup. The math ran once, async, on the server.

---

## The pre-mid-post API

The orchestrator should expose this contract:

```gdscript
# labs/multi-iso/srv/orchestrator.gd
class_name Orchestrator
extends RefCounted

# READ — pre-state lookup. O(1) on materialized.
# Async, non-blocking, returns immediately.
func query(axes: Dictionary) -> Array:
    return _composite_tables.intersect(axes)

# WRITE — mid-state event. O(1) emit.
# Returns an event handle; side effects run async.
func emit(event: String, payload: Dictionary) -> EventHandle:
    return _event_bus.publish(event, payload)

# TICK — post-state derivation. The only place math runs.
# Called by the server at tick boundary (e.g., 30 Hz).
# Batched, async, off the read path.
func tick() -> void:
    var changed_axes := _event_bus.drain_pending()
    for axis in changed_axes:
        _rebuild_axis(axis)            # math here, once
    _composite_tables.refresh()       # update pre-state
    _state_tree.re_root()             # new post-state
```

**Three methods. Reads are free. Writes are events. Math is a tick.**

---

## The 5 changes to commit

The multi-iso design already has the components. The grail is
the **commitment**. Five small changes make it real.

### 1. The orchestrator exposes a `tick()` method

Currently the orchestrator is reactive (events trigger
updates). The grail adds a periodic tick that batches all
pending changes and refreshes the pre-state once per tick.
This is what makes the math async and off the read path.

### 2. Composite tables are the canonical read source

Every query MUST go through `orchestrator.query()`. Direct
iteration over `EntityService.get_all()` is forbidden inside
the read path. Lint rule. Code review rule.

### 3. The state tree is re-rooted on tick, not on demand

The state tree re-roots when the world changes. The grail
moves this to the tick boundary. Reads return the most recent
re-rooted tree, not a partial state.

### 4. Math is a pure function of pre-state → post-state

Every "math" operation in the frame is a pure function:
```
post_state = f(pre_state, event_batch)
```
No side effects. No IO. No globals. This makes it testable,
parallelizable, and cacheable.

### 5. The pre/mid/post types are explicit

A `PreState` struct, a `MidEvent` struct, a `PostState`
struct. The orchestrator hands them around. The read path
sees only `PreState`. The tick path sees only `PreState` +
`MidEvent` → `PostState`. No mixing.

```gdscript
class PreState:
    var composite_tables: Dictionary
    var content_hashes: Dictionary

class MidEvent:
    var event: String
    var axis: int
    var payload: Dictionary
    var tick: int

class PostState:
    var pre_state: PreState
    var new_composite_tables: Dictionary
    var new_content_hashes: Dictionary
    var diff: Array  # what changed
```

The compile-time type boundary makes it impossible to mix
read and write paths by accident.

---

## What "the math" actually means

When the grail is committed, "the math" is:
- Intersection table rebuild (when entities move between axes)
- Content hash recompute (when the tree changes)
- LOD promotion/demotion (when a region crosses a threshold)
- Markov predict + materialize (the future states)
- Composite table intersection refresh (the pre-state itself)

All of these run **on tick**, **batched**, **async**,
**parallelizable** (and the polyglot FFI lets us ship the
heavy ones to Julia or C++).

The math budget per tick is finite. The tick rate is 30 Hz by
default. The math budget is ~33ms of CPU per server tick. If
the math fits, the reads are infinite.

---

## Why this is the grail for our stack

| Without the grail | With the grail |
|-------------------|----------------|
| Every query re-iterates | Every query is O(1) |
| Math budget per query | Math budget per tick, batched |
| Frame scales with N² | Frame scales with N |
| Cache is a speedup | Cache IS the answer |
| 10K entities = lag | 10K entities = one tick |
| Frame budget on read | Frame budget on write |
| Reads slow down the world | World re-derives in background |

**The user said:** "reduce cpu/cycles, while preserving math,
and pre-mid-post state, as orchestration, prior to redis,
Db, etc."

That's the grail. The math is preserved (it's in the tick).
The CPU is reduced (reads are free). The state is pre/mid/post
typed. The orchestration is the gate, prior to any caching or
persistence.

---

## What this doc is NOT

- A replacement for the multi-iso docs. It's a *lens* on them.
- A performance optimization. It's a structural commitment.
- A complete implementation. It's the contract; the rest is code.
- A short-term change. The 5 commitments are 1-2 sessions of work.

The multi-iso orchestrator, the state tree, the LRU cache, the
composite tables — all of these *already exist in the design*.
The grail is the *order*:

1. Read pre-state first. Always.
2. Write to mid-state only. Never mutate the pre-state.
3. Math is a tick operation. Never on the read path.
4. Post-state is what enables the next pre-state.

That's it. One contract. Five changes. The grail.

---

## See also

- [`multi-iso-frame.md`](./multi-iso-frame.md) — Part 1: the
  orchestrator primitives. The grail sits on top of these.
- [`multi-iso-lod-prediction.md`](./multi-iso-lod-prediction.md) —
  Part 2: LOD + materialized + prediction. The composite
  tables and the Markov predictor are the grail's building
  blocks.
- [`labs/prd.md §10.10`](../../../prd.md#1010-three-tiers-of-computation-the-frame-runtime) —
  the three computation tiers. Tier 1 (GDScript) handles the
  pre/mid/post glue. Tier 2 (Julia) handles the math on tick.
  Tier 3 (C++/GDExtension) handles the absolute hot path
  within the tick.
- [`labs/polyglot-ffi/`](../../../polyglot-ffi/) — the math
  that the tick dispatches to.

## Status

- [x] Principle
- [x] Pre-mid-post API sketch
- [x] 5 changes to commit
- [ ] `Orchestrator.tick()` implementation (B-4)
- [ ] `PreState` / `MidEvent` / `PostState` types (B-4)
- [ ] Lint rule: no direct iteration in read path
- [ ] Tick-rate benchmark (B-9 perf budget)
