# Synmergia Implementation Tasks

## Completed Systems

### Title System
- TitleData schema
- TitleService - 9 titles
- Title UI
- NamePlate integration
- title_color support

### Achievement System
- AchievementData schema
- AchievementService - 8 achievements
- Achievement UI
- Achievement -> Title unlock wiring

### Quest System
- QuestData schema
- QuestService
- Quest UI

### Dialog System
- DialogueData schema
- DialogService - 2 dialogues
- Dialog UI

## Infrastructure
- DataService loads titles and achievements
- get_all_titles() method added
- Auto-loading in services

## Pending / Future Work
- Test NPC dialog triggering
- Test quest offering flow
- Test achievement unlock -> title unlock
- Test title display in gameplay
- Add more content and integration points

## Notes
- Gold color reserved for GM titles only
- Prefix + suffix title slots per player
