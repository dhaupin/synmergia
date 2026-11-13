# PRD: The Clipmap Terrain Renderer (replacing the icosa face streamer)

> **Status:** v1 SHIPPED (2026-11-04) -- the clipmap is the default
> renderer. **v2 DESIGNED (2026-11-04): the prop layer + multi-world
> terrain (sections 9-13).** The clipmap draws the ground mesh and
> NOTHING else -- no trees, rocks, grass, or detail props (section 9.1),
> because every prop law still lives in the legacy streamer. This round
> designs the fix: a renderer-agnostic, **chunk-addressed** prop layer
> (9.2-9.6), a **per-world ground provider** so the underworld and the
> moon get real terrain (10), the streamer's retirement order (11), the
> scale law for an online MMO (12), and the build plan (13). Cold boot
> parallelised
> (2026-11-04, S6: ~3 s -> ~2 s, bit-identical; then the ground-law rounds
> 6c/6d took the cold build to **~780 ms**, 2.6x, still bit-identical).
> The default ground renderer is
> now the clipmap; the streamer is kept as a fallback. The world's
> *addressing* stays icosahedral (NSC-9, `IcosahedralFaces`, zone/waypoint
> math -- all of it is good and untouched). The world's *rendering* moved
> from the icosa face-patch LOD streamer
> (`globe_terrain_streamer.gd`, 3945 lines: 4 live faces, skirts, async
> derive lanes, hot-reload graft) to a **player-centred polar clipmap**
> (`globe_clipmap.gd`). The ground LAW is unchanged
> (`TerrainGen.terrain_height` + `splat_skin`); only the mesh that draws
> it changes. Where this doc and the code disagree, the code's constants
> win and this doc is the intent behind them.
>
> **Shipped:** `globe_clipmap.gd` + `probe_clipmap.gd` (6 gates green);
> `globe_world.terrain_render` default `clipmap`, scale-gated to
> planet scale (>= 1000 m). The floating-structure band-pop is closed.
> The streamer stays as a sub-planet / fallback path.
>
> Related: `prd-terrain.md` (the ground law itself), `prd-world.md` (the
> planet's topology), `prd-spherical-mvp.md` (the spherical execution
> record), `prd-geometry.md` (NSC-9 addressing), `prd-ground-sample.md`
> (the fused-sample refactor behind the section-8 slow systems).

## 1. Why replace the streamer

The streamer renders the planet as 20 spherical-triangle faces, 4 live at
once, each subdivided to a discrete LOD level (7 near, floor 5 far). Three
structural defects fall out of that shape:

1. **The float / band-pop.** Authored structures ride the *analytic* walk
   law; the drawn mesh is a *discrete sample* of the same law. Between
   samples a flat triangle sags below the law, so a structure seated on
   the law reads as floating above the drawn ground. Worse, the LOD flips
   in discrete bands (face rides level 7 near, level 5 far), so the gap
   *snaps* as you approach rather than gliding. This is inherent to
   discrete per-face LOD, not a bug in the law.
2. **Seam machinery.** Adjacent faces meet at different levels, so the
   streamer carries skirts, tapered skirt depths, edge-use counting, and a
   shared-corner quantization law -- a large fraction of its 3945 lines
   exists to hide seams a clipmap does not have.
3. **Cost shape.** Per-face mesh derive runs on worker lanes with a
   hot-reload graft so a level change does not rebuild props. The whole
   apparatus exists because a face is a coarse unit that swaps wholesale.

A clipmap has none of these problems by construction (section 3).

## 2. The hard constraint: the ground law is expensive

Measured this session with a COLD spread sample (`diag_law_cold`,
`diag_law_internals` -- Fibonacci-sphere directions rotated per bench so
every call is a fresh sector, no accidental cache hits):

| call | COLD cost | notes |
|---|---|---|
| `TerrainGen.terrain_height` | **245 µs** | the full carved+road+river law |
| `_terrain_height_base` (warm-cached read) | 27 µs | |
| `TerrainGen.splat_skin` (per-vertex color) | **674 µs** | dominates |
| `TerrainGen.vertex_color` | 720 µs | |
| `TerrainGen.climate_biome_id` | 318 µs | |
| `TerrainGen.water_table_raw` | 167 µs | |
| `TerrainGen.river_channel` | 111 µs | |
| sector-cache HIT (any of the above) | ~2 µs | |

