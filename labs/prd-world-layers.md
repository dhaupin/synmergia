# PRD: World Layers -- Which System Owns What

> **Status:** LAW (round 10). One page. Nobody re-litigates this in
> an issue, a play-test round, or a refactor.
>
> The user law it encodes: "solid math, shared state, seed, physics,
> mechanics, layers" -- the ENGINE's layers are the layering systems.
> We do not build bespoke parallel stacks where Godot already has one.

Synmergia is a layered world. Five subsystems all get called
"layers" or "world state"; each owns exactly one question. When a
feature seems to need two, the feature is wrong, not this table.

| Layer | Owner | Owns the question | Never owns |
|---|---|---|---|
| **Canonical state** | `FrameService` + T3 tree (content-hash) | What IS true. Registered entities, bags, quests, acts, flags -- the server's word. Every state mutation ends here. | Positions as a physics source. It records outcomes, it does not simulate. |
| **Spatial truth** | Godot physics (CollisionObject3D layers, the surface pad, ray/shape queries) | What can I touch, where does the ground hold me. The pad IS the ground; PropCollider bodies ARE the walls. | Gameplay targeting. A raycast may *inform* a target; it never *decides* one. |
| **Interest** | `EntityService` + `game/core/services/entity_interest.gd` | Who is around me (players/enemies/NPCs, radii, aggro ranges, chat channels). ONE law: `query_interest` / `query_all` / `query_players`. | "Nearby" redefined per call site. No system may hand-roll its own radius scan over raw dicts. |
| **Named collision bits** | `data/physics_layers/` LayerProfile (round 10) | Which bit means what: entity=1, solid=2, ground=4. `Layers.bit("entity")`, `Layers.mask("world")`. No new magic-bit literals in `game/` (lint-checked intent; `test_layer_profile.gd` pins the values). | Per-scene ad-hoc masks. A scene that needs a new bit adds it to the .tres first. |
| **Ground law** | `TerrainGen` + `GlobeTerrainStreamer` (the terrain arc) | How high is the ground. One law: `terrain_height(dir, seed)` analytic == tile mesh == pad lift == snap provider. Visuals and physics read the SAME function. | A second heightfield. If a system disagrees with the ground law, the system is wrong. |

## Deliberately NOT used (recorded decisions, do not "fix")

- **`NavigationServer`** -- future work (pathfinding for mounts,
  ferries, companion AI). Interest + steering covers every current
  mechanic. Adding it early means maintaining navmeshes over a
  streamed planet for zero shipped features.
- **`MultiplayerSynchronizer`** -- peer-shaped replication. Our
  transport is authoritative-server state push (T3 -> client). A
  per-node synchronizer would fight the frame for authority.

## The rules this page enforces

1. **Physics is spatial truth, not game state.** If you can answer a
   gameplay question from EntityService/FrameService, you must.
2. **One interest law.** New "nearby" code calls `entity_interest.gd`.
   `get_entities_in_radius` with a default type arg is a bug shape
   (the round-10 lesson: projectile scans defaulted to NPC, making
   explosions unable to hit players or enemies).
3. **One ground law.** Any height you read comes from the terrain
   law, never from a node's transform of some other node.
4. **Bits are data.** `0b0000111` in a .gd file is a bug. Add the
   semantic name to `physics_layers_main.tres`, then use it.
5. **Visuals never outrun truth.** A streamed tile renders the same
   law the player stands on; if the screen disagrees with the truth
   line, we instrument the screen (round-10 truth line reports the
   stream state) rather than explain it away.
