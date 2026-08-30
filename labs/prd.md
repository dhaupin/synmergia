# Synmergia — Open World MMORPG

> **Status (2026-08-30):** Modernized to reflect the current
> architecture (state tree, multi-iso orchestrator, content-hash
> layer, predictive LOD) and the Track A / Track B plan. This
> document lives in `labs/` because the architecture is
> experimental; the game itself is in `synmergia/`.

> **Vision:** A 3D open-world MMORPG inspired by Risk Your Life 2
> (RYL2) combat/action mechanics, infused with the depth and
> player-driven economy of Ultima Online. Mobile-first
> (Android/iOS), with PC support. Built on a reusable **frame**
> (multi-iso orchestrator + state tree) that can be extracted to
> its own project — see the Frame appendix.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Core Game Pillars](#2-core-game-pillars)
3. [Combat Systems](#3-combat-systems)
4. [World & Exploration](#4-world--exploration)
5. [Player Systems](#5-player-systems)
6. [Economy & Crafting](#6-economy--crafting)
7. [Player Housing](#7-player-housing)
8. [PvP Systems](#8-pvp-systems)
9. [Social & Guild Systems](#9-social--guild-systems)
10. [Technical Architecture](#10-technical-architecture)
11. [Art & Audio Direction](#11-art--audio-direction)
12. [Mobile Optimization](#12-mobile-optimization)
13. [Phases & Milestones](#13-phases--milestones)
14. [Open Questions](#14-open-questions)

## Architecture documentation

This PRD is the product spec. The architecture is in
[`docs/architecture/`](../../synmergia/docs/architecture/) (in the
`synmergia/` subdirectory because it ships with the game):

- [`multi-iso-frame.md`](../../synmergia/docs/architecture/multi-iso-frame.md) — the multi-iso orchestrator (Part 1)
- [`multi-iso-lod-prediction.md`](../../synmergia/docs/architecture/multi-iso-lod-prediction.md) — LOD + materialized + prediction (Part 2)
- [`labs-organization.md`](../../synmergia/docs/architecture/labs-organization.md) — the `/labs/` convention
- [`nsc9-honest-evaluation.md`](../../synmergia/docs/architecture/nsc9-honest-evaluation.md) — why the geometry is a layer, not a replacement
- [`NEXT-AGENT-PICKUP.md`](../../synmergia/docs/architecture/NEXT-AGENT-PICKUP.md) — survival guide

Section 10 of this PRD links to these for the technical details.

---

## 1. Executive Summary

**Synmergia** is a 3D open-world MMORPG targeting mobile
(Android/iOS) with PC support. The game combines RYL2's
fast-paced, free-form action combat with Ultima Online's depth
of player-driven economy, housing, and world interaction.

**Core Loop:** Explore vast world → Fight enemies/dungeons →
Craft gear → Build houses → Participate in PvP → Repeat

**Target Audience:**
- MMORPG players who miss the depth of UO/EVE-era games
- Mobile gamers who want console-quality action combat on the go
- Players who enjoy crafting, housing, and player economies
  over theme-park content

**Competitive Landscape:**
- Similar to: RYL2 (combat feel), UO (economy/housing), Black
  Desert (action combat), Albion Online (full loot PvP)
- Differentiator: Mobile-first with full MMO depth, not a
  stripped-down mobile port. Plus: a **reusable game frame**
  (multi-iso orchestrator + state tree + content-hash layer) that
  could be extracted to its own project, so other games can be
  built on the same architecture.

**Development Approach:**
- Agent-assisted development using LLMs for code generation
- Incremental feature delivery with continuous integration
- Godot 4.7.2 for cross-platform deployment
- Two-track plan: **Track A** ships the game (state tree,
  islands, save games, asset addressing, build pipeline);
  **Track B** develops the frame (math primitives,
  multi-iso orchestrator, materialized intersection, LOD,
  prediction). See the [Frame appendix](#frame-appendix) and
  [`multi-iso-frame.md`](../../synmergia/docs/architecture/multi-iso-frame.md).

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

### 5. Mobile-First Quality 📱
The same full experience on mobile as on PC. Touch controls designed for action combat, not afterthought keyboard mappings. Optimized for all device tiers.

---

## 3. Combat Systems

> **Lead:** This section defines the RYL2-inspired action combat with tab-targeting hybrid.

### 3.1 Movement

| Feature | Description | Priority |
|---------|-------------|----------|
| **3rd Person Camera** | Auto-follow camera behind player, adjustable zoom | P0 |
| **Virtual Joystick** | Left side of screen for movement | P0 |
| **Jump** | Single jump with animation | P0 |
| **Dodge/Roll** | Quick directional evade with i-frames | P0 |
| **Sprint** | Hold to run faster, consumes stamina | P0 |
| **Swimming** | Move through water, slower than land | P1 |
| **Climbing** | Scale ladders, walls, ledges | P1 |
| **Mounts** | Rideable horses/dragon mounts | P2 |
| **Flight** | Unlockable flying mounts for endgame zones | P2 |

### 3.2 Targeting System

| Feature | Description | Priority |
|---------|-------------|----------|
| **Tab Targeting** | Cycle through nearby enemies with Tab | P0 |
| **Soft Targeting** | Hover over enemy to aim ground-targeted spells | P0 |
| **Auto-Target Closest** | Option to auto-lock nearest enemy | P1 |
| **Friendly Targeting** | Target allies for buffs/heals (Tab + Shift) | P0 |
| **Target Lock** | Hold target even when out of range | P1 |
| **Target Nameplate** | Show enemy name, health bar, level, elite indicator | P0 |

### 3.3 Combat Actions

| Feature | Description | Priority |
|---------|-------------|----------|
| **Auto-Attack** | Basic melee/ranged attack on loop when engaged | P0 |
| **Skill Hotbar** | 8-12 slot hotbar (skills 1-0, Shift+1-0) | P0 |
| **Skill Queuing** | Queue next skill while current one animates | P0 |
| **Skill Combos** | Certain skill sequences trigger bonus effects | P1 |
| **Interrupt** | Stun/knockback can interrupt channeled skills | P0 |
| **Dodge Mechanics** | I-frames during dodge roll | P0 |
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
| **Player HP Bar** | Large bar above character, follows player | P0 |
| **Target HP Bar** | Bar below target's nameplate | P0 |
| **HP/Mana/Stamina HUD** | Always visible bars (adjustable position) | P0 |
| **Damage Numbers** | Float up on hit (crits are larger, different color) | P0 |
| **Status Effects** | Icons above player showing buffs/debuffs | P0 |
| **Enemy Health Scaling** | Health bar size reflects remaining HP % | P1 |

### 3.6 Death & Resurrection

| Feature | Description | Priority |
|---------|-------------|----------|
| **Death State** | Character falls, ghost mode activates | P0 |
| **Respawn Options** | Return to nearest bind point or town | P0 |
| **Resurrection by Others** | Party/guild members can rez with cast time | P0 |
| **Death Penalty** | XP loss, item degradation, drop chance in PvP zones | P0 |
| **Kill Credit** | Proper credit for kills (last hit vs damage dealt) | P0 |

### 3.7 Combat Animations & Feedback

| Feature | Description | Priority |
|---------|-------------|----------|
| **Hit Reactions** | Enemies stagger/recoil on hit | P0 |
| **Impact Effects** | Particles/sounds on hit connection | P0 |
| **Screen Shake** | Subtle shake on heavy hits | P1 |
| **Armor Sounds** | Distinct sounds for different weapon types | P0 |
| **Weapon Trails** | Visible trails for sword swings | P1 |
| **Animation Canceling** | (Specific rules TBD - RYL2 had strict cancels) | P1 |

### 3.8 Combat Open Questions

> **DECIDED:** These questions have been answered in development.

- [x] **How does aggro work?** → Proximity-based aggro with configurable detection radius. Enemies detect players within aggro range. Higher level enemies don't aggro much lower level players (20+ level gap). Players 20+ levels higher get minimal XP.

- [x] **PvP combat differences?** → CC reduction in PvP (50% duration), damage modifiers based on gear differential. Open for tuning.

- [ ] Solo vs group damage scaling? → TBD (no decision yet)

- [ ] Level scaling within zones? → TBD (world scaling not planned for initial release)

---

## 4. World & Exploration

> **In Progress:** Terrain, zones, procedural generation, dungeons.

### 4.1 World Structure

| Feature | Description | Priority |
|---------|-------------|----------|
| **Main Continent** | Central hub zone with starter areas | P0 |
| **Satellite Zones** | Surrounding islands/regions | P1 |
| **Underworld** | Underground realm with unique content | P2 |
| **Dimension Planes** | Instance realms for high-level content | P2 |
| **Open Ocean** | Navigable water between continents | P2 |
| **Seasonal Zones** | Rotate available zones (events) | P3 |

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
| **Towns** | Safe zones, vendors, quest hubs | P0 |
| **Dungeons** | Instance or open-world dungeon zones | P0 |
| **Difficult Spawns** | Elite mobs, world bosses | P0 |
| **Resource Nodes** | Ore, herbs, wood spawns | P0 |
| **Landmarks** | Visible markers for navigation | P0 |
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

### 4.5 World Open Questions

- [ ] How large is the main continent? (RYL2 scale vs WoW scale?)
- [ ] Instance vs open-world dungeons?
- [ ] Server meshing for player density?
- [ ] Loading screens between zones or seamless transitions?

---

## 5. Player Systems

> **In Progress:** Character creation, progression, classes, leveling.

### 5.1 Character Creation

| Feature | Description | Priority |
|---------|-------------|----------|
| **Race Selection** | Human, Elf, Orc, Dwarf, custom? | P0 |
| **Gender** | Male/Female/Other | P0 |
| **Appearance** | Face, hair, skin tone, features | P0 |
| **Starting Class** | Initial class choice | P0 |
| **Bind Point** | Choose starting town as respawn | P0 |

### 5.2 Class System

| Feature | Description | Priority |
|---------|-------------|----------|
| **Base Classes** | Warrior, Mage, Rogue, Priest, Ranger | P0 |
| **Hybrid Classes** | Paladin (Warrior/Priest), etc | P1 |
| **Advanced Classes** | Tier 2/3 specialization | P1 |
| **Class Skills** | 20-30 skills per class | P0 |
| **Skill Trees** | Point allocation for specialization | P0 |
| **Dual Class** | Play as two classes (limited) | P2 |

### 5.3 Leveling & Progression

| Feature | Description | Priority |
|---------|-------------|----------|
| **Experience System** | XP from kills, quests, exploration | P0 |
| **Level Cap** | Starting cap, expandable | P0 |
| **Skill Points** | Earn per level to unlock skills | P0 |
| **Attribute Points** | Earn per level to boost stats | P0 |
| **Death Penalty** | XP debt, reduced XP until recovered | P0 |

### 5.4 Inventory & Equipment

| Feature | Description | Priority |
|---------|-------------|----------|
| **Equipment Slots** | Head, Chest, Hands, Legs, Feet, Main Hand, Off Hand, Rings, Neck | P0 |
| **Backpack** | Grid-based inventory (24-36 slots) | P0 |
| **Bank** | Shared storage at towns | P0 |
| **Bag System** | Expandable bags with more slots | P0 |
| **Loot Filtering** | Auto-sort, stack similar items | P1 |
| **Equipment Comparison** | Show stat diff when hovering new item | P0 |

### 5.5 Player Open Questions

- [ ] How many levels? (50? 100?)
- [ ] Free respec or paid? Limited respec?
- [ ] Bind on pickup vs bind on equip?

---

## 6. Economy & Crafting

> **In Progress:** Resource gathering, crafting professions, player-driven economy.

### 6.1 Gathering System

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

### 6.2 Crafting Professions

| Feature | Description | Priority |
|---------|-------------|----------|
| **Blacksmithing** | Weapons, armor, metal goods | P0 |
| **Tailoring** | Cloth/leather armor | P0 |
| **Alchemy** | Potions, elixirs, poisons | P0 |
| **Enchanting** | Add magical properties to gear | P1 |
| **Engineering** | Gadgets, explosives, devices | P1 |
| **Cooking** | Food buffs | P1 |
| **Crafting Recipes** | Discovered or purchased | P0 |
| **Crafting Quality** | Normal, Fine, Masterwork tiers | P0 |

### 6.3 Player Economy

| Feature | Description | Priority |
|---------|-------------|----------|
| **Currency** | Gold coin standard | P0 |
| **Dropped Loot** | Items drop from mobs | P0 |
| **Player Trading** | Direct trade between players | P0 |
| **Player Shops** | Rent vendor stalls in towns | P1 |
| **Auction House** | Central marketplace (with tax) | P1 |
| **Item Degradation** | Gear loses durability, repairs needed | P0 |
| **Item Sinks** | Repairs, taxes, crafting costs | P0 |
| **Player Merchants** | NPC merchants buy/sell | P0 |

### 6.4 Economy Open Questions

- [ ] Crafted vs dropped item balance?
- [ ] Gold cap per player?
- [ ] Real-money trading policy?

---

## 7. Player Housing

> **In Progress:** Placement, customization, functionality.

### 7.1 Housing Features

| Feature | Description | Priority |
|---------|-------------|----------|
| **Placement System** | Choose plot in designated zones | P1 |
| **House Types** | Small, medium, large, mansion | P1 |
| **Interior Customization** | Furniture, decorations, trophies | P1 |
| **Exterior Customization** | House skin, garden, mounts displayed | P1 |
| **Storage** | Additional chest space at home | P1 |
| **Crafting Stations** | Functional workbenches at home | P1 |
| **Teleport Home** | Easy recall to house | P1 |
| **Guild Houses** | Shared guild housing | P2 |

### 7.2 Housing Open Questions

- [ ] Instanced vs shared world housing?
- [ ] Housing demolition/relocation?
- [ ] Housing permissions (friends, guild)?

---

## 8. PvP Systems

> **In Progress:** Zone types, full loot, guild wars.

### 8.1 Zone Types

| Feature | Description | Priority |
|---------|-------------|----------|
| **Safe Zones** | Towns, starting areas — no PvP | P0 |
| **Contested Zones** | PvP enabled, no full loot | P0 |
| **PvP Zones** | Full loot enabled | P0 |
| **Arena/PvP Battlegrounds** | Structured PvP content | P1 |
| **Guild War System** | Declare war, territory control | P1 |

### 8.2 Full Loot Mechanics

| Feature | Description | Priority |
|---------|-------------|----------|
| **Death Drop** | Lose equipped items on death | P0 |
| **Drop Protection** | Some items protected (bind on pickup) | P0 |
| **Bag Drop** | Chance to drop inventory items | P0 |
| **PvP Kills Credit** | Last hit gets loot rights | P0 |
| **Revenge System** | Kill a ganker for bonus loot | P1 |

### 8.3 PvP Open Questions

- [ ] Level bracket restrictions for PvP?
- [ ] Karma/reputation system for PKers?
- [ ] World PvP incentives vs pure griefing?

---

## 9. Social & Guild Systems

### 9.1 Communication

| Feature | Description | Priority |
|---------|-------------|----------|
| **Global Chat** | Shout to zone | P0 |
| **Whisper/PM** | Private messaging | P0 |
| **Party Chat** | Group-only chat | P0 |
| **Guild Chat** | Guild-only chat | P0 |
| **Local/NPC Interaction** | Click NPCs for dialogue | P0 |
| **Emotes** | Social emotes | P1 |

### 9.2 Grouping

| Feature | Description | Priority |
|---------|-------------|----------|
| **Party Formation** | Invite, join, kick | P0 |
| **Party Size** | Standard 5, raid 20? | P0 |
| **Loot Distribution** | Free-for-all, round-robin, loot council | P0 |
| **Party Finder** | Automated group finder | P1 |
| **Mentoring** | Higher level helps lower | P1 |

### 9.3 Guilds

| Feature | Description | Priority |
|---------|-------------|----------|
| **Guild Creation** | Form guild with name, tag | P0 |
| **Guild Ranks** | Customizable roles/permissions | P0 |
| **Guild Bank** | Shared storage | P0 |
| **Guild Upgrades** | Guild hall, buffs, perks | P1 |
| **Guild Wars** | Declare on other guilds | P1 |
| **Alliance** | Multiple guilds allied | P2 |

---

## 10. Technical Architecture

> **Decided (2026-08-30):** Godot 4.7.2 chosen for open source,
> lightweight, no royalties, and strong 3D support. The
> architecture is now four layers: **Godot client → Multi-iso
> orchestrator → State tree (content-hash) → Postgres + cache**.
> The frame is the orchestrator + state tree, liftable to its own
> project.

### 10.1 Engine Selection

| Option | Pros | Cons | Status |
|--------|------|------|--------|
| **Godot 4.7.2** | Open source (MIT), lightweight, no royalties, strong 3D, GDScript | Smaller ecosystem than Unity | ✅ **CHOSEN** |
| **Unity** | Industry standard, great mobile support, large asset store | License fees after revenue | ❌ Not chosen |
| **Unreal 5** | Powerful graphics, Blueprints | Heavy for mobile, complex | ❌ Not chosen |

**Key Godot Features Used:**
- GDScript for game logic
- Godot 4.x scene system (`.tscn`)
- ENet for multiplayer
- `var_to_bytes` / `bytes_to_var` for network serialization
- Physics3D for collision
- Headless server mode for dedicated servers
- `@tool` scripts for editor-time content

### 10.2 Client Architecture

| Component | Description |
|------------|-------------|
| **UI (Islands)** | Each UI panel is a PackedScene with an `IslandPlaceholder` root. Mounted by `IslandManager` from a static `IslandRegistry`. Replaces the old monolithic UIPanel base. POC shipped. |
| **UI (HUD / Widgets)** | Separate `UIWidget` base (sibling to UIPanel) for in-world overlays: health bar, target frame, buff bar. Not islands. |
| **State (client side)** | The client holds a (possibly divergent) state tree, the same shape as the server's. Predicted inputs locally; reconciled by hash diff from server. |
| **Rendering** | Standard Godot 3D pipeline. LOD on graphics is independent of LOD on state. |
| **Input** | Touch-first (mobile), keyboard/mouse on PC. Both go through a unified action layer. |

### 10.3 Server Architecture

| Component | Description | Priority |
|-----------|-------------|----------|
| **Auth Server** | Login, account creation | P0 |
| **Game Server** | Authoritative game world simulation | P0 |
| **Multi-Iso Orchestrator** | Multi-dimensional state queries (spatial ∩ faction ∩ temporal ∩ social). The control plane for the state tree. See [`multi-iso-frame.md`](../../synmergia/docs/architecture/multi-iso-frame.md). | P0 |
| **State Tree (content-hash)** | Each entity is a content-hashed node. Server tick = re-rooting the tree. Client sync = diff between hashes. See section 10.7. | P0 |
| **Snapshot Store (Postgres)** | `state_snapshots` table persists root hashes. Lazy load on restart. | P0 |
| **Cache Layer (in-memory)** | LRU-backed materialized intersection tables for hot queries. See [`multi-iso-lod-prediction.md`](../../synmergia/docs/architecture/multi-iso-lod-prediction.md). | P0 |
| **Message Queue** | Handle real-time messages | P0 |
| **Load Balancer** | Distribute players across servers | P0 |
| **Anti-Cheat** | Server-side validation, hash-chain tick verification | P0 |
| **CDN** | Asset distribution by content-hash | P1 |

### 10.4 Networking

| Feature | Description | Priority |
|---------|-------------|----------|
| **Protocol** | UDP for game state, TCP for reliable (auth, inventory) | P0 |
| **Client Prediction** | Smooth movement despite latency | P0 |
| **Server Reconciliation** | Rollback to known-good hash, apply patch | P0 |
| **Lag Compensation** | Fair hit detection with latency | P0 |
| **Interest Management** | Only sync nearby entities (use icosahedral adjacency) | P0 |
| **Tick Rate** | Server update frequency (10-60 Hz) | P0 |
| **State Diff (the new bit)** | Server sends root hash + diff, not full state. Bandwidth = O(diff size), not O(state size). | P0 |
| **P2P Entity Sync (optional)** | Nearby players gossip via hash-set reconciliation. Reduces server load. The "assimilation" piece. | P2 |

### 10.5 Database Design

| Concern | Storage | Notes |
|---------|---------|-------|
| **Durable state** | Postgres (rows for entities, snapshots for root hashes) | Single source of truth. |
| **Hot path** | In-memory state tree (content-hash nodes) | Re-built from Postgres on restart. |
| **Intersection cache** | LRU of (axis_combo) → entity_set | Bounded, evicts cold combos. |
| **Save games** | Content-hashed tree, diff between versions | Patchable, tamper-detectable. |
| **Item templates** | Content-hashed | Cross-shard dedup via hash equality. |
| **Assets** | Content-hashed pck + CDN | Old clients can still find old assets on update. |

### 10.6 The State Tree (the redis-like layer)

This is the foundation of Track A Session A-3. The state tree is a
content-addressed tree where:

- Every node has a `hash` (SHA-256 of its serialized value)
- Two systems with the same hash have the same subtree
- `diff(old_root, new_root)` returns a list of `(path, new_hash, value)` entries
- `apply_diff(root, diff)` returns the new root
- Server tick = re-rooting the tree with new state
- Client sync = `apply_diff(my_root, server_diff)` → new_root

**Why this matters for the PRD**: every "interesting" state
question ("is the player still alive?", "do we have this item
template?", "is this region the same as yesterday?") becomes a
hash equality check. The frame extracts this into
`labs/multi-iso/kv/state_tree.gd`.

### 10.7 The Multi-Iso Orchestrator (the frame core)

A controller layer above the state tree. Multiple icosahedral
"isos" (one per axis: spatial, factional, temporal, social) are
projections of the same world. Multi-dimensional queries become
intersections: `query(region, faction, time) =
iso_spatial[region] ∩ iso_faction[faction] ∩ iso_temporal[time]`.

**Materialized intersection tables** (LRU cache) make the
intersection O(1) for hot queries.

**LOD pyramid** (full / summary / cold / archived) lets inactive
regions serialize and unload.

**Predictive prefetch** (Markov over temporal patterns)
pre-loads regions before the player arrives.

**Fused mode** is the default: each entity's state record
contains its axis coordinates. The geometry integrates with
state, not a separate layer.

Full design in
[`multi-iso-frame.md`](../../synmergia/docs/architecture/multi-iso-frame.md)
(Part 1) and
[`multi-iso-lod-prediction.md`](../../synmergia/docs/architecture/multi-iso-lod-prediction.md)
(Part 2).

### 10.8 NSC-9 Reserved Space Identifiers

Every entity has a 12-digit NSC-9 code that encodes its axis
membership:

```
9-AAA-BBB-CCCCCC
  │   │    └──── sequence within axis (16M)
  │   └───────── axis reservation (1000 axes)
  └───────────── facility
```

Axis ranges are administratively reserved:

- `001-099` spatial
- `100-199` factional
- `200-299` temporal
- `300-399` social
- `400-499` game-specific
- `500-999` free for new axes

The barcode IS the multi-dimensional index. Two entities with the
same NSC-9 code (within their axis) are the same entity.

### 10.9 DevOps

| Feature | Description | Priority |
|---------|-------------|----------|
| **CI/CD Pipeline** | Automated builds, testing | P0 |

> ⚠️ **Note:** CI is currently disabled
> (`.github/workflows/godot-ci.yml.disabled`). Re-enable when a
> playable slice exists. See `ROADMAP.md` → Phase 8: Launch
> Readiness → "Enable CI/CD Pipeline".
| **Server Hosting** | Cloud provider (AWS/GCP/Azure) | P0 |
| **Monitoring** | Player counts, server health, intersection cache hit rate | P0 |
| **Analytics** | Track player behavior, economy, prediction accuracy | P1 |
| **Auto-scaling** | Respond to player load; prefetch more on scale-up | P1 |

---

## 11. Art & Audio Direction

### 11.1 Visual Style

| Aspect | Description | Priority |
|--------|-------------|----------|
| **Art Style** | Realistic but stylized (not photorealistic) | P0 |
| **Lighting** | Dynamic day/night cycle | P0 |
| **Weather** | Rain, snow, fog effects | P1 |
| **Character Art** | Humanoid with distinct silhouettes | P0 |
| **Environment Art** | Modular tilesets for buildings, terrain | P0 |
| **VFX** | Spell effects, hit impacts | P0 |

### 11.2 Quality Tiers

| Tier | Target Devices | Settings | Priority |
|------|---------------|----------|----------|
| **Low** | Budget phones, 2GB RAM | Reduced draw distance, simpler shaders | P0 |
| **Medium** | Mid-range phones | Balanced quality | P0 |
| **High** | Flagship phones, PC | Max quality | P0 |
| **Ultra** | PC only | Maximum effects | P1 |

### 11.3 Audio

| Feature | Description | Priority |
|---------|-------------|----------|
| **Sound Effects** | Combat, environment, UI | P0 |
| **Music** | Ambient, combat, town themes | P0 |
| **Spatial Audio** | 3D positioned sounds | P1 |
| **Voice Acting** | NPC dialogue (optional) | P2 |

---

## 12. Mobile Optimization

### 12.1 Touch Controls

| Feature | Description | Priority |
|---------|-------------|----------|
| **Virtual Joystick** | Left side, configurable opacity | P0 |
| **Camera Control** | Right side drag to rotate | P0 |
| **Skill Buttons** | Bottom of screen, customizable | P0 |
| **Targeting** | Tap enemy to select | P0 |
| **Auto-Run** | Toggle for long travel | P1 |
| **Gesture Support** | Double tap, long press | P1 |

### 12.2 UI Scaling

| Feature | Description | Priority |
|---------|-------------|----------|
| **Screen Sizes** | Support phones and tablets | P0 |
| **Notch Handling** | Safe areas for modern phones | P0 |
| **UI Scaling** | Adjustable UI element size | P1 |
| **Colorblind Mode** | Accessibility options | P1 |

### 12.3 Performance Targets

| Metric | Target | Priority |
|--------|--------|----------|
| **Frame Rate** | 30 FPS minimum, 60 FPS target | P0 |
| **Load Times** | < 30 seconds on fast 3G | P0 |
| **Memory** | < 2GB RAM usage | P0 |
| **Battery** | Optimized drain, frame cap option | P1 |

---

## 13. Phases & Milestones

> **Modernized 2026-08-30:** Phases are now aligned with the
> **Track A** (product) and **Track B** (frame research) plan in
> [`NEXT-AGENT-PICKUP.md`](../../synmergia/docs/architecture/NEXT-AGENT-PICKUP.md).
> Track A ships the game. Track B develops the frame in parallel.

### Phase 0: Foundation ✅ COMPLETE
- [x] Complete PRD
- [x] Choose engine (Godot 4.7.2)
- [x] Set up dev environment
- [x] Architecture decisions (services, components, .tres)
- [x] Initial combat/skill systems implemented
- [x] ROADMAP.md created for tracking
- [x] AGENTS.md conventions

### Phase 0.5: UI Modernization + Islands POC ✅ COMPLETE
- [x] UIPanel migration (commit `d25ad67`)
- [x] Islands POC shipped (commit `3e942bb`)
- [x] 19/19 islands tests passing
- [x] NEXT-AGENT-PICKUP doc for crash survival
- [x] Multi-iso orchestrator design (Part 1 + Part 2)
- [x] `/labs/` directory convention (frame staging area)
- [x] Modernized PRD (this file)

### Phase 0.6: Cleanup 🔄 IN PROGRESS
- [ ] Fix pre-existing parse errors project-wide
- [ ] Replace `GameConfig.*` with `_get_config_*` helpers
- [ ] Add static shims for autoloads with `class_name`
- [ ] Clean lint warnings
- [ ] Add `.uid` and `tools/` to `.gitignore` (mostly done)
- [ ] Fix `inventory_component.gd` unindent
- [ ] Create separate `UIWidget` base for HUD/widgets

### Phase 1: State Tree + Track A Foundation (NEXT)
- [ ] **A-2**: Migrate remaining UIPanels to islands
- [ ] **A-3**: State tree (content-hash, diff, sync) → `labs/multi-iso/kv/state_tree.gd`
- [ ] **A-4**: Save games as content-hashed trees
- [ ] **A-5**: Item template content-hash (cross-shard dedup)
- [ ] **A-6**: Asset addressing (pck + CDN by hash)
- [ ] **A-7**: Build pipeline (`tools/build.sh`)

### Phase 2: Vertical Slice (MVP)
- [ ] Single playable zone
- [ ] Basic movement + camera
- [ ] One class with 5-10 skills
- [ ] 3 enemy types
- [ ] Basic combat loop
- [ ] Touch controls working
- [ ] Mobile build (APK/IPA)
- [ ] State tree driving the game state

### Phase 3: Core Loop
- [ ] All movement mechanics (dodge, swim, etc)
- [ ] 3+ classes
- [ ] 20+ skills
- [ ] 3+ zones
- [ ] Basic crafting
- [ ] Basic inventory
- [ ] Basic PvP in one zone

### Phase 4: Track B (parallel to Phases 2-3)
- [ ] **B-1**: Math primitives (NSC-9, icosahedral, quasicrystal) → `labs/multi-iso/math/`
- [ ] **B-2**: Single-axis orchestrator → `labs/multi-iso/srv/axis.gd`
- [ ] **B-3**: Multi-axis intersection
- [ ] **B-4**: NSC-9 axis reservation → `axis_registry.gd`
- [ ] **B-5**: Orchestrator + frame glue
- [ ] **B-6**: Materialized intersection tables (LRU cache)
- [ ] **B-7**: LOD pyramid (4 levels)
- [ ] **B-8**: Predictive prefetch (Markov)
- [ ] **B-9**: Performance budget (GDScript vs NativeScript C++ vs server)
- [ ] **B-10**: Frame extraction (alongside vant)

### Phase 5: World Building
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

### Phase 7: Frame Extraction + Polish
- [ ] **B-10**: Frame extracts to its own project (alongside vant)
- [ ] Synmergia becomes an example consumer
- [ ] Frame documentation for external users
- [ ] Optimization pass on the frame
- [ ] Bug fixes
- [ ] Balance tuning

### Phase 8: Launch
- [ ] Mobile-first launch (Android + iOS)
- [ ] PC launch
- [ ] Launch marketing
- [ ] Community building
- [ ] Re-enable CI/CD pipeline

---

## 14. Open Questions

> **Modernized 2026-08-30:** Many questions answered. The new
> architecture has changed what we're asking.

### Resolved

1. ~~**Engine Choice:**~~ → ✅ Godot 4.7.2
2. ~~**Server Hosting:**~~ → Official servers planned (cloud TBD)
3. ~~**PC Support:**~~ → ✅ PC support from day 1 (same Godot build)
4. ~~**Aggro:**~~ → Proximity-based, configurable detection, level-gated XP (see section 3.8)
5. ~~**PvP combat differences:**~~ → CC reduction, gear-differential damage modifiers (tunable)
6. **Architecture (the big one):** → State tree + multi-iso orchestrator + content-hash layer. See section 10.
7. **Networking serialization:** → `var_to_bytes` / `bytes_to_var` (Godot 4.x idiom)

### Open

8. **Scale:** How many players per server?
   - LOD pyramid + intersection cache can carry a lot. 500+ is plausible. 1000+ needs the frame's perf budget answered first.
9. **Level Cap:** 60 levels planned. Expandable.
10. **Art Assets:** AI generation, purchase, custom? TBD.
11. **Real Money:** Cosmetics shop planned. Subscription unlikely. RMT banned, no third-party.
12. **Platform Priority:** Simultaneous Android + iOS via Godot exports.
13. **Loading screens:** Zone transitions? Seamless? Open world with portal? Depends on the multi-iso orchestrator's spatial axis.
14. **Frame extraction timeline:** When does the frame spin out to its own repo? After Phase 7? Earlier?
15. **Performance budget:** GDScript enough? NativeScript C++? Standalone C++ server? Decided in Track B Session B-9.
16. **Build pipeline shape:** Bash? Godot CLI? CI step? Custom tool? Session A-7.

---

## Development Tracking

📋 **See [ROADMAP.md](../../ROADMAP.md)** for implementation
progress and technical details. The ROADMAP maps PRD features to
actual code files and tracks completion status.

The architecture is in `docs/architecture/`:

- [multi-iso-frame.md](../../synmergia/docs/architecture/multi-iso-frame.md)
- [multi-iso-lod-prediction.md](../../synmergia/docs/architecture/multi-iso-lod-prediction.md)
- [labs-organization.md](../../synmergia/docs/architecture/labs-organization.md)
- [nsc9-honest-evaluation.md](../../synmergia/docs/architecture/nsc9-honest-evaluation.md)
- [NEXT-AGENT-PICKUP.md](../../synmergia/docs/architecture/NEXT-AGENT-PICKUP.md)

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
| **Scope creep** (frame research distracts from product) | High | Track A is non-negotiable; Track B is research that may not pan out. |
| **Performance** (state tree + orchestrator too slow at 10K entities) | Medium | B-9 budget. Fall back to NativeScript C++ for the hot path. |
| **Godot 4.7 stability** (4.7 is recent; bugs in the engine) | Medium | Pin version. Test against the headless server mode. |
| **Mobile build size** (Godot exports bloat with all features) | Medium | Asset content-hash → only what the player needs. A-6. |
| **Anti-cheat** (state tree hashes are forgeable) | High | Server-side hash chain. Each tick is signed by previous. |
| **Frame over-engineering** (build abstractions no game uses) | Medium | Frame is a byproduct of game work, not a goal. If no game needs it, it doesn't extract. |

### D. Frame Appendix

> This is the part of the PRD that describes the **frame** —
> what could be extracted from Synmergia and shipped as its own
> project. The frame is the part that any future game on this
> architecture would consume.

**The frame is the union of:**

1. **State tree** (`labs/multi-iso/kv/state_tree.gd`) — content-hash, diff, sync
2. **Content hash** (`labs/multi-iso/kv/content_hash.gd`) — SHA-256 wrapper
3. **LRU cache** (`labs/multi-iso/kv/lru_cache.gd`) — generic LRU
4. **Multi-iso orchestrator** (`labs/multi-iso/srv/axis.gd` + `axis_registry.gd` + `composite_table.gd`)
5. **Materialized intersection tables** (`labs/multi-iso/srv/composite_table.gd`)
6. **LOD manager** (`labs/multi-iso/srv/lod_manager.gd`)
7. **Predictor + prefetcher** (`labs/multi-iso/srv/predictor.gd` + `prefetcher.gd`)
8. **Markov chain** (`labs/multi-iso/srv/markov.gd`)
9. **Math primitives** (`labs/multi-iso/math/nsc9.gd` + `icosahedral.gd` + `quasicrystal.gd`)
10. **Snapshot store** (`labs/multi-iso/db/snapshot_store.gd`)

**The frame is NOT:**

- The game itself (services, components, scenes, assets)
- The Godot client (rendering, input, UI)
- The Postgres schema (specific to Synmergia's data)
- The autoload singleton pattern (specific to Godot)

**Why the frame matters:**

A new game on this frame would write:

```gdscript
# 1. Define axes
var spatial = SpatialAxis.new(depth=8)
var faction = FactionAxis.new()
var orchestrator = Orchestrator.new([spatial, faction])

# 2. Insert entities
orchestrator.insert(entity_id, axis_coords)

# 3. Query
var result = orchestrator.query({
    "spatial": region_aabb,
    "faction": guild_id
})
# result is materialized intersection — O(1) if cached, O(n) otherwise
```

That's it. No global state, no autoload, no GameManager
dependency. The orchestrator is the entire API.

**The "could pioneer" outcome:**

If the frame works for Synmergia, it works for any state-heavy
multiplayer game. The frame extracts to its own project
(alongside vant). Synmergia becomes the example game. Other
games can build on the same primitives, getting multi-dim
queries, content-hash sync, and predictive LOD for free.

The frame is the lever. The game is the proof.
