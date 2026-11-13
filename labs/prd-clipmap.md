# PRD: The Clipmap Terrain Renderer (replacing the icosa face streamer)

> **Status:** v1 SHIPPED (2026-11-04). The default ground renderer is
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
- The **ground-law cold cost** (section 8) is the real ceiling: at 920 µs
  per fresh vertex the clipmap's cold build is ~3 s. Caching + hysteresis
  hide it, but shrinking the law itself would help every consumer.

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
| S6 | Cold boot derive | ~3 s | the boot `build_all()` derives every ring vertex cold (no memo warm yet). | Warm the memo during the loading screen (a cheap pre-pass over the spawn sectors), or accept the 3 s behind a fade. |
| S7 | Streamer `_patches` machinery | 3945 lines | seams/skirts/hot-reload exist only because a face swaps wholesale. | Delete once the clipmap is the only path (7, Open items). |

**The big-arch question (for discussion after this round):** S1-S4 are all
the same shape -- a "derive the ground at a direction" law where each
public entry point re-runs its neighbours. The structural fix is a single
`GroundSample` struct computed once per quantized direction (height,
water table, biome, skin, road) and memoized together, with every public
function becoming a field read. That is a real refactor of `terrain_gen`
(not a local patch), so it is flagged for a conversation, not done here.