> **Corrected.** An earlier note in this doc said 27 µs / 31 µs. Those
> were WARM (already-cached-sector) reads. The COLD rate is ~10-20x
> higher, and that changes the design: a fresh per-vertex sample is
> ~920 µs (height + splat color), so a 5.8k-vertex clipmap costs
> **~3 s COLD** to derive. A naive re-sample-everything renderer is not
> merely wasteful, it is impossible. The whole design follows.

**Four laws follow, and they are the whole design:**

- **L1 -- Hysteresis, not slide.** The lattice centre is quantized to a
  global arc grid and only re-centres when the player crosses
  `RE_CENTER_M` (150 m) from it. Between re-centres the mesh is RIGID;
  nothing is re-sampled. Vertices never slide through the heightfield
  (which would shimmer).
- **L2 -- Memoize every vertex.** Height and color read through a
  per-quantized-direction memo (the frame's `sector_cache`). A
  re-sampled direction seen before costs ~2 µs, not ~920 µs.
- **L3 -- Time-budget the rebuild.** A re-centre marks the rings dirty;
  the tick advances an incremental builder for at most `BUDGET_MS` (4 ms)
  per frame, near rings first, so no single frame pays the full ~3 s bill.
  Measured worst tick incl. a re-centre: **7 ms**.
- **L4 -- The memo is what makes it liveable.** Within the 150 m
  hysteresis window the player moves over ground the memo already holds
  (adjacent sectors overlap), so the steady state is cache hits. A
  re-centre derives ~1 new sector band; the budgeted builder spreads that
  over frames.

The heightfield is also smooth away from authored carve seams (measured
max 1 m second-difference near the apron seam, ~cm on open ground), so
small cells give small sag -- the fine inner rings make the drawn surface
*equal* the law underfoot.

## 3. The clipmap design

**Polar (radial) clipmap centred on the player.** Chosen over a square
tangent-plane clipmap because a square tangent grid diverges from a 20 km
sphere fast (a 4 km tangent square sags ~400 m from the surface); a polar
grid re-projects every vertex to the sphere, so vertices always lie on the
surface.

```
        level L covers radii [r0 * 2^L, r0 * 2^(L+1))
        SEG angular cells  (constant across levels -> seamless stitching)
        RSUB radial cells  (constant)
        centre cap: a fan from the player out to r0
```

- **Constant `SEG` (128) across levels** is what makes the rings stitch:
  level L's outer boundary and level L+1's inner boundary have the *same*
  angular vertex count, so they share vertices exactly -- **no seams, no
  skirts, no T-junctions.** This is the property the streamer spends
  hundreds of lines faking. Verified by `probe_clipmap` G3 (shared
  boundary directions == `SEG`).
- **Geometric rings** mean the triangle count is CONSTANT and independent
  of the visible range: `N_LEVELS * RSUB * SEG * 2` = 10,240 tris
  regardless of how far you can see. (Compare: the streamer's cost scales
  with face count × level.)
- **Vertex height = `TerrainGen.terrain_height(dir)`**, so the drawn
  surface near the player IS the law (L1-L4 keep it affordable).
- **Vertex color = `TerrainGen.splat_skin`**, riding the SAME shared splat
  shader the streamer used (`assets/shaders/terrain_splat.gdshader`), so
  the look is unchanged.
- **The whole-planet horizon**: a coarse static sphere mesh sampled from
  the same law once at boot (the current `GlobeShell` visual, re-enabled
  and re-sampled), so the horizon and any from-space view stay coherent.
  The near clipmap draws over it.

### 3a. Why this fixes the float

The fine inner rings (smallest cells, ~8 m at R=20 km) cover the ground
under the player and the authored structures near the boot. The drawn
surface there is the law to within **0.52 m** (measured, `probe_clipmap`
G1), so a structure seated on the law sits flush, and because the rings
are geometric (continuous doubling, no discrete face-level flip) the
transition to coarser ground is smooth -- **no band pop.** The measured
float was **~400 m at the 1.8 km harbor dock** on the streamer (a coarse
face-level sample of a carved shoreline); on the clipmap the harbor is
beyond the fine rings but the coarse rings sample the SAME law, so the
gap is a smooth LOD error, not a snapped band.

### 3b. Scale gate

The ring ladder constants (inner radius fraction, 150 m hysteresis, ~8 m
innermost cell) are tuned for the canon **20 km** planet. Below
`PLANET_RENDER_MIN_R` (1000 m) -- e.g. the R=100 prototype bench sphere
that several probes boot -- the clipmap would re-centre every step on a
628 m-circumference sphere, so `_setup_streamer` falls back to the
streamer. This is the same planet-scale line the world's other gates use.

## 4. Public surface (drop-in for the streamer)

`globe_world` and the probes talk to the renderer through a small API. The
clipmap implements the same names so the swap is a one-line switch:

| member | meaning on the clipmap |
|---|---|
| `configure(radius, target_edge, parent)` | build the ring ladder under `parent` |
| `terrain_on` / `terrain_on_flag()` | the law is active (always true at planet scale) |
| `world_seed` | the heightfield seed (same source as the streamer) |
| `update(player_pos) -> Dictionary` | hysteresis + budgeted build tick; returns `{face, loaded, unloaded, active, ms}` |
| `build_all() -> int` | synchronous full build (boot + probes); returns wall-clock ms |
| `walk_surface_h(dir)` | the walk law (law + rock caps) -- UNCHANGED, the ground truth |
| `terrain_h(dir)` | the bare heightfield |
| `is_loaded(face)` / `current_face` | the icosa face under the player (for the boot gate + truth line) |
| `active_faces()` | the icosa face the clipmap is centred on |
| `triangle_count()` / `patch_count()` / `visible_patch_count()` | clipmap tri/ring census |
| `pending_derive()` / `_mesh_pending()` / `_prop_pending()` | the build queue depth (streamer-compat drain shims) |
| `mesh_lane_stats()` | `{pending, lanes}` (streamer-compat) |
| `async_shutdown()` | clears the build queue (no worker lanes) |
| `face_changed`, `patch_loaded`, `patch_unloaded` | emitted on ring build / face change |

The **walk law is not touched**: the player, props, and structures keep
riding `TerrainGen` (probe_ground_law_audit pins it). The clipmap only
changes what is DRAWN.

## 5. The switch

`globe_world.terrain_render` (`"clipmap"` | `"streamer"`, default
`"clipmap"`, read from `synmergia/world/terrain_render`) selects the
renderer in `_setup_streamer`, gated to `planet_radius >= 1000 m` (3b).
The streamer stays in-tree as the fallback until the clipmap has a full
probe green; a follow-up round deletes it once nothing references it.

Probes that read the streamer's *internals* (`_patches`, `_patch_lvl`,
`_level_for_edge`, the Sundered deep beds) pin
`synmergia/world/terrain_render = "streamer"` in their entry function, so
they keep testing what they were written to test. Probes that read only
the shared surface (`update`, `triangle_count`, `active_faces`,
`pending_derive`, `_mesh_pending`) run against the default renderer.

