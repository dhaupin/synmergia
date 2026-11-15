# World Building — Current Overview

> **Status:** ACTIVE INDEX (2026-11-14). This is the entry point for world
> law, not a design plan. The original 5,035-line 2026-09-17 plan is archived
> at [`archive/world-building-plan-2026-09-17.md`](./archive/world-building-plan-2026-09-17.md);
> cite it only as history.
>
> **Authority order:** code + its receipts > [`prd-terrain.md`](./prd-terrain.md)
> (the ground law) > [`prd-world.md`](./prd-world.md) (topology and player
> experience) > this page. If this page disagrees with those, they win.

---

## 1. Current world law

### 1.1 One spherical planet

- Synmergia is a single sphere with a **20 km radius** for v1
  (`Spherical.PLANET_RADIUS_METERS`). The planet is not a flat map with a
  spherical skin.
- The live world is spherical. `project.godot` declares the spherical shape
  and boots `globe_world.tscn`; the old planar open world and its controller
  are deleted.
- Planar geometry survives only where the instance contract allows it:
  arenas, duels, and dungeons are planar AABBs with vanilla -Y gravity. They
  do not join the icosahedral mesh. See
  [`prd-world.md`](./prd-world.md) §2c and `core/schemas/instance_contract.gd`.

### 1.2 Land is a law, not a painted map

`TerrainGen.terrain_height(dir, world_seed)` is a pure function of direction
and seed. The mesh, the walk surface, biome selection, and placement all read
the same law, so there is no "world map is a lie" seam.
[`prd-terrain.md`](./prd-terrain.md) owns the climate, hydrology, surface, and
progressive-detail rules; [`prd-world.md`](./prd-world.md) owns why the places
exist.

Two layers compose:

- **The emergent field** — value noise gated by latitude grows continents,
  islands, and coastlines from the seed.
- **The authored sculpt** — pinned features the game needs: the homeland dome
  around spawn, the boot cove and coast capital, the inland village and its
  road, the ring mountain range, the mountain lake, the ferry island, the Sun
  Pans atoll, the two polar caps, and the Sundered Sea backend. These are
  pure functions of direction too, not placed scene objects.

The starter continent is the only inhabited landmass at launch. The ferry
island, lake, atoll, poles, and emergent continents are real ground; the moon
is a separate world scene. The old "one 150 km² continent, rest ocean" framing
is retired.

### 1.3 Zones are seamless; transitions are explicit jumps

- Zones on the starter continent are contiguous geographic regions, not
  loading screens. Zone data lines govern PvP mode, level gates, spawn
  ownership, and quest credit. Walking across a boundary is seamless.
- Crossing the world uses `WaypointService` gateways, ferries, and portals.
  Instances (dungeons, arenas, bouts) are separate scopes with their own
  lifecycle.

### 1.4 The server tick is authoritative

`TickService` is a live autoload. It runs the authoritative tick, re-roots the
shared world state tree, emits AOI diffs, persists root snapshots, and adapts
the heartbeat from the shard flywheel. Phase 6 (the old planar Markov chunk
prefetch) is retired; predictive prefetch now lives on the canonical read side
in `PropLayer.enable_prefetch()`.

The implementation and its real status are documented in
[`world-building-tick.md`](./world-building-tick.md). The short version:
phases 1-5 are implemented; phase 6 is retired, not pending.

### 1.5 The moon is the dev and test space

The old dev island is retired. Development and test content live on the moon
(`world_moon`, [`prd-multiworld.md`](./prd-multiworld.md)); the island off the
coast is the real ferry island. The moon is a separate world scene, not a
second patch of the same sphere.

### 1.6 Shape is a parameter

`world.shape` is `planar | spherical`; no system may hardcode one shape. The
shape selects the projection function and the walk/gravity contract. The
current live world selects `spherical`; `planar` is retained for the instance
contract (arena, duel, dungeon). This is a parameter, not a promise that the
open world supports a planar mode.

### 1.7 Deterministic entity seeds

Every entity carries a `seed` field. `EntityService` derives it through the
canonical `SeedChain` stack: the owning player's frame seed when one exists,
otherwise the entity id bytes. The same entity derives the same seed across
logins and machines. See `game/core/frame/kv/seed_chain.gd` and
[`prd-seed-schema.md`](./prd-seed-schema.md).

---

## 2. Authority map

