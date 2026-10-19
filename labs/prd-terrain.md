# PRD: Terrain -- Biomes, Surface Look, Hydrology, Progressive Detail

> **Status:** v2 (2026-10-19). ALL FOUR SLICES ARE IN THE GROUND LAW AND
> LIVE IN THE STREAMED GLOBE (this doc's old line -- "slices 2-4
> designed" -- was stale; the 2026-10-19 audit found the implementation
> ahead of the doc). Current truth:
>
> - **Slice 1** climate field + biome law: SHIPPED, probe-pinned
>   (`probe_terrain_biome.gd`, `probe_terrain_climate.gd`).
> - **Slice 2** surface colors: SHIPPED and beyond the v1 design --
>   the vertex law carries the biome palette blend, slope rock,
>   strata/fracture crag law, temperature snowline, wet dimming,
>   shore foam, waterfall seams, the grass expression and the road
>   tint.
> - **Slice 3** hydrology: SHIPPED -- water-table fields with gated
>   basins at ANY elevation, carved river channels with moisture
>   ripple and waterfall seams, bridge decks read by the biome law.
> - **Roads** (originally "new PRD entry"): SHIPPED ahead of plan --
>   seeded route graph + corridor carve (bed/deck) + surface tints;
>   the starter village battery pins the connecting road to the
>   capitol plaza.
> - **Slice 4** progressive scatter: SHIPPED and EXTENDED this
>   session -- v4 density raise (barycentric site draws, belt-dry
>   hydrology, homeland grass yield, boot grove pull), v5 grass
>   tier (tufts + blooms), v6 threading + MultiMesh grass fields.
>   Numbers: 25 collided trees / 1.2 km at boot, ~900 meadow clumps
>   per face in one draw call.
>
> The original visibility gap (props placed 6+ km from a boot that
> sits in a face corner) is what kept slices 2-4 "invisible"; the
> density law fixes it at the seams all four slices share.
> **Last verified checks:** determinism/village/lint batteries green
> 2026-10-19; perf budget build pin passes. See TASKS.md for the
> session log.

## 1. The law that already holds (context)

Everything under this PRD extends ONE seam: `TerrainGen.terrain_height(dir,
world_seed)` in `game/scenes/worlds/terrain_gen.gd`. It is a pure function
of (direction, seed): no time, order, or locality. The streamer
(`globe_terrain_streamer.gd`) samples it per tile vertex with a quantized
direction cache (shared corners never crack), the skirt taper reads the
law's unsampled amplitude, and the walk surface rides the analytic law
(level-independent). Every slice below must preserve:

- **Purity:** any new field (climate, hydrology) is a pure function of
  `(dir, seed)`. Same answer twice, same answer on every machine.
- **Continuity:** blended fields only (lerp/smoothstep of continuous
  fields); the spawn plaza/apron carving stays last-writer-wins and dry.
- **The probe contract:** every field ships with a `probe_*` that asserts
  the law analytically AND through a live streamed globe (the continent
  walk). Determinism test stays green.

## 2. Slice 1 -- The biome climate field (SHIPPED)

**Goal:** the planet resolves a biome everywhere, deterministically:
deserts, forests, tundra at the poles, swamp in wet hollows, alpine stone
up high. Implemented in `terrain_gen.gd`:

- `ClimateField` (inner class): three pure fields on the direction cube
  via the existing value-noise family (`_vnoise`):
  - `temperature(d, seed_signal)` — latitude band (cos of lat, smooth
    clamp at 45 deg like the land-mass band) + altitude lapse (min(land
    height, lapse ceiling) x lapse rate) + noise jitter. Range [0, 1].
  - `moisture(d, seed_signal)` — octave noise (2 freqs), shaped by the
    land-mass field (interior stays moister than coasts at the same
    noise). Range [0, 1].
  - `biome(d, seed)` — resolution law: ocean when land < OCEAN_LINE
    (deep vs shelf vs shore), alpine above the snowline, tundra at cold
    + dry, desert at hot + dry, swamp at wet + low + gentle, forest at
    mild/wet, taiga at cold-ish wet, grassland otherwise. Deterministic
    banding thresholds, smooth blend WEIGHTS for rendering (slice 2
    consumes the weights, not the discrete id).
- `BiomeId`, an inner class of stable integer codes
  (ocean/deep/shore/alpine/tundra/desert/swamp/taiga/forest/grassland),
  documented in the class. It rides inside terrain_gen.gd like
  RockSpec/BoulderSpec (terrain_gen is no-autoload, no-class_name by
  law, so the inner-class pattern is the convention that fits).
- Pure-function guarantees the probe pins:
  - Same dir + seed => same biome, twice.
  - Spawn apron resolves DRY (never ocean/swamp) — the plaza law stands.
  - The lake bowl resolves lake, the island shore resolves shore.
  - Continuity: neighboring samples (small angular step) never jump
    more than one non-ocean biome band (no salt-and-pepper).
  - Band sanity at the planet scale: polar directions resolve cold
    bands (tundra/alpine/ocean), the homeland resolves green/grass
    bands, at least one desert NOISE pockets exist somewhere warm+dry
    (statistical pin sampled over a coarse direction lattice, counted,
    deterministic count contract: >= 1 desert sample exists; exact
    count NOT pinned — the seed is free, the LAWS are pinned).

## 3. Slice 2 -- Surface colors (design)

**Goal:** each tile vertex's albedo comes from the climate weights +
slope + snowline, not the height-band tint table. Changes:

- `_band_color(lift, sea)` delegates to a biome blend: sample the
  climate weights at the vertex direction, mix the biome palette
  (grass green, forest darker green, sand tan, tundra pale, swamp murk,
  alpine gray, snow white), then darken below the waterline as today.
