---
permalink: /world/
layout: default
title: The World
description: A systems view of Synmergia - the planet, combat, economy, social play, housing, and the browser client.
---

# The world, as a system

This is the systems view, not the story. It explains how the world is put together and where each part lives in the code and data. The canon - the Codex, lore, rules, and guides - stays on the [main website](https://synmergia.creadev.org/).

## A planet, not a map

The main world is a 20 km sphere rendered as a clipmap around the player. There is no loading screen between regions and no rectangular map edge. The world is described by data declarations and streamed by the client; the server owns the state that matters.

[Read how the planet works]({{ '/world/planet/' | relative_url }}) for the sphere, the terrain rings, and the world declarations.

## The systems

| System | What it is | Where to see it |
|---|---|---|
| **Combat** | Action combat with roles, resources, reach bands, and a five-rung upgrade scale | [Codex: classes and skills](https://synmergia.creadev.org/codex) |
| **Economy** | Gathering, blacksmithing and crafting, direct trading, and a black-market sink | [Codex: items and recipes](https://synmergia.creadev.org/codex) |
| **Social** | Guilds with ranks and permissions, parties and raids, friends, chat, and territory claims | [Codex](https://synmergia.creadev.org/codex) and the [rules](https://synmergia.creadev.org/rules) |
| **Housing** | Player plots and house tiers placed in the world | [Codex](https://synmergia.creadev.org/codex) |
| **The browser client** | The Godot WebAssembly build, served beside the website at `/game/` | [Play](https://synmergia.creadev.org/play) |

The Codex is the complete read of the data. This page is the map of the systems; the Codex is the index of every entry.

## What this section is not

- It is not the [Codex](https://synmergia.creadev.org/codex). The Codex enumerates classes, skills, items, enemies, recipes, mounts, and more from `game/data`.
- It is not the [Lore](https://synmergia.creadev.org/lore). Story and canon are authored for the website.
- It is not a player guide. Guides and the community wiki belong on the website.

## The surface is part of the world

The world is not only seen. Every actionable node also has a name, a focus position, and a stable handle, so a screen reader and an agent can read the same surface. Start with [Access and agents]({{ '/access/' | relative_url }}) for the one-tree model, or [Human accessibility]({{ '/access/human/' | relative_url }}) for the engine side.

## Under the hood

The reusable frame lives in `game/core/frame/`: the state tree, scope engine, rules engine, spatial geometry, and the clipmap addressing that the world, client, and spatial index all share. The game consumes those primitives; it does not fork them.

[The frame]({{ '/build/frame/' | relative_url }}) page covers what is reusable today, what stays game-side, and the current packaging boundary. The short version: the code is real and MIT-licensed, but there is no standalone install yet.

For the current deep design notes, see [the frame architecture](https://github.com/dhaupin/synmergia/blob/main/labs/world-building-arch.md) and [the spherical world reference](https://github.com/dhaupin/synmergia/blob/main/labs/world-building-spherical.md) in `labs/`. Those graduate into this portal as they stabilize.
