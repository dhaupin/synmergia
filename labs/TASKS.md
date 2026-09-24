# Session Scratch Pad

Persistent memory across resets for Synmergia development.
**Condensed 2026-09-23**: full historical session logs live in
[TASKS_ARCHIVE.md](./TASKS_ARCHIVE.md) (verbatim copy of this file at
commit fc316b1). Git history is the durable record; this file tracks
CURRENT state + ACTIVE work only.

## Orchestration (Kilo Code Towns)

### Branching model
- `main`  -  shared integration branch. Always pull before starting.
- `labs/*`  -  experimental / docs work. Push here first.
- Feature branches: `kilo/<topic>` or `town/<topic>`. One branch per town.
- Never rebase `main` while another town is working. Use merge commits.

### Before you start a task
1. Pull latest `main`  -  check for parallel work.
2. Read this file for current state + the archive for history.
3. Check `prd-db.md` section 2 + section 8 for service ownership.
4. Mark your task `in_progress` with your town name + timestamp.
5. If the task touches `game/` AND `labs/`, coordinate with both towns.

### Task ownership tags
- `[town:core]`  -  core services, autoloads, entities, login/seed flow
- `[town:frame]`  -  T3 substrate, seed chain, state tree, scope engine, geometry
- `[town:adapter]`  -  persistence/cache/memory adapters
- `[town:bridge]`  -  pg-bridge, redis-bridge, docker, backup scripts
- `[town:web]`  -  HUD, panels, portal, admin dashboard, WASM client
- `[town:docs]`  -  TASKS.md, world-building PRDs, arch specs
- `[town:test]`  -  lint, syntax, smoke, unit & integration tests

---

## PRD Roadmap Status (details in archive + world-building-arch.md)

- **Phase 1 (KV substrate, canonical trees)**  -  COMPLETE
- **PRD-DB storage/persistence layer**  -  COMPLETE (35+ services on adapters)
- **PRD-WEB web client + admin portal**  -  COMPLETE (wasm export green in CI)
- **Phase 2 (rules engine, world integration)**  -  COMPLETE (RulesEngine
  consolidation: QoS, Security, AppFirewall, AutoResponse)
- **Phase 3 (memory + social trees, definition tree)**  -  COMPLETE (all
  three trees load-bearing: EnemyAI memory, FriendsService social mirror,
  ZoneManager zone defs)
- **Phase 4 (tick pipeline, AOI, LOD, horde scale)**  -  COMPLETE
  (zone-aware AOI diff, L0/L1 LOD tiers, peer bridge, tick-routed
  projection writes)
- **Phase 5 (NSC-9 integration bridge)**  -  COMPLETE
- **Frame extract to container**  -  DEFERRED in-process (FrameClient +
  local RulesEngine fallback per world-building-arch.md sec. 11.2)

## Live gameplay systems (all verified in-world)

- Combat loop: spawn -> AI -> aggro/threat -> taunts -> kill credit
  (direct killer or threat owner) -> XP/gold rewards -> quests ->
  achievements. Bosses included (bare-Entity bosses carry enemy_data on
  base Entity, spawn in-tree, deaths route through KillRewards).
- Loot: EnemyData loot tables (resolver) -> ground drops (visuals +
  minimap) -> pickup (auto-loot, party rules FFA/round-robin/leader/
  master, class routing, karma gates) -> inventory. Skill books expand
  through SkillAcademyService; academy upgrades burn real inventory.
- Death/respawn: ankh bind (personal/guild/faction via PlacementAccess),
  respawn modes, durability loss, PvP/duel drop rules.
- Housing: plots, house guards, personal ankhs (DwellingService).
- Guards: per-player hostility (GuardAI), watch sharing, spawn sanctuary.
- Hordes: HordeData .tres configs (mixed-template waves, per-wave
  payouts, instance scoping), HordeEventService state machine, HordeBar
  UI, proportional rewards, horde achievements, /horde command
  (config_id, zone, `alert` override for open-world events).
- Flex spawns: /boss <template> [zone] [name...] [world|zone|none]
  (standalone bosses: world/zone/quiet metadata, multi-word names),
  /spawn <template> [count] [zone] [level] (on-demand enemies, capped
  at 24, level-override scaling), pure-boss-wave hordes, bossless
  open-world hordes, mid-horde wave champions (per-wave boss_template_id
  + boss_name, "wave champion" vs finale messaging), per-wave payouts
  merged at boss death. Enemy.spawn_data_applied flag: pre-configured
  level/stats survive Enemy._ready's template reload (the level-7 slime
  regression). Demo configs: horde_haven_siege (bossless siege,
  bosses_alert) + horde_boss_gauntlet (3 boss waves).
