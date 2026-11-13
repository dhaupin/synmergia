# Synmergia — Web Client, Portal & Admin PRD

> **Status:** Draft — 2026-09-14  
> **Target Engine:** Godot 4.7.2  
> **Author:** Web Architecture Team  
> **Purpose:** Master specification for the web delivery architecture, Godot Web/WASM runtime, CI/CD resource conservation strategy, and Web Admin Portal.

---

## 1. Executive Summary & Goals

Synmergia requires a multi-tiered web presence:
1. **Official Engine Web Client (`/web`):** The full Godot 4.7.2 client compiled to WebAssembly (WASM) and WebGL2, connecting to the authoritative server over WebSockets.
2. **Web Portal & Admin Dashboard:** An operations control hub for server shard monitoring, database persistence verification (per `labs/prd-db.md`), security firewall inspection, and GM/moderator tools.
3. **Instant Browser Companion (2D Canvas):** A zero-download, lightweight interactive 2D client for quick web previews, status checks, and instant gameplay testing without heavy WASM initialization.
4. **Zero-Waste CI/CD Economy:** A strict build and packaging pipeline designed to minimize GitHub Actions minutes on the free tier (avoiding full Godot headless compilation on routine git commits).

---

## 2. System Architecture

```
                                  +----------------------------------------------------+
                                  |           Synmergia Web Portal (Port 3000)         |
                                  |                (React + Vite + Tailwind)           |
                                  +---------+--------------------+---------------------+
                                            |                    |
                 +--------------------------+                    +---------------------+
                 |                                                                     |
                 v                                                                     v
+------------------------------------+                               +------------------------------------+
|       Official Godot WASM          |                               |        Admin & Operations Hub      |
|           (`/web`)                 |                               |                                    |
| - Engine Runtime: game.wasm        |                               | - Shard Concurrency & Health       |
| - Engine JS:      game.js          |                               | - DB Adapters & Migration Verifier |
| - Game Package:   game.pck         |                               | - QoS, Firewall & Ban Logs         |
| - WebInputBridge: shared/input.js  |                               | - GM Slash Commands & Broadcasts   |
+-----------------+------------------+                               +-----------------+------------------+
                  |                                                                    |
                  | WebSocket (Authoritative Protocol)                                 | REST / Webhook
                  v                                                                    v
+---------------------------------------------------------------------------------------------------------+
|                               Synmergia Authoritative Server / Multi-Iso Orchestrator                  |
|                        (Godot 4.7.2 headless / `game/` + Adapter Layer `game/adapters/`)                |
+---------------------------------------------------------------------------------------------------------+
```

---

## 3. WASM Build Economy (Free-Tier CI Strategy)

### 3.1 The Problem
Building the full Godot Web export in GitHub Actions requires:
- Downloading Godot 4.7.2 engine binaries and standard Web export templates (~800 MB).
- Compiling/exporting assets and linking WASM.
- **Cost:** 4–8 minutes per build. At 20–40 commits per day across multiple developers or autonomous agents, free-tier limits (2,000 mins/month) are depleted within days.

### 3.2 The Solution: Strategy 2 (Engine Binary vs. Game Logic Separation)

Godot Web exports consist of two distinct layers:

| Component | Files | Frequency of Change | Size | Packaging Mechanism |
|-----------|-------|---------------------|------|---------------------|
| **Engine Runtime** | `game.wasm`, `game.js` | Rare (only upon Godot 4.7.2 patch updates) | ~25 MB | Exported **once** locally or via release tags. Committed or cached in `/web`. |
| **Game Logic & Assets** | `game.pck` | High (code, scenes, resources) | ~5–15 MB | Packaged using fast PCK pack tool (`< 5 seconds`, zero engine compilation). |

### 3.3 CI Execution Rules
1. **Never run Godot WASM builds on routine push commits.**
2. **PCK-Only Workflow:** For CI testing or staging updates, only package `game.pck` using `godot --headless --export-pack "Web" web/game.pck`.
3. **Manual Trigger (`workflow_dispatch`):** Full export workflows run only when explicitly triggered by developers via GitHub UI.
4. **Release Tag Trigger:** Full exports compile automatically only when a release tag (e.g. `v0.*`, `v1.*`) is pushed.
5. **Path Filtering:** Web workflows must ignore changes that only touch `labs/`, `*.md`, or non-game files.

