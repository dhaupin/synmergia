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
  (2)  test_placement_system's GuildPlayer inner-class extends of the
  stub crashed script-mode compilation (parse-time entity.gd load);
  extracted to tests/support/guild_player_stub.gd, applied via
  set_script. Placement 65/65, guard 31/31, full-boot 43/43. Also
  logged: solo /say sends return false (empty audience rejects your own
  echo) -- authentic MMO behavior, not a bug.
- Scene-flow journey (play_full_flow.gd, 26 asserts, xvfb): a bot
  plays the WHOLE player path -- main menu -> Play -> species card ->
  class card -> world combat (hit table + skillbar) -> MAIN_MENU ->
  Account -> register (real LoginService) -> lobby -> /create ->
  linked character -> auto-play -> world again. Playing it found +
  fixed two production bugs: (1) set_kv/get_kv/erase/has_key existed
  only on the DictStore WRAPPER -- ~25 services (account_service,
  login_service, guild_service, faction_manager, ...) call that
  surface directly on stores from AdapterRegistry.get_persistence(),
  so every account/character/guild/waypoint persist threw "Nonexistent
  function 'set_kv' in base 'RefCounted (MemoryPersistenceStore)'"
  and silently dropped the write. Single-key API now implemented on
  the PersistenceStore base routed through the portable batch API
  (set_many/get_many/delete_many, prd-db.md sec 4); Memory + Postgres
  standardized to JSON-strings-at-rest with get_many DECODING
  (Postgres already did; memory get_many returned raw strings so even
  load-time reads were half-broken), DictStore hardened to tolerate
  both decoded and legacy raw-string backends. (2) spawn_npc_entity
  configured + registered NPCs BEFORE ever parenting them -- every
  global_position read/write threw "!is_inside_tree()" engine errors
  and identity transforms reached TargetingManager + the NSC-9
  address; NPCs now parent into current_scene first (same ordering as
  the /spawn enemy path) and EntityService._entity_position() is the
  safe-read helper for metadata/spatial-address/NSC-9 derivation.
  Also this session: human_time_warp.tres created (class
  human_temporalist starting_skills referenced a nonexistent skill
  id), main_menu gained a working Account button (the login screen
  was unreachable from the shipped menu), out-of-tree guards in
  ZoneManager/LODManager/CombatSystem/world_state_projection/
  NotificationService + LoadingUI._exit_tree nulling the static
  instance (the PLAYING -> MAIN_MENU segfault class), captures/
  gitignored so dev screenshots stay local, old screenshots deleted.
  Verification: journey 26/0 (account character persisted through the
  real kv path for the first time), adapter suite 5/5, login/e2e/
  hit_table/account_rollup/full_boot_live green, lint 36/0,
  parse_check + autoload_audit clean, engine log 0 SCRIPT ERRORs
  (was 5 set_kv + 26 is_inside_tree per run).
- Logo pack shipped + wired: user exported the 4-up Gemini logo sheet
  to assets/branding/ as logo-synmergia-{emblem,emblem-small,
  horizontal,wordmark}.png (redundant combined sheet deleted); Brand.*
  loads them with a direct-PNG decode fallback so fresh drops render
  before Godot's import pass; main menu header takes the horizontal
  lockup (text fallback kept), loading panel shows the small emblem.
  test_branding.gd 12 asserts incl. the real shipped pack; journey
  26/0 with the lockup live (screenshot 01_main_menu).
- Art direction canonized (labs/art-direction.md): the 26-sheet Gemini
  concept set (Drive: Synmergia Concept Art (Shared)) is the style
  bible's source of truth -- stylized cyber-organic, grey-green base
  with SEMANTIC accents (teal #80c0c0 dormant tech / gold active
  convergence / violet mycelium-arcane ONLY, magenta = hostility key
  for corrupted agents), agent fauna naming convention, in-world Agent
  Core emblem (Convergence Spire door = logo diegetically justified).
  Measured palettes recorded from pixel analysis of the set. Known
  gaps prioritized: characters, hostile fauna, bosses, interiors/UI.
- Prompt staging pipeline (labs/prompts/): human renders via Gemini,
  agent art-directs/critiques/canonizes. First briefs: 
  gemini_species_classes.md (3 species + 6 human classes incl.
  Temporalist flagship, 6 Akkan, 6 Synthetic, trio hero shot; anchors
  are the real .tres species/classes; style lock block embedded),
  gemini_hostile_agents.md (neutral->hostile pairs with the magenta
  key). Gemini-rendered text is often gibberish -- treat baked-in text
  as decorative; labels-only instruction added to every brief.
