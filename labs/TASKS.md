# Synmergia Development Tasks

> **Purpose:** Track active development tasks, blockers, and pending features.
> **Status:** Live document - update as work progresses.

---

## Completed Tasks ✅

### Title System
- [x] TitleData schema with prefix/suffix forms
- [x] TitleService for managing titles (with color support)
- [x] TitleUI panel for equip/unequip
- [x] Titles tab in CharacterPanel
- [x] NamePlate support for title display (auto-fetches from TitleService)
- [x] Achievement → Title unlock wiring
- [x] `Entity.get_full_display_name()` method

### Achievement System
- [x] AchievementData schema with rewards
- [x] AchievementService for tracking
- [x] AchievementUI with filtering and progress bars
- [x] Notification popup on unlock
- [x] Gold/XP rewards structure (placeholder logging)
- [x] Achievement unlock persistence to player data

### Dialogue System
- [x] Fixed `@global_class` annotation errors
- [x] Dictionary-based node storage
- [x] DialogService with proper loading (2 dialogues)

---

## Deferred / Future Tasks

### Services Needed
| Service | Purpose | Status |
|---------|---------|--------|
| `EconomyService` | Gold/currency management | TODO |
| `LevelService` | XP and leveling | TODO |
| `PlayerDataService` | Save/load character data | TODO |

### UI Components Needed
| Component | Status | Notes |
|-----------|--------|-------|
| TitleSelectionPopup | ✅ In TitleUI | Could be extracted to separate file |
| AchievementDetailPopup | ❌ Missing | Show rewards, progress details |
| TitleColorPicker | ✅ In TitleUI | Could be enhanced |

### Database / Persistence
- Player character data save/load
- Achievement progress persistence
- Title unlock state persistence
- See `prd-state-schema.md` for schema design

---

## Scene Integration Checklist

### Core Scenes
- [ ] `res://scenes/world/World.tscn` - Main game scene
- [ ] `res://scenes/ui/Hud.tscn` - In-game HUD
- [ ] `res://scenes/ui/CharacterSheet.tscn` - Character panel

### UI Components to Wire
- [ ] `TitleUI` → CharacterPanel Titles tab
- [ ] `AchievementUI` → HUD or menu button
- [ ] `NamePlate` → Entity rendering (signals needed)
- [ ] `DialogUI` → NPC interaction

---

## Testing Required

### Title System
1. [ ] Unlock title via achievement
2. [ ] Equip/unequip prefix title
3. [ ] Equip/unequip suffix title  
4. [ ] Title appears on name plate
5. [ ] Title color customization works

### Achievement System
1. [ ] Track enemy kill → progress updates
2. [ ] Complete achievement → notification appears
3. [ ] Gold/XP reward applied (when services exist)
4. [ ] Title unlocked automatically
5. [ ] Category filter works

### Dialogue System
1. [ ] NPC interaction opens dialog
2. [ ] Choices display correctly
3. [ ] Advancing through nodes works
4. [ ] Dialog ends properly

---

## Implementation Notes

### Title Color
TitleService now stores `title_color` per player (Color(0,0,0) = default). Use:
```gdscript
TitleService.get_title_color(player_id)  # Returns custom color or black
TitleService.set_title_color(player_id, Color(...))  # Set custom color
```

### NamePlate Integration
`NamePlate.show_for()` auto-fetches titles for PLAYER type:
```gdscript
# Just call without title params for auto-fetch:
name_plate.show_for(entity, NamePlate.PlateType.PLAYER, entity.display_name, entity.level)
```

### Gold/XP Reward Implementation
When EconomyService/LevelService are created:
```gdscript
# In AchievementService._apply_gold_reward():
EconomyService.add_gold(player_id, amount, "achievement_%s" % achievement_id)

# In AchievementService._apply_xp_reward():
LevelService.add_xp(player_id, amount)
```

---

_Last updated: 2026-09-06_
