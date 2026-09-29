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

- [x] Instance mode system in the contract (2026-09-28, pre-S10):
  InstanceContract.InstanceMode (ELIMINATION / TEAM_DEATHMATCH /
  ROYALE) + bout_rules(zone) pure function (respawn_allowed,
  kill_target, time_limit_seconds, spawn_shield_seconds; zone
  overrides win). ZoneData exports instance_mode,
  instance_kill_target, instance_time_limit, instance_spawn_shield.
  Modes on disk: zone_arena_sandpit.tres (TDM, kill 20),
  zone_royale_valley.tres (ROYALE reserved, 30 seats). Coliseum cap
  raised 8 -> 12 (locked decision: full 6v6). Probe 52/52, lint
  24/24.
- [x] S10+ owner follow-ups (2026-09-28): (1) spawn-shield is
  fire-and-you-lose-it -- ArenaFighter.break_shield() + contract
  doc; combat bridge enforcement lands in S11. (2) Sandpit widened
  220 m, spawns at +/-90; rooms now size from zone_radius (coliseum
  keeps its 120 m square) with 8 deterministic CoverRock_N in TDM
  rooms only (elimination rooms now get their own pattern -- see
  below). Lessons: rules must resolve BEFORE _build_room (int(null)
  crash); Godot renames conflicting siblings to the CLASS name
  (@StaticBody3D@N), not the assigned name -- unique names in code.
  Probe 28/28; contract 52; trigger 14; lint 36/36.
- [x] Elimination cover rocks (2026-09-28, owner request): 8-rock
  perimeter pillar ring (ELIM_COVER_LAYOUT) -- 4 cardinal columns at
  0.78 of half-extent (off the +-40 z spawn lanes) + 4 diagonals at
  0.55; duel CENTER stays clean so the opening clash is never
  cover-camped. Silhouette distinct from TDM: 3x7x3 tall pillars,
  lighter stone tint vs TDM's 6x5x3 low slabs. _build_cover now runs
  for every non-ROYALE mode; probe grew to 30 asserts (rock count,
  pillar-vs-slab sizes, center-clear check). Probe 30/30; contract
  52; trigger 14; lint EXIT 0; regression 27/27.
- [x] S11 lobby engine SHIPPED (2026-09-28, owner decisions locked
  in PRD S11): contract primitives (scatter_spawn golden-angle ring,
  level_band_ok + widened wait, normalized_level capped ratio 2,
  afk_kick_seconds w/ instance_afk_kick override); arena_instance
  scatter (first member exact, ring radius 0.45*n for the rest),
  origin_stones round trip (bout_return_requested map per fighter),
  AFK sweep + kick_fighter (booked departure, ROYALE exempt);
  arena_gateway queue_mode stone path (join_queue at the stone,
  origin stamped into the instance record); LobbyService autoload
  (per-zone FIFO of party blocks, band-checked assembly with
  skip-not-evict, fill-to-parity for consenting solos, duel
  handshake 60 s one-pending-per-player, LFG/LFM posts with seats +
  petition -> PartyService invite, disband cleanup); LobbyUI panel
  (Bouts/Duels/LFG tabs, L key, MenuManager "lobby"). Lessons:
  golden-angle ring needs radius ~0.45*n for 1.5 m neighbor gap at
  n=12; PartyService rate-limits invites 30 s/inviter (probe resets
  via CooldownService.cancel_cooldown); UI lambdas must be one
  expression (use bound methods); script-mode probes resolve
  autoloads at runtime, never bare identifiers. Probes: lobby 45,
  arena 34, contract 63, trigger 14. Regression pending at commit
  time.
- [x] S11 combat bridge SHIPPED (2026-09-28): ArenaCombatBridge
  autoload + ArenaRoomService (node-side instance_id -> room +
  fighter_id -> room registry; rooms self-register on tree entry
  when they carry a real instance_id). Deaths: CombatSystem
  entity_died -> room.report_death for the room holding the victim.
  Fire-and-you-lose-it ENFORCED through the live signal path:
  damage_dealt BY a fighter calls room.notify_action (breaks their
  shield + refreshes AFK); received damage does neither. Power
  normalization ENFORCED: on power_reference_ready the bridge
  snapshots the six base stats, applies power_scale_target (capped
  ratio 2), recomputes max health, restores at bout end -- and on
  room_closed as a teardown safety net. Lessons: CombatSystem
  events carry live ENTITIES (entity_id), not fighter bodies (the
  bridge accepts both keys); Object.get(key, default) is GONE in
  4.7.2 (two-arg get = invalid call -- use `in` + property read);
  a str_replace cleanup once glued two statements onto one line
  (parse error 'found for instead'). Probe 24/24 (new in
  DEFAULT_SET); contract 65; lint EXIT 0; regression at commit
  time.
