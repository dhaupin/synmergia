# Synmergia

**A 3D open-world MMORPG that runs in your browser.**

*Browser-first action combat meets the deepest player-driven economy since Ultima Online.*

```
    ╔═══════════════════════════════════════════════════════════╗
    ║  ⚔️  Browser MMORPG  •  RYL2 Combat  •  UO Economy  ⚔️  ║
    ╚═══════════════════════════════════════════════════════════╝
```

No downloads. No installs. Fight, craft, build, and conquer — from any device with a browser.

## Why Synmergia?

**🎮 Combat That Respects Your Skill**
- Free-form action combat (no tab-target lock)
- Dodge, parry, interrupt, and chain skills mid-combat
- Positioning and timing matter more than gearscore

**🏪 Economy That Players Own**
- No auction house bot — prices are set by supply and demand
- Resources spawn in the world; you gather and craft everything
- Player housing dots the landscape, guilds control territories

**⚔️ PvP With Real Stakes**
- Full loot in designated zones
- Guild wars shape server politics
- Death has consequence

**🌐 Play Anywhere**
- Browser-first via Godot HTML5/wasm
- Touch controls for mobile, keyboard/mouse for desktop
- Same experience across all devices

**🤖 AI Agents Welcome**
- Connect AI agents (Claude, GPT, Vant) to play alongside humans
- MCP protocol support for standard AI interfaces
- Agents see the same game state humans do

---

## Quick Links

| 📄 [Product Spec](./labs/prd.md) | Full design document |
|-----------------------------------|---------------------|
| 🏗️ [Architecture](./labs/world-building-arch.md) | Technical deep-dive |
| 🗺️ [ROADMAP](./ROADMAP.md) | Implementation progress |
| 🤖 [AGENTS.md](./AGENTS.md) | Developer notes for AI agents |

---

## Tech Stack

| | |
|---|---|
| **Engine** | Godot 4.7.2 (MIT) |
| **Language** | GDScript |
| **Platforms** | Browser (HTML5/wasm), Android, iOS, PC |
| **Architecture** | Authoritative server + Multi-iso orchestrator + Content-hash state tree |
| **Persistence** | Postgres (snapshots) + Redis (intersection cache) |

---

## Key Features

### Core Gameplay
- ✅ 30+ services (combat, trading, crafting, guilds, factions)
- ✅ Buff/debuff system with dispel rules (8 categories)
- ✅ Entity-component architecture for flexible entity composition
- ✅ Data-driven design — drop `.tres` files to add content

### Social Systems
- ✅ Friends, party, guilds with ranks and permissions
- ✅ Item trading with safety confirmations
- ✅ Community governance (player voting, moderator progression)
- ✅ Full loot PvP with configurable zone modes

### UI Islands
- ✅ Each UI panel is a standalone `PackedScene`
- ✅ Mounted dynamically by `IslandManager`
- ✅ Unified tooltip/toast notification pipeline

### AI Agent Support
- ✅ MCP (Model Context Protocol) connector
- ✅ Vant framework integration
- ✅ Structured observation/action space for agent decision-making

---

## Getting Started

```bash
# Clone the repo
git clone https://github.com/dhaupin/synmergia.git
cd synmergia

# Open in Godot 4.7.2
godot --editor game/

# Or run headless server
godot --headless --server --path game/
```

See [AGENTS.md](./AGENTS.md) for developer conventions and code patterns.

---

## The Frame

Beyond the game, Synmergia is building a **reusable MMORPG frame** — extractable to its own project.

The frame includes:
- **T3 content-hash state tree** — Server tick = re-rooting. Client sync = diff.
- **Multi-iso orchestrator** — Query across spatial × faction × temporal axes at O(1)
- **Scope engine** — Hierarchy walker for world→shard→instance→player scoping
- **LOD pyramid + predictive prefetch** — Markov over player transitions

See [`labs/prd.md`](./labs/prd.md#12-technical-architecture) and [`labs/world-building-arch.md`](./labs/world-building-arch.md) for the full architecture.

---

## Testing

```bash
./tools/godot --headless --path synmergia --script res://tests/test_notification_toast.gd
./tools/godot --headless --path synmergia --script res://tests/test_login_flow.gd
```

**47/47 smoke tests green** (notification pipeline, HUD integration, login flow, auto-response signals)

---

## Status

**Phase:** Pre-vertical-slice

Core systems implemented:
- Combat math and entity components
- Buff/aura system with 7 dispel categories
- Notification → toast pipeline (QoS, security, firewall, auto-response)
- UI Islands architecture (19/19 tests)
- Login/account/character flow (21/21 tests)

In progress:
- Action combat implementation (tab-target hybrid)
- World content and procedural generation
- Full social systems integration

---

## License

MIT — See [LICENSE](LICENSE)

