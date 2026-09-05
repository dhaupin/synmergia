# World-Building Research

> **Status:** Research companion to `world-building.md`. When
> the implementation pace permits, this is the place to dig
> into §21's experimental angles. When implementation is
> blocked on rate limits (or anything else), this is where
> the thinking happens.
>
> **Scope:** Each of the 10 experimental angles from
> `world-building.md §21` gets a research section here with:
> hypothesis, math/background, prototype sketch, prior art
> references, expected cost, trigger-to-adopt, and current
> status. Plus a cross-angle synthesis at the end: which
> ideas compose.
>
> **Why a separate file:** keeps the main plan stable
> while research churns. The main plan commits to a path;
> this file explores alternatives without disturbing the
> plan. When research concludes (idea is viable, idea is
> dead, or we don't know yet), the result migrates back
> into the main plan as a §21 update.

---

## Table of Contents

1. [Quasicrystal address space (Penrose / Ammann-Beenker)](#1-quasicrystal-address-space-penrose--ammann-beenker)
2. [Edge shards (world cache layer)](#2-edge-shards-world-cache-layer)
3. [Adaptive chunk size (LOD-by-content)](#3-adaptive-chunk-size-lod-by-content)
4. [LOD-by-type](#4-lod-by-type)
5. [Merkle suffix trees for diffs](#5-merkle-suffix-trees-for-diffs)
6. [Algebraic effects / lenses for state diffs](#6-algebraic-effects--lenses-for-state-diffs)
7. [Jolt Physics swap-in](#7-jolt-physics-swap-in)
8. [Polyglot FFI (GDScript ↔ Julia ↔ C++)](#8-polyglot-ffi-gdscript--julia--c)
9. [Adaptive tick rate (per-player)](#9-adaptive-tick-rate-per-player)
10. [Pure-function-of-state for all gameplay](#10-pure-function-of-state-for-all-gameplay)
11. [Cross-angle synthesis: which compose](#11-cross-angle-synthesis-which-compose)

---

## 1. Quasicrystal address space (Penrose / Ammann-Beenker)

**Phase assignment** (from `world-building.md §21.1`):
Phase 6 — only pursued if icosahedral seams become
user-noticeable. Currently research-only.

### 1.1 The hypothesis

Aperiodic tilings (Penrose, Ammann-Beenker) give us
address-space properties that periodic tilings (square,
hex, icosahedral) cannot:

- **No visible seams.** No periodicity, no wrap-around.
  Players walking in any direction never see a
  repeating pattern.
- **Multi-scale hierarchical structure naturally.** A
  Penrose tiling at one scale is the *same tiling* at
  another scale (with the inflation/deflation rules).
  Parent cells contain child cells by the deflation
  rules; no separate hierarchy design needed.
- **Better space-filling than icosahedral.** The
  icosahedral mesh has anisotropy: face centers are
  "normal" but vertices and edges are not. Quasicrystal
  tiles are all congruent (modulo matching rules), so
  no place is structurally privileged.
- **Self-similar locality.** A region of radius r in
  the tiling has the same *internal structure* at every
  scale. This means "what's around me" looks the same
  whether I'm standing in a small clearing or a vast
  plain.

### 1.2 The math, briefly

**Penrose P3 tiling** (rhombus version): two rhombus
prototiles — fat (72°/108°) and thin (36°/144°) — that
tile the plane aperiodically. Matching rules force the
aperiodicity: you can't place the rhombi in any
old pattern, only in patterns that satisfy the
"dart-and-kite" matching constraints.

**Inflation/deflation**: there's a linear map that takes
a Penrose tiling to a "scaled-up" version of the same
tiling (inflation), and the inverse (deflation). The
inflation factor is `φ²` (where `φ = (1 + √5) / 2`,
the golden ratio). This is what gives the multi-scale
hierarchy.

**Address scheme**: a Penrose tile at scale `n` has a
unique **window sequence** — a finite string over a
small alphabet that locates it within the inflation
hierarchy. Two adjacent tiles have related sequences
(differing by one letter). The address is logarithmic
in the scale, not polynomial like `(x, y, z)`.

**Ammann-Beenker tiling**: similar idea but with octagonal
symmetry (45° rotations). Better for square-ish
arrangements. Inflation factor is `1 + √2`.

### 1.3 Why this is interesting for Synmergia

The user explicitly flagged the "what about
non-icosahedral addresses?" question. Quasicrystals are
the most rigorous answer:

- A **spherical** Penrose tiling: project the planar
  Penrose tiling onto a sphere via some gnomonic or
  stereographic projection. The aperiodicity is
  preserved; we get a sphere with no poles-as-singular.
- **Hierarchical content placement** without separate
  hierarchy design: the inflation tree IS the
  hierarchy. A "region" in the game is a Penrose tile
  cluster at some scale; sub-regions are deflated
  children; POIs are leaves. The game designer reasons
  about the Penrose structure, not about chunk grids.
- **LOD comes for free**: scale n=0 of the inflation
  is the LOD-3 summary; scale n=k is LOD-0. Different
  scales of the same address space; no separate LOD
  logic.
- **No AABB assumption**: queries like "what's near
  me" use the tiling's natural neighborhood, which is
  always a "normal" neighborhood (no special cases for
  poles, edges, corners).

### 1.4 The catch

This is genuinely hard:

- **Address operations are non-trivial.** No simple
  `(x, y)` → tile id. Need to implement the
  Robinson-style decomposition: given a point, find the
  tile containing it. The naive algorithm is O(log n)
  per point using the window sequence; faster
  implementations exist but are involved.
- **Rendering is harder.** Non-uniform mesh sizes;
  need a tessellation library that handles Penrose
  tiles. The `penrose` and `quasiperiodic` libraries
  in Python/JS exist but aren't production-grade.
- **Less prior art in games.** I can find 0 commercial
  games using aperiodic tilings for the world address
  space. Procedural-texture research uses them, but
  the world is built on periodic grids.
- **Hierarchical instancing (§7.12) interaction is
  unclear.** Penrose tiles at different scales have
  different *shapes* (the inflation multiplies
  rhombi), so the "type" concept might not compose
  cleanly with the "instance" concept.
- **Authoring tools are nonexistent.** Designers
  would need a new tool to place content in
  Penrose-tiled space.

### 1.5 Prototype sketch

Pure-Python prototype in `labs/multi-iso/math/penrose/`
(planned):

```
penrose/
├── tile.gd              # tile types, matching rules
├── window.gd            # window-sequence encoding
├── inflate.gd           # inflation / deflation
├── point_to_tile.gd     # Robinson decomposition
├── neighborhood.gd      # adjacent-tile queries
├── test_penrose.gd      # unit tests
└── README.md
```

Test cases:
- `test_penrose_inflation_idempotent`: inflate twice
  should equal a single inflation at the higher scale.
- `test_penrose_matching_rules_satisfied`: every
  constructed tiling satisfies dart-kite matching.
- `test_penrose_point_to_tile_is_robust`: a point at a
  tile boundary returns one of the bordering tiles
  deterministically.
- `test_penrose_neighborhood_is_symmetric`: if A is
  adjacent to B, then B is adjacent to A.

If this prototype shows:
- Sub-millisecond point-to-tile queries at game scale.
- A clean neighborhood definition.
- A composable inflation tree.

...then we can think about Phase 6.

If it shows:
- Algorithm complexity is too high.
- Hierarchical instancing breaks.
- Rendering requires a custom tessellator.

...then we kill the idea and document the negative
result.

### 1.6 Prior art

- **De Bruijn's Penrose tiling via multigrids** (1981):
  the standard mathematical construction. Algorithm in
  ~50 lines.
- **Penrose tilings and quasicrystals** (various
  textbooks): the canonical references.
- **Robinson's decomposition** (1975): the
  point-to-tile algorithm.
- **Ammann tilings** (Grünbaum & Shephard, 1987):
  aperiodic tilings taxonomy.
- **PatternBoost** and other procedural-texture libs
  use Penrose in 2D textures, but for surface
  decoration, not world structure.
- I have not found a game using Penrose for the
  world address space. **If anyone reading this knows
  of one, please share** — would be relevant prior art.

### 1.7 Expected cost

If pursued:
- Pure-Python prototype: 2-4 weeks.
- GDScript port: 1-2 weeks.
- Tessellation library: 2-4 weeks.
- Authoring tool: 2-6 weeks.
- Integration test: 2-4 weeks.
- Total: ~3-6 months of dedicated work.

If abandoned at prototype stage: 2-4 weeks wasted.

### 1.8 Trigger to adopt

Phase 5 ships with user-noticeable seams in the
icosahedral mesh. The icosahedral mesh has known
issues at the 12 vertices of the icosahedron
(5-face junctions) and at subdivision level boundaries.

If 5-10% of players in user testing notice the seams
without prompting, we have a problem. If they don't
notice without prompting, the seams are not a real
issue and Phase 6 doesn't happen.

### 1.9 Current status

- Research: started in this document.
- Prototype code: not yet.
- Performance numbers: not yet.
- Decision: pending Phase 5 user-testing data.

---

## 2. Edge shards (world cache layer)

**Phase assignment** (from `world-building.md §21.2`):
Phase 4+. Trigger: >5000 active players per shard OR
>100MB/s outbound per shard.

### 2.1 The hypothesis

A thin **edge shard** process sits near the clients and
does:
- AOI filter (already on the central shard, but moving
  the per-client filter to the edge cuts central outbound
  bandwidth).
- Chunk generation (move it off the central shard;
  pre-gen cache lives on the edge).
- Markov prediction (close to the player, so prediction
  is more accurate).
- Static chunk CDN-style caching (already content-hashed;
  the edge shard serves chunks from a local LRU cache).

The **central shard** then only sees:
- Authoritative state changes (player inputs, mob
  deaths, loot drops, etc.).
- Aggregate metadata (chunk hash sets per region, for
  fan-out).
- Heartbeat/health from edge shards.

The architecture becomes a **two-tier system**: one
central authority + many edge caches.

### 2.2 Why this is interesting for Synmergia

CDN architecture for the open web works because static
content can be cached near users. Game state is harder
because it changes, but **static content within game
state** (the chunks, the assets, the world geometry) is
immutable once generated. The dynamic layer (mob
positions, player positions, effects) is small per-edge.

For 100 clients in a busy area:
- **Centralized model** (current): central shard sends
  100× the same chunk diffs. 100× outbound bandwidth on
  the central shard.
- **Edge model** (proposed): central shard sends 1
  chunk diff to the edge; edge fans out to its 100
  clients. 1× outbound on central, 100× on the edge
  (but the edge is local to the clients, so this
  bandwidth is cheap).

For 10,000 active players on a shard, this is the
difference between "needs a beefy central server" and
"works on commodity hardware".

### 2.3 The math, briefly

Let:
- `N` = number of active clients on a shard.
- `C` = number of distinct chunks in their combined AOI.
- `D` = per-tick diff size per chunk.
- `B` = outbound bandwidth per shard.

**Centralized**: `B = N × C × D / T` (where T = tick
interval). For N=1000, C=100, D=1KB, T=50ms: `B = 2 GB/s`.
Commodity hardware can't do that.

**Edge-cached**: central sends `B_central = C × D / T = 2
MB/s`. Each edge (serving 100 clients) sends `B_edge = 100
× C × D / T = 200 MB/s` to its clients. The edge is
co-located with the clients (same datacenter, often same
machine), so 200 MB/s is fine.

So edge caching cuts central bandwidth by `N` (1000x in
this example). The trade-off: each edge needs to subscribe
to the central's state tree, which means central has
1× outbound per edge (much smaller than 1× per client).

### 2.4 The catch

- **State consistency.** The edge shard sees the
  central's state with some lag (maybe 50-200ms). For
  most game state this is fine (player positions are
  fuzzy anyway). For combat (hit detection) it's not
  fine — combat needs authoritative, current state.
  The edge shard forwards combat-relevant state changes
  to the central immediately; the central arbitrates.
- **Edge process failure.** If an edge shard crashes,
  its 100 clients disconnect. Central has to
  re-assign them to other edges. Failover complexity.
- **State tree subset subscription.** We currently
  assume each shard owns its full spatial partition.
  Edge shards would need a way to subscribe to *parts*
  of a central shard's state tree, with diffs emitted
  on changes. This is essentially "sub-shard" — a new
  granularity in the architecture.
- **AOI on the edge vs central.** The central still
  needs to know AOI centers for cross-shard awareness
  (so two clients on different edges can interact).
  Either edges report AOI to central, or central gets
  approximate AOI from cross-shard visibility rules.

### 2.5 Prototype sketch

`labs/multi-iso/srv/edge_shard.gd` (planned). A
simplified version:

```
edge_shard/
├── edge_transport.gd        # WebSocket + WebRTC; subscribes to central diffs
├── edge_aoi.gd              # per-client AOI filter
├── edge_chunk_cache.gd      # LRU cache of chunks (content-hashed)
├── edge_predictor.gd        # Markov predictor (per-client)
├── edge_authority_proxy.gd  # forwards combat state to central
├── test_edge_shard.gd       # unit tests
└── README.md
```

Test cases:
- `test_edge_aoi_matches_central`: an edge filtering the
  same AOI as the central produces the same diff.
- `test_edge_chunk_cache_lru`: chunks evicted by LRU
  policy.
- `test_edge_subscribes_to_subset`: edge subscribes to
  N chunks; central only sends diffs for those N.
- `test_edge_failure_recovery`: edge crash → clients
  reconnect → state resumes from last acked tick.

### 2.6 Prior art

- **CDN architecture** (Akamai, Cloudflare, Fastly):
  the inspiration. The same patterns (caching, fan-out,
  edge nodes, TTL-based eviction) apply.
- **Multiplayer game server frameworks** (SpatialOS,
  Photon, PlayFab): have edge-relay components, but
  mostly for network relay, not for state caching.
- **MMO architecture references** (GDC talks on WoW,
  EVE, etc.): most use a "realm" + "shard" model but
  not edge caching. The "instance server" pattern in
  EVE is closest to what we propose.
- **Cloud gaming** (Stadia, GeForce Now): ran into
  similar bandwidth problems; their solution was
  rendering on the edge. We can do better because
  we control the state representation.

### 2.7 Expected cost

- Pure-Python prototype: 1-2 weeks.
- GDScript port + integration: 2-3 weeks.
- WebRTC + signaling: 1-2 weeks.
- Failure recovery + load balancing: 1-2 weeks.
- Total: ~6-8 weeks.

### 2.8 Trigger to adopt

Measured at >5000 active players per shard, OR >100MB/s
outbound from a single shard. At v1's 20km planet with
150km² continent, this probably doesn't happen until
we have a real player base. Phase 4+ by that point.

### 2.9 Current status

- Research: started in this document.
- Prototype code: not yet.
- Performance numbers: not yet (depends on Phase 1
  baseline).
- Decision: pending Phase 4 load measurements.

---

## 3. Adaptive chunk size (LOD-by-content)

**Phase assignment** (from `world-building.md §21.3`):
Phase 5+. Trigger: Phase 5 profiling shows 90% of chunks
are mostly empty.

### 3.1 The hypothesis

A fixed chunk size (64m cubes for planar, ~250m
icosahedral faces for spherical at level 5) is the same
size for the capital and for empty ocean. But the
**content density varies enormously**:
- Capital city: hundreds of entities, dense geometry,
  lots of state per 64m cube.
- Forest: hundreds of trees, but the *type* is shared
  (instatancing helps here).
- Plains: a few mobs, some resources.
- Ocean: empty. The 64m cube contains exactly one mesh
  (water) and zero entities.

For the empty ocean, the chunk overhead is 100% of the
work; the actual content is 0%. We're paying 50KB of
state tree overhead per chunk for content that doesn't
need any state.

**Adaptive chunk size** says: make the chunks bigger
where there's less to store. Empty ocean gets 1km chunks
(16x fewer chunks for the same area). Dense city gets
16m chunks (16x more chunks for the same area). The
icosahedral mesh supports this naturally via mixed
subdivision levels.

### 3.2 The math, briefly

For a 200km² planar world with:
- 50 km² of dense city/forest: 16m chunks = 1,953,125 chunks.
- 150 km² of empty ocean: 1km chunks = 150 chunks.

Compare to fixed 64m chunks: 48,828 chunks for the
whole world.

The adaptive version is 1.95M chunks but the city ones
are tiny (mostly empty) and the ocean ones are huge but
also empty. The **state tree size** stays similar; what
changes is the **granularity of updates**. A mob in the
city causes 1 chunk diff (16m cube); the same mob in the
ocean would have caused a 1km chunk diff (huge diff for
one mob). With adaptive chunks, both are 1 chunk.

Cost: the address-space code has to handle variable
sizes. Hierarchical instancing (§7.12) needs to handle
variable-size transform lists. LOD transitions between
subdivisions need visual stitching.

### 3.3 The catch

- **Address-space complexity.** `(x, y) → chunk_id` is
  no longer a simple division. Need a tree structure
  (octree for planar, subdivision tree for spherical)
  that knows which regions are subdivided finer.
- **Hierarchical instancing interaction.** If a forest
  is at 16m chunks, instances are in 16m chunks. If we
  promote the same area to 64m chunks later (because
  density dropped), the instances need to migrate. This
  is doable but adds state-tree work.
- **LOD transitions.** When a player walks from a dense
  16m-chunk area to a sparse 1km-chunk area, there's a
  visible "step" in the world's address granularity.
  Visual stitching hides this (we already have LOD
  transitions for mesh detail).
- **Designer ergonomics.** "Where do I place this
  building?" is harder when chunks have variable size.
  Authoring tools have to render the subdivision
  structure visually.

### 3.4 Prototype sketch

`labs/multi-iso/math/adaptive_chunks.gd` (planned).
Likely a sparse octree (planar) or sparse subdivision
tree (spherical). Test cases:
- `test_octree_subdivides_only_dense_regions`: an octree
  with density threshold subdivides correctly.
- `test_point_to_chunk_octree`: a point lookup returns
  the correct cell at the correct depth.
- `test_lod_transition_visual_stitching`: a transition
  between two subdivision levels doesn't have a visible
  seam in the rendered mesh.

### 3.5 Prior art

- **Sparse voxel octrees** (mikola/lyons et al., game
  industry standard for "infinite worlds"): the
  canonical adaptive subdivision structure.
- **GeoTIFF / quadtrees** (GIS): the same idea for
  spatial data; lots of existing libraries.
- **The whole LOD industry** is a form of this
  (mesh-LOD is a special case).

### 3.6 Expected cost

- Octree + tests: 1-2 weeks.
- Address-space refactor: 2-3 weeks.
- Visual stitching: 1-2 weeks.
- Total: ~4-6 weeks.

### 3.7 Trigger to adopt

Phase 5 profiling: 90% of chunks in v1's 20km planet
are mostly empty (vast ocean + flat plains). At that
point, the per-chunk overhead is dominant and adaptive
chunks would save 10-100x on the empty regions.

### 3.8 Current status

- Research: started.
- Prototype code: not yet.
- Performance numbers: not yet.
- Decision: pending Phase 5 profiling data.

---

## 4. LOD-by-type

**Phase assignment** (from `world-building.md §21.4`):
Phase 5+. Trigger: GPU profiling shows we're
vertex-bound, not draw-call-bound.

### 4.1 The hypothesis

The LOD pyramid in `world-building.md §14` is one
shape-fits-all: every chunk's L0 is the full mesh, L1
is a summary, etc. But different content types want
different LOD shapes:

- **Trees**: a distant tree is a billboard. A near tree
  is a 3D mesh. The "summarize" step (L1) for trees is
  just a count.
- **Mountains**: a distant mountain is a low-poly mesh.
  A near mountain is a high-poly mesh. The L1 summary
  is a low-poly mesh, not just a count.
- **Cities**: a distant city is a colored dot on the
  map. The L1 summary is the dot.

Forcing all content types through the same LOD shape
(just "count + position") wastes the LOD opportunity for
content that has rich L1 representations (mountains,
buildings) and over-summarizes content that's already
simple (trees, mobs).

**LOD-by-type** says: each content type defines its own
LOD ladder. The LOD pyramid's "this chunk at L1"
becomes a *vector* of L1 representations, one per type.

### 4.2 The math, briefly

For a chunk with 1000 oaks, 200 rocks, 50 mobs, 1
building:

**Current LOD (count-only L1)**:
- L0: 1000 oak meshes + 200 rock meshes + 50 mob meshes
  + 1 building mesh = ~30MB.
- L1: just counts: `oaks: 1000, rocks: 200, mobs: 50,
  buildings: 1` = ~50 bytes.

**LOD-by-type**:
- L0: same as current.
- L1.oaks: billboard atlas (one mesh with all 1000
  trees as billboards, GPU-instanced) = ~50KB.
- L1.rocks: 200 low-poly rock meshes = ~200KB.
- L1.mobs: type histogram (no meshes) = ~100 bytes.
- L1.buildings: 1 simple cube = ~5KB.

Total L1: ~250KB. That's larger than count-only (50
bytes) but far smaller than L0 (30MB). The visual
fidelity at L1 is *much* higher than count-only.

For rendering: the renderer picks the right L1
representation per type, blends to L0 as the player
approaches. No "popping" because the L1 representations
are designed to look like the L0 from a distance.

### 4.3 The catch

- **Per-type LOD configuration.** Each entity type
  needs an LOD spec: "at distance D, render as X". This
  is designer input.
- **Mesh-LOD generation.** The low-poly L1 mesh for a
  mountain needs to be generated from the high-poly L0
  mesh. Tools like `meshoptimizer` or `Simplygon` do
  this; integrating them is a real task.
- **Cross-LOD seam avoidance.** When the player is
  exactly at the L0/L1 boundary, you can get Z-fighting
  or visual pop. Needs fade logic.
- **State tree bloat.** Per-type L1 data makes chunks
  larger at the L1 level. Worth it for the visual win,
  but not free.

### 4.4 Prototype sketch

Likely in `labs/multi-iso/kv/lod_by_type.gd`. Test:
- `test_l1_oak_count_matches_l0`: the L1 oak count
  matches the L0 oak count after promoting/demoting.
- `test_l1_mountain_low_poly_smaller`: the L1
  mountain mesh is 10-100x smaller than L0.
- `test_lod_transition_no_pop`: rendering the chunk
  at L0 and L1 side-by-side, the difference is below
  the perceptual threshold at the transition distance.

### 4.5 Prior art

- **Mesh LOD in every modern game** (Unreal's
  `MeshSimplifier`, Unity's LOD Group, Godot's
  `Mesh LOD`). Standard.
- **Billboard atlases** for distant objects (SpeedTree,
  various open-world games). Standard.
- **Per-type LOD ladders** (Shadow of the Colossus,
  various RTS games). The specific pattern is
  game-specific; not a general library.

### 4.6 Expected cost

- LOD spec schema + per-type configuration: 1-2 weeks.
- Mesh simplification integration: 2-3 weeks.
- Cross-LOD seam avoidance: 1-2 weeks.
- Total: ~4-6 weeks.

### 4.7 Trigger to adopt

Phase 5 GPU profiling: vertex-bound (GPU is at
100% vertex shading) but draw-call-bound is low.
This means we're spending GPU time on tiny meshes
that could be combined. LOD-by-type fixes this.

If we're CPU-bound or bandwidth-bound, LOD-by-type
doesn't help.

### 4.8 Current status

- Research: started.
- Prototype code: not yet.
- Decision: pending Phase 5 GPU profiling.

---

## 5. Merkle suffix trees for diffs

**Phase assignment** (from `world-building.md §21.5`):
Phase 4+. Trigger: diff cost is dominant in profiling.

### 5.1 The hypothesis

The path-keyed state tree (`world.surface.chunks.64_128_256.entities.player_42.position.x = 100`) is conceptually a tree but practically a hash map keyed by string paths. Diffing two states means comparing every path; that's O(N) where N is the number of paths in the tree.

For a v1 world with 20,000 chunks × 50KB each = 1GB of state, the path-keyed tree has ~1M paths. A diff between two ticks that change 1000 entities is O(1M) to compute — most paths are unchanged but we check them all.

**Merkle suffix trees** (MST) reorganize: instead of one tree per path, you have a *trie* of suffixes, where internal nodes are content-hashes and leaves are the actual values. Two nodes with the same hash are *trivially* equal, so the diff can skip entire subtrees by hash comparison.

The diff becomes O(modified) — we only walk down subtrees where the root hash differs. For 1000 changed entities in a 1M-path tree, the diff visits ~1000 paths plus some constant-time hash comparisons.

### 5.2 The math, briefly

**Path-keyed tree** (current): the entire state is a `Map[String, Bytes]`. To diff:
- Iterate all keys in old.
- For each key, look up in new. O(N).
- Iterate all keys in new not in old. O(N) in worst case.
- Total: O(N).

**Merkle suffix tree**: state is a trie where each node has `(hash, children: Map[Byte, Node])`. To diff:
- Recursively walk both tries.
- If `old_node.hash == new_node.hash`, return empty diff. O(1).
- If hashes differ, recurse into children. O(size of differing subtree).
- Total: O(K) where K = size of differing subtree.

For K ≪ N, this is a big win. K is roughly proportional to the number of *paths that actually changed*, which for a 20Hz tick is on the order of 100-10,000 paths (depending on player activity). N is 1M+.

Compression: the MST also compresses the *storage* because identical subtrees are represented once (content-hash dedup). Two chunks with the same content share the same internal nodes. This is a 10-100x compression for highly-procedural worlds.

### 5.3 Why this is interesting for Synmergia

Two big wins:

1. **Faster diffs at scale.** As the world grows (v2, v3), the total state grows, but the per-tick change set stays bounded by player activity. MST diffs are bounded by activity, not by state size. Phase 5+ scaling becomes much easier.
2. **Free content-hash dedup at the structural level.** Two identical forest chunks *automatically* share their internal MST nodes. State tree size doesn't grow linearly with chunk count; it grows with unique content.

### 5.4 The catch

- **New data structure.** The path-keyed tree is simple; the MST is more complex (trie operations, hash interning, subtree merge detection).
- **API compatibility.** All the code that does `state_tree.get("world.surface.chunks.64_128_256.entities.player_42.position.x")` would need a compatible interface. Easy to wrap; tedious to ensure.
- **Wire format impact.** The current wire format (§10.3) sends diffs as path-keyed entries. With MST, diffs are subtree replacements. The wire format needs to encode this. Not a huge change but real.
- **Snapshot format.** Snapshots are currently "all paths with their values". With MST, a snapshot is a single root hash + the tree under it. The tree can be lazy-fetched from the chunks table (each chunk is one subtree).

### 5.5 Prototype sketch

`labs/multi-iso/kv/merkle_suffix_tree.gd` (planned). A clean re-implementation:
- `MerkleSuffixTree` with `insert`, `delete`, `get`, `diff`, `apply_diff`, `hash`.
- Trie-based internal storage.
- Hash interning for dedup.
- Test cases: same as `state_tree.gd` (insert, delete, hash, diff, apply) plus:
  - `test_identical_subtrees_share_nodes`: two trees with the same subtree have the same hash.
  - `test_diff_skips_identical_subtrees`: diffing two trees that differ only in one subtree visits only that subtree.

### 5.6 Prior art

- **Merkle trees** in general (cryptography, Git, IPFS, Cassandra, etcd, blockchain). The hash-tree idea is old; the specific "suffix tree" optimization is novel.
- **HAMTs** (Hash Array Mapped Tries, used in Clojure, Scala, etc.): a related trie structure with structural sharing. Not content-hashed, but the same shape.
- **Persistent data structures** (Okasaki, every functional language): the structural-sharing idea.
- **Content-addressable storage** (Git, IPFS, Cas): the dedup-via-content-hash idea.
- I have not seen a content-hash + trie + suffix-tree combo in prior art. This is the novel bit.

### 5.7 Expected cost

- Pure-Python prototype: 2-3 weeks.
- GDScript port: 1-2 weeks.
- Wire format update: 1-2 weeks.
- API wrapper for backward compat: 1-2 weeks.
- Total: ~6-8 weeks.

### 5.8 Trigger to adopt

Phase 4 profiling: diff cost is dominant (e.g. >30% of
per-tick CPU is diff computation). At v1 scale (20km
planet, ~10K active entities), this probably doesn't
happen. At v2-v3 scale (1000km planet, 100K+ active
entities), it likely will.

### 5.9 Current status

- Research: started.
- Prototype code: not yet.
- Performance numbers: not yet.
- Decision: pending Phase 4 profiling data.

---

## 6. Algebraic effects / lenses for state diffs

**Phase assignment** (from `world-building.md §21.6`):
Phase 4+. Trigger: same as §5 (diff cost dominant).

### 6.1 The hypothesis

The state tree is "just" a giant nested key-value store. Diffing it is "compare every key". The MST (§5) optimizes by skipping identical subtrees. **Lenses** go further: instead of comparing keys, we track *which lenses* were touched in the current tick, and only those contribute to the diff.

A **lens** is a bidirectional value-transformer: it has a `get` (read from state) and a `set` (write to state). Lenses compose: a lens on `player_42.position` composed with a lens on `player_42` gives a lens on `player_42.position`.

The tick loop tracks which lenses were *used* in the tick (which entities, which fields). The diff is the set of all `set` calls on those lenses. The hash is recomputed only for the affected subtrees.

### 6.2 The math, briefly

For a tick that touches 1000 entities (player + mob updates):
- **Path-keyed diff**: O(N) where N = total paths in tree.
- **MST diff**: O(K) where K = affected subtree size.
- **Lens diff**: O(T) where T = number of lens operations in the tick (T ≤ K, often much less because each entity update might only touch 3-5 fields).

For a 1000-entity tick that updates positions and health (5 fields per entity), T = 5000. K is the affected subtree, ~1000 paths but bounded by entity-aggregate size. N is 1M+.

So lenses give another 5-10x reduction on top of MST, in the limit.

### 6.3 The catch

- **GDScript doesn't have first-class lenses.** This is a fundamental GDScript limitation. Lenses want a type system with higher-kinded types. We'd need a DSL or codegen.
- **Tracking lens usage has overhead.** Every read/write to a lens is recorded. If the per-lens overhead is 100ns, a tick with 5000 lens ops is 0.5ms of pure overhead.
- **Per-lens hash recomputation.** If a lens is touched, its containing subtree's hash needs recomputing. For a deeply nested tree, that's a chain of hash updates — fine if the path is short, expensive if it's deep.
- **Migration is invasive.** Every state access in the codebase has to go through a lens. There are hundreds of state accesses.

### 6.4 Why I'm skeptical

The MST (§5) gets most of the benefit (O(K) instead of O(N)) without requiring a lens-aware codebase. Lenses add a 2-5x improvement on top of MST, but at the cost of invasive code changes.

The pattern I'd actually recommend: **start with MST, see if it's enough**. If MST gets us to <5ms per diff, lenses are premature optimization. If MST is at 20ms+ and we need more, lenses are the next step.

### 6.5 Prior art

- **Lenses** (Foster et al., 2007, the bidirectional-programming paper). The standard reference.
- **Algebraic effects** (Plotkin & Pretnar, 2009). The closely related effect-system idea.
- **Functional reactive programming** (FRP, Elm, React, etc.): similar pattern in UI.
- **Incremental computing** (Demers, Aiken, et al.): the academic work on tracking which computations depend on which inputs.

### 6.6 Expected cost

- DSL for lenses: 2-4 weeks.
- Migration of state accesses: 4-8 weeks (big change).
- Performance validation: 1-2 weeks.
- Total: ~2-3 months.

This is the most invasive of the experimental angles. Realistically, it's a "we already shipped v3 and we're looking for the next 10x" optimization, not a Phase 1-4 thing.

### 6.7 Trigger to adopt

Same as §5 — diff cost is dominant — AND MST didn't get us close enough. Specifically: per-tick diff is >20ms in the v3 world (1000km, 100K entities) and MST brings it to 15ms. We need 5ms; lenses might get us there.

### 6.8 Current status

- Research: started.
- Prototype code: not yet.
- Decision: gated on MST (§5) outcomes.

---

## 7. Jolt Physics swap-in

**Phase assignment** (from `world-building.md §21.7`):
Phase 5+. Trigger: physics is a bottleneck OR we need
determinism.

### 7.1 The hypothesis

Jolt Physics (https://github.com/jrouwe/JoltPhysics) is
an MIT-licensed C++ physics engine used in Horizon games
and others. Benchmarks show it's 2-5x faster than
PhysX/Bullet on typical game workloads, with better
determinism (fixed-point math, predictable across
platforms).

Godot's default Physics3D is built on a different
backend. Swapping in Jolt (as a GDExtension) gives us
a faster, more deterministic physics engine without
changing the rest of Godot.

### 7.2 What's already in the codebase

`labs/jolt-playground/` already has a benchmark harness
for Jolt vs Godot's default physics. The agent (or
whoever ran it) noted that Jolt is faster and more
deterministic in the tested scenarios.

The decision to NOT integrate Jolt yet is "wait until
we have game code that actually needs the perf or
determinism." At v1, Godot's default physics is
probably fine for 100 entities. At v2-v3 with 10K+
entities and complex interactions, Jolt is needed.

### 7.3 The integration path

Jolt as a GDExtension means:
- A C++ GDExtension that wraps Jolt's API.
- The C++ extension registers with Godot as a
  `PhysicsServer3D` implementation.
- Godot's existing physics-using code (RigidBody3D,
  CharacterBody3D, Area3D) automatically uses the
  GDExtension's implementation.
- Zero code changes to gameplay code that uses
  Godot's physics API.

The catch: any custom physics integration
(game-specific collision callbacks, custom force
applications) needs to be re-implemented using Jolt's
APIs. The Jolt API is similar to PhysX, so most code
ports cleanly.

### 7.4 Why this is interesting for Synmergia

Two reasons:

1. **Determinism** for combat hit detection (§11.8):
   rewind-time hit detection needs the physics to be
   reproducible from a past state. Godot's default
   physics is *mostly* deterministic but has
   platform-specific float behavior. Jolt's fixed-point
   math is fully deterministic.
2. **Performance** at scale: 10K entities, complex
   collision, projectiles, AoE — Jolt is 2-5x faster
   than Godot's default.

### 7.5 The catch

- **Integration cost.** A GDExtension + Godot's
  PhysicsServer3D shim is real work. Maybe 2-4 weeks
  for someone familiar with both.
- **Jolt API differs from Godot's in some cases.**
  Custom force applications, character controllers
  with custom slopes/step behavior, etc., may need
  porting.
- **Compile-time dependency.** Adding Jolt to the
  build means every contributor needs the Jolt
  dependency.

### 7.6 Prototype sketch

The `labs/jolt-playground/` already has a benchmark.
What's missing:
- A GDExtension binding (`godot-jolt` is a thing; we
  could use it as a starting point or write our own).
- A test that ports one of our existing physics
  interactions to Jolt and measures the perf delta.
- A test that verifies determinism: same input → same
  collision events on different platforms.

### 7.7 Prior art

- **godot-jolt** (https://github.com/godot-jolt/godot-jolt):
  an existing GDExtension that integrates Jolt with
  Godot. Mature, well-tested, MIT-licensed. Could just
  use this instead of writing our own.
- **Horizon Zero Dawn, Forbidden West**: Jolt in
  production. The canonical case study.
- **Jolt Physics itself**: production-grade.

### 7.8 Expected cost

If we use `godot-jolt`:
- Integration: 1-2 weeks (build system, scene setup).
- Porting custom physics: 1-2 weeks.
- Determinism verification: 1 week.
- Total: 3-5 weeks.

If we write our own GDExtension:
- 6-10 weeks.

### 7.9 Trigger to adopt

Either:
- Phase 5 profiling shows physics is a bottleneck
  (CPU is at 100% in physics step, not in game logic
  or rendering).
- We find that combat hit detection has platform-
  specific variance that breaks lag compensation
  (rewind-time hit detection is non-deterministic
  on different machines).

The first is a perf optimization; the second is
correctness.

### 7.10 Current status

- Research: complete (Jolt is well-understood).
- Prototype code: `labs/jolt-playground/` exists.
- Decision: pending Phase 5 profiling OR hit-detection
  determinism test.

---

## 8. Polyglot FFI (GDScript ↔ Julia ↔ C++)

**Phase assignment** (from `world-building.md §21.8`):
Phase 4+. Trigger: HTTP bridge latency is a bottleneck.

### 8.1 The hypothesis

The current `MultiIsoService` bridge uses HTTP between
Godot and the Julia orchestrator. Per call: ~1-2ms of
HTTP overhead + JSON serialization. At 20Hz tick, a
typical game logic path might call Julia 10 times per
tick = 10-20ms of pure overhead. That's a real chunk
of the 50ms budget.

**In-process FFI** eliminates the overhead. GDScript
calls Julia functions directly; Julia calls back into
GDScript for scene-related operations. C++ GDExtensions
register with Godot and are callable from GDScript.

### 8.2 The architectures

Three options, in order of complexity:

**Option A: HTTP bridge (current)**: GDScript ↔ HTTP
↔ Julia. Simple, works, but ~1-2ms/call.

**Option B: Julia as a Godot process with shared
memory**: GDScript and Julia run as separate processes
but share a memory region. IPC cost ~10µs. More complex
to set up; faster than HTTP.

**Option C: Julia embedded in Godot via GDExtension**:
A C++ GDExtension that embeds the Julia runtime. GDScript
calls Julia functions directly through the C++ binding.
~1µs/call. Most complex; most performant.

**Option D: Replace Julia with C++ GDExtension directly**:
The Julia work gets re-implemented in C++. No FFI needed.
Loses Julia's productivity gains; gains maximum perf.

For Phase 1-3, Option A (HTTP) is fine. For Phase 4+ at
scale, Option B (shared memory) is the sweet spot. Option
C is for the deepest optimization; Option D is a
re-evaluation of the runtime choice.

### 8.3 Why this is interesting for Synmergia

The Phase 1-3 cost of HTTP bridge is small (10-20ms per
tick). The Phase 4+ cost is real: at 100K active entities
in v3, we'd be calling Julia thousands of times per tick.
HTTP is no longer tolerable.

Polyglot FFI is the migration path that gets us there
without rewriting the codebase.

### 8.4 The catch

- **Build system complexity.** Mixed-language binaries
  (Godot + GDExtension + embedded Julia) is harder to
  build, harder to package, harder to debug.
- **Debugging cross-language.** A stack trace that goes
  GDScript → C++ → Julia → C++ → GDScript is hard to
  read.
- **Lifecycle management.** GDExtensions need to be
  loaded/unloaded correctly. The Julia runtime needs
  to be initialized once. Failure modes are subtle.
- **The FFI boundary is a leaky abstraction.** When
  GDScript and Julia disagree about types (Godot's
  Vector3 vs Julia's tuple, etc.), the boundary needs
  explicit conversion.

### 8.5 What's already there

`labs/polyglot-ffi/` has a README and a `julia-runtime/`
sketch. Not yet implemented. The plan was always
"start with HTTP, graduate to FFI when needed."

### 8.6 Prototype sketch

A minimal `julia_runtime.gd` GDExtension:
- C++ shim that starts a Julia runtime in the same
  process.
- Exposes a small set of Julia functions to GDScript.
- Benchmark: HTTP vs FFI for the same call.

Test:
- `test_julia_call_latency`: time 1000 calls to Julia
  via HTTP vs FFI; verify FFI is at least 100x faster.
- `test_godot_julia_round_trip`: a value defined in
  GDScript is processed by Julia and returned to
  GDScript, end-to-end.

### 8.7 Prior art

- **FFI in general**: CFFI, ctypes, JNI, P/Invoke,
  etc. Standard.
- **Julia's `ccall`**: direct C interop, very fast.
- **Godot's GDExtension API**: allows C++ extensions;
  we just need to write a Julia C-API binding for it.
- **Game engines with embedded scripting**: Unreal with
  Blueprints/Python, Unity with C# scripting, etc. The
  pattern is well-understood.

### 8.8 Expected cost

- Option B (shared memory): 2-3 weeks.
- Option C (embedded Julia): 4-6 weeks.
- Option D (rewrite in C++): 8-12 weeks.
- Migration of existing HTTP-bridge code: 1-2 weeks
  per service.

### 8.9 Trigger to adopt

Phase 3-4: HTTP bridge latency is >5ms per tick in
profiling. At that point, switching to Option B
(shared memory) is a quick win with minimal risk.

### 8.10 Current status

- Research: started.
- Prototype code: not yet (sketch only).
- Decision: pending Phase 3-4 profiling.

---

## 9. Adaptive tick rate (per-player)

**Phase assignment** (from `world-building.md §21.9`):
Phase 5+. Trigger: significant CPU spent on AFK players.

### 9.1 The hypothesis

Every connected player currently gets a 20Hz tick on
their entity + AOI diff. But a player who's been AFK
in town for 10 minutes doesn't *need* 20Hz updates; their
state barely changes. A player in active combat in a
dungeon *might benefit* from higher than 20Hz.

**Adaptive tick rate** per player: each player has a
*tick rate class* based on their activity profile. The
server schedules updates at the rate their class needs.

Tick rate classes:

| Class | Tick rate | Profile |
|---|---|---|
| AFK | 0.1 Hz (every 10s) | Logged in, not at keyboard |
| Idle | 1 Hz | At keyboard but not moving |
| Active | 5 Hz | Moving, not in combat |
| Combat | 20 Hz | In combat |
| Critical | 30-60 Hz | Endgame boss mechanics |

The classification is automatic (derived from recent
input activity + game state).

### 9.2 The math, briefly

For a shard with 1000 players:
- 20% AFK: 200 players × 0.1 Hz = 20 ticks/s
- 30% idle: 300 players × 1 Hz = 300 ticks/s
- 30% active: 300 players × 5 Hz = 1500 ticks/s
- 15% combat: 150 players × 20 Hz = 3000 ticks/s
- 5% critical: 50 players × 30 Hz = 1500 ticks/s

Total: ~6,320 ticks/s.

Compare to fixed 20Hz for all 1000: 20,000 ticks/s.

**3x reduction in update work.** Most of the saving
comes from downgrading AFK/idle to lower rates.

### 9.3 The catch

- **Class detection lag.** If a player goes from idle
  to combat, the class doesn't change until we detect
  it. If detection takes 1 second, the player has 1
  second of "wrong" tick rate. For most game states
  this is invisible. For combat-critical states
  (dodging a one-shot), it matters.
- **AOI subscription churn.** When a player's tick rate
  changes, the AOI subscription might change too. AFK
  players in a busy area shouldn't be receiving 20Hz
  updates of nearby combat; idle players shouldn't be
  receiving combat events they're not involved in.
  The AOI filter needs to be tick-rate-aware.
- **State machine complexity.** The server tracks
  tick rate per player; the wire protocol needs a
  "rate limit" field per client; the LOD manager
  (§14) needs to know per-client rates.
- **Test complexity.** Hard to write deterministic
  tests for adaptive behavior.

### 9.4 Why this is interesting for Synmergia

The "giant sim on commodity VPS" goal benefits
directly. Reducing tick work per player by 3x means
a commodity shard can handle 3x the players. At
v3 scale, this is the difference between a single
beefy server and a small cluster.

### 9.5 Prototype sketch

`labs/multi-iso/srv/adaptive_tick.gd` (planned). Test:
- `test_classification_idle_to_combat`: a player with
  no input for 30s is "idle"; receiving a combat
  trigger reclassifies to "combat" within 1s.
- `test_tick_rate_per_class`: a player in each class
  gets the expected tick rate.
- `test_aoi_churn_on_class_change`: a class change
  causes an AOI re-subscribe.

### 9.6 Prior art

- **LoD scaling in MMOs** (WoW reduces update rate for
  far-away players; EVE does the same). The pattern
  is well-known.
- **Game thread scheduling** (Unity's Time.deltaTime,
  Unreal's tick groups, Godot's `_process` vs
  `_physics_process`). The "do less for less active
  things" idea is universal.
- **HTTP/2 priorities**: similar idea, applied to
  network requests rather than game entities.

### 9.7 Expected cost

- Tick rate classification: 1-2 weeks.
- AOI churn handling: 1-2 weeks.
- Wire protocol update: 1 week.
- Testing: 1-2 weeks.
- Total: 4-6 weeks.

### 9.8 Trigger to adopt

Phase 5 profiling: significant CPU is spent on AFK/idle
players. Specifically, the LOD + AOI + diff pipeline
combined costs >30% of tick budget for these classes.

If the profile shows most AFK players are quickly
disconnecting (or the active player count is low),
adaptive tick rate isn't needed.

### 9.9 Current status

- Research: started.
- Prototype code: not yet.
- Decision: pending Phase 5 profiling.

---

## 10. Pure-function-of-state for all gameplay

**Phase assignment** (from `world-building.md §21.10`):
Phase 3+ gradual. Aspirational.

### 10.1 The hypothesis

Every gameplay mutation should be a pure function of:
- Current state (read from state tree).
- Command (player input or system event).
- RNG seed (explicit, not from `rand()`).

→ (New state, command result, next RNG seed).

No hidden state, no side effects. The same input
produces the same output, deterministically.

Benefits:
- **Testability**: tests are trivial — give a state,
  a command, verify the new state.
- **Rewindability**: rewind to tick T means "apply
  commands from T-now with state at T". Lag compensation
  (§11.8) is the same logic.
- **Save/load**: state is the save; no separate
  serialization layer.
- **Reproducible bugs**: record commands, replay them,
  see the bug.
- **Determinism**: pre-computing the next 1000 ticks
  for prediction is just running the pure function
  1000 times.

### 10.2 What's currently impure

Looking at the codebase (per `m3-initial-world-audit.md`):

- **Autoload singletons** with global mutable state
  (`GameManager`, `EventBus`, etc.). Many gameplay
  queries read these and modify them.
- **Node tree state** that lives outside the state
  tree (e.g. a mob's `current_target` field, a player's
  `last_input_tick`). Some of this is in the state
  tree; some is in Godot nodes.
- **Signals** that carry mutable data (`EventBus.
  entity_spawned` carries a reference to the spawned
  entity; listeners mutate it).
- **RNG calls** scattered through the code. Some are
  seeded explicitly; some are not.

The migration to pure-function-of-state means:
- All gameplay state lives in the state tree.
- All RNG calls take an explicit seed and return the
  next seed.
- All command processing is `(state, command, seed)
  → (new_state, result, new_seed)`.
- Signals emit immutable events; listeners don't
  mutate.

### 10.3 Why this is hard

The hardest part isn't the code; it's the discipline.
Every time we want to "just store this in a variable
for later", we have to put it in the state tree. Every
time we want to "just emit a signal and let the
listener handle it", we have to ensure the listener
doesn't mutate. The GDScript type system doesn't help
us enforce this; we have to enforce it by convention.

### 10.4 What this enables (concretely)

If we get this right:

- **Lag compensation for free**: rewinding is just
  replaying commands from a past state.
- **State-tree-as-save**: every checkpoint is just
  the state tree. The "where is the player" question
  is a state-tree query. No "save/load" code.
- **Replay debugging**: the game logs `(tick, command)
  → (new_state, result)`. Bug? Replay the commands;
  see the bug. No more "can't reproduce" issues.
- **Pre-computation for prediction**: the client runs
  the same pure function on the client side, gets the
  same result, and only needs the server's
  authoritative diff when prediction diverges.

### 10.5 The catch

- **Refactoring is invasive.** Every service that
  has implicit state needs to be reworked.
- **Performance overhead.** Reading/writing the state
  tree is slower than reading/writing a Godot node
  field. For hot paths (20Hz × 6000 entities = 120K
  reads/writes per tick), the overhead matters.
- **Some "convenient" patterns become forbidden.**
  E.g. caches that mutate, signals that carry
  mutable data, autoloads that hold global state.
- **ECS helps but isn't sufficient.** §9.13 introduces
  ECS for performance. Even with ECS, the discipline
  of "everything is in the state tree, mutations are
  pure functions" still has to be maintained.

### 10.6 Prototype sketch

A small but representative refactor: make
`SkillService.cast_skill(player_id, skill_id, target_id)`
a pure function.

Before:
```gdscript
func cast_skill(player_id, skill_id, target_id):
    var player = _players.get(player_id)
    if not _can_cast(player, skill_id, target_id):
        return false
    _apply_skill_effects(player, skill_id, target_id)
    _emit_skill_cast_signal(player_id, skill_id, target_id)
    return true
```

After:
```gdscript
func cast_skill(state, player_id, skill_id, target_id, rng_seed):
    if not _can_cast(state, player_id, skill_id, target_id):
        return (state, CastResult.INVALID, rng_seed)
    var new_state = _apply_skill_effects(state, player_id, skill_id, target_id)
    var new_seed = advance_seed(rng_seed)
    return (new_state, CastResult.OK, new_seed)
```

No signals; the "I cast a skill" is just a state diff
that the tick loop emits as part of the normal diff
protocol.

### 10.7 Prior art

- **Redux** (React state management): the same pattern
  in UI.
- **Event sourcing** in general: the same pattern in
  distributed systems.
- **Elm's update function**: `(Model, Msg) → (Model,
  Cmd)` is exactly this pattern.
- **Database triggers + stored procedures**: the same
  pattern, but at the SQL level.
- **Functional core, imperative shell**: the
  architectural pattern that enables this.

### 10.8 Expected cost

This is a continuous refactor over Phase 3+, not a
discrete project. Each service refactored is 1-3 weeks
of work. The migration spans multiple phases.

Realistically, by Phase 5 (post-launch), maybe 60-80%
of gameplay is pure-function-of-state; the rest (UI,
rendering) is inherently imperative and stays that way.

### 10.9 Trigger to adopt

We don't adopt this as a "switch" — we adopt it as a
discipline. Every new service is written as
pure-function-of-state from the start. Every old
service is refactored when touched. The migration is
continuous.

The discipline pays off when we hit a real "I can't
reproduce this bug" or "I need to add lag
compensation" problem. At that point, the
pure-function codebase is easy; the impure codebase
is impossible.

### 10.10 Current status

- Aspirational.
- Some services are already close (e.g. CombatMath).
- Some are far (the autoload-heavy services).
- Decision: continuous, no specific trigger.

---

## 11. Cross-angle synthesis: which compose

The 10 angles aren't independent. Some compose well
(multiplicative gains); some are mutually exclusive
(different worlds); some are sequential prerequisites
(do A before B).

This section is the synthesis: which combinations
matter, which don't.

### 11.1 Compositions (multiplicative wins)

#### Hierarchical instancing + CDN for static chunks

**§7.12** (instancing) reduces state per chunk. **§11.11.4**
(CDN) serves the chunks from a CDN. Together:
- A forest of 1000 oaks is 42KB on the server (instancing).
- The CDN caches it once; 1000 clients requesting it hit
  the same edge.
- Total state cost: 42KB. Per-client cost: 42KB once.

vs naive: 500KB per chunk × 1000 instances × every
client = 500MB+. **The composition is 1000x better than
either alone.**

#### Edge shards + adaptive tick rate

**§2** (edge shards) puts state near clients. **§9**
(adaptive tick rate) reduces per-client work. Together:
- Edge shard serves 100 clients.
- 80% of those clients are AFK or idle → low tick rate.
- Edge shard does minimal work; central shard is barely
  involved.

This composition is what makes "commodity VPS for 10K+
players" plausible.

#### Pure-function-of-state + Merkle suffix trees

**§10** (pure functions) gives us explicit "what
changed" (the set of commands processed). **§5** (MST)
gives us fast diffs. Together:
- A tick processes N pure-function commands.
- The diff is the union of (state, command) → (state',
  seed') for each command.
- MST diffs the resulting trees: O(modified) thanks to
  content-hash skipping.
- The result: per-tick diff is proportional to *work
  done*, not to *state size*.

This is the "math as pure function" + "Merkle" combo
that the user originally flagged in the audit's
`grail-path.md` reference.

#### ECS + adaptive tick rate

**§9.13** (ECS) makes per-entity work cheap. **§9**
(adaptive tick) reduces the per-entity frequency.
Together: even at 10K entities, the per-tick cost is
manageable.

#### LOD-by-type + adaptive chunks

**§3** (adaptive chunks) puts variable-size chunks in
the world. **§4** (LOD-by-type) makes L1 of each chunk
content-type-aware. Together: a dense city has 16m
chunks with rich L1; an empty ocean has 1km chunks
with a "water" billboard L1. The world renders
efficiently at every scale.

#### CDN + edge shards

**§11.11.4** (CDN) is for static chunks. **§2** (edge
shards) is for dynamic state. Together: clients get
static chunks from a CDN; dynamic state from an edge
shard. The central shard is only for authoritative
state changes. This is the "CDN + game-server relay"
architecture that the largest MMOs use.

### 11.2 Sequential dependencies (do A before B)

These have to be done in order because A enables B:

- **State tree (Phase 1) → MST (§5)**: MST replaces
  the state tree's path-keyed structure. You can't
  ship MST before the state tree exists.
- **State tree (Phase 1) → lenses (§6)**: lenses
  operate on the state tree.
- **State tree + AOI (Phase 1-2) → adaptive tick rate
  (§9)**: adaptive tick rate needs per-client AOI
  classification, which needs AOI.
- **CDN for chunks (§11.11.4) → edge shards (§2)**:
  edge shards are a more sophisticated version of CDN
  caching; you want CDN proven before going to edge.
- **Pure-function-of-state (§10) → MST (§5) →
  lenses (§6)**: lenses are the most invasive; MST
  gets 80% of the benefit; pure-function discipline
  is what makes lens tracking tractable. Do them in
  this order.

### 11.3 Mutual exclusions (different worlds)

Some angles are alternatives, not compositions:

- **Quasicrystal address space (§1) vs icosahedral
  (current)**: if we adopt quasicrystals, we replace
  the icosahedral mesh. They're not both.
- **Polyglot FFI (§8) vs replacing Julia with C++**:
  Option C (embed Julia) and Option D (rewrite in C++)
  are alternatives. Pick one. My recommendation: B
  (shared memory) until we need more, then C.

### 11.4 The "if you could only do three" choice

If we're resource-constrained and can only do three of
these, which three?

My ranking:

1. **Pure-function-of-state discipline (§10)**.
   Lowest cost, highest long-term payoff. Doesn't
   require any new tech; just a different way of
   writing existing services. Pays off the first
   time you have an un-reproducible bug or need lag
   compensation.

2. **Edge shards + CDN (§2 + §11.11.4)**. The "giant
   sim on commodity VPS" promise. CDN is cheap to
   ship (Phase 1+); edge shards are the bigger
   commitment (Phase 4+). Together they cut server
   bandwidth 5-10x.

3. **MST (§5)**. Replaces the path-keyed state tree
   with a content-hash trie. Pays off as the world
   grows (v2, v3). Sub-linear diffs.

Honorable mention: **Hierarchical instancing (§7.12)**
which is already in the Phase 1 plan and is the
biggest single win for state size.

### 11.5 The "if you could only do one" choice

If we could do only one: **pure-function-of-state
discipline (§10)**. It enables every later optimization
(rewind-time, replay debugging, lens-based diffs,
deterministic prediction). It's the cheapest in code
and the longest-lived in payoff.

### 11.6 What this section is for

When we hit a Phase 4-5 scaling wall, we look at this
section to see which compositions to try first. The
goal is to avoid "we need 10x improvement" becoming
"we need to add 5 new things" when "we need to add
2-3 of the right things" would have worked.

The composition list is the answer to "if the system
isn't fast enough, what do we add?" — and the
answer is "the cheapest, highest-payoff combination
that addresses the actual bottleneck we measured."

### 11.7 What this section is NOT

- Not a commitment to do all of these.
- Not a plan for Phase 1-3 (those are in the main
  plan's §18).
- Not a substitute for measurement. Each composition
  is "if X is the bottleneck, then Y+Z should help";
  the actual adoption is gated on measurement.

---

## Document state

- Sections: 11 (10 angles + 1 synthesis).
- Length: ~1900 lines.
- Status: research companion to `world-building.md`.
- Next: when implementation pace allows, pick one
  angle (the user's choice) and start prototyping.

---

