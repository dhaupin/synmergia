# PRD: World Topology & Player Experience

> **Status:** Decisions locked 2026-09-25 after the Nexus Central +
> id-convention work. This is the "what kind of world is this" doc:
> planet shape, land masses, seamless zone transitions, instanced
> content, and the procgen pipeline that builds it all.
>
> Related: `prd.md` (frame), `prd-geometry.md` (NSC-9 / spatial
> addressing), `prd-story.md` (the world's history), `prd-quests.md`
> (quest engine).

## 1. The planet

- **One sphere.** Synmergia is a single spherical world (NSC-9
  icosahedral addressing; see prd-geometry.md). No floating-island
  skyboxes, no "world map is a lie."
- **Land masses (total: two + poles TBD):**
  1. **The Starter Continent** -- the only inhabited land mass. The
     Nexus Central capital sits **on its coast** (harbor district,
     ferry docks), with the starter plains and Haven village inland.
     All of Act 1 and Act 2 live here.
  2. **The Dev Island** -- an isolated sandbox land mass for
     tooling, tests, and experimental content. Not reachable by
     normal travel; reachable by dev teleport. Never ships as
     player-reachable unless promoted deliberately.
  3. **Poles (ice):** deferred. Design later whether they are
     walkable regions, ocean, or narrative-only.
- **Everything else is ocean.** The fleet/ferry system (VehicleData,
  kind=FERRY) is the canonical long-haul over water.

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

Mostly procedural, hand-authored where it earns it:

1. **Common building blocks.** A library of authored primitives --
   walls, floors, conduits, ruins, props (DwellingData items double
   as world-scale pieces). Rules assemble them: settlements grow
   along roads, roads follow terrain, conduits follow old-world
   lines from the story PRD.
2. **Hand-authored anchors.** Signature places (Nexus Central
   harbor plaza, the Spire doors, Haven) can be authored as whole
   meshes (Blender/Meshy) and placed as anchors that procgen
   respects rather than overwrites.
3. **AI-assisted assembly (exploration).** A generative step that
   composes block layouts from prompts/style constraints is worth a
   spike -- same contract as rule-based procgen: it must emit the
   same block vocabulary, so the pipeline cannot tell which hand
   made a layout.
4. **Determinism law.** Every generated result must be reproducible
   from a seed (the frame's seed authority, prd-frame-authority.md).
   A regenerated chunk is bit-identical.

## 4. Scale budget (the size question)

- The current 20 km planet / 150 km2 continent numbers are a
  **budget**, not a promise. The honest scaling factors:
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
- **Procgen quality floor:** generated settlements must read as
  built by people in a post-machine world -- scarcity-driven,
  assembled from salvage. Block vocabulary inherits the art PRD's
  rules (no engines, no factory lines).
- **Ocean is not empty:** ferries, sea content, and the horizon
  promise ("there is more out there") carry the sense of scale.

## 6. What this changes in existing docs

- `prd-story.md` Act 1 locations stand as written; this doc fixes
  their planet-level context (coast, harbor, waypoint hop).
- `prd-geometry.md` remains the addressing authority; this doc adds
  the land/ocean/instance topology on top of it.
- World-building docs' "capital at geographic center" is superseded:
  **Nexus Central is on the coast.** Inland capital references in
  older docs are pre-2026-09-25 drift.
