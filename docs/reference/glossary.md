---
permalink: /reference/glossary/
layout: default
title: Glossary
description: The shared vocabulary used across Synmergia's docs, code, and deployment.
---

# Glossary

The words that mean something specific in this repository. When a page uses one of these, this is the intended meaning.

| Term | Meaning |
|---|---|
| **AgentDoor** | The opt-in agent control path. Enabled with `SYN_AGENT=1` or the web build's `window.SynmergiaAgent` bridge; agents use the same verbs as players. |
| **Authoritative server** | The server owns world state. Clients send input; they do not decide outcomes. |
| **Clipmap** | The sole terrain renderer. Terrain is drawn in rings around the player, with detail falling off toward the horizon. |
| **Codex** | The website's browsable read of `game/data`, generated through `src/data/godot_data.json`. It is not a separate content store. |
| **Frame** | The reusable core under `game/core/frame/`: spatial geometry, the state tree, the scope engine, the rules engine, and related primitives. |
| **Multi-iso orchestrator** | The sidecar that provides indexed spatial queries for the world. |
| **Shard** | A running server/world instance in the Docker-based mesh. A shard is infrastructure, not a zone. |
| **Scope band** | A skill's reach or area folded from its upgrade level. Higher tiers can extend range or fan a skill to more targets. |
| **Seed** | The deterministic input used to generate world content. The same seed and content produce the same world. |
| **Tier** | The five-rung item and skill scale: common, rare, epic, legendary, mythic. `GameTier` is the single source. |
| **`.tres`** | Godot's text resource format. The canonical game content under `game/data/` is authored as `.tres` files. |
| **T3 state tree** | The content-hash state tree used by the frame for authoritative world state. |
| **World** | A planet-scale play space described by a world declaration such as `world_main.tres`. |
| **Zone** | An authored content area inside a world, such as a starter plain or a dungeon entrance. |
| **prestruct** | The React prerender/SSG tool used by the website. It is not part of the game runtime. |
| **freestruct** | The post-build SEO layer used by this docs portal. It is not part of the game runtime. |

If a term is missing, [open a docs issue](https://github.com/dhaupin/synmergia/issues) or send a pull request.
