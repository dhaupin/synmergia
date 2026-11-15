---
permalink: /world/planet/
layout: default
title: The Planet
description: Synmergia's 20 km spherical world, the clipmap terrain, and the world declarations that give each globe its identity.
---

# The planet

Synmergia's main world is a **20 km sphere**. The player stands on the outside of it; the terrain is rendered as a clipmap around the camera, so detail follows the player instead of arriving in rectangular chunks.

## What the player sees

- A continuous horizon with no map edge and no region loading screen.
- Terrain rings that add detail near the player and simplify toward the horizon.
- A water sheet, road deck, and procedural prop layer over the terrain.
- Authored zones, landmarks, NPCs, quests, and world bosses placed into the same spherical space.
- A day/night and weather layer that the server and client share.

The planet is not a painted skybox. The client derives its position and the visible terrain from the same world data the server uses.

## The world declarations

The scene is generic; the data gives it identity. A world declaration is a `.tres` resource that names the world and supplies its radius, gravity, orbit, and lore. The main world is `world_main.tres`.

The repository also carries declarations for the moon and The Deep Root. The main world is the live play surface; the other declarations are part of the same world model, not separate engines.

## Under the hood

- `game/core/frame/` holds the reusable spatial and state primitives.
- The clipmap is the sole terrain renderer. `LODManager` and the legacy globe streamer are retired.
- The same `PropChunk` addressing is used by the prop layer, the client, and the spatial index.
- The authoritative server owns world state; the client renders its view of that state.

Deep design notes, still in the workshop:

- [The clipmap](https://github.com/dhaupin/synmergia/blob/main/labs/prd-clipmap.md)
- [The spherical world reference](https://github.com/dhaupin/synmergia/blob/main/labs/world-building-spherical.md)
- [The frame architecture](https://github.com/dhaupin/synmergia/blob/main/labs/world-building-arch.md)

## Where to go next

- [The world overview]({{ '/world/' | relative_url }}) for combat, economy, social play, and housing.
- [The Codex](https://synmergia.creadev.org/codex) for the zones and content that populate the planet.
- [Play](https://synmergia.creadev.org/play) to see it run in the browser.