## 6. Acceptance gates

`probe_clipmap` (exit 0, ALL PASS):

1. **G1** drawn-vs-law < 1 m in the fine rings (player + hall + 80/140 m
   out) -- measured **0.52 m**.
2. **G1b** far-field drawn-vs-law < 6 m (400 m / 1 km / 2.5 km) -- the
   coarse rings sample the same law.
3. **G2** triangle count constant across a 2.5 km walk -- **10,240**.
4. **G3** ring boundaries share `SEG` vertex directions (stitch).
5. **G4** walk law == terrain law at spawn (the law is untouched).
6. **G5** budgeted tick < 40 ms incl. a re-centre -- measured **7 ms**.

Plus: `probe_ground_law_audit` ALL PASS (walk law untouched);
`probe_starter_village`, `probe_world_shape_ground` ALL PASS;
`probe_globe_world` ALL PASS (scale gate routes the R=100 bench to the
streamer).

## 7. Open items

- Per-vertex color memo sizing (bound the sector cache for the clipmap).
- Whether the coarse horizon sphere needs its own LOD rings for the
  from-space view (currently one static sample).
- Decommissioning the streamer + its skirt/hot-reload machinery once the
  clipmap is the only path (a later cleanup round).
- The **ground-law cold cost** (section 8) is the real ceiling: at ~390 µs
  per fresh fused sample the clipmap's cold build is ~2 s even after the
  S6 parallel build. Caching + hysteresis hide it, but shrinking the law
  itself (prd-ground-sample.md) would help every consumer.
