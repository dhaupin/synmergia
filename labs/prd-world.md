# PRD: World Topology & Player Experience

> **Status:** v2 (2026-11-04). Rewritten to match the planet the
> terrain law actually builds. The v1 doc (2026-09-25) was the
> initial draft; the terrain arc (`terrain_gen.gd` + the streamer)
> has since outgrown it. Where this doc and the code disagree, **the
> code's `terrain_gen.gd` constants are the planet's truth** and this
> doc is the intent behind them. This is the "what kind of world is
> this" doc: planet shape, land masses, seamless zone transitions,
> instanced content, and the procgen pipeline that builds it all.
>
> Related: `prd-terrain.md` (the biome/climate/hydrology law that
> builds the ground), `prd.md` (frame), `prd-geometry.md` (NSC-9 /
> spatial addressing), `prd-multiworld.md` (the moon + the lattice),
> `prd-story.md` (the world's history), `prd-quests.md` (quest
> engine).

## 1. The planet

- **One sphere.** Synmergia is a single spherical world (NSC-9
  icosahedral addressing; see prd-geometry.md). The ground is a pure
  analytic heightfield law -- `TerrainGen.terrain_height(dir, seed)`
  -- sampled by the streamed globe. No "world map is a lie": the
  same law drives the mesh, the walk pad, and every placement.
- **Land comes from a noise field, not a fixed map.** The landmass
  law is value-noise gated by latitude, so continents, islands, and
  coastlines emerge from the seed. On top of that, a set of
  **authored features** pin the places the game needs (the home
  continent, the boot cove, the ferry island, the lake, the desert
  atoll). Both layers are in `terrain_gen.gd`; see `prd-terrain.md`
  for the climate/biome law and the measured numbers.
- **Floating islands are allowed (and wanted).** The v1 "no
  floating-island skyboxes" rule is **retired**. Sky islands --
  hovering landmasses reachable by **thermal updrafts** (the
  `ThermalService` / `data/thermals/` system) or by **gates** -- are
  first-class content, both in the main sky and in the underworld.
  The floating-island law is **not built yet**; this doc records the
  intent so the terrain arc can grow it. The rule that stands: a
  floating island is *real ground* (its own heightfield + walk law),
  not a decorative box parked at a fixed altitude.
