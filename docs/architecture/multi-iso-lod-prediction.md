# Multi-Iso Orchestrator, Part 2: LOD, Prediction, and the Self-Tuning Loop

**Status: Design exploration, continues from `multi-iso-frame.md`.**

**TL;DR:** Don't compute intersections at query time. Pre-compute
them at ingest time. Apply Level-of-Detail to iso regions (full,
summary, cold, archived). Use the temporal axis to predict which
spatial regions will be hot next. The system self-tunes: hot
regions stay loaded, cold regions get archived, predictions feed
predictions, full circle.

This is **fused mode** — the geometry integrates with the existing
state representation instead of being a separate layer. The
entity *already* has its axis coordinates, so the isos become
indexes into state, not separate storage. The state tree + icosahedral
encoding is one structure, not two.

---

## What changed from Part 1

Part 1 treated the orchestrator as a separate layer:
`Game → Orchestrator → State Tree → Postgres`. The orchestrator
maintained separate iso indexes that the state tree referenced.

The user pointed out: "combining isos into existing states." This
means the state itself carries its axis coordinates, so the
is indexes are derived, not separate. The state tree IS the
multi-axis index. The orchestrator's job becomes:

1. **Project** new state onto axes (compute vertex coordinates)
2. **Materialize** the intersection tables for hot queries
3. **Demote** cold regions to lower LOD
4. **Predict** next-hot regions from temporal patterns
5. **Prefetch** predicted regions' materialized tables

The orchestrator doesn't *store* the multi-axis index. It
*manages* it. The state tree is the source of truth.

---

## Fused vs separated mode

Two ways to represent multi-axis data:

### Fused mode (default)

The entity's state record *is* the multi-axis index.

```json
{
  "nsc9": "9-018-042-A7F2C1",
  "spatial_vertex": 17,
  "faction_vertex": 3,
  "temporal_vertex": 2024,
  "social_vertex": 12,
  "content_hash": "abc123...",
  "value": { ... }
}
```

Query: "all entities at spatial vertex 17 AND faction vertex 3"
= `SELECT * FROM state WHERE spatial_vertex=17 AND faction_vertex=3`

In Godot: a Dictionary keyed on (spatial, faction) composite, or a
sparse 2D array, or just filter on the fly. With NSC-9, the barcode
encodes the axis reservation, so you can do range queries:
"all entities with NSC-9 axis = 018 (spatial) AND axis = 103 (faction 3)"
= range scan on the barcode prefix.

This is the *natural* representation. The state tree has the data;
the icosahedral encoding is in the NSC-9 code; queries are direct.

### Separated mode (for traversal)

When you need to traverse ("give me the 5 nearest entities to vertex 17"),
you need an index. Separated mode maintains:

```
iso_spatial: { vertex_17: [nsc9_codes], vertex_18: [nsc9_codes], ... }
iso_faction: { vertex_3: [nsc9_codes], vertex_4: [nsc9_codes], ... }
```

The orchestrator maintains these as derived data. They're rebuilt
from the state tree on demand. The cost: a one-time scan when the
orchestrator starts, or incremental updates as state changes.

The benefit: traversal queries (adjacency, range, nearest) are O(1)
instead of O(N) scans.

### When to use which

- **Fused mode**: point queries, exact lookups, "give me entity X"
- **Separated mode**: traversal queries, "give me all entities in region X"
- **Composite (fused + separated)**: both, as needed

The orchestrator switches between them based on query type. The
state tree is the source of truth in both modes.

---

## Materialized intersection tables (the CPU-cycle win)

The user said: "leverage our geometric nsc9 namespace to reduce
CPU cycles for lookups, syncs, etc, by combining isos."

This is the **materialized view** pattern. Instead of computing
intersection at query time, pre-compute it at ingest time.

### Naive (slow)

```
query("region X, faction Y, time T")
  = iso_spatial[X] ∩ iso_faction[Y] ∩ iso_temporal[T]  # 3 lookups + intersection
  ≈ O(|X| + |Y| + |T|) per query
```

If the same query is made 1000 times per second (common in a
busy MMO region), that's 3000 lookups + intersections per second.
For 10K entities, ~30M operations per second. GDScript won't keep up.

### Materialized (fast)

At ingest time, when an entity is added/updated, the orchestrator
also updates the intersection table for the *combinations it cares about*.

```
on_entity_update(entity):
  for combo in active_combos:
    key = (combo.axes..., entity.coords[combo.axes])
    composite_table[key].add(entity.nsc9)

query("region X, faction Y, time T")
  = composite_table[(spatial_X, faction_Y, temporal_T)]  # 1 lookup
  ≈ O(1) per query
```