- The **cold build is parallel now** (S6): `build_all` derives the cap +
  rings on a bounded worker pool and installs meshes on the main thread.
  The incremental `update()` tick stays SERIAL on purpose -- it must run
  inside the frame budget (L3), and its rows are already chunked against
  the deadline (probe_clipmap G5 pins < 40 ms; it is now ~5 ms).

## 8. Slow systems found this round (fix candidates)

The clipmap work measured the ground law directly and turned up several
systems whose cost is worth attacking. These are NOT required for the
clipmap to ship (it hides them behind the memo); they are listed here so
the next round can pick them up. None is a "big arch" change -- each is a
local fix -- but the user asked for anything slow to be recorded here.

| # | system | measured | why it is slow | fix candidate |
|---|---|---|---|---|
| S1 | `TerrainGen.splat_skin` | **674 µs** cold | re-derives `skin_classes` (which itself calls the biome law) AND `climate_temperature`, AND `hydro_water_surface`, AND `terrain_height`, AND `road_state_at` -- several of those overlap with what the caller already computed. | Let callers pass the already-known height/water-table in (the clipmap already has `h`); split the "cheap" limbs (snowline, road tint) from the "expensive" ones (water surface, crag noise) and cache each limb on its own quantized key. |
| S2 | `TerrainGen.climate_biome_id` | **318 µs** cold | calls `terrain_height` + `hydro_water_surface`, both of which re-enter the expensive water/climate stack. | Same pattern: compute once per sector and memoize the *pair* `(biome, water_surface)` together, since they share inputs. |
| S3 | `TerrainGen.water_table_raw` | **167 µs** cold | runs `_vnoise` twice + `climate_moisture` + `_terrain_height_base`; the moist/height inputs are re-derived by callers. | Memoize on the sector (already does) but ALSO expose a batch form so a mesh pass gets the whole row in one call (fewer per-call overheads). |
| S4 | `TerrainGen.river_channel` | **111 µs** cold | IS sector-cached (`_channel_cache`), so only the first call per sector pays; the cost is the inner loop -- every river spec × every segment × 3 slerp samples, no bounding early-out. | Add a coarse bounding test (skip specs whose nearest endpoint is > the river's angular radius away) before the segment loop. |
| S5 | The memo itself (`SectorCache`) | ~2 µs hit | fine, but the clipmap keys height and color separately, so a vertex costs two lookups. | One combined `(height, skin)` memo entry per quantized direction halves the lookups. |
| S6 | Cold boot derive | **~2.0 s** (was ~3 s) | the boot `build_all()` derives every ring vertex cold (no memo warm yet). | **SHIPPED**: (a) the vertex skin is resolved ONCE per distinct vertex, not once per emission (the ring quad pass emits each shared vertex up to 6x); (b) `build_all` fans the cap + each ring onto a bounded worker pool (cores-sized) and installs the meshes on the main thread (the streamer's derive/apply split; the law is thread-safe). Bit-identical geometry, 1.5x faster cold. Still ~2 s because the cold ground-sample (~390 us) IS the cost. |
| S7 | Streamer `_patches` machinery | 3945 lines | seams/skirts/hot-reload exist only because a face swaps wholesale. | Delete once the clipmap is the only path (7, Open items). |

### 8b. Resolutions (2026-11-04)

The ground-law rounds (prd-ground-sample.md sections 6c/6d) resolved the
S1-S6 candidates below. Recorded here so the table is not re-worked:

| # | status | what closed it |
|---|---|---|
| S1 `splat_skin` | **RESOLVED** | `splat_skin_from(GroundSample, ...)` reads the precomputed sample (height, temperature, water surface, crag, road) instead of re-deriving; `splat_skin` is now a thin wrapper. Cold 674 -> ~226 us (most of the rest is the `waterfall_seam_at` scan, itself bounded in 6c). |
| S2 `climate_biome_id` | **RESOLVED** | folded into the fused `GroundSample` (`biome_id` is a field, computed once per sector); the public entry reads the memo. |
| S3 `water_table_raw` | **RESOLVED** | memoized on the sector AND its inputs (`climate_moisture`, `_terrain_height_base`) are the cached/memoized forms; a fresh sample now pays 2.14 calls / 1.15 hits (measured), down from the full re-derivation. |
| S4 `river_channel` | **RESOLVED** | `RiverSpec.bound_ang` + `_river_spec_far()` (a per-spec angular bound; 6c) and the same for `waterfall_seam_at` (`seam_bound_ang`). |
| S5 combined memo | **PARTIAL** | the fused `GroundSample` is ONE cache entry carrying height + skin, so a vertex no longer keys height and color separately (the S5 goal). The per-field caches remain for the non-fused public entry points. |
| S6 cold boot derive | **RESOLVED** | S6 parallel build PLUS the 6c/6d law shrinks: cold build 2004 -> ~780 ms (2.6x). The cold sample itself fell 389 -> ~290 us (`ground_sample` ~196 us + splat ~28 us + overhead). |
| S7 streamer `_patches` | open | decommission the streamer once the clipmap is the only path (section 7). |

**New (6d):** `road_height_override` was the LAST per-vertex scan without
a bound -- `RoadSpec.probe_pts` (the precomputed node + slerp-third set)
+ `bound_pts`/`bound_ang` (the checkpoint early-out) closed it: cold
81 -> 7 us. See prd-ground-sample.md section 6d.

**Measured redundancy (instrumented `SectorCache`, partial clipmap
build): 675,904 `get_value` calls at a 90.6% hit rate.** Nearly all of
those are the SAME quantized direction re-entering a different sub-law
within one vertex derive -- the dedup is real, but it is paid for one
key build + lock + LRU probe at a time. This is the number the
`GroundSample` refactor (`prd-ground-sample.md`) is meant to collapse.

**The big-arch question (SCOPED):** S1-S4 are all
the same shape -- a "derive the ground at a direction" law where each
public entry point re-runs its neighbours. The structural fix is a single
`GroundSample` struct computed once per quantized direction (height,
water table, biome, skin, road) and memoized together, with every public
function becoming a field read. That is a real refactor of `terrain_gen`,
so it is scoped in **`prd-ground-sample.md`** (design + a staged,
bit-identical plan) -- not done here.

## 9. The prop layer (v2 -- the world is bare without it)

### 9.1 The gap (measured)

The clipmap is the DEFAULT renderer (`synmergia/world/terrain_render`,
default `"clipmap"`; the world boots at 20 km so the scale gate never
fires). It draws the ground MESH and nothing else. **Every prop law
still lives in the legacy streamer** (`globe_terrain_streamer.gd`):
trees + species variants + vines (`_spawn_trees` / `_apply_tree_sites`),
rocks + scree collars (`_spawn_rocks`), climbable boulders
(`_spawn_boulders`), the nine detail kinds (`_spawn_detail_props`:
ore, cattail, bush, tuft, flower, mushroom, mycelium, shell, wrack),
and the grass field (`_spawn_grass_field`). The clipmap's `_prop_pending()`
is a stub returning `0`.

Measured on the live globe (a full tree walk of `world_root`):
- **default (clipmap):** `{}` -- zero `Tree`/`Rock`/`Grass`/`Mushroom`
  nodes anywhere. The starter plains read as bare colored terrain.
- **streamer (pinned):** 229 trees, 49 rocks, 6 boulders, 2 grass fields,
  2120 detail instances.

The streamer was never ported because its prop laws are FACE-addressed
(20 icosa triangles, 4 live) and the clipmap is RING-addressed (polar
rings re-centred on the player). Porting the laws one-for-one into the
clipmap would be wrong twice over: the ring lattice moves under the
player (props would re-derive and pop on every re-centre), and the laws
would be trapped in the clipmap, unavailable to the underworld, the
moon, or any future renderer.

### 9.2 The design: a chunk-addressed `PropLayer` (renderer-agnostic)

Props become a THIRD system, independent of both renderers, addressed by
a stable **prop chunk** -- a quantized direction cell. A chunk is a PURE
FUNCTION of `(world_seed, chunk_key)`:

```
chunk_key  = a TERRAIN face (0..19, `IcosahedralFaces.face_for_direction`)
             + a barycentric subdivision cell at PROP_CHUNK_DEPTH -- the
             SAME addressing the streamer's site law already uses, so a
             chunk key is a stable integer with no float seam cracks.
             (NB the codebase's namespace note: `SpatialFragmenter`'s
             "vertex" field is the 0..11 icosa VERTEX, not the 0..19
             terrain face -- pick the right one; do not mix them.)
chunk_data = SeedChain.derive_seed([world_seed], "props/<ruleset>/<chunk_key>")
           -> the ordered prop instance list (kind, dir, scale, yaw, species...)
```

A chunk's content re-derives byte-identically on every machine and every
boot (the same content-hash discipline the terrain already uses). This
buys, for free, the four properties the prop system needs:

- **Independently derivable** -- no shared state, so a chunk derives on a
  worker thread (the clipmap's own S6 worker-pool law).
- **Cacheable** -- an LRU on `chunk_key` (the `SectorCache` pattern);
  overlapping re-derives hit at ~2 us.
- **Streamable** -- load chunks within `PROP_RADIUS` of the viewer,
  unload beyond `PROP_RADIUS + hysteresis`. Player-independent identity:
  two players near the same chunk share the derived content.
- **Renderer-agnostic** -- the clipmap, the streamer, the underworld, and
  the moon all consume the SAME layer; a renderer swap no longer touches
  props at all.

### 9.3 Why chunk-addressed (not face- or ring-addressed)

| addressing | owner today | why it is wrong for props |
|---|---|---|
| icosa FACE | streamer | coarse (20 faces, 4 live); props rebuild wholesale per face; LOD flips pop the whole face's scatter; tied to the icosa grid, awkward for polar rings. |
| polar RING | clipmap | rings RE-CENTRE on the player, so a prop's address changes as the player walks -- props would pop and re-derive on every re-centre. Fatal. |
| **CHUNK** | (new) | stable, player-independent, matches how an MMO streams content around many viewers at once; a chunk is the natural unit for caching, budgeted build, and (later) server authority. |

### 9.4 The density + LOD law (ported, data-driven)

- **Density per biome** -- port the `_DETAIL_BUDGETS` table, the tree
  count ladder (the band-scaled `rng.randi_range` asks), and the species
  gate (`TerrainGen.tree_species_at`). Density is DATA (per-band tables),
  not code, so the underworld/moon declare their own.
- **Distance LOD** -- near chunks: real `Node3D` props with colliders +
  harvest registration (the interactive band); far chunks: batched
  `MultiMesh` (trunks + canopies + tufts, the streamer's `BatchedTrunks`
  pattern); beyond `PROP_RADIUS`: not derived at all.
- **Budgeted build** -- the same L3 law the clipmap uses: a per-frame
  prop budget, near chunks first, chunked against an absolute deadline so
  no frame stalls.
- **The decorative salt** -- preserve the FIELD-2 split: decorative bands
  (canopies, grass) mix a session salt so nature recombines between days;
  anchored culture (harvest nodes, quest anchors) derives from the world
  seed alone so depletion/respawn ownership survives.

### 9.5 The prop taxonomy (the port surface)

One `PropLayer` with a per-kind builder registry (the `BiomeBand.Family`
enum becomes the real dispatch key -- see 10.3). Ports, keeping the
existing SHARED mesh registry (`_shared_prop_cyl` / `_shared_prop_sphere`,
the quantized-key dedup):

| family | kinds | collider | harvest |
|---|---|---|---|
| TREE | trunk + species canopy + vine hangs | trunk yes | no (vines pure paint) |
| ROCK | rock + scree collar | yes | no |
| BOULDER | climbable squat ellipsoid + rim collar | yes | no |
| DETAIL | ore, cattail, bush, tuft, flower, mushroom, mycelium, shell, wrack | ore yes | ore/kelp/pearl yes |
| GRASS | MultiMesh blade field | no | no |

### 9.6 Colliders, harvest, persistence

- Near props carry `PropCollider` (trunk bodies block + join the
  climbable group; canopies stay intangible).
- Harvest nodes register through `HarvestService.register_node` with
  STABLE ids: `hs_<chunk_key>_<idx>` (the streamer's `hs_<face>_<idx>`
  discipline, chunk-keyed instead of face-keyed) so a chunk reload
  re-claims the SAME node identity -- depletion/respawn ownership survives
  a re-stream.
- Prop IDENTITY is seed-derived (stable); harvest DEPLETION is
  service-side (already). No prop state enters the world save.

## 10. Multi-world terrain: the ground-provider seam (v2)

### 10.1 The coupling to break

`globe_clipmap.gd` hardcodes the main world's ground law: `preload(.../
terrain_gen.gd)` at line 38, `TerrainGen.terrain_height`, `TerrainGen.
SPAWN_CENTER`, `TerrainGen.rock_top_height`. The underworld
(`globe_underworld.gd`) and the moon (`globe_moon.gd`) do not use
`TerrainGen` at all -- each builds a bare `SphereMesh` + `SphereShape3D`
(a flat ball): no heightfield, no biomes, no water, no props. They are
globes with no terrain.

### 10.2 The design: a `GroundProvider` interface

Extract a small interface every world's ground law implements, and have
the clipmap take a PROVIDER in `configure()` instead of preloading
`TerrainGen`:

```
GroundProvider:
  ground_sample(dir)        -> {height, biome_id, biome_weights, ...}
  walk_height(dir)          -> float   # height + walk-over caps
  rock_top_height(dir, ...) -> float
  sea_level()               -> float
  water_surface(dir)        -> float   # -1e9 = none
  spawn_center()            -> Vector3
  biome_density(biome_id)   -> int     # the prop ask table
```

`TerrainGen` becomes the provider for `world_id = "main"` (its public
statics already ARE this interface -- the extraction is mostly a thin
adapter). The clipmap, the prop layer, the walk law, and the water law
all read the provider, so the SAME clipmap renders any globe.

### 10.3 The underworld + moon get real terrain

Both are 2 km / 1.2 km globes. They already have the pieces to become
real worlds:

- **The underworld already has a band system.** `BiomeBand`
  (`data/biomes/`, `world_id`-filtered) declares five bands with count,
  radii, palette, and a `Family` enum -- but `globe_underworld.gd`
  hardcodes five builders by band id and **never reads `.family`**. The
  provider's `biome_density` + the prop layer's family dispatch make
  `BiomeBand` the real data law it was written to be.
- **The moon declares a crater pool** (`data/oceans/
  ocean_lunar_crater.tres`, "The Builder's Pool") that `globe_moon.gd`
  never builds -- a data-vs-build gap the provider's `water_surface`
  closes.
- **Authored geography must move out of `TerrainGen`.** `SPAWN_CENTER`,
  `LAKE_CENTER`, `ISLAND_CENTER`, `SUN_PANS_*`, and the polar caps are
  main-world constants. Each globe's authored geography belongs in its
  `WorldData` (or its provider), so the moon's crater and the
  underworld's lava lake/cistern are declared per world, not inherited.

### 10.4 What stays main-world-only

The `terrain_backend_id` seam (`backend_sundered.gd` composes over
`TerrainGen._natural_raw`) stays as-is -- it is a MAIN-world authored
override. Other worlds get their own provider, not a backend over
`TerrainGen`.

## 11. The streamer's retirement order

Retiring the streamer FIRST would delete all flora (it holds the only
prop system) and strand 14 streamer-internal probes. The safe order:

1. **Extract** the prop laws into `PropLayer` (renderer-agnostic).
2. **Wire the clipmap** to consume `PropLayer` -- parity receipts.
3. **Migrate the underworld/moon** onto the provider + prop layer.
4. **Retarget the 14 streamer-internal probes** to the shared surface
   (`probe_prop_density`, `probe_biodiversity_v7`, the continent/flow
   probes) so they test the new layer, not the dead internals.
5. **Delete** `globe_terrain_streamer.gd` (3945 lines: skirts, seams,
   hot-reload graft -- all existence-proof of the face-swap model the
   clipmap retired).

Each step is independently shippable and gated; no step leaves the world
without flora.

### 11a. Progress (2026-11-04)

- **Step 1 (extract) -- DONE.** `PropLayer` owns trees/rocks/boulders/details
  and now the DEEP family too: the Sundered Sea's kelp shelf + pearl trench
  (`GroundProvider.deep_beds()`, receipt `probe_deep_garden`).
- **Step 2 (wire clipmap) -- DONE.** The clipmap consumes `PropLayer`; the
  prop layer reads a `GroundProvider`, never `TerrainGen`.
- **Step 3 (underworld/moon) -- DONE.** `UnderworldProvider` +
  `MoonProvider` back the clipmap + prop layer; `BiomeBand.family` is the
  real dispatch (receipt `probe_conjured_ground`).
- **Step 3b (instances) -- OPEN (the "prop everywhere" leg).** Instanced
  zones (arena/coliseum/sandpit/dungeon) do NOT boot a globe at all:
  `arena_instance.gd` builds a sealed flat room (a `PlaneMesh` floor +
  `BoxShape3D` slab) in its own local frame -- there is no clipmap, no
  provider, no prop layer. Two honest options, and the choice is a DESIGN
  call:
    1. **Provider-backed instance room.** Give the arena a `GroundProvider`
       (its `zone_data` seed + the mode env palette) and stream the prop
       layer over the room. But the arena frame is LOCAL (metres around
       origin), while `PropLayer`/`PropChunk` address a GLOBE (unit dirs,
       `radius_m`). A local room would need the chunk layer to accept a
       planar adapter (a `LocalFrameProvider` + a flat chunk key), which is
       new machinery, not a wiring change.
    2. **Instance prop kit.** A room-scoped, seed-derived prop scatter over
       the flat floor (the same `SeedChain` law, no globe addressing) --
       cover rocks already exist this way; generalize them into a per-mode
       prop kit.
  RECOMMENDATION: option 2 first (cheap, matches the sealed-room reality),
  option 1 only if instances ever become open terrain. Recorded so the
  choice is explicit, not accidental.
- **Step 4 (retarget probes) + Step 5 (delete streamer) -- OPEN.** The
  streamer still owns nothing the clipmap lacks now (the deep beds were the
  last gap), so the deletion is unblocked once the 14 streamer-internal
  probes are retargeted.

## 12. The scale law (what an online MMO needs)

The chunk is not just a rendering convenience -- it is the unit the whole
online pipeline wants:

- **Determinism as the network law.** A chunk is a pure function of the
  seed, so the SERVER and every CLIENT derive identical props without
  shipping prop data. Authority over harvest/interaction rides the
  existing service path (HarvestService ids); the world ships only the
  seed.
- **Streaming around MANY viewers.** Unlike the streamer's single-viewer
  face LOD, chunks stream around every player independently; the LRU
  serves overlapping viewers from one derive.
- **Cost is bounded by radius, not by world size.** Derive + build cost
  scales with `PROP_RADIUS`/chunk, constant regardless of how large the
  planet is -- the property the clipmap already has for the mesh.
- **Batching is the draw-call law.** The mass of props is `MultiMesh`
  (one draw per kind per chunk); real nodes only for the interactive
  near band. `visibility_range` (Godot's built-in) can fade the far
  batches without a per-frame CPU pass.
- **The seed cache is shared with the ground.** Props read the same
  `GroundSample` / sector cache the mesh does, so a chunk's prop derive
  and its ground derive share memoized samples.

## 13. Build plan (parallelisable across the existing lanes)

The work splits cleanly along the existing subagent-lane pattern
(`labs/lanes/`), with the parent owning the shared interfaces:

| lane | scope | touches |
|---|---|---|
| **PARENT** | `GroundProvider` interface + `PropLayer` skeleton + `PropChunk` addressing + the density/LOD law. The shared seam everything else consumes. | `globe_clipmap.gd`, new `prop_layer.gd`, `terrain_gen.gd` (adapter) |
| **LANE A** | Port the prop taxonomy (trees/species/vines, rocks/scree, boulders) from the streamer into `PropLayer` builders + the shared mesh registry. | new prop builder files |
| **LANE B** | Port the detail kinds + grass field + harvest registration (stable chunk-keyed ids). | new prop builder files, `harvest_service.gd` |
| **LANE C** | `UnderworldProvider` + wire `BiomeBand.family` dispatch + the lava lake/cistern as declared geography. | `globe_underworld.gd`, `biome_band.gd` |
| **LANE D** | `MoonProvider` + build the declared crater pool + the moon's own biome bands. | `globe_moon.gd`, `world_moon.tres`, new `data/biomes/moon_*` |
| **PARENT** (last) | Retarget the 14 streamer-internal probes; delete the streamer. | `game/tests/`, delete `globe_terrain_streamer.gd` |

Gates at every step: `probe_clipmap` ALL PASS; a NEW `probe_prop_layer`
(family counts, determinism, chunk-keyed harvest ids, LOD parity);
`probe_ground_law_audit` ALL PASS; the underworld/moon receipts
(`probe_underworld`, `wilds_probe`) green on the provider path; zero
SCRIPT ERROR; lint + naming clean.

