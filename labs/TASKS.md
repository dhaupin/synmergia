# Session Scratch Pad

Wipe and reuse each session. This file is mine to use as
persistent memory across resets.

## Orchestration (Kilo Code Towns)

### Branching model
- `main` — shared integration branch. Always pull before starting.
- `labs/*` — experimental / docs work. Push here first.
- Feature branches: `kilo/<topic>` or `town/<topic>`. One branch per town.
- Never rebase `main` while another town is working. Use merge commits.

### Before you start a task
1. `git pull origin main` — check for parallel work.
2. Read the bottom of this file for recent completions.
3. Check `prd-db.md` section 2 + section 8 for service ownership.
4. Mark your task `in_progress` with your town name + timestamp.
5. If the task touches `game/` AND `labs/`, coordinate with both towns.

### Task ownership tags
Use these in the task list:
- `[town:core]` — core services, autoloads, entities
- `[town:adapter]` — persistence/cache/memory adapters
- `[town:bridge]` — pg-bridge, redis-bridge, docker
- `[town:ui]` — HUD, panels, targeting, social
- `[town:docs]` — TASKS.md, prd-db.md, DEPLOY.md
- `[town:test]` — lint, smoke, adapter tests

### Merge rules
- Push to your branch, open PR, wait for CI (lint + parse check).
- Do not force-push to `main`.
- If merge conflicts: ask in town channel, do not resolve silently.
- After merge: update `## Recently Completed (2026-09-09)

- [x] Created game/adapters/persistence/dict_store.gd (RefCounted KV wrapper)
- [x] LoginService: replaced user://accounts.json with DictStore
- [x] PlayerConfig: replaced ConfigFile with DictStore  
- [x] AccountService: added DictStore persistence for accounts/characters
- [x] SecurityService: persist player restrictions (bans/mutes)
- [x] WaypointService: persist player waypoints across restarts
- [x] FollowService: persist active follows per player
- [x] VaultService: persist personal/guild/account vaults
- [x] PartyService: persist parties and pending invites
- [x] TitleService: persist unlocked player titles
- [x] QuestService: persist player quest progress
- [x] AchievementService: persist unlocked player achievements
- [x] GuildService: persist guild state and invites
- [x] TradeService: persist completed trade history
- [x] ShardManager: persist shard info
- [x] LootService: persist player loot history
- [x] CooldownService: migrated to CacheWrapper with TTL expiration
- [x] DictStore enhanced with batch ops (set_batch, get_many, erase_batch)
- [x] CacheWrapper created for CacheStore with TTL support
- [x] Branch kilo/festive-ribbon-wav pushed to origin