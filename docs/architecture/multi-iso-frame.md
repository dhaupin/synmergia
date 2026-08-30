# Multi-Iso Orchestrator: A New MMORPG Frame

**Status: Design exploration. Pioneering work, parallel to vant.**

**TL;DR:** Spawn two or more icosahedral spaces (each a "view" of the
world — spatial, factional, temporal, social, etc.). Intersect them
to get multi-dimensional queries. Reserve NSC-9 digit ranges per
axis so addresses are namespace-typed. Run the whole thing through
an *orchestrator* that handles before/during/after data flow.

This is a **frame** (a reusable abstraction), not a Synmergia
feature. It can be extracted later. We just happen to be building
the first instance of it.

---

## The reframing: KV and beyond

The user caught the right thing. Content-hash as a redis-like
extension (the previous revised eval) is fine but flat — it's
just a fast KV with versioned values. The actual leverage is in
**multi-dimensional intersection**:

```
iso_spatial  := project(world,   x→vertex)   # "where"
iso_faction  := project(world,   faction→vertex)  # "who"
iso_temporal := project(world,   tick→vertex)    # "when"
iso_social   := project(world,   relation→vertex) # "with whom"
```

Each `iso_X` is a *view* of the same world. An entity exists in
every iso, at a different coordinate in each.

**Intersection** answers multi-dimensional queries:

```
query("enemies in region X that are in faction Y and updated in last 5 ticks")
  = iso_spatial[region X] ∩ iso_faction[faction Y] ∩ iso_temporal[last 5 ticks]
  = sub-tree of world
```

The intersection is the set of entities matching all three
criteria. With icosahedral projection + content-hash, you can
answer this in O(1) lookup per axis: hash the (region, faction,
time-range) tuple, look up each in its iso, intersect the three
result sets.