The cost is at ingest (O(combos × entities) per update). The
benefit is at query (O(1) per query).

The trade-off: `composite_table` can grow large. If you have 100
spatial regions × 10 factions × 10 time-buckets = 10K combo keys,
each with up to N entities, the table is up to 10K * N entries.
For N=10K, that's 100M entries. Too much.

### Bounded materialized (the right answer)

Don't materialize all combinations. Materialize the **hot ones** —
the combinations that have been queried recently or are predicted
to be queried.

```
hot_combos = LRU_cache(max_size=1000)  # keep last 1000 hot combos

on_query(combo_key):
  if combo_key in hot_combos:
    return hot_combos[combo_key]  # O(1) hit
  else:
    # miss: compute intersection, add to hot_combos (evict oldest if full)
    result = intersect(combo_key)
    hot_combos[combo_key] = result
    return result

on_entity_update(entity):
  for combo_key in hot_combos:
    if entity matches combo_key:
      hot_combos[combo_key].add(entity.nsc9)
```

This is an LRU cache of materialized intersections. Hits are O(1).
Misses fall back to compute (O(N)). The cache auto-tunes to the
query pattern.

Combined with the LOD pyramid (next section), this is the actual
CPU-cycle win: hot combos are O(1) lookups, warm combos are
in-memory but recomputed on demand, cold combos are on disk and
reconstructed on demand.

---

## LOD pyramid: 4 levels for iso regions

The user said: "if no one has been there, or it's not touched, safe
to save and unload."

Apply the LOD pattern to iso regions. Not just to graphics.

### The pyramid

```
LOD 0 (full)
  - All entities present
  - All materialized tables in memory
  - In-memory state tree nodes
  - Real-time updates
  - Hot regions: where players are NOW

LOD 1 (summary)
  - Entity count + last-touched timestamp + region_hash
  - No materialized tables
  - Can be promoted to LOD 0 in O(1) (load from snapshot)
  - Warm regions: where players were recently

LOD 2 (cold)
  - Just (region_hash, last_touched)
  - Serialized to disk
  - Promoting requires re-deriving entities from seed/worldgen
  - Cold regions: where players haven't been in a while

LOD 3 (archived)
  - Just a tombstone in the namespace
  - "This region existed, was at hash X, was archived at time T"
  - Cannot be promoted without worldgen + history
  - Ancient regions: never visited
```

### Promotion and demotion

```
promote(region, target_lod):
  if target_lod == LOD_0:
    load state tree nodes from disk (LOD_1) or worldgen (LOD_2/3)
    rebuild materialized tables
    mark as LOD_0
  elif target_lod == LOD_1:
    load summary from disk (LOD_2) or just compute (LOD_3)
    mark as LOD_1

demote(region, target_lod):
  if target_lod == LOD_1:
    save entity_count, last_touched, region_hash to memory
    free entity data
  elif target_lod == LOD_2:
    serialize summary to disk
    free memory
  elif target_lod == LOD_3:
    write tombstone, free everything
```

### Triggers

- **Demote** when `last_touched > T_demote` (e.g., 5 minutes idle)
- **Promote** when a query requests a region at LOD > 0
- **Predict promote** when temporal pattern suggests region will be queried (next section)

The thresholds are tunable. Start with T_demote=5min for LOD 0→1,
1 hour for 1→2, 1 day for 2→3. Adjust based on memory pressure.

---

## Predictive prefetch: temporal feeds spatial

The user said: "predict hot zones, or zones next, it's a full circle."

This is the temporal axis being used to predict the spatial axis.

### The pattern

```
iso_temporal[player_P, recent_ticks] = [region_A, region_B, region_C, ...]
```

The orchestrator sees: player P was at A, then B, then C. So when
player P is at A *now*, predict they'll be at B *next*.

```
on_player_at(player_P, region_A):
  predicted_next = predict_next_region(player_P, region_A)
  if predicted_next and predicted_next.lod > LOD_0:
    promote(predicted_next, LOD_0)  # pre-load
```

The prediction is from `iso_temporal[player_P]` history. Simple
Markov chain: P(region_B | region_A, player_P) = count(A→B) / count(A).

### The full circle

The prediction creates a feedback loop:

1. Player P is at region A (spatial: hot)
2. iso_temporal records "P at A" (temporal: log)
3. Orchestrator predicts P will go to B (spatial: predict)
4. Orchestrator pre-loads B (spatial: warm)
5. P moves to B (spatial: hot)
6. iso_temporal records "P at B" (temporal: log)
7. Orchestrator now has more data for "A→B" transition (temporal: better prediction)
8. Orchestrator predicts P will go to C (spatial: predict)
9. ...

