# World Smith — Open World MMORPG

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

*To be filled: High-level description of the game, target audience, competitive landscape, and development approach.*

---

## 2. Core Game Pillars

*To be filled: The 3-5 foundational principles that define the game experience.*

---

## 3. Combat Systems

> **Lead:** RYL2-inspired action combat with tab-targeting hybrid. Fast-paced, mobile-optimized, skill-based with depth for PvP.

### 3.1 Design Philosophy

The combat system combines the **action-oriented feel of RYL2** with **accessibility for touch controls**:

1. **Responsive** — Every input produces immediate visual feedback
2. **Skillful** — Timing, positioning, and build optimization matter
3. **Readable** — Clear visual/audio cues for all combat events
4. **Mobile-first** — Touch controls as capable as keyboard/mouse

### 3.2 Movement System

#### 3.2.1 Camera
| Feature | Specification | Notes |
|---------|--------------|-------|
| **Type** | 3rd person, over-shoulder | Similar to RYL2 |
| **Distance** | Adjustable 3-10 units via pinch/scroll | Default: 6 units |
| **Height** | Slightly above character head | Smooth follow |
| **Rotation** | 360° horizontal, 30°-80° vertical clamp | Right-drag to rotate |
| **Auto-Follow** | Camera smoothly tracks behind player | Can be toggled |

#### 3.2.2 Movement Actions
| Skill | Keybind | Stamina Cost | Cooldown | Description |
|-------|---------|--------------|----------|-------------|
| **Walk** | WASD/Joystick | 0 | - | Base movement speed |
| **Sprint** | Hold Shift | 5/sec | - | 50% faster, drains stamina |
| **Jump** | Space | 0 | - | Small hop, clears small obstacles |
| **Dodge Roll** | Q or Double-tap dir | 25 | 1.5s | Quick evading roll with 0.3s i-frames |
| **Swim** | Walk into water | 2/sec | - | 50% land speed in water |
| **Knockback Recovery** | Auto | - | - | Brief stun after knockback, then recovery |

#### 3.2.3 Movement Stats
| Stat | Effect | Scaling |
|------|--------|----------|
| **Move Speed** | Base 5 units/sec | +% from gear/traits |
| **Sprint Speed** | 7.5 units/sec | - |
| **Swim Speed** | 2.5 units/sec | - |
| **Jump Height** | 2 units | Fixed |
| **Dodge Distance** | 3 units | Fixed |
| **Stamina Regen** | 10/sec out of combat, 3/sec in combat | +% from gear |

### 3.3 Targeting System

#### 3.3.1 Target Acquisition
| Method | Input | Behavior |
|--------|-------|----------|
| **Tap Target** | Tap enemy on screen | Selects enemy if within range |
| **Tab Target** | Tab key / Tap enemy nameplate | Cycles through enemies in front of player |
| **Friend Tab** | Shift+Tab | Cycles through allies in range |
| **Soft Target** | Hover/touch and hold | Shows ground-targeting reticle |
| **Lock Target** | Double-tap Tab | Locks current target, keeps focus |

#### 3.3.2 Target Info Display
```
┌─────────────────────────────────────────┐
│  [Boss Icon] Great Wraith of Karath     │  ← Name + Elite/Boss indicator
│  Level 35  ████████████░░░░  12,450/15k │  ← Health bar with numbers
│  [Frost Giant]  [Stunned 2s]            │  ← Debuffs/Status
└─────────────────────────────────────────┘
```

#### 3.3.3 Target Range Rules
| Target Type | Max Range | Notes |
|-------------|-----------|-------|
| Melee | 2 units | Auto-attack range |
| Melee Skills | 2.5 units | Most melee abilities |
| Ranged Physical | 25 units | Bow, crossbow |
| Ranged Magic | 30 units | Spells |
| Ground AoE | 40 units | Placed zones |
| Friendly Range | 30 units | Heals, buffs |

### 3.4 Resource System

#### 3.4.1 Health (HP)
| Property | Value |
|----------|-------|
| **Base HP (Level 1)** | 500 |
| **HP per Level** | +50 |
| **HP per Vitality** | +10% of base |
| **Regen (OOC)** | 5% HP/sec |
| **Regen (Combat)** | 1% HP/sec |
| **Death Trigger** | HP ≤ 0 |

#### 3.4.2 Mana (MP)
| Property | Value |
|----------|-------|
| **Base MP (Level 1)** | 200 |
| **MP per Level** | +30 |
| **MP per Intelligence** | +8% of base |
| **Regen (OOC)** | 10% MP/sec |
| **Regen (Combat)** | 2% MP/sec |
| **OOM Behavior** | Skills grayed out, no cast |

#### 3.4.3 Stamina (STA)
| Property | Value |
|----------|-------|
| **Base Stamina** | 100 (fixed pool) |
| **Regen** | 10/sec OOC, 3/sec Combat |
| **Dodge Cost** | 25 |
| **Sprint Cost** | 5/sec |
| **Heavy Attack Cost** | 15 |
| **Empty Behavior** | Cannot dodge/sprint, slower regen |

### 3.5 Stats & Attributes

#### 3.5.1 Primary Attributes
| Stat | Abbreviation | Effect per Point |
|------|--------------|------------------|
| **Strength** | STR | +2% physical damage, +50 carry weight |
| **Agility** | AGI | +1% attack speed, +0.5% dodge, +0.3% crit |
| **Intelligence** | INT | +3% magic damage, +8% max mana |
| **Vitality** | VIT | +10% max health, +2% physical defense |
| **Endurance** | END | +5% max stamina, +5% stamina regen |
| **Wisdom** | WIS | +8% mana regen, +5% buff duration |

#### 3.5.2 Secondary Stats (Derived)
| Stat | Calculation | Cap |
|------|-------------|-----|
| **Physical Damage** | Base + (STR × 2%) + weapon bonus | - |
| **Magic Damage** | Base + (INT × 3%) + staff bonus | - |
| **Attack Speed** | Base (1.0/s) × (1 + AGI%) × (1 + gear%) | 2.0/s max |
| **Crit Chance** | 5% base + (AGI × 0.3%) + (gear%) | 50% max |
| **Crit Damage** | 150% base + (gear%) | 250% max |
| **Dodge** | 3% base + (AGI × 0.5%) + (gear%) | 40% max |
| **Physical Defense** | (VIT × 2%) + (armor contribution) | 75% DR max |
| **Magic Defense** | 10% base + (gear%) | 50% DR max |

#### 3.5.3 Damage Calculation
```
Final Damage = (Base Damage × Skill Multiplier) × (1 + Damage%) × (1 - Defense%)
```

### 3.6 Skill System