- Combat cosmetics pass: damage numbers are school-colored (red
  physical / violet magic / white true / orange CRIT override; heal
  green via show_heal). EventHub.damage_dealt widened with is_crit
  (all 5 emitters + 5 handlers migrated). Crit roll lives in
  Skill.calculate_damage (_last_was_crit) and rides take_damage ->
  EventHub, so floats/log/toast style one roll. Crits get the [CRITICAL]
  combat-log line + a deduped CRITICAL! toast (local-player hits only,
  3s dedupe window). Scene HUD now uses typed CombatLog methods
  (log_damage/log_critical/log_heal/log_loot) so the Damage/Healing/
  Loot filter buttons actually route. Entity.take_damage gained
  damage_type + is_crit params and EMITS damage_dealt itself (bare
  Entity/bosses/NPCs now report); school-based mitigation: physical vs
  armor (get_defense), magical vs get_magic_resistance, min 1 chip.
  Enemy.take_damage applies EnemyData armor/resist by school -- the
  dummy's 25/40 finally do something visible. Enemy heals also emit
  heal_dealt. Guard.take_damage aligned to the new parent signature.
  Fixed: magical DoTs crashed (take_magical_damage never existed ->
  routed through take_damage "magical"); Entity.heal now caps + emits
  heal_dealt + no-ops at 0; reward_player_stub gained declared
  health_component (undeclared assignment silently skipped the ankh
  dead-player asserts -- ground_loot now 44 asserts).
  test_full_boot_live at 43 asserts: crit roll proven end-to-end
  (bot agility boosted, crit observed on the signal + toast fired).
- Integration audit (post boss/horde side-quest) found + fixed four
  dead wires: (1) heal_dealt signal on EventHub -- heals had NO event,
  so no heal floats and no combat-log lines; health_component.heal
  emits it (zero-heals silent, guard regen bypasses heal() so no
  spam), world_playable bridges it to show_heal + log (local-player
  filter). (2) World-boss KILL announcements -- spawns announced,
  kills never did; _on_boss_entity_died now broadcasts WORLD BOSS
  DEFEATED via notify() (runtime lookup, NotifKind.CUSTOM, dedupe by
  entity_id), world-boss flag bound at connect time so horde wave
  champions sharing the handler stay quiet. (3) Level-up toasts --
  notify_level_up existed with ZERO callers; NotificationService._ready
  connects PlayerManager.level_up (loads after PM: reverse connect
  would resolve null; live run shows the toast firing). (4) Bare-Entity
  bosses never emitted damage_dealt (Enemy/HealthComponent was the only
  emitter) -- boss fights showed no damage numbers; spawn_service
  mirrors Entity.took_damage into EventHub.damage_dealt.
- Hit table wired (MWo-style single roll): CombatMath.calculate_hit
  splits ONE randf() into miss -> dodge -> parry -> block -> crit ->
  hit (misses roll first so they can never crit; crit takes only the
  leftover segment). Level penalty fixed -- the old clamp penalized
  fighting DOWN, exactly backwards. Defensive chances derive from the
  target's real stats: dodge/agility, parry/strength (halved without
  shield), block shield-gated + vitality. Duck-typed across both
  combatant families (bare Entity/Enemy AND PlayerController) -- the
  old version dereferenced combat_component and would have thrown on
  the live player the first time it ran. Wiring: Skill.calculate_damage
  runs the roll (cached in _last_hit_result); whiffs return 0 and BOTH
  Skill.execute and CombatSystem._apply_hit skip take_damage(0) (the
  Enemy armor floor would chip 1 on a miss) and skip on-hit effects/CC;
  EnemyAI._perform_attack rolls the same table for enemy swings.
  EventHub.hit_resolved (attacker, defender, outcome dict, skill,
  amount) fires for BOTH outcomes from all three emitters;
  world_playable._on_hit_resolved renders defender-side Miss/Dodge/
  Parry floats, "Blocked <chip>" annotations, log_miss/log lines, and
  defender toasts through notify_combat (YOU dodged / your swing
  missed). CombatMath.hit_label is the shared label source and
  is_whiff() the family test. Tests: test_hit_table.gd (34 asserts, 8
  groups) de-flaked three ways that matter for future tests: (1) load()
  entity.gd/skill.gd AFTER boot, never parse-time preload -- both
  reference EventHub at compile time, and a --script-mode preload
  before autoloads poisons the cached script so .new() vanishes with
  "Nonexistent function 'new'" while _fails stays 0; also no `: Skill`
  type annotations in the test (same poison, different door). (2) await
  every async group -- un-awaited group calls race quit() and the
  summary prints while pending groups never run. (3) deterministic
  chance-curve asserts over raw frequency comparisons, huge HP pool on
  the whiff dummy (a landed execute used to kill + free it mid-test),
  and whiff-family asserts instead of flavor-locked EVADE (agi 1000
  stacks miss+parry, so the first whiff is a coin flip between flavors).
  Same load()-after-boot fix applied to test_combat_pipeline.gd (which
  also had a real hang: a silent script error aborted its coroutine
  before quit()) and test_entity_autoload.gd (load() inside _init hit
  the same poison; 8/8 green again).