### 3.4 Git Configuration (`.gitignore`)
Allow version-controlled tracking of the web artifacts in `/web`:
```gitignore
# General Godot export files ignored globally
*.pck
*.wasm

# Whitelist web deployment artifacts
!web/*.pck
!web/*.wasm
!web/*.js
```

---

## 4. Directory & File Organization

```
synmergia/
├── web/                           # Official Godot WASM Runtime & Static Web Assets
│   ├── index.html                 # Godot Engine HTML5 loader & WebGL2 canvas
│   ├── game.js                    # Godot 4.7.2 Web Engine launcher (built once)
│   ├── game.wasm                  # Godot 4.7.2 WebAssembly binary (built once)
│   ├── game.pck                   # Packaged game data (scenes, scripts, assets)
│   ├── config.js                  # Dynamic server endpoint configuration
│   ├── worker.js                  # Cloudflare Workers / Edge proxy
│   ├── wrangler.toml              # Cloudflare configuration
│   └── shared/
│       └── input.js               # WebInputBridge: Int32Array bridge for mouse/touch
│
├── src/                           # Unified Web Portal & Admin UI (React + Vite)
│   ├── components/                # Modular UI components
│   │   ├── admin/                 # Shard monitor, persistence explorer, QoS logs
│   │   ├── wasm/                  # Godot WASM iframe/embed wrapper & loader
│   │   ├── game/                  # 2D Companion Canvas view
│   │   └── common/                # Navigation, status badges, modals
│   ├── gameData.ts                # TypeScript mirrors of species, classes, zones
│   └── types.ts                   # Core interfaces
│
├── game/
│   └── export_presets.tres        # Preset for "Web": export_path="../web/game.pck"
│
└── labs/
    ├── prd-web.md                 # This document
    ├── prd-db.md                  # Database & persistence specification
    └── TASKS.md                   # Operational task log
```

---

## 5. Web Portal & Admin Dashboard Specifications

The Web Portal provides an operational management interface integrated with Synmergia’s core services (documented in `AGENTS.md` and `labs/prd-db.md`).

### 5.1 Shard & Zone Concurrency Monitor
- **Real-Time Heartbeat:** Concurrency per shard, tick latency, tick duration, memory utilization.
- **Zone Map:** Live player distributions across zones:
  - `zone_village_center` (Haven)
  - `zone_starter_plains` (Meadowhaven)
  - `zone_forest_meadow` (Gloamwood Meadow)
  - `zone_sundered_sea` (Sundered Sea)
- **Zone Rules:** Visual status of safe zones, contested zones, and full PvP flags (`FactionManager`).

### 5.2 Database & Persistence Inspector (`labs/prd-db.md` Integration)
- **Adapter State:** Status of active storage adapters (`PostgresStore`, `RedisStore`, `DictStore`, `MemoryStore`).
- **Migration Status:** Verification of applied Flyway/Postgres migration scripts (`V20260907_001__init_accounts.sql`, `V20260909_001__init_kv.sql`).
- **Account & Character Lookup:** Search accounts, inspect character rosters, verify inventory arrays and vault slots.

### 5.3 Security, QoS & Firewall Console
- **`QoSService` Monitor:** Rate-limiting infractions, packet flood warnings, and client ping distributions.
- **`AppFirewall` Audit:** Tool-call recursion guards, depth violations (max depth 16), and execution limits.
- **`AntiCheatService` & `SecurityService`:** Suspicion scoring, active player mutes, temporary suspensions, and hardware/token bans.
- **`CommunityGovernance`:** Active voting proposals, moderator action log.

### 5.4 GM Command & Live Operations Console
- **Broadcast System:** Server-wide announcements, maintenance notices.
- **Player Utilities:** `/unstuck`, teleport to zone, inspect inventory, grant items/currency for testing.
- **Loot Table Simulator:** Test drop rates and item roll math against configured loot tables (`LootService`).

---

## 6. Data & Protocol Bridges (`game/data/` Single Source of Truth)

To ensure the 2D Companion client and the Godot WASM client stay mathematically and mechanically consistent, `game/data/` serves as the sole canonical source of truth for game definitions.

### 6.1 Static Data Bridge (`.tres` → TypeScript JSON)
Godot 4 stores game data as text-based `.tres` resources. A build-time bridge extracts and types this data for web consumption.

