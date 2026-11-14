# Synmergia

**A 3D open-world MMORPG that runs in your browser.**

> **Repo layout (2026-10 wasm-first split):** `game/` is the Godot
> project (the game itself), `web/` is the raw engine shell (served at
> `/game/`), and `src/` is the website around it (lander, legal,
> gated /play + /admin) — built by `npm run build`, prerendered by
> prestruct, deployed to Cloudflare Pages. See
> [DEPLOY_WEB.md](./DEPLOY_WEB.md) for the web/site deployment guide
> and [DEPLOY.md](./DEPLOY.md) for the game-server (Docker) guide.

*Browser-first action combat meets the deepest player-driven economy since Ultima Online. No downloads. No installs. Just play.*

```
    ╔═══════════════════════════════════════════════════════════════╗
    ║   ⚔️  Browser MMORPG  •  Open World  •  Action Combat   ⚔️ ║
    ║      RYL2-Style Combat  •  UO Economy  •  Guild Alliances     ║
    ╚═══════════════════════════════════════════════════════════════╝
```

## What Is Synmergia?

Synmergia is an **open-world multiplayer RPG** built for the browser. Step into a persistent world where your choices shape the economy, your guild forges alliances, and every battle matters. Whether you're gathering resources to craft legendary gear, building your dream house on the frontier, or leading your faction into heated wars — this is your world.

No other browser-based MMORPG offers this combination of deep action combat, player-driven sandbox economy, and true open-world freedom.

---

## Why Players Love Synmergia

### 🎮 Combat That Respects Your Skill

This isn't a auto-attack-and-wait game. Synmergia features **free-form action combat** inspired by classics like Risk Your Life 2. Every fight is a dance of positioning, timing, and decision-making:

- **Dodge, parry, interrupt, and chain skills mid-combat**
- **Positioning matters** — flanking, terrain advantage, line-of-sight
- **Skill combos** planned — chain abilities for bonus effects
- **Hybrid targeting** — aim freely or tab-target nearby enemies
- **Meaningful death** — lose your gear in PvP zones, respawn with strategy

### 🏪 Economy That Players Own

Forget auction house bots and NPC vendors setting prices. In Synmergia, **the economy is built by players, for players**:

- **Resources spawn in the world** — mines, forests, fishing spots scattered across the land
- **Craft your gear** — blacksmithing with profession tiers, more crafting planned
- **Player housing** — claim land, build your home, watch it persist
- **Guild alliances** — ranks, permissions, and alliance play
- **Legendary gear from players and world bosses** — not loot boxes

This is the sandbox economy you remember from Ultima Online, rebuilt for a modern audience.

### ⚔️ PvP With Real Stakes

Risk and reward in constant tension. Synmergia offers **configurable PvP across zones**:

- **Full loot in PvP zones** — drop everything on death, fight for glory and gear
- **Territory ownership** — factions and guilds hold zones; `/claim` stakes a guild claim, and territory control persists across restarts
- **Faction wars (operator-run)** — `/war declare|end` is admin-gated until factions have a leader model; player-declared wars are the next PvP layer
- **Faction battles** — join species or ideological factions, shape the world's future
- **Arena combat** — organized PvP with balanced rulesets
- **Death has weight** — no zerg rushing, no consequence-free ganking

### 🌐 Play Anywhere, On Any Device

Your adventures shouldn't be chained to a desktop:

- **Browser-first** — play directly in Chrome, Firefox, Safari, Edge
- **Mobile-ready** — touch controls designed for action combat
- **Cross-platform** — same world, same players, any device
- **No downloads** — click, play, immerse yourself instantly

### 🤖 AI Adventurers Welcome

Want to play with friends but can't find enough players? **AI agents can join your world**:

- Connect AI characters (Claude, GPT, Vant) that play alongside humans
- Agents see the same game state, make the same decisions
- Fill out guild raids, dungeon groups, and trading posts
- MCP protocol support for standard AI interfaces

---

## Features At A Glance

