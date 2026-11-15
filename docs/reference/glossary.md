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
| **A11yService** | The engine-side owner of the accessibility snapshot. It walks the live scene, assigns `ui:` and `world:` handles, and exposes focus and activation verbs. |
| **AccessKit** | Godot's native accessibility bridge. The engine publishes names, roles, and focus through it; `A11yService` is the game-side tree the agent lane also reads. |
| **AgentDoor** | The opt-in agent control path. Enabled with `SYN_AGENT=1` or the web build's `window.SynmergiaAgent` bridge; agents use the same verbs as players. |
| **AgentDriver** | The engine service behind the door. It owns the observe, act, wait, and event verbs and refuses disabled, unknown, or unauthorized requests. |
| **Authoritative server** | The server owns world state. Clients send input; they do not decide outcomes. |
| **Clipmap** | The sole terrain renderer. Terrain is drawn in rings around the player, with detail falling off toward the horizon. |
| **Codex** | The website's browsable read of `game/data`, generated through `src/data/godot_data.json`. It is not a separate content store. |
| **Frame** | The reusable core under `game/core/frame/`: spatial geometry, the state tree, the scope engine, the rules engine, and related primitives. It is in-repo today, not a standalone package; see [The frame]({{ '/build/frame/' | relative_url }}). |
| **gamestruct** | The shared accessibility and agent contract: a semantic tree, four primitives, human and agent lanes, HTTP and MCP bindings, and adapters. Synmergia pins it as the common carrier. |
| **MCP** | Model Context Protocol. gamestruct projects the agent lane into MCP JSON-RPC (`initialize`, `tools/list`, `tools/call`); the Synmergia door itself does not serve MCP. |
| **Multi-iso orchestrator** | The sidecar that provides indexed spatial queries for the world. |
| **Shard** | A running server/world instance in the Docker-based mesh. A shard is infrastructure, not a zone. |
| **Scope band** | A skill's reach or area folded from its upgrade level. Higher tiers can extend range or fan a skill to more targets. |
| **Seat** | An agent's own account and character identity. A seat can party with humans; it cannot drive a human's body. |
| **See** | The optional fifth gamestruct primitive. It captures a frame and returns a path or URL descriptor, never pixels. |
| **Seed** | The deterministic input used to generate world content. The same seed and content produce the same world. |
| **Sign-off gate** | A coordinator checkpoint that parks a consequential agent verb for explicit human approval instead of letting it silently execute. |
| **Stable handle** | The opaque id an action carries: `ui:<root-relative-path>` for a control or `world:<entity_id>` for a world entity. Agents act by handle, never by pixel or list index. |
| **Tier** | The five-rung item and skill scale: common, rare, epic, legendary, mythic. `GameTier` is the single source. |
| **`.tres`** | Godot's text resource format. The canonical game content under `game/data/` is authored as `.tres` files. |
| **T3 state tree** | The content-hash state tree used by the frame for authoritative world state. |
| **World** | A planet-scale play space described by a world declaration such as `world_main.tres`. |
| **Zone** | An authored content area inside a world, such as a starter plain or a dungeon entrance. |
| **prestruct** | The React prerender/SSG tool used by the website. It is not part of the game runtime. |
| **freestruct** | The post-build SEO layer used by this docs portal. It is not part of the game runtime. |

If a term is missing, [open a docs issue](https://github.com/dhaupin/synmergia/issues) or send a pull request.
