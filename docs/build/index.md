---
permalink: /build/
layout: default
title: Build Synmergia
description: The repository map, local setup, tests, architecture notes, and the contribution path.
---

# Build the world with us

Synmergia is MIT-licensed and developed in the open. The engine, server, data, website, and docs all live in one repository. This section is the contributor path; the player-facing surface stays on the [main website](https://synmergia.creadev.org/).

## Start here

1. [Set up the local toolchain]({{ '/build/local-setup/' | relative_url }}) - Godot 4.7.2, Node 20+, Bun, and the repository scripts.
2. [Run the tests]({{ '/build/testing/' | relative_url }}) - the one Godot runner, the web checks, and the docs build.
3. Read [CONTRIBUTING.md](https://github.com/dhaupin/synmergia/blob/main/CONTRIBUTING.md) for the PR flow and the conventions.
4. If you are touching GDScript, read [AGENTS.md](https://github.com/dhaupin/synmergia/blob/main/AGENTS.md) first. It carries the autoload, indentation, and test rules.
5. Read [Access and agents]({{ '/access/' | relative_url }}) before adding a UI control or an agent-facing endpoint. Every new actionable needs a name, a focus position, and a stable handle.

## Repository map

| Path | What lives there |
|---|---|
| `game/` | The Godot 4.7.2 project: services, world, combat, data, UI, and tests |
| `src/` | The React/Vite/Tailwind website and its prerender configuration |
| `web/` | The raw engine shell served at `/game/`, including the packed PCK |
| `srv/` | Bridges, the Julia sidecar, Docker, and deployment configuration |
| `labs/` | PRDs, architecture notes, world-building docs, and the task board |
| `docs/` | This Jekyll docs portal |
| `scripts/` | Setup, test, build, data-sync, and generation tooling |

## The stack

- **Godot 4.7.2 + GDScript** for the game, exported to the browser as WebAssembly.
- **Authoritative server** with a content-hash state tree and server-owned world state.
- **React + Vite + Tailwind** for the website, prerendered with prestruct.
- **Jekyll + freestruct** for this docs portal.
- **Docker** for the game server and the optional shard mesh.

## Current docs status

This is the first cut of the portal. The stable, code-backed material is here; the deep architecture notes still live in `labs/` until they are rewritten for this audience. The most useful starting points in the workshop are:

- [Frame architecture](https://github.com/dhaupin/synmergia/blob/main/labs/world-building-arch.md)
- [Persistence and adapters](https://github.com/dhaupin/synmergia/blob/main/labs/prd-db.md)
- [Web client and portal](https://github.com/dhaupin/synmergia/blob/main/labs/prd-web.md)
- [Data authoring baseline](https://github.com/dhaupin/synmergia/blob/main/labs/data-authoring-baseline.md)

## Build these docs

```bash
cd docs
bundle install
bundle exec jekyll build
cd ..
node node_modules/freestruct/bin/freestruct.mjs --strict
```

Or use the repository scripts:

```bash
npm run docs:build
npm run docs:serve
```

The deploy lane runs the same Jekyll build, then freestruct, pagefind, and the GitHub Pages upload. The site is served at [docs.creadev.org/synmergia](https://docs.creadev.org/synmergia/).

## Where to ask

- [Open an issue](https://github.com/dhaupin/synmergia/issues) for a bug, a question, or a proposal.
- [Read the Code of Conduct](https://github.com/dhaupin/synmergia/blob/main/CODE_OF_CONDUCT.md).
- [Report a security issue privately](https://github.com/dhaupin/synmergia/blob/main/SECURITY.md), never in the public tracker.