| Question | Read |
| --- | --- |
| What is the planet, where are the landmarks, how do zones work? | [`prd-world.md`](./prd-world.md) |
| What is the ground made of (biomes, climate, hydrology, surfaces)? | [`prd-terrain.md`](./prd-terrain.md) |
| How is terrain rendered and streamed? | [`prd-clipmap.md`](./prd-clipmap.md) |
| How is space addressed (NSC-9, icosahedral, fragments)? | [`prd-geometry.md`](./prd-geometry.md) |
| How is the frame architected (T3, scope, rules, trees)? | [`world-building-arch.md`](./world-building-arch.md) |
| How does one server tick work? | [`world-building-tick.md`](./world-building-tick.md) |
| Which decisions, risks, numbers, and terms are recorded? | [`world-building-risks.md`](./world-building-risks.md) |
| What are the spherical math conventions and constants? | [`world-building-spherical.md`](./world-building-spherical.md) |
| What research angles were considered, adopted, or dropped? | [`world-building-research.md`](./world-building-research.md) |
| What is on the moon and in the underworld? | [`prd-multiworld.md`](./prd-multiworld.md), [`prd-underworld.md`](./prd-underworld.md) |

---

## 3. Retired and superseded claims

These are the traps in the old prose. Do not restore them.

| Retired claim | Current truth |
| --- | --- |
| The open world supports planar and spherical maps equally. | Spherical only. Planar is an instance contract for arenas, duels, and dungeons. |
| One 150 km² continent contains all content; the rest is ocean. | Starter continent + ferry island + mountain lake + Sun Pans atoll + polar caps + emergent continents. |
| The capital sits at the geographic center of the continent. | The capital is on the coast at the boot cove; the starter village is inland about 1 km away. |
| The dev island is an isolated sandbox off the coast. | Retired. The island is the real ferry island; dev content lives on the moon. |
| Floating islands are forbidden skyboxes. | Allowed and wanted, reachable by thermal updraft or gate. They are real ground, not decorative boxes; the law is designed but not built. |
| The spherical docs use Earth's 6,371 km radius and 111.32 km per degree. | v1 uses a 20 km radius; 111.32 km/degree is an Earth known-answer constant, not the game's scale. |
| LODManager, the planar chunk generator, and the terrain streamer are live. | The clipmap is the sole renderer; PropLayer/PropChunk owns scatter; the streamer is deleted. |
| The tick is design-only, with no tick loop or flywheel service. | `TickService` and `FlywheelService` are live autoloads; phases 1-5 run. |
| Prediction runs inside the tick over planar chunks. | Phase 6 is retired. Prefetch warms the predicted PropChunk cell on the read side. |
| Per-player tick rates are the model. | The heartbeat adapts at shard level; per-player flywheels are anticheat/activity instrumentation in `FlywheelService`, not separate tick loops. |

---

## 4. Where the old plan went

The full 2026-09 plan is preserved at
[`archive/world-building-plan-2026-09-17.md`](./archive/world-building-plan-2026-09-17.md)
with its section numbers. Use this map when an old citation sends you there.

| Old plan section | Current authority |
| --- | --- |
| §3.9-3.12 world spec / continent / capital | [`prd-world.md`](./prd-world.md) §1-2; [`prd-terrain.md`](./prd-terrain.md) §2b |
| §4 seed model | [`prd-seed-schema.md`](./prd-seed-schema.md), [`prd-state-schema.md`](./prd-state-schema.md) |
| §5 content-hash state tree | [`prd-state-schema.md`](./prd-state-schema.md), [`world-building-arch.md`](./world-building-arch.md) §8 |
| §6 geometric addressing | [`prd-geometry.md`](./prd-geometry.md) |
| §7 procedural generation | [`prd-terrain.md`](./prd-terrain.md) |
| §8 zone model | [`prd-world.md`](./prd-world.md) §2 |
| §9 server tick | [`world-building-tick.md`](./world-building-tick.md) |
| §10 transport | [`world-building-tick.md`](./world-building-tick.md) §4; `game/core/services/network_manager.gd` |
| §12 persistence | [`prd-db.md`](./prd-db.md) |
| §14 LOD and predictive prefetch | [`prd-clipmap.md`](./prd-clipmap.md) |
| §18.8 per-entity seed | §1.7 above; `SeedChain` |
| §21 experimental angles | [`world-building-research.md`](./world-building-research.md) |

---

## 5. Reading order

- **New to the world:** `prd-world.md` -> `prd-terrain.md` -> `prd-clipmap.md`.
- **Working on the frame or server:** `world-building-arch.md` ->
  `world-building-tick.md` -> `world-building-risks.md`.
- **Doing spherical math or navigation:** `world-building-spherical.md` ->
  `game/core/frame/math/spherical.gd`.
- **Looking for a discarded idea:** `world-building-research.md` and the
  archive. Neither is current law.

When the world law changes, update the PRD that owns it and this index in the
same edit. A sentence that names a deleted system is a bug, not history.
