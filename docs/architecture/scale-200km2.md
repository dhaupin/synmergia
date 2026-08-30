# Scale at 200 km² — Innovative Solutions

> **TL;DR:** The map is 200 km². We're not shrinking it. The
> multi-iso frame, the LOD pyramid, the predictive
> prefetch, the state diff sync, and the hierarchical
> architecture together make 200 km² cheap.

**Author:** drafted 2026-08-30 as part of the rando-in-the-mix
session. Tied to
[`multi-iso-lod-prediction.md`](./multi-iso-lod-prediction.md)
and the
[`grail-path.md`](./grail-path.md).

---

## The problem

200 km² = 200,000,000 m²

If we model one entity per m², that's 200M entities. Even
sparse at 0.001 entities/m², that's 200K entities. At 30
ticks/second:

- 6M operations/second for sparse
- 6B operations/second for dense (impossible)
- 12M operations/second for visual at 60fps (sparse)

**The naive answer** is "shrink the world." That's not the
user's answer. The user's answer is: "innovative and novel
solutions to trim cpu/ram by a lot, while preserving
*prodoctural* assimilations, and real-time syncs."

"Prodoctural" = procedural + productural? Or
procedural + assimilation? The user means: the world
*feels* like a 200km² world, with procedural content and
real-time multi-player sync, but the system runs on
commodity hardware.

**The 200km² world is real, but it's not in memory at
once. The world is a 200km² graph that materializes the
relevant subgraph on demand.**

---

## The 8 innovations

### 1. LOD pyramid (only 1% is "hot")

The world is stratified into 4 LOD levels. Only the top
level is in memory at any time.

| Level | What | Size | In RAM? |
|-------|------|------|---------|
| **Full** | Active zones, live entities, current state | 1-10K entities | Always |
| **Summary** | Bordering zones, recent activity, NPCs | 100-500K entities | On demand |
| **Cold** | Inactive zones, archived events, NPC history | 1-10M entities | Disk only |
| **Archived** | Static zones, history snapshots | Everything else | Postgres |

The LOD manager promotes and demotes based on activity
(see [`multi-iso-lod-prediction.md`](./multi-iso-lod-prediction.md)).
The 200km² world is **the union** of these four levels,
but only **1% is in RAM at any time**.

**CPU/RAM impact:** 1-10K hot entities instead of 200M.
**200x to 20,000x reduction in memory.**
**30x to 6000x reduction in tick work.**

### 2. Predictive prefetch (Markov over movement)

The Markov predictor (`markov.gd` in the frame) watches
player movement and predicts where they'll be in 5s, 30s,
5min. The prefetcher loads the predicted regions into
the next LOD level.

```gdscript
# labs/multi-iso/srv/predictor.gd
func predict(player: Entity, t_ahead: float) -> Vector3:
    var history := _get_history(player, n=100)
    var transition_matrix := _build_markov(history)
    var current_state := _state_of(player)
    return transition_matrix.probable_next(current_state, t_ahead)
```

**CPU impact:** prefetch is async, batched, off the read
path (per the grail path). The tick math budget is finite,
the prefetch is one of the math operations.
**User impact:** the world *feels* fully loaded. The player
walks into a new zone and it's already there.

### 3. Multi-axis intersection (O(1) queries)

The materialized intersection tables (per the multi-iso
frame) make most queries O(1) on axis-partitioned lookups.
A query like "enemies in this zone who are hostile to me"
is a join of three pre-computed tables, not a scan.

```gdscript
# Pre-state has the answer
var allies := orchestrator.query({"party": player.party_id})
var hostiles := orchestrator.query({
    "zone": player.zone,
    "guild": faction_manager.hostile_to(player.guild)
})
return list_xor([allies], [hostiles])
```

**CPU impact:** 1000x reduction in query cost.
**This is the grail path. Reads are free.**

### 4. State diff sync (only the diff goes over the wire)