### Combat & Progression
- 🎯 **21 authored classes** across 6 archetypes (Tank, DPS, Mage, Rogue, Bender, Healer)
- 🧬 **3 species** with unique abilities (Akkan, Human, Synthetic)
- 📚 **Skill academy** with upgradeable abilities and signature skills
- 🛡️ **Buff/debuff system** with 11 dispel categories (magic, curse, poison, etc.)
- ⬆️ **Level 1-60** progression with mastery tiers

### World & Exploration
- 🌍 **Persistent world** — spherical planet architecture (20 km globe, clipmap terrain)
- 🗺️ **Procedural generation** — terrain, prop scatter, and resource placement in code; dungeons planned
- 🌅 **Day/night cycle** with dynamic world events
- 🌲 **Multiple biomes** — forest, plains, mountains, desert, swamp, and more
- ⚔️ **Dungeons, world bosses, and dynamic encounters** planned

### Economy & Crafting
- 🔨 **Crafting system** with profession tiers (blacksmithing and more planned)
- 🏠 **Player housing** — claim land and build your home
- 🏰 **Guild halls** planned; territory ownership is shipped, player-run guild wars still planned
- ⛏️ **Resource gathering** and player trading
- 💰 **Player-driven market** — no auction house bot, prices set by players

### Social & Community
- ⚔️ **Guilds** with ranks, permissions, and alliance support
- 👥 **Party and raid** systems with configurable loot rules
- 👫 **Friends list** with ignore and block features
- 🗳️ **Community governance** — player voting and moderator progression
- 💬 **Chat channels** with range-based delivery

### PvP Systems
- 🗺️ **5 zone PvP modes** (Safe, Species, Faction, Free, Warzone)
- 💀 **Full loot** in PvP zones — drop your gear on death
- 🏟️ **Arena combat** with organized rulesets
- 🎖️ **Faction reputation** and progression

---

## The Technology

### Built With Godot 4.7.2

- **Open source** (MIT license) — fork it, mod it, extend it
- **Browser export** via HTML5/wasm
- **Cross-platform** — Android, iOS, Windows, macOS, Linux
- **GDScript** — clean, readable game logic

### Architecture Highlights

- **Authoritative server** — anti-cheat, fair gameplay
- **Content-hash state tree** — deterministic sync across clients
- **Multi-iso orchestrator** — efficient spatial queries at scale
- **90+ service modules** — clean separation of game systems
- **Entity-component architecture** — flexible, data-driven design

### The Reusable Frame

Beyond the game, Synmergia ships a **reusable MMORPG frame** — the architecture is extractable to its own project:

- T3 content-hash state tree for deterministic game state
- Multi-dimensional query system (spatial × faction × temporal)
- Player-centred clipmap LOD rings with a prop-prefetch predictor
- Scope engine for hierarchical world management

---

## Getting Started

### Play Now (When Available)

Synmergia will launch as a **free-to-play browser MMORPG**. Create your account, choose your species and class, and enter the world.

### For Developers

```bash
# Clone the repository
git clone https://github.com/dhaupin/synmergia.git
cd synmergia

# Install the dev toolchain (Godot 4.7.2, Node 20, bun, system libs).
# Add --with-templates / --with-blender / --with-web-probe as needed.
sh ./scripts/setup-dev.sh

# Open in Godot 4.7.2
godot --editor game/

# Or run a headless server
godot --headless --server --path game/

# Run the tests -- one runner, concurrent when it helps, serial when faster
sh ./scripts/godot_test_runner.sh            # default regression set
sh ./scripts/godot_test_runner.sh --all      # every test_*.gd, parallel
```

See [AGENTS.md](./AGENTS.md) for developer conventions and code patterns,
and [DEVCODE.md](./DEVCODE.md) for the mechanics of running things.

### Contributing

