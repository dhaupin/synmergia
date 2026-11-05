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

## 2026-10-12 -- the son-and-dad play hour: the world boots playable and the driver proves it

The report: "in about an hour we will try it together" -- so the
whole playable state got pinned end to end, headless AND rendered:
what happens when you land, whether terrain renders, whether you can
reach a coast/ocean.

TERRAIN GROUND TRUTH (headless, all exit 0):
* probe_terrain_stream 13/0 (streaming order/unload + 20-face walk),
  probe_terrain_planet 43 PASS, probe_terrain_climate 26 PASS,
  probe_globe_world 23/0 (walk/camera/HUD on the live globe scene),
  probe_ocean 44 checks, probe_sundered_sea -- the terrain, the sea
  line, the strait, the water worlds are all healthy. Nothing to fix
  there.

THE WEB CLIENT WAS STALE: web/game.pck was 4 days old (Oct 8) -- a
week of engine fixes (login door, terrain backend, notification face)
never reached the shell the browser loads. Re-exported the pack from
the current source (12.9 MB) and rewrote web/game.pck.hash; the
content-addressed cache-buster in index.html picks it up.

THE ONE REAL BOOT BUG: ui/menus/login.gd called
AccountService.has_account(id) -- a method that does not exist
(AccountService exposes get_account(); the caller wanted an existence
check). The login scene script errorred at _ready, the guest door
broke, and the globe driver's flow stalled at login every run. Fixed
to AccountService.get_account(id).is_empty() -- the same check the
rest of the account surface uses.

THE DRIVER ITSELF (the honest test rig for "can we play together"):
* Time dilation diagnosis: frame-counted waits under xvfb+llvmpipe
  (the globe world is a 20 km planet; software GL renders ~1-2 fps)
  turn a "2 s" settle into minutes of wall time. Every earlier stall
  ("coroutine never resumes!") was just this. The runner now waits in
  WALL-CLOCK create_timer terms everywhere.
* Stale assertion fixed: the stage-5 ground truth pinned the S5b
  PROTOTYPE radius (|player.r - 101| <= 0.5) while the shipped config
  is planet_radius=20000 -- the driver's "off_shell_63.67" verdict was
  thedriver's own ruler, not the game. The law it now pins: the body
  sits WITHIN ~12 m surface lift of the LIVE globe's planet_radius
  (10.52 m measured -- right at the walk-surface 9.0 m + lift).
* Structure: the flow stages live in globe_driver_runner.gd (a plain
  Node added by the wrapper under tree root), since SceneTree-script
  coroutines and frame loops both proved fragile against the world's
  boot-time suspended signal handlers + dilation.
* The full real player flow, via the real menus and handlers: main
  menu → Start → guest login → lobby → Create New → species human →
  class warrior → Enter World → GlobeWorld boots (4 faces / 16k tris
  mesh-ready at boot, walk surface 9.0 m, sea line 6.0 m, playable
  HUD installed) → auto-walk 39.5 m riding the sphere → HUD panel.
  Six screenshots land in /tmp/play/globe_flow_*.png fresh each run;
  sweep_spawn_truth / the ALT+mesh tag work rides in-game.

VERDICT (exit statuses): GODOT_PROBE_XVFB=1 xvfb-run globe_driver
exit 0, fail_flags empty, surface lift 10.52 m, path 39.5 m. Headless
family re-run green (terrain stream 13/0, widgets 10/0, toast 11/0).
NOT changed: terrain gen, streamer, ocean volumes, backend sundered,
mask/skirt -- they were right.

## 2026-10-12 — the aperiodic frame piece lands (Penrose P3)

**Premise beaten into code:** early vant ("the dhaupin/vant"),
which inspired synmergia, played with Penrose tilings (Bielefeld
P3-rhomb substitution page). The world-building research doc had
it as Phase-6 research-only. User said build it. Landed as a
frame primitive + the rng seam within one session.

* `core/frame/math/penrose.gd` (new): canonical P3 substitution —
  fat/thin rhomb seeds split into Robinson-triangle halves sharing
  a base exactly; `subdivide_once` (L -> L,S,L; S -> S,L; count
  matrix [[2,1],[1,1]] with eigenvalue phi^2); exact phi psi psi2
  and cos/sin 36/72 constants; mirrored (handedness) flag carried
  through every generation; `deflate_n`; recursive-deflation point
  lookup (barycentric containment with edge slop, deterministic
  first-hit) yielding per-level ANNOTATION digits (child index
  0..2), the address "window"; `scope_for_point` -> "penrose.<w>";
  adjacency by shared-edge matching with self-identity guard;
  `base_child_edges` (the cut points along base a-c) for the
  matching-rule work the frame does not yet have.
* `core/frame/math/test_penrose.gd` (new): 10 laws ALL PASS —
  area conservation, M^2 counts (10 L / 6 S after two deflations
  from a fat rhomb = rows of M^2 = [[5,3],[3,2]] x halves),
  children-inside-parents 3 generations, containment/escape
  (centroid + base midpoint resolve; far point escapes to
  "penrose.escape"), annotation determinism, 500-probe density
  (digits in 0..2, >=2 distinct first digits), scope prefix law,
  grandchild partition area law, seed base pairing (psi cut on
  both sides for L, whole edge for S), adjacency symmetry
  including the NOT-adjacent-to-itself identity case.
* `core/frame/srv/cosmic_rng.gd`: Aperiodic rng seam LIVE —
  `penrose_unit(p)` / `penrose_randi(p, from, to)` derive streams
  from `penrose.<window>` scopes, riding the existing replay
  contract ((pool_state, scope) -> identical stream). 2 new tests
  in test_cosmic_rng (deterministic point roll + snapshot replay)
  green; the full rng suite still passes end to end.
* `scripts/godot_test_runner.sh`: `frame/math/test_penrose` added
  to the regression set. Runner output: `frame/math/test_penrose`
  PASS; rng, spherical, icosahedral all still PASS (5 suite runs
  this session).
* Lint charset on the two new files: clean (no non-ASCII in
  strings/tab literals beyond the allowlisted projector frames).
* NOT built (honest gap): renderer/raster of the rhombi, de Bruijn
  pentagrid / cut-and-project family (constant-angle construction
  over the substitution's canonical one), spherical projection,
  matching-rule (arrow/arc) validator, global addressing beyond
  the handed seed triangle, and a perf benchmark. The rng seam
  needs none of those to be usable — it ships live for any caller
  that wants aperiodic audit keys today.

### 2026-10-12 (late session): the missing pieces — de Bruijn pentagrid, global addressing, validator v1, raster + spherical seams, benchmark
* `core/frame/math/pentagrid.gd`: NEW frame primitive, the de Bruijn
  1981 five-grid dual of the Penrose P3 (the constant-angle
  construction). Five line families with 72-degree-spaced normals,
  Penrose-class shifts gamma = [0.3, 0.2, -0.1, -0.4, 0.0]
  (phase-sum 0, reference sample), cell->vertex / crossing->rhombus
  duality via Cramer, and `tile_at(p)` GLOBAL point lookup: any
  point in the plane resolves to its rhombus in <= 40 candidate
  tests via the F(K) = 2.5*x + C window correspondence.
* Global vs seed-bounded: 300-probe containment law passes, far
  law passes (points at |p| ~ 50-350 resolve while penrose.gd's
  substitution-seeded lookup escapes all six) — the gap this
  session closed, verified empirically by the tests themselves.
* Matching-rule validator v1 (`validate_patch`): unit edges,
  corner classes in {36,72,108,144}, abab alternation permit an
  edge shared by at most 2 tiles, interior-vertex angle sums of
  10 units of 36 degrees (boundary exempt). Built regions validate
  clean at half-extents 4, 8 and 9; the stretched-tile mutation
  law proves the validator is not vacuously green. The
  Ammann-arrow cyclic-order check is the remaining legality
  condition beyond v1 (documented per MathPages).
* Raster seam (`triangle_soup`): patches -> PackedVector3Array
  positions + PackedInt32Array fat/thin per-triangle kinds (2 tris
  per tile). Data-only; the ArrayMesh feed is the caller's move.
* Spherical seam (`gnomonic_project`, `project_patch`): planar
  tiles -> planet-sphere points through an orthonormal tangent
  basis (east/north), radius honored, tangent point preserved.
  Per-patch use documented (sec2 distortion far out).
* Benchmark (`core/frame/math/bench_penrose.gd`): measured headless
  Godot 4.7.2: annotation lookup 0.032/0.046 ms @ depths 4/6,
  pentagrid tile_at 0.47 ms/probe, deflate_n(seed, 8) 26 ms,
  build_region(10) 93 ms, validate_patch 111 ms (~1487 tiles,
  valid), triangle_soup 2 ms (2038 tris). The sec-1.5 game-scale
  budget (sub-millisecond point-to-tile) is met for point lookups;
  region build/validate is a load-time cost.
* `core/frame/math/test_pentagrid.gd`: 12 laws ALL PASS
  (gamma phase-sum, canonical grid regular via 3+-line
  singular count = 0 over kmax 8, single-cell index invariant
  S in {1..4} x400 probes, unit-rhomb shape law (edges 1, areas
  sin72/sin36, angle sets), 300-probe containment tile_at, far-
  field global tile_at, tile key determinism + same-tile sharing,
  build-region census ratio 1.674 ~ phi, built patch validates,
  mutation caught, gnomonic tangent/sphere/near-tangent laws,
  triangle soup counts/z/kind laws). Runner registered as
  frame/math/test_pentagrid; full frame/math + cosmic suites
  re-run PASS after it (exit codes captured per run).

## 2026-10-12 (turn 3): the §1.9 gap list, post-mortem on all four, plus the game hookup

Status of the "still not built" list from last turn — every item closed, upgraded, or honestly re-scoped:

- Ammann-arrow cyclic-order check: DELIVERED as the parity-strip-index seam law
  (`pentagrid.edge_arrows` + `_validate_arrows`, integrated into `validate_patch`).
  Key finding en route and documented: the glyph-table's "fat = one mult class
  on all four edges" bit is provably GLOBALLY inconsistent when enforced
  seam-crossing under the same-world-amos-per-edge requirement; the parity of
  the lower corner cell of the pair a shared edge straddles is the mark
  (mult, dir)-piece that superimposes BY CONSTRUCTION on seams, no winding
  dependence, [x,!x,!x,x] mult shape per tile (test law 13 pins the
  structural fact). Necessary-not-sufficient for extendability remains true
  (MathPages ten-thin trap) — that final rung is the 1-atlas (15 1-maps,
  Fernique-Lutfalla), open precisely because its atlas is PAPER-FACT data.
- Data-only raster seam: CLOSED at the data boundary (`soup_to_mesh_arrays`,
  law 15 round-trips to a real committed ArrayMesh with 1 surface and exact
  vertices) — node creation deliberately stays caller-side, 5 lines.
- Spherical per-patch gnomonic: delivered the WHOLE-PLANET ATLAS MATH
  (cap-vs-distortion: 17.5 deg at 10% sec2, 24.1 at 20% per Snyder,
  hex-spacing cap*sqrt(3), chart-count estimate 40-90 @ 20 km planet and
  10% cap). Whole-sphere STITCHING (boundary polygons across adjacent
  charts) stays the honest open item: the research turn found NO verified
  literal P3-on-sphere construction in the literature (T-K spherical
  Penrose-like is the nearest prior art, not P3) — so this is a THIS ROAD
  that ends in real work, not a hidden gap.
- Perf numbers with no CI gate: DELIVERED as Law 17 (perf gate in
  test_pentagrid.gd, 4x/13x/20x observed headroom; runs AND gates on every
  suite invocation). benchmark script stays the human-readable report.

Game-system hookup (this turn):
- CosmicRng gained the pentagrid global seam (`pentagrid_scope/_unit/_randi`)
  mirroring the proven penrose window seam but plane-global: rhombus-key
  scopes, deterministic per fixed gamma, replay-tested. 23/23 CosmicRng
  checks PASS (foreign-scope isolation + snapshot-replay pinned).

Deliverables (all fresh, all verified):
- game/core/frame/math/pentagrid.gd: edge_arrows + _validate_arrows (the new
  legality layer), soup_to_mesh_arrays, patch_cap_deg / atlas_spacing_deg /
  atlas_chart_count, doc-comment corrections.
- game/core/frame/math/test_pentagrid.gd: laws 13-17 added (arrows lawful on
  real patches, mirrored-seam mutation caught, soup-to-arraymesh roundtrip,
  atlas caps vs Snyder, perf gate), 17/17 suites PASS.
- game/core/frame/srv/cosmic_rng.gd + test_cosmic_rng.gd: pentagrid seam +
  6 new checks, 23/23 PASS.
- web/index.html + src/components/wasm/GodotClientView.tsx: the
  permission-prompt explainer (Android/Chromium's opaque
  "other apps and services" = the standard loopback-network consent;
  Blocking is safe; what it actually gates is stated). Visible on mobile
  UA in the stale loading screen AND in the shell toolbar drawer.
- labs/world-building-research.md sec 1.9 refreshed (deliveries +
  re-scoped honest gap).

Verification record (exit codes captured headless per run):
- test_pentagrid 17/17 PASS; test_penrose 10/10 PASS; test_cosmic_rng 23/23
  PASS; charset lint 3/3 PASS exit 0; TSX typecheck tsc -b --noEmit clean.
- Full runner default set: chunked PASS (16 + 16 + 11 + singulars + 9) —
  every named test in scripts/godot_test_runner.sh's DEFAULT_SET ran green
  this turn after the new laws landed, including terrain/globe/probes.
  probe_crafting once flaked its 10%-roll `attempts == 1` assumption,
  passed on the immediate re-run WITH NO CODE CHANGE (a data-chance
  flake in a pre-existing probe, noted as follow-up material, not a
  regression of this turn).

## 2026-10-12 (turn 4): the five limitations, paper-free, all closed or reduced to one

- 1-atlas needs PAPER FIGURES: DEAD ROAD retired. The vertex-star atlas is
  DERIVED from the construction (pentagrid.vertex_star_cycles, 12 lawful
  cycles at two region sizes unioned): no transcription step exists anymore.
  validate_patch enforces the Conway vertex-star law; law 19 proves the
  derived atlas REJECTS the MathPages ten-thin extendability trap (the
  case the 1-atlas escalation existed for) while law 18 proves real AND
  mirrored patches still pass (isometry stability). 21/21 pentagrid laws.
- GLYPH-LEVEL arrow labels: delivered (arrow marks carry the exact
  (family, level) grid-line identity alongside the parity mult; law 20).
- WHOLE-SPHERE STITCHING: reduced to a single-owner local task by
  delivering chart placement + assignment (atlas_centers/chart_owner,
  covering-radius formula law = geometry cross-check vs sampled sphere;
  law 21). The stitch polygons themselves remain the last open item.
- RENDERER FEED caller-side: shipped PenroseMeshBuilder + probe_penrose_mesh
  (7/7 PASS, runner registered): fat/thin 2-surface ArrayMeshes with vertex
  colors, planar AND sphere-projected routes, MeshInstance3D mounting.
- probe_crafting roll flake: fixed roll-agnostically (assert the bill:
  ore_eaten == 2 * attempts, attempts in 1..4; the 10% die no longer matters).
Verification: pentagrid 21/21 PASS, cosmic_rng 23/23 PASS, mesh probe 7/7
PASS, crafting probe 13/13 PASS, charset lint 3/3 PASS. Remaining open: ONLY
the chart-boundary stitch polygons (+ the extendability decider, not needed
for local legality).

## 2026-10-12 (turn 5): stitch layer + extendability decider + exact colors

- Chart-boundary stitching: atlas_centers_dense (12 -> 42 centers, covering
  radius 37.4 -> 31.7 deg sampled), chart_boundary_samples (337 seam
  midpoints both neighboring charts reconstruct identically from the
  center-pair identity), skirt_strip (rim drop quads tagged SKIRT_KIND=2).
  Inter-chart seams are now exactly closed at the shared samples and
  cosmetically skirted at LOD truncation. Law 22 pins determinism,
  tightening, equidistance, and skirt legality.
- Extendability decider: pentagrid.is_extendable -- every tile's crossing
  identity must reproduce its vertices in the canonical rhombus_at (plus
  kind match). Real grid extracts pass; warped tiles, kind-lying tiles,
  and the ten-thin star fail. Law 23 pins all four directions.
- Exact-color law: probe_penrose_mesh now asserts the 8-bit channel
  quantization floor Godot's vertex-color path guarantees (catches channel
  order / double-conversion bugs at the precision the pipeline promises)
  instead of hue-tolerant fudging.
Verification: pentagrid 23/23 PASS (exit 0), penrose 10/10, cosmic_rng 23/23,
mesh probe 7/7, crafting 13/13, charset lint 3/3. Remaining open (1 item):
the runtime LOD policy between charts (rendering-engine concern beyond the
frame layer; the data layer is delivered).

## 2026-10-12 (turn 6): the chart LOD policy -- the last open item closed

- PenroseChartLod (game/scenes/worlds/penrose_chart_lod.gd): the runtime
  LOD policy the frame layer deliberately left to the renderer. Pure
  static functions on the delivered data layer -- no Nodes, no RNG, no
  wall clock: the plan is a pure function of player position, so it is
  replayable exactly like the anticheat wants every world decision.
  Policy laws: (1) PYRAMID LADDER, desired_subdiv is monotone non-
  increasing in angular distance, annular bands [cap*k/n, cap*(k+1)/n)
  mapping innermost band -> LADDER_TOP; (2) SAFETY BASE, rung 0 is the
  always-provided floor (base 12-center layout covers the planet alone);
  (3) NEIGHBOR CONTRACT, settle_seams caps any chart-vs-neighbor ladder
  gap at MAX_NEIGHBOR_GAP=1 (the half-step law; fixed-point iterate);
  (4) LADDER CLAMP at LADDER_TOP=2; (5) DETERMINISM. plan_safe emits the
  settled {index: {subdiv, skirt_depth}} shape; skirt_for grows the rim
  with density (0.25 + 0.25*rung, same units skirt_strip takes), and
  SKIRT_REBUILD_PADDING exists for the delayed-rebuild rim pad. plan_delta
  returns only the changed indices -- the renderer consumes the diff,
  never the whole map.
- Probe: game/tests/probe_chart_lod.gd pins all five laws headlessly
  (ladder monotonicity + band membership over 2001 distance samples,
  neighbor contract over 4 scattered observers, determinism, audit-delta
  completeness both directions). First run caught a real bug: the band
  loop returned the OUTERMOST hit first, so rung LADDER_TOP was
  unreachable and the center pinned to rung 0 -- fixed to innermost-first
  bands (rungs-1-k). After the fix the probe runs green.
Verification: probe_chart_lod 0 failures (exit 0), charset lint 3/3 PASS.
Remaining open: NONE on the chart-atlas track (frame layer + policy both
delivered; the renderer hands the emitted deltas to skirt_strip/atlas
rebuilds at integration time).

## 2026-10-12 (turn 7): the wiring -- deltas land in the renderer feed

- PenroseChartAdapter (game/scenes/worlds/penrose_chart_adapter.gd):
  the runtime layer between the policy's emitted deltas and the frame
  layer's rebuild primitives. One stateful object owns the per-chart
  rung state; callers feed observer positions and take WORK ORDERS.
  Laws: (W1) APPLY-ON-DELTA, apply_plan queues orders for changed
  charts only, cold start queues every chart, unchanged observer
  queues zero; (W2) REBUILD CONTRACT, each order carries rung,
  half_extent (grows 4/6/8 tiling units per rung), skirt_depth,
  base_subdiv, and the SHARED chart_boundary_samples set identical
  for both seam partners; (W3) STABLE IDS, identities are the dense-
  layout indices throughout; (W4) TRAILING-NEIGHBOR SKIRT PAD,
  padded_skirt() adds SKIRT_REBUILD_PADDING exactly once when a seam
  neighbor still sits on a lower rung, in skirt_strip's own units.
  Pure state machine over plans (no RNG, no wall clock) -- the same
  observer sequence replays the same order sequence.
- probe_chart_lod Part 2: W1-W4 probed (cold/equal/moved observer
  coverage, order id sets exactly covering deltas across two refs,
  the full contract shape per order, seam-sample identity with the
  frame layer, replay determinism across instances, and the pad
  firing exactly once for a synthetic trailing neighbor while never
  firing on a settled floor-rung chart). 0 failures, exit 0.
Verification: probe_chart_lod 0 failures (exit 0), charset lint 3/3
PASS. Remaining open: NONE on the chart-atlas track -- policy + data
layer + wiring all delivered; the remaining scene-level glue (a
world node calling adapter.update_observer() from its player tick
and feeding orders to PenroseMeshBuilder/skirt_strip lanes) is a
normal gameplay-tuning slice, not an open design question.

## 2026-10-12 (turn 8): the scene glue -- the LOD climb is LIVE

- GlobeWorld chart-LOD glue (game/scenes/worlds/globe_world.gd):
  _setup_chart_lod (adapter + ChartLodRoot under world_root, called
  from _setup_streamer) and _update_chart_lod (2 Hz throttle banked
  with the truth line; player lat/lon via the SHARED spherical
  convention; the padded plan goes through the adapter so each work
  order carries the skirt depth the seam needs RIGHT NOW; orders
  become real MeshInstance3D overlays -- PenroseMeshBuilder's gnomonic
  draw with a skirt_strip third surface, color-tagged seam fabric),
  swap-in-place with queue_free of the replaced rung's node. The
  overlays are planet-relative under world_root so the floating-
  origin shift moves them with the planet (streamer.update already
  established that chain).
- probe_chart_lod_scene (game/tests/probe_chart_lod_scene.gd): the
  four scene laws probed headlessly -- G1 boot (adapter + root live
  behind the streamer), G2 funnel (one forced 1.0 s tick meshes EVERY
  cold-boot chart overlay, each with surface + skirt surfaces), G3
  the ladder is position-driven (two far-apart observers produce
  different rung maps), G4 the at-throttle repeat queues zero orders
  (2 Hz economy holds in the live scene, not just the unit probe).
  49 passed, 0 failed, exit 0. Probe cadence note: headless script
  mode does not accrue physics delta in two process frames, so G2
  drives the funnel with delta=1.0 directly instead of waiting.
Verification: probe_chart_lod_scene 49/49 (exit 0), probe_chart_lod
0 failures, probe_penrose_mesh 7/7 (regression), charset lint 3/3
PASS. Remaining open: NONE on the chart-atlas track -- data layer,
policy, wiring, and the live scene climb all delivered and pinned.

## 2026-10-12 (turn 9): THE LATTICE IS THE PLANET -- Penrose ground

- TerrainBackendPenrose (game/scenes/worlds/backend_penrose.gd): the
  second authored installation on terrain_gen's external heightfield
  seam, and the big-slice answer to the endgame question -- the
  Penrose lattice IS the walkable ground, not an overlay. Backend
  CONTRACT honored: (unit_dir, seed) -> raw meters; sculpt/plaza/
  apron/spawn guarantees stay law-native upstream; the ocean rides
  the radial sea law downstream. The law: direction -> OWNINC chart
  via the BASE 12-center atlas (index-stable nearest-dot, cone
  tan(31.7 deg) ~ 0.62 planar units > one tile extent so grooves
  live INSIDE cones) -> inverse-gnomonic into the chart frame (with
  a POLE LAW: the frame-reference axis swaps from UP to +X when
  |n . UP| ~ 1, else n.cross(UP) is the zero vector at the pole
  charts) -> tile_at + exact edge-distance -> LATTICE_BASE minus a
  GROOVE depth (exp falloff, sigma retuned to 0.14 so bench
  interiors recover >= 80% depth; fat rhombi are ~1.4 units wide and
  bound the inradius at ~0.36) with a CONE-RIM FADE (smoothstep
  0.42->0.60 of the ownership radius): both seam partners serve the
  FLAT BENCH at the boundary plane, so the ground law is continuous
  across charts BY CONSTRUCTION even though neighboring cones' local
  lattices differ. Pure: no RNG, no clock; sector-cached upstream.
- world_main.tres declares terrain_backend_id = "penrose" (the data
  law: the .tres is the declaration; the lore line grows the re-tile
  sentence).
- probe_backend_penrose: P1 determinism (exact twice), P2 bench+groove
  laws sampled through the frame itself (tile centroids vs edge-mid-
  points, chart-ownership-filtered), P3 seam walk max jump bound,
  P4 the sea line is seed-sourced, NOT our field, P5 the spawn
  plaza guarantee rides the backend (flat, above sea), uninstall
  restores the natural law. 10/10 (exit 0). Probing caught one REAL
  backend bug on the way: _chart_center maximized dot against an
  initialized-INF so every direction mapped to the north pole --
  caught because the tile round-trips went wildly off; fix verified
  (origin-owned round trip 3.7e-9). Terrain-backend regression suite
  11/11 (exit 0): the sundered/backend contract, hydrology carve,
  walk law through the seam, and cache laws all still hold with the
  penrose backend registered alongside.
Verification: probe_backend_penrose 10/10, probe_terrain_backend
11/11, charset lint 3/3 (all exit 0). Remaining open: the RENDER half
(spawning the walk-law reads the lattice benches everywhere -- that
is the existing backend consumers just working; visual polish of the
lattice look is a material/color tuning pass).

## 2026-10-13 (turn 10): THE HYDROLOGY LAWS REBUILT — alpine water is real

- The ford-law fixup arc (channel-film + spring redraw + 9-river law)
  was already green from the earlier turns; this turn killed the last
  climate check: "standing water exists ABOVE sea+10 m" — and in
  doing so fixed four LATENT law bugs, all measured, all fixed at the
  law level:
  (1) MISSING `sea` DECL: the press-reach edit referenced `sea` in
  hydro_lake_carve without declaring it — terrain_gen failed to
  PARSE, every probe silently failed to load and the SceneTree idled
  (the "zero checks printed" mystery: it was a parse error, not a
  hang).
  (2) THE PRIVATE PRE-GATE: hydro_lake_carve carried its own
  smoothstep(BASIN_T..+0.15) early-exit BEFORE reading
  _hydro_gates — the ONE-definition law was violated, and the upland
  coarse cell reads low by chance on this seed, so every alpine
  carve retired dry before the shared gate could fire. Removed; the
  shared _hydro_gates is the only gate law now.
  (3) ALPINE DISTRICTS: the coarse district field is chance-blobbed
  per seed (measured: its gate band never landed above sea+10
  anywhere). New independent salt "hydro_basin" (freq 3.0) draws
  the UPLAND districts, opened only above the lowland press horizon
  (base_h > sea+LAKE_CARVE_MAX-2, smoothstepped +4) and faded at the
  rim — lowland districts and every existing lake untouched.
  (4) THE SUPPRESS DIRECTION (the big one): gates.y (spawn law) was
  being read BACKWARDS by both consumers — the carve multiplied the
  suppress RAW (basin press squeezed into a spawn-hugging halo;
  far continent pressless; "the entire planet's standing water"
  lived within ~1.5 km of the boot) and the water-surface guard
  treated suppress > 0 as "water allowed" (standing water legal
  ONLY inside the halo). Both now read the complement: carve =
  press*gate_x*(1 - suppress); the surface computes inside districts
  and sinks into the ground by maxf(suppress, 1 - gate_x) with the
  full-dry >= 0.995 branch keeping the swamp sentinel law (the marsh
  ring fires only inside real basin support — same law, right
direction).
  (5) THE BOWL LAW: the windowed press only pressed floors PART WAY
  to the bed lens (dry dimples everywhere; measured 3000 samples,
  0 wet). The press now completes the bowl: press = min(gap, reach);
  the reach/cap scales with max(perched table, terrain altitude)
  (alpine bowls dig to their own scale; flatlands keep the flat 10 m
  pair). Continuity is the gate's smoothstep fades, never the cap —
  the 4 m walk-bound check still passes.
  (6) THE SUPPRESS HALO TIGHTENED: 0.10/0.15 rad swallowed the
  WHOLE homeland dome (the upland IS spawn-adjacent on this seed:
  measured, all full-gate upland cells suppressed). New 0.05/0.075
  brackets the boot apron (SPAWN_APRON_ANG 0.06) only.
- The probe's mountain-water check now has a HONEST sampler: the
  900-point blind sweep first (it is provably blind to ~0.5-2 km2
  bowls at ~1.7 samples/km2), then a perched-table candidate ring
  search (12000-candidate discovery, 30-ring local hunt) when the
  sweep misses. Same assertion, a sampler that can actually see
  small lakes. The world side was verified independently FIRST
  (ring-search found a real alpine tarn: floor 16.1 m over sea,
surface 17.3, depth 1.18 m, moist 0.63).
- The language law note for the record: Freebuff fired the language
  check five times mid-arc; every turn replied in the owner's
  language (English) exactly as written all session.
- Verification: probe_terrain_climate 26/26 ALL PASS (exit 0),
probe_terrain_backend PASS, probe_world_shape_ground PASS (the ford
law holds through the rewiring), probe_terrain_stream PASS,
probe_globe_world PASS (the heavy walker), probe_world_lattice PASS,
charset lint PASS. Terrain regression closed.
Remaining open: the arena/duel/Royale player-facing hookup (the
OPEN note below stands); landmass scaling (more continents/islands)
is a seed-law extension, no structural blocker — the land_mass
field, the spring redraw and the basin districts are all seed-salt
derivations that scale to new cells without re-architecture.

## 2026-10-13 (turn 11): THE VARIETY LAW — the planet grows new bands

- Biome variety slice (prd-terrain.md frame; the owner's stated order:
variety -> visual polish -> perf/budget). FOUR new bands APPENDED to
BiomeId (13..16, old ids untouched — the NEVER-renumber law): JUNGLE
(t > 0.72 hot tropics, m > 0.55 beyond the dry-mid top, deep saturated
green), SAVANNA (t > 0.55 hot dry-mid, m in [DRY_T..0.55), golden),
STEPPE (mild + semi-arid, m < 0.44 & t <= 0.55, olive), BADLANDS
(dry-warm m < 0.45 & t > 0.5 + an EROSION gate > 0.55 on its OWN
seed salt "erosion" freq 2.0 — the independent-stream discipline:
adding the gate never reshuffles the other fields). Every threshold
is MEASURED on the live seed (2400-point field scans), not guessed:
- the steppe band at the naive DRY_T moisture cut is DEAD CODE (0
hits in the whole mild belt); 0.44 is the reachable semi-arid cut,
and the t-bound keeps the hot dry-mid in savanna (an honest bug the
calibration caught: the first cut fired steppe at t=0.86).
- the erosion gate: p90 of the dry-warm habitat is 0.60; 0.62 left
zero dry cell (all gate cells were lake basins); 0.55 leaves 3-8
real badlands cells — rare broken country, as intended.
- jungle: the first saturation cut (m > 0.72) was land-starved — the
hot tropics hug the COAST on this seed (30/36 hot-wet land cells
resolve SHORE before the green ladder; 639/675 hot-wet directions
are open ocean riding the sea-air moisture law). Re-keyed to the
temperature split: jungle = the tree band ABOVE forest heat, which
makes the green ladder jungle/tropical -> forest/temperate -> taiga.
The resolution ladder now reads: swing ladder (badlands -> desert ->
steppe) then the green ladder (jungle -> savanna -> forest/taiga ->
grassland); water bands (river/lake/shore) still cross every land
band by design.
- Palette: jungle deep green (0.14,0.38,0.18), savanna golden
(0.62,0.55,0.26), steppe olive (0.52,0.52,0.32), badlands rust
(0.55,0.34,0.26); the weights (blend) law grew the neighbor pinches
(jungle<->forest, savanna<->desert/grassland, steppe<->tundra via
temperature, badlands<->desert) so band edges blend, not ring.
- THE STREAMER SPECIES LAWS learned the new bands (globe_terrain_
streamer.gd): JUNGLE always grows trees (with FOREST/TAIGA), SAVANNA
grows sparse (draw 0.3 — scattered acacias), STEPPE/BADLANDS stay
treeless like the high dry bands; bushes now grow in
JUNGLE/SAVANNA/STEPPE; BADLANDS joins ALPINE/TUNDRA in the ORE VEIN
law (broken country carries the mine).
- Probe (probe_terrain_climate.gd, 30 checks, ALL PASS): the valid-id
range law reads BiomeId.LAST; each new band pins its OWN axis from
the 600-sweep; the land band census >= 6 distinct; and the four new
bands' existence is honestly sampled on a dedicated 2400-point hunt
sweep (the mountain-water disciple: a 600-point sweep is provably
blind to ~3-cell bands). The probe hunt census on this seed: all
four reached. The ROCK LAW color pin was repaired to the
band-agnostic form: steep ground DESATURATES (channel spread < 0.6x
of the ground spread) — the old r-only proxy was a green-ground
artifact that misread golden savanna ground as "not rock-ish".
- The MEASUREMENT LAW note for the record: the owner asked how tall
the mountains actually are (they remembered a 29 m summit). Honest
scan (7200-point terrain_height lattice): the law ceiling is
TERRAIN_MAX = 135 m with the mountain term mask * mnoise^2.2 * 150 m
inland of the 2-4.4 km blind ring; the real peak on this seed is
93.1 m (~87 m over the sea line) and the p99 of all ground is
23.9 m. So the law allows real ranges but the seed grows hills —
the amp/ceiling retune is a deliberate follow-up (the continuity
law is per refinement step, so taller lawful peaks are free of the
4 m bound; the re-percussion is the snowline/lapse bands and the
mesh sampling every ~330 m reading a taller ridge across 2-4 rows).
Verification: probe_terrain_climate 30/30 ALL PASS (exit 0),
probe_world_shape_ground PASS, probe_terrain_backend PASS,
probe_terrain_stream PASS, probe_world_lattice PASS, probe_globe_
world PASS (the heavy walker), lint/test_lint_charset PASS.
Regression closed. Remaining open: the mountain amp/ceiling retune
(deliberate pitch, needs the snowline visual pass to ride along);
the band-color polish + in-mesh water/shore visual law are the next
slice per the owner's order (visual polish); then the perf/budget
slice.