The temporal axis improves over time as more data accumulates. The
spatial axis becomes predictive, not just reactive. The isos feed
each other.

### Beyond Markov

For more sophistication:
- **Time-of-day patterns**: "Players in this MMO tend to gather at zone X on Friday nights"
- **Group patterns**: "Guild G always does dungeon D after farming F"
- **Anti-patterns**: "After event E, players leave region R for 10 minutes"

These can be encoded as additional temporal axes (per-day, per-event,
per-group). The multi-iso orchestrator's pattern naturally extends
to this: more axes = more refined predictions.

---

## Concrete example: 100 zones, 10K players

Let's make this concrete. Synmergia has (hypothetically) 100 zones
and 10K concurrent players.

### Without multi-iso (current)
- Each player has 100 entities in scope (their zone's entities)
- Each entity update = server tick broadcast to all in-scope players
- Bandwidth: 100 * 10K = 1M entity updates per tick
- Per-frame cost: high

### With multi-iso + materialized (proposed)
- 100 zones, each LOD 0
- 10K players, each in 1 zone (so 10K hot regions, but only 100 unique zones)
- Materialized table: (zone_X, faction_Y, recent_T) → 100 * 10 * 5 = 5K combo keys
- Each combo has up to ~1000 entities (zone_X has ~1000 entities)
- Total materialized table size: 5M entries
- Per query: O(1) lookup

### With multi-iso + LOD (further)
- Most zones are at LOD 0 (where players are)
- Some zones at LOD 1 (recently visited, no one there)
- Few zones at LOD 2 (cold)
- In-memory state: ~5M entries (current hot zones)
- On-disk: full state for all 100 zones, lazy loaded
- Per query on hot zone: O(1) lookup, in-memory
- Per query on cold zone: load from disk, promote to LOD 1 (or 0 if player enters)

### With multi-iso + prediction (further still)
- 90% of player movements are predictable from temporal patterns
- Prefetch: when player enters zone A, pre-load predicted zone B
- Net result: player movements feel instant because B is already loaded
- Self-tuning: the more data, the better the prediction

This is the "golden" state the user described. CPU cycles for
lookups: O(1) for hot queries, O(load) for cold (with prefetch
reducing load frequency), and the system self-tunes over time.

---

## Performance reality check

GDScript is slow. Some honest numbers:

### What GDScript can do
- LRU cache with 1000 entries: trivial, < 1ms per operation
- Composite table lookup (dict access): ~10ns per lookup in pure GDScript
- Iso lookup (range scan on NSC-9 codes): ~1μs per code
- 1000 queries per second: comfortable in GDScript
- 10K queries per second: getting tight
- 100K queries per second: GDScript will struggle

### What GDScript can't easily do
- Per-frame intersection recomputation on 10K entities
- Real-time quasicrystal serialization for large regions
- Markov chain training on millions of transitions

### Options
- **Cache aggressively.** Most queries are repeated. Cache hits are O(1).
- **Async computation.** Off-thread (worker thread) for cold-region recompute.
- **Server-side.** Move the multi-iso math to a server process; clients get cached results.
- **NativeScript C++ module.** If profiling shows GDScript is the bottleneck, port the hot paths to C++ via GDExtension. This is a 1-2 session investment for a 10-100x speedup.
- **Drop GDScript entirely for the math.** The frame can be a standalone Rust/Go server that the Godot client talks to. Multi-iso is a backend concern more than a game-engine concern.

For the research prototype, GDScript is fine. The performance
optimization is a separate session.

---

## The full vision: a self-tuning MMO engine

Putting it all together, the multi-iso orchestrator (Part 1) +
materialized intersections + LOD + prediction (Part 2) is a
**self-tuning MMO engine**:

```
                  ┌──────────────────────────────────────┐
                  │           Self-Tuning Engine         │
                  │                                      │
   Player input ──┤  ┌──────────┐    ┌──────────────┐    │
                  │  │ Fused    │    │ Materialized │    │
   Tick update ───┤  │ State    │───▶│ Intersect    │    │
                  │  │ Tree     │    │ Tables (LRU) │    │
   Peer sync  ────┤  │ + NSC-9  │    └──────┬───────┘    │
                  │  └──────────┘           │            │
                  │                         ▼            │
                  │                  ┌──────────────┐    │
                  │                  │ LOD Pyramid  │    │
                  │                  │ 0 full       │    │
                  │                  │ 1 summary    │    │
                  │                  │ 2 cold       │    │
                  │                  │ 3 archived   │    │
                  │                  └──────┬───────┘    │
                  │                         │            │
                  │                         ▼            │
                  │                  ┌──────────────┐    │
                  │                  │ Predictor    │    │
                  │                  │ (Markov)     │    │
                  │                  │ next_region  │    │
                  │                  └──────┬───────┘    │
                  │                         │            │
                  │                         ▼            │
                  │                  pre-fetch → promote │
                  └──────────────────────────────────────┘
```

The orchestrator is the *control plane* for this engine. It:
1. Maintains the fused state tree (the source of truth)
2. Maintains the materialized intersection tables (the L1 cache)
3. Manages the LOD pyramid (the L2/L3 cache)
4. Runs the predictor (the prefetch engine)
5. Promotes/demotes regions based on activity (the self-tuning)

The user gets fast queries (L1 hits), graceful cold regions
(L2/L3 lazy load), and smooth gameplay (predictive prefetch). The
operator gets a system that uses memory efficiently (LOD) and
improves over time (prediction).

This is what the user meant by "we would be golden."

---

## Revised plan: additions to Track B

Sessions B1-B5 (from Part 1) plus:

### Session B6 — Materialized intersection tables
- `core/orchestrator/composite_table.gd` — LRU cache of (axis_combo) → entity_set
- `core/orchestrator/materializer.gd` — on_entity_update, on_query
- Test: 10K entities, 1000 hot combos, verify hit rate

### Session B7 — LOD pyramid
- `core/orchestrator/lod_manager.gd` — promote/demote regions
- `core/orchestrator/lod_state.gd` — LOD 0/1/2/3 representations
- Test: 100 regions, 90 hot, 9 warm, 1 cold, verify memory profile

### Session B8 — Predictive prefetch
- `core/orchestrator/predictor.gd` — Markov chain over player transitions
- `core/orchestrator/prefetcher.gd` — promote predicted regions
- Test: 1000 player movements, verify prediction accuracy

### Session B9 — Performance budget
- Decide: GDScript enough? NativeScript C++? Standalone server?
- Run profiling with realistic load
- Document the answer

### Session B10 — Frame extraction
- Identify Synmergia-specific parts
- Move generic parts to a separate repo (alongside vant)
- Document the frame API for external use

---

## What this means for Synmergia specifically

For the actual Synmergia product:

- **Track A still ships first.** The state tree (Session 3) and
  islands (Session 2) are the practical foundation. They don't
  need the orchestrator.
- **Track B is the future.** When Track A is solid, Track B
  can layer on top. The first Track B feature to ship in
  Synmergia is probably the materialized intersection tables
  (B6) — direct CPU win for the most common queries.
- **LOD (B7) is the second feature to ship.** It addresses the
  "shard is using too much memory" problem that's universal in
  MMOs. Even without the orchestrator, LOD for entities is a
  win.
- **Prediction (B8) is the third.** Once the orchestrator has
  enough data (a few hours of playtime), predictions become
  useful. Earlier than that, it's just overhead.

For the frame (alongside vant):

- **Sessions B1-B5** are the foundation.
- **B6** is the "killer feature" — materialized intersections.
- **B7-B8** are the self-tuning layer.
- **B9-B10** are the productionization.

The frame can be published alongside vant at the end of B10.
The user said "could pioneer" — this is the pioneering.

---

## Open questions

1. **Is the Markov-chain predictor enough, or do we need ML?**
   Markov is simple, fast, no training. ML is more accurate but
   adds complexity. Start with Markov, see if it's enough.
2. **Composite table size cap.** How many combo keys to keep?
   LRU with max 1000 is a guess. Tune based on memory budget.
3. **LOD thresholds.** What are the right idle times for
   LOD 0→1, 1→2, 2→3? Depends on memory pressure and
   worldgen speed (cold regions must re-derive fast).
4. **Prediction horizon.** How far ahead to predict? 1 region?
   3 regions? More? Trade-off: more prediction = more prefetch
   = more memory used for things that might not be needed.
5. **Cross-shard prediction.** If player walks from shard 1 to
   shard 2, does shard 2 know the player's movement history?
   Probably needs a small cross-shard state for prediction
   purposes.

These are tunable. Start with defaults, iterate.

---

## What this doc is

Part 2 of the multi-iso orchestrator design. Part 1 was the
basic pattern; this is the self-tuning extension. Together they
are the "frame" — the reusable abstraction that could be
extracted as a project alongside vant.

User's framing: "leverage our geometric nsc9 namespace to reduce
CPU cycles for lookups, syncs, etc, by combining isos instead
into existing states, we would be golden."

That's exactly what materialized intersection + LOD + prediction
do. CPU cycles go from O(N) per query to O(1) for hot queries
and O(load) for cold (with prefetch). The state tree *is* the
multi-axis index (fused mode). The isos feed each other (full
circle).

This is the golden state. Let's build it.
