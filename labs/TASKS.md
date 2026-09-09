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
- [x] Created game/adapters/cache/cache_wrapper.gd (CacheStore wrapper)
- [x] Created game/adapters/memory_layer/memory_wrapper.gd (MemoryStore wrapper)
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
- [x] FactionManager: persist factions, reputations, alliances
- [x] AntiCheatService: persist suspicion scores and bans
- [x] DeathFeatures: persist death stats and kill streaks
- [x] RespawnService: persist karma per entity
- [x] ChatService: persist ignored lists and player settings
- [x] AutoResponseService: persist exploit counts
- [x] PlayerLockService: persist lock state
- [x] VendorService: persist buyback items
- [x] SkillAcademyService: persist skill progression
- [x] WorldService: persist gateway definitions + active events
- [x] FairnessService: persist trust scores and session data
- [x] ConnectorService: persist connected agent registrations
- [x] SameAccountTransferService: persist transfer stats
- [x] MatchmakingQoS: persist latency/quality/packet loss data
- [x] NotificationService: persist notification history per entity
- [x] DataService: fixed directory bugs, added canonical getters
- [x] ZoneManager: persist zone definitions and active instances
- [x] EntityService: persist entity metadata on spawn/despawn
- [x] InventoryService: persist player inventories with Item serialization
- [x] NetworkManager: persist peer mappings via CacheWrapper
- [x] FriendsService: persist online status via CacheWrapper with TTL
- [x] ServerManager: persist server lifecycle state via DictStore
- [x] DictStore enhanced with TTL, batch ops, sweep_expired
- [x] CacheWrapper created for CacheStore with TTL support
- [x] MemoryWrapper created for MemoryStore access
- [x] Migration V20260909_001__init_kv.sql created
- [x] Adapter tests: test_dict_store, test_dict_store_ttl, test_service_integration, test_adapter_e2e
- [x] Bridge tests pass: pg-bridge 12/12, redis-bridge 20/20
- [x] Branch kilo/festive-ribbon-wav pushed to origin
- [x] Branch kilo/heavy-services-arch pushed to origin