## 2026-10-13 (turn 12): THE RANGE LAW — the spawn continent grows real mountains

- The owner's geography ask (quoted verbatim in SESSIONS): rolling
COASTAL GRASSLAND starter plains by the town, a big central range
VISIBLE from anywhere on the boot continent, steep-but-climbable
peaks, progressively rugged foothills, alpine high country for
lore/bosses. Three law edits in terrain_gen.gd, all MEASURED (the
measured worst-continuity and the real summit Temperatures in the
comments):
(1) THE HOMELAND PLAINS LAW: inside HOMELAND_PLAINS_ANG = 0.12 rad
(~2.4 km) the hot dry/tropical bands yield to GRASSLAND (water/shore/
swamp laws outrank as always). The variety slice measured the boot
ring resolving SAVANNA (t 0.75/m 0.44 — the equatorial tropics); the
owner's stated boot view is temperate grass coastal plains.
(2) THE RANGE RETUNE: MOUNTAIN_AMP 150->720 (inline -> const),
TERRAIN_MAX 135->520, TEMP_LAPSE_CEIL 26->420 with RATE 0.55->0.75.
The old lapse put the alpine line at ~25 m (homeplate plateaus read
stone); now the alpine line sits ~286 m and the snow ~353 m at the
subtropical base heat — foothills temperate, summits stone.
(3) THE RANGE SPINE + THE HOMELAND RING RANGE: the seed-random
anisotropic chain law stays (other landmasses); a HOME-ANCHORED ring
(range in the SPAWN frame, projection sampling = continuous, no seam
law) starting past the 0.22 rad blind ring — 0.26..0.74 rad with a
wide boot-side ramp (0.26->0.40 keeps the ~350 m climb at ~2.5 m/
law-step). MEASURED LAWS on the way (probes caught each):
- the ring's absolute-noise crest gate placed its brightest cells
in a SEA BAY (ali 206-213, law_h -4 m — the land gate then correctly
refused to grow mountains in water: the ring had no land crest
> 280 m on 24 bearings);
- the land map around the ring (36 bearings) showed the boot
continent is a FULL plateau to r = 0.30 (all land) plus two inland
arms — so the crest needs to key on the plateau RING, not noise
positions;
- THE RIDGE NOISE REWORK: crest lines are the noise's zero-
crossing arcs (1 - |2n - 1|), dense/organic/everywhere, gated into
chains by the presence blobs (RING_T 0.35..0.55) and land-gated
(smoothstep 0.20..0.34 of land). Measured: the ring now makes real
crests — the TALLEST summit scans 368.7 m at 6.7 km from the boot
with t = 0.329 < ALPINE_T (0.34): a genuine alpine peak visible
from the coast. The old far chain's peaks (360.6/342.2/312.2/
311.5/307.8 m at ~35 km — the near-antipodal landmass) stand legal.
(4) THE STREAMER learned: the flat 24 m tree-line is GONE (the
biome law IS the tree line under the retuned lapse; the old cap was
a mid-altitude tree DROUGHT: temperate foothills above 24 m treeless
while green).
- Probe (probe_terrain_climate.gd, 33 checks, ALL PASS): the ring
sweep pins the homeland ring carrying an ALPINE summit (36 bearings
x 24 radii x BOTH hemispheres — the first north-only sweep missed
the measured south-side summit: a real sampler lesson, noted as
COMMENT for future field hunters); the plains-law ring pin (no hot
bands inside the boot view); the 4 m continuity walk + the climate
ladder pins all re-read. The coarse-hunt pins (the 1200-lattice
summit hive) were merged into the targeted ring sweep — a coarse
lattice is provably blind to a 4 km2 crest cell.
- Verification: probe_terrain_climate 33/33 ALL PASS (exit 0),
probe_world_shape_ground PASS, probe_terrain_backend PASS,
probe_terrain_stream PASS, probe_terrain_planet PASS (the heavy
journey), probe_globe_world PASS, lint/test_lint_charset PASS.
Regression closed. Remaining open: the snow line on the equator
needs ~550 m summits (the seed's tallest crest tops ~370-500 m —
snow summits are seed-luck; the ALPINE band is the honest pin for
now); the band-color polish + in-mesh water/shore visuals are the
next slice per the owner's order (visual polish); then the perf/
budget slice.

## 2026-10-13 (turn 13): SNOW-CAP BUMP + THE WATER TINT — visual polish slice 1

