# World-Building Plan

> **Status:** Phase 2 - Frame primitives consolidated, single-process architecture. Companion reference: `m3-initial-world-audit.md`
> (the "where we are today" snapshot) and `world-building-research.md`
> (research companion for §21's experimental angles) and
> `world-building-arch.md` (the systems architecture — frame
> substrate, scope engine, rules engine, world environment).
> This doc is the "where we're going" — server, sync, net code,
> map, procedural generation, zone, world, and the geometric-
> addressing layer that ties them together.
>
> **Last updated:** 2026-09-17
>
> **Scope:** Design the full world + network + persistence stack for
> Synmergia such that (a) the same server and client agree on
> terrain/POIs/drops across logins and across players, (b) instanced
> regions (dungeons, arenas, party/guild halls) get their own
> deterministic seed, (c) the open world supports **both planar
> (square/circle ~200 km²) and spherical (planet) maps**, (d) a
> geometric addressing layer (NSC-9 + icosahedral + quasicrystal)
> optionally sits on top of Redis + Postgres for KV and spatial
> query speedups, (e) the client runs in a **browser** (Godot
> HTML5/wasm), and (f) the design covers player-placed content
> (ankhs, guild halls, houses) with cross-shard awareness.
>
> **Non-goals (this doc):** combat math, AI behavior, UI panels,
> notification pipeline, anti-cheat internals, payment/auth, art
> pipeline, mobile (Android/iOS native) builds. Each touched only
> where it crosses the world/network boundary.

---

## Table of Contents

1. [Principles & commitment](#1-principles--commitment)
2. [Top-level architecture](#2-top-level-architecture)
3. [Coordinate system: planar + spherical](#3-coordinate-system-planar--spherical)
4. [Seed model: world / shard / instance](#4-seed-model-world--shard--instance)
5. [The content-hash state tree](#5-the-content-hash-state-tree)
6. [Geometric addressing layer (NSC-9 + icosahedral + quasicrystal)](#6-geometric-addressing-layer-nsc9--icosahedral--quasicrystal)
7. [Procedural generation](#7-procedural-generation)
8. [Zone model: regions, gateways, instances, transitions](#8-zone-model-regions-gateways-instances-transitions)
9. [Server tick model](#9-server-tick-model)
10. [Transport: WebSocket for browser + agent compatibility](#10-transport-websocket-for-browser--agent-compatibility)
11. [Sync protocol: diffs, prediction, AOI, lag compensation](#11-sync-protocol-diffs-prediction-aoi-lag-compensation)
12. [Persistence: Postgres + Redis + optional geo-cache](#12-persistence-postgres--redis--optional-geo-cache)
13. [Frame services: axes, projection, when & how](#13-frame-services-axes-projection-when--how)
14. [LOD pyramid & predictive prefetch](#14-lod-pyramid--predictive-prefetch)
15. [Player-placed content (ankhs, halls, houses)](#15-player-placed-content-ankhs-halls-houses)
16. [Cross-shard sync](#16-cross-shard-sync)
17. [Three-tier runtime: GDScript / Julia / C++](#17-three-tier-runtime-gdscript--julia--c)
18. [Migration path & milestones](#18-migration-path--milestones)
19. [Risks, open questions, deferred items](#19-risks-open-questions-deferred-items)
20. [Glossary](#20-glossary)
21. [Experimental angles (post-Phase-1 research)](#21-experimental-angles-post-phase-1-research)

---

## 1. Principles & commitment

These are the load-bearing commitments. Every section below
is checked against them. If two sections conflict, the
principles win.

### 1.1 Determinism over cleverness

A given seed + a given input sequence produces the same world
state on every client and server, always. Same tree at the
same coordinates, same rock, same drop table result for the
same RNG draws. We choose determinism even where it costs
us flexibility (no fancy GPU-only terrain that diverges by
hardware, no async noise that depends on thread scheduling).

**Implication:** procedural generation must be **pure
functions** of (seed, coordinate, generation rules). No
floating-point tricks that drift across platforms; we either
use integer/fixed-point hashes or accept the platform delta
and hash the result.

### 1.2 The seed is a first-class object

Seeds are not buried inside procedural functions. They are
named, versioned, scoped, addressable, and inspectable. We
have a `Seed` type with `purpose` (world, shard, instance,
player, generation-pass), `value`, `version`, `derivation`
(parent seed + derivation rule), and `scope` (set of players
or entities that see this seed's output).

### 1.3 Authoritative server, predicted client

The server is the source of truth. The client predicts
locally for responsiveness (movement, animation, basic
attacks) and reconciles via state diffs. **No client-side
authority** on world state, drop tables, mob health, or
currency. The client may *display* anything the server
broadcasts, but it cannot *change* anything without server
ack.

### 1.4 Read = lookup, write = command

The "grail path" from `grail-path.md`. Reads are projections
over materialized state. Writes are commands that re-derive
the projections. We never compute intersections at query
time if we can materialize them; we never re-derive a chunk
of state at read time if it's already on disk.

### 1.5 Geometry is a layer, not a replacement

The geometric addressing layer (NSC-9, icosahedral,
quasicrystal) sits *on top* of Postgres + Redis. It is not
the storage system. It is an indexing/caching layer that
can be turned off, dimmed, or replaced without breaking the
underlying state tree or Postgres queries. This is the
lesson from `nsc9-honest-evaluation.md`.

### 1.6 Map shape is a parameter, not a hardcoded choice

The same engine serves a planar 200 km² open world AND a
planet. The state tree, the seeds, the address space, and
the LOD pyramid are all shape-agnostic. Only the
*projection function* (world coordinate → address cell)
changes between planar and spherical maps.

### 1.7 Browser-compatible transport, no exceptions

The game runs in a browser (Godot HTML5/wasm). That means
**WebSocket only** for client→server. No raw UDP, no
peer-to-peer from the browser. ENet stays as an option for
native clients and dedicated-server-internal traffic.

### 1.8 Shards are not worlds

Shards are **horizontal scaling units** of the same world.
A player on shard 2 sees the same forest as a player on
shard 1; only the *players around them* differ. Cross-shard
state (guilds, alliance wars, world bosses, auction house)
is shared via a coordinator service, not broadcast between
every shard.

### 1.9 Player-placed content is world state

Ankhs, guild halls, houses, planted crops, crafted signs —
all of it goes through the state tree, gets content-hashed,
and is syncable across shards the same way terrain is. No
second-class "housing database" beside the world database.

### 1.10 Test what we ship

The state tree, the diff protocol, the address projection,
the seed system, the LOD promotion logic — every layer
gets a headless smoke test in `tests/` before the UI/UX
work begins. A green test for "two clients see the same
tree after 1000 ticks" is the gate, not a stretch goal.

---

## 2. Top-level architecture

### 2.1 The five layers (revised from PRD §10)

```
┌─────────────────────────────────────────────────────────────┐
│  CLIENT (Godot 4.7.2 → HTML5/wasm)                          │
│  - Predicted view of the state tree                         │
│  - WebSocket transport only                                 │
│  - Local LOD cache + address-space cache                    │
│  - Geometry-renderer for cells it has been told about       │
├─────────────────────────────────────────────────────────────┤
│  TRANSPORT LAYER (WebSocket relay + framing)                │
│  - Auth handshake, tick-aligned batches, diff framing       │
│  - One WebSocket per client; pure message-oriented          │
│  - Optional ENet lane for native-only dedicated traffic     │
├─────────────────────────────────────────────────────────────┤
│  GAME SERVER (Godot 4.7.2 headless, per shard)              │
│  - Tick loop (read state → step world → diff → emit)       │
│  - State tree: re-rooted every tick, content-hashed         │
│  - Multi-iso orchestrator: projects state onto axes         │
│  - Materialized intersection cache (LRU, hot combos)        │
│  - LOD manager: promote/demote chunks/cells                 │
│  - Predictive prefetch (Markov)                             │
│  - Procedural generator: invoked on LOD promotion           │
├─────────────────────────────────────────────────────────────┤
│  STORAGE (Postgres + Redis + optional geo-cache)            │
│  - Postgres: durable state, snapshot roots, player-placed   │
│  - Redis: tick cache, materialized intersections, sessions │
│  - Geo-cache (NSC-9 + icosahedral): spatial index on Redis  │
│    or Postgres, optional layer, opt-in per shard            │
├─────────────────────────────────────────────────────────────┤
│  COORDINATOR (cross-shard, separate process)                │
│  - Guilds, factions, world events, auction house            │
│  - Player identity, character persistence (master record)   │
│  - Cross-shard state diffs (state tree applied across)      │
│  - Shard registry, player routing, presence                 │
└─────────────────────────────────────────────────────────────┴
```

Compared to PRD §10.3, two notable changes:
- The **transport layer is explicit**, because browser-only
  forces a redesign.
- The **coordinator is split out** as its own process;
  guilds and factions aren't owned by any single shard.

### 2.2 Process topology

**Current (Phase 2): Single Godot process**
```
┌─────────────────────────────────────────────────────────────┐
│ synmergia (Godot 4.7.2)                                     │
│  ├── All 50+ autoloads (GameManager, NetworkManager,       │
│  │    EntityService, FrameService, ShardParameters,         │
│  │    OpenSeedRegistry, RulesEngine, etc.)                 │
│  ├── Frame primitives (game/core/frame/math, kv, srv, db)  │
│  └── Adapter layer (game/adapters/)                        │
└─────────────────────────────────────────────────────────────┘
```

> **Note:** Multi-process architecture (Coordinator + Shard servers) is a future Phase 5+ goal. See `world-building-arch.md` §11 for deferred extraction.

### 2.2.1 Future topology (Phase 5+)

### 2.3 What lives where

| Layer | Lives in |
|---|---|
| Godot client (game UI, prediction, address-space render) | `game/` |
| Godot server (tick loop, state tree, LOD) | `game/` (server mode), separate executable target |
| Frame services (FrameService, ShardParameters, OpenSeedRegistry, RulesEngine) | `game/core/frame/srv/` |
| State tree primitives | `game/core/frame/kv/` |
| Geometric addressing | `game/core/frame/math/` + thin Godot wrapper |
| Postgres schema + migrations | `game/core/frame/db/` |
| Coordinator service | NOT IMPLEMENTED (deferred to Phase 5+) |

The "labs graduates into game or extracts to a new project"
rule still holds. The coordinator is the most likely
candidate to extract early — it has no Godot dependency.

### 2.4 Authority & data flow

| Concern | Authoritative owner | Read by | Writes by |
|---|---|---|---|
| Player position | Shard (server) | Same shard's clients + coordinator (rate-limited snapshot) | Server only; client sends input commands |
| Mob/NPC state | Shard | Clients on shard | Server only |
| World terrain (heightmap, biome, POI placement) | Shard's seed (immutable) | All clients with that region loaded | Server promotes chunks; chunks content-hash, immutable once promoted |
| Player-placed content (houses, ankhs, signs) | Shard where placed (default) OR coordinator (if cross-shard-visible) | Clients | Player, via validated server command |
| Guild state | Coordinator | All shards (subscribed) | Server (via validated player command) |
| Faction state | Coordinator | All shards | Server |
| World events | Coordinator (canonical) → shard (instances) | All shards | Server (event scheduler) |
| Character persistence (level, skills, inventory IDs) | Coordinator (master) + shard (live copy) | Players | Server (validated commands) |
| Item templates | Coordinator + cached on shard | All | Designer (data files) |

Note the **split authority** on player-placed content: the
shard owns the canonical record (because that's where the
spatial hash is), but the coordinator has a pointer/index
("house X exists on shard 2 at coord Y"). This avoids the
"every shard needs every shard's housing data" problem.

---

## 3. Coordinate system: planar + spherical

### 3.1 The world coordinate (W) is shape-agnostic

The engine internally uses **integer coordinates in a fixed
unit (1 meter)**. The choice between planar and spherical
is a **map-shape parameter** stored in the world metadata,
not a fork in the code. Both shapes project `W` to an
address cell differently:

- **Planar**: `W = (x, y, z) ∈ Z^3`, with `y = up`. World
  bounds are `(min_x, min_y, min_z)` to `(max_x, max_y,
  max_z)`. Wraps outside bounds → either out-of-world or
  wraparound (TBD; default out-of-world).
- **Spherical**: `W = (lat, lon, alt) ∈ Z^3`, encoded in
  degrees × 1e6 (micro-degrees for 1.1m at the equator; we
  may go finer). `alt` is meters above the surface radius.
  Wraps naturally (lat ∈ [-90e6, 90e6], lon ∈ [0, 360e6)
  wraps mod).

The **address cell** (the unit the state tree, the LOD
pyramid, and the geometric layer all key off) is computed
by:

```
address_cell(W) = projection_fn(W, world.shape, world.resolution)
```

Where `projection_fn` is one of:

| Shape | Function | Cell shape |
|---|---|---|
| Planar | `floor(W / chunk_size)` | Cubic chunk (e.g. 64m³, 128m³) |
| Spherical | `quantize(W, chunk_size_m)` on icosahedral mesh | Triangular cell on subdivided icosahedron |

### 3.2 Chunk size

Default chunk size: **64 meters on a side** (planar) or
**~64m edge length** (spherical). Tunable per world. We
chose 64m because:
- 200 km² at 64m chunks = 3.125 km × 3.125 km × N layers =
  ~3,200 chunks per km² × 200 = **~640,000 chunks** total.
  Storing a content hash per chunk = 32 bytes × 640K =
  20MB. Trivial.
- Memory budget per active chunk (full LOD, sparse entity
  grid): aim for <50KB on average. At 1% hot = 6,400 chunks
  × 50KB = 320MB. Fits on commodity server RAM.
- Visibility/render budget: at 64m, a 6,400m² visible patch
  (render distance 80m on each side, 64m chunks) ← 8 chunks.
  Reasonable draw call count.

### 3.3 Spherical map mechanics

For spherical worlds (planets), we use an **icosahedral
mesh** for the address space, not a lat/lon grid. Reasons:
- lat/lon has the pole singularity — cells at the pole are
  degenerate.
- Icosahedral cells are roughly equal-area, which makes
  content distribution (biomes, POI density, mob density)
  uniform.

The icosahedron starts at 12 vertices / 20 triangular faces
/ 30 edges. We subdivide: level 0 = 20 faces, level 1 =
80 faces, level 2 = 320 faces, … Each subdivision doubles
the face count. At level 7 we have **20 × 4^7 = 327,680
faces**, edge length ~62m on an Earth-sized planet. **One
icosahedron subdivision level ← one chunk size.**

The icosahedral mesh *is* the address space. Each face
(further subdivided) is one chunk. Cell address = `(face_id,
subdiv_level, sub_triangle_id)`. This is what we hand to the
geometric addressing layer (NSC-9 axis `001-099`).

### 3.4 y / alt — vertical axis

Both shapes have a vertical axis (planar `y`, spherical
`alt`). We treat vertical as a separate axis from the
horizontal address cell. A chunk at `(x_cell, y_layer,
z_cell)` (planar) or `(face_id, alt_layer)` (spherical)
holds its full vertical extent as a single value tree.

Why split? Most queries are horizontal (AOI, pathing,
biome). Treating vertical as a separate dimension lets us
do "all entities at this lat/lon, any altitude" cheaply.

### 3.5 Bounds, edge cases, wrap

- **Planar:** bounds are explicit. Out-of-bounds = no chunk
  loaded = fall through to "void" / kill plane. We *can*
  add wraparound (`x % width`) but the default is hard edge.
- **Spherical:** lat is bounded [-90°, 90°] in micro-degrees.
  Lon wraps [0, 360°). When a player crosses the antimeridian,
  the chunk address wraps; the state tree handles this by
  aliasing: both `(lon = 359.9°)` and `(lon = 0.1°)` map to
  the same chunk (we use modular addressing on lon). The
  projection function returns the canonical address.

### 3.6 Scale math (planar)

| Map | Area | Chunks (64m) | Hot @ 1% | All-hash total |
|---|---|---|---|---|
| Village (demo) | 1 km² | 244 | 2-3 | 8KB |
| Small region | 25 km² | 6,100 | ~60 | 200KB |
| Open world | 200 km² | 48,800 | ~500 | 1.6MB |
| Huge world | 10,000 km² | 2.4M | ~24K | 80MB |

(Note: `200 km²` was the original target; `200 km × 200 km
= 40,000 km²` is the alternate interpretation. PRD §4.5
leaves it open. We'll set it at 200 km² in the sense of
*playable area*, not total world disk. This becomes a
config-time choice.)

### 3.7 Scale math (spherical)

For an Earth-sized planet (radius 6,371 km), at icosahedral
subdivision level 7 (edge length ~62m):
- Faces: 327,680
- Surface area per face: ~488,000 m² ← 0.49 km²
- Total surface: 510M m² = 510M km² (Earth is 510M km²,
  math checks out).
- Hot @ 1% = 3,277 faces in RAM.
- All-hash total: 327,680 × 32 bytes = 10.5MB.

For a smaller game-scale planet (radius 100 km, surface
~125,000 km²), level 5 subdivision (edge ~250m) gives
~5,120 faces. **Both work.**

### 3.8 The world metadata

`WorldManifest` (lives in coordinator; read by all shards on
boot, cached):

```yaml
world_id: "synmergia_prime"
shape: "planar" | "spherical"
chunk_size_m: 64
vertical_layers: 8
planar:
  bounds_min: [0, 0, 0]
  bounds_max: [14000, 0, 14000]  # 14km × 14km = 196 km²
spherical:
  radius_m: 6371000
  subdivision_level: 7
seed:
  world_seed: <int64>
  world_version: 1
  generation_rules_version: 1
shards:
  - id: "shard_1"
    spatial_partition: [0, 0, 7000, 0, 7000]   # planar AABB
    spatial_partition: [lat_min, lon_min, lat_max, lon_max]  # spherical
```

### 3.9 V1 world spec (decided 2026-09-05)

Decisions for the v1 dev/alpha/beta world:

- **Shape**: spherical (with planar support compiled in
  for future worlds).
- **Planet radius**: 20 km.
- **Surface area**: ~5,000 km².
- **Landmass**: one continent, ~150 km², containing all
  biome variety for testing. The rest is ocean (intentional,
  for future boat/ship mechanics and to test spherical
  wrap-around).
- **Capital city**: at the geographic center of the
  continent. New players start here.
- **Biome layout** (within ~5 km radius of the capital):
  - North: forest (tutorial zone, starter mobs).
  - East: plains + farmland (starter quests, low-level).
  - South: lake + river system (fishing, water mobs).
  - West: mountain ridge (mining, mid-level mobs).
  - Coastline (where the continent meets the ocean): harbor
    district in the capital, fishing village, shipwright.
  - One dungeon entrance ~3 km from the capital (instance
    portal test).
  - One PvP arena on a small island ~6 km offshore
    (instance portal test for arena-style content).

### 3.10 V1 chunk math

At planet radius 20 km, surface area 5,000 km², subdivided
to subdivision level 5:
- Faces: 20 × 4^5 = 20,480 faces.
- Average edge length: ~250m.
- Total face area: ~244,000 m² ≈ 0.24 km² per face.
- Hot @ 1% = 205 faces in RAM.
- All-hash total: 20,480 × 32 bytes = 655KB.

Smaller subdivisions (level 6, level 7) for denser areas
like the capital. The icosahedral mesh supports mixed
subdivision levels — the capital's neighborhood gets
higher resolution than the empty ocean.

### 3.11 Scaling path (v1 → v2+)

The v1 world is configured by `WorldManifest`. Scaling up
is a config change, not a code change:

| Version | Planet radius | Landmass | Use |
|---|---|---|---|
| v1 (dev/alpha/beta) | 20 km | 150 km² continent | Active development |
| v2 (soft launch) | 100 km | ~3,000 km² | More room, more variety |
| v3 (full launch) | 1,000+ km | full planet surface | "Earth-like" planet |

Each step is `WorldManifest` + new generation-rules
version. Old players keep their old-world snapshots; new
players get the new world. **Same code, different config.**

### 3.12 Why spherical as default for v1

The user chose spherical for v1 with planar support. The
reasons we agreed:

1. **Spherical exercises the harder math first.** If the
   icosahedral projection, the antimeridian wrap, and the
   mixed-subdivision-level logic work on a 20 km planet,
   they work on a 1000 km planet. Starting small lets us
   shake out the bugs cheaply.
2. **Planar is a degenerate spherical case.** A planar
   map is a small patch on a very large sphere. We can
   always flatten; going the other way is harder.
3. **The "planet that has a continent" framing is natural.**
   Players understand "you're on a small planet with one
   big landmass". Easier to author than "you're on a
   square 14×14 km of land that happens to be flat".
4. **The geometric-addressing payoff lands on day one.**
   The icosahedral mesh is where NSC-9 + icosahedral
   geometry pays off most. Starting spherical means we
   test the geometric layer on day one, not as a retrofit.

Planar remains fully supported (the engine compiles both
paths; the world manifest chooses). Future "flat" worlds
(arenas, special maps) are trivial — small AABB regions
on an effectively-infinite plane, with the same chunk
system.

---

## 4. Seed-state model: the recursive view

The seed is the recipe; the state is what changed since
the recipe was last applied. **Every node in the state
tree carries both** — a *seed* (how to regenerate the
procedural part) and a *state* (the mutable part). The
seed and state compose recursively up and down the tree,
from the world to a stick on the ground.

### 4.1 Two orthogonal axes

A seed has two independent attributes
(D025, D026):

| Axis | Values | Question it answers |
|---|---|---|
| **Seed type** | `locked` / `open` / `frame` | How is the seed generated, stored, and disposed? |
| **Visibility scope** | `world` / `shard` / `instance` / `player` | Who can see the result? |

The two axes are orthogonal. A seed can be
`locked + world`, `open + instance`, `frame + player`,
and so on. Some combinations are nonsensical
(`frame + world` doesn't make sense), but most are
valid.

This is a substantial upgrade from the original
"four scopes" model: that model conflated *who sees*
(visibility) with *how the seed works* (type). The
two are different concerns and benefit from being
named separately.

### 4.2 The recursive seed chain

The seed chain descends from the world seed to
every leaf. At every level, the node has both:

- A **seed** — the generative rule. Derivable from
  the parent's seed + this node's path segment.
- A **state** — the mutable current values.

```
world_seed  →  world (procedural: shape, manifest)
   │
   └─ shard_seed = derive(world_seed, "shard_1")
         │
         └─ shard (procedural: terrain, biomes)
            │
            └─ chunk_seed = derive(shard_seed, "chunk:64:128:256", "terrain")
                  │
                  └─ chunk (procedural: terrain mesh)
                        │
                        └─ entity_seed = derive(chunk_seed, "entity:abc")
                              │
                              └─ entity (procedural: stick on ground)
                                    │
                                    └─ sub_state (mutable: stick broken?)
```

**The key insight:** the seed chain is *fully
derivable* from `world_seed + path`. The state
chain is *mutable*. The two compose. When a
player walks into a chunk, the server:

1. Computes the seed chain (cheap, deterministic).
2. Reads the state for each node.
3. Hands the merged result to the client.

The state tree's diff (§5.6) becomes a *state-only*
diff — the seed chain is recomputable, so diffs
only carry state changes. This is a significant
diff size reduction: most nodes are unchanged, so
the diff is mostly `(path, "unchanged", new_hash)`
entries — 32 bytes per node, no value bytes.

### 4.3 Seed types: locked, open, frame

Three seed types (D026), orthogonal to
visibility scope (4.4):

**`locked`** — Persistent, regenerable. Lives in
the manifest. Has a stable identity across boots.

Examples: the world map; a shard's terrain; a
guild hall; a player's house location.

Storage: a `locked` seed is part of the
`WorldManifest`. It's regenerated when generation
rules change (a `generation_rules_version` bump)
or when a season ends. A "winter world" is the
same `world_seed` with a `season:winter`
parameter; the rules version bumps, and the
procedural output reflects winter.

Regen trigger: `manifest_bump`, `season_change`,
`operator_action`. The seed itself doesn't
change; what changes is the *parameter set* that
the procedural function reads.

**`open`** — Per-instance, ephemeral. Derived on
demand. Not persisted.

Examples: a dungeon run; a PvP arena match; a
random encounter; a one-shot quest instance.

Storage: an `open` seed is *never* persisted.
It's derived from `(parent_seed, instance_id)` on
demand and discarded when the instance ends. The
instance's *state* (mob health, party progress) is
persisted; the seed is just the recipe.

Regen trigger: `instance_start`. The seed is
recomputed each time. The same `(parent_seed,
instance_id)` always gives the same seed
(determinism), so a dungeon for run 42 has the
same layout for every player who enters it.

**`frame`** — Bounded, per-event. A generation
frame is a procedural experience with its own
internal seed scope.

Examples: a dream sequence; a tutorial; a jail
cell; a vision quest; a hallucination.

Storage: a `frame` seed may or may not be
archived. A *training* frame (tutorial) is
deterministic per player, derived from
`(player_seed, frame_id)`, and doesn't need
archiving. A *lore* frame (a vision quest that
becomes part of the player's story) might be
archived into the player's persistent state as
a "remembered" entry.

Regen trigger: `frame_start`. The seed is
recomputed for each frame instance. The frame's
*outcome* (the player learned skill Y) is
persisted as state; the frame's *content* is
procedural and doesn't need to be replayed.

**The jail example (your lol):** a player's jail
cell is a `frame + player` seed. The cell layout
is procedural from `(player_seed, "jail", cell_id)`.
The cell is deterministic for that player
(reproducible for review). The cell is not
persisted as state — what is persisted is
"player X is in jail until T" (a state entry on
the player node, not on the cell node).

### 4.4 Visibility scopes

Four visibility scopes (D026, the second of
the two orthogonal axes), orthogonal to seed
type (4.3):

**`world`** — visible to everyone on every
shard, forever. Examples: the world manifest;
the season; the rules version.

**`shard`** — visible to everyone on this
shard, forever (until reset). Examples: shard
terrain; shard mob spawns; shard world events.

**`instance`** — visible to everyone with
access to this instance. Examples: dungeon
layout for run 42; arena match 7; party
instance state.

**`player`** — visible to just this player.
Examples: drop tables; personal loot rolls;
nicknames; remembered frames; personal house
interior.

**A note on "open" and "instance":** the
`open` seed type and the `instance` visibility
scope are commonly paired (a dungeon run is
`open + instance`) but not the same. A
`locked + instance` is a public dungeon that
exists once and never changes (e.g. a raid
boss lair with fixed layout). A `frame +
instance` would be unusual (a frame that's
shared by an instance) but is theoretically
valid.

### 4.5 The cross-product (which combinations are valid)

| | `world` | `shard` | `instance` | `player` |
|---|---|---|---|---|
| **`locked`** | World map, season | Shard terrain, POIs | Public dungeon (fixed) | Personal house (location) |
| **`open`** | (rare; world-event per shard?) | (rare; per-shard event?) | Dungeon run, arena match | (rare; per-player random event?) |
| **`frame`** | (unusual) | (unusual; cutscene per shard?) | (rare; per-instance vision?) | Dream, tutorial, jail cell |

**Bold = common. The diagonal is the most
common pattern; off-diagonal is rare but valid.**

The off-diagonal cases are interesting:

- **`locked + world`**: the world map. Stable
  identity, everyone sees.
- **`locked + shard`**: per-shard terrain. Stable
  per shard, everyone on that shard sees.
- **`open + instance`**: a dungeon run. Ephemeral,
  only the party in that run sees.
- **`frame + player`**: a dream or tutorial.
  Procedural per player, only that player sees.
- **`locked + instance`**: a public dungeon with
  fixed layout. Stable identity, only the
  instance's players see.
- **`open + shard`**: a per-shard event that's
  recomputed each time it fires (e.g. a world
  boss spawn that rolls a different mob each
  trigger).

The matrix is the spec; we don't need to
enumerate every cell. New region types fill in
the cells as they're designed.

### 4.6 The node schema

Every node in the state tree carries its seed
(or its derivation rule) AND its state:

```yaml
StateNode:
  path: ["world", "shard_1", "chunk_64_128_256", "entity_abc"]
  seed:
    type: "locked" | "open" | "frame"
    visibility: "world" | "shard" | "instance" | "player"
    derivation:
      parent_path: ["world", "shard_1", "chunk_64_128_256"]
      rule: "hash" | "concat" | "fold"
      salt: String | null
    value: int64
  state:
    # mutable, freeform — schema per node type
    position: {x: float, y: float, z: float}
    health: int
    ...
  hash: <SHA-256>
```

**The seed fields** are: the type (locked/open/
frame), the visibility (world/shard/instance/
player), the derivation rule (how the seed was
computed from the parent's seed), and the value
(64-bit int).

**The state fields** are: whatever the node
type needs. The state is freeform — there's no
schema for it at the tree level. The node type
defines the schema.

**The hash** is `SHA-256(canonical_encoding({seed,
state}) || parent_hash)`. Including the parent
hash gives the Merkle property: change any leaf
anywhere, the root hash changes.

**Hash function discipline:** SHA-256 is
mandatory for state tree content addressing —
collision resistance is load-bearing here
(we use the hash as a content-addressable
identifier). xxhash3 (or fnv-1a) is acceptable
for *derived seeds* (the `chunk_seed` for a
chunk's RNG), where we only need good
distribution, not collision resistance. Don't
swap the two.

### 4.7 Worked example: the stick on the ground

The user-suggested example that surfaced the
recursive view. Walking through it:

1. **`world_seed = 0xABCD1234...`** (locked,
   world visibility). Lives in the manifest.
2. **`shard_1_seed = derive(world_seed,
   "shard_1") = 0x12345678...`** (locked, shard
   visibility). Stored in the shard manifest.
3. **`chunk_64_128_256_seed = derive(shard_seed,
   "chunk:64:128:256", "terrain") = 0x5678...`**
   (locked, shard visibility). Stored at the
   chunk node.
4. **`entity_stick_seed = derive(chunk_seed,
   "entity:abc123") = 0x9ABC...`** (locked,
   shard visibility). Stored at the entity node.
5. **Procedural content from the seed chain:**
   the stick exists at position (X, Y, Z),
   pointing at angle θ, made of oak wood. This
   is *derivable* from the seed chain; the
   client can recompute it.
6. **State at the entity node:** the stick is
   broken (player hit it), belongs to chunk
   64_128_256, last updated at server tick T.
   The state is *mutable*; only changed fields
   are persisted in the state tree.
7. **Hash at every level:**
   `SHA-256(canonical({seed, state}) ||
   parent_hash)`. The stick's hash includes the
   chunk's hash, which includes the shard's
   hash, which includes the world's hash.

**When a player walks into the chunk:** the
server reads the chunk node from L0, walks
down to the entity node, recomputes the seed
chain (cheap), reads the state, and hands the
merged result to the client. The client
verifies by recomputing the hash and comparing
to the server's.

**When a player breaks the stick:** the server
updates the entity node's state (broken=true,
last_actor=player_id, tick=T). The hash
changes. The state tree re-roots. The diff
emits `(path, "set", new_hash, {state
bytes})` to subscribers. The seed chain is
*unchanged* (the stick's procedural identity
is the same; only its state changed).

**When a player *moves* a stick:** the stick's
position becomes state. The procedural position
is overridden. The hash covers both the seed
(unchanged) and the new state (changed). Two
sticks with the same seed but different
positions have different hashes — correctly so.

### 4.8 Shard parameters: the small, region-keyed KV layer

A shard has state that:
- *Affects generation* (e.g. "boss X defeated"
  changes which mobs spawn).
- Is *small* (KB per shard, not GB).
- *Doesn't change often* (slow-changing flags,
  not per-tick state).

This state needs to be *persisted* (it's not
derivable from the seed alone) but shouldn't
clutter the state tree. The solution: a
**shard parameter layer** — region-keyed KV
stored in the state tree under
`/shard_<id>/parameters/<region_id>/<key>`.

**Properties:**
- Region-keyed (each parameter belongs to a
  region, partition inherited from plan §8).
- Flywheel-coalesced writes (the parameter
  write piggybacks on the next shard snapshot,
  unless the shard is hot — then it goes
  through immediately, see D024).
- 5-minute heartbeat (under entropy 0, the
  parameter write still fires every 5 min as
  part of the snapshot, so no staleness beyond
  that window).
- Cluster rollup (the coordinator asks each
  shard for its last-seen timestamp every
  minute; if a shard is >10 min stale, alarm).

**Examples:**
- `parameters/zones/Z7/boss_dragon_killed: true`
- `parameters/zones/Z3/tower_destroyed: true`
- `parameters/zones/Z7/spawn_rate_modifier: 0.5`
- `parameters/global/siege_active: false`

**When a parameter changes:** the server
invalidates the affected region's content
hash. The next chunk request in that region
re-generates from the new parameter + the
unchanged seed chain.

**When a parameter reads:** the procedural
pipeline reads the parameter, applies it to
the generation function, and produces content.
The content hash reflects both the seed and
the parameter.

**Cost:** a shard has ~50 regions, ~10
parameters per region = 500 parameters per
shard. At 100 shards = 50,000 parameters.
Storing in Redis: ~5 bytes per key × 50,000
= 250KB total. Trivial.

**The line between parameters and state:**
parameters are *generation inputs*; state is
*gameplay outcomes*. "Boss killed" is a
parameter (it affects what spawns next).
"Mob health 50/100" is state (it's the current
gameplay state). The boundary is: if the value
would change a procedural output, it's a
parameter; if it's the result of gameplay, it's
state.

### 4.9 What's NOT seeded (and what goes in the state tree)

Some things are not deterministic across
clients — they're authoritative server state,
broadcast to clients:

- Current mob health, position, target.
- Active projectiles, AoE effects.
- Player inventory contents (after binding).
- Chat messages, party state, recent damage log.
- Active world event status (the event
  *template* is seeded, but its current state
  is authoritative).
- Player-placed content (per D009, ankhs,
  guild halls, signs, crops — these are state,
  not seed).
- Shard parameters (§4.8) — they're state
  too, just a special small-KV kind.

These all go through the state tree as
mutable nodes. The seed chain still applies
(procedurally-generated nodes have a seed),
but the state is authoritative.

### 4.10 Seed versioning and regen

When we change generation rules (e.g. add a
new biome, fix a heightmap bug), we bump
`generation_rules_version`. Chunks generated
under old rules keep their hash (so clients
can still prove they have the right chunk),
but new regions use the new version.
Mixed-version regions are fine as long as the
boundary is at a chunk edge.

If we need to invalidate a region (e.g. seed
was leaked), we bump a `seed_epoch` counter on
the world manifest. Chunks generated under the
old epoch are treated as untrusted until the
server re-emits them.

**Regen per seed type:**

- **`locked`**: regenerates on
  `manifest_bump` (rules version change),
  `season_change`, or operator action. The
  seed itself doesn't change; the *parameters*
  change (new season, new rules). The
  procedural output reflects the new
  parameters. Hashes change; old content is
  archived as `version:N` snapshots.
- **`open`**: regenerates on `instance_start`.
  Each instance gets a fresh seed. No archival
  (the seed is recomputed, never persisted).
  The instance's *state* is archived on
  instance end.
- **`frame`**: regenerates on `frame_start`.
  Each frame gets a fresh seed. Archival is
  per-frame-type: training frames (tutorial)
  are not archived; lore frames (vision quest)
  may archive the outcome as state.


## 5. The content-hash state tree

### 5.1 What it is

A persistent, content-addressed tree structure where:

- Every node has a `hash` = SHA-256 of `(canonical_encoding({seed, state}), parent_hash)`.
- Two trees with the same root hash have the same content (modulo encoding).
- `diff(old_root, new_root) -> List[(path, op, new_hash, payload)]`.
- `apply_diff(root, diff) -> new_root`.
- Server tick = re-root the tree with new state.
- Client sync = `apply_diff(my_root, server_diff) -> new_root`.

**Every node carries both a seed and a state** (§4.6).
The seed is the recipe (derivable from the parent
seed + path); the state is the mutable current
values. The hash covers both, giving us the Merkle
property: change any leaf anywhere, the root hash
changes.

**The diff is state-only** (§5.6). Because the seed
chain is recomputable from `world_seed + path`, the
diff doesn't need to carry seed changes — only state
changes and the resulting hash updates. This is a
significant diff size reduction: most nodes are
unchanged, so the diff is mostly `(path, "unchanged",
new_hash)` entries — 32 bytes per node, no value
bytes.

This is the **redis-like layer** in front of
Postgres. It's the substrate for everything else
(sync, frame services, LOD, procedural generation).

### 5.2 Tree shape

We use a **branching tree** that mirrors the data
model (world → shard → chunk → entity). The
*identity* of each node is its content hash (§5.3);
the *path* is the navigation structure used to walk
the tree. D007: state tree is content-hash, not
path-keyed — the path is *not* the identity, the
hash is.

Each node has:

- `path`: array of path segments (e.g. `["world",
  "shard_1", "chunk_64_128_256"]`).
- `seed`: the seed chain entry (§4.6) — type,
  visibility, derivation, value.
- `state`: the mutable state values.
- `value_hash`: SHA-256 of the canonical
  `{seed, state}` bytes.
- `value_ref`: pointer to where the value bytes
  live (in memory for hot, on disk for warm, in
  Postgres for cold).
- `children`: dict of name → child node.

We do NOT use a binary trie. We use a **branching
factor that matches the domain** (the natural
branching points: world → shard → chunk → entity).
This means:

```
root
├── world                  (one)
│   ├── manifest           (the WorldManifest)
│   ├── shards
│   │   ├── shard_1
│   │   │   ├── manifest
│   │   │   ├── chunks
│   │   │   │   ├── chunk_64_128_256
│   │   │   │   │   ├── terrain
│   │   │   │   │   ├── biome
│   │   │   │   │   ├── pois
│   │   │   │   │   ├── mob_spawns
│   │   │   │   │   ├── player_placed
│   │   │   │   │   └── entities
│   │   │   │   │       ├── entity_abc123
│   │   │   │   │       ├── entity_def456
│   │   │   │   │       └── ...
│   │   │   │   └── ...
```

This branching mirrors the data model (world → shard →
chunk → domain → entity). Path traversal is O(branching
depth), typically 4-6 levels deep.

### 5.3 The hash invariant

For any node N, `hash(N) = SHA-256(canonical_encoding(value) ||
hash(N.parent))`. Including the parent hash in the hash
gives us a **Merkle property**: changing any leaf anywhere
changes the root hash. This means:

- A client can prove they have "all of chunk X" with just
  `hash(chunk_X)`.
- A server can prove "the world is at version H" with just
  `hash(root)`.
- Diffs between root hashes are guaranteed correct: the
  client applies the diff, gets the new root, and the root
  hash matches the server's.

### 5.4 Canonical encoding

Values are encoded for hashing using a canonical form:

- **Numbers**: 8-byte little-endian fixed-point (or signed
  int64 with explicit decimal scaling where needed).
- **Strings**: UTF-8, length-prefixed.
- **Lists/Dicts**: sorted by key (for dicts), length-prefixed.
- **Floats**: NOT supported in canonical encoding (they're
  not bitwise-reproducible across platforms). Anything that
  needs decimals uses fixed-point int64 instead.

This is more restrictive than JSON but it's why the hash
is reproducible across platforms.

### 5.5 Storage tiers

The state tree is held in four tiers:

| Tier | Where | What |
|---|---|---|
| L0 | In-memory (RAM) | Hot chunks, current tick state, player entities |
| L1 | On-disk (local FS) | Warm chunks, last-N ticks, current snapshot |
| L2 | Redis | Tick cache, materialized intersections, session state |
| L3 | Postgres | Snapshots, root history, durable state, migrations |

Tier promotion/demotion happens automatically:
- A chunk accessed in the last 60s stays in L0.
- A chunk not accessed in 5min goes L0 → L1.
- A snapshot older than 1h goes L1 → L3.
- Materialized intersections rebuild lazily on demand.

### 5.6 Diff format (state-only, D027)

With the recursive seed-state model (§4), the diff
becomes a **state-only diff**. The seed chain is
recomputable from `world_seed + path`, so the diff
doesn't need to carry seed changes — only state
changes and the resulting hash updates.

A diff is a list of `(path, op, hash, payload)`
tuples. Operations:

- `set_state`: the node at `path` has new state
  (carries `payload` = the new state bytes).
  The seed is unchanged; the hash is recomputed
  locally by the client.
- `unchanged`: the node at `path` did not change
  state, but its parent did — so its hash
  changed. Carries `hash` only (32 bytes), no
  payload. The client recomputes by walking the
  unchanged state + the new parent hash.
- `delete`: remove the node at `path` (and its
  subtree). Used when an entity is despawned.
- `set_meta`: change metadata only (e.g.
  lod_level, last_access). No state change; no
  hash recomputation.

**Diff size math:** with 5000 entities per tick
and 50 state changes, the diff is:
- 50 × `set_state` entries (~100 bytes each with
  payload) = 5KB
- ~5000 × `unchanged` entries (32 bytes each) =
  160KB
- Total: ~165KB per tick

This is much smaller than the naive "send the
whole tree" (~5MB at 1000 bytes per entity ×
5000). The 99% reduction is the Merkle
deduplication property: most nodes don't carry
state changes, just hash updates.

Diffs are **delta-encoded** and **content-hashed**
themselves: the diff's own hash is
`SHA-256(ordered_concat(diff_entries))`. This lets
a client request "give me diff from H1 to H2" and
verify the response matches H2's root.

Wire format: see §11.6 (binary framing).

### 5.7 Tick = re-root

Every tick (configurable, default 20Hz), the server:

1. Reads the current root from L0.
2. Applies the tick's commands (player inputs, scheduled
   spawns, scheduled despawns). These update *state*
   fields, not *seed* fields. (See §4.6: seeds are
   persistent, only state changes per tick.)
3. For each node whose state changed, recompute
   the node's hash. For each ancestor, recompute
   the ancestor's hash (since the hash includes
   parent_hash, the change propagates up).
4. Computes `diff(old_root, new_root)`. The diff
   is state-only (§5.6) — most entries are
   `unchanged` hash updates, only the actual
   changes carry state bytes.
5. Emits the diff to subscribers.
6. Writes the new root snapshot to L1 (debounced; not every
   tick).
7. Periodically (every N ticks), writes a Postgres snapshot.

The tick is **the only place where authoritative state
changes**. Between ticks, the tree is read-only.

### 5.8 The `apply_diff` semantics

A client (or the server itself, when receiving a diff from
another source — coordinator, peer) calls `apply_diff(local_root,
diff) -> new_root`. The function:

1. Walks each `path` from the local root.
2. If the path doesn't exist, creates the path.
3. If the `value_hash` matches the existing hash, skip
   (already up to date).
4. Otherwise, replace the value, recompute the hash up to
   the root.
5. Return the new root.

If the resulting root hash doesn't match the expected
`new_root_hash` (the server's), the client has detected a
divergence — typically due to missing intermediate diffs.
The client requests a **full snapshot** from the server.

### 5.9 Garbage collection

Values in the tree that are no longer referenced by any
node are subject to GC. We run a **reference-counted GC**
for value bytes (each value ref-counted by nodes that
point to it) and a **generational GC** for paths (paths
not accessed in N ticks are pruned from L0 but kept in
L1+L2+L3).

### 5.10 What the tree is NOT

The state tree is NOT:
- A relational database. There's no SQL, no schema, no joins.
- A CRDT. There's no merge logic; the server is the only
  writer. **Single-writer is what makes the diff
  O(changed_nodes) and the diffs state-only.** The
  cost of multi-writer (CRDT, OT) is paid in
  complexity — we don't need it in v1. Adding CRDT
  later (D015 escalate trigger) is a contained
  upgrade, not a redesign.
- A blockchain. There's no proof-of-work, no consensus,
  no chain. The chain analogy is just the hash linking.
- A version control system. There's no branching/merging.

It's a **monotonic, hash-chained, persistent tree** — like
a content-addressed FS, but in-memory hot, on-disk warm,
Postgres cold.

---

## 6. Geometric addressing layer (NSC-9 + icosahedral + quasicrystal)

### 6.1 What this layer is for

The geometric addressing layer is an **optional index** on
top of the state tree. It does not store data; it indexes
data already in the tree. Three concrete uses:

1. **Spatial queries** — "all entities within radius R of
   point P". The geometric layer answers this in O(k) where
   k is the result set, by intersecting adjacent cells. A
   brute-force scan of all entities is O(n).
2. **AOI computation** — "which chunks touch this viewing
   frustum". The geometric layer answers this in O(faces
   on frustum) by intersecting the frustum with the
   icosahedral mesh (spherical) or grid (planar).
3. **Hierarchical aggregation** — "average mob density per
   region". The geometric layer's tree structure lets us
   pre-compute aggregations at parent cells and read them
   instead of recursing.

If the geometric layer is unavailable (turned off, crashed,
not yet migrated), the state tree is still functional. The
geometric layer is a **performance optimization**, not a
correctness layer.

### 6.2 Why icosahedral for spherical, grid for planar

The address space for spherical worlds is the icosahedral
mesh (§3.3). For planar worlds, it's a regular grid. Both
have a natural **hierarchical structure** — coarser cells
contain finer cells. We exploit this for hierarchical
queries.

| Shape | Coarsest cell | Default chunk | Hierarchical range |
|---|---|---|---|
| Planar | World (whole) | 64m cube | World → 8km → 1km → 64m → 8m (5 levels) |
| Spherical | Whole planet | ~62m triangle | Planet → ~248m triangle → 62m → ~15m (3 levels) |

### 6.3 Why "geometric addressing helps Godot specifically"

Three reasons this matters for the Godot client/server:

1. **Spatial queries are O(1) instead of O(n).** In GDScript
   (interpreted, single-threaded), an O(n) scan over 10K
   entities costs ~5ms. An O(k) intersection over the same
   10K costs ~50µs (per `iso_math.py` benchmark). That's
   100x faster.
2. **The icosahedral mesh is GPU-friendly.** A subdivided
   icosahedron produces triangular meshes that tile
   cleanly with no UV seam at the poles. We can ship a
   single mesh resource per subdivision level and use it
   for chunk rendering, AOI tests, and minimap.
3. **Hierarchical aggregation in shaders.** The same
   hierarchy that powers CPU-side queries can drive GPU
   compute/fragment shaders for things like "density of
   grass at this region" without a CPU roundtrip.

### 6.4 The geometric namespace: NSC-9

Every entity in the state tree can have an NSC-9 code that
encodes its position across multiple "axes". Each axis is
a reservation of digit space. From the existing
frame primitives design:

```
NSC-9: 9-AAA-BBB-CCCCCC
         │  │   │   │
         │  │   │   └── sequence within axis (16M)
         │  │   └────── axis reservation (1000)
         │  └────────── facility (1000)
         └───────────── NSC-9 prefix
```

Axis reservations:

- `001-099`: spatial (icosahedral vertex or planar grid cell)
- `100-199`: factional (faction_id 0-99)
- `200-299`: temporal (sub-axes: 200=year, 201=season, 202=month, …)
- `300-399`: social (per-player, per-guild, per-party)
- `400-499`: game-specific (class, level, species, …)
- `500-999`: free for new axes

### 6.5 Frame primitives: Fragmenter + SpatialFragmenter + NSC-9 Bridge

The geometric addressing layer is implemented as **frame primitives**
in `game/core/frame/geometry/` (pure functions, no state, no
autoloads, no GameManager dependency). Three modules:

#### 6.5.1 Fragmenter (`fragmenter.gd`)
Stateless data sharding via Knuth multiplicative hash
(`LATTICE_MULTIPLIER = floor(phi * 2^32) = 2654435769`).

**Core API:**
- `derive_lattice_keys(sequence: int, num_fragments: int = 5) -> Array[String]` — Derive N aperiodic lattice keys from a single sequence integer. Deterministic, base-36 encoded.
- `fragment(data: Variant, num_fragments: int = 5) -> Array[Dictionary]` — Split arbitrary data into N fragments with XOR spreading. Returns `Array` of dicts with `shard`, `data` (base64), `size`, `checksum`.
- `weld(fragments: Array) -> String` — Reconstruct original data from fragments. Reverses XOR spreading, sorts by shard, concatenates.

**Use case:** Distributed storage of large entity state across shards without a central manifest.

#### 6.5.2 SpatialFragmenter (`spatial_fragmenter.gd`)
Deterministic sub-cell addressing for icosahedral/NSC-9 spatial state.

**Address encoding (64-bit):**
- Bits 0-15:   X offset (16-bit quantized coordinate)
- Bits 16-31:  Y offset (16-bit quantized coordinate)
- Bits 32-47:  Z offset (16-bit quantized coordinate)
- Bits 48-55:  Depth (8-bit subdivision level, 0-24)
- Bits 56-63:  Face/region type (8-bit, e.g., NSC-9 spatial axis or icosahedron face)

**Core API:**
- `make_address(x, y, z, depth, face=0) -> int` — Build address
- `get_x/y/z/depth/face(address)` — Accessors
- `subdivide(address, depth=1) -> Array[int]` — Split cell into 8 children (octree)
- `get_parent(address) -> int` — Immediate coarser cell
- `is_ancestor(ancestor, descendant) -> bool` — Lineage check (cross-face returns false)
- `get_bounding_box(address) -> Dictionary` — Integer min/max bounds (`min_x`, `max_x`, etc.)
- `find_common_ancestor(addresses) -> int` — Spatial compression (cross-face = 0)
- `generate_key(address) -> String` — Fixed-width key: `%04x-%04x-%04x-d%d-v%d`
- `nsc9_code_to_vertex(code) -> int` — NSC-9 axis 1-12 -> face 0-11 (non-spatial = -1)
- `path_for_address(address) -> String` — T3 path: `spatial/%04x-%04x-%04x-d%d-v%d`
- `store_fragment_in_t3(t3, path, address, metadata) -> PackedByteArray` — T3 bridge
- `query_spatial_tree(t3, scope_path="/") -> Array[Dictionary]` — T3 query

**MAX_DEPTH = 24** prevents fragment explosion.

#### 6.5.3 NSC-9 Bridge (`nsc9_bridge.gd`)
Unified pipeline: NSC-9 spatial code -> SpatialFragmenter address -> T3 content-hash tree.

**API (10 methods):**
| Method | Purpose |
|---|---|
| `nsc9_to_address(code, depth=0)` | NSC-9 -> SpatialFragmenter address |
| `address_to_t3_path(address)` | Address -> T3 path string |
| `nsc9_to_t3_path(code, depth=0)` | NSC-9 code -> T3 path (convenience) |
| `store_nsc9_state(t3, nsc9_code, state, depth, metadata)` | Store entity state in T3 |
| `store_nsc9_fragmented(t3, nsc9_code, state, fragmenter, depth)` | Fragment + store in T3 |
| `restore_nsc9_fragmented(t3, nsc9_code, fragmenter, depth)` | Restore fragmented state |
| `query_nsc9_region(t3, nsc9_code, depth)` | Query fragments in region |
| `query_nsc9_vertex(t3, nsc9_code)` | Query all fragments on face |
| `is_spatial_nsc9(code)` | Check if code has spatial axis |
| `entity_spatial_to_vertex(facility, vertex)` | Entity spatial -> face |

**NSC-9 -> Spatial mapping:**
- `facility` -> x coordinate (0-999, fits in 16 bits)
- `axis` -> face via `SpatialFragmenter.nsc9_code_to_vertex` (1-12 -> 0-11)
- `sequence` -> split into y (bits 10-19) and z (bits 0-9)
- `depth` -> subdivision depth (caller-specified)

**Service integration:**
- **EntityService**: `_nsc9_bridge` initialized, caches NSC-9 codes in `_entity_nsc9_codes`, sets `metadata.nsc9_code`
- **ZoneManager**: `_nsc9_bridge` initialized, derives zone NSC-9 codes, exposes `get_zone_nsc9_code()` and `get_zone_nsc9_t3_path()`

**Tests:** `test_nsc9_bridge.gd` (9 integration tests), `test_spatial_fragmenter.gd` (11 tests), `test_fragmenter.gd` (fragmenter tests). Run with `godot --headless --path . --script res://core/frame/geometry/test_nsc9_bridge.gd`.

### 6.6 Multi-axis intersection = materialized views

The Julia orchestrator already implements set-intersection
across axes. The plan is:

1. **Project every entity** onto all relevant axes at spawn
   time. The projection is content-hashed (entity's hash
   includes its axis codes), so we can detect corruption.
2. **Materialize the hot intersections** (LRU cache, bounded
   size). "What entities are at this icosahedral vertex
   AND in this faction AND updated in the last 5 ticks?"
   = one cached entry per `(vertex, faction, time_bucket)`
   combo.
3. **Invalidate cache entries** when entities change
   axis membership (e.g. a player joins a faction, or
   moves to a new vertex).

The cache lives in Redis. The Julia orchestrator queries
Redis directly; the Godot game server queries the
orchestrator over its existing HTTP bridge
(`MultiIsoService`).

### 6.6 What does this buy us?

For the world's hot operations:

| Operation | Without geo layer | With geo layer |
|---|---|---|
| "Enemies in this AABB" | O(n) scan of all entities | O(k) intersection over spatial axis + filter |
| "Players in faction X" | O(n) scan of all players | O(1) lookup on faction axis |
| "Density of mobs at chunk C" | Iterate mobs in C | Read precomputed aggregate |
| "Chunks in frustum" | Test each chunk AABB vs frustum | Walk the icosahedral tree |
| "Who is at this POI" | Linear search through POIs | Spatial index lookup |

For a 200km² world at 1% hot = ~6,400 chunks, each holding
~50 entities avg, the difference is:
- Scan: 320K entity tests per query
- Intersection: ~50 entity tests per query (intersect
  produces the actual answer; prefilter cuts to ~200
  candidates before refinement)

### 6.7 The cost we accept

The geometric layer costs us:

- **Projection cost** at spawn: O(axes_used). ~1µs per axis
  in pure GDScript, ~100ns in Julia. For 1000 entities
  spawning per minute, this is sub-millisecond.
- **Cache memory**: each cached combo is ~1KB. With 10K
  combos in cache = 10MB. Trivial.
- **Cache invalidation complexity**: when an entity moves
  to a new vertex, we have to remove it from the old
  vertex's set and add to the new. This is fine for
  infrequent moves; for high-frequency moves (every tick),
  we batch the updates.
- **Maintenance burden**: another module to ship, test, and
  keep in sync with the state tree.

The break-even is around **500 entities per query**. Below
that, the scan is faster than the cache lookup. The LOD
manager and predictive prefetcher should ensure we don't
issue queries below the threshold.

### 6.8 Quasicrystal extension (optional, for the future)

A **quasicrystal** is a structure with long-range order
but no translational periodicity. For world-tiling, this
matters because:

- **No seams.** Periodic tilings (squares, hexagons) have
  visible boundaries when rendered. Quasicrystalline
  tilings (Penrose, Ammann-Beenker) have no such
  boundaries.
- **Multiple scales.** Quasicrystalline tilings have
  naturally multi-scale structure, which composes well
  with hierarchical aggregation.
- **Better space-filling.** Quasicrystals fill space more
  uniformly than cubes or hexagons (no anisotropy).

The catch: **quasicrystals are harder to implement and
harder to reason about**. The Penrose tiling requires
matching rules; quasicrystal addressing is more complex
than grid addressing.

**Recommendation:** defer quasicrystal to a later phase.
Start with icosahedral + grid. Add quasicrystal only if
the visible-seam problem becomes user-noticeable.

### 6.10 Phasing

| Phase | Geometric layer scope |
|---|---|
| Phase 1 (now) | Grid (planar) only. No icosahedral. No Julia. State tree + Redis + Postgres. |
| Phase 2 | Icosahedral for spherical worlds. Julia sidecar for multi-axis. NSC-9 codes per entity. |
| Phase 3 | Materialized intersection cache. Predictive prefetch via Markov. |
| Phase 3.x | Vant fragmenter implementation (`fragmenter.gd`), SpatialFragmenter, and NSC-9 bridge wired into EntityService + ZoneManager. **Status: DONE** |
| Phase 4 | Quasicrystal experimental layer (if seams matter). |

**Phase 3.x (completed):** Fragmenter, SpatialFragmenter, and NSC-9 bridge are implemented and wired into EntityService + ZoneManager. The bridge provides the unified NSC-9 -> SpatialFragmenter -> T3 path. See `labs/prd-geometry.md`.

---

## 7. Procedural generation

### 7.1 The contract

Procedural generation is a **pure function** of `(parent_seed,
chunk_address, generation_pass) -> content`. No side
effects, no hidden state. Two clients with the same parent
seed compute the same content for the same chunk.

This is the only contract. Everything else (which passes
run in which order, which LOD triggers which pass, which
content is hand-authored vs generated) is built on top.

### 7.2 Generation passes (the ordered pipeline)

A chunk's content is built up by running passes in order.
Each pass reads the parent seed and the chunk address,
computes a derived seed, and writes a portion of the
chunk's content into the state tree.

| Pass | Output | When |
|---|---|---|
| 0. `terrain_height` | Heightmap (height values per sub-cell) | LOD 0 (full) |
| 1. `terrain_shape` | Mesh geometry, normals, materials | LOD 0 |
| 2. `biome` | Biome assignment per sub-cell | LOD 0 |
| 3. `hydrology` | Rivers, lakes, ocean | LOD 0 (depends on terrain_height + biome) |
| 4. `roads_and_paths` | Hand-authored roads + procedural dirt paths | LOD 0 (roads are content; paths are derived from heightmap + POI graph) |
| 5. `poi_placement` | Towns, dungeons, vendors, landmarks | LOD 0 (depends on biome + hydrology) |
| 6. `mob_spawns` | Where mobs spawn in this chunk | LOD 0 (depends on biome) |
| 7. `resource_nodes` | Ore, herbs, wood spawns | LOD 0 (depends on biome + terrain) |
| 8. `npc_vendors` | Vendor placement (subset of poi) | LOD 0 |
| 9. `narrative_anchors` | Quest hooks, lore fragments | LOD 0 |

Each pass's output is content-hashed. A client that has
passes 0-5 can render the chunk but won't have mobs until
pass 6 is loaded. The state tree path for each pass is
independent (`chunk.path.terrain`, `chunk.path.biome`,
etc.), so passes can be loaded on demand.

### 7.3 LOD-triggered ordering

Not all passes are needed at all LOD levels:

| LOD | Passes loaded |
|---|---|
| LOD 0 (full, ~64m chunk) | 0-9 (all) |
| LOD 1 (summary, ~256m group) | Aggregate of passes 2 (biome), 5 (poi count), 6 (mob count). No terrain mesh. |
| LOD 2 (cold, ~2km group) | Aggregate of passes 2, 5, 6 (coarser). No POI names, no exact counts. |
| LOD 3 (archived, ~20km group) | Just the parent biome and rough POI type (city vs. / dungeon / wilderness). |

A LOD-2 chunk is a **summary** — "this is forest, has 2
POIs, moderate mob density". A LOD-3 chunk is just "this
is forest". Aggregation rules are deterministic.

### 7.4 Hand-authored vs generated

Most content is generated, but some is hand-authored and
**overrides** the procedural output:

| Content type | Source |
|---|---|
| Terrain heightmap | Generated (pass 0) |
| Biome | Generated (pass 2) |
| Roads | Hand-authored (overrides pass 4) |
| Towns (village_center, etc.) | Hand-authored (overrides pass 5) |
| Dungeons (procedural layouts) | Generated (pass 5) |
| Dungeon templates (the "kit") | Hand-authored |
| Mob spawns | Generated (pass 6) |
| Named NPCs (bosses, vendors) | Hand-authored (overrides pass 5/8) |
| Resource nodes | Generated (pass 7) |
| Quests | Hand-authored (referencing procedural hooks from pass 9) |

The override is itself content-hashed: a hand-authored
override at `chunk.path.overrides.town_center` replaces
the procedural output at `chunk.path.pois.town_center`.
The client/server can tell which content is which by the
path.

### 7.5 Generation triggers

When does a pass run?

| Trigger | Passes run | By whom |
|---|---|---|
| Server boot | 0-9 for chunks within spawn-load radius | Server |
| Player enters AOI of unloaded chunk | 0-9 for that chunk | Server (LOD promotion) |
| Predictive prefetch fires | 0-9 for predicted chunk | Server (background) |
| Designer previews chunk in editor | 0-9 for chunk | Editor tooling |
| Mob respawn timer expires | 6 (re-roll mob spawns for existing terrain) | Server |
| World event starts | 5 (new POI placement) | Server |
| Player places an ankh | New node at `chunk.path.player_placed.ankh` | Server (validated command) |
| World reset / shard restart | Re-run 0-9 for chunks | Server |

### 7.6 Determinism: same seed → same chunk

If two servers with the same `world_seed` and
`generation_rules_version` generate chunk `C`, the output
is **bit-identical**. We verify this in tests:

```
test: deterministic_chunk_gen
  seed1 = 12345
  seed2 = 12345
  chunk_a = generate(seed1, "chunk_64_128_256", "world")
  chunk_b = generate(seed2, "chunk_64_128_256", "world")
  assert hash(chunk_a) == hash(chunk_b)
```

This is the gate before any client work begins. Without
it, the "same world for everyone" promise is broken.

### 7.7 What can break determinism

Watch out for:

- **Floating-point math** in noise functions. Two platforms
  compute `sin()` differently at the bit level. We use
  integer-based noise (PCG + custom hash mixing) where
  possible, or accept the platform delta and hash the
  result (so two platforms see the same hash for "their"
  noise, which is wrong).
- **Iteration order of hashmaps/dicts.** We sort by key
  before hashing.
- **Thread scheduling.** Generation is single-threaded for
  determinism; parallelism happens at the chunk level, not
  within a chunk.
- **Time-dependent RNG.** Anything that uses wall-clock time
  to seed is forbidden. All RNG seeds from the seed chain.
- **External data lookups that aren't deterministic.**
  E.g. fetching a row from Postgres that may have changed.
  Generation must be a pure function of the seed and the
  hardcoded rule set; it cannot look up mutable external
  state.

### 7.8 Generation rules versioning

When we add a new biome or fix a heightmap bug:

1. Bump `generation_rules_version` in `WorldManifest`.
2. Chunks generated under the old version keep their hash
   (immutable; we never regenerate them).
3. New chunks use the new version.
4. Mixed-version regions are fine at chunk boundaries;
   the LOD manager knows which version a chunk was made
   under and only merges compatible neighbors.

If a chunk was generated under old rules but is now
considered "wrong" (e.g. mob density too high), the fix is
to bump `generation_rules_version`, not to overwrite. Old
players who have the chunk hash cached keep seeing the old
content; new regions use the new rules.

### 7.9 Designer control points

Designers override procedural output by writing files:

- `world/overrides/<shape>/<chunk_addr>/town.tres` — replaces
  `chunk.path.pois.town` for that chunk.
- `world/overrides/<shape>/<chunk_addr>/biome.tres` — replaces
  `chunk.path.biome`.
- `world/overrides/spawn_points/<zone_id>.tres` — replaces
  SpawnService data.

The override system is content-hashed and diffable. A
designer's override file change is a normal diff in the
state tree, not a special path.

### 7.10 Procedural vs content pipelines

We have two pipelines:

- **Procedural pipeline**: `(seed, address, pass)` → content.
  Runs at LOD promotion. Pure. Re-runnable.
- **Content pipeline**: `*.tres` files → `Resource` objects
  → values in the state tree. Runs at deploy + at content
  edits. Has its own hash (the file content hash).

Both pipelines write into the same state tree. The
designer can mix: "this chunk is mostly procedural, but
the town in it is hand-authored" is a totally normal
configuration.

### 7.11 What we DON'T procedurally generate

Some content stays hand-authored forever because it's
either:
- **One-of-a-kind** (main storyline, signature boss
  mechanics).
- **Requires human judgment** (quest text, voice lines,
  cinematic scripts).
- **Has external dependencies** (art assets, sound files).

These go through the content pipeline only, not the
procedural pipeline.

### 7.12 Hierarchical instancing (the single biggest win for procedural worlds)

Procedural worlds have lots of **repetition with
variation**: 1000 oak trees in a forest, 500 houses in a
city, 200 rock formations in a mountain, 50 mob spawns of
the same type in a region. Each one is a distinct entity,
but they share a type.

The naive state-tree representation stores every entity
fully:

```
chunks.chunk_X.entities
    ├── oak_1 { type, position, rotation, scale, health, ... }   ~500B
    ├── oak_2 { type, position, rotation, scale, health, ... }   ~500B
    ├── ... 998 more oaks
    ├── rock_1 { ... }                                           ~500B
    ├── ...
```

For a forest of 1000 oaks, that's ~500KB. The state tree
hashes, diffs, and broadcasts all of this every tick the
forest changes.

**Hierarchical instancing** separates the **type** (shared,
immutable) from the **instances** (per-entity transforms
- dynamic state):

```
chunks.chunk_X.types
    └── oak_common_v1          # full type definition, hashed once
chunks.chunk_X.instances
    ├── oak_instances
    │   ├── type: oak_common_v1
    │   ├── transforms: [
    │   │   [x, y, z, rot, scale],   # 5 ints = 40 bytes
    │   │   ...
    │   │   # 1000 entries = 40KB
    │   │ ]
    │   └── dynamic_state: {
    │       # only things that change at runtime
    │       # (none for a tree)
    │     }
    └── rock_instances
        └── ...
```

The chunk's content hash now includes both the type
definitions AND the instance list. Two chunks with the
same type + the same instance positions hash to the same
value — meaning **identical forests across the world can
dedup at the chunk level** (if you have the same forest
in two regions, both chunks content-hash to the same
thing if the type + transforms match; the world state tree
keeps the pointers but the *payloads* deduplicate via
content-hash).

#### 7.12.1 What gets instanced

| Category | Instanced? | Notes |
|---|---|---|
| Trees, rocks, plants, decorations | YES | Pure transforms; no dynamic state. |
| Static buildings (untouched houses) | YES | Transforms + variant ID. |
| Mob/NPC spawn points (templates) | YES | The *spawn point* is instanced; the live entity is not. |
| Resource nodes (ore, deposits) | YES | Respawn timer per node. |
| Player-placed decorations | NO | Each is unique (different owner, different metadata). |
| Houses with active players inside | NO | Dynamic state (who's in it, inventory). |
| Mobs (live) | NO | They move, fight, have health. |
| Players | NO | Obviously. |
| Active projectiles / AoE | NO | Short-lived, per-entity. |

The split is: **anything that's purely a transform of a
static thing** is instanced. Anything with dynamic state
is not.

#### 7.12.2 The instancing cost equation

Naive: `N × full_entity_payload`. For 1000 oaks at 500B =
500KB.

Instanced: `1 × type_payload + N × (40B transform + tiny
overhead)`. For 1000 oaks:
- Type payload: ~2KB (one oak definition).
- Transforms: 1000 × 40B = 40KB.
- Total: 42KB.

**12x reduction** for the same content. At higher N
(10,000 trees in a giant forest), it's 100x.

The state tree's content hash includes both, so dedup
still works. Two forests with the same oaks + same
positions = same chunk hash, regardless of how the
entities are stored.

#### 7.12.3 When an instance becomes dynamic

If a tree gets cut down, it transitions from "instanced
oak" to "dynamic oak-stump entity". The state tree diff:
- Remove from `instances.oak_instances.transforms` (delete
  the transform entry).
- Optionally add to `entities.fallen_oak_stump` (if we
  want the stump to persist).

This is a normal state-tree diff. Clients receiving the
diff see one fewer tree at that position. Re-render.

#### 7.12.4 LOD interaction

At LOD 1 (summary), we don't need per-tree transforms. We
need "this chunk has ~1000 oak_instances". The L1 summary
just stores `instances.oak_instances.count = 1000`. LOD 0
unpacks to transforms.

This composes with the LOD pyramid: instance count at L1,
full transforms at L0, both derived from the same source
data.

### 7.13 Async generation + pre-generation cache

Generation is CPU-bound. When a player walks into an
unloaded chunk, the server has to run passes 0-9 (or at
least 0-6 for "load enough to play"). At 10ms per chunk,
that's a noticeable hitch.

#### 7.13.1 Gen workers (Julia processes)

Generation runs in **worker threads / processes**, not the
main tick thread. The tick thread queues generation work
and gets results asynchronously.

```
tick thread:
  ...
  for chunk in newly_promoted_set:
    if chunk not in generation_cache:
      gen_queue.push(chunk_address)
  ... (tick ends)

worker:
  while not empty(gen_queue):
    chunk_addr = gen_queue.pop()
    result = run_passes(chunk_addr)
    state_tree.apply_diff(result)
```

The tick never blocks on generation. A player walking into
an unloaded chunk sees a "loading" indicator until the
worker finishes; meanwhile the player can still move (the
client predicts locally).

#### 7.13.2 Pre-generation cache (Markov-predictive)

The Markov predictor (§14.4) already predicts where the
player will be in 5s, 30s, 5min. We **pre-generate** the
chunks along the predicted path:

- Worker queue has low priority for predicted chunks
  (generates when idle).
- LRU cache: keep the last N=10,000 generated chunks.
- A chunk that's been generated but never visited can be
  evicted from cache; it will re-generate when needed
  (deterministic, so re-generation = same content).

#### 7.13.3 Lazy mesh, eager data

Generation produces **data** (heightmap, biome, POIs, mob
spawns). The mesh is a separate concern: it's pure graphics.

The flow:

1. Worker generates data (cheap: ~1ms per chunk).
2. Tick sees the data, marks it ready for rendering.
3. **Render thread / mesh worker** generates the mesh from
   the data (expensive: ~10-50ms per chunk).
4. Mesh goes into the render queue.

The player can see + interact with the data immediately
(collision, mob AI, etc. work off the data); the visual
mesh catches up a frame or two later.

This decouples the tick latency from the mesh-generation
cost. The user never sees a "hitch" from terrain mesh
building.

#### 7.13.4 Generation cost at v1 scale

For the v1 20km planet with 20,480 level-5 faces:
- Total chunks: 20,480.
- Gen per chunk (passes 0-6, eager data): ~1ms.
- Total cold generation: ~20s (single-threaded).
- With 4 workers: ~5s.
- With pre-gen cache: a player never waits >100ms (most
  chunks are pre-generated).

This is fine. Scaling up to level-7 subdivisions on a
1000km planet (327,680 chunks × ~5ms each = ~27 minutes)
will need more workers or smarter pre-gen. v1 doesn't hit
that.

---

## 8. Zone model: regions, gateways, instances, transitions

### 8.1 Zones vs chunks vs regions

Three concepts, often conflated:

| Concept | Granularity | Purpose | Lifetime |
|---|---|---|---|
| **Chunk** | 64m cube (planar) / ~62m triangle (spherical) | The state-tree's spatial unit. The LOD pyramid's smallest cell. | Permanent (content-hashed, immutable) |
| **Region** | 256m–2km group of chunks | An authoring and gameplay unit. Designers place content "in region R". The procedural generator runs per region (groups of chunks share a generation context). | Permanent |
| **Zone** | Hand-authored, gameplay-rule scope (PvP mode, level range, instance flag) | Gameplay logic that operates above the spatial grid. Where PvP rules apply, where respawn behavior is configured, where NPCs "belong". | Permanent |

A zone **covers** one or more regions. A region contains
many chunks. A chunk is the LOD unit.

### 8.2 The ZoneData schema (extended)

The current `ZoneData` (in `game/core/schemas/zone_data.gd`)
covers most of what we need. We extend it with:

```yaml
zone:
  id: "zone_forest_meadow"
  display_name: "Gloomwood Meadow"
  pvp_mode: SAFE | SPECIES_PVP | FACTION_PVP | FREE_PVP | WARZONE
  level_requirement: 1
  max_level: 15
  allowed_factions: []
  blocked_species: []

  # spatial extent
  bounds: AABB                    # planar; for spherical use cell_range
  cell_range: [face_id_lo, face_id_hi]  # spherical, optional

  # NEW: link to chunks
  region_ids: ["region_gloomwood_north", "region_gloomwood_south"]

  # respawn
  respawn_at_bind: true
  respawn_timer: 8.0
  bind_point: [0, 0, 0]

  # instance
  is_instanced: false
  instance_capacity: 0            # 0 = unlimited (open world)
  instance_seed_derivation: "world" | "shard" | "run"

  # NEW: procedural generation hints
  generation_overrides:           # paths to override files
    - "world/overrides/planar/chunk_*_*/biome.tres"

  # gameplay
  ambient_light_color: Color
  ambient_light_energy: float
  has_weather: bool
  weather_type: string

  spawn_points: Array[Vector3]
  npcs: Array[String]             # NPC IDs

  loot_multiplier: 1.0
  xp_multiplier: 1.2
```

The biggest delta is `region_ids`: a zone now declares which
regions it's composed of, and the chunk system can
auto-discover zone membership for any chunk. This replaces
the current "zone is a circle with center+radius" model
with a more flexible "zone covers regions, regions contain
chunks".

### 8.3 Why we still need zones

Zones are **gameplay-rule containers**. Chunks are spatial
units; zones are rules:

- "PvP rules in this area"
- "Level range for players here"
- "Respawn point configuration"
- "Instance scope and capacity"
- "NPCs that live here"
- "Loot and XP multipliers"

A chunk is just spatial data. A zone attaches behavior.
Multiple zones can cover the same chunk (overlapping rules;
rare but legal — e.g. an event zone layered on top of an
open-world zone).

### 8.4 Zone detection

This is the missing piece from the current ZoneManager
(per §2.1 of the audit). The fix:

**Per-tick per-player check**: For each player with a
known chunk, check the 8 neighboring chunks (and the
player's current chunk) for zone coverage. If the player's
chunk coverage changed since the last tick, fire
`player_entered_zone` / `player_exited_zone`.

This is **O(27 chunks × #1 zones covering them)** per
player per tick = ~5µs in GDScript. At 1000 players,
that's 5ms per tick. Negligible.

The check uses the **chunk → zone index** (built at zone
load time, content-hashed for cacheability) for O(1)
membership lookups.

### 8.5 Gateways

Gateways are transitions between zones (or instances of
zones). The current `GatewayRecord` is fine; we extend
the schema:

```yaml
gateway:
  id: "dungeon_forest_depths_entrance"
  from_zone_id: "zone_forest_meadow"
  to_zone_id: "zone_dungeon_forest_depths"
  to_position: [120, 0, 80]

  # NEW: instance behavior
  transition_type: "seamless" | "load_screen" | "fade"
  instance_behavior: "create" | "join_existing" | "auto_assign"
  instance_capacity: 5            # 0 = open world

  # requirements
  required_level: 10
  required_faction: ""
  required_quest: ""
  is_locked: false
  activation_radius: 3.0
```

The `instance_behavior` field is the key addition: a
gateway can `create` a new instance (party dungeon),
`join_existing` (raid finder), or `auto_assign` (free-for-all
queue). The instance seed is derived per §4.5.

### 8.6 Seamless transitions

A "seamless transition" means the player crosses a gateway
without a loading screen. Implementation:

- The destination zone is loaded into the player's LOD
  pyramid **before** the player reaches the gateway (via
  predictive prefetch, §14).
- When the player enters the gateway radius, both source
  and destination chunks are in memory.
- The transition is a state-tree diff that re-parents the
  player entity from `world.shards.shard_X.chunks.<src>...
  .<player>` to `world.shards.shard_X.chunks.<dst>...
  .<player>`. The diff also fires `seamless_transition_*
  signals`.
- The rendering on the client uses the same camera; only
  the surrounding chunks change.

### 8.7 Load-screen transitions

Some transitions are too expensive for seamless (the
player teleports across the world, the destination has
different rules, etc.). For these:

- Client sends "use gateway" command to server.
- Server validates, creates the destination instance if
  needed, gets a snapshot of the destination's bootstrap
  state (manifest + spawn chunks + nearby POIs).
- Server returns the snapshot + new entity path.
- Client applies the snapshot, swaps the world scene,
  shows a brief loading screen.
- Server emits `instance_joined(player, instance_id)`.

### 8.8 Instance lifecycle

An instance is a **scoped subtree** of the state tree:

```
world
└── instances
    ├── <instance_id_1>
    │   ├── manifest
    │   ├── seed
    │   └── chunks (live, in-memory only)
    ├── <instance_id_2>
    └── ...
```

Instances have:

- **`seed`**: derived per instance type (§4.5).
- **`manifest`**: which template, capacity, expiration, owner.
- **`chunks`**: live state, only in memory while the instance
  is active.
- **`archive`**: snapshot written to Postgres when the
  instance completes; can be replayed or queried later.

When the last player leaves an instance, the server:

1. Snapshots the instance's chunks to Postgres.
2. Emits `instance_destroyed(instance_id)`.
3. Drops the in-memory chunks.

When a player re-enters an archived instance (e.g.
re-entering a completed dungeon to farm), the server
restores the snapshot or starts a fresh run depending on
the dungeon template's policy.

### 8.9 Why zones stay in the codebase

We considered replacing zones with "just chunks and rules",
but kept zones for one big reason: **gameplay-rule
authoring is easier with named zones**. Designers think in
zones ("the Gloomwood Meadow area"), not in chunks
("64,128,256"). Zones are a layer of human-meaningful
naming on top of the spatial grid.

A designer writes `zone_forest_meadow.tres` and it's
intuitively a place. They don't write
`chunk_64_128_256.tres` for the same content.

---

## 9. Server tick model

### 9.1 Tick rate

The game-state tick is **adaptive** (D020), driven by
the shard-level flywheel (§9.14):

- **50ms (20 Hz)** when flywheel momentum > 80% of max
  (high load: combat, mob spawn, player surge).
- **100ms (10 Hz)** when flywheel is at 20-80%
  (normal traffic).
- **200ms (5 Hz)** when flywheel is < 20% (idle shard,
  no players in AOI).

Day/night, regen, and buff timers all advance per
tick — slower ticks mean slower day/night, but that's
fine on an idle shard. When players arrive, the
flywheel spins up and the rate jumps.

**Other tick rates** (independent, not flywheel-driven):

- **10 Hz** for the LOD/predictive-prefetch tick
  (every 100ms, see §9.12).
- **1 Hz** for the world-event / day-night tick
  (every 1s, see §9.10).
- **1 / 60s** for the Postgres-snapshot tick (see §9.11).

The game-state tick is the hot path; the others are
background loops.

### 9.2 The tick pipeline

```
tick_n (50ms, adaptive via §9.1):
  1. drain_input_queue()      # player commands from clients
  2. for each entity:
       - read state
       - apply input command if any
       - update AI / physics / auras
       - increment per-player flywheel sub-meters (§9.16)
  3. for each chunk in hot set:
       - process mob AI, despawns, respawns
       - apply scheduled events
  4. compute new_root_hash
  5. diff(old_root, new_root)
  6. for each subscriber:
       - filter diff to subscriber's AOI
       - queue for batch send (next 50ms boundary)
  7. increment shard-level flywheel (§9.14)
       - decay per tick (default 0.5/tick)
       - check trigger; if hot, write snapshot
  8. emit local signals (in-process observers)
  9. tick ends
```

The flywheel is updated at step 7 (after the
emission, before tick ends) so the snapshot fires
with the post-tick view. Per-player flywheels are
incremented at step 2 as the player's actions are
processed.

The **six-phase view** (from the tick model
discussion) maps onto this pipeline as:

| Phase | Pipeline step | Sync/async |
|---|---|---|
| 1. Input collection | step 1 | sync |
| 2. World step | steps 2-3 | sync |
| 3. State re-root + diff | steps 4-5 | sync |
| 4. Diff emit | step 6 | sync |
| 5. Persistence | (async, after tick) | async |
| 6. Predicted prefetch | (async, after tick) | async |

For the full 6-phase deep-dive, see
`labs/world-building-tick.md` §4.

### 9.3 Why batching matters for the browser

WebSocket over the browser means we can't blast 20 messages
per second to a client and expect good throughput. We
batch:

- Each tick produces a diff.
- Diffs are queued per-client, filtered to that client's
  AOI.
- Every 50ms (the tick boundary), the server flushes
  queued messages to all clients as a single
  **WebSocket frame** per client (binary).
- Multiple diffs can be coalesced if a client has slow
  throughput — but we never drop; we always deliver the
  most recent N ticks' worth.

### 9.4 Per-client state on the server

The server tracks per-client:

```yaml
ClientSession:
  peer_id: int
  auth_token: String
  player_id: String
  character_id: String
  connected_at: int64
  last_input_tick: int

  # AOI subscription
  aoi_center: [x, y, z]
  aoi_radius: float        # ~100m default
  subscribed_chunks: Set[String]
  interest_set: Set[String]  # entities the client cares about

  # prediction state (for reconciliation)
  last_acked_tick: int
  last_acked_root_hash: String
  pending_inputs: [ClientInput]

  # transport
  ws_handle: WebSocketPeer
  send_queue: Array
  last_send_time_ms: int
```

### 9.5 The client command queue

Clients send commands. Commands are typed:

```yaml
ClientCommand:
  tick: int                  # tick the command was issued
  type: "move" | "use_skill" | "use_item" | "interact" | "chat" | ...
  payload: bytes             # type-specific
  client_seq: int            # for ordering / dedup
  signature: bytes             # HMAC of (tick, type, payload, client_seq, secret)
```

The server:

1. Receives a command.
2. Verifies the signature (anti-cheat; see security doc).
3. Queues it for the next tick.
4. On the tick, applies it to the authoritative state.

### 9.6 Client prediction + server reconciliation

The client predicts locally for responsiveness. The server
reconciles via diff.

Client-side:

```
client_tick_n:
  1. drain input → predict next position
  2. apply predicted input to local state
  3. render
  4. when server_diff arrives for tick_k:
       - if k >= last_acked_tick:
         - apply server_diff to local state (this corrects the
           prediction)
         - update last_acked_tick
       - else: ignore (already past)
```

The server is **never** confused by prediction — it
processes the original input commands, computes the
authoritative state, and sends a diff. The client's
prediction is purely cosmetic until the server diff
arrives.

### 9.7 Lag compensation

For hit detection (the player's click needs to land on
the enemy where the player *saw* it, not where it is now
50ms later), we use **rewind-time hit detection**:

1. Client sends "I attacked target Y at client_tick T_c".
2. Server looks up entity Y's position at server_tick
   T_c - latency_estimate.
3. Server evaluates hit at that historical position.
4. If hit, server applies damage in current tick.
5. If miss, server tells client.

The lag estimate is per-client, EWMA-smoothed, and bounded
(never rewind more than 500ms = 10 ticks).

### 9.8 Authority boundaries

| Operation | Authority | Notes |
|---|---|---|
| Player position | Server | Client predicts but server decides |
| Mob AI | Server | Mob decisions are server-only |
| Player skills (cast) | Server validates | Client can show predicted cast; server decides if it lands |
| Loot drops | Server | Client displays the result; server owns the RNG (per-player seed) |
| Chat | Server | Optional client-side filtering for spam UX |
| UI / menus | Client | No authority needed |
| Crafting / inventory changes | Server | Client can show "preview" but server decides if successful |

The split: **anything that affects game state is server**.
Anything that's purely visual or UI feedback is client.

### 9.9 Tick pacing under load (D021)

When a tick overruns its budget (e.g. 60ms in a
50ms slot), the server **defers to a side queue**
with the **flywheel as the awareness layer** (D021).

The side queue is the *defer* policy: phase-2 work
that doesn't fit in the budget goes to a queue,
processed in the next tick. The flywheel is the
*response* policy: it tells us *why* and *who*:

- **Who is the contributor?** Top-N chaos
  contributors (§9.14 snapshot) identify the
  player, mob spawn, or input type driving the
  load.
- **What subsystem is hot?** Sub-meters
  (player_inputs, mob_ai, cross_shard) identify
  the system.
- **Where to slim?** The highest sub-meter gets
  throttled first (reduce NPC AI rate, drop
  cosmetic effects, lower LOD aggression).
- **Is an exploiter involved?** Per-player
  flywheel (§9.16) flags suspicious players;
  their inputs get deprioritized.
- **Races?** Sub-meter patterns
  ("cross_shard HLC storm" or "input flood")
  indicate contention.
- **Health?** The flywheel momentum is a leading
  indicator of stress; >80% is operator-visible.

The side queue itself has a flywheel (queue-
flywheel). When the queue-flywheel exceeds its
threshold, the system knows it's overrun
persistently and triggers the **load-shedding
policy**:

- Reduce AOI radius (less work per tick).
- Skip non-essential systems (skip world-event
  ticks, skip loot roll for far-away mobs).
- Eventually, refuse new connections (full shard
  signal).

This is per-shard; other shards are unaffected.
The shedding policy is informed by the
flywheel — it knows *which* subsystem to shed,
not just "shed everything."

### 9.10 The 1Hz world-event tick

Once per second:

- Update world clock (day/night cycle).
- Roll world-event timers.
- Schedule future events (announce world boss in 30min).
- Check for shard-wide triggers (siege start, faction war).

This is independent of the 20Hz game-state tick. It
operates on the same state tree but its outputs are
diff'ed separately (low frequency = small diffs).

### 9.11 The 1/60s Postgres-snapshot tick

Once per minute:

- Compute the current root hash.
- Write the snapshot row: `(root_hash, timestamp, tick_count)`.
- Write any changed entity rows (if they're "dirty" — see
  §12.4 on Postgres-tier writes).
- Update the diff window: keep the last N diffs in Redis
  for clients that need to catch up.

Snapshot writes are debounced: a fast snapshot is fine
(empty data, just the root); a slow one (entity changes)
is fine because Postgres is async-friendly.

### 9.12 The 10Hz LOD tick

Every 100ms:

- For each player, recompute their AOI center.
- For each chunk, check if it's in any player's AOI
  (hot) or only in predictive-prefetch (warm) or neither
  (cold).
- Promote cold → warm if needed.
- Demote warm → cold if idle.

This is a single-threaded pass; at 1000 players and 6,400
hot chunks, it's ~1ms.

### 9.13 Simulation cost per entity (the ECS question)

The current player/enemy model is Godot Node-based with
components (HealthComponent, CombatComponent, AggroComponent,
etc). This is fine for ~100 entities. At 1000 players +
5000 mobs = 6000 nodes, each emitting ~10 signals per tick
= 60K signal dispatches per tick = ~60ms in GDScript.

**We will blow the tick budget.** The signal-based,
node-graph model doesn't scale to MMO size.

#### 9.13.1 The pattern that scales: ECS

**Entity-Component-System** separates:
- **Entity**: a stable ID + a list of components.
- **Component**: a data record (no behavior). E.g.
  `Position { x, y, z }`, `Health { current, max }`,
  `CombatState { target, last_attack_tick }`.
- **System**: a pure function over all entities with a
  matching component set. E.g. `MovementSystem` reads
  `Position + Velocity`, writes `Position`. `CombatSystem`
  reads `Health + CombatState + IncomingDamage`, writes
  `Health`.

Systems are O(rows of matching components), not O(nodes).
A `MovementSystem` over 6000 entities is ~6000 row ops =
~1ms in GDScript.

#### 9.13.2 The /labs/ ECS primitive

`game/core/frame/kv/ecs.gd` (planned) provides:
- `EntityId` (64-bit).
- `EntityStore`: dense arrays of components per type.
- `System`: registered function with component-set signature.
- Tick: run all systems in dependency order.

The Godot-side uses the ECS primitive for the **server's
authoritative simulation** (tick logic). The Godot scene tree
is still used for the **client's rendering** (Node3D,
AnimationPlayer, etc).

A player is one entity: `{ Position, Velocity, Health,
Mana, CombatState, SkillCooldowns, Auras, ... }` in the
ECS, but also a `Node3D` in the scene tree with a mesh +
animation player. The two stay in sync via a thin
`EntityBinding` adapter that listens to ECS changes and
updates the Godot side.

#### 9.13.3 What about the FSM states (idle/run/jump/fall)?

The current FSM-based PlayerController (Idle/Run/Jump/Fall)
becomes a **`MovementStateSystem`** in ECS. State transitions
are pure functions of inputs + state. ~6 states total,
updated as part of the ECS tick.

#### 9.13.4 Tick batching + staggering

Beyond ECS, two more optimizations on the hot path:

- **Tick batching**: instead of per-entity `_process()`, run
  one batched pass per system per tick. The current code's
  per-Node signal flow is replaced by per-system loop.
- **Tick staggering**: don't tick all 6000 entities every
  tick. Stagger: entity A at t=0, B at t=50ms, C at t=100ms.
  Each entity gets effective 20Hz "for itself"; the server
  processes 1/3 of entities per real tick. ~3x cheaper.

Staggering is simple and orthogonal to ECS. We do both.

#### 9.13.5 Phasing

| Phase | ECS scope |
|---|---|
| Phase 1 | None — manual Node-based is fine for first vertical slice with 100 entities |
| Phase 2 | `ecs.gd` primitive in /labs/ with unit tests |
| Phase 3 | Player simulation moves to ECS (Position, Velocity, Health, Mana) |
| Phase 4 | Mob simulation moves to ECS; tick staggering enabled |
| Phase 5 | Combat systems, aura systems, AI systems all in ECS |

The first vertical slice stays Node-based for clarity. We
introduce ECS as soon as we need it for scaling.

### 9.14 The shard-level flywheel (D020-D022, D024)

The tick has a **flywheel** — a shard-local
accumulator of "chaos" (work). The flywheel is the
load profiler; it makes the work-proportionality of
the tick explicit and observable.

This is a port of the
[`nature.js`](https://github.com/dhaupin/vant/blob/axolotl/lib/nature.js)
hit-and-miss engine pattern from the sibling vant
repo. See `labs/world-building-tick.md` for the
full deep-dive.

**Three states:**

- **Ephemeral:** in-memory. Normal operation. No
  I/O cost.
- **Snapshot:** Redis key `flywheel:<shard_id>`,
  TTL'd 1 hour. Written on trigger.
- **Restored:** loaded on boot if a recent snapshot
  exists.

**Snapshot triggers (write):**

1. Flywheel > 80% of max (high-entropy).
2. Planned event signal (operator-initiated).
3. SIGTERM (planned restart).
4. Resource pressure (CPU > 80% for 30s, memory
   > 90%, connection backlog).
5. Crash recovery (read-side companion).

**Discard rules (don't restore):**

- Snapshot > 1 hour old.
- World seed has rolled (manifest change).
- Operator-flagged discard.

**Snapshot record (the embedded data when hot):**

- `momentum` (the headline number)
- `trigger` (which trigger fired)
- `sub_meters` (player_inputs, mob_ai,
  cross_shard, wall_clock — the "where is the
  chaos coming from" breakdown)
- `top_contributors` (top-10 chaos sources —
  only when hot, otherwise empty)

When calm: ~50 bytes. When hot: ~200 bytes with
forensic detail. Same Redis key, same TTL.
**Low-signal-when-calm, high-signal-when-hot.**

**Cost:** one Redis op on trigger, not per tick.
Hot path unchanged.

### 9.15 Postmortem: load-driven vs bug-driven

The killer use case for the flywheel snapshot is
crash forensics. The flywheel is a **leading
indicator** of trouble; CPU and memory are
*lagging* indicators.

When a shard crashes with a recent snapshot, the
postmortem reads the answer in 30 seconds:

- **Flywheel=950, 80% mob AI, top contributor:
  mob spawn cascade** → "tune mob AI throttling
  / cap spawn rate."
- **Flywheel=950, 95% player inputs, top
  contributor: one player's combat macro** →
  "throttle / ban that player."
- **Flywheel=950, 70% cross-shard, top
  contributor: HLC storm** → "fix coordinator
  reconnection."
- **Flywheel=150, normal load** → "find the
  bug."

Without the snapshot, all four are "shard crashed."
With the snapshot, each gets a different postmortem.
This is the value of persisting the flywheel.

### 9.16 The per-player flywheel (D023)

In addition to the shard-level flywheel, **each
player has their own flywheel** for security and
anticheat. Same pattern, smaller scope, different
purpose. See `labs/world-building-tick.md` §9 for
the full deep-dive.

**The inversion:** instead of security scanning
every player for anomalies, each player's flywheel
*is* the anomaly detector. The player audits
themselves. Security investigates only the hot
players.

**Sub-meters per player:**

- Movement (distance, speed, teleport, fast-travel)
- Combat — hits (timing, crit rate, hits per tick)
- Combat — cooldowns (skill uses, gaps, downtime)
- Chat (msg/min, channel-switches)
- Trade (opens/min, items/trade, gold flow)
- Loot (rolls/min, rare-drop rate)
- Instance / fast-travel (enters/min)

Each sub-meter has warn + trigger thresholds.
When trigger fires, a snapshot of the player's
recent activity goes to
`suspicious:<player_id>` in Redis (TTL 1 hour).

**The anticheat pipeline:**

1. Per-tick: every player's flywheel updates
   (O(1) per player).
2. Per-trigger: snapshot fires; goes to
   `suspicious:<player_id>`.
3. `AutoResponseService` subscribes; decides
   action (warn / mute / restrict / kick / ban).
4. `SecurityService` and `AppFirewall` also
   listen, bring their own context.

**Maps to existing code:**

- New: `PlayerFlywheelService` autoload.
- Adapts: existing `SecurityService`,
  `AutoResponseService`, `AppFirewall` become
  data-driven (the snapshot is the trigger).

**Cost:** ~1MB memory (5000 players × 200 bytes),
O(N) per tick, one snapshot per trigger. Hot path
unchanged.

**The principle (generalizes):** any time you
have "find the bad actors in a population," build
them a per-entity flywheel. The same abstraction
(flywheel + sub-meters + thresholds + snapshot)
works for shard load, player behavior, NPC AI,
services, etc.

### 9.17 The monitorability commitment (D022)

Every signal in the events system can register as
a chaos source. The flywheel doesn't care *where*
chaos comes from; it just accumulates. NPCs,
entities, services, signals — any emitter can
declare a chaos weight.

**The principle:** observability becomes
load-bearing. Without the flywheel, "make
everything monitorable" is an observability virtue
(a nice-to-have). With the flywheel, it's a
load-profiling necessity (a must-have). The
flywheel justifies the observability investment.

**The implementation:** the existing `EventBus`
autoload is the natural registration point. New
services emit signals there; chaos observers
attach. The pattern is additive — existing
services don't change, they just become
observable.

**The cost:** per-event is O(1). Per-trigger is
the existing snapshot mechanism. Memory is trivial.

**The benefit:** the flywheel becomes the
**single load-profiling abstraction** for the
entire game. One flywheel, many sub-meters, one
snapshot. The "we forgot to monitor X" failure
mode disappears — X either emits a signal (and
feeds the flywheel) or it doesn't.

### 9.18 Account-level rollups (anticheat escalation, D028)

The per-player flywheel (§9.16) is **shard-local**.
That's the right scope for the flywheel itself
(chaos is shard-local), but cross-shard exploit
patterns need a different scope: the *account*.

A player who causes chaos on shard A, then
quickly moves to shard B, then back to A is
*shard-skipping* — a known exploit pattern. The
per-player flywheel on each shard sees only that
shard's view. The account-level rollup sees the
pattern across all shards.

#### 9.18.1 The four layers

**Layer 1: Per-player flywheel (shard-local).**
What §9.16 describes. 7 sub-meters, ~200 bytes
per player per trigger snapshot. Lives on the
shard. Snapshot goes to
`suspicious:<player_id>` in Redis, TTL 1 hour.

**Layer 2: Account-level rollup (account-scoped).**
The account has its own KV in Redis:
`account:<account_id>:flywheel`. Fields:
- `total_chaos` (sum of shard-local moments).
- `per_shard` (a dict of
  `{"shard_1": 950, "shard_2": 200, ...}`).
- `top_contributors` (which shards are hot for
  this account).
- `cross_shard_flags` (e.g. "frequent shard
  hops with high chaos" — pattern matches).
- `recent_triggers` (last 10 trigger events:
  timestamp + shard + type + sub-meter).

**Layer 3: Session metadata.** Per session, in
Redis with TTL = session lifetime:
- `session_id` (UUID).
- `account_id`.
- `player_id` (the active character; can change
  in a session if the account has multiple).
- `device_fingerprint_hash` (see Layer 4).
- `connection_timestamps` (connect, disconnect,
  last activity).
- `shard_transitions` (which shards this session
  touched, in what order).

**Layer 4: Device fingerprint.** A long-lived
device identifier (independent of session):
- `device:<hash>` key in Redis.
- Hash = `SHA-256(UA + screen + WebGL renderer
  - first-seen-cookie + browser entropy)` —
  computed client-side, sent on session start.
- TTL 30 days (refreshed on activity).
- Used to detect: same device, multiple accounts
  (smurf detection); or different devices, same
  account (account sharing).

#### 9.18.2 Cross-shard pattern detection

The detection question: is this account exhibiting
a known exploit pattern? Three patterns the
rollup catches:

**Pattern A: shard-skipping.**
Account has high chaos on shard A (flywheel
moment 950), then transitions to shard B within
60s, then back to A. Detected by:
`account:<id>:flywheel.shard_transitions` showing
A → B → A within 1 hour, with
`per_shard[A] > 500` and `per_shard[B] < 100`.

**Pattern B: account-cycling.**
Same device fingerprint, multiple accounts, all
active in the same time window. Detected by
querying `device:<hash>` for all linked
accounts and computing the activity-overlap.

**Pattern C: account sharing.**
Same account, multiple devices, simultaneous
sessions. Detected by
`account:<id>:sessions` showing
`device_fingerprint_hash` mismatches within
the same activity window.

The rollup doesn't *act* on these — it
*signals*. AutoResponse (next subsection)
consumes the signals.

#### 9.18.3 AutoResponse subscription model

AutoResponse today reacts to per-shard trigger
snapshots (`suspicious:<player_id>`). With the
rollup layer, AutoResponse grows a second
subscription:

- **Fast path (shard-local):** trigger fires,
  AutoResponse acts within seconds (existing).
  Default for clear-cut cases (macro detection,
  obvious speed-hacks).
- **Slow path (account-level):** the rollup
  flags a cross-shard pattern, AutoResponse
  acts on the *account* within hours/days.
  Default for ambiguous cases (shard-skipping,
  smurf detection).

**The new pipeline:** `AccountAutoResponse`
subscribes to the account-key
(`account:<id>:flywheel`). When the rollup's
`cross_shard_flags` flip, it produces a
deliberate action: warn the account, restrict
the account, or ban the account. Banning an
account is a heavier hammer than banning a
character — the player's other characters and
future accounts are also affected (Phase 3+).

**Why a separate pipeline:** the fast path
needs to be reactive (seconds). The slow path
needs to be *forensic* (hours, sometimes days
of accumulated evidence). Two different
latency profiles, two different action
policies. The rollup is the bridge.

**Wiring:** AutoResponse subscribes to both
`suspicious:<player_id>` (existing) and
`account:<account_id>:flywheel` (new). The
new subscription is Phase 3+; the data layer
(§9.18.1, §9.18.2) is Phase 2+.

#### 9.18.4 Cost analysis

For 5000 active players on 100 shards:

| Layer | Memory | Per-trigger | Per-session |
|---|---|---|---|
| Per-player flywheel | ~1MB | 1 snapshot | — |
| Account rollup | ~25MB | 1 HSET (1KB) | — |
| Session metadata | ~2MB | — | 1 HSET per transition |
| Device fingerprint | ~700KB | — | 1 HSET per day |
| **Total** | **~30MB** | **2 Redis ops** | **bounded by session count** |

**Hot-path cost:** 2 Redis ops on trigger
(flywheel snapshot + account rollup update).
This is the existing snapshot cost plus one
HSET. The account rollup is debounced (not
per trigger; only when momentum crosses a
threshold) to keep the cost bounded.

**Storage cost:** 30MB across the rollup layer
is rounding error against the existing
state-tree storage.

**Bandwidth cost:** the per-shard flywheel
already includes player_id in its snapshot.
The account_id is looked up via a single
indexed Redis read (cached). Negligible.

#### 9.18.5 What we capture vs what we don't

**Capture (always):**
- Per-shard flywheel moments and triggers.
- Per-shard session transitions.
- Per-account cross-shard rollup (smurf
  detector).
- Per-device fingerprint (100 bytes per
  device — rounding error).

**Don't capture:**
- Per-keystroke movement samples (too
  granular, too expensive).
- Per-second timeline reconstruction
  (we sample, not record all).
- Per-other-player observation (privacy
  - bandwidth).
- Audio, video, screenshots (out of
  scope; client-side only if at all).

**The line:** "if it helps detect a known
exploit pattern, capture it; if it's
forensic-only, capture on trigger only."
The rollup is the systematic version of
this principle — it captures exactly the
cross-shard fields that patterns need, no
more.

**The principle (generalizes):** any time
you have a "per-entity X" that's also
meaningful at a "per-account Y" scope,
build a rollup. Same abstraction
(per-entity + per-account + sessions +
device), different domain. The flywheel
is one; the rollup is the *aggregation*
mechanism. This pattern will repeat
(trade, social, guild — any domain where
players have multiple shards/characters).

---

## 10. Transport: WebSocket for browser + agent compatibility

### 10.1 Why WebSocket

Browser clients (Godot HTML5/wasm export) cannot do raw
UDP or raw TCP from a page. The browser exposes
WebSocket only. To run the same game client in a browser,
we need WebSocket transport.

For non-browser clients (dedicated servers, native
desktop, agent connectors), we have options:
- Use the same WebSocket transport (simple, single code
  path, slightly higher latency).
- Use a faster lane (ENet for native clients — already in
  the codebase as `NetworkManager`).

The default is: **WebSocket for everything**. ENet stays
as an internal-only lane for shard↔coordinator and for
peer-to-peer traffic between native clients (P2P entity
sync, future).

### 10.2 The WebSocketServer (Godot)

Godot has `WebSocketServer` and `WebSocketPeer`. We wrap
these in a transport module:

```
Transport (game/core/net/transport.gd):
  - WebSocketServer (for shard server)
  - WebSocketPeer (for client connection)
  - WebSocketClient (for client connection to shard)
```

The transport layer:

- Accepts WebSocket connections.
- Performs the auth handshake.
- Frames messages (binary frames preferred).
- Routes messages to/from the game-state tick pipeline.
- Provides back-pressure (slow consumer → disconnect).

### 10.3 The wire protocol

We use a **binary protocol** over WebSocket text/binary
frames. Text frames are reserved for debugging (JSON
diagnostic messages); production traffic is binary.

Message envelope:

```
[1 byte: type]
[1 byte: flags]
[4 bytes: payload length (LE u32)]
[N bytes: payload (type-specific)]
[8 bytes: HMAC tag (optional, for critical messages)]
```

Types:

| Type | Direction | Payload |
|---|---|---|
| 0x01 `HELLO` | client → server | ClientHello |
| 0x02 `WELCOME` | server → client | ServerWelcome |
| 0x03 `INPUT` | client → server | ClientCommand |
| 0x04 `STATE_DIFF` | server → client | DiffBatch (filtered to AOI) |
| 0x05 `SNAPSHOT_REQ` | client → server | SnapshotRequest |
| 0x06 `SNAPSHOT_RESP` | server → client | SnapshotResponse |
| 0x07 `PING` | both | empty (heartbeat) |
| 0x08 `PONG` | both | empty (response) |
| 0x09 `ERROR` | both | ErrorPayload |
| 0x0A `BYE` | both | empty (graceful close) |
| 0x10 `EVENT` | server → client | EventPayload (world events, announcements) |
| 0x20 `RPC` | both | RPCPayload (player-to-player, system-to-player) |

### 10.4 The handshake

Client → Server (HELLO):

```
{
  "client_version": "0.4.2",
  "auth_token": "...",
  "preferred_character_id": "...",
  "capabilities": ["aoi_100m", "lod_2", "nsc9_v1", ...],
  "client_type": "browser" | "native" | "agent",
  "agent_connector": "mcp" | "claude" | "openai" | null
}
```

Server → Client (WELCOME):

```
{
  "session_id": "...",
  "shard_id": "shard_1",
  "character_id": "...",
  "tick_rate": 20,
  "world_manifest_hash": "abc123...",
  "initial_snapshot_hash": "def456...",
  "initial_diff_bytes": "..."
}
```

If the client's `client_version` is too old, the server
responds with an `ERROR` and disconnect. If the auth token
is invalid, ERROR. Otherwise WELCOME.

### 10.5 The diff frame

STATE_DIFF messages are batched. The payload contains a
list of `(tick, diff_bytes)` pairs (one per coalesced
tick), with AOI-filtering applied per-client. The client
applies each diff in order.

```
STATE_DIFF payload:
  u16: count of diffs
  for each:
    u32: tick_number
    u16: diff_size_bytes
    bytes: diff_content (already AOI-filtered)
```

The diff content itself uses the path-keyed encoding from
§5.6. It's binary; no JSON.

### 10.6 Why binary, not JSON

Three reasons:
1. **Bandwidth.** A diff for one entity is ~50 bytes
   binary vs ~500 bytes JSON. For 100 entities/tick,
   that's 5KB vs 50KB per tick per client. At 1000
   clients = 5MB/s vs 50MB/s.
2. **CPU.** Parsing binary is ~10x faster than parsing
   JSON in GDScript (no string allocation, no escape
   handling).
3. **Safety.** Binary doesn't have JSON-injection
   concerns, no need for BBCode-escaping or
   user-content sanitization on the wire.

### 10.7 Heartbeat & reconnect

- Client sends `PING` every 5s.
- Server responds `PONG` immediately.
- If 3 pings missed (15s), server disconnects (assumes
  network drop).
- Client, on disconnect, attempts reconnect with the same
  session_id. Server validates session, resumes from the
  last acked tick (sends a fresh diff since then).

If the session has expired (>5 min idle), the server
responds with `ERROR: session_expired` and the client
must log in fresh.

### 10.8 Compression

WebSocket supports `permessage-deflate` extension. We
enable it for STATE_DIFF frames (which compress well due
to repeated structure) and disable for PING/PONG/ERROR
(where the compression overhead exceeds the savings).

For especially large diffs (initial snapshot, world
event broadcasts), we apply LZ4 pre-compression on top
of permessage-deflate. LZ4 is fast (~500MB/s on
commodity hardware) and produces ~3x better compression
than deflate alone on typical game state.

### 10.9 The agent path

AI agents (Claude, GPT, Gemini, MCP) connect the same way
as human clients: WebSocket, full handshake, full diff
protocol. The only difference is `client_type: "agent"`
in HELLO, which lets the server apply agent-specific
QoS/rate limits and emit an `agent_observation` event
instead of UI render commands.

This means **one transport, three clients**: browser
humans, native humans, AI agents. Same auth, same sync,
same AOI rules. The agent's "render" is an observation
payload; the human's "render" is pixels.

### 10.10 The P2P lane (PROMOTED from deferred)

Originally deferred in the PRD §10.4. **Promoted to active
in Phase 1** because the user explicitly flagged it as
high-leverage for scaling on commodity VPS.

The P2P lane lets nearby clients **exchange chunks
directly**, bypassing the server. Two clients near each
other have ~70% overlap in their AOI chunks; if both have
the full state, they can gossip diffs in parallel.

#### 10.10.1 Why this matters

In a busy area (a city, a dungeon, a raid), the server's
outbound bandwidth scales with **clients × diff-size ×
20Hz**. For 100 clients in the same region, the server is
broadcasting the same chunk diffs 100 times.

P2P chunk sync lets clients exchange chunk hashes, and if
one has a chunk the other needs, sync it directly. The
server sees only **"X has hash H" and "Y has hash H"**
metadata, not the chunks themselves. Server outbound
bandwidth in dense areas drops ~5x.

#### 10.10.2 The wire format

**Reuses the state-tree diff protocol**. A P2P chunk
exchange is just a STATE_DIFF message (from §10.3) sent
peer-to-peer. The chunk hash is the message ID. The
sender's chunk state is the payload. Same canonical
encoding, same Merkle verification.

This means **zero new code for the wire format** — we
just add a transport (WebRTC or direct WebSocket-to-
WebSocket-to-WebSocket, depending on browser support)
that can carry the same binary frames.

#### 10.10.3 Browser constraints

Browsers don't allow direct socket-to-socket P2P without
a relay. The realistic options:

- **WebRTC with the game server as signaling relay.** The
  server tells clients "X is near you, here's an ICE
  candidate". Clients establish a WebRTC data channel.
  Throughput: ~10-100 Mbps typical.
- **Loopback through the server.** Clients exchange chunks
  via the server (chunk upload from A, server forwards
  to B). No P2P gain, but works everywhere.
- **Native clients: direct UDP/TCP between clients.**
  Native Godot can do real P2P. ENet or raw sockets.

Default for v1: **WebRTC with the game server as signaling
relay**. Browser clients get most of the benefit; native
clients get full P2P later.

#### 10.10.4 The gossip protocol

1. Client A and Client B are nearby (server detects via
   AOI overlap).
2. Server sends both: "X and Y, please consider peering".
3. A and B exchange their chunk-hash sets:
   ```
   A → B: [hash_1, hash_2, hash_3, ...]
   B → A: [hash_5, hash_6, hash_7, ...]
   ```
4. Each computes the diff (what the other has that I
   don't): A wants hash_5/6/7; B wants hash_1/2/3.
5. Each requests the missing chunks from the other:
   ```
   A → B: "send me hash_5"
   B → A: STATE_DIFF { path: chunk_X, value: <chunk bytes> }
   ```
6. Each applies the diffs locally. Both clients now have
   the full chunk set; the server doesn't see the chunks.

The server still owns *authoritative state changes* —
P2P is just for **chunk distribution**, not for state
mutation. A P2P-received chunk is treated as a hint; if
the server subsequently sends a diff that contradicts, the
server wins.

#### 10.10.5 What doesn't go P2P

- Authoritative state changes (player position, mob
  health, loot drops). Always server-relayed.
- Cross-shard state. Always server-relayed.
- Initial snapshot (first connect). Server delivers.
- Active effects / projectiles. Server broadcasts.

P2P is for **static chunk distribution** only.

#### 10.10.6 Phasing

| Phase | P2P scope |
|---|---|
| Phase 1 | None — server-only sync, prove the basics |
| Phase 2 | WebRTC signaling; P2P chunk exchange for chunks the server already sent |
| Phase 3 | Optimize: predict which P2P chunks will be useful next; gossip in background |
| Phase 4 | Native-only direct UDP/TCP for power users |

---

## 11. Sync protocol: diffs, prediction, AOI, lag compensation

### 11.1 The fundamental protocol

The client and server maintain **the same state tree**.
The server is the writer; the client is the reader (with
prediction for local-only feedback).

Flow:

1. Client sends commands.
2. Server applies commands at tick T.
3. Server computes new root hash R_T.
4. Server diffs from R_{T-1} to R_T.
5. Server filters diff by client's AOI.
6. Server sends diff (binary, compressed, batched).
7. Client applies diff → local R_T.
8. Client renders.

### 11.2 AOI filter (interest management)

Each client subscribes to a **volume of interest** (VOI)
centered on their character. Default radius 100m, can be
expanded up to 500m or contracted to 50m based on device
class and player preference.

Server-side, for each tick:

1. Compute the diff.
2. For each client:
   - Determine which chunks the client's VOI overlaps.
   - Filter the diff to only those chunks' contents.
   - Add/remove entries to the client's interest set
     (subscribed chunks).
3. Send the filtered diff.

A chunk's contents include:
- The chunk itself (terrain, biome, etc.) — sent once
  on subscribe, then on change (rare).
- Mob entities in the chunk.
- Player entities in the chunk.
- Active effects (projectiles, AoE, auras).
- Player-placed entities (ankhs, houses, signs).

### 11.3 The subscribe/unsubscribe lifecycle

When a client first connects:
1. Server sends initial snapshot (full state at the
   client's current position, ~100m radius).
2. Client applies snapshot, builds local tree.
3. As the player moves, server sends subscribe/unsubscribe
   messages for chunks entering/leaving VOI.
4. Each subscribe includes the chunk's current state hash
   and a one-shot diff.

On disconnect:
1. Server unsubscribes the client from all chunks.
2. Server cleans up session state.
3. The player's entity stays in the world (other clients
   still see them).

### 11.4 The initial snapshot

The initial snapshot for a client is **not the whole
world**. It's:

- The 27 chunks around the player's current position
  (3×3×3 cube, ~64m each = ~192m radius).
- The player's character entity + inventory + skills.
- The player's current zone metadata.
- Any active world events in the area.
- The player's party/guild roster (just names + positions,
  not full state).

Size estimate: ~500KB compressed. Sent in 1-2 WebSocket
frames. Client receives, builds local tree, ready to
play in <1s on a typical connection.

### 11.5 Subscribing to chunks beyond AOI

Players can extend their VOI temporarily:
- "Scouting" mode (10s, 500m radius) — used by scouts,
  rangers.
- "Looking through a window" (5s, 200m radius) — for
  town views.
- "Map view" (player opens world map) — fetches LOD 2
  summaries for visible area, no full state.

These are explicit VOI-extend commands the client sends,
with time bounds. The server grants or denies based on
the player's skills / level / zone rules.

### 11.6 Diff encoding (binary)

The diff content (the bytes inside STATE_DIFF.payload)
uses a simple binary encoding:

```
diff_header:
  u32: from_root_hash (first 4 bytes; full hash is 32 bytes
       but we send it in the frame header)
  u32: to_root_hash (same)

diff_entry: (variable-length, repeated)
  u8: op (0=set, 1=delete, 2=set_meta)
  varint: path_length_segments
  for each segment:
    varint: segment_length_bytes
    bytes: segment_utf8
  varint: value_length_bytes
  bytes: value_content (canonical encoding per §5.4)
  u32: value_hash
```

Total size for a typical tick diff: ~5-50KB (binary),
~1-10KB after LZ4 compression.

### 11.7 Reconciliation when divergence detected

If the client computes `apply_diff(my_root, server_diff)`
and the resulting root hash doesn't match the server's
expected `new_root_hash`, the client has diverged. Common
causes:

- Missed intermediate diffs (network glitch).
- A bug in our canonical encoding.
- Cheating client trying to forge state.

The client's response:

1. Detect mismatch (compare root hashes).
2. Send `SNAPSHOT_REQ` with the client's current
   `last_acked_tick` + `last_acked_root_hash`.
3. Server validates: is the client's claimed tick +
   hash one we know about? If yes (legitimate catch-up),
   the server sends the diffs from that tick to the
   current tick. If no (impossible), the server
   disconnects (cheating).
4. Client applies diffs, resumes.

### 11.8 Lag compensation in detail

For combat (hit detection), the client's `INPUT` message
includes the client's tick number T_c. The server
interprets this as "the player is attacking what they saw
at tick T_c", which on the server side corresponds to
"the entity's position at tick T_s = T_c - (latency /
50ms)".

Server stores a **history window** per entity: last 500ms
(10 ticks) of position, animation state, and any active
hitbox state. The server uses the historical snapshot to
evaluate the hit.

This is **bounded** — we never rewind more than 500ms.
For high-latency clients (200ms+), the server reduces the
rewind window and the client sees "I hit but it didn't
register" more often. The trade-off is intentional.

### 11.9 AOI-extended events

Some events broadcast to a wider area than the player's
VOI:
- World boss spawns (broadcast to whole shard, ~50KB).
- Faction war declarations (broadcast to whole cluster).
- Auction house sales (broadcast to subscribers only).
- Guild chat (broadcast to guild members).

These are **event-frame** messages (type 0x10), not
STATE_DIFF. They don't affect the state tree directly;
they trigger client-side UI/logic.

### 11.10 The bandwidth budget

Per client, per second:

- 20 STATE_DIFF frames @ ~3KB each = 60KB/s baseline.
- World events @ 0-5KB/s bursty.
- Heartbeat @ 0.1KB/s.
- Total: ~60-100KB/s per client.

For 1000 clients on a shard, the server's outbound
bandwidth is ~60-100MB/s. Fits a single 10Gbps NIC with
plenty of headroom.

### 11.11 Bandwidth optimizations (browser-first)

For browser clients on flaky networks, raw 60-100KB/s is
too much. Four levers:

#### 11.11.1 Diff coalescing across ticks

Server-side, hold back up to 200ms of diffs and ship as
one batch. Tick-rate on the wire goes from 20Hz to 5Hz;
updates still arrive within human-perception threshold
(~150ms latency). Halves bandwidth.

Implementation: per-client send queue, flush every 200ms.
If a tick's diff is empty for a client, skip. If a tick
produces a non-empty diff for a client, queue it.

#### 11.11.2 Longer client prediction windows

Default client predicts 1 tick (50ms). Increase to 5 ticks
(250ms). Server sends corrections less often, since the
client's prediction matches the server for 250ms most of
the time.

Trade-off: when prediction *is* wrong, the correction is
bigger (5 ticks of divergence vs 1 tick). For MMO with
mostly-predictable movement, this wins.

#### 11.11.3 Region-of-interest compression (lossy at edges)

AOI is currently binary "in/out". Replace with a soft
function:

| Distance from player | Update rate | Content |
|---|---|---|
| 0-100m | 20Hz | Full position, full state |
| 100-300m | 5Hz | Position only, no state |
| 300-1000m | 1Hz | Type + approximate position |
| 1000m+ | Event-driven | Spawn/despawn events |

Bandwidth scales with **relevance × distance**, not with
**entity count**. For a 1000-entity AOI, ~80% of entities
are at >100m; the optimization cuts their update cost
by 4-20x.

#### 11.11.4 CDN for static chunks (the big win)

Chunks are content-hashed. Once a chunk has been
generated, it's immutable (same hash forever for the
same `(seed, address)`). **A CDN can serve it**.

Architecture:
- Game server emits diffs for *dynamic* state (mobs,
  players, effects) only.
- *Static* state (terrain, biome, POIs, mob-spawn slots)
  is fetched by the client from the CDN by content hash.
- CDN cache key = chunk content hash. Two clients asking
  for the same chunk hit the same CDN edge.
- First client to load a chunk can fetch from CDN; CDN
  edge pulls from origin (game server's Postgres
  `chunks` table) once, then serves to everyone.

CDN costs pennies per GB. Game server costs dollars per
GB egress. **Putting static content on a CDN reduces
game server bandwidth 5-10x in dense areas.**

#### 11.11.5 Combined bandwidth budget

With all four optimizations, the per-client bandwidth
drops from 60-100KB/s to ~15-30KB/s. Server outbound
drops to 15-30MB/s for 1000 clients. Same 10Gbps NIC,
10x more headroom.

### 11.12 What the sync protocol is NOT

- **Not a CRDT.** Clients don't merge; they apply the
  server's diff. If two clients disagree about a value,
  the server wins.
- **Not a snapshot stream.** Clients receive diffs, not
  full snapshots, after the initial snapshot. Full
  snapshots are only requested on divergence.
- **Not lossy.** Every diff is delivered (or the client
  reconnects / requests catch-up).
- **Not just server-relayed.** Phase 2+ adds P2P chunk
  exchange (§10.10); the server is still the only
  authority, but chunk *distribution* can be P2P.

### 11.13 World cache (edge shards — future)

For very large shards (>5000 active players), the
centralized shard becomes a bandwidth bottleneck even with
the optimizations above. The next step is **edge shards**:

```
                ┌──────────────┐
                │ Central shard │  (authoritative state)
                └──────┬────────┘
                       │ state-tree diffs
        ┌──────────────┼──────────────┐
        │              │              │
   ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
   │ Edge A  │    │ Edge B  │    │ Edge C  │  (filter + cache for nearby clients)
   │ (10-100 │    │         │    │         │
   │ clients)│    │         │    │         │
   └─────────┘    └─────────┘    └─────────┘
```

An edge shard:
- Subscribes to a *subset* of the central shard's state
  tree (the chunks near its assigned players).
- Performs AOI filter, prediction, and chunk generation
  on behalf of its clients.
- Forwards authoritative state changes back to the central
  shard.
- Doesn't hold durable state; restarts empty.

This is the CDN pattern for game state, not static assets.
Latency-sensitive clients (mobile, far-away regions) get
an edge shard near them; the central shard sees only
aggregated state.

**Phasing**: deferred to Phase 4+ (after central-server
scaling is proven). Phase 1-3 use the centralized model
with the bandwidth optimizations above.

---

## 12. Persistence: Postgres + Redis + optional geo-cache

### 12.1 The three tiers, redesigned

The current docs say "Postgres + cache". We now have three
distinct tiers, each with a clear role:

| Tier | Purpose | Latency target | Durability |
|---|---|---|---|
| **L0: In-memory (state tree)** | Hot data, current tick state | <1µs | Volatile; rebuilt on restart |
| **L1: On-disk (local FS)** | Warm data, recent snapshots | <1ms | Durable to process restart |
| **L2: Redis** | Tick cache, materialized intersections, session state | <1ms | Durable to Redis crash (AOF) |
| **L3: Postgres** | Historical snapshots, durable state, player-placed content, character persistence | <10ms | Highly durable |

### 12.2 What lives where

| Data | Tier | Notes |
|---|---|---|
| Current root hash | L0 | The authoritative "now" pointer |
| Hot chunks (last 60s accessed) | L0 | Spatial hot data |
| Warm chunks (5min-1hr) | L1 | On-disk, lazy-loaded |
| Cold chunks (1hr+) | L3 (Postgres) | Historical record |
| Tick cache (last 1000 diffs) | L2 (Redis) | For client catch-up on reconnect |
| Materialized intersections | L2 (Redis) | LRU, hot combos |
| Player-placed entities (live) | L0 + L2 | Live in L0 for fast access; cached in L2 for fast AOI queries |
| Player-placed entities (archive) | L3 (Postgres) | Permanent record |
| Character persistence | L3 (Postgres) | The master record (coordinator-owned) |
| World manifest | L3 + L2 (cached) | Read by all shards on boot |
| Shard metadata | L3 (coordinator's Postgres) | One row per shard |
| Tick history (last 1hr) | L1 | On-disk log; periodically archived to L3 |
| Session tokens | L2 (Redis with TTL) | 5-min TTL |
| Rate-limit counters | L2 (Redis) | Sliding window |
| Audit log | L3 (Postgres) | Permanent |

### 12.3 Postgres schema (initial)

We need:

```sql
-- World state
CREATE TABLE world_manifests (
  id TEXT PRIMARY KEY,
  shape TEXT NOT NULL,
  world_seed BIGINT NOT NULL,
  generation_rules_version INT NOT NULL,
  seed_epoch INT NOT NULL,
  config JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE snapshots (
  id BIGSERIAL PRIMARY KEY,
  shard_id TEXT NOT NULL,
  root_hash BYTEA NOT NULL,
  tick_count BIGINT NOT NULL,
  taken_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- payload: serialized full state for cold restore
  payload BYTEA,
  payload_size_bytes INT
);
CREATE INDEX snapshots_shard_tick ON snapshots(shard_id, tick_count DESC);

CREATE TABLE chunks (
  shard_id TEXT NOT NULL,
  chunk_address TEXT NOT NULL,
  -- the immutable content hash of this chunk
  content_hash BYTEA NOT NULL,
  -- what generation rules version this chunk was made under
  gen_version INT NOT NULL,
  -- the payload (compressed) for restore
  payload BYTEA NOT NULL,
  payload_size_bytes INT NOT NULL,
  -- metadata
  lod_level INT NOT NULL DEFAULT 0,
  last_accessed TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (shard_id, chunk_address)
);
CREATE INDEX chunks_hash ON chunks(content_hash);

-- Player-placed content (canonical record)
CREATE TABLE player_placed (
  entity_id TEXT PRIMARY KEY,
  owner_player_id TEXT NOT NULL,
  shard_id TEXT NOT NULL,
  chunk_address TEXT NOT NULL,
  content_hash BYTEA NOT NULL,   -- links to chunks.payload
  type TEXT NOT NULL,            -- 'ankh' | 'house' | 'sign' | ...
  placed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  metadata JSONB
);
CREATE INDEX player_placed_owner ON player_placed(owner_player_id);
CREATE INDEX player_placed_shard ON player_placed(shard_id, chunk_address);

-- Cross-shard (coordinator only)
CREATE TABLE characters (
  id TEXT PRIMARY KEY,
  owner_account_id TEXT NOT NULL,
  name TEXT NOT NULL,
  class_id TEXT NOT NULL,
  level INT NOT NULL DEFAULT 1,
  xp BIGINT NOT NULL DEFAULT 0,
  -- ... character data
  current_shard_id TEXT,
  current_chunk_address TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE guilds (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  faction_id TEXT,
  leader_player_id TEXT,
  -- state tree hash (cross-shard subset)
  state_hash BYTEA NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE factions (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  state_hash BYTEA NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Diff history (for catch-up)
CREATE TABLE diffs (
  id BIGSERIAL PRIMARY KEY,
  shard_id TEXT NOT NULL,
  tick BIGINT NOT NULL,
  from_root_hash BYTEA NOT NULL,
  to_root_hash BYTEA NOT NULL,
  diff_bytes BYTEA NOT NULL,
  size_bytes INT NOT NULL,
  taken_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX diffs_shard_tick ON diffs(shard_id, tick DESC);
-- Keep last 10000 diffs; older ones pruned
```

### 12.4 When data gets written

| Event | Writes to |
|---|---|
| Server tick completes | L0 (root hash); L2 (current diff, if non-empty); queued for L1 (snapshot, debounced) |
| Snapshot tick (1/min) | L1 (on-disk snapshot); L3 (Postgres snapshot row + dirty entity rows) |
| Chunk demoted L0 → L1 | L1 (write chunk to disk) |
| Chunk demoted L1 → L3 | L3 (Postgres chunk row) |
| Player places an ankh | L0 (new node); L2 (cache); L3 (player_placed row, durably committed) |
| Character levels up | L3 (character row update, async-batched) |
| Guild member joins | L3 (guild row + member table); broadcast to shards |
| Diff window full (1000 diffs) | L1 (archive old diffs); L3 (optional, for replay) |
| Server shutdown | Force L0 → L1 → L3 (graceful shutdown writes everything to durable tiers) |

### 12.5 The "dirty" mechanism for Postgres

Not every entity write hits Postgres. We use a **dirty
flag** per entity:

- Entity created → dirty.
- Entity modified → dirty.
- Snapshot tick (1/min) → flush dirty entities to
  Postgres, clear flags.

This means: an entity that's modified every tick still
only writes to Postgres once per minute. For an MMO with
100K entities and 1% active = 1000 active entities, that's
1000 rows/flush = trivial for Postgres.

### 12.6 Snapshot strategy

Snapshots are **content-addressed, not full-state**. We
store:

- `root_hash` (32 bytes).
- `tick_count`.
- The set of dirty entities (their current state).

To rebuild from a snapshot:

1. Find the most recent snapshot before this tick.
2. Load the snapshot's dirty entities.
3. Apply diffs from that snapshot's tick to this tick.
4. Result = current state.

For cold restore (server boot, no warm cache):
1. Load the latest snapshot.
2. Apply all diffs since.
3. Result = current state.

For very cold restore (snapshot from 6 months ago):
1. Load the snapshot.
2. Apply diffs since.
3. *Slow* but correct.

For extra-cold restore (Postgres backup from years ago):
1. Restore Postgres from backup.
2. Boot the server.
3. Replay diffs from the archived period.
4. *Very slow* but correct.

### 12.7 Redis usage

Redis stores:
- **Tick cache**: last 1000 diffs per shard, indexed by tick.
- **Materialized intersections**: LRU cache, hot combos.
- **Session tokens**: with TTL.
- **Rate-limit counters**: sliding window.
- **Co-located with each shard**: shard 1's Redis is
  separate from shard 2's Redis. The coordinator has its
  own Redis.

### 12.8 Migrations

Schema migrations live in `game/core/frame/db/migrations/`
as numbered SQL files:

```
001_initial_schema.sql
002_add_player_placed.sql
003_add_faction_tables.sql
...
```

Migrations run at coordinator startup (and shard startup,
for shard-local schema). They are forward-only (no
downgrade); rollbacks use Postgres backup.

### 12.9 The state tree IS the Postgres layer (revisited)

The schema in §12.3 has many tables (snapshots, chunks,
characters, guilds, factions, player_placed, diffs). For
a small deployment this is fine. For a "giant Sim on
commodity VPS" target, we push further:

**Idea**: instead of N tables, Postgres stores
**content-hashed state-tree payloads** as rows:

```sql
CREATE TABLE shard_state (
  shard_id           TEXT NOT NULL,
  tick               BIGINT NOT NULL,
  root_hash          BYTEA NOT NULL,
  payload            BYTEA NOT NULL,        -- full chunk payloads, content-hashed
  dirty_entity_count INT NOT NULL,
  PRIMARY KEY (shard_id, tick)
);
CREATE INDEX shard_state_root ON shard_state(shard_id, root_hash);

CREATE TABLE shard_chunks (
  shard_id       TEXT NOT NULL,
  chunk_address  TEXT NOT NULL,
  content_hash   BYTEA NOT NULL,
  gen_version    INT NOT NULL,
  payload        BYTEA NOT NULL,            -- the canonical chunk bytes
  payload_size   INT NOT NULL,
  lod_level      INT NOT NULL DEFAULT 0,
  last_accessed  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (shard_id, chunk_address)
);
CREATE UNIQUE INDEX shard_chunks_hash ON shard_chunks(content_hash);
```

Two tables, not eight. All queries are "give me the
state at tick T" (one row) or "give me the chunk with
hash H" (one row, dedup'd by content hash).

Why this matters:

- **Fewer connections.** 2 tables = 2 prepared statements.
  Postgres is connection-heavy; this saves a lot.
- **No schema migrations for new entity types.** Adding a
  new entity type means a new state-tree path; no SQL
  schema change. Schema migrations are reserved for
  *truly* new persistence features (e.g. when we add a new
  tier).
- **Deduplication is free.** Two shards with the same
  chunk-content hash share the payload via the unique
  index on `content_hash`. The world becomes naturally
  deduplicated at the byte level.
- **Backups are simpler.** `pg_dump shard_state` is one
  row per tick per shard. Diff between any two ticks is
  reconstructable. Restoring is "load last snapshot +
  replay diffs".
- **CDN-friendly.** Chunks are content-hashed; a CDN can
  serve `chunk.content_hash` directly (see §11.11.4).

The trade-off: less natural SQL querying. We lose the
ability to do "SELECT * FROM characters WHERE level > 50
ORDER BY xp DESC". To get that back, we use **projection
tables** maintained by background workers:

```sql
CREATE MATERIALIZED VIEW character_leaderboard AS
SELECT id, name, level, xp FROM <projection>;
-- refreshed every 60s from the current state tree
```

These projections are *derived data*, rebuilt on demand.
The source of truth is always `shard_state`.

This pattern (state-tree-as-storage + materialized
projections) is what lets us scale Postgres connection
count down and content-hash dedup up. **It's the
Postgres-friendly version of the content-addressed
pattern.** Recommended for v1+.

### 12.10 Append-only event log (alternative to dirty-flag)

The dirty-flag mechanism in §12.5 works, but for very
high-churn state (player positions, projectiles), even
1- per minute is overkill.

**Alternative**: append-only event log. Every state
change is an event row, never UPDATE:

```sql
CREATE TABLE events (
  id          BIGSERIAL PRIMARY KEY,
  shard_id    TEXT NOT NULL,
  tick        BIGINT NOT NULL,
  entity_id   TEXT NOT NULL,
  path        TEXT NOT NULL,        -- state-tree path within entity
  value_hash  BYTEA NOT NULL,
  value_bytes BYTEA NOT NULL,
  taken_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX events_shard_entity_tick ON events(shard_id, entity_id, tick DESC);
```

Reconstructing an entity's state at tick T = "apply all
events for this entity where tick ≤ T". Postgres handles
append faster than UPDATE (no MVCC churn). With
content-hash dedup on `value_hash`, common values
(position-update events that produce the same hash) are
deduplicated.

This is *better* than dirty-flag for high-churn data
and *worse* for low-churn data (because you have to
replay). We use **both**:
- Append-only log for entities that change every tick
  (players, mobs, projectiles).
- Snapshot + dirty-flag for entities that change rarely
  (chunk data, hand-authored overrides, character
  inventory).

### 12.11 CRDT for cross-shard state (future)

For state that crosses shards (guild membership, faction
relations, friend lists), the coordinator's
last-write-wins approach (§16.5) works but can lose
concurrent updates.

**Future alternative**: use a **CRDT** (commutative
replicated data type) for these specific data types:
- Guild membership: 2P-Set or OR-Set (add/remove are
  commutative).
- Friend list: OR-Set with timestamps.
- Faction relations: a small bounded set with commutative
  union.

CRDTs converge without coordinator bottleneck; shards
gossip state changes; the coordinator only arbitrates
uncommon conflicts.

Deferred to Phase 4+. Phase 1-3 uses last-write-wins.

---

## 13. Frame services: axes, projection, when & how

### 13.1 The axes we project for Synmergia

From the existing frame primitives design (axis reservations
001-099 spatial, 100-199 factional, etc), we pick the
following axes for this game:

| Axis | Reservation | Source | Used for |
|---|---|---|---|
| `spatial` | 001-099 | `address_cell(W)` | AOI queries, "who's here", mob lookup |
| `faction` | 100 | `entity.faction_id` | Faction-member queries, PvP rules |
| `species` | 101 | `entity.species_id` | Species-pvp-zone rules |
| `class` | 102 | `entity.class_id` | Class-restricted areas |
| `level` | 103 | `entity.level` | Level-range filters |
| `party` | 300 | `entity.party_id` | Party-member queries |
| `guild` | 301 | `entity.guild_id` | Guild-member queries |
| `instance` | 302 | `entity.instance_id` | Instance scoping |
| `temporal_hour` | 203 | `world_time.hour` | Day/night-dependent queries |
| `temporal_year` | 200 | `world_time.year` | Long-time-arc events |

We **don't** project every possible axis. The break-even
in §6.7 means we only project what's actually queried
frequently.

### 13.2 When projection runs

Projection happens at the **write boundary**, not the read
boundary. That is:

- When an entity is **created** (spawn): project onto all
  relevant axes. Cost: O(axes_used), ~10µs.
- When an entity **changes axis membership** (moves to a
  new spatial cell, joins a party, etc.): remove from old
  axis, add to new axis. Cost: O(axes_affected).
- When an entity is **destroyed** (despawn): remove from
  all axes. Cost: O(axes_used).

Reads (queries) don't project; they just look up cached
intersections. This is the "grail path".

### 13.3 Per-tick projection batch

Most entity-axis changes are clustered (mobs moving in a
chunk, players joining a party). We **batch** projection
updates per tick:

```
tick:
  ... (game logic) ...
  projection_batch = collect_changes_from_tick()
  julia_orchestrator.apply_batch(projection_batch)
  ... (diff + emit) ...
```

The Julia orchestrator applies the batch as a single
transaction; the materialized intersection cache is
updated atomically at the end.

### 13.4 Materialized intersection strategy

Following `grail-path.md` and `frame-lod-prediction.md`:

- **Hot combos**: LRU cache (1000 entries) in Redis.
  Updated eagerly on projection changes.
- **Cold combos**: computed on demand, cached for 60s,
  then evicted.

The hot combos are the ones we *expect* to be queried:

- `(spatial, party)` — "who's in my party near me"
- `(spatial, faction, level)` — "enemies I can attack"
- `(spatial, instance)` — "everyone in this instance"
- `(guild, online)` — "online guild members"
- `(species, faction)` — "faction members of species X"

These are hardcoded (we know we'll query them). Other
combinations are cold.

### 13.5 The orchestrator API

The Julia orchestrator exposes (already in part):

```
POST /register       # add an entity
GET  /spatial/:v     # entities at spatial cell v
GET  /faction/:f     # entities in faction f
GET  /party/:p       # entities in party p
GET  /guild/:g       # entities in guild g
POST /intersect      # multi-axis intersection
GET  /stats          # orchestrator stats
GET  /health         # health check
```

We add:

```
POST /batch_register # batch entity registration
POST /batch_update   # batch axis updates
POST /materialize    # force-materialize a combo into cache
DELETE /cache/:combo # invalidate a cached combo
GET  /intersect_cached # query with materialization guarantee
```

### 13.6 What doesn't go through the orchestrator

- **Single-entity lookups**: "give me entity X". Direct
  state-tree query, no orchestrator.
- **Updates that don't change axes**: position within the
  same cell, health changes. These are state-tree diffs
  only; orchestrator never sees them.
- **Spatial AABB queries**: "all entities in radius R of
  point P". Computed by walking the spatial axis within
  R's bounding box. Could go through the orchestrator
  for cached combos, but for one-off queries, direct
  walk is fine.

### 13.7 Performance budget

For a shard with 1000 active players and 5000 active
mobs:

- Per-tick projection batch: ~1000 axis changes (most
  players don't change spatial cell every tick).
- Apply batch: ~100µs in Julia.
- Materialized cache update: ~10µs per combo touched ×
  ~50 combos = ~500µs.
- Total per-tick orchestrator cost: ~600µs.

For comparison, scanning all 6000 entities: ~3ms in
GDScript. So the orchestrator wins by ~5x even at this
small scale. At 10K entities (a busy shard), the
difference is 50x.

---

## 14. LOD pyramid & predictive prefetch

### 14.1 The four LOD levels

Per `scale-200km2.md`, the world is stratified:

| LOD | Granularity | What's loaded | RAM cost |
|---|---|---|---|
| L0 (full) | Single 64m chunk | All passes (0-9), all entities, full state | ~50KB |
| L1 (summary) | 4×4 chunk group (~256m) | Aggregate stats, no terrain mesh | ~5KB |
| L2 (cold) | 32×32 chunk group (~2km) | Coarser aggregate, just biome + POI count | ~1KB |
| L3 (archived) | 256×256 chunk group (~16km) | Just the parent biome and rough POI type | <100B |

For 1% hot (L0+L1), at the 200km² scale:
- L0 chunks: 6,400 × 50KB = 320MB
- L1 chunks: 1,600 × 5KB = 8MB
- Total: ~330MB. Fits comfortably.

### 14.2 Promotion and demotion

Promotion L3 → L2 → L1 → L0 happens when a player enters
the chunk's region. Demotion is the reverse when a player
leaves. The triggers:

- **L3 → L2**: predictive prefetch detects a chunk is
  likely to be entered within 30s. OR a player is now
  within 2km of the chunk.
- **L2 → L1**: player is within 500m of the chunk.
- **L1 → L0**: player is within 100m of the chunk (active
  engagement).
- **L0 → L1**: player leaves the chunk AND no other player
  has been in it for 30s.
- **L1 → L2**: same but 5min idle.
- **L2 → L3**: 1hr idle.

The thresholds are configurable per zone (a town might
  have a wider L1 footprint than a wilderness).

### 14.3 The LOD manager (server-side)

The LOD manager is a singleton per shard that runs the
10Hz LOD tick (§9.12). It tracks:

- Per chunk: current LOD, last-access timestamp, players
  in range.
- Per player: AOI center, AOI radius, subscribed chunks.

On each LOD tick:

```
for each chunk in shard:
  desired_lod = compute_desired_lod(chunk, players_in_range)
  if desired_lod > current_lod:
    promote(chunk, desired_lod)
  elif desired_lod < current_lod:
    demote(chunk, desired_lod)
```

`compute_desired_lod` is pure function: given the chunk's
spatial position, the player's positions, and the LOD
thresholds, return the desired LOD.

### 14.4 Predictive prefetch (Markov)

The Markov predictor (`game/core/frame/srv/predictor.gd` —
not yet implemented) watches player movement and predicts
where they'll be in 5s, 30s, 5min.

For each player:

1. Maintain a history of (chunk_address, tick) tuples.
2. Build a transition matrix: P(next_chunk | current_chunk).
3. Predict: given current chunk, what's the most likely
   next chunk at T+5s, T+30s, T+5min?
4. Promote those predicted chunks to L2 (or L1 if close
   enough).

The Markov is per-player at first; we can aggregate to
per-zone or per-class predictions later.

### 14.5 The LOD manager (client-side)

The client mirrors the server's LOD pyramid:

- L0: full chunk data + mesh rendered.
- L1: aggregate stats shown as overlays on the map.
- L2: shown as colored regions on the world map.
- L3: not shown.

The client subscribes to chunks based on its AOI (§11.2).
When the server promotes a chunk, the client receives the
chunk's content (a one-shot diff). When the server
demotes, the client can drop the chunk (or keep it
warm in L1 cache).

### 14.6 What doesn't get LOD'd

- **Player entities themselves never get demoted.** The
  client always has its own character at full LOD.
- **Active effects (projectiles, AoE)** stay L0 until they
  expire.
- **Player-placed content (ankhs, signs)** the player
  owns never gets demoted while the player is online.
- **Active world events** stay L0 for the duration of the
  event.

### 14.7 The seam between LOD and sync

LOD promotion triggers a **state-tree diff** to bring the
client up to date. This is the same diff protocol as the
regular tick diffs (§11) — just with a larger initial
payload (the full chunk content).

The subscription diff has the same format as a tick diff
but is sent out-of-band (not coalesced into the next tick
batch). The client applies it, gets the new chunks into
its local tree, and renders.

---

## 15. Player-placed content (ankhs, halls, houses)

### 15.1 Why this is a state-tree concern, not a side-system

The user's instinct is correct: ankhs, guild halls, houses,
planted crops, crafted signs — all of it is **world state**.
A player walking through a town sees the same houses
everyone else sees. A guild hall is persistent across
sessions.

The temptation is to put housing in a separate "housing
database" with its own API. We resist this. Why?

- A house at coordinates (120, 0, 80) is the same kind of
  state as a tree at (120, 0, 81). They both live in the
  same chunk. They both need AOI updates, both get
  serialized in the same diff.
- The state tree already handles CRUD, content-hashing,
  diff/apply, persistence, AOI distribution. Reusing it
  means no second system to maintain.
- Cross-shard awareness ("this guild has a hall on shard 2")
  becomes a single tree path lookup.

### 15.2 The player-placed subtree

Each chunk has a `player_placed` subtree:

```
shard_1
└── chunks
    └── chunk_64_128_256
        └── player_placed
            ├── ankh_abc123
            │   ├── type: "ankh"
            │   ├── owner_player_id: "player_xyz"
            │   ├── position: [120, 0, 80]
            │   ├── content_hash: "..."     # the visual mesh + colliders
            │   ├── placed_at: 1729123456
            │   └── metadata: { ... }
            ├── house_def456
            │   ├── type: "house"
            │   ├── owner_player_id: "player_abc"
            │   ├── ...
            └── sign_ghi789
                └── ...
```

When a player enters a chunk, they receive the full
`player_placed` subtree as part of the chunk's diff.

### 15.3 Placing a structure

When a player wants to place an ankh:

1. Player issues `place_structure` command (with the
   structure template + position).
2. Server validates:
   - Player has the structure template unlocked.
   - Position is valid (in a placeable area, not blocked).
   - Player has the resources.
   - Zone rules allow it (some zones forbid player-placed
     structures).
3. Server computes the content hash of the new structure.
4. Server applies the diff: add node at
   `chunk.player_placed.<new_id>`.
5. Server emits the diff to all clients in the chunk's
   AOI.
6. Server writes to Postgres (`player_placed` table,
   durable commit).
7. Server writes to Redis (cache for fast lookups).

### 15.4 Visibility rules

Player-placed structures have **visibility rules**:

| Structure | Visible to | Notes |
|---|---|---|
| Ankh (bind point) | Everyone in the chunk | Public utility |
| Personal house | Owner + invited guests | Access-controlled |
| Guild hall | Guild members | Access-controlled |
| Sign | Everyone in the chunk | Public, with optional text filter |
| Crafted decoration (e.g. planted flower) | Owner + nearby | Personal display |

The visibility check happens at **diff emission time**:
the server filters which clients receive each structure's
diff. The structure lives in the state tree; the diff
controls who sees it.

### 15.5 Cross-shard awareness

A guild hall on shard 2 is owned by a guild that exists
across all shards. The shard's state tree has the spatial
record of the hall; the coordinator's state has the
guild record (which lists hall locations across all
shards).

When a player joins a guild:

1. Coordinator updates guild membership (L3).
2. Coordinator broadcasts to all shards: "player X is now
   in guild Y".
3. Each shard updates its own copy of the player's guild
   axis (§13.1).
4. Shard re-evaluates visibility: player can now see
   guild Y's halls in this shard.

### 15.6 Houses and ownership transfer

When a player trades a house to another player:

1. The transfer is a state-tree diff:
   `house_X.owner_player_id: old → new`.
2. The shard updates the player-placed table in Postgres.
3. The shard broadcasts the diff to all clients in the
   chunk's AOI.
4. The new owner now sees the house in their "my houses"
   list.

No second system. Same diff protocol as everything else.

### 15.7 Player-placed content and the geometric layer

Each player-placed entity gets an NSC-9 code on the
spatial axis (which cell it's in). It's projected onto
the spatial axis at placement time, so "all ankhs in this
region" is an O(k) intersection query.

Other axes (faction, guild, instance) are projected per
the standard rules.

### 15.8 Decorations, signs, planted crops

These are lightweight player-placed entities. They:

- Have a small content hash (~1KB).
- Have a position (within the chunk).
- May have rotation, scale, color variations.
- Are visible to everyone in the chunk (or filtered per
  visibility rule).

Treating them the same as ankhs/houses keeps the system
uniform. The cost difference is negligible (the state tree
doesn't care about the value's size; it hashes and stores).

### 15.9 What if a chunk is demoted with structures in it?

When a chunk goes L0 → L1 (or lower), the structures
**stay in the chunk's payload**. They just stop being
individually rendered; the L1/L2/L3 summaries count them.

When the chunk is promoted back, all structures are
restored. There's no "lost structure" scenario because
the chunk's content hash includes its player-placed
subtree.

### 15.10 The "house database" anti-pattern, summarized

| Pattern | Cost |
|---|---|
| Side housing database | Second query path; second auth model; second snapshot strategy; second AOI integration; second set of bugs |
| State tree (our choice) | One system; one auth model; one AOI; one diff protocol |

We choose the state tree. The user was right to call this
out.

---

## 16. Cross-shard sync

### 16.1 What crosses shards

Some state is **shard-local** (only one shard cares):

- Mob spawns in this shard's chunks.
- Player positions in this shard.
- Per-chunk dynamic content.

Other state is **cross-shard** (multiple shards care):

- Guild membership and state.
- Faction relationships.
- World events (coordinated across shards).
- Player-placed structures in other shards (for guild
  members to see in map UI).
- Auction house (subscribers across all shards).

### 16.2 The coordinator as the cross-shard hub

The coordinator process (per §2.1) owns cross-shard state.
It:

- Holds the master record for characters, guilds, factions.
- Subscribes to changes from all shards.
- Re-broadcasts to other shards.

The communication is **state-tree diffs**, not RPCs. A
guild membership change is a diff applied at
`world.cross-shard.guilds.<guild_id>.members`. Each shard
subscribes to the relevant subtree.

### 16.3 The coordinator's state tree

The coordinator has its own state tree:

```
root
├── world
│   ├── manifest (mirrored from canonical)
│   └── cross_shard
│       ├── guilds
│       │   ├── guild_abc
│       │   │   ├── members
│       │   │   ├── halls        # list of (shard_id, chunk_addr) per hall
│       │   │   ├── state_hash
│       │   │   └── ...
│       │   └── ...
│       ├── factions
│       │   ├── faction_human
│       │   │   ├── members
│       │   │   ├── relations
│       │   │   └── ...
│       ├── characters
│       │   ├── character_xyz
│       │   │   ├── state
│       │   │   ├── current_shard_id
│       │   │   ├── current_chunk_address
│       │   │   └── ...
│       ├── world_events
│       │   └── event_abc
│       └── auction_house
│           └── listing_xyz
```

The coordinator's Postgres backs this tree.

### 16.4 Shard ↔ coordinator protocol:

- **Shard → coordinator**: shard sends diffs for the
  portions of cross-shard state it owns. E.g. when a
  player levels up, shard sends diff to
  `cross_shard.characters.<id>.state.level`. When a player
  joins a guild, shard sends diff to
  `cross_shard.guilds.<id>.members.<player_id>`.
- **Coordinator → shards**: coordinator broadcasts relevant
  diffs to all interested shards. E.g. a guild member
  joined: coordinator broadcasts the diff to all shards
  that have guild members of that guild.

The transport is **server-to-server HTTP** (or gRPC, if
we adopt it). Not WebSocket — there's no browser in this
loop.

### 16.5 Conflict resolution

Two shards could update the same cross-shard entity at the
same time (rare, but possible). The coordinator's policy:

- **Last-write-wins** with a vector clock.
- Each shard's update carries the shard's vector clock.
- The coordinator accepts the update with the highest
  clock; if clocks tie, by the lexicographic order of
  `(shard_id, sequence_number)`.

For most cross-shard state (guild membership, faction
relations), conflicts shouldn't happen because the
canonical owner is one shard (the one the player is on).
The coordinator just relays.

### 16.6 Player-placed content across shards

A guild hall on shard 2 is owned by a guild that may have
members on shard 1. The shard-1 player wants to see the
hall on their world map.

The mechanism:

1. Coordinator has the cross-shard record:
   `guilds.guild_X.halls = [{shard: "shard_2", addr:
   "chunk_64_128_256"}, ...]`.
2. Shard 1 subscribes to its guild members' halls.
3. When shard 1 renders the world map for player Y, it
   queries the coordinator's tree for guild X's halls.
4. Shard 1 displays the hall icons on the map.
5. If the player wants to "fast travel" to the hall, the
   client sends a `request_portal` command; the shard
   checks permissions and either portals the player or
   denies.

### 16.7 World events across shards

A world boss spawn is a coordinator-canonical event:
- Coordinator decides the boss spawns at T = ...
- Coordinator broadcasts `world_events.boss_dragon.spawn`
  to all shards.
- Each shard sets up the local instance (the actual boss
  entity is created in whichever shard the boss's spawn
  location is in; other shards see "boss is spawned in
  shard 2" and can route players there).
- Loot distribution is per-player (per-player seed), but
  the kill is coordinator-tracked for leaderboards.

### 16.8 Auction house across shards

The auction house is a coordinator-owned structure:
- Listings are stored at
  `cross_shard.auction_house.listings`.
- Each listing has a `shard_id` (where the item physically
  is).
- Buyers can be on any shard; the trade (item transfer)
  is mediated by the coordinator and the relevant shard.

### 16.9 What doesn't cross shards

- Per-tick game state (positions, mob health, projectiles).
- Local-only chat.
- Player-internal UI state.

These never leave their shard.

### 16.10 Shard partitioning policy

Shards partition the world by **spatial region**, not by
player count. Each shard has a fixed spatial area:

- Planar: an AABB.
- Spherical: a range of icosahedral face IDs.

When the world is created, the manifest specifies the
shards and their partitions. Players on shard 1 see only
shard 1's spatial content (plus cross-shard content via
the coordinator).

If a shard gets too loaded, we can **redistribute** by
changing the partition (rare; requires a planned event).
Most load balancing is per-shard (AOI radius, tick rate).

---

## 17. Three-tier runtime: GDScript / Julia / C++

### 17.1 Why three tiers

The frame can ship in three runtime tiers, picked per call
site based on what's best at the problem:

| Tier | Language | Strength | When |
|---|---|---|---|
| 1 | **GDScript** | Game logic, UI, scene composition, signal handling | Default for everything that doesn't need performance |
| 2 | **Julia** (via HTTP or FFI) | Vector math, ML inference, hot loops, multi-axis intersection | Spatial queries, intersection materialization, LOD batch ops |
| 3 | **C++ / GDExtension** | Absolute hot path, physics, low-level | Future: Jolt Physics, SIMD batch ops |

The rule: **write the algorithm in the language that's best
at the problem**, then call it from GDScript at the right
layer.

### 17.2 Tier 1 (GDScript) — what stays here

- All autoloads (GameManager, NetworkManager, EventBus).
- All UI / scene composition.
- All gameplay logic (combat, skills, crafting).
- The state tree implementation itself.
- The diff/apply logic.
- The tick pipeline.

These are tied to Godot's node lifecycle, signal system,
or scene tree. Moving them to Julia or C++ buys nothing
and costs a lot.

### 17.3 Tier 2 (Julia) — what goes here

- Frame services (RulesEngine, ScopeEngine, Markov, LOD, Axis) - already in `game/core/frame/srv/`
- Materialized intersection cache management.
- Spatial queries on the geometric layer.
- Procedural noise functions (heightmap, biome).
- Markov predictor.
- Bulk vector math (per-entity updates).

These are pure functions of (state, params) → (state,
result). Easy to extract from Godot. The HTTP bridge
(`MultiIsoService.gd`) already exists.

When `labs/polyglot-ffi/` is mature, we can replace the
HTTP bridge with direct FFI calls (faster, no serialization
cost).

### 17.4 Tier 3 (C++ / GDExtension) — what goes here

Currently: nothing. The codebase has `labs/jolt-playground/`
which is a benchmark for Jolt Physics. Jolt would replace
Godot's default Physics3D if it proves faster or more
deterministic.

The plan: when the state tree and sync are proven, we add a
**state-tree GDExtension** that does the canonical encoding
and hashing in C++. GDScript calls it via the FFI boundary.

This is the only C++ code we're committing to in the near
term. Everything else stays GDScript + Julia.

### 17.5 Performance budget per tier

A 20Hz tick has 50ms. Budget allocation:

| Phase | Budget | Tier |
|---|---|---|
| Drain input queue | <1ms | GDScript |
| Apply inputs to entities | ~10ms (1000 entities) | GDScript (with Julia helpers) |
| Update mob AI / physics | ~10ms | GDScript (with Jolt if installed) |
| Compute root hash | ~1ms | GDScript (with C++ helper) |
| Diff + apply | ~2ms | GDScript |
| Materialized cache update | ~1ms | Julia |
| Per-client filter + queue | ~5ms | GDScript |
| Emit / network | ~10ms | GDScript (with C++ helper) |
| Idle / buffer | ~10ms | — |

Total: ~50ms. Tight at scale. We can move more phases to
Julia/C++ as profiling dictates.

### 17.6 The polyglot FFI

`labs/polyglot-ffi/` is the long-term plan for in-process
language calls. Today it's a sketch (`README.md`,
`julia-runtime/`). When implemented:

- GDScript calls Julia functions directly (no HTTP).
- Julia calls back into GDScript for scene-related things.
- C++ GDExtensions register with Godot and are callable
  from GDScript.

This is the path that makes the three-tier runtime feel
like one runtime, not three.

### 17.7 What we don't do

- We don't try to write the whole server in C++ "for
  performance". GDScript is fine for 95% of the code.
- We don't try to move Godot's node/scene system to
  Julia. That would mean rewriting Godot.
- We don't introduce a fourth tier (Rust, Python,
  TypeScript) without a concrete need.

---

## 18. Migration path & milestones

### 18.1 Phasing overview

```
Phase 0 (current)        Phase 1                Phase 2
Pre-vertical-slice   →   State tree + sync  →   Geometric layer
                                               (icosahedral + Julia)

                            ↓                        ↓

Phase 3                Phase 4                Phase 5
Player-placed       →  LOD + predictive   →   Spherical worlds
content + cross-       prefetch               (planets)
shard sync

                            ↓

Phase 6
Quasicrystal
experimental
(if seams matter)
```

### 18.2 Phase 1 deliverables (the next 4-6 weeks)

**Goal:** Two clients can connect to a single shard on the
v1 spherical world (20km planet, 150km² continent, capital
city + biome variety) and see the same tree. Server ticks.
Diffs apply. Browser works.

Concrete deliverables:

1. **`state_tree.gd`** at `game/core/frame/kv/`. The
   content-hash tree primitive: `insert`, `delete`,
   `diff`, `apply_diff`, `hash`. With tests.
2. **`transport.gd`** at `game/core/net/`. WebSocket
   server + client. The wire protocol from §10.3.
3. **`tick.gd`** at `game/core/net/`. The 20Hz tick loop
   that:
   - Reads root.
   - Applies inputs.
   - Computes new hash.
   - Diffs.
   - Filters per client.
   - Sends.
4. **`aoi.gd`** at `game/core/net/`. Interest management.
5. **`snapshot.gd`** at `game/core/net/`. Initial snapshot
   - reconciliation.
6. **V1 world manifest**: spherical, 20km planet radius,
   one 150km² continent with capital at center, biome
   layout per §3.9. Loaded from `data/worlds/v1.tres` or
   similar.
7. **Capital city + starter zones**: at least 4 hand-
   authored regions (capital, plains/forest, lake/river,
   mountain ridge) with manual content placement. NO
   procedural gen yet — the variety comes from
   hand-authored content for Phase 1.
8. **Test**: `tests/test_sync_deterministic.gd` — two
   clients, same seed, same input sequence, same final
   state hash.
9. **Test**: `tests/test_browser_connect.gd` — a synthetic
   browser client connects via WebSocket, receives
   snapshot, plays for 1000 ticks, ends with same hash as
   server.
10. **Test**: `tests/test_bandwidth_budget.gd` — measures
    actual per-client bandwidth (with LZ4 + permessage-
    deflate + binary frames). Verifies the §11.10 number
    holds. **This is the test that gates the
    "commodity VPS" promise.**
11. **Test**: `tests/test_geometric_layer_roi.gd` — measures
    orchestrator.query vs state_tree.scan at 100, 1K, 10K,
    100K entities. **Decides whether the geometric layer
    earns its place in Phase 2.** No committing to Phase 2
    until we have real numbers.
12. **Test**: `tests/test_node_based_simulation.gd` —
    measures per-entity signal cost at 100, 1000, 5000
    entities. **Tells us when we need to introduce ECS
    (§9.13).** Phasing: ECS primitive in /labs/ at Phase 2;
    player sim moves to ECS in Phase 3.

**Exit criteria for Phase 1:**
- Two browser clients (real Godot HTML5 export) can play
  together for 5 minutes without diverging.
- 1000-tick test passes.
- Code coverage on the core (state tree + sync) > 80%.
- Bandwidth budget: actual measured ≤ 100KB/s/client
  (target: 60-100KB/s, see §11.10).
- Geometric layer ROI: data point on the break-even curve.
- Simulation cost: data point on the per-entity curve.

**If any of these fail, Phase 1 doesn't exit.** We
iterate until the numbers support the design.

### 18.3 Phase 2 deliverables

**Goal:** Geometric layer + Julia orchestrator wired in.

1. **NSC-9 codes per entity**: spatial + faction + class +
   party + guild axes.
2. **`MultiIsoService`** upgraded to use batch_update +
   materialize endpoints.
3. **Materialized intersection cache** in Redis. LRU 1000
   entries.
4. **Procedural generator** (Phase 1 minimum): one pass
   (terrain_height) generating heightmaps deterministically.
6. **Test**: same-seed, two-chunk gen produces identical
   hashes. Multi-axis intersect query is O(k).

### 18.4 Phase 3 deliverables

**Goal:** Player-placed content + cross-shard sync.

1. **Player-placed subtree** in the state tree.
2. **`place_structure` command + validation**.
3. **Coordinator process** (separate binary) with its own
   state tree + Postgres.
4. **Shard ↔ coordinator diff protocol** (HTTP).
5. **Guild + faction cross-shard sync**.
6. **Test**: ankh placed on shard 1 is visible on shard
   2's map for guild members.

### 18.5 Phase 4 deliverables

**Goal:** LOD + predictive prefetch.

1. **LOD manager** running at 10Hz.
2. **Promotion/demotion** triggers wired.
3. **Markov predictor** with per-player history.
4. **Predictive prefetch** promoting chunks before the
5   player arrives.
6. **Test**: predict next chunk with >70% accuracy over
   1000 ticks.

### 18.6 Phase 5 deliverables

**Goal:** Spherical worlds.

1. **Spherical projection** (icosahedral mesh subdivision).
2. **Wrap-around handling** (lon mod 360°).
3. **Subdivision-level switching** at LOD promotion.
4. **Test**: spherical world produces consistent chunks
   at all latitudes (especially near poles).
5. **Test**: lon-wrap chunk is the same on both sides of
   the antimeridian.

### 18.7 Phase 6 (deferred)

**Goal:** Quasicrystal experiment (if seams matter).

1. **Penrose tiling** address space.
2. **Multi-scale addressing**.
3. **Render test**: visible seams vs icosahedral.

Only pursued if Phase 5 ships with visible seams.

### 18.8 Phase 0 cleanup (do alongside Phase 1)

Before/while implementing Phase 1:

- Fix the 22 autoload cascade failures (use shim approach
  from `autoload-race-solutions.md`).
- Rename `game/core/state/state.gd` to `game/core/state/
  fsm_state.gd` to free up `state.gd` for the content-hash
  tree node type.
- Migrate the existing ZoneManager spawn point data into
  the state-tree path (`chunks.<addr>.>.spawns`) so we
  have a precedent for the migration.
- Add `seed` column / field to all entity types.

---

## 19. Risks, open questions, deferred items

### 19.1 Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Godot HTML5 export has a perf cliff | Medium | High | Profile early in Phase 1; have a "browser-lite" client mode (less AOI, lower LOD) |
| WebSocket throughput on browsers is insufficient | Low | Medium | LZ4 compression + permessage-deflate + binary frames. Native fallback to ENet for power users |
| Postgres schema migrations break on running shards | Medium | High | Forward-only migrations; tested against a staging shard before prod |
| Procedural determinism fails on some platform | Medium | High | Phase 1 test gate: two-platform determinism check |
| Julia HTTP bridge is too slow | Low | Low | polyglot-ffi in Phase 4+ |
| LOD pyramid mispredicts, causes stutter | Medium | Medium | Phase 4 has its own test for prediction accuracy |
| Cross-shard conflict resolution causes lost updates | Low | Medium | Coordinator's last-write-wins is correct for our use cases; rare enough to accept |
| 200km² target is unreachable on commodity hardware | Low | Medium | We can shrink to 50km² at any point; configuration not code change |

### 19.2 Open questions (resolved 2026-09-05)

| Question | Resolution | Recorded in |
|---|---|---|
| Planar vs spherical for v1? | **Spherical as default; planar supported.** | §3.12 |
| 200 km² vs 40,000 km² vs other? | **v1: 20 km planet, 150 km² continent.** v2: 100 km, v3: 1000+ km. | §3.9, §3.11 |
| Open world vs instanced-first for v1? | **Open world first; instances for dungeons / special islands / arenas / etc.** | §3.9, §8.5 |
| Coordinator: separate process or just a flag? | **Separate process** (per §2.1, §16). | §2.1 |
| Materialized intersection cache size? | **LRU 1000 entries in Redis** (per §13.4); measured and tuned in Phase 2. | §13.4 |
| Native client ENet fallback? | **Phase 2+**; native clients can opt into direct P2P UDP/TCP. | §10.10.3 |

All Phase 1 entry decisions are now made. Phase 1 can
begin.

### 19.3 Deferred items (updated 2026-09-05)

- **P2P chunk sync**: PROMOTED from deferred to **active
  Phase 2** (see §10.10). User flagged as high-leverage.
- **Jolt Physics** swap-in: deferred to Phase 5+ per PRD.
- **Quasicrystal experimental**: deferred to Phase 6; only
  pursued if icosahedral seams become user-noticeable.
- **CDN for static chunks**: PROMOTED to **Phase 1+**
  (see §11.11.4); cheap to ship, big bandwidth win.
- **Edge shards** (world cache): deferred to Phase 4+;
  only needed at >5000 active players per shard.
- **CRDT for cross-shard state**: deferred to Phase 4+
  (see §12.11); Phase 1-3 use last-write-wins.
- **MCP / agent observation** beyond `client_type: agent`
  flag in HELLO: deferred. Wire protocol is Phase 1-ready;
  richer observation semantics is a later project.
- **Mobile native clients** (Android/iOS): deferred.
  Browser (HTML5/wasm) is the v1 target; native comes
  after browser is proven.

---

## 21. Experimental angles (post-Phase-1 research)

After the Phase 1 numbers land, we have a baseline. The
following experimental angles are the "if the baseline
isn't good enough" research directions. Each has a phase
assignment, a cost estimate, and a measurement that would
trigger adopting it.

> **Research companion:** Each angle below is researched in
> depth in `world-building-research.md` (10 sections, one
> per angle, plus a cross-angle synthesis). The summaries
> here stay tight; the deep dives live there. When research
> concludes, the result migrates back into this section.

### 21.1 Quasicrystal address space (Penrose / Ammann-Beenker)

**Phase**: 6 (deferred; only pursued if icosahedral seams
are user-noticeable).

**Hypothesis**: a Penrose (or Ammann-Beenker) aperiodic
tiling as the address space gives:

- No visible seams (no periodicity to wrap around).
- Multi-scale hierarchical structure naturally.
- Better space-filling than icosahedral (no anisotropy;
  corner cells as "normal" as center cells).

**Cost**:

- Address-space operations are non-trivial (no simple
  `(x, y)` → cell id; need matching-rule machinery).
- Rendering is harder (non-uniform mesh sizes; need
  tessellation library).
- Less prior art in games.
- Initial prototype: 2-4 weeks of pure-Python work in
  `game/core/frame/math/penrose_prototype/`.

**Trigger to adopt**: Phase 5 ships with user-noticeable
seams. We have no real evidence yet that icosahedral at
subdivision level 7 (62m chunks) will seam — that's a
Phase 5 measurement.

**Status**: research-only until Phase 5. No code in
game/.

### 21.2 Edge shards (world cache layer)

**Phase**: 4+ (after central-server scaling proven).

**Hypothesis**: thin "edge shard" processes near clients
do AOI filter + chunk gen + prediction, forwarding only
aggregate state to the central shard. Same pattern as CDN
but for game state.

**Cost**:

- New process type (the edge shard).
- Subset-of-state-tree subscription mechanism (we
  currently assume the shard owns its full partition).
- State consistency: edge shard sees slightly stale state
  relative to the central shard. Acceptable for most
  reads; not acceptable for combat.

**Trigger to adopt**: >5000 active players per shard, or
a single shard's bandwidth exceeds 100MB/s outbound.

**Status**: sketched in §11.13. No code yet.

### 21.3 Adaptive chunk size (LOD-by-content)

**Phase**: 5+.

**Hypothesis**: instead of fixed 64m chunks, use chunk
size based on content complexity. Empty ocean = 1km
chunks. Dense city = 16m chunks. The icosahedral mesh
supports this naturally via mixed subdivision levels.

**Cost**:

- Address-space code becomes more complex (variable chunk
  size).
- Hierarchical instancing (§7.12) needs to handle
  variable-size transforms.
- LOD transitions between subdivisions need visual
  stitching logic.

**Trigger to adopt**: Phase 5 profiling shows 90% of
chunks are mostly empty (vast ocean, flat plains) and the
per-chunk overhead is dominant.

**Status**: design-level only.

### 21.4 LOD-by-type

**Phase**: 5+.

**Hypothesis**: distant trees are billboards; distant
mountains are low-poly meshes; distant cities are colored
dots on the world map. The LOD pyramid doesn't have to be
one shape-fits-all.

**Cost**:

- Per-type LOD configuration (designer input).
- Mesh-LOD libraries (LOD generator, edge-collapse).
- Cross-LOD seam avoidance.

**Trigger to adopt**: Phase 5 GPU profiling shows we're
vertex-bound, not draw-call-bound.

**Status**: design-level only.

### 21.5 Merkle suffix trees (MST)

**Phase**: 4+ (research; pure-Python prototype in /labs/).

**Hypothesis**: replace the path-keyed state tree with a
**suffix-tree-of-hashes** structure. Same hash invariant,
but locality-of-reference means:

- "All entities in chunk X" is one subtree with one root
  hash.
- A chunk diff is O(chunk_size), not O(tree_size).
- Better cache behavior on iteration.

**Cost**:

- New data structure (replaces the simple path-keyed
  tree).
- Need to maintain the path-keyed API for compatibility
  with everything that already uses it.
- Diff format may change (affects the wire protocol).

**Trigger to adopt**: Phase 4 profiling shows diff cost
is dominant and we need sub-linear diffs.

**Status**: research-only. No code yet.

### 21.6 Algebraic effects / lenses for state diffs

**Phase**: 4+ (research; pure-Python prototype in /labs/).

**Hypothesis**: treat the state tree as a tree of lenses.
The diff is just the composition of modified lenses.
O(modified), not O(state).

**Cost**:

- New abstraction (lenses are not natural in GDScript).
- Storage layer has to know which lenses depend on which.
- Per-lens hash recomputation, which is more frequent
  than the current per-tree hash.

**Trigger to adopt**: same as 21.5 (diff cost dominant).

**Status**: research-only.

### 21.7 Jolt Physics swap-in

**Phase**: 5+.

**Hypothesis**: Jolt Physics (already in
`labs/jolt-playground/`) is faster and more deterministic
than Godot's default Physics3D. Replaces the physics
backend without changing the rest of the engine.

**Cost**:

- Replace Godot's physics bodies with Jolt equivalents.
- Re-test all combat, collision, and movement code.
- Engine integration work.

**Trigger to adopt**: Phase 5 profiling shows physics is
a bottleneck, OR we need determinism that Godot's
physics doesn't provide.

**Status**: prototype exists in `labs/jolt-playground/`.
Not integrated.

### 21.8 Polyglot FFI (GDScript ↔ Julia ↔ C++ in-process)

**Phase**: 4+.

**Hypothesis**: replace the HTTP bridge to Julia with
direct in-process FFI. Same for C++ GDExtensions. Single
runtime, three languages, no marshalling.

**Cost**:

- New build system for mixed-language binaries.
- Per-language lifecycle management.
- Debugging is harder (cross-language stack traces).

**Trigger to adopt**: HTTP bridge latency becomes a
bottleneck (probably 1-2ms per call adds up at 20Hz
tick). The state tree + Julia orchestrator will hit this
in Phase 3.

**Status**: sketch in `labs/polyglot-ffi/`. README only.

### 21.9 Adaptive tick rate (per-player)

**Phase**: 5+.

**Hypothesis**: not all players need 20Hz. A player who's
AFK in town for 10 minutes doesn't need 20Hz updates of
the world; their entity state can update at 1Hz. A player
in active combat needs 20Hz+.

**Cost**:

- Per-player tick-rate tracking.
- Subscription adjustment based on tick rate.
- Server-side scheduling (a player on 1Hz tick rate
  doesn't get every STATE_DIFF frame).

**Trigger to adopt**: Phase 5 profiling shows we're
spending significant CPU on AFK players.

**Status**: design-level only.

### 21.10 Pure-function-of-state for all gameplay

**Phase**: 3+ (gradual).

**Hypothesis**: every gameplay mutation is a pure
function of (current state, command, RNG seed) → (new
state, command result, next RNG seed). No hidden state,
no side effects. This means:

- Easy to test (same input → same output).
- Easy to rewind (for lag compensation, for debugging).
- Trivially serializable for save/load.

**Cost**:

- Discipline. Every service must be refactored to be
  pure.
- Some "convenient" patterns become forbidden (e.g.
  shared mutable caches).

**Trigger to adopt**: as soon as we start having
debugging pain. The current Node-based code already
shows this (state scattered across components).

**Status**: aspirational. Phase 1-2 will violate this
frequently; Phase 3+ moves toward it.

### 21.11 Why we have a §21 at all

Each of these ideas is a real research direction. The
point of §21 is **not** to commit to all of them — it's
to **catalog them so we don't lose them**. When Phase 5
or 6 shows that we need a particular angle, we don't
have to re-derive the idea; we have it here with phase,
cost, and trigger documented.

If a new idea comes up during Phase 1-4 work, it goes
here with the same treatment.

---

## 20. Glossary

- **AOI** — Area of Interest. The volume around a player
  that the server sends diffs for. Default 100m radius.
- **AABB** — Axis-Aligned Bounding Box. Used for spatial
  bounds (planar maps).
- **Address cell** — The unit of the address space (chunk
  for planar, icosahedral face for spherical). The state
  tree, the LOD pyramid, and the geometric layer all key
  off this.
- **Chunk** — 64m spatial unit (planar) or ~62m triangular
  unit (spherical). The LOD pyramid's smallest cell.
  Content-hashed and immutable once promoted.
- **Coordinator** — The cross-shard process. Owns guilds,
  factions, character master records, world events.
- **Diff** — The list of state-tree changes between two
  root hashes. The unit of sync.
- **Grail path** — Read = lookup, write = command.
  Materialize intersections; don't compute at query time.
- **Hash** — SHA-256 of (canonical_encoding(value) ||
  hash(parent)). The Merkle property.
- **HLC** — Hybrid Logical Clock. Used in cross-shard
  conflict resolution. Vector clock + wall-clock.
- **Instance** — A scoped subtree of the state tree with
  its own seed and lifecycle. Used for dungeons, party
  halls, arenas.
- **LOD** — Level of Detail. L0 = full, L1 = summary, L2 =
  cold, L3 = archived.
- **L1/L2/L3 storage tier** — In-memory / on-disk / Redis /
  Postgres. (This conflicts with LOD levels; in context,
  we always say "tier L0" vs "LOD level L0".)
- **Manifest** — The world's metadata: shape, seeds,
  shard partitions. Read by all shards on boot.
- **NSC-9** — A 12-digit code (`9-AAA-BBB-CCCCCC`)
  encoding facility, axis, and sequence per entity.
- **Pass** — A single step in the procedural pipeline
  (terrain, biome, poi, mob_spawn, …).
- **Shard** — A horizontal scaling unit of the world. One
  process. One spatial partition.
- **State tree** — The content-hash persistent tree that
  holds all game state. The substrate for sync, frame services,
  LOD, generation.
- **Tick** — One 50ms cycle of the server. The only place
  where authoritative state changes.
- **VOI** — Volume of Interest. Same as AOI; we use both
  interchangeably.
- **VOI-extend** — A temporary expansion of AOI (scouting,
  map view, etc.).
- **World seed** — The root seed for an entire world.
  Immutable. Source of all open-world determinism.

---

*End of plan.*