- **Land masses (the authored set + the emergent field):**
  1. **The Starter Continent** -- the home landmass and the only
     one inhabited at launch. Around `SPAWN_CENTER` (lat 0 / lon 0)
     within `HOMELAND_ANGULAR_REACH` (0.70 rad ~ 14 km). It holds:
     - the **Nexus Central capital on its coast** -- harbor
       district, ferry docks, and a **large monolith visible for
       kilometers** (the capitol plaza anchor on the cove's far rim);
     - the **starter village inland** (~1 km from the coast) with a
       **road** connecting it to the capital;
     - an **inland mountain range** (the home-anchored ring range,
       ~5-10 km from the village) so the boot's vista reads: village
       on grassland, capital + ocean downhill in front, mountains
       behind.
     All of Act 1 and Act 2 live here.
  2. **The Ferry Island** -- a real player island off the coast,
     reached by ferry (and its dock waypoint). Volcanic plateau
     (`ISLAND_CENTER`, ~10.5 km from spawn), ringed by a deep moat
     channel the ferry owns. This is **not** a dev sandbox.
  3. **The Mountain Lake** -- an authored inland bowl on the
     continent's hinterland (`LAKE_CENTER`), held by the hydrology
     law at its own elevation (a lake above the sea line is legal).
  4. **The Sun Pans** -- an authored desert atoll far across the sea
     (a volcanic atoll on face 12), the only desert on this seed;
     reached by the long-haul Pans ferry. Glide-reachable from the
     homeland islands.
  5. **The Poles** -- **SHIPPED (v12, 2026-11-04).** Two authored
     ice/snow landmasses at the top and bottom of the sphere. The land
     law's latitude band zeroes land above ~45 deg, so the poles were
     open sea; the v12 polar cap adds a plateau-then-coast dome around
     each pole (the SAME max-law the homeland and the Sun Pans atoll
     pay) plus a masked relief stream, so the caps read as broken ice,
     not a flat pancake. The temperature law already reads the poles as
     the coldest place on the sphere, so the caps resolve the freeze
     ladder (TUNDRA/ALPINE) and the snowline tints them white -- no new
     biome id. Symmetric in `absf(d.y)`, so the north/south compass +
     map lat sign are untouched (the early "polar broke the compass"
     fear was a lat-sign bug in the map, fixed since by the shared
     `lat_lon_to_uv` law). Constants: `POLAR_CAP_ANG` 0.34 rad (~6.8 km
     cap radius), `POLAR_RELIEF_AMP` 420 m. Receipt:
     `game/tests/probe_polar_caps.gd`. The build-out also exposed and
     fixed a latent `_cove_window` bug (see `prd-terrain.md` section 6).
  6. **Emergent continents** -- the noise field grows additional
     far continents and islands anywhere the seed rolls land. These
     are real ground (the terrain law renders them) and are
     candidates for future content; nothing currently places on them.
- **The Dev Island is retired.** The v1 "isolated dev sandbox
  island" is **gone**. Dev/test content now lives on **the moon**
  (`world_moon`, `labs/prd-multiworld.md`), which is gate-reachable
  for normal players eventually (the moon gate; today DEV_ONLY). The
  island off the coast is the real **Ferry Island** (item 2 above),
  not a dev sandbox.
- **The ocean is the connective tissue.** The fleet/ferry system
  (VehicleData, kind=FERRY) is the canonical long-haul over water:
  `veh_haven_ferry` (village <-> capitol bay), `veh_island_ferry`
  (village docks <-> island), `veh_pans_ferry` (capitol pier <->
  Sun Pans). See section 2b.

## 2. Zone model: seamless world + explicit jumps

Two movement truths, both first-class:

### 2a. Seamless open world

- Zones on the starter continent are **contiguous geographic
  regions**, not loading screens. Walking from starter_plains into
  forest_meadow (or into Nexus Central) is seamless: no fade, no
  teleport, no "entering zone" UI beyond the ambient name plate.
- You can walk for a mile and stay in one continuous experience.
  Zone boundaries are **data lines** (ZoneData bounds/center/radius)
  used for rules (PvP mode, level gates, spawn ownership, quest
  EXPLORE credit), not for travel breaks.
- World-builder requirement: zone geometry must tile. The NSC-9
  spatial fragmenter owns addressing; zone .tres files own rules.
  Nothing in the zone schema may grow a "load on entry" concept.

### 2b. Portals: the transport system

- **Waypoints/gateways are the fast-travel network.** You do not
  walk across the whole continent to reach the capital; you walk to
  a waypoint stone and jump. (waypoint_nexus_central is the first
  continental hop.)
- Mounts shorten the walk between waypoints; vehicles (ferries,
  caravans) move groups and cargo.
- Portals are diegetic: waypoint stones, the dungeon portal, ferry
  docks -- never UI menus floating in space.

### 2c. Instances: non-world content

- **Dungeons, arenas, royales, duels are instance zones.** They run
  per-group copies of a zone definition with their own entity
  population and tick budget (ZoneData.is_instanced +
  instance_capacity; InstanceTypeDefinition owns the types).
- Instances never share entity state with the open world. Horde
  events (data/hordes/) are the open-world exception and are
  deliberately broadcast, not instanced.

## 3. Procgen pipeline: how the world gets built

Mostly procedural, hand-authored where it earns it. **The ground
itself is already built** (`prd-terrain.md`); this section is the
pipeline for the content on top of it:

1. **The ground law (SHIPPED).** `TerrainGen.terrain_height(dir,
   seed)` is the analytic heightfield: noise landmasses + authored
   features (homeland dome, boot cove, ferry island, lake, atoll,
   ring range). Climate, biome, hydrology, roads, and scatter all
   read it. See `prd-terrain.md`.
2. **Common building blocks.** A library of authored primitives --
   walls, floors, conduits, ruins, props (DwellingData items double
   as world-scale pieces). Rules assemble them: settlements grow
   along roads, roads follow terrain, conduits follow old-world
   lines from the story PRD. The starter village + capitol monolith
   are the first authored anchors on the ground law.
3. **Hand-authored anchors.** Signature places (Nexus Central
   harbor plaza + monolith, the Spire doors, the village) are
   authored as whole meshes and placed as anchors that procgen
   respects rather than overwrites. Anchors ride the **walk law**
   pedestal (analytic heightfield), never a fixed altitude -- this is
   the floating-structure contract (see section 5).
4. **AI-assisted assembly (exploration).** A generative step that
   composes block layouts from prompts/style constraints is worth a
   spike -- same contract as rule-based procgen: it must emit the
   same block vocabulary, so the pipeline cannot tell which hand
   made a layout.
5. **Determinism law.** Every generated result must be reproducible
   from a seed (the frame's seed authority, prd-frame-authority.md).
   A regenerated chunk is bit-identical.

## 4. Scale budget (the size question)

- The v1 "20 km planet / 150 km2 continent" numbers were a
  **budget**, not a promise. Measured on the live seed
  (`diag_biome_map.gd`, 6000-sample fibonacci scan, 2026-11-04):
  **~79% deep ocean, ~11% shore, ~6% land, ~3% lake**. The land
  splits between the **home continent** (faces 16 + 18, the ~14 km
  homeland dome -- ~159-251 km2) and **emergent noise continents**
  elsewhere; the whole-planet land is ~320 km2, inside the seed
  sweep band of 100-380 km2. The honest scaling factors:
  - **State:** entity count x tick cost, not raw area. Ocean tiles
    are nearly free (no entities, no state tree writes); coastlines
    and settlements dominate cost.
  - **Compute:** NSC-9 LOD (frame/srv) culls detail by player
    proximity; a bigger planet mainly grows the *address space*
    (cheap), not the *ticked set* (expensive).
- **Decision:** keep current size for v1. If perf at scale demands
  it, shrink the **land** mass (coast-dense content per km2 rises,
  ocean share grows, players never feel it) rather than the sphere
  radius, which would distort day/night and horizon feel. Any
  resize lands as a seed/schema change + full world re-bake, so it
  must happen before content lock, not after.

## 5. Dev challenges this creates (the honest list)

- **Seamless borders mean shared context:** mobs aggroing across a
  zone line, chat/zone-channel boundaries, EXPLORE quest credit
  ("entered zone") needs a walk-over trigger, not a loading
  transition. ZoneManager's entity_enter_zone already keys on
  position; the rules layer must tolerate mid-transition states.
- **Instances need a lobby contract:** enter/exit must preserve
  player state cleanly (the frame's state tree already scopes by
  zone; instances add a per-instance scope id).
- **The floating-structure contract (OPEN):** authored structures
  (village halls, houses, docks, monoliths) ride the **walk law**
  pedestal -- `planet_radius + tile_lift + walk_surface_h(dir)` --
  while the **rendered mesh** is a discrete LOD sampling of the same
  law. Where a far face's coarse mesh sags meters below the law
  between samples, a structure reads as "floating". The `LOD_FLOOR_
  LEVEL` raise (4 -> 5) shrank this; the durable fix is to seat
  authored structures on the DRAWN surface (or keep their face at a
  fine level). Reported live ("houses floating"); tracked as a bug.
- **Procgen quality floor:** generated settlements must read as
  built by people in a post-machine world -- scarcity-driven,
  assembled from salvage. Block vocabulary inherits the art PRD's
  rules (no engines, no factory lines).
- **Ocean is not empty:** ferries, sea content, and the horizon
  promise ("there is more out there") carry the sense of scale.
- **Zones are meta until the land is online:** `ZoneData` currently
  carries rules (PvP mode, level gates, instance flags) but no real
  world placement -- every `zone_center` is `Vector3.ZERO` and
  `bounds` is null. Once the terrain renders planet-wide, zones get
  real centers/bounds so EXPLORE credit, spawn ownership, and PvP
  boundaries key on actual ground.

## 6. What this changes in existing docs

- **v1 sections 1 and the "no floating islands" rule are superseded
  by this v2** -- the Dev Island is retired, the poles are real
  landmasses, and floating islands are allowed.
- `prd-story.md` Act 1 locations stand as written; this doc fixes
  their planet-level context (coast, harbor, waypoint hop).
- `prd-geometry.md` remains the addressing authority; this doc adds
  the land/ocean/instance topology on top of it.
- `world-building.md` (the original 150 km2 plan) is **historical**:
  its "capital at the geographic center" is superseded --
  **Nexus Central is on the coast**, the village is inland ~1 km
  with a road to the capital, and the mountain range is behind the
  village. Its "one continent" claim is superseded by the authored
  set + emergent continents in section 1.
- `prd-terrain.md` is the ground-law authority; this doc is the
  topology intent on top of it.
