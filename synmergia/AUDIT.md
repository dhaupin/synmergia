# Synmergia MMORPG Engine - Audit Report

**Date:** 2026-08-29  
**Engine:** Godot 4.7.2 (upgraded from 4.2+)  
**Language:** GDScript  
**Architecture:** Authoritative Server

---

## Roadmap

### Phase 1: Core Infrastructure
- [x] Upgrade Godot to 4.7.2
- [x] Fix game_config.gd (removed class_name conflict, fixed Logger calls)
- [x] Fix qos_service.gd (removed class_name, fixed GameConfig paths, added missing variables)
- [x] Fix respawn_service.gd indentation
- [ ] Fix remaining ~40 scripts with parse errors

### Phase 2: Type Dependencies (Main Blocker)
Services that use custom types (Entity, Item, etc.) in signal definitions fail because those types aren't registered yet.

**Options:**
1. Add Entity, Item, etc. as singletons/autoloads to force load order
2. Remove type hints from signal definitions (use Variant)
3. Create interface/base classes that are autoloaded
4. Restructure service architecture to use composition over inheritance

### Phase 3: StatusEffect Consolidation
Consolidate buff, aura, and DoT systems into unified StatusEffect class.

**Current files:**
- `core/combat/status_handlers.gd`
- `core/combat/buff.gd` (class_name Buff)
- `core/components/aura_component.gd`

**Target:** Single `core/entities/status_effect.gd` with:
- Base StatusEffect class
- Buff (stat modifiers, duration-based)
- Aura (area-effect, continuous)
- DamageOverTime (DoT)
- HealOverTime (HoT)

---

## Executive Summary

The Synmergia MMORPG Engine has **41 scripts with parse/compilation errors** preventing the project from loading. The root cause was `game_config.gd` which has been fixed. The remaining issues stem from missing type definitions, a missing Logger autoload, space vs tab indentation inconsistencies, and some syntax errors.

---

## ✅ Completed Fixes

### 1. Godot 4.7.2 Upgrade
- Downloaded Godot_v4.7.2-stable_linux.x86_64 to /tmp/
- Binary is executable and validated

### 2. game_config.gd - Fixed
**Location:** `synmergia/core/autoload/game_config.gd`