```
game/data/ (Canonical .tres)
  ├── classes/          # Class stats, starter attributes, primary resource
  ├── species/          # Species base modifiers and descriptions
  ├── skills/           # Base damage, mana costs, cooldowns, scaling formulas
  ├── weapons/          # Attack damage, attack speed, durability, item tier
  ├── armors/           # Armor rating, resistances, slot type (head/chest/legs)
  ├── consumables/      # Health/mana recovery values, buff durations
  ├── enemies/          # HP, attack power, defense, XP reward, aggro radius
  └── zones/            # Zone bounds, safe/contested PvP rules, spawn lists
           │
           │  npm run sync:data (`scripts/sync_godot_data.ts`)
           v
src/data/godot_data.json (Generated typed payload)
           │
           v
src/gameData.ts (Used by 2D Companion Client & Admin Simulator)
```

#### npm Pipeline Integration
Add the following commands to `package.json`:
- `"sync:data": "tsx scripts/sync_godot_data.ts"`: Scans `game/data/**/*.tres`, parses resource fields into JSON, and updates `src/data/godot_data.json`.
- `"build:web": "npm run sync:data && vite build"`: Ensures every web deployment automatically inherits the latest Godot balance tweaks and item additions.

### 6.2 Network & State Protocol Bridge
The 2D web client connects to the authoritative multi-iso orchestrator / server via WebSocket using the identical packet structure handled by `NetworkManager` and `EventHub`:
- **Opcode 0x01 (Handshake):** Authenticate session token (`AccountService` / `LoginService`).
- **Opcode 0x02 (Player Movement):** Peer position vector updates `(x, y, zone_id, velocity)`.
- **Opcode 0x03 (Combat Cast):** Skill invocation `(skill_id, target_entity_id)` resolved authoritatively by `CombatSystem.gd`.
- **Opcode 0x04 (Chat & Broadcast):** Channel messages (Global, System, Combat, Local).
- **Opcode 0x05 (Entity State Sync):** Spawn, despawn, HP change, and buff/debuff ticks.

### 6.3 Godot 4 WASM Runtime & Header Requirements
Godot 4.7.2's WebAssembly export relies on multi-threading (Web Workers) and `SharedArrayBuffer`. Browsers enforce strict Cross-Origin Isolation headers for this to execute without throwing security exceptions:
```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```
- **Vite Dev Server:** Configured via `server.headers` in `vite.config.ts`.
- **Cloudflare / Production:** Configured in `web/wrangler.toml` or `nginx.conf`.
- **Embedded Wrapper (`src/components/wasm/GodotCanvas.tsx`):** Renders the WebGL2 canvas with responsive fullscreen toggles, dynamic loading progress bar tracking `game.pck` fetch status, and WebInputBridge initialization.

---

## 7. Implementation Roadmap

### Phase 1: Portal Framework & Dual-Client Host (P0)
- [ ] Configure `.gitignore` whitelist for `web/*.pck` and `web/*.wasm`.
- [ ] Configure Cross-Origin Isolation headers (`COOP`/`COEP`) in `vite.config.ts`.
- [ ] Build Portal navigation shell switching between:
  - Official Godot Web Client (`/web`)
  - 2D Canvas Companion
  - Admin & Operations Dashboard
- [ ] Set up local PCK export script (`scripts/pack_web.sh` or Python helper) for zero-CI local updates.

### Phase 2: Data Bridge & Admin Dashboard (P1)
- [ ] Implement `scripts/sync_godot_data.ts` and add `npm run sync:data`.
- [ ] Hook 2D client state directly to `src/data/godot_data.json`.
- [ ] Implement Shard & Concurrency monitor view.
- [ ] Implement DB Adapter & Account Inspector (mockable/connectable to backend APIs per `labs/prd-db.md`).
- [ ] Implement QoS, Firewall, and Security audit logs viewer.
- [ ] Implement GM command panel (broadcast, kick, inspect).

### Phase 3: CI/CD Pipeline Optimization (P2)
- [ ] Create GitHub Actions workflow with `workflow_dispatch` and `paths` filtering for automated `.pck` packaging.
- [ ] Configure artifact uploads for release builds.
- [ ] Document developer export guide in `DEPLOY.md`.

---

## 8. Change Log

| Date | Author | Summary |
|------|--------|---------|
| 2026-09-14 | Web Architecture Team | Initial creation of PRD. Outlined Strategy 2 for zero-waste CI, directory structure, and Admin Dashboard specifications. |
| 2026-09-14 | Web Architecture Team | Added Section 6: Data & Protocol Bridges (`.tres` parser, `npm run sync:data`, WebSocket opcode parity, and COOP/COEP isolation headers for Godot 4 WASM). |

