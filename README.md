# Synmergia

**A browser-first, open-world MMORPG built on Godot 4.7.2.**

Synmergia is a persistent 3D sandbox: a spherical planet with player housing,
territory, guilds, action combat, an economy shaped by players, and a world that
keeps running while you are offline. The client is a WebAssembly build of the Godot
project; the game server is authoritative; the site around it is a
React/Vite/Tailwind app deployed on Cloudflare Pages.

[Play the early-access build](https://synmergia.creadev.org/play) ·
[Main site](https://synmergia.creadev.org/) ·
[Docs](https://docs.creadev.org/synmergia/) ·
[Product spec](labs/prd.md) ·
[Contributing](CONTRIBUTING.md)

> **Status: pre-launch.** The core world, combat, social, and economy loops are
> in the code and exercised by the headless test suite. The public `/play` page
> is gated to early-access key holders while launch is finished. "Planned" below
> means not shipped yet; it is not a release date.

## What works today

| Pillar | In the current code |
|---|---|
| **Combat** | 21 class resources: 18 playable classes across 6 archetypes and 3 species, plus 3 GM-only classes; a skill academy, buffs/debuffs, arena combat, and open-world PvP |
| **World** | 20 km spherical planet, clipmap terrain, procedural props and resources, player housing, and timed world bosses |
| **Economy** | Gathering, blacksmithing and crafting, direct player trading, and a black-market sink; a player-run market/auction is not shipped yet |
| **Social** | Guilds with ranks and permissions, parties and raids, friends/ignore, chat, territory claims, and community governance |
| **Platform** | Browser WASM client, authoritative Godot server, Docker-based shard mesh, and a React/Vite web portal |

## What is still in progress

- A player-run market/auction and deeper crafting professions.
- More dungeon content and broader dynamic encounters; world bosses already ship.
- Guild halls, and player-declared faction wars (the current `/war` surface is
  operator-gated until factions have a leader model).
- Public launch, onboarding, and live operations.

## Technology

- **Godot 4.7.2 + GDScript** for the game, exported to the browser as
  WebAssembly/WebGL2.
- **Authoritative server** with a content-hash state tree, deterministic seed
  derivation, and server-owned world state.
- **Canonical world addressing** through the clipmap's `PropChunk` cells; the
  same cell is derived by the prop layer, the client, and the spatial index.
- **Multi-iso orchestrator** sidecar for indexed spatial queries, with a
  stdlib-only Julia `server_lite.jl` for development and container boot.
- **React + Vite + Tailwind** for the site, prerendered by `prestruct` and
  deployed to Cloudflare Pages.
- **Docker** for the game server and the optional shard mesh.

The reusable frame — T3 content-hash state tree, scope engine, rules engine, and
clipmap addressing — is deliberately extractable from the game.

## AI agents

Agents can join the same world as players through the opt-in **AgentDoor**
(`SYN_AGENT=1`) or the web build's `window.SynmergiaAgent` bridge, using the
same verbs a player uses. The generic MCP projection is not included in this
repository; it lives in gamestruct.

## Repository map

| Path | What lives there |
|---|---|
| `game/` | The Godot project: services, world, combat, data, UI, and tests |
| `src/` | The React/Vite/Tailwind site and its prerender configuration |
| `web/` | The raw engine shell served at `/game/`, including the built PCK |
| `srv/` | Bridges, the Julia sidecar, Docker, and deployment configuration |
| `labs/` | PRDs, architecture notes, world-building docs, and the task board |
| `scripts/` | Setup, test, build, data-sync, and generation tooling |

## Quick start

You need **Godot 4.7.2**, **Node 20+**, **bun** (npm also works), and Python 3
for a few sidecar scripts.

```bash
git clone https://github.com/dhaupin/synmergia.git
cd synmergia

# Install the base toolchain (add --with-templates, --with-blender,
# --with-web-probe, or --all as needed).
sh ./scripts/setup-dev.sh

# Open the game project.
godot --editor game/

# Run the one headless test runner.
sh ./scripts/godot_test_runner.sh          # default regression set
sh ./scripts/godot_test_runner.sh --all    # every test_*.gd
```

For the website:

```bash
bun install
npm run dev       # local site
npm run build     # type-check + prerender
```

See [DEVCODE.md](DEVCODE.md) for environment details, sidecars, shard mode,
and the test-runner mechanics.

## Documentation

| | |
|---|---|
| [Docs portal](https://docs.creadev.org/synmergia/) | The systems view, build and contribution paths, operations, and the access and agent contract |
| [Product spec](labs/prd.md) | Gameplay, systems, and product direction |
| [Architecture](labs/world-building-arch.md) | Frame, services, tick model, and sync |
| [World design](labs/world-building.md) | Current world index: topology, terrain, retired claims |
| [Labs index](labs/README.md) | The PRD and design-doc map |
| [Developer notes](AGENTS.md) | Code conventions, patterns, and autoload rules |
| [Contributing](CONTRIBUTING.md) | Setup, conventions, tests, and pull requests |
| [Dev environment](DEVCODE.md) | Rebuilding the dev loop from the repo alone |
| [Game-server deployment](DEPLOY.md) | Docker profiles, operations, and production notes |
| [Web deployment](DEPLOY_WEB.md) | Website and browser-client deployment |
| [GPU & asset pipeline](DEPLOY-GPU.md) | GPU asset generation and the CPU import path |
| [Database & cache](labs/prd-db.md) | Persistence, cache, and adapter contracts |
| [Sidecars & operations](srv/README.md) | pg/redis/webhook/Julia, Docker tests, and backup |
| [Shard mesh](labs/prd-shard-mesh.md) | Multi-container topology and phased path |
| [Open-source audit](labs/OSS-AUDIT.md) | Launch audit and hardening checklist |
| [Security policy](SECURITY.md) | How to report a vulnerability |

## Contributing

Synmergia is built in the open. Start with [CONTRIBUTING.md](CONTRIBUTING.md)
for the setup, conventions, and pull-request flow; use [AGENTS.md](AGENTS.md)
before touching GDScript. Everyone participating agrees to the
[Code of Conduct](CODE_OF_CONDUCT.md).

Security issues should not go in the public tracker; report them privately per
[SECURITY.md](SECURITY.md).

## License

Synmergia is open source under the **MIT License** — see [LICENSE](LICENSE).
Copyright © 2026 [Creadev.org](https://creadev.org).

Third-party software, fonts, and assets are credited in [CREDITS.md](CREDITS.md)
with their own licenses. The Synmergia name and logo are covered separately by
[TRADEMARK.md](TRADEMARK.md).

---

*Synmergia — shape the world, forge your legacy, play anywhere.*
