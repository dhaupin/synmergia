# Session Log: Captures + Control Layer

**Date:** 2026-09-04  
**Branch:** `labs/captures`  
**Status:** Pushed to GitHub ✓

---

## What We Built

### Login Flow (Now Working!)
```
Main Menu → Login (F5) → Lobby → Create (F5) → CharSelect → Lobby → Play (F6) → PLAYING
```

**Keyboard Shortcuts for Headless Testing:**
| Key | Context | Action |
|-----|---------|--------|
| F5 | Login | Guest login |
| F5 | Lobby | Create character |
| F5 | CharSelect | Auto-select first species/class |
| F6 | Lobby | Play selected character |
| F6 | CharSelect | Confirm & save character |
| F3 | Anywhere | Toggle DebugOverlay |

### DebugOverlay
- Shows: current game state, hovered element, mouse position
- Toggle with F3
- Useful for AI agent inspection and debugging

---

## Files Modified

### Core Fixes
| File | Issue | Fix |
|------|-------|-----|
| `game/ui/components/debug_overlay.gd` | `get_node("/root/...")` crash | Use `get_tree().root.get_node_or_null()` |
| `game/ui/hud/hud_integrator.gd` | Empty `else:` block | Removed dead else clause |
| `game/ui/menus/character_select.gd` | `.get()` on resource | Use `.property` directly |
| `game/ui/menus/character_select.gd` | Character not saved | Call `_lobby_save_character()` before returning to lobby |
| `game/core/autoload/game_manager.gd` | Mixed tabs/spaces | Fixed indentation |

### New Features
| File | Purpose |
|------|---------|
| `game/ui/components/debug_overlay.gd` | UI inspection layer |
| `game/ui/menus/login.gd` | F5 guest shortcut |
| `game/ui/menus/lobby.gd` | F5/F6 shortcuts, character_confirmed signal |
| `game/ui/menus/character_select.gd` | F5/F6 shortcuts, auto-save |

---

## Known Issues

### 1. Scene Structure Warnings
**Problem:** "Parent path has vanished" warnings when loading `world_playable.tscn`
```
WARNING: Parent path './Player' for node 'CollisionShape3D' has vanished when instantiating
```

**Root Cause:** Relative paths in scene breaking during instantiation

**Fix:** Convert relative paths to absolute or use `get_node()` with absolute paths

### 2. Character Auto-Select After Return
**Problem:** When CharacterSelect saves & returns to LOBBY:
- LOBBY scene is unloaded then reloaded
- `_ready()` runs fresh (no signal connection)
- User must manually select character + click Play

**Proposed Fix (Option A - Proper):**
1. Store last-created character ID in `GameManager.set_meta("last_character_id", id)`
2. In LOBBY `_ready()`: if `last_character_id` exists, auto-select that character
3. Clear meta after selection

---

## Architecture Proposal: Input Handler

### Why a Unified Input System?

Currently inputs are scattered:
- `InputManager` for mode detection
- `InteractionLayer` for mouse/keyboard
- Individual `_input()` handlers in menus
- `TargetingManager` for target actions

**Problem:** Changing input style (gamepad, touch, voice, accessibility) requires touching many files.

**Solution:** Single `InputService` that:
1. Normalizes all inputs to canonical `Action` objects
2. Routes to appropriate handlers
3. Enables hot-swapping input sources

### Proposed Structure
```
InputService (autoload)
├── InputSource[] sources
│   ├── KeyboardSource
│   ├── GamepadSource  
│   ├── VoiceSource (future)
│   ├── AccessibilitySource (future)
│   └── AISource (for agent control)
├── action("target_nearest")
├── action("cast_skill", "healing_totem")
├── action("open_menu", "inventory")
└── InputMapper (configures bindings)
```

### Benefits
- **Single source of truth** for all inputs
- **Hot-swap input sources** at runtime
- **A11y integration point** - voice/eye-tracking map to same `action()` calls
- **Testing** - can inject synthetic inputs easily

### Implementation Path
1. Extract `InteractionLayer` input handling to `InputService`
2. Create `InputSource` interface
3. Add `KeyboardSource` implementation
4. Wire through existing `TargetingManager` / `ActionMenu`

---

## Accessibility (A11y) Architecture

### Control Layer Dual-Purpose

The same control layer we build for AI agents enables accessibility:

| User | Input Method | Same Action? |
|------|-------------|-------------|
| AI Agent | `action("target_nearest")` | ✓ |
| Motor impairment | Voice recognition | ✓ → calls `action()` |
| Limited mobility | Eye tracking dwell | ✓ → calls `action()` |
| Visual impairment | Screen reader | Reads same UI nodes |

### A11y MVP Scope
1. **Tab navigation** - focus cycling with Shift+Tab
2. **Screen reader labels** - `accessible_label` on Controls
3. **Control layer** - `action()` interface ready for voice/eye inputs

### Voice Integration (Deferred)
- Note: Hold on building voice integration
- Will need: `webkitSpeechRecognition` or external service
- Must discuss later with team

### A11y Dashboard (Future)
- Configurable control schemes
- Visual/audio feedback options
- Input remapping

---

## Screenshots Architecture

### Current State
- Location: `game/captures/screenshots/`
- Naming: Sequential (00-main-menu.png, 01-login.png, etc.)
- Issue: Naming is inconsistent, storage location unclear

### Proposed Structure
```
labs/screenshots/
├── YYYY-MM-DD-session-name/
│   ├── 00-main-menu.png
│   ├── 01-login.png
│   ├── 02-lobby.png
│   ├── ...
│   └── metadata.json
└── README.md
```

### Naming Convention
```
{sequence:02d}-{screen-id}-{action}.png
```

Example:
- `00-main-menu-overview.png`
- `01-login-guest-click.png`
- `02-lobby-character-selected.png`

---

## Session Commits

| Commit | Description |
|--------|-------------|
| `ca4bf72` | feat: keyboard shortcuts for headless testing + auto character creation |
| `2cd0722` | fix: hud_integrator empty else block |
| `78e641e` | feat: full login flow working end-to-end |

---

## Next Session Priorities

### ✅ Completed
1. **Auto-select character in lobby** ✅ - Done (lobby.gd lines 45-51)
2. **Scene structure warnings** ✅ - Done (world_playable.tscn CapsuleShape3D + CapsuleMesh sub_resources added, commit 2d932b2)

### P1 - Should Have  
3. **Tab navigation** - Add focus cycling to main menus (in progress)
4. **Screen reader labels** - Add `accessible_description` to key UI Controls (in progress)

### P2 - Nice to Have
5. **Screenshot naming/archiving** - Proper folder structure (`labs/screenshots/`)
6. **Input handler extraction** - Begin `InputService` architecture

### P3 - Future
- Voice integration (discuss with team)
- A11y dashboard
- Eye tracking support

---

## Notes for Next Session

1. **Start with:** Pull `labs/captures` branch
2. **Test:** Run full login flow before making changes
3. **Check:** Look for parse errors in `hud_integrator.gd`, `debug_overlay.gd`
4. **Input Handler:** Consider extracting from `InteractionLayer` as first step

---

## Resources

- Godot Input system: https://docs.godotengine.org/en/stable/tutorials/inputs/
- A11y in games: https://gameaccessibilityguidelines.com/
- Godot accessibility: https://docs.godotengine.org/en/stable/tutorials/assets/importing/importing_accessibility_resources.html