- Play session (play_session.gd): a bot hero PLAYS the real scene under
  xvfb -- chat, dummy sparring through the new hit table, class skills,
  slime cull with kill rewards, an honest boss duel (no smites; hitbox
  swings + mid-fight top-ups), haven_siege spectating + sweep, dungeon
  gateway tour, dev screenshots, printed journal. One run observed
  hit x119, miss x27, dodge x11, parry x1 across the session. Playing
  found + fixed two production bugs: (1) GuardData declared the
  GuardDuty ENUM but never the guard_duty FIELD -- guard_ai's leash
  check threw 5,675 script errors per siege and never fenced; field
  declared (default TOWN_WATCH) + house_guard() now stamps PERSONAL.
  (2) test_placement_system's GuildPlayer inner-class extends of the
  stub crashed script-mode compilation (parse-time entity.gd load);
  extracted to tests/support/guild_player_stub.gd, applied via
  set_script. Placement 65/65, guard 31/31, full-boot 43/43. Also
  logged: solo /say sends return false (empty audience rejects your own
  echo) -- authentic MMO behavior, not a bug.
- Party/loot/reward chains verified live: kill_rewarded -> quest
  objectives + achievements + XP/gold grant + PlayerManager mirror;
  party split via PartyService.share_xp with per-member grants;
  loot pickup -> LootRulesService delegation (FFA/RR/leader/master,
  class routing, karma gates) -> InventoryService.add_item ->
  currency via add_gold -> toasts (ITEM_TRANSFERRED / bags full /
  reserved-for-other). Boss loot tables pay (void_lord: skill-book
  table + 500g + 5000xp).
  data/world_bosses/ (SpawnService scans at boot). Respawn counted
  from DEATH (interval_seconds), not spawn; first_delay_s settles the
  server before the first appearance; window_seconds despawns unclaimed
  bosses and rearms the timer; announce=false mutes the spawn callout;
  interval 0 = one-shot (loop completes on death). Admin surface:
  /boss schedule list|info|run|stop|start (start reloads the .tres by
  convention path). Demo: forest_void_lord (3h interval, Gloomwood
  Meadow). Wedge guards: bosses destroyed without died still rearm the
  timer; run_now returns the live boss instead of duplicating it.
- Dungeon loop: world_playable registers the authored gateway .tres
  (data/gateways/dungeon_forest_depths_entrance.tres) as a targetable
  portal; dungeon zone declares horde_config_id="vault_seal" so the
  FIRST player entry auto-starts the instance horde (late joiners pin
  without re-start). DataService.get_horde serves configs from the
  catalog (bare + file-stem ids); list_configs merges catalog + scan.
- Training dummy: is_dummy flag on EnemyData -> Enemy refuses an AI
  brain + aggro component (attach_ai gate covers scene, SpawnService,
  horde waves, respawn cycle), take_damage/heal work for dmg/resist
  measurement, death chain skips loot roll + kill rewards entirely but
  still unregisters so the scene respawn cycle rebuilds it. Placed in
  town in world_playable (enemy_training_dummy.tres, 5000 HP, armor
  25 / resist 40, 15s respawn).
- Chat: commands (/horde /duel /lootrule /buyplot ...), channel
  restrictions, profanity/security/QoS pipeline.
- UI: 24 panels alive (UIPanel base-panel heal), touch HUD, camera
  settings fully wired, web input bridge (GDScript + JS contract).

## State-tree projection (resync architecture)