This is **not a database query** (you don't scan). It's **not a
redis get** (it's multi-axis). It's something new. A
*multi-dimensional content-addressable space*.

---

## NSC-9 reserved space identifiers

The 12 digits of NSC-9 aren't just a barcode. They're a
**namespace reservation**:

```
NSC-9 code: 9-AAA-BBB-CCCCCC
            │  │    │    │
            │  │    │    └── sequence within axis (6 hex digits = 16M entities)
            │  │    └─────── axis reservation (3 digits = 1000 axes)
            │  └──────────── facility (3 digits = 1000 facilities)
            └─────────────── NSC-9 prefix (the "9" is the GS1 indicator for "non-product")
```

**Axis reservations** are the new bit. The middle 3 digits encode
*which icosahedral axis* this entity lives on. Pre-allocate:

- `001`–`099`: reserved for the spatial axis (iso_spatial)
- `100`–`199`: reserved for factional axes (100 factions × 1 axis each)
- `200`–`299`: reserved for temporal axes (year, season, hour, ...)
- `300`–`399`: reserved for social axes (per-player, per-guild, per-party)
- `400`–`499`: reserved for game-specific axes (class, level, ...)
- `500`–`999`: free for new axes as the game evolves

When you want to know "is this entity on the spatial axis?", check
if the axis digits are in `001-099`. When you want to know "is
this in faction 7's subtree?", check axis = `100 + 7 * 1` and
hash that path. The barcode *is* the multi-dimensional index.

The reservation scheme is administrative. It can be encoded in a
config file (`nsc9_axis_registry.tres`) and updated as new axes
are added.

---

## Orchestrator: the before/during/after pattern

The orchestrator isn't a layer of the data stack. It's a
*controller* that runs at three points in the data lifecycle:

### Before (input: projecting onto axes)

When new state arrives (server tick, peer sync, save load, player
input), the orchestrator projects it onto all relevant axes:

```
def on_state_received(state_chunk):
    for entity in state_chunk:
        for axis in active_axes:
            coord = axis.project(entity)
            axis.store(coord, entity.nsc9_code)
```

The result: every entity is registered in every relevant iso. The
same entity can be at "spatial vertex v17" AND "faction vertex f03"
AND "temporal vertex t2024" simultaneously.

### During (processing: intersecting for queries)

When the game needs to query, the orchestrator intersects:

```
def query(spatial_range, faction_filter, time_range):
    a = iso_spatial.range(spatial_range)   # hash-set of NSC-9 codes
    b = iso_faction.eq(faction_filter)     # hash-set of NSC-9 codes
    c = iso_temporal.range(time_range)     # hash-set of NSC-9 codes
    return a ∩ b ∩ c                       # hash-set intersection
```

The intersection is a hash-set, so it's O(min(|a|, |b|, |c|))
which is fast. The result is a list of NSC-9 codes (entity
references), which the orchestrator resolves back into the state
tree (via content-hash).

### After (output: projecting from axes)

When data leaves (broadcast, persist, send to peer), the
orchestrator projects from the axes back into a serializable form:

```
def on_state_destination(entity_codes, format):
    entities = [state_tree.get(code) for code in entity_codes]
    if format == 'rpc':
        return serialize_rpc(entities)
    elif format == 'sql':
        return serialize_sql(entities)
    elif format == 'peer':
        return serialize_peer(entities)
```

The orchestrator knows which axes are relevant for each output
format. Spatial+ faction are relevant for player view; social is
relevant for friend list updates; temporal is relevant for
analytics.

---

## Architecture: where it sits

```
┌────────────────────────────────────────────────────────┐
│                       Game                             │
│  (entities, components, world, ui, ai)                 │
└────────────────────────┬───────────────────────────────┘
                         │ before / during / after
                         ▼
┌────────────────────────────────────────────────────────┐
│                    Orchestrator                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │ iso_spatial │  │ iso_faction │  │ iso_temporal│    │
│  │ (qcrystal)  │  │ (qcrystal)  │  │ (qcrystal)  │    │
│  └─────────────┘  └─────────────┘  └─────────────┘    │
│  ┌─────────────┐                                      │
│  │ iso_social  │  ... N axes                          │
│  │ (qcrystal)  │                                      │
│  └─────────────┘                                      │
│  axis_registry.tres: NSC-9 → axis mapping             │
└────────────────────────┬───────────────────────────────┘
                         │ state tree by NSC-9
                         ▼
┌────────────────────────────────────────────────────────┐
│                  State Tree (content-hash)             │
│  node = { path, nsc9, hash, value, children[] }       │
│  diff(old_root, new_root) → (path, new_hash, value)[]  │
│  apply_diff(root, diff) → new_root                    │
└────────────────────────┬───────────────────────────────┘
                         │ snapshot / patch
                         ▼
┌────────────────────────────────────────────────────────┐
│              Postgres / KV / file (durable)            │
└────────────────────────────────────────────────────────┘
```

**The orchestrator is the new layer.** It sits in front of the
state tree (Session 3 of the previous plan) and provides
multi-dimensional access. The state tree is the per-entity
canonical form. Postgres is the durable record.

The orchestrator doesn't replace anything; it adds a new way to
think about state.

---

## Why "frame" and not "feature"

A *feature* is a thing this MMORPG does. A *frame* is a
reusable abstraction that other games can be built on.

The multi-iso orchestrator is a frame because:

1. **It's axis-agnostic.** Today Synmergia uses spatial + faction
   + temporal + social. A strategy game might use territory +
   diplomacy + economy. A card game might use deck + hand +
   discard. The frame supports any set of axes.
2. **The orchestrator pattern is reusable.** Before/during/after
   is a general pattern for any stateful system. The frame
   provides the orchestrator; games provide the axes.
3. **NSC-9 reserved space is reusable.** The axis reservation
   scheme is administrative. Other games can use the same scheme
   with different reserved ranges.
4. **The state tree underneath is reusable.** Any game with
   entities can use the content-hash tree.

If we extract this as a separate project (alongside vant), it
becomes a "MMORPG frame" that others can build on. Not a game
engine — a frame. Like React is a frame, not a game.

This is the "could turn into anything" the user mentioned.

---

## The honest constraints

This is a research project. Be honest about what's hard:

### 1. Math performance
GDScript is slow for hot-path math. Multi-iso intersection
involves:
- Hashing the (region, faction, time) tuple per query
- Looking up each axis in its quasicrystal
- Hash-set intersection of the results
- Resolving NSC-9 codes back into the state tree

If this runs every frame at 60fps with 10K entities, we need
to budget carefully. Realistic options:
- Move the math to a NativeScript C++ module (Godot supports it)
- Move the math to a server-side process and the client just gets results
- Pre-compute intersections for common queries (cache them)

### 2. Intersection semantics
What does "intersection" mean concretely?
- **Hash-set intersection:** fast, exact, O(min(|a|, |b|, |c|))
- **Spatial intersection:** geometric, slower, more expressive
- **Range intersection:** for temporal/social, natural

The frame should support all three. Pick by axis type.

### 3. NSC-9 namespace governance
Who decides which axis gets which digit range? This is a
governance problem. Initial allocation is in this doc; future
allocation needs a process. Probably:
- Static config file (axis_registry.tres) at first
- On-chain or signed config for multi-game / multi-shard use
- The "9" prefix is reserved by the NSC-9 spec; we can't repurpose

### 4. State tree + orchestrator ordering
The orchestrator sits on top of the state tree. But the state
tree is a per-entity canonical form. Do we store the state tree
NSC-9 codes in the orchestrator's axes, or do we store the
content-hashes? Both, probably:
- Axes store NSC-9 codes (the references)
- State tree stores content-hashed values (the data)
- Orchestrator joins them: NSC-9 → state tree lookup

### 5. What if the geometry doesn't pan out?
If multi-iso intersection turns out to be overengineered for
Synmergia's actual needs (or too slow), we can fall back to:
- Just the state tree (Session 3) without the orchestrator
- Plain SQL with composite indexes
- A simpler multi-key lookup

The frame is additive. Falling back to "no orchestrator" loses
nothing because Postgres + state tree is already enough.

---

## Revised plan (with the orchestrator as a research track)

The orchestrator is **parallel** to the practical work, not
blocking. The plan splits into two tracks:

### Track A: Practical (shipping features)
- **Session 1**: Islands POC ✅
- **Session 2**: UIPanel → islands
- **Session 3**: State tree (content-hash, diff, sync)
- **Session 4**: Save games as content-hashed trees
- **Session 5**: Item template content-hash
- **Session 6**: Asset addressing
- **Session 7**: Build pipeline

### Track B: Research (the frame, alongside vant)
- **Session B1**: Math primitives in GDScript
  - `labs/multi-iso/math/nsc9.gd` — 12-digit code, axis reservation
  - `labs/multi-iso/math/icosahedral.gd` — projection + depth recursion
  - `labs/multi-iso/math/quasicrystal.gd` — paths from content
  - Tests for all three (round-trip, edge cases)
- **Session B2**: Single-axis orchestrator prototype
  - `labs/multi-iso/srv/axis.gd` — base class
  - `labs/multi-iso/srv/spatial_axis.gd` — iso_spatial
  - `labs/multi-iso/srv/faction_axis.gd` — iso_faction
  - Test: project 1000 entities, query by range, verify result
- **Session B3**: Multi-axis intersection
  - `labs/multi-iso/srv/intersect.gd` — hash-set / range / spatial
  - Test: 3-axis query, verify intersection is correct
- **Session B4**: NSC-9 axis reservation
  - `labs/multi-iso/srv/axis_registry.gd` — load axis_registry.tres
  - Test: reserve axis 100 for faction 7, verify NSC-9 code format
- **Session B5**: Frame extraction
  - Identify which parts are Synmergia-specific vs generic
  - Move generic parts to a new repo (alongside vant)
  - Document the frame API

Track B is research. It may take many sessions. It may not
pan out. That's fine. Track A is the real product work.

---

## How this could "turn into anything"

The user is right. With multi-iso intersection, you can build:

- **Spatial MMO** (use iso_spatial + iso_faction + iso_temporal)
- **Strategy game** (use iso_territory + iso_diplomacy + iso_economy)
- **Card game** (use iso_deck + iso_hand + iso_discard)
- **Social network** (use iso_social + iso_interest + iso_geo)
- **Simulator** (use iso_temporal + iso_entity + iso_property)
- **All of the above in one game** (intersect more axes)

The frame is the constant. The axes are variable. This is why
it's a frame, not a game.

If we publish it alongside vant, others can use it for their
own games. Pioneering.

---

## Open questions

1. **Should Track B be in a separate repo from the start?** The
   "alongside vant" framing suggests yes. But it's also fine to
   prototype in Synmergia and extract later. User's call.
2. **What's the axis allocation for non-spatial games?** The
   current allocation is biased toward spatial MMOs. A strategy
   game might want more faction/territory axes. Should the
   allocation be configurable per-game?
3. **Performance budget.** What's the target frame time for a
   multi-iso query with 10K entities? 1ms? 10ms? This decides
   whether the math needs C++ or stays in GDScript.
4. **Multi-shard orchestrator.** Does each shard have its own
   orchestrator, or is there a global orchestrator? The
   content-hash tree is shard-local; the orchestrator might
   need to be too.

---

## What this doc is

A record of a design exploration. The multi-iso orchestrator is
*proposed* as a research project. It's not the Synmergia roadmap;
it's a parallel track. The state tree (Session 3 of Track A) is
the foundation; the orchestrator builds on top of it.

The user said: "Overbuilt for internal KV, but well built for a
new mmorpg frame." That's the honest framing. We build Track A
for Synmergia. We build Track B as a frame. They're related
(the state tree is shared) but Track A doesn't depend on Track B.

If Track B pans out, it becomes a separate project. If it doesn't,
no harm done.

This is the actual frontier. Let's go.