- Slope modifier: steep faces (normal dot vs radial from the tile
  geometry the streamer already builds normals per vertex) blend
  toward rock gray. Snow overrides above the snowline (temperature
  band, not a fixed lift) BUT the spawn apron stays snow-free.
- Materials: no extra draw calls -- same `vertex_color_use_as_albedo`
  path, same checker texture underneath, skirts take the ground color
  of their top edge as today.
- Probe additions (`probe_terrain_biome`): mesh surface-0 vertices are
  colored (non-black), seabed below sea reads darker than land above
  sea in the SAME face, no vertex is the old TINT placeholder when the
  biome blend owns it (acceptance: palette colors differ from the old
  band table in >= 90% of samples). Renders verified via the existing
  playtest probe boot.

## 4. Slice 3 -- Hydrology: water independent of the sea line (design)

**The user constraint stated as law:** standing water (seas, lakes,
ponds, rivers, swamps) can occur at ANY elevation -- a mountain can
hold a lake. Depressing terrain to a global water shell is therefore
WRONG for inland water. The design:

- **Water table field:** `water_table(d, seed) -> float` -- a smooth
  noise field (2-3 octaves) of the LOCAL water surface height, clipped
  below terrain + a minimum depth, and always < the terrain rim that
  holds it. Basins (where `water_table > terrain_height`) hold lakes;
  the water BODY is the water table surface, NOT the sea.
- **Carving:** where a basin forms, depress terrain by
  `max(0, water_table - terrain + MIN_DEPTH)` smoothed over the basin
  -- so pools have depth, not paper-thin sheets, AND the depression
  feeds the continuity bound (max step bound unchanged).
- **Rivers:** seed-chosen SPRING nodes (one per ~N land noise cells,
  pure function of seed). Each spring walks a downhill polyline
  (greedy steepest-descent over the analytic law with a max step count,
  deterministic tie-breaking by seed) until it hits the sea line or a
  lake basin. The polyline CARVES its channel (deepen + smooth the bed
  over an angular radius) and RAISES the water table along itself
  below the crest, so rivers are data in the heightfield law, not
  scene nodes. Downstream of a lake the river rides the lake level.
- **Rendering:** each patch gets a WATER SURFACE mesh built from the
  water-table field sampled at tile resolution over the land where
  `water_table > terrain` (build-time, like skirts): a translucent
  blue StandardMaterial, transparency OFF in the material budget for
  the WASM build if needed (fall back: opaque water-ish tint). The
  ocean keeps the existing globe scene water shell (sea-level body of
  water already works; it is the 0-height water table boundary).
- **Swamps:** biome reads the water table: `water_table within
  [terrain - WET_BAND, terrain]` and flat/gentle -> swamp band renders
  (murk green-brown), scattered cattails later (slice 4).
- **Walk law:** hydrology does NOT change the walk law unless a slice
  adds swim-through ponds; v1 pins: ponds are shallow (<= SWIM_DEPTH
  cap at their deepest) or carve themselves so the walker can still
  cross; mountain lakes deepen and the existing swim class trees out
  via the water-as-data law later if desired (design note only).
- **Probe pins:** basins hold water above the sea line (a mountain
  basin sampling pin: exists a direction where water_table > sea and
  terrain < water_table); rivers slope strictly downhill per step and
  terminate at sea or lake; no river crosses a ridge crest silently
  (the downhill law guarantees it); continuity: the carve adds no
  step > 4 m; determinism: same seed -> identical polyline.

## 5. Slice 4 -- Progressive detail scattering (design)

The Reddit idea, made law: props PAY BY DISTANCE, not by presence.
Extends the existing prop holder + hot graft (rocks/trees keep identity
across LOD changes):

- **Budget bands per patch level:** base level (near): full scatter --
  trees, bushes, rocks, detail tufts (grass, flowers, cattails by
  biome) via a shared-biome color palette; demoted levels: trees only,
  as ONE MultiMeshInstance3D per species-per-patch (one draw call);
  farthest floor level (LOD_MIN): biome COLOR does the work -- no
  scattered trees at all (the vertex palette already paints forest
  green bands).
- **Scatter law:** density per face derived from the climate weights
  (forest weight draws trees, swamp weight draws reeds near water,
  grass weight draws tufts), pure function of (face, seed) like
  rock_specs today. Independent derived streams per prop type (the
  boulder law's discipline: adding trees never reshuffles rocks).
- **The grammar:** trees keep trunk+canopy; detail props are single
  mesh instances (no colliders); swim-through reeds get none either.
  Numbers stay budget-sized per face so 4 streamed patches never
  exceed a fixed instance cap (probe counts it).
- **Hot graft stays:** detail scatter lives under the SAME prop holder;
  level changes graft it like rocks today. Only the CONTENT GROWS on
  cold visits (accepted cost, journaled).
- **Probe pins:** near face carries the full band (trees + tufts),
  demoted face carries the reduced band, floor face carries nothing,
  MultiMesh count <= cap, hot demote+promote keeps prop identity,
  cold visit respawns (the accepted contract).

## 6. Non-goals / later

- Town/city detail meshes (covered by PRDs elsewhere).
- Flowing river animation (river beds are carved; the water surface
  animation rides the ocean shell law later).
- Weather-driven biome tinting (the cosmic/weather band already tints
  the SKY; ground tinting joins only if it proves cheap).

## 7. Acceptance gates (all slices)

1. All new fields are pure: probes pin same-ness twice + determinism
   test battery stays green.
2. Spawn apron stays dry, flat, and the boot horizon law pins stay.
3. Continuity: no new carve may produce a radial step > 4 m at probe
   refinement.
4. Runner battery + charset lint (ASCII) green after every slice.
5. The continent-walk probe (stream probe section) extends naturally:
   walk law == analytic law at every stop even WITH hydrology carves.
