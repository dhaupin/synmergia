# Synmergia — Open World MMORPG

> **Status (2026-09-16):** This PRD is the product spec.
> Technical architecture details are in `/labs/` (source of truth):
> `world-building.md` (full stack design), `world-building-arch.md`
> (systems architecture), `world-building-tick.md` (tick model),
> `world-building-risks.md` (risks), and the PRD specs (`prd-*.md`).
> The frame (T3 substrate + scope engine + rules engine) is
> documented in `world-building-arch.md` and the PRD specs.
> This document lives in `labs/` because the architecture is
> experimental; the game itself is in `game/`.

> **Vision:** A 3D open-world MMORPG inspired by Risk Your Life 2
> (RYL2) combat/action mechanics, infused with the depth and
> player-driven economy of Ultima Online. Built on a reusable **frame**
> (T3 content-hash substrate + scope engine + rules engine) that
> can be extracted to its own project — see the Frame appendix.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Core Game Pillars](#2-core-game-pillars)
3. [Combat Systems](#3-combat-systems)
4. [World & Exploration](#4-world--exploration)
5. [UI Systems Overview](#5-ui-systems-overview)
6. [Player Systems](#6-player-systems)
7. [Economy & Crafting](#7-economy--crafting)
8. [Player Housing](#8-player-housing)
9. [PvP Systems](#9-pvp-systems)
10. [Social & Guild Systems](#10-social--guild-systems)
11. [Account & Server Systems](#11-account--server-systems)
12. [Technical Architecture](#12-technical-architecture)
13. [Data Schemas](#13-data-schemas)
14. [Art & Audio Direction](#14-art--audio-direction)
15. [Platform Support & Optimization](#15-platform-support--optimization)
16. [Phases & Milestones](#16-phases--milestones)
17. [Open Questions](#17-open-questions)
18. [Geometry Layer: NSC-9 + Spatial Fragmenter](#18-geometry-layer-nsc9--spatial-fragmenter)

## Architecture documentation

This PRD is the product spec. The technical architecture is in
`/labs/` (source of truth):

**Deployment & Operations:**
- [`DEPLOY.md`](../DEPLOY.md) — Docker deployment, production setup, and operations

**World-building docs** (world + network + persistence design):
- [`world-building.md`](./world-building.md) — full stack design
- [`world-building-arch.md`](./world-building-arch.md) — systems architecture
- [`world-building-tick.md`](./world-building-tick.md) — server tick model
- [`world-building-risks.md`](./world-building-risks.md) — risks and mitigations
- [`world-building-research.md`](./world-building-research.md) — experimental angles

**PRD specs** (Phase 1 deliverables):
- [`prd.md`](./prd.md) — this document
- [`prd-t3-substrate.md`](./prd-t3-substrate.md) — T3 state tree spec
- [`prd-seed-schema.md`](./prd-seed-schema.md) — seed schema
- [`prd-state-schema.md`](./prd-state-schema.md) — state schema
- [`prd-scope-engine.md`](./prd-scope-engine.md) — scope engine
- [`prd-login-seed-chain.md`](./prd-login-seed-chain.md) — login + seed chain
- [`prd-frame-authority.md`](./prd-frame-authority.md) — server authority
- [`prd-critical-params.md`](./prd-critical-params.md) — critical params
- [`prd-open-seed-ttl.md`](./prd-open-seed-ttl.md) — seed TTL
- [`prd-manifest-backup.md`](./prd-manifest-backup.md) — manifest backup
- [`prd-geometry.md`](./prd-geometry.md) — Vant fragmenter / geometric addressing

**Frame primitives** (in `../game/core/frame/`, consolidated from legacy multi-iso):
- [`math/`](../game/core/frame/math/) — NSC-9, icosahedral
- [`kv/`](../game/core/frame/kv/) — T3, LRU, state tree, seed chain, definition tree
- [`srv/`](../game/core/frame/srv/) — RulesEngine, ScopeEngine, Markov, LOD, Axis
- [`db/`](../game/core/frame/db/) — snapshot_store

**Experimental** (in `/labs/`, kept for reference):
- [`polyglot-ffi/`](./polyglot-ffi/) — FFI exploration
- [`jolt-playground/`](./jolt-playground/) — Jolt physics experiments

**Archived** (outdated, in `/labs/archive/`):
- `/labs/archive/docs/architecture/` — previous architecture docs (may be stale)

---

## 1. Executive Summary

**Synmergia** is a 3D open-world MMORPG starting browser-first
(HTML5/wasm) with planned mobile (Android/iOS) and desktop
(Windows, macOS, Linux) support. The game combines RYL2's
fast-paced, free-form action combat with Ultima Online's depth
of player-driven economy, housing, and world interaction.

**Core Loop:** Explore vast world → Fight enemies/dungeons →
Craft gear → Build houses → Participate in PvP → Repeat

**Target Audience:**
- MMORPG players who miss the depth of UO/EVE-era games
- Players who want browser-based gaming without installs
- Players who enjoy crafting, housing, and player economies
  over theme-park content

**Competitive Landscape:**
- Similar to: RYL2 (combat feel), UO (economy/housing), Black
  Desert (action combat), Albion Online (full loot PvP)
- Differentiator: Browser-first (HTML5/wasm) with full MMO
  depth, not a stripped-down mobile port. Plus: a **reusable
  game frame** (T3 content-hash substrate + scope engine + rules
  engine) that could be extracted to its own project, so other
  games can be built on the same architecture.

**Development Approach:**
- Agent-assisted development using LLMs for code generation
- Incremental feature delivery with continuous integration
- Godot 4.7.2 for cross-platform deployment (browser-first, then mobile/desktop)
- See the [Frame appendix](#frame-appendix) and
  [`world-building-arch.md`](./world-building-arch.md) for the
  full architecture and development phases.

---

## 2. Core Game Pillars

The 3-5 foundational principles that define the game experience:

### 1. Free-Form Action Combat ⚔️
Combat is not turn-based or tab-target locked. Players move, jump, dodge, and attack freely during combat (RYL2-style). Skills can be used while moving. Positioning matters.

### 2. Player-Driven Economy 🏪
No auction house bot. Resources spawn in the world, players gather and craft. Prices are determined by supply/demand. Legendary items come from players and world bosses, not loot boxes.

### 3. Meaningful World Presence 🌍
Player houses dot the landscape. Guilds control territories. Resources are finite. What you build affects the world. The world persists and changes based on player actions.

### 4. Risk vs Reward PvP ⚔️
PvP zones offer better rewards but carry the risk of losing your gear. Full loot in designated zones. Guild wars shape server politics. Death has consequence.

### 5. Browser-First Deployment 🌐
Client runs in browser via Godot HTML5/wasm. Touch controls designed for action combat, keyboard/mouse on desktop. Optimized for all device tiers.

---

## 3. Combat Systems

> **Implemented:** Combat math, loot distribution, enemy spawning, respawn logic, and
> death features are implemented. Action combat with tab-targeting hybrid is planned.

### 3.1 Movement

| Feature | Description | Priority |
|---------|-------------|----------|
| **3rd Person Camera** | Auto-follow camera behind player, adjustable zoom | ✅ Implemented |
| **Virtual Joystick** | Left side of screen for movement | ✅ Implemented |
| **Jump** | Single jump with animation | ✅ Implemented |
| **Dodge/Roll** | Quick directional evade with i-frames | ✅ Implemented |
| **Sprint** | Hold to run faster, consumes stamina | ✅ Implemented |
| **Swimming** | Move through water, slower than land | P1 |
| **Climbing** | Scale ladders, walls, ledges | P1 |
| **Mounts** | Rideable horses/dragon mounts | P2 |
| **Flight** | Unlockable flying mounts for endgame zones | P2 |

### 3.2 Targeting System

| Feature | Description | Priority |
|---------|-------------|----------|
| **Tab Targeting** | Cycle through nearby enemies with Tab | ✅ Implemented |
| **Soft Targeting** | Hover over enemy to aim ground-targeted spells | ✅ Implemented |
| **Auto-Target Closest** | Option to auto-lock nearest enemy | P1 |
| **Friendly Targeting** | Target allies for buffs/heals (Tab + Shift) | ✅ Implemented |
| **Target Lock** | Hold target even when out of range | P1 |
| **Target Nameplate** | Show enemy name, health bar, level, elite indicator | ✅ Implemented |

### 3.3 Combat Actions

| Feature | Description | Priority |
|---------|-------------|----------|
| **Auto-Attack** | Basic melee/ranged attack on loop when engaged | ✅ Implemented |
| **Skill Hotbar** | 8-12 slot hotbar (skills 1-0, Shift+1-0) | ✅ Implemented |
| **Skill Queuing** | Queue next skill while current one animates | ✅ Implemented |
| **Skill Combos** | Certain skill sequences trigger bonus effects | P1 |
| **Interrupt** | Stun/knockback can interrupt channeled skills | ✅ Implemented |
| **Dodge Mechanics** | I-frames during dodge roll | ✅ Implemented |
| **Parry/Block** | Timing-based defense with shield | P1 |
| **Counter** | Offensive parry that guarantees crit | P2 |

### 3.4 Stats & Attributes

| Stat | Description | Affected By |
|------|-------------|-------------|
| **Health (HP)** | Hit points, reaches 0 = death | Vitality, equipment, buffs |
| **Mana (MP)** | Resource for casting skills | Intelligence, equipment | 
| **Stamina** | Resource for sprint, dodge, heavy attacks | Endurance |
| **Strength** | Physical damage, carry weight | Melee damage |
| **Agility** | Attack speed, dodge chance, crit | Ranged/melee speed |
| **Intelligence** | Magic damage, mana pool | Spell damage |
| **Vitality** | HP pool, physical defense | Tankiness |
| **Endurance** | Stamina pool, resource regen | Sustain |
| **Wisdom** | Mana regen, buff duration | Caster sustain |

### 3.5 Health & Resource Display

| Feature | Description | Priority |
|---------|-------------|----------|
| **Player HP Bar** | Large bar above character, follows player | ✅ Implemented |
| **Target HP Bar** | Bar below target's nameplate | ✅ Implemented |
| **HP/Mana/Stamina HUD** | Always visible bars (adjustable position) | ✅ Implemented |
| **Damage Numbers** | Float up on hit (crits are larger, different color) | ✅ Implemented |
| **Status Effects** | Icons above player showing buffs/debuffs | ✅ Implemented |
| **Enemy Health Scaling** | Health bar size reflects remaining HP % | P1 |

### 3.6 Death & Resurrection

| Feature | Description | Priority |
|---------|-------------|----------|
| **Death State** | Character falls, ghost mode activates | ✅ Implemented |
| **Respawn Options** | Return to nearest bind point or town | ✅ Implemented |
| **Resurrection by Others** | Party/guild members can rez with cast time | ✅ Implemented |
| **Death Penalty** | XP loss, item degradation, drop chance in PvP zones | ✅ Implemented |
| **Kill Credit** | Proper credit for kills (last hit vs damage dealt) | ✅ Implemented |

### 3.7 Combat Animations & Feedback

| Feature | Description | Priority |
|---------|-------------|----------|
| **Hit Reactions** | Enemies stagger/recoil on hit | ✅ Implemented |
| **Impact Effects** | Particles/sounds on hit connection | ✅ Implemented |
| **Screen Shake** | Subtle shake on heavy hits | P1 |
| **Armor Sounds** | Distinct sounds for different weapon types | ✅ Implemented |
| **Weapon Trails** | Visible trails for sword swings | P1 |
| **Animation Canceling** | (Specific rules TBD - RYL2 had strict cancels) | P1 |

### 3.8 Combat Open Questions

> **DECIDED:** These questions have been answered in development.

- [x] **How does aggro work?** → Proximity-based aggro with configurable detection radius. Enemies detect players within aggro range. Higher level enemies don't aggro much lower level players (20+ level gap). Players 20+ levels higher get minimal XP.

- [x] **PvP combat differences?** → CC reduction in PvP (50% duration), damage modifiers based on gear differential. Open for tuning.

- [ ] Solo vs group damage scaling? → TBD (no decision yet)

- [ ] Level scaling within zones? → TBD (world scaling not planned for initial release)

### 3.9 Buff/Aura System

| Feature | Description | Status |
|---------|-------------|--------|
| **Status Effects** | Unified buff/debuff/DoT/HoT system | Implemented |
| **Effect Categories** | BUFF, DEBUFF, NEUTRAL | Implemented |
| **Effect Types** | STAT_MODIFIER, HEALTH_MODIFIER, IMMUNITY, STEALTH, CONTROL, SPECIAL | Implemented |
| **Control Types** | STUN, ROOT, SNARE, FEAR, SILENCE, KNOCKBACK, INCAPACITATE | Implemented |
| **Stack Behaviors** | NONE (refresh), REFRESH, ADD, REPLACE | Implemented |
| **Tick Behaviors** | INSTANT, DURATION, TICKED, TOGGLE | Implemented |
| **Dispel Rules** | Magic, Curse, Poison, Physical, Holy, Shadow, Fire, Ice, Lightning, Arcane, Bleed | Implemented |

See `core/entities/status_effect.gd`, `core/components/aura_component.gd`, `core/schemas/status_effect_data.gd`.

### 3.10 Combat Components

| Component | File | Description |
|-----------|------|-------------|
| **HealthComponent** | `core/components/health_component.gd` | Health, death, respawn |
| **CombatComponent** | `core/components/combat_component.gd` | Combat state, skills, damage |
| **AuraComponent** | `core/components/aura_component.gd` | Buff/debuff management (32 buff, 16 debuff max) |
| **AggroComponent** | `core/components/aggro_component.gd` | Threat/aggro management |
| **InventoryComponent** | `core/components/inventory_component.gd` | Item storage and equipment |

---

## 4. World & Exploration

> **Spherical planet** — The world is a sphere (planet radius 20km for v1).
> One continent (~150 km²) contains all initial content. The rest is ocean.
> Dungeons and some islands are instances. See [`world-building.md`](./world-building.md) §3.9 for the v1 world spec.

### 4.1 World Structure

**V1 World (Dev/Alpha/Beta) — ✅ Implemented:**

| Feature | Description |
|---------|-------------|
| **Planet** | Spherical, radius 20km, surface ~5,000 km² |
| **Continent** | ~150 km², centered on planet |
| **Capital City** | At geographic center of continent, new players start here |
| **Ocean** | Covers the rest of the planet (future boat/ship mechanics) |
| **Instances** | Dungeons, PvP arena island, capital interior areas |

**V1 Biome Layout** (within ~5km radius of capital):

| Direction | Biome | Content |
|-----------|-------|---------|
| **North** | Forest | Tutorial zone, starter mobs |
| **East** | Plains + Farmland | Starter quests, low-level mobs |
| **South** | Lake + River | Fishing, water mobs |
| **West** | Mountain Ridge | Mining, mid-level mobs |
| **Coastline** | Harbor | Capital harbor district, fishing village, shipwright |

**Near Capital:**
- Dungeon entrance ~3km north (instance portal test)
- PvP arena on small island ~6km offshore (instance portal test)

**Future Scaling:**
| Version | Planet Radius | Landmass |
|---------|--------------|----------|
| v1 (dev) | 20 km | 150 km² |
| v2 (soft launch) | 100 km | ~3,000 km² |
| v3 (full launch) | 1,000+ km | Full planet |

See [`world-building.md`](./world-building.md) §3.9–3.12 for full world architecture.

### 4.2 Terrain Types

| Feature | Description | Priority |
|---------|-------------|----------|
| **Grasslands** | Default outdoor terrain | P0 |
| **Forests** | Dense trees, pathfinding challenges | P0 |
| **Mountains** | Uneven terrain, climbing spots | P0 |
| **Deserts** | Heat damage without preparation | P1 |
| **Swamps** | Slow movement, disease chance | P1 |
| **Snow/Ice** | Slippery surfaces, cold damage | P1 |
| **Urban Areas** | Cities, ruins, player housing districts | P0 |
| **Water** | Rivers, lakes, oceans (swim or boat) | P0 |

### 4.3 Points of Interest

| Feature | Description | Priority |
|---------|-------------|----------|
| **Towns** | Safe zones, vendors, quest hubs | ✅ Implemented |
| **Dungeons** | Instance or open-world dungeon zones | ✅ Implemented |
| **Difficult Spawns** | Elite mobs, world bosses | ✅ Implemented |
| **Resource Nodes** | Ore, herbs, wood spawns | ✅ Implemented |
| **Landmarks** | Visible markers for navigation | ✅ Implemented |
| **Secret Areas** | Hidden zones requiring puzzle/platforming | P1 |
| **Waypoint Portals** | Fast travel nodes (unlock progressively) | P1 |

### 4.4 Procedural Generation

| Feature | Description | Priority |
|---------|-------------|----------|
| **Extended Terrain** | Algorithmically generate outer regions | P1 |
| **Dungeon Layouts** | Procedural dungeon room generation | P1 |
| **Resource Distribution** | Spawn resources in patterns | P1 |
| **Quest Generation** | Simple procedural quests (gather X, kill Y) | P2 |
| **World Events** | Random spawns, world events | P2 |

### 4.5 World Service

| Feature | Description | Status |
|---------|-------------|--------|
| **Day/Night Cycle** | 24-hour game time cycle | Implemented |
| **World Time** | Configurable time multiplier for testing | Implemented |
| **Gateways** | Portal systems for zone transitions | Implemented |
| **World Events** | Scheduled world-wide events | Implemented |
| **Procedural Seeds** | Deterministic world generation | Implemented |

See `core/services/world_service.gd`.

### 4.6 Zone & Instancing Model — ✅ Implemented

> **Full spec:** See [`world-building.md`](./world-building.md) §8 for zone model,
> gateway transitions, and instance lifecycle.

| Concept | Description |
|---------|-------------|
| **Seed** | Top-level container: world, shard, or instance |
| **Region** | Geographic zone within a seed |
| **Gateway** | Portal between regions or into instances |
| **Instance** | Ephemeral per-group content (dungeons, arenas) |
| **Zone Transition** | Player movement through gateways triggers loading |

**Instance types:**
- `open + instance` — Per-group, derived from `(parent_seed, instance_id)`
- `frame + instance` — Computed per-frame (dynamic encounters)
- Regen triggers on `instance_start`; state persisted to seed on `instance_end`

### 4.7 Respawn System

| Respawn Mode | Description | Status |
|--------------|-------------|--------|
| **TIMED** | Standard timed respawn | Implemented |
| **ANKH** | Respawn at bound ankh (respawn point) | Implemented |
| **REVIVE** | Resurrected by another player | Implemented |
| **SELF_REVIVE** | Item/spell self-resurrect | Implemented |
| **ARENA_TEAM** | Arena team respawn | Implemented |
| **CONTESTED** | Fight for respawn control | Implemented |
| **GATEWAY** | Respawn at zone gateway | Implemented |
| **SAFE_ZONE** | Safe area respawn with invincibility | Implemented |

See `core/services/respawn_service.gd` and `core/schemas/ankh.gd`.

---

## 5. UI Systems Overview

> **Pattern:** UI uses an Islands architecture where each panel is a `PackedScene`
> with an `IslandPlaceholder` root, mounted by `IslandManager`. HUD widgets are
> separate `UIWidget` instances for in-world overlays.

### 5.1 Authentication Flow — ✅ Implemented

| Screen | File | Description |
|--------|------|-------------|
| **Login** | `ui/menus/login.gd` | Login/Register/Guest modes. PBKDF2 password hashing, rate limiting. |
| **Lobby** | `ui/menus/lobby.gd` | Per-account character list. Play/Create/Delete/Logout actions. |
| **Character Select** | `ui/menus/character_select.gd` | Species selection → Class selection → Name entry. |

See `core/services/login_service.gd` for auth logic.

### 5.2 Game Menus — ✅ Implemented

| Menu | File | Description |
|------|------|-------------|
| **Main Menu** | `ui/menus/main_menu.gd` | Entry point with Play/Settings/Quit |
| **Character Stats** | `ui/components/character_stats_ui.gd` | Character sheet with stats display |
| **Settings** | `ui/components/settings_panel.gd` | Audio, video, keybinds, accessibility |

### 5.3 HUD Elements — ✅ Implemented

| Element | File | Description |
|---------|------|-------------|
| **Action Bar** | `ui/components/action_bar.gd` | Skill hotbar with cooldowns |
| **Buff Bar** | `ui/components/buff_bar.gd` | Active effects display (8 buff, 8 debuff slots) |
| **Minimap** | `ui/components/minimap.gd` | Zone map with player position |
| **World Map** | `ui/components/world_map.gd` | Full map view |
| **Target Frame** | `ui/components/target_frame.gd` | Selected target display |
| **Boss Health Bar** | `ui/components/boss_health_bar.gd` | Boss encounter UI |
| **Cooldown Indicator** | `ui/components/cooldown_indicator.gd` | Skill cooldown display |
| **Loading UI** | `ui/components/loading_ui.gd` | Loading screens |
| **Combat Log** | `ui/components/combat_log.gd` | Scrolling combat/event feed |
| **Action Menu** | `ui/components/action_menu.gd` | Right-click context menus |
| **Tooltip Manager** | `ui/components/tooltip_manager.gd` | Unified tooltip system |

> **Notification-toast pipeline:** `NotificationService → HudIntegrator → TooltipManager.show_toast()` implemented. Headless test: `test_notification_toast.gd`

### 5.4 Inventory & Equipment — ✅ Implemented

| Panel | File | Description |
|-------|------|-------------|
| **Inventory** | `ui/components/inventory_ui.gd` | Grid-based inventory with item icons |
| **Bank/Vault** | `ui/components/bank_ui.gd` | Shared storage with withdraw/deposit |
| **Trade** | `ui/social/trade_ui.gd` | Player-to-player trading |
| **Shop** | `ui/components/shop_ui.gd` | Vendor buying/selling interface |
| **Blacksmith** | `ui/components/blacksmith_ui.gd` | Item repair and upgrading |

### 5.5 Social Panels — ✅ Implemented

| Panel | File | Description |
|-------|------|-------------|
| **Friends List** | `ui/social/friends_list.gd` | Friends, requests, block/ignore |
| **Guild UI** | `ui/social/guild_ui.gd` | Guild management, ranks, MOTD |
| **Party UI** | `ui/social/party_ui.gd` | Party formation and management |
| **Faction UI** | `ui/social/faction_ui.gd` | Faction reputation display |
| **Achievement UI** | `ui/social/achievement_ui.gd` | Achievement tracking and display |
| **Quest UI** | `ui/components/quest_ui.gd` | Quest tracking and objectives |
| **Dialog UI** | `ui/components/dialog_ui.gd` | NPC conversation rendering |

### 5.6 Admin Tools — ✅ Implemented

| Tool | File | Description |
|------|------|-------------|
| **Admin Dashboard** | `ui/admin/admin_dashboard.gd` | GM panel with commands, player list, terminal |
| **Admin Toolbar** | `ui/admin/admin_toolbar.gd` | Quick admin actions toolbar |
| **Admin Shell** | `core/admin/admin_shell.gd` | Command execution engine |

### 5.7 Debug & Accessibility — ✅ Implemented

| Feature | File | Description |
|---------|------|-------------|
| **Debug Overlay** | `ui/components/debug_overlay.gd` | UI inspection (F11 toggle). Shows game state, hovered elements. |
| **Colorblind Mode** | `settings_panel.gd` | Deuteranopia, Protanopia, Tritanopia support |
| **UI Scaling** | `settings_panel.gd` | Adjustable UI element size |
| **UIStyles** | `ui/components/ui_styles.gd` | Centralized theming (colors, fonts, styles) |

### 5.8 Islands Architecture — ✅ Implemented

| Component | File | Description |
|-----------|------|-------------|
| **Island Manager** | `ui/islands/island_manager.gd` | Mounts/unmounts UI panels dynamically |
| **Island Registry** | `ui/islands/island_registry.gd` | Static registry of available panels |
| **Island Placeholder** | `ui/islands/island_placeholder.gd` | Root node for island scenes |

---

## 6. Player Systems

> **Implemented:** Character creation, species, classes, skill academy.

### 6.1 Species (Races)

Three playable species implemented:

| Species | Description | Stats Focus |
|---------|-------------|-------------|
| **Akkan** | Ancient beings with innate magical affinity | Magic, Wisdom |
| **Human** | Versatile survivors of the eastern plains | Balanced, Vitality |
| **Synthetic** | Constructed beings with technological roots | Agility, Endurance |

See `game/data/species/` for implemented species.

### 6.2 Class System

18 classes across 3 species × 6 archetypes:

| Archetype | Akkan | Human | Synthetic |
|-----------|-------|-------|-----------|
| **Tank** | Bulwark | Guardian | Warden |
| **DD (Damage)** | Attacker | Warrior | Exploiter |
| **Mage** | Rune | Sorcerer | Psion |
| **Rogue** | Stalker | Marksman | Tracker |
| **Bender** | Seer | Temporalist | Overclocker |
| **Healer** | Shaman | Cleric | Conduit |

Plus 3 GM classes (Akkan, Human, Synthetic) with `role = 0`.

**Canon: the Bender teleport.** Benders are the only class family that can
teleport party members — one verb, three voices (the Akkan Seer's spatial fold,
the Human Temporalist's slip, the Synthetic Overclocker's blink). No other class
teleports the party. **Waystones** (see `prd-monetization.md` §20) are the
no-Bender fallback door: slower, charge-bound, mark-scoped — never a replacement
for the class verb.

See `game/data/classes/` for implemented classes.

### 6.3 Skill Academy

Players unlock and upgrade skills via the Skill Academy:

| Feature | Description |
|---------|-------------|
| **Upgradable Skills** | Every non-signature skill of a class is upgradable (exactly 10 per class) |
| **Signature Skills** | 3 non-upgradable abilities per class; unlock 1 at level 10 |
| **Upgrade Tiers** | 5 rungs: common → rare → epic → legendary → mythic |
| **First Signature** | FREE |
| **Subsequent Changes** | 1000 gold |
| **Skill Points** | 30 + (level × 2) points total |
| **Upgrade Cost** | 1 skill point + 4 books of the matching tier |
| **Respec Cost** | 500 gold base + 20 gold per point spent |

#### The upgrade law

- **Tiers.** The ladder is five rungs, `common` → `mythic`, mapped to
  upgrade levels 1-5. It lives in ONE place:
  `core/schemas/game_tier.gd` (`GameTier`) — THE game-wide tier scale.
  Every consumer — `SkillAcademyService`, `DataService`,
  `GroundLootService`, `SkillBook`, `SkillAcademyUI`,
  `CharacterStatsUI`, `Item`, `TitleData`, `AchievementData`,
  `UIStyles` — reads it. Do not re-declare the array.
- **Books.** A book id is `book_<skill_id>_<tier>`. Reaching tier N
  consumes **4 books of tier N** plus **1 skill point**. Books are
  runtime-generated items (`SkillBook.create`), never authored `.tres`;
  `GroundLootService` expands a `book_…` loot id through
  `SkillAcademyService.create_book`.
- **Upgradable gate.** A book exists ONLY for an upgradable skill. A
  signature is `upgradable = false`, so `book_<signature>_<tier>`
  resolves to nothing on both the academy and loot paths.
- **Stat gate.** Each rung carries a stat-total threshold
  (0/30/60/90/120 for common…mythic) in `GameTier.TIER_STAT_THRESHOLD`.
  The gate is **live**: a tier whose skill authors no `min_stat` gates on
  the character's primary focal stat (`focal_stat_1`), so a level-1
  warrior cannot buy a rare upgrade until strength reaches 30. An explicit
  `min_stat` / `min_stat_value` on the tier overrides both.
- **Class kit.** Every class ships **3 signatures** and **exactly 10
  upgradable class skills** (`FLOOR == CAP == 10` in the parity receipt),
  and every upgradable class skill is reachable from that class's own
  `skill_tree_unlocks` / `starting_skills`. The roster is balanced
  class-to-class: no one-button shell, no runaway.
- **Shared verbs.** A band of **5-10 class-agnostic common skills** lives
  in `data/skills/general/` (bind, stun, slow, sprint, regen, shield,
  purge, recover), all `required_class = ""` and upgradable, so every
  species and class has a meaningful baseline kit. Every character's
  skillbar leads with them (`DataService.get_general_skills()` ->
  `PlayerBase._setup_starting_skills`).
- **One engine.** Skills are DATA in `core/schemas/skill.gd`
  (`SkillSchema`, the `.tres` shape) and BEHAVIOUR in
  `core/combat/skill.gd` (`Skill.from_schema` -> `execute`, the single
  live combat path). The one effect vocabulary is the `match` in
  `from_schema`: `damage`, `heal`, `stun`/`root`/`slow`, `buff`/`debuff`,
  `shield`, `damage_over_time`, `hot`, `revive`, `cleanse`. An authored
  type outside that set is a lint-gate miss, never a silent no-op.


#### ONE scale everywhere: tiers ARE rarity

There is a single five-rung scale, `common → mythic`, in
`core/schemas/game_tier.gd` (`GameTier`). It is used by **skill upgrade
tiers, item rarity, titles, and achievements** alike — one vocabulary,
one colour set (grey / blue / purple / orange / red).

History: this used to be three ladders that shared names but disagreed —
the skill ladder was five rungs; `Item.Rarity` was **six** (an extra
`UNCOMMON` wedged between common and rare); titles and achievements were
five but stopped at `legendary`. `UNCOMMON` is retired, and the tier
names are now identical everywhere. The old `Item.Rarity` ints were
migrated on disk (`UNCOMMON` folded into `common`, everything above
shifted down one).

See `core/services/skill_academy_service.gd`, `core/schemas/game_tier.gd`,
and `ui/components/skill_academy_ui.gd`.

### 6.4 Leveling & Progression

| Feature | Description | Status |
|---------|-------------|--------|
| **Experience System** | XP from kills, quests, exploration | Implemented |
| **Skill Academy** | Upgrade skills + select signature | Implemented |
| **Death Penalty** | XP loss, item degradation | Implemented |
| **Respawn Service** | Respawn logic with bind points | Implemented |

### 6.5 Inventory & Equipment

| Feature | Description | Status |
|---------|-------------|--------|
| **Equipment Slots** | Head, Chest, Hands, Legs, Feet, Main Hand, Off Hand, Rings, Neck | Implemented |
| **Inventory Service** | Grid-based inventory management | Implemented |
| **Bank/Vault** | Shared storage at towns | Implemented |
| **Bag System** | Expandable bags with more slots | Implemented |
| **Item Binding** | Bind on pickup, bind on equip | Implemented |
| **Trade Service** | Player-to-player trading | Implemented |
| **Blacksmith Service** | Item repair/upgrading | Implemented |

See `core/services/inventory_service.gd`, `vault_service.gd`, `trade_service.gd`.

### 6.6 Player Open Questions

- [ ] Level cap expansion beyond initial cap?
- [ ] Additional respec options for gold?
- [ ] Crafted vs dropped item balance?

---

## 7. Economy & Crafting

> **Partial Implementation:** Trade, vendor, and item degradation implemented.
> Gathering and full crafting professions are planned.

### 7.1 Gathering System

| Feature | Description | Priority |
|---------|-------------|----------|
| **Mining** | Extract ore from nodes | P0 |
| **Herbalism** | Harvest plants for potions | P0 |
| **Woodcutting** | Chop trees for lumber | P0 |
| **Skinning** | Harvest materials from beasts | P0 |
| **Fishing** | Catch fish from water | P1 |
| **Gathering Tools** | Pickaxe, sickle, axe, knife | P0 |
| **Node Respawn** | Resources respawn after time | P0 |
| **Rich Nodes** | Bonus loot chance from rare nodes | P1 |

### 7.2 Crafting Professions

| Feature | Description | Status |
|---------|-------------|--------|
| **Blacksmithing** | Weapons, armor, metal goods | Implemented (repair/upgrade) |
| **Tailoring** | Cloth/leather armor | P0 |
| **Alchemy** | Potions, elixirs, poisons | P0 |
| **Enchanting** | Add magical properties to gear | P1 |
| **Engineering** | Gadgets, explosives, devices | P1 |
| **Cooking** | Food buffs | P1 |
| **Crafting Recipes** | Discovered or purchased | P0 |
| **Crafting Quality** | Normal, Fine, Masterwork tiers | P0 |

See `core/services/blacksmith_service.gd` and `ui/components/blacksmith_ui.gd`.

### 7.3 Player Economy

| Feature | Description | Status |
|---------|-------------|--------|
| **Currency** | Gold coin standard | Implemented |
| **Dropped Loot** | Items drop from mobs | Implemented |
| **Player Trading** | Direct trade between players | Implemented |
| **Vendor System** | NPC vendors buy/sell | Implemented |
| **Item Degradation** | Gear loses durability, repairs needed | Implemented |
| **Item Sinks** | Repairs, taxes, crafting costs | Implemented |
| **Player Shops** | Rent vendor stalls in towns | P1 |
| **Auction House** | Central marketplace (with tax) | P1 |

See `core/services/vendor_service.gd`, `core/services/trade_service.gd`.

### 7.4 Economy Open Questions

- [ ] Crafted vs dropped item balance?
- [ ] Gold cap per player?
- [ ] Real-money trading policy?
- [ ] Full crafting professions timeline?

---

## 8. Player Housing

> **Status: PARTIAL (2026-11-14).** The plot purchase, three house tiers,
> house guard, personal ankh and functional station commands ship. Housing
> is runtime-only: plots reset on restart. See
> [`prd-housing.md`](./prd-housing.md) for the canonical contract and gaps.

### 8.1 Housing Features

| Feature | Description | Status |
|---------|-------------|--------|
| **Placement System** | Buy the demo plot with `/buyplot`; one plot per player | ✅ Service, one scene-registered plot |
| **House Types** | Claim / Cottage / Hall from `data/houses/` | ✅ Three tiers; no mansion |
| **Interior Customization** | Furniture, decorations, trophies | P1 — no general furniture placement |
| **Exterior Customization** | House skin, garden, mounts displayed | P1 |
| **Storage** | Additional chest space at home | P1 |
| **Crafting Stations** | Functional workbenches at home | ✅ `/placestation` consumes the item |
| **Teleport Home** | Easy recall to house | P1 |
| **Guild Houses** | Shared guild housing | P2 — `PlacementAccess` seam only |

### 8.2 Housing Open Questions

- [ ] Instanced vs shared world housing?
- [ ] Housing demolition/relocation?
- [ ] Housing permissions (friends, guild)?
- [ ] Persist plots and placed objects, or keep housing session-scoped?

---

## 9. PvP Systems

> **Status:** Zone types implemented. Full loot mechanics: zone types done, item drop mechanics NOT done (keep as planned).

### 9.1 Zone Types — ✅ Implemented

| Feature | Description | Priority |
|---------|-------------|----------|
| **Safe Zones** | Towns, starting areas — no PvP | ✅ Implemented |
| **Contested Zones** | PvP enabled, no full loot | ✅ Implemented |
| **PvP Zones** | Full loot enabled | ✅ Implemented |
| **Arena/PvP Battlegrounds** | Structured PvP content | P1 |
| **Guild War System** | Declare war, territory control | P1 — territory claims ship; guild wars do not |

### 9.2 Full Loot Mechanics

| Feature | Description | Priority |
|---------|-------------|----------|
| **Death Drop** | Lose equipped items on death | P0 |
| **Drop Protection** | Some items protected (bind on pickup) | P0 |
| **Bag Drop** | Chance to drop inventory items | P0 |
| **PvP Kills Credit** | Last hit gets loot rights | P0 |
| **Revenge System** | Kill a ganker for bonus loot | P1 |

### 9.3 PvP Open Questions

- [ ] Level bracket restrictions for PvP?
- [ ] Karma/reputation system for PKers?
- [ ] World PvP incentives vs pure griefing?

---

## 10. Social & Guild Systems

### 10.1 Communication

Implemented chat channels:

| Channel | Description | Status |
|---------|-------------|--------|
| **SAY** | Local say | ✅ Implemented |
| **WHISPER** | Private message | ✅ Implemented |
| **YELL** | Large radius shout | ✅ Implemented |
| **ZONE** | Zone-wide chat | ✅ Implemented |
| **GLOBAL** | Server-wide chat | ✅ Implemented |
| **PARTY** | Party chat | ✅ Implemented |
| **GUILD** | Guild chat | ✅ Implemented |
| **ALLIANCE** | Alliance chat | ✅ Implemented |
| **TRADE** | Trade channel | ✅ Implemented |
| **SYSTEM** | System messages | ✅ Implemented |
| **EMOTE** | Social emotes | ✅ Implemented |

See `core/services/chat_service.gd` and `ui/components/chat_ui.gd`.

### 10.2 Grouping

| Feature | Description | Status |
|---------|-------------|--------|
| **Party Formation** | Invite, join, kick | ✅ Implemented |
| **Party Size** | Standard 5, raid 20 | ✅ Implemented |
| **Loot Distribution** | Free-for-all, round-robin, loot council | ✅ Implemented |
| **Party Finder** | Automated group finder | P1 |
| **Mentoring** | Higher level helps lower | P1 |

See `core/services/party_service.gd` and `ui/social/party_ui.gd`.

### 10.3 Friends & Social

| Feature | Description | Status |
|---------|-------------|--------|
| **Friends List** | Add/remove friends, online status | ✅ Implemented |
| **Friend Requests** | Send/accept/expire requests | ✅ Implemented |
| **Block/Ignore** | Block or ignore players | ✅ Implemented |

See `core/services/friends_service.gd` and `ui/social/friends_list.gd`.

### 10.4 Guilds

| Feature | Description | Status |
|---------|-------------|--------|
| **Guild Creation** | Form guild with name, tag | ✅ Implemented |
| **Guild Ranks** | Customizable roles/permissions | ✅ Implemented |
| **Guild Bank** | Shared storage | ✅ Implemented |
| **Guild Chat** | Guild-only chat | ✅ Implemented |
| **Territory Claims** | `/claim` under `MANAGE_GVG`; a 50-influence claim contests but does not unseat a 100-influence holder | ✅ Implemented |
| **Guild Wars** | Declare on other guilds | P1 — no guild war record yet |
| **Guild Upgrades** | Guild hall, buffs, perks | P1 |
| **Alliance** | Multiple guilds allied | ✅ Service-level; UI polish P2 |

See `core/services/guild_service.gd` and `ui/social/guild_ui.gd`. Canonical:
[`prd-guild.md`](./prd-guild.md).

### 10.5 Achievements

| Feature | Description | Status |
|---------|-------------|--------|
| **Achievement Tracking** | Track player achievements | ✅ Implemented |
| **Achievement UI** | View and display achievements | ✅ Implemented |
| **Achievement Popup** | In-game notification | ✅ Implemented |

See `core/services/achievement_service.gd` and `ui/social/achievement_ui.gd`.

### 10.6 Social Open Questions

- [ ] Party finder implementation?
- [ ] Mentoring system?
- [ ] Guild upgrades timeline?

### 10.7 Faction System

| Feature | Description | Status |
|---------|-------------|--------|
| **Faction Reputation** | Player standing with each faction | ✅ Runtime (persistence gap) |
| **War Declarations** | Admin-gated `/war declare`; player faction leadership pending | 🟡 Admin-only |
| **Guild Alliances** | Guilds can ally with factions | ✅ Service-level |
| **War Cooldowns** | 24-hour cooldown between war declarations | ✅ Runtime |
| **War Costs** | 10,000 gold constant exists; no purse is charged yet | ❌ Not enforced |

See `core/services/faction_manager.gd`. Canonical:
[`prd-factions.md`](./prd-factions.md).

### 10.8 Death System

| Feature | Description | Status |
|---------|-------------|--------|
| **Death Penalties** | XP loss, item degradation | ✅ Implemented |
| **Invincibility Frames** | Brief immunity after respawn | ✅ Implemented |
| **Griefing Protection** | Protection from repeated kills | ✅ Implemented |
| **Kill Streaks** | Track consecutive kills | ✅ Implemented |
| **Death Statistics** | Track deaths by type (PvP/PvE) | ✅ Implemented |
| **Revive System** | Player-to-player revival | ✅ Implemented |

See `core/services/death_features.gd`.

### 10.9 Fairness System

> **Unique:** Synmergia treats AI agents and humans as equals with identical
> capabilities and limits. No special privileges for either.

| Feature | Description | Status |
|---------|-------------|--------|
| **Trust System** | 0.0-1.0 trust score per player | ✅ Implemented |
| **Anti-Marathon** | Debuffs after 8+ hour sessions | ✅ Implemented |
| **Anti-Bot Detection** | Behavioral analysis for automation | ✅ Implemented |
| **Rate Limiting** | Per-action rate limits | ✅ Implemented |
| **Consensus Voting** | Player-driven governance decisions | Planned |

See `core/services/fairness_service.gd`.

### 10.10 Quest System

| Feature | Description | Status |
|---------|-------------|--------|
| **Quest Tracking** | Track active quests and objectives | ✅ Implemented |
| **Quest Acceptance** | Accept from NPCs | ✅ Implemented |
| **Objective Types** | Kill, collect, interact, explore | ✅ Implemented |
| **Quest Rewards** | Gold, XP, items | ✅ Implemented |
| **Quest UI** | Display active/available quests | ✅ Implemented |

See `core/services/quest_service.gd` and `ui/components/quest_ui.gd`.

### 10.11 Dialogue System

| Feature | Description | Status |
|---------|-------------|--------|
| **NPC Dialogue** | Branching conversation trees | ✅ Implemented |
| **Dialogue Choices** | Player-selectable options | ✅ Implemented |
| **Dialogue Data** | Load from `.tres` resources | ✅ Implemented |
| **Dialogue UI** | Render conversations in-game | ✅ Implemented |

See `core/services/dialog_service.gd`, `core/schemas/dialogue_data.gd`, and `ui/components/dialog_ui.gd`.

---

## 11. Account & Server Systems

### 11.1 Account Management

| Feature | Description | Status |
|---------|-------------|--------|
| **Account Creation** | Email/password registration | ✅ Implemented |
| **Character Slots** | Up to 5 characters per account | ✅ Implemented |
| **Character Transfer** | Same-account character transfers | ✅ Implemented |
| **Account Settings** | Per-account configuration | ✅ Implemented |

See `core/services/account_service.gd` and `core/services/same_account_transfer_service.gd`.

### 11.2 Server Infrastructure

| Feature | Description | Status |
|---------|-------------|--------|
| **Shard Management** | Multiple game shards/instances | ✅ Implemented |
| **Server Manager** | Orchestrates game servers | ✅ Implemented |
| **Login Service** | Authentication and session management | ✅ Implemented |
| **Data Service** | Centralized data loading | ✅ Implemented |
| **Connector Service** | Client connection handling | ✅ Implemented |

See `core/services/shard_manager.gd`, `core/services/server_manager.gd`, `core/services/login_service.gd`.

### 11.3 Anti-Cheat & Security

| Feature | Description | Status |
|---------|-------------|--------|
| **Bot Detection** | Behavioral analysis for automation | ✅ Implemented |
| **Macro Detection** | Pattern recognition for repeated actions | ✅ Implemented |
| **Speed Hack Detection** | Movement velocity validation | ✅ Implemented |
| **Anomaly Detection** | Statistical analysis of player behavior | ✅ Implemented |
| **Player Banning** | Permanent and temporary bans | ✅ Implemented |

See `core/services/anticheat_service.gd`, `core/services/security_service.gd`.

### 11.4 Infrastructure Services

| Service | Description | File |
|---------|-------------|------|
| **QoS Service** | Latency monitoring, rate limiting | `qos_service.gd` |
| **Notification Service** | Toast notifications, alerts | `notification_service.gd` |
| **Security Monitor** | Security event tracking | `security_service.gd` |
| **Auto Response** | Automated moderation responses | `auto_response_service.gd` |
| **Logger** | Centralized logging | `logger.gd` |

---

### 11.5 Agent Connectors

> **Unique:** AI agents can play as characters with the same capabilities as humans.

| Connector | Description | Status |
|-----------|-------------|--------|
| **MCP** | Model Context Protocol — standard interface for AI agents | ✅ Implemented |
| **Vant** | Vant framework integration | ✅ Implemented |
| **Webhook** | Webhook-based agent communication | ✅ Implemented |

See `core/services/connector_service.gd` and `game/connectors/`.

---

## 12. Technical Architecture

> **Updated 2026-09-16:** Godot 4.7.2 chosen for open source,
> lightweight, no royalties, and strong 3D support. The frame is
> T3 content-hash substrate + scope engine + rules engine (per
> `world-building-arch.md`). The game is in `game/`, the frame
> in `game/core/frame/`.

### 12.1 Engine Selection

| Option | Pros | Cons | Status |
|--------|------|------|--------|
| **Godot 4.7.2** | Open source (MIT), lightweight, no royalties, strong 3D, GDScript | Smaller ecosystem than Unity | ✅ **CHOSEN** |
| **Unity** | Industry standard, great mobile support, large asset store | License fees after revenue | ❌ Not chosen |
| **Unreal 5** | Powerful graphics, Blueprints | Heavy for mobile, complex | ❌ Not chosen |

**Key Godot Features Used:**
- GDScript for game logic
- Godot 4.x scene system (`.tscn`)
- WebSocket for networking (browser + agent compatibility)
- `var_to_bytes` / `bytes_to_var` for network serialization
- Physics3D for collision
- Headless server mode for dedicated servers
- `GameManager` detects headless mode (`OS.has_feature('headless')` / `DisplayServer.get_name() == 'headless'`), skips 3D WorldPlayable scene load, still emits `player_entered_world` signal for tests
- `@tool` scripts for editor-time content
- HTML5/wasm export for browser deployment

### 12.2 Client Architecture

| Component | Description |
|------------|-------------|
| **UI (Islands)** | Each UI panel is a PackedScene with an `IslandPlaceholder` root. Mounted by `IslandManager` from a static `IslandRegistry`. Replaces the old monolithic UIPanel base. POC shipped. |
| **UI (HUD / Widgets)** | Separate `UIWidget` base (sibling to UIPanel) for in-world overlays: health bar, target frame, buff bar. Not islands. |
| **State (client side)** | The client holds a (possibly divergent) state tree, the same shape as the server's. Predicted inputs locally; reconciled by hash diff from server. |
| **Rendering** | Standard Godot 3D pipeline. LOD on graphics is independent of LOD on state. |
| **Input** | Touch, keyboard/mouse, and controller (planned). All go through a unified action layer. |

### 12.3 Server Architecture

| Component | Description | Priority |
|-----------|-------------|----------|
| **Auth Server** | Login, account creation with seed chain | ✅ Implemented |
| **Game Server** | Authoritative game world simulation | ✅ Implemented |
| **T3 Substrate** | Content-hash tree primitive. Each entity is a content-hashed node. Server tick = re-rooting the tree. See [`world-building-arch.md`](./world-building-arch.md). | ✅ Implemented |
| **Scope Engine** | Hierarchy walker for world→shard→instance→player scopes. Resolves rules and values at scope boundaries. | ✅ Implemented |
| **Rules Engine** | Generic evaluator for behavior rules. | ✅ Implemented |
| **Snapshot Store (Postgres)** | `state_snapshots` table persists root hashes. Lazy load on restart. | Partial |
| **Cache Layer (in-memory)** | LRU-backed intersection cache for hot queries. See [`world-building-arch.md`](./world-building-arch.md). | Partial |
| **Message Queue** | Handle real-time messages | Partial |
| **Load Balancer** | Distribute players across servers | Partial |
| **Anti-Cheat** | Server-side validation, hash-chain tick verification | Partial |
| **CDN** | Asset distribution by content-hash | P1 |

See [`world-building-arch.md`](./world-building-arch.md) for the full frame architecture (substrate, scope engine, rules engine, spatial layer) and [`world-building-tick.md`](./world-building-tick.md) for the server tick model.

### 12.4 Networking

| Feature | Description | Priority |
|---------|-------------|----------|
| **Protocol** | WebSocket for browser + agent compatibility | P0 |
| **Client Prediction** | Smooth movement despite latency | P0 |
| **Server Reconciliation** | Rollback to known-good hash, apply patch | P0 |
| **Lag Compensation** | Fair hit detection with latency | P0 |
| **Interest Management** | Only sync nearby entities (use icosahedral adjacency) | P0 |
| **Tick Rate** | Server update frequency (10-60 Hz) | P0 |
| **State Diff** | Server sends root hash + diff, not full state. Bandwidth = O(diff size), not O(state size). | P0 |
| **P2P Entity Sync (optional)** | Nearby players gossip via hash-set reconciliation. Reduces server load. The "assimilation" piece. | P2 |

See [`world-building.md`](./world-building.md) §10 for the full transport design.

### 12.5 Database Design — ✅ Implemented via Adapter Layer

| Concern | Storage | Notes |
|---------|---------|-------|
| **Durable state** | Postgres (rows for entities, snapshots for root hashes) | Single source of truth. |
| **Hot path** | In-memory state tree (content-hash nodes) | Re-built from Postgres on restart. |
| **Intersection cache** | LRU of (axis_combo) → entity_set | Bounded, evicts cold combos. |
| **Save games** | Content-hashed tree, diff between versions | Patchable, tamper-detectable. |
| **Item templates** | Content-hashed | Cross-shard dedup via hash equality. |
| **Assets** | Content-hashed pck + CDN | Old clients can still find old assets on update. |


### 12.6 The T3 Substrate

The frame's core primitive: a generic content-hash tree. Every
node has a `hash` (SHA-256 of its serialized value). The frame
extracts this into `game/core/frame/kv/t3.gd`.

See [`prd-t3-substrate.md`](./prd-t3-substrate.md) for the full spec.

### 12.7 The Scope Engine

Data-driven hierarchy walker. Resolves rules and values at scope
boundaries (world→shard→instance→player). The frame extracts
this into `game/core/frame/srv/scope.gd`.

See [`prd-scope-engine.md`](./prd-scope-engine.md) for the full spec.

### 12.8 The Rules Engine

Generic behavior evaluator. Runs rules defined in the state tree
against entities. Composes with the scope engine for per-scope
rule overrides.

See [`world-building-arch.md`](./world-building-arch.md) §5 for the rules engine design.

### 12.9 DevOps

| Feature | Description | Priority |
|---------|-------------|----------|
| **CI/CD Pipeline** | Automated builds, testing | P0 |
| **Server Hosting** | Cloud provider (AWS/GCP/Azure) | P0 |
| **Monitoring** | Player counts, server health, intersection cache hit rate | P0 |
| **Analytics** | Track player behavior, economy, prediction accuracy | P1 |
| **Auto-scaling** | Respond to player load; prefetch more on scale-up | P1 |

### 12.10 Three Tiers of Computation (the frame runtime)

The frame can ship in three runtime tiers. The rule is: write
the algorithm in the language that's best at the problem. The
GDScript side calls into the appropriate tier for each call
site.

| Tier | Language | When | Example |
|------|----------|------|---------|
| 1 | **GDScript** | Game logic, UI, event handling, scene composition | All autoloads, UI, services |
| 2 | **Julia** (via polyglot FFI) | Vector math, ML inference, hot loops | Spatial query, state hashing, intersection materialization, LOD batch |
| 3 | **C++ / GDExtension** | Absolute hot path, physics, low-level | Jolt Physics, future SIMD paths |

**Tier 1 (GDScript) is the default.** Most of the game lives here.

**Tier 2 (Julia) is the vector processor.** When GDScript is
too slow for a math-heavy hot path, the polyglot FFI
([`labs/polyglot-ffi/`](polyglot-ffi/)) calls into a Julia
sidecar. The pattern is lifted from vant
[`lib/compute.js`](https://github.com/dhaupin/vant/blob/axolotl/lib/compute.js)
(adapted for GDScript). The first concrete implementation is
[`labs/polyglot-ffi/julia-runtime/`](polyglot-ffi/julia-runtime/).

**Tier 3 (C++ / GDExtension) is the absolute hot path.**
Physics is the first example: Jolt Physics
([`labs/jolt-playground/`](jolt-playground/)) is C++ with a
Godot 4.3+ binding. Future SIMD ops land here.

The frame is **runtime-agnostic**. The game passes the
orchestrator + state tree around via dependency injection, not
via singleton access. Each tier plugs in via the polyglot FFI
or GDExtension — the game logic doesn't change.

When a path needs more than Julia, it moves to GDExtension C++.
When a path needs less, it stays in GDScript. The migration
is incremental: profile, port, re-profile, ship.

### 12.11 Geometry Layer: NSC-9 + Spatial Fragmenter

The geometry layer bridges three frame primitives into a
unified spatial addressing pipeline:

```
NSC-9 spatial code (9-AAA-BBB-CCCCCC)
    -> SpatialFragmenter 64-bit address (octree subdivision)
       -> T3 content-hash tree (deterministic state storage)
```

**NSC-9** (`game/core/frame/math/nsc9.gd`): Encodes facility/axis/sequence
into a 14-digit integer. Spatial axes 1-12 map to icosahedral faces.
Pure functions only; `class_name Nsc9` (NOT an autoload).

**SpatialFragmenter** (`game/core/frame/geometry/spatial_fragmenter.gd`):
64-bit address encoding (x:16, y:16, z:16, depth:8, face:8), octree
subdivision, ancestor lineage, bounding boxes. `MAX_DEPTH=24`.
`class_name SpatialFragmenter` (NOT an autoload).

**Nsc9Bridge** (`game/core/frame/geometry/nsc9_bridge.gd`):
Pure function bridge connecting NSC-9 -> SpatialFragmenter -> T3.
`extends RefCounted`. 10 methods: `nsc9_to_address`, `address_to_t3_path`,
`nsc9_to_t3_path`, `store_nsc9_state`, `store_nsc9_fragmented`,
`restore_nsc9_fragmented`, `query_nsc9_vertex`, `query_nsc9_region`,
`is_spatial_nsc9`, `entity_spatial_to_vertex`. No state, no autoload,
no GameManager dependency.

Integration: EntityService caches NSC-9 codes per entity (`_entity_nsc9_codes`);
ZoneManager derives NSC-9 codes per zone (`get_zone_nsc9_code`). Both
services gracefully degrade if bridge is unavailable.

Integration tests: `game/core/frame/geometry/test_nsc9_bridge.gd` — 9 test
cases, runs with `godot --headless --path . --script ...`.

See `labs/prd-geometry.md` for the full fragmenter spec.

---

## 13. Data Schemas

> **Pattern:** Game data is defined in `.tres` Resource files loaded at runtime.
> Schemas define the structure; data files provide the values.

### 13.1 Core Schemas

| Schema | File | Description |
|--------|------|-------------|
| **CharacterData** | `core/schemas/character_data.gd` | Player character state, stats, skills |
| **CharacterClass** | `core/schemas/character_class.gd` | Class definitions with skill trees |
| **Species** | `core/schemas/species.gd` | Species/race definitions with base stats |
| **Item** | `core/schemas/item.gd` | Item templates with rarity, soulbound, stack |
| **EnemyData** | `core/schemas/enemy_data.gd` | Enemy templates with stats, loot tables |
| **NpcData** | `core/schemas/npc_data.gd` | NPC definitions for vendors, quest givers |
| **QuestData** | `core/schemas/quest_data.gd` | Quest definitions with objectives, rewards |
| **DialogueData** | `core/schemas/dialogue_data.gd` | NPC dialogue trees with choices |
| **Faction** | `core/schemas/faction.gd` | Faction definitions with relationships |
| **Skill** | `core/schemas/skill.gd` | Skill definitions with effects, costs |
| **SkillBook** | `core/schemas/skill_book.gd` | Skill upgrade book definitions |
| **StatusEffectData** | `core/schemas/status_effect_data.gd` | Buff/debuff templates |
| **LootTable** | `core/schemas/loot_table.gd` | Loot drop probability tables |
| **GatewayData** | `core/schemas/gateway_data.gd` | Portal/dungeon entrance definitions |
| **FurnishingData** | `core/schemas/furnishing_data.gd` | Player housing definitions |
| **EventData** | `core/schemas/event_data.gd` | World event definitions |
| **NpcOffering** | `core/schemas/npc_offering.gd` | Vendor inventory definitions |
| **Ankh** | `core/schemas/ankh.gd` | Respawn point definitions |

### 13.2 Agent Schemas

| Schema | File | Description |
|--------|------|-------------|
| **AgentConnector** | `core/schemas/agent_connector.gd` | AI agent connection configuration |
| **AgentAction** | `core/schemas/agent_action.gd` | Agent action definitions |

### 13.3 Data Loading

| Service | File | Description |
|---------|------|-------------|
| **DataService** | `core/services/data_service.gd` | Centralized resource loading |
| **CharacterData** | `core/schemas/character_data.gd` | Provides `get_all_species()`, `load_species()`, `get_all_classes()` |

---

## 14. Art & Audio Direction

### 14.1 Visual Style

| Aspect | Description | Priority |
|--------|-------------|----------|
| **Art Style** | Realistic but stylized (not photorealistic) | P0 |
| **Lighting** | Dynamic day/night cycle | P0 |
| **Weather** | Rain, snow, fog effects | P1 |
| **Character Art** | Humanoid with distinct silhouettes | P0 |
| **Environment Art** | Modular tilesets for buildings, terrain | P0 |
| **VFX** | Spell effects, hit impacts | P0 |

### 14.2 Quality Tiers

| Tier | Target Devices | Settings | Priority |
|------|---------------|----------|----------|
| **Low** | Budget phones, 2GB RAM | Reduced draw distance, simpler shaders | P0 |
| **Medium** | Mid-range phones | Balanced quality | P0 |
| **High** | Flagship phones, PC | Max quality | P0 |
| **Ultra** | PC only | Maximum effects | P1 |

### 14.3 Audio

| Feature | Description | Priority |
|---------|-------------|----------|
| **Sound Effects** | Combat, environment, UI | P0 |
| **Music** | Ambient, combat, town themes | P0 |
| **Spatial Audio** | 3D positioned sounds | P1 |
| **Voice Acting** | NPC dialogue (optional) | P2 |

---

## 15. Platform Support & Optimization

> Browser-first deployment (HTML5/wasm), with planned mobile (Android/iOS)
> and desktop (Windows, macOS, Linux) support. Controller support planned.

### 15.1 Input Methods

| Input | Description | Status |
|-------|-------------|--------|
| **Touch** | Virtual joystick (left), camera drag (right), skill buttons | Planned |
| **Keyboard/Mouse** | Standard WASD + mouse, hotbar | Planned |
| **Controller** | Gamepad support (joystick, buttons, triggers) | Planned |
| **Auto-Run** | Toggle for long travel | P1 |
| **Gesture Support** | Double tap, long press on touch | P1 |

### 15.2 UI Adaptation

| Feature | Description | Priority |
|---------|-------------|----------|
| **Screen Sizes** | Support phones, tablets, desktop monitors | P0 |
| **Notch Handling** | Safe areas for modern phones | P0 |
| **UI Scaling** | Adjustable UI element size | P1 |
| **Colorblind Mode** | Accessibility options | P1 |
| **Controller UI** | Controller-friendly navigation | P1 |

### 15.3 Performance Targets

| Metric | Target | Priority |
|--------|--------|----------|
| **Frame Rate** | 30 FPS minimum, 60 FPS target | P0 |
| **Load Times** | < 30 seconds on fast 3G | P0 |
| **Memory** | < 2GB RAM usage | P0 |
| **Battery** | Optimized drain, frame cap option | P1 |

---

## 16. Phases & Milestones

> **Updated 2026-09-16:** Phases reflect the current state
> based on source-of-truth docs in `/labs/`. The frame
> architecture is T3 substrate + scope engine + rules engine
> (per `world-building-arch.md`). PRD specs in `/labs/prd-*.md`
> define the implementation details per phase.

### Phase 0: Foundation ✅ COMPLETE
- [x] Complete PRD (`prd.md`)
- [x] Choose engine (Godot 4.7.2)
- [x] Set up dev environment
- [x] Architecture decisions (services, components, .tres)
- [x] 38 services implemented in `game/core/services/`
- [x] AGENTS.md conventions for AI agents
- [x] `/labs/` directory convention (frame staging area)

### Phase 1: Frame Foundation ✅ COMPLETE
- [x] UI Modernization + Islands POC
- [x] UIPanel → Islands migration
- [x] Multi-iso orchestrator design documented
- [x] Frame architecture designed (T3 + scope + rules)

### Phase 2: Frame Primitives ✅ COMPLETE
Implementation per PRD specs in `/labs/prd-*.md`:

- [x] **T3 Substrate** — `game/core/frame/kv/t3.gd` (DONE)
- [x] **Seed Schema** — Seed type + visibility scope
  - See [`prd-seed-schema.md`](./prd-seed-schema.md)
- [x] **State Schema** — State value types
  - See [`prd-state-schema.md`](./prd-state-schema.md)
- [x] **Scope Engine** — `game/core/frame/srv/scope.gd` (DONE)
- [x] **Rules Engine** — `game/core/frame/srv/rules_engine.gd` (DONE)

> All frame primitives consolidated at `game/core/frame/` (math, kv, srv, db). Legacy `labs/multi-iso/` removed -- the Julia orchestrator now lives at `srv/julia-bridge/` with the other HTTP bridges (2026-09-30).

### Phase 3: Seed System
- [ ] Login + seed chain (D029)
  - See [`prd-login-seed-chain.md`](./prd-login-seed-chain.md)
- [ ] Open seed TTL semantics (D032)
  - See [`prd-open-seed-ttl.md`](./prd-open-seed-ttl.md)
- [ ] Manifest + backup (D031)
  - See [`prd-manifest-backup.md`](./prd-manifest-backup.md)

### 3.x: Geometry Layer Scaffolding (NSC-9 + Spatial Fragmenter Bridge)
- [x] **Fragmenter** (`game/core/frame/geometry/fragmenter.gd`)
  - Knuth multiplicative hash, `derive_lattice_keys`, `fragment`, `weld`
- [x] **SpatialFragmenter** (`game/core/frame/geometry/spatial_fragmenter.gd`)
  - 64-bit addresses, octree subdivision, bounding boxes, MAX_DEPTH=24
- [x] **NSC-9 Bridge** (`game/core/frame/geometry/nsc9_bridge.gd`)
  - Unified pipeline: NSC-9 -> SpatialFragmenter -> T3
  - EntityService + ZoneManager wire the bridge
- [x] **Integration tests** (`test_nsc9_bridge.gd`)
  - 9 test cases covering full pipeline

### Phase 4: State + Sync
- [ ] Server authority model
  - See [`prd-frame-authority.md`](./prd-frame-authority.md)
- [ ] State diff sync (client reconciliation)
- [ ] Critical params system (D033)
  - See [`prd-critical-params.md`](./prd-critical-params.md)

### Phase 5: World Building 🔜 NEXT
- [ ] 5+ zones
- [ ] Dungeons (2-3)
- [ ] Full crafting system
- [ ] Player housing (basic)
- [ ] Guild system
- [ ] Auction house
- [ ] Server infrastructure (Postgres + state tree)

### Phase 6: MMO Features
- [ ] Full world population
- [ ] Player economy (content-hashed item templates)
- [ ] Full loot PvP zones
- [ ] Guild wars
- [ ] World events
- [ ] Anti-cheat (hash-chain tick verification)

### Phase 7: Browser Deployment + Polish
- [ ] Godot HTML5/wasm browser build
- [ ] WebSocket transport
  - See [`world-building.md`](./world-building.md) §10
- [ ] Frame extraction (optional, per viability)
- [ ] Optimization pass
- [ ] Bug fixes
- [ ] Balance tuning

### Phase 8: Launch
- [ ] Browser-first launch (web)
- [ ] Desktop builds (Windows, macOS, Linux)
- [ ] Launch marketing
- [ ] Community building

---

## 17. Open Questions

> **Updated 2026-09-16:** Architecture is now T3 substrate +
> scope engine + rules engine (per `world-building-arch.md`).
> Many open questions are now answered in the PRD specs.

### Resolved

1. ~~**Engine Choice:**~~ → ✅ Godot 4.7.2
2. ~~**Server Hosting:**~~ → Official servers planned (cloud TBD)
3. ~~**PC Support:**~~ → ✅ PC support from day 1 (same Godot build)
4. ~~**Aggro:**~~ → Proximity-based, configurable detection, level-gated XP (see section 3.8)
5. ~~**PvP combat differences:**~~ → CC reduction, gear-differential damage modifiers (tunable)
6. ~~**Architecture:**~~ → ✅ T3 substrate + scope engine + rules engine (per `world-building-arch.md`)
7. ~~**Networking:**~~ → ✅ WebSocket for browser + agent compatibility
8. ~~**Networking serialization:**~~ → ✅ `var_to_bytes` / `bytes_to_var` (Godot 4.x idiom)
9. ~~**World Shape:**~~ → ✅ Spherical planet (radius 20km v1), icosahedral mesh (per `world-building.md` §3)
10. ~~**World Size:**~~ → ✅ ~150 km² continent, rest ocean, capital at center
11. ~~**Zone Transitions:**~~ → ✅ Dungeons/instances via portal, open world seamless

### Open

12. **Scale:** How many players per server?
    - LOD pyramid + intersection cache can carry a lot. 500+ is plausible. 1000+ needs the frame's perf budget answered first.
13. **Level Cap:** 60 levels planned. Expandable.
14. **Art Assets:** AI generation, purchase, custom? TBD.
15. **Real Money:** Cosmetics shop planned. Subscription unlikely. RMT banned, no third-party.
16. **Frame extraction timeline:** When does the frame spin out to its own repo? After Phase 7? Earlier?
17. **Performance budget:** GDScript enough? GDExtension C++? Decided in Phase 4.
18. **Build pipeline shape:** Bash? Godot CLI? CI step? Custom tool? TBD.

---

## Development Tracking

Implementation progress and technical details are tracked in the
codebase. See [`AGENTS.md`](../AGENTS.md) for developer notes.

The architecture documentation is in `/labs/` — see the section
above for the full listing of world-building docs and PRDs.

---

## Appendix

### A. Reference Games
- Risk Your Life 2 (RYL2) — Combat mechanics reference
- Ultima Online — Economy, housing, social systems reference
- World of Warcraft — Quest structure, zone design reference
- Black Desert Online — Mobile optimization reference

### B. Similar Projects
*Links to indie MMORPGs for reference.*

### C. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Scope creep** (frame research distracts from product) | High | Phase 2 is non-negotiable; frame primitives are research that may not pan out. |
| **Performance** (T3 substrate + scope engine too slow at 10K entities) | Medium | Phase 4 perf budget. Fall back to GDExtension C++ for the hot path. |
| **Godot 4.7 stability** (4.7 is recent; bugs in the engine) | Medium | Pin version. Test against the headless server mode. |
| **Build size** (Godot exports bloat with all features) | Medium | Asset content-hash → only what the player needs. |
| **Anti-cheat** (state tree hashes are forgeable) | High | Server-side hash chain. Each tick is signed by previous. |
| **Frame over-engineering** (build abstractions no game uses) | Medium | Frame is a byproduct of game work, not a goal. If no game needs it, it doesn't extract. |
| **Jolt integration cost** (swap-in breaks physics assumptions) | Low | Game is `PhysicsServer3D`-agnostic. Jolt drop-in via project setting. Benchmark first. |
| **Polyglot FFI boundary cost** (Julia subprocess round-trips add latency) | Low | Tier 1 (GDScript) for anything latency-sensitive. Tier 2 only for batch ops. Migration to GDExtension C++ if needed. |

### D. Frame Appendix

> This describes the **frame** — what could be extracted from
> Synmergia and shipped as its own project. The frame is the part
> that any future game on this architecture would consume.
> See [`world-building-arch.md`](./world-building-arch.md) for the
> full architecture.

**The frame is the union of:**

1. **T3 substrate** (`game/core/frame/kv/t3.gd`) — generic content-hash tree primitive
2. **Scope engine** (`game/core/frame/srv/scope.gd`) — hierarchy walker, scope stack, rule resolution
3. **Rules engine** (`game/core/frame/srv/rules_engine.gd`) — generic behavior evaluator
4. **Spatial layer** (`game/core/frame/math/`) — NSC-9, icosahedral, quasicrystal math primitives
5. **LRU cache** (`game/core/frame/kv/lru_cache.gd`) — generic LRU
6. **Snapshot store** (`game/core/frame/db/snapshot_store.gd`) — Postgres persistence

**The frame is NOT:**

- The game itself (services, components, scenes, assets)
- The Godot client (rendering, input, UI)
- The Postgres schema (specific to Synmergia's data)
- The autoload singleton pattern (specific to Godot)

**Why the frame matters:**

The frame is the lever. The game is the proof. If the frame
works for Synmergia, it works for any state-heavy multiplayer
game. The frame extracts to its own project. Synmergia becomes
the example game. Other games can build on the same primitives,
getting content-hash sync, scope-based hierarchy, and behavior
rules for free.

See [`world-building-arch.md`](./world-building-arch.md) §2 for the
full dual-goal architecture (frame + game instance).

---

## 18. Geometry Layer: NSC-9 + Spatial Fragmenter

> **Status (2026-09-17):** Implemented and wired into services.
> See `labs/prd-geometry.md` for the full spec.

The geometry layer bridges three frame primitives into a unified
spatial addressing pipeline:

```
NSC-9 spatial code (9-AAA-BBB-CCCCCC)
    -> SpatialFragmenter 64-bit address (octree subdivision)
       -> T3 content-hash tree (deterministic state storage)
```

### 18.1 The Three Primitives

**NSC-9** (`game/core/frame/math/nsc9.gd`):
Encodes facility/axis/sequence into a 14-digit integer.
Spatial axes 1-12 map to icosahedral faces.
Pure functions only; `class_name Nsc9` (NOT an autoload).

Axis reservation:
- 001-099: spatial axis (icosahedral vertices 1-12)
- 100-199: factional axes
- 200-299: temporal sub-axes
- 300-399: social axes
- 400-499: game-specific axes

**SpatialFragmenter** (`game/core/frame/geometry/spatial_fragmenter.gd`):
64-bit address encoding (x:16, y:16, z:16, depth:8, face:8), octree
subdivision (8 children per step), ancestor lineage, integer-only
bounding boxes. `MAX_DEPTH=24`. `class_name SpatialFragmenter`
(NOT an autoload).

**Nsc9Bridge** (`game/core/frame/geometry/nsc9_bridge.gd`):
Pure function bridge connecting NSC-9 -> SpatialFragmenter -> T3.
`extends RefCounted`. 10 methods:

| Method | Purpose | Signature |
|--------|---------|-----------|
| `nsc9_to_address` | NSC-9 code -> address | `nsc9_to_address(code: int, depth: int = 0, sf: Variant = null) -> int` |
| `address_to_t3_path` | Address -> T3 path | `address_to_t3_path(address: int, sf: Variant = null) -> String` |
| `nsc9_to_t3_path` | NSC-9 code -> T3 path | `nsc9_to_t3_path(code: int, depth: int = 0) -> String` |
| `store_nsc9_state` | Store entity state in T3 | `store_nsc9_state(t3, nsc9_code, state, depth=0, metadata={}) -> PackedByteArray` |
| `store_nsc9_fragmented` | Fragment + store in T3 | `store_nsc9_fragmented(t3, nsc9_code, state, fragmenter, depth=0) -> PackedByteArray` |
| `restore_nsc9_fragmented` | Restore fragmented state | `restore_nsc9_fragmented(t3, nsc9_code, fragmenter, depth=0) -> Dictionary` |
| `query_nsc9_region` | Query fragments in region | `query_nsc9_region(t3, nsc9_code, depth=0) -> Array[Dictionary]` |
| `query_nsc9_vertex` | Query all fragments on face | `query_nsc9_vertex(t3, nsc9_code) -> Array[Dictionary]` |
| `is_spatial_nsc9` | Check if code has spatial axis | `is_spatial_nsc9(code: int) -> bool` |
| `entity_spatial_to_vertex` | Entity spatial -> face | `entity_spatial_to_vertex(facility: int, vertex: int) -> int` |

No state, no autoload, no GameManager dependency.

### 18.2 NSC-9 -> Spatial Mapping

NSC-9 components map to SpatialFragmenter address as:
- `facility` -> x coordinate (0-999, fits in 16 bits)
- `axis` -> vertex via `SpatialFragmenter.nsc9_code_to_vertex` (1-12 -> 0-11)
- `sequence` -> split into y (bits 10-19, 0-1023) and z (bits 0-9, 0-1023)
- `depth` -> subdivision depth (caller-specified, default 0)

Non-spatial axes (100+) return 0 (invalid address).

### 18.3 Service-Level Integration

**EntityService** (`game/core/services/entity_service.gd`):
- `_nsc9_bridge` initialized in `_init_spatial_and_t3()`
- `_compute_nsc9_code(entity)` derives codes from position + entity_id
  - Facility: `abs(hash(entity_id)) % 1000`
  - Axis: `Nsc9.nearest_vertex(lat, lon)` -> `Nsc9.spatial_axis(vertex)`
  - Sequence: `Nsc9.deterministic_seq(entity_id, "nsc9")`
- `_entity_nsc9_codes` dict caches codes per entity_id
- `metadata.nsc9_code` set on registration

**ZoneManager** (`game/core/services/zone_manager.gd`):
- `_nsc9_bridge` initialized in `_init_spatial_fragmenter()`
- `_compute_nsc9_code(zone_id, zone_center)` derives codes for zones
- Public helpers: `get_zone_nsc9_code(zone_id)`, `get_zone_nsc9_t3_path(zone_id)`

Both services gracefully degrade if bridge is unavailable.

### 18.4 Testing

`game/core/frame/geometry/test_nsc9_bridge.gd` — 9 test cases:
- NSC-9 -> address conversion (face mapping, depth)
- NSC-9 -> T3 path (format validation)
- Store/query state + deterministic hash
- Fragmented store + restore round-trip
- Face query isolation
- Non-spatial NSC-9 rejection
- `is_spatial_nsc9` checks
- `entity_spatial_to_vertex` mapping

Run with `godot --headless --path . --script res://core/frame/geometry/test_nsc9_bridge.gd`.

### 18.5 File Organization

```
game/core/frame/geometry/
├── fragmenter.gd              # Data sharding (Knuth hash, fragment, weld)
├── spatial_fragmenter.gd      # Spatial addressing (64-bit, octree)
├── nsc9_bridge.gd             # NSC-9 -> SpatialFragmenter -> T3 bridge
├── test_fragmenter.gd         # Fragmenter tests
├── test_spatial_fragmenter.gd # SpatialFragmenter tests
└── test_nsc9_bridge.gd        # Bridge integration tests
```

See `labs/prd-geometry.md` for the full fragmenter spec.