- FrameService owns the SHARED world state tree; `world_root_hash()` is
  the single resync key for clients.
- PlayerProgress projects durable character state under `/player/<id>/`.
- Instance hordes pin their trigger player + zone entrants at entry
  (not just on first damage); horde sweep releases mob + participant +
  entrant pins so the next event starts clean.
- WorldStateProjection projects ephemeral state zone-scoped under
  `/world/zones/<z>/entities|players/` (mobs + player live state) and
  instance-scoped under `/world/instances/<scope>/` (dungeon hordes via
  "instance:<scope>" scope overrides). Tick-routed writes (0.5s coalesce
  aligned to ticks). Zone snapshots capped at 2000 nodes.
- TickService Phase 4 delivers AOI diffs: zone-membership + chunk-box
  routing, non-spatial entries to their owner, instance entries only to
  pinned clients, L1 payload stripping under load or for far-zone
  clients.

## Test suite (run headless: `cd game && godot --headless --path . --script res://tests/<t>.gd`)

Current green baseline: horde_configs 68, boss_commands 52,
world_boss_schedule 37, horde_rewards 37, horde_events 34, phase4_aoi
17, projection 44,
bridge 41, kill_rewards 21, guard 31, loot_tables_live 33, loot_rules
30, duel 28, placement 54, academy 25, aggro 33, combat_loop 31,
combat_pipeline, combat_live 10, entity_autoload 8, hit_table 34,
onboarding_live 26, e2e 40, login 21, ui_alive 33, interaction 16,
settings 14,
splash 14, touch 17, ground_loot 42, persistence 23, notification
frame 26, state_schema, frame_authority, frame_memory, lint x5,
parse_check, autoload_audit.

dungeon_portal is the end-to-end loop test: real WorldService gateway
walk -> zone entry -> auto-start -> wave spawns -> instance pins ->
sweep release (19 asserts).

full_boot_live is the full-boot live test under xvfb (NOT headless):
boots the real world_playable scene and drives every system through
production entry points (42 asserts, ~60s after boot): dummy
dmg/heal/no-reward/respawn, /spawn 3+level-override slimes killed via
create_hitbox (kill rewards verified), /boss world metadata +
announcement, 4s world-boss timer respawn cycle, haven_siege open-
world horde swept to success, dungeon portal auto-horde with instance
scope pin. Gotchas baked in: GatewayRecord exposes .id (not
.gateway_id), horde wave bosses are bare Entities (duck-type
is_alive()/take_damage, no health_component), reward-event baseline
must be captured BEFORE the kill (death chain is synchronous inside
the lethal hitbox), 300s watchdog force-quits if a SCRIPT ERROR kills
the run coroutine (otherwise the process ticks forever and hangs the
session).

Lint lives in `tests/lint/` (run_all.sh). xvfb live-run suites: touch,
splash, ui_alive, interaction (zero SCRIPT ERROR requirement).

## Ops notes (important)

- Disk fills from Godot logs: purge
  `~/.local/share/godot/app_userdata/Synmergia/logs/godot*.log` and
  check `df -h /` + `ps aux | grep -i godot` when runs hang (zombie
  Godot processes from crashed sessions hold deleted log handles).
- Script-mode (`--script`) tests: autoload identifiers do not resolve at
  parse time -- use `get_node_or_null("/root/Name")` runtime lookups for
  forward edges.
- PermissionManager._validation_cache TTL is 5s: test seams that stamp
  admin levels expire quickly; re-stamp before late test sections.
- Sandbox: no web export templates (wasm export happens in CI);
  `gh workflow dispatch` returns 403 (user runs it manually).

## Open / next candidates

- [ ] Islands suite: ~20 bare-autoload script-mode compile notes
  (batched runtime-lookup conversion).
- [ ] WebInputBridge browser e2e once a full web export lands.
- [ ] Zone data is concentric discs sharing one center; real region
  shapes would exercise the overlap resolver more meaningfully.
- [ ] Wolf spawn-camp mitigated by sanctuary; revisit levels/positions
  when world content grows.
- [ ] DataService horde catalog admin surface if content grows.
- [ ] /boss + /spawn smoke coverage inside a full-boot live test
  (DONE: test_full_boot_live 42 asserts under xvfb -- /boss metadata,
  /spawn combat loop, 4s timer cycle, both horde flavors).
- [ ] More world_bosses .tres content once world zones grow (one demo:
  forest_void_lord).
