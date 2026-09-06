# Synmergia

**A 3D open-world MMORPG that runs in your browser.**

*Browser-first action combat meets the deepest player-driven economy since Ultima Online. No downloads. No installs. Just play.*

```
    ╔═══════════════════════════════════════════════════════════════╗
    ║   ⚔️  Browser MMORPG  •  Open World  •  Action Combat   ⚔️ ║
    ║      RYL2-Style Combat  •  UO Economy  •  Guild Territory     ║
    ╚═══════════════════════════════════════════════════════════════╝
```

## What Is Synmergia?

Synmergia is an **open-world multiplayer RPG** built for the browser. Step into a persistent world where your choices shape the economy, your guild controls territory, and every battle matters. Whether you're gathering resources to craft legendary gear, building your dream house on the frontier, or leading your faction into heated guild wars — this is your world.

No other browser-based MMORPG offers this combination of deep action combat, player-driven sandbox economy, and true open-world freedom.

---

## Why Players Love Synmergia

### 🎮 Combat That Respects Your Skill

This isn't a auto-attack-and-wait game. Synmergia features **free-form action combat** inspired by classics like Risk Your Life 2. Every fight is a dance of positioning, timing, and decision-making:

- **Dodge, parry, interrupt, and chain skills mid-combat**
- **Positioning matters** — flanking, terrain advantage, line-of-sight
- **Skill combos** — certain sequences trigger bonus effects
- **No tab-target lock** — aim and strike where you choose
- **Meaningful death** — lose your gear in PvP zones, respawn with strategy

### 🏪 Economy That Players Own

Forget auction house bots and NPC vendors setting prices. In Synmergia, **the economy is built by players, for players**:

- **Resources spawn in the world** — mines, forests, fishing spots scattered across continents
- **Craft everything** — blacksmithing, alchemy, tailoring, and more
- **Player housing** — claim land, build your home, watch it persist
- **Guild territories** — control resource nodes and levy taxes
- **Legendary gear comes from players and world bosses** — not loot boxes

This is the sandbox economy you remember from Ultima Online, rebuilt for a modern audience.

### ⚔️ PvP With Real Stakes

Risk and reward in constant tension. Synmergia offers **configurable PvP across zones**:

- **Full loot in PvP zones** — drop everything on death, fight for glory and gear
- **Guild wars** — political alliances, territory control, server-shaping conflicts
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
- ✅ 18 player classes across 6 archetypes (Tank, DPS, Mage, Rogue, Bender, Healer)
- ✅ 3 species with unique abilities (Akkan, Human, Synthetic)
- ✅ Skill academy with upgradeable abilities and signature skills
- ✅ Buff/debuff system with 11 dispel categories (magic, curse, poison, etc.)
- ✅ Level 1-60 with 3 mastery tiers

### World & Exploration
- ✅ Spherical planet world (20km radius for v1)
- ✅ Procedural terrain and dungeon generation
- ✅ Day/night cycle and dynamic world events
- ✅ Multiple biome types (forest, plains, mountains, desert, swamp)
- ✅ Dungeons, world bosses, and dynamic encounters

### Economy & Crafting
- ✅ Full crafting system with profession tiers
- ✅ Player housing with persistence
- ✅ Guild halls and territory control
- ✅ Resource gathering and trading
- ✅ Player-driven market economics

### Social & Community
- ✅ Guilds with ranks, permissions, and alliances
- ✅ Party and raid systems with loot rules
- ✅ Friends, ignore lists, and block features
- ✅ Community voting and moderator progression
- ✅ In-game mail and chat channels

### PvP Systems
- ✅ 5 zone PvP modes (Safe, Species, Faction, Free, Warzone)
- ✅ Full loot and partial loot options
- ✅ Guild war declarations
- ✅ Arena and battlegrounds
- ✅ Faction reputation and progression

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
- **30+ services** — clean separation of game systems
- **Entity-component architecture** — flexible, data-driven design

### The Reusable Frame

Beyond the game, Synmergia ships a **reusable MMORPG frame** — the architecture is extractable to its own project:

- T3 content-hash state tree for deterministic game state
- Multi-dimensional query system (spatial × faction × temporal)
- LOD pyramid with predictive prefetch
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

# Open in Godot 4.7.2
godot --editor game/

# Or run a headless server
godot --headless --server --path game/
```

See [AGENTS.md](./AGENTS.md) for developer conventions and code patterns.

---

## Project Status

**Current Phase:** Pre-vertical-slice

### Implemented
- Combat math and entity-component system
- Buff/aura framework with 11 dispel categories
- Notification pipeline (toast, combat log, admin alerts)
- UI Islands architecture (19/19 tests passing)
- Login, account, and character creation flow (21/21 tests)
- Core social systems (party, guild, friends, trading)
- Faction and reputation system
- Anti-cheat and security services

### In Development
- Full action combat implementation (hybrid tab/aim targeting)
- World content and procedural generation
- Browser client optimization
- Social system integration and testing

---

## Documentation

| | |
|---|---|
| [📄 Product Spec](./labs/prd.md) | Full design document — gameplay, systems, architecture |
| [🏗️ Architecture](./labs/world-building-arch.md) | Technical deep-dive — frame, services, sync |
| [🗺️ World Design](./labs/world-building.md) | World, zones, procedural generation |
| [📋 ROADMAP](./ROADMAP.md) | Implementation tracker with file-level progress |
| [🤖 Developer Notes](./AGENTS.md) | Code conventions, patterns, and tips for contributors |

---

## License

Synmergia is open source under the **MIT License**. See [LICENSE](LICENSE) for details.

---

*Synmergia — Shape the world. Forge your legacy. Play anywhere.*

