# Synmergia — Open World MMORPG

> **Vision:** A 3D open-world MMORPG inspired by Risk Your Life 2 (RYL2) combat/action mechanics, infused with the depth and player-driven economy of Ultima Online. Mobile-first (Android/iOS), with PC support.

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

---

## 1. Executive Summary

**Synmergia** is a 3D open-world MMORPG targeting mobile (Android/iOS) with PC support. The game combines RYL2's fast-paced, free-form action combat with Ultima Online's depth of player-driven economy, housing, and world interaction.

**Core Loop:** Explore vast world → Fight enemies/dungeons → Craft gear → Build houses → Participate in PvP → Repeat

**Target Audience:**
- MMORPG players who miss the depth of UO/EVE-era games
- Mobile gamers who want console-quality action combat on the go
- Players who enjoy crafting, housing, and player economies over theme-park content

**Competitive Landscape:**
- Similar to: RYL2 (combat feel), UO (economy/housing), Black Desert (action combat), Albion Online (full loot PvP)
- Differentiator: Mobile-first with full MMO depth, not a stripped-down mobile port

**Development Approach:**
- Agent-assisted development using LLMs for code generation
- Incremental feature delivery with continuous integration
- Godot 4.2+ for cross-platform deployment

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

> **Decided:** Godot 4.2+ chosen for open source, lightweight, no royalties, and strong 3D support in 4.x versions.

### 10.1 Engine Selection

| Option | Pros | Cons | Status |
|--------|------|------|--------|
| **Godot 4.2+** | Open source (MIT), lightweight, no royalties, strong 3D, GDScript | Smaller ecosystem than Unity | ✅ **CHOSEN** |
| **Unity** | Industry standard, great mobile support, large asset store | License fees after revenue | ❌ Not chosen |
| **Unreal 5** | Powerful graphics, Blueprints | Heavy for mobile, complex | ❌ Not chosen |

**Key Godot Features Used:**
- GDScript for game logic
- Godot 4.x scene system (`.tscn`)
- ENet for multiplayer
- VarToStr for network serialization
- Physics3D for collision
- Headless server mode for dedicated servers

### 10.2 Client Architecture

*To be filled: Rendering pipeline, asset management, input handling, UI framework.*

### 10.3 Server Architecture

| Component | Description | Priority |
|-----------|-------------|----------|
| **Auth Server** | Login, account creation | P0 |
| **Game Server** | Authoritative game world simulation | P0 |
| **Message Queue** | Handle real-time messages | P0 |
| **Database** | Player data, world state persistence | P0 |
| **Cache Layer** | Redis for session data | P0 |
| **Load Balancer** | Distribute players across servers | P0 |
| **Anti-Cheat** | Server-side validation, detection | P0 |
| **CDN** | Asset distribution | P0 |

### 10.4 Networking

| Feature | Description | Priority |
|---------|-------------|----------|
| **Protocol** | TCP, UDP, or hybrid (UDP for game, TCP for reliable) | P0 |
| **Client Prediction** | Smooth movement despite latency | P0 |
| **Server Reconciliation** | Correct mispredicted states | P0 |
| **Lag Compensation** | Fair hit detection with latency | P0 |
| **Interest Management** | Only sync nearby entities | P0 |
| **Tick Rate** | Server update frequency (10-60 Hz) | P0 |

### 10.5 Database Design

*To be filled: Schema for players, characters, inventory, world state.*

### 10.6 DevOps

| Feature | Description | Priority |
|---------|-------------|----------|
| **CI/CD Pipeline** | Automated builds, testing | P0 |

> ⚠️ **Note:** CI is currently disabled (`.github/workflows/godot-ci.yml.disabled`). Re-enable when a playable slice exists. See `ROADMAP.md` → Phase 8: Launch Readiness → "Enable CI/CD Pipeline".
| **Server Hosting** | Cloud provider (AWS/GCP/Azure) | P0 |
| **Monitoring** | Player counts, server health | P0 |
| **Analytics** | Track player behavior, economy | P1 |
| **Auto-scaling** | Respond to player load | P1 |

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

### Phase 0: Foundation ✅ COMPLETE
- [x] Complete PRD
- [x] Choose engine (Godot 4.2+)
- [x] Set up dev environment
- [x] Architecture decisions
- [x] Initial combat/skill systems implemented
- [x] ROADMAP.md created for tracking

### Phase 1: Vertical Slice (MVP)
- [ ] Single playable zone
- [ ] Basic movement + camera
- [ ] One class with 5-10 skills
- [ ] 3 enemy types
- [ ] Basic combat loop
- [ ] Touch controls working
- [ ] Mobile build (APK/IPA)

### Phase 2: Core Loop
- [ ] All movement mechanics (dodge, swim, etc)
- [ ] 3+ classes
- [ ] 20+ skills
- [ ] 3+ zones
- [ ] Basic crafting
- [ ] Basic inventory
- [ ] Basic PvP in one zone

### Phase 3: World Building
- [ ] 5+ zones
- [ ] Dungeons (2-3)
- [ ] Full crafting system
- [ ] Player housing (basic)
- [ ] Guild system
- [ ] Auction house
- [ ] Server infrastructure

### Phase 4: MMO Features
- [ ] Full world population
- [ ] Player economy
- [ ] Full loot PvP zones
- [ ] Guild wars
- [ ] World events
- [ ] Anti-cheat

### Phase 5: Polish & Launch
- [ ] Optimization pass
- [ ] Bug fixes
- [ ] Balance tuning
- [ ] Launch marketing
- [ ] Community building

---

## 14. Open Questions

> **ANSWERED:** Most questions have been addressed.

1. ~~**Engine Choice:**~~ → ✅ Godot 4.2+ chosen
2. ~~**Server Hosting:**~~ → Official servers planned
3. **Scale:** How many players per server? (50? 500?) → TBD
4. **Level Cap:** What level range? (50, 100, no cap?) → 60 levels planned
5. **Art Assets:** AI generation, purchase, custom? → TBD
6. **Real Money:** RMT policy? (subscriptions, cosmetics, nothing?) → Cosmetics shop planned
7. **Platform Priority:** Android first, iOS later, or simultaneous? → Simultaneous with Godot exports
8. ~~**PC Support:**~~ → ✅ PC support from day 1 (same Godot build)

---

## Development Tracking

📋 **See [ROADMAP.md](./ROADMAP.md)** for implementation progress and technical details.

The ROADMAP maps PRD features to actual code files and tracks completion status.

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
*To be filled: Technical risks, scope risks, market risks.*