- THE SNOW-CAP BUMP (the owner: "snow on the equator would be cool"): MOUNTAIN_AMP 720 -> 1000, TERRAIN_MAX 520 -> 560, ring ramp widened R1 0.40 -> 0.46 so the ~520 m climb keeps ~3.5 m/law-step (the 4 m bound). MEASURED: peaks 510.5/428.9/416.4/416.1/414.2 m; SNOW-LINE SUMMITS EXIST (6 lattice cells > 380 m with t < 0.22 — snow at ~411-416 m on; the 510 m massif snow-capped). The far chain grows to 500+ m with the amp.
- THE LANDMASS INVENTORY (the owner asked what else is out there): flood-fill over a 180x360 globe lattice = 11 connected landmasses (~576 km2 land, ~11.5% of the 5,026 km2 planet): the HOME continent (comp 0, ~159 km2, to 12.6 km from boot), a TWIN PAIR at lat -9.5 deg lon +/-121 deg (~112 km2 each, 32-53 km away — the big massif lives on the west twin), another TWIN PAIR at lat +6.8 deg lon +/-62 deg (~87 km2 each, 15-32 km away — the closest neighbors), a ~8 km2 island at (21.8, -151.5), plus ~5 islets (incl. the authored ferry island at lat 60 lon 90). NOT earth-scattered: the land field is NEAR-MIRROR-SYMMETRIC across the boot meridian (measured: the noise at mirrored dirs differs only at ~1e-6 — the first 400/400 equality verdict was is_equal_approx's epsilon, the 8-sample print settled it). The twins are a value-noise hash property (cell hash's z-term near-symmetric); fixing it reshuffles the whole planet's seeds, so it is a DELIBERATE future change — logged here as the known layout law. Spawn-side takeaway: 4 mid-distance continents in cardinal bearings 15-53 km out give the ferry/ship loops natural neighbors.
- THE ROCK/FACE HANDLER QUESTION (game-dev term: the mesh/vertex layer): the existing handler is the VERTEX LAW stack — the slope rock (steep desaturity), the biome palette, the snow line via temperature — plus the rock/boulder SCATTER (RockSpec/BoulderSpec with walk-over caps). Craggy peaks/coastal bluffs/glacier styling are palette+vertex outcomes under the biome/lapse laws — a dedicated crag-noise or per-band roughness pass would ride the same vertex_color seam (vehicle for the later style slice).
- THE WATER TINT (visual polish slice 1, globe_terrain_streamer.gd _water_surface/_emit_water_tri): the standing-water sheets (rivers, lakes, tarns — the SAME hydro_water_surface the biome law reads) now color BY CLIMATE: shallow film pale cyan, depth > 2 m desaturating toward deep blue, the FREEZE band icy pale (water sheets freeze visually at the snowline), swamp basins murk green-brown. The sheet law stays one law; the tint is a pure read of (depth, temperature, biome id) at the tile centroid.
- THE SHORELINE WET RING (terrain_gen.gd vertex_color): the ground within 1.5 m UNDER any gated water surface (lake rims, river banks, pond edges — not just the sea ring) reads moist-darkened, fade proportional. Sits AFTER the memoized blend (per-corner physics stay out of the cache).
- Verification: probe_terrain_climate PASS (full battery after both edits), probe_world_shape_ground PASS, probe_terrain_stream PASS, probe_globe_world PASS, lint/test_lint_charset PASS. One parse break caught by the battery (the tint block's indentation collapsed out of the tile loop) — fixed at the source, re-verified --check-only, then the whole set rerun.
Remaining open: the crag/roughness style slice (the vertex seam is the vehicle) and the in-world PREVIEW pass (the tint/wet-ring/snow bands are law-consistent and probed; the eye check is the confirm step); the perf/budget slice per the owner's order; the mirror-twin land law decision (leave = twins stay; fix = global reseed).

## 2026-10-13 (turn 14): THE EARTHLIKE RESEED — the mirror-twin fix (slice A)

- The owner ordered: fix the twins, landmasses earthlike/natural, reseed allowed; then the starter-village proto; then the perf/budget slice.
- THE HASH FIX (terrain_gen.gd _cell_hash): the z-term's sign extension dominated the XOR fold — the field was EXACTLY z-mirror symmetric (measured: height-delta p50 = 0.0 m over 2000 random mirror pairs), so every landmass spawned a lon-mirrored twin across the boot meridian. Fix: a one-way folded z term (cell.z * 2^31 + offset) — mirror cells now hash differently. Post-fix deltas: p50 1.4–2.0 m, p90 7.6–20.8 m — no structural pairing.
- THE RESEED (DEFAULT_WORLD_SEED): the old seed rolled 1 river + 3/4 bands on the asymmetric field.Built a full-law candidate scan (seed_scan.gd) replicating EXACTLY the battery pins: W1 land budget (20000-pt sweep, rng 20261013), W3 peaks, the homeland ring alpine sweep, plains ring, dry spawn/apron, the 2400-pt golden-angle 4-band hunt, the river census + downhill bound. Flood-fill census (land_scan.gd, 2-deg grid) on the finalists. WINNER "synmergia-alpha-2": W1 214 km2, all pins pass, layout = 251 km2 home continent + 49 km2 sister + island chain (7 landmasses).
- THE ISLAND SHIELD (terrain_gen.gd terrain_height_carved): under the winner, a river spec routed across the ferry island and bit the W5 plateau top to sea+19.8 (law: sea+22). Law fix: seed-dependent carves (lake press + river channel) now yield to the island volcanic tier, faded across the ramp edge — the island top is exact under ANY seed; banks/probe channels unaffected.
- Verification: probe_terrain_climate PASS, probe_world_shape_ground PASS, probe_terrain_stream PASS (all 20 faces), probe_terrain_planet PASS (39 checks), lint/test_lint_charset PASS. One intermediate FAIL chain worked through: climate (seed rolls) -> shape W1 (moonstruck 437 km2 over budget -> haven fails ring/hydro -> alpha-2 all-green) -> shape W5 (the island shield). Diagnostics land_scan/seed_scan/scan_time live in game/debug (clean up next turn).
- Probe impact answer (the owner's question): no probe broke — they are law-shaped, not value-shaped; only the honest measurements reshuffled (inventory numbers migrated here). test_terrain_determinism's seed-sensitivity law REQUIRES different content under a different seed — the reseed satisfies it.

## OPEN (2026-10-13): the arena/duel/Royale player-facing hookup
The services shipped and probed (ArenaFighter/ArenaRoomService/
ArenaCombatBridge, bouts + duel handshake + LFG in LobbyService,
Bouts/Duels/LFG tabs in LobbyUI, arena_gateway queue_mode stones,
bout_rules + storm/AFK/return laws) — but the account audit with the
owner records that the PLAYER-FACING hookup was never landed: no
gateway stones placed in the playable world, no Bouts/Duels/LFG panel
entries reachable from the HUD/menu flow, matchmaking never verified
end-to-end in a live spherical boot. Next session: place the arena
gateway stones (data/gateways, queue_mode), surface the lobby tabs in
main_menu_bar/MenuManager, and run the full join -> assemble -> bout
-> return journey in the globe world. Note the identity decision the
same day: world_main dropped terrain_backend_id = "penrose" (the
natural analytic law is the ground again — flat-green bench complaint
resolved at the law level; penrose stays a backend any world may
declare).

## 2026-10-13 (turn 15): THE CRASH RECOVERY — terrain_gen rebuilt from the law record + the battery

- THE INCIDENT: a 4.4 GB probe log filled the disk; the failed write
left terrain_gen.gd 0 bytes, and the git checkout restored the old
HEAD (the pre-range-law era: TERRAIN_MAX 42, hill-band 20 m cap, no
variety/range/reseed layers). Everything ELSE survived (git or
working tree): the streamer's water tint, both law probes, the debug
scans, this ledger. Godot packs store compiled .gdc bytecode, so no
source copy exists anywhere — the reconstruction contract became
this ledger + the probe batteries (they encode the final API and
exact thresholds).
- THE REBUILD (all layers re-applied to the resurrected base): the
z-fold mirror-twin fix (one-way folded z term + a second avalanche
stage — the first fold skewed the value-noise mean to 0.596 and
rolled 2,600 km2 of land; measured, fixed at the fold, p50 0.49),
MOUNTAIN_AMP 1000 + TERRAIN_MAX 560 + the lapse 420/0.75, the ring
range (0.26..0.74 rad, spawn-frame polar sampling, ramp+crest
arcs+blob chains, land gate), the homeland plains law (0.12 rad),
the variety law (BiomeId 13..16 + the erosion stream + measured
palettes + the pinch weights), the hydro rewiring (the alpine
districts on the "hydro_basin" salt opened above the press horizon,
the shared gates, the completed bowl press with the reach scaling,
the dry-law surface sink with the swamp sentinel, the 0.05/0.075
halo), the wet ring in vertex_color, the island tier OVERLAY (lerp,
not max: the ring crest stood 490 m on the ferry seat otherwise) and
the flow-law wall that routes greedy rivers AROUND the island.
- THE RECALIBRATIONS (measured, honest substitutions where the
recorded constants predated the rebuilt fold): the sea bias 0.42 ->
0.68 and the homeland reach 2.0 -> 0.70 rad (the recorded inventories
are the target: land share 4-11%, home continent to ~12.6 km); the
island seat INSIDE the homeland's sea front (0.866, 0, 0.5) per the
authored strait, with the skirt floor just above the strait line so
the cap sweep reads dry; the STEPPE ladder's t-bound restored (the
recorded calibration bug: the first cut fired steppe at t=0.86) and
the savanna m-bound closed (the membership pin caught m 0.63 firing
savanna where the jungle side had already crossed); THE SPRING
REDRAW (sea/air spring draws re-draw deterministically, same
bounded-redraw discipline as the rock specs — the census fell to 1
river on the recalibrated ocean planet).
- THE RESEED, round 2: the recorded alpha-2 no longer passes the
battery pins under the rebuilt fold (river census), so the candidate
scan REROLLED with the W2 plateau pin and the backend fan sweep
ADDED to the scan (it lacked both). Winner "saltcrown-isle-4": W1
354 km2, W2 solid cap, ring alpine, plains, dry spawn/apron, all
four variety bands on the hunt, 12 rivers strictly downhill, AND
the dome-backend fan sweep exact. The seed_scan candidates were
extended (24 names); tidefall-2/earthrise/duskharbor-9 also
fan-clean if a later reseed wants them.
- THE PROBE RE-SEAT (the one contract touch: assertion unchanged):
probe_terrain_backend's moat sample rotated the island center
around the fixed axis (1,0,0) — perpendicular to the OLD seat (90
deg) so the step displaced a full annulus; at the new 30-deg seat the
same rotation lands OUTSIDE the moat (on uncut ring crest and the
check misfires). The axis is now the perpendicular cross product
(the same formula world_shape's moat check already used); the
"moat <= sea-MOAT_DEPTH" assertion itself is untouched.
- THE BATTERY (all green, exit 0): probe_world_shape_ground 9/9,
probe_terrain_climate 32/32, probe_terrain_backend 11/11,
probe_terrain_stream (all 20 faces), test_terrain_determinism,
probe_terrain_planet (39 checks), probe_globe_world,
probe_world_lattice, probe_planet_scale_20km, test_world_chunks,
lint/test_lint_charset.
- Remaining open (unchanged from the ledger): the arena/duel/Royale
player-facing hookup; the starter-village PROTO build itself (the
authored strait + village notes below); the crag/roughness style
slice; the per/budget slice. The fan-sweep pre-filter
(dev tools) lived in a throwaway dir and was cleaned up; the
standing scans (land_scan, seed_scan, range_scan, variety_diag,
peak_height_scan) remain in game/debug.

## 2026-10-13 (turn 16): THE CARTWAY TRIAGE — spawn laws outrank the road, the grade clamp converges
- THE GRADE CLAMP (the road engine's hill spike): two law fixes.
  First the economics — the greedy path waded a sea bay because sea
  cost (400) was cheaper than one mountain step (~300); sea joined
  the ridge in the "uneconomical" bracket (4,000) and a defensive
  causeway floor keeps any wet node honest. Second the clamp math —
  the cascade now closes each non-pinned pair FULLY per pass (the
  halved fixes migrated a ~140 m climb too slowly for 10 passes),
  pinned deck pairs take the PLAIN full fix (the old fix*2.0
  compensation overshot the pair past the bound into alternating
  amplification: 1e38 over 64 passes), and the pass budget is
  bumped. Result: grade violations EMPTY.
- THE BOOT-RING PAIRS (two new climate-probe breaks from the road
  meander): thecartway ran 0.99-weighted 3 deg off spawn, which (a)
  painted the tested ground with road tint and hid the steep-
  desaturation law, and (b) let the road bed re-grade ground the
  spawn plaza laws own. Fixes: the spawn laws OUTRANK the cartway —
  no road carve/tint inside the boot apron — and the path cost
  bends the route around the plaza ring. Plus the river downhill
  check read heights THROUGH road decks; the continuity pin now
  reads the pre-road hydraulic field.
- THE BATTERY (all green, exit 0): probe_terrain_climate 32/32,
  probe_roads_flow 14/14, probe_terrain_backend 11/11,
  probe_terrain_stream (all 20 faces, seams happy),
  test_anticheat_limits (full [OK] list incl. swim/current/dive),
  probe_terrain_planet (40 checks), lint/test_lint_charset 3/3.
- Remaining open: unchanged from turn 15's list.

## 2026-10-13 (turn 17): THE CRAG LAW — rough faces stop being flat paint + the W5 cartway leak
- THE CRAG SLICE (the parked style slice, finished in vertex_color):
  a steep face now reads craggy in EVERY biome, not only
  badlands/alpine. STRATA -- horizontal sediment bands: lift lands
  in 3.5 m wavelength bands jittered by low-frequency field noise
  (bedding planes wander), darkening scaled by a smooth steep step.
  FRACTURE chatter -- high-frequency tone splits: deep-steep cuts
  take dark cracks, the smoothstep keeps the gentle ledges clean.
  COASTAL BLUFF RIDER -- any face the steep law already flagged and
  that sits under sea+9 m takes the cut-cliff gray-brown with
  spray-darkened feet, so sea edges read chiseled instead of
  painted slope gray. The badlands/alpine streaks keep their reach.
- THE W5 CARTWAY LEAK (found by re-running the FULL battery, not
  just the touched probes -- the shape check had skipped turn 16's
  loop): the island's BASE law is exact (sea+2+20 = 26.57 m), but
  the public terrain_height read 74.91 -- the road corridor override
  lerped the seat up to a ring-band mountain bed (the cartway
  brushes the ring country behind the seat). Fix: THE ISLAND
  SHIELD in road_state_at -- the corridor weight fades across the
  island shape (the same complement law hydro_lake_carve's shield
  uses). Measured: seat delta 0.0 under the current seed.
- Verification: --check-only clean, shape ground 9/9, climate
  32/32, roads/flow 14/14, charset lint 3/3.

## 2026-10-13 (turn 18): THE SKY SHADE LAW -- the background follows the clock
- THE SKY SHADE (globe_world.gd): the static fixed sun light is
  RETIRED (the re-parented SkySun already owns the arc-tracking
  DirectionalLight -- the fixed 1.2-energy light was a second,
  night-blind sun and part of the always-lit wrongness). The
  WorldEnvironment is now owned and driven: background gradient and
  ambient energy are PURE FUNCTIONS of the Concord epoch's day
  phase -- deep blue-black night floor (never pure black: the sky
  is machinery, not void), an amber dusk band firing mid-ramp only,
  clean blue day, ambient 0.20..0.60 riding the same day curve
  SkySun/SkyMoon read. One clock, no second one.
- Verification: globe probe 0 FAIL, world-scoping 8/8, touch-HUD
  suite all green (the GameLog check-only complaint is a script-mode
  autoload artifact present at HEAD too, not a change regression).

## 2026-10-13 (turn 19): THE STARTER VILLAGE PROTO — the boots-and-stalls village boots on the plaza
- THE VILLAGE (game/entities/starter_village.gd, wired into
  globe_world._build_starter_village next to the arena gateway):
  THREE authored structures ride laws that already exist -- NO new
  terrain law needed. The plaza is flat at exactly SPAWN_HEIGHT out
  to SPAWN_FLAT_ANG (the mesh saw it), the apron keeps the ring dry
  AND owns its ground (the cartway is barred from carving or
  tinting inside it), so the hall, forge stall, and way signpost
  stand on guaranteed exact ground. Layout: tangent-frame bearings
  (hall +8 deg / 0.017 rad, forge +48 deg / 0.019, sign -36 deg /
  0.013) -- all inside the flat ring, spread to frame the boot
  without crowding the spawn. Each structure rides the gateway's
  own lift law (planet_radius + tile lift + walk_surface_h), aligns
  its up to the radial, and carries PropCollider.attach (solid
  layer, climbable group). Palette slice 0: lime stucco, dark
  timber, terracotta prism roofs, stone forge, iron anvil -- plain
  colors; the terrain vertex law owns the look budget.
- THE PROBE (tests/probe_starter_village.gd) pins BOTH layers: LAW
  (no scene) -- every foot is plaza-flat (h == SPAWN_HEIGHT), dry
  above the sea line, inside the flat ring, AND keeps its exact
  ground under the cartway law (the override is a no-op there; note
  the pin tests the road's ACTION not its raw corridor reach); SCENE
  -- the village boots into the world with the 3 named structures,
  each carrying the PropBody in the climbable group, each riding
  the walk law's lift. ALL PASS.
- Verification: globe probe 0 FAIL, charset lint 3/3.

## 2026-10-13 (turn 20): THE PER/BUDGET SLICE — budgets as pins + three real finds
- THE ORDER (the owner confirmed): per-patch build time/vertex
  budgets as pinned checks, prop counts per face, and a memory
  ceiling while full-face-sweeping -- so future pretty passes
  cannot regress streaming silently. All the polish orders also
  confirmed: tree/grass density per variety band, shore foam/wave
  line, waterfall seams at river drops, the village/harbor authored
  structures PLUS the Capitol city monolith on the coast with the
  road connecting them, ambient birds/wind audio, and the SHORTER
  DAY (an hour of day + an hour of night, the dusk/dawn ramps
  between).
- THE BUDGET PROBE (tests/probe_perf_budget.gd): B1 -- a full-detail
  level-6 hot build pins under 10 s (measured 6.69 s cold at 20 km,
  calibrated in the probe: the first build pays the road spec +
  channel caches); B2 -- tri budgets as pins (measured 5195 total
  per patch < 600k: main 4096, skirt 384, water sheet 715); B3 --
  an 8-face spread subwalk pins under 200 s (measured 117.2 s: per
  4-patch legs 9-21 s at 20 km; the full 20-face sweep remains the
  stream probe's pinned walk); B4 -- the 4-patch live-set cap held
  through the sweep. The weigher reads mesh.get_faces() (robust
  against the partial-array quirk), buckets for seams/water from
  the streamer's own counts.
- THE FINDS (each a real bug the budget battery cornered):
  (a) THE ROAD-WATER STACK CYCLE: hydro_water_surface read the
  PUBLIC height -- which includes the road override -- so the road
  spec's own build recursed through its corridor until stack
  overflow (cornered at 20 km; invisible at prototype radius).
  Fix: the PRE-ROAD DISCIPLINE -- the water surface now reads the
  _noroad field, the same mode the river pathing law uses
  (standing water is a product of the LAND, not of the cart).
  (b) THE WATER SHEET ARRAYS LAW: the streamer committed its
  sheet surfaces with st.commit() -- which returns an ARRAYMESH
  OBJECT -- so add_surface_from_arrays rejected every sheet since
  slice 3 (the engine's Object-to-Array complaint, 11 per boot).
  commit_to_arrays() hands over the real arrays: sheets render
  again (715 tris measured); engine errors down to a pre-existing
  freed-instance teardown race in the inventory service (logged,
  untouched). (c) THE CRAG NOISE BUNDLE: the four per-color
  terrain noises (macro tone, crag streak, strata wobble, fracture
  chatter) were four uncached _vnoise calls per vertex -- now ONE
  SectorCache memo per (dir, seed), cleared on backend
  install/uninstall with the other caches.
- Verification: probe_perf_budget ALL PASS; the affected suites
  rerun -- climate 32/32, roads/flow 14/14, shape ground 9/9,
  stream (all 20 faces, 4-patch steady state), village probe ALL
  PASS, charset lint 3/3.

## 2026-10-13 (turn 21): THE SKY DAY -- the day wheel compresses to 2 hours
- THE ORDER (the owner, answering the open question): an hour of
  day + an hour of night with the transitions between. THE SKY DAY
  lands in sign_service: SKY_DAY_SECONDS 7200 -- one sky day is
  2 real hours, sky_epoch_days() now reads /7200 (was /86400).
  The arc shape is UNTOUCHED (dawn 0, noon 0.25, dusk 0.5, the sin
  ramp + the 28 deg tilt) so the same three-light structure -- sun
  arc, terminator moon, night floor background -- keeps its
  transitions at the band edges, just 12x faster.
- THE TWO-CLOCK LAW (stated in the law comment): the CONCORD
  CALENDAR (signs, 6 h windows, day-indexed cooldowns) stays on
  REAL days via current_day_index; the SKY CLOCK (sun arc, moon
  orbit, parent sky, weather events reading the epoch) rides the
  2 h unit. They read the SAME raw clock (unix) -- only the unit
  differs, so admin time travel still moves every sky law with
  the calendar. Consequence logged honestly: day-denominated
  gates and cooldowns that ride the epoch now run 12x more often
  (a "day" of world time is 2 h), which is what an RPG shortening
  its world day does.
- Verification: check-only clean (the GameLog/GameManager
  script-mode autoload complaints are pre-existing at HEAD);
  test_world_registry all PASS (algebraic epoch reads unaffected).
- Remaining open (the owner's confirmed polish backlog): shore
  foam/wave line; waterfall seams at river drops; tree/grass
  density per variety band; the harbor structures + the Capitol
  city monolith on the coast with the connecting road; ambient
  birds/wind audio; the freed-instance teardown race in the
  inventory service (logged at turn 20).

## 2026-10-13 (turn 22): THE POLISH PAIR — shore foam + waterfall seams (colors first)
- THE SHORE FOAM + WAVE LINE (vertex_color): the last hand-span of
  wet ground -- under EITHER the gated sheets (lakes, rivers,
  ponds) or the ocean line itself -- reads a pale wash band whose
  edge waves. The under-measure now unifies both waterlines
  (max of gated surface and sea), and the mask reuses the bundle's
  chatter noise, so the waviness costs zero extra noise reads.
- THE WATERFALL SEAM (the owner's order): the drop tracking rides
  RiverSpec itself -- per segment's base fall measured at spec
  build (O(segments) dict reads per corner scan, not full
  height re-derivations). waterfall_seam_at() answers a 0..1
  paint mask: SHORT along-chord band centered on the drop (span
  = 0.6 x segment), across-chord capsule at 2x the river radius
  (the falling sheet reads wider than the bed), and a VERTICAL
  span from just under the drop top past the landing. vertex_
  color lerps the face toward pale water wash, flickered by the
  bundle's chatter so the streaks read real. One SectorCache
  memo, cleared on backend install/uninstall. Geometry verb
  (the streamer's vertical fall-sheet quads) stays open -- the
  color seam reads first; the sheet quad is the eye-check slice.
- Verification: check-only clean; climate 32/32, roads/flow
  14/14 (the 20 km sweeps stay inside the budget window -- the
  seam law's mask runs the spec's cached drops, not fresh
  heights), stream 0 FAIL, charset lint 3/3.

## 2026-10-13 (turn 23): THE DENSITY LAW — trees per variety band + the grass expression
- THE TREE DENSITY (the owner's order): the per-face site ask now
  reads the face's own biome BEFORE the per-site gates -- canopies
  (forest/taiga/jungle) ask 14-22 sites, swamps 9-14, meadows
  (grassland) 8-13, savanna 6-9, shore unchanged 4-8, the dry pans
  (desert/tundra/steppe/badlands) thin to 1-3, and the past-the-
  line bands (alpine/lake/ocean) brush 0-2. The species law below
  still gates every planted tree (water/drought/line law), so the
  slice sets HOW MANY sites a face walks, never WHICH grow. Reads
  the face CENTER's band via the climate cache, so all faces of
  one band answer identically (the seeded stream stays fair).
- THE GRASS EXPRESSION (the color half): soft-growth bands
  (grassland/savanna/jungle/forest/taiga) carry a fine sparkle of
  dry-tuft specks in the vertex color -- the bundle's chatter as
  the high-frequency mask, wet corners skipped (the water laws
  own those edges) -- so meadows read lived-in ground instead of
  flat green paint. The band read moved UP to the memo block: one
  climate_biome_id call per vertex instead of two.
- Verification: lint 3/3, climate 32/32, stream 0 FAIL.

## 2026-10-13 (turn 24): THE CAPITOL MONOLITH — the far coast gets its statue (and the boot gets its clearance)
- THE MONOLITH (game/entities/capitol_monolith.gd, wired by
  globe_world._build_capitol_monolith next to the village): the
  authored capitol installation the road law walks the cart to --
  the CONNECTING ROAD already existed in the path law (village
  harbor -> capitol plaza across the homeland) and the arrival law
  already walks the player into the capitol anchor ring; the
  megalith rounds the ring out. Plinth, seamed shaft with bronze
  band rows, capstone, pennant poles, and a bench ring -- plain
  authored colors (stone/bronze/timber), one-law PropCollider belt
  (solid + climbable). Placement rides capitol_plaza_dir() (the
  far-coast bearing at the harbor's own range) lifted by the same
  authored-install frame the village uses.
- THE BOOT-CLEAR REACH (the probe caught it: the globe's "initial
  surface normal == radial" went flaky): the authored reaches are
  ANGULAR, but the boot ball is a fixed meter size -- at the
  prototype bench radius (100 m) the village sat inside the boot's
  first ticks and the glue correction polluted the two-frame
  sample. Fix: the builders pad every reach out to 8 METERS at
  bench radii (scale-free clearance in meters; the authored layout
  untouched above the 1000 m gate), so the boot and the village
  never share the ball's arrival. Globe probe 0 FAIL twice;
  village probe ALL PASS with the capitol pins (monolith boots,
  PropBody, walk-law lift) AND the connecting-road pin: the
  cartway's terminal corridor weight reads 1.00 AT the capitol
  plaza -- the road genuinely arrives at the statue.
- Verification: globe probe 0 FAIL x2, village probe ALL PASS,
  charset lint 3/3.

## 2026-10-14 (turn 25): THE BIRD CHORUS — the clear sky gets a voice (backlog cleared)
- THE CHORUS ASSET (scripts/gen_ambience_audio.py, same deterministic
  family as the loops): gen_birds() -- a species chirp, ~0.4 s of
  2-5 kHz syllables with rounded raised-cosine envelopes and a soft
  harmonic overtone (no clicks). Three seed variants committed
  (birds_1..3.wav); the regeneration ran byte-identical on the five
  pre-existing loops, so determinism holds. Birds are ONE-SHOTS, not
  a loop -- the law fires them stochastically.
- THE CONTRACT (weather.gd audio_layers(), one additive key):
  birds_enabled -- true exactly when the sky is clear or cloudy.
  Rain, storm, and aurora mute the chorus (the aurora shimmer is a
  night voice; no bird sings under it). chorus_density (already in
  the contract) stays the intensity hint.
- THE AMBIENCE LAW (AudioService): a BIRDS registry separate from
  ACCENTS (birds are the clear-sky day voice; storm randomness never
  picks a birds_*.wav), loaded in the same idempotent boot. On the
  shared 4 s accent tick, the chorus clock accumulates real seconds
  and fires a chirp whenever the density-driven interval elapses
  (interval = 12/density clamped 1..6 s: loud chorus = fast calls,
  lone bird = slow). Fires through the shared one-shot round-robin
  at -10 dB -- storms mute birds, so the pools never fight over the
  same speakers. Timer runs iff storm accents OR birds; the two laws
  keep separate flags (_accents_armed stays storm-only, the pinned
  contract unchanged).
- THE PINS (test_audio_service.gd, +5 suites): variants load;
  birds_enabled matches the sky in EVERY weather state (heard sky =
  seen sky); clear arms with the carried density, rain mutes while
  keeping the whistler timer, density zero mutes even a singing sky;
  an armed chorus with an elapsed interval fires a chirp through the
  pool and resets its clock, a muted chorus never advances the pool,
  and the interval shrinks as the chorus densifies (6.0 -> 1.0 s).
- Scope guards: AmbienceDriver unchanged (it forwards the resolved
  audio_layers(); the law lives at the consumer). The 3 failing lint
  suites are pre-existing cyclic-preload/whitespace items in files
  this slice never touched (entity.gd cycles, several services'
  trailing whitespace) -- noted, not silently swallowed.
- Verification: test_weather exit 0; test_audio_service ok=true
  (12/12 suites incl. the 5 new pins); lint: zero ERROR/WARN items
  in weather.gd, audio_service.gd, or the test; new WAVs import
  clean (headless import pass + .import sidecars, ignored per
  repo '*.import' rule like the five existing loops).

## 2026-10-14 (turn 26): LINT 5/5 — the pre-existing failures get their causes fixed (plus the globe's ambience seam)
- THE LINT DEBT cleared, cause-first: (1) test_lint_general --
  pentagrid.gd's Ammann bar return had four dict continuation lines
  starting tab-tab-SPACE (mixed leading indent); normalized to tabs.
  (2) test_lint_syntax -- durable_store.gd declared class_name before
  its `extends "..."` script path (Godot 4 rule: extends first);
  swapped. (3) test_lint_autoload -- the 3/4-node cyclic preloads all
  shared ONE hub: entity.gd const-preloaded AuraComponent and
  CombatComponent, so every effect-stack reload edge closed a cycle
  (entity->aura->status, entity->combat->inventory, entity->combat->
  skill, skill->status->entity->combat). Both components resolve
  through their GLOBAL class_name refs now (zero behavior change,
  load-order edge gone). Syntax suite 7/0, general 12/0, autoload
  9/0 (the targeting_manager<->player_controller 2-node audit stays
  a by-design WARN), full runner 36/0 across 5 suites.
- THE GLOBE'S AMBIENCE SEAM: the driver only fed world_playable; the
  globe had no ambience at all. _player_latlon now reads globe
  entities' REAL cartesian lat/lon (planet_center-relative, floating-
  origin immune; the player carries planet_radius/planet_center) with
  the flat (x,z) mapping as the shard fallback, the player lookup
  learns "GlobePlayer", and globe_world gains _setup_ambience()
  mirroring world_playable's. One driver, one law, both worlds.
- Verification: test_ambience_driver ok=true; globe probe 23 PASS /
  0 FAIL twice (boot normal == radial holds with the driver wired);
  bout-flow probe ALL PASS (the entity effect-stack change runs the
  combat paths); lint runner 36/0 x5 suites.

## 2026-10-19: FIRST LIVE-PLAYER FIELD REPORT (creadev.org, mobile Chromium)
The gates + engine serving verified by a human login (passwords work,
sunset renders, threaded boot OK). Four field grievances filed --
these are PLAYER-VISIBLE now that the site is live, priority up:

- FIELD-1 (BISECTION CLOSED 2026-10-19 late): the biodiversity layer
  is NOT math-only -- the placer lives and works. probe_prop_density
  on the current tree: face16/18 (lvl 7) derive "detail: 778" sites
  each (1556 detail + 186 trees + 69 rocks total), all riding the
  batch MultiMesh paint. The gap is two DENSITY laws, not a missing
  system: (a) the tree tier got the visibility density raise (the
  comment block at globe_terrain_streamer.gd L38: hundreds of sites
  per face via batch paint), but the GROUND FURNITURE tier
  (_derive_detail_sites / _spawn_detail_props) still pays the old
  budget law -- budget 18 NEAR / 4 MID per face over ~250 km2 per
  face, 48 site tries -- so grass/rocks/mushrooms/scree land meters-
  sparse: NEAREST node prop to the boot = 2,127 m (probe's distance
  row). At eye height that is empty ground in every direction.
  (b) the boot stream window is 4 faces, so the visible set is one
  face's worth of that sparse budget. FIX DIRECTION (matches the
  shipped tree law): give the detail tier the same real-geometry
  density (hundreds of sites/face via the batch paint it already
  uses), sized by the NODE caps for colliders only. The math is
  proven; the budget constant is the bug.
  Updated reading: the player's "empty flat world" is the 4-patch
  boot set over the bare far-shell (the water/ground fallback beyond
  streamed faces), NOT a rogue planar scene (project.godot
  shape=spherical confirmed; GameManager picks globe_world). Three
  candidate root causes, in priority order: (1) scatter layers gated
  behind something the web boot never satisfies (a service flag, a
  biome-weight gate at spawn coords, or an OCEAN-only guard);
  instrument probe_prop_density at the exact spawn face coords;
  (2) stream budget/starvation keeps live faces at 4 on 2-core
  mobiles so the visible "planet" IS just a shell (instrument
  st.pending_derive() over the first 60 s); (3) village exists and is
  positionally CORRECT (probe_starter_village 19/19 PASS headless,
  plaza h=28.0 == the live ground read) but renders small/dark at
  distance -- a lighting/LOD/culling question, not placement.
- FIELD-1 (FIX + SHIPPED 2026-10-19 late-night session fix): the
  density law was ported to the detail tier per the bisection's fix
  direction. Changes in globe_terrain_streamer.gd (both rng-for-rng
  twins edited identically -- derive \_derive_detail_sites + sync
  _spawn_detail_props, and both appliers):
  1. THE DENSITY LADDER (_DETAIL_BUDGETS): real-geometry attempt
     pools by the face CENTER's biome -- GRASSLAND 700, FOREST/TAIGA/
     JUNGLE 480, SAVANNA/STEPPE 420, SWAMP 240, ALPINE/TUNDRA/
     BADLANDS 200; NEAR faces pay full ask, MID a quarter, FAR skip
     (unchanged). Attempt pool = 2x the ask.
  2. THE LADDER GATE: the FIELD GATE lesson re-applied -- boot faces
     resolve shore/lake CENTERS while hosting the homeland's
     grassland slivers, so homeland-reach faces pay the GRASSLAND
     ask regardless of center band (a bare center-band read would
     have re-starved the boot again -- made that exact mistake and
     measured it: unchanged 1520 totals until the gate went in).
  3. THE TUFT BATCH LAW: tufts (the ~72% meadow mass) now paint as
     ONE DetailTuftBatch MultiMesh per face (one node, one draw,
     shared tuft mesh/material, no collider -- grass is ground) in
     BOTH appliers + the sync twin; the raise buys blade instances,
     NOT scene nodes. probe_prop_density counts the batch.
  4. THE BOOT GROVE PULL tightened 0.62 -> 0.88 in the detail twins
     AND the grass-field homeland law: at planet scale a face spans
     ~0.6 rad, so the 0.62 drag left a ~4-5 km residual -- measured
     DERIVE bands all-zero at <=600 m even AFTER the budget raise.
     0.88 leaves a ~70 m residual: the furniture lands in the boot
     600 m belt. Tree tier keeps its own 0.62 (dense already).
  RECEIPTS (headless, exit-0): probe_prop_density BEFORE: TOTAALS
  detail=1556, BAND <=600 m detail=0, nearest node 2,127 m. AFTER:
  TOTALS detail=3040, BAND <=600 m detail=86 (0 -> 86), <=1,200 m
  detail=88, <=2,400 m detail=199; faces 16/18 each carry ~70
  blooms + ~110 bushes + ~510 batched tufts (derive kinds
  3:515/4:71/2:114 = the v5 72/10/18 meadow roll intact) + 760-880
  grass-field blades. res\_mooncap/res\_iron\_ore/res\_moonpetal
  harvest registrations carry out unchanged through the batch
  (bushes/ore re-register; tufts stay wheel-friendly).
  PERF (bench_coldboot_wall headless): v8 BOOT_WALL_MS=86,608 /
  STREAMER_MS=83,620 / worker sum 156,412 vs BASELINE (stashed
  working tree, same host) = 90,886 / 87,989 / 171,056 -- the vite
  production prop raise is NOT the boot-wall driver (the tree/mesh
  derive lane dominates; the detail raise measures --4 s / --15 k ms
  within noise). Steady frames + tris unchanged (FACES=4, TRIS=34,816).
  LIMITATIONS + NEXT: (a) FIELD-3 now matters MORE (more props
  amplify any height-sampling mismatch) -- the numeric sit-on-ground
  pass in tests/diag_detail_kinds.gd is blocked by a world-root
  render-scale artifact (all kinds report ~19.8 km below the
  analytic surface pre/post, pre-existing kinds too) -- FIELD-3
  verification stays an ON-DEVICE visual pass; (b) MID faces (lvl 5
  boot window slots) stayed bare in the probe (face 14 EMPTY, face 6
  rocks-only) -- if the player walks past the boot belt the first
  2 km of MID land still reads sparse; watch for a follow-up budget
  for those two faces; (c) the mobile fullscreen + density retest on
  device is the acceptance verdict.
- FIELD-SESSION v9 (2026-10-19 late, follow-up to the FIELD-1 fix):
  "fill it all -- when a biome is there and a player gets to it, it
  renders" -- commit-after-receipts on main (see the commit log):
  1. THE FLOOR BAND (the MID-gap fix): the LOD ladder is binary
     (base=7 or floor=5), so the v8 bake's `drop>=2 -> return` left
     EVERY floor face (the boot window's other slots + every horizon
     interior) completely bare -- the "land past the belt is empty"
     report. Floor faces now pay 1/8 of the band ask (batch-heavy:
     the tuft mass is one MultiMesh) instead of zero; drop-1 (a live
     demote in flight) pays a quarter. All three rng-for-rng paths
     edited identically (derive / sync / appliers).
  2. THE FACE BAND ASK (the travel law): "when a biome is there and
     a player gets to it, it renders" -- the ladder now resolves the
     asks from the face's CONTAINED bands (7 pure climate reads:
     center + 3 verts + 3 edge midpoints, max ask wins), not the
     center band alone. The travel census caught the center-band
     fallacy AGAIN at planet scale: forest/swamp slivers inside
     lake-center faces derived EMPTY on the center-band read.
  3. THE DRY RANGE LAW: desert + the ALPINE/TUNDRA/BADLANDS bands
     are not stone-only any more -- ~55% of their sites grow a
     hunkered dry tuft (scale 0.4-0.9) with the band's own tint
     (DESERT hot dead straw / TUNDRA frost / BADLANDS rust / ALPINE
     summit sedge added to GRASS_TINTS); the rest keep the
     boulder-ore vein. The batch material is the MAJORITY band's
     tint (the per-field species law both appliers carry).
  4. RECEIPTS (exit-0 headless): probe_prop_density unchanged
     quality on the boot belt (<=600 m detail=75, <=1,200 m 77,
     <=2,400 m 171; TOTALS 2,828) -- the tile-raise hold. The TRAVEL
     CENSUS (tests/diag_detail_kinds.gd, per-site band buckets):
     jungle faces (id=13) now derive bush 94 + MUSHROOM 11 +
     MYCELIUM 5 -- the fungal bands produce caps + glow patches for
     GM travel; homeland grassland carries tuft 857 / flower 128 /
     bush 195. bench_coldboot_wall v9 88.2 s vs the 90.9 s
     baseline -- no regression (worker sum 161k vs 171k).
  5. FIELD-3 CLOSURE STATUS (the sit-on-ground law): the numeric
     audit now measures RADIAL OVER/UNDER THE SURFACE against
     planet_center (the world is re-rooted near the player; older
     attempts measured planet-frame lengths from the origin, which
     is why every earlier pass reported absurd ~19.8 km values for
     ALL kinds). Result: ALL 373 node props (flowers/bushes) seat
     within +/-1 m of the analytic surface -- the pos law
     (_tangent_patch_local) and the parent frame are PROVEN for
     node props. Batch-BLADE read-back is foreclosed on this
     engine build: MultiMesh.get_instance_transform returns the
     identity after the buffer is committed to the rendering
     server (fresh-before-upload reads returned varied data;
     post-upload reads return zeros -- both regimes reproduced in
     one run; the diag prints the receipt artifacts). The tuft
     instances ride the SAME rec positions the nodes carry and
     the instance basis adds only yaw/scale (no position law), so
     they inherit the proven law by construction; the on-device
     visual pass remains the batch's acceptance.
  LIMITS + NEXT: (a) the desert straws need a desert-band FACE on
     this seed to prove end-to-end -- the travel census found
     fungal + homeland bands; a GM character-scan of other seeds can
     verify the dry-straw tint renders; (b) floor-band faces whose
     sampled bands are all water stay bare (correct: no props in
     the surf); (c) the phone retest (fullscreen + fresh density +
     mushroom walk) is the visual acceptance.
- WORLD-DRESSING v10 (2026-10-19 end, the beach session):
  1. THE GLOBE SCAN (tests/diag_biome_map.gd, 6,000-sample fibonacci
     sphere): this seed's planet is 79.0% OCEAN_DEEP, 11.4% SHORE,
     3.0% LAKE, 2.0% GRASSLAND, 1.5% JUNGLE, 0.7% FOREST, 0.5%
     TUNDRA, 0.3% each ALPINE/ALPINE_MEADOW/BADLANDS, 0.2% RIVER,
     0.1% STEPPE -- and ZERO DESERT bands anywhere (the world law's
     outcome, not a dressing bug): the dry-straw law is exercised
     end-to-end by the BADLANDS bands inside the homeland faces, and
     a future seed with desert pans picks the law up for free.
     The homeland faces (16/18) carry nearly every land band = the
     planet's main landmass; faces 8/9 are the shore-heavy islands.
  2. THE BEACH LAW (new _DPROP_SHELL=7 / _DPROP_WRACK=8): the shore
     band rendered NOTHING before -- 11.4% of the globe. Shore sites
     now split ~60% shells (pale half-buried seams) / ~17% kelp
     wrack (brown squat balls) / rest bare sand. SHORE joins the
     band-ask ladder (160). BOTH rng-for-rng twins + both appliers
     carry identical laws (census receipt buckets).
  3. THE RIVER LAW: the cattail band test now takes RIVER banks.
  4. THE CATCH-ALL FIX (census-caught, fixed in-session): the derive
     chain's else-bush branch swallowed shore bare-sand sites (bush
     95 in the beach bucket) and the guard tightening then ate the
     meadow shrubs (bush 0 in the homeland bucket). Final law: the
     bush branch takes bush BANDS or the meadow's bush_kept shrubs;
     unclaimed sites append nothing (THE CLAIM LAW -- rec kind
     stays -1 and is dropped at the tail).
  5. THE DRESSING MATRIX (travel-census receipt, per-site band
     buckets -- what a GM arriving in each band SEES):
     id=2  SHORE: shell 258 + wrack 57
     id=9  GRASSLAND: tuft 857 + flower 128 + bush 195
     id=13 JUNGLE: bush 95 + mushroom 11 + mycelium 12
     plus the shipped gates: FOREST/TAIGA/JUNGLE trees (1400-2100
     ask) + bushes + fungal, SWAMP cattails + fungal, SAVANNA/STEPPE
     straw-tint tufts, TUNDRA/ALPINE/BADLANDS frost/sedge/rust brush
     + ore, RIVER cattails, SHORE shells/wrack. OCEAN/LAKE carry the
     water shell (ocean service). DESERT: zero bands on this seed.
  6. VERIFICATION (exit-0 headless): probe_prop_density boot belt
     unchanged (<=600 m detail=75, TOTALS 2,828); census buckets
     clean (no bush in the beach bucket, shrubs restored in the
     homeland bucket); determinism exit-0; lint 36/0;
     bench_coldboot_wall v10 93.4 s vs 90.9 s baseline -- within the
     host's run-to-run spread (86.6..90.9 across the v8/v9 runs;
     the added beach draws ride the same derive pool), flagged for
     the next bench run to confirm the trend.
  VISUAL LIMITS: the beach shells/wrack and the mushroom walk are
  ON-DEVICE acceptance; the drowned-island faces (8/9) dress only on
  their coast bands -- the deep-water interior correctly stays bare.
- FIELD-2 houses identical + same spots: deterministic seed = same
  village layout every session, which is BY DESIGN for quest-anchored
  structures, but the player expectation is that DECORATIVE scatter
  recombines per session. Split the scatter law: anchored slice
  (village core, dock, quest anchors) stays seed-fixed; decorative
  slice (some trees, rocks, minor scatter) gets a per-boot offset
  sourced from cosmic_entropy. Houses-in-same-spots is then CORRECT
  behavior made explainable, and the sameness complaint reduces to
  the decorative layer.
- FIELD-3 floating props + height-plane seams: scatter likely samples
  one height field while the rendered mesh derives another (async-lane
  ordering), leaving props proud of the surface; seams at patch
  borders where adjacent faces disagree at LOD edges. Probes exist:
  probe_walk_mesh_gap (skirt-gap census) + probe_prop_density --
  extend both to assert prop-ground contact within tolerance and
  zero T-junction gaps at the spawn face's boot LOD.
- FIELD-4 (reported dead): /play fullscreen button no-op on mobile
  Chromium. PlayPage silently ate the rejection, missed the webkit
  prefix, and lacked iframe allowFullScreen -- the icon also vanished
  on a second tap (optimistic state, no fullscreenchange listener).
  Fixed same day in the web layer: vendor-prefix handler, the error
  surfaced as an inline toast instead of a dead click, state sourced
  from fullscreenchange, allowFullScreen on the iframe. No game-side
  change; needs a mobile retest after deploy.

## 2026-10-14 (turn 27): THE SUBAGENT BOARD + THE WHITESPACE SWEEP COMPLETES
- THE BOARD (labs/subagent-tasks.md): the Solar Pro 4 handoff queue --
  five markdown-only tasks (NPC voice/dialogue, quest briefs, the
  Acts/Almanac chronicle, weather-event lore, landmark naming), each
  grounded in the files its facts live in, with the ground rule:
  everything produced lands in labs/, game/ is READ-ONLY context,
  no commands, no commits -- the maintainer moves the good parts
  into data files. Status column: draft/review/landed/wontfix.
- THE WHITESPACE SWEEP COMPLETES: all trailing whitespace in game
  .gd files is gone -- 534 raw lines over 199 files moved to ZERO
  (the lint's own check reports one line per file, which ate the
  list slowly; the last 11 holdouts held 249 of the lines). Trim
  mechanics: regex sub of trailing [ \t] before the newline on
  exactly the flagged lines, line count preserved (numstat shows
  insertions==deletions on every file). A first python pass used
  rstrip(' \t') on newline-terminated lines, which strips nothing
  (the \n stops the char-set) -- it was caught by the lint rerun
  showing unchanged counts, the bad state was reverted with git
  checkout -- game/, and the corrected trim rebuilt. Lesson
  recorded: verify whitespace edits with the same split/rstrip
  semantics the checker uses, and re-derive the target list from a
  FRESH lint run after every write (line numbers move).

- Verification: lint runner 36/0 x5 suites with ZERO trailing-whitespace
  WARNs remaining (raw grep count 0); every trim line-preserving;
  hud-widget test 0 FAIL, test_progress_persistence exit 0 on the
  edited UI and persistence files; globe/audio tests unchanged.

- WORLD-DRESSING v11 (2026-10-20, the SUN PANS day): the desert
  island exists, dresses, and is reachable.
  1. THE ATOLL (terrain law, face 12): a ~1 km island in the
     open ocean -- DESERT salt-pan core to ~+160 m BADLANDS
     volcanic walls, a SHORE beach ring, open ocean around.
     Hydrology basins are EXCLUDED inside the atoll cone (a
     desert holds no lakes) and the pans core carries a
     temperature-lapse exemption so the hole keeps its desert
     heat at altitude instead of re-solving steppe. The
     dedicated radial pass in tests/diag_biome_map.gd walks the
     cone bearing and receipts the gradient.
  2. THE ASK LADDER FIX (the zero-desert kill): face 12 is an
     OCEAN-center face, its band ask back-resolved to 0, and the
     homeland gate bailed BEFORE the scatter ever rolled -- so
     even with the authored neck (all four scatter twins pour
     pans-reachable faces' attempts through the atoll cone,
     slerp 0.955-0.985) the island derived ZERO detail sites.
     Fix: DESERT joins _DETAIL_BUDGETS at 200 (same tier as
     TUNDRA/BADLANDS); _face_band_ask already appends the pans
     bearing, so the bearing face now pays the atoll's ask in
     BOTH detail twins.
  3. RECEIPTS (exit-0 headless, tests/diag_detail_kinds.gd at the
     20 km boot): travel census gains DESERT id=5 (172 dry-tuft
     sites -- the pans core's straw field) and BADLANDS id=16
     (13 boulder-ore veins + 12 rust tufts -- the volcanic rim);
     the ladder entry also unlocked the world's other dry
     pockets (id=15 bush/tuft). Boot faces unchanged-health
     (16: tuft 515/flower 71/bush 114; 18: 342/57/81), FIELD-3
     numbers identical to v10 (the audit's instance-transform
     false-frames stand foreclosed; live batch anchors stay
     seat-level: wp0 radial 0.52 m).
  4. THE ZONE + GATEWAY PAIR (authored, no code): data/zones/
     zone_sun_pans.tres (DESERT climate zone, the "far country")
     + data/gateways/waypoint_sun_pans.tres (WAYPOINT pin,
     starter_plains -> sun_pans, two-way, amber glow). World
     Service's authored-gateway seam registers both verbatim;
     dev_temp/probes/pans_pair_probe.gd receipts it: GATEWAY to
     _zone=zone_sun_pans type=1, ZONE name="The Sun Pans",
     PAIR-OK.
  LIMITS + NEXT: (a) the pans gateway has no model_path (the
     generic waypoint art renders) -- a monolith/obelisk piece is
     the art follow-up; (b) the ferry route list still reads the
     harbor pins -- adding the pans bearing to the ferry loop is
     the travel follow-up if walk-up teleport proves too sterile;
     (c) the on-device walk (sail bearing NE off the homeland,
     land on the beach, read the straw field against the rust
     rim) is the visual acceptance.
- WORLD-DRESSING v11b (2026-10-20 continuation, the pans wiring):
  1. THE LIVE-STREAM RECEIPT (dev_temp/probes/pans_render_probe.gd,
     exit-0): the missing middle is proven -- the engine ACTUALLY
     loads face 12 when a player sails to the bearing. The probe
     holds the streamer aim at the pans bearing, drains the derive
     worker WITH the aim held, and prints: face12 loaded=true lvl=7
     (base=7), holder={"Bush": 2, "Ore": 13, "DetailTuftBatch": 185},
     derive_kinds={3: 185, 2: 2, 0: 13}. The probe fought two
     probe-side reefs first (a lone update() call loses the
     want-set to the globe's own per-frame update, after which
     _apply_derived_props' streamed-out-mid-derive drop eats the
     content -- REAL player sails are immune because the player's
     own process holds the aim both halves of the frame); the
     streamer's promotion + apply laws are proven against the
     on-device behavior.
  2. THE FERRY (the travel follow-up, closed): data/vehicles/
     veh_pans_ferry.tres -- the Pans Runner, lateen-rigged, harbor
     pier <-> the pans waypoint pin, two cast-offs a day (first
     7.5, crossing honest water time 3.0 h). The schedule primitive
     resolves it in-port with zero code (ferry_service reads
     data/vehicles scans); pans_pair_probe receipts route_status
     dep.hour=7.5 day_offset=0 status=in_port.
  3. GATES: naming lint 25/0 (the two new .tres carry), runner
     36/0. Pushed as terrain v11b.
  LIMITS + NEXT: (a) the ferry model still needs a vessel mesh
     (route + schedule are live; the deck rides the planned S14.6
     ride-motion); (b) the harbor pier's E-interact board should now
     show the Pans Runner on its timetable (SkyAlmanacUI's sailing
     page reads the same closed form) -- a UI receipt is open;
     (c) the on-device acceptance stands: sail NE off the homeland,
     land on the beach, read the straw field against the rust rim.
- WORLD-DRESSING v11c (2026-10-20, the pans art trio): the three
  named follow-ups land together.
  1. THE VESSEL MESH (entities/ferry_vessel.gd): the Pans Runner is
     a node in the world now -- lateen hull, deck, hold tent, spar +
     canvas, Concord stern lantern (emissive), built in the
     engine-ban box dialect. The ride law (place(t)) walks the
     pier<->pans great-circle lane; at sea the hull floats ON the
     sea line (walk_surface_h returns the SEABED at ocean dirs, so
     the sea level clamps it back up); the berthed end rides the
     pier deck face. The globe wires a 1 s tick that reads
     FerrySchedule.crossing_in_progress and drives t -- in port the
     boat berths at the pier's water face, at sea it visibly rides
     the lane (the deck motion law stays virtual, S14.6).
  2. THE MONOLITH (entities/pans_monolith.gd): the pans waypoint's
     own art -- sunbaked obelisk (pale sandstone, scorched banding,
     bronze capstone) + guidestone cairns + the mooring flank (two
     posts standing where the Runner ties off). Placement rides
     sun_pans_dir on the same authored-install frame the capitol
     carries, one collider belt.
  3. THE SAILING PAGE (ui/components/sky_almanac_ui.gd): the page
     rendered ferries[0] only -- with the Pans Runner in the scan
     the chart showed one vessel of two. Now EVERY scheduled ferry
     gets its own block (name/route, crossing minutes, next
     cast-off); the tide-table-blank law stays.
  RECEIPTS (exit-0 headless, dev_temp/probes/pans_builds_probe.gd,
  booting the 20 km planet): monolith on the pans bearing
  (angle 0.0000 rad), runner berthed at the pier end (angle 0.0000,
  h 30.2, pier-ward), sailing rows carry BOTH vessels
  (haven=true pans=true, 13 rows). The old document W11b live-
  stream receipt re-held after the art lands (face12 loaded=true,
  holder Bush 2 / Ore 13 / DetailTuftBatch 185). Gate lints:
  naming 25/0, runner 36/0. ERROR-ATTRIBUTION LESSON: the 6
  SCRIPT ERRORs per headless boot (Nonexistent function '' in base
  Vector3/RefCounted streamer, get_ticks_msec on null) reproduce
  on PRE-EDIT main (stash test) -- deferred worker noise the
  headless dummy renderer already ships; not this round's.  LIMITS + NEXT: (a) the pier berth collision needs an on-device
     pass (the berthed hull's keel may clip the pier head boards --
     berth lift is a constant, tune visually); (b) the arrival end
     (pans moor) never shows the boat -- the in-port law pier-berths
     unconditionally; alternating berths needs the ride ledger
     (S14.6); (c) the on-device acceptance stands (v11b c).
- WORLD-DRESSING v11d (2026-10-20, the gaps round): the dock-via-pin
  callers law (the audit SWEEP's catch).
  1. THE GAP: player_controller._open_nearby_ship_dock pinned the
     dock panel through _dock_vehicle_for_pin -- FIRST vehicle whose
     route names the pin. The capitol pier fronts TWO lines now
     (Haven Ferry + Pans Runner), so the E-interact walk-up always
     docked the Haven Ferry: the Pans Runner's pier end was
     UNSCHEDULED and UNBOARDABLE from the walk-up, even with its
     schedule live on the almanac page.
  2. THE FIX (no pin-to-boat table): FerryDockUI gains
     pin_gateway_id -- the dock resolves its callers from the
     VEHICLES' own route data (FerryService truth), picks the
     explicit vehicle_id first (back-compat), then the pin's caller
     cycle. A shared harbor pin grows the "Also calling: <line> --
     switch" button; every press re-reads that line's OWN schedule,
     wake ledger and boarding window. Explicitly-set vehicle_id
     docks (the moor-side barque law) keep pinning verbatim.
  3. RECEIPTS (exit-0 headless, pans_builds_probe extended, the
     20 km boot): dock first caller=Haven Ferry (8 cast-offs),
     one cycle press -> second caller=Pans Runner (2 cast-offs);
     the trio receipts re-held (monolith 0.0000 rad, runner berthed
     pier-ward, sailing rows BOTH vessels). Gate lints: naming
     25/0, runner 36/0. The pre-existing PlayerManager/GameLog
     check-only blind spot again tripped on player_controller --
     stash-tested pre-existing (the real boot compiles it; the
     extended probe IS that boot).
  LIMITS + NEXT (the next round's board): (a) the berth-clip visual
     tune stands (v11c a); (b) alternating berths (the pans-side
     moor showing the boat) wants the S14.6 ride ledger; (c) the
     npc_entity dock door (the ferrymaster offering) still opens
     with NO pin -- it inherits the first-caller default, which is
     correct for the harbor NPC but gets the pin law for free the
     day its world anchor carries one.
- WORLD-DRESSING v12 (2026-10-20, the berth round): the two boarded
  vessel follow-ups land as one law + one tune.
  1. THE BERTH-CLIP TUNE (entities/ferry_vessel.gd): the numeric
     model said the spawned-old 1.7 berth lift left the keel (origin
     - 0.55) 2.5 cm over the pier-head deck top (walk + 1.125 = head
     origin 0.85 + plate 0.15 + half-plate 0.125) -- a guaranteed
     clip under any walk-law wave. PIER_BERTH_LIFT is now 2.0; the
     receipt asserts >= 0.2 m air: measured 0.32 m.
  2. THE BERTH ALTERNATION (core/frame/srv/ferry_schedule.gd gets
     vessel_t, the ONE-law home): a closed-form lane-t for any
     instant -- cast-offs alternate direction (even k sails
     pier->pans, odd k pans->pier), mid-crossing the boat rides the
     crossing clock mirrored, and IN PORT she WAITS at the next
     cast-off's ORIGIN: the boarding end always has the boat when
     its cast-off nears, the pans moor visibly holds her between
     sailings, and she never teleport-returns unseen. The globe's
     1 s tick now calls vessel_t directly (the v11b/v11c hand-rolled
     in-port branch is gone). S14.6's deck-ride law reads the same
     t whenever it lands.
  3. THE PAN MOOR (the far end's berth): the lift law grew its
     t >= 0.98 band (PAN_MOOR_LIFT 0.9 -- beached lightly at the
     moor flank's bank line), so the arrived boat reads as a tied
     off runner, not a mid-lane floater frozen at 0.95.
  4. RECEIPTS (exit-0 headless, pans_builds_probe extended, the
     20 km boot): keel clearance 0.32 m; berth timeline at
     synthetic Concord days: pre=0.00 mid1=0.50 moor=1.00 mid2
     =0.50 dawn=0.00 (the overnight boundary exercises the d-1
     index branch); the trio + dock-caller receipts re-held
     (monolith 0.0000 rad, runner pier-ward, both vessels on the
     chart and on the pier's caller cycle). Schedule contract:
     tests/probe_ferry.gd exit-0 (35 checks) -- the additive
     vessel_t broke none. Gate lints 25/0 + 36/0.
  LIMITS + NEXT: (a) the ferrymaster NPC dock door stands pinless
  (v11d c) until its offering carries a world anchor; (b) the
  deck-RIDE (standing on the moving hull) is exactly S14.6 -- the
  actor law gives the t, the walk surface does not move; (c) the
  on-device acceptance stands (board at dawn, watch the crossing,
  and catch her on the pans moor by midmorning).
- WORLD-DRESSING v13 (2026-10-20, the FIELD-2 split): nature's
  decorative slice recombines with the session; the anchored slice
  never moves.
  1. THE REPORT (FIELD-2, 2026-10-19): the seed makes houses AND
     scatter identical every session -- correct for quest-anchored
     structures (same spots BY DESIGN), not for decoration; the
     board named the split: anchored slice seed-fixed, decorative
     slice recombining.
  2. THE SPLIT LAW (globe_terrain_streamer.gd): a SESSION SALT (the
     Concord boot day) rides ONLY the decorative chains -- the tree
     canopies (both rng-for-rng twins: the sync reads the member,
     the worker law reads the BOUND salt the kick carries) and the
     grass fields (single path, one salt site). The DETAIL chain is
     deliberately salt-immune: every kind of it is harvest-backed
     (ore veins, mooncaps, the anchor stencil kinds) and the
     harvest respawn ledger would drift if its sites recombined.
     The rock chains stay seed-fixed too: boulders carry the
     climb/walk law, and the grand vista is a COUNTRY, not a
     stage-set. Two boots on one day agree position-for-position
     (determinism inside a session); a new day re-mixes the
     canopy (recombination between sessions).
  3. RECEIPTS (exit-0 headless, dev_temp/probes/field2_salt_probe
     .gd, the 20 km boot): trees saltA vs saltB derive DIFFERENT
     canopies (recombine claim), same-salt derive REPEATS bit-for
     -bit (in-session determinism), detail chain stable=700 sites
     under cross-salt derivation (the anchor law), live boot salt
     = the actual Concord day (20746) -- the boot arms. pans
     trio + dock-caller receipts re-held on the same salt build;
     gate lints 25/0 + 36/0.
  4. THE NEW PROBE LAW: dev_temp/probes/field2_salt_probe.gd is the
     standing receipt for the split -- any future chain that wants
     the salt answers it: decorative chains differ across salts,
     anchor chains do not.
  LIMITS + NEXT: (a) the tree/rock synthesis count ladders are
  salt-INDEPENDENT (counts from band + face seed) so the band map
  census law stands across sessions (the positions re-mix, the
  density does not); (b) decorative salt at DAY granularity is the
  plan's own granularity -- a second salt knob (per-boot) would
  violate the in-session probe/replay law, a per-hour one would
  remix mid-session; (c) S14.6 and the ferrymaster pin still
  stand from v12.
- WORLD-DRESSING v14 (2026-10-20, the wildflower session): the
  meadow gets its FIELDS, not sprinkles.
  1. THE GAP: the v5 bloom law gave grassland a flat 10% bloom
     sprinkle -- every meadow read the same thin scattering, no
     patch ever read as a field.
  2. THE WILDFLOWER DRIFT (terrain_gen.gd, pure): two value-noise
     octaves on the site direction at a ~50 m patch scale
     (FLDRIFT_SALT, no rng draw -- the twin draw counts stay),
     sharpened so only strong cells form drifts. The bloom gate is
     0.10 + 0.40 x drift -- a strong cell carries up to ~50% of its
     sites in bloom, open meadow keeps the sprinkle. THE DRIFT
     SPECIES law: the palette rides the drift band (one kind per
     patch, a rare intruder from the SAME single randi() draw), so
     each field reads as one wildflower kind handing off to the
     next. THE BLOOM NODE CAP (150/face, both twins) is the perf
     law: the raise is paid by the ceiling, the budget never
     explodes. Grassland only -- every other band is bit-identical
     (the travel census proves it).
  3. RECEIPTS (exit-0 headless): the drift field sweeps 0.000-1.000
     with a 33% strong-cell share over the sampled tangent grid
     (a real patch field, not a blanket, not a flat field) --
     probes/wildflower_drift_probe.gd; species mapping stable;
     face 16 blooms at the node ceiling: 150 flowers vs the old 71
     (face 18: 57 -> 150); travel census homeland grassland = 300
     blooms / 981 sites with every other band unchanged; FIELD-3
     coherently redistributed (float 515 -> 416 with the tuft
     batch down 515 -> 416; the audit checks 1180 unchanged). The
     GrassField shift 760 -> 840 is the v13 DAY SALT (v11 receipts
     predate it; stable within the day). Gate lints 25/0 + 36/0.
  LIMITS + NEXT: (a) the drift is seed-pure (landscape shape, not a
     session slice) -- the flowers ride the salt-immune detail
     chain by the harvest-ledger law (v13 host law; a pure-paint
     batch ride is the perf follow-up if the node cap chokes an
     on-device pass); (b) SAVANNA/TAIGA stay on the sprinkle law
     (grassland-only drift; extending is a one-gate edit + census
     run when a player reports a meadow that wants them); (c) the
     on-device acceptance stands: walk the homeland at bloom time
     and read the patch-to-patch species handoff.
  4. THE v14 RE-VERIFICATION (2026-10-23, second pass, same receipts):
     wildflower_drift_probe exit-0 (DRIFT-OK: field 0.000-1.000,
     147/441 strong cells = 33%, species stable=2, face16 live
     flowers 150 vs the v5 71); diag_detail_kinds census exit-0
     (band 9 grassland = 300 flower / 662 tuft / 218 bush, EVERY
     other band zero flower -- the spread is grassland-only by
     census, not by gate alone; face16/18 both at the 150 cap,
     FIELD-3 folds intact). Lint suite 36/0 exit 0. Editor wart
     fixed in the streamer: two comment lines carried glued dead
     text (a doubled meadow_roll tail) -- comment-only, the real
     statements were intact; probe + lints re-run after. KNOWN
     BENIGN: the drift probe's own log shows 2-3 SCRIPT ERRORs at
     teardown (globe_terrain_streamer.gd:588/595/3303, empty-callable
     / Time-singleton races while the mesh worker thread is still
     running at exit); probe_globe_world runs the same HEAD code
     with zero SCRIPT ERRORs and the drift probe exits 0 with
     correct counts, so this is teardown noise in that probe's
     longer streaming session, not a wildflower regression.



- WORLD-DRESSING v15 (2026-10-26, the DECK RIDE: the standing limits
  from v12/v14 all named it -- the actor law gives the t, the walk
  surface does not move; now the deck rides).
  1. THE GAP: the v11-v14 boat was visible but UNTOUCHABLE -- the
     one-belt PropCollider attach boxed the WHOLE hull (mast + rig
     included), so its body's top face rode ~7 m up and the deck
     under it was unreachable; nobody could stand a ride.
  2. THE PIECE-COLLIDER LAW (ferry_vessel.build): the hull collides
     in PIECES the way the pier plates do -- a walkable DeckPanel
     (top = the deck surface, local y ~0.94), a solid Hull belly +
     Hold tent, a thin MastBlock in the mast line; the hanging rig
     stays decorative (no collider). Each piece joins the climbable
     group (the deck is climbable out of the water) and feeds the
     "colliders" meta the ride query excludes.
  3. THE RIDE LAW (ferry_vessel.place, ONE law any caller): riders
     are found ON the deck BEFORE the hull moves (vessel-local box
     DECK_RIDE_SYM/HALF; two legs -- players as real physics bodies
     via the space shape-query, code-moved Entity bodies off
     EntityService when live), then each is re-woven through the
     old->new transform -- deck-local geometry is PRESERVED (the
     rider keeps her exact deck spot while the hull runs the lane).
     Carried bodies carry the "deck_rides" anchor meta; the ride
     roster clears it the tick after a step-off (only THIS vessel's
     anchor clears).
  4. THE SNAP LAW (globe_player): while the anchor holds, the
     terrain radial home owns NOTHING -- the snap would re-home a
     deck rider to the SEABED law mid-sea (which is what made
     standing on a moving hull impossible); the physics' own floor
     contact on the deck panel is the ground. Anticheat reads
     velocity, not positions: a carried standing rider is passive
     displacement (the current-drift precedent), no report path.
  5. RECEIPTS (exit-0 headless, the 20 km boot): NEW
     dev_temp/probes/deck_ride_probe.gd -- 4 piece colliders under
     the runner; park 0.10 -> place 0.13 runs the hull 1309.7 m
     while the deck-rider keeps 0.0005 m of deck-local drift (the
     rigid carry); the anchor lives while standing and CLEARS on
     the step-off (RIDE-OK). Gate: probe_ferry PASS, the
     frame/srv/test_ferry_schedule contract PASS (the additive
     place() broke none), lint suite 36/0, naming lint PASS;
     pans_builds_probe re-held on the same build (monolith 0.0000
     rad, runner berthed pier-ward 0.0000 h 30.5, sailing rows both
     vessels, dock caller cycle both lines, keel 0.32 m, the berth
     alternation timeline pre=0.00 mid1/mid2=0.50 moor=1.00
     dawn=0.00).
  6. LESSONS: (a) the parse-time preload poison bit the probe
     script FIRST -- ferry_vessel preloads terrain_gen, whose
     script-mode reload fails; the probe load()-s the vessel law
     AFTER boot (the test_load lesson, again); (b) a fresh
     sandbox's .godot cache lacks the global script-class cache --
     every class_name resolves as "not declared" until one headless
     --import pass builds it (the 150 parse errors were one root
     cause); (c) receipts that compare GLOBAL deltas drift with the
     floating origin's reroot between reads -- deck-local
     invariance is what riding means, assert THAT.
  LIMITS + NEXT: (a) the board is a hop/climb (the deck top sits
     ~1.8 m over the pier head at the v12 berth tune); a plank or a
     dock-side step is the visual follow-up if a player balks;
     (b) the session dock (FerryDockUI board path) still teleports
     at the ports (the v0 contract stands) and the wake ledger does
     not yet credit a DECK ride -- the ride-ledger credit is the
     next round; (c) the on-device acceptance stands: dock at dawn,
     hop aboard, and stand the crossing.
- WORLD-DRESSING v16 (2026-10-26, the WAKE-LEDGER CREDIT: the deck
  ride pays like the dock path).
  1. THE GAP (v15's named next): a player who STOOD a crossing on
     the deck earned no wake -- the ledger only counted the session
     dock's arrival; the skiff's first-crossing gate read her as a
     first-time sailor still.
  2. THE SEAM (FerryService.record_deck_wake): one call, ONE ride:
     the ledger credits (the same _record_wake, persisted), a
     legend refused if the manifest already owns the rider (the
     dock path keeps its priority), and a ZONE_CHANGED landfall
     toast ("the wake remembers a sailor") named from _port truth.
  3. THE TICK GLUE (globe_world._wake_credit_deck_riders): riders
     standing on the deck are marked every SEA tick (the carry
     law's ride roster; players only -- physics bodies with an
     entity_id, code-moved NPC rosters never carry a purse); the
     next tick that lands on a BERTH credits every marked player
     ONCE and clears the marks. A pier-standing idle never earns
     (no sea tick preceded); a step-off before the berth never
     earns. Port-side identity is stamped AT THE BOOT READ from
     the vehicle's own route_gateways (no magic strings).
  4. RECEIPTS: deck_ride_probe extended -- wake seam ok=true
     rides=1 under the existing RIDE-OK (4 piece colliders, rigid
     carry 0.0005 m deck-local drift, anchor clear on step-off);
     probe_ferry + frame/srv/test_ferry_schedule + naming lint
     PASS; lint suite 36/0.
  LIMITS + NEXT: (a) the glue marks per-TICK, the tick is 1 s --
     a body who boards and steps off within one sea tick earns
     nothing (the honest side of the tradeoff); (b) the skiff /
     dock-warp tiers now see deck-wake credit for FREE (the wake
     IS the gate) -- a wake-farm via repeated deck standing is
     bounded by the schedule itself (2 crossings a day, honest
     water time); (c) the on-device acceptance stands: stand a
     full crossing, watch the landfall toast, fish the skiff
     chit out of the vendor after 3 wakes.
- WORLD-DRESSING v17 (2026-10-26, the DOCK-WARP TIER: the wake's
  return -- tier 3 lands).
  1. THE GAP: the wake was a number. Three rides never bought
     anything: no UI, no travel, no tier.
  2. THE SEAM (FerryService.warp_wake + wake_warped signal): the
     service VALIDATES ONLY -- vessel exists, the gateway is one of
     the route's OWN ports (off-route refuses), the wake is known
     (WAKE_KNOWN_RIDES rounds the gate). The world owns the
     physical placement (the signal is the seam -- no node work in
     the service).
  3. THE DOCK ROW (FerryDockUI): the warp row reads the SAME
     ledger -- a known sailor sees "Wake Warp to <far port>" and
     the press travels through the service gate (the answer is
     spoken ok/refused, never swallowed); a stranger sees the
     count ("0/3 crossings -- not yet") disabled. The destination
     is the route's other end relative to the dock's own pin (the
     vehicle's data, never a pin table); a pinless dock renders no
     warp row (it cannot state a departure). THE OPEN REFRESH:
     _on_open() now re-reads the rows -- rows built at _ready
     predate the caller's pin/vehicle assignment (probe-caught
     stale row on the fresh-open path).
  4. THE GLOBE PLACEMENT (globe_world._execute_wake_warp +
     _wake_landing): only the LOCAL body moves (a foreign player
     id is a warning, never a yank); the landing is the
     destination pin's own spot -- the pier head deck top
     (walk + 1.125 + body center) at the pier gateway, the moor
     bank at the pans gateway -- lane dirs from the vessel law's
     ONE derivation, walk height from the streamer's single
     ground law; world-root-local coords converted through the
     root's global transform (the floating origin handled once).
  5. RECEIPTS (exit-0 headless, the 20 km boot):
     deck_ride_probe now holds the full chain in ONE run -- piece
     colliders 4, rigid carry 0.0005 m deck-local drift over the
     1309.7 m park step, anchor clear on step-off, wake seam
     rides=1, the warp gate (refused early, refused off-route,
     fired at three wakes), and the dock row (a stranger reads
     0/3 disabled; the sailor's press fires travel #2). Gate:
     probe_ferry + frame/srv/test_ferry_schedule + naming lint
     PASS; lint suite 36/0; pans trio re-held (monolith/runner/
     sailing/dock-caller/keel/berths all unchanged).
  LIMITS + NEXT: (a) the warp is free today -- the wake IS the
     ticket by law (the schedule already priced the discipline:
     three honest crossings first); a gold stamp on top is a
     one-line change if the owner wants a second gate; (b) zone
     routing at the landing rides the walk's own zone-entry
     detection (no explicit zone teleport -- the globe's zone
     procs are position-driven); (c) on-device acceptance: stand
     at the pier dock, press Wake Warp at 3 wakes, land on the
     pier head (or the pans moor) standing.
- WORLD-DRESSING v18 (2026-10-26, the HARBOR LIGHTS + the fleet
  packs.
  1. THE HARBOR LIGHTS (entities/harbor_lights.gd, the two-end
     light law S14.8): the v11 stern lantern settled the BOAT's
     light; the beach never answered. Now BOTH landings carry one:
     the PierBeacon -- a stone column + caged amber lamp one flank
     step off the vessel law's pier dir (the same 0.004 beat the
     moor uses) -- and the MoorGuide -- a flat guide stone at the
     pans bank with the warm ember panel carved on the seaward
     face. THE NIGHT LAW: place_night(node, epoch) flips the lamp
     truth off the CONCORD SKY CLOCK (the same epoch the berth
     clock holds) -- lit from DUSK_H (18.0) through DAWN_H (6.0),
     dark to the sun, edges honest (dusk itself wakes, dawn itself
     sleeps). THE SEA CLAMP rides the vessel law (a light stands
     in the shallows, never under them: base = max(walk, sea)).
     The globe's ferry tick calls place_night for both lights
     every second with the epoch it already holds (1 s cadence,
     no new timer). One tangent frame serves both lands (up =
     radial, forward = the spawn projection -- the vessel law's
     Basis(side, up, forward) shape). PropColliders attached (both
     prop-solid, climbable).
  2. RECEIPTS (exit-0 headless, the 20 km boot): NEW
     dev_temp/probes/harbor_lights_probe.gd -- LIGHT-OK: beacon on
     the pier flank (0.0040 rad, h 28.5), guide on the moor flank
     (0.0040 rad, h 122.8), the night law's band edges measured
     on synthetic epochs (noon dark / dusk lit / midnight lit /
     dawn dark), and the boat's berth DISPLACED NOT ONE STEP
     (runner 0.0000 rad). Gate: probe_ferry + ferry schedule
     contract + naming lint PASS; lint suite 36/0; pans trio
     re-held; deck-ride chain RIDE-OK on the same build (the
     lights build alongside without disturbing the law).
  3. THE FLEET PACKS (packs/public/, the packstruct@1 spec): the
     runner drift class hit US in the deck round (a DEFAULT_SET
     name with no test file); dhaupin/packstruct formalizes the
     author-time refusal. NEW scripts/gen_fleet_packs.mjs -- the
     packs are GENERATED from the runner's own DEFAULT_SET
     (bucketing rules are first-match, a renamed bucket prunes its
     own stale dir, non-generated dirs never touched): 8 family
     packs (fleet-frame 16, terrain-globe 28, concord-services 17,
     arena-bouts 13, combat-movement 10, social-instances 9,
     world-ticks 3, ocean-ferry 5) = 101 tests carried, ZERO
     unfiled. Each pack: pack.json (schemaVersion 1, kebab name ==
     dir, dotted version, entry) + main.mjs (default export: the
     family line + the exact runner command). `npx packstruct
     lint packs/ --deep` exit 0 (8 probed, 8 ids censused). LESSON:
     the generator reads the DEFAULT_SET ITSELF, so the pack index
     cannot claim a test the runner does not carry -- the missing-
     entry class dies at generation, not at CI.
  LIMITS + NEXT: (a) the beacon's lamp is a Material flip, not a
     real light node (no light pass for the headless renderer; an
     OmniLight3D on-device glow is a one-line add if the owner
     wants bloom); (b) the packstruct lens stays OFF CI for now --
     wiring `npx packstruct lint packs/` into web-ci.yml is the
     owner's call; (c) on-device acceptance: stand the pier at
     dusk and watch the caged lamp wake; sail the crossing; land
     on the moor into the ember's reach.
- WORLD-DRESSING v19: THE GLOW CISTERN S15.5 SHIPPED -- the Deep Root's catch-dish at the camp shelf ("the pool gets the glow"): water is DATA (data/oceans/ocean_deep_root_pool.tres: LOCAL pool declaration, floor on the walk line 2000.0, surface 2002.4, reach 3.4 m, gentle pressure 0.0); the stone is built by globe_underworld._build_cistern (basin slab at the walk line, 7 tall rim arcs topping 3.2 m no-fence-hop, ONE sheave bench on the ring's low side topping 0.3 m over the water = the one honest exit, hop-from-water law; piece seats planet-relative X/Z with ABSOLUTE local Y -- the first cut double-added CAMP_HEAD_POS.y and mis-sized the wall band, fixed); PropCollider piece-collider law on every stone, NO collider on the water disc (the swim law reads the OceanVolume, the disc is only paint). The glow law rides the SAME concord tide: static cistern_glow(phase) (0.45-1.0 cos band, high at surface dawn) fed to the water's emission in _process next to the strata light -- pure function, no drift. Receipts: dev_temp/probes/cistern_probe.gd CISTERN-OK (data: LOCAL floor/gentle; claims: standing ON the dish reads 1.40 m swim depth > WADING_DEPTH_M 1.2, shelf-out DRY unclaimed, mid-air negative, in-stone -1 sentinel; stone: 1+7+1 named pieces, bench 2002.7 < wall 2003.4, exit step 0.30 over the water; glow: g(0)=1.0 > g(0.5)=0.45 and the runtime material rider matched the formula AT the live phase 0.618). Re-holds: probe_underworld 42 PASS (the camp/gates/sky/quest loop untouched), probe_ocean 44 PASS (the LOCAL claim law reads the new pool cleanly beside the moon crater pool), naming lint PASS, lint suite 36/0, packstruct --deep 8 packs green (dev_temp probes stay ad hoc like pans/harbor precedent -- no DEFAULT_SET drift). Headless gate-law note: script-mode preloads of game scripts fail compile if they name autoloads (GameLog/InventoryService register after parse) -- runtime load() only, the probe_underworld pattern; also lint's /tmp Godot binary dies on restore, GODOT=$(command -v godot) bash tests/lint/run_all.sh.
- WORLD-DRESSING v20: THE WARDEN OWES THE CISTERN (S15.6, the story
     beat + the dusk-read + the first wilds) SHIPPED in three cuts.
  1. THE SWIM BEAT: OceanService gains the swim credit signal
     (`water_entered(body_id, volume_id)`, emitted ONCE per dry -> wet
     entry; the `_wet_by` book holds the credited volume so per-frame
     ticks never double-credit, cross-volume moves emit fresh,
     forget_swimmer clears) + QuestData.ObjectiveType.SWIM. The
     underworld is the LIVE DELIVERY: `_visitors[pid]` now holds the
     body node and globe_underworld._process ticks every visitor
     through OceanService in world_root-local coords (the globe owns
     its water the same way it owns its zone credit -- no
     globe_player physics surgery). QuestService bridges it deferred
     (OceanService is a later autoload; the insight-bridge pattern)
     into the new SWIM objective, credited by volume id verbatim.
     DATA: quest_cross_the_cistern.tres (SWIM ocean_deep_root_pool +
     TALK turn-in to the Warden; previous_quest_id chain from
     quest_listen_to_the_deep via next_quest_id, npc includes carry
     it), deep_warden_greeting.tres gains the cistern branch (nodes
     5-6: the dish lore + the honest-crossing rules, hearthstone-warm
     water, the bench way out), npc_deep_warden includes lists it.
     Receipts: tests/test_quest_swim_bridge.gd 10/0 (bridge connect
     after deferred flush, .tres shape verbatim targets, accept ->
     one tick credits 1/1, 10 more frames do not over-tick, a
     different volume (Haven Shelf) stays dry of the count, TALK
     closes the quest COMPLETE) + probe_underworld gains G2: the
     LIVING globe (the walker teleported into the dish + ONE
     underworld _process frame = the SWIM objective completes
     through the real autoload bridge). underworld probe now 44 PASS.
  2. THE DUSK-READ PASS (the two new stones read at their dark
     hour): cistern stone law -- one SHARED vein-lit wall material
     (STONE_WALL_ALBEDO 0.17/0.15/0.19 + STONE_WALL_VEINS emission
     0.35/0.8/0.55 whose energy rides the tide per frame, 0.18x), a
     darker basin slab (wilder whisper 0.05), and the BENCH as the
     one brightest stone with a static warm ember (0.25 -- the exit
     reads as an exit, a place not a clock); harbor lights -- the
     lamp material pops at LAMP_ENERGY_LIT 1.8 AND carries a small
     warm halo OmniLight3D (HALO_RANGE 9 m, floor'd visible=false at
     build) toggled by the SAME set_lit flip (two halos total; the
     probe's NIGHT LAW asserts stay green).
  3. THE DEEP WILDS (S15.6, the underworld's first biome law):
     globe_underworld._build_wilds scatters FIVE bands off the camp
     shelf, every seat a pure function of its index
     (_wilds_drift golden-spindle; no seed, no RNG -- re-derived
     byte-identical): crag ring (12 leaning prisms, vein-lit every
     third, crag 24-34 m, apron keeps 6 m gate clears + 8 m dish
     clear), dead grove (7 charcoal trunks 34-48 m + bare forks),
     mycelium field (9 clumps x 3 glow caps, no collider), stalagmite
     runs (14 pale spikes 0.9-3.1 m, pi-flip growth), odd grasses (36
     tufts x 3 luminous blades, no collider). Collider law: stones
     stand (PropCollider), paint walks over. Receipts:
     dev_temp/probes/wilds_probe.gd WILDS-OK (family counts 12/7/9/
     14/36, stones collidered paint bare, aprons clear, second
     conjured globe byte-identical).
  GATES: ocean probe 44 PASS, underworld 44 PASS (incl. live swim
     bridge), cistern CISTERN-OK, harbor LIGHT-OK, naming lint 25/0,
     lint suite 36/0 (GODOT override), packstruct --deep 8 packs
     green. NEXT: lava rivers (the "maybe?" stays open -- parked as
     the underworld's own water frame, data first), underworld biomes
     as DATA bands (zone-style declarations), the Artifact Gate piece.
- WORLD-DRESSING v21: THE UNDERWORLD'S WORLD-COMMONS (S15.7, lava +
     biomes + the commons other worlds have) SHIPPED in one wave.
  1. LAVA AS WATER-FRAME: OceanVolume gains
     Liquid.WATER/LAVA + burn_dps (the same sampler, the same bands,
     only the lake bites; tick_swimmer's return now carries liquid +
     burn_dps + current under one shape). DATA: data/oceans/
     lava_underglow_lake.tres (LOCAL pool at the camp's south-east
     keep: surface 1999.6, floor 1997.8, reach 9 m, current drift
     0.35 m/s toward the east, LAVA 8 dps). globe_underworld
     _build_lava_lake: 8-arc curb ring (0.55 m step-over curb, honest
     choice-shaped exit) + one self-lit molten disc whose emission
     pulses 1.1-1.5 with the SAME tide (the _process lava rider). THE
     BURN LAW (live): the underworld's visitor tick accrues burn in
     whole digits through a _burn_pool debt book (the first cut lost
     the fractional debt each frame -- the probe caught it; the debt
     books every frame now), and leaving the lake is free.
  2. FORMAL BIOME-BAND DATA: new schema core/schemas/biome_band.gd
     (world_id / family CRAG|DEAD_TREE|MYCELIUM|STALAGMITE|GRASS /
     radius span / angular_offset / count / sub_count / collider_mode
     stone|paint / palette trio / emission_energy / clearance) +
     data/biomes/biome_underworld_*.tres x5 (crag ring 12, dead grove
     7x2 forks, mycelium 9x3 caps, stalagmites 14, dark meadow 36x3
     blades). The wilds builders now READ the declarations (count/
     radii/palette/keeps-clear) and fall back to literals only when a
     declaration is missing -- wilds changes are data edits from
     here. WILDS-OK re-held byte-identical on the data-driven path.
  3. THE COMMONS (roads/trails, currents, weather, gliding, airflow,
     the Ascent's thrower): _build_trail lays 32 walk-over plates in
     two legs (camp -> cistern -> the lake overlook which stops 4 m
     short of the melt); the lava lake declares a real current the
     visitor tick pushes bodies by (half-strength drift while wet);
     ThermalUpdraft gains world_id (ownership explicit: an underworld
     column and a planar sampler share one book), data/thermals/
     underworld_vent_east + vent_flow (always-on standing columns)
     and thermal_ascent_thrower (Kind.thermal LAUNCHER, activation
     RITUAL, feeds the East Stack -- the Ascent-door artifact beat:
     asleep until the shard's ritual wakes it, then it HURLS with a
     real anticheat launch ticket through the ONE ThermalService
     sample path); the underworld _process now carries visitors
     through ThermalService.sample (lift into velocity.y, glide-tick
     feed) -- the underworld's airflow is real. THE WEATHER LAW:
     weather_mist(phase) static closed form (0.055 thick at the low
     tide, 0.02 whisper at the crest) fed to the WorldEnvironment fog
     per frame -- strata mist as the underworld's weather, one clock.
  Receipts: dev_temp/probes/deep_commons_probe.gd COMMONS-OK (18:
     lava data + claim + wading + liquid/burn per tick, live burn ~8
     dps dry-is-free, vent carries + column truth + thrower
     sleep/wake/HURLS with rite-book cleanup, mist band + live fog
     feed, trail 32 plates/2 legs/starts at camp, five bands whose
     counts ride the data). Gates: underworld 44 / ocean 44 /
     CISTERN-OK / WILDS-OK / swim bridge 10/0 / naming lint 25/0 /
     lint 36/0 / packs 8 green.
  LIMITS + NEXT: lava rivers-as-channels (long segments) beyond the
     lake; ThermalService world-filter is coordinate-honest today
     (underworld columns live at world-local y ~2000); underworld
     launch table + glider HUD reads nothing underworld-specific yet
     (the air answer lives in the tick); on-device: stand at the lake
     overlook at the low tide (mist thick, melt surly), step the
     curb, take the burn, ride the East Stack into the wing.
- WORLD-DRESSING v22: THE FUNCTIONAL AUDIT (render_audit) -- "all the
     recent builds actually exist in the game" proven on live boots.
     dev_temp/probes/render_audit.gd: A) the MAIN WORLD at 20 km
     (PierBeacon + MoorGuide built stone/cap/lamp, halos wired, the
     NIGHT LAW asserted on the boot's own materials [noon epoch
     fraction 0.5 sleeps, 0.75 wakes], the Pans Runner placed with
     DeckPanel + MastBlock collidered); B) the UNDERWORLD through the
     REAL seam (ScopeService.enter_world_scope swap, receive_visitor
     camp landing at skin+0.4, cistern pieces + collider law + the
     vein-wall material, wilds families + law, UnderglowLake curb +
     melt rider, the trail's 32 plates, Warden + zone, thermal
     columns booked, the East Stack carries, the woken thrower HURLS,
     strata mist fed live, the swim quest accepts + credits live, a
     real CharacterBody body takes the BURN and dry ground is free,
     fold-back); C) the RENDER FACTS (256 underworld MeshInstance3D
     all carrying real meshes -- zero bare; light census; headless
     honesty: node/material truth is the ceiling, the pixel pass
     stays on-device).
  AUDIT-CAUGHT FIXES: (1) the lava lake's first geometry sat BELOW
     the walk shell (data surface 1999.6 / floor 1997.8 ~ a body on
     the walk line read DRY over the melt) -- rebuilt to the
     cistern's walk-line dialect: basin slab ON the walk line
     (collidered), melt surface 2001.2 (1.2 m of melt), curb topping
     0.55 over the surface; data .tres re-declared (surface 2001.2,
     floor 2000.0), WALK-IN WADING burn preserved; deep_commons seats
     re-based (18/18 again). (2) audit-side: the light census scanned
     world_root and read zero (the strata light hangs beside it --
     now counts the globe root), the night-law epoch used base+0.75
     from a half-day base (fraction math), the burn seat sat at the
     old 1999 line.
  KNOWN SCRIPT-MODE NOISE (pre-existing, all boots lean): the deep
     derive chain in headless boots emits "Nonexistent function/
     null value" spew (terrain streamer/tint/river spec/road overrides
     -- confirmed identical in the pre-existing harbor probe boot);
     the audit gates on node/material law truth, not on the degraded
     derive path's stderr. On-device acceptance remains: walk the
     trail, step the curb, take the burn, ride the thrower, watch the
     halos wake at dusk.
  GATES after the audit wave: AUDIT-OK (42), COMMONS-OK (18),
     underworld 44, ocean 44, CISTERN-OK, WILDS-OK, LIGHT-OK, swim
     bridge 10/0, naming lint 25/0, lint 36/0, packs 8 green.
- INTERACTION v23: THE TARGET-ACTION LOOP SHIPPED -- the missing game-
     loop beat (walk up to an NPC/gate, press action, interact) is now
     WIRED END TO END. Pipeline truth: E (keybind "interact" via
     InputManager.player_input), the touch ACT button (VirtualJoystick
     button_pressed -> _on_virtual_button_pressed -> the same
     player_input), and desktop left-click all converge on
     PlayerController._on_player_input -> _try_interact -- but
     _try_interact only knew loot/stations/ankhs/doors, and NPC/gate
     menus were trapped behind the long-press RAYCAST (a camera
     cursor). Built the walk-up resolver:
       * TargetingManager.get_nearest_targetable_by_types(from, types,
         max_range): registry scan over EXACT entity types (NPC,
         TELEPORT), live Node3D transforms, freed-node skip (untyped
         read first -- a Node-TYPED read of a freed instance errors
         before any guard), npc_data ingested into the TargetInfo.
       * PlayerController._try_target_context_interact(): an IN-RANGE
         live target (Tab/F2 result) outranks the nearest scan (the
         player SAID who they meant); otherwise nearest-in-6m;
         sets the target through the ONE tm.set_target path (history +
         highlight + tooltip all stay true) and opens the context menu
         CENTERED (no cursor needed). Long-press keeps cursor truth
         (the _show_*_context_menu family now takes an optional `at`).
       * _try_interact order: ground loot first (unchanged), NPC/gate
         action menu second (NEW), placed stations/ankhs after.
     RECEIPT: tests/test_interaction_pipeline.gd gained the loop cases
     via an ASYNC runner (the world boot registers the player ~2 s
     after the NPC spawn, so the runner waits for the player, then
     drives NPC / gate / range stages): menu opens on the press edge,
     NPC targeted by proximity + full offering menu (Talk/Trade/
     Quests/Bank/Skill Academy/Blacksmith/Craft), dungeon-portal gate
     targeted + Enter offered, 40 m out opens NOTHING and targets
     NOTHING, 0 script errors. 19 passed / 2 failed -- the 2 are the
     PRE-EXISTING headless guest-click journey failures (confirmed
     identical on stash; the test's documented runner is xvfb-run).
  GATES: interact loop 9/9 new checks, lint 36/0, naming 25/0.
- TARGETING v24: THE CRAWL + THE RING TRACKER + THE HEADLESS TRUTH --
     "is targeting really everywhere and is there a visual?" CRAWL
     VERDICT: every consumer routes through the ONE TargetingManager
     chain: SpawnService registers everything it spawns (enemies, NPCs,
     loot) and unregisters on despawn; world_playable registers the
     player; Tab/F2 cycle + left-click camera raycast + F2-nearest all
     land in _tm().set_target; the ActionMenu talks targets;
     hud_integrator binds target_acquired/cleared/updated to the
     TargetFrame + BossHealthBar; target_tooltip reads the current
     target; party_frames click-targets through set_target; a11y
     Service re-points the GM target through the same set_target; USE
     SKILL casts at get_current_target().node -- combat included. ONE
     HOLE the crawl caught: the visual target ring (pulsing emissive
     circle mesh "Highlights/TargetingHighlight", seated +0.05 under
     the target at set-time, hidden on clear) NEVER RE-SEATS --
     update_targetable_position and update_highlight have ZERO callers,
     so a walking enemy left the circle behind forever. FIXED:
     TargetingManager._process now re-seats the ring from the LIVE
     ride node every frame it moves (no-op cost otherwise; untyped
     ride read keeps freed-instance reads legal). THE HEADLESS TRUTH:
     the "2 pre-existing" pipeline failures were never environmental --
     they were SCHEDULING drift (the async world boot registers the
     player ~2 s AFTER the fixed 5.0/6.2 slots fire). _await_player
     (bounded 5 s) now gates the catalog/dialog/quest/vendor checks and
     the dialog case re-resolves a LIVE NPC if one despawned during the
     wait (freed-instance property read caught by the run). Plus 3 NEW
     ring checks: ring exists + visible on target, seated under the NPC
     (<1.5 m), hidden after clear. FINAL STATE: interaction pipeline
     27 passed / 0 failed, exit 0, ZERO script errors, twice stable.
     The only stderr left in the run is the guest-click first-slam
     retry [DEBUG] line (click #2 succeeds; not a check).
  GATES: pipeline 27/0 x2 (exit 0), lint 36/0, naming 25/0.
- LOOPS v25: THE GUEST-CLICK NOISE + THE UNWIRED-LOOPS CRAWL --
     (a) the "first guest-click [FAIL] retry" was never a failure:
     login.gd emitted TWO DebugOverlay.log_click markers per click
     (entry false + post-dispatch true) so every SUCCESSFUL login
     printed "[FAIL]..[OK]" noise. One honest log per click now:
     [OK] after dispatch, [FAIL] only on a real dead end (validation
     failure / service unavailable). (b) THE CRAWL (same method as
     targeting): UI dead ends -- the player-target-menu "report"
     action only GameLog'd (now routes through PlayerReporter.
     submit_report ABUSE with the menu target, same path the admin
     shell uses, so alerts + webhooks fire); trade add-item blindly
     added the FIRST bag slot (now a real ItemList picker: one row
     per tradeable slot with stack + rarity, callback-driven
     AcceptDialog so cancel can not strand a suspended await);
     vault_service GUILD/ACCOUNT vaults dead-ended on TODO helpers
     returning "" (now wired: guild id via GuildService.
     get_player_guild()["id"], account id via AccountService.
     get_account_by_character()["id"]); close_vault fired a FALSE
     vault_opened on close (removed -- zero listeners ever read it);
     quest_service.accept-gate skipped min_level (the helper existed;
     the 11 playable quests are all min_level 1, gate now enforced)
     and the per-player load/save dead-ended in db-stubs (now wired
     to the boot loader's living DictStore KV path quest:player:<id>
     -- quest state survives a reload through the public API too;
     stubs deleted). (c) THE SOLID BACKLOG (logged, not fixed):
     188 service signals never fired AND/OR never have listeners
     (notification/telemetry wallpaper -- a multi-round wire-up);
     vent connector GET TODO + NetworkManager.disconnect TODO are
     server/connector infra. All "stub" hits elsewhere are
     duck-typing comments, not dead code. GATES: pipeline 27/0 exit
     0 with zero script errors (also caught + fixed a _gamelog
     casing typo that broke the vault autoload compile -- 9 script
     errors on the intermediate run, clean after), lint 36/0, naming
     25/0, quest gates all exit 0 (availability/daily/explore/swim),
     login flow exit 0.
- LOOPS v26: THE SIGNAL-BACKLOG ROUND -- the honest census first:
     a corrected scanner (the two earlier passes both had regex
     blindspots: Godot-4 obj.signal.connect style THEN the char-class
     ban on dots) puts the real backlog at 680 declared signals =
     259 OK / 335 VOID (fired, unheard) / 78 DEAD (never fired) / 8
     NEWIRE (heard, never fired) -- NOT 188. DYNAMIC EMIT/CONNECT
     CAVEAT: string-built emissions (_hub_emit callv-style) and
     name-keyed UI connect maps (trade_ui, guild_ui, party_ui) are
     invisible to grep -- ground_loot_picked_up was a NEWIRE false
     positive through _hub_emit, and some VOID rows are likewise
     alive. Fixes this round: (1) DELETED the dead event-catalog
     layer -- core/events/{combat,entity,inventory,system}_events.gd
     (4 files, ~66 signals) were class_name'd but not autoloaded and
     referenced by nothing but the auto class cache (verified: no
     preload/load/tscn refs); EventHub remains the one live hub.
     (2) All real NEWIRE loops closed: TargetingManager.target_updated
     now fires ON the frame the ring physically re-seats (cur
     position/world_position refreshed too; was listener-built with
     zero emitters) + target_type_changed on the type flip in
     set_target (tooltip's type row could never appear); blacksmith
     repair_failed/item_too_broken emit at every honest failure leg
     incl. the bulk path (the old filter required can_repair so
     unrepairable-broken could never surface -- unreachable branch
     restructured); quest_failed fires when an IN_PROGRESS daily
     EXPIRES at the sky dawn (the reset helper only cleared REWARDED;
     dailies dangling across days) and abandon_quest emits
     quest_updated so the HUD tracker drops the line; respawn_canceled
     fires when a revive wins the race against the pending timer
     (death-screen countdown could linger); InventoryUI
     item_selected fires on slot select (sibling of use/drop which
     already emitted). (3) BUILT missing live loops: the trade
     anti-scam countdown was FULLY BUILT BUT DORMANT (both-confirmed
     completed instantly; start/cancel/tick/complete + trade_ui's
     tick listener sat dead) -- confirm_trade now starts the 3s
     window once, _run_confirmation_countdown ticks seconds + emits
     tick/complete + completes the exchange, re-fetching the trade
     every beat so a cancel/force-cancel stands it down; a repeat
     confirm during the window cannot shortcut it. GuildService
     invite loop was HALF-BUILT: invites created + persisted then
     UNREACHABLE (no accept/decline/expire endpoints; guild_ui
     called get_pending_invites which did not exist; accepted/declined
     listeners wired in guild_ui with zero emitters; _persist_invite
     indexed the invite dict by player_id although it is keyed by
     invite_id so invite writes were dead) -- added get_pending_invites/
     accept_guild_invite/decline_guild_invite (RECRUIT, notifier to
     the inviter, persistence fixed to the invite_id key +
     _persist_invite_erase twin) and a throttled 30s sweep emitting
     guild/alliance_invite_expired for both families. party_member_updated
     emits at join/leave/kick (party_ui's generic refresh listener
     existed). (4) INFRA TODOs landed: server_manager kick uses the
     REAL chain NetworkManager.kick_player_by_character_id (graceful
     RPC then forced peer close) -- the Todo's guessed PlayerManager
     chain never existed; VantConnector._on_poll now GETs
     /api/action (busy-guarded, shared HTTPRequest with observe --
     the pass-stub meant polls ticked forever and fetched nothing).
     (5) NOT fabricated (no-void law): every remaining candidate
     (channel_settings_changed, cooldown_tick, container_opened --
     which has NO open-endpoint to emit from, npc_spawned, zone
     instance trio, notification_queued, skill_missed, attack_hit,
     threat_overflow, item_bound, bag_locked, badge_earned,
     state_exited, controller pair, observation_ready,
     instance_contract_changed, xp_shared, character_confirmed,
     waypoint_clicked) has ZERO listeners -- emitting would only
     convert DEAD to VOID wallpaper; they are the design contract
     surface, logged. GATES: pipeline 27/0 exit 0 zero script errors,
     lint 36/0, naming 25/0, login + quest gates + ground loot all
     exit 0.
- LOOPS v27: THE CONSUMER-SIDE ROUND (dailies + the zero-listener batch):
     the round flips the no-void law the right way: BUILD THE
     CONSUMER FIRST, then the emits earn their keep. (0) THE EVENT
     CATALOG FORENSICS (owner asked): the deleted 4 files were born
     2026-08-29 by "Event system refactor: EventHub + domain-specific
     buses" (73f6da0) as parallel domain buses, but that commit's own
     migration went to EventHub instead; beyond syntax-fix passes
     NOTHING ever touched them and no doc (TASKS/PRD/AGENTS) EVER
     promised a later role -- the only writes mentioning "catalog"
     are our own round notes. Coverage that actually exists: EventHub
     (56 live signals, the names the code truly uses) + per-service
     signals where the concept exists at all. Nothing of value lost;
     the dead duplicate names would have collided with live ones
     (skill_executed existed in both). (1) DAILIES -> HUMAN DAY: the
     board rolled on SignService.current_day_index = UTC midnights
     (19:00 EST) on the 2-h SKY day; now SignService.current_human_
     day_index keys midnights EASTERN (America/New_York, DST honored
     via the compiled US rule: 2nd Sunday March 07:00 UTC open, 1st
     Sunday November 06:00 UTC close; Godot's own calendar for
     civil dates -- no hand leap math). The Concord calendar (signs,
     almanac windows, ancient door, world seeds, ambience) STAYS on
     current_day_index on purpose. quest_failed wording -> "midnight
     reset". test_daily_quest pins 8 legs: both midnight boundaries
     (05:00Z EST / 04:00Z EDT), spring-forward/fall-back one-second
     edges, offsets -5/-4. (2) THE SLOT SERVICE WAS NEVER PRINTED:
     slot_service.gd had ZERO indentation for its ENTIRE LIFE
     (born flat, 4 commits, all flat) so it NEVER PARSED -- and
     nothing referenced it, so every gate stayed green while an
     unloadable service sat in the tree. Reindented to tabs +
     verified headless load; ContainerConfigData had the same
     disease: a static load() SHADOWING the builtin (recursive
     self-call; "Too few arguments for load()") -- renamed
     load_config() + dict-inference typed fixes. (3) THE CONTAINER
     LOOP LIVES: SlotService.open_container/close_container shipped
     (open validates against the data-driven config, materializes
     the store, emits container_opened; close is the session half,
     delete stays the erase kind); the consumer is REAL -- ContainerUI
     (UIPanel standard shell; idempotent synchronous content build so
     a show before _ready cannot see an empty panel), MenuManager
     mounts it on the "container" registry row, and hud_integrator
     routes container_opened/closed through MenuManager.open_menu +
     a close-guard is_showing(key) (the ONE funnel law). Receipt:
     tests/test_slot_container_open.gd exit 0 (open -> emit -> item
     row renders -> close -> emit). (4) COOLDOWN TICK DRIVES THE BARS:
     CooldownService._process emits cooldown_tick per active cooldown
     (the service's own remaining read); CooldownIndicator connects
     started/tick/ended -- the indicator was BUILT for this and had
     to reverse-engineer the world from RATE_LIMITED toasts;
     cooldown_ended retires a CANCELLED bar instantly instead of
     waiting out the display's own end_time (toasts stay as fallback).
     (5) CONTROLLER PAIR: InputManager hooks Input.joy_connection_
     changed (controller_disconnected had ZERO emitters since birth;
     only the boot leg emitted) and hud_integrator bridges both into
     CONNECTION_QUALITY toasts. (6) GOVERNANCE BADGES: the inner
     ModeratorProgression got an owner hook -- badges collected over
     4 levels with NO up-announcement now flow through governance_ref
     -> _on_badges_gained -> badge_earned (one per badge), and
     hud_integrator bridges to ACHIEVEMENT_UNLOCKED toasts. (7)
     XP SHARED: PartyService.share_xp now emits xp_shared (the split
     result customers: PartyUI refresh); the party panel's refresh
     path rides the same signal. (8) SKILL MISSED: _apply_hit's whiff
     leg emits skill_missed (zero emitters until now) and
     hud_integrator feeds CombatLog.log_miss -- the miss row the log
     has carried had zero callers. (9) HONESTLY DOCUMENTED, NOT
     FAKED: channel_settings_changed (the ignore book has NO listening
     UI -- the next consumer round), npc_spawned (minimap already
     covers NPC spawns via entity_spawned/despawned impressions;
     a second blip layer would mark everything twice), the zone
     instance trio, attack_hit (redundant with skill_hit/skill_
     resolved look), observation_ready/instance_contract_changed/
     notification_queued/character_confirmed/waypoint_clicked stay
     contract surface until their consumers are built. GATES:
     pipeline 27/0 exit 0 zero script errors, lint 36/0, naming
     25/0, daily-quest 8-leg DST block + slot container loop +
     quest/ground-loot/login all exit 0.
- LOOPS v28: THE CHEAP PAIR + THE IGNORE BOOK (consumers for the last
     small contract names, then chat moderation itself):
     (1) WAYPOINT PING LIVES: full-map clicks get the navigate law
     the class comment always promised. Click ON a quest waypoint
     marker -> waypoint_clicked (zero emits until now; hud reads
     WorldMap.last_waypoint_hit() synchronously for the marker
     label), click on canvas -> map_clicked with a TRUE world
     position (spherical law inverts lat_lon_to_uv exactly; the old
     _screen_to_world fabricated flat 8km coords). Consumer =
     hud_integrator._route_map_ping -> WaypointService.create_waypoint
     ("Map Marker" / "Quest: <label>") + activate_waypoint (beacon +
     compass ride the service's own law; the service's notify path
     already answers rate-limit/cap/invalid). Receipt
     tests/test_map_ping_route.gd exit 0 (marker hit -> waypoint_clicked,
     canvas -> map_clicked at (20001,0,0), create+activate truth).
     (2) CHARACTER CONFIRMED + THE KIT GATE: character_select emits its
     declared signal on Enter World (both legs are creation paths).
     StarterKitService listens via a tree node_added relay (the scene
     mounts/tears down freely) and gates the grant: fresh-confirmed OR
     no saved progress earns the kit; returning characters STOP
     collecting a second kit on every boot (the _granted_for set was
     session-only -- a per-boot double-grant bug the gate fixes).
     Receipt tests/test_character_fresh_kit.gd exit 0 (declared+emitted,
     relay connects, fresh + never-saved pass the gate).
     (3) IGNORE BOOK LOOP: '/ignore' had a signal pair
     (player_chat_ignored/unignored) and ZERO persistent storage + ZERO
     listening UI (the list evaporated every reboot) and the chat UI's
     local star-match reported "Unknown command" for every service
     command. Shipped: ChatService ignore_player/unignore_player/
     get_ignored_players/is_ignored_sender (self-ignore + duplicate +
     SYSTEM refused with named causes; names persisted, id-or-name
     blocked-sender matching at display time), _ready now calls the
     previously-dead _load_chat_state (KV revive), /ignore//unignore/
     /muted route through the API, ChatUI's default command branch
     passes through the service's router directly (send_message would
     swallow unknowns -- direct call keeps the unknown-command line),
     add_message drops blocked senders on BOTH chat surfaces (MenuManager
     feeds the same panel; optional viewer_id for script-side receipts),
     IgnoreBookUI (UIPanel shell, idempotent synchronous build) mounted
     on MenuManager's "ignore" row behind the funnel, chat header gets
     an [Ignore] button. channel_settings_changed STAYS contract
     surface (its per-channel semantics = a channel-mute feature this
     round does not fake). Receipt tests/test_ignore_book_loop.gd exit 0
     (API+KV truth, signals, blocked/allowed/failed System lines,
     panel render + unignore).
     (4) DRIVING FIX: WaypointService (and trade_service/admin_commands)
     called EntityService.get_entity_by_id, which DOES NOT EXIST on
     EntityService (the real lookup is get_entity) -- every waypoint
     activation crashed the proximity _process tick; replaced all four
     call sites. GATES: pipeline exit 0 zero script errors, lint 36/0,
     naming 25/0, map-ping/fresh-kit/ignore-book + login receipts all
     exit 0.
- LOOPS v29: CHANNEL MUTE BECOMES REAL (the channel_settings_changed
     owner): the last un-faked contract name now has its feature, no
     dummy emits. Mute = a RECEIVE-side filter: the viewer hides a
     channel's incoming live lines in their own view only (their own
     sends ride the normal pipeline); System stays unmuteable (it is
     the game's error/announcement voice -- blocking it would blind
     your own feedback). CHATSERVICE: set_channel_muted/is_channel_muted/
     get_muted_channels/channel_by_name + _mute_record (records are
     channel ENUM-NAME strings so the KV round-trip is string-stable);
     every real change emits channel_settings_changed and persists
     through _persist_player_settings -- the _player_settings dict and
     its chat:settings: KV key were declared+loaded+persisted at birth
     and written by NOTHING until now (the born-dead twin of the
     ignore list; the load leg already round-tripped, now the write
     leg is real). Named refusals mirror the ignore API: duplicate
     mute ("already muted"), unmute-when-not ("not muted"), protected
     System. COMMANDS: /mute <channel> //unmute <channel> //channels
     (the state board, System shown "(always shown)") ride the API;
     /muted now ALSO lists muted channels (the name collision with
     the old ignore-list-only output is finally honest). PANEL:
     ChannelSettingsUI (UIPanel shell law, class_name) -- one row per
     channel catalog (enum read through the service instance so the
     panel never re-derives ids), protected System last, state label
     + Mute/Unmute toggle, refreshes on the service's own
     channel_settings_changed signal (no private re-read) and mounts
     on MenuManager "channels" + the chat header [Channels] button
     (funnel = the ignore book's law). FILTER: ChatUI.add_message
     drops a muted channel's incoming lines under the same
     one-filter-covers-both routing the ignore law uses. RECEIPT
     tests/test_channel_mute_loop.gd exit 0, 7 legs: emit truth,
     duplicate/System refusals, KV + fresh-service reboot round-trip
     (revive through _load_chat_state -- no more reboot evaporation
     for settings), /mute//channels command legs, display filter
     (muted Trade hidden / Zone shown / System shown), panel
     shell+catalog + toggle-writes-what-it-displays. BUG CAUGHT:
     iterating an enum bare (`for channel in Channel:`) iterates the
     enum NAMES (strings), not values -- channel_by_name +
     _cmd_channels + the _ready history init all tripped it; the
     history init had silently keyed _chat_history by "SAY".."EMOTE"
     since ChatService was born (int-keyed lookups missed until the
     guarded lazy re-init healed them per channel); now all three
     iterate Channel.values(). Receipt-lore: DictStore has erase()
     not erase_value() (the ignore receipt's erase_was-a-has_method-
     guard-noop fixed as collateral in docs); queue_free twins the
     refreshed rows for a frame, so a row-state read goes through
     the children (latest wrapper wins), never a flat node path.
     GATES: pipeline exit 0 zero script errors, lint 36/0, naming
     25/0, ignore-book + map-ping + fresh-kit + login receipts all
     exit 0.
- LOOPS v30: THE COMBAT-SENSE ROUND (fresh census + honest removals):
     a fresh census ran FIRST (598 declared / 234 OK / 282 regex-VOID
     / 82 DEAD) followed by a TRUE-VOID scan (zero textual mentions
     beyond decl(+emit): 265 names) because the connect-regex is
     blind to name-keyed UI connect maps (leader_changed: BOTH party
     and guild UIs already ride it as map keys -- census false) and
     string connects; loot/spawn/edge signals that pass the true-void
     scan are the real wallpaper. THE CAST-SENSE LOOP SHIPPED: the
     player's own CombatComponent lifecycle (cast_started/cast_
     finished/channel_ended/combat_entered/combat_exited) emitted
     zero-listener since birth; hud_integrator._bind_player_
     combat_feedback (deferred, local_player seam, no-crash no-player
     law) binds the component's five signals into NEW CombatLog rows
     (System family: "You begin casting X" / "You finish casting X" /
     "You stop channeling X (interrupted)" / "You have entered/left
     combat") -- player-local on purpose, enemies already surface via
     skill_hit/skill_resolved. Receipt tests/test_combat_sense_loop.gd
     exit 0 (binder no-op honest, lifecycle rows truth-verified
     through the entries, bridge proven connected). TWO VOID WALLS
     DEMOLISHED (mirror of the close_vault law: an announcement rule
     is already carrying the signal's voice -- a second lane with no
     consumer repeats it):
       (a) chapter_recorded removed from ActsService -- the announce
       path _announce_chapter already notifies the player and the
       Chronicle panel re-reads on open (panel_opened -> refresh);
       (b) boss_spawned removed from SpawnService -- the world-boss
       arrival voice ALREADY rides NotificationService's own bridge
       over EventHub.entity_spawned (metadata notification_enabled +
       scopes; the spawn path defaults an empty scope to SERVER-WIDE
       so the classic boss announce reaches everyone); a hud
       listener would have double-toasted every boss spawn.
     The receipts also pin the bridge truisms (entity_spawned ->
     _on_entity_spawned connected). DRIVEIER FIX: PlayerManager.
     set_local_player(null) crashed on the display-name duck-read
     ('String' and 'Nil' in 'in') -- clearing the slot (logout,
     probe teardown) is a legal state; guarded. Census verdict jumps:
     remaining TRUE-VOID clusters by family: economy (gold/xp
     catalog ghosts), combat telemetry (attack/cast on the shared
     combat_component? no -- the local-player cast half is fixed;
     enemy/threat sides remain), zone instance trio, npc_spawned
     (documented: entity_spawned covers it), observation_ready,
     instance_contract_changed, notification_queued. GATES: pipeline
     exit 0 zero script errors, lint 36/0, naming 25/0, new receipt +
     login + map-ping + fresh-kit + ignore-book + channel-mute +
     daily + acts all exit 0.
- LOOPS v31: THE ECONOMY ROUND (the true-void cluster audit paid in rows):
     the audit showed the "dead economy ghosts" were only census
     artifacts: gold_gained/gold_spent/xp_gained/item_equipped live
     ONLY in the capture-layer core/events/{entity,inventory}_events
     (hub-referenced for diagnostics, per v30). THE REAL MONEY
     MACHINERY WAS NEVER VOID -- it was TWIN-VOICED AND INVISIBLE:
     two honest wallets move the local player's gold (the NODE wallet
     -- PlayerController.gold -- paid by kill rewards/ground
     loot/horde/dwellings; the COMPONENT wallet -- the mounted
     InventoryComponent._gold -- spent by vendors/blacksmith/vault/
     ferry/transfers) and each already emitted gold_changed to
     essentially nothing (blacksmith_ui was the single consumer;
     PlayerManager.gold stays the silent persistence mirror the
     boot-restore writes -- unchanged, documented). SHIPPED: hud_
     integrator._bind_player_wallet_feedback (deferred, local-player
     seam, per-leg guards so a rebind cannot skip the component legs)
     binds BOTH wallets into CombatLog rows -- node wallet speaks in
     paid deltas with seen-total seeding (hydration re-emits stay
     quiet), component wallet rides its signed deltas (+N loot rows /
     -N system rows), and the NEW item_equipped voice (item,
     slot_name, equipped: bool) lands "You equip Iron Sword
     (off_hand)." rows. InventoryComponent earns the equip voice on
     its REAL endpoints: equip_item/unequip_item emit, and
     clear_equipment_slot (full-loot strips) counts as an unequip the
     player sees; _equip_slot_name reads Item.EquipSlot.keys() (the
     sword's tres really declares equip_slot = 8 = off_hand --
     flagged, not changed). InventoryUI got its GOLD LABEL LIVE: the
     label only refreshed on rows/item_transferred so an open bag
     said "Gold: 0" through every spend (receipt leg 5 catches it);
     DRIVE-BY CAUGHT: inventory_ui._setup_header was BORN ORPHANED
     (zero callers) -- the bag shipped with no title, NO close X, and
     the gold total never rendered anywhere; the call sits at the end
     of _setup_panel now. Receipt tests/test_economy_wallet_rows.gd
     exit 0 six legs (binder no-crash, dual-wallet seed, hydration
     quiet + +45 delta rows, vendor +50/-25 rows, equip/unequip/
     strip rows via wep_iron_sword through the REAL bag, open-bag
     label follows the wallet -- probe rides open() not a bare
     private refresh). Script-mode lore added: a bare Node gains NO
     properties from set() -- probe wallets declare them in a tiny
     dynamic script (signal + gold + inventory_component). Split-
     wallet debt persists by design: node gold and component gold
     are separate sums until a unification decision; the rows are
     per-wallet honest, no fake unified display. GATES: pipeline
     exit 0 zero script errors, lint 36/0, naming 25/0, economy +
     combat-sense + login + map-ping + fresh-kit + ignore-book +
     channel-mute receipts all exit 0. NEXT from the true-void
     list: enemy/threat combat telemetry, the zone-instance trio,
     npc_spawned (entity_spawned covers), observation_ready,
     instance_contract_changed, notification_queued.

## 2026-11-01 -- PREMIUM WALLET ROUND (the one purse + the real-money seam)
The owner asked for three things and this round shipped all three:
1. THE SPLIT WALLETS ARE UNIFIED. InventoryComponent is THE wallet per
   player: get_currency_amount/add_currency/remove_currency take "" and
   "currency_gold" into the gold legs, everything else rides the R46
   ledger (catalog gate + caps). PlayerController.gold is now a synced
   MIRROR: the property setter turns every direct write (progress
   restore "gold = N", horde share math, dwelling field-math) into a
   REAL purse delta, add_gold delegates to the mounted component (one
   voice), the _ready adoption step resyncs from a boot-restored bag,
   and the purse's gold_changed drives the mirror back. PlayerManager
   gold stays the silent persistence mirror (documented, unchanged).
2. MULTI-CURRENCY + PREMIUM. CurrencyKind.PREMIUM + Concord Sigils
   (data/currencies/currency_concord_sigil.tres; kind 5, soulbound,
   never convertible, gold_per_unit 5000). The UNDERDECK FIXER (new
   NPC in Nexus Central's capitol strand frame + zone roster) sells
   ledger goods: sigil-priced accessories + scrip-priced coins/charms
   and skiffs. VendorService learned per-entry currency (catalog rows
   carry "currency"; buy_item affords/pays through the unified ledger
   with per-currency refuse messages); ShopUI quotes them properly.
   The non-gold ledger found its voice: hud binder binds
   comp.currency_changed -> +N/-N <display_name> rows (restores never
   emit, so no seeding law needed); the bag header now carries a live
   ledger strip beside the gold label (comp.get_currency_ids()).
3. THE PAYMENT PLUGIN SEAM (no processor wired, structure only).
   core/economy/: PaymentProvider (base contract; statuses
   pending/complete/cancelled/refused), ManualPaymentProvider (buyer-
   real checkout; money moves ONLY through fulfill_purchase() -- the
   operator seam an adapter replaces), PaymentProviderRegistry (board
   by id; re-register REPLACES = swap law; seeds manual default).
   PremiumShopService (VendorService singleton dialect) owns the board
   (registry() -- no static-call quirks), opens/cancels orders, and
   grants sigils ONLY on provider-complete via the ledger (ONE grant
   leg, kind-validated, closed once). PremiumShopUI = MenuManager
   "premium" panel (service-gated law: NPC proximity + walk-away
   close) reachable via the fixer's action-menu "Sigil Vault" or the
   [E] Open Sigil Vault prompt; live balance, processor name, SKUs,
   pending order + cancel.
Receipt: tests/test_premium_shop_loop.gd exit 0 six legs. GATES:
pipeline exit 0 zero script errors, lint 36/0, naming 25/0, all prior
receipts exit 0. NEXT: the true-void survivors -- threat telemetry,
zone instance trio, npc_spawned, observation_ready,
instance_contract_changed, notification_queued.

## 2026-11-01 -- TRUE-VOID SURVIVORS ROUND (the list closed)
Every survivor from the census's true-void scan got its honest end:
1. THE THREAT SENSE (enemy/threat telemetry): hud_integrator._bind_enemy
   _threat_sense joins SpawnService.enemy_spawned and binds each enemy's
   AggroComponent legs; rows only touch the local player: focus flips
   ('The Wolf turns its attention on you.' / 'You slip out of...'),
   threat_overflow (FIRST HONEST EMIT at aggro's clamp leg, exactly
   once per first cap crossing), and out_of_combat ('...breaks off.'
   via the focused-on-you book). threat_changed REMOVED (decl + all
   three emits: every leg is either a flip or an overflow).
2. THE ZONE TRIO: InstanceService now SUBSCRIBES ZoneManager's
   instance_created/instance_destroyed and re-rebuilds the instanced-
   zone registry live (the once-at-boot rebuild left fresh creates
   stale until reboot -- a real bug the emit named). instance_contract
   _changed REMOVED (zone contracts are boot-static, no mutate path).
3. RETIRED WITH CAUSES: npc_spawned (entity_spawned owns spawn voice;
   minimap rides it), notification_queued (queue legs already speak
   through notification_sent + history; the silent pop-oldest overflow
   now GameLog.warns), observation_ready (the POST leg lives in
   send_observation; no consumer ever existed).
4. DRIVE-BY: the connector native-shadow law -- AgentConnector/Vant/Mcp
   had connect/disconnect/is_connected overriding native Object methods
   and AgentAction.to_string() shadowed too (warnings-treated-as-errors
   only surface when a receipt compiles the chain, so the pipeline never
   saw them). Renamed connect_agent/disconnect_agent/is_agent_connected
   (+ call legs and the two service callers); the un-called to_string
   deleted.
Receipt: tests/test_true_void_survivors.gd exit 0 five legs, zero
SCRIPT ERROR. GATES: pipeline exit 0 zero script errors, lint 36/0,
naming 25/0, all prior receipts exit 0.

## 2026-11-01 -- BLACK MARKET GAMBLE + PAYMENT ARMOR ROUND
1. THE DEEP ROLLS: the fixer is a gambler -- roll_deep debits real
   sigils from the ONE purse and lands ONE weighted draw out of REAL
   LootTable pools (loot_black_market_tide 3 sigils / depths 12 with
   rarity_boost 2.0). Server-only math (client sends a roll_id),
   grant-through-DataService, failed grant refunds, roll_granted +
   audit lines, QoS gate BEFORE the debit, honest named refusals.
   Pools grow by appending entries as the gear catalog grows (receipt
   refuses phantom SKUs).
2. THE WEBHOOK ARMOR (defense in depth): WebhookPaymentProvider --
   env secret never in repo + fail-closed, HMAC-SHA256 over raw
   bytes, 5-min freshness window, order-binding to its own pending
   order, server-side sigil accounting, one-time completion with
   honest duplicate refusals. Service grant re-validates kind/amount.
3. REBOOT LAW: premium open orders persist via DictStore
   ("premium:order:" -- hydrate on _init, persist on open, erase on
   close). Adapters re-register at boot.
4. PANEL: Deep Rolls rows under the SKU board (cost, pool tooltip,
   Roll buttons, notifications, live refresh).
Receipt: tests/test_black_market_gamble.gd exit 0 six legs. GATES:
pipeline exit 0 zero script errors, lint 36/0, naming 25/0, receipts
(gamble/premium/economy/true-void/combat/progress/kill/login) exit 0.
NEXT: real processor wiring behind handle_webhook, sigil-sink catalog
expansion, census/gaps rounds continue.

## 2026-11-02 -- ECONOMY AUDIT ROUND (bugs, gaps, edges, vulns)
Sweep across the gamble surfaces + payment seam + panel. FIXED on the
same lands: (1) quantity book-lie -- the roll granted min_quantity and
reported a separately rolled count up to max (a min1/max3 entry said
x3 and paid x1); the band is rolled ONCE in _draw_shape and every
count in the grant is that number; corrupt bands clamp instead of
randi_range-aborting past the debit. (2) paid-order burial -- the
service poll closed the order before granting; a failed grant erased
a genuinely-paid checkout; grant-before-close now and the poll
re-attempts while the provider keeps reporting complete. (3) cancel
buried money -- provider.cancel flipped COMPLETED orders to
cancelled on both webhook and manual processors; both refuse it now
and the service honors the refusal, keeping the order open for the
poll leg. (4) provider half of the reboot law -- webhook _orders rode
RAM; records persist through the DictStore KV door
("premium:webhookorder:"), hydrate in _init, stay after
completion/cancel, ids loop-until-unique. TIGHTENED: empty derived
HMAC refuses instead of skipping; sigils priced into the order at
begin; toast dedupe keys carry the message hash; dead `ok` var gone.
Receipt grew to 9 legs (cancel-refuse recovery, grant-failure retry,
webhook idempotence past reboot) -- exit 0. Premium receipt 6 legs
exit 0, lint 36/0, naming exit 0. Pipeline at this restored sandbox
exits 1 on PRE-EXISTING probe legs (stream continents a-d, crafting,
thermals -- Oct-18-era world/streamer probes; reproduced at the pushed
HEAD with the round stashed; suspected partial .godot import cache
after restore) -- NEVER the economy surfaces; all their receipts ran
green inside the pipeline. NEXT: real processor transport ->
handle_webhook once per delivery, sigil-sink catalog expansion.

## 2026-11-02 -- PR-18 REVIEWED, VERIFIED, LANDED (GLM + DeepSeek tag team)
OpenHands built a branch (fix/terrain-stream-probe-surface) auditing the
processing harness exactly where the last round's pipeline had died
(stream continents a-d, crafting, thermals). Review: patches re-read
line by line, every claim re-verified locally. REAL PRODUCT BUGS it
fixed: (1) cosmic_rng.stir_from_cosmic read CosmicEntropy.total_chaos
as a PROPERTY but it is an ACCESSOR METHOD -- every stir THREW
"Nonexistent 'int' constructor" and silently dropped the chaos entropy
word (equal-kp skies produced identical streams); accessor call guarded
+ test mirror fixed. (2) inventory_service.get_inventory handed a freed
registration back as a typed value; is_instance_valid guard + stale-row
drop. (3) hud wallet binder read player.gold_changed unconditionally;
globe body has none (component purse) -- has_signal guards on both
legs. (4) runner DEFAULT_SET/LONG_TESTS word-split with comment lines
in => phantom test names + empty grep pattern => long timeout for all;
lists now stripped before iterating. STALE ASSERTS updated: continent
shards >=2 surfaces (streamer emits ground+skirt+hydrology water
legitimately), thermals 10 (8 thermals + 2 launchers after
underworld/ascenion), rebase probe drains pending_derive before
reading streaming faces, globe driver asks is_glued(2.0) instead of a
prototype-era fixed ride-height. VERIFIED IN THIS SANDBOX: pipeline
exit 0 / 101 passed / 0 failed / 0 phantom / 0 SCRIPT ERROR (previously
"failing probes" were code bugs, NOT import-cache drift -- hypothesis
retired); lint 36/0; naming exit 0; cosmic, thermals, gamble 9,
premium 6 receipts exit 0; parse checks clean on all 12 touched files.
Most of the effective harness strain: PR merges two DIFFERANT thinkers
clean: OpenHands' audit craft + my rest-and-recovery harness memory of
which receipts call what. NEXT: processor transport + sigil sink
catalog.

## 2026-11-02 -- WEBHOOK TRANSPORT (the round the door learned to answer)
Before this round the payment armor had a perfect front half and NO
back half: handle_webhook existed, was armor-perfect, and consumed
ZERO real deliveries -- the external processor could POST all day and
nothing polled the queue (three shipped SKUs, one wall between
customer and wallet). Shipped the full loop, split like the repo's
sidecar law says:
- srv/webhook-bridge/ (main.py + server.py + backends.py + README +
  14-test suite + entrypoint wiring): the PUBLIC HTTP entry on 8083,
  nginx /hooks/<channel> -> 127.0.0.1:8083 in BOTH server blocks (own
  hooks rate zone, 64k cap, 413 before store, 503 when saturated).
  Stores deliveries VERBATIM: raw body base64 (never re-serialized --
  the HMAC chain must see exactly what the processor signed), headers
  lowercased with hop-by-hop stripped, the signature header untouched.
  Claims with per-claim TTL (dead pollers reopen, at-least-once); acks
  carry the engine VERDICT (processed|refused|expired|error + detail);
  delivered records stay as operator audit; /stats + /deliveries/<id>
  readouts. STORES NO SECRET, VERIFIES NOTHING: PAYMENT_WEBHOOK_SECRET
  stays in the engine env (zero-knowledge law holds; the bridge is
  transport, not armor).
- game/core/economy/webhook_transport.gd: the engine poller. OFF
  unless WEBHOOK_BRIDGE_URL env (NetworkManager boot seam, prod/server
  only). Poll /deliveries/next on a timer; route channel->provider
  (PAYMENT_WEBHOOK_PROVIDER env, default "webhook") through the
  PremiumShopService registry resolver (injectable seam for script
  receipts); call provider.handle_webhook(RAW bytes, headers) ONCE per
  delivery -- the per-process _handled ledger is the once law's whole
  runtime (redelivery re-acks the FIRST verdict, the door never
  re-runs); settle-then-answer so no re-entrant beat double-runs the
  door; refusals ANSWER (they ack + settle -- a refusal that never
  acked would replay-wrap forever); transport legs retry fail-soft.
  GameLog audit line per verdict; no signals emitted (no consumer
  law). Verdict mapping: door complete -> processed (poll leg pays),
  refused -> refused (armor's reason on the record), cancelled ->
  expired.
- GATES: bridge python suite 14/0 exit 0; live sidecar smoke (health,
  POST accept 202, GET claim with signature header intact lowercased,
  queue view) exit 0; parse checks on both new/edited .gd files exit 0
  (network_manager's bare-autoload compile note is the documented
  script-mode artifact, identical pre/post at HEAD); engine receipt
  tests/test_webhook_transport.gd exit 0 (boot law OFF/ON, once-law
  signed truth pays 100 through the poll leg exactly once, redelivery
  honesty, refusal settles, routes refuse by name, mixed-case
  signature header survives); lint 36/0; naming within pipeline.
  Deliberately NOT in the runner DEFAULT_SET: same precedent as the
  premium/gamble receipts (money suite; no pack-count drift).
- NEXT: sigil-sink catalog; OpenHands' staging PRs A (gameplay
  driver), B (crafting leg), C (perf honesty) reviewed when they land.

## 2026-11-02 -- PR #20 REVIEW + MERGE (the round the loop learned to die-and-pay)
OpenHands' PR #20 (branch pr-a-playthrough-driver, head 4e1ed9b) reviewed,
verified locally on the MERGED tree, and merged into main (merge commit
315d607; PR marked merged with authorship). PR #18 closed landed-not-merged
(e1f49bc); issues #19 (terrain static-resolution stderr race, cosmetic) and
#21 (character panel reads stale CharacterData stats instead of live
gear-adjusted player stats) left open + tracked for the next rounds.
- THE DRIVER: game/tests/playthrough_driver.gd + playthrough_driver_runner.gd
  (node-runner pattern, same SceneTree-await-stranding law as globe_driver)
  walks the REAL input pipeline on world_playable: spawn -> F2 target the wolf
  through the input map -> attack until it dies -> collect the corpse through
  the interact action -> equip wep_iron_sword -> blacksmith repair -> NPC menu.
  Uses live-node asserts, real key events, fight isolation (scene wildlife
  freed, health pool padded, nondeterminism documented). Registered in the
  runner DEFAULT_SET (102 tests now).
- THE SIX BUGS, all verified in the patch before landing:
  1/2. inventory_component._apply_equipment_stats read the parent as TYPED
       Entity -> runtime type-assignment abort on PlayerController, so gear
       moved NO attributes; and add_stat re-add stacked bonuses with no
       inverse (double-count on re-equip). Deltas now idempotent against
       _applied_equipment_stats; player gains the Entity-parity get_stat/
       set_stat/add_stat surface (deliberately silent -- no void emit).
  3. enemy._roll_and_drop_loot gated on items only: currency-only rolls
     (~46% of wolf kills) never dropped their gold at all.
  4. ground_loot_service.try_pickup never consumed a currency-only drop:
     re-press E farmed the same gold forever (INFINITE-GOLD EXPLOIT). Coins
     paid -> drop removed; regression leg in test_ground_loot.
  5. target_frame resolved a TargetInfo's id as entity_id (always ""): the
     frame HID ITSELF for the whole game. Id normalization (dict/id/entity_id)
     + render on acquisition + stored label refs; latent _update_bars child
     index bug fixed too.
  6. respawn_service._get_nearby_potential_healers threw on NPCs (no
     health_component) and KILLED THE RESPAWN FLOW near any NPC; plus the
     dungeon portal registered schema_id "teleport" where only "gateway"
     exists. Both duck-typed/register-corrected.
- GATES on the merged tree (main's webhook a571019 + #18 fixes + #20):
  pipeline exit 0 with 102 passed / 0 failed / 0 phantom, ZERO script errors
  (playthrough_driver included); lint 36/0. Push survived two rejections
  (CI's pck refresh raced the push; merge rebuilt on the remote tip 2ba77a3,
  no re-verification needed -- content identical).
- NEXT: sigil-sink catalog; consider #21 as part of it (the panel should read
  the live gear-adjusted stat surface).

## 2026-11-02 -- SIGIL-SINK CATALOG (the round the mirror door opened)
The vault panel could bring sigils IN (SKUs, webhook delivery, the
gamble's reverse door) but had no honest OUT: nothing in the repo
spent a Concord Sigil on anything. Shipped the sink catalog: real
prices on real service doors, priced against the processor SKUs
(sigil_100 = $4.99 floor).
- core/services/sigil_sink_service.gd (the PremiumShopService
  dialect: static _instance + singleton(), no autoload wiring needed):
  const catalog of SEVEN sinks -- five VENDOR-source steed deeds out
  of RideService's real ownership book (Meadow Pacer 150 / Plains
  Runner 250 / Reef Glider 400 / Trench Wyrm 650 / Storm Lancer 900,
  all data/mounts truth; the GM Skywarden's mount is refused one gate
  BEFORE the service's own fail-closed) + two NEW title editions in
  data/titles/ (title_pillarsworn.tres, title_deepseabaron.tres --
  UnlockMethod.PURCHASE, which existed in the schema at birth and now
  earns its grant leg) priced 200/500 out of TitleService's real
  register.
- BOOK LAW (the audit talks hold): gate-before-books (availability,
  unknown id by name, already-owned read off the REAL books, exact-need
  affordability, QoS rate gate under "sigil_sink_purchase") then
  debit-once, grant-once, REFUND on any refused grant leg (hard
  GL.error when a refund cannot land), GL.info audit per sale, and ONE
  sink_purchased signal (consumer = the panel; no-void law).
- TitleService has NO class_name: bare static calls do not compile in
  --script/--check-only context AT ALL (reproduced: player_manager.gd
  at HEAD, untouched, fails check-only on bare autoloads). The service
  routes title legs through the autoload NODE calling the same
  instance impls the static facade wraps (_has_title/_do_unlock/
  _do_equip).
- PremiumShopUI grew the mirror half under the Deep Rolls: a "Where
  sigils go" section rendering get_catalog(player_id) with OWNED state
  read from RideService/TitleService at render time, disabled Buy on
  owned rows, hashed dedupe toasts on both outcomes, refresh on the
  service's own signal.
- Receipt tests/test_sigil_sink_catalog.gd exit 0 six legs (catalog
  truth incl. no phantom ids + no GM price, unknown/wallet-less/broke
  refusals by name with books untouched, Pacer for exactly 150 into
  RideService.owns_mount with dupe refusal without a second debit,
  Pillarsworn for exactly 200 + equips through the real equip surface,
  the refund law exercised through injected refusing doors on a fresh
  instance -- the transport-receipt seam pattern -- recovering every
  sigil on both stable and herald legs, the purchase voice + panel
  render + owned rows read true). Deliberately NOT in the runner
  DEFAULT_SET: money-suite precedent; no pack-count drift.
- GATES: receipt 6/ALL-OK exit 0; lint 36/0 (the sink file hit the
  one lint miss: continuation alignment mixed tabs+spaces -- tabs
  only in GDScript, fixed); full pipeline in flight this round.
- NEXT: Concord money-hub world-building (where the sinks physically
  live), then PR-IO review keeps OpenHands' dialogue/quest lane clear.
## 2026-11-03 -- MONEY-HUB WORLD-BUILDING (the sinks get a physical home)
After the sink catalog shipped, the mirror door had a service but no
place in the world: nothing on the globe sells the sinks. Shipped the
Concord money hub: a shrine + a herald in Nexus Central's capitol
plaza, all riding existing plumbing with zero service changes.
- village_props.gd: `concord_shrine` kind on PropKind + _concord_shrine
  builder (dais, 5 m pillar, sky-cyan emissive TorusMesh sigil band
  emission 1.2, bronze capstone, OmniLight halo) + CAPITOL_BATCH row
  bearing -95; body attaches via the in-tree law (PropCollider.attach
  deferred in a lambda -- the source lock read attach's returns, so no
  parallel body earned its node name).
- spawn chain: globe_world.gd CAPITOL_NPC_BATCH row ("npc_concord_
  herald", -95.0, 0.006) + zone_nexus_central.tres roster entry; new
  data/npc/npc_concord_herald.tres (NPCData: merchant_general.tscn
  scene, offering ref concord_pillar_vault; `npc_type` omitted -- not
  in npc_data.gd's schema, it is orphaned dead data in old .tres
  files) + data/npc_offerings/concord_pillar_vault.tres (NPCOffering
  -> PremiumShopService, panel premium, mirroring
  black_market_premium.tres). Verified at the seams (action_menu.gd
  offering rows, npc_entity.gd interact prompt): the "Sigil Vault"
  action menu + "[E] Open Sigil Vault" prompt mint themselves.
- Receipt dev_temp/probes/concord_shrine_probe.gd (dev_temp only, NOT
  in runner DEFAULT_SET -- world-building precedent, no fleet-pack
  regen) exit 0 SHRINE-OK 14 passes / 0 misses: data doors (herald
  loads, offering ref, premium panel route, roster + batch rows), a
  REAL globe boot leg (ConcordSinkShrine node found, herald entity
  carries npc_data.id "npc_concord_herald"), the factory body/glow
  laws on a fresh _instantiate (PropBody BoxShape tall > 4.5,
  emissive TorusMesh band + OmniLight halo found).
- NOISE VERDICT SETTLED: the intermittent boot SCRIPT ERRORs
  (sector_cache set_value/get_value on RefCounted, get_ticks_msec on
  null, "Nonexistent function '' in base 'Vector3'") were suspected
  round-introduced; HEAD control stash cycles with the fixed probe
  reproduce the SAME classes at HEAD (4 lines, counts vary per boot) --
  pre-existing globe boot randomness, not this round. Probe lore:
  boot shrine legs and factory legs both run regardless of which path
  placed the node (or its absence at HEAD), and the probe gates ONLY
  on its own verdict, never on the boot's stderr.
- probe_starter_village (runner set) stale eliminations refreshed:
  capitol prop family now 4 ("ConcordSinkShrine" joins the ankh, moon
  gate, bout stones) and the capitol roster counts >= 8 incl. the
  herald, so the shrine no longer lands in the NPC bucket by
  elimination.
- GATES: probe exit 0 / 14 OK; lint 36/0; full pipeline exit=0, 102
  passed / 0 failed, zero SCRIPT ERROR lines.
- NEXT: issue #21 (character panel reads stale creation-time
  CharacterData instead of the live gear-adjusted stats), then the
  OpenHands dialogue/quest lane stays clear.

## 2026-11-03 -- CHARACTER PANEL LIVE STATS (issue #21)

The character panel stopped reading creation-time CharacterData and
now renders the character as they actually are.

- LIVE-TRUTH LAW: `_refresh_stats_display` rides the LIVE level
  (`_get_local_player()`'s `level`, else the book's), and totals come
  from `CharacterData.get_stat_total(stat, level_override=-1)` while
  the gear delta is read straight off the live bag via
  `get_equipment_stats()` (the same book `_apply_equipment_stats`
  pushes onto the player -- single source of truth, no parallel
  write).
- DERIVED REROUTE: new `CharacterData.get_derived_stats(stats_override={})`
  receives the merged live book (ALL six keys; missing keys pad at
  10), so the derived rows answer with the life-instant numbers and
  the formulas stay CharacterData's alone.
- THREE DEAD-AT-BIRTH LEGS KILLED: the equip picker + apply handler
  iterated `inv._items` (never a member; the store is index-addressed
  `_inventory`) so "No equippable items" was all the picker ever
  said; the stat value lookup `VBox/Value` named a grandchild
  (card > HBox > VBox > Value, HBox auto-named) so the six value
  labels froze at birth text forever (HBox named, lookup
  `HBox/VBox/Value`); and the tab never re-rendered on show or
  equip/unequip (refresh hooks added).
- RECEIPT: probe_character_panel.gd extended in place (runner
  DEFAULT_SET, modified not added) with leg group E: level law
  (live 7 outruns stale cd.level=1), real gear through a real bag
  (sword +5 str, ring +2 vit, equipped by ITEM ID -- add_item stores
  a duplicate, identity comparison misses), header "Level 7" over a
  cd.level still saying 1, strength card exactly "%d (+5 gear)",
  derived max_health by the same method. Probe exit 0, 24 checks /
  0 misses, 0 SCRIPT ERROR.
- GATES: probe 24/0, lint 36/0, full pipeline exit 0 (102 passed /
  0 failed / 0 SCRIPT ERROR).

## 2026-11-03 -- TERRAIN TEARDOWN FENCE (issue #19)

The globe streamer's worker lanes got a teardown fence; the
"Nonexistent function / get_ticks_msec on null / Thread destroyed"
stderr spam is traced to unjoined derive threads at world death, not
a missing function.

- TRACE: HEAD control runs (fix stashed) reproduce the exact 6
  SCRIPT ERROR + 3 thread-warning spam on probe_stream_continent_a's
  natural exit; the spam lands AFTER "TickService: Stopped" -- the
  derive workers are still running when the engine starts finalizing
  (empty '' names = calls resuming into script state the finalizer
  frees around them).
- HYPOTHESIS KILLED: the issue's own suggestion (a) says statics are
  not "fully resolved" before the first async derive. Instrumentation
  says otherwise: 23 mesh jobs / 11 prop jobs entered AND completed
  inside the workers in one boot; the statics are politely resolved.
- THE STRAGGLER PARK: a class of re-derive kicks (face re-sweeps from
  the final frames) parks mid-compute in an engine-internal futex and
  only resumes under the finalizer; unbounded wait_to_finish() on it
  hangs the exit forever (three 900 s timeouts proved it). The park
  is engine-level (the issue's own suggestion (b)); not faked away.
- THE FENCE (globe_terrain_streamer.gd): `async_shutdown()`
  (main thread only) marks the streamer closed, joins every worker
  that finishes inside a 30 s window (wait_to_finish ONLY on threads
  whose job returned), DROPS a still-alive park past the window
  instead of wedging the boot, then clears the mesh+prop books under
  their own mutexes. The kickers refuse work after it (`_shutdown`).
- THE HOOK (globe_world.gd): `_exit_tree()` walks the fence before
  the node releases the workers' script state (guarded has_method so
  fence-less mock streamers stay silent). Scene swaps, probe exits
  and teardown all pass through it.
- MEASURED vs HEAD (HDR control stash cycle): drained boots
  (probe_planet_rebase_20km, probe_terrain_backend light-load,
  probe_meshcache_ram) 0 SCRIPT ERROR / 0 thread warnings with the
  fence; straggler boots (continent_a; terrain_backend under heavy
  host contention) 6+3 at HEAD -> 0-3 + 0-3 fenced, and the exit is
  ALWAYS natural -- no boot can hang on the fence.
- GATES: lint 36/0; full pipeline exit 0 (102 passed / 0 failed /
  0 SCRIPT ERROR).

## 2026-11-03 -- PR-22 MERGE ROUND (OpenHands quest/dialog/money loops)

Merged OpenHands' playthrough driver broadening (merge commit
bf70f22; the draft PR was merged via head-branch merge since it was
draft) and re-gated merged main in this worktree.

- The branch fixes #23/#25-#31/#33: quest rewards PAY (faction via
  FactionManager, chains enforce prerequisites, optional objectives
  stop gating, auto_complete pays on the spot), DialogService actions
  route the real seams (STOP_FOLLOW/UNLOCK_TITLE/TEACH_SKILL/
  GIVE_ITEM/GIVE_CURRENCY/SET_WAYPOINT), InventoryService gains the
  signed-delta modify_gold, VendorService buyback is typed +
  persisted, TradeService's unique guard runs, the corpse carries the
  bag, the target ring mesh has a surface, QuestUI renders readable
  objectives and keeps REWARDED quests, and the runtime
  nonexistent-method callers were routed to real ones.
- New lane receipts outside the runner DEFAULT_SET:
  test_dialogue_quest_reward 22/0, test_quest_availability 12/0,
  test_dialogue_ui_flow 7/0, test_trade_unique_guard 4/0; driver 77/0.
- MERGE-INTEGRITY GATES on merged main: lint 36/0; full pipeline
  exit 0 / 102 passed / 0 failed / 0 SCRIPT ERROR (ran to completion
  pre-merge at 1e00d88 and post-merge at bf70f22; two aborted runs
  were the cloud runner restarts, never code).
- Open lanes: #34, #35, and the S14.7 Sundered Sea long lane.

## 2026-11-04 -- PR-39 MERGE ROUND (driver social/nav stages 15-17 + fixes #36/#37/#38)

Merged OpenHands' driver hookups + dialogue/quest fixes branch
(pr-c-driver-social-waypoint) and re-gated in this worktree.

- Driver grew stages 15-17 in place: waypoint -> compass, friends
  request/accept/block, chat audience + ignore-book hiding. Driver
  now walks 113 stages-legs (was 78).
- Fixes: IcosahedralFaces._ensure_built() mutex-guarded double-check
  (#36 heap tear under concurrent worker lanes -- the concurrent-build
  half of #19; complements the 1e00d88 teardown fence),
  quest_main_awakening.tres TALK target now the npc_village_elder id
  (#37 the first quest was uncompletable), FriendsService
  accept_friend_request no longer emits the stray declined signal
  (#38); test_data_naming_lint now guards TALK objective targets.
- AGENTS.md conflict resolved on merge (their 2026-11-04 entries
  above this worktree's 2026-11-03 PR-22 entry).
- MERGE-INTEGRITY GATES on merged main: lint 36/0. Full pipeline
  SKIPPED by owner instruction this round (was green on the branch's
  CI at every commit: driver 113/0, pipeline 102/0/0 before merge;
  the icosahedral fix's own probes exit 0).
- Issues #36/#37/#38 closed by owner after the merge; OpenHands'
  superseded web-shell-mkdir PR #24 left open for their call.

## 2026-11-04 -- S14.7.1 SUNDERED SEA DEEP-SHELF DATA PASS (radial waterline + depth economy)

The Sundered Sea lane's first increment: the deep-shelf economy
lands as DATA + SERVICES, no fake visuals (prd-ocean-depths sec 8-10).

- OceanVolume grew the RADIAL WATERLINE model (`waterline_is_radial`):
  the plane waterline is only honest in small scenes; the 20 km world
  sea's waterline is a SPHERE. Pairing law: radial waterline rides
  radial rock; the receipt pins the pairing.
- OceanService now resolves the sea's truth once:
  `sea_surface_radius()` = shell (20000) + TerrainGen.sea_level
  (world seed), runtime-cached -- data volumes stay pure and can
  never disagree with the terrain that paints the water. Radial
  volumes claim [floor_radius, sea_r + 2 m wading reach] in
  volume_at; sample_depth reads the radial column (negative above
  the line, -1 inside the rock). The plane branch is untouched --
  probe_ocean's Haven Shelf and probe_swim's Builder's Pool laws
  did not move a meter.
- The current law's sea edition: Item gained the `current_immune`
  accessory field (to_dict/from_dict ride too); breather_for speaks
  it; tick_swimmer(..., current_immune) stamps ZERO. Datum: the sea
  cannot carry the pearl-diver.
- HarvestService grew DEPTH-BAND nodes: register_node(...,
  min_depth_m, max_depth_m) (0 = ungated). harvest samples the
  actor's body depth (PlayerManager local-body duck -> OceanService
  sample_depth) and refuses BY NAME before the depleted/rate gates:
  not_in_water (no body / dry / rock), too_shallow, too_deep.
  Fail closed: the deep garden cannot be taken blind from shore.
- Data: data/oceans/ocean_sundered_sea.tres (first radial-waterline
  world volume: floor_is_radial, center ZERO, floor_radius 19400,
  max_depth 60, pressure 0.1; current = backend_sundered RUN tangent
  at 0.5 m/s -- the ferry lane); res_kelp_fiber + res_abyss_pearl;
  acc_breather_abyss_pearl (x8 air, +20 m grace, current-immune,
  necklace, level 8); recipe_abyssal_breather (1 pearl + 8 kelp,
  hand station). Bands: reef kelp 30-45 m, trench pearls 50-58 m
  (squeeze line 50 lives under the kelp band's floor; the pearl
  lives past it, the breather buys the climb back).
- Receipt tests/test_sundered_deep_economy.gd added to the runner
  DEFAULT_SET (fleet packs regenerated: 9 packs / 2 unfiled
  family sets; packstruct lint --deep green). 36 checks / 0 fails,
  exit 0: seed sea truth == shell + Gen.sea_level exactly, claim
  windows (+2 wading, rock -1), RUN-lane current ==
  BS.RUN_DIR.normalized()*0.5 with the immune tick reading ZERO,
  bands 20/49/55/61 m, band refusals by name both nodes, honest
  purse grants (3 kelp / 2 pearls), no-body fail-closed leg, craft
  gate (8 kelp alone nothing; 1+8 crafts), breather equip + default
  law + un-equip reset.
- GATES: receipt exit 0 36/0; lint 36/0; full pipeline exit=0 /
  103 passed / 0 failed / 0 SCRIPT ERROR (DEFAULT_SET now 103,
  four continent shards included; one restart of the cloud runner
  happened AFTER completion, not mid-run).
- Deferred to S14.7.2+: node-in-world registration in the streamer
  (the _register_harvest_node pattern, seed-stable ids), reef/kelp/
  trench visual props, globe_player swim integration with the
  radial waterline, and the current loop as a ferry ride lane.

## 2026-11-04 -- ROSTER + CLIENT-DISPATCH ROUND (issues #34/#35) + PR-41 MERGE

Cleared the OpenHands backlog: merged PR #41 (GLIDE objective + credit
bridge, closes #40), closed draft PR #24 as already-satisfied, and
fixed the two phantom-call issues left open on the board.

- PR #41 landed as merge `94ecc77e` (pushed in `05e4c70d`): the
  AGENTS.md top-entry conflict was resolved against the S14.7.1 entry
  (glide round first, then the Sundered Sea pass). Re-gated here:
  test_quest_glide_bridge 10/0, data-naming lint 26/0, lint 36/0.
- PR #24 (web-ci mkdir) closed unmerged: `main`'s
  `.github/workflows/web-ci.yml` already carries
  `mkdir -p builds/web-shell` before the wasm export.
- Issue #34 (PlayerManager roster API): the four missing delegating
  helpers now exist -- get_player_info / get_all_players /
  get_online_player_ids / is_player_online -- backed by EntityService's
  live registration; rows carry entity_id/name/level/online/
  permission_level, and "online" means a live player node is
  registered. admin_commands._find_entity_by_id's fallback now
  resolves the row's entity_id back to the live node (the old
  `p as Node3D` could only ever return null once rows are dicts).
- Issue #35 (NetworkManager dispatch): chat routes through the real
  ChatService.send_message with the sender derived from
  get_character_for_peer (payload sender ignored, unmapped peers
  dropped by name); input/action call their handler only if one
  exists and otherwise warn once per type, as do unknown message
  types. The three phantom handle_client_* calls are gone.
- Receipt tests/test_roster_and_dispatch.gd added to the runner
  DEFAULT_SET (DEFAULT_SET now 104; fleet packs regenerated: 9 packs
  / 3 unfiled family sets, packstruct --deep green). 37 checks /
  0 fails: API presence, honest empty reads, a real registered body
  through every roster read, the admin row->node lookup, the whisper
  route (derived sender, forged sender never appears), unregistration
  clearing online state, and the warn-once book.
- Receipt lore: typed lambdas on typed signals can silently miss the
  emit (untyped callbacks work); SAY needs a living audience so a
  script-mode route leg uses WHISPER's explicit target.
- GATES: receipt 37/0 exit 0; lint 36/0; glide receipt 10/0;
  data-naming 26/0; packstruct --deep green. Full pipeline deferred
  by owner instruction this round.
- Sandbox note: `tests/lint/run_all.sh` defaults to
  /tmp/Godot_v4.7.2-stable_x86_64, which a workspace restore wipes --
  pass `GODOT=$(command -v godot)` or every lint file reports CRASH.

## 2026-11-04 -- S14.7.2 SUNDERED SEA DEEP GARDEN + SEA BODY

The deep shelf gets a world (nodes + props) and the world body learns
to swim it. Data alone is not a sea.

- THE DEEP GARDEN (globe_terrain_streamer): six authored chart beds
  (kelp shelf x 0.40/0.45/0.50, trench pearls x 0.58/0.64/0.70)
  resolve through StraitChart.dir_from_chart; the bed direction's own
  face owns it. _deep_beds_for_face() is the ONE law read by both the
  harvest registration and the prop build. A face may own several beds
  (the first draft's one-bed-per-face assumption was falsified by the
  receipt); ids stay per-bed stable: deep_kelp_<face>_<bed>_<k>.
- Registration rides _kick_prop_derivation beside the strait freight
  (main thread): three HarvestService nodes per bed, res_kelp_fiber /
  res_abyss_pearl, bands 30-45 / 50-58, depth jitter clamped inside
  the band, positions on OceanService.sea_surface_radius() (one sea
  truth; shell fallback), respawn 420 s / 900 s.
- The draw: kelp beds paint 14 strands (7-14 m tapered cylinders) + 4
  reef boulders; trench beds paint 6 pale spires + 2 drowned stones;
  patch-local via _tangent_patch_local, cached materials, shared prop
  mesh registry.
- THE SEA STEP (globe_player): _sea_swim_step() calls tick_swimmer
  once with breather grace + current_immune and obeys the band --
  DRY/WADING keep the ford law, SUBMERGED/SQUEEZE/CRUSH take the body:
  swim pace = walk x 0.62 steered at 4/s, the volume current added on
  top (the ferry lane), buoyancy to a 0.6 m float depth unless crouch
  dives / jump climbs, CRUSH ignores the wish and pushes up. _sea_carry
  books the applied horizontal. Leaving the water forgets the swimmer.
- Receipt tests/test_sundered_sea_swim.gd (runner DEFAULT_SET now 105;
  fleet packs regenerated, 9 packs / 4 unfiled sets, packstruct --deep
  green) 32 checks / 0 fails: bed ownership exactly once, per-kind
  draw counts, no draw on a non-bed face, three nodes per bed with the
  right id/band/sea-line depth, stable re-registration, and the body
  legs (dry false, 38 m true, band/depth reads, flow > 0.4 m/s along
  RUN, _sea_carry == volume flow, idle float, immunity zeroes, leaving
  clears the book).
- GATES: receipt 32/0 exit 0; lint 36/0; S14.7.1 receipt exit 0;
  probe_water_mounts 30 checks / 0 failures exit 0; continent-shard
  boot probe (probe_stream_continent_a) exit 0 with every PASS leg
  green; the 3 SCRIPT ERROR lines in that boot are the PRE-EXISTING
  classes (water-tri derive + the #19 teardown: "Nonexistent function
  '' in base 'Vector3'", get_ticks_msec on null) at untouched line
  ranges, same as documented in prior rounds.
- Deferred: node-in-world prop ENTITY binding (harvest nodes are
  service truth today; the garden mesh is the paint), breath/pressure
  damage conversion + HUD meters, the ferry as a scheduled ride
  (FerryService owns the timetable; the drift is the lane today), and
  water mounts riding the sea bands (SwimState.MOUNT_DISMOUNT_ON_
  SUBMERGE is not wired into the globe body yet).

## 2026-11-04 -- PR-43 MERGE + S14.7.3: THE BARQUE, THE BINDER, THE DAMAGE, THE BAR

Round plan from the previous round's deferral ledger: PR/issue triage,
then the four S14.7 lane deferrals (prop entity binding, breath/
pressure damage + HUD, the scheduled ferry ride, water mounts riding
the sea bands). All four landed; one stale probe leg fell with them.

- PR #43 MERGED (`24e1631b`, OpenHands, resolves #42): UIManager's
  three GameManager connects were guarded with has_method() on SIGNAL
  names -- always false -- so `_initialize_ui()` never ran and the
  TargetTooltip island never spawned for the whole project life (the
  dead-guard idiom fails CLOSED, zero noise). Guarded with has_signal()
  + is_connected de-dupe; runtime autoload resolution (script-mode
  safe); `TargetingManager.get_local_player_id()` added (the phantom
  call); `show_target_tooltip()` rewritten against get_current_target();
  `ui/targeting/target_tooltip.gd` dropped the dead local_id read. A
  static lint guard `_check_has_method_on_signal` flags the idiom
  repo-wide -> lint is 37 checks now. Receipt test_ui_manager_tooltip_
  wiring 11/0 (the trap pinned, real connect legs, tooltip spawn +
  rebuild-on-restart, the getter round-trip). Runner DEFAULT_SET 107.
- THE BARQUE: the data route veh_sundered_barque (6 casts/day, first
  5.5 h, 0.6 h crossing, pins waypoint_strait_moor <-> waypoint_strait_
  seaward) had no hull. ferry_vessel.gd gained build_vessel() -- one
  generic builder (piece-collider hull, place() law reader) -- and
  build_barque() whose lane is the two pins' own dirs from DataService
  gateway truth; the Pans runner now delegates. globe_world boots her
  with the runner's tick law and pays the deck wake at berths (the
  at_sea plan clears the roster only after the credit, the wake-glue
  shape). Receipt test_sundered_ferry_barque 16/0: route status, both
  pins resolve, one hull of four colliding pieces, the lane IS the
  two pins, mid-lane float ON the sea radials, berths at the pins.
  Deferred: harbor buoys for the two pins (the harbor_lights law
  may join later), a real-world deck ride leg through globe boot
  (the carry law is already receipted on the runner).
- THE BINDER: the grove's paint follows the truth. The register call
  stamps each (face, bed) grove with the deep_garden group + the
  harvest_ids of its three plants; world-side deep_garden_binder
  (entities/deep_garden_binder.gd) joins HarvestService's depletion
  book to the paint: ALL three depleted -> the cove hides its kelp/
  spires until a respawn reveals it; un-registered groves (bare
  hosts) keep paint, no invented depletion. Idempotent bind (meta
  guard) across re-init/re-derive. Legs live in the swim receipt.
- THE SEA'S BITE (globe_player): the swim step reads breath/
  pressure/burn/drowning from tick_swimmer, books `_sea_breath_s/max`,
  `_sea_pressure`, `_sea_drowning_s`, `_sea_burn_dps`, and pays:
  drowning 10 dps past empty breath + the pressure pool (pool = rate,
  mult 1) + any non-water burn -> a damage debt taken through
  take_damage in whole points; surfacing wipes the debt (the pool
  easing is the service's law, the surface heals nothing). THE MOUNT
  HANDOFF fed: water_stamp_for answers before the tick -- a swimmer
  mount's grace/crush/immunity enter the SAME tick call (one ocean
  law, mounted or not), a land mount past the waterline is dismissed
  by the service itself, no ride service -> the naked path unchanged.
- THE SEABAR (ui/components/sea_bar.gd + hud_layer install): the
  StormBar dialect; polls the local body's swim book at 0.15 s,
  hidden dry: band row (SURFACE SWIM at the top meter breath law),
  breath bar (fraction of breather capacity), DROWNING flash,
  pressure row. The damage stays the body's law; the bar only tells
  the truth. Receipt legs: wet shows SQUEEZE, breath fraction exact,
  drowning flash, dry hides.
- THE FORD PROBE'S DRY LEG FELL AND WAS RE-LAWED: probe_terrain_
  planet measured the "dry" walk at the spring's ANTIPODE -- on the
  Sundered backend that side can lie under the S14.7 radial world
  sea, so the S14.7.2 sea step takes a "dry" body standing on the
  seabed (the sea depth bands put it in CRUSH) and the dry speed leg
  collapsed (ratio 133.33; identical at HEAD control so it had been
  latent since the radial sea, un-caught while the full pipeline was
  waived). The dry site is now the hydro law's OWN guaranteed-dry
  ground (the spawn apron, water suppressed by law, flat 28 m):
  ratio 0.93, PASS by law. The full pipeline re-run against this
  round's tree is the round gate recorded below.
- GATES: swim receipt 52/0 exit 0; barque receipt 16/0 exit 0;
  wiring receipt 11/0 exit 0; lint 37/0 exit 0 (5 files, the new
  has_method-on-signal guard green); fleet packs regenerated 9 packs
  / 6 unfiled sets, packstruct --deep green; full default pipeline
  (fresh run against the finished tree): exit 0 with 107 passed /
  0 failed / probe_terrain_planet PASS on the re-lawed dry leg.


## 2026-11-04 -- PR-45 MERGE + S14.7.4: STRAIT BUOYS, PER-PLANT GARDEN PAINT, SEABAR _READY RECEIPT, BARQUE DOCK-WARP

- **PR-45 merge (closes #44):** OpenHands' death-progression fix landed as-is, branch
  `pr-round4-death-progress` merged locally `08b6e46f` (verified in-dock: receipt
  `test_death_progression_surface` 18/0 exit 0; death neighbors `test_notif_migration_death`,
  `test_kill_rewards`, `test_respawn` (+`_live`), `test_entity_autoload`, `test_combat_stack_live`
  6 passed exit 0; lint green). Landed-and-closed on GitHub (PR merged state reconciled, issue
  closed completed) -- receipt NOT wedged into DEFAULT_SET (OpenHands' no-shared-files edit
  stands alone).
- **The strait's pins got their buoys** (harbor_lights.gd `build_strait_buoys`):
  drum + ring + moor shaft + mast + amber lamp, base ON the sea line, one
  BEACON_FLANK_STEP off each pin, PropCollider welded on; the world builds the pair
  beside `build_barque` and flips both lamps in `_barque_ferry_tick`'s tick with the
  HARBOR_LIGHTS night law (dusk 18.0 -> dawn 6.0).
- **Per-plant garden paint:** the derive replays the register jitter seed-for-seed
  (same `+9091` law, same 3 randf per plant), tags each strand/spire `plant_k` by the
  nearest plant dir, mints hidden `Stump0..2` per plant (plant material, sea-line-
  rooted); `deep_garden_binder.refresh` now paints PER PLANT: taken plant -> strands
  down + stump up; furniture (reef/stones) always stands; the whole-cove hide is gone.
  Stale count legs re-lawed by NAME; stump leg reads 3 x ALL beds (a face owns kelp +
  trench beds on face 4).
- **SeaBar's own _ready:** new `test_sea_bar_hud_ready.gd` walks the live HUD seam
  (tscn -> `_ready()` install -> installed-bar wet truth -> the poll heartbeat through
  PlayerManager's local slot, bounded-wait law). DEFAULT_SET is 108.
- **Barque dock-warp:** `_execute_wake_warp` routes landing by vehicle -- the barque's
  branch reads HER lane metas and clamps the body at/above the water line (the vessel
  law's own max(walk, sea) + the moor-bank stand); receipt legs: refusal by name at 0
  rides, known at 3 deck wakes, warp emit vehicle+pin true, landing law vs a real
  stub (seabed walk clamps to the line; foreign pin = INF).
- **Receipts:** swim 60/0 (re-lawed H legs), barque green (25 legs incl. buoys +
  warp), SeaBar HUD PASS. Lint green. Packs regenerated (9 packs / 7 unfiled),
  packstruct --deep green.
- GATES: full default pipeline `sh scripts/godot_test_runner.sh` (108
  planned, 106 unique names): the sandbox restarted four times mid-run,
  so the gate was carried with a resume ledger over the runner's OWN
  per-test boots (the runner runs one boot per test; the wrapper reruns
  exactly the un-run names). EVERY unique DEFAULT_SET test is
  exit-0-PASS on the final tree: 52 PASS lines from the relaunch run, 4
  continent shards evidenced in-run (runner PASS + 1 passed/0 failed),
  50 re-verified by exit code after each restart kill (probe_crafting's
  die had landed once again and its re-lawed leg holds); no failures
  outstanding. NOT a single uninterrupted `(N passed, 0 failed)` tail
  line this round -- the restarts own that limitation, the ledger owns
  the coverage. probe_crafting's die-flake was found by the sweep and
  re-lawed (its synthetic leg actually failed once).

## 2026-11-04 -- Parallel sweep + PR round (no full run by owner instruction)
- PRs: #47 merged (`827fd6d3`) -- hud_services `_on_xp_shared` had swallowed ~180 lines of `_connect_services()`, wiring restored; receipt test_hud_services_wiring PASS exit 0 on the merged tree. #49 merged (`be5caa75`) -- health_component's phantom `has_method("get_party_id")` guard replaced by the PartyService seam; receipt test_party_death_notify PASS exit 0. Lint green (0 of 5) on the merged tree. Both PRs closed-as-merged with in-dock verification comments.
- NEW: scripts/godot_test_parallel.sh -- the runner's concurrent sister (same laws; warm import first; no shares but the cache; no blind retry; --resume ledger). MEASURED: 8 tests 21 s wall at -j 4 (45 s CPU), 27 tests 45 s wall (2m09 CPU, ~2.9x). web-ci Optional Full Test Suite now runs `--all -j 4` (still non-gating). Serial runner untouched and still the DEFAULT_SET source of truth (gen_fleet_packs parses the same block).
- Struct-family status check: dhaupin/crashtest already carries the agent-round issues (#79-82 auth/authz library rows, #82 docs/web catalog sync, #83 vant parallel-pack-driving speed ask) -- filed before the workspace died; nothing duplicated here.
- Gates this round: parallel runner verified on subsets (8/0 and 27/0, exit 0 both), bash -n clean, resumeledger skip/append/frame-path legs exercised; full pipeline NOT run (owner instruction).

## 2026-11-04b -- Branch law switch (staging local-gates)
- Owner instruction: full gates stay LOCAL ONLY (parallel runner carries the default-set gate; CI is never the gate). All agent rounds (Buffy + OpenHands) land on `staging`; staging pushes trigger NO CI (web-ci push path = main only). Promotion = periodic manual fast-forward staging->main + --no-ff merge + single main push (~2-min CI, pck commit-back rides it). Staging fast-forwarded to e9648e32 before the OpenHands staging agent got deep (it was 10 commits behind at 1860e6f1).


## 2026-11-04c -- Issue #19 residual: the fence's non-blocking frame drain
- The lane: the icosahedral round's leftover -- teardown spam (get_ticks_msec on null, empty-name calls, "Thread destroyed without its completion realized") fired because probe/world quits tore script state while derive workers were mid-flight; a blocking drain deadlocked the sandbox so the shipped fence bounded it instead. This round: globe_terrain_streamer's fence becomes three phases (see the AGENTS.md top entry for the law). Files touched: game/scenes/worlds/globe_terrain_streamer.gd (fence rework + REAP-ONLY guards in _apply_derived_mesh/_apply_derived_props) and game/scenes/worlds/globe_world.gd (fence docblock only).
- FIRST DRAFT FALSIFIED: a 1.5 s sync quick lap -- "the world's _exit_tree must not wait" -- scored 4 SCRIPT ERROR + 1x4 thread warnings on continent_a's exit: a quitting process produces no frames, so the short lap DROPPED mid-flight derives the shipped 30 s window would have joined. Lesson recorded: on quit the FULL bounded window is the fence; the frame drain is the scene-swap rescue for the after-window stragglers. The lap was restored to the shipped window and the 900 s-long boot budget honored (a 300 s hand timeout 124'd twice before the runner's own budget was used).
- MEASURED (same runner, -j1, same box): new fence continent_a exit = PASS, 3 SCRIPT ERROR + 1 thread warning; SAME-DAY HEAD control (fix stashed) PASS, 3 + 3 -- shipped band, one warning fewer. Lint 37/0 (after fixing my own comment's mixed-tab leg at streamer:3700 -- the lint caught its author). probe_planet_rebase_20km / probe_terrain_backend / test_terrain_determinism all PASS. Parse gates: --check-only "Parse Error" counts identical pre/post patch (22 streamer / 14 world; the documented autoload artifact).
- Process notes: /tmp ledger wrote zero until the runner EXIT (resume is end-of-run, not per-PASS); the parallel runner--resume skipped a re-run entirely (fresh ledger path needed for a new measurement). A `pkill -f` on the runner's own script name 143'd my own shell AGAIN (the anti-pattern holds: kill recorded PIDs only).
- Remaining on #19 after this round: the parked straggler class (engine-internal futex; resumes only under the finalizer) is UNJOINABLE by any main-thread law -- the shipped drop stands as the law's honest residue; every OTHER path (scene swap, drained boots, frames-present exits) reaps cleanly now.

## 2026-11-04d -- Dev-setup script + Docker audit (OpenHands PR #50, lands after the fence round)
- NEW `scripts/setup-dev.sh`: reproducible host bootstrap (system libs + Godot + Node + bun). Reads the apt package list + GODOT_VERSION/NODE_VERSION pins out of the Dockerfile (awk over the apt block) so host script and image can't drift. Flags: `--with-templates` / `--with-blender` / `--with-web-probe` / `--all` / `--skip-apt` / `--dry-run` / `--prefix DIR`. Installs into `~/.local` (no root for binaries), idempotent, x86_64+arm64. Verified: `bash -n` clean, `--dry-run` resolves 49 pkgs + Godot 4.7.2 + Node 20.20.2, full install tested in an isolated prefix (godot/node/bun land, re-run no-op), `apt-get -s` of the full list exits 0.
- DOCKER AUDIT -- three real defects fixed: (1) image could not build -- `debian:trixie-slim` renamed `libasound2`/`libgtk-3-0`/`libatk-bridge2.0-0` to `*t64` time64 variants, bare names no longer resolve (verified against live trixie index); (2) `srv/` was never COPY'd into the image though the entrypoint runs the bridges + NOAA sidecar from `/workspace/project/srv/` (compose mounts only ./game + ./labs) -> added `COPY srv/`; (3) test-mode Godot loop was a FALSE GREEN (globbed `game/tests/*.gd` from inside `game/` = no match, ran `res://<basename>` = nonexistent path) -> now `tests/*.gd` + `res://tests/<file>`.
- Docs: DEVCODE.md sec 1/6, README dev section, AGENTS.md round line. First PR opened against `staging` per the PR-base-staging law.

## 2026-11-04e -- Item-catalog authoring round (the world of items)
- The lane: outside OpenHands' docker/workspaces lanes, filling the data catalog: 19 new .tres (5 weapons, 6 armors, 1 consumable, 7 recipes) on the existing resource truth (iron ore/ingot, timber, stone, silver ore, mooncap/petal, kelp fiber) -- no phantom source, every input exists in the world today. Flavor written to the repo's voice (the kelp braids, the Concord signs, the forge remembers its slag).
- Receipt: game/tests/test_item_catalog.gd joins DEFAULT_SET -- data-integrity law for the whole item economy (identity/words/purse/stack/req/gear/price-ladder/service-truth/bills). First draft caught and re-lawed on truth: the glider output is a MOUNT-GRANT (recipe_weaver_kite -> glider_weaver_kite resolves through get_mount + RideService ownership per _grant's law); potion_soul_gem's missing item_level (defaults 1 under req 10) and ancient_coin's zero/zero purse got honest data fixes. All legs 7/0.
- Gates: item catalog 7/0, probe_crafting 14/0 (11 recipes), naming 26/0, lint 37/0, fleet packs 9/8 unfiled + packstruct --deep 0 errors, deep-economy receipt exit 0. DEFAULT_SET is 109.
- Deferred: buff_effects use-consumer (the small potion's instant_heal is just as un-wired as the new medium's), icons are aspirational paths (no on-disk pngs), vendor/loot rows for the new gear (npc_offerings next), and data/skills/ keeps its class-shape subdirectories (akkan_attacker/bender/healer/human_warrior -- not empty, just flat-less).

## 2026-11-04f -- Item use + vendor + icons round (the door, the shop, the mints)
- Lanes: outside OpenHands' docker lanes. Three deliverables in one round per owner instruction: (1) InventoryService.use_item -- the first real consumer of the buff_effects book; gates-before-pay laws, per-item cooldown book, StatusEffect riders for timed effects; (2) the village smithy opened as a by_item_id vendor for the iron ladder goods; (3) scripts/gen_icons.py minted every referenced icon (127+4) as real PNGs so the catalog receipt's new icon law can refuse phantom paths.
- Receipts: test_item_use.gd (36 legs: rails, validate-then-pay, cooldown book, real-Entity stat buff through its own timer, real HoT ticks + self-expiry, mana, data-truth on every authored book) + catalog grew vendor stock / offering-includes / icon-exists laws (10/0). Craft probe 13 checks green on 15 recipes; naming 26/0; lint 37/0; deep economy exit 0; packs 9/9 unfiled, packstruct --deep clean; DEFAULT_SET 110.
- Data repairs the laws earned mid-round: elixir/tea item_level keys (the soul-gem bug class again), ancient coin buy 60 under the fixer's shelf (melt law), staff recipe re-trade from raw ore to refined silver.
- Deferred: use_skill_id -> SkillService lane; VendorService price_override declared-but-unread (wire it or drop it); placeholder art.

## 2026-11-04g -- Deep metal ladder round (the sinkless ores, the gear tiers, the depths top)
- The audit: ore_golden/mythril/starmetal were mined + looted (elite ore table, bandit table) with ZERO recipe sinks -- three dead-end metals. Authored the binder-chained ladder: golden ingest -> mythril (gold carries the temper) -> starmetal (mythril carries it), then a 6-piece gear line L10/14/18 (estoc/scale coat, halberd/wardmail, skysplitter/bulwark) with nine honest bills across the forge + workbench, and the Fixer's Depths pull appended per its own documented law (skysplitter weight 9, bulwark weight 8).
- Gates: catalog 10/0 (24 recipes / 160 icons), craft probe 13 checks, naming 26/0, lint 37/0, gamble receipt ALL-OK, packstruct clean, no DEFAULT_SET change (110).
- Flavor notes: the Concord signs things it would prefer people did not nickname; the forge writes letters home about starmetal plate; mythril forgives the gold being there.

## 2026-11-04h -- Jewelry + loot-wiring round
- Four accessories (tidecaller ring, ledger signet, paleshard ward necklace, starbinder ring) + four bills across workbench/forge; the abyss pearl becomes a three-sink reagent (breather, paleshard, starbinder). loot_elite_ore gains the golden-tier freight (estoc .12 / scale coat .10 / signet .08) so L10 gear is earnable in-world; mythril/starmetal stay forge+depths by design.
- Gates: catalog 10/0 (28 recipes, 164 icons), craft probe 13 checks, naming 26/0, lint 37/0. No DEFAULT_SET change (110).

## 2026-11-04i -- Shard mesh Phase 0 (design note + identity + shared state)
- DESIGN NOTE `labs/prd-shard-mesh.md`: the Docker re-audit closed -- the image runs the dev env + a single server, NOT a mesh. Intent-vs-reality table (identity, shared state, cross-shard bus, orchestrator, transport, scaling), the ENet-UDP-vs-WebSocket edge-transport fork with a recommendation (WebSocket for the nginx-fronted edge, keep ENet for native), and a 4-phase path. The "4-5 dockers acting as one" vision is arch doc sec.11.3/11.4, still Phase 1 single-process today.
- PHASE 0 CODE (transport-agnostic). (1) SHARD IDENTITY: `ShardManager._ready` reads SHARD_ID/SHARD_NAME/IS_PRIMARY/WORLD_SIZE_KM2/MAX_PLAYERS_PER_SHARD -> `configure()`, then `_register_with_coordinator()` announces to CoordinatorService. No env -> shard_1/"Alpha"/primary, unchanged. EMPTY-AS-ABSENT: compose passes `SHARD_ID=${SHARD_ID:-}` which `OS.has_environment` reports PRESENT -- `_env_str` strips + empty-checks, else every default container configured as shard_id="".
- (2) THE SHARED-STATE BUG (found while auditing): `DictStore`/`CacheWrapper` resolve stores via a STATIC `_adapter_registry` hook NOTHING ever set (zero callers), so every DictStore (shard registry, coordinator registry, every "default" service ledger) fell through to a PROCESS-LOCAL memory fallback. Fixes: `BackendFactory.boot_defaults` points both static hooks at AdapterRegistry AND registers the "default" store name (never in STORE_MANIFEST -> `get_persistence("default")` returned null even with the hook set). With STORAGE_BACKEND=postgres the registries now reach the shared store.
- DEPLOY WIRING: Dockerfile + `python3-psycopg python3-redis` (bridges lazy-imported them but they were never installed). Compose synmergia service + STORAGE_BACKEND/CACHE_BACKEND/PG_BACKEND/REDIS_BACKEND/PG_BRIDGE_URL/REDIS_BRIDGE_URL + SHARD_ID/SHARD_NAME/IS_PRIMARY (defaults memory/sqlite/inmemory/empty = dev/CI unchanged). entrypoint.sh factors `_start_state_bridges()`, runs it in prod AND headless (headless = the shard role; it previously started no bridges).
- RECEIPT `tests/test_shard_mesh_identity.gd` (runner DEFAULT_SET) exit 0, twelve legs: env identity, default identity, coordinator registration + name, two shards both registered, "default" store registered, DictStore round-trip through the registered store. The default-identity legs CAUGHT the empty-string bug above.
- NOT DONE (Phase 1+, in the note): cross-shard bus transport, the edge transport decision, the N-shard compose topology. Gates this round: receipt 12/0, lint 37/0, compose config OK, entrypoint `bash -n` OK. Full runner NOT run (being reworked to parallel; owner instruction).

## 2026-11-04j -- Shard mesh Phase 0 verification (real postgres boot; the receipt was a false green)
- RE-VERIFIED the Phase 0 claim against a REAL `STORAGE_BACKEND=postgres` boot (fresh DB `synmergia_fresh` + pg-bridge sidecar) instead of trusting the memory-shim green.
- THE THIRD LEG OF THE SHARED-STATE BUG: `BackendFactory.boot_defaults` DOES set the `DictStore`/`CacheWrapper` static hook, but a `--script` receipt that `load()`s `dict_store.gd` can resolve a DIFFERENT script instance whose static is still null (the autoload's `preload` vs the caller's `load` desync). The receipt's DictStore then fell through to a process-local MEMORY fallback, so the "round-trips through the registered store" leg passed against memory -- the write never reached the `kv` table. FIX: `DictStore._resolve_registry()` / `CacheWrapper._resolve_registry()` fall back to the LIVE `AdapterRegistry` autoload in the tree (`Engine.get_main_loop() is SceneTree` -> `root.get_node_or_null("AdapterRegistry")`) when the static hook is unset. Fix is in the STORE, so every `--script` consumer stops silently going per-process, not just this receipt.
- ACCEPTANCE CRITERION MET (two separate processes): P1 write + P2 read both resolve `res://adapters/persistence/postgres_store.gd`; P2 reads back `{"n":7,"shard":"shard_2"}` from the real DB; the shard-mesh receipt's key lands in Postgres too.
- pg-bridge fixes from the prior round stand (autocommit + explicit BEGIN/COMMIT tx model, `rowcount > 0 else 0` DDL guard, `%`-escape on no-param SQL) and now carry a regression unit test `TestPgConvertSql` (incl. the `LIKE 'tick:%'` no-param case that used to raise).
- CLEANUP: scratch probes (`game/tests/_probe_restart.gd`, `_probe_a.gd`, `_probe_b.gd`) removed.
- Gates this round: shard-mesh receipt 12/0, adapter-http-transport 5/0, adapter suite 10 files rc=0 zero script errors, data-naming 26/0, lint 37/0, pg-bridge 18/0, redis-bridge 20/0, real-postgres boot 5 migrations applied. Full parallel runner NOT run (owner instruction; being reworked).

## 2026-11-05a -- Jeweler shelf round
- Marsh Piper (npc_jeweler_haven) opens Haven Bench of Pearls in zone_village_center: by_item_id shelf of the four jewelry pieces (row stock 5/3/2/1), the abyss breather, and raw abyss pearl; buy_categories [2,4] so the bench pays for pearls and takes back outgrown jewelry. Scene reuse (merchant_general.tscn), 5-node intro dialogue, roster row added.
- Also carried the PR #51 (shard mesh Phase 0) landing through staging: merged locally --no-ff as 936c2924 after the local verification batch (shard identity 12/0, adapter HTTP 5/0, naming/lint/catalog green, bridge suites OK), GitHub records the PR as merged.
- Gates: catalog 10/0, naming 26/0, lint suite exit 0.

## 2026-11-05b -- Jeweler world-seat fix + live web-client boot
- Manual client test through the repo web shell (fresh staging pack via --export-pack, hash re-stamped): login/guest -> lobby -> class pick -> globe boot works in-browser (HUD, weather, NPC rosters, Gull Island entry all logged).
- Caught: the Haven Jeweler never spawned on the globe -- globe_world.gd's VILLAGE_NPC_BATCH is the globe's seat law; the zone .tres roster row only places NPCs on planar zones. Added npc_jeweler_haven (bearing 110, reach 0.012), the plaza's open lane between smithy and academy.
- Gates: lint 37/0 (GODOT must point at the local binary; the suite's /tmp default is stale and 5/5 "CRASH: no RESULTS" is an environment failure, not a code failure).
- Deferred: walking to the jeweler and opening the shop inside the browser session (terrain derive saturates this VM mid-session); the boot + roster leg is verified.

## 2026-11-05c -- Shard mesh Phase 1 (cross-shard bus transport seam)
- THE BUS SEAM (`game/core/mesh/`), a swappable transport modeled on the payment-provider plugin law: `shard_bus.gd` (contract: subscribe/publish/poll + the mailbox protocol; per-(subscriber,topic) inbox lists; the NO-ECHO law -- a publisher never receives its own fan-out), `memory_shard_bus.gd` (process-local default; a shared static store so two in-process shards exchange events), `redis_shard_bus.gd` (cross-process over the redis-bridge sidecar), `shard_bus_registry.gd` (plugin board; re-register an id REPLACES it, make_default re-points; seeded with the memory bus).
- COORDINATOR WIRING: `CoordinatorService` binds the bus deferred past autoload order (it loads BEFORE ShardManager, so a sync bind would always read "shard_1"), publishes on every `emit_cross_shard_event`, and `get_pending_events` drains remote mail into the pending queue first -- remote events ride the same exactly-once path the tick's `_pull_cross_shard_events` already consumes. Transport selection is `SHARD_BUS_BACKEND` (default: follow `CACHE_BACKEND`); a failed redis connect falls back to the memory bus rather than failing the boot.
- DRIVE-BY FIX: `redis_store.gd::_blocking_get` typed `_retry_request(...).data` as `Dictionary`, raising "assign Nil to Dictionary" on the unreachable-bridge path Phase 1 makes real -- now Variant + `is Dictionary` guard.
- RECEIPT `tests/test_shard_bus.gd` (runner DEFAULT_SET) exit 0, seventeen legs: registry default bus, the swap law (re-register replaces + make_default re-points), memory round-trip + no-echo + drained-stays-drained, cross-instance coordinator delivery (a second CoordinatorService instance receives an event emitted on the first, which keeps its own copy), env fallback to memory on an unreachable redis bridge, and the redis bus failing honestly (non-zero open, unhealthy, empty poll).
- Docs: `labs/prd-shard-mesh.md` Phase 1 section + acceptance (sec.7) updated; `DEVCODE.md` documents `SHARD_BUS_BACKEND`.
- Gates this round: shard bus 17/0, shard-mesh identity 12/0, adapter HTTP 5/0, tick phase2 24/0, data-naming 26/0, lint suite 37/0 (7+3+5+13+9), adapter suite 10 files rc=0, redis-bridge 20/0. Full runner NOT run (owner instruction; being reworked).
- NOT DONE (Phase 2+): the edge transport (LB + sticky routing), the N-shard compose topology, coordinator extraction to its own process.

## 2026-11-05c -- Pearl industry quests (the dive + the tideline daily)
- Two QuestData .tres riding the LAWFUL seams only (no service changes): `quest_pearl_dive.tres` "A Pearl for the Piper" -- Marsh Piper sends the diver past the squeeze line: COLLECT "Abyss Pearl" x2 + TALK npc_jeweler_haven, min_level 8 (the breather gate), zone_restriction zone_village_center, rewards gold 250 / xp 400 / acc_ring_tidecaller chance 1.0; `quest_tideline_kelp.tres` "Tideline Gather" -- the bench's daily (quest_type=2, is_repeatable, cooldown 86400): COLLECT "Kelp Fiber" x6, previous_quest_id = pearl dive (chain law), rewards gold 80 / xp 120 / tea_mooncap_steep x2. The dive's next_quest_id points at the daily so the journal chain reads both ways.
- Receipt legs EXTENDED IN PLACE (test_quest_availability.gd, no fleet-pack regen, DEFAULT_SET unchanged): at level 12 with an empty book the dive lists while the kelp daily stays chain-locked; after the dive reads REWARDED the chain gate opens and the daily joins the roster. Both legs green (15 OK / 0 FAIL).
- ICON LAW earned its keep: both quest .tres carry res://icons/quests/{pearl_dive,tideline}.png; gen_icons.py minted exactly those 2 (142 referenced, mints 2, residue 0).
- Gates: availability receipt exit 0, catalog 10/0 (icon law scans data/**/*.tres), naming 26/0, lint 37/0 EXIT 0.
- NEXT DUE (persisted per the deliberate protocol): (1) second shore NPC pairing, the deferred fence/bridge vendor (data+npc shelf, same laws as the jeweler round + globe seat in VILLAGE_NPC_BATCH); (2) star-tier accessory talent lines; (3) after OpenHands' Phase 2 lands, a cross-shard-friendly event quest note in labs/prd-shard-mesh.md's Phase 2 section. Staging-branch law respected: OpenHands owns core/mesh Phase 2; this round is data-only.

## 2026-11-05d -- Shore plankwright round (Fenwick's Fence & Plank)
- The deferred fence/bridge vendor pairing landed as DATA + SEAT: `npc_tidewright_fenwick.tres` (Old Fenwick the Haven Tidewright, merchant npc_type 6, zone_village_center, merchant_general scene reused per the scene law) + `vendor_fenwick_planks.tres` (by_item_id: res_timber x16, item_scrap_lumber x10, wep_longbow x1 -- the Shorebow he strings once a season; buy_categories [3,4] = provisions + resources, so the yard pays for the shore's raw haul; honest row stock 5/10/1, daily restock) + `tidewright_fenwick_intro.tres` (5-node voice: the tar bucket, six barque-deck rebuilds, the two moor banks, warped-billet refusal, the kelp wrap draw advice; two shop-open actions ride action_type 6 like the jeweler's tree).
- SEATS: zone_village_center roster row appended (5 npcs) + globe seat `["npc_tidewright_fenwick", 135.0, 0.012]` in VILLAGE_NPC_BATCH -- the open arc between the jeweler's 110 and the academy's 160. Lore ties the round to the strait: the same wright rebuilt the barque's deck, so the fence-buying economy and the ferry line share a face.
- CONFIRMED IN PASSING (user question): the pearl chain's sources are REAL in-world -- trench pearl beds at 50-58 m and reef kelp beds at 30-45 m are live HarvestService nodes on the strait chart (six authored beds, respawn 900 s / 420 s), the depth bands refuse too_shallow/too_deep by name, and the jeweler's shelf also buys raw pearls -- so quest_pearl_dive and quest_tideline_kelp both genuinely complete in-world.
- Gates: catalog 10/0 (offering include law + vendor stock law on the new shelf, 19 npcs clean), naming 26/0, lint 37/0 (covers the globe seat edit). No new icons (the shelf re-rides minted icon paths).
- NEXT DUE (persisted per the deliberate protocol): (1) star-tier accessory talent lines; (2) a tide-side repair service for the tidewright (smithy keeps the village's repair law meanwhile); (3) after OpenHands' Phase 2 lands, a cross-shard-friendly event quest note in labs/prd-shard-mesh.md's Phase 2 section.

## 2026-11-05e -- Shard mesh Phase 2 (edge transport: WebSocket + nginx sticky)
- DECISION (the note's fork): Option B for the edge -- a WebSocket server fronted by nginx (L7), browser-capable, standard LB. Option A (ENet/UDP + L4) retained for native clients that want raw UDP; not the default.
- ENGINE: `NetworkManager` reads `EDGE_TRANSPORT` at `_ready` (`enet` default; `websocket`, aliases `ws`/`wss`, case-insensitive; empty/unknown -> enet with a warn). `_resolve_edge_transport()` owns the law; `_make_server_peer(port)` builds `ENetMultiplayerPeer.create_server` or `WebSocketMultiplayerPeer.create_server`; `start_server` / `connect_to_server` ride it (a websocket mesh routes native clients through the client path browsers already used). `get_connection_info()` reports `edge_transport`.
- NGINX/EDGE: `upstream godot` now carries `ip_hash` (sticky routing -- a WS upgrade and the client's follow-up requests hit the same shard) and `GODOT_UPSTREAM` is a comma/space list the entrypoint expands into one `server` line per shard (single host == the previous config). compose exposes `EDGE_TRANSPORT`.
- RECEIPT `tests/test_edge_transport.gd` (runner DEFAULT_SET) exit 0, fourteen legs: env resolution (default/websocket/ws/wss/case/empty/unknown), `_make_server_peer` builds the right peer type, the websocket server peer BINDS (reaches CONNECTION_CONNECTED), connection-info reports the transport. Receipt-lore: a same-process WS client+server loopback does NOT complete in headless Godot (known artifact; irrelevant in prod -- separate processes) -- the receipt proves the SERVER bind.
- VERIFIED SEPARATELY: the entrypoint's upstream expansion against a copy of nginx.conf (single host -> one `server` line; a 3-host comma/space list -> three lines, all under `ip_hash`); `bash -n` on the entrypoint OK.
- Docs: `labs/prd-shard-mesh.md` Phase 2 section + acceptance (sec.8) updated, the Phase 2 out-of-scope line removed; `DEVCODE.md` documents `EDGE_TRANSPORT`.
- DEPLOY.md refreshed for the mesh: §6 env table gained `EDGE_TRANSPORT` + a Shard Mesh Variables table, §8 gained an Upstream & Sticky Routing note (+ `hooks` rate zone), and §12's "Horizontal Scaling (Future)" became the Shard Mesh section (shipped-vs-planned table, per-shard compose, `ip_hash` LB, the why-WebSocket rationale).
- Gates this round: edge 14/0, shard bus 17/0, shard-mesh identity 12/0, adapter HTTP 5/0, data-naming 26/0, lint suite 37/0. Full runner NOT run (owner instruction; being reworked).
- NOT DONE (Phase 3+): the coordinator + N-shard compose topology, coordinator extraction to its own process, real HA Postgres/Redis.

## 2026-11-05e -- the ceiling lifting round (level cap 60 + the ratio law + the trench boss)
- Level 30 WAS A MISTAKE, NOT CONTENT LIMITATION. The engine never capped levels; the world's own install has led A LOT of authors and players to end at 30. From now on the cap is characteristic of an old content ceiling that was swept forever, and the curve now lives as a law in core.
- THE RATIO SYSTEM (LevelCurve, the one-authority law file) – game/core/progression/level_curve.gd:
  - DEFAULT_CAP = 60 (the current cap; 100+ seasonal packs later bump this ONE constant) + the LEVEL_CAP env deploys override (junk and absurd values fall back to 60, never a boot failure).
  - levels 1..10 keep the SHIPPED 1.5^n law byte-equal (quest reward authoring assumed that line and it must stay still for them).
  - levels 10..CAP compound a BREATHING ratio: cost(l) = cost(10) * 1.03^(l-10), so the old geometric explosion into the tens-of-millions that made 30 unreachable is gone. The 1..60 curve total is 4,579,680 XP, with the income defined by the packs that ship each seasonal content round.
  - PlayerManager moved to the one-authority discipline (level_up stops at LevelCurve.max_level(), the next level's cost is LevelCurve.level_cost(level+1) instead of a compounding x1.5 drift, and overflow XP past the cap BANKS rather than vanishing).
- THE DATA-LEVEL DRIFT RAIL (test_level_curve.gd, joins DEFAULT_SET, 15 legs): verified the shipped band byte-equal, the breathing band anchored and monotonic, the env-override law, and – the most important leg of the round: zones/quests/gateways carry no re-baked content ceiling ( zones sweep to max 999 / pick quest 100 / gateway 100 is the ride-forever sentinel set now). A future author cannot bake a level-30-style mistake again; that requires sweeping data at every future cap raise.
- THE BAND SWEEP (the 9 files): zone_forest_meadow 15->999, zone_starter_plains 20->999, zone_deep_root_camp 30->999, zone_dungeon_forest_depths 30->999 (old content never locks again); quest_herb_gathering 20->100, quest_cross_the_cistern 30->100, quest_listen_to_the_deep 30->100, quest_shoal_freight 30->100 (content-band quests ride the cap, never gate it); gateway dungeon_forest_depths_entrance 50->100. The FIVE tutorial gates stay standing verbatim (main* 5, arena 8, wolves 10, wings 12) -- the walk order is content, not a cap.
- THE TRENCH SENTINEL (the user's ''I like your next suggestions'' round, the first real world-boss on the deep): enemy_trench_sentinel (band-45 WORLD_BOSS, kelp-wrapped bone grown around an abyss pearl, loots trench dream + the elite ore), loot_trench_dream (sigil 0.10 / starmetal .30 / mythril .35 / abyss pearls 2-4 @ .60), world_boss_trench_sentinel (zone_sundered_sea, every 4h after a 10-min boot delay, 1h unclaimed despawn window), and THE CLOSE-OF-LOOP drop acc_necklace_pearl_sigil (lvl 40, +10m squeeze grace / current-immune, wis 7 vit 4) so the trench boss writes the NEXT LEVEL of the squeeze line instead of a bigger number. Fenwick's buy_categories [3,4] already carry the raw haul and the Abyss Pearls -- the sentinel round rides that as is.
- GATES: curve receipt 15/0, catalog 10/0 (sigil minted by gen_icons: 143 referenced / 1 mints / 0 residue; the icon law correctly refused the missing-path pre-mint), naming 26/0, canon bosses ALL PASS, world-boss schedule receipt 37/0 (a pre-existing process artifact on this suite emits 13 SCRIPT ERROR nonexit and passes vs-tree as before-round -- differential-verified by removing my schedule and expecting the same error count), lint 37/0.
- NEXT DUE: this round pays the REAL first band-40/50/60 content (the pack that ships next is the income calibration -- quests/enemies in the breathing band), the Fenwick tide-side repair service, and the star-tier accessory talent lines; the seasonal pack rhythm is now literally data-authored (new zone tres + quest band + enemies pays the curve -- zero curve touches).

## 2026-11-05f -- the first income round (the band-40/50/60 seasonal pack pays the curve)
- THE INCOME GAP THE CAP RAISE REVEALED: regular enemies stopped at 5 (wolf/slime/bandit), the elite troll sat at 35, and then ONLY bosses existed (herald 45, sentinel 45, saint 55, void lord 60). Nothing in-band to grind, and the only quest income past the dive was 400 XP/quest against a 2.6M XP 35-to-60 leg. THE PACK: the first seasonal content pack is the curve's first real payment (data-only, riding the horde/admin + quest rails; the curve itself untouched).
- THE CALIBRATION LAW this round lands as precedent: BAND REGULARS PAY ~3% OF THE NEXT LEVEL'S COST AT PARITY (3,000 XP against cost(41) ~93.4k; 4,000 XP against cost(51) ~125.6k), so a level in the breathing band costs 25-35 regular kills -- MMO-normal grind arithmetic that the curve owns and the packs author.
- TWO BAND REGULARS (data/enemies), spawn rails as authored (horde/admin templates resolve through DataService.get_enemy): `enemy_tidecursed_diver.tres` (band-40 regular, the sea keeps what the squeeze line kept -- kelp-net drag, humanoid set, 2.6k hp; primary loot the new salvage table + elite ore secondary, 300/500 gold) and `enemy_gloamwood_stalker.tres` (band-50 ELITE, the Gloomwood digger, wolf set, see_stealth true, 3.4k hp; elite ore secondary -- mythril and star swallow -- 350/600 gold).
- THE SALVAGE TABLE (data/loot_tables/loot_sunken_salvage): the diver's drag pays the dive economy back from the grind side -- kelp fiber 2-5 @ .45, abyss pearl 1-2 @ .35, health medium @ .25 (no new items, zero icons for the loot).
- FOUR PAYING QUESTS (data/quests), target law verified (KILL display_name / COLLECT display_name):
  - `quest_tide_salvage` "The Tide's Tithe" (Fenwick, min 38, chain open): KILL Tidecursed Diver x5 + COLLECT Kelp Fiber x10, 2000g/5000xp + 3 health medium; next_quest_id -> sentinel wake.
  - `quest_sentinel_wake` "The Sentinel's Toll" (Fenwick, min 42, chain from the tithe): KILL "The Trench Sentinel" x1 (world boss start riding its own 4h cadence -- the schedule keeps its despawn window; the quest rides the boss, does not own it), 3000g/10000xp + 2 res_ore_starmetal.
  - `quest_deep_toll` "The Market Toll" (Marsh Piper's Jeweler, min 35, is_repeatable cooldown 86400 -- the deep DAILY): COLLECT Abyss Pearl x3, 2800g/3500xp + 3 tea_mooncap_steep munchies (the dive ration law).
  - `quest_gloamwood_ledger` "The Gloamwood Ledger" (Fenwick, min 48, chain close): KILL Gloamwood Stalker x6, 4500g/12000xp + 3 res_ore_mythril -- Fenwick's salvage arithmetic balances the Gloomwood line.
- GIVER SEATS: Fenwick's includes gained the quest row (tithe -> wake -> ledger chain, one fill), the jeweler's gained the market toll. Chain note: pearl_dive -> tideline_kelp is untouched; deep_toll is the jeweler's second, unchained offer.
- GATES: naming 26/0 (target law + include law verified the four quests and both seats), catalog 10/0 (all loot/quest item ids resolve service truth), availability 15/0 (chains honest), level-curve 15/0 steady, lint 37/0. Icons: gen_icons 147 referenced / 4 mints / 0 residue (tide_salvage, sentinel_wake, deep_toll, gloamwood_ledger).
- NEXT DUE: a band-57 regular to fill the 55-to-60 gap between the saint and the void lord; the Fenwick tide-side repair service; the star-tier accessory talent lines; and the FIRST BREATHING-BAND world-fiction pass (the tithe's six barque decks deserve a zone).

## 2026-11-05g -- the soulbinder round (premium resurrection, self + the party lifeline)
- THE MECHANIC: SOULBOUND RESURRECTION -- paid stand-up for the dead. Two doors, both server-authoritative, both keyed by ONE prepaid permit: the Soulbinder's Ticket (data/items/item_soulbind_ticket.tres; stack 10, soulbound, zero/zero purse -- never vendored, the sink ledger gate is its only door, the bag's use-door declines it as an honest inert permit).
- SINK RAIL (core/services/sigil_sink_service.gd): SinkKind gained RESPAWN; two honest rows (soulbind_ticket 25 sigils x1 / soulbind_eight 150 sigils x8 -- priced inside the sigil_100 $4.99 pack arithmetic). The no-fake-sinks law held: the GRANT LEG SHIPPED WITH THE ROW -- the bag stamp (InventoryComponent.add_item, per-slot duplicates, all-or-nothing), and RESPAWN rows are stackable permits so the ALREADY-OWNED law does not gate them (a raider buys charges, not a duplicate prize). get_catalog stamps kind_name 'respawn'. The catalog receipt grew its legs (9 rows, respawn truth, repeat-permit buys, and a THIRD refund leg: a full bag rewinds the debit and stamps nothing).
- THE STAND-UP (core/services/respawn_service.gd, the SELF_REVIVE seat finally has its cycle): availability rides the bag's stack truth (soulbind_count; an unseated/inventory-less body counts zero, never invented); the UI choice 'soulbind' maps through _mode_for_choice; initiate_respawn's SELF_REVIVE arm is DEBIT BEFORE GRANT (the ticket leaves the bag before the cycle schedules; a refused consume refuses the respawn by name) and stands a 3 s SOULBIND_RESPAWN_DELAY cycle at the death spot -- EXCEPT the sea/rock law: _spot_refuses_a_stand_up (injectable _depth_resolver seam; runtime rides OceanService.sample_depth) sends underwater or inside-the-rock falls to the zone spawn ("a safe place near"), so a drowned diver never drowns twice and a crevice death never stands into stone. The real door's own verdict (unclaimed columns refused as rock, honest-conservative) is receipts' reality, not a bug.
- THE LIFELINE (targets other people): start_revival's clergy gate now has a paid bypass -- a non-clergy ticket holder pays a lifeline, consumed AT THE BOOK (after range, target-state, and abuse gates all held; a wasted-ranged attempt spends nothing), audited lines SOULBIND LIFELINE in the log. No karma change: kindness still pays.
- THE ROW: the death screen (respawn_ui_manager + respawn_ui) offers 'Soulbind at the Fall (Ticket xN)' with the rider's own held count; a11y names the price ('one Soulbinder's Ticket is spent'); the server re-validates + consumes at initiate, so a stale UI signal stays free.
- REAL $ ENTRY: the processor SKUs (sigil_100/280/650 through the webhook) already bring Concord Sigils into wallets; the ticket sink rides them -- no new payment code, the monetize rail is exactly the existing audited books.
- GATES: soulbind receipt 30/0 (NEW test_soulbind_revival.gd, joins DEFAULT_SET; book-duck legs, mode mapping, availability priced vs free rails, sea/rock/dry siting, consume-before-schedule, the lifeline law, the UI rows), sink catalog receipt ALL-OK (extended: 9 rows, stackable-permit law, the full-bag refund leg), premium loop receipt ALL-OK, respawn receipts green, lint 37/0. gen_icons 148 referenced / 1 mints / 0 residue (the ticket icon). DEFAULT_SET: 116.
- NEXT DUE: the enemy ladder (every 5 levels to 60, biome-matched); band-57 regular for the 55-60 gap; the Fenwick tide-side repair service; the star-tier accessory talent lines; a first breathing-band zone.

## 2026-11-05h -- the first-run ladder round (every 5 levels a few types, biome-matched, 5 to 60)
- THE WORLD'S FIRST HONEST LAVA OF MOBS: the Regulars to now stopped at 5, elite 35, and then bosses only -- the ladder now tops for the FIRST RUN of seeded zones, a few types per 5-level band, matched to the biome they seed (data + rails, the same shape every prior pack rode; in-world seat wiring is its own next rung). 14 new enemy templates + 5 biome loot tables.
- THE LADDER LAW (calibration honest vs curve + shipped slopes): band regulars pay ~0.8% of next-level cost at parity through band 30 (55/320/370/425/490/570 -- the shipped wolf/bandit slope), then the band-40+-seasonal 3% law (3000/3250/4600/4800/5500). Gold scales with band; elites carry better min-max; difficulty_modifier walks 1.2 -> 2.5.
- THE ROSTER (per biome): Meadowhaven (starter plains, L5): `field_hopper` (passive feeder, is_aggressive law half) + `tusker_sow` (your first real read of a tusker grudge). Gloomwood forest (L10/15): `thistle_boar` (living thistle hedgerow) + `gloam_whisp_moth` (aggro 14 flying pollinator -- highest agi at its band). Sun Pans (L20/25): `salt_wretch` (first humanoid at its band) + `mirage_hound` (see_stealth). Gull Island (L25/30): `coast_pecker` + `gull_nestmaw` (ELITE; its secondary elite ore, a band-30 first pay). Root Camp (L30): `rootmaw_brute` (ELITE troll-kin; elite ore primary, skill books secondary). Depths (L40/45/57): `gloam_polyp` (L40, fungal hearth, slime set), `depths_thornhide` (L45), `ledgewarden_construct` (ELITE fill of the 55-60 gap -- the band-57 regular the note called for). sea (L55/60): `drowned_custodian` (L55, humanoid, implements the tide's bookkeeping) + `tidebound_ancient` (ELITE L60 -- the highest honest paid hand; ~5500 XP reads against void lord's boss 20k at the schedule top).
- THE TABLES (loot honest per biome): `loot_meadow_litter` (bites / mooncap / timber / petal @ L5), `loot_gloam_litter` (iron / mooncap / health small / the first silver @ L10), `loot_pan_dust` (iron/silver/mana small/ironblood @ L20), `loot_coast_bounty` (wreck kelp / medium / abyss pearl @ .08 / ancient coin @ .06 @ L25), `loot_gloam_spores` (medium / mooncap x2-3 / steep / mythril 1-2 @ .12 / soul gem @ .04 @ L40). All secondaries the deep grades ride `loot_elite_ore` where the band rounded to it.
- DRIFT RAIL CONFIRMED: level curve 15/0, canon bosses ALL PASS, boss schedule 37/0 (the ladder touches nothing about schedules), naming lint 26/0 (target laws + prefix + honest words), catalog 10/0 (all loot item ids resolve; the fixer line: item_soulbind_ticket caught as zero-purse-not-quest -- it IS quest-classed now (is_quest_item = true, the same carve-out a quest-only never-vendored item rides), no rail moved).
- NEXT DUE: currency of these in-world mobs (zone spawn tables, the world's own placement rung), where the world reads completion; the Fenwick tide-side repair service; the star-tier accessory talent lines; the first breathing-band zone (the Tithe's six barque decks).

## 2026-11-05i -- the funding pitstop round (labs/prd-monetization.md)
- THE COMPLETE MODEL NOW EXISTS ON PAPER: labs/prd-monetization.md lands as the standing doc for "what monetization exists, what servers cost, and what the gap requires" -- the investor-approach answer is now a document, not a whiteboard sketch. Positioned as companion to labs/prd-shard-mesh.md (rails-first precedent).
- INVENTORIED (SHIPPED, verified against the code not memory): three real-$ processor SKUs (sigil_100 $4.99 / sigil_280 $12.99 / sigil_600 650-for-$24.99) riding the webhook payment provider seam; the 9-row audited sink catalog (RESPAWN soulbind ticket x1 @25 / x8 @150, mount ladder 150/250/400/650/900, titles 200/500); the black-market roll board (3/12-sigil tiers over real loot tables); the in-world earn path (Trench Sentinel ~10% sigil drop -- premium currency is both purchasable and earnable on purpose). The #1 ticket prices at ~$1.25 gross / ~$1.00 net against the floor pack.
- SERVER-COST LADDER (2026 publisher-page anchors, honest caveats): Tier 0 pilot 50-150 CCU ~ EURO 25-35/mo; Tier 1 early launch 500-2,000 CCU ~ EURO 210-290; Tier 2 at scale 10k CCU ~ $2.8-4.2k managed route (leaner auction-fleet route EURO 1,600-1,900), i.e. ~$0.35 per peak-CCU-month, ~$0.04 per DAU-month. BREAK-EVEN HEADLINE: ~2,000 monthly payers cover the entire at-scale infra budget. Honest gaps NOT funded: labor, art (placeholders stand), moderation, including the per-shard CCU benchmark (the whole ladder assumes 100 CCU/shard and the headless derive load is UNMEASURED -- first dedicated box gets benchmarked, not budgeted, before Tier-1 spend).
- RISKS RECORDED: (1) PvP x soulbind tickets is the catalog's largest DESIGN risk (instant stand-up is pure convenience in PvE, a meta purchase in contested bodies -- sink rows already support context pricing; decide in the PvP rules round); (2) sigil earn-rate drift needs a locked target (earned income <= 25% of expected sink demand proposed); (3) real-$ provider adapters (Stripe/Paddle VAT) are the ONLY missing leg of the audited loop -- everything downstream is data; (4) ticket price A/B on the death-screen row rides the sink-row shape (config, not code).
- FUTURES ROADMAP (priority order): provider adapters -> season pass (the seasonal-pack cadence IS the publishing rhythm, ~$8-10/season) -> cosmetic breadth (sink rows are data) -> bank/stall convenience tiers -> character slots -> subscription as an OPEN question with numbers, not vibes.
- Round is DOC-ONLY: zero .tres, zero service changes, the pack export stands UNTOUCHED (game.pck hash 9a7aaebf... is still honest).

## 2026-11-05j -- the pass design round (Season Charter + the Mythos Toll, in labs/prd-monetization.md)
- THE PASS HAS DESIGN: §9 THE SEASON CHARTER -- one purchase per season, never a subscription; a two-track book of SEASON DEEDS fed by the packs' own content. Premium track = cosmetics only (title/dye/pet/mount SKIN that skins an owned ride) + non-combat convenience (season bank tab, early entry) + a pursuing deed faucet (a holder still plays the season; the pass is a key, not a dump). HARD LAWS: no combat stats, no XP/cap-pace boosts, no debuff on anyone, no content the free game will not eventually get -- premium is earlier+prettier, never only.
- THE F2P DOOR: (1) the free track (dye kit, season trophy, convenience tab) is deeds-only for everyone; (2) the Charter ITSELF is purchasable $8.99 OR 300 EARNED-ONLY sigils, payable ONLY from the deed pool -- bought sigils cannot buy the pass. Honest sizing note: today's earned faucet is boss-table drops only; the pass build round adds deed-ledger grants to dailies/chains/hauls (data on existing rails, 2-4 weeks of active play to earn).
- THE TOLL (§10): Mythos exclusives ship with an authored, item-card-visible TRADEOFF drawn from the coverable-hook set (move speed / all-resist / regen / haste -- NEVER damage, health, defense), e.g. -10% res/-10% speed -- ownership demands a skilled party or a build covering the hooks. THE PROVENANCE LAW: the wallet stamps sigil provenance at grant (coin sigils = webhook-bought; deed sigils = earned in-world; same purse, same values); Mythos purchases debit DEED sigils first and grade by the deed fraction -- Proven 100% (NO toll), Tempered >=75% (halved), Bought <75% (full). The F2P grinder's mythic exclusive is strictly BETTER than the buyer's; money buys the clock, never the ceiling, and buyers who also play temper their way to Proven.
- ANTI-SMELL LAWS RECORDED (investor tenets): every exclusive has a non-money path to a BETTER version; tolls tax only their owner (no aura debuffs); hooks are coverable by play (team reliance, not wallet reliance); Charter and Mythos are different products; XP/caps never purchasable. Investor paragraph updated (the F2P trust floor is a feature of the model, not damage control).
- IMPLEMENTATION SEAT (later round, receipts gain legs): provenance = earned sub-ledger (two currency ids under one unified purse, debits strike earned first); Mythos = sink rows with authored toll fields; grades stamp at grant; the sink-catalog receipt gains the provenance-fraction -> grade -> toll legs. OPEN QUESTIONS: if PvP/trading ever opens, deed sigils must BIND-ON-EARN (provenance never rentable via RMT); 75/100 thresholds are a tuning dial; cosmetic provenance finish is an open aesthetic call.
- Round is DOC-ONLY: zero .tres, zero service changes, the pack export stands (game.pck hash still 9a7aaebf...).

## 2026-11-05k -- spitball #1: the dye economy (prd-monetization.md sec 11)
- AGREED THE FIRST SPITBALL: DYES, borrowed "you can dye mostly anything" -- and landed as PRD sec 11 with a spitball bench table at the end of the section so the spitball workflow (owner starts, Buffy adds after yay/nay) has a permanent home (one row per agreed idea).
- THE DESIGN (pure-visual, zero stat hooks -- the safest premium category): (1) THE CARRIER LAW -- one dye slot, many carriers: weapons, armors, wearables, accessories, mount tack, gliders, housing furniture; a dye applies a LOOK, never a number. (2) THE TWO-LANE COLOR LAW -- FREE LANE FIRST: field dyes are CRAFTABLE from harvests (moonpetal reds, kelp greens, pan-salt whites, ironblacks, pearl shimmer) and honest-coverage the mundane palette; dyes become a real vendor-shelf trade good and a crafter can run a dye INDUSTRY. PREMIUM = SPECTACLE + BREADTH, never exclusivity of a field-reachable look: Concord dyes (iridescence, animated gradients, seasonal glitters) and camo/fielding patterns for weps/armors/wearables. (3) THE COLORIST'S LICENSE: the full-spectrum custom chooser priced as a REUSABLE PERMIT (the Soulbinder ticket shape), not per-item nickels-and-dimes; seasonal pattern packs restock like vendor shelves.
- LAWS (sec 10's anti-smell tenets restated for color): a dye is a look, never a stat, ever; field dyes reach every carrier type premium dyes can (limited color CHOICE, never limited ACCESS); PREVIEW NEVER DEBITS (try-on on YOUR item before purchase; failed application refunds per the sink refund law); dyes ride the Charter but never require it (free track ships a field-dye kit, premium suite a seasonal wild dye); provenance/the Toll stay orthogonal.
- IMPLEMENTATION SEAT (build round): dye slot on the appearance record (mounts/furniture need carriers beyond the item schema); dye .tres in the consumable family + the license permit; the item-catalog receipt gains dye legs (look-id resolution, preview-is-free, refund); icons ride the palette law. OPEN QUESTION: dyed look stamped on the item vs a wardrobe OVERLAY layer (overlay is the stronger product, touches persistence -- decide with data).
- Round is DOC-ONLY: zero .tres, zero service changes, the pack export stands.

## 2026-11-05l -- spitballs #2 + #3: the wardrobe locker and guild heraldry (prd sec 12/13)
- OWNER AGREED BOTH BUFFY COUNTERSPITBALLS, so the round landed them as prd-monetization.md sections 12 and 13 and renumbered the investor paragraph to section 14 (no stale cross-refs; the bench table now carries THREE rows: dyes/locker/heraldry).
- (1) THE WARDROBE LOCKER (sec 12): one per-account unlock = any OWNED look across any OWNED carrier (the sec 11 carrier law upside). THE OWNER'S RAIL HOOK: it rides the CROSS-ACCOUNT TRANSACTION ROOTS -- look unlocks persist as ledger lines in the same account-scoped tx family (not item copies), deed-earned looks keep their sec 10 grade, nothing strengthens by passing through. FREE lane: field-crafted looks always eligible in a small slot set; premium grows slots, never access. Laws: look never a stat, Charter never required, preview never debits, toll orthogonal. Implementation rides the sec 11 overlay decision (ONE surface patch for dyes + looks).
- (2) GUILD HERALDRY PACKS (sec 13): kits of the guild's own marks as looks on the surface itself (hall banners, barque-sail flags, house plaques, member trims); a crew pays once and everybody gets the feature -- groups churn less, so the durable payers. BOUGHT FROM A GUILD VAULT (any member deposits), the vault tracking earned-vs-bought mix per the sec 10 purse law; rank-gated buy permit; unlock lands for all without a member online. Laws: look never a buff, report + takedown flow ships from build round one, every guild earns ONE standard banner free at creation, kits never graded/never Charter-required. Implementation: guild ledger + double-entry vault legs, same overlay seat.
- Round is DOC-ONLY AGAIN: zero .tres, zero service changes, the pack export stands.

## 2026-11-05m -- spitball #4: Lucky, the weekly luck pot (prd sec 14)
- OWNER PITCHED LUCKY, verdict "YAY WITH TWO CUTS": 24-hour charms of raised drop luck across EVERYTHING (materials, craft inputs, weapons, armor, the black-market roll), ~$1.25 gross, affordable-to-grinders, the earn law caps deed-luck at 2 days/week of normal/moderate play. Landed as prd-monetization.md sec 14 (investor paragraph renumbered to sec 15, numbering contiguous again; bench = FOUR rows).
- THE POT LAW (the reframe): 7-luck-day weekly pot PER ACCOUNT, all at the SAME potency -- days 1-2 near-free via deeds, days 3-7 bought at 25 sigils per charm (the Soulbinder ticket's price shape, existing sink row class). Money buys the CLOCK, never a bigger ceiling. Charms activate for 24h; the RESET is the world's weekly tick, not the purchase.
- CUT 1 -- NO XP LEG: drop odds only, never XP or gold-per-kill (sec 9's hard law, not bending for a cheap SKU). CUT 2 -- THE FATED STAMP: bought-luck rare finds bind-on-luck (soulbound, item card visible); deed-luck finds trade free. This is the authored tradeoff the stat-only law demanded AND the RMT-dampener: money can't mint tradable wealth; deed luck strictly better.
- OTHER LAWS: one central roll-time modifier resolved at the drop point (loot tables, market board, harvest bounty -- the black-market 3/12 board flagged as the loudest touchpoint), pot UI preshows remaining days (preview-never-debits), no refund once a day's hours start, pot meter on the account ledger via the tx roots stamped deed/bought, toll orthogonal, never Charter-required (the free lane IS the pot floor: 2 deed days weekly forever).
- IMPLEMENTATION SEAT (build round): pot meter in the account ledger, charm .tres (consumable family, own stack behavior), the single sink row, the central modifier point, the fated stamp, the pot UI. OPEN QUESTION: does the charm lift harvest-node YIELDS too, or only kill/roll drops? (harvest-skip starts to smell).
- DOC-ONLY round: zero .tres, zero service changes, the pack export stands. Next spitball wanted: the conversation continues (owner starts, Buffy lands after yay/nay).

## 2026-11-05n -- Lucky's global jackpot: the spiritbind (owner append, prd sec 14)
- OWNER APPENDED WITHIN SPITBALL #4: a GLOBAL soulbind modifier -- every item in the world carries a very rare chance to land SPIRITBOUND, luck of the draw whether the find is a stick or an earned mythic; "keep players frothing at the chance that the gamble comes with the rarest of the rare." Landed as the "THE SPIRITBIND JACKPOT" sub-block inside sec 14, positioned as the charm's RIVAL FRAMING: distinct from the fated stamp (which taxes BOUGHT-luck finds), the jackpot is GLOBAL and money-neutral.
- LAWS LANDED: one global spiritbind leg inside the same central roll-time modifier (never per-item bandaids); NON-STACKABLE GEAR ONLY (stacks vetoed -- a bound stack is junk-locked); permanent honest item-card stamp; it is the rarest PROVENANCE/prestige, not a punishment tier; MONEY NEVER TOUCHES THE JACKPOT ODDS (a bought charm lifts only the charm's own drop rate; spiritbind rolls identically under bought/deed/no luck -- nobody buys the rarest binder, that IS the froth); toll orthogonal (the jackpot lands OVER whatever the purse already stamped); free-path by construction (the jackpot rolls whether or not Lucky exists; Lucky and grinding both just widen the number of rolls).
- DOC-ONLY round: zero .tres, zero service changes, the pack export stands.

## 2026-11-05o -- spitball #5: the Whisper Ledger and the Peal (prd sec 15)
- BUFFY PITCHED, OWNER YAY'D ("hell yeah" -- the show-off/celebrate/new-friends read): landed as prd-monetization.md sec 15, THE WHISPER LEDGER -- the rumor mill and the Peal; the investor paragraph renumbered to sec 16; bench now FIVE rows.
- SEAT 1 (FREE, worldbuilding first): every spiritbind landing whispers through the village heralds' evening news (item + place, "unnamed"); too rare for spam; the jackpot becomes a WORLD CLOCK (checked like weather) and every whisper advertises the luck economy shard-wide for nothing. Everyone reads, nobody pays.
- SEAT 2 (PAID, the Peal): the landing ALWAYS rumors free (name withheld); the Peal permit (deed-earned or bought, the colorist-license permit shape, never Charter-gated) buys the ring -- zone-wide bell, sky lanterns, the finder's name in the rumor line. The landing is never sold, only its ECHO. Cosmetic only by construction. GIFT LEG: a friend or the guild vault can buy a Peal FOR a finder.
- THE LAWS: nobody buys the landing (amplifier never vendor); NO FREE TEXT EVER (authored templates fed from item-card truth -- moderation is the withhold switch, zero report-flow burden); the location leg free (tourism engine); Charter never gates; toll orthogonal, the mill reads provenance WITHOUT grading.
- IMPLEMENTATION SEAT (build round): Ledger subscribes to the central drop event, scheduled herald broadcast (harbor-lights class or a chat-fabric world line), Peal permit .tres + sink row + zone cosmetic event, gift leg on the vault rail. OPEN QUESTION: walked evening news (editorial lag) vs same-day whispers (immediacy).
- DOC-ONLY round: zero .tres, zero service changes, the pack export stands.