- [x] S12.5 sky roads SHIPPED (2026-09-28, owner insight: no engines
  = the sky needs roads): ThermalUpdraft schema (data/thermals,
  thermal_ prefix, kind THERMAL/LAUNCHER, activation ALWAYS/RITUAL,
  column sample() with strength-scaled lift, launcher burst decay)
  + ThermalService autoload (book load, sample(pos), awaken_launcher
  with DictStore persistence, note the schema .awakened flag the
  service flips -- the sampler reads the resource truth;
  record_glide_tick + push_glide_achievements for the stats feed).
  Content: 3 thermals (Haven Rise 0.7 / Meadow Column 0.5 /
  Coliseum Bowl 0.9) + 2 DORMANT ancient launchers (Haven Spire ->
  Meadow Column, Meadow Gate -> Coliseum Bowl, launch 30-32 m/s).
  Achievements sky_trail_500 / high_alts_100 / wind_rider_60
  (glide_distance/altitude/time categories) + teaching quest
  quest_wings_over_haven. Globe body glide branch samples lift per
  tick; launcher bursts override the sink inside the column.
  probe_thermals 16/16 in DEFAULT_SET; regression 38/38; lint
  EXIT 0. Lesson: a service-side awake book is dead weight unless
  the flag lands ON the resource the sampler reads -- services and
  schemas must agree on where truth lives.