- Round 2 art canonized (23 new renders from the prompt packs, Drive
  now 50 images; /tmp/syn_concept cache + id_map refreshed): magenta
  hostility key pixel-audited across the drop (<1% of frame, only on
  corrupted agents); violet boss battle = canon Forest Devourer visual
  (world_boss_forest_void_lord.tres, zone_forest_meadow); AETHER-
  CONDUIT canonized as the in-world terminal/kiosk term; the four
  service interiors (vault/academy/blacksmith/storekeeper) mapped to
  VaultService/SkillAcademyService/BlacksmithService/vendor; Akkan-vs-
  Synthetic duel = PvP key art; Human species sheet = Human reference
  (label drift noted: anchor filenames baked as labels, "MIY WORDMARK"
  gibberish). Style-lock text rule hardened (no filenames/other text).
  New briefs: gemini_bosses.md (Devourer standalone + Clockwork Saint
  + Mossbound Herald trio) and gemini_zones.md (6 establishing shots
  anchored to zone .tres ids). Full critique + next steps in
  labs/art-direction.md sec. 8-10.
- Round 2 visual critique pass (user re-attached 8 renders to chat --
  chat attachments are the only channel the agent actually SEES; the
  Drive cache is palette-analysis-only): bestiary sheet canonized
  (magenta eyes only on all 4 variants, violet = corruption medium),
  trio hero shot = co-op key art, class sheets + species lineup
  canonized (sec. 8.9). New drift ruled on: MARKSMAN rendered twice
  (grid permutation), "RUNEBLADE" label -- data says Runesmith
  (class_akkan_rune.tres display_name, .tres wins), "[STYLE LOCK]"
  placeholder token rendered as literal header text -- convention
  changed to paste the expanded paragraph (README + all packs),
  stray annotation words are decorative.
- Prompt pipeline gap-closure: every bible gap now has a brief --
  species deep-studies added to gemini_species_classes.md sec. 6-7
  (Akkan civilian/elder/head-row, Synthetic wake-states + faceplate
  variants), gemini_class_heroes.md (Temporalist/Conduit/Runesmith
  single-figure key art, right-two-thirds UI-safe composition),
  gemini_interiors_ui.md (Echo Plaza Inn, dwelling, gateway chamber,
  HUD mock, 16-icon sheet, Aether-Conduit service menu -- violet
  never on chrome, gold = reward/active only). art-direction.md
  sec. 6 rewritten as gap->brief index.
- Round 3 canonized (all 9 renders seen in chat; the dropped HUD
  mock followed separately): text rules HELD -- all labels
  correctly spelled incl. RUNESMITH, and the HUD mock rendered real
  UI copy perfectly ([Main] Reach the Nexus Core (3/7), [Daily]
  Siphon Aether, [Side] Recover Lost Schematics; chat [System]/
  [Party]/[Local]). Class heroes + inn/dwelling/gateway + 16-icon
  sheet + Aether-Conduit service menu + HUD skin canonized
  (sec. 8.10). New canon: currency = gold ingots stamped with the
  Agent Core star; Conduit floor wake-ring = synthetic activation
  gesture; service-menu tile names adopted (VAULT SERVICE, GUILD
  REGISTRY, CONVERGENCE CHRONICLES = lore/journal, SMITHING
  SERVICES, MARKET EXCHANGE, WAYPOINT NETWORK); HUD quest tags
  [Main]/[Daily]/[Side] + chat tags [System]/[Party]/[Local] +
  wireframe minimap with teal sweep cone carry to code. Drift
  notes: saturated-purple Akkan patron (rerun: desaturated skin),
  violet moss indoors = damp/neglect rule, violet gateway moss kept
  out of focus zones. Clarified for the user: boss trio + zone shots
  NOT yet rendered (battles study + duel/trio hero are the closest
  existing art); those two packs are the next render batches. Drive
  upload of the round-3 batch not yet visible to the agent's folder
  scrape (still 50 files) -- palette audit pending the upload
  propagating.
- Round 4 canonized (boss trio + standalone Devourer + all 6 zone
  splashes, 8/8 seen in chat): WORLD ART SET COMPLETE -- labels
  clean third round running, ZERO magenta across all six zones,
  hostility spectrum demonstrated on the trio sheet (Devourer
  violet+magenta / Saint teal+one-eye / Herald teal-only neutral).
  Devourer design lock: ROOTS GREW THROUGH THE HULL INTO THE LIMBS.
  Saint/Herald world_bosses .tres files = code follow-up when
  encounters get designed. Sec. 6 rewritten as coverage status
  (iteration queue: species deep-studies unrendered, 3/18 class
  heroes done, faction banners/mounts/crafting stations/emotes are
  next-phase subjects). Palette audit still deferred (round-3/4
  Drive uploads not yet visible to the folder scrape).