Synmergia is built in the open and contributions are welcome — engine,
art, world building, testing, or just a good idea. Start with
[CONTRIBUTING.md](./CONTRIBUTING.md) for setup, conventions, and the pull
request process. Everyone participating agrees to the
[Code of Conduct](./CODE_OF_CONDUCT.md). Report security issues privately
per [SECURITY.md](./SECURITY.md).

---

## Project Status

**Current Phase:** Pre-vertical-slice (World Building Phase 1 Complete)

### Implemented (In Code)
- **World Building Substrate & Canonical Trees (Phase 1)**: T3 Merkle-Patricia trie, HMAC recursive seed derivation (`SeedChain`), discrete spatial geometry (NSC-9 & icosahedral), and deterministic state trees
- **Frame Authority & Seed Services**: `FrameService` execution isolation (D030), `ShardParameters` immediate/coalesced storage (D033), and `OpenSeedRegistry` 5-minute reconnect TTL (D032)
- **Disaster Recovery**: 3-tier `WorldManifest` backup pipeline with SHA-256 integrity verification (D031)
- **Pluggable Storage Adapters**: Multi-backend persistence layer (`DictStore`, `CacheWrapper`, `MemoryWrapper`, `AdapterRegistry`) across 35+ services
- **Combat & Entity Systems**: Combat math, entity-component system, buff/aura framework with 11 dispel categories
- **Notification Pipeline**: Typed `NotifKind` pipeline (toast, combat log, admin alerts)
- **UI Islands & Web Portal**: 19/19 UI tests passing; COOP/COEP web client packaging and administrative portal
- **Core Social & Account Systems**: Login, account, and character creation flow (21/21 tests); party, guild, friends, trading, factions
- **Security**: Anti-cheat, rate limiting, and application firewall

### In Development (Phase 2)
- Multi-scope Rules Engine (`rules_engine.gd`, `rules_schema.gd`)
- Canonical Definition Tree (`definition_tree.gd`)
- Full action combat integration (hybrid tab/aim targeting)
- World content, procedural cells, and client optimization

---

## Documentation

| | |
|---|---|
| [📄 Product Spec](./labs/prd.md) | Full design document — gameplay, systems, architecture |
| [🏗️ Architecture](./labs/world-building-arch.md) | Technical deep-dive — frame, services, sync |
| [🗺️ World Design](./labs/world-building.md) | World, zones, procedural generation |
| [🤖 Developer Notes](./AGENTS.md) | Code conventions, patterns, and tips for contributors |
| [🛠️ Contributing](./CONTRIBUTING.md) | Setup, conventions, tests, and the pull request process |
| [🧰 Dev Environment](./DEVCODE.md) | Rebuilding the dev loop from the repo alone |
| [🚀 Deployment Guide](./DEPLOY.md) | Docker deployment, production setup, and operations |
| [🌐 Web Deployment](./DEPLOY_WEB.md) | Website + browser client deployment (Cloudflare) |
| [🧩 Shard Mesh](./labs/prd-shard-mesh.md) | Multi-container deployment: intent vs reality, transport fork, phased path |
| [📜 Credits](./CREDITS.md) | Third-party software, fonts, and asset provenance |
| [🔒 Security Policy](./SECURITY.md) | How to report a vulnerability |
| [🤝 Code of Conduct](./CODE_OF_CONDUCT.md) | Community standards |
| [✅ Open Source Audit](./labs/OSS-AUDIT.md) | Launch audit + post-public hardening checklist |

---

## License

Synmergia is open source under the **MIT License** — see [LICENSE](./LICENSE).
Copyright © 2026 [Creadev.org](https://creadev.org).

- **Code and content** (game, website, data, generated art and audio) are
  MIT-licensed.
- **Third-party** software, fonts, and assets are credited in
  [CREDITS.md](./CREDITS.md) with their own licenses (Godot Engine — MIT;
  Cinzel and Plus Jakarta Sans — SIL OFL 1.1).
- **The Synmergia name and logo** are not covered by the code license; see
  [TRADEMARK.md](./TRADEMARK.md).

---

*Synmergia — Shape the world. Forge your legacy. Play anywhere.*