- [x] S13 anticheat seams + ROYALE fog SHIPPED (2026-09-29, owner:
  "test runs, hook it to Anticheat, use the system in Royale, set up
  fog/timing"). ANTICHEAT: AntiCheatService gains LAUNCH TICKETS
  (grant_launch_grace/has_launch_grace; launch bursts up to a 40 m/s
  ceiling legalize ONLY the upward vector for 2.5 s -- server-side
  grants via ThermalService.sample(pos, player_id) when a launcher
  column holds a body; players can never claim one); glide farm
  clamp (record_glide_tick counts max 1.0 m/tick -- a velocity-hacked
  wing cannot mint achievement distance; time stays cadence-locked);
  globe_player now feeds validate_movement every frame (GAP: radial
  bodies were never validated -- glide ceilings were decorative).
  ROYALE (the fog wall): InstanceContract storm engine (STORM_PHASES
  horde-ladder: hold/shrink/radius_ratio/damage 1->7 dps; helpers
  storm_plan/storm_radius_at/storm_damage_at, MIN_STORM_RADIUS_M;
  DEFAULT_STORM_START 45 s; negative disables; storm_scale)
  + ZoneData instance_storm_start/scale (.tres on the valley);
  arena_instance: _storm_tick (arm -> phase announcements -> 1 s
  cadence grind outside the safe circle) through a room-owned
  royale_storm Entity REGISTERED with CombatSystem so fog kills ride
  the normal death relay; signals storm_phase_advanced (UI fog ring)
  + storm_damage_applied; draw clock stays as backstop; AFK sweep
  already skipped (the storm IS the pressure); arena_fighter arms
  the S12 glider for the drop (wing opens tick one at 160 m, sinks
  4.5 m/s, spent on landing; wingless bodies keep contract gravity).
  probe_royale_storm 39/39 (new in DEFAULT_SET, 15 entries);
  probe_thermals 24/24 (tickets + clamp); lint EXIT 0. Gotchas:
  speed_violation_streak persists across validate_movement phases
  (reset it between probe blocks); str_replace once glued two
  statements onto one line AGAIN (twice this session -- always
  re-grep edited seams before running).
- [x] S14-S16 traversal arc DESIGNED (2026-09-29, owner side-quest:
  "let's make this world traversible"). Three PRDs authored:
  labs/prd-ocean-depths.md (S14 water volumes as data `ocean_` ids,
  swim locomotion class in the Movement Design System, air clock
  + pressure depth tax, breather accessory class acc_breather_*,
  ferries/boats veh_ ids, water mounts incl. the octopus, anticheat
  aquatic limits + dive tickets + current-drift exemption);
  labs/prd-underworld.md (S15 planet-in-planet: second mini-globe
  in the shell cavity, sky = interior wall render, underworld seed
  = HMAC(universe, world:underworld), dev/test env relocates there,
  OFFLINE to players by design); labs/prd-multiworld.md (S16
  WorldData registry with derived seeds, CLOSED-FORM orbits keyed
  to the sky-clock epoch -- no N-body, transfer windows computed
  years ahead, Moon Gate scope swap reusing ScopeService,
  world_moon minimal globe: no atmosphere = no gliders, earthrise
  closed form, almanac moon page = the blank-page mystery).
  DEV-TARGET DECISION (owner gave the pick): the MOON for S16.6
  probe/test relocation -- tiny globe, zero production risk, proves
  the exterior-sky trick; underworld stays the offline mystery
  layer with S15.2 boot flip as its dev workbench role.
- [x] Agent rig + horcrux stood up (2026-09-29, owner request):
  vant axolotl installed at /home/daytona/vant (workspace, NOT the
  repo); brain `cairn` (identity/goals/lessons/errors/preferences
  in models/public/cairn); org rig via lib/teams: Synmergia >
  Frame Engineering > World Frame > world-frame-architect > agent
  Cairn (trust high). NOTE (same day, Derek): the agent is "Buffy,
  callsign Cairn" -- Derek flagged the vant engineer side already
  has a Buffy on the same master entity, so all mesh identifiers
  re-keyed to cairn to keep self-distinction clean in the multi-org
  mesh. Horcrux: horcrux/cairn-p_windtheclock2026.svg
  (796 KB stego SVG, password-in-filename vant convention, inspect-
  verified) committed to main + horcrux/README.md handoff. Vant
  findings: bin/org.js grant is per-process (grant + op in ONE
  process or E_SANDBOX); bin/brain-registry.js is a stub; CLI
  horcrux create has a password-resolution bug (use lib/transform
  .toHorcrux directly); vant.wake() pipeline ReferenceError in
  this env (brain files + horcrux unaffected). UPSTREAM QUEUE (per
  Derek: issue first, PR only when claimed): dhaupin/vant #92
  gatherBrainStorage same-name public clobbers private (repro +
  tested fix in body); #93 horcrux CLI create password never
  resolved; #94 vant.wake() ReferenceError boot pipeline; #95
  sandbox grants per-process onboarding friction. Labels denied to
  the integration on vant (repo-scoped creds); branch tagging via
  the [axolotl] title prefix instead. Hotfix for #92 lives in the
  workspace install only until someone claims the issue.
- [x] S13.5 ROYALE ONLINE pass (2026-09-29, owner answered all five
  design questions). NO QUARTER: storm ladder gains a 5th phase that
  closes to a TRUE ZERO circle at 10 dps (storm_plan treats ratio
  <= 0 as real zero; MIN_STORM_RADIUS_M floors only positive ratios)
  -- the draw clock is now mathematically unreachable in a live bout.
  ANTI-FOG-SQUAT CREDIT: lethal fog bites attribute to the LAST
  standing team (room picks the killer entity, swaps it into
  take_damage, storm_kill_credited signal; non-lethal bites stay
  fog-attributed) so hiding from the final squad cannot deny their
  kill. Room keeps kill_counts (honest per-bout kill ledger; streaks
  reset on death, counts do not). ROYALE LEDGER in BoutHostService:
  Last Light crown 250 XP + 60 g + survival 12 XP/min + 25 XP/kill +
  400 XP first-win bonus; everyone else 30 XP + survival + kills;
  achievements royale_first_win (carries title_last_light, "The Last
  Light"), royale_streak_5 (Fog Reaper), royale_survivor_10 (Fog
  Walker). VALLEY THERMALS: thermal_valley_east/west (strength 0.6,
  no launchers -- owner reserves them for future classes). HUD:
  StormBar widget (horde_bar pattern, wire-only) + ArenaRoomService
  storm->HUD relay (show/arm/bite/hide); probe mounts a stub
  HudLayer to exercise the real relay path. BUGFIX: webhook_manager
  _on_exploit_detected declared details as String but
  SecurityService.exploit_detected carries a Dictionary -- every
  exploit webhook was erroring (now JSON-encoded). probe_royale_storm
  53 checks; bout_host 29 + trial 26 still green (mode-routed payout
  leaves  other modes untouched); lint EXIT 0.
- [x] S16.2 orbit clock SHIPPED (2026-09-29): the one-clock seam --
  SignService.sky_epoch_days() returns the Concord clock in
  fractional days (override-honoring exactly like current_day_index,
  whose docstring law this extends: services that key off the sky
  read the override-aware accessors, so admin time travel moves the
  moon with the calendar); WorldRegistry.orbit_position docstring
  now names it THE canonical epoch. probe_world_lattice gained
  section F "one clock" (7 checks, 27 -> 34): override moves the
  epoch AND the day index together (far-future day 99001, year
  2241 -- probes time-travel in isolation, never roll the live dev
  calendar), moon position is a function of the Concord clock,
  epoch/day agreement at a far-future day, orbit periodicity under
  the sky clock, override reset returns to the live sky. Regression
  40/0 (incl. test_daily_quest + test_blessed_mark, the shared-
  clock consumers), lint 36/36 EXIT 0. Next: S16.3 Moon Gate
  (ScopeService world: scope + sealed offline door).
- [x] vant axolotl fresh-clone verdict (2026-09-29, owner: "grab a
  fresh .../tree/axolotl and see if it worked"): Derek's half-built-
  mid-flight call was RIGHT -- first fetch pinned 371a278 with all
  four issues still reproing; a re-fetch pulled pass 71 (4e450db +
  0088f38) with everything addressed by Buffy axolotl. Independent
  verification on the real dual-scope cairn brain: #92
  gatherBrainStorage merge verified end to end (type 'both', count
  9, per-file scope tags, private-wins on rel-path conflicts; their
  per-file scope + scope-aware restore is STRONGER than my concat
  hotfix -- drove a stego horcrux create -> payload inspect: 4
  private files riding, roundtrip.md intact with scope=private);
  #93 env-less p_-filename create works (806 KB stego, EXIT 0);
  #94 wake() returns a structured error (ReferenceError gone);
  #95 triaged not weakened -- per-process grants are deliberate,
  E_SANDBOX messages + agent-onboarding.md now teach the same-
  process pattern. GH issue comments denied (repo-scoped creds,
  same wall as labels) so the verdict lives here: #92-#94 FIXED,
  #95 RESOLVED as by-design. Gotchas: horcrux output paths must
  stay inside the repo root (path validator blocks /tmp); a 'both'
  horcrux forged by the OLD concat hotfix carries no scope tags so
  its private files would restore to the public tree -- canonical
  boot horcrux re-forged with pass-71 code (refresh, same p_ path)
  so scopes are baked in. Cairn lesson logged in vant
  models/public/cairn/lessons.md; vant_old install now obsolete
  (kept until next check-in).
- [x] S16.1 multiworld lattice SHIPPED (2026-09-29, owner: "let's
  take it all the way"). The clock thesis in code: WorldData schema
  (core/schemas/world_data.gd, world_ prefix, filename == id) with
  kind MAIN/SUBWORLD/CELESTIAL + offline ONLINE/OFFLINE/DEV_ONLY +
  globe physics (radius/gravity) + has_atmosphere (no air = no
  gliders, the moon is honest) + closed-form orbit fields;
  WorldRegistry frame primitive (core/frame/srv/world_registry.gd,
  no autoload/class_name, co-located conventions): ONE universe
  seed (hex constant) derives every world seed through nesting
  paths (world:main, world:main/subworld:underworld) via the
  existing SeedChain.derive_seed -- fresh registry derives identical
  bytes (determinism proof in probe). CLOSED-FORM ORBITS:
  orbit_position(epoch) is pure (periodic, radius-honoring, null
  safe); window_favorability keys on ORBITAL PHASE not distance
  (a circular moon keeps constant parent distance -- physics note
  in the docstring; first implementation normalized against a
  pivot-relative span and was wrong for root-pivoted moons);
  next_transfer_window scans epochs to the horizon. Content:
  data/worlds/{world_main,world_underworld,world_moon}.tres (moon:
  1.2 km, 6 m/s^2, no atmosphere, 8-sky-day orbit, DEV_ONLY;
  underworld: 2 km, OFFLINE mystery layer). probe_world_lattice
  27 checks in DEFAULT_SET (16 entries); regression 40/40; lint
  EXIT 0. Lesson: window_favorability's arg-pairing bug was caught
  by driving the function inline with prints -- the swap logic read
  the moon twice; untyped `var body = b if ab == a else a` was the
  culprit (condition inverted, not the math).
- [x] S12 real glider mechanic SHIPPED (2026-09-28): GliderState
  frame primitive (game/core/frame/srv/glider_state.gd + co-located
  test 14/14): GROUNDED/FALLING/GLIDING/STOWED_FALL; deploy gate
  6 m, auto vs manual (jump-again, 4 s grace, PlayerConfig
  "glider_deployment" account setting), stow mid-air; glide model
  4.5 m/s sink / 7-16 m/s by dive pitch / thermal lift to 3 m/s.
  All-realms: the same primitive drives the radial globe body
  (altitude above local surface, integrated in _physics_process
  with glide vertical/horizontal move_toward) and planar rooms
  (ROYALE drop). Anticheat set_glide_active swap wired in the
  glide branch + cleared on landing. MOUNT_DISMOUNT_ON_FALL: the
  mount bails, the rider keeps the fall (rule decided once in the
  primitive; implementation rides the mount system when it lands).
  probe_glider 9/9 in DEFAULT_SET; regression 37/37; lint EXIT 0.
  Lessons: --check-only has no autoloads (resolve PlayerConfig/
  AntiCheatService at runtime via Engine.get_main_loop); the
  headless probe cannot run the physics loop -- verify the math
  the body executes (settle-loop pattern), not the loop.
- [x] S12 scene swap + spectate SHIPPED (2026-09-28): ScopeService
  autoload (enter_room_scope / exit_to_globe / enter_spectate_scope;
  reparent + planar_mode flip; pre-swap parent remembered as escape
  hatch; room-closed net RESCUES players from freed rooms -- the
  regression caught the trial probe dying on 'previously freed')
  + globe_player.planar_mode (radial math yields to planar contract
  in-room; globe path verbatim when off; + entity_id field) +
  LobbyService.request_spectate (friend/party allowed with reason,
  stranger refused) + ArenaInstance.spectators book +
  BoutTeleportService drives both swaps (assembly reparents before
  positioning; return exits scope before the world move).
  ZoneManager zone-entry log de-crashed for bodies without
  display_name (get() guard, not direct access). probe_scene_swap
  14/14 in DEFAULT_SET: reparent/flag both ways, planar gravity,
  permission matrix, spectator exclusions, rescue net. Lessons:
  the scope swap MUST rescue on room close or queue_free'd rooms
  free reparented players (regression caught it solo probes
  missed); Node.get on a missing property returns null and
  bool(null) throws in 4.7.2 -- compare == true instead.
- [x] S12 dungeon front door SHIPPED (2026-09-28): InstanceService
  zone_kind (bout/dungeon/open; discriminator = horde_config_id
  because ELIMINATION is instance_mode 0 -- mode cannot separate
  arenas from dungeons), join_dungeon (same contract checks as
  bouts: capacity/party_fits/QoS) + session book + backstops:
  AFK sweep (90 s contract / instance_afk_kick) returns idlers to
  the dungeon bind; dwell sweep (instance_time_limit > 0) returns
  the whole party and closes the session; _remove_instance_seat
  frees ZoneManager roster seats on return (no removal API existed
  -- seats were burning against capacity); note_instance_activity
  AFK ledger for fight code; HordeEventService untouched (horde
  loop rides zone entry ON TOP of the door). Gloomwood Depths:
  instance_time_limit 3600. probe_dungeon_front_door 19/19 in
  DEFAULT_SET (kinds, admission, session book, AFK return-to-bind,
  activity survival, dwell expiry, capacity enforcement).
  Lessons: _dungeon_sessions.get returns a COPY -- mutate then
  write back or the change evaporates; a str_replace cleanup can
  leave an orphan duplicate line two lines below the fix (sweep
  TWICE with --check-only before probes); entry-denial backoff +
  cooldowns + QoS buckets all need clearing in probes when the
  subject is the path, not the throttle.
- [x] S12 social presence + LFG kinds (2026-09-28, next session):
  LobbyService get_presence/get_friend_presence (joins EntityService,
  ZoneManager._entity_zones, PartyService, lobby queues,
  ArenaRoomService into one row: online/zone/party+size/queue/
  bout-instance/instance-zone); petition_party + party_leader_id
  (consent path). LobbyUI 4th tab People: presence rows with
  Join-queue / Ask-to-join / Spectate-greyed actions. LfgKind enum
  (PARTY/DUNGEON/RAID) in the one LFG book; list_lfg kind_filter;
  solo posters auto-form their party on first petition (petitions
  need a party home; 0-seat hidden rows fixed with a company-slot).
  QoS: party instance creation now attributes the leader as owner
  (get_or_create_party_instance threads party_leader_id into
  create_instance -- the previously dead per-owner limit now binds
  for party joins too). probe_social_presence 17/17 in DEFAULT_SET;
  regression 34/34; lint EXIT 0. Lessons: create_party spends the
  same 30 s party_invite cooldown (clear the bucket when the test
  subject is the routing, not the throttle); pending INVITE != party
  membership (inspect _pending_invites "to"+"party_id"); a
  --check-only Compile Error for an autoload identifier is script-
  mode noise, full-boot regression is the arbiter.
- [x] S12 trial bout SHIPPED (2026-09-28): LobbyService queue-aging
  sweep (TRIAL_PATIENCE_SECONDS 45 on the 5 s timer ->
  trial_fallback_due(zone, block), block popped, _player_zone
  cleaned); BoutHostService fabricates 2 marshal's dummies
  (trial_health 45 via ArenaFighter, entity-FREE, bridge resolves
  their deaths from real entity damage_dealt via effective_health
  -- real fighters untouched, hp<=0 guard), AFK sweep exempt,
  4 s fast start, queued block's origin stone honored, reduced
  payout (40 XP + 10 gold / 15 XP loss) + quest/achievement credit:
  quest_arena_trial "Prove Yourself" (KILL "marshal's dummies" x1,
  elder-gated lvl 1-8) + achievement_trial_by_fire (bout_win via
  AchievementService.track). Trial id uniquifier (_trial_seq) after
  a same-second collision. probe_trial_bout 26/26 in DEFAULT_SET;
  regression 32/32; lint EXIT 0. Lessons: a str_replace inserting
  effective_health() replaced respawn_at's header (orphan body,
  parse errors downstream) -- always re-read after insertion edits;
  the sweep signal auto-hosts, so probes ride the real wiring
  instead of double-calling (same-second id collision).
- [x] S12 keystone SHIPPED (2026-09-28): BoutHostService autoload
  (on bout_assembled: spawn room, seat LINKED fighters by entity_id
  w/ real levels into the power book, seed origin stones from the
  signal's 5th arg, arm the start timer at the zone entry deadline
  w/ room.start_deadline_override probe seam, on bout_ended -- bind-
  keyed -- payout + queue_free). Payout: winners 120 XP + 25 gold,
  losers 40 XP via PlayerManager duck-typed ledger. Owner clarifier
  enforced: seats bind the live entity, no loaner forms, stats
  restore post-bout. bout_assembled grew a 5th arg (origin stones
  dict); teleport + host listeners updated. probe_bout_host 21/21
  golden path (enqueue -> assemble -> host -> start -> normalize ->
  kill -> payout -> home -> restore), in DEFAULT_SET. Lessons:
  script-mode InstanceService needs refresh_registry() after
  load_zones() (boot-order registry gap); bind signal args (connect
  .bind) over emitter-scanning when a handler needs its source.
  Regression 31/31. Trial-bout fallback is the next open S12 item.
- [x] S11 loop closed + ROYALE/glider groundwork (2026-09-28):
  BoutTeleportService autoload (assembly scatters player entities
  into team staging via Contract.scatter_spawn; bout_return_requested
  -- room signal AND direct apply_return_map seam -- moves everyone
  home; missing nodes skip+log, never half-apply). ROYALE drop in
  arena_instance: start_bout throws fighters to 0.8x-half height on
  a wide ring (0.35x half, min 0.45/fighter, 30 never stack).
  Glider groundwork: 5 glider_ .tres devices (data/gliders, MountData
  schema), movement_glider profile (AERIAL, gravity 4.5, fall 8,
  jump 0/false), anticheat GLIDE_MAX_SPEED/FALL + set_glide_active
  swap/restore. Probe probe_bout_flow 26/26 (new in DEFAULT_SET).
  Lessons: stamp WORLD limits from the player's ground profile (fall
  55x2=110) and GLIDE maxima from the wing profile separately --
  conflating them fails the restore check; standard tres fall is
  55.0 (the 110 in the service fallback is a constant, not a
  profile value).
- [ ] S11 goals added (2026-09-28): bout assembly engine, solo
  matchmaking queue, fill-to-parity consent flag (see PRD S11).
- [x] S10 arena wiring (2026-09-28): arena_instance.gd planar room
  + bout controller (rules from bout_rules, never hardcoded;
  elimination last-team-standing + TDM respawn/shield/kill-target
  paths; bout_started/ended/fighter_down ready for S11 duels),
  arena_fighter.gd contract-gravity bodies, arena_gateway.gd Area3D
  built into globe_island (dedupe in-volume, re-arm on exit, party
  joins via PartyService roster, OPEN/FULL + deadline toasts).
  Probes probe_arena_instance 24/24 + probe_arena_trigger 14/14 in
  DEFAULT_SET; regression 27/27. Scene swap into the room stays a
  GameManager flow item (headless-probed logic; visual verify in a
  rendered session later).
- [ ] S11 duel bouts (planned): private instances. Challenge
  handshake (PartyService pending-invite pattern, 60s timeout) creates
  a bout-owned instance; both parties join_party_instance into it;
  LOCKED on start; ELIMINATION bout = last team standing ->
  TitleService reward. TEAM_DEATHMATCH bout (sandpit zone) rides the
  same controller via bout_rules: respawn + spawn shield buff,
  score to kill_target. S9's one-live-instance rule applies to
  PUBLIC instances only; private instances are explicit bout rooms.
- [x] S9 instances/lobby contract (2026-09-28): InstanceContract
  constants (planar -Y gravity 20.0 sealed per locked decision 3,
  LobbyState enum, entry deadline + override), InstanceService
  autoload (front door over ZoneManager lifecycle: per-zone contract,
  capacity-checked join, lobby queue semantics -- FULL returns
  capacity_ok=false and NEVER spawns a phantom second instance),
  ZoneData.instance_entry_deadline, arena zone_arena_coliseum.tres
  (FREE_PVP cap 12 -- full 6v6 parties per locked decision 4),
  ZoneManager.add_to_instance now enforces capacity
  (the gap: can_enter_instance checked it but no join path called
  it). Probe test_instance_contract.gd 40/40 in DEFAULT_SET.
  Pickup: prd-spherical-mvp.md S9.
- [x] 20 km stall FIXED (S8 continuation, 2026-09-28): floating
  origin + re-anchored surface pad. Proven root cause: the BODY's
  own world-transform magnitude (local-floor experiment: free walk
  at |r| = 200 with planet_radius = 20000, 0.03 m at |r| = 20001);
  collider-locality alone does not fix it and world-space trimeshes
  are degenerate for physics import. globe_island.gd: planet-bound
  content under world_root, _maybe_shift_world moves planet AND
  player by the same delta past SHIFT_RADIUS = 1500; one curved-disc
  pad (local coords <= 64 m) re-anchored under the player every
  frame carries planet-scale collision (megasphere disabled > 2000
  m). planet_center threads through player snap/glue, streamer face
  addressing (planet-relative update()), and the rock-top provider.
  Streamer patches are vertex-local under world_root; per-patch
  trimesh machinery REMOVED. Walk surface = R + 0.52 + 1.0 only at
  planet scale (prototype keeps shell contact; test-caught).
  probe_planet_scale_20km flipped to the fix: 25/25 incl. forced
  rebase stage. Regression 24/24 + lint quartet. Pickup:
  prd-spherical-mvp.md S8.
- [x] Planet-radius config + 20 km probe S8 (2026-09-28): config
  `synmergia/world/planet_radius` read by globe_island.gd; SHELL_RADIUS
  renamed to planet_radius var; probe_planet_scale_20km.gd
  (control/stall/isolation experiment, 11 asserts exit 0) registered
  in the runner. VERDICT OPEN: 20 km walk stall (0.14 m vs ~48 m
  commanded) persists with the radial snap OFF and gravity is
  canceled by the shell contact -- physics-contact float32 precision
  is the lead suspect, not the snap and not transform precision.
  Probe Stage C tripwire asserts the stall until a fix lands.
- [x] Full-flow spherical driver S6 (2026-09-28): GameManager world
  scene branches on the shape knob (planar default intact),
  test_world_shape.gd, globe_driver.gd (real menu->select->Play->
  GlobeIsland flow, xvfb pixel-verified 6 stages, radial err
  0.001 m, HUD over the globe). Regression 22/22.
- [x] Terrain streaming S5 (2026-09-28): icosahedral_faces.gd
  (20 face regions, Voronoi-exact point->face, min-chord edge
  construction -- lesson: chord-2.0 golden-rectangle triples force
  min-chord anchoring), globe_terrain_streamer.gd (4-patch steady
  state, ~7 m tiles, per-face tints), probe_terrain_stream.gd 9/9
  headless + rendered (border crossing swaps stale patches; all-20
  sweep). Regression 20/20. Pickup: prd-spherical-mvp.md sec 0.
- [x] Spherical world MVP (2026-09-27 night): S1 spherical.gd
  frame primitive (haversine/bearing/great-circle/converters,
  7/7 known-answer groups incl. Icosahedral convention match),
  S2 world_shape.gd project setting + WaypointService shape-gated
  haversine + new get_bearing_to_active, S3 globe-island radial-
  gravity prototype (globe_player.gd + globe_island.tscn/.gd,
  probe 12/12 headless AND xvfb-rendered, pixel-verified stages:
  250 m equator walk, zero radial drift, curvature ratio 1.31 =
  predicted chord math, live cell+neighbors) -- pickable via
  labs/prd-spherical-mvp.md (pickup protocol in its sec 0).
  Runner now resolves co-located frame tests (`frame/<rel>` names);
  regression 18/18 including the two new tests in DEFAULT_SET.
- [x] Rando batch 14 (2026-09-26): door-open world event + chapter-
  gated mysteries (user picked: audio path A + mysteries, sky-code
  first, title + small XP rewards).
  AUDIO (the repo's first): scripts/gen_door_open_audio.py synthesizes
  3 deterministic WAVs into game/audio/ (ancient_door_open chime+
  rumble, mystery_solved resolve, ui_click tick) -- the model-pipeline
  convention (deterministic assets from scripts, committed, no
  hand-edited binaries). AudioService autoload (core/autoload/
  audio_service.gd, registered after ActsService) plays them through
  a 6-player round-robin pool, non-positional (the door bell is
  communal -- heard shard-wide); play/play_world/play_ui, unknown
  names warn not crash; ensure_initialized for script mode. FRESH WAV
  LESSON: a new .wav fails to load until an editor/import pass -- run
  the headless import boot once before the test suite.
  DOOR PAYOFF (ancient_door._open): PayoffPillar (30m emissive amber
  cylinder) + PayoffFlash (OmniLight3D) bloom at the slab, sky
  renderer's new flash_payoff(seconds) tints the whole star pool
  amber then restores each star's OWN current tint (first cut lerped
  to the default blue and would have re-colored untouched stars),
  and AudioService.play_world("ancient_door_open") fires -- the shard
  FEELS the door. probe_ancient_loop 3d asserts pillar + flash + API.
  MYSTERIES (chapter-gated puzzle content on ChronicleUI's
  _add_section hanging point): MysteryData schema (core/schemas/
  mystery_data.gd); data/mysteries/mystery_*.tres (new mystery_
  prefix, lint-enforced); answer_kind SKY_CODE derives the answer
  from SignService.get_ancient_code(answer_day) at attempt time --
  NOTHING answer-shaped is ever stored (the sky's own record is the
  answer key); answer_kind OBSERVATION_TALLY derives from the live
  sign catalog count. ActsService gains the solved ledger (DictStore,
  per-player, int-key normalize on load): attempt_mystery gates on
  act chapter records (unknown -> locked -> wrong -> solved), pays
  TitleService.unlock + duck-typed XP (the KillRewards pattern),
  toasts ACHIEVEMENT_UNLOCKED. ChronicleUI renders teaser (locked),
  riddle + LineEdit input (unlocked), full record (solved).
  Two mysteries shipped: The First Vault (sky code of day 1 -- the
  almanac IS the world's memory) and The Watcher's Tally (count the
  catalogued signs), rewarding title_vault_reader and
  title_wardens_word.
  FIXES this batch (test-caught): QuestService._load_player_quests
  scanned ALL DictStore keys without filtering its own prefix and
  hard-cast with `as Dictionary` -- accumulated KV from other
  services (4.7.2 strict cast) crashed it; now filters quest:player:
  and is-instance checks. TitleService._do_unlock hard-failed when
  _title_defs was empty (boot race / script mode -- definitions load
  in _ready); lazy-loads once when empty, genuinely unknown ids still
  warn. Test-side: the tally suite must NOT clear the solved ledger
  (distinct mystery ids cannot collide; clearing erased the vault
  solve before the persistence check), and the round-robin assertion
  derives its expected index instead of assuming a full cycle.
  Regression 16/16 (new test_mysteries 6 checks + test_audio_service
  4 checks; probe extended). Docs: prd-psy section 10, AGENTS.md
  (mystery_ row, test table).
- [x] Rando batch 13 (2026-09-26): blessed-class visual motif (user:
  "let's make a blessed-class visual motif ... different from GM gold
  ... leverage the title system to add a blessed title or
  distinguishable icon in front of the existing title prefix").
  MOTION MARK (game/entities/blessed_mark.gd): eight sky-cyan motes in
  a breathing ring + a soft halo behind the head, lit ONLY while
  SignService.is_class_blessed says the wearer's class is the wheel's
  earned pick (no solve, no glow -- the earn gate rides inside the
  mark); 10s recheck cadence for live day-rolls and late code
  assemblies, transition toasts once per flip, set_wearer(class,
  wearer) duck-typed so tests pass plain dicts. Attached twice over
  (world_playable._setup_blessed_marks AND PlayerController
  _attach_blessed_mark deferred -- both idempotent, class rebinding
  rebinds). SIGIL: "(*)" in #73D9FF rides IN FRONT of
  TitleService.get_display_name's composition ("(*) [The Slayer]
  name") -- the sky outranks the mortal honors for a day; GM classes
  exempt (staff gold stays alone). CHAT: plain-text sigil + channel
  color swap in format_message (THE LESSON: display names pass
  through _escape_bbcode, so injected markup gets stripped -- no
  [color] in the name, prefix + recolor instead). Almanac's blessed
  line now demos the sigil. PARSE-ERROR CASCADE (3 compounding
  traps, all documented but now personally verified): (1) a brand-new
  class_name is invisible to the global cache until an editor import
  -- BlessedMark unresolvable everywhere (the GuardData lesson, hit
  exactly as AGENTS.md warns); fixed by dropping class_name and
  preloading the script in consumers (statics + consts work through
  preload). (2) A script preloaded at parse time cannot use BARE
  autoload identifiers -- entity.gd:198's EventHub made even a
  string-extends fake uncompilable standalone; the mark now resolves
  SignService/NotificationService late via Engine.get_main_loop (the
  CombatMath static pattern). (3) EntityService.register_entity
  needs a real Entity node (internal targeting + EventHub), so the
  title-composition test pins the ORDER at the logic level instead
  of registering fakes. Regression 14/14 (new test_blessed_mark, 5
  checks: sigil truth, GM-gold distinctness, mark visuals, transition
  toast, title order), boot clean.
- [x] Rando batch 12 (2026-09-26): daily quest reset + RECORD_INSIGHT
  objective + Chronicle panel (user: "Yeah we can do the daily-quest
  reset + 'record an insight' objective for quest_watch_the_sky. I
  feel like a dedicated Chronicle lore panel would be useful too").
  DAILY QUEST: QuestData gained RECORD_INSIGHT (enum index 11 --
  ACHIEVE_STEP was the last); QuestService bridges
  SignService.insight_recorded -> update_quest_progress(RECORD_INSIGHT,
  "sky_insight") per player (deferred connect: SignService is a later
  autoload, the null-instance trap), and _maybe_reset_dailies erases
  REWARDED DAILY quests at the day boundary on a 60s timer -- the
  reset reads SignService.current_day_index() (NEW helper honoring
  the clock override; my first version read the raw clock and the
  admin time-travel desynced the calendar, caught by the test).
  quest_watch_the_sky.tres (DAILY, repeatable, 1x sky_insight,
  25g/50xp, elder giver) auto-accepts in world_playable beside the
  hunt. FOUND + FIXED a live bug on the way: the QUEST_COMPLETED
  toast used 2-arg Resource.get ("data", {}) -- 4.7.2 removed the
  default arg, so ANY quest completion script-errored the moment a
  player completed anything in script mode. CHRONICLE PANEL:
  chronicle_ui.gd (J key = journal, MenuManager "chronicle"),
  scrollable acts reader -- full record lines for recorded chapters,
  sealed frames naming WHAT they wait on ("opens when day N's Ancient
  is earned"), never the lesson; _add_section(title, lines) is the
  extension point for future mysteries/puzzles; almanac gained an
  "Open the Chronicle" button that closes itself and hands off.
  TESTS: test_daily_quest.gd (5 checks: data shape, per-player
  credit, turn-in, reset, full re-earn loop; pins days +300/+301 to
  stay clear of other suites); test_acts_service grew the panel check
  (13 checks total). Regression 13/13, boot clean.
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