- Next-phase briefs written (four new packs, awaiting renders):
  gemini_faction_banners.md (Akkan Horde / Human Alliance /
  Synthetic Collective standards + neutral way-stone; faction color
  law: ember-Akkan, teal-Human/Synthetic, gold finials, violet/
  magenta forbidden on marks; Agent Core star only on Human
  quartered + Synthetic alone), gemini_mounts.md (Canopy Strider /
  Boulderhoof / Conduit Courser + Little Symbionts companions;
  design seed -- no mount/pet data exists yet; zero magenta, tablet
  cradle in every saddle), gemini_housing.md (Claim/Cottage/Hall
  tiers + Hearth Kit placeables; warm windows join the inn's warm
  exception, door-side Aether-Conduit post = house terminal +
  address stone), gemini_crafting_stations.md (Forge/Loom/Crucible
  Table/Rune Anvil; station law: teal idle / gold active = in-world
  status feedback), gemini_vehicles.md (Conduit Glider / Islet
  Lifter / Caravan Crawler; vehicle law: multi-passenger platforms
  vs mounts' single-rider split, woken by tablet-socket helm --
  never built or fueled, no engines/wheels/cabins, teal dormant /
  gold underway per the station law).
- Saint + Herald wired from art to data (bible sec. 6 item 3
  closed): enemy_clockwork_saint.tres (lvl 55 WORLD_BOSS,
  aggressive = half-corrupted law) scheduled in
  zone_dungeon_forest_depths 4h interval; enemy_mossbound_herald.tres
  (lvl 45 WORLD_BOSS, is_passive + aggro_range 1.0 = neutral law,
  heavy armor 150/150 resist, slow 1.2 move) scheduled in
  zone_starter_plains 6h interval. SpawnService.load_world_boss_
  schedules scans the dir so both boot automatically. New durable
  smoke test tests/test_canon_bosses.gd encodes story-PRD canon as
  mechanics (Herald passive / Saint aggressive) + template/
  schedule/zone resolution: 8 asserts green; parse_check, world
  boss schedule 37/0, boss commands 52/0 all green.
- Quest-engine repair + quest design bible (labs/prd-quests.md,
  CANON for quest design; companion to prd-story.md): TALK and
  COLLECT objective bridges landed in QuestService (before this,
  only KILL could advance -- the Awakening, a TALK quest, was
  permanently stuck). TALK credits via DialogService.dialogue_ended
  with display-name OR raw-id targets (attribution scan over
  in-progress players; exact because update_quest_progress
  re-validates); COLLECT keys off item display_name via
  EventHub.item_picked_up. NPC ids normalized to npc_-prefix
  (village_elder/test_merchant -> npc_*; dialogue already referenced
  npc_village_elder -- the mismatch this fixes; zero stale refs).
  Story-PRD drift CLOSED: village elder says Gloomwood (was
  Darkwood). New quest main_teachings.tres "The Old Roads" (EXPLORE
  wake-3-waypoints, gated on main_awakening) -- first act-1 spine
  beat past the tutorial. Tests: test_quest_lore_bridges 8/0,
  notif_migration_quest 10/0, parse_check verdict 11/0 (the 10
  SCRIPT ERROR lines under --script mode are pre-existing harness
  noise, identical on clean HEAD -- autoloads do not pre-load in
  that mode).
- EXPLORE objective bridge wired (third and last of the Act-1
  objective types): QuestService connects ZoneManager.
  player_entered_zone, credits the trimmed zone convention AND the
  raw ZoneData id (dual-candidate law; quest .tres targets use
  "starter_plains", zone ids are "zone_starter_plains"). The Old
  Roads is now playable end-to-end. When a true world-waypoint wake
  mechanic lands, its events tick the same contract and stack
  additively. test_quest_explore_bridge.gd 6/0; lore bridges 8/0,
  notif migration 10/0, parse 11/0 all green.
