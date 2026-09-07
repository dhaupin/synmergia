# Session Scratch Pad

Wipe and reuse each session. This file is mine to use as
persistent memory across resets.

## 2026-09-07 — second session

**Goal:** Extend prd-db.md with adapter layer + scope the full
DB / cache / Redis surface across the codebase before writing
code.

**Hold:** Build of .gd files deferred until the parallel agent
finishes. This session is docs only.

**On user's safety note:** another agent is working under us.
Pull main before push. Push to `labs/db` branch when ready.

## Active

- [x] Pull main (clean — no parallel commits)
- [x] Move `game/adapters/tests/` → `game/tests/adapters/`
- [x] Update `game/adapters/README.md` to reflect move
- [ ] Sweep `game/core/services/` for persistence touchpoints
- [ ] Sweep `game/core/autoload/` for persistence touchpoints
- [ ] Sweep `game/core/admin/`, `community/`, `connectors/`
- [ ] Sweep `game/data/` for reference-data shapes
- [ ] Update prd-db.md §2 (Adapter column) and §3 (schemas)
      with anything found
- [ ] Re-clarify prd-db.md §10 transport language

## Notes for myself

- Test naming: `test_<thing>.gd` in `game/tests/` (existing convention)
- Existing persistence patterns to look for:
  - `user://` / `res://` file paths (LoginService JSON)
  - `OS.execute` / `OS.shell_open`
  - HTTPRequest / `http_request` to other services
  - JSON serialization (`JSON.stringify` / `JSON.parse_string`)
  - Timer + Dict combos (cache pattern)
  - Existing sql/db files
- The `MultiIsoService` is already a working HTTP bridge —
  the pg-bridge / redis-bridge should follow the same shape

## Found

### Persistence touchpoints already in code

- **`login_service.gd:24`** — `const SAVE_PATH := "user://accounts.json"`
  Hand-rolled JSON persistence of `accounts` + `sessions` Dict.
  Calls `FileAccess.WRITE` and `JSON.stringify(_store)`.
  This is the de-facto `AccountStore` / `SessionStore` impl,
  just on local file instead of Postgres+Redis.

- **`player_config.gd:24-26`** — three ConfigFile paths:
  - `user://account_settings.cfg`
  - `user://settings/char_%s.cfg`
  - `user://global_settings.cfg`
  Per-account + per-character settings. Needs `PlayerConfigStore`
  (or a sub-store inside the existing `AccountStore`).

- **`character_select.gd:167`** + **`lobby.gd:185`** — both write
  `user://characters.json`. Duplicated persistence logic. Needs
  to go through the registry.

- **`logger.gd:18`** — `user://logs/game.log` for game-side logs.
  Already fine (separate concern, not adapter-layer).