**Issues Fixed:**
- Removed `class_name GameConfig` (conflicted with autoload singleton)
- Renamed inner `EventBus` class to `EventBusConfig` (avoided conflict)
- Fixed `Logger.info()` and `Logger.debug()` calls (Logger doesn't exist yet)
- Converted space indentation to tabs (Respawn class had 2 tabs, needed 1)
- Removed duplicate line: `const MAX_INPUT_VALUE: float = 10000.0`
- Fixed multiple space indentation issues throughout file

**Current Status:** ✅ Loads successfully

---

## 🔴 Remaining Parse Errors: 41 Scripts

### Error Categories

#### 1. Missing Type Definitions (Root Cause of ~25 errors)
These types are referenced but never defined:

| Type | Files Using It |
|------|----------------|
| Entity | entity_service.gd, event_bus.gd, targeting_manager.gd |
| Item | inventory_service.gd, trade_service.gd |
| Buff | multiple services |
| AuraBuff | targeting/buff systems |
| DamageOverTime | combat services |
| StatusEffect | buff systems |
| CharacterClass | player/character services |
| Faction | faction_manager.gd, guild_service.gd |
| Skill | skill systems |
| Species | character creation |
| ZoneData | zone_manager.gd, world_service.gd |
| NPCData | spawn_service.gd |
| EnemyData | entity_service.gd |
| QuestData | quest systems (implied) |
| DwellingData | housing (implied) |
| GatewayData | zone systems (implied) |
| PlayerController | input_manager.gd |
| InventoryComponent | inventory_service.gd |
| TargetTooltip | ui_manager.gd |
| RespawnUI | respawn_ui_manager.gd |
| DiscordWebhook | webhook_manager.gd |
| EventData | event_bus.gd |

#### 2. Missing Logger Autoload (~15 errors)
The Logger autoload singleton doesn't exist. Scripts call:
- `Logger.info()`
- `Logger.debug()`
- `Logger.warn()`
- `Logger.error()`

**Affected Files:**
- game_manager.gd
- network_manager.gd
- player_manager.gd
- input_manager.gd
- qos_service.gd
- data_service.gd
- entity_service.gd
- event_bus.gd
- zone_manager.gd
- And ~7 more services

#### 3. Space vs Tab Indentation (~10 files)
**Critical Finding:** Godot 4.x uses **tabs** for indentation, but many files use **spaces**.

**Files with indentation issues:**
| File | Issue |
|------|-------|
| qos_service.gd | Enum values use 5 spaces instead of 1 tab |
| Multiple service files | 4-space or 8-space indentation |
| game_config.gd | Respawn class, Security class had wrong indentation |

#### 4. Singleton Name Conflicts
- `class QoSService` inside qos_service.gd conflicts with the autoload `qos_service.gd`
- Similar issue with `RespawnService` in respawn_service.gd

#### 5. Syntax Errors
- Unclosed brackets/braces
- Bad match statements
- Unindent doesn't match previous level
- Empty function bodies without `pass`
- `join()` called on Array (should be `join("")`)

---

## 📋 Failed Scripts List

```
res://core/admin/permission_manager.gd
res://core/admin/player_reporter.gd
res://core/autoload/game_manager.gd
res://core/autoload/input_manager.gd
res://core/autoload/network_manager.gd
res://core/autoload/player_manager.gd
res://core/autoload/qos_service.gd
res://core/autoload/security_monitor.gd
res://core/autoload/webhook_manager.gd
res://core/community/community_governance.gd
res://core/input/interaction_layer.gd
res://core/services/account_service.gd
res://core/services/anticheat_service.gd
res://core/services/auto_response_service.gd
res://core/services/blacksmith_service.gd
res://core/services/chat_service.gd
res://core/services/data_service.gd
res://core/services/death_features.gd
res://core/services/entity_service.gd
res://core/services/event_bus.gd
res://core/services/faction_manager.gd
res://core/services/guild_service.gd
res://core/services/inventory_service.gd
res://core/services/loot_service.gd
res://core/services/notification_service.gd
res://core/services/party_service.gd
res://core/services/respawn_service.gd
res://core/services/same_account_transfer_service.gd
res://core/services/security_service.gd
res://core/services/server_manager.gd
res://core/services/shard_manager.gd
res://core/services/spawn_service.gd
res://core/services/trade_service.gd
res://core/services/world_service.gd
res://core/services/zone_manager.gd
res://core/targeting/targeting_manager.gd
res://core/ui/ui_manager.gd
res://core/utils/admin_commands.gd
res://core/utils/app_firewall.gd
res://ui/menus/main_menu.gd
res://ui/respawn/respawn_ui_manager.gd
```

---

## 🔧 Recommended Fix Order

### Phase 1: Create Missing Infrastructure
1. Create `Logger` autoload (stub implementation)
2. Create base types in `synmergia/core/types/`:
   - Entity.gd
   - Item.gd
   - Buff.gd (base for AuraBuff, DamageOverTime, StatusEffect)
   - Faction.gd
   - CharacterClass.gd

### Phase 2: Fix Indentation (Bulk Fix)
Create a script to convert all 4-space and 8-space indentations to tabs across the codebase.

### Phase 3: Fix Syntax Errors
Address individual parse errors in remaining scripts.

### Phase 4: Resolve Conflicts
- Rename `QoSService` class inside qos_service.gd
- Fix RespawnService class/singleton conflict

---

## 📝 Roadmap Addition

### StatusEffect Consolidation Project

**Priority:** Medium  
**Description:** Consolidate and simplify modifier systems for buffs, auras, DOTs, and other status effects into a unified `StatusEffect` system.

**Current State:**
- Multiple overlapping systems: `Buff`, `AuraBuff`, `DamageOverTime`, `StatusEffect`
- Duplicated logic for stat modifications
- Inconsistent application/removal patterns

**Proposed Approach:**
1. Create unified `StatusEffect` base class with:
   - Type enum: BUFF, DEBUFF, AURA, DOT, HOT, CROWD_CONTROL
   - Modifier system for stats (additive/multiplicative)
   - Duration management
   - Stacking rules
   - Priority system for conflicting effects

2. Refactor existing systems:
   - `AuraBuff` → `StatusEffect` with type=AURA
   - `DamageOverTime` → `StatusEffect` with type=DOT
   - `Buff` → `StatusEffect` with type=BUFF

3. Benefits:
   - Single source of truth for status logic
   - Easier balancing (all modifiers in one place)
   - Cleaner combat calculations
   - Better save/load for character state

---

## 📁 Project Structure

```
synmergia/
├── core/
│   ├── autoload/
│   │   ├── game_config.gd ✅ FIXED
│   │   ├── qos_service.gd 🔴 NEEDS FIX
│   │   ├── network_manager.gd 🔴
│   │   ├── player_manager.gd 🔴
│   │   ├── game_manager.gd 🔴
│   │   ├── input_manager.gd 🔴
│   │   ├── security_monitor.gd 🔴
│   │   └── webhook_manager.gd 🔴
│   ├── services/
│   │   ├── entity_service.gd 🔴
│   │   ├── event_bus.gd 🔴
│   │   ├── zone_manager.gd 🔴
│   │   ├── data_service.gd 🔴
│   │   └── [30+ more services] 🔴
│   ├── admin/
│   ├── community/
│   ├── input/
│   ├── targeting/
│   ├── ui/
│   └── utils/
├── ui/
│   ├── menus/
│   └── respawn/
└── project.godot
```

---

## 🛠️ Tools Available

- Godot 4.7.2: `/tmp/Godot_v4.7.2-stable_linux.x86_64`
- Test command: `--headless --quit` (validates scripts on load)

---

## 📊 Metrics

- **Total GDScript files:** ~50+
- **Files with parse errors:** 41
- **Error types:** 60+ unique error messages
- **Estimated fix time:** 2-4 hours for full resolution

---

*End of Audit Report*