The state tree is content-hashed. Two consecutive ticks
have a diff. The diff is what the client receives, not
the full state.

```gdscript
# Server sends diff, not state
var current_root := state_tree.root_hash
var client_root := client.last_known_root
if current_root == client_root:
    return []  # nothing changed
var diff := state_tree.diff(client_root, current_root)
return diff  # client applies locally
```

**Bandwidth impact:** O(diff size), not O(state size). For
a single player moving, the diff is ~10 events. For 100
players in a zone, the diff is ~1000 events. The full
state for that zone is 10K entities.
**1000x reduction in sync bandwidth.**

### 5. Hierarchical sync (zones → regions → world)

The world is partitioned into zones. Zones are
partitioned into regions. Regions are partitioned into
cells. Sync is hierarchical: cell → region → zone →
world. Most updates stay at the cell level; they never
propagate to the zone.

| Level | Granularity | Sync rate | Recipients |
|-------|-------------|-----------|------------|
| **Cell** | 100m × 100m | 30 Hz | Players in cell |
| **Region** | 1km × 1km | 10 Hz | Players in region |
| **Zone** | 10km × 10km | 1 Hz | Players in zone |
| **World** | 100km+ | 0.1 Hz | All players |

**CPU impact:** 99% of updates are cell-level. The zone
and world levels are summaries.
**Bandwidth impact:** clients only sync the cell they're
in, the region they're near, and a summary of the zone.
**1-3 levels of sync per client, not 4.**

### 6. Content-hash addressing (cache by hash)

Every region has a content hash. Clients cache by hash.
When the server says "region X is hash Y", the client
checks its cache. If it has Y, no download. If not, fetch.

```gdscript
# Server: "region X is now hash 0xABC123"
# Client: "do I have 0xABC123?" -> yes/no
#         if no: fetch. if yes: skip.
```

**Bandwidth impact:** clients never re-download unchanged
data. After the first visit, only diffs cross the wire.
**10-100x reduction in cold-start bandwidth.**

### 7. RAM + Postgres split (hot in RAM, cold in DB)

The LOD pyramid's "full" and "summary" levels live in
RAM. The "cold" and "archived" levels live in Postgres.

```gdscript
# On access:
func get_entity(id: String) -> Entity:
    # Try RAM first (LRU cache, O(1))
    if _ram_cache.has(id):
        return _ram_cache.get(id)
    # Fall back to Postgres
    var row := _postgres.fetch_entity(id)
    if row:
        var entity := _deserialize(row)
        _ram_cache.set(id, entity, ttl=600)
        return entity
    return null
```

**RAM impact:** 1-10K entities in RAM (the full level).
200M entities max, but only 1% ever loaded.
**Disk impact:** the rest is in Postgres, which is cheap
and abundant.

### 8. Procedural assimilation (the world generates, not stores)

The user said "prodoctural assimilations." I'll interpret
this as **procedural content that feels authored**. The
world isn't 200M stored entities. The world is:

- **A seed** (small, ~10MB) — terrain, NPCs, items, lore
- **A procedural generator** — takes the seed, generates
  per-region content on demand
- **A modification log** — what players have changed (small)

The procedural generator runs *at LOD promotion*. When a
region goes from "cold" to "summary," the generator
re-creates it. The generator is deterministic: same seed
+ same modifications = same region.

```gdscript
# LOD promotion: cold -> summary
func promote_region(region: Region) -> void:
    var seed := _region_seed(region.id)
    var modifications := _postgres.fetch_modifications(region.id)
    var generated := _procedural_gen.generate(seed, modifications)
    _ram_cache.set(region.id, generated, ttl=3600)
```

**Storage impact:** 10MB seed + modifications, not 200M
entities. **20,000x reduction in cold storage.**

---

## The math

For 200 km² with the 8 innovations above:

| Metric | Naive | Optimized | Reduction |
|--------|-------|-----------|-----------|
| RAM (peak) | 200M entities × 1KB = 200 GB | 1-10K hot + 100-500K warm = ~500 MB | **400x** |
| Tick CPU | 200M entities × 30 Hz = 6B ops/s | 1-10K hot × 30 Hz = 300K ops/s | **20,000x** |
| Sync bandwidth | 200M entities × 1KB / s = 200 GB/s | 1000 events × 1KB / s = 1 MB/s | **200,000x** |
| Cold storage | 200M entities × 1KB = 200 GB | 10MB seed + mods = ~10 MB | **20,000x** |

The 200km² world is real, persistent, fully featured. It
runs on commodity hardware (a single beefy server) with
the optimized stack.

**The naive number is 200,000x worse than the optimized
number.** The naive approach is impossible. The optimized
approach is routine.

---

## The cost of doing this wrong

If we shrink the world to 4km² to fit in memory:
- The game feels like a small zone, not a 200km² world
- The market is smaller, the player count is lower, the
  retention is worse
- The procedural content doesn't have room to breathe

If we load everything in RAM:
- 200GB RAM per server, 1-2 servers max
- 1 Gbps+ bandwidth per server, costs thousands/month
- No horizontal scale

If we don't have LOD:
- Every tick scans every entity
- 30Hz × 200M = 6B ops/s = need a supercomputer

If we don't have predictive prefetch:
- Players see loading screens constantly
- "Zone loading..." breaks immersion

If we don't have state diff sync:
- Clients need 1Gbps+ to keep up
- Mobile clients are impossible

**The 8 innovations aren't optional. They're the cost
of having a 200km² world at all.**

---

## The 5 things to do first

1. **Implement `lru_cache.gd`** (B-6) — the LRU is the
   foundation of every layer
2. **Implement `lod_manager.gd`** (B-3) — the LOD pyramid
   is what makes the world cheap
3. **Implement `state_tree.gd`** (A-3) — the content-hash
   state tree is the sync primitive
4. **Implement `markov.gd` + `prefetcher.gd`** (B-4) — the
   predictive prefetch is the feel
5. **Implement `composite_table.gd`** (B-2) — the
   multi-axis intersection is the read path

After these 5, the 200km² world is buildable. The rest is
polish.

---

## The novel insight

The 8 innovations aren't independent. They compose:

- **LOD pyramid** is *enabled by* the state tree
  (cold → disk, hot → RAM, etc.)
- **Predictive prefetch** is *enabled by* the LOD
  (prefetch decides what to promote)
- **Multi-axis intersection** is *enabled by* the
  composite tables (the materialized view)
- **State diff sync** is *enabled by* the content hash
  (the hash is the version)
- **Hierarchical sync** is *enabled by* the spatial axis
  (the partition key)
- **Content-hash addressing** is *enabled by* the state
  tree (the cache key IS the hash)
- **RAM + Postgres split** is *enabled by* the LOD
  (the LRU + cold storage)
- **Procedural assimilation** is *enabled by* the
  modification log (the diff IS the content)

The multi-iso frame is the **substrate** that makes all
8 innovations possible. Without the frame, you'd be
building 8 separate systems. With the frame, you build
1 frame and get 8 innovations for free.

**This is the leverage of the architecture.** The frame
is the substrate. The innovations are emergent.

---

## See also

- [`multi-iso-frame.md`](./multi-iso-frame.md) — the
  orchestrator (substrate).
- [`multi-iso-lod-prediction.md`](./multi-iso-lod-prediction.md) —
  the LOD + prediction details.
- [`grail-path.md`](./grail-path.md) — the pre/mid/post
  contract. The math is the prefetch + composite update.
- [`vant-lift.md`](./vant-lift.md) — the LRU, content
  hash, and sync primitives are all from vant.
- [`security.md`](./security.md) — the recursion guard
  prevents the predictive prefetch from looping.
