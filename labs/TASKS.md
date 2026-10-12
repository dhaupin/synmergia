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
- [x] The Folded Shell BUILT (2026-09-29, owner: "intersection
  vectors as infinite, even between 2 spaces; increasing surface
  area increases store/state; let's crush on a literal geometric
  shape that solves storage, compute, ram, and stress"): frame
  primitive frame/kv/folded_shell.gd + co-located test (21 checks,
  in DEFAULT_SET). The owner's two intuitions are real physics and
  now mechanism: (1) SURFACE STORAGE -- the holographic law
  (Bekenstein: information scales with boundary area, not volume;
  brains fold cortex in a fixed skull): NSC-9 cells on a folded
  2-manifold, each fold FOURFOLDS capacity in the same footprint,
  complete 4-ary heap addressing children(p)=4p+1..4p+4, 4^depth
  per facet, MAX_FOLD_DEPTH 11 (4.2M cells/facet in the 24-bit
  sequence), fold refused past the budget; (2) THE INTERSECTION
  REBATE -- content-hash cells claimed by many spaces, shared
  facts stored ONCE (T3 law applied to geometry), removal
  intersection-aware (a leaving space never erases claimed
  state), rebate() MEASURES the savings. Stress bounded not
  feared: LRU hot set with evictions counted, no integration.
  LESSON (the discipline pays): my first slot-base addressing had
  the root's first child = the root's own address (cell 0
  collision) -- the co-located test  caught it before any consumer existed; rebuilt on the classic
  complete-heap law, provably collision-free. Also: GDScript
  compares dicts by CONTENT, so never branch on dictionary equality
  (use ids). Regression 41/0 pending re-run with the new entry,
  lint 36/36.
- [x] T3 Dedup at Scale SHIPPED (2026-09-29, owner queue: "square
  up T3 dedup at scale"): the FIRST FoldedShell consumer. t3.gd
  node records slimmed to (path, hash, schema, cell); the payload
  VALUE lives in a content-hash cell on the shell -- identical
  state blocks pay ONE store, every path re-claims the cell (the
  rebate in production; savings_ratio() measured, test shows 300
  stores over 12 distinct states = 12 cells, ~0.96 savings).
  Content bytes are identity, so dedup CANNOT change tree identity
  -- the same-root proof is in the co-located test (15 checks,
  DEFAULT_SET frame/kv/test_t3_dedup): byte-identical rebate,
  no-false-merge, scale measurement, same-root, diff/apply re-claim
  (transport unchanged -- only the store changed), Resource
  fallback (inline cells; Object identity is not content),
  intersection-aware clear. get_full_scope_snapshot/diff still
  carry value_bytes, so the wire format and full-boot resync paths
  are untouched. Lessons: (1) T3 content is IMMUTABLE (the node
  hash folds the content) which is WHY sharing decoded values
  across paths is safe -- but only while every consumer treats
  returned payloads as read-only; the contract test holds that
  line; (2) rebasing nodes under apply_diff must _store_value again
  -- diff bytes carry no cell keys; (3) a no-dedup baseline counter
  must count ATTEMPTED stores, not paid ones (paid == distinct
  makes the ratio identically zero -- caught it in review).
- [x] X2 Star Cells SHIPPED (2026-09-29, owner queue: "star cells
  for X2"): frame/srv/star_cells.gd + co-located test (21 checks,
  in DEFAULT_SET as frame/srv/test_star_cells). Stars exist because
  their NSC-9 address says so -- one 32-byte derive_seed(universe,
  "star:<address>") IS the verdict: top byte high bit = existence,
  ladder bytes map into the historical O B A F G K M spectral
  classes with temperature/luminosity/radius, ALL DERIVED (nothing
  stored that nobody chose; empty addresses return {}). Storage is
  the FoldedShell: observe_facet walks a facility/axis sequence
  space (the galaxy tier's hourly EVALUATE exercised for real),
  stores each found star as a content-hash cell, and every observer
  (shard / far-gaze / almanac page) is a shell space that RE-CLAIMS
  the shared sky -- one universe, one sky, many claimants, rebate
  measured between observers (test: two observers of one facet, one
  store; different facets ~no intersection). Telescope = address
  lookup not raycast: telescope_lookup(facility, axis, sequence)
  deterministic across installs. Ladder closure: the galaxy tier's
  own anchor (nsc9:0) now evaluates through the primitive, and the
  test reads c + H0 off the universe tier -- the reservations
  consume. Lessons: (1) NSC-9 has TWO encodings (decimal 14-digit,
  bit-packed uint64) -- decode with the format you encoded with,
  their decoders do NOT interchange (my own gotcha list, bit me
  again in test code); (2) shell measurement needed a total
  distinct-fact accessor -- added fact_count(); (3) empty-seed
  edge in SeedChain is a real derivation surface: a 32-byte
  SHA("universe:...") works as an alternate-universe seed for
  testing "different seed = different sky".
- [x] QC pass on the two new consumers (2026-09-29, owner: "run
  some qc and logic tests against our new changes first ... make
  sure there's no weird edges, gaps, bugs we missed"): three real
  gaps found and closed BEFORE the moon arc builds on them.
  (1) PHANTOM STARS: star_cells took unguarded facility/axis -- a
  call at facility 1234 (or negative) would derive stars at
  addresses NO NSC-9 decoder can reach: stored, counted,
  unreachable by any telescope. Fixed with the address-domain law
  (facility/axis 0..999, sequence 0..999999; observe_facet refuses
  + push_error, telescope_lookup returns {} -- the same answer as
  an empty coordinate, never a phantom; sequence_limit clamped so
  a bad caller cannot turn the hourly EVALUATE into a stress
  generator). encode_int is INJECTIVE on the domain (999*1e6 +
  999999 < 1e9), which is what makes one address name exactly one
  star -- now stated and tested. (2) CONTENT LAW UNPINNED: the
  hash IS identity, so first store wins and key ORDER is part of
  content (var_to_bytes is insertion-order) -- both now tested
  rather than assumed; two equal-but-distinct Resources stay
  distinct (identity law). (3) UPDATE-HEAVY WORKLOADS pinned:
  overwrites accumulate distinct content cells (content-addressed
  history, same asymptotics as the T3 snapshot law -- no
  regression, stated honestly; savings_ratio() = 0.0 on
  all-distinct workloads as it should be), and a 20-update chain
  roundtrips through diff/apply EXACTLY with the root DELTA only
  -- intermediate history never crosses the wire (diff carried 1
  entry, destination paid 2 cells, not 21: the transport theorem
  working BETTER than my first assertion claimed). Insert-batch
  obeys the same rebate (50 over 10 distinct = 10 cells). Test
  totals: t3_dedup 15 -> 23 checks, star_cells 21 -> 25.
  Regression + lint re-run before push.
- [x] S16.6 Dev Flip SHIPPED (2026-09-29, owner: "hit the dev flip
  next, get all our stuff on the moon lol, so the world is clean"):
  the moon is the dev target and the Moon Gate COMPLETES transit.
  Mechanism in authority order: (1) world_moon.tres keeps offline=2
  (DEV_ONLY) -- the lattice still says not-a-player-world; the flip
  changes WHO MAY KNOCK, not the declaration. (2) moon_gate.gd grew
  dev_hatch (default false): a hatched gate lifts a DEV_ONLY
  destination to open FOR ITSELF (law state 2, prompt "Step
  through"); OFFLINE worlds refuse for everyone -- the hatch
  cannot open doorless worlds (probe-verified). The placed gate in
  world_playable opts in; default gates stay the sealed mystery
  shell. (3) At transit the gate CONJURES the destination:
  scenes/worlds/globe_moon.gd instantiates (load-by-path, GuardData
  lesson), registers world_root_moon, reads radius from the
  declaration (1.2 km, sphere collider ON -- under the
  PLANAR_SHELL_MAX_R stall threshold), hangs earthrise (ParentSky),
  stands a return Earthward Gate, and receive_visitor() adopts the
  body (bind_to_world for globe bodies, world_id for planar
  visitors -- the gravity/vacuum laws read it; landing on the
  regolith tilted toward the home meridian). (4) The swap rides the
  SAME ScopeService seam with force=true -- one seam, no new
  transport. The conjured globe folds back into derivation when
  the last visitor leaves (tree_exiting tracking); the next
  transit re-derives it identically (the seed never forgot).
  Probe: section G rewritten for the flip (default gate sealed,
  hatch opens, underworld unopenable even hatched) + G2 end-to-end
  (conjure, group, scale-from-declaration, return gate, earthrise,
  lunar law adoption, landing radius, seam transit, return) -- 65
  -> 77 checks. Lessons: (1) the probe's visitor needed
  EntityService registration (gate_walker got it, moon_dev didn't
  -- _player_node resolves through EntityService.get_entity);
  (2) world_playable's player is the PLANAR PlayerController (the
  main world has no planet_center) -- adaptation must probe for
  what a body actually has ("world_id" in body), not assume the
  globe shape; (3) conjure-holder must be the current SCENE, never
  the gate (a freed gate must not take the moon with it -- same
  law as ScopeService's escape capture).
- [x] WASM BOOT FIXED + Startup-Flow Audit SHIPPED (2026-09-30,
  owner: "now it's loading! Got to the species select page, and
  there's no way to choose -- go through startup, guest, species
  select, class select, through playing and see what isn't wired
  up"). ROOT CAUSE of the wasm dead-end: the custom shell loaded
  /game.js ABSOLUTELY while served under /web/ -- the request fell
  through to the React SPA and returned HTML as JavaScript, so
  Engine never existed (black pane + Retry for every visitor). The
  shell also carried invented identifiers (SynmergiaThreadsEnabled
  -- a Godot-to-Synmergia rename accident) and a 20 s watchdog that
  faked failure on slow 38 MB downloads. FIX (df6426b): boot block
  now mirrors the REAL export shell (web/game.html): relative asset
  paths, the 4.7 config keys (pools 8/4, fileSizes matching the
  shipped binaries for honest progress), watchdog fires only when
  NOTHING ever progressed. Memory dropdown: disabled BY DESIGN but
  the reason hid in a desktop-only tooltip -- now the lock's
  explanation is drawer text (initial heap is baked in game.wasm;
  getModuleConfig whitelists Module keys; Emscripten grows the
  heap at runtime anyway). STARTUP FLOW AUDIT (probe_startup_flow,
  18 checks, DEFAULT_SET): species data -> picker (3 species, GM
  filtered), species select -> class list (6 human classes), class
  select ENABLES Play, direct play reaches PLAYING with species +
  class + home zone, guest login exists, LOBBY-without-auth
  bounces to LOGIN (the gate holds). The REAL species-select
  dead-end: character_select.tscn was a FIXED-PIXEL layout (an
  800 px bottom-anchored strip) inside a 1280x720 canvas_items
  stretch -- on a portrait phone the UI renders at ~0.3x and the
  card Select buttons are ~9 px: untappable. FIX: scene rebuilt
  responsive (full-rect ScrollContainer -> List VBox -> HBox strip
  sized by content; Back bottom-left / Play bottom-right corner
  anchors; cards 240/300 px min height) + sensor_landscape
  orientation for handhelds. Login/lobby were already responsive
  full-rect (why they worked on the phone). Regression 50/0,
  lint 36/36, data naming 24/24.  Lesson: fixed-pixel menu layouts
  + a stretch-based scale factor = invisible-but-real mobile
  dead-ends; probe the SCENE GEOMETRY (anchors, min sizes), not
  just the signal graph.
- [x] EXPORT-SAFE RESOURCE SCANNING SHIPPED (2026-09-30, species
  select still empty after the responsive fix: owner reloaded in a
  private tab, same result). ROOT CAUSE: Godot's exporter converts
  text .tres resources into BINARY .res files inside the pack (plus
  .tres.remap sidecars that rewrite path references) -- 14 runtime
  scanners filtered ends_with(".tres") and found NOTHING in the
  exported web pack (boot printed "Loaded 0 species / 0 classes";
  data grep-proved present). Dev-tree tests cannot see this: the
  exporter only runs in CI. FIX: new frame primitive
  core/frame/srv/resource_scan.gd (ResourceScan.list_resources /
  load_dir / resource_base: handles .tres, .res, .tres.remap,
  .res.remap; dedupes the .res vs .tres.remap pair to one resource;
  normalizes trailing slashes; missing dir = empty). All 14 scan
  sites refactored onto it (data_service, character_data fallbacks
  x3, world_registry, achievement_service, dialog_service,
  ferry_service, horde_event_service, ocean_service,
  open_seed_registry, shard_parameters, spawn_service,
  thermal_service, targeting_manager, sky_almanac_ui -- the last
  one missed by the original grep, found via the regression).
  _get_resource_id now delegates to ResourceScan.resource_base,
  killing the latent ternary-precedence bug (length-5-if-else)
  before it ever fired. Co-located test_resource_scan (11 checks,
  DEFAULT_SET after probe_startup_flow). Regression 51/0, lint
  36/36, data naming 24/24. Lesson: scan by CONTENT FORM, never by
  one extension -- and the pack must be booted to prove an export
  fix (godot --headless --main-pack ../web/game.pck).
- [x] S15 THE DEEP ROOT BUILT OUT (2026-09-30, owner: "full S15 1-4
  -- set the underworld up and make it alive"). (1) S15.1 THE
  INTERIOR SKY: entities/interior_sky.gdshader -- an inverted dome
  (cull_front) rendering Synmergia's inner wall: strata banding by
  elevation, root veins by value-noise, all pulsing on a glow tide
  that is a PURE FUNCTION of the Concord epoch (fposmod(epoch_days /
  1.0) -- one cycle per surface day, dawn = high glow; no second
  clock ever). globe_underworld.gd feeds the material per frame and
  breathes a strata DirectionalLight with the same phase (the honest
  light floor for any renderer). (2) S15.2 REACHABILITY:
  world_underworld.tres offline 1 -> 2 (DEV_ONLY -- the same flip
  the moon got; the PLAYER entry law still refuses, OFFLINE-to-players
  stays true). MoonGate grew destination_scene (empty = convention
  path globe_<target_world>.tscn -- a conforming world needs NO gate
  code), so the underworld conjures like the moon. Lattice probe
  law-states updated (default gates still sealed; the hatch lifts
  DEV_ONLY; force=false still refuses). (3) S15.3 THE CAMP LIVES:
  zone_deep_root_camp.tres (bind at the camp head), npc_deep_warden
  .tres (glowing-cloak scene twin of the elder), deep_warden_greeting
  dialogue (where are we / why does the rock glow / work),
  quest_listen_to_the_deep (EXPLORE zone_deep_root_camp + TALK the
  Warden -- both REAL bridges: the globe fires player_entered_zone
  itself because ZoneManager's planar distance loop never sees a
  conjured globe, and dialogue_ended credits the turn-in; probe
  asserts COMPLETE through the live QuestService). Globe bodies have
  no entity_type, so _credit_arrival branches: globe bodies get the
  signal only (entity_enter_zone would dereference entity_type and
  crash), PlayerController bodies get the full roster path. The
  Warden spawns DIRECTLY on the surface (spawn_npc_entity + reparent
  under world_root -- the planar bind-point path would land her at
  the planet's core). (4) S15.4 THE ASCENT: the shaft-head monolith
  stands on Synmergia (-22, 0, 10) next to the Moon Gate -- the
  future PLAYER door down, sealed for everyone today (the mystery
  layer is the door that does not open), dev-hatched for round
  trips; at camp the Ascent names main with window_law OFF (a world
  and its own interior have no orbit phase to read -- moon_gate's
  static-pair refusal would block the way home). probe_underworld.gd
  42 checks (A declaration law, B gate law, C conjure+transit+law
  adoption, D internals, E interior sky + tide periodicity, F camp
  + zone, G quest bridge end-to-end, H fold-back), DEFAULT_SET.
  Verified: boot clean, underworld 42/42, lattice 94/94, lint 36/36,
  regression 52/0. Lessons: (1) a zone credit bridge is SIGNAL
  shaped, not coordinate shaped -- emit the same event the planar
  path emits and the whole quest pipeline works on a globe; (2)
  gates to non-orbiting pairs must set window_law=false or the sky
  law refuses a way that has no sky; (3) dev flips are DECLARATION
  edits (offline=2) plus ONE hatched gate -- the player law never
  changed and no default gate moved. Next: glow-tide content hooks
  (S14.x water mount in the crater pool?), the Warden's second beat,
  and eventually the mystery that seals the Ascent shut.
- [x] GLOBE NAMING CONVENTION + RENAME SHIPPED (2026-09-30, owner:
  "why is it called globe_island? let's make this a naming convention
  opp for zones, planets, etc -- imply relations like orbiting").
  DECISIONS: planet = Synmergia (already canon in world_main.tres),
  moon = the pale stone (kept -- lowercase, in-lore, mystery-friendly;
  "The Watched Stone" stays the epithet), underworld = The Deep Root
  (already canon). THE CONVENTION (now AGENTS.md "Scene & World
  Naming Conventions"): scene layer names by CONTAINMENT relation --
  globe_world (generic globe; radius from synmergia/world/planet
  _radius so one scene boots AS Synmergia at 20 km or the prototype
  at 100 m), globe_<world> for other bodies (globe_moon), runtime
  nodes Globe<Scope>, one scope-generic globe_player controller.
  RENAMES: globe_island.gd/.tscn -> globe_world (5 code refs +
  game_manager routing + project.godot comment + globe_driver node
  waits + 3 test files + test-runner entry), moon_globe.gd/.tscn ->
  globe_moon (the reversed-order inconsistency; group moon_globes ->
  globe_moons, no external consumers), class GlobeIslandPlayer ->
  GlobeWorldPlayer, ~20 labs doc refs. Residue sweep clean (only
  .godot cache, regenerates). Lesson: a rename's blast radius hides
  in (1) runtime NODE names the drivers wait on, (2) test-runner
  entries, (3) probe scene-path constants -- grep all three before
  committing. Canon names live in the .tres only; identifiers stay
  structural.
- [x] FEEDBACK SIX-PACK: touch gate + globe cleanup + camera-relative
  walk + HUD layout + one-HUD init + dual export SHIPPED (2026-09-30,
  owner 6-item in-browser feedback: controls over the main menu; garbled
  HUD; probe pillars; "remove globe island"; "1 init for the HUD";
  "wasm + native in one command"). (1) TOUCH GATE: InputManager no
  longer auto-shows the touch HUD at boot -- _ready creates it hidden
  and GameManager game_state_changed/paused/resumed drive
  _on_gameplay_state_changed, which only reveals it in PLAYING/PAUSED
  and hides it EVERYWHERE else (menus, character select). hide_joystick
  not visible=false: a CanvasLayer keeps receiving _input while
  invisible. PlayerConfig touch_controls still decides WHETHER it shows
  in gameplay. (2) PROBE PILLARS REMOVED: globe_world._build_probe
  _markers/_make_marker deleted (the red/blue/yellow boxes the owner
  walked into); _build_arena_gateway now called from _ready (it used to
  ride inside the deleted function -- caught on diff review, the
  gateway would have silently vanished). Scene stays: planet_radius
  setting makes it the 20 km prod globe and the dev moon shell.
  (3) THE REAL WALK-BLOCKER was not the pillars:
  globe_player's spherical branch moved on WORLD north/east
  (wish = east*x + north*(-y)), so after orbiting the camera "forward"
  walked map-north -- read as stuck against an invisible wall. Now
  camera-relative like the planar branch: forward/right projected from
  the PREVIOUS frame's CameraPivot basis onto the tangent plane
  (collapse guards fall back to the compass frame); auto_walk follows
  cam_fwd.rotated(up, auto_walk_yaw). Probe asserts are direction
  agnostic so no expectations changed. (4) HUD GARBAGE: hud_layer no
  longer forwards the class icon_path -- res://ui/icons/... rendered as
  literal text over the chat (now a "[C]" badge; paths are not glyphs).
  chat_ui self-anchors one TOP_LEFT rect (tabs+history+input in ONE
  panel; the old inner-vbox BOTTOM_LEFT anchor inside a CanvasLayer
  parent left its rect undefined) and _esc()s system messages.
  buff_bar/minimap keep their .tscn placement (they used to self-anchor
  over each other -- the corner pile + P N E Q * $ W strip). KEY LESSON:
  the guard is "were my own anchors set" (anchor_left/top/right != 0),
  NOT parent type -- hud_layer.tscn parents widgets to a CanvasLayer
  root, so `get_parent() is Control` is always false and the old-style
  self-anchor would have come right back. (5) ONE HUD INIT:
  HudLayer.ensure_installed(scene_root) is the single idempotent entry
  (instance-in-tree or child-name check, else load hud_layer.tscn);
  world_playable.tscn embeds it, globe_world delegates to it, any
  future playable scene calls one static. Touch controls are the other
  half of the contract and live behind the state gate. (6) DUAL EXPORT:
  scripts/export_clients.sh builds web/game.pck (preset "Web Default")
  + builds/linux/synmergia.x86_64 (NEW preset "Linux", embed_pck) in
  one command; --web-only / --native-only flags; web first (itch.io
  demos). Verified: boot parse clean, probe_globe_world 24/24 (walked
  250.0 m, curvature 1.75, orbit 90 deg, touch stick forward -1.00),
  regression 51/0, lint 36/36. Lessons: (a) fuzzy str_replace silently
  ate an `extends` line (hud_layer) and duplicated a function header --
  ALWAYS git-diff each patch and grep the residue; (b) when you delete a
  function, grep for what it CALLED (the gateway call was hiding inside
  the deleted marker builder); (c) a walk that "feels stuck" after a
  camera turn is a frame-authority bug -- input must be relative to the
  look frame, never the map frame.
- [x] PLAY-DAY 4: chat layering revert + the CLIMB LAW (2026-09-30,
  owner mid-party play-test: "fix chat to load under menus -- can't
  read stuff underneath it; make props not walk-through with a
  handler we can attach or that default-attaches; big rocks/features
  should need BotW-style CLIMBING with stamina"). (1) CHAT z 700 ->
  300: above the raw HUD widgets (100), BELOW the panel stack (500)
  -- unreadable bleed-through was worse than hidden chat; round-2
  probe assertion flipped to match the new law. (2) PropCollider
  (entities/prop_collider.gd, RefCounted, no autoload): the one-law
  attachment. attach(prop) auto-sizes a StaticBody3D (layer 2,
  "climbable" group) from the prop's mesh AABB union;
  attach_trunk(tree) makes a SLIM cylinder around the trunk only --
  canopies stay intangible (walking under a crown must not hit a
  ceiling); attach_all(root) is the default-wiring sweep for missed
  props (skips sub-MIN_VOL m^3 decorations). Bodies are prop
  children, so streaming drops them free. Globe streamer attaches
  trunks per patch; globe_player defaults collision_mask |= 2 in
  _ready so a scene that forgets the wiring still collides.
  LESSON (probe-caught twice): the trunk collider is a CYLINDER, not
  a box -- a sphere body wedges on box corners (slide budget
  exhausts) and dead-stops the walk; and a head-on push into a thin
  prop has zero tangential velocity so move_and_slide has nothing to
  slide along at all. The WEDGE ASSIST: when the wish speed is high
  but frame progress collapses against a climbable body, deflect
  along the wall tangent toward the wish -- walking into a tree
  slides you around it. (3) THE CLIMB LAW (globe_player): hold jump
  (not the tap that hops) against a steep face (normal steepness >=
  50 deg off up) or a climbable body within CLIMB_REACH 1.7 m
  (PhysicsRayQueryParameters3D, mask 2, group check) engages the
  climb; CLIMB_STAMINA_MAX 6 drains 1/s while grabbing, regens 2/s
  off-wall; the body sticks (-normal * 0.6) and rides the wall
  (wall-projected up * 2.2 m/s); cresting the wall mantles onto the
  surface and re-arms the radial snap; stamina empty or button let
  go releases. probe_climb.gd (11 checks: trunk slimness/group/
  layer, attach auto-size, idempotency, stamina pool, props mask,
  wall probe zero-in-open-space + steep-normal-on-hit) joins
  DEFAULT_SET. Verified: climb probe 11/11, terrain stream 9/9 (the
  blind auto-walk now deflects around a trunk sitting exactly on its
  line -- the probe IS the wedge test), round-2 UI 17/17, globe
  23/23, regression 55/0, lint 36/36, touch battery 17/17 xvfb,
  boot clean.
- [x] PLAY-DAY 3: round-2 feedback (2026-09-30, owner playing in the
  Freebuff preview: "jump works, sun works, minimap fixed... but").
  (1) #7 MOBILE HUD DEAD AFTER THE X: the panel's own close button
  routes through panel_closed -> _on_panel_closed, which erased the
  panel from _open_panels but never re-armed the touch HUD (only the
  MenuManager-initiated _close_panel path did). Same re-arm law
  applied to _on_panel_closed -- X, Esc, and funnel closes now all
  re-arm. (2) #4 MENU BELOW CHAT: chat sat at z 90 in MenuManager
  (layer 20) while every panel is z 500 -- the menu could never
  cover it. Chat is a persistent overlay, not a menu peer: z 700,
  above everything. (3) #5b SETTINGS X + the second-pass header: UI
  subclasses that build their Main AFTER super._ready() (settings
  builds Main in _setup_ui called from its own _ready) had no Main
  when _setup_standard_header ran -- fix is a DEFERRED second
  _setup_standard_header pass (idempotent; hand-rolled headers with
  a title Label are not double-titled via _header_row_has_label).
  (4) #5a ScrollFrame (ui/components/scroll_frame.gd): reusable
  scroll body with UP/DOWN arrow Buttons that appear only when the
  content actually overflows that way (tap-friendly on touch, built
  in _init so set_content works pre-tree). Wired into the expanded
  MainMenuBar (capped at 72% viewport height) and the Settings
  category stack (Controls keybinds overflow a 550px panel alone).
  (5) #3 NO ROCKS/TREES/TEXTURE: root cause was a PRE-EXISTING S7
  transform bug the trees inherited -- rock_specs dirs are
  GLOBE-absolute but the rocks/trees were parented to the patch node
  sitting at the face-center offset, so absolute coords used as
  patch-LOCAL displaced every scatter roughly a face-width off its
  true spot (floating in space off your tile). Placement now
  subtracts the scaled patch offset (patch-local), the tile mesh
  gained tangent-plane UVs * 0.22 with a 2x2 checker
  StandardMaterial3D texture (repeat via default UV wrap), and the
  tree basis handed to Godot had a mirrored north (det<0) -- fixed.
  (6) #1 PCK HASH CACHING: CI writes web/game.pck.hash (sha256 of
  the exported pack, tracked via .gitignore whitelist); game.html
  fetches it no-cache and starts the engine with mainPack =
  game.pck?v=<hash> (falls back to the bare path on any failure);
  worker.js serves ?v= requests immutable-for-a-year (edge-cached
  per full URL), 302s the bare path to the current hash, and serves
  the hash file itself no-store. A refresh now re-validates a tiny
  hash file instead of re-downloading the multi-MB pack; a new pack
  gets a new hash and every client picks it up next visit. PCK_HASH
  wrangler var is an optional zero-fetch shortcut for the 302.
  vite mime map gained .hash (dev + preview servers). (7) #8
  LOADING SCREEN NEVER SEEN: _show_loading_and_change_scene hid the
  overlay one frame after the deferred swap -- a 2-frame flash. Now
  it waits until the new scene is actually current_scene (safety cap
  600 frames), then holds a 700 ms minimum so fast transitions read
  as an intentional screen. (8) #6 EMPTY PANELS: MenuManager only
  called panel.open(pid) when a PlayerManager character resolved --
  in the guest/offline flow pid was empty, so _on_open (where most
  panels refresh) never ran and panels showed their ready-time
  skeleton. open() now runs unconditionally (panels defend against
  empty ids), and quest/bank/title gained _on_open refresh hooks.
  probe_round2_ui.gd (17 checks: ScrollFrame arrows, settings
  header/X/title, chat z, X-close re-arm) joins DEFAULT_SET.
  Verified: round-2 probe 17/17, touch battery 17/17 xvfb,
  regression 54/0, lint 36/36 (lint caught the scroll_frame doc
  example's self-preload string -- reworded), boot clean, tsc clean.
  Lessons: (1) a funnel law is only as strong as its least-used
  path -- the X button had its own close path nobody re-armed;
  (2) parent-local vs world-absolute coordinates: every scatter
  helper must DECLARE its frame in the comment next to the math,
  or the next helper inherits the lie; (3) deferred second passes
  are the honest fix for 'super._ready ran before my Main existed'
  -- fighting call order in subclasses just moves the bug.
- [x] PLAY-DAY 2: the wasm round + the ghost-teleport SOLVED
  (2026-09-30, owner playing in browser: "the minimap is bars, jump
  does nothing, panels won't close, Character tabs are empty...").
  (1) THE GHOST TELEPORT (play-day root-cause hunt, pre-existing
  S15 bug, NOT the day's edits): test_touch_live's player ended at
  (3, 2002.001, 2) = EXACTLY Deep Warden spawn (camp bind (0,2000,0)
  + npc spawn_offset (3,0,2)). Chain: S15.3 registered
  zone_deep_root_camp in the GLOBAL ZoneManager with planar-frame
  coords -> spawn_all_offering_npcs spawned the Warden INTO the
  planar world at y=2000 -> planar entry detection + boot position
  law seamless-transitioned the player to stand on him (only under
  the full live schedule; reduced repros stayed clean -- the
  schedule's movement phases put the player where the detector
  could claim him). THE FIX = world scoping (S16 law pulled into
  the data layer): ZoneData.world_id ("" = main/planar;
  zone_deep_root_camp = "underworld" -- world ids are UNPREFIXED,
  world_main.tres says id="main"); spawn_all_offering_npcs skips
  NPCs whose zone names a non-main world (the owning globe spawns
  them itself in its own frame); ZoneManager._zone_is_planar gates
  the seamless claimant scan, BOTH entry detectors (spatial +
  fallback), and perform_seamless_transition refuses subworld
  destinations outright. entity_enter_zone stays OPEN (globe
  bodies roster through it deliberately). probe_world_scoping.gd
  7 checks (new, DEFAULT_SET candidate). touch battery after the
  gate: xvfb 17/17 (was 12/5; headless stays un-runnable -- 64x64
  viewport vs the test's absolute coords, documented, NOT in
  DEFAULT_SET). P1 flake fixed the test's way (Land-recovery
  window at t=2.0 caught the spawn drop; same re-check pattern as
  P7's retry, release moved 2.2 -> 2.8 so P2's sprint phases keep
  their wall-clock offsets). (2) Web asset caching (#A):
  web/worker.js serveStatic now sets Cache-Control per file class
  -- game.wasm/game.js immutable 1y behind the Workers cache API
  (they change ~never); game.pck + index.html/game.html no-store
  must-revalidate (CI re-commits the pck on every content push);
  everything else 1h; + nosniff. Players stop re-pulling 38MB per
  visit; the pck still revalidates (hash-suffix scheme noted in a
  comment as the follow-up). (3) The day's fix list (all in this
  round): #1 loading screens -- root-level CanvasLayer overlay in
  GameManager survives change_scene (the old LoadingUI.instance
  lived inside hud_layer.tscn, the very scene being freed);
  #2/#6 UIPanel standard header (Title/Spacer/CloseButton) built
  in _ready and by set_title for header-less panels, Main gets
  EXPAND_FILL so ScrollContainer tab pages stop rendering 0px
  (Character tabs), close buttons everywhere; #3 touch HUD below
  panels (layer 24 -> 18 < MenuManager 20) AND set_panels_open
  input gate funneled from MenuManager._open_panel/_close_panel
  through InputManager (a hidden-but-enabled CanvasLayer still
  gets _input); #4 minimap bars = the toggle HBox was a direct
  child of the PanelContainer (7 buttons stretched screen-tall);
  re-parented under map_container + hud_layer.tscn rects
  de-overlapped (Minimap/QuickAccessBar/BuffBar); #5 jump wired on
  globe_player (ballistic hop, snap re-arms on fall-back-to-ground,
  anticheat stamped like the planar controller); #7 motion
  parallax -- streamer _spawn_trees (4-8 seeded trees/face,
  tangent-aligned) + world_playable checker-grass 256x256 + seeded
  rocks, all visual-only (snap_height_provider stays walk
  authority); #8 sky_sun.gd -- the sun is a pure function of the
  Concord epoch (fposmod day phase, ARC_TILT 28 deg, NIGHT 0.18 /
  DAY 1.15 energy, sun_direction() exposed for future shadows),
  built by world_playable + globe_world. Boot clean throughout.
  Verified: probe_world_scoping 7/7, underworld 42/42, lattice
  94/94, globe 23/23 (caught my TerrainGen.TILE_LIFT vs streamer
  TILE_LIFT misref -- the streamer owns the constant), touch
  17/17 xvfb, regression 52/0, lint 36/36. Lessons: (1) world ids
  are "main"/"underworld"/"moon" -- data/worlds/world_main.tres
  carries the FILE prefix only; scoping checks must compare the
  id, never the filename shape (caught by probe before commit);
  (2) a subworld zone in the shared ZoneManager is a loaded gun:
  every planar consumer (spawn, claim, entry, transition, respawn)
  must either filter or the coordinates lie -- filter ONCE in the
  data (world_id) and gate the four read paths;
  (3) xfail-in-headless is fine, but document WHY in the test
  header (viewport size) or the next agent re-hunts the ghost.
- [x] PLAYTEST ROUND 5 (2026-10-01, owner in-browser wasm round).
  Seven items. (1) "SPAWNED IN AN OCEAN": ROOT CAUSE was NOT the
  height law -- globe_terrain_streamer._load_patch displaced verts by
  the patch-LOCAL corner vector (center subtracted, ~5 km magnitude)
  instead of the GLOBE direction (v+center).normalized(), scattering
  every tile vertex as debris; only the water shell survived intact.
  LESSON: probe the GEOMETRY, not just the function -- the analytic
  law was green for rounds while the mesh was soup. Added a mesh-truth
  check to probe_terrain_planet (samples real patch verts vs law, 22
  checks now). (2+3) Z-STACK LAW documented in
  menu_manager._initialize_panels: HUD widgets 100 < chat 300 <
  expanded menu 350 < panels 500 < boot overlay (root CanvasLayer
  100); settings panel ADOPTS into MenuManager's layer at z 500 one
  frame after ready (its first cut never ran: a nested ternary read a
  /root/MenuManager path that does not exist AND an unguarded
  PlayerConfig read in _apply_current_settings aborted _ready before
  the block -- in headless probes the ternary was not even the first
  killer; explicit ifs + deferred adoption, verified by 3 new
  probe_round2_ui checks). Lookups go through HudLayer.
  _resolve_settings_panel (MenuManager instance fallback); hud_hotkeys
  routes via it (direct child lookup goes stale post-adoption).
  LESSON: a deferred re-parent invalidates every static get_node path
  at once -- give panels ONE dynamic resolver and wire all consumers
  through it. (4) Exit to Character Select in the in-game menu, wired
  through GameManager.CHARACTER_SELECT (loading overlay rides along).
  (5+6) LoadingUI rewritten as a full-screen dimmed backdrop + centered
  spinner ring; scene change now awaits TWO process_frames after
  show_loading so the overlay paints before the world freezes the
  frame, and _handle_playing_state shows it before the heavy world
  init. (7) Sun tracked too fast because the disc was parented to the
  WORLD (its _process produced a celestial bearing, but the node rode
  world space) -- at 100 m scale the world is 200x denser per frame,
  so the disc whipped; now globe_world parents SkySun under the PLAYER
  (celestial frame, adopt fallback in _build_player) and it rides
  floating-origin rebases. Verified: boot clean, terrain 22/22,
  globe_world 23/23, round2_ui 20/20, regression 58/58, lint 36/36,
  xvfb touch 17/17.
- [x] WORLD AT CANON SCALE (2026-10-01, owner: "I didn't see
  terrain last test"). ROOT CAUSE: the shipped game booted the 100 m
  PROTOTYPE globe (project.godot synmergia/world/planet_radius=100)
  while the terrain arc only exists at planet scale (terrain_on gated
  at > 2000 m) -- every probe passed because they PIN 20 km
  explicitly; the real game never did. The data layer already
  declared the truth (world_main.tres radius_m=20000); the project
  setting contradicted it. FIX: planet_radius=20000.0 (the .tres is
  the declaration; the setting must match), globe_world fallback
  updated, prototype-scale probes (probe_globe_world,
  probe_terrain_stream) PIN 100 explicitly with restore-to-20000 on
  exit, probe_planet_scale_20km already did. Also: the arena gateway
  now rides the walk law at its direction (fixed radius+1 was buried
  under the plaza at planet scale). LESSONS: (a) a project setting
  and a data declaration can silently disagree -- the probes pin the
  setting they test, so only a live boot catches the shipped value;
  (b) "probes green" means "the pinned scales are green", not "the
  game as booted is green". VERIFIED: terrain 21, globe 23, stream
  9, 20 km 25, climb 11, glider 10, regression 58/58 in chunks,
  lint 36/36, xvfb touch 17/17, boot clean.
- [x] PLAYTEST FOLLOW-UPS (2026-10-01): (1) SLIDE END LAW: a slide
  ends back into the RUN (not crouch) -- held sprint flows straight
  out of the slide; the crouch tap is now ONE chain: bail-while-
  sliding > engage-while-sprinting > toggle otherwise. (2) GLIDER
  LIVE ON THE GLOBE: the S12 machine was wired but two gaps --
  altitude measured against the static lift only, so terrain made
  every hill read as airborne (the wing auto-popped on a 9 m plaza;
  dbg-walk caught the body GLIDING at spawn). Altitude now measures
  against the WALK SURFACE law (provider), the same law everything
  else reads. Plus: manual deploy/stow (jump tap mid-fall/mid-glide,
  the primitive's grace window), dive pitch from camera look
  (7->16 m/s, the look stick IS the pitch stick). (3) ROUND-2
  REGRESSION CAUGHT: the sprint-override hook had swallowed the
  glider init + anticheat stamp inside _on_sprint_override --
  probe_glider (previously not in DEFAULT_SET) failed 'body carries
  a state machine'; _ready owns its chain again. LESSON: when a
  probe exists and starts failing after unrelated edits, that is
  the system talking -- add it to DEFAULT_SET (now 58 with
  probe_glider) instead of trusting old green runs. VERIFIED:
  glider 10, globe 23, terrain planet 21, 20 km 25, climb, lava-
  clean regression 57 + glider, lint 36/36, xvfb touch 17/17.
- [x] TERRAIN ARC V1 SHIPPED (2026-10-01, owner: "we should add
  terrain ... hills, valleys, mountains, plains, rivers, lakes ...
  then oceans ... the continent and a smaller island ... hook up the
  ferry"). WHAT SHIPPED:
  (1) TERRAIN HEIGHTFIELD: terrain_gen.gd v2 (RULESET terrain_v2) --
  trilinear value-noise ground law terrain_height(dir, seed), pure
  and deterministic. Bands: ocean floor -> shelf -> beach -> plains
  -> hills -> mountains (rare, mask-tuned) -> snowline ceiling at
  TERRAIN_MAX 42. A guaranteed-land STARTING CONTINENT (homeland
  dome, PLATEAU shape, 2.0 rad ~ 40 km, detail-noise-carved bays)
  with the spawn plaza flattened at SPAWN_HEIGHT (flat + clean of
  props via SPAWN_CLEAR_ANG). A volcanic ISLAND offshore (lat 60,
  lon 90, 240 m radius, ISLAND_PLATEAU 20 m) with an explicit MOAT
  channel (the ferry's crossing). A mountain LAKE bowl below the sea
  line. Per-seed sea level (SEA_LEVEL_MIN+SPAN).
  (2) BOULDERS: 1-2 per face (VARIETY LAW: universal), 3.5-6.5 m,
  PropCollider-carried (BLOCK + climbable), squat ellipsoids sunk
  1/3 radius, radial basis, decorative collar rocks whose walk-over
  caps the ground law already carries (no tunnel).
  (3) STREAMER: tile vertices displaced radially by the terrain law
  (dir-quantized cache -> no tile-border cracks); height-band vertex
  colors (seabed->sand->grass->forest->rock->snow, wet darkening
  below the waterline); props pose onto the displaced surface
  (radial, arc-exact, ROCKS EXCLUDE their own cap -- walk_height
  double-count lesson); underwater/tree-line gating (terrain only,
  prototype keeps S7 look). walk_surface_h()/terrain_h() = the ONE
  ground law the pad, snap provider, and mobility read.
  (4) GLOBE WORLD: _ready order streamer-BEFORE-player (spawn rides
  the terrain law); water shell SphereMesh at sea level (translucent,
  visual only -- the sea floor IS the terrain, one collision truth);
  _surface_lift = TILE_LIFT + terrain under the player (pad rides
  hills/valleys); player.ground_offset = STATIC lift only (terrain
  arrives via provider -- double-count lesson err=10m caught by
  probe); terrain_h_at() seam for the player's slope law.
  (5) GLOBE PLAYER MOBILITY: crouch TOGGLE (CRH/C, x0.5), SPRINT
  (SHIFT or touch auto-sprint via sprint_override signal, x1.55,
  needs stamina reserve), SLIDE (crouch while sprinting: fall-line
  momentum law -- accelerate on ground-law drop ahead, friction,
  steering blend, ends to crouch), steep-uphill terrain slow-down
  (reads TERRAIN ONLY via the seam -- walk-over caps are free
  ground; probe-caught 175 m/30 s loss when caps counted), mantle
  down-ray lands on the walk surface (provider top), is_glued = the
  snap equation (provider law at the body's direction), perch law:
  stepping off a >=0.55 m cap is AIRBORNE (no snap crutch).
  (6) FERRY: veh_island_ferry.tres (Gullwing Ferry, village docks ->
  waypoint_island_dock, 6/day, 0.75 h) + waypoint_island_dock.tres
  + zone_gull_island.tres (bare zone id -- NO underworld world_id;
  the S15.3 scoping lesson). FerryService.ensure_loaded() picks the
  route up from data automatically (schedule primitive shared).
  (7) PROBE: probe_terrain_planet.gd 21 checks (law bands, spawn
  glue, provider==law, water shell radius, boulder pipeline
  survive=attach audit, homeland solid-land) in DEFAULT_SET (now
  57). 20 km probe updated: surface expectations add the terrain law
  read (documented in-place; the re-land exact-gap identity was
  flat-pad-era, replaced by the glue + walk proofs).
  LESSONS: (a) icosa neighbor-face centers sit 0.955 rad from the
  spawn face -- a homeland dome smaller than that reads as "start
  area is an island" (fixed: plateau 2.0 rad); (b) Vector3 has NO
  .orthogonal() in GDScript -- build the axis from a hint cross;
  (c) slope law must read terrain, never walk-over caps; (d)
  double-counting terrain in ground_offset AND the provider floats
  the body exactly one terrain-height (probe err=10.00 m read it
  instantly). VERIFIED: probe_terrain_planet 21/21, determinism,
  terrain stream 9, globe 23, 20 km 25, climb 11, ocean 44, ferry,
  swim, regression 36/36 (57 tests), lint 36/36, xvfb touch 17/17.
- [x] GLOBE HUD + WEB TOUCH CONTROLS SHIPPED (2026-09-30, owner:
  "species and class work, we got in -- but there is no HUD, no
  mobile controls, no menus"). ROOT CAUSE (two independent gaps):
  (1) synmergia/world/shape="spherical" makes GameManager load
  globe_world.tscn, which was born as a movement PROBE scene and
  never received the HUD that world_playable.tscn embeds -- the
  screenshot's curved horizon + moons was the tell. (2)
  InputManager._detect_platform classed only Android/iOS as mobile,
  so a phone BROWSER got keyboard mode: no touch HUD, no stick, no
  buttons. FIXES: globe_world._install_hud() instantiates
  res://ui/hud/hud_layer.tscn (the same composition -- MenuManager,
  bars, combat log, minimap) and _setup_touch_hud() bridges the
  VirtualJoystick camera_look into a new
  GlobePlayer.orbit_camera(dx, dy) (yaw/pitch on the local tangent
  frame; pivot basis re-derived per physics frame so the old fixed
  north/east frame is the zero-look special case; probe asserts
  yaw 90 deg turns the view 90 deg). globe_player now reads
  InputManager.get_movement_input() (controller > touch stick >
  keyboard merge) instead of raw Input.get_vector, so the phone
  stick drives the globe walk. InputManager: web +
  DisplayServer.is_touchscreen_available() => mobile (PlayerConfig
  touch_controls still overrides). probe_globe_world extended to
  24 checks (HUD installed, MenuManager + CombatLog/Minimap/
  ActionBar/QuickAccessBar present, orbit_camera turns the view,
  TOUCH-mode stick drives merged movement input). Lesson: every
  playable scene carries the HUD composition; web touch-capable
  hardware is mobile.
- [x] S14.5 FerryService + the One-Law Cleanup SHIPPED (2026-09-30,
  owner: "S14.5 rides the same schedule math and a water cleanup
  round before we tackle wasm"). (1) THE PRIMITIVE:
  core/frame/srv/ferry_schedule.gd -- departure_hours /
  next_departure / crossing_in_progress, closed form off the
  Concord epoch, co-located test (11 checks). THE CLEANUP: the
  almanac's private _next_departure is DELETED; the sailing page
  calls the same primitive the dock reads -- chart-dock
  disagreement is now structurally impossible (one derivation,
  two readers, the moon-page law applied to boats). (2) THE
  SERVICE: FerryService autoload (NO class_name, after
  OceanService): board_ferry free, boarding-window only; empty
  boat stays tied; arrival records the wake + per-rider
  ZONE_CHANGED toast; skiff = 2.5x + ticket via remove_gold (the
  gold sink) + THE WAKE LAW (zero recorded rides = refused --
  first crossings are never skippable); wake ledger one
  DictStore key per player (WaypointService idiom), reboot-safe;
  wake_is_known(3) staged for the dock-warp tier. Manifest =
  session truth (logout misses the boat); emptied dock releases
  the sailing slot; boat at sea sails on; 1 s driver timer
  (SignService idiom); abandon_riding is the logout seam (no
  roster-left signal exists yet). v0 path contract: positions
  are the ports, ride time honest, deck motion S14.6+. (3)
  probe_ferry.gd (25 checks, DEFAULT_SET) caught: the cast-off
  boundary (crossing_in_progress claimed the boat at sea AT the
  departure instant, swallowing the boarding window -- the
  instant belongs to boarding, crossing starts strictly after)
  and the phantom sailing (board then desert = a sailing slot
  ticking at an empty dock). Also caught three wrong
  hand-derivations in my own schedule test -- the primitive was
  right every time; the test now verifies one clock read against
  pinned epochs. Regression 49/0 (47 + the two new ferry suites:
  test_ferry_schedule 11 checks, probe_ferry 25), lint 36/36.
  Lessons: (1)
  boundary ownership must be DECLARED (who owns the instant:
  boarding or sea) -- floats make "at the instant" a real
  question, not a pedantic one; (2) delete the private copy when
  you promote math to a primitive -- a kept copy is a future
  disagreement; (3) claims need release paths (a stamped slot
  with nobody left to sail it is a leak the state machine won't
  catch). Next: wasm preview triage (the game, playable), then
  S14.6 water mounts + ride motion; owner has a GLB-on-Colab
  side quest after.
- [x] S14.2 the Swim Class + S14.3 Aquatic Anticheat + S14.4 the First
  Breather Gear + the Sailing Almanac Page SHIPPED (2026-09-29,
  owner: "first the sailing Almanac, then let's hit S14.3
  (anticheat aquatic limits + dive tickets -- currents exempted as
  server truth) followed by S14.4 (the first breather gear)").
  (1) SWIM CLASS (S14.2, committed 26be90a): SwimState frame
  primitive (the glider's below-water twin: DRY/WADING/
  SURFACE_SWIM/SUBMERGED/SQUEEZE/CRUSH; 45 s breath; pressure
  accrues only when the volume taxes; rock sentinel -1 reads DRY;
  set_breath_capacity for gear) + movement_swim.tres (AQUATIC=3,
  swim 3.4, no jump) + OceanService.tick_swimmer returning the
  whole water truth per tick. test_swim_state (25) + probe_swim
  (20) in DEFAULT_SET. (2) AQUATIC ANTICHEAT (S14.3): the validator
  now judges a swimming body by its SWIM maxima
  (set_aquatic_limits, speeds x the same multipliers, stamped into
  validate_movement as an override) -- land maxima never apply
  underwater. CURRENTS ARE SERVER TRUTH: set_current_drift stamps
  the OceanVolume's declared vector and _legal_under_current
  forgives displacement ALONG it only -- the perpendicular
  component (the swimmer's own effort) stays hard-checked, and
  parallel <= 0 (upstream) gets no forgiveness at all; a zero
  current erases the stamp. DIVE TICKETS mirror the launch tickets
  (ceiling 30 m/s, 3 s, prune-on-read): they forgive ONLY the
  downward plunge past the swim terminal (the boat-fall entry);
  horizontal/absurd stay flagged. unregister_player clears all
  three books. test_anticheat_limits +4 sections (10-13). (3)
  BREATHER GEAR (S14.4): Item gains AccessoryType.BREATHER +
  breath_multiplier/squeeze_grace_m exports; two .tres pieces
  (Hollow Reed x2/+2 m, Lungshell x4/+8 m, NECKLACE slot) +
  OceanService.breather_for resolving through InventoryService to
  {mult, grace_m} (unbreathered default when anything is missing).
  ORTHOGONAL LAW kept: gear owns air (multiplier + grace), the
  MovementProfile owns speed -- a breather never swims faster.
  The primitive now applies the grace itself (squeeze_eff), so
  band_for and tick state can never disagree about where squeeze
  starts; CRUSH never moves. (4) SAILING PAGE (sec 9 ferry honesty
  law): VehicleData gains ferries_per_day/first_departure_hour/
  crossing_hours (closed-form schedule off the Concord epoch -- no
  timetable table stored, chart and dock cannot disagree, same law
  as the moon page); veh_haven_ferry declares 8 cast-offs/day,
  first at 06:00, 30-min crossing; SkyAlmanacUI grows the sailing
  page (route, crossing minutes, next cast-off with the departing-
  now window, the wake law line) and _sail_ferries reads the
  vehicle declarations directly (the almanac is a chart, not a
  service). Panel grew 520 -> 620 tall. probe_ocean 27 -> 44
  checks (H breather + I schedule + J page-render via the panel
  driver). Full regression 47 -> 51/0, lint 36/36. Lessons this
  leg: (1) the band and the state MUST share one squeeze-line
  derivation -- the service passing band_with_grace but raw state
  line made a breathered body at 51 m SQUEEZE by state and
  SUBMERGED by band (caught by probe section H's service-path
  drive-by); (2) when a test passes TWO representations of one
  thing (deepened line AND grace), it is asserting the bug --
  caller-applied grace was the old contract; the primitive owns
  it now; (3) write_file batches can silently no-op on a busy
  workspace -- ls the files before trusting a green tool result.
  which is also the mystery hook the lore's been promising"):
  SkyAlmanacUI grows the moon page (between the sky rows and the
  Chronicle): where the pale stone stands (orbit_position, km out
  + period), how the sky aligns (window_favorability, colored by
  regime: aligns/leans/against), the next favorable window
  (next_transfer_window at the Gate's 0.25 threshold, Day N + days
  out), and the moon's declaration lore as the mystery line. THE
  CHART-AND-STONE LAW: the page reads the same closed-form math on
  the same canonical epoch as the Moon Gate's window law -- one
  derivation, two readers, they can never disagree. Probe section
  J asserts it (same registry, same epoch, same favorability, same
  next window to 1e-7, periodic position) through the panel's math
  seam -- headless-safe. 87 -> 93 checks. Verification notes: the
  render path was exercised with a standalone driver (4 rows live,
  lore included; refresh twice shows 12 unique ids 0 shared -- the
  old rows free next frame, no accumulation leak). Design law for
  the ledger: when two surfaces read one law, the TEST must pin
  their AGREEMENT, not just each one's correctness -- a drift
  between chart and stone would be a silent lore break.
- [x] S14.1 Water-Is-Data + Moon Lore Lock SHIPPED (2026-09-29,
  owner: "moon lore options A and B make sense -- the world
  builders, the ancients, the devs ... we can def dev the ocean on
  the moon, let's fill in a crater"): (1) LORE LOCK -- the Watched
  Stone adopted: the moon is where the world works on itself, the
  builders come and go as the sky aligns (faith-shaped hole in a
  religion-free world, prd-psy-safe); world_moon.tres lore + gate
  arrival line carry it; the dev hatch is permanent and never
  lore-gated; the address observatory (star cells endgame) is
  reserved. (2) WATER AS DATA -- OceanVolume schema +
  OceanService autoload (NO class_name) + two volumes: the Haven
  Shelf (main, 60 m, ferry-lane currents) and the Builder's Pool
  (the moon crater: 24 m, no current, no pressure -- tame by
  design, the dev workshop's test water where S14.2 swims first).
  The law set: sign discipline (negative above the waterline,
  ThermalService mirror); pressure depth is the WATER ABOVE the
  body -- the rock does not reduce depth, it REFUSES (inside the
  stone reads the -1 no-water sentinel); two floor models on one
  schema (radial world-shell ready for a true globe scene, local
  rock-plane for playable dishes); breather grace DEEPENS the
  squeeze line and CRUSH never moves; specificity rule (tighter
  horizontal reach wins overlapping claims). probe_ocean.gd (27
  checks, in DEFAULT_SET). The probe EARNED its keep: caught a
  BACKWARDS squeeze formula (more grace made squeeze start
  shallower), a pressure-depth/column conflation, an
  overlapping-claim resolution bug, and a str_replace line-glue
  that commented out the whole clamp block -- all before any
  swimmer existed. Lessons: (1) define WHICH quantity the clamp
  caps before writing min/max -- pressure depth (water above) and
  floor column (water below) are DIFFERENT quantities; (2) overlap
  policy: separate volumes in XZ when you can, specificity tiebreak
  when you cannot; (3) grep the seams after every str_replace that
  joins a return line to a comment block (gotcha #7, twice now).
- [x] The Rest and the Horizon (2026-09-29, owner: "calibration
  state and origin from 3 of the intersecting isos ... we have to
  have an outer limit in synmergia, like irl. If mine doesn't work,
  what's your idea?"): BOTH landed. THE REST declared on the
  universe tier (origin_unix = 1789861412 -- THE FIRST COMMIT, the
  universe began when its code did; rest_frame =
  "nsc9:trilateral:0+1+2", three facilities at balanced rest --
  IRL has no center, ours is wound). THE HORIZON derived in
  world_registry: cosmic_age_s (clamped) and observable_radius_m =
  age * c -- the light cone AS the outer limit (the edge exists
  because light has only had time to travel so far; grows at
  exactly c; nothing observable before the bang). Balance law:
  centers are CHOSEN, limits are DISCOVERED (Rest without Horizon
  = prison; Horizon without Rest = drift). probe_calibration grew
  20 -> 28 checks (age IS now-minus-bang, horizon growth rate,
  pre-bang clamp, trilateral validity, origin lives only on the
  universe tier; lessons: date arithmetic bit me twice -- unix
  1789861412 = 2026-09-19/20 not July, and horizon growth needs a
  RELATIVE tolerance, absolute meters are below float64 resolution
  at 2e15). labs sec 9 written. Regression 41/0, lint 36/36.
- [x] Cosmic constants + the globe typewriter (2026-09-29, owner:
  "yes use the constants ... fold the surface area and intersect our
  isohedrons like those old globe typewriters ... dimensions in
  code"): CalibrationTier gained light_speed_m_s (SI exact
  299792458.0) + expansion_rate_h0_km_s_mpc (Planck 2018 67.4) --
  DECLARED on the universe tier only (0.0 = undeclared elsewhere;
  premature precision is the only evil, sec 7). probe_calibration
  grew 16 -> 20 checks: constants exact, fast tiers make no cosmic
  claim, and light-lag honesty measured (90 km orbit / c ~ 0.3 ms
  -- the system tier may ignore lag today, proven not assumed).
  prd-industry-labs.md sec 8: the owner's sketch recorded as the X2
  MECHANISM -- icosahedron = the sphere folded flat (Dymaxion net),
  NSC-9 = the typewriter carriage (axis/sequence bits are the
  dimensions folded into an integer), assimilation = assigning a
  cell, intersection = comparing prefixes, telescopes = carriage
  moves not raycasts, H0 = the slow stretch of the paper under the
  type. Reserved, not built. Regression 41/0, lint 36/36.
- [x] prd-industry-labs.md sec 7 "On precision" (2026-09-29, owner
  riff: "Knuth heavy ... a physics frame is based on precision"):
  the reconciliation -- Knuth's evil is PREMATURE cost, not
  precision; the CalibrationTier IS the schedule of when each
  scale's precision becomes load-bearing. Spent where it compounds
  (one epoch law, O(1) skies), withheld where it doesn't (circular
  orbits, named heuristics, the not-build list), budgeted in data
  so recalibration never recompiles the universe. The allocation of
  precision is the architecture.
- [x] CalibrationTier substrate SHIPPED (2026-09-29, owner: "the
  universe should align time, space, state irl; Linux epoch is/and
  should be aligned -- that's the first thing I'd do in a physics
  engine; .tres/schema it for the OSS frame"): the alignment
  substrate as DATA. core/schemas/calibration_tier.gd (TierScale
  LOCAL/UNIVERSE, AdvanceMode TICK/EVALUATE, epoch_source, tick_hz,
  tick_horizon_s, eval_period_s, max_drift_s accuracy contract,
  anchor -- space spine, derives_state -- derive-vs-fold law) +
  data/calibration/*.tres x5: local 60 Hz tick (0.05 s drift
  budget), world 2 Hz tick, system EVALUATE (barycenter:main, the
  tier the lattice already lives on), galaxy EVALUATE hourly
  (nsc9:0 anchor, X2 reservation), universe folds the ledger daily
  (X3). DataService consumes (load_calibration/get_calibration_tier;
  Resource-typed getter per the GuardData lesson -- new class_name
  misses the cache until an import pass). probe_calibration.gd (16
  checks, in DEFAULT_SET now): THE EPOCH LAW measured live --
  Concord epoch IS unix/86400 and the sky calendar is floor(unix/
  86400); mode law (fast tick / slow evaluate); drift monotone per
  mode; schedulers served by period_s(); anchors name the spine;
  pure physics derives, the universe folds. Regression 41/0, lint
  36/36.
- [x] prd-industry-labs.md SHIPPED (2026-09-29, owner: "let's call
  bluff on the game industry"): the industry call doc. T1-T7
  theorems, each citing shipped code -- seed derivation (T1),
  closed-form time (T2), NSC-9 GEOMETRIC ASSIMILATION AND ADDRESSING
  (T3, the owner's idea mapped onto what the frame already runs:
  nsc9.gd bit-packed cells + spatial_fragmenter + nsc9_bridge -- the
  address IS the identity, adjacency is arithmetic), T3 content-hash
  state (T4), cadence valves (T5: 5-min coalesce + horcrux), laws
  not triggers (T6), nested invocations (T7: reality state is
  callable, side-effect free). Extension ladder: X1 heliocentric
  clock (planets = one more nesting level; seasons =
  parent_sky_direction), X2 address-space galaxy (stars exist
  because their NSC-9 address says so -- derive_seed on
  "star:<address>"), X3 universe slow ticks (civilization
  fast-forward = closed-form evaluation at large epoch + REPLAYING
  THE LEDGER of chosen events through deterministic folds -- the
  Concord Chronicle at century scale; drift never accumulates
  because there is no integration), X4 the epoch valve.
  Not-build list: no N-body, no streamed space mesh, no tick for
  things that are functions. Falsifiable claims C1-C7 with the
  probe/test that breaks each. Citations verified before ship
  (COALESCE_WINDOW_MS, state_tree/t3 + tests, nsc9 bridge tests).
- [x] S16.4 world physics SHIPPED (2026-09-29, owner: "we aren't
  building stubs or simulations"): per-world physics as DECLARATION.
  movement_lunar.tres (Movement Design System profile: 6 m/s^2
  gravity, 4.6 m/s jump -- the 1.75 m hop, slow 14 m/s terminal
  fall, floaty accel; consumed via DataService.get_movement_profile).
  globe_player.bind_to_world(id) adopts WorldData.gravity_force (the
  moon's 6 is a law of that globe, not a tweak; only gravity --
  profile/species layers stay authoritative for feel); the vacuum
  glider gate runs INSIDE _physics_process: no atmosphere = the wing
  closes the same frame, the body falls honestly (globe_player:
  world_id + _world_allows_gliding, allows_gliding is the law).
  Earthrise as closed-form theorem (world_registry): spin_period_days
  on WorldData (0 = tidal lock, the synchronous theorem -- sigma
  follows a, home hangs over ONE meridian forever, where your base
  lands decides whether Earth ever rises); parent_sky_direction =
  the synodic angle a - sigma (unit vector, body-fixed; direction
  convention: sub-parent meridian at a-sigma+PI); parent_beat_period
  = |1/Po - 1/Ps|^-1 (spun moon: home rises every 24 d);
  parent_visible_from (flat-horizon heuristic, visuals use the exact
  vector). entities/parent_sky.gd: the home world's disc at EXACT
  angular size (2*asin(r_parent/r_orbit) ~= 26 degrees in our
  lattice -- real Luna's Earth gets 2; our universe is
  bigger-hearted), positioned by the closed-form vector every frame
  on the Concord epoch, constant size/brightness (circular orbit,
  constant distance -- the sky keeps its promise). Probe section H:
  49 -> 65 checks (real one-frame physics step: vacuum closes the
  wing, 6 m/s^2 pull; theorems; disc hung). Regression 40/0, lint
  36/36. Next: S16.5 transfer windows + almanac moon page (the
  mystery shell), S16.6 moon hosts dev/probes (the dev flip).
- [x] S16.3 Moon Gate SHIPPED (2026-09-29): the AncientDoor pattern
  between worlds (prd-multiworld.md sec 3). ScopeService gained world
  scopes -- "world:<id>" joins globe|bout|spectate on the SAME seam
  (reparent + scope record; NO planar flip, every world is a globe):
  enter_world_scope/exit_to_world + world_of/is_off_world; the entry
  law is enforced IN the service (registry is_enterable gates every
  swap, force=true is the S16.6 dev hatch), a transit without a
  destination root refuses rather than strand the player, escape
  capture only on the first hop out of main. entities/moon_gate.gd:
  monolith + lunar glow strip, states dark/dim-pulse/bright-pulse
  (unknown/offline/online), try_interact {ok,reason,message}
  contract, prompts; the underworld's gate refuses as if the place
  is not on any chart; the moon's gate is the SEALED MYSTERY SHELL
  (DEV_ONLY) until the dev flip makes the moon real. Placed in
  world_playable (-16,0,10; loaded by path, GuardData lesson) +
  _try_interact dispatch (moon_gates group, nearest within 4 m, same
  toast pipeline as doors/stones). probe_world_lattice section G:
  34 -> 49 checks. Regression 40/0, lint 36/36. Next: S16.4
  world_moon minimal globe (lunar movement profile, no-atmosphere
  glider rule, earthrise).
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
- [x] S16.5 world-state engine V1 SHIPPED (2026-10-08, owner:
  "V1 slice: World-state engine first... Best to solidify world
  state"; synthetics are the agent species, species-agnostic bodies).
  The STATE half of the clock thesis (S16.1 shipped geometry; this
  ships state): WorldState frame primitive
  (core/frame/srv/world_state.gd, no autoload/class_name) -- world
  deltas under /world/w/<id>/state/<key> in the SAME StateTree every
  other service writes (one book, no side doors). GEOMETRY vs STATE
  law: WorldRegistry owns derived geometry (seed functions, nothing
  stored players did not choose); WorldState owns the deltas players
  and agents cause (harvested nodes, opened gates) -- each write
  carries PROVENANCE {payload, actor, epoch}; erasure is itself a
  delta ({cleared: true, actor, epoch}) so an audited world answers
  who cleared what. Hierarchical keys ("harvest/iron_1") nest as
  T3 paths. AGENT-CITIZEN LAW: no species or role special-casing --
  a synthetic rides the same write_entity path as a human, and the
  probe proves identical projection + readback + provenance shape.
  WorldStateProjection grew the world dimension ADDITIVELY (no AOI
  rewrite): identity nodes stamp world_id (ZoneData.world_id, empty
  = main), _zone_worlds maps zone->world, snapshot_for_world unions
  a world's zones + its deltas (the underworld resync: main-globe
  hordes never cross the namespace), active_worlds() diagnostics.
  probe_world_state 17 checks in DEFAULT_SET (incl. the real-zone
  union branch: ZoneManager boots empty in script mode -- load_zones
  then stamp -- and the zone half of the no-bleed proof); regression
  73/0; lint EXIT 1 but pre-existing on main (status_effect/skill/entity
  cyclic preloads + durable_store class_name-first), verified via
  stash on clean HEAD. Lesson: T3 normalizes paths (no leading
  slash) and get_state returns {type, entity_id, payload} -- a
  provenance envelope must BE the payload, not wrap it twice.
- [x] S16.5.2 live world deltas + world-scoped resync SHIPPED
  (2026-10-08). FIRST LIVE WRITER: AncientDoor._open/_reseal record
  gates/<door> deltas through the one chain -- provenance actor=door,
  epoch=SignService.sky_epoch_days() (the S16.2 clock, not wall
  time); re-seal is the auditable cleared record. probe_ancient_loop
  grew the delta assertion (open loop -> gates/AncientDoor reads
  back with the right day + actor; 13 OKs, exit 0). WORLD-SCOPED
  RESYNC: TickService.send_full_scope_sync used to ship the ENTIRE
  world scope to any requesting client; now it resolves the player's
  world via ScopeService.world_of and sends
  WorldStateProjection.snapshot_for_world(wid) -- a moon client's
  resync never pulls main-globe horde state; unscoped fallback kept
  for deep script mode. probe_world_scoping/probe_world_lattice/
  probe_world_state all exit 0.
- [x] S16.5.3 HarvestService SHIPPED (2026-10-08, the live-delta
  thread complete). Gatherable nodes: register_node (data truth --
  unknown item refused, world resolved from ZoneData), harvest gate
  chain {ok, message} (no purse refused -- the world drops nothing
  into the void; QoS rate limit; grant rides InventoryService
  add_item), deplete + world delta harvest/<node_id> with provenance
  (actor=harvester, epoch=sky clock), timed respawn -> ERASE delta
  (auditable cleared record, actor=world). Agent-citizen law proven
  end to end: a synthetic harvests the SAME node through the SAME
  chain -- identical answer shape, purse grant, delta provenance.
  probe_harvest 16 checks in DEFAULT_SET, exit 0. FOUND + FIXED a
  real production bug: InventoryComponent._try_stack_item read
  weight_per_unit (not an Item property -- the export is weight),
  so every SECOND add of a stackable item crashed and the caller
  got a silent refusal; test_ground_loot 44/0 + probe_character_panel
  14/0 after the fix. Bag quirk noted: add_item quantity is only
  honored via stacking (a non-stacked add grants 1) -- inventory-
  layer wart for a future pass.
- [x] S16.6 AGENT LAW reframed + PRD skeleton SHIPPED (2026-10-08,
  owner directive). THE REFRAME: agent law is NOT agent
  special-casing -- it is a BEHAVIORAL INTEGRITY LAYER over
  AnticheatService for EVERY account (humans cheat; species is not
  the threat model). Detector classes: economy (dup patterns,
  harvest cadence, trade asymmetry), input humanity (entropy --
  scripted input is too clean), session shape (sequences no human
  walk produces). THE A11Y ADVANTAGE: the a11y rig already gives
  the server a clean SEMANTIC action stream -- typed, attributable
  events -- so cheater tooling must mimic it perfectly or betray
  itself; the a11y law doubles as the integrity law without
  degrading the a11y experience. Synthetics are ACCOUNTS through
  the lawful login chain; AnticheatService.register_player's
  is_agent flag tunes (no unearned grace), never exempts. PRD:
  labs/prd-agent-law.md. Build order: synthetic accounts ->
  semantic action ledger -> measured detectors -> tribunal riding
  the existing flag/ban spine.
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
  built into globe_world (dedupe in-volume, re-arm on exit, party
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
  are degenerate for physics import. globe_world.gd: planet-bound
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
  `synmergia/world/planet_radius` read by globe_world.gd; SHELL_RADIUS
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
  GlobeWorld flow, xvfb pixel-verified 6 stages, radial err
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
  gravity prototype (globe_player.gd + globe_world.tscn/.gd,
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
  zones exist.- [x] S14.7 Sundered Sea content pass SHIPPED 2026-10-10 (NOT the
  Round-41 riding slice that shares the name -- that S14.7 slot above
  is the mount-acquisition pass). The content pass turned the river
  fork-under-island seam into a destination: a carved strait where the
  ferry moat law (ISLAND_MOAT_OUTER) and the offshore shelf meet, so
  Sundered Sea reads as a PLACE, not a gap. All four scope legs
  landed:
  (1) terrain_gen: one SunderedStraits sculpt (two headlands pinching
  the moat ring into a channel + a wreck shoal law site),
  RULESET_VERSION stays terrain_v3 (additive; the v3 bit-identity
  contract held -- test_terrain_determinism PASS after the edits).
  (2) The backend seam landed FIRST: backend_sundered.gd (NEW) ships
  the authored site law (strait center, headlands, wreck shoal,
  ferry line) through install_terrain_backend() with an EXACT
  radial/chart round-trip (sinc correction on _chart, r=|x,y|), so
  authored content no longer grows the analytic law forever.
  probe_terrain_backend PASS.
  (3) Hydrology: ESTUARY_WIDEN 1.8 -- sea-terminating river mouths
  now widen their capsule radius quadratically toward the mouth at
  2 (moisture ripple already live).
  (4) Content staged DATA ONLY (backend-seam-first policy -- no code
  till the site renders): zone_sundered_sea.tres, npc_ferryman_sundered.tres,
  npc_salvor_wreck.tres, quest_shoal_freight.tres.
  Verification: probe_sundered_sea 13/13 PASS (site law, strait
  geometry on the chart, headland shoulders, shoal crest +4.07 m
  above the moat floor, ferry line clearance, channel half-width,
  round-trip), probe_terrain_planet, probe_terrain_stream,
  probe_terrain_climate, probe_ancient_loop all PASS. Both probes
  + climate are in the runner DEFAULT_SET.
- [x] Islands suite: ~30 bare-autoload script-mode compile notes
  CONVERTED 2026-10-10 (batched runtime-lookup pass). Root cause:
  --script-mode runs parse BEFORE autoloads exist, so any bare
  `X.y` reference to an autoload global fails to COMPILE (not just
  resolve). The conversion law (mirrors kill_rewards.gd,
  inventory_component._resolve_service, and the QoSService\n  singleton idiom): a per-file static-ish helper `_resolver() ->
  Node` reads `Engine.get_main_loop() as SceneTree` and
  `root.get_node_or_null(NodePath("Name"))` -- null outside a live
  tree, the bare identifier nowhere. Scope crossed three layers:
  (1) the entity core chain (entity.gd damage/heal events,
 aura/combat/inventory/health components, skill.gd hit_resolved,
  vendor/dialog/vault/security(chat+admin) services, targeting
  manager + its action map),
  (2) the island UI panels (bank, shop, inventory, character,
  quick-access, minimap, world-map, target-frame, settings, mount,
  dialog, quest, skill-academy, title, voting, admin dashboard +
  toolbar, menu manager, main menu, chat UI, social party/guild/
  friends/trade/faction/transfer, report dialog, targeting tooltip,
  cooldown indicator),
  (3) the UIPanel base + hud_layer + player_controller autoload
  touch-points (anticheat stamp, input, lock, follow, looting,
  dialog, notifications, loot collect/drop, respawn, zones,
  gateways, self-rez, hub emit).
  Two compile-law ripples fixed along the way: class_name must
  appear BEFORE any func in a class body (v4.7 pride) so the
  batch-insert helper blocks were moved below the header consts
  (13 files), and typed-inference on dynamic lookups
  (`var x := resolver().y`) needed explicit types (bank_ui cost
  Dictionary, chat_service player arrays, minimap/quest progress,
  player_controller movement Vector3 -- forward * input.y + right * input.x is
  Vector3, don't "fix" it to Vector2).
  ChatService/chat_ui got enum-import-via-preload const (`Channel`
  read from the script resource, not the global)
  and AdminCommands / ReportType / TitleService the same way.
  Constants that ate the runtime pull (MAX_MESSAGE_LENGTH +
  MAX_HISTORY_PER_CHANNEL) became lazy vars initialized in _ready
  (GameConfig fallbacks when absent); the parse-time const read of
  them stayed out.
  Verification: test_islands 19/19 ZERO identifier errors,
  probe_round2_ui, probe_character_panel, probe_riding,
  test_combat_stack_live, test_anticheat_limits,
  test_movement_profiles, test_hitbox_profiles, test_data_naming_lint,
  test_a11y_service, probe_startup_flow, probe_ferry,
  probe_water_mounts, probe_glider, probe_playtest_r12,
  probe_bout_flow all PASS (nothing behind the islands pane
  regressed).
- [ ] WebInputBridge browser e2e once a full web export lands.
- [x] Harness LOD slice (streamer draw-call cut): TREE MULTI-MESH
  BATCHING in globe_terrain_streamer._spawn_trees. The law: a tree
  on the BASE-level face is a real Node3D (its trunk still mounts
  PropCollider.attach_trunk -- NEAR faces are walkable). A tree on a
  DEMOTED face (far/horizon) is pure detail: the SAME deterministic
  scatter (same seed acc, same rng draws, same biome gates) is
  batched into two MultiMeshInstances (BatchedTrunks: unit cylinder
  scaled per-instance by trunk height; BatchedCanopies: unit sphere
  scaled by crown), cutting up to 2xN draw calls per far face to
  exactly 2. Far trunks carry NO collider (the horizon can't be
  walked to; the collider law re-arms for free when the face
  promotes and re-spawns per-tree). Poses are identical between
  modes: the batch path computes the same radial placement +
  radial-up Basis the per-tree path does, then composes
  tree-pose x trunk-local/canopy-local. Face seed stream UNCHANGED
  (all rng draws happen in the same order both paths), so the
  deterministic content contract (S7 + the v3 bit-identity claims
  in terrain_gen) never notices the render path.
  Verification: probe_terrain_stream (4-patch steady state +
  continent walk + rock audit), test_terrain_determinism,
  probe_planet_scale_20km, probe_terrain_planet (shore fan),
  probe_sundered_sea, probe_globe_world, test_world_shape,
  test_world_chunks, probe_terrain_backend all PASS.
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
- [x] Play-test round 6 (9 items, web client + shell + world): (1) LoadingUI
  full-screen again -- UIPanel._ready's missing-Panel safety net auto-built
  its centered 400x500 PanelContainer inside the boot overlay (built with
  LUI.new(), no scene Panel); _setup_ui now frees any stray Panel before
  raising the backdrop. (2) web/index.html wires onProgress into BOTH the
  Engine config and startGame options (some exports read the config-level
  key -- the loader showed no percent) + a MB readout. (3) Expanded menu
  adopts into MenuManager's CanvasLayer 20 (settings-panel pattern): chat
  lives on layer 20, MainMenuBar on layer 10 -- CanvasLayer order beats
  z_index, so the round-5 z=350 could never cover chat. (4) Spawn sea
  guard: boot height < sea line now fails LOUD (error + lifted boot) and
  one always-on boot log prints walk surface vs sea line ("boot at lat 0.0
  lon 0.0, walk surface 9.0 m (sea line 6.0 m)"); plaza law was verified
  correct (SPAWN_HEIGHT 9 > max sea 7) so a reported ocean spawn would
  now be diagnosable from the log alone. (5) CharacterPanel tabs populate:
  refresh_inventory actually fills the grid now (was a pass stub),
  _refresh_equipment_display paints equipped names (was pass), _on_open
  self-resolves character data + refreshes all tabs, player-id resolution
  falls back through InventoryService -> local player component; index-
  zipped raw slot array (get_all_items skips nulls -> misaligned grid).
  (6) Splash: ONE Start button (old Account flow: login/register/guest ->
  lobby -> play); Play button + its parallel direct flow deleted, 7
  journey/driver tests rewired through the real flow (Start -> guest ->
  create). (7) UIPanel viewport guard: _clamp_panel_to_viewport() clamps
  panel minimum size to 92% viewport at ready + every open (settings
  700x550 bled off phones). (8) Mobile scale: UIStyles.get_text_scale()
  returns 1.3 on web/mobile touch devices (was hardcoded 1.0; HUD widgets
  already multiply by it; canvas_items stretch keeps fonts fixed unless
  scaled). (9) Minimap: layer-toggle row had NEGATIVE height
  (BOTTOM_WIDE + only offset_bottom=-2 on a zero-size control) -> pinned
  20px strip; added the missing MapButton emitting map_button_pressed
  (hud_layer connected that signal since round 2 -- it never existed, a
  silent has_signal no-op) -> WorldMap opens via M or the button.
  Verified: lint 36, regression 56/56 (3 chunks), probe_round2_ui 20/20,
  probe_globe_world 23, probe_terrain_planet 22, play_driver (planar)
  clean, test_splash_to_play 17/17 through the NEW flow, touch/click
  probes exit 0. Known pre-existing (failed identically at HEAD in a
  clean worktree, NOT round-6 regressions): test_ui_alive 13/17
  (panels don't open via hotkeys in the xvfb harness), the world-content
  legs of test_interaction_pipeline (NPC/loot checks; journey itself now
  passes 4/10 vs 0/10 at HEAD) and play_full_flow leg1 card picks
  (rewired flow reaches select + state cleanly; card signals don't land
  in the harness). Suspect the shared cause is the harnesses' input
  dispatch, not the panels; filed for round 7.
- [x] Play-test round 7 (4 items, Android portrait web client):
  (1) Boot loader rendered small in the upper-left: LoadingUI is a
  root Control under a CanvasLayer; set_anchors_preset(PRESET_FULL_RECT)
  PRESERVES the node's current rect, and on the boot path that rect is
  0x0 -- anchors froze correct while offsets stayed (0,0,-1280,-1280),
  collapsing the overlay to 0x0 (spinner drew at its content size,
  169x222, top-left). _setup_ui now assigns anchors 0/0/1/1 + all-zero
  offsets + GROW_DIRECTION_BOTH explicitly on overlay and backdrop.
  New probe tests/probe_boot_loader_rect.gd reproduces the exact boot
  path (CanvasLayer 100 + LUI.new() + show_loading): 4/4 (overlay/
  backdrop/center all 1280x1280, no stray auto Panel). Law: PRESET_*
  on a zero rect must be followed by explicit offsets.
  (2) Settings panel obeyed the vertical clamp but hung off the
  horizontal: _clamp_panel_to_viewport shrank custom_minimum_size, but
  PRESET_CENTER had frozen the OFFSETS at the original size, so the box
  kept its old displacement. After clamping, center-anchored panels
  (all anchors ~0.5) re-run set_anchors_and_offsets_preset(
  PRESET_CENTER) so offsets recompute from the new min-size; hand-
  placed panels untouched. probe_round2_ui 20/20.
  (3) Character/eq tabs blank on the globe: the globe had NO inventory
  loop at all. globe_player now builds an InventoryComponent in _ready
  (deferred 0.1 s SceneTree timer -- NOTE: root_node.create_timer does
  not exist, Window is not a SceneTree; resolve via Engine.get_main_loop
  + cast), stamps entity_id (selected character id, else globe_player_1)
  and registers with InventoryService; globe_world stamps the id before
  spawn and emits player_entered_world via new _notify_world_entry()
  after begin_loop() (world_playable ~line 175 was the only emitter, so
  StarterKitService never granted on the globe; GameManager dedupes per
  boot). character_panel._resolve_inventory read property "inventory"
  (real property: inventory_component) + bag-child fallback. lobby.
  _blob_to_character_data now hydrates species_data/class_data like
  character_select does (get_stats() lazily self-heals class_data but
  species stat modifiers were silently skipped when null).
  (4) Ocean spawn: CharacterData.spawn_position (0,1,0) pole theory
  DISPROVED -- zero consumers (enemy AI has its own _spawn_position);
  the globe boot uses its equator plaza consts and the round-6 sea
  guard holds. Real hazard found + fixed: RespawnService.
  _get_default_respawn_position returned PLANAR zone coords, which on a
  sphere decode to arbitrary ocean/planet-interior points; it now
  detects globe bodies (has_method planet_up) and respawns ON the walk
  surface at the body's own direction using the exact resting law
  (radius + ground_offset + SKIN + provider lift) -- all 4 call sites
  funnel through it. No PlayerProgress restore on the globe path
  (world_playable only) and no waypoint/gateway raw-position writes:
  respawn was the one live planar-coord funnel. Diagnostic for future
  reports: on-screen spawn-truth line (top-right of the playable HUD,
  2 Hz) prints lat/lon, ground height, sea line; WET tints amber --
  the Android reporter cannot read GameLog. Landscape: project.godot
  already pins window/handheld/orientation=sensor_landscape (line 121);
  the web/pck path takes orientation from the browser and portrait
  letterboxes correctly since the round-6 viewport guard -- nothing to
  lock in code. Verified: lint 36, regression 56/56 (3 chunks),
  probe_boot_loader_rect 4/4, probe_round2_ui 20/20, probe_globe_world
  23/23, test_splash_to_play 17/17 (xvfb, through the Start flow).
- [x] Play-test round 8 (11 items, desktop web client):
  (1) Boot progress bar never filled: the launcher takes PER-FILE
  totals ONLY from config.fileSizes (never Content-Length) and looks
  the pack up by the EXACT mainPack string -- our content-addressed
  'game.pck?v=<hash>' key missed (fileSizes was keyed 'game.pck'), the
  pack tracked total 0, animateProgress invalidates the aggregate
  total to 0 when ANY file is unknown, and the shell's total>0 guard
  never drew. index.html now HEADs game.wasm + the pack for real
  sizes, keys fileSizes under the pack URL TOO, and onProgress falls
  back to the known sum (capped 100%) when the engine reports 0.
  (2) Splash Start was a ~200x30 default-theme button under a huge
  logo: UIStyles.apply_cta_button() -- Synmergia green fill (new
  accent_green tokens), dark text, 380x76, font 30. (3) Loaders on
  guest-login/create-hero: ALREADY wired (GameManager.
  _show_loading_and_change_scene); they stay -- accounts go live and
  auth needs the cover. Species tap swaps cards in-scene, no loader.
  (4) Char select UX: class-card button says Select (was Play), Enter
  World is the green CTA (340x64, font 26) disabled until a class is
  picked, Back is a neutral 180x64 secondary, card/species headers
  bigger. (5) Flow panels bigger: login 420x520 -> 540x640 (fields
  48, buttons 52, fonts up), lobby 720x520 -> 880x640 (buttons
  180x52), class cards 260x380, species cards 300x340, fonts 13-26.
  (6) Tab-away refresh: NOT a React remount (GodotClientView's iframe
  src is static) -- browser tab-discard reloads the page, and the old
  middleware forced Cache-Control: no-cache on EVERYTHING with no
  Content-Length, so every return re-downloaded 44 MB. godot-
  WebRequestHandler (one handler for dev+preview, no more pasted
  copies) sets Content-Length + answers HEAD, keeps index.html +
  .hash as no-cache anchors, serves game.pck?v=<hash> immutable (1y)
  and game.wasm 1-day. A discard-reload now reboots in seconds; the
  discard itself is browser-owned (Memory Saver) and cannot be
  disabled from the page. (7) "Spawned in ocean" perception: the
  truth line read ground 9.0 m / sea 6.0 m / DRY -- the boot was ON
  dry land; the homeland-dome detail noise carved the coast right up
  to the plaza edge, so half the view was water. New SPAWN_SHORE
  APRON in terrain_gen: from the plaza edge out to 0.004 rad (~80 m)
  the land floors to sea+0.25 m, ramping down from SPAWN_HEIGHT so
  the plaza-flat, ramp-continuity (worst step ~3.2 m < 4 m) and
  homeland laws all still hold (probe_terrain_planet 22/22).
  (8) Char/eq panel bled off-screen and was unclosable: the R7
  recenter only fixed center-anchored panels; _clamp_panel_to_viewport
  now ALSO shifts any laid-out rect that escapes the viewport back
  inside (by overflow, after the size clamp), so the close X is always
  reachable. (9) Back gesture stack: Android back (NOTIFICATION_WM_GO_
  BACK_REQUEST on MenuManager), web browser back (popstate bridge:
  sentinel history.pushState at HUD install, popstate re-pushes +
  fires request_back via a JavaScriptBridge callback -- resolved
  through Engine.has_singleton, never a bare identifier), and ESC
  (HudHotkeys._handle_escape upgraded) share ONE law: close top panel
  -> collapse expanded menu bar -> modal "Leave the world?" confirm
  (dim + CenterContainer -- never hand-place a center-anchored box,
  the round-7 frozen-offsets trap) -> Exit runs GameManager.
  change_state(CHARACTER_SELECT). Verified: tsc clean, lint 36,
  regression 56/56 (3 chunks), probe_boot_loader_rect 4/4,
  probe_round2_ui 20/20, probe_globe_world 23/23, probe_terrain_planet
  22/22 (with the apron), test_splash_to_play 17/17 (xvfb).
- [x] Play-test round 9 (7 items, Android portrait + desktop):
  (1) RESPONSIVE FRAMEWORK seed: new ui/components/responsive.gd
  (viewport-class helpers: is_narrow/is_compact + card_size/panel_size
  -- screens ask the viewport layer, never hardcode). Card strips in
  character_select are HFlowContainer now (Godot's flex-wrap): species
  and class cards WRAP to new rows on portrait instead of clipping at
  both edges; card mins adapt (two-up on narrow). probe_startup_flow
  typed its strip handle HBoxContainer -- retyped FlowContainer (the
  tscn type change broke it: "assign HFlowContainer to HBoxContainer"
  + a probe hang). Also: the static SPECIES header now hides in the
  class view (both headers showed at once).
  (2) SETTINGS EXPOSED BUT BROKEN, now fixed: the UI Scale + UI Text
  Scale sliders already existed -- _apply_ui_scale set .scale on every
  CanvasLayer NODE (scaling from top-left origin: center-anchored
  panels flew off-screen -- the bleed reports were partly THIS), and
  the text-scale broadcast had ZERO listeners (UIStyles.get_text_scale
  ignored the setting entirely; MenuManager's propagation called
  update_accessibility_settings with the WRONG arg count). Now:
  content_scale_factor on the root window (the correct lever with the
  canvas_items stretch -- everything scales, anchors keep working);
  get_text_scale() composes the saved ui_text_scale (resolved through
  the root, script-mode-safe); MenuManager connects the EventHub
  signal and re-broadcasts the SAVED value once at HUD install, with
  (high_contrast, scale, reduce_motion) read live from PlayerConfig.
  (3) GODOT LEVERAGE (answered in the report): HFlowContainer,
  content_scale_factor, anchors presets, Theme/type variations,
  CenterContainer, custom Resources -- the responsive.gd + UIStyles
  pair is our thin frame over them; keep new screens on containers
  only, no absolute offsets.
  (4) OCEAN VIEW round 2: the 80 m apron was smaller than the boot
  horizon (~360 m from 3 m eye height) -- the screenshot showed sea
  past it. Tier 2: the shore floor is now HELD from 80 m out to
  SPAWN_APRON_OUTER_ANG 0.02 rad (~400 m); the coast begins past the
  horizon. Worst step to natural dome terrain at the outer edge stays
  under the 4 m continuity bound (probe_terrain_planet 22/22).
  (5) UNCLOSABLE DIALOG root-caused: friends used native AcceptDialog
  / ConfirmationDialog popups -- their close buttons never receive
  touches in the embedded web canvas (round-9 screenshot: dead X).
  BONUS BUG: _on_add_friend read dialog_text (the PROMPT STRING) as
  the player name and sent a request to "Enter player name to add:";
  the native dialog had no input field at all. New ui/components/
  interaction_modal.gd: in-canvas modal (dim + CenterContainer + real
  LineEdit + working X), PRELOAD-CYCLE-SAFE (resolves menu_manager via
  runtime load(); menu_manager load-time-preloads friends_list, so a
  preload here closes menu_manager -> friends_list -> modal ->
  menu_manager) and STALE-CACHE-SAFE (no self-name annotations; new()
  inside the static -- the global class cache is cold for new
  class_names in --script mode). friends add/remove now use it.
  (6+7) INTERACTION STATES + PERM BACK: MenuManager gained an
  interaction stack (push_interaction/pop_interaction) that request_back
  pops before panels, and a permanent bottom-center "< Back" button
  visible while any panel/interaction/exit-confirm is live -- the
  phone back gesture collides with browser exit-fullscreen (first
  back is browser-owned), so an always-tappable back lives on the HUD.
  Panel open/close funnel through _update_back_button.
  Verified: lint 36, regression 56/56 (small chunks -- the 180 s cap
  ate the old 19-test chunks), probe_round2_ui 20/20 with ZERO script
  errors, probe_terrain_planet 22/22, probe_boot_loader_rect 4/4,
  probe_globe_world 23/23, test_splash_to_play 17/17 (xvfb).
- [x] Round 10 (4 items: engine layers, one interest law, ownership
  doc, spawn-on-ocean diagnosis):
  (1) NAMED COLLISION BITS: audit found ~50 magic-bit sites in 14
  files (de-facto map: 1=entity, 2=solid, 4=ground; broad masks 63 /
  126 / 0xFFFFFFFF spanning reserved bits). New LayerProfile schema
  (core/schemas/layer_profile.gd, HitboxProfile pattern) + DATA at
  data/physics_layers/physics_layers_main.tres (bits + named GROUPS:
  world/entity_solid/solid_ground composed; all_solid/geometry_no_
  entity/everything as explicit value overrides so the legacy broad
  masks ride data instead of arithmetic). DataService loads it
  (get_layer_profile); every call site now reads
  Layers.layer_bit("entity") / Layers.group_mask("world"); admin
  ghost toggles use 0/0 + named restore. GUARD TEST test_layer_
  profile.gd pins the .tres values to the audit map (a data edit that
  renumbers a bit is now a LOUD test failure, not a silent physics
  change); added to the regression runner. LESSON (twice): a static
  cannot share a name with an instance method (static bit() vs
  instance bit() -> renamed statics layer_bit/group_mask), and new
  class_names are invisible to --script mode's class cache until the
  local import cache regenerates (static-factory new() dodges the
  self-reference).
  (2) ONE INTEREST LAW: core/services/entity_interest.gd --
  query_interest (players+enemies, combat), query_all (+NPCs),
  query_players. FIXED A REAL BUG: get_entities_in_radius defaults to
  NPC, so the four projectile scans (trap, chain, ricochet, explosion)
  only ever saw NPCs -- player explosions could not hit wolves or
  players. Rewired: projectile x4 -> query_interest; guard_ai /
  enemy_ai -> query_players (guard_ai inherits the const -- cannot
  redeclare a parent's member); chat channel range -> query_players;
  respawn healers -> query_all; skill heal-threat -> query_interest;
  agent_connector observation -> query_all.
  (3) labs/prd-world-layers.md: the ownership law (FrameService =
  canonical state, physics = spatial truth, EntityService = interest,
  LayerProfile = named bits, TerrainGen = ground law;
  NavigationServer = future, MultiplayerSynchronizer = deliberately
  unused). Nobody re-litigates this.
  (4) SPAWN-ON-OCEAN, root-caused as a WEB RENDER bug: the sim is
  airtight (truth line reads the analytic law; streamer loads the
  spawn face SYNCHRONOUSLY at boot; tiles sit R+0.52+terrain, water
  shell at R+0.52+sea -- the tile floor is always >= 0.25 m above
  water at spawn). The terrain UVs were patch-local * 0.22 where
  patch-local coords reach +-5 km: UVs ~10^6. Desktop fp32 varyings
  survive that (moire); the WEBGL2 fragment path is mediump (max
  ~65504), so ground UVs read INF on web -- sampling breaks and the
  tiles render garbage/vanish, leaving the water shell as the only
  intact sphere. EXACTLY the round-5 and round-9 screenshots (truth
  says dry, pixels say ocean). Fix: fposmod-wrapped UVs (the checker
  texture repeats, wrapping is invisible). TRUTH LINE now reports the
  stream state (mesh:fN xC/T) so a render-side break is visible ON
  the next screenshot instead of a sim-vs-render argument; boot log
  gains a spawn-face mesh-ready/mesh-FAILED gate line.
  Verified: lint 36/36, test_layer_profile 18/18,
  test_data_naming_lint 24/24, probe_terrain_planet 22/22,
  probe_globe_world 23/23, probe_round2_ui 20/20, probe_startup_flow
  18, probe_arena_instance PASS, probe_climb 11/11 (zero SCRIPT
  ERRORs across all logs).
- [x] Round 11 (post-crash screenshots: "still ocean under player" +
  "Character panel Inventory tab STILL blank"):
  (1) PACK FRESHNESS settled by reading the loader chain end to end:
  web/index.html fetches game.pck.hash no-cache -> mainPack =
  game.pck?v=<hash>; the worker serves index.html + .hash no-store,
  hashed packs immutable, and 302s bare game.pck to the hashed URL.
  A hash change makes a NEW url, so a plain reload must fetch the new
  pack -- no staleness path found. The screenshot problem was
  VISIBILITY: the mesh:fN xC/T tag sat at the END of the truth line,
  exactly where the minimap overlaps. Moved the tag to the FRONT
  ("mesh:f0 x12/3456 | lat .. | ground .. | sea .. | dry"); no test
  parses the old order. Next screenshot reads pack-fresh even on a
  phone/portrait layout.
  (2) BLANK CHARACTER PANEL -- ROOT CAUSE, not hydration timing:
  _show_tab() iterated `for tab in Tab:` -- the enum DICT yields
  String NAMES, but _tab_contents is keyed by the ints from
  Tab.values() -- every get() missed and NO tab body was ever shown.
  Tabs painted, body blank (the R6 fix note even called this lookup
  out, but only the _setup_tabs half got fixed). Fixed to
  Tab.values(). ALSO: refresh_inventory() gated on _char_data !=
  null -- the globe single-player world never sets
  GameManager.selected_character_data, so even a visible tab refused
  to hydrate. Gate removed (grid + equipment read the live bag;
  stats/skills keep their gate).
  (3) THE BAG WAS UNREACHABLE IN GLOBE MODE: the planar controller
  binds PlayerManager.set_local_player(self) and exposes
  `inventory_component`; the globe body did neither, so the panel's
  resolve path (get_local_player_id -> InventoryService, or the
  player-node duck type) missed the bag it was standing on. Globe
  body now binds itself + exposes inventory_component (same wiring,
  line-for-line). Bonus fix: the "Inventory is empty" hint was
  sticky -- an open before the bag registered left it behind forever
  even after hydration; retired when a live bag resolves.
  New probe_character_panel (14 checks) pins all of it: tab-body
  visibility flip, hydration WITHOUT character data, globe binding,
  service registration, panel->globe bag resolve, un-sticky hint.
  Added to the runner DEFAULT_SET after probe_round2_ui.
  Verified: probe_character_panel 14/14; full regression in 7 chunks
  58/58 (zero script errors).
- [x] Round 12 (screenshots after R11: char/inv loads; new evidence --
  mesh:f16 x4/16384 ON SCREEN):
  (1) PACK FRESHNESS + SPAWN TRUTH SETTLED: mesh:f16 visible means the
  UV-fix pack RAN and 4 faces/16384 tris are loaded, law says dry 9.0
  vs sea 6.0 -- yet pixels show ocean. The coast-scan probe kills the
  apron-sea theory: with the REAL seed (sea 6.03, spawn 9.0) there is
  NO coastline within 600 m in any of 16 directions, and terrain is
  already 30 m at 200 m out. An xvfb render of the real spawn scene
  (Compatibility GL = the WebGL2 family) shows GREEN ground with teal
  only at the physical horizon -- so the draw works in-family on
  desktop and the break is web-specific. TRUTH LINE UPGRADED to split
  the remaining hypotheses on the next screenshot: ALT = the player
  BODY's altitude above the base shell (law said dry; if ALT ~ 10
  while pixels are teal, the body never sank and the break is in the
  draw; if ALT collapsed to ~6, the body sank), vis = patches visible
  in-tree (vis>0 + teal pixels = tiles in tree but not drawn; vis=0 =
  streamer side). Line: mesh:fN xC/T visV | ALT A | lat .. | ground ..
  | sea .. | WET/dry. Streamer gains visible_patch_count().
  (2) WORLD MAP WAS A 150x150 CORNER BOX: _ready pins corner geometry,
  and toggle() (the R6 minimap-button target) only flipped VISIBILITY
  -- never switched to full-map mode. toggle() now opens FULL-RECT
  (expand_to_fullscreen) and closing restores the corner. The
  1920x1080 custom_minimum_size forced overflow on small windows (now
  ZERO in full mode, anchors govern; _screen_to_world divides by the
  real size now). Backdrop added: the globe streams per-face terrain
  and mounts no ZoneData, so MapTexture was textureless and the full
  map drew raw black.
  (3) FACTIONS RENDERED '? Rep: 0': the Faction schema field is
  display_name; the panel read "name". Falls back name -> id, never
  anonymous. (First probe run caught MY OWN dropped var line here --
  parse error cascade, the hang-signature lesson again.)
  (4) QUEST JOURNAL TABS read as one text run: buttons now carry the
  Bank panel's 100 px min width. ("(No quests)" on all three tabs is
  CORRECT globe state -- no quest givers exist in the globe scene
  yet, not a hydration bug. Titles list empty is also correct: First
  Blood needs 1 kill.)
  New probe_playtest_r12 (12 checks): full-size open/close round
  trip, backdrop, display_name rows (resource + dict + empty), quest
  tab widths. In DEFAULT_SET after probe_character_panel.
  Verified: probe_playtest_r12 12/12, probe_globe_world +
  probe_terrain_planet green after the truth-line change, full
  regression 59/59 in 7 chunks.
- [x] Round 13 (R12 screenshots: vis4 | ALT 10.5 | dry ON SCREEN with
  teal pixels; map opens fullscreen but empty, no exit, touch HUD on
  top):
  (1) THE OCEAN, root-caused (evidence chain now closed): vis4 = four
  patches IN-TREE and visible, ALT 10.5 = body standing on land, law
  says dry -- desktop-GL xvfb render of the same scene is green.
  Remaining web-only draw suspects, both fixed in the tile path:
  (a) the checker TEXTURE had no mipmaps -- Godot's default filter is
  linear-with-mipmaps and STRICT GLES3/WebGL2 drivers render
  incomplete textures BLACK (desktop is lenient). Black tiles under
  dim ambient + the water shell showing where the expected ground
  isn't = exactly the user's teal-over-gray-green frames with a
  curved horizon (the water sphere horizon at eye height, not a
  coastline -- the coast scan proved none exists within 600 m).
  (b) UVs reached 512 in a mediump varying: ULP at 512 ~0.03 is
  larger than the whole 2x2 texture. Texture is now 64x64 POT with
  generate_mipmaps (6 levels verified headless); UVs wrapped to
  [0,1) at 0.0015 scale (the 8x8 checker cell keeps the walking
  parallax cue). This is the round-12 WEB RENDER LAW, continued:
  small UVs AND complete textures.
  (2) MAP UX (round-13 screenshot fixes): the fullscreen map had no
  world content (globe mounts no ZoneData), no visible exit (the X
  sat under the web shell's EDIT chip at top-right), and the touch
  HUD drew over it (CanvasLayer 18 vs HudLayer 10 -- MenuManager's
  yield only fires for ITS panels; the map is a HudLayer child).
  Now: _ensure_world_canvas() generates an equirectangular world
  map ONCE from the terrain law (384x384, height-band colors, water
  by depth) -- "map with no content" is dead; the gold player dot
  rides the truth line's lat/lon via set_player_lat_lon(); the close
  button moved below the EDIT chip with a title + "M / Back / X
  closes" hint; the map registers with MenuManager's interaction
  stack (push_interaction/close_modal) so the BACK gesture and the
  always-tappable Back button close it; _set_touch_hud_yield(true)
  drops the joystick below the map, re-asserted on a 0.5 s _process
  cadence against the last-panel-closed re-arm race.
  probe_playtest_r12 extended to 15 checks (canvas generated, close
  button visible, dot inside viewport, close_modal path). Verified:
  15/15, probe_terrain_planet/globe_world/stream green with the new
  UVs, tex check 64x64 mips=6, full regression 56/56 in 6 chunks.
- [x] Round 14 (web play-test automation; black-viewport hunt closes
  as NOT reproducible on the R13 pack; loader + panel fixes):
  (1) HEADLESS WEBGL2 TOOLING (user-authorized installs): Playwright
  1.63 + full Chromium in ~/.cache/ms-playwright, pngjs, libvulkan1
  (pulls Mesa lavapipe). PROVEN boot config: the FULL chrome binary,
  headless:true, args --enable-unsafe-swiftshader --no-sandbox
  --disable-dev-shm-usage --in-process-gpu -> webgl2 = ANGLE (Google,
  Vulkan 1.3.0 (SwiftShader)). headless-shell and separate-GPU-process
  Chromium both FAIL in this container (eglInitialize SwANGLE ->
  EGL_NOT_INITIALIZED -> GPU process exits -> NO webgl2). The probe,
  labs/web_probe_r14.cjs (committed this round), serves web/ with
  COOP/COEP on :8099, boots the engine, classifies screenshots (top
  colors + 4x4 region grid), drives input, and writes console.txt +
  summary.json + PNGs to /home/daytona/r14-webtest/out/.
  (2) FULL CLICK-THROUGH, IN-WORLD FOR THE FIRST TIME headless:
  Start(640,408) -> Guest(640,588) -> Create(544,646) -> species
  Select(316,436) -> class Select(214,516) -> Enter World(1086,676)
  RETURNS TO LOBBY (character_select links the new character and
  goes back; lobby Play(352,646) is the real world entry). Ground
  truth = DebugOverlay "Click:" lines + GameLog "Game state changed:",
  never pixels alone (login/lobby/char-select all classify as dark
  16,16,16 ~90%). world.png: green terrain 48.7% + teal water 38.6%,
  black 0.5%; ZERO shader/material errors across the whole boot (only
  noise: the pre-existing invalid-UID warnings). M opens and closes
  the fullscreen map with the generated world canvas. VERDICT: the
  user's black in-game viewport is NOT reproducible on the current CI
  pack (game.pck 3c7f522f) under working WebGL2 -- the R13 web draw
  law (POT textures + mipmaps + [0,1) UVs) holds. Remaining suspect
  is user-side GPU/context loss (a strict driver chokes where
  SwiftShader is lenient, or the context dies mid-game). Hardened
  that failure class: index.html now listens for webglcontextlost and
  shows the error screen with a reload hint instead of a silent black
  canvas. Open item: W-hold produced no pixel delta in the probe
  (canvas focus/keyboard reach under headless unproven) -- movement
  is still verified only by the native probes.
  (3) index.html WATCHDOG BUG FIXED: the 20s stall watchdog read
  progressSeen, declared inside startWithPack() -- 'progressSeen is
  not defined' threw on EVERY page load at 20s (captured in probe
  console), so the stalled-download safety net never ran. The flag
  now lives at IIFE scope (anyProgressSeen).
  (4) SCREENSHOT UI FIXES: character_panel.gd (a) emoji stat icons
  removed (no-UTF-8 law; they rendered as tofu boxes); (b) the
  "Human Human Marksman" header -- class_id is species-prefixed
  (human_marksman) so .capitalize() double-printed the species; the
  header now prefers CharacterClass.display_name ("Marksman"),
  falling back to the id only when class data cannot load; (c)
  derived stats showed "--" forever -- the refresh pass looks for
  rows named Derived_<key> holding a child Label named "Value", but
  the rows were nameless; named both, values now fill from
  get_derived_stats(). Also removed a duplicated dead return line in
  globe_terrain_streamer._make_checker_texture.
  (5) USER CLARIFICATION + MAP HARDENING: the round's black
  screenshots were the MAP OVERLAY (opened in-game), not the world
  viewport -- the R12-era "textureless map drew raw black" symptom.
  On the current pack the probe's map_open.png HAS content (landmass,
  water, gold dot), so headless cannot repro it. Hardened the one
  silent-failure path that would repaint that symptom on any machine:
  _ensure_world_canvas now verifies preconditions (math script + seed
  bytes present) and painted coverage after the pixel loop
  (Image.create starts transparent black; a GDScript runtime error
  inside the loop does NOT abort it -- the pixels just never get
  painted and the map shows the dark backdrop = black overlay). A
  failed generation is NOT cached (retry next open, boot-order races
  heal), warns via GameLog, and shows a fallback ocean chart so the
  map stays usable. probe_playtest_r12 A5 (canvas generated) green.
  (6) Verified: probe exit 0 with an in-world frame (re-run AFTER the
  index.html edits: zero progressSeen pageerrors); full regression
  58/58 in 6 chunks (probe_character_panel, probe_terrain_stream,
  probe_globe_world all green with the edits).
- [x] Round 15 (R14 web frames: "player spawns on the ocean, land is
  above me" + "the fullscreen map is MIRRORED"; two independent root
  causes, both in the WORLD BUILD, plus a map orientation law):
  (1) THE PLAZA WAS SUB-TILE. At the v1 planet scale the streamed
  icosahedral mesh samples the heightfield only every ~330 m (face
  edge ~21 km / 2^6 subdivisions). The old spawn plaza was
  SPAWN_FLAT_ANG 0.0015 rad = 30 m -- SMALLER THAN ONE TILE -- so the
  mesh never rendered it: the body sat at SPAWN_HEIGHT (9 m) while
  the rendered ground stayed at the natural ~30 m hills. The camera
  ended up INSIDE the hillside. terrain_gen.gd: SPAWN_FLAT_ANG 0.04
  (~800 m, full-flat within 0.024 = 480 m, past the ~360 m boot
  horizon), SPAWN_APRON_ANG 0.06 (~1200 m), SPAWN_APRON_OUTER_ANG
  0.09 (~1800 m); the apron is the tier OUTSIDE the plaza so its
  inner edge must never sit inside it. Verified: the nearest mesh
  vertex to spawn now has terrain lift exactly 9.00 m, and six verts
  within 360 m are all 9.00 m -- the whole visible ground is plaza.
  (2) EVERY STREAMED PATCH WAS BACK-FACING AND CULLED. Godot's front
  face is CLOCKWISE, but the icosahedral face corner order is
  COUNTER-clockwise from outside (the math convention).
  globe_terrain_streamer._load_patch built corners (fv[0], fv[1],
  fv[2]) = the wrong winding, so no terrain fragments drew and the
  boot saw only the base green shell + the teal water shell -- the
  literal "I spawned on the ocean layer, land above me" report.
  Corners are now (fv[0], fv[2], fv[1]); the radial normals already
  point outward. Proof chain: UNSHADED / CULL_DISABLED changed the
  frame ([3]22,25,32 -> [3]246,8,3 red fills), i.e. the stock
  material was drawing almost nothing. Patch mean gnorm.dot(radial)
  went +0.7737 (inward) -> -0.0502, matching a Godot-built
  SphereMesh reference (-0.0067): same sign, so the patch is now
  front-facing like a normal mesh.
  (3) MAP MIRRORED -- LAT SIGN FLIPPED BETWEEN CANVAS AND MARKER.
  world_map.gd painted row 0 as the SOUTH pole (lat = -90 + ...)
  while the player marker read py = (90 - lat) / 180: the map was
  vertically flipped AND the dot disagreed with it. One shared
  static lat_lon_to_uv(lat, lon) = ((lon+180)/360, (90-lat)/180) now
  drives both -- u grows EAST, v grows SOUTH from lat +90, image row
  0 = the north pole; the canvas uses the inverse (lat = 90 - 180 *
  row / 384).
  (4) REGRESSION GUARDS: probe_terrain_planet adds "mesh: spawn
  plaza is RESOLVED", "mesh: boot horizon is flat plaza", and "mesh:
  patch winding matches a Godot sphere (patch %.4f vs sphere
  %.4f)"; probe_playtest_r12 adds A10 (lat/lon->UV is north-up) +
  A11 (canvas is north-up, not mirrored -- N/N discriminating
  samples match the law).
  (5) Verified: probe_terrain_planet, probe_playtest_r12,
  probe_globe_world, probe_planet_scale_20km, probe_terrain_stream,
  test_world_shape, test_terrain_determinism green; full default
  regression 59/59 in 8 chunks; web/game.pck rebuilt (export-pack
  Web Default) AFTER the winding fix -- the world frame's teal water
  share dropped from 38.6% to 1.8% (terrain now renders). NOTE: the
  user's browser only picks this up once the refreshed pack is
  committed + reloaded with the cache-buster; until then the live
  site still serves the pre-fix pack, which is why the R15
  screenshots still looked wrong.
- [x] Round 16 (frame audit, second set of eyes -- game/core/frame/*,
  triggered by the R15 clockwise/counter finding; every claim below
  was reproduced with a headless probe before it was written down):
  (1) FIXED -- SpatialFragmenter.MAX_DEPTH was 24 but the 64-bit
  address layout gives each coordinate a 16-bit field, so a
  subdivision path holds 16 x-bits + 16 y-bits + 16 z-bits = 48 bits =
  16 levels (3 bits/level). Past depth 16 the coordinate shift is
  silently masked and DISTINCT cells collapse onto the same address.
  Reproduced: two distinct depth-16 parents produced fully-overlapping
  depth-17 child sets (8/8), and make_address(x=0x10000) ==
  make_address(x=0) at depth 17. MAX_DEPTH is now 16; new guard
  _test_depth_within_coord_bits (3*MAX_DEPTH <= 48 + refusal at
  MAX_DEPTH). Consumers: nsc9_bridge clamps depth to it; no other
  caller depended on 24.
  (2) FIXED -- Icosahedral.cell_center returned the RAW vertex
  (length sqrt(1+phi^2) ~= 1.902) while face_center / nearest_vertex /
  to_cell all work in unit directions; the only test hid it behind a
  tautology (`... or abs(len - 1.0) > 0` is true for every non-unit
  vector). cell_center now returns _normalized[cell_id]; the test
  asserts unit length for real.
  (3) FIXED -- Markov chunk keys could not represent negative offsets.
  The 3x3 neighbour grid runs -1..+1, but generate_key masks to
  16-bit unsigned, so offset(-1,-1) encoded as "ffff-...-ffff" and
  decoded back as (65535,65535) instead of (-1,-1), poisoning
  last_move_delta and the velocity-conditioned transitions.
  _chunk_key_to_offset now sign-extends 16-bit fields (_sign16).
  Verified round-trip true.
  (4) FIXED/guarded -- the frame winding contract is now pinned and
  documented: IcosahedralFaces.face_vertices() is wound
  COUNTER-clockwise from OUTSIDE (right-handed, outward normal) for
  ALL 20 faces -- the math convention and the OPPOSITE of Godot's
  front face. Reproduced: 20/20 CCW, 0 CW. That is precisely how the
  R15 terrain streamer ended up back-facing and culled, so the
  contract now has a guard (_test_winding_is_outward_ccw) and a
  comment saying any Godot mesh builder MUST flip the winding.
  (5) NOTED, not fixed (behavioral/design, needs an owner call):
  - "face" names TWO namespaces: IcosahedralFaces = 0..19 triangles
    (the terrain); SpatialFragmenter/Nsc9 = 0..11 icosahedral VERTICES
    (nsc9_axis_to_face = axis-1), yet the address field is documented
    "icosahedron face". Mixing them silently addresses the wrong cell.
  - RulesEngine: _evaluate_top_wins reads stack[0] but reports
    "innermost scope decision" while _evaluate_bottom_wins reads
    stack[-1] and reports "outermost" -- the two labels/indices
    contradict; one is wrong. _evaluate_predicate_gated is a stub
    (both branches return default_allow; the predicate is never
    evaluated) and register_rule stores str(predicate), which is not a
    portable or invokable representation.
  - LRUCache comment claims O(1) get/set/evict but _move_to_front uses
    Array.erase (O(n)); FoldedShell.release_space loops `for cell in
    fact_cells(h)` only to call _hot.delete(h) once per cell.
  - swim_state.set_breath_capacity multiplies CURRENT breath (partial
    drain scales the remaining too) rather than the capacity.
  (6) Verified: frame/math/test_icosahedral, test_icosahedral_faces,
  frame/geometry/test_spatial_fragmenter green; probe_terrain_planet,
  probe_globe_world, frame/math/test_spherical, test_terrain_determinism,
  probe_terrain_stream green. NOT yet audited (next pass): scope_*,
  rules_schema, resource_scan, ferry_schedule, world_registry,
  memory/social/definition trees, schemas/.
- [x] Round 17 (owner-directed follow-ups to the R16 second-eyes
  report: the 4 fix requests + Markov tests + the face-namespace
  split). Item 1 (switching the math/iso layer to CW winding) was
  DISCUSSED ONLY -- no code changed; see the chat analysis.
  (1) MARKOV TESTS + FIX -- added co-located frame/srv/test_markov
  (sign16 round-trip incl. "ffff" negative encode, transition
  learning, predict_next ordering/probabilities, predict_n_steps,
  multi-horizon, simulation accuracy, sufficiency/current/clear) and
  added it to the runner DEFAULT_SET. Fixed predict_n_steps: it
  divided each outgoing count by the GLOBAL state.total_transitions
  while predict_next row-normalizes, so multi-step probabilities
  leaked mass every step and disagreed with predict_next. It now
  row-normalizes on the source key's outgoing counts (guard: two
  rows of 10 with global total 20 -> probability 1.0, was 0.5).
  (2) FACE NAMESPACE SPLIT -- "face" named two things: IcosahedralFaces
  = 0..19 TRIANGLES (terrain); SpatialFragmenter/Nsc9 = 0..11
  icosahedral VERTICES. The iso/triangle layer KEEPS "face"; the
  fragmenter field/API/key suffix were renamed to "vertex":
  make_address(...,vertex), get_vertex(), VERTEX_MASK/SHIFT,
  nsc9_axis_to_vertex(), nsc9_code_to_vertex(),
  to_spatial_address(...,vertex), entity_spatial_to_vertex(),
  query_nsc9_vertex(), the frag dict/bbox key "vertex", and the
  encoded key suffix f->v (%-d%d-v%d). Numeric semantics unchanged
  (axis 1-12 -> vertex 0-11). Callers updated: lod_manager,
  zone_manager, entity_service, test_lod_predictor, and the
  prd-geometry / prd-spatial-geometry / prd / world-building-arch /
  world-building specs. (globe_terrain_streamer's "face" is the
  triangle terrain -- untouched.)
  (3) RULES ENGINE -- _evaluate_top_wins read stack[0] while
  _evaluate_bottom_wins read stack[-1]; both contradicted their own
  reason strings. Fixed to the spec (prd-scope-engine US-006):
  push() appends, so stack[0] = outermost/root (BOTTOM of stack) and
  stack[last] = innermost/player (TOP). TOP_WINS now reads the last
  element, BOTTOM_WINS the first. _evaluate_predicate_gated now
  actually invokes the predicate as predicate.call(action, context)
  and requires a bool (invalid/non-bool falls back to default_allow).
  register_rule no longer writes str(predicate) into the T3 payload:
  predicates live in an engine-side table keyed by rule_id (a real
  Callable in the payload would break var_to_bytes/bytes_to_var in
  diff/apply_diff). New tests: TOP/BOTTOM ordering, predicate
  true/false, payload excludes predicate.
  (4) GAME-LOOP MINORS -- LRUCache replaced its Array order (erase =
  O(n) per get/set) with an O(1) intrusive doubly-linked recency
  order (_prev/_next, MRU head / LRU tail); FoldedShell.release_space
  now deletes each orphan hash once (the old loop iterated
  fact_cells(h) but deleted h per cell, leaking the hot entry when a
  fact had zero indexed cells); swim_state.set_breath_capacity now
  sets breath to the new FULL capacity BREATH_SECONDS * multiplier
  instead of scaling the current (possibly drained) breath.
  (5) Verified green: frame/{math,geometry,kv,srv} set (spherical,
  icosahedral, icosahedral_faces, spatial_fragmenter, nsc9_bridge,
  lru_cache, folded_shell, t3_dedup, rules_engine, markov,
  scope_engine, swim_state, star_cells, ferry_schedule,
  resource_scan) + probes startup_flow/globe_world/world_scoping/
  terrain_stream + test_lod_predictor (the last three boot autoloads,
  so the edited services compile). No new non-ASCII; tabs only.
- [x] Round 18 (continue the frame audit into the files R16 deferred):
  (1) FIXED -- FerrySchedule.crossing_in_progress never detected an
  OVERNIGHT crossing. The yesterday leg used dep_h = h + 24, so
  elapsed = now_h - h - 24 was always negative and day_offset -1 was
  unreachable (the boat vanished between midnight and its arrival: the
  dock read "in_port" and offered "next cast-off in Xh"). dep_h is now
  h - back*24, and the scan walks departures NEWEST-first within a day
  (the doc's "newest sail" intent). New tests: overnight seen at 01:00
  (day_offset -1), gone at 02:30, and two simultaneous sails report the
  newest. test_ferry_schedule + probe_ferry green.
  (2) NOTED, not fixed (need an owner call / are not defects on their
  current contract):
  - Every kv schema defines _to_canonical_bytes (sorted keys,
    length-prefixed values, seed_schema's sign-stripping), but T3
    hashes var_to_bytes(value) and never calls them -- the canonical
    encoders are effectively dead w.r.t. content addressing. Wiring
    them changes EVERY content hash, so it is a deliberate migration,
    not a drive-by.
  - The *_schema._validate methods read untrusted values into typed
    locals (var x: String = value["x"]), which throws on a wrong-typed
    field instead of returning false.
  - memory_schema's writer names a float encoder write_f32 but stores
    int(weight * 1000) (a 1/1000 quantized int).
  - world_registry.cosmic_age_s subtracts a Unix origin_unix (seconds
    since 1970) from epoch_days * 86400 (seconds since the Concord
    epoch) -- two different origins; the mapped design intent needs
    confirming before it is called a bug. resource_scan,
    scope_hierarchy/scope_node, the kv tree wrappers, star_cells and
    seed_chain were read and are clean.
- [x] Round 19 (owner-requested fixes for the round-18 open items):
  (1) WIRED -- T3 now hashes a payload's SCHEMA CANONICAL BYTES when
  the schema provides _to_canonical_bytes and the payload is a
  Dictionary (new _hash_bytes_for); the kv schema encoders are no
  longer dead w.r.t. content addressing. value_bytes (the TRANSPORT
  form diff carries and apply_diff decodes) stays var_to_bytes, so
  serialization round-trips are unchanged, and native/plain-Resource
  schemas fall back to var_to_bytes (test_t3_dedup's key-order law
  still holds).
  (2) HARDENED -- the _validate methods of definition/memory/social/
  seed/state schemas read untrusted fields as Variant and typeof-check
  them; a wrong-typed field now returns false instead of THROWING from
  a typed local (var x: String = value["x"]).
  (2b) ALSO FIXED (found while writing (2)'s test) -- definition/memory/
  social _validate called X.get_type(), which Variant does NOT have in
  Godot 4.7.2. The call errored to null, so `null != TYPE_*` was always
  true and _validate rejected VALID payloads. Now typeof()-based. New
  co-located test_kv_schemas (valid + wrong-typed for all three) proves
  it and is in DEFAULT_SET. Invisible in production because T3.insert
  does not validate; only tests ever called these validators
  (scope_engine calls ScopeHierarchy._validate, a different function).
  (3) FIXED -- memory_schema's writer was named write_f32 but stored
  int(weight * 1000) (a 1/1000-quantized int), folding distinct nearby
  weights into one content hash; it now writes a real IEEE-754 float32.
  (4) VERIFIED, NOT A BUG -- world_registry.cosmic_age_s is correct:
  SignService.sky_epoch_days() IS unix/86400 (calibration_tier.gd), so
  epoch_days * 86400 - origin_unix is unix seconds since the origin.
  The round-18 note was a misread of the world_registry "Concord clock"
  comment; the comment is clarified and the new co-located
  test_world_registry.gd locks the alignment (age = unix elapsed, the
  horizon grows at exactly c, negative age clamps). Noted: the
  UNIVERSE_SEED_HEX constant is 33 bytes ("synmergia" + zeros), not 32
  -- harmless (SeedChain hashes it) and left as-is because changing it
  re-derives every world seed.
  Verified green: frame/kv/{test_t3, test_t3_dedup,
  test_frame_seed_schema, test_frame_state_schema, test_memory_tree,
  test_social_tree, test_definition_tree}, frame/srv/{test_rules_engine,
  test_star_cells, test_world_registry (new, added to DEFAULT_SET)},
  probe_world_lattice.
- [x] Round 20 (seed width + derived-seed hashing, and the scope-stack
  order bug):
  (1) FIXED -- UNIVERSE_SEED_HEX was 33 bytes ("synmergia" + 24 zero
  bytes), the lone odd-width link in a chain where every derived seed
  is a 32-byte SHA-256. Now exactly 32 bytes (9 ASCII + 23 zeros); the
  root is uniform with its descendants. The owner approved re-deriving
  seeds (alpha, no players, world not built). test_world_registry locks
  the 32-byte width, the 64-char hex, and the ASCII-prefix tail.
  (2) FIXED -- seed_schema._to_canonical_bytes omitted derived_seed. The
  payload fields do NOT capture the seed STACK, so two seed trees built
  from the SAME declaration under DIFFERENT stacks produced
  byte-identical nodes and therefore identical T3 content hashes -- a
  real collision, not a theoretical one. derived_seed is now folded into
  the canonical bytes (absent -> empty, deterministic). New tests:
  test_frame_seed_schema case (derived_seed changes the bytes),
  test_seed_chain case (same declaration + different stacks -> different
  tree hashes), and an updated length-prefix layout assertion.
  (2b) ROBUSTNESS -- test_star_cells hardcoded an address it assumed was
  empty; the re-derived sky moved it. The test now SEARCHES the probe
  slice for a genuinely empty and a populated address (covers both
  branches) instead of weakening the assertion.
  (3) FIXED (real, live bug) -- core/services/matchmaking_qos.gd had
  `extends Node` AFTER two const preloads, which is a PARSE ERROR. The
  script never compiled, so `class_name MatchmakingQoS` never registered
  even though backend_factory.gd maps "matchmaking_queue" to it by name.
  extends now precedes the consts. Only .gd in the repo with the defect.
  (4) FIXED (real bug) -- the rules scope stack had TWO orders in the
  wild. The canonical order is ROOT-FIRST (spec prd-scope-engine.md
  US-006: resolve_rule walks root -> player; RulesEngine R17 reads
  stack[0] as BOTTOM/outermost and stack[size-1] as TOP/innermost).
  SecurityService and MatchmakingQoS built the stack INNERMOST-FIRST,
  silently inverting TOP_WINS and BOTTOM_WINS for both (e.g. a
  BOTTOM_WINS permission_check read the player scope, not the world's).
  Both now build root-first. AppFirewall was already root-first; its
  "innermost first" comments were backwards and are corrected. New
  booting test test_scope_stack_order (in DEFAULT_SET) locks both.
  (5) FIXED -- SnapshotStore.latest_snapshot() kept a stale ordering when
  an EXISTING root was re-stored (the order was only rebuilt for new
  keys, so stored_at moved but the sort did not), and same-second stores
  tied non-deterministically. Added a monotonic seq tiebreaker and
  rebuild-on-every-store. New test_snapshot_store case (re-store moves a
  root to the front).
  Verified green: frame/kv/{test_seed_chain, test_frame_seed_schema,
  test_t3, test_t3_dedup, test_kv_schemas}, frame/srv/{test_world_registry,
  test_star_cells, test_rules_engine, test_scope_engine},
  frame/db/test_snapshot_store, frame/geometry/{test_spatial_fragmenter,
  test_nsc9_bridge}, test_scope_stack_order (new), test_anticheat_limits,
  test_auto_response_signals, test_notification_frame, test_login_flow,
  probe_{startup_flow, globe_world, world_scoping, ferry, world_lattice},
  test_terrain_determinism. No new non-ASCII; tabs only.
- [x] Round 21 (walk world_state_projection + scope_service, then the
  game layer -- quest availability was broken end-to-end):
  Audited core/services/scope_service.gd (WorldRegistry API use is
  correct -- load_worlds/get_world/is_enterable all exist; the room and
  world scope reparent/escape seam is sound) and
  core/services/world_state_projection.gd (scope token -> tree path
  prefix, zone-drift teardown, instance overrides, tick buffering all
  correct). Only a cosmetic defect there: a `##` doc block was glued to
  the tail of _is_player_target's return (so it never documented
  _extract) and carried a non-ASCII em dash; now separated and ASCII.
  REAL BUGS found while walking the game layer (QuestService
  get_available_quests / _get_available_quest_ids):
  (1) DataService.get_all_quests() returns the VALUES (Array[QuestData]),
  but the code indexed the array BY the value (all_quests[quest_id]
  where quest_id was itself a QuestData) -- an invalid index that aborted
  the whole function, so quest availability always came back empty.
  (2) quest.get("min_level", 1) used Resource.get's default argument,
  which 4.7.2 removed; on a QuestData it raises "Invalid call to function
  'get' ... Expected 1 argument(s)" and aborts. Verified empirically on
  the engine (static parse error when typed; runtime error when dynamic).
  Now the loops iterate the values and read the exports directly
  (quest.id, quest.min_level, quest.display_name, quest.description).
  (3) META-BUG exposed by (1): once get_available_quests actually returned
  its rich dicts, the live consumer QuestUI.refresh_quest_list fed each
  one into a String-typed _create_quest_button -- a runtime "Cannot
  convert argument 1 from Dictionary to String" (verified) that would
  blank the AVAILABLE tab. The UI now normalizes each element to its id
  (dict["id"] or the string itself).
  New booting test test_quest_availability (in DEFAULT_SET) locks the
  whole chain: ids are Strings that resolve through DataService.get_quest,
  the dict shape is String id/name/description + int min_level, level
  gating, and the real QuestUI AVAILABLE tab renders buttons.
  Verified green: test_quest_availability (new), test_data_naming_lint,
  test_quest_explore_bridge, test_quest_lore_bridges, test_daily_quest,
  test_world_state_projection, test_horde_configs, test_dungeon_portal,
  probe_playtest_r12, probe_round2_ui. No new non-ASCII; tabs only.
  NOTE: test_full_boot_live's open-world horde phase FAILS, but it fails
  identically on a clean tree (confirmed by stashing) -- pre-existing and
  unrelated to this round.
- [x] Round 22 (fix the six dead suites from the round-21 sweep; ROOT
  CAUSE of the whole class: the headless boot never loaded the world
  scene, so headless runs had NO PLAYER at all):
  ROOT FIX -- core/autoload/game_manager.gd _handle_playing_state
  skipped change_scene under headless, on the misconception that
  headless has "no rendering context". Godot 4 headless runs the full
  scene tree + physics (probes/terrain tests already build real 3D
  worlds headless); only DRAWING is absent. And the Player node lives
  INSIDE world_playable.tscn, so skipping the scene skipped the player
  spawn itself. The world scene now loads in every mode (loading
  overlay flow unchanged). Visible player spawn on the globe works as
  conceptually intended: boot -> world scene -> Player ready ->
  EntityService registers (player_1) -> ZoneManager zone entry ->
  player_entered_world fires once (StarterKitService, achievements).
  Per-suite fixes (test paths stale against product, product code was
  right):
  (1) test_ui_alive: MenuManager's round-6 z-fix ADOPTS the expanded
  panel (MenuItems and all menu_item_* buttons) into MenuManager's
  CanvasLayer 20 (_adopt_expanded_into_menu_manager) so the menu can
  cover chat; the test only searched under MainMenuBar. Now searches
  MenuManager too. 0/37+ -> 31 pass.
  (2) test_touch_live: injected touches are WINDOW coords;
  parse_input_event runs the stretch inverse. xvfb window == the
  1280x720 canvas (scale 1) so raw positions worked; headless's dummy
  window gave a ~x20 scale that flung every touch into the camera-look
  half (probed: injected (50,50) arrives at (1000,1000)). Injection now
  converts through get_final_transform(). P4 check re-timed 4.9 -> 4.65
  (0.15s after the jump press; 0.4s raced the apex under precise 60Hz
  headless physics). 8/17 -> 17/17.
  (3) test_respawn_live: poll window (frame 900) raced RespawnService's
  15s timer (frame ~990 at headless 60Hz) and the test then hung with
  no terminal verdict. Window widened to frame 3600 with an honest
  FAIL verdict past it; _verify guarded once. All 9 respawn checks
  PASS (the respawn chain itself was never broken).
  (4) test_settings_camera: MenuManager also adopts SettingsPanel (same
  round-6 z-fix); test lookup now falls back to a recursive find.
  14/14.
  (5) test_full_boot_live (LAST round-21 open item): phase 6 started
  the horde in legacy shorthand "starter_plains" but queried
  "zone_starter_plains" (canonical, per the data-naming law); the
  service stores zone_id verbatim so the query could never match. The
  start command now uses the canonical id. FULL-BOOT 43/43.
  Validation: DEFAULT_SET 64/64 green in 7 chunks (C1..C7 exit 0) with
  the boot-path change in place; login-flow-driven suites re-run green
  after it (test_e2e_flow, test_login_flow, test_onboarding_live,
  test_achievement_flow, test_combat_live, test_scene_enemy_respawn,
  test_dungeon_portal, test_horde_events, test_horde_rewards,
  test_progress_persistence, quest bridges). Hygiene: tabs only, no
  new non-ASCII.
- [x] Round 23 (inside-out audit lands on the adapters + tick core;
  SQL-shim query defects fixed, two live-flow defects in
  TickService/T3 fixed):
  Adapters (game/adapters/): Registry/BackendFactory/MigrationRunner/
  MemoryCacheStore audited CLEAN (manifest maps every persistence name
  to one shared store; migrations lexical + metadata table + env skip;
  cache TTL math correct). Five REAL defects fixed in the memory
  persistence SQL shim (memory_persistence_store.gd) + dict_store.gd:
  (1) operator scan matched '=' inside '>=' / '<=' / '!=' (earliest-
  match ordering now, ops list explicit); (2) IN param slice off-by-2
  (defensive paren strip before value parse); (3) ORDER BY / GROUP BY /
  LIMIT only parsed when a WHERE was present (clause indices now on
  the clause tail unconditionally); (4) DictStore.get_many double-
  decoded plain strings to null (decode only when the raw value parses
  as JSON); (5) 'IN (' spelling never matched (added to the ops list).
  Permanent regression suite game/tests/adapters/test_memory_sql_shim.gd
  (26 checks: WHERE ops, IN forms, LIKE, clause tails with/without
  WHERE, UPDATE, DELETE, kv type round-trips) -- 26/26 green.
  TickService (game/core/services/tick_service.gd) DEFECT A (major,
  live flow): _phase3_reroot_and_diff rotated the hash pair at the end
  of Phase 3, so Phase 4's _compute_aoi_diff gate
  (_previous_root_hash != _current_root_hash) was ALWAYS false -- no
  client ever received incremental diffs in the live tick; the phase-4
  test masked it by setting the hash pair by hand. Fix: Phase 3 now
  stashes the computed diff in _last_tick_diff BEFORE the rotation;
  _compute_aoi_diff prefers the stash and keeps the hash-pair recompute
  as a fallback for direct Phase 4 entry. test_phase4_zone_aoi extended
  with a live-flow mirror case (rotated pair + stash only) that asserts
  the same zone/progress routing; both paths covered (7 checks added
  total incl. the helper).
  T3 (game/core/frame/kv/t3.gd) DEFECT B (memory): _record_snapshot
  cloned the full node dict into _snapshots on every insert/apply/walk
  and NEVER pruned -- one snapshot per tick root on a live server,
  unbounded. Fix: bounded retention (SNAPSHOT_RETENTION = 64) driven by
  an insertion-ordered _snapshot_order; re-recorded roots move to the
  newest slot, oldest evicted from both _snapshots and
  _schema_refs_by_root; clear() resets the order. 64 (not 16) because
  the dedup contract test diffs a 20-update chain end to end
  (diff(roots[0], roots[20])) -- long-range diff is a documented frame
  capability, so the window must exceed it; consumers diff adjacent
  roots in the tick flow, which 64 covers with headroom.
  Known-noted (not fixed, harmless): _on_tick's N014 check measures
  tick DURATION against TOTAL_SYNC_BUDGET_MS, not diff-emit latency vs
  the boundary; warn-only either way.
  Validation: frame/kv/test_t3, frame/kv/test_t3_dedup,
  frame/kv/test_state_tree, frame/kv/test_folded_shell,
  test_phase4_zone_aoi (5/5), adapter chunk adapters/test_registry,
  test_dict_store, test_cache_store, test_memory_store,
  test_memory_sql_shim, test_persistence_store, test_dict_store_ttl,
  test_adapter_e2e, test_adapter_integration, test_service_integration
  (10/10). Hygiene: tabs only, no new non-ASCII, extends-first intact.
- [x] Round 24 (tick core walk continues: the N014 known-noted item
  fixed for real, plus three more defects found in the same file):
  TickService (game/core/services/tick_service.gd):
  (1) N014 fixed properly (was the round-23 "known-noted, warn-only").
  The old check computed |whole-tick duration - 48ms sync budget|, but
  the spec (risks doc N014) says: record SEND timestamps, assert within
  +/-2ms of a tick boundary -- and the old form FALSE-POSITIVED every
  quiet tick (~47ms deviation with one connected client, phases taking
  ~1ms). Phase 4 now records wall-clock send timestamps per client
  (send_times in the emit result); _on_tick measures the worst lateness
  against the tick's scheduled END (tick_start + TICK_BUDGET_MS, when
  the next tick is due) via new _n014_worst_late_ms(); warn only past
  N014_TOLERANCE_MS=2. Early sends are healthy (idle ticks run trivial
  phases 1-3) and never warn.
  (2) Side queue LEAK: _side_queue was appended on Phase 2 overrun and
  NEVER read or drained anywhere -- overflow work silently lost AND
  unbounded growth on a busy server. Phase 2 now drains it (Step 0.5)
  each tick: input items re-apply via _apply_player_input, items carry
  a _retries counter, and items past SIDE_QUEUE_RETRY_CAP=5 drop with
  a debug log (a logged-off player's input must not loop forever).
  Fresh overflow appends with the counter regardless of budget overrun
  (entity-not-found races happen under budget too). New accessor
  get_side_queue_size().
  (3) unregister_client erased _input_queues by client_id (int peer)
  while queues are keyed by player_id (String) -- dead erase. Resolves
  via _get_player_id_from_peer first; Phase 1's per-tick clear already
  bounded the leak to one tick.
  (4) Phase 6 prefetch passed a Vector2 chunk coord where
  LODManager.promote_chunk wants a String fragmenter-format chunk key
  -- latent (Markov stub returns null so the branch never ran) but it
  would corrupt LOD state under a key nothing reads back the moment
  prediction lands. Now resolves through LODManager's own
  get_chunk_key_from_position first.
  (5) Phase 5 persistence wrote a NEW key per tick ("tick:N:root")
  with NO reader anywhere (the live reads are the latest_* pointers)
  -- unbounded store growth (~1.7M rows/day at 50ms ticks). Now bounded
  by TICK_ROOT_HISTORY=100: _persisted_root_keys window, stale keys
  batch-deleted via store.delete_many (exists on the store contract and
  the memory store). Restart-time orphan keys in a real DB backend are
  a known remainder (N017 retention is owner-level design).
  test_phase4_zone_aoi extended: send_times shape check, four N014
  measurement checks (empty/early/tolerance/exceeds), and side-queue
  retry-then-drop checks driving _phase2_world_step directly with a
  ghost player's input. Validation: test_phase4_zone_aoi,
  test_world_state_projection, test_horde_rewards, test_e2e_flow,
  test_login_flow (5/5, e2e/login run the real tick loop so the new
  drain + prune execute every live tick). Hygiene: tabs only, no new
  non-ASCII, extends-first intact.
- [x] Round 25 (N017 boot cleanup built + WorldService.generate_chunk
  built for real -- Phase 6's generation step is no longer a no-op):
  (1) N017 boot policy implemented: TickService._ready calls
  _cleanup_orphan_root_keys() before the tick loop starts. The
  per-tick root history keys ("tick:N:root") are write-only telemetry
  (verified R24: no reader anywhere) and the TICK_ROOT_HISTORY window
  only covers the current session, so ANY such key present at boot is
  an orphan of a previous session -- all removed once via the store's
  SQL shim (SELECT key FROM kv WHERE key LIKE 'tick:%', filtered to
  the ':root' suffix, batch delete_many; stores without the shim skip
  best-effort). Live world_state:latest_* pointers and lookalike keys
  survive. New suite test_tick_n017_cleanup seeds three orphans + a
  lookalike + the live pointers and asserts exactly that.
  (2) WorldService.generate_chunk built: one chunk = biome
  (plains/forest/rocky/wetland), elevation, 0-4 resource nodes
  (ore/herb/wood) and 0-2 enemy pack hints with in-chunk world
  positions. DETERMINISM LAW: content derives ONLY from world_seed +
  coords via SeedChain.derive_seed (the frame's folded SHA-256
  derivation) through a per-chunk-seeded RNG -- never global RNG
  state -- so the same chunk regenerates identically everywhere.
  Records persist under world:chunk:<key> (the service's existing
  DictStore pattern) and load lazily, so reboots load instead of
  regenerate; in-session repeats return as-is. Signal chunk_generated
  for later consumers; Phase 6's _promote_generation now hits the real
  implementation (was a guarded debug no-op).
  TWO real defects the new test caught during the build, both fixed:
  (a) JSON round-trips through the kv store turn ints into floats, so
  a reboot-loaded chunk was TYPE-different from a freshly generated
  one (int 41 vs float 41.0; GDScript dict equality is type-strict).
  Fixed in the schema owner: _normalize_chunk_record coerces the
  record's integer fields on load. (b) float64 last-bit loss in JSON
  stringify/parse (15-digit reprs) broke record equality while
  field-by-field str() comparison looked identical -- fixed by
  snapping positions to the millimeter grid (_snap_mm) at build AND
  load, since short decimal forms round-trip exactly.
  test_world_chunks: generation + in-session dedup, record shape and
  in-chunk bounds, fresh-instance reboot dedup, seed law (different
  world seed AND different coords derive different chunk seeds),
  garbage-key rejection. Both suites added to DEFAULT_SET. Validation:
  test_world_chunks, test_tick_n017_cleanup, test_phase4_zone_aoi,
  test_world_state_projection, test_horde_rewards, test_e2e_flow,
  test_login_flow, frame/srv/test_world_registry, frame/srv/test_markov
  (9/9). Hygiene: tabs only, no new non-ASCII, extends-first intact.
  NEXT-ROUND CANDIDATES (unbuilt stub survey, tick/world ring):
  _markov_predict is a null stub while frame/srv already ships a Markov
  implementation LODManager.get_markov() exposes -- wiring Phase 6
  prediction to the frame Markov + record_movement feed is the natural
  next build; then _decay_effects/_regen_entities/_step_entity (Phase 2
  stubs), _pull_cross_shard_events (coordinator HLC), and
  seed_chain.update_root().
- [x] Round 26 (the prefetch loop is CLOSED end-to-end + the world
  boot now binds the lattice seed):
  (1) TickService._markov_predict built (was a null stub): resolves
  the frame Markov through LODManager.get_markov(), takes the TOP
  prediction for the player (predict_next returns probability-sorted
  {chunk_key, probability, offset} in fragmenter key format), and
  converts it to a world position at the predicted chunk's center via
  LODManager's new public get_chunk_position(). Null on every cold
  path: no LODManager, no markov, no entity_id, empty predictions,
  empty key. The movement feed already existed (LODManager
  record_movement fires on every chunk change; _update_predictions
  refreshes predictions at LOD tick rate) -- Phase 6 only consumed it
  for the first time now. The full chain is live: movement -> Markov
  -> prediction -> LOD promote_chunk(WARM) ->
  WorldService.generate_chunk.
  (2) World seed binding fixed (was the R25 limitation): WorldService
  initialize_world now calls _bind_registry_seed() FIRST -- builds the
  frame's WorldRegistry (same lazy pattern scope_service uses), derives
  the canonical "main" world's 32-byte seed from the committed
  universe constant through the nesting path, and takes its first 8
  bytes as the chunk domain seed via generate_world_from_seed
  (idempotent: early-returns when already bound; lattice-unavailable
  warns and leaves world_seed untouched). Every chunk now derives from
  the real lattice seed instead of 0, deterministically, on every
  install.
  Tests: test_phase4_zone_aoi section 10 feeds six real chunk-key
  movements through LODManager.record_movement and asserts the
  prediction returns a chunk-center world position plus all four null
  paths (null player, entity without id, player with no history);
  test_world_chunks section 6 asserts _bind_registry_seed adopts the
  registry's derived main seed and is idempotent. Validation:
  test_phase4_zone_aoi (34/0), test_world_chunks (21/0),
  frame/srv/test_markov, frame/srv/test_world_registry, test_e2e_flow,
  test_login_flow, test_world_state_projection, test_horde_rewards
  (8/8). Hygiene: tabs only, no new non-ASCII, extends-first intact.
  Note: live Phase 6 generation only fires for players WITH movement
  history (headless boot suites have no players, so e2e coverage is
  boot-path only; the unit path is what the new asserts lock).
  Remaining stubs (deliberate, vertical-slice scale):
  _decay_effects/_regen_entities/_step_entity (Phase 2 gameplay),
  _pull_cross_shard_events (coordinator HLC), seed_chain.update_root().
- [x] Round 27 (Phase 2 tick systems built + the buff/effect stack
  resurrected from a parse-broken dormant island; the new suite caught
  three product defects in the working path):
  (1) Effect stack repairs. buff.gd carried a second mid-file
  class_name (AuraBuff) -- a parse error that made the whole island
  dead weight. AuraBuff extracted to core/combat/aura_buff.gd (extends
  Buff) with its undefined refs repaired: target_entity->target,
  phantom Faction enum->Entity.Relation, costs renamed
  aura_cost_mana/aura_cost_stamina (Buff owns mana_cost/stamina_cost),
  is_active()->is_toggled_on() (clash), remove(Node) signature,
  explicit types for inference traps. buff.gd truncated to the Buff
  class only (198 lines) and de-shadowed: removed re-declarations of
  effect_name/effect_id/duration/max_stacks/shield_amount/resistances/
  target/_shield_remaining inherited from StatusEffect; target->
  target_rule (the Target enum); shield_amount_export feeds
  _shield_remaining = export * stack_count; apply/remove signatures
  aligned with the parent. aura_component.gd's orphan double-indented
  _physics_process rewritten (advances each debuff's remaining_duration
  per frame, removes at 0), AuraBuff refs via AuraBuffScript preload,
  nonexistent EffectCategory.DISEASE dropped (cleanse = POISON+CURSE),
  remove(get_parent()) at 4 sites. physics_area.gd: 3 Variant-inference
  fixes. status_handlers.gd DELETED (+ .uid): four classes illegally
  nested after a Node extends; DamageOverTime already lives in
  status_effect.gd. Island confirmed never instantiated (no
  CombatComponent.new, no aura_component referencers) -- the WORKING
  path is Entity.status_effects + StatusEffect, which is what the tick
  janitor targets.
  (2) Five Phase 2/3 systems built (R26's stub list retired):
  _decay_effects = the server-authoritative janitor (advances
  DURATION-behavior remaining_duration by tick dt, then sweeps
  expired/inactive/null slots out of every entity's status_effects via
  remove_status_effect, which reverses modifiers); _regen_entities =
  out-of-combat regen 1% max HP + 2% max mana per second through
  per-entity fractional accumulators, whole-point application so the
  50ms tick never rounds to zero; _step_entity = tick-cadence AI grudge
  decay via EnemyAI._decay_grudges (server authority at tick rate, not
  frame rate); _pull_cross_shard_events = exactly-once CoordinatorService
  drain (get_pending_events + clear_processed_events,
  _cross_shard_events_absorbed counter); seed_chain.update_root =
  SHA-256 fold of each Phase 3 root hash into the chain head (empty
  root = no-op; same fold order -> same head), chain now created
  eagerly in TickService so every fold lands.
  (3) Three product defects the new suite caught in the working path:
  (a) status_effect.gd called target.is_instance_of(EntityScript) at 5
  sites -- is_instance_of is a GLOBAL function, not an Object method,
  so every apply to an Entity errored (stealth/invisible path +
  tick_damage/tick_heal); fixed to the global-function form.
  (b) apply_status_effect's is_expired() gate rejected every effect
  configured after construction as dead-on-arrival: _init captures
  remaining_duration = duration BEFORE callers assign duration (and
  .tres loads assign exported props after _init) -- skill.gd's entire
  HoT/DoT/stun/root/slow pipeline sets duration then applies, i.e. all
  DOA; fixed with a duration setter that keeps remaining_duration in
  sync. (c) entity.gd connected the NO-ARG effect_expired signal to a
  1-arg handler -- every natural timer/tick expiry was a
  wrong-argument-count error and the effect stayed stuck in the array
  (the janitor masked it); fixed with .bind(effect).
  Tests: new game/tests/test_tick_phase2_systems.gd (24 asserts, 5
  sections: decay sweep incl. permanent-survival + null-slot sweep,
  regen accumulators, cross-shard exactly-once, AI grudge decay via
  _step_entity, seed-chain fold determinism + eager chain); added to
  the runner DEFAULT_SET. Regression: 8/8 (test_phase4_zone_aoi,
  test_world_chunks, test_tick_n017_cleanup, test_e2e_flow,
  test_horde_rewards, test_world_state_projection, frame/kv/test_t3,
  frame/kv/test_seed_chain). Hygiene: tabs only, extends-first intact,
  two stray non-ASCII comment chars normalized (seed_chain header,
  aura_component comment).
- [x] Round 28 (the dormant stack is LIVE: CombatComponent +
  AuraComponent wired into the real attack path; the wiring walk found
  and fixed seven live-path defects):
  (1) Component attach. Entity gains _ensure_effect_stack() (aura
  component always; combat component for fighters) -- attached on
  demand rather than in _ready inheritance alone, because Enemy._ready
  does not call super._ready() and a _ready-only attach would miss
  every enemy. Enemy._ready calls it with combat=true; PlayerController
  gets its own stack + a status-effect surface mirroring Entity's
  (the hitbox sweep calls target.apply_status_effect on whichever
  family it hits -- the player previously had NO surface, so every
  DoT/CC landing on a live player threw). Player DoT/HoT ticks route
  through take_damage/heal so depletion + the 3-arg health_changed
  stay correct.
  (2) Single-store delegation. Entity.apply_status_effect remains the
  canonical store (tick janitor sweeps it; StatusEffect self-manages
  timing); AuraComponent now MIRRORS it via track_effect/untrack_effect
  (classification + EventHub buff/debuff signals for the HUD) and its
  add/remove/dispel APIs delegate to the canonical owner instead of
  keeping a divergent second store. Its per-frame debuff advance is
  GONE (a frame-advance on the mirror double-drained effects that run
  their own Timers).
  (3) CombatComponent is the GATE + state machine: rate limit,
  anticheat, casting state, GCD. Costs/cooldowns belong to
  skill.execute (the component consuming too double-spent); hitbox-
  family skills route through CombatSystem.execute_skill so the sweep/
  combo/skill_executed path stays the single live one; PlayerController
  .use_skill routes through the component. Resurrecting it surfaced
  the island's full defect list: duplicate SkillSchema const (parse
  error), InventoryComponent.EquipSlot (the enum lives on Item --
  parse error), ghost `upgraded_skill` emits in _finish_channel/
  _perform_attack, nonexistent EventHub.emit_skill_used at 3 sites
  (now _emit_skill_used -> EventHub.skill_executed), Entity-typed
  params rejecting PlayerController everywhere (all duck-typed),
  double resource consumption, and a skill.execute double-hit with the
  hitbox sweep (hitbox now seeds hit_entities with the primary target
  skill.execute already damaged).
  (4) Live-path effect fixes in skill.gd/combat_system.gd: DoT/CC/
  teleport were applied TWICE (skill.execute at cast AND
  _apply_skill_effects per landed hit) -- execute() gained a
  defer_target_effects flag that hitbox casts pass, giving landed hits
  exclusive ownership (the dodge-exploit comment's intent); DoT/CC now
  route through the skill's own appliers on both paths; the broken
  DoTEffect inner class is deleted (phantom signal connect,
  _physics_process that could never run -- DoTs ticked zero damage);
  applyDoT sets a total_ticks budget (a TICKED effect with 0 budget is
  infinite by contract and the janitor never reaped it); the three CC
  creators set DURATION behavior (INSTANT default meant nothing ever
  expired a stun -- perma-CC); applyDoT/applyCrowdControl guard null
  and non-StatusEffect targets; the tick janitor advances TICKED
  remaining_duration too (backstop for stalled timers).
  (5) AuraComponent defect list: `.category` read (field is
  effect_category -- first dispel crashed), buff.stat_modifiers read
  (field does not exist -- now derived from the typed _bonus exports),
  remove_debuff emitting buff_removed, dispel removing during for-in
  iteration (collect-then-remove), and the missing
  EventHub.debuff_removed signal (added to event_hub.gd -- my own first
  draft of untrack_effect emitted it and the new suite caught the
  nonexistent signal on the first live removal).
  Tests: new game/tests/test_combat_stack_live.gd (33 asserts, 9
  sections: attach, canonical routing + EventHub probes, dispel, live
  DoT on Entity and player with real-tick expiry, perma-CC expiry,
  component GCD gate, CombatSystem-preserving melee route, defer-flag
  double-apply guard); added to the runner DEFAULT_SET. Regression:
  10/10 (phase4_zone_aoi, world_chunks, tick_n017_cleanup,
  tick_phase2_systems, combat_stack_live, e2e_flow, horde_rewards,
  world_state_projection, frame/kv/test_t3, frame/kv/test_seed_chain).
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 29 (enemies cast their kits through the live stack; the
  signal-signature sweep fixed three more latent EventHub defects):
  (1) EnemyAI skill kits. EnemyData.skills (already an exported
  Array[String] on the schema, previously unread by any runtime code)
  materializes into combat Skills lazily on first attack via
  DataService.get_skill + Skill.from_schema; _next_ready_skill picks
  the first off-cooldown castable kit entry and _perform_attack casts
  it through the enemy's CombatComponent (rate limit -> anticheat ->
  GCD -> CombatSystem sweep -> landed-hit effect appliers), mirroring
  swing-path threat on both aggro tables. The plain MWo swing stays as
  the no-kit / GCD-busy / class-locked fallback. The kit cast is a
  TRUE live-path test: AI -> component -> CombatSystem hitbox sweep
  (defer_target_effects) -> DoT lands on the target and drains
  health.
  (2) targeting_manager._on_skill_executed was typed for
  CombatSystem's object signal (Node, Resource) but connected to the
  hub's (caster_id: String, skill_id: String, target_ids) -- every
  emit on the live path threw "Cannot convert argument 1 from String
  to Object". Re-annotated to the hub shape (the handler is a stub,
  so nothing else changes).
  (3) EventHub.entity_despawned was DECLARED (entity_id: String,
  reason: String) but its only emitter (EntityService.unregister)
  sends (entity Node, SpawnMetadata) -- the declaration never matched
  reality. Fixed the declaration to the node shape its two consumers
  already assume.
  (4) minimap.gd connected EntityService.entity_despawned -- a signal
  that does not exist -- so the guarded connect silently never fired
  and despawned entities kept their minimap markers forever. Now
  connects entity_unregistered(entity, metadata) (guarded +
  is_connected, matching the file's other connects) and the handler
  pulls entity_id off the node.
  (5) The target frame's effect list was permanently dead:
  EventHub never declared entity_effect_added/removed, so the guarded
  connects in target_frame.gd never fired. The hub now declares both
  (payload: (entity_id: String, snapshot Dictionary) with id/name/
  description/is_debuff/remaining/stack/icon_path -- the UI never
  holds a live StatusEffect), and AuraComponent track/untrack emits
  them alongside the buff/debuff signals (orphans with no canonical
  parent stay silent).
  Tests: test_combat_stack_live extended to 43 asserts -- new section
  10 covers EnemyAI kit casting end-to-end (component GCD gate, DoT
  landing through the sweep, EnemyData.skills materialization, the
  schema class gate keeping a cleric skill uncastable by a classless
  enemy) and section 2 now pins both target-frame snapshot emissions.
  Regression: full runner DEFAULT_SET 53/53 in five chunks + 7/7
  extras (hud_integration, notification_toast/frame, e2e_flow,
  login_flow, entity_autoload, autoload_audit).
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 30 (the player's own buff bar was a dead display -- four
  stacked defects in the HudIntegrator binding path, found by walking
  the same signal/wiring bug class as R29):
  (1) _bind_aura_signals first tries get_node("AuraComponent"), but
  _ensure_effect_stack attaches the component with an AUTO-GENERATED
  name (@AuraComponent@N) -- that lookup never resolves for stack
  components. Now falls back to the entity's aura_component field.
  (2) The last-resort child scan compared child.get_class() ==
  "AuraComponent" -- get_class() returns the ENGINE class ("Node");
  the scan never matched anything. Now `child is AuraComponent`.
  (3) All four handlers read buff.get("id") / debuff.get("id") --
  neither Buff nor StatusEffect has an "id" key (both use effect_id),
  so every handler early-returned and the bar stayed empty forever.
  Handlers now read effect_id/duration via `in` guards (4.7.2-dropped
  default args on get() avoided).
  (4) The "rebind on local_player change" comment described behavior
  that does not exist (set_local_player emits nothing; the bind runs
  once at HUD ready) -- comment corrected to say so.
  Test hardening: the "melee damage landed" assert in
  test_combat_stack_live flaked ~5-10% of runs (95% base hit + 3%
  dodge means an unseeded single roll sometimes lands a miss-family
  outcome) -- the cast path consumes exactly one randf() synchronously,
  so the test now seeds immediately before the cast (deterministic;
  verified 2/2 consecutive runs).
  Tests: test_combat_stack_live now 47 asserts -- new section 11 pins
  the handler contract (effect_id + polarity + duration reads off a
  live StatusEffect through a stub bar) and that _bind_aura_signals
  finds the stack-attached aura component; game/tests/stub_buff_bar.gd
  added (Node-based: the typed _buff_bar property rejects RefCounted).
  Regression: hud_integration + combat_stack_live green (2/2 runs).
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 31 (THE DEATH SEAM: DoT kills now trigger the real death
  chain and pay the caster -- three defects, one ordering wrinkle):
  (1) StatusEffect._apply_tick_effect applied tick damage by DIRECT
  health mutation (maxi(0, ...)) -- a killing tick never called
  take_damage, so no death trigger (0-HP zombie enemies, unkillable,
  never despawning), no killer attribution (no XP/loot/quest credit),
  and no damage_dealt signal. Now the canonical applier routes through
  the family's own combat entry points: duck-typed
  take_damage(tick_damage * stacks, source, "periodic") /
  heal(tick_heal * stacks) covering Entity and the PlayerController
  CharacterBody3D in one path (bare targets without a combat surface
  keep the legacy mutation fallback). "periodic" bypasses school
  mitigation by design (tick budget already priced the damage).
  (2) skill.applyDoT never set dot.source -- attribution was broken at
  the ROOT: even with the reroute the kill would have paid nobody.
  applyDoT now stamps the caster onto the effect.
  (3) PlayerController's tick_occurred handler (take_damage(amount,
  null, "periodic")) became a DOUBLE-APPLY once _apply_tick_effect
  went canonical -- handler + connect removed; the source also stops
  being dropped (was null, now the effect's caster).
  (4) Ordering wrinkle found BY the new test: Enemy.take_damage
  mirrored is_dead/current_health onto the base fields only AFTER
  health_component.die() returned -- but die() emits
  EventHub.entity_died and runs the whole rewards/unregister chain
  synchronously, so is_alive() lied DURING the death chain (CombatSystem
  sweeps and kill-credit checks could see a corpse as alive). The
  mirror now happens before die(), matching Entity.die's own
  set-then-emit convention.
  Tests: test_combat_stack_live now 54 asserts -- new section 12 pins
  the whole seam ("DoT kills an enemy and the caster gets credit"):
  source carried on the effect, real death flow with is_dead set at
  signal time, node freed by the despawn path, kill_rewarded crediting
  the caster, XP > 0, EntityService unregistration. Test-side lessons:
  the Enemy family's death chain FREES the node (post-wait asserts
  must capture state inside the signal -- the first draft poked a
  freed object and the script error silently aborted the section while
  still exiting 0), and EventHub.entity_died -- not the base Entity.died
  -- is the authoritative death event for the health_component family.
  Regression: 11/11 (tick_phase2_systems, combat_stack_live, e2e_flow,
  hud_integration, login_flow, tick_n017_cleanup, world_chunks,
  frame/kv/test_t3_dedup, kill_rewards, horde_rewards,
  skill_academy_live).
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 32 (live WASM probe: the harness works, the sandbox can't
  render -- everything short of engine boot verified, tooling banked):
  (1) Rebuilt web/game.pck + game.pck.hash locally with the CI recipe
  (--export-pack "Web" + sha256sum) so the served export embeds
  R29-R31 content (CI had not refreshed yet at fetch time). Content
  proof: res://tests/stub_buff_bar.gd -- a path that exists only since
  R30 -- is in the pack's embedded file list (3248 res:// entries).
  Script BODY text does not grep in a Godot 4 pck (binary tokens) --
  source-string greps are a false-negative trap.
  (2) scripts/serve_web.py committed: stdlib static server for web/
  with the COOP/COEP headers the THREADED Godot web build requires
  (the shell checks window.crossOriginIsolated; a plain http.server
  sends neither header and the engine refuses to start), plus wasm/pck
  MIME and the injected PORT. Verified live: 200 + both headers +
  application/wasm.
  (3) The managed preview currently runs the Vite dev server (no
  cross-origin headers, would never boot the engine) and the
  freebuff-preview set CLI rejects every port with "must be an integer
  from 1024 to 65535" (even valid ints / both argument orders / with
  --help) -- CLI quirk to revisit; serve_web.py is the manual workaround.
  (4) Boot probe harness (playwright-core 1.63 + the pre-cached
  chromium-1243, /tmp/wasmtest/test.js, not committed): drove the real
  export headless. VERIFIED LIVE: cross-origin isolation achieved,
  index.html shell runs, canvas created, 12MB pck fetched with zero
  failed requests, and the shell's feature gate correctly fails closed
  with its friendly "missing required features: WebGL2" message.
  BLOCKED in this sandbox: ANGLE's Vulkan/SwiftShader backend cannot
  initialize (vk_renderer.cpp Internal Vulkan error -3; explicit
  VK_ICD_FILENAMES, vulkan/swiftshader/gl backends, and headless shell
  vs full chrome all tried) -- no WebGL2 headless means the ENGINE
  itself never starts here.  In-browser verification of gameplay needs
  a real GPU-capable browser (user's machine / GPU runner) against
  serve_web.py.
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 33 (LIVE WASM BOOT ACHIEVED: engine boots and ticks in
  headless chromium; three real shell defects fixed on the way):
  (1) Sandbox GL unlocked with user-authorized system installs:
  mesa-vulkan-drivers (lavapipe) gave ANGLE's SwiftShader backend a
  working Vulkan ICD -- the R32 "Internal Vulkan error -3" vanished.
  The rest of the recipe: Xvfb + chrome HEADED (headless=new still
  killed the GPU process even with desktop GL), plain launch flags
  (--no-sandbox --disable-dev-shm-usage --disable-gpu-sandbox
  --enable-unsafe-swiftshader; forcing --use-angle=swiftshader was
  the thing that BROKE it), playwright-core 1.63 + cached
  chromium-1243. Probe: Godot banner prints, TickService/LODManager
  phase timings stream every second -- the live game in WASM.
  (2) web/index.html shell defects found and fixed by the probe:
  (a) startGame's promise REJECTS after boot (the worker-pool handoff
  aborts the main thread's pck/wasm reads -- net::ERR_ABORTED) and
  the catch painted "Failed to load" over the LIVE game; the catch
  now ignores post-boot/abort rejections (engineBooted flag set by
  the engine banner via onPrint, which also hides the loader and
  focuses the canvas, and re-logs to preserve the default print
  bridge). (b) GODOT_CONFIG.fileSizes hardcoded the OLD pack size
  (4.67MB vs 12.16MB actual) and nothing ever updates it -- progress
  math lied; the real HEAD sizes already override at runtime, plus
  the static value is corrected. (c) Verified CLEAN, not a bug: the
  .hidden overlay toggles work (style.css rules exist) -- my probe's
  wrong .css MIME type made Chrome parse ZERO stylesheet rules,
  which is a harness lesson, not a shell defect.
  (3) Probe ecosystem: /tmp/wasmtest/{test,overlay2}.js banked; the
  e2b preview (Vite on 3000) already sends COOP/COEP and serves the
  export under /web/ with correct MIME -- the user's browser (real
  GPU) should boot it directly from that URL with the refreshed pack.
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 34 (DIRECTION: the canonical Accessibility + Agent-Action
  layer, designed on an engine fact discovered this round):
  (1) ENGINE FACT (verified on our 4.7.2 binary with a live probe):
  accessibility_name / accessibility_description are REAL Control
  properties -- Godot 4.5 integrated AccessKit; the stale
  "these properties do not exist" comments in ui_styles.gd predate
  it and sent the old a11y attempts down the wrong path.
  (2) labs/prd-accessibility.md written: ONE annotation set on the
  Controls (accessibility_name = the imperative action,
  accessibility_description = the consequence, FOCUS_ALL everywhere)
  feeding FOUR consumers through one tree -- desktop AT (AccessKit),
  web AT via AccessKit's web adapter, agents/probes via a new
  A11yService.snapshot()/dump() (walking, never side-car), and the
  in-world extension through InteractionLayer-shaped entity entries
  with the same snapshot schema. Non-goals locked: no custom reader
  protocol, no agent backdoor around the input pipeline, no per-frame
  scans, no third id namespace.
  (3) Graveyard inventoried with dispositions (PRD sec 8): the mangled
  nname/ndescription find-replace remnants, the 2-scene
  accessible_string keys (invented property), the F13 mapping with no
  consumer, the three per-menu _cycle_focus copies (fold into
  A11yService), the DebugOverlay walker (KEEP -- seeds the snapshot
  walker), the reverted [CS] dumps (superseded). Five landing rounds
  planned, each green; round 1 rewrites the R33 probe against the
  contract (snapshot-driven, zero coordinates).
  (4) Probe-state note: R33's driving run reached char select fully
  (guest login, create-new at its true center (542,640), species card
  click, classes dump, class click, Enter World, char:linked) but the
  world-build wait did not complete inside the probe deadline; also
  discovered the web build self-detects InputManager Mode=2
  Mobile=true. That probe is superseded by PRD round 1 -- no more
  pixel archaeology.
  (5) pck determinism bonus: after reverting the [CS] hack, a fresh
  --export-pack reproduced byte-identical web/game.pck (hash
  651d5598... unchanged) -- exports are deterministic, so pack diffs
  in CI mean real content changes only.
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 35 (PRD-ACCESSIBILITY ROUND 1 SHIPPED: A11yService + menu
  annotations + the snapshot-driven probe -- the agent navigated the
  game BY ACTION NAME, zero coordinates):
  (1) A11yService autoload (core/services/a11y_service.gd, registered
  early in project.godot): walking snapshot() of actionable Controls
  (BaseButton/LineEdit/ItemList/Slider) in tree order, entry =
  {path(/root-relative), kind, action, detail, rect, focused,
  disabled, visible}. Action label priority: annotated
  accessibility_name > button text > placeholder > node name; detail
  = accessibility_description. BootLoadingLayer family excluded.
  focus_next/prev/index + activate(index)/activate_by_action(label)
  (buttons emit pressed; disabled refuse; line edits focus).
  dump() prints [A11Y] JSON lines; the service ALSO auto-dumps on
  actual actionable-set changes (label-signature gated, so world
  churn cannot spam) -- the layer announces every screen by itself.
  Debounce fixes found by tests: mark-dirty only, NEVER reset the
  0.25s window on mutation (TickService churn starved a reset-style
  debounce forever); /root-relative paths (current_scene-relative
  resolution broke in script mode and scene swaps).
  (2) UIStyles.apply_accessibility now writes the REAL AccessKit
  properties (verified exist on 4.7.2) -- the stale "do not exist"
  comment corrected in place; create_accessible_button annotates;
  login.tscn/main_menu.tscn renamed accessible_string ->
  accessibility_name (6+2 keys, the invented property is gone).
  lobby/character_select annotate their buttons in _ready; species
  and class cards name the CHOICE ("Choose Human", "Play Warrior")
  not the widget; the three per-menu _cycle_focus/_trigger_tab know
  how to cycle focus is now ONE implementation on A11yService
  (PRD sec 8 disposition).
  (3) test_a11y_service.gd 13/0 (new in runner DEFAULT_SET): discovery
  counts, label fallbacks, annotation round-trip, rect/state flags,
  focus walk, activate-by-name, disabled refusal, dump, debounced
  focusables_changed + late-arriving actionables. Regression green:
  combat_stack, e2e_flow, login_flow, hud_integration, world_chunks.
  (4) LIVE ACCEPTANCE under xvfb (playwright-core + chrome headful,
  software GL): the [A11Y] stream announced the menu unprompted; the
  probe clicked Start/Guest/Create New/Choose Akkan/Play Attacker/
  Enter World purely by reported rect centers, verified each hop via
  the game's own logs, reached character-linked + ENTERING PLAY, 53
  actions announced over the journey, pause/resume worked in-world.
  The world-build registration mark hit the wasm stdout-batching
  window (2-4fps software GL) but PNG forensics on the screenshots
  shows the world rendered and stayed alive through the wait.
  (5) Product fix along the way: GameManager's scene-swap wait loop
  was 600 FRAMES -- minutes of stuck loading screen on low-fps
  devices; now a 90-second wall-clock cap with a loud timeout error.
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 36 (PRD-ACCESSIBILITY ROUND 2 SHIPPED: the HUD and
  in-game surfaces are actionable by name -- dynamic populations
  annotate themselves at assignment):
  (1) Service upgrade: an EXPLICITLY annotated control is actionable
  regardless of kind (`accessibility_name` present and non-empty),
  while unannotated non-buttons stay invisible (20-assert suite pins
  both directions). activate() synthesizes a REAL press+release
  through the viewport's GUI input path for annotated non-buttons
  (skill slots are PanelContainers driven by gui_input buttons/
  slots): push_input(event, true) -- the in_gui flag is REQUIRED in
  headless/script mode (plain push_input drops the event; found by
  the suite). A hit-test guard refuses clicks the pointer path would
  deliver elsewhere (stale overlays can never swallow an agent tap).
  (2) Surfaces annotated: ActionBar page buttons ("Show skill bar N")
  and slots at update_slot time ("Cast <Skill>" + mana cost + key,
  empty slots self-describe); QuickAccessBar slots at set_slot_item
  ("Use <Item> xN"); virtual joystick touch cluster ("Attack",
  "Jump", "Dodge", "Interact", "Use ability N" -- the short ATK/JMP
  labels are agent/reader meaningless); DialogUI Continue ("Continue
  dialog") and reply choices ("Say: <line>"); RespawnUI option
  buttons ("Respawn: <destination>") + the skip action; the loading
  overlay restores MOUSE_FILTER_STOP while showing and hands the
  pointer back (IGNORE) on hide -- a hidden full-rect STOP backdrop
  was a latent pointer-swallowing window during handoffs.
  (3) Test lessons (suite 20/0): synthesized clicks need a REAL
  rect (zero-size contains no point), and Container children ALWAYS
  fill their parent -- a sibling added to the same PanelContainer
  stacks over the slot and (later in tree order) legitimately wins
  pointer delivery; fixtures must not overlap their own targets.
  The loading-layer hijack from the first draft was a phantom (the
  fixture button was never actually hidden); the real LoadingUI
  discipline fix stands on its own merits.
  (4) Regression: 5/5 (a11y_service 20/0 in DEFAULT_SET,
  combat_stack_live, e2e_flow, login_flow, hud_integration). Live
  probe re-verified the full journey on the repacked pck (dec1ccb4
  ...): actions arrive mid-journey (lobby/species/class announced
  live), all hops verified, in-world pause/resume working. The known
  sandbox limitation persists: world-build log marks land outside
  the wait window at 2-4fps software GL stdout batching.
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 37 (PRD-ACCESSIBILITY ROUND 3 SHIPPED: the world is
  actionable -- entities announce and respond by name; one product
  bug found by the bridge and one more by the take_damage audit):
  (1) In-world bridge on A11yService: _append_world_entries walks
  the entity family (Entity codes 2=ENEMY, 4=NPC, 1=PLAYER) inside
  40m, skipping dead and self; verb by entity (npc_data -> "Talk",
  ENEMY -> "Attack", else "Inspect"); detail "Xm away, level N";
  entries are kind=="entity" with the path law world/entity:<id>.
  _entity_rect camera-projects with a distance-scaled centered
  fallback (no camera position leakage into paths); _world_sig
  signature-gates the announce so world churn cannot spam (same
  label-signature discipline as the menu walker); _resolve_world_
  entity -> EntityService.get_entity; _set_game_target ->
  TargetingManager.set_target (7-arg form).
  (2) activate() dispatches kind=="entity" BEFORE control
  resolution: Attack = set target THEN player.use_skill(0) (the
  player's real attack path, not a damage shortcut); Talk =
  entity.interact(player) with the _on_interact fallback; Inspect
  = set target (the HUD panel does the describing).
  (3) THE PRODUCT BUG (found by the probe, headline of the round):
  Enemy.take_damage mutated only health_component.current_health
  and never mirrored back to the base Entity field -- base
  current_health stayed 100 forever, so anything reading
  enemy.current_health (CombatSystem damage checks, HUD binds,
  probes) saw permanently full-health enemies. Evidence:
  take_damage(10) on an armor-5 wolf left hc=91 but field=100.
  Fix: clamp into the component then mirror onto the field before
  the health_changed emit. Full-path proof: use_skill ->
  CombatSystem sweep took the wolf 100 -> 46 through the real
  attack path.
  (4) take_damage audit (all six implementations, same dual-store
  class): entity.gd and PlayerManager are single-store and
  consistent; guard.gd extends enemy.gd so the fix covers it;
  player_controller.gd HAD the miss -- take_damage emitted the
  stale local current_health (the component owns the damage path),
  and the add_experience level-up bump (+10 max health, "mirroring
  PlayerManager") never synced into the health_component, so the
  per-level HP never actually applied in combat. Fixed both: emit
  component truth; sync the bump into the component.
  Test lesson: the level-up block's pre-existing glued `if` on the
  comment line was a LATENT PARSE ERROR sitting in the tree (cat -A
  forensics -- a trailing comment swallows the statement); found
  only because the batch re-ran after the edit. Split it, scanned
  all six touched files for the same artifact class, re-ran green.
  (5) Verification: test_a11y_service extended with the R37 world
  section (fake player_controller as PlayerManager.local_player,
  Enemy "a11y_wolf" registered in EntityService; asserts announce/
  verb/kind/rect and that activate-the-wolf deals REAL damage) --
  25/0. Regression batch 6/0: a11y_service, combat_stack_live,
  kill_rewards, horde_rewards, e2e_flow, hud_integration.
  (6) Probe-state note: the live WASM journey already covers the
  in-world pause/resume hop (53 actions announced, R35/R36); the
  world-build registration mark still times out at 2-4fps software
  GL (documented sandbox limitation). The suite now proves the
  in-world bridge directly, so no probe re-run was required.
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 38 (PRD-ACCESSIBILITY ROUND 4 SHIPPED: engine AT support
  on, the palettes audited against WCAG with two real fixes, and the
  probe rig moved into the repo):
  (1) The rig first (committed as 06f13ed): scripts/web_probe/ --
  probe_boot.js (boot smoke) + probe_a11y.js (the snapshot-driven
  journey, extended with the round-3 in-world entity step) +
  package.json (playwright-core) + README.md carrying the R32/R33
  sandbox GL recipe (xvfb + mesa-vulkan-drivers/lavapipe; the flags
  that work and the one that broke it). Paths env-driven
  (PROBE_CHROME/PROBE_PORT/PROBE_WEB); the harness no longer lives in
  /tmp. Verified live in-sandbox: syntax + install + a boot-smoke
  PASS through the committed files (engine banner, TickService/
  LODManager streaming; the two ERR_ABORTED reqfails are the
  documented post-boot worker-pool handoff, not failures).
  (2) Engine AT support: accessibility/general/accessibility_support=0
  (Auto -- active when a screen reader is detected) pinned in
  project.godot. Verified the setting exists on our 4.7.2 binary
  (strings) and read the enum from the docs (Auto=0/Always=1/
  Disabled=2); Always was rejected deliberately (upstream reports of
  AT-triggered log spam and focus side effects). PRD's "(Auto)"
  honored.
  (3) High-contrast audit: new game/tests/test_a11y_contrast.gd in
  the runner DEFAULT_SET computes WCAG 2.x ratios for the pairs the
  UI really renders (4.5:1 normal text AA 1.4.3; 3.0:1 for status
  indicators under 1.4.11) and prints the table as the audit record.
  TWO REAL FIXES: text_disabled 0.5 -> 0.55 (was 4.35:1, below AA --
  Synmergia's disabled states carry actionable hints so their text
  must be readable) and the panel border 0.3/0.3/0.4 ->
  0.42/0.42/0.5 (was 2.10:1, below 1.4.11's 3.0 for component
  boundaries; now 3.33:1). The HIGH_CONTRAST palette's "WCAG 4.5:1
  compliant" comment is now proven, not trusted (8.3-20.4:1 across
  its pairs); the mint CTA's dark-on-green design validated at
  8.22:1; offline status 3.01:1 within 1.4.11.
  (4) Mobile/tablet focus review (the PRD's sec-8 flag): InputManager
  self-detects web+coarse-pointer as mobile (Mode=TOUCH) but nothing
  in the touch path gates keyboard focus or the a11y walk -- the R36
  touch-cluster annotations ride the same actionable snapshot, and
  A11yService.focus_next/prev work identically in TOUCH mode. No
  defect found; PlayerConfig "touch_controls" remains the override.
  (5) Probe step (OS screen reader smoke + manual web pass): NVDA
  cannot run in this sandbox -- recorded as the manual desktop
  acceptance step; the web half is tooling-complete via the
  committed rig. Verification: 8-test regression batch 8/0
  (a11y_service, a11y_contrast, combat_stack_live, kill_rewards,
  horde_rewards, e2e_flow, hud_integration, login_flow -- login_flow
  doubles as the project.godot boot canary). Test lessons: `pass` is
  a reserved word in GDScript 4 (renamed in the audit test), and a
  const needs preload, not load (4.7.2 constant-expression rule).
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 39 (PRD-ACCESSIBILITY ROUND 5 SHIPPED: the graveyard is
  empty -- every sec-8 disposition executed, PRD status flips to
  SHIPPED):
  (1) Scene keys: login.tscn still carried six invented
  accessible_description keys (R35 renamed accessible_string but the
  description keys were missed) -- renamed to the real
  accessibility_description; the descriptions were dead property
  writes before, now they are live AccessKit data.
  (2) ui_panel.gd: create_accessible_slider/dropdown/checkbox/
  line_edit all carried the "set if available in this Godot version"
  stub with the property writes commented out -- wired through
  UIStyles.apply_accessibility (the real properties, one
  implementation); signatures unchanged so callers keep compiling.
  (3) Focus folds complete: character_select.gd was the last menu
  with its own _cycle_focus (back/play buttons) -- now delegates to
  A11yService.focus_prev/focus_next and the copy is deleted; login.gd
  orphaned _trigger_tab removed (its caller was replaced in R35).
  Grep confirms no per-menu focus-cycle implementation remains
  outside A11yService.
  (4) F13 disposition executed: the keycode mapping stays
  (forward-compatible, unconsumed) and the NEW agent-only JS hook
  ships in web_input_bridge.gd -- on web, _ready registers
  window.__synA11yDump via JavaScriptBridge.create_callback; calling
  it from the console forces A11yService.dump() ([A11Y] lines to the
  console the probes already parse). Web-guarded; desktop/headless
  never touch JavaScriptBridge.
  (5) Docs: AGENTS.md carries the one-paragraph note (dated
  2026-10-05) and the PRD status line flips to SHIPPED with the
  round map. Rows verified closed: nname/ndescription remnants gone
  (grep hits were "Unnamed" substrings), [CS] dumps never landed,
  DebugOverlay walker kept per disposition, InputManager mobile
  reviewed in R38.
  (6) Verification: 8-test regression batch 8/0 (a11y_service,
  a11y_contrast, combat_stack_live, kill_rewards, horde_rewards,
  e2e_flow, hud_integration, login_flow -- the menu/panel edits are
  exercised by login_flow/e2e_flow/hud_integration; the bridge
  autoload boots in every test).
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 40 (POST-PRD LIVE ACCEPTANCE: the committed rig found and
  fixed three real defects -- a pack-staleness bug, a silently dead
  agent hook, and the wasm print bridge):
  (1) pack_web.sh had three defects: BASH_SOURCE is unset under dash
  (the repo's own `sh ./scripts/foo.sh` convention) so the root
  misresolved to the shell's parent and every cd failed; `&>` is a
  bashism that misparses under dash; and it never refreshed
  game.pck.hash -- the cache-buster the shells fetch ("CI rewrites it
  on every content change"), so local repacks shipped stale. Fixed
  ($0 resolution, POSIX redirects, sha256 step); live-proven: the
  shell fetched the NEW hash (?v=53d3fb15...) after the first repack.
  (2) The round-5 agent hook was a SILENT NO-OP on web: the
  create_callback result lived in a _ready local, got collected, and
  left a dead function object on window (typeof "function", calls
  vanish without error). Fixed by retaining it Godot-side for the
  bridge's lifetime. AND the print bridge swallows or indefinitely
  holds lines issued from inside a JS callback (forced dumps never
  surfaced through console across two calls and 45s of polling, while
  frame-context auto-dumps do) -- the hook now also hands the
  snapshot to JS directly (window.__synA11yLast, the same direction
  as the proven drain() polling), so agents get the JSON in the same
  JS turn they call the hook.
  (3) Live verification on the rebuilt pack: boot smoke PASS; full
  menu journey 7/7 hops by action name, 69 actions announced, zero
  SCRIPT ERROR/pageerror through every round 4-5 change (AT setting,
  renamed scene keys, wired factories); world rendered (143KB PNG)
  with the registration mark outside the window (the documented 2-4fps
  stdout-batching limitation, unchanged); hook probe PASS --
  __synA11yLast carries the live snapshot (Start playing, path/rect/
  detail) in the calling turn.
  (4) Lessons for the rig: the hook is screen-agnostic (the menu alone
  exercises it -- no world leg needed); wasm stdout batching makes
  console-line counting an unreliable oracle inside 45s (use the
  JS-visible return channel instead).
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 41 (THE RIDING LAYER: one ledger for land, water, sky, and
  space -- owner asked for a riding service tying land+water mounts and
  flexible for sky+space, plus three elite sky mounts, "the hardest
  mounts to acquire by far"; the S14.7 slot folded into this slice):
  (1) RideService (game/core/services/ride_service.gd, NEW autoload
  after FerryService) is the stamping seam, not a screen: ownership is
  persisted truth (DictStore ride_service/mounts/<player_id>, the
  FerryService wake idiom; grant refuses unknown mounts and duplicates
  -- soulbound is the default posture), riding is session truth (the
  _active book, summon again next login like the ferry manifest), and
  the service stores NO numbers -- summon resolves the mount's
  MovementProfile through DataService.get_mount_movement_profile (the
  one derivation) and stamps the anticheat via the NEW
  AntiCheatService.set_profile_limits(profile_id) (resolves through
  DataService.get_movement_profile, stamps through the existing
  _limits_from_profile x2.5/x2.5/x2.0 multipliers; unknown -> false).
  Dismount restamps movement_standard (humanoid 25/25/110).
  MountKind.SPACE added -- space mounts ride the identical path, one
  profile .tres away, no new service code.
  (2) The water handoff is one call: RideService.water_stamp_for(
  player_id, band) -> ride (wading, any mount) / dismount (non-swimmer
  past the waterline: dismiss + restamp, the S12 glider law mirrored)
  / swim (the S14.6 stamp payload: speed, squeeze grace, crush bonus,
  current immunity) / none (naked-swimmer paths run unchanged). The
  band laws live in exactly one place.
  (3) The elite three (FLYING, cost 0, soulbound, locomotion_class 2
  like movement_aerial): mount_storm_lancer (DROP, lvl 50,
  movement_sky_lancer sprint 21 jump 16 gravity 8),
  mount_skyreef_soarer (QUEST, lvl 55, movement_sky_soarer sprint 17
  air_control 1.0 gravity 7, hitbox_sky_large NEW),
  mount_moonwing_moth (EVENT, lvl 50, movement_sky_moth sprint 15
  gravity 5 turn_grip 0.9). Acquisition difficulty lives in the DATA
  (source/level/drop rarity) -- the service is the ledger, never the
  gate.
  (4) The 52.5-ceiling lesson: the lancer's sprint 21 stamps a cruise
  ceiling of 21 x 2.5 = 52.5 m/s (the anticheat SPEED_LIMIT_MULTIPLIER
  applies to mount profiles exactly as it did to the water ray's
  9 -> 22.5) -- sky profiles get deliberate headroom, and every future
  sky profile chooses its number KNOWING the stamp multiplies it.
  (5) Verification: probe_riding.gd NEW, 33 checks 0 failures, in the
  runner DEFAULT_SET after probe_water_mounts -- declarations/elite
  law/hitbox refs, ledger persistence round-trip + duplicate refusal,
  summon stamps (lancer 52.5/40.0, dismiss -> 25.0), the full water
  handoff matrix (ray swim stamp 9/6, glider immune=true, wyrm
  crush+30, plains_runner wades band 1 then dismounts band 3 with the
  book cleared + restamp, no-mount "none"), SPACE == 3, revoke
  dismisses. Family batch 10/0 (riding, water_mounts, ocean, swim,
  ferry x2, naming lint, movement profiles, combat, e2e).
  (6) Docs: labs/prd-mounts.md NEW (status SHIPPED; the three laws,
  the stamping seam, the elite table, space-already-lawful; the seams
  NOT built are named: 3D saddle physics, mount UI, grant wiring).
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 42 (MOUNTS GET REAL: the cliff law lands, the warden takes
  the sky, the rider is told -- owner: "further craft the mount systems
  and make them more real. Gms need a sky mount to get around too"):
  (1) The S12 cliff law was DECIDED but unwired -- glider_state carried
  MOUNT_DISMOUNT_ON_FALL with the note "implementation lands with the
  mount-riding system." It landed: RideService.fall_stamp_for(
  player_id, falling, altitude) -> none / ride / bail. Bail gate = the
  glider's own deploy gate (ONE number, GliderState.DEPLOY_HEIGHT_METERS
  = 6.0 -- hops stay rides); only GROUND mounts bail (MountData.
  bails_on_fall() -- sky mounts fly, swimmers swim, space is space); a
  bail dismisses (whistle, humanoid restamp) and the rider keeps the
  fall, glider usable from there. Callers feed it per tick while
  airborne, exactly like water_stamp_for while wet.
  (2) The GM door: MountSource.GM (5) is the acquisition door that is
  not a door -- grant_mount is FAIL-CLOSED for it (an unknown rider is
  not a warden) and GameManager.player_entered_world auto-answers a
  warden's entry with the whistle (idempotent; the ledger refuses
  duplicates). RideService also keeps session character truth (_chars)
  from the same hook -- the seam that makes the level gate real.
  (3) mount_gm_skywarden ("Skywarden", FLYING, level 1, cost 0,
  soulbound, source GM) rides movement_gm_sky -- sprint 28 (70 ceiling
  = 28 x 2.5, fastest body in the sky), jump 22 (55), gravity 5,
  air_control 1.0, sprint_stamina_cost 0 (the Warden does not tire).
  GM tooling, not a leaderboard entry.
  (4) The level gate closes: required_level was declared in the first
  schema and enforced NOWHERE. summon enforces it for every rider the
  service knows (world-entry truth); unknown riders (probes, admin
  paths, agents) stay trusted service-level callers -- documented,
  deliberate: the SOURCE gates acquisition, the summon gate is the
  second lock on the same door. Probe covers both sides (10 refused,
  50 summons).
  (5) The rider's voice: NotifKind.MOUNT_SUMMONED / MOUNT_DISMISSED
  through the typed pipeline ("You summon the Storm Lancer" / "The ...
  returns to its whistle"), explicit INFO/NORMAL mappings, dedupe keys
  per rider+mount. The service announces RIDING only -- acquisition
  announcements belong to whatever grants.
  (6) Verification: probe_riding 33 -> 53 checks, 0 failures (GM door
  incl. fail-closed grant + auto-grant via the real
  notify_player_entered_world path; cliff matrix incl.
  bail/hop/sky-carries/none; level gate both sides); family batch 10/0
  (riding, water_mounts, ocean, swim, ferry x2, naming lint, movement
  profiles, combat, e2e -- e2e boots the world-entry hook the service
  now listens on); notification pipeline 3/0 (frame, toast, hud -- the
  two new kinds ride it).
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 43 (THE WARD GATE: the hard gate registry and the breach
  embargo -- owner: "if species 0 gm AND holds mount_gm_skywarden it
  opens gates and stuff. We should make a tres or inventory for max
  Gms, skywardens, or other admin things. Hard gate, defense in depth.
  You could also put items here in a breach ... to temporarily prevent
  their drops or dupes"):
  (1) The Skywarden is a CAPABILITY TOKEN. WardGateService (NEW
  autoload after RideService) holds the admin keys in one registry
  (data/gates/, gate_ prefix, filename == id; gate_warden_keys ships
  role 0 + the Skywarden, opens admin_shell/warden_tools, embargo
  SHIPS EMPTY) and the breach embargo in the same place.
  (2) Defense in depth is the law: every key signal must match (role
  truth AND every token mount AND every token item); fail-closed
  everywhere (unknown rider, unknown gate, missing InventoryService
  lookup = closed); role resolves through CharacterData.is_gm_class
  from the service's OWN session book -- kept independent of
  RideService's (two books, same hook: poison one, the other still
  gates); the mount token is itself independently verified because
  the GM source door is fail-closed. can_open/gate_open_for public;
  the item leg rides the AGENTS defensive-helper pattern and upgrades
  automatically when InventoryService grows a player-level lookup.
  (3) The breach embargo has two layers, one check: the .tres
  embargoed_items (standing) + the runtime ledger (DictStore
  ward_gate/embargo/<item_id> with reason/by/optional expiry; expired
  rows erase themselves on read -- "temporarily" is a contract;
  lift_embargo by hand). ADMIN_ALERT + loud logs; reasons are admin
  truth, never shown to players.
  (4) The bite is real: LootService asks allow_drop at CREATION (the
  rolled drop never materializes) and at PICKUP (pending loot dies at
  the gate, loudly logged). The duped ore stops existing as a drop
  the moment it enters the gate -- no restart, no deploy.
  (5) Lessons: a brand-new class_name is invisible to --script mode
  until the global class cache regenerates (godot --headless --path
  game --import; the cache is gitignored, CI regenerates its own) --
  DataService's typed get_gate cascaded until the scan ran; and typed
  Array[String] exports reject untyped literals at runtime (even [])
  -- the probe builds typed locals before assigning.
  (6) Verification: probe_ward_gate NEW, 31 checks 0 failures, in the
  runner DEFAULT_SET after probe_riding (registry law; every gate leg:
  unknown closed, non-warden closed, warden open, revoke-closes,
  item leg fail-closed, in-memory-gate proofs needing no test-only
  data; the full embargo cycle: persist, live list, self-erasing
  expiry, lift, lift-twice no-op; the loot seam end to end: embargoed
  ore filtered from a drop, fully-embargoed drop spawns NOTHING, lift
  restores the flow). Family batch 14/0 (riding, ward gate, water
  mounts, ocean, swim, ferry x2, naming lint -- the gate_ category
  joined the audit, movement profiles, combat, e2e, ground loot,
  kill/horde rewards -- the loot seams exercised).
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 44 (THE FIRST SPACE MOUNT: the Vesper answers a whistle --
  owner: "Go free spirit, stay in bounds with our physics/reality frame
  and a11y human/agent controller layer. Build whatever you like,
  you're the mystery hehe"):
  (1) prd-mounts.md sec 5 has promised since R41 that "space mounts
  ride the identical path, one profile .tres away, no new service
  code" -- nothing had ever called the bluff. The mystery gift is the
  collection notice: mount_vesper_whale ("Vesper", MountKind.SPACE,
  EVENT-sourced like the moth, level 60 -- the highest wall yet, cost
  0, soulbound, hitbox_sky_large) rides movement_leviathan (sprint 24
  = 60 stamp ceiling, fastest PUBLIC body in the sky; jump 24;
  gravity 2.5, terminal 40, turn_grip 0.6, no stamina -- the PROFILE
  owns the gravity, which is the entire physics story; nothing in
  code knows this mount is special).
  (2) The one reserved line: DataService's kind default grew its SPACE
  case (3 -> movement_leviathan; was the quadruped catch-all -- sec
  2's "its own class when space mounts land" is now true). Explicit
  movement_profile_id still wins; the one derivation is untouched.
  No RideService changes: sec 5 was not a promise, it was a schedule.
  Lesson earned mid-round: movement_lunar was ALREADY shipped canon
  (S16.4's Lunar Settler humanoid -- the per-world low-gravity
  archetype); the first write clobbered it and the kind default
  squatted its id. Repaired before push: the Settler restored byte
  for byte, the mount profile took its own id (movement_leviathan),
  and the lesson is now law -- git log a data id before writing
  over it, even when every test stays green (no test asserts an
  archetype's numbers).
  (3) The mystery stays in bounds: the Vesper swims the dark between
  the world's curve and the Watched Stone (the moth's crater-garden
  canon) -- the spherical frame's above-the-sky stratum, lawful
  because the lunar profile says so. It does not bail on falls
  (space is space: "it remembers the way down"), wades, and is
  dismissed at the waterline (space is not a swimmer).
  (4) The a11y controller layer is a FIRST-CLASS leg of the probe: the
  Vesper's summon is asserted through the typed pipeline via the
  NotificationService.notification_sent signal -- player-directed,
  MOUNT_SUMMONED -> INFO, message "You summon the Vesper". Human and
  agent hear the dark arrive identically: typed, mapped, addressable.
  No new NotifKind needed; riding already has a voice.
  (5) Verification: probe_riding 53 -> 67 checks, 0 failures (load/
  declarations, explicit profile + blanked-duplicate kind default,
  gravity law, anticheat stamp 60, wade/waterline, no-bail fall,
  level gate both sides 59/60, typed-pipeline toast); family batch
  8/0 (naming lint -- mount_ + movement_ prefixes, movement profiles,
  anticheat, hitbox, notification frame + toast, resource scan,
  riding).
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 45 (THE SEAMS LAND: the body takes the saddle, the stable
  opens its doors, the shop takes gold -- owner: "Awesome work! Ty!
  Let's keep going, buikding out runtime 3D saddle physics, mount UI,
  and grant wiring remain named seams"):
  (1) prd-mounts.md sec 6 named three seams and sec 8 recorded them
  still open; all three land this round by existing idioms -- no new
  service, no data schema, no --import regen. The body adopts the
  mount's movement profile (the S16.4 law-adoption shape, now for a
  quadruped); the stable is a UIPanel island (the BankUI shape); the
  shop is RideService.purchase_mount, a gate chain ending in the
  existing grant door.
  (2) The body: RideService grew mount_summoned/mount_dismounted
  signals -- ONE sync path, emitted where _active is written, so the
  player can never drift from the service's ledger. On summon,
  globe_player adopts the profile's walk/jump/gravity; the live
  gravity is captured and restored on dismiss -- the summit test
  binds the body to the moon (6.0), summons (adopts 22.0), dismisses,
  and the captured 6.0 comes home. Sprint gear is SADDLE_SPRINT_SCALE
  0.6 under the existing x2.5 anticheat ceiling (plains runner
  13.5 x 0.6 = 8.1 against 33.75). SADDLE_LIFT 0.4 rides under the
  0.55 perch law, so a standing mount never trips the perch gate.
  fall_stamp_for is fed every tick in the glider branch, with cliff
  bail EXECUTED (radial velocity damped) -- the saddle rides the
  frame's laws, not around them. F (dismount, physical_keycode 70)
  taps out before the climb chain.
  (3) The stable: mount_ui.gd extends the UIPanel base and resolves
  RideService BEFORE super._ready(); IslandRegistry carries it as
  "mounts" (TRIGGERS untouched -- the stable opens from the menu and
  examine paths, not a keyword; a deliberate seam for a future stable
  door if canon asks). Ledger truth only: rows rebuild from DictStore
  ride_service/mounts/<player_id>; text labels for the a11y layer;
  ONE button per mount, one meaning -- Summon_ becomes dismiss when
  that mount is active. refresh() is idempotent (clear + rebuild).
  The island is reached by preload path, not global class lookup, so
  the brand-new class_name needs no cache regen (the R43 lesson,
  sidestepped on purpose).
  (4) The shop: get_shop_catalog is data truth -- only priced mounts
  (currency "" or gold AND cost > 0); the gullwing's favor wallet is
  excluded and waits for the reclaimer economy. purchase_mount is the
  VendorService-shaped gate chain: known -> priced -> not owned ->
  level law (world-entry truth) -> gold law (InventoryService purse;
  a ledger refusal ROLLS BACK the gold) -> grant_mount, and the
  grantor speaks: NotifKind.MOUNT_ACQUIRED joins the enum and BOTH
  maps (INFO type, NORMAL priority) -- "You have acquired the Plains
  Runner" rides the same typed pipeline human and agent hear.
  (5) Lessons, again the hard way: a void call (bind_to_world) inside
  a boolean `and` chain is a parse error, not a style smell -- hoist
  it; a block-scoped var (snap lift inside its if) is invisible to
  the elif below -- lift_expected() lives in scope; a body created
  AFTER a signal fired never hears it -- dismiss then re-summon
  re-fires the wire; PlayerManager duck-types the LAST body that
  self-registered -- the buyer is created last, on purpose.
  (6) Verification: probe_riding 67 -> 88 checks, 0 failures (real
  GlobeWorldPlayer on the signal wire; law adoption walk 6 / jump 9 /
  gravity 22; sprint gear 8.1 under 33.75; summit restore on the
  moon; perch note 0.4 < 0.55; cliff bail through the real body;
  catalog has plains_runner, not gullwing; the gold chain broke ->
  249 short -> 250 buys -> purse 0 -> re-buy refused, purse intact;
  the young buyer, level 4, refused; MOUNT_ACQUIRED toast typed end
  to end; the buyer wire re-fired; the stable's panel, row, button,
  and Riding/Walking labels; the button press dismisses and the list
  shrinks). Family batch 8/0 (naming lint, movement profiles,
  anticheat, notification frame + toast, a11y service + contrast,
  riding).
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 46 (THE FAVOR PURSE, THE FACTION LAW, THE STABLE DOOR:
  CurrencyData's wallet promise kept, the gullwing's people get
  their bird back, the stable grows a door -- owner: "Let's keep
  working on mount systems pls. Whatever we need, in addition to
  3D mount models/camera-follow remain future seams since the
  saddle is law-adoption"):
  (1) Scoping followed the PRD's own debts, not new appetite: sec
  8/9 left the favor wallet "waiting for the reclaimer economy,"
  the gullwing's faction_id was data nobody read, and the stable
  had no door a player could open. All three served by existing
  idioms; 3D models and camera-follow stay future seams (the
  saddle is law-adoption -- the owner's own boundary, kept).
  (2) The R45 collision caught first: F was ALREADY bound.
  HudHotkeys toggles FRIENDS on F, and the dismount action's raw
  Input poll on F would tap the saddle every friends-list open.
  The key is U now (physical 85; the probe asserts 85-not-70
  straight from project.godot), the poll respects the text-entry
  law (gui_get_focus_owner is LineEdit/TextEdit/CodeEdit --
  InputManager's _is_text_entry_focused idiom, mirrored in the
  body for --script mode), and HudHotkeys' U swallows the event
  while mounted instead of fighting the body's poll -- one key,
  two lawful meanings, the WoW saddle rule.
  (3) The favor purse: InventoryComponent grew add_currency /
  remove_currency / get_currency_amount + a currency_changed
  signal, in the SAME purse the vendor chain already trusts;
  to_dict/from_dict carry "currencies" (persistence survives a
  save round trip). The laws: no minting (amounts <= 0 refused),
  no invented money (an id the catalog does not know is
  refused), the wallet_cap from the currency's data is a hard
  ceiling. Gold stays on _gold -- one REGULAR currency is the
  naming law; the ledger is for FAVOR/TOKEN/EVENT.
  (4) The catalog speaks every vendor wallet: rows carry their
  currency truth ("" = the default gold wallet, exactly as the
  DATA says -- the R45 row that "read gold" never did), a
  non-gold price is a shop good when its CurrencyData kind is
  FAVOR/TOKEN/EVENT (BLACK_MARKET scrip waits for darker
  vendors), and purchase_mount branches on the wallet with the
  same gate chain and the same refund-on-ledger-refusal. The
  gullwing buys for 400 Reclaimer Favor; 399 is one short.
  (5) The faction ride law: summon AND purchase refuse a rider
  whose species does not match the mount faction's species_id --
  resolved through the .tres registry (DataService.get_faction,
  the resources the faction system itself loads), NOT
  FactionManager's book, which rehydrates from persistence and
  fills only when a world loads (the diagnostic that found it:
  get_faction("faction_human") null in a fresh script-mode run
  while DataService held all four). Unknown rider, unknown
  faction, empty species: fail-closed. Empty mount faction:
  anyone rides.
  (6) The stable door: "mount"/"stable" trigger the mounts island
  in IslandRegistry's TRIGGERS; MenuManager carries the panel in
  its own funnel (z 500, panel_closed bound, _get_panel route);
  U toggles it unmounted; and the panel connects
  mount_summoned/mount_dismounted so the open stable refreshes
  live -- the wire already existed, the body was just the only
  listener.
  (7) Lessons: the .tres registry is the truth that works in every
  mode -- a manager's runtime book can be empty exactly when a
  law needs it; a new hotkey action must be grepped against
  HudHotkeys/follow_manager BEFORE it ships (raw Input polling
  leaks through other systems' bindings as surely as through UI
  focus); and a null-check bug can hide behind a passing catalog
  -- the add_currency unknown-id hole was caught because the
  doc comment said one thing and the code did another (comments
  are contracts too).
  (8) Verification: probe_riding 88 -> 105 checks, 0 failures
  (key law 85-not-70 with the poll armed in the bare harness;
  ledger laws invented-id/zero/negative/short-purse plus the
  to_dict round trip; currency-truth rows; the favor chain 399
  short -> 400 buys -> purse 0 -> the gullwing answers the
  whistle; the faction law both sides -- synthetic refused,
  human granted rides; the stable door words + key, source-
  checked; the live-refresh wire). The R45 legs (summit test,
  perch, bail, gold chain, stable panel) unchanged and green.
  Family: the FULL runner DEFAULT_SET, 60 tests in three
  bounded chunks (21 + 20 + 19), all EXIT=0, zero FAIL lines.
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 46.1 (THE MOBILE RIDER, THE FROZEN SADDLE, THE CAMERA
  SEAT: the touch HUD answers the mount question, the QC pass frees
  a saddle that never moved, the camera-follow setup lands --
  owner: "Are there mobile hud buttons for mounts? And confirm the
  glide mobile stuff is working (press jump in air to glide, demounts
  if mounted) ... Then we can do camera follow work to set it up. And
  any qc needed for mounts systems we have so far"):
  (1) The owner held 3D models (workflow hashing) and asked for
  mobile mount buttons, the mobile glide/demount flow, camera-follow
  setup, and a QC pass. The QC pass outranked the features: it
  caught a saddle that never physically moved.
  (2) The frozen saddle: the R45 mounted gate sat INSIDE the glide
  block (glider != null runs every frame), so every mounted globe
  body returned BEFORE the shared move_and_slide tail -- laws
  adopted, physics never integrated. Value-based probes could not
  see it (headless runs no physics; probe_glider documents the
  constraint). Fixed: the gate integrates + validates, then returns.
  Lesson: a control-flow seam needs a control-flow assertion -- the
  probe pins the shipped lines tab-exact (gate -> move_and_slide ->
  _validate_movement -> return), prose in comments never counts.
  (3) The mobile rider: the touch HUD had no mount button at all
  (summon via the stable panel, but never tap out). MNT joins the
  cluster beside dodge -- edit-mode draggable, persisted, annotated
  "Mounts" for the a11y layer -- wired through the SAME
  parse_input_event bridge as JMP, so the body's dismount poll
  consumes it unchanged.
  (4) The air-tap demount, the owner's mobile law, now real for
  every input path: an airborne jump TAP dismisses (touch JMP and
  keyboard jump feed the same action). Grounded taps stay hops (the
  not-on-floor gate -- a gallop's first beat never throws the
  rider). U and MNT still dismount anywhere.
  (5) The camera-follow setup: the globe rig is the body's
  CameraPivot with globe_world's code-built seat (0, 2.2, 4.5);
  the body holds CAMERA_SEAT / MOUNT_CAMERA_SEAT and swaps to the
  wider mount seat (0, 3.4, 7.0) only over the walk rig's own seat
  (a world scene with its own camera keeps it). One const per mount
  class is the model-ready hook for later.
  (6) Lessons: grep the real UI before answering "is there a
  button?" (the honest answer was no); run the QC pass BEFORE the
  features it gates; and a generic "Hygiene:" anchor in TASKS
  copied an entry 19 times over -- the repair was an honest restore
  from HEAD plus a unique anchor (the R46 entry's own chunk
  counts), because entries are contracts too.
  (7) Verification: probe_riding 105 -> 109 checks, 0 failures
  (MNT button + verb annotation; the mounted frame integrates,
  tab-exact; the air-tap law with the ground-hop gate; the camera
  seat coupled to the walk rig's exact seat). Family re-run in
  four bounded chunks covering the FULL DEFAULT_SET (round2_ui
  constructs the real joystick and builds the MNT button live),
  all EXIT=0, zero FAIL lines.
  Hygiene: tabs only, ASCII, extends-first intact.
- [x] Round 47 (THE STABLE SELLS, THE JOURNEY RIDES: the shop window
  closes R46's open product gap, the Meadow Pacer makes ownership
  lawful for a fresh guest, and the mount journey runs green in a
  real browser -- owner: "Sure let's do it : That mount-journey
  probe (guest -> world -> stable -> summon -> walk -> air-tap
  demount) is the ready next slice"):
  (1) The probe's first demand exposed the gap before a single line
  of probe code: purchase_mount existed since R46 but the STABLE
  HAD NO SHOP WINDOW, and grant_mount has no production caller
  besides the GM auto-grant -- a fresh guest could not own a mount
  lawfully at all. The product got the window; the probe just
  walked through it.
  (2) The starter economy: the Meadow Pacer (mount_meadow_pacer,
  GROUND, level 1, 150 gold, VENDOR, soulbound, kind default to
  movement_quadruped). Role 0 spawns 500 gold (StarterKitService);
  the level-5 250-gold runner stays out of reach at level 1 --
  acquisition difficulty is DATA and the entry tier is real.
  (3) MountUI: shop rows from get_shop_catalog (unowned vendor-
  priced mounts only; the gullwing's favor wallet included; the
  owned vanish), the SAME gate chain on a buy press, refusals
  spoken through GameLog, refresh() re-reading truth. And the
  Godot rename trap, caught by the DIAG print: queue_free'd rows
  still OWN their names, so a same-frame refresh burst auto-
  renamed fresh rows to @HBoxContainer@N and orphaned every
  lookup -- _clear_container removes immediately (frees the name)
  and frees deferred (emission-safe). Buttons speak unique verbs
  (Buy/Ride/Dismiss <name>); the node names keep the wire
  contract.
  (4) The clickable stable door: the menu bar's Mounts item ([U])
  beside the hotkey -- keyboardless players had no door at all.
  MainMenuBar -> MenuManager "mounts" -> the stable, the one
  funnel.
  (5) The probe (probe_mount_journey.js): the a11y stream ONLY for
  action discovery/clicks, oracles = RideService's new audit trio
  (mount purchased/summoned/dismissed -- one channel) PLUS label
  transitions (Buy -> Ride -> Dismiss -> Ride), because wasm
  stdout batching kills GameLog marks at slow fps -- the world
  gate reads the HUD's "=" button, not the registered mark.
  (6) QC the probe forced into the open: a11y rects are canvas-
  space and a 640x360 viewport desyncs them (the fps lever is
  not a viewport squeeze); a "Buy " prefix predicate clicks
  whichever Buy announced first (three Buys; the gullwing ate
  the first run -- exact labels are the law); stale entries
  linger in the action map (screen truth is a fresh predicate);
  the char-list/species screens swallow slow clicks (retry on
  the next screen's announcement, not the click's dispatch).
  (7) Verification: probe_riding 109 -> 117 checks, 0 failures
  (pacer data truth incl. the kind default; young buyer: refused
  the runner, BUYS the pacer, summons, dismisses; shop window's
  exact rows/label; the window button BUYS through the chain,
  purse 150 lighter, row leaves the window; unique verbs; the
  menu door). Family green (naming lint, movement profiles,
  notification frame). THE WEB JOURNEY: RESULT: PASS, EXIT=0,
  ERRORS: [] -- boot + purchased + summoned marks, the demount
  label transition, 79 actions announced, zero script errors.
  web/game.pck re-packed for the run (export carries the shop +
  pacer); the README table carries the new probe.
  Hygiene: tabs only, ASCII, extends-first intact.

- [x] THE CANONICAL SECTOR CACHE (frame/kv/sector_cache.gd, 2026-10-11).
  The quantized-direction memoization terrain_gen grew by hand is now
  a frame primitive and terrain_gen rides it wholesale. Context: the
  previous note ("Adding a quantized cache (same pattern as the
  streamer's dir_h)") + the flagged future work: "Cache bounds (524 k
  per-class statics) cleared wholesale on overflow -- bounded memory,
  not optimal hit-rate; multi-world hot-swapping clears rather than
  LRU-evicts; not exercised by any probe."
  (1) Frame primitive: core/frame/kv/sector_cache.gd (SectorCache, no
  autoload, no class_name -- preload-const like definition_tree /
  folded_shell). One String key law for the whole repo:
  str(2048->quantized Vector3i) + "|" + seed hex (SECTOR key constant
  SECTORS_PER_AXIS = 2048, the same bucketing every old cache used, so
  no cross-swap invalidation question can even arise). Backing store
  = the existing frame LRUCache (O(1) intrusive recency order): bounds
  EVICT the least-recently-used sector; nothing clears wholesale for
  capacity. Defaults keep the legacy 524288 law. Co-located
  test_sector_cache.gd 5 suites: key stability/seed separation,
  bound-by-eviction, evict-then-rederive-answers-the-same (pure-law
  discipline), MULTI-SEED COEXISTENCE (two seeds alternating stay
  fully warm -- the exact hot-swap hole this closes), full-flush law.
  (2) terrain_gen adoption: height, water surface, biome blend, and
  river channel statics all ride SectorCache now (identical key law);
  the per-seed river-spec table rides a tiny LRUCache(8) instead of
  pinning every world's rivers forever; the four separate 524288
  per-class bounds collapsed into four independent per-cache bounds.
  install/uninstall_terrain_backend keeps the only legal wholesale
  flush (the LAW changed; warm sectors are not stale-able but wrong).
  (3) Probe repair (the one direct internal-stdout touch): 
  probe_terrain_climate.gd pinned determinism by erasing one seed's
  specs from the old Dictionary; now _river_spec_cache.delete(key) --
  evict-one, same assertion, stricter isolation than a table clear.
  Verification (exit statuses captured): frame/kv/test_lru_cache +
  test_terrain_determinism + frame/kv/test_sector_cache 3/3 PASS;
  probe_terrain_stream PASS; probe_terrain_planet + probe_sundered_sea
  2/2 PASS; probe_terrain_backend + probe_terrain_climate (rerun after
  the erase->delete repair) + probe_startup_flow 3/3 PASS; charset
  lint PASS (exit 0). No probe loosened: every failure that surfaced
  was fixed at its cause (the deleted static), no assertions weakened.
- [x] SECTOR-CACHE WAVE 2 (the remaining hot pure fields, 2026-10-11).
  Scan for further hand-rolled memoization to consolidate onto the
  canonical frame SectorCache after the round-1 conversion (height,
  water surface, blend, channel, river specs):
  (1) CONVERTED: climate_temperature (lapse reads terrain_height --
  the mesh pass asks temperature per vertex corner via biome weights)
  and water_table_raw (TWO noise octaves + moisture + perch per miss;
  read by both the water-surface law and the lake carve at every
  corner -- priciest non-river corner call). Both keep bit-identical
  answers (pure per quantized sector); both newly flush at the
  backend install/uninstall seam (lapse + perch ride the ground law).
  (2) DELIBERATELY NOT CONVERTED: the streamer's per-patch dir_h --
  it is ALREADY the same pattern (quantized globe dir -> displaced
  radius, 4096 sectors) but scoped to ONE patch build and thrown
  away; converting it buys a hit-rate the height SectorCache already
  provides underneath (every dir_h miss IS a terrain_height call,
  which now hits the frame cache across patches). No double-keying.
  Scope-engine/adapter caches call the persistence sidecars (I/O
  bounds, not pure functions) -- wrong shape for SectorCache.
  Verification (exit statuses captured): probe_terrain_climate +
  probe_terrain_backend 2/2 PASS; probe_sundered_sea +
  probe_terrain_stream 2/2 PASS; test_terrain_determinism +
  probe_startup_flow 2/2 PASS; charset lint PASS (exit 0); terrain_gen
  parse check exit 0.
- [x] CACHE HARDENING WAVE: the poison guard + the architecture
  answers on record (2026-10-11). User asked: Redis? T3? TTL? clear/
  mitigate? poisoning protection (seeds+states)? What else for
  robust+secure caching?
  (1) THE ARCHITECTURE (durable doc below): the terrain SectorCaches
  are IN-PROCESS Godot memory -- deliberately NOT the Redis bridge
  adapters and NOT the T3 Merkle tree. Both are the WRONG layer: T3
  is the persistence/hash substrate (indexed canonical state, not
  float memoization), redis-bridge is a cross-process/session store
  (these caches are per-process derivative computation, and a
  WRONG-net Redis read would need the full t3-hash verification chain
  -- more cost than re-deriving). The canonical sector law is:
  process-local, LRU-bounded, seed-scoped, flushed on law change.
  (2) TTL: NONE, on purpose. TTL expiry is a staleness patch for
  caches whose backing data can change WITHOUT their key changing.
  A pure function's backing data IS its key (dir sector + seed hex +
  law constant) -- the value cannot go stale, only evicted. The two
  honest staleness points in this system already self-manage:
  install/uninstall_terrain_backend does the full flush (the LAW
  changed), and kernel upgrades of the law itself are covered by the
  RULESET_VERSION bump contract (content re-derives deliberately).
  (3) CLEAR/MITIGATE: three ranked levers, all wired -- LRU eviction
  at the per-cache bound (capacity, automatic, hot set survives);
  .clear() (the legal LAW-CHANGED full flush, called at the backend
  seam today); .delete() per-key (probe-verified, one seed's worth
  out without touching the hot set). Uninstall also full-flushes --
  even though seeds key the caches, uninstall clearing is DEFENSE IN
  DEPTH (the layer above)\n: a re-install under the same rule must
  never serve a stale sector no matter what.
  (4) POISONING: two layers shipped. The seed-and-state theory: the
  cache key binds (quantized dir, seed, field) so cross-world
  contamination is structurally impossible (different seeds never
  share a bucket -- test-suite pinned); the state layer is the
  backend SEAM itself (whoever installs a backend changes the LAW,
  and install/uninstall flushes everything). The remaining vector
  was VALUE poisoning: a misbehaving backend returning NaN/inf --
  stored forever once written, evictable-but-re-servable, and a NaN
  dodges every equality pin (NaN == NaN is false), so determinism
  probes CANNOT catch it. Shipped: SectorCache.set_value REJECTS
  non-finite floats (returns false, nothing written) and non-finite
  color components (component-wise); terrain_gen honors the reject
  (never caches, returns the honest clampf answer; rogue backend
  non-finite raw values fall to the plaza-flat fall-through -- the
  law stays total). Co-located test suite 6 now: poison guard
  accepts finite, rejects +/- INF and NAN and poisoned color tuples,
  writes nothing on reject.
  (5) What else robust+secure caching WOULD need (future law, not
  now): if any of these caches ever cross a process boundary (a
  server sharing height answers with clients, or persistence to
  disk), THEN Redis/T3-shape becomes right, and the checklist is --
  integrity stamp on entries (t3 hash of (key, value, law version)),
  bounded replay (never deserialize an entry the CURRENT law cannot
  re-validate), and an admin surface to flush per-seed and per-cache
  from the permission_manager chain. None of it applies while the
  caches are process-local and re-derivable.
  Verification (exit statuses captured): frame/kv/test_sector_cache
  + frame/kv/test_lru_cache 2/2 PASS (6th suite = poison guard);
  probe_terrain_backend + probe_terrain_climate 2/2 PASS; 
  test_terrain_determinism + probe_sundered_sea 2/2 PASS; charset
  lint PASS (exit 0); terrain_gen parse check exit 0.
- [x] THE AUTHORED TERRAFORM GOES LIVE (2026-10-11). User asked:
  what's next in terrain building; is biomes/water actually rendering
  in game; terraform the continent/island/oceans and make it real.
  (1) THE STATE OF RENDER (the honest audit): biome vertex tint,
  species-tree scatter over biome ids, standing-water sheets
  (surface 2), the ocean shell at the sea line, wet-dimmed seabed
  hunks, the homeland plateau + island + moat + spawn apron -- ALL
  already live in the planet-scale streamer/water path. The oceans'
  bottom IS the displaced terrain (one ground law; no fake faces).
  (2) THE REAL GAP: the authored SUNDERED STRAIT lived only in a
  probe (probe_terrain_backend/probe_sundered_sea install it
  script-side and uninstall at exit). The playable world never saw
  it. SHIPPED: data-driven per-world terraform -- new WorldData
  field terrain_backend_id (empty = natural analytic law, the
  declaration is the difference); globe_world._install_world_backend
  resolves the id to res://scenes/worlds/backend_<id>.gd and installs
  through the seam BEFORE the streamer's first height read (no
  two-frame flash of the natural world); unknown id logs loud and
  still boots (natural law renders -- the world stays playable).
  world_main.tres now declares terrain_backend_id = "sundered":
  the playable home world renders the strait, the headland mounds,
  and the wreck shoal the ferry content was authored against.
  (3) What "real" still owes: the strait is a channel through the
  home continent; the ferry (veh_haven_ferry / ride chain) can cross;
  next slices = the ferry line ride-through content and shoreline
  town content near the moat (content, not laws).
  Verification (exit statuses captured): probe_globe_world +
  probe_startup_flow 2/2 PASS (a real scene boot through the new
  install path, world_main's sundered declaration LIVE);
  probe_sundered_sea + probe_terrain_backend 2/2 PASS (the strait
  still laws bit-identical through the data path);
  probe_terrain_stream + probe_terrain_planet 2/2 PASS;
  test_terrain_determinism + probe_terrain_climate +
  probe_terrain_backend 3/3 PASS; charset lint PASS (exit 0).
  No aborts weakened: the silent-uninstall contract stays, the canal
  law is the same code the S14.7 probe pinned, and the world data
  declaration is idempotent with the probe's install path.
- [x] THE PRD GOODIES LAND: scoping pin, the strait ferry, and the
  crafting gate (2026-10-11).
  (1) TERRAFORM SCOPE PIN (the completion check's follow-up):
  probe_world_scoping grew the authored-backend scoping check --
  world_main declares sundered, the moon declares NOTHING (its ground
  is the natural analytic law). Data is the single authority; the pin
  guards the .tres the boot reads. probe_terrain_backend +
  probe_water_mounts joined the runner DEFAULT_SET (backend seam +
  wet-mount law ride the regression floor now).
  (2) THE STRAIT FERRY IS REAL DATA (the ferry ride-through): two
  SHIP gateways on the strait zone -- waypoint_strait_moor (moat-side
  pin) + waypoint_strait_seaward (past the wreck shoal) -- and
  veh_sundered_barque (Old Brack's barque, 6 sailings/day, 0.6 h
  crossing, moor->seaward). zone_sundered_sea now carries world_id =
  "main" (the zone scopes to the authored terraform). probe_ferry
  grew the F2 suite: the barque is scheduled data through the SAME
  DataService scan, both pins resolve on the strait zone, and the
  chart law agrees with the primitive on the barque's OWN schedule
  (5.3 h clock, 4 h step => 5.5/9.5/13.5 cast-offs; the 0.25 h
  boarding window is the page's law -- found + fixed the probe's own
  clock misread, no service change needed).
  (3) THE CRAFTING GATE (prd-crafting.md slice 1, the missing third
  economy leg): RecipeData schema (inputs/station/output/byproducts/
  failure posture, data truth), DataService recipe scan
  (data/recipes/) + get_recipe, CraftingService autoload with the
  gate chain -- unknown recipe refused, unknown input in a recipe is
  a DATA defect (loud, refused, no invention), purse checked for ALL
  inputs (no partial consumes), QoS cadence, failure roll (inputs
  GONE, byproducts drop), success grant, ONE world delta per craft
  call with actor + full bill provenance (craft/<recipe>/<nonce>).
  First recipe: recipe_iron_ingot (2 ore -> 1 ingot @ the forge, 10%
  failure, slag byproduct) + res_iron_ingot + res_slag items -- the
  gather->craft loop the blacksmith feeds from. probe_crafting in
  DEFAULT_SET: recipes-are-data, gate chain (broke purse, honest
  bill, posture law), data-defect refusal, delta provenance, and the
  citizen law (a synthetic crafts through the SAME chain -- identical
  answer shape).
  (4) THE LIVE HARVEST SEED (prd-gathering build order 2): the
  streamer's detail-prop placement pass now registers its drawn
  props as HarvestService nodes -- bushes register gather nodes
  (45 s respawn) and the ALPINE/TUNDRA band draws ORE VEINS (dark
  chunks, 90 s respawn, res_iron_ore). One placement law: seed-
  derived, seed-stable node identity (hs_<face>_<idx>) so a face
  reload re-registers the same node; what you SEE is what you can
  harvest; the gather->forge surface closes the ore leg on the
  authored terrain itself.
  Verification (exit statuses captured): probe_world_scoping ->
  PASS (terraform scope); probe_ferry -> PASS (barque data + pins +
  chart law); probe_crafting -> PASS (the gate chain); probe_harvest
  -> PASS (placement law symmetric); probe_startup_flow PASS (boot
  through the recipe scan + new services); probe_globe_world PASS
  (globe boots with the gatherable pass live); probe_terrain_stream
  + probe_terrain_climate + probe_terrain_backend PASS (terrain laws
  untouched); test_terrain_determinism PASS; probe_water_mounts
  PASS; charset lint PASS (exit 0). parse checks on crafting_service
  + globe_terrain_streamer exit 0. NOT changed: no service assertions
  weakened; the ferry probe's own clock read was the bug (fixed at
  the probe, the schedule law stays).

## 2026-10-11 -- the craft->mount seam closes (breather + kite steady)

  probe_crafting extended to the equippable crafts and the parse error
  that hid them is GONE:
  (1) The probe file itself had a collapsed line-continuation (a stray
  backslash folding three lines into one) -- GDScript could not parse
  it; splitting it fixed even the pre-existing syntax. Also fixed the
  probe's own stale read (broke["attempts"][0] -> results; attempts is
  an int count).
  (2) DataService.load_mounts now scans data/gliders/ INTO the mount
  registry (a sewn glider IS a MountData -- MountKind.FLYING,
  movement_glider). One get_mount door; the craft/ride/ledger paths
  resolve a craft output glider through the same resolution the
  whistle mounts use. No second registry to drift.
  (3) THE DATA BUG the probe was guarding all along: glider_weaver_kite
  .tres shipped WITHOUT its `script = ExtResource("1")` line -- Godot
  loaded it as a bare Resource (id=null, script=null), so CraftingService's
  mount-output grant silently refused an unregistered id. Restored the
  script line; the mount grant into RideService's OWNERSHIP ledger now
  works end-to-end and the mount never lands in the bag.
  (4) probe_crafting coverage now: the reed breather crafts as an ITEM
  through the purse; the weaver's kite crafts a MOUNT into the ledger
  (6 timber + 1 stone, bill consumed exactly); a short purse refuses
  WHOLE at the kite gate (missing_inputs, no partial eats).
  Verification: probe_crafting PASS 13 checks; probe_riding PASS 117
  checks 0 failures; probe_glider PASS 10; probe_bout_flow PASS 26;
  probe_forge PASS 11; probe_harvest PASS 23; probe_startup_flow PASS 18.

## 2026-10-11 -- crafting world+UI integration (S16.9 slice 2)

  The gate was lawful; now the world can FIND it:
  (1) WORKBENCH UI (ui/components/workbench_ui.gd): station-aware
  recipe table. Lists the CraftingService catalog filtered by the
  bench's own station (NONE recipes list everywhere; a forge lists
  FORGE+NONE; the workbench WORKBENCH+NONE). Each row shows the bill
  per-input colored by purse sufficiency (have vs need), the output,
  the failure/openness posture ("fails 10%" / "never fails"), and a
  Craft button that executes through CraftingService.craft ONLY --
  refusals speak the gate's own reason verbatim (REASON_TEXT maps
  unknown_recipe/missing_inputs/recipe_data_defect/no_inventory/
  forge_ate_it). The UI owns no second gate; a mount output lands in
  the RideService ledger, never the bag (the service _grant decides).
  (2) THE STATION LAW IS DATA: NPCData.get_crafting_station() resolves
  any includes-entry whose offering carries service_id
  "CraftingService" and reads service_params.station (one door; probes
  pin workbench=2, forge=1, dialogue-only=-1). New offerings:
  forge_service.tres + workbench_service.tres. A "Craft" context
  action (action_menu filter by that station door) opens the
  WorkbenchUI at the NPC's station via PlayerController's
  _open_workbench_ui (~the blacksmith action idiom).
  (3) THE CRAFT SHELF (vendor_craft_shelf.tres, by_item_id): the
  general merchant carries a second offering stocking only craft-loop
  goods -- recipe inputs PLUS byproducts (res_slag sells, the failure
  sink is recoverable). Data truth: every catalog id is either an
  input or byproduct of some recipe; prices are the items' buy_price
  through the vendor multiplier; the probe refuses invented ids.
  (4) THE DASHBOARD CODEX (src/components/CraftingCompendium.tsx):
  recipe browser fed by the SAME .tres sync (scripts/sync_godot_data.ts
  gained the recipes category; loadGodotData exports RAW). Input/arrow/
  output cards with byproducts, failure posture, station filter chips;
  item names resolve from the same payload (no invented names).
  [K] hotkey toggle in App.tsx. tsc --noEmit clean.
  Probes/scripts: probe_crafting_ui (12 checks: parsing, station door,
  catalog split, shelf inventory law, vendor resolution, merchant
  wiring) added to godot_test_runner.sh DEFAULT_SET after probe_crafting.
  Verification: probe_crafting_ui PASS 12, probe_crafting PASS 13
  (one 10%-roll RNG flake observed then re-run green -- documented
  flake, not touched), probe_forge PASS 11, probe_riding PASS 117,
  probe_startup_flow PASS 18, charset lint 3/3, naming lint exit 0,
  tsc exit 0, sync:data emits recipes:3. NOT changed: the gate chain,
  no service assertions weakened, no probe set weakened.

## 2026-10-11 -- placeable crafting stations (S16.9 slice 3)

  The request: NPCs to visit, places to install your own bench. The
  NPC arm already stood (station law = NPCData.get_crafting_station,
  forge/workbench_service.tres); this slice builds the PLOT arm so a
  house or guildhall can host its own smithy.
  (1) DATA: four FUNCTIONAL dwellings in data/dwellings/ --
  dwel_anvil_iron (blacksmith/repair), dwel_forge_coal
  (crafting_forge), dwel_workbench_oak (crafting_workbench),
  dwel_cauldron_brew (crafting_alchemy). Item-scripted like the
  existing fireplace/chair (the purse carries them; buy_price 14k-36k,
  dismantle_returns refund bill). DataService.load_dwellings merges
  item-scripted dwellings into _items (the accessory idiom);
  Item.gained the station law fields (provides_function,
  interaction_type, is_interactable, tax/maintenance, refund bill).
  get_dwelling's return type widened to Resource (Item-scripted
  entries were rejected by the DwellingData-typed door).
  (2) SERVICE: DwellingService.place_station(player, plot_id,
  dwelling_id) -- the PLOT LAW: owner-only, one station per function
  per plot (the slot key IS the function), paid in GOODS not gold
  (remove_item_by_id; no partial eats), a world node stamped with the
  plot's PlacementAccess, object_placed emitted. STATION_FUNCTIONS
  maps provided function -> the SAME RecipeData.Station ids the NPC
  door reads; "blacksmith" is the repair station. remove_station
  refunds the item through the same purse law. Commands:
  /placestation <dwelling_id>, /removestation; /plotinfo lists
  stations. InventoryService.remove_item_by_id: the by-id stack-aware
  seam (count-first, no partial consumes).
  (3) PARITY: the WorkbenchUI opened at a placed station's
  RecipeData.Station lists the same catalog and presses the SAME
  CraftingService.craft gate -- a place is a station host, never a
  second gate. A kite crafted at a PLACED bench rides RideService;
  the bag never smells a wing; provenance actor = the placer.
  Probes/scripts: probe_placeable_stations (16 checks: data truth,
  station-law map, plot law, goods payment, slot uniqueness,
  non-station refusal, station filter, gate parity, mount law,
  provenance, refund) joins DEFAULT_SET after probe_crafting_ui.
  Verification: placement tests 65/0, probe_placeable_stations 16,
  probe_crafting 13, probe_crafting_ui 20, startup 18, riding 117/0,
  charset lint 3/3, naming lint exit 0, tsc exit 0, sync exit 0.
  NOT changed: the gate chain, the NPC station door, the service
  assertions. Pre-existing lint cyclic-preload/extends-order failures
  untouched (different systems).

## 2026-10-11 -- the walk-up seam + the smithy list fix (slice 3 hardening)

  Two real bugs found the moment the placed-bench probe went interactive:
  (1) WALK-UP PURSE MISMATCH: PlayerControllerproximity opened the
  bench UI keyed on str(player_id) (the fallback int "1") while EVERY
  other service (InventoryService, CraftingService, RideService) keys
  the purse on entity_id. A walk-up player got an EMPTY inventory and
  a craft gate that read "missing inputs" forever. Fix: keying off
  entity_id -- the same id every purse-reading service stamps.
  (2) BLACKSMITH REPAIR LIST: _get_repairable_items matched a
  nonexistent item_type STRING property with two-arg Variant gets --
  both fatal on typed Items (the get throws) and matched nothing even
  when it didn't (the property was item_category, an ItemCategory
  int). Fix: compare ItemCategory ids (WEAPON/ARMOR/ACCESSORY) with
  null-safe one-arg gets + int coercion. The smithy list was empty
  whenever it ran through a typed-bag path.
  (3) PROBE FIX: probe_placeable_stations line-join mangle at 260
  un-mangled; probe now 26 checks (walk-up seam included).
  (4) _spawn_at ADDITIVE POSITIONING: DwellingService._spawn_at no
  longer clobbers a node's own offset with the plot center -- node
  offset respects the plot via addition.
  Verification: probe_placeable_stations 26/26 PASSED, probe_crafting
  13 PASSED, probe_crafting_ui 20 PASSED, probe_forge 11 PASSED,
  probe_harvest 23/0, probe_riding 117/0, charset lint 3/0.
  NOT changed: the gate chain, the station law, the payment law.

## 2026-10-11 -- the shipwreck quay lands (the strait content slice)

  The roadmap's declared next slice (ferry line ride-through content +
  shoreline town content near the moat), built as DATA TRUTH first:
  the audit found the strait arm was hollow -- the two NPCs shipped
  with DANGLING include refs (salvor_stock, ferry_passage_sundered
  loaded no offering), both dialogue ids (sundered_salvor_talk,
  sundered_ferry_talk) loaded no tree, the shoal freight quest had no
  giver wiring, and both SHIP gateways sat at Vector3(0,0,0) -- the
  zone bind point inside the moat ring, nowhere near the channel the
  barque sails.
  (1) OFFERINGS: salvor_stock (timber/ore/stone/slag, shoal prices,
  buys WHAT+MISC), ferry_passage_sundered (Brack's ticket hut),
  shoal_freight_quests (wires quest_shoal_freight into BOTH parties:
  Mag gives, Brack turns in, both sell it).
  (2) DIALOGUES: sundered_salvor_talk + sundered_ferry_talk (both
  4-node trees voiced from the NPCs' own greeting/farewell lines --
  wreck lore, salvage law, the freight job).
  (3) THE STRAIT CHART (core/services/strait_chart.gd): content-side
  resolver over backend_sundered's exact tangent frame -- ONE
  derivation, two readers (the terrain field + the .tres anchors), so
  content can never disagree with the terrain it sits on. Anchors are
  chart coords -> world positions at the planet radius (20000 m).
  (4) GATEWAY POSITIONS AUTHORED: waypoint_strait_moor (x=0.045,
  channel mouth), waypoint_strait_seaward (x=0.310, past the shoal),
  waypoint_shipwreck_quay (NEW, x=0.060 y=0.0135 on the north
  headland -- the shoreline town anchor, two-way link home).
  Probes: probe_shipwreck_quay, 32 checks (include refs resolve,
  dialogue trees loadable + owner-matched, quest wiring lawful,
  round-trip chart inversion, corridor-band placement, route port
  truth, schedule honesty). NEVER returns placeholder-origin.
  Verification: probe_shipwreck_quay 32/32 PASSED, probe_ferry 28
  PASSED, probe_sundered_sea 13/0, probe_terrain_backend 11/0,
  probe_placeable_stations 25 PASSED, probe_crafting 13 PASSED,
  charset lint 3/0 (exit 0).
  NOT changed: the backend field (terrain law untouched), the ferry
  service, the schedule primitive, any .gd service logic beyond the
  new additive StraitChart resolver.

## 2026-10-11 -- the quay's cellar shelves (real item data for the strait arm)

  The quay slice's honest gap closed: the two strait vendors now sell
  REAL item data, not catalog shells.
  (1) DATA: three new items -- item_scrap_lumber (RESOURCE, drift
  wood the strait beat loose, bought by the forge loop's stock),
  item_strait_charm (MISC, pitch-sealed barque-rope luck trinket, 2
  coin), item_skiff_ticket (MISC, the chartered skiff chit, 25 coin
  = FerryService.DEFAULT_SKIFF_TICKET; the wake law is printed on
  the item's own description).
  (2) CATALOGS: salvor_stock gains the scrap lumber entry;
  ferry_passage_sundered stops being an empty shell and stocks the
  charm + the ticket.
  (3) PROBE: probe_shipwreck_quay grew the CATALOG LAW -- every
  vendor stock item_id resolves to real Item data, pricing is
  lawful (sell <= buy, never negative), qty is lawful. 32 -> 53
  checks. The probe's own offer-check bug fixed honestly: an
  include entry of type != offering no longer loads "" and fails
  (guard restructured, not assertions weakened).
  Verification: probe_shipwreck_quay 53/53 PASSED (exit 0),
  probe_ferry 28 PASSED, probe_placeable_stations 25 PASSED,
  probe_crafting 13 PASSED, charset lint 3/0 (exit 0).

## 2026-10-11 -- the ticket law + the double-charge fix (the limitation pair closes)

  The final-check limitations, both fixed at the ROOT:
  (1) THE TICKET LAW (ferry_service.charter_skiff): the chartered
  skiff chit (item_skiff_ticket) is now the LAWFUL FARE -- a chit in
  the purse is spent FIRST (count-first, no partial eats, the
  place_station goods seam) and the gold fare is the FALLBACK for
  travelers who never pre-paid (the sink stays; the chit is not a
  tax). Wake law gates BOTH fares. No purse at all = no ride.
  (2) THE DOUBLE-CHARGE BUG (inventory_component.remove_item_by_id):
  the consume loop never decremented `left` on a PARTIAL take -- a
  stacked item (skiff ticket stack 3, take 1) ate one unit AND
  returned false, so upstream callers replayed the gold charge on
  top. The old path only succeeded for stack_size==1 items
  (dwellings), which is why place_station never tripped it. Fix: the
  take is ALWAYS accounted; a partially-eaten stack leaves the
  remainder in the slot AND pays its share. Direct dev probe:
  remove("item_skiff_ticket",1) -> true, stack 3->2.
  (3) THE NULL-BAG PERSIST CRASH (inventory_service._persist_inventory):
  a null registered bag (no-purse law checks) crashed to_dict at
  register time. A purse that is not held erases its save instead.
  Probes/tests: probe_ferry grew G-section THE TICKET LAW (chit is
  the fare / gold untouched / one chit spent / no-purse refusal /
  chits exhausted then gold fallback) -- 28 -> 34 checks.
  Verification (exit statuses): probe_ferry 34/34 exit 0, probe_
  shipwreck_quay 53 PASSED, probe_placeable_stations 25 PASSED,
  probe_crafting 13 PASSED, probe_crafting_ui 20 PASSED, charset
  lint 3/0 (exit 0).
  NOT changed: the ferry schedule primitive, the manifest/riding
  book, the wake persistence law, the place_station payment path
  (it now benefits from the honest partial-take accounting).

## 2026-10-11 -- the dock front-end exists (S16.10: the sea crossing's UI)

  The audit-of-unwired-seams slice: FerryService was fully lawful
  service-side (schedule primitive, ticket law, wake book -- all
  probe-covered) and had ZERO UI entry. The almanac's sailing page
  read the schedule chart but nobody could BOARD or CHARTER from any
  panel. This builds it the same way every other island got built.
  (1) FerryDockUI (ui/components/ferry_dock_ui.gd): extends UIPanel
  the MountUI way. The dock invents nothing -- the route row reads
  FerryService.route_status live (the same chart the almanac's page
  reads; they cannot disagree), the Board button stands only inside
  the boarding window (the schedule law is the UI's law too: the
  button LIES DOWN outside the window), every press rides the SAME
  gate chain the headless probe rode (board_ferry / charter_skiff),
  refusals are spoken IN the panel (the wake law announces itself to
  a greenhorn), and the skiff's ticket law surfaces explicitly in
  the button text.
  (2) WIRING: MenuManager grows the "dock" panel (_dock_panel;
  get_panel/closed-signal wired like every other island);
  ferry_dock_service.tres (NPCOffering, service_id FerryService)
  added and included on npc_ferryman_sundered (after his dialogue);
  NPCEntity._dispatch_service grew the FerryService arm: opens the
  dock panel AND hands it the acting player (open_for_player) --
  one gate chain, same as blacksmith.
  (3) PANEL SCOPING: the dock panel takes vehicle_id (a shoreline
  knows its boat -- the moor-side dock names the barque, not
  "whatever dict order says"; empty = the first scheduled ferry).
  Probes: probe_shipwreck_quay grew F-section THE DOCK UI (script
  loads, route row reads the barque, Board lies down outside the
  window, stands inside, press boards the manifest via the same
  chain, ferry tier never bills the purse, skiff press spends the
  CHIT through the UI, the wake records on the skiff's own arrival
  clock, the refusal line speaks). 53 -> 65 checks.
  Verification (exit statuses): probe_shipwreck_quay 65/65 exit 0,
  probe_ferry 34 PASSED, probe_crafting 13 PASSED, probe_placeable_
  stations 25 PASSED, probe_crafting_ui 20 PASSED, charset lint 3/0.
  NOT changed: FerryService (the seam was already lawful), the wake
  book, the schedule primitive.

## 2026-10-11 -- the walk-up dock seam + the leak audit (the pins enter the world)

  Both final-check limitations + the unwired-systems audit, in one
  slice.
  (1) THE WALK-UP DOCK SEAM: the dock existed (f38331f) but ONLY
  opened through Old Brack's fence. Three honest gaps closed:
  a. GatewayRecord grew gateway_type (forwarded from the authored
     .tres through register_gateway config) -- the runtime record
     never carried the class, so nothing could tell a dock pin from
     a dungeon door. Default 4 (SHIP) for legacy ad-hoc records,
     preserving prior behavior.
  b. THE PINS ENTER THE WORLD: WorldService._register_authored_
     gateways scans data/gateways/*.tres at _ready and registers
     every authored pin verbatim as a live GatewayRecord. Before
     this the SHIP pins were data truth with NO world body -- the
     probe chart checked the .tres files, but the walk-over law and
     proximity checks never saw them (world_playable only registered
     the one dungeon portal ad hoc). Authored ids that the
     persistence layer already loaded are skipped, so waypoint
     unlock states survive a reboot.
  c. PlayerController._open_nearby_ship_dock: the E-interact law
     grows the SHIP arm -- a SHIP-classed pin in activation range
     opens the dock panel SCOPED to the pin's vessel via
     _dock_vehicle_for_pin (the ferry whose route_gateways NAMES the
     pin: moor/seaward -> the barque, village/nexus -> the Haven
     Ferry, island_dock -> the Island Ferry -- no lookup table, one
     data-truth door). _try_interact order: loot -> stations -> dock
     (a station plot shared with a dock face belongs to the plot).
  d. DataService.get_all_vehicles: the accessor the seam exposed
     (was: vehicles had a get-one door but no all-door; the resolver
     iterates ROUTES, not ids).
  Probes: probe_shipwreck_quay grew H-section THE WALK-UP DOCK SEAM
  (authored pins are live records with SHIP class; non-dock pins are
  NOT SHIP; the walker caries the pin->boat resolver; moor->barque,
  village->Haven Ferry, unknown->"" -- the resolver invents nothing).
  65 -> 73 checks. GDScript note pinned: has_method is instance-side
  -- probing the walker needs the authored instance, not set_script.
  (2) THE EXIT-TIME LEAK, root-caused: "1 resources still in use"
  fires on an EMPTY SceneTree probe too (leak_isolate2 -- Godot
  boots 40+ autoloads off project.godot; the warning is engine-exit
  teardown noise from the boot graph itself, not repo code). The
  honest repo-side hygiene still landed: AppFirewall._exit_tree
  severs the Scope tree (child Scope holds parent; parent's
  children: Array holds the child back -- a RefCounted cycle the
  engine cannot free cleanly). The warning may persist on exit
  (engine-side); the CYCLE is our fault and is fixed.
  (3) THE UNWIRED-SYSTEMS AUDIT (the asking question: what is
  probe-covered but faceless?): sweep of 50 panels + HUD against the
  services:
  - WIRED: RideService (MountUI),_vendor (ShopUI), LootService
    (loot_drop_visual + hud), FriendsService (3 UI refs),
   -cliChronicleService (ChronicleUI via MenuManager),
    WeatherEventService (sky_totem, wire-only by design),
    housing/harvest (chat commands /buyplot /placestation /
    plotinfo + E-interact placed stations), signs (SignService +
    insight), HordeEventService (HordeBar).
  - PARTIAL (the honest remainder, NOT blocking): CosmeticsService
    has no dedicated panel (cosmetics ride the variety pass);
    CosmicService surfaces only through sky_totem's lore lines
    (a cosmic almanac page is the natural next panel); harvesting
    relies on E-interact proximity + chat, no harvest progress UI.
  Verification (exit statuses): probe_shipwreck_quay 73/73 exit 0
  (twice: after the seam and after the audit), probe_ferry 34,
  probe_crafting 13, probe_placeable_stations 25,
  probe_crafting_ui 20, charset lint 3/0 exit 0.
  NOT changed: FerryService, the dock panel's own law, the schedule
  primitive, any .tres content truths (only the wiring).

## 2026-10-11 -- the maintenance pass (stale / not-wired / not-in-world / security health)

  The audit you asked for, findings fixed at the ROOT:
  (1) STALE: .godot/imported was EMPTY in the workspace -- five audio
  resources (ancient_door_open, mystery_solved, ui_click, thunder,
  whistler) failed to load at runtime (the .import remaps pointed at
  samples that no longer existed). FIXED by the standard re-import
  pass (godot --headless --path . --import): 302 imported samples
  restored, load errors gone. Data-reference sweep (offerings,
  recipes, quests, loot tables, vehicles, NPC zone/scene paths): all
  resolve (the 9 "missing zone" rows in the first scan were the
  scanner not lazy-loading ZoneManager; the glider recipe output
  resolves through the mounts merge).
  (2) NOT-IN-WORLD, the top finding: two live quests were DEAD-END
  quests -- the collect targets did not exist as items anywhere:
  * quest_herb_gathering: "Moonpetal Flower" (x5) -- no item .tres.
  * quest_shoal_freight: "Sealed Crate" (x3) -- no item .tres.
  FIX AT THE ROOT, both halves:
  * res_moonpetal.tres (RESOURCE, stack 50, the alchemist's herb)
    + item_sealed_crate.tres (MISC quest item, quest_id wired to
    quest_shoal_freight, turn-in-expires). The collect law
    (QuestService._on_item_picked_up_for_quest matches
    item.display_name against the objective target) now resolves.
  * WORLD PRESENCE: the streamer's biome law is what a seeded
    gatherable must ride. MEADOW bushes now yield the meadow's
    herb: ALPINE_MEADOW bushes register "res_moonpetal" (was:
    every bush in every biome yielded res_iron_ore -- shrubs
    pretending to be a mine; grass/forest/taiga bushes keep ore
    only where the mine law already runs them ALPINE/TUNDRA).
  * THE STRAIT FREIGHT SEED: faces whose center lies on the
    authored corridor chart register the quest's 3 crates
    ("freight_<face>_<k>") on zone_sundered_sea through
    HarvestService, seed-stable ids, respawn past the tide turn --
    the walk the quest demands exists on the actual strait floor.
  (3) SECURITY / QoS / ANTICHEAT HEALTH: all three chains are LIVE
  and wired -- AntiCheatService registered (project.godot
  AntiCheatService), movement/lift validation called per physics
  tick from BOTH player rigs (player_controller + globe_player),
  mount profiles stamp their movement limits through it;
  QoSService.rate_limit guards 29 call sites (crafting, dialogue,
  inventory transfer, etc.); SecurityService feeds
  webhook_manager.exploit_detected. No maintenance action needed;
  the health probe family is green.
  Verification (exit statuses): probe_shipwreck_quay 73/73 exit 0,
  probe_harvest 23/0, probe_ferry 34, probe_crafting 13,
  probe_placeable_stations 25, probe_crafting_ui 20, charset lint
  3/0 exit 0, re-import restored 302 samples.
  NOT changed: the quest .tres files (their display-name law was
  right; the WORLD owed the items), the collect law, the harvest
  gate chain, services' security calls.

## 2026-10-12 -- the dead HUD faces wake up (orphan sweep: PartyFrames + NotificationToast)

The 51-panel dead-UI sweep closed: TooltipManager and WaypointUI were
fine (scene-mounted via hud_layer.tscn / MenuManager), but two LIVE
panel scripts had no mount and no caller anywhere:
* ui/components/party_frames.gd (PartyFrames -- the 5-stack party
  health/mana/role frames)
* ui/components/notification_toast.gd (NotificationToast -- the rich
  corner toast stack: 6 types, click actions, progress bars, and an
  N-key notification center with history)

THE WIRE, both halves:
* Mount: hud_layer.tscn grew three ext_resources + three Control nodes
  (MainMenuBar had already dropped from the mount list in a prior
  commit shock -- restored) -- NotificationToast full-rect + mouse
  ignore, PartyFrames full-rect + mouse ignore (it hides itself until
  a member dict arrives).
* Route: HudIntegrator._on_notification now routes by DisplayLocation.
  NotificationService.send_event() already maps HIGH+ kinds to
  CENTER_SCREEN and everything else to CORNER; the integrator honors
  that law: CORNER payloads render on the DEDICATED face
  (NotificationToast.show_toast, ToastType.INFO) with the legacy
  TooltipManager.show_toast() kept as the fallback for HUD scenes
  predating this wiring. One send() fires both notification_sent and
  notification_received with the same payload, so the integrator
  gates identical payloads with a rolling 5s md5-key guard
  (hud_toast:<md5>), swept past 64 keys; the stack cap (5 visible +
  queue) still has the last word.
* The old law ("every notification toasts") is gone with the reason
  it existed: CHAT_LOG/CENTER payloads stay in the combat log
  (center-screen has its own billboard face upstream).

BUGS FOUND BY THE PROBE (probe-first paid for itself):
* notification_toast.gd DID NOT PARSE (the "orphan" was actually
  dead twice over): ToastType bare members (INFO/WARNING/...) fail
  to resolve inside const-dict literals -- qualified
  ToastType.INFO; two `:=` type-inference hangs on
  get_theme_font_size (untyped returns) -- explicit int; Input has
  no static map_action() (the button silently dead) -- InputMap
  add_action + action_add_event(KEY_N).
* party_frames.gd null-widget crashes: _update_member_frame resolved
  ten named widgets with get_node() -- one missing piece kills the
  whole update tick; frame paths were also wrong in two places
  (ClassIcon/RoleIcon live under a nameless HBox; NameRow/InfoColumn
  were anonymous). All ten resolved with get_node_or_null + nulled
  pieces skipped; builders now name InfoColumn + NameRow so the
  lookups are path-stable. The gui_input connect lived inside the
  per-frame update (a fresh lambda connection per update tick --
  one right-click fired N handlers and _on_member_gui_input's
  signature mismatched the bind) -- connected once with .bind(frame).
* update_party took Array[Dictionary] -- plain-Array callers (HUD
  integrator, PartyService bridges) tripped Godot's strict
  typed-array check; now takes Array and re-types locally.
* test_notification_toast's recursion step orphan-hunted ITSELF for
  years: "test_toast_ctx" depth sits in RecursionGuard's process-
  level tracker across suite runs, so the first enter() can block
  (breaking allow/allow/block) and the dedupe time-bucket collapses
  repeats; fresh keyed context name per run. Its last assertion is
  also re-stamped to the RENDERING LAW: the firewall's recursion
  alert is HIGH + SECURITY_BLOCKED -> the frame maps it
  CENTER_SCREEN, so the CORRECT result is "not on the corner toast
  stack, but in get_history(\"admins\") with kind=24 + the context
  in data" -- the old "panel count > 0" check only passed by riding
  ambient achievement/bout toasts that shared the stack during the
  await frame.

VERIFICATION (exit statuses): test_notification_toast 11/0 exit 0,
test_hud_widgets 10/0 exit 0 (new: mounts both faces on the live
scene, drives a CORNER notification through NotificationService
into the dedicated face, blocks CHAT_LOG, pins one-send-one-toast
dedupe, pins the 5-stack flood cap, drives PartyFrames visible ->
render -> empty-hides -> frame render cap (5/7 pushed)),
test_notification_frame 26/0 exit 0, lint charset 3/0 exit 0.
NOT changed: TooltipManager's show_toast (still the fallback face),
NotificationService's kind/priority maps, RecursionGuard's depth
semantics.