- Story & world-lore PRD written (labs/prd-story.md, CANON): the
  missing narrative bible -- premise (the unpowered world + the
  Convergence + the Silence), 4-age timeline (Convergence / Silence
  / Long Sleep / the Waking), species roles (Human rebuild /
  Akkan guardians / Synthetic emergent; NO makers in evidence =
  the setting's mystery engine), institutions, THE BLOOM as the
  antagonist force (mycelium gone masterless; magenta = the Bloom's
  refused handshake -- unifies the hostility key diegetically),
  player identity (tablet-bearer), 3-act arc skeleton (Act 3
  deliberately open), tone rules ("woke/answered", never "powered
  on"; the Bloom is never called evil), 5 open mysteries (do not
  canonize answers), drift log (village elder says "Darkwood", data
  + art say Gloomwood -- fix when quests are authored), and a
  canon-pointer table. Prompted by the user asking for a story PRD
  after the vehicle-law pitch resonated ("old MMO feeling with a
  twist").
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

Regression runner (committed): `sh ./scripts/godot_test_runner.sh`
(default set: data-naming lint, movement profiles, blacksmith model/
anim/scene probes). `--all` runs every `test_*.gd`; pass names to run
specific tests. Use it instead of hand-rolling for loops.

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

- Anticheat movement limits are STAMPED per player from their
  MovementProfile (call_deferred after _ready -- entity_id must
  resolve first). Limits live in AntiCheatService._movement_limits;
  get_movement_limits() falls back to movement_standard-derived
  bounds for unregistered ids. Escalation bridge:
  cheat_detected -> SecurityService.report_anticheat_finding.
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

- [x] Rando batch 11 (2026-09-26): something behind the open door --
  Acts/chapters consumer + almanac Watch-the-sky button (user: "Let's
  do it! ... This can also show up as a daily quest if that's what you
  mean by act/chapter?"). DOOR RE-SEAL FIX: ancient_door's header
  promised a dawn re-seal but nothing reset _is_open -- door_opened
  fired once per server lifetime, which would have dead-ended any
  milestone consumer. Door now re-seals in _refresh_state when its
  day's unlock disappears (slab rises via _slab_home, glow back to
  0.4); probe section 7 covers seal + reopen. ACTS (game/core/
  services/acts_service.gd, autoload after SignService): the
  door_opened consumer -- every open records the next eligible
  chapter per act. Two gates: a concrete gate_day needs
  SignService.is_ancient_unlocked(day); gate_day = -1 fill-ins
  advance one per open inside advance_from_day. ActProfile schema
  (chapters authored as plain dicts -- the QuestData .tres pattern;
  typed ChapterProfile views via get_chapter_profiles(ledger)).
  DataService loads data/acts/ (act_ prefix; 3 acts authored: First
  Vault day-gates 1-3, Unpaid Debt fenced at day 3, Trust Audit
  open-ended). Persistence: DictStore "acts:recorded" with
  _normalize_ledgers on load -- JSON round-trips stringify dict keys
  ("1" vs 1) and every lookup indexes ints. Toasts: NotifKind.CUSTOM
  broadcast, dedupe keys include the day so repeat opens stay
  silent. ALMANAC: the old "Watch the sky again" button only
  refreshed -- added a real "Watch the sky" button that records the
  local player's insight (PlayerManager.get_local_player,
  almanac_observer fallback in headless), one insight per window so
  the tribal price is unchanged, SIGN_INSIGHT_RECORDED toast, rows
  rebuilt after; Chronicle block in a scroll (act summaries +
  recorded lines, "[not yet recorded]" otherwise -- the Chronicle
  withholds what no door has paid for). TEST LESSONS:
  notification_sent carries kind nested in data for TARGETED notifies
  (notification_received only fires on the broadcast path);
  Resource.get(k, default) 2-arg bites on custom Resource scripts
  (read act.advance_from_day directly); ensure_initialized must guard
  get_tree() with is_inside_tree (script mode boots before the tree
  exists); door-scan on a 2s timer, not a one-shot frame await (the
  world scene attaches after the menu). DAILY QUEST DECISION: not
  forced -- QuestData has DAILY/is_repeatable fields but
  check_quest_availability permanently blocks REWARDED (no daily
  reset) and no objective type expresses "record an insight"; noted
  in prd-psy.md section 10. Regression 12/12 (new test_acts_service,
  9 checks), boot clean, lint covers act_ prefix.
- [x] Rando batch 10 (2026-09-26): Concord Stone + blessed-login
  toast + legacy warrior deletion (user: "Next slice: Concord stone
  interact | Let's delete legacy warrior tres too, and make the
  toast"). CONCORD STONE (game/entities/concord_stone.gd): the
  player-facing insight trigger -- record_insight was admin-only
  before, so the tribal loop could never close in-game. Monolith +
  pulsing crystal (brighter once the window is revealed), E-interact
  via the "concord_stones" group (same resolver pattern as
  ancient_doors), idempotent repeat gaze, no-religion voice (the
  stone observes, it does not bless). One placed at (-6, 0, -4) in
  world_playable; loop probe now presses it and treats the E-press
  as tribe_a's insight (watched threshold arithmetic: an extra
  observer shifts the reveal -- first version used a separate gazer
  and broke "revealed below threshold"). LOGIN TOAST:
  SignService._on_player_entered_world on
  GameManager.player_entered_world -- the blessed class hears "YOUR
  class today" on login, only when the day is earned; test listens
  on notification_received (notification_sent was the wrong signal --
  connect() errored and aborted the function, cascading into the
  combatmath check). LEGACY WARRIOR DELETED: class_warrior.tres
  removed (DataService 21 classes = 18 playable + 3 GM);
  CharacterData default + _init, lobby blob fallback migrated to
  human_warrior (tests using class_id "warrior" in dicts are data
  literals, not the .tres -- they pass). FLAKE FIX: combatmath test
  asserted blessing_multiplier on a raw calculate_hit roll -- the
  MISS segment returns early WITHOUT the stamp (by design; a miss
  deals no damage and calculate_damage defaults the key), so the
  runner intermittently rolled MISS and failed. Test now asserts the
  deterministic _blessing_multiplier_for() lookup and feeds a stamped
  dict into calculate_damage; 3 consecutive clean runs. Regression
  11/11, boot clean.
- [x] Rando batch 9 (2026-09-26): Daily Class Blessing -- the
  retention beat (prd-psy.md section 8). The assembled sky code names
  TOMORROW'S blessed class: +20% damage/heal/XP + effective level +5
  for the whole shard, one day. SKY WHEEL: per-round Fisher-Yates
  (seed = round epoch) over sorted playable class ids, walked slot by
  slot -- every class blesses exactly once per rotation BY
  CONSTRUCTION (my first two attempts -- per-day hash jitter, then
  slow-wheel+jitter -- both allowed collisions within a rotation;
  permutation-per-round is the only construction that guarantees the
  reroll-if-too-soon rule). WHEEL CATALOG FIX (same session, user
  asked "18 classes + 1 hidden GM per species, correct?"): the id
  filter originally only excluded role-0 GMs, so legacy
  class_warrior.tres (bare id "warrior", role 2, never grantable at
  creation) occupied a rotation slot -- 19 slots, one unpickable.
  _playable_class_ids() now requires a species prefix (human_/akkan_/
  synthetic_), matching CharacterData.get_available_classes_for_
species doctrine; test gained a wheel-catalog fairness check; 18
  classes confirmed, regression 11/11. EARN GATE: is_class_blessed pays only
  when the day is Ancient-unlocked (no solve, no buff; agents may
  reveal outside game processes). Hooks: CombatMath.calculate_hit +
  calculate_magic_hit stamp blessing_multiplier into the hit_result,
  calculate_damage applies it (one choke point for every damage
  path); Skill.calculate_healing +20%; KillRewards._grant_xp +20%;
  CharacterData.get_stat_total computes at level+5. All hooks
  duck-typed + late-resolve SignService via Engine.get_main_loop
  (script-mode-safe; enemies/bare Entities never blessed).
  CLASS_BLESSED NotifKind: announced at code-assembly + dawn
  (_maybe_roll_day, only when the day is earned). Almanac shows
  blessed class + live state + tomorrow preview. Tests:
  test_daily_class_blessing 6 checks (hydration x2 rotations,
  determinism, earn gate, 3 hooks) + probe_ancient_loop now verifies
  the blessing goes live after the tribal solve. Gotchas: inner-class
  test fakes beat RefCounted+set() (set() on a nonexistent property
  SILENTLY no-ops, so every property probe then fails); Skill is a
  Resource -- never .free(); a test control must zero its stat
  defaults or WIS healing masks the blessing (plain_heal read 120
  from WIS, looked like a phantom blessing). Regression 11/11.

- [x] Rando batch 8 (2026-09-26): Concord loop closed -- doors, sky,
  almanac. AncientDoor entity (entities/ancient_door.gd,
  for_day_offset=1 = TOMORROW's Ancient: today's completed code turns
  the key NOW and the door re-seals at dawn -- daily urgency; E via
  "ancient_doors" group in PlayerController._try_interact; sealed
  refusal includes tribal glyph progress; glow states dim/amber-pulse/
  bright; slab sink tween on open; door_opened signal is the future
  acts/chapters hook). SkySignRenderer (entities/sky_sign_renderer.gd,
  billboard star pool, per-sign deterministic scatter from
  hash(sign_id)+"arrange"; sealed = dim flat ring, revealed = bright
  figure in sign.sky_tint -- the sky withholds the pattern until the
  tribe shares it). SkyAlmanacUI (ui/components/sky_almanac_ui.gd,
  hotkey V, MenuManager "sky_almanac" + panel_map + _get_panel;
  4 window rows with observer counts, current-sign lore, door state;
  honors the tribal rule: un-revealed = "glyph unknown (N watching)").
  World placement: world_playable._setup_ancient_door +
  _setup_sky_signs (loaded by path, the GuardData lesson).
  Gotchas fixed in passing: UIStyles.COLORS key is text_primary (not
  "text" -- Dictionary dot-access crashes at runtime not parse time);
  loop-probe lesson: a door tracking tomorrow is keyed by TODAY's
  code, so the test reveals now_day's windows. Probe:
  probe_ancient_loop.gd (6 checks: placement, sealed refusal, tribal
  3-observer reveal -> DOOR OPEN, open readback, sky stars visible,
  almanac tribal honesty) in runner DEFAULT_SET. Regression 10/10.

- [x] Rando batch 7 (2026-09-26): Skyward Concord v1 -- the communal
  sky clock (labs/prd-psy.md created: post-religion worldview as
  DESIGN LAW + this system as its first mechanic). SignService
  autoload: four 6h windows/day, window->Sign pick is a pure hash of
  (day,window) so server+clients agree with zero sync; each window
  shows one Sign from data/signs/*.tres (SignProfile schema: glyph,
  sky_tint, observation_hint; 3 signs shipped). TRIBAL RULE: a
  window's glyph goes public only after 3 DISTINCT players record an
  insight (record_insight, idempotent per player) -- the day's code
  is unfillable by one watcher alone. When all 4 windows reveal, the
  ordered glyph sequence (get_ancient_code) unlocks TOMORROW's
  server-wide Ancient; rollover wipes rumor state, keeps unlock
  history. NotifKind +SIGN_WINDOW_CHANGED/SIGN_INSIGHT_RECORDED/
  ANCIENT_UNLOCKED; admin /sign status|record|force_reveal|
  unlock_tomorrow; DictStore persistence (mirrors anticheat);
  ensure_initialized() idempotent boot (script-mode autoloads exist
  before _ready fires -- real trap); clock override for tests.
  Lint: sign_ prefix + filename==id + glyph presence. Tests:
  test_sign_service 7 checks (window math, determinism, tribal
  reveal, code assembly, rollover, future-day). Fixed in passing:
  admin_commands ternary type-inference (var sub: String), AGENTS
  header + last-updated, runner DEFAULT_SET +test_sign_service.

- [x] Rando batch 6 (2026-09-26): Hitbox Profile System + species
  scale fairness. NEW schema HitboxProfile (core/schemas/
  hitbox_profile.gd: capsule/box/sphere kinds, stance variants,
  clamped scale band, pvp_fair flag) + data/hitbox_profiles/*.tres
  (hitbox_player, hitbox_humanoid, hitbox_beast_medium, hitbox_blob,
  hitbox_dummy, hitbox_npc). Single resolution path
  DataService.get_creature_hitbox_profile() (explicit
  hitbox_profile_id wins, else animation_set derives the body plan;
  new hitbox_profile_id fields on EnemyData + NPCData, 4 core enemy
  .tres pinned). enemy.gd _apply_hitbox_profile() targets the
  scene-authored StaticBody3D/Hitbox node (world_playable inline
  shapes renamed Hitbox), falls back Hitbox -> bare CollisionShape3D
  -> built pair; EnemyData.scale now actually applies (hitbox AND
  ModelRoot multiply the same clamped scale, wolf 1.2). FAIRNESS
  RULE: all 3 playable species resolve to ONE shared player hitbox
  via resolve_player_hitbox_profile() (deviating overrides logged +
  forced back; hitbox_player scale locked to 1.0) so no species/
  sex/body_type spawns with a bigger target. PlayerController
  _apply_hitbox_profile() (deferred) + set_hitbox_stance(); Crouch
  + Slide swap to the 0.9 crouch capsule and restore on exit.
  NPCEntity applies NPCData hitbox (default hitbox_npc) onto the
  scene capsule. SpawnService.spawn_npc_entity defers its add_child
  during scene setup (fixed pre-existing rejected-add error spam +
  half-configured NPCs). Lint extended: hitbox_ prefix +
  filename==id, ref resolution, species fairness; runner DEFAULT_SET
  now includes test_anticheat_limits + probe_wolf_model (was passed
  by name only). Tests: test_hitbox_profiles (9 checks) + lint;
  default regression 8/8; xvfb boot clean.

- [x] Rando batch 5 (2026-09-25): Anticheat movement hard limits --
  AntiCheatService.validate_movement() checks horizontal speed / jump
  launch / fast-fall against limits DERIVED FROM each player's
  MovementProfile (stamped by PlayerController via call_deferred,
  GMs exempt via set_movement_exempt); sustained 30-frame streaks
  (~0.5s) report through cheat_detected -> NEW bridge
  SecurityService.report_anticheat_finding -> exploit pipeline ->
  AutoResponseService speedhack rules (3 confirmations -> admin
  review, auto-ban config-gated false). Legal play (slide peak 9.5,
  dodge 4.5, jump 10, terminal fall 55) all pass at 2.5x/2.0x
  multipliers; single-frame lag spikes never report. Anticheat
  _ready() now loads persisted state + wires the bridge (was
  orphaned: _load_state never called, cheat_detected never heard).
  Shared model export lib (scripts/model_export_lib.py) extracted;
  blacksmith regenerated through it byte-comparable. WOLF: first
  quadruped model (gen_wolf_model.py, 4 two-bone leg chains, real
  trot with diagonal pairs, idle breathing/ear/tail) ->
  game/models/enemies/enemy_wolf.glb; enemy.gd mounts EnemyData.
  model_path glbs (hides placeholder box, swaps walk/idle clips with
  AI movement); wolf .tres wired to the model + movement_quadruped.
  movement_aerial + movement_aquatic profiles added; MountData +
  VehicleData carry movement_profile_id resolved through the single
  path DataService.get_mount_movement_profile() (kind-derivation:
  GROUND->quadruped FLYING->aerial AQUATIC->aquatic; explicit
  override wins; vehicles -> mechanical). Tests: anticheat_limits 9
  checks, movement_profiles 11 checks, wolf probe (trot drives all 4
  legs 0.532 rad), regression 9/9 + lint + xvfb boot clean. Wolf
  screenshot art/screenshots/enemy_wolf.png.
- [x] Rando batch 4 follow-up (2026-09-25, session recovery): fixed
  the two parse errors that killed the previous session --
  MovementProfile.get_ground_speed used `var x = match ...` (match is
  a STATEMENT, not an expression) and enemy.gd passed a default arg to
  Resource.get (removed in 4.7.2). Movement Design System landed +
  tested: MovementProfile schema, data/movement_profiles/ (standard,
  quadruped, mechanical, npc_ambient), DataService loader,
  PlayerController profile stamping + capability gates in idle/run
  states, EnemyData.movement_profile_id + enemy.gd profile scaling
  (movement_standard preserves historical 5.0/10.0/10.0 tuning).
  Blacksmith 3D pipeline PROVEN end-to-end: generator restructured to
  export-once-per-clip (action swap + scene-range clamp) + stdlib GLB
  merger + fix_clip_ranges.py NLA slot placement, now writes the
  final .glb straight into game/models/npcs/ (no manual copy step);
  blacksmith_village.tscn embeds the skinned glb under ModelRoot and
  NPCEntity._play_model_idle() drives it; probes confirm walk moves
  thigh_l 0.399 rad in-slot and idle breathes arm_r in-scene.
  Screenshot: art/screenshots/npc_blacksmith_village.png (Cycles CPU --
  EEVEE cannot render headless). Durability: scripts/godot_test_runner.sh
  (default regression set + --all), flow + gotchas documented in
  labs/prd-3d-pipeline.md sections 6-7. Lint + autoload suites still
  green.
- [x] Rando batch 3 (2026-09-25): Blender 3.0 installed + numpy for
  the glTF addon; blender_smoke_test.sh now dash-safe and PASSES
  end-to-end (headless cube -> .glb -> Godot PackedScene). The
  .glb lands in game/models/blocks/ as the first procgen block.
  Consistency pass: data/roots/ frame schemas (seed_schema/
  state_schema) moved to core/frame/schemas/ (5 preloads updated,
  embedded ext_resource paths in world/seed.tres + state.tres
  fixed, class cache reimported), roots test files co-located in
  core/frame/kv/, dead quest_guide_npc stub archived to
  labs/archive/ (never wired, broken refs from day one),
  test_seed_receipt float-precision assert fixed (pre-existing
  baseline failure). Web: mapItemType now mirrors the real
  ItemCategory enum (was silently mis-mapping accessory/material),
  ItemType widened. Lint 18/18, live 26/26, tsc clean.
- [x] Rando batch 2 (2026-09-25): data/misc -> data/items with
  item_ prefix + item_quest_* taxonomy (loot table refs updated);
  deleted the never-loaded vestigial data/buffs/; moved the
  mislocated test_seed_receipt.gd from core/schemas/ into tests/;
  killed all 14 phantom model_path/scene_path refs (law: the .glb
  filename IS the registry -- paths stay empty until the file
  exists; the naming lint now enforces this, 18/18 incl. item_
  style + model-path integrity). Web: build now copies web/ ->
  dist/web/ (prod deploys were losing the WASM shell entirely);
  GodotClientView probes shell+pck separately (deploy bug vs
  export notice), auto-focuses the iframe so keyboard input works
  without clicking, honest read-only labels for the decorative
  memory/debug controls; sync:data now exports items/resources/
  accessories and transformItems maps them; merchant vendor
  categories unified to ItemCategory label casing.
- [x] Rando-thoughts batch (2026-09-25): anti-stack spawn helper
  (SpawnService.ring_spread hex rings; /spawn jitter for repeated
  singles, spawn-point box -> ring slots; stack=true is the escape
  hatch). CurrencyData + data/currencies (gold, conduit shards,
  Reclaimer favor, Junker scrip -- exchange rates + caps + faction
  gates in data). MountData/VehicleData + samples (engine-ban
  consistent: creatures, ferry). Item.is_quest_item/quest_id/
  keep_after_turn_in flags + EquipSlot.BELT + CharacterData
  appearance fields (skin/hair/eye/hairstyle/body + species color
  lists). data/accessories/ dir wired into load_items merge (ring,
  necklace, cloak, belt, shield samples). Lint 16/16 incl. new
  currency/mount/vehicle/quest-item ref checks. labs/prd-world.md
  (sphere, two land masses, seamless zones, waypoint transport,
  instance contract, procgen pipeline, scale budget) +
  labs/prd-3d-pipeline.md + scripts/blender_smoke_test.sh
  (blender not in sandbox yet; script is ready).
- [x] Capital zone authored: zone_nexus_central ("Nexus Central",
  the story-PRD machine-age capital) + two-way waypoint from the
  starter plains (waypoint_nexus_central). npc_armory_capital +
  npc_skill_academy_capital flipped to it -- spawn system placed
  all 6 offering NPCs with zero code change (idempotent path did
  its job). species_synthetic.home_zone + faction_synthetic
  controlled_zones now resolve to the real zone; dungeon entrance's
  phantom reverse_gateway_id cleared. Lint extended with gateway
  zone/reverse cross-ref checks (11/11). Live onboarding 26/26,
  spawn log: "Spawned 6 offering NPCs".
- [x] ID naming convention locked (see AGENTS.md "ID Naming
  Conventions"): npc_/quest_/zone_/faction_ + kind prefixes for
  items, one id per entity, filename == id for prefixed categories,
  NO dual-format shims. Renamed all NPC/quest/zone/faction ids to
  the convention, soul_gem -> potion_soul_gem, killed the
  display-name/trimmed-zone dual-candidate loops in QuestService
  (TALK/EXPLORE now credit one verbatim form). New
  tests/test_data_naming_lint.gd enforces styles + cross-file refs
  (it caught faction id/filename mismatches + the phantom
  npc_alchemist on first run -- both fixed; herb quest now belongs
  to the herbalist). Trimmed to ONE blacksmith; starter village has
  elder + blacksmith + merchant + herbalist via spawn_offset
  placement; armory + skill academy authored-but-unplaced. Scene-
  placed MerchantNPC/ElderNPC twins removed from world_playable.tscn:
  spawn_all_offering_npcs is the single spawn path, now idempotent
  (_spawned_offering_npcs registry + freed-entity prune + lazy zone
  load) and called from world_playable._ready so every boot route
  gets NPCs. Live onboarding suite 26/26 after fixing its armor-
  naive slime damage assert.- [x] Consolidated `data/npc/` + `data/npcs/` into one canonical dir:
  migrated the 8 unique offering NPCs into `data/npc/`, deleted the
  dead `data/npcs/` (was never loaded by DataService), gave the two
  village-tier NPCs `zone_id = "zone_village_center"` so they spawn
  via the data-driven placement from the zone_id migration; the
  capital/town/outpost tier stays authored-but-unplaced until those
  zones exist.- [ ] Islands suite: ~20 bare-autoload script-mode compile notes
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
