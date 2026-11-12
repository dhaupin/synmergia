# PRD: The Clipmap Terrain Renderer (replacing the icosa face streamer)

> **Status:** v1 (2026-11-04). DECIDED + IN BUILD. The world's
> *addressing* stays icosahedral (NSC-9, `IcosahedralFaces`, zone/waypoint
> math -- all of it is good and untouched). The world's *rendering* moves
> from the icosa face-patch LOD streamer
> (`globe_terrain_streamer.gd`, 3945 lines: 4 live faces, skirts, async
> derive lanes, hot-reload graft) to a **player-centred polar clipmap**
> (`globe_clipmap.gd`). The ground LAW is unchanged
> (`TerrainGen.terrain_height` + `splat_skin`); only the mesh that draws
> it changes. Where this doc and the code disagree, the code's constants
> win and this doc is the intent behind them.
>
> Related: `prd-terrain.md` (the ground law itself), `prd-world.md` (the
> planet's topology), `prd-spherical-mvp.md` (the spherical execution
> record), `prd-geometry.md` (NSC-9 addressing).

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

Measured this session (`probe_profile_law`, `probe_color_cost`,
`probe_measure_law`):

| call | cost |
|---|---|
| `TerrainGen.terrain_height` (uncached) | **27 µs** |
| `terrain_height` (sector-cache hit) | 2.4 µs |
| `TerrainGen.splat_skin` (per-vertex color) | **31 µs** |
| `TerrainGen.vertex_color` | 80 µs |

So a *fresh* per-vertex sample is ~33 µs (height + splat color). A naive
clipmap that re-samples every vertex every frame is impossible (5000
verts × 33 µs = 165 ms/frame). **Three laws follow, and they are the
whole design:**

- **L1 -- Snap, never slide.** The lattice is quantized (centre direction
  to a global cell, heading to one angular segment). Between snaps the
  mesh is RIGID: it translates/rotates with the player for free. Vertices
  never slide through the heightfield (which would shimmer), and no
  vertex is re-sampled until the lattice actually moves.
- **L2 -- Memoize every vertex.** Height and color are read through a
  per-quantized-direction memo (the frame's `sector_cache`). A re-sampled
  direction that was seen before costs ~2 µs, not 33 µs.
- **L3 -- Amortize the rebuild.** A snap marks the rings dirty; the
  clipmap rebuilds at most `REBUILD_RINGS_PER_TICK` rings per frame, so no
  single frame pays the full bill. The near rings (the ones the player is
  standing on) rebuild first.

The heightfield is also smooth away from authored carve seams (measured
max 1 m second-difference of 1.8 m near the apron seam, ~cm on open
ground), so small cells give small sag -- the fine inner rings make the
drawn surface *equal* the law underfoot.

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

- **Constant `SEG` across levels** is what makes the rings stitch: level
  L's outer boundary and level L+1's inner boundary have the *same* angular
  vertex count, so they share vertices exactly -- **no seams, no skirts, no
  T-junctions.** This is the property the streamer spends hundreds of lines
  faking.
- **Geometric rings** mean the triangle count is CONSTANT and independent
  of the visible range: ~`SEG * (RSUB+1) * N_LEVELS` vertices regardless of
  how far you can see. (Compare: the streamer's cost scales with face count
  × level.)
- **Vertex height = `TerrainGen.terrain_height(dir)`**, so the drawn
  surface near the player IS the law (L1-L3 keep it affordable).
- **Vertex color = `TerrainGen.splat_skin`**, riding the SAME shared splat
  shader the streamer used (`assets/shaders/terrain_splat.gdshader`), so
  the look is unchanged.
- **The whole-planet horizon**: a coarse static sphere mesh sampled from
  the same law once at boot (the current `GlobeShell` visual, re-enabled
  and re-sampled), so the horizon and any from-space view stay coherent.
  The near clipmap draws over it.

### 3a. Why this fixes the float

The fine inner rings (smallest cells) cover the ground under the player and
the authored structures near the boot. The drawn surface there is the law to
within centimetres, so a structure seated on the law sits flush, and because
the rings are geometric (continuous doubling, no discrete face-level flip)
the transition to coarser ground is smooth -- **no band pop.** Structures far
from the player (e.g. the 1.8 km harbor dock) still seat on the law; when the
player approaches, the fine rings arrive under them and the drawn ground meets
the law, so they stay flush.

## 4. Public surface (drop-in for the streamer)

`globe_world` and the probes talk to the renderer through a small API. The
clipmap implements the same names so the swap is a one-line switch:

| member | meaning on the clipmap |
|---|---|
| `configure(radius, target_edge, parent)` | build the level ladder + centre cap |
| `terrain_on` / `terrain_on_flag()` | the law is active (always true at planet scale) |
| `world_seed` | the heightfield seed (same source as the streamer) |
| `update(player_pos) -> Dictionary` | snap/rebuild tick; returns `{face, loaded, unloaded, active}` |
| `walk_surface_h(dir)` | the walk law (law + rock caps) -- UNCHANGED, the ground truth |
| `terrain_h(dir)` | the bare heightfield |
| `is_loaded(face)` / `current_face` | the icosa face under the player (for the boot gate + truth line) |
| `active_faces()` | the icosa faces the clipmap currently overlaps |
| `triangle_count()` / `patch_count()` | clipmap tri/ring census |
| `async_shutdown()` / `pending_derive()` | no-op / 0 (no worker lanes) |
| `face_changed`, `patch_loaded`, `patch_unloaded` | emitted on ring build / face change |

The **walk law is not touched**: the player, props, and structures keep
riding `TerrainGen` (probe_ground_law_audit pins it). The clipmap only
changes what is DRAWN.

## 5. The switch

`globe_world.terrain_render` (`"clipmap"` | `"streamer"`, default
`"clipmap"`) selects the renderer in `_setup_streamer`. The streamer stays
in-tree as the fallback until the clipmap has a full probe green; a
follow-up round deletes it once nothing references it.

## 6. Acceptance gates

1. `probe_clipmap` exit 0: drawn-vs-law delta at the player + at every boot
   structure < 1 m; triangle count constant across a 3 km walk; ring
   stitching holds (adjacent rings share boundary vertices).
2. `probe_ground_law_audit` ALL PASS (walk law untouched).
3. `probe_starter_village`, `probe_polar_caps`, `probe_sundered_backend`,
   `probe_world_shape_ground` ALL PASS.
4. Boot build time sane (report the ladder build wall clock).
5. No per-frame hitch > ~8 ms on a snap (amortized rebuild).

## 7. Open items

- Per-vertex color memo sizing (bound the sector cache for the clipmap).
- Whether the coarse horizon sphere needs its own LOD rings for the
  from-space view (currently one static sample).
- Decommissioning the streamer + its skirt/hot-reload machinery once the
  clipmap is the only path (a later cleanup round).