- **`chat_service.gd:194-213`** — profanity words file
  (`user://config/profanity_words.txt`). Already a runtime
  config file load. Could stay on disk, but probably belongs
  in the `GameDataStore` (it's reference data, not user data).

- **`security_monitor.gd:59-110`** — `JSON.stringify(details)`
  used to format exploit evidence for logging. The store-side
  anti-cheat is the `AntiCheatStore` (in §2); logging is fine
  on its own.

- **`game_config.gd:221`** — `PROFANITY_WORDS_FILE` constant.
  Same file as chat_service. Same conclusion.

### In-memory state that maps to a store (already in §2)

- `cooldown_service.gd:9` — `_cooldowns: Dictionary`
- `login_service.gd:36` — `_current_session_token`
- `login_service.gd:41` — `_store: Dictionary` (the accounts)
- `login_service.gd:54, 157` — `_check_rate_limit` (in-memory
  rate limiting; should move to Redis once the bridge lands)
- `entity_service.gd:14-19` — `_entities`, `_players`, `_enemies`,
  `_npcs`, `_entity_metadata`
- `trade_service.gd:19, 25` — `_active_trades`, `_players_in_trade`
- `shard_manager.gd:16, 20` — `_online_players`, `_connected_shards`
- `waypoint_service.gd:106, 108` — `_player_waypoints`, `_active_waypoint`
- `world_service.gd:19` — `_active_events`
- `loot_service.gd:7, 12, 16` — `_active_loot`, `_player_loot`,
  `_need_greed_rolls`
- `zone_manager.gd:18` — `_players_in_zone`
- `follow_service.gd:21` — `_active_follows`
- `friends_service.gd:67` — `_online_players`
- `faction_manager.gd:14` — `_active_wars`
- `respawn_service.gd:109` — `_active_revives`
- `anticheat_service.gd:21` — `_player_profiles`
- `connector_service.gd:18` — `_connected_agents`
- `dialog_service.gd:21, 22` — `_dialogues`, `_current_dialogue`
- `player_lock_service.gd:16` — `_player_locks`
- `matchmaking_qos.gd:43-47` — `_player_latency`, `_player_quality`,
  `_player_packet_loss`, `_player_jitter`, `_latency_history`
- `data_service.gd:25-34` — `_skills`, `_items`, `_weapons`,
  `_armors`, `_accessories`, `_consumables`, `_resources`
  (template loaders — would be replaced by Postgres-backed
  `GameDataStore` with Redis cache)

### Reference data on disk that should be in `GameDataStore`

The `data/` directory has 26 subdirs containing ~200 `.tres`
files across 18 schemas:

- achievements (8) / titles (9) / skills (8) / classes (22)
- armors (1) / weapons (2) / consumables (2) / resources (1) / misc (1)
- buffs (1) / status_effects (62)
- containers (3) / dialogues (2) / dwellings (2) / enemies (5) / events (1)
- factions (4) / gateways (3) / loot_tables (3) / npc (2) / npcs (9)
- npc_offerings (9) / quests (4) / species (3) / targets (6) / zones (4)

These are loaded at runtime via `data_service.gd` (file scan)
or directly via `preload("res://data/.../foo.tres")`. The
schemas average 20-50 `@export` fields each — these all become
columns in `GameDataStore` tables.

### Connectors (HTTP, not adapter-layer)

These are NOT adapter-layer concerns (they're outbound
service calls to third-party APIs, not DB/cache backends):

- `connectors/mcp/mcp_connector.gd:115-120` — JSON-RPC over
  WebSocket
- `connectors/vant/vant_connector.gd:18-85` — REST + Bearer auth
- `connectors/webhook/webhook_base.gd:93-110` — outbound HTTP
- `core/services/multi_iso_service.gd:25-137` — HTTP to
  Julia orchestrator

These go in their own `connectors/` adapter pattern, not
under `game/adapters/`. (Future expansion — flag for §7.4.)

### Services missing from §2 (10 found)

Need to add to the §2 table + §8 wiring:

- `DialogService` — dialogue state. Runtime only (in-memory);
  templates come from `data/dialogues/*.tres` via `GameDataStore`.
- `ConnectorService` — agent connector registry. Runtime only
  (in-memory); agent metadata probably needs Postgres though.
- `PlayerConfig` — per-player settings. **Persists to disk
  today** (`user://...cfg`); needs a real `PlayerConfigStore`.
- `PlayerLockService` — pure in-memory lock state.
- `ScreenshotService` — saves PNG to disk; not adapter-layer.
- `SlotService` — the unified slot container manager
  (inventory, bank, vault, house, mount, equipment, loot,
  shop, trade). Its backing data is `InventoryStore` +
  `VaultStore` + `TradeStore`. Worth a top-level row to make
  the service discoverable.
- `StarterKitService` — static consts; `InventoryStore` for
  what gets granted.
- `VendorService` — buy/sell transactions; `TradeStore` for
  history, `InventoryStore` for stock changes.
- `MatchmakingQoS` — already in PRD as `MatchmakingQoS`
  (camelCase). I had it as `MatchmakingStore`. Align.
- `NotificationService` — in PRD; already in §2. No change.

### Schemas not yet covered by §3

- `ankh.gd` (27 exports) — respawn / save point. Tied to
  `RespawnStore`. Add a `respawn_points` table.
- `dialogue_data.gd` (4 exports) — narrative trees. Loaded
  from `data/dialogues/`. Belongs in `GameDataStore`.
- `npc_offering.gd` — shop inventory. Vendor-side, belongs
  in `GameDataStore` (templates) + `InventoryStore` (instances).
- `container_config_data.gd` — slot configs. `GameDataStore`.
- `target_schema.gd` — targeting metadata. `GameDataStore`
  (per `data/targets/*.tres`).
- `species.gd` — race definitions. `GameDataStore`.
- `event_data.gd` — world events. `GameDataStore` (templates)
  + `WorldStateStore` (instances).
- `agent_connector.gd` + `agent_action.gd` — agent integration
  shapes. Probably goes in `ConnectorStore` (new — agents need
  their own auth/permissions/audit trail).

## Done this session

- [x] Moved `game/adapters/tests/` to `game/tests/adapters/`
- [x] Pulled main (no parallel commits)
- [x] Full sweep of services, autoloads, admin, community, data, connectors
- [x] prd-db.md extended to 1150 lines:
      - §2 added Adapter column + 8 missing services
      - §3 added §3.10-§3.20 (respawn_points, dialogues,
        npc_offerings, container_configs, target_schemas,
        species, world_events, agent_connectors,
        player_settings, existing-to-migrate list,
        data/*.tres inventory)
      - §5-§10: adapter architecture, contracts, backends,
        wiring, migrations, transport
      - §11: open questions including the transport
        mechanism decision and the connectors question
      - §5: clarified the five terms (Layer / Store /
        Adapter / Registry / Transport)
      - §10: explicitly scoped what "transport" means
        vs. doesn't (connectors, MultiIsoService)
- [x] All encoding fixed: 0 mojibake chars, file is clean UTF-8

## On hold (per user)

- [ ] First migration SQL — schemas in §3 not yet locked
- [ ] Building .gd files (interfaces, memory stubs, registry)
- [ ] pg-bridge / redis-bridge sidecar scaffolding
- [ ] Pushing to labs/db branch (waiting for the parallel agent)

## Found (already in TASKS.md above)

8 new services added to §2: DialogService, ConnectorService,
PlayerConfig, PlayerLockService, SlotService, StarterKitService,
VendorService, ScreenshotService.

10 new tables in §3: respawn_points, dialogues, npc_offerings,
container_configs, target_schemas, species, world_events,
world_event_instances, agent_connectors, agent_actions,
player_settings.

Existing hand-rolled persistence to migrate (5 paths):
user://accounts.json, 3 user://*.cfg, 2 user://characters.json,
user://config/profanity_words.txt, user://logs/game.log.

26 subdirs of data/*.tres = ~200 reference data files, all
headed for GameDataStore via a one-shot loader.

## 2026-09-07 Session 2 — Autoload/class_name audit + AGENTS.md rules

### What happened

Other agent on main mass-deleted 20k lines of business logic in 43
service/component/UI files (a9ede10) to "fix Godot 4.7.2 parse errors"
by reducing them to 3-line stubs. They re-implemented 6 critical
files (b2fc65e) but left 42 others gutted.

Recovery:
- Discovered the `/backup/2026-09-07-0320est` branch had clean
  pre-damage code + 30+ legitimate feature commits
- Reset adapter-layer to 8dbd2a1, then `git rebase --onto backup 2af7c05`
  replayed my 2 adapter commits onto backup with zero conflicts
- Final state: backup base + my adapter layer, 0 gutted files

### AGENTS.md update

Replaced the misleading "Autoloads" section with "Autoloads and
class_name" covering:
- The two rules (no name collisions, no .new() on autoloads)
- When to add class_name (and when not to)
- The Entity latent-bug case (active in spawn_service.gd)
- Autoload order + forward reference detection
- Three flavors of cycle (_ready, preload, autoload name)
- Self-recovery playbook (5 steps)
- Diagnostic commands (awk + grep one-liners)

### Found latent bug (NOT YET FIXED)

`class_name Entity` in `game/core/entities/entity.gd` is also
listed as `Entity` autoload in `project.godot`. Code at
`game/core/services/spawn_service.gd:246, 487` calls `Entity.new()`.
This will fail at runtime. Workaround: use a subclass
(`EnemyEntity`, `NPCEntity`) or `load(...).new()`. Documented in
AGENTS.md but the bug itself remains.

### Next session

Recommended order:
1. Fix the Entity collision (Option A: split base + singleton)
2. Wire first 3 services to AdapterRegistry (per prd-db.md §10)
3. Test the wired services in headless
4. Then continue with the rest of the services