#### 3.6.1 Hotbar Layout
```
┌─────────────────────────────────────────────────────────────────┐
│  [1] [2] [3] [4] [5]  |  [SHIFT+1] [SHIFT+2] [SHIFT+3] [SHIFT+4] [SHIFT+5]  │
│                                                                 │
│  [6] [7] [8] [9] [0]  |  [SHIFT+6] [SHIFT+7] [SHIFT+8] [SHIFT+9] [SHIFT+0]  │
│                           ↓                                      │
│                      (Shifted = Alt Bar)                         │
└─────────────────────────────────────────────────────────────────┘
```
- **10 slots per bar**, 2 bars (toggle with `)
- Skills 1-0 assigned by user from learned pool
- Shift-modified bar for secondary actions (mount, consumables)

#### 3.6.2 Skill Properties
| Property | Description |
|-----------|-------------|
| **Cooldown** | Time before skill usable again |
| **Mana Cost** | MP consumed on cast |
| **Cast Time** | Channel time before effect (0 = instant) |
| **Range** | Maximum distance to target/ground |
| **Radius** | Area of effect (if applicable) |
| **Anim Lock** | Player locked during animation |

#### 3.6.3 Skill Categories
| Category | Examples | Properties |
|----------|----------|------------|
| **Damage (DD)** | Strike, Fireball, Arrow Shot | Direct damage |
| ** Crowd Control (CC)** | Stun, Freeze, Fear, Root | Prevents actions |
| **Buff** | Strength, Haste, Shield | Positive effects |
| **Debuff** | Slow, Weaken, Armor Break | Negative on enemy |
| **Heal** | Heal, Regen, Barrier | Restore HP |
| **Utility** | Teleport, Cleanse, Dispel | Non-damage utility |

#### 3.6.4 Skill Queuing
| System | Behavior |
|--------|----------|
| **Queue Window** | 200ms before current skill ends |
| **Queue Behavior** | Next skill casts immediately when ready |
| **Interrupt** | Pressing movement cancels queued skill |
| **Priority** | Latest input wins within queue window |

### 3.7 Auto-Attack System

#### 3.7.1 Melee Auto-Attack
| Property | Value |
|----------|-------|
| **Range** | 2 units (weapon reach + 0.5) |
| **Rate** | Determined by weapon speed + attack speed |
| **Damage** | [Weapon DPS × Attack Speed] averaged |
| **Trigger** | Automatically fires when in range + target locked |
| **Cancel** | Movement or skill use cancels current swing |

#### 3.7.2 Ranged Auto-Attack
| Property | Value |
|----------|-------|
| **Range** | 25 units (bows), 20 units (thrown) |
| **Projectile** | Visible arrow/projectile travels to target |
| **Travel Time** | Distance / projectile speed (not instant) |
| **Cancel** | Movement cancels, projectile still flies |

### 3.8 Crowd Control System

#### 3.8.1 CC Types
| Type | Effect | Removable? |
|------|--------|------------|
| **Stun** | Cannot act, cannot move | Hard CC |
| **Fear** | Run away randomly | Hard CC |
| **Sleep** | Cannot act, breaks on damage | Soft CC |
| **Root** | Cannot move, can act | Hard CC |
| **Silence** | Cannot cast spells | Hard CC |
| **Slow** | Reduced movement speed | Soft CC |
| **Snare** | Root if speed < 20% | Soft CC |
| **Blind** | Accuracy reduced to 50% | Soft CC |
| **Taunt** | Must target taunter | Soft CC |

#### 3.8.2 CC Duration Scaling
| CC Type | Base Duration | Diminishing Returns |
|---------|---------------|---------------------|
| **Stun** | 2s | 1st: 100%, 2nd: 50%, 3rd: 25%, 4th+: Immune |
| **Root** | 3s | Same as stun |
| **Fear** | 2s | Same as stun |
| **Slow** | 4s | No DR |
| **Silence** | 3s | 1st: 100%, 2nd: 50%, 3rd+: Immune |

### 3.9 Death & Resurrection

#### 3.9.1 Death Sequence
1. HP reaches 0
2. 1-second death animation (falls)
3. "YOU DIED" message with respawn options
4. Enter ghost form (see world, move through objects)
5. Respawn timer: 10 seconds (can be reduced by certain items)

#### 3.9.2 Respawn Options
| Option | Description |
|--------|-------------|
| **Return to Bind Point** | Instant respawn at bound town (default) |
| **Respawn Here** | Respawn at death location (50% HP/MP) |
| **Accept Resurrection** | Party member casts 3s rez on ghost |

#### 3.9.3 Death Penalties
| Zone Type | Penalty |
|-----------|---------|
| **Safe Zone** | 5% XP debt, respawn at nearest town |
| **PvE Zone** | 5% XP debt, 10% drop chance for 1 item |
| **PvP Zone** | Full loot: equipped items + bag drops |
| **Dungeon** | 10% XP debt, respawn outside dungeon |

#### 3.9.4 Kill Credit
- **Last Hit** gets kill credit
- **Damage Dealt** tracked for contribution rewards
- **Friendly Fire** disabled (cannot kill allies)
- **Kill Streak** tracked for bonus loot in PvP

### 3.10 Combat Feedback

#### 3.10.1 Damage Numbers
| Type | Color | Size | Text |
|------|-------|------|------|
| **Normal** | White | Normal | "1,234" |
| **Critical** | Yellow | 150% | "2,468 CRIT!" |
| **Glancing** | Gray | 75% | "617" |
| **Blocked** | Blue | 50% | "123 (BLOCKED)" |
| **Miss** | Red | - | "MISS" |
| **Dodge** | Orange | - | "DODGE" |
| **Absorb** | Purple | 50% | "500 (ABSORB)" |
| **Heal** | Green | Normal | "+1,234" |
| **Overkill** | Red | 150% | "5,000!" (damage that exceeds HP) |

#### 3.10.2 Visual Effects
| Event | Effect |
|-------|--------|
| **Hit** | Flash on target, blood/spark particles, damage number |
| **Crit** | Larger flash, screen shake (subtle), crit number |
| **CC Applied** | Target color shift, CC icon above head |
| **CC Received** | Screen edge tint, control icon flash |
| **Dodge** | Whoosh effect, white "DODGE" text |
| **Death** | Ragdoll fall, fade to ghost |

#### 3.10.3 Audio Cues
| Event | Sound |
|-------|-------|
| **Swing Miss** | Whoosh |
| **Swing Hit** | Impact (varies by weapon) |
| **Crit Hit** | Heavier impact + crit indicator |
| **Skill Cast** | Skill-specific cast sound |
| **Buff Applied** | Positive chime |
| **Debuff Applied** | Negative tone |
| **Low HP** | Heartbeat pulse |
| **Death** | Dramatic sting |

### 3.11 PvP Combat Modifiers

| Modifier | Value | Notes |
|----------|-------|-------|
| **Damage vs Players** | 70% of PvE damage | Prevents instant kills |
| **CC Duration vs Players** | 50% duration | Avoid stunlocks |
| **Resilience (PvP Defense)** | +20% CC reduction | Scales with gear |
| **Death Penalty (PvP)** | Full loot in PvP zones | Core risk/reward |
| **Kill Rewards** | Bonus currency + gear chance | Incentivize PvP |

### 3.12 Aggro & Enemy Behavior

#### 3.12.1 Aggro System (Proximity-Based)
| Behavior | Specification |
|----------|---------------|
| **Detection** | Enemies aggro players within detection radius (varies by enemy) |
| **Herd Range** | Enemies will follow/chase player up to 150% of aggro range |
| **Return to Spawn** | If player exits herd range, enemy returns to spawn point |
| **De-aggro** | Enemies reset after losing sight for 5 seconds |

#### 3.12.2 Level-Based Engagement Rules
| Scenario | Behavior |
|----------|----------|
| **Enemy is 20+ levels higher** | Enemy does NOT aggro (too dangerous) |
| **Player is 20+ levels higher** | Enemy aggroes normally, but gives minimal XP/loot |
| **Party Level Difference** | Enemy sees highest-level party member for aggro calculation |

#### 3.12.3 Experience Scaling by Level Difference
| Player Level vs Enemy | XP Modifier | Loot Modifier |
|-----------------------|-------------|----------------|
| **Player 20+ below enemy** | 500% (bonus!) | 200% |
| **Player 10-19 below enemy** | 200% | 150% |
| **Player 1-9 below enemy** | 100% | 100% |
| **Player 0-9 above enemy** | 100% | 100% |
| **Player 10-19 above enemy** | 25% | 50% |
| **Player 20+ above enemy** | 5% (minimal) | 10% |

**Design Intent:** Higher-level enemies are risky but rewarding. Grinding lower-level enemies is safe but minimal XP.

### 3.13 Animation & Timing

#### 3.13.1 Animation Lock Policy
| Skill Type | Lock Behavior | Cancel Window |
|------------|---------------|---------------|
| **Instant Skills** | No animation lock | N/A |
| **Quick Skills (< 0.5s)** | Lock during animation only | Cannot cancel |
| **Channel Skills (e.g., Fireball)** | Lock during cast time | Cancel at 70% for instant release |
| **Charge Skills (e.g., Slam)** | Full commitment | Cancel at 60% (movement cancels) |
| **Ultimate Skills** | Full commitment | No cancel (reward timing) |

#### 3.13.2 Skill Queuing Behavior
| System | Specification |
|--------|---------------|
| **Queue Window** | 200ms before current skill animation ends |
| **Queue Behavior** | Next skill casts immediately when queue window opens |
| **Queue Limit** | Only 1 queued skill at a time |
| **Interrupt on Move** | Movement cancels queued skill (unless charge skill) |

### 3.14 Touch Controls (Mobile)

#### 3.14.1 Primary Controls
| Control | PC Equivalent | Mobile Input |
|---------|---------------|---------------|
| **Move** | WASD | Virtual joystick (left thumb) |
| **Camera** | Mouse | Right side drag |
| **Jump** | Space | Joystick up / dedicated button |
| **Dodge** | Q | Dedicated button / double-tap joystick |
| **Target** | Tab / Click | Tap enemy on screen |
| **Attack** | Left Click / Auto | Default only: tap targeted enemy |
| **Skills** | 1-0 | Bottom skill buttons |

#### 3.14.2 Aim Assist
| System | Strength | Behavior |
|--------|----------|----------|
| **Melee Snap** | Light (5° cone) | Slight rotation toward enemy when swinging |
| **Ranged Lock** | Medium | Projectiles slightly curve toward moving target |
| **Ground Target** | Light | AoE indicators snap to valid ground |

#### 3.14.3 HUD Layout (Mobile)
```
┌────────────────────────────────────────────┐
│  [Menu]              [Mini-Map]    [Chat] │
│                                            │
│                                            │
│              [3D GAME VIEW]                │
│                                            │
│                                            │
│  [Target HP Bar - when combat]             │
│                                            │
│  [HP] [MP] [STA]                          │
│  ┌─────┐                                   │
│  │ JOY │  [Skill] [Skill] [Skill] [Skill] │
│  │     │  [Skill] [Skill] [Skill] [Dodge] │
│  └─────┘                                   │
└────────────────────────────────────────────┘
```

### 3.15 Combo System

#### 3.15.1 Combo Chains
| Combo | Trigger Window | Bonus Effect |
|-------|---------------|--------------|
| **Strike → Strike** | 2s | 2nd strike +25% damage |
| **Strike → Strike → Heavy Strike** | 2s between each | 3rd strike +50% damage, slight knockback |
| **Dodge → Any Attack** | 0.5s after dodge ends | Attack +20% crit chance |
| **CC Break → Shield Bash** | 1s after CC ends | Guaranteed stun on hit |

#### 3.15.2 Combo Display
| Element | Visual |
|---------|--------|
| **Combo Counter** | "x2", "x3" shown near target |
| **Combo Window** | Circular indicator showing time remaining |
| **Combo Break** | Combo counter resets with visual feedback |

### 3.16 Combat System Summary & Resolved Decisions

| Decision | Resolution | Notes |
|----------|-----------|-------|
| **Aggro System** | Proximity-based with herd range | RYL2-style |
| **Level Gap XP** | Scaled (5% to 500%) | Rewards risky kills |
| **Animation Lock** | Soft lock with cancel windows | Charge skills: 60% cancel |
| **Auto-Fight** | No auto-fight | Melee auto-attack only when targeted |
| **Aim Assist** | Light snap assist | Not full lock |
| **Combo System** | Enabled with 2s windows | Adds depth |
| **Skill Macroing** | No full automation | Combos yes, macro chains no |

### 3.17 Remaining Open Questions

- [ ] **Combo System Scope:** How many combo chains per class? (5-10 recommended)
- [ ] **Ultimate Skill System:** Shared ultimate bar or per-class ultimates?
- [ ] **Parry/Block Mechanic:** Add timing-based parry or rely on dodge?
- [ ] **PvP Only Skills:** Class skills that only work in PvP zones?

---

## 4. World & Exploration

> **Lead:** RYL2-scale open world with seamless zones, procedural extension, and dimensional depth.

### 4.1 World Philosophy

The world balances **handcrafted quality** (towns, dungeons, story beats) with **procedural scale** (extended regions, dungeons, content):

1. **Seamless** — No loading screens between outdoor zones (instanced dungeons load)
2. **Verticality** — Underground (Underworld), sky (Dimensional Planes), underwater (Ocean Depths)
3. **Layered Danger** — Safe towns → Contested zones → Full loot PvP → Endgame realms
4. **Living World** — Day/night, weather, world events, dynamic spawns

### 4.2 World Structure

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DIMENSIONAL PLANES                          │
│                    (Endgame content, instanced)                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   ┌─────────────────────────────────────────────────────────┐      │
│   │                    MAIN CONTINENT                        │      │
│   │                                                         │      │
│   │   [Starting Zone]  ──►  [Mid Zones]  ──►  [Endgame]   │      │
│   │        (Safe)           (Contested)        (PvP/Instanced)   │
│   │                                                         │      │
│   └─────────────────────────────────────────────────────────┘      │
│                              │                                      │
│                    [Open Ocean]                                    │
│                              │                                      │
│   ┌──────────────────────────┴──────────────────────────────────┐  │
│   │                      UNDERWORLD                              │  │
│   │         (Underground realm - dungeons, resources, danger)   │  │
│   └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│   [Satellite Islands]  [Ocean Depths]  [Hidden Dimensions]        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.3 Main Continent

#### 4.3.1 Size & Scale
| Metric | Value | Notes |
|--------|-------|-------|
| **Surface Area** | ~40 sq km (walkable) | ~2x RYL2 size |
| **Zones** | 15-20 distinct outdoor zones | Each ~2-4 sq km |
| **Width (N-S)** | ~8 km | 20 min run at base speed |
| **Height (E-W)** | ~5 km | 15 min run at base speed |
| **Outdoor Loading** | Seamless between zones | No load screens |

#### 4.3.2 Continent Regions
| Region | Theme | Level Range | Zone Type |
|--------|-------|-------------|-----------|
| **Verdant Vale** | Starter grasslands | 1-15 | Safe/PvE |
| **Thornwood Forest** | Dense forest, moderate | 10-25 | Contested |
| **Ashfields** | Volcanic/scorched | 20-35 | PvP enabled |
| **Crystalmere Highlands** | Mountains, ice | 30-45 | PvP + Dungeon |
| **Shadowfen** | Swamp, dark | 40-55 | PvP + Dungeon |
| **Ironpeak Mountains** | High mountains | 50-60 | Endgame PvP |
| **Sunfire Desert** | Desert, heat | 35-50 | PvE + Dungeon |
| **City of Dawn** | Central hub city | All | Safe hub |

### 4.4 Zone Architecture

#### 4.4.1 Zone Properties
| Property | Specification |
|----------|---------------|
| **Zone Size** | 2-4 sq km per zone |
| **Chunk System** | Zones divided into 100m × 100m chunks |
| **Active Chunks** | 3×3 around player loaded at full detail |
| **LOD Distance** | Terrain LOD transitions at 200m |
| **Entity Cap** | Max 50 players + 100 NPCs per zone shard |

#### 4.4.2 Zone Transitions
| Transition Type | Method | Loading |
|----------------|--------|---------|
| **Outdoor → Outdoor** | Walk across boundary | Seamless (stream next zone) |
| **Outdoor → Town** | Enter city portal/door | Seamless (town is part of zone) |
| **Outdoor → Dungeon** | Enter dungeon portal | 3-5 second load screen |
| **Surface → Underworld** | Cave entrance, mine shaft | 3-5 second load screen |
| **Any → Dimensional Plane** | Portal, item use | 3-5 second load screen |

#### 4.4.3 Zone Sharding
| Zone Type | Sharding Strategy |
|-----------|------------------|
| **Safe Zones (Towns)** | One shard, all players together |
| **PvE Zones** | Shard by population (50 players/shard) |
| **PvP Zones** | Shard by population (30 players/shard) |
| **Dungeons** | Instance per party/raid (1-5 players or 10-20) |
| **World Boss** | Cross-shard events with announcements |

### 4.5 Terrain System

#### 4.5.1 Terrain Types
| Terrain | Visual | Gameplay Effect |
|---------|--------|-----------------|
| **Grass** | Green plains, flowers | Normal movement |
| **Dirt/Path** | Brown roads, trails | Normal movement |
| **Forest Floor** | Leaf litter, soft ground | Normal movement |
| **Shallow Water** | < 1m depth | Swim speed, no combat |
| **Deep Water** | > 1m depth | Swim speed, visibility reduced |
| **Mud** | Brown, wet areas | 25% slower movement |
| **Sand** | Desert dunes | 25% slower movement, heat damage |
| **Snow/Ice** | Frozen areas | Slippery (slight slide), cold damage |
| **Rock/Stone** | Mountains, ruins | Normal movement, jumpable ledges |
| **Lava** | Volcanic pools | Instant death without immunity |

#### 4.5.2 Terrain Modifiers
| Modifier | Condition | Effect |
|----------|-----------|--------|
| **Heat** | Desert, volcanic | 5 HP/sec damage, requires water/buff |
| **Cold** | Snow, ice | 3 HP/sec damage, requires fire buff |
| **Poison** | Swamps, certain caves | 2 HP/sec, stacks up to 10 |
| **Darkness** | Caves, night | Reduced visibility radius |
| **Magnetic** | Special zones | Interferes with compass |

### 4.6 Points of Interest (POI)

#### 4.6.1 Towns & Cities
| Feature | Specification | Priority |
|---------|---------------|----------|
| **Starter Town** | Verdant Vale, safe zone, tutorial NPCs | P0 |
| **Major Cities** | 3-4 regional capitals with vendors, banks | P0 |
| **Villages** | Small settlements with basic services | P1 |
| **Outposts** | PvP zone entry points, capture points | P1 |
| **Ruins** | Abandoned settlements, treasure/danger | P1 |

#### 4.6.2 Dungeon Types
| Type | Size | Players | Duration | Loot |
|------|------|---------|----------|------|
| **Solo Dungeon** | Small (15-20 min) | 1 | 15-20 min | Blue gear |
| **Group Dungeon** | Medium (30-45 min) | 5 | 30-45 min | Purple gear |
| **Raid Dungeon** | Large (1-2 hr) | 10-20 | 1-2 hr | Epic gear |
| **World Dungeon** | Open zone | Any | Varies | Mixed, rare spawns |

#### 4.6.3 Dungeon Design
| Feature | Specification |
|---------|---------------|
| **Entry** | Portal at zone location, requires minimum level |
| **Loading** | Instance created on entry, solo/group/raid sizes |
| **Checkpoints** | Save progress at boss rooms (for disconnects) |
| **Boss Mechanics** | 3-5 bosses per dungeon, phases, CC checks |
| **Trash Mobs** | 2-3 groups between each boss |
| **Completion** | Exit portal at end, loot chest, return to entry |

#### 4.6.4 Dynamic POIs
| Feature | Specification |
|---------|---------------|
| **Resource Nodes** | Ore veins, herb patches, wood logs, fish spots |
| **Elite Spawns** | Random elite spawns every 30-60 min |
| **World Events** | Dragon attack, NPC invasion, weather events |
| **Treasure Chests** | Random spawn, requires key or lockpick |
| **Hidden Caves** | Secret entrances, require perception or puzzle |

### 4.7 Vertical Dimensions

#### 4.7.1 Underworld
| Feature | Specification |
|---------|---------------|
| **Entry Points** | Major cave systems, mine shafts |
| **Size** | ~30 sq km (smaller than surface) |
| **Theme** | Dark, dangerous, resource-rich |
| **Content** | Mine dungeons, earth elemental bosses |
| **Difficulty** | +20 levels compared to surface equivalent |
| **Resources** | Rare ores, gems, unique herbs |

#### 4.7.2 Ocean
| Feature | Specification |
|---------|---------------|
| **Open Water** | Between continents, navigable with mount |
| **Ocean Depths** | Underwater zones for high-level players |
| **Islands** | Satellite islands with unique content |
| **Underwater Combat** | Limited (slower attacks, reduced vision) |
| **Treasure** | Shipwrecks, underwater ruins |

#### 4.7.3 Dimensional Planes
| Plane | Theme | Entry | Content |
|-------|-------|-------|---------|
| **Faerie Realm** | Ethereal, magical | Portal | Fae enemies, magic resources |
| **Shadow Plane** | Dark, corrupted | Portal | Shadow enemies, dark artifacts |
| **Celestial Realm** | Heavenly, light | Portal | Angelic enemies, divine items |
| **Chaos Dimension** | Randomized, unstable | Portal | Mixed content, high risk/reward |

### 4.8 Procedural Generation

#### 4.8.1 Extended Terrain (Far Regions)
| Feature | Specification |
|---------|---------------|
| **Generation Method** | Perlin noise + hand-tuned seeds |
| **Visual Quality** | LOD, simplified meshes, distant only |
| **Purpose** | "Infinite" feel beyond main continent |
| **Player Use** | Exploration, rare resources, no quests |
| **Server** | Procedural, not saved to DB (regenerates) |

#### 4.8.2 Procedural Dungeons
| Feature | Specification |
|---------|---------------|
| **Room Templates** | 20-30 pre-made room modules |
| **Generation Rules** | Ensure connectivity, boss room last |
| **Difficulty Scaling** | Mob stats scale to player level |
| **Loot Quality** | Scaled to dungeon level |
| **Daily Rotation** | New layout each day (deterministic seed) |

#### 4.8.3 World Events
| Event | Frequency | Duration | Effect |
|-------|-----------|----------|--------|
| **World Boss** | Every 4-6 hours | 15 min | Elite spawn, global announcement |
| **Treasure Invasion** | Random | 10 min | Rare chest spawns across zones |
| **Weather Shift** | Every 2-4 hours | Varies | Rain, storm, fog changes |
| **Raid Alert** | Weekly | 30 min | Large-scale PvP event |

### 4.9 Navigation & Waypoints

#### 4.9.1 Fast Travel System
| Method | Unlock | Cost | Notes |
|--------|--------|------|-------|
| **Town Portal Scroll** | Always | Gold (50-200) | Cast, enter, click, destination |
| **Resurrection** | Always | None | Return to bind point |
| **Zone Waypoints** | Unlock per zone | Gold or quest | Instant teleport between waypoints |
| **Mount Speed** | Always | None | Fastest ground travel |
| **Ship/Ferry** | Always | Gold | Travel between continents/islands |

#### 4.9.2 Waypoint Unlocks
| Unlock Method | Waypoint Access |
|---------------|-----------------|
| **Default** | Starter town only |
| **Quest Completion** | Zone's main quest grants waypoint |
| **Discovery** | Visit waypoint location to unlock |
| **Purchase** | Buy unlock with gold (200-500g) |

### 4.10 World Open Questions

- [ ] **World Size:** 40 sq km sufficient, or scale up/down?
- [ ] **Zone Shard Caps:** 50 PvE / 30 PvP — acceptable player density?
- [ ] **Procedural Extent:** How far beyond main continent to generate?
- [ ] **Underwater Combat:** Full combat system or limited underwater zone?
- [ ] **Dimensional Planes:** Start with all planes or add over time?
- [ ] **Day/Night Cycle:** 24-hour real time or accelerated?

---

## 5. Player Systems

> **Lead:** Character creation, class system, progression, and inventory management.

### 5.1 Design Philosophy

The player systems prioritize **build expression** and **meaningful progression**:

1. **Class Identity** — Each class feels distinct in combat and gameplay
2. **Build Depth** — Multiple viable specs per class through skill trees and gear
3. **Progression Satisfaction** — Clear power growth with each level/upgrade
4. **Inventory Management** — Strategic decisions about gear and resources

### 5.2 Races

#### 5.2.1 Available Races
| Race | Description | Racial Trait |
|------|-------------|---------------|
| **Human** | Balanced, versatile | +5% all XP gains |
| **High Elf** | Magical affinity | +10% mana pool, +5% magic damage |
| **Orc** | Physical power | +10% health, +5% physical damage |
| **Dwarf** | Sturdy craftsman | +10% gathering speed, +5% defense |
| **Shadow Elf** | Stealthy | +10% stealth, +5% crit chance |

#### 5.2.2 Race Selection
| Feature | Specification |
|---------|---------------|
| **Choice Point** | Character creation only |
| **Lock-In** | Permanent, cannot change |
| **Visual Customization** | Face, hair, skin tone, markings |

### 5.3 Class System

#### 5.3.1 Base Classes
| Class | Role | Primary Stat | Weapon Focus | Armor |
|-------|------|--------------|--------------|-------|
| **Warrior** | Melee Tank/DPS | Strength | Sword, Axe, Hammer, Shield | Plate |
| **Mage** | Ranged DPS/Caster | Intelligence | Staff, Wand | Cloth |
| **Rogue** | Melee DPS/Stealth | Agility | Dagger, Bow | Leather |
| **Priest** | Healer/Support | Wisdom | Mace, Staff | Cloth |
| **Ranger** | Ranged DPS | Agility | Bow, Crossbow | Mail |

#### 5.3.2 Hybrid Classes (Unlocked at Level 20)
| Class | Combination | Role | Notes |
|-------|-------------|------|-------|
| **Paladin** | Warrior + Priest | Healer Tank | Shield, holy damage |
| **Bard** | Rogue + Priest | Buffer/Support | Instrument, buffs |
| **Berserker** | Warrior + Rogue | Melee Burst | Heavy armor, rage |
| **Warlock** | Mage + Rogue | Cursed DPS | Dark magic, dots |
| **Druid** | Priest + Ranger | Shapeshifter | Heal/nuke/buff |
| **Runekeeper** | Mage + Priest | Hybrids | Runes, shield |

#### 5.3.3 Class-Specific Skills
| Class | Skill Count | Skill Types |
|-------|-------------|-------------|
| **Warrior** | 25 | Stances, taunts, shields, weapon masteries |
| **Mage** | 25 | Elements, wards, conjures, passives |
| **Rogue** | 25 | Stealth, poison, backstab, evasion |
| **Priest** | 25 | Heals, shields, buffs, purifies |
| **Ranger** | 25 | Aimed shots, traps, pet, traps |

### 5.4 Leveling System

#### 5.4.1 Leveling Curve
| Level Range | XP per Level | Total XP to Reach |
|-------------|--------------|-------------------|
| 1-20 | 1,000 → 10,000 | 85,000 |
| 21-40 | 10,000 → 50,000 | 650,000 |
| 41-60 | 50,000 → 200,000 | 2,500,000 |
| **Total to 60** | — | ~3,235,000 XP |

#### 5.4.2 Leveling Rewards
| Level | Rewards |
|-------|---------|
| **Every Level** | +1 Skill Point, +1 Attribute Point |
| **Every 5 Levels** | Unlock new skill tier |
| **Milestone Levels** | 10, 20, 30, 40, 50, 60 unlock class abilities |

#### 5.4.3 XP Sources
| Source | XP Modifier |
|--------|-------------|
| **Kill Enemy** | Enemy XP × level gap modifier |
| **Quest Completion** | 500-5,000 XP (varies by quest) |
| **Exploration** | Discover new area: 100-1,000 XP |
| **Crafting** | Craft item: 50-500 XP |
| **World Event** | Participate: 1,000-10,000 XP |
| **Gathering** | Harvest node: 10-100 XP |

### 5.5 Skill System

#### 5.5.1 Skill Tree Structure
```
Warrior Skills
├── Weapon Mastery
│   ├── Sword Proficiency (Passives)
│   ├── Axe Proficiency
│   └── Hammer Proficiency
├── Combat Arts
│   ├── Strike Line
│   │   ├── Strike (Lvl 1)
│   │   ├── Heavy Strike (Lvl 10)
│   │   └── Devastate (Lvl 30)
│   ├── Defensive Arts
│   │   ├── Block (Lvl 5)
│   │   ├── Shield Bash (Lvl 15)
│   │   └── Shield Wall (Lvl 35)
│   └── Mobility
│       ├── Charge (Lvl 8)
│       └── Leap (Lvl 25)
└── Stances
    ├── Battle Stance (+Damage)
    └── Defensive Stance (+Defense)
```

#### 5.5.2 Skill Point Allocation
| Allocation | Rule |
|------------|------|
| **Points Earned** | 1 per level |
| **Points Available** | Equal to level |
| **Prerequisites** | Some skills require previous tier |
| **Respec** | Full respec available (gold cost) |
| **Respec Cost** | 500 gold per level respec |

#### 5.5.3 Skill Categories
| Category | Behavior |
|----------|----------|
| **Active** | Must manually cast/use |
| **Passive** | Always active, no input |
| **Toggle** | Can turn on/off (e.g., Stealth) |
| **Stance** | Only one stance active at a time |
| **Ultimate** | Powerful, long cooldown, level 50+ |

### 5.6 Attribute System

#### 5.6.1 Attribute Points
| Allocation | Rule |
|------------|------|
| **Points Earned** | 1 per level |
| **Points Available** | Equal to level |
| **Primary Caps** | None (distribute freely) |
| **Soft Cap** | Diminishing returns after 50 in one stat |
| **Respec** | Free at level 1, gold cost otherwise |

#### 5.6.2 Attribute Effects
| Stat | Effect per Point |
|------|------------------|
| **Strength** | +2% physical damage, +50 carry weight |
| **Agility** | +1% attack speed, +0.5% dodge, +0.3% crit |
| **Intelligence** | +3% magic damage, +8% max mana |
| **Vitality** | +10% max health, +2% physical defense |
| **Endurance** | +5% max stamina, +5% stamina regen |
| **Wisdom** | +8% mana regen, +5% buff duration |

### 5.7 Equipment System

#### 5.7.1 Equipment Slots
| Slot | Item Type | Icon |
|------|-----------|------|
| **Head** | Helmet, Hood, Crown | [H] |
| **Chest** | Armor, Robe, Leather | [C] |
| **Hands** | Gauntlets, Gloves | [G] |
| **Legs** | Pants, Greaves, Skirt | [L] |
| **Feet** | Boots, Shoes | [F] |
| **Main Hand** | Sword, Staff, Bow, Dagger | [M] |
| **Off Hand** | Shield, Orb, Dagger, Torch | [O] |
| **Ring 1** | Ring | [R1] |
| **Ring 2** | Ring | [R2] |
| **Neck** | Amulet, Necklace | [N] |
| **Cape/Cloak** | Cape, Back item | [B] |

#### 5.7.2 Item Quality (Loot)
| Quality | Color | Drop Rate | Stat Range |
|---------|-------|-----------|------------|
| **Poor** | Gray | Common | 50-75% base |
| **Common** | White | Very Common | 75-100% base |
| **Uncommon** | Green | Common | 100-125% base |
| **Rare** | Blue | Uncommon | 125-150% base |
| **Epic** | Purple | Rare | 150-175% base |
| **Legendary** | Orange | Very Rare | 175-200% base |

#### 5.7.3 Item Binding
| Bind Type | Behavior |
|-----------|----------|
| **Bind on Pickup** | Cannot trade, soulbound on pickup |
| **Bind on Equip** | Can trade until worn, then bound |
| **Bound to Account** | Binds to account, not character |
| **Never Bind** | Always tradable |

#### 5.7.4 Item Durability
| Feature | Specification |
|---------|---------------|
| **Durability** | Equipment has HP, degrades on use |
| **Damage Rate** | 1 durability per 10 min combat |
| **Break Point** | 0 durability = item useless until repaired |
| **Repair Cost** | Gold cost based on item level |
| **Repair NPC** | Available in all towns |

### 5.8 Inventory System

#### 5.8.1 Inventory Layout
```
┌────────────────────────────────────────────────────┐
│ INVENTORY                           Gold: 12,450  │
├────────────────────────────────────────────────────┤
│ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐│
│ │  │ │  │ │  │ │  │ │  │ │  │ │  │ │  │ │  │ │  ││
│ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘│
│ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐│
│ │  │ │  │ │  │ │  │ │  │ │  │ │  │ │  │ │  │ │  ││
│ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘│
│ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐│
│ │  │ │  │ │  │ │  │ │  │ │  │ │  │ │  │ │  │ │  ││
│ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘│
│ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐│
│ │  │ │  │ │  │ │  │ │  │ │  │ │  │ │  │ │  │ │  ││
│ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘│
├────────────────────────────────────────────────────┤
│ [Equipment] [Skills] [Quests] [Bank] [Crafting]    │
└────────────────────────────────────────────────────┘
```
- **Base Slots**: 40 (4 rows × 10 columns)
- **Bag Slots**: Expandable via bag items (add rows)

#### 5.8.2 Item Stacking
| Item Type | Stack Size |
|-----------|------------|
| **Consumables** | 99 |
| **Crafting Materials** | 99 |
| **Quest Items** | 1 (never stack) |
| **Equipment** | 1 (never stack) |
| **Currency** | No limit (gold only) |

#### 5.8.3 Bank System
| Feature | Specification |
|---------|---------------|
| **Base Slots** | 200 (shared across characters) |
| **Gold Shared** | Bank gold shared with character gold |
| **Tabs** | 5 tabs (expandable with premium) |
| **Withdrawal** | Any character on account can access |

### 5.9 Progression Systems

#### 5.9.1 Account Progression
| System | Scope | Benefit |
|--------|-------|---------|
| **Mounts** | Account | Unlock for all characters |
| **Titles** | Character | Earned through achievements |
| **Recipe Knowledge** | Account | Recipes available on all chars |
| **Bank** | Account | Shared storage |
| **Waypoints** | Character | Must unlock per character |

#### 5.9.2 Leveling Benefits
| Level | Unlock |
|-------|--------|
| **1** | Game start, basic skills |
| **5** | First skill tier, can join guild |
| **10** | Dungeon access, second weapon type |
| **15** | Can trade with other players |
| **20** | Hybrid class unlock |
| **30** | Advanced mounts |
| **40** | Can create guild |
| **50** | Ultimate skills, endgame content |
| **60** | Max level, prestige unlocks |

### 5.10 Player Open Questions

- [ ] **Level Cap:** 60 final, or higher? (MMOs often add levels post-launch)
- [ ] **Hybrid Class Unlock:** Free or require quest/prestige?
- [ ] **Respec Philosophy:** Free respec (no penalty) or gold cost (economic sink)?
- [ ] **Twinking:** Allow high-level players to send gear to alts?

---

## 6. Economy & Crafting

> **Lead:** UO-inspired player-driven economy with deep crafting systems and resource gathering.

### 6.1 Design Philosophy

The economy prioritizes **player agency** and **meaningful crafting**:

1. **Player-Driven** — Supply and demand set prices, not NPCs
2. **Crafting Depth** — Multiple tiers, quality differences, specialization
3. **Resource Scarcity** — Rare materials create valuable items
4. **Item Durability** — Continuous gold sink, demand for repairs/crafts

### 6.2 Gathering System

#### 6.2.1 Gathering Professions
| Profession | Resources Gathered | Tool Required |
|------------|-------------------|---------------|
| **Mining** | Ore (Copper, Iron, Silver, Gold, Mithril, Adamant) | Pickaxe |
| **Herbalism** | Herbs (Healing, Mana, Strength herbs) | Sickle |
| **Woodcutting** | Logs (Oak, Pine, Ironwood, Heartwood) | Axe |
| **Skinning** | Hides, furs, scales from beasts | Skinning Knife |
| **Fishing** | Fish, seafood, rare ingredients | Fishing Rod |
| **Archaeology** | Ancient artifacts, fossils (P2) | Trowel, Brush |

#### 6.2.2 Gathering Mechanics
| Feature | Specification |
|---------|---------------|
| **Node Spawn** | Resources appear in world at specific locations |
| **Node Types** | Common (80%), Uncommon (15%), Rare (4%), Legendary (1%) |
| **Respawn Time** | Common: 5 min, Uncommon: 15 min, Rare: 1 hr, Legendary: 4 hr |
| **Gather Time** | 3-5 seconds per node |
| **Gather Skill** | Gathering level increases yield and speed |
| **Depletion** | Nodes deplete after 3-5 gathers, then respawn |

#### 6.2.3 Gathering Leveling
| Level | Unlock | Bonus |
|-------|--------|-------|
| 1-20 | Basic nodes | +10% yield |
| 21-40 | Uncommon nodes | +25% yield, faster gather |
| 41-60 | Rare nodes | +50% yield, chance for double |
| Master | Legendary nodes | Chance for rare materials |

#### 6.2.4 Gathering Locations
| Location | Primary Resources |
|----------|-------------------|
| **Mountains** | Ore (mining), Gems |
| **Forests** | Wood (woodcutting), Herbs |
| **Plains** | Herbs, Hides (from beasts) |
| **Water** | Fish (fishing) |
| **Caves** | Rare ore, Gems |
| **Underworld** | Adamant, Mithril ore, Rare gems |

### 6.3 Crafting Professions

#### 6.3.1 Primary Professions
| Profession | Creates | Materials Used |
|------------|---------|----------------|
| **Blacksmithing** | Weapons, Plate armor, Shields | Ore, Ingots, Leather |
| **Tailoring** | Cloth armor, Leather armor, Bags | Cloth, Leather, Thread |
| **Woodworking** | Bows, Staves, Shields, Furniture | Wood, Leather |
| **Alchemy** | Potions, Elixirs, Poisons | Herbs, Vials, Water |
| **Cooking** | Food buffs, Feasts | Fish, Meat, Vegetables |
| **Jewelcrafting** | Rings, Necklaces, Gems | Gems, Precious metals |
| **Enchanting** | Magical augmentations | Crystals, Gold, Mana essence |

#### 6.3.2 Crafting System
| Feature | Specification |
|---------|---------------|
| **Recipe Knowledge** | Learn by crafting, buying, or questing |
| **Crafting Station** | Required station (forge, loom, cauldron) |
| **Crafting Time** | 5-30 seconds per item |
| **Success Rate** | Based on skill level and recipe difficulty |
| **Failure** | Materials lost, must retry |
| **Quality Tiers** | Normal → Fine → Masterwork → Legendary |

#### 6.3.3 Crafting Quality
| Quality | Stat Bonus | Craft Success |
|---------|------------|---------------|
| **Normal** | 100% base stats | 100% at skill level |
| **Fine** | 110% base stats | 90% at skill level |
| **Masterwork** | 125% base stats + special property | 70% at skill level |
| **Legendary** | 150% base stats + 2 properties | 40% at skill level + rare materials |

#### 6.3.4 Crafting Leveling
| Level | Craftable Items | Specialization Unlock |
|-------|-----------------|---------------------|
| 1-20 | Basic (Level 1-20 gear) | 1 specialization |
| 21-40 | Intermediate (Level 20-40) | 2 specializations |
| 41-60 | Advanced (Level 40-60) | 3 specializations |
| Master | All items + Legendary | All specializations |

#### 6.3.5 Specialization Trees
```
Blacksmithing Specializations
├── Weaponsmith
│   └── Focus: All weapons (+15% quality, -20% time)
├── Armorsmith
│   └── Focus: All armor (+15% quality, -20% time)
├── Shieldsmith
│   └── Focus: Shields only (+25% quality)
└── Jewel Inlay
    └── Focus: Add gem sockets (+10% quality)
```

### 6.4 Crafting Recipes

#### 6.4.1 Recipe Acquisition
| Method | Description |
|--------|-------------|
| **Starting Recipes** | 5 basic recipes per profession |
| **Crafting Discovery** | 10% chance to discover new recipe on craft |
| **Vendor Purchase** | Buy from crafting trainers (1-500g each) |
| **Quest Reward** | Complete crafting quests for rare recipes |
| **Loot Drop** | Rare recipe drops from mobs/dungeons |
| **Player Trade** | Buy/sell recipes on auction house |

#### 6.4.2 Recipe Categories
| Category | Contents |
|----------|----------|
| **Basic** | Common items, low materials, quick craft |
| **Standard** | Mid-tier items, moderate requirements |
| **Advanced** | High-tier items, rare materials |
| **Masterwork** | Legendary items, master materials, special recipes |
| **Secret** | Hidden recipes from rare sources |

### 6.5 Player Economy

#### 6.5.1 Currency System
| Currency | Name | Acquisition |
|----------|------|-------------|
| **Gold (G)** | Primary | Drops, quests, sales |
| **Silver (S)** | Secondary (100S = 1G) | Used for small transactions |
| **Copper (C)** | Tertiary (100C = 1S) | Dropped by low-level mobs |

#### 6.5.2 Money Sinks
| Sink | Cost | Frequency |
|------|------|-----------|
| **Repair** | 5-20% of item value | Every death/combat |
| **Town Teleport** | 50-200g | Per use |
| **Auction House** | 5% sale tax | Per transaction |
| **Guild Upkeep** | 100-1000g/week | Weekly |
| **Housing** | Weekly rent | Weekly |
| **Crafting** | Material cost | Per craft |
| **Death Penalty** | 10% XP debt | Per death |

#### 6.5.3 Money Sources
| Source | Amount | Frequency |
|--------|--------|-----------|
| **Mob Drops** | 10-1000g | Per kill |
| **Quest Rewards** | 100-5000g | Per quest |
| **Selling to NPC** | 10-50% market value | Unlimited |
| **Selling to Player** | Market value | Unlimited |
| **Crafting Profit** | Varies | Per craft |
| **Gathering** | 1-100g per node | Per gather |

#### 6.5.4 Gold Cap
| Cap Type | Limit |
|----------|-------|
| **Character Gold** | 1,000,000g (1M) per character |
| **Bank Gold** | 10,000,000g (10M) per account |
| **Trading** | Cannot exceed cap on transaction |

### 6.6 Trading Systems

#### 6.6.1 Direct Player Trading
| Feature | Specification |
|---------|---------------|
| **Trade Window** | Drag items, see offers |
| **Trade Confirm** | Both parties must confirm |
| **Trade Limit** | Can trade any amount |
| **Trade Tax** | None for direct trades |
| **Scam Prevention** | Clear confirmation, no reversal |

#### 6.6.2 Auction House
| Feature | Specification |
|---------|---------------|
| **Listing Fee** | 10g per listing |
| **Sale Tax** | 5% of sale price |
| **Duration** | 24, 48, or 72 hours |
| **Categories** | Weapons, Armor, Materials, Consumables, Misc |
| **Search** | By name, quality, level, price |
| **Bidding** | Optional bid vs instant buy |

#### 6.6.3 Player Shops
| Feature | Specification |
|---------|---------------|
| **Location** | Designated shop plots in towns |
| **Rent** | 500g per week |
| **Shop Size** | 20 item slots |
| **Shop Types** | Personal stall, NPC vendor, Display case |
| **Features** | Custom name, sign, 24/7 operation |

### 6.7 Item Distribution

#### 6.7.1 Loot Sources
| Source | Quality Range | Drop Rate |
|--------|--------------|-----------|
| **Trash Mobs** | Poor → Uncommon | 10% drops |
| **Elite Mobs** | Uncommon → Rare | 30% drops |
| **Dungeon Trash** | Uncommon → Epic | 50% drops |
| **Dungeon Boss** | Rare → Legendary | 100% drops |
| **World Boss** | Epic → Legendary | 100% drops |
| **Crafting** | Uncommon → Legendary | Player-controlled |

#### 6.7.2 Crafted vs Dropped Balance
| Item Type | Crafted Better | Dropped Better |
|-----------|----------------|----------------|
| **Weapons** | ✓ High-tier endgame | Entry-level |
| **Armor** | ✓ High-tier endgame | Entry-level |
| **Consumables** | ✓ Alchemy advantage | Some quest items |
| **Materials** | N/A | Primary source |
| **Rare Items** | Limited | Some dungeon exclusives |

#### 6.7.3 Bind on Pickup Items
| Item Type | Binding |
|-----------|---------|
| **Dungeon Loot** | Bind on Pickup |
| **Quest Rewards** | Bind on Pickup |
| **Crafted Gear** | Bind on Equip (can trade before wearing) |
| **Crafting Materials** | Never Bind |
| **Consumables** | Never Bind |

### 6.8 Resource Nodes (World Integration)

#### 6.8.1 Node Types by Zone
| Zone Type | Primary Nodes | Rarity |
|-----------|--------------|--------|
| **Starter (1-15)** | Copper, Iron, Basic herbs, Oak | Common |
| **Mid (15-35)** | Silver, Gold, Healing herbs, Pine | Uncommon |
| **High (35-50)** | Mithril, Gems, Rare herbs, Ironwood | Rare |
| **Endgame (50-60)** | Adamant, Adamantite, Gems, Heartwood | Very Rare |
| **Underworld** | All ores, Gems, Dark herbs | Rare + |
| **Dimensional Planes** | Plane-specific materials | Legendary |

#### 6.8.2 Node Distribution
| Feature | Specification |
|---------|---------------|
| **Density** | 50-100 nodes per zone |
| **Clusters** | Nodes appear in groups of 3-5 |
| **Despawn** | Node disappears when depleted |
| **Respawn** | Timer starts on despawn (see 6.2.2) |
| **Ownership** | No ownership, first-come basis |

### 6.9 Economy Open Questions

- [ ] **RMT Policy:** Allow third-party gold selling? Ban with anti-cheat? Embrace with official store?
- [ ] **Crafting Overpower:** Should crafted gear always be better than drops?
- [ ] **Resource Spawn Rates:** Increase for faster economy or decrease for scarcity?
- [ ] **Gathering Competition:** Allow multiple players to gather same node?
- [ ] **Crafting Failures:** Materials lost on failure — good or bad for economy?

---

## 7. Player Housing

> **Lead:** UO-inspired housing system with player customization and functional benefits.

### 7.1 Housing Philosophy

Housing provides **home base benefits** and **player expression**:

1. **Functional** — Storage, crafting stations, teleport
2. **Social** — Party hosting, guild halls
3. **Expressive** — Customization, trophies, decoration
4. **Economic** — Housing plot market, furniture economy

### 7.2 Housing Zones

#### 7.2.1 Housing Districts
| District | Location | Plot Types Available |
|----------|----------|---------------------|
| **Verdant Commons** | Starter zone | Small, Medium |
| **Thornwood Glen** | Mid zone | Small, Medium, Large |
| **Crystalmere Heights** | High zone | Medium, Large, Mansion |
| **Ironpeak Summit** | Endgame zone | Large, Mansion |
| **Guild Quarter** | Each city | Guild plots only |

#### 7.2.2 Plot Placement
| Feature | Specification |
|---------|---------------|
| **Placement Mode** | Walk to plot, enter placement, rotate/scale |
| **Snap Points** | Plots snap to grid for alignment |
| **Neighbors** | Adjacent plots visible, cannot overlap |
| **Decay Timer** | 30 days offline = house enters decay |
| **Protection** | Houses cannot be damaged in safe zones |

### 7.3 House Types

#### 7.3.1 House Sizes
| Type | Dimensions | Interior | Cost/Week | Storage |
|------|------------|----------|-----------|---------|
| **Small House** | 8m × 8m | 2 rooms | 200g | 50 slots |
| **Medium House** | 12m × 12m | 4 rooms | 500g | 100 slots |
| **Large House** | 16m × 16m | 6 rooms | 1,000g | 200 slots |
| **Mansion** | 24m × 24m | 10 rooms | 2,500g | 500 slots |

#### 7.3.2 House Exteriors
| Element | Customizable |
|---------|--------------|
| **Walls** | Material, color |
| **Roof** | Style, color |
| **Door** | Style, size |
| **Windows** | Style, placement |
| **Porch/Patio** | Size, decoration |
| **Garden** | Plants, paths |
| **Mount Display** | Show mounted pets outside |

### 7.4 Interior System

#### 7.4.1 Rooms
| Room Type | Purpose | Furnishings |
|-----------|---------|-------------|
| **Main Hall** | Entry, social | Tables, chairs, trophies |
| **Bedroom** | Rest, respawn | Bed, dresser, wardrobe |
| **Storage Room** | Extra storage | Chests, shelves |
| **Crafting Room** | Workbenches | Smithing, alchemy, cooking stations |
| **Library** | Study, trophies | Bookshelves, maps |
| **Garden/Pool** | Decoration | Plants, water features |

#### 7.4.2 Furniture
| Category | Items | Function |
|----------|-------|----------|
| **Seating** | Chairs, benches, thrones | Decoration |
| **Tables** | Dining, side, workbenches | Work surface |
| **Storage** | Chests, wardrobes, shelves | Extra storage |
| **Beds** | Cots, beds, ornate | Respawn point |
| **Lighting** | Torches, chandeliers, candles | Lighting |
| **Decoration** | Paintings, trophies, rugs | Aesthetics |
| **Crafting** | Workbenches, forges, looms | Functional stations |

#### 7.4.3 Furniture Limits
| House Size | Furniture Limit | Storage Limit |
|------------|---------------|--------------|
| **Small** | 50 items | 50 slots |
| **Medium** | 100 items | 100 slots |
| **Large** | 200 items | 200 slots |
| **Mansion** | 500 items | 500 slots |

### 7.5 Housing Functions

#### 7.5.1 Respawn Point
| Feature | Specification |
|---------|---------------|
| **Set Bed** | Click bed to set as respawn |
| **Respawn** | Return to house on death (if set) |
| **Cooldown** | Respawn at home: 5 minute cooldown |

#### 7.5.2 Storage
| Feature | Specification |
|---------|---------------|
| **Personal Chest** | 50-500 slots (based on house) |
| **Shared with Alts** | All account characters can access |
| **Guild Access** | Optional guild chest (separate) |

#### 7.5.3 Crafting Stations
| Station | Function |
|---------|----------|
| **Forge** | Blacksmithing |
| **Loom** | Tailoring |
| **Alchemy Lab** | Alchemy |
| **Cooking Fire** | Cooking |
| **Workbench** | Woodworking |
| **Enchanting Table** | Enchanting |

#### 7.5.4 Teleport
| Feature | Specification |
|---------|---------------|
| **Recall Rune** | Craft/buy rune, attune to house |
| **Cooldown** | 10 minute cooldown |
| **Cost** | 50g per recall |

### 7.6 Housing Permissions

#### 7.6.1 Permission Levels
| Level | Access |
|-------|--------|
| **Owner** | Full control, demolition |
| **Co-Owner** | All permissions except demolition |
| **Friend** | Enter, use storage, move furniture |
| **Guild Member** | Enter (if guild house) |
| **Private** | Only owner/co-owner |

#### 7.6.2 Guest Management
| Feature | Specification |
|---------|---------------|
| **Invite** | Owner/co-owner invites players |
| **Remove** | Remove any guest |
| **Transfer** | Transfer ownership to another player |
| **Ban** | Prevent specific players from entering |

### 7.7 Guild Housing

#### 7.7.1 Guild Hall Features
| Feature | Specification |
|---------|---------------|
| **Size** | Large or Mansion only |
| **Cost** | 5,000g initial + 2,000g/week |
| **Guild Bank** | Separate 500-slot storage |
| **Roster Display** | Show online members |
| **Guild Crests** | Display guild emblem |

#### 7.7.2 Guild Hall Upgrades
| Upgrade | Cost | Effect |
|---------|------|--------|
| **Bank Expansion** | 10,000g | +250 slots |
| **Crafting Wing** | 15,000g | All crafting stations |
| **War Room** | 20,000g | Guild buffs, strategy table |
| **Training Hall** | 25,000g | XP boost for members |

### 7.8 Housing Economy

#### 7.8.1 Plot Market
| Feature | Specification |
|---------|---------------|
| **Initial Purchase** | Bid on open plots (auction) |
| **Resale** | Players can sell houses (player-to-player) |
| **Rent** | Weekly rent (see 7.3.1) |
| **Demolition** | If rent unpaid, house enters decay |

#### 7.8.2 Decay System
| Stage | Duration | Condition |
|-------|----------|-----------|
| **Grace Period** | 7 days | Warning message |
| **Decay Warning** | 7 days | House visible but damaged |
| **Demolition** | After 14 days | House destroyed, plot opens |

### 7.9 Housing Open Questions

- [ ] **House Gifting:** Allow gifting houses to other players?
- [ ] **Instanced Housing:** Instance per player or shared world houses (UO-style)?
- [ ] **Furniture Persistence:** Save furniture positions on logout?
- [ ] **House Alarms:** Notify owner when someone enters?

---

## 8. PvP Systems

> **Lead:** Full loot PvP in designated zones, guild wars, and structured PvP content.

### 8.1 PvP Philosophy

PvP creates **risk vs reward** and **meaningful conflict**:

1. **Zone Differentiation** — Safe zones for protection, PvP zones for risk
2. **Full Loot Risk** — High-reward PvP zones with equipment loss
3. **Guild Power** — Territory control and guild warfare
4. **Fair Combat** — Level scaling and mechanics for balanced fights

### 8.2 Zone Types

#### 8.2.1 Zone PvP Settings
| Zone Type | PvP Enabled | Full Loot | Player Damage |
|-----------|-------------|-----------|---------------|
| **Safe Zone** | No | No | Disabled |
| **Contested Zone** | Yes | No | 50% damage |
| **PvP Zone** | Yes | Yes | 100% damage |
| **Guild War** | Yes | Yes | 100% damage |
| **Arena** | Yes | No | 100% damage |

#### 8.2.2 Safe Zones
| Zone | Type | Protection Level |
|------|------|-----------------|
| **Verdant Vale (Starter)** | Safe | Full protection |
| **City of Dawn** | Safe | Full protection |
| **Major Cities** | Safe | Full protection |
| **Dungeons** | Safe | Full protection (inside) |

#### 8.2.3 Contested Zones (PvP Enabled, No Loot)
| Zone | Level Range | Notes |
|------|-------------|-------|
| **Thornwood Forest** | 10-25 | Moderate risk |
| **Sunfire Desert** | 35-50 | High-level contested |
| **Seasonal Event Zones** | Varies | Limited time |

#### 8.2.4 Full Loot PvP Zones
| Zone | Level Range | Notes |
|------|-------------|-------|
| **Ashfields** | 20-35 | Volcanic, high risk |
| **Shadowfen** | 40-55 | Swamp, ganking popular |
| **Ironpeak Mountains** | 50-60 | Endgame PvP |
| **Open Ocean** | All | Ship PvP |
| **Underworld** | All +20 | Dangerous all around |

### 8.3 Full Loot Mechanics

#### 8.3.1 Death Drop Rules
| Condition | Item Drops |
|-----------|-----------|
| **Safe Zone** | Nothing (cannot die to players) |
| **Contested Zone** | 10% chance: 1 random inventory item |
| **PvP Zone** | 50% chance: 1-3 equipped + 1-2 inventory items |
| **Guild War** | 75% chance: 1-3 equipped + 1-3 inventory items |

#### 8.3.2 Drop Protection
| Protection Type | Behavior |
|----------------|----------|
| **Bind on Pickup** | Cannot be dropped/traded ever |
| **Newbie Protection** | Players < level 10 cannot drop items |
| **Recent Spawn** | 5 min after zone entry, reduced drop chance |
| **PvE Death** | Normal durability loss, no item drops |

#### 8.3.3 Loot Distribution
| Mechanic | Behavior |
|----------|----------|
| **Loot Rights** | Killer (last hit) gets drops |
| **Shared Loot** | Party members can loot (even if not killer) |
| **Loot Timer** | 60 seconds before items disappear |
| **Loot Range** | Must be within 20m of corpse |

#### 8.3.4 Revenge System
| Feature | Specification |
|---------|---------------|
| **Revenge Window** | 5 minutes after being killed |
| **Revenge Kill** | +50% loot from killer |
| **Bounty** | Player gains "bounty" if kills many |
| **Bounty Reward** | 1,000g for killing high-bounty player |

### 8.4 Player vs Player Combat

#### 8.4.1 PvP Damage Modifiers
| Modifier | Value |
|----------|-------|
| **Damage vs Players** | 70% of PvE damage |
| **CC Duration vs Players** | 50% duration |
| **Healing vs Players** | 70% effectiveness |
| **Resilience** | +20% CC reduction per 10 levels |

#### 8.4.2 Level Scaling in PvP
| Scenario | Effect |
|----------|--------|
| **Attacker 10+ levels higher** | Damage reduced 20% |
| **Defender 10+ levels higher** | Damage reduced 20% |
| **Level 10 vs Level 60** | Higher level gets significant reduction |
| **Party PvP** | Highest levels' gap applies to group |

#### 8.4.3 Kill Credit
| Credit Type | Behavior |
|-------------|----------|
| **Last Hit** | Gets kill credit, loot rights |
| **Assists** | 30% damage in last 10s = assist credit |
| **Kill Streak** | Tracked, shown on death screen |
| **Death Streak** | Tracked, affects some mechanics |

### 8.5 Guild Wars

#### 8.5.1 War Declaration
| Requirement | Specification |
|-------------|---------------|
| **Minimum Level** | Guild level 10 (requires members) |
| **Gold Cost** | 10,000g to declare |
| **Acceptance** | Target guild can accept or ignore |
| **Duration** | 7 days, then auto-end |
| **Cooldown** | 24 hours after war ends before new war |

#### 8.5.2 War Mechanics
| Feature | Specification |
|---------|---------------|
| **Kill Credit** | Guild members get bonus loot from enemy guild |
| **War Score** | Kills = points, highest score at end wins |
| **Territory** | Winning guild claims defeated guild's territory |
| **Restrict** | Guild can restrict members during war |

#### 8.5.3 War Rewards
| Reward | Winner | Loser |
|--------|--------|-------|
| **Gold** | +50,000g from pot | Nothing |
| **Territory** | Claim 1 zone | Lose 1 zone |
| **Reputation** | +100 guild reputation | -50 guild reputation |
| **Banners** | War Winner banner | N/A |

### 8.6 Battlegrounds & Arenas

#### 8.6.1 Arena System
| Feature | Specification |
|---------|---------------|
| **Access** | Level 20+ |
| **Queue** | Solo, party, or guild queue |
| **Match Size** | 1v1, 3v3, 5v5 |
| **Map** | Instanced arena |
| **Reward** | Arena currency, cosmetics |

#### 8.6.2 Battlegrounds
| Battleground | Type | Size | Duration |
|--------------|------|------|----------|
| **Capture the Flag** | Objective | 10v10 | 15 min |
| **King of the Hill** | Control | 15v15 | 20 min |
| **Team Deathmatch** | Kill count | 20v20 | 10 min |
| **Siege** | Objective | 25v25 | 30 min |

#### 8.6.3 PvP Rewards
| Reward | Source | Currency |
|--------|--------|----------|
| **Arena Points** | Arena wins | Spent on PvP cosmetics |
| **Battleground Marks** | BG participation | Spent on consumables |
| **Conquest Points** | Weekly PvP | Spent on PvP gear |
| **Honor** | PvP kills | Spent on titles, cosmetics |

### 8.7 Reputation & Karma

#### 8.7.1 Karma System
| State | Behavior |
|-------|----------|
| **Neutral** | Default state, no restrictions |
| **Caution** | After 3 kills in contested zone |
| **Dangerous** | After 5 kills, cannot enter safe zones |
| **Outlaw** | After 10 kills, NPCs attack on sight |

#### 8.7.2 Karma Decay
| State | Decay Rate |
|-------|-----------|
| **Caution** | Decays after 30 min offline |
| **Dangerous** | Decays after 2 hours offline |
| **Outlaw** | Does not decay, must complete quest |

### 8.8 PvP Open Questions

- [ ] **Solo PvP Balance:** Level bracket restrictions (e.g., ±10 levels)?
- [ ] **Ganking Policy:** Encourage or discourage low-level ganking?
- [ ] **PvP Seasons:** Seasonal ranked PvP with leaderboards?
- [ ] **Guild War Frequency:** Limit wars per guild per month?

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

> **Lead:** Engine selection, client/server architecture, networking, database, and DevOps infrastructure.

### 10.1 Engine Selection

#### 10.1.1 Comparison Matrix
| Engine | Mobile Support | Cost | Learning Curve | Asset Store | Recommendation |
|--------|--------------|------|---------------|-------------|----------------|
| **Unity 2023+** | Excellent | 1.8% after $100k revenue | Medium | Extensive | ✓ Recommended |
| **Godot 4** | Good | Free (MIT) | Low-Medium | Limited | Consider for MVP |
| **Unreal 5** | Good | 5% royalty | High | Moderate | Graphics-focused only |

#### 10.1.2 Recommendation: Unity
| Reason | Justification |
|--------|----------------|
| **Mobile Maturity** | Proven Android/iOS export, millions of players |
| **DOTS/ECS** | Performance for large worlds (future) |
| **Netcode** | Mirror, FishNet, Unity NetCode available |
| **Asset Store** | Speed up development with pre-made assets |
| **Documentation** | Extensive mobile optimization guides |

#### 10.1.3 Alternative: Godot 4
| Reason | Justification |
|--------|----------------|
| **No Royalties** | 100% revenue to team |
| **Lightweight** | Better for low-end mobile devices |
| **Rapid Iteration** | Faster build times |
| **Multiplayer** | Built-in High-Level Multiplayer (HLAPI) |

### 10.2 Client Architecture

#### 10.2.1 Unity Project Structure
```
WorldSmith/
├── Assets/
│   ├── Art/           # 3D models, textures, materials
│   ├── Audio/         # Sound effects, music
│   ├── Prefabs/       # Reusable game objects
│   ├── Scenes/        # Level scenes
│   ├── Scripts/       # All C# code
│   │   ├── Core/      # Base classes, managers
│   │   ├── Combat/    # Combat system
│   │   ├── World/     # World generation, zones
│   │   ├── Player/    # Player controls, UI
│   │   ├── Network/   # Networking, sync
│   │   └── UI/        # HUD, menus
│   └── ScriptableObjects/  # Data definitions
├── ProjectSettings/
└── Packages/
```

#### 10.2.2 Core Client Systems
| System | Description | Priority |
|--------|-------------|----------|
| **GameManager** | Master controller, state machine | P0 |
| **SceneManager** | Zone loading, streaming | P0 |
| **InputManager** | Touch, keyboard abstraction | P0 |
| **CameraManager** | 3rd person camera logic | P0 |
| **UIManager** | HUD, menus, popups | P0 |
| **AudioManager** | Sound pool, music | P0 |
| **NetworkManager** | Connection handling | P0 |
| **EntityManager** | Spawn, despawn, pooling | P0 |

#### 10.2.3 Rendering Pipeline
| Setting | Low Quality | Medium Quality | High Quality |
|---------|-------------|----------------|--------------|
| **Render Pipeline** | Built-in | URP | URP/HDRP |
| **Shadow Distance** | 50m | 100m | 200m |
| **Shadow Resolution** | 512 | 1024 | 2048 |
| **Texture Quality** | Half | Full | Full + Mipmap |
| **Particle Density** | 50% | 75% | 100% |
| **LOD Bias** | 2.0 | 1.5 | 1.0 |
| **Max FPS** | 30 | 45 | 60 |

### 10.3 Server Architecture

#### 10.3.1 Server Topology
```
                    ┌─────────────────┐
                    │   Load Balancer │
                    │   (Game Gate)   │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
    ┌────▼────┐        ┌────▼────┐        ┌────▼────┐
    │ Auth    │        │ Game    │        │ Game    │
    │ Server  │        │ Server  │        │ Server  │
    │ (Node)  │        │ (Node 1)│        │ (Node 2)│
    └────┬────┘        └────┬────┘        └────┬────┘
         │                   │                   │
         │              ┌────▼──────────────────▼────┐
         │              │     Redis (Cache/PubSub)  │
         │              └───────────────────────────┘
         │                   │
    ┌────▼──────────────────▼────┐
    │      PostgreSQL Cluster      │
    │   (Players, Characters,     │
    │    Inventory, World State)  │
    └─────────────────────────────┘
```

#### 10.3.2 Server Components
| Component | Technology | Purpose | Priority |
|-----------|-----------|---------|----------|
| **Auth Server** | Node.js/Go | Login, account creation, token generation | P0 |
| **Game Server** | Go/C++ (or Unity with Mirror) | Authoritative world simulation | P0 |
| **Message Queue** | RabbitMQ/Redis | Async event processing | P0 |
| **Database** | PostgreSQL | Persistent player/world data | P0 |
| **Cache** | Redis | Session data, real-time state | P0 |
| **File Storage** | S3/MinIO | Asset storage, logs | P0 |
| **CDN** | CloudFlare/CloudFront | Asset distribution | P0 |

#### 10.3.3 Game Server Features
| Feature | Specification | Priority |
|---------|---------------|----------|
| **Zone Management** | Create/destroy zone instances | P0 |
| **Entity Simulation** | NPCs, mobs, physics | P0 |
| **Combat Resolution** | Damage calculation, CC | P0 |
| **Inventory System** | Item management, trading | P0 |
| **Quest System** | Tracking, completion | P1 |
| **Economy** | Loot drops, currency | P0 |
| **Anti-Cheat** | Speed hack, tele detection | P0 |

### 10.4 Networking

#### 10.4.1 Network Protocol
| Layer | Protocol | Purpose |
|-------|----------|---------|
| **Transport** | UDP (KCP) | Real-time game data, low latency |
| **Reliable** | TCP | Account operations, trading |
| **Encryption** | TLS 1.3 | All connections |
| **Serialization** | FlatBuffers/Protobuf | Compact, fast |

#### 10.4.2 Client-Side Prediction
| Mechanism | Description |
|-----------|-------------|
| **Input Buffer** | Store last 10 inputs locally |
| **Prediction** | Apply input immediately on client |
| **Reconciliation** | Server sends correction, client interpolates |
| **Smoothing** | Blend corrected position over 100ms |

#### 10.4.3 Netcode Specifications
| Parameter | Value | Notes |
|-----------|-------|-------|
| **Client Tick Rate** | 60 Hz | Send input every ~16ms |
| **Server Tick Rate** | 20 Hz | 50ms per tick |
| **Interpolation** | 100ms buffer | Smooth entity movement |
| **Snap Threshold** | 5 units | Teleport if correction > threshold |
| **Timeout** | 10 seconds | Disconnect if no response |

#### 10.4.4 Interest Management
| Technique | Description |
|-----------|-------------|
| **Spatial Hashing** | Divide world into grid cells |
| **AOI (Area of Interest)** | Only sync entities in proximity |
| **Relevancy** | Prioritize nearby entities over distant |
| **Throttling** | Reduce updates for distant entities |

### 10.5 Database Schema

#### 10.5.1 Core Tables
```sql
-- Account (auth server)
CREATE TABLE accounts (
    id UUID PRIMARY KEY,
    username VARCHAR(32) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    last_login TIMESTAMP
);

-- Character (game server)
CREATE TABLE characters (
    id UUID PRIMARY KEY,
    account_id UUID REFERENCES accounts(id),
    name VARCHAR(24) UNIQUE NOT NULL,
    race VARCHAR(20) NOT NULL,
    class VARCHAR(20) NOT NULL,
    level INTEGER DEFAULT 1,
    xp BIGINT DEFAULT 0,
    -- Stats
    strength INTEGER DEFAULT 10,
    agility INTEGER DEFAULT 10,
    intelligence INTEGER DEFAULT 10,
    vitality INTEGER DEFAULT 10,
    endurance INTEGER DEFAULT 10,
    wisdom INTEGER DEFAULT 10,
    -- Position
    zone_id VARCHAR(50),
    x FLOAT, y FLOAT, z FLOAT,
    -- Progression
    skill_points INTEGER DEFAULT 0,
    attribute_points INTEGER DEFAULT 0,
    -- Bind point
    bind_zone VARCHAR(50),
    bind_x FLOAT, bind_y FLOAT, bind_z FLOAT,
    created_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP
);

-- Inventory
CREATE TABLE inventory (
    id UUID PRIMARY KEY,
    character_id UUID REFERENCES characters(id),
    slot INTEGER NOT NULL,
    item_id VARCHAR(50) NOT NULL,
    quantity INTEGER DEFAULT 1,
    durability INTEGER,
    UNIQUE(character_id, slot)
);

-- Equipment
CREATE TABLE equipment (
    character_id UUID REFERENCES characters(id),
    slot VARCHAR(20) PRIMARY KEY, -- head, chest, etc.
    item_id VARCHAR(50),
    durability INTEGER
);

-- Guild
CREATE TABLE guilds (
    id UUID PRIMARY KEY,
    name VARCHAR(32) UNIQUE NOT NULL,
    tag VARCHAR(5) NOT NULL,
    leader_id UUID REFERENCES characters(id),
    level INTEGER DEFAULT 1,
    gold BIGINT DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Guild Members
CREATE TABLE guild_members (
    guild_id UUID REFERENCES guilds(id),
    character_id UUID REFERENCES characters(id),
    rank VARCHAR(20) NOT NULL, -- leader, officer, member
    joined_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (guild_id, character_id)
);
```

### 10.6 Cloud Infrastructure

#### 10.6.1 Recommended Stack
| Service | Provider | Purpose |
|---------|----------|---------|
| **Compute** | AWS EC2 / GCP Compute Engine | Game servers |
| **Database** | AWS RDS / GCP Cloud SQL | PostgreSQL |
| **Cache** | AWS ElastiCache / GCP Memorystore | Redis |
| **Storage** | AWS S3 / GCP Cloud Storage | Assets, logs |
| **CDN** | CloudFlare / AWS CloudFront | Asset delivery |
| **Load Balancer** | AWS ALB / GCP LB | Traffic distribution |
| **Monitoring** | Datadog / CloudWatch | Observability |
| **Logging** | ELK Stack / GCP Logging | Log aggregation |

#### 10.6.2 Estimated Monthly Costs (100 concurrent players)
| Resource | Spec | Est. Monthly |
|----------|------|--------------|
| **Game Servers** | 4x c5.large | $280 |
| **Database** | db.t3.medium | $120 |
| **Cache** | cache.t3.medium | $60 |
| **Storage** | 100 GB | $10 |
| **CDN** | 50 GB transfer | $20 |
| **Load Balancer** | Basic | $25 |
| **Total** | | **~$515/month** |

#### 10.6.3 Scaling Strategy
| Player Count | Servers Needed | Estimated Cost |
|--------------|----------------|----------------|
| 100 concurrent | 2-4 game servers | $300-600/mo |
| 500 concurrent | 10-15 game servers | $1,000-1,500/mo |
| 1,000 concurrent | 20-30 game servers | $2,000-3,000/mo |

### 10.7 Anti-Cheat

#### 10.7.1 Server-Side Validation
| Check | Implementation |
|-------|----------------|
| **Movement** | Validate speed, teleport detection |
| **Combat** | Validate damage, cooldown, range |
| **Loot** | Validate drops, RNG seed server-side |
| **Crafting** | Validate materials, success rates |

#### 10.7.2 Detection Systems
| System | Detection Method |
|--------|-----------------|
| **Speed Hack** | Calculate distance / time, flag anomalies |
| **Teleport** | Detect instant position changes |
| **Aimbot** | Detect perfect aim patterns |
| **Scripting** | Detect input patterns, timing anomalies |
| **Memory** | Integrity checks on client |

### 10.8 CI/CD Pipeline

#### 10.8.1 Build Pipeline
| Stage | Tool | Action |
|-------|------|--------|
| **Trigger** | GitHub Actions | On push/PR |
| **Test** | Unity Test Runner | Unit tests |
| **Build** | Unity Cloud Build | Android/iOS builds |
| **Sign** | Platform tools | Code signing |
| **Deploy** | Custom script | Push to CDN/store |

#### 10.8.2 Server Deployment
| Stage | Tool | Action |
|-------|------|--------|
| **Build** | Docker | Containerize servers |
| **Test** | Kubernetes | Deploy to staging |
| **Deploy** | Helm/Kubectl | Rolling update to prod |
| **Monitor** | Datadog | Watch metrics/logs |

### 10.9 Technical Open Questions

- [ ] **Engine Decision:** Unity or Godot? (Need to decide for development to begin)
- [ ] **Server Language:** Go for performance or C# for Unity parity?
- [ ] **Database:** PostgreSQL sufficient or need sharding strategy?
- [ ] **Launch Scale:** Target concurrent players at launch?
- [ ] **Hosting:** Self-host, AWS, or game hosting provider?

---

## 11. Art & Audio Direction

> **Lead:** Visual style, quality tiers, and audio implementation.

### 11.1 Visual Style

#### 11.1.1 Art Direction Philosophy
| Principle | Description |
|-----------|-------------|
| **Stylized Realism** | Realistic proportions, stylized colors/textures |
| **Readability** | Clear silhouettes, distinct character classes |
| **Performance** | Optimized for mobile, LOD-ready |
| **Cohesion** | Unified color palette per zone |

#### 11.1.2 Lighting
| System | Description | Priority |
|--------|-------------|----------|
| **Dynamic Sun** | Moving light source, day/night cycle | P0 |
| **Ambient Occlusion** | Contact shadows | P0 (High/Medium) |
| **Global Illumination** | Baked + dynamic | P1 |
| **Bloom** | Light glow effects | P0 (Medium/High) |
| **Shadows** | Dynamic shadows from key lights | P0 |

#### 11.1.3 Weather Effects
| Weather | Visual | Gameplay |
|---------|--------|----------|
| **Clear** | Default | None |
| **Cloudy** | Gray sky, ambient shift | Reduced visibility |
| **Rain** | Particles, puddles | Slippery surfaces |
| **Storm** | Rain + lightning | Reduced vision |
| **Fog** | Density fog | Reduced visibility |
| **Snow** | Particle snow | Cold damage outside |

### 11.2 Character Art

#### 11.2.1 Character Design
| Element | Specification |
|---------|---------------|
| **Style** | Humanoid with distinct silhouettes per race/class |
| **Proportions** | ~7 heads tall (realistic) |
| **Detail Level** | High-quality on visible areas, lower on hidden |
| **Customization** | Face, hair, skin, markings |
| **Equipment Visibility** | Clear equipment display on character |

#### 11.2.2 Character Races
| Race | Silhouette Distinction | Color Palette |
|------|----------------------|---------------|
| **Human** | Balanced, medium build | Natural skin tones |
| **High Elf** | Tall, slender, long ears | Pale, ethereal |
| **Orc** | Large, muscular, tusks | Green/gray skin |
| **Dwarf** | Short, stocky, beard | Earth tones |
| **Shadow Elf** | Slender, hooded, mysterious | Dark purples/blacks |

#### 11.2.3 Equipment Tiers
| Tier | Visual Quality | Detail |
|------|---------------|--------|
| **Cloth** | Flowing robes, magical effects | Medium |
| **Leather** | Straps, pouches, practical | Medium-High |
| **Mail** | Chain patterns, protective | High |
| **Plate** | Heavy, ornate, intimidating | Very High |

### 11.3 Environment Art

#### 11.3.1 Terrain
| Element | Specification |
|---------|---------------|
| **Textures** | 512×512 base, 1024×1024 for key areas |
| **Trees** | LOD 4 levels (Billboard → Low → Med → High) |
| **Rocks** | Modular rock system |
| **Water** | Shader-based with reflection |
| **Ground Cover** | Grass billboards, flower patches |

#### 11.3.2 Architecture
| Element | Specification |
|---------|---------------|
| **Building Style** | Medieval fantasy |
| **Modular Kit** | Wall segments, roofs, doors |
| **Towns** | 5-10 unique building types, repeated |
| **Dungeons** | Modular interior kit |

### 11.4 VFX (Visual Effects)

#### 11.4.1 Combat Effects
| Effect | Type | Priority |
|--------|------|----------|
| **Hit Sparks** | Particles on impact | P0 |
| **Damage Numbers** | Floating text | P0 |
| **Projectiles** | Arrows, spells, abilities | P0 |
| **AOE Indicators** | Ground targeting circles | P0 |
| **Buff/Debuff Icons** | Above character | P0 |

#### 11.4.2 Skill Effects by Class
| Class | Effect Style |
|-------|--------------|
| **Warrior** | Slash marks, impact flashes, ground cracks |
| **Mage** | Elemental particles, arcane circles, explosions |
| **Rogue** | Quick slashes, smoke, poison clouds |
| **Priest** | Holy light, healing particles, shields |
| **Ranger** | Arrow trails, nature effects, traps |

### 11.5 Audio

#### 11.5.1 Sound Design
| Category | Examples | Priority |
|----------|----------|----------|
| **Combat** | Swords clash, spell impacts, footsteps | P0 |
| **UI** | Button clicks, notifications, menu open/close | P0 |
| **Environment** | Wind, water, birds, ambient | P0 |
| **NPC** | Greetings, merchant calls, combat taunts | P0 |
| **Pickups** | Item equip, loot, coin sounds | P0 |

#### 11.5.2 Music
| Type | Description | Priority |
|------|-------------|----------|
| **Main Menu** | Ambient title theme | P0 |
| **Combat** | Dynamic battle music | P0 |
| **Town** | Peaceful, welcoming | P0 |
| **Dungeon** | Tense, mysterious | P0 |
| **Boss** | Epic, dramatic | P0 |
| **PvP** | Intense, competitive | P1 |

#### 11.5.3 Audio Settings
| Setting | Options |
|---------|---------|
| **Master Volume** | 0-100% |
| **Music Volume** | 0-100% |
| **SFX Volume** | 0-100% |
| **Voice Volume** | 0-100% |
| **Mute on Background** | On/Off |
| **Spatial Audio** | On/Off (mobile: Off default) |

---

## 12. Mobile Optimization

> **Lead:** Performance targets, quality tiers, and mobile-specific features.

### 12.1 Performance Targets

#### 12.1.1 Frame Rate Targets
| Quality | Target FPS | Minimum FPS | Description |
|---------|------------|-------------|-------------|
| **Low** | 30 FPS | 25 FPS | Smooth on budget phones |
| **Medium** | 45 FPS | 30 FPS | Good balance |
| **High** | 60 FPS | 50 FPS | Flagship phones |
| **PC (Future)** | 60+ FPS | 60 FPS | No cap |

#### 12.1.2 Memory Targets
| Metric | Target | Maximum | Priority |
|--------|--------|---------|----------|
| **RAM Usage** | < 1.5 GB | 2.0 GB | P0 |
| **VRAM** | < 500 MB | 800 MB | P0 |
| **App Size** | < 500 MB | 1 GB | P0 |
| **Initial Load** | < 30s (fast 3G) | 60s | P0 |

#### 12.1.3 Network Targets
| Metric | Target | Priority |
|--------|--------|----------|
| **Latency Tolerance** | < 200ms playable | P0 |
| **Packet Loss Tolerance** | < 5% acceptable | P0 |
| **Reconnection** | 60s timeout, auto-retry | P0 |
| **Offline Mode** | Partial (single player zones) | P1 |

### 12.2 Quality Tiers

#### 12.2.1 Graphics Settings
| Setting | Low | Medium | High |
|---------|-----|--------|------|
| **Shadow Quality** | Off | Soft | Hard |
| **Shadow Distance** | 20m | 50m | 100m |
| **Texture Quality** | Half | Full | Full + Mipmap |
| **View Distance** | Low | Medium | High |
| **Particle Density** | 25% | 50% | 100% |
| **Anti-Aliasing** | Off | FXAA | MSAA 2x |
| **V-Sync** | Off | On | On |
| **Terrain Quality** | Low | Medium | High |
| **Grass Density** | Low | Medium | High |
| **LOD Multiplier** | 2.0 | 1.5 | 1.0 |

#### 12.2.2 Auto-Detection
| Device Tier | Criteria | Default Quality |
|------------|----------|-----------------|
| **Low** | < 3GB RAM, Mali-4xx, Adreno 3xx | Low |
| **Medium** | 3-6GB RAM, Mali-6xx, Adreno 5xx | Medium |
| **High** | > 6GB RAM, Mali-G7x, Adreno 6xx+ | High |

#### 12.2.3 Quality Presets
| Preset | Target Device | Use Case |
|--------|--------------|----------|
| **Battery Saver** | Any | Maximize battery life |
| **Balanced** | Any | Default recommended |
| **Performance** | High-end | Maximize FPS |
| **Quality** | High-end | Maximize visuals |

### 12.3 Touch Controls

#### 12.3.1 Control Layout
```
┌────────────────────────────────────────────────────────┐
│  [Menu]              [Mini-Map]              [Social] │
│                                                        │
│                     [3D WORLD]                         │
│                                                        │
│                   [Target Info]                        │
│                   [Damage Numbers]                     │
│                                                        │
│  ┌─────┐                                               │
│  │JOYST│   [HP ████████] [MP ████████] [STA ████]    │
│  │     │                                               │
│  │  ◯  │  [1]  [2]  [3]  [4]  [5]                    │
│  └─────┘  [6]  [7]  [8]  [9]  [0]                    │
│                    [Dodge] [Target]                    │
└────────────────────────────────────────────────────────┘
```

#### 12.3.2 Virtual Joystick
| Setting | Specification |
|---------|---------------|
| **Size** | 120px diameter (adjustable) |
| **Opacity** | 30-80% (adjustable) |
| **Dead Zone** | 15% of radius |
| **Position** | Left side, draggable |
| **Invert Y** | Option for camera |

#### 12.3.3 Camera Control
| Control | Input | Behavior |
|---------|-------|----------|
| **Rotate** | Right drag | 360° horizontal, vertical clamp |
| **Zoom** | Pinch | 3-10 unit distance |
| **Reset** | Double tap right side | Return behind character |

#### 12.3.4 Skill Buttons
| Feature | Specification |
|---------|---------------|
| **Layout** | 2 rows × 5 buttons |
| **Size** | 64px minimum tap target |
| **Opacity** | 50-100% (adjustable) |
| **Position** | Bottom center, adjustable |
| **Cooldown** | Radial fill + icon tint |
| **Range Indicator** | Show when targeting |

#### 12.3.5 Additional Controls
| Control | Input | Action |
|---------|-------|--------|
| **Dodge** | Single tap | Roll in movement direction |
| **Target** | Single tap enemy | Select target |
| **Interact** | Tap NPC/object | Interact |
| **Auto-Run** | Double tap joystick | Toggle autorun |
| **Camera Lock** | Swipe down on right | Toggle follow mode |

### 12.4 UI/UX Optimization

#### 12.4.1 Screen Support
| Aspect | Specification |
|--------|---------------|
| **Portrait** | Supported for menus, character creation |
| **Landscape** | Primary gameplay mode |
| **Tablet** | Scaled UI, additional buttons |
| **Notch** | Safe area padding |
| **Foldables** | Aspect ratio adaptation |

#### 12.4.2 UI Scaling
| Element | Base Size | Scale Range |
|---------|-----------|--------------|
| **Skill Buttons** | 64px | 48-80px |
| **Hotbar** | Full width | 80-120% |
| **Resource Bars** | 200px wide | 150-250px |
| **Minimap** | 150px | 100-200px |
| **Text** | 16sp base | 14-20sp |

#### 12.4.3 Accessibility
| Feature | Implementation | Priority |
|---------|---------------|----------|
| **Colorblind Mode** | Color shift presets | P1 |
| **Font Size** | 3 presets (small, medium, large) | P0 |
| **UI Scale** | 80-120% slider | P0 |
| **Button Size** | Large touch targets | P0 |
| **Screen Reader** | Basic narration | P2 |

### 12.5 Battery & Thermal

#### 12.5.1 Power Saving
| Feature | Behavior |
|---------|----------|
| **Frame Cap** | Option: 30/45/60 FPS |
| **Background Pause** | Pause game when backgrounded |
| **Reduced Effects** | Diminishing options for battery |
| **Brightness** | In-game brightness slider |

#### 12.5.2 Thermal Management
| Level | Action |
|-------|--------|
| **Normal** | Full performance |
| **Warm** | Reduce particle effects |
| **Hot** | Lock to 30 FPS, reduce quality |
| **Critical** | Prompt user, reduce further |

### 12.6 Platform Specifics

#### 12.6.1 Android
| Requirement | Specification |
|-------------|---------------|
| **Min SDK** | Android 8.0 (API 26) |
| **Target SDK** | Android 14 (API 34) |
| **Architecture** | ARM64 (primary), ARMv7 |
| **Store** | Google Play Store |
| **Signing** | Release keystore required |

#### 12.6.2 iOS
| Requirement | Specification |
|-------------|---------------|
| **Min iOS** | iOS 14 |
| **Target iOS** | iOS 17 |
| **Device** | iPhone 8+ |
| **Store** | Apple App Store |
| **Signing** | Apple Developer account |

---

## 13. Phases & Milestones

### Phase 0: Foundation (Current)
- [x] Complete PRD
- [ ] Choose engine (Unity vs Godot)
- [ ] Set up dev environment
- [ ] Design core architecture
- [ ] Create Git repository structure

### Phase 1: Vertical Slice (3-6 months)
**Goal:** Playable prototype proving core mechanics

| Milestone | Deliverables |
|-----------|--------------|
| **M1.1** | Engine setup, empty scene, touch controls |
| **M1.2** | Player movement (walk, jump, dodge) |
| **M1.3** | Third-person camera following |
| **M1.4** | 3 enemy types with basic AI |
| **M1.5** | 5 skills for one class (Warrior) |
| **M1.6** | Basic combat loop (auto-attack, skills) |
| **M1.7** | UI: HUD, skill bar, target info |
| **M1.8** | Mobile build: APK running on device |

### Phase 2: Core Loop (6-12 months)
**Goal:** Complete core gameplay systems

| Milestone | Deliverables |
|-----------|--------------|
| **M2.1** | All 5 classes implemented (25 skills each) |
| **M2.2** | Leveling system (1-60) |
| **M2.3** | Skill trees and attribute allocation |
| **M2.4** | Inventory and equipment system |
| **M2.5** | 3 zones (starter, mid, PvP) |
| **M2.6** | Basic crafting (2 professions) |
| **M2.7** | Party system (5 players) |
| **M2.8** | Mobile-optimized builds |

### Phase 3: World Building (6-12 months)
**Goal:** Full world with MMO features

| Milestone | Deliverables |
|-----------|--------------|
| **M3.1** | All 7 zones of main continent |
| **M3.2** | 5 dungeons (1 solo, 3 group, 1 raid) |
| **M3.3** | Full crafting system (7 professions) |
| **M3.4** | Player housing (small/medium houses) |
| **M3.5** | Guild system (create, invite, ranks) |
| **M3.6** | Auction house and trading |
| **M3.7** | Server infrastructure (auth, game, DB) |
| **M3.8** | Anti-cheat system |

### Phase 4: MMO Features (6-12 months)
**Goal:** Full persistent world experience

| Milestone | Deliverables |
|-----------|--------------|
| **M4.1** | Full loot PvP zones |
| **M4.2** | Guild wars |
| **M4.3** | Battlegrounds and arenas |
| **M4.4** | Procedural dungeons |
| **M4.5** | Underworld zone |
| **M4.6** | Dimensional planes (2-3) |
| **M4.7** | World events and dynamic spawns |
| **M4.8** | Player economy balance |

### Phase 5: Polish & Launch (3-6 months)
**Goal:** Production-ready game

| Milestone | Deliverables |
|-----------|--------------|
| **M5.1** | Full optimization pass |
| **M5.2** | Bug fixes and balance tuning |
| **M5.3** | Store listings (Google Play, App Store) |
| **M5.4** | Launch marketing |
| **M5.5** | Soft launch / beta |
| **M5.6** | Full release |
| **M5.7** | Community building |

**Total Estimated Timeline: 24-48 months**

---

## 14. Open Questions

### Game Design
1. **Engine Decision:** Unity or Godot? (Critical for development start)
2. **Server Language:** Go for performance or C# for Unity parity?
3. **Level Cap:** 60 final, or expandable?
4. **Hybrid Class Unlock:** Free or require quest?
5. **Crafting Failures:** Materials lost on failure?
6. **Housing Style:** Instanced or shared world (UO-style)?

### Business/Monetization
7. **RMT Policy:** Allow, ban, or embrace with official store?
8. **Subscription:** Consider optional subscription for perks?
9. **Platform Priority:** Android first, iOS later, or simultaneous?

### Technical
10. **Launch Scale:** Target concurrent players at launch?
11. **Database Sharding:** Need from day 1 or scale later?
12. **Hosting:** Self-host, AWS/GCP, or game hosting provider?

---

## Appendix

### A. Reference Games
| Game | Reference Element |
|------|------------------|
| **Risk Your Life 2** | Combat feel, tab-targeting hybrid, skill combos |
| **Ultima Online** | Player housing, full loot PvP, player-driven economy |
| **World of Warcraft** | Quest structure, dungeon design, raid encounters |
| **Black Desert Online** | Mobile optimization, action combat, world feel |
| **EVE Online** | Player economy, territorial control |

### B. Industry Benchmarks
| Metric | Industry Standard | Target |
|--------|------------------|--------|
| **Retention D1** | 25-35% | 30% |
| **Retention D7** | 10-15% | 15% |
| **Retention D30** | 5-8% | 8% |
| **Session Length** | 15-30 min | 20 min |
| **Time to LTV** | $5-10 ARPDAU | $5 min |

### C. Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **Scope Creep** | High | High | Strict PRD, phase gates |
| **Mobile Performance** | Medium | High | Early optimization, testing |
| **Server Costs** | Medium | Medium | Auto-scaling, optimize |
| **Content Drought** | High | High | Procedural generation, UGC |
| **Cheating** | High | High | Server-side validation, monitoring |
| **Team Burnout** | Medium | High | Realistic timelines, automation |

---

*Document Version: 1.0*
*Last Updated: 2024*
*Status: Draft — Pending Engine Selection*
