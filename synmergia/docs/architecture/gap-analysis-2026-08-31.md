# Synmergia Gap Analysis — 2026-08-31

## What works (verified by tests)

- **Account lifecycle**: register, login, logout, guest, wrong-password rejection (test_login_flow + test_e2e_flow, 56/56 OK)
- **Rate limiting**: 5 wrong attempts in 5 min → blocks even correct password (test_e2e_flow)
- **Game state machine**: all 7 states (LOADING, LOGIN, MAIN_MENU, LOBBY, CHARACTER_SELECT, PLAYING, PAUSED) present in GameManager
- **Scene swap chain**: every state handler in GameManager calls `change_scene_to_file` to the right .tscn
- **HUD layer**: 14 widget children instantiated under HudLayer; HudIntegrator installed and bound (test_hud_integration)
- **Targeting system**: TargetingManager autoload present, 6 schemas loaded, 17 actions
- **UI Islands**: 19/19 islands tests pass
- **Boot**: main scene boots cleanly, all 20 types register, no parse errors

## What's stubbed or partial (gaps)

### High priority
1. **Settings button on main menu** — `_on_settings_pressed` shows a notification
   "Settings coming soon" instead of opening SettingsPanel.
2. **world_playable.tscn misattach warning** — engine logs
   `Script inherits from native type 'CharacterBody3D', so it can't be assigned
   to an object of type 'CollisionShape3D'`. Does NOT prevent scene load.
   Likely a stale PackedScene cache; needs editor re-import.
3. **TODO backlog in services**:
   - `quest_service.gd:30,58,86,96` — Load from quest database
   - `vault_service.gd:120,314,330,353,376,380,384,388` — Persistence + gold math
   - `friends_service.gd` — clean (no TODOs in current tree)

### Medium priority
4. **HUD widget binding** — HudIntegrator wires all 14 widgets but only basic
   signals (health/mana/xp/level) are tested. Targeting, auras, dialog, settings
   need separate integration tests.
5. **QoS rate limiting** — the LoginService has its own rate limiter (5/5min),
   but the QoSService autoload is separate. Single source of truth needed.

### Low priority / polish
6. **LoadingUI** — Defined as a class with `static var instance` but the HUD
   scene instantiates a `LoadingUI` Control child. Two coexisting systems.
7. **Chat profanity list** — `user://config/profanity_words.txt` not present.
8. **DataService item path** — `res://data/items` not present, only `data/` variants.

## Bug scan results

- `chat_ui.gd` previously called nonexistent `PlayerManager.get_local_player()`
  and `get_local_player_id()`. Fixed in c8cd1e4 to use `PlayerManager.local_player`
  property with null guards.
- 0 hardcoded credentials detected in `core/services/` or `ui/`.
- 0 unhandled null dereferences in HUD paths tested.
- Several `TODO` comments remain in services — see above.

## Security review (initial)

- Passwords stored (presumably hashed) in `user://accounts.dat`. Need to
  verify: (a) hashing algorithm, (b) timing-attack resistance.
- LoginService rate-limits per account_id. Need to verify per-IP limiting too.
- ChatService has profanity filter placeholder; until list ships, content
  is unfiltered.
- Admin dashboard reachable from any GM class. Ensure GM promotion is gated
  by `account_level >= admin_threshold`.

## Performance

- 107 SkillAcademyService skills loaded on boot. Profile to confirm
  acceptable.
- 20 type classes registered via TypeRegistry autoload. Acceptable for 20
  but does not scale to 200.
- LootService + QuestService + VaultService all autoload. Heavy startup.
  Consider lazy-init after login.

## What I would do next session

1. Build a smoke test that boots the full main menu and walks:
   MAIN_MENU → LOGIN → register → LOBBY → CHARACTER_SELECT → play → PAUSED
   → exit. Currently each is tested in isolation.
2. Fix the SettingsPanel wire-up.
3. Investigate the world_playable CharacterBody3D error in-editor with
   `godot --editor --path .` to confirm it's a stale cache.
4. Ship the profanity list or document its absence.
5. Implement one TODO from each service (quest, vault, friends) to clear
   the backlog incrementally.
