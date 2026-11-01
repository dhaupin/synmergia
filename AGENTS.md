# Synmergia - Developer Notes for AI Agents

> **Purpose:** This file is a **stable reference** for AI agents
> working on Synmergia. It documents code conventions, architecture,
> and patterns that don't change frequently.
>
> **What this file is NOT:** An operational log, debugging status,
> or session history. (Session notes go in `labs/TASKS.md`.)

> **Last updated 2026-11-01 (channel mute round):** THE LAST UN-FAKED CONTRACT NAME GOT ITS FEATURE, NO DUMMY EMITS. channel_settings_changed is now the OWNER signal of a per-channel mute feature: mute = a RECEIVE-side filter (the viewer hides a channel's incoming live lines in their own view only; own sends ride the normal pipeline); System stays unmuteable (the game's error/announcement voice). ChatService gains set_channel_muted/is_channel_muted/get_muted_channels/channel_by_name; every real change emits channel_settings_changed AND persists through _persist_player_settings -- the _player_settings dict + chat:settings: KV key were declared+loaded at birth with NO writer (the born-dead twin of the ignore list), now the write leg is real. Named refusals mirror the ignore API (duplicate mute, unmute-when-not, protected System). Commands /mute <channel> //unmute <channel> //channels (the state board) ride the API; /muted now ALSO lists muted channels. ChannelSettingsUI panel (UIPanel shell law; catalog rows read the enum through the service instance; System last + protected; refreshes on the service's own signal -- no private re-read) mounts on MenuManager "channels" + chat header [Channels] funnel. ChatUI.add_message drops a muted channel's incoming lines under the same one-filter-covers-both routing the ignore law uses. Receipt tests/test_channel_mute_loop.gd exit 0 (emit truth, refusals, KV + fresh-service reboot round-trip, command legs, display filter, panel toggle-writes-what-it-displays). BUG CAUGHT: iterating an enum bare (for channel in Channel:) iterates the enum NAMES, not values -- channel_by_name + _cmd_channels + the _ready history init all tripped it (history had silently keyed _chat_history by "SAY".."EMOTE" since birth; now all three iterate Channel.values()). Receipt-lore: DictStore.erase() is the real method (not erase_value); queue_free twins refreshed rows for a frame -- row-state reads go through the children, latest wrapper wins. Gates: pipeline exit 0 zero script errors, lint 36/0, naming 25/0, ignore-book + map-ping + fresh-kit + login receipts all exit 0.
> **Last updated 2026-11-01 (cheap pair + ignore book):** THE CHEAP PAIR SHIPPED + THE IGNORE BOOK. (1) WAYPOINT PING: full-map clicks navigate now -- click ON a quest waypoint marker emits waypoint_clicked (the declared signal, zero emits until now) and hud reads WorldMap.last_waypoint_hit() synchronously for the label; canvas clicks emit map_clicked with a TRUE world position (spherical law inverts lat_lon_to_uv exactly -- the old _screen_to_world fabricated flat 8km coords); consumer = hud_integrator._route_map_ping -> WaypointService.create_waypoint ("Map Marker" / "Quest: <label>") + activate_waypoint (beacon + compass ride the service law); the service's own notify path answers rate-limit/cap/invalid. Receipt tests/test_map_ping_route.gd exit 0. (2) CHARACTER CONFIRMED + KIT GATE: character_select emits its signal on Enter World (both legs are creation paths); StarterKitService listens via a tree node_added relay and gates the grant: fresh-confirmed OR no saved progress earns the kit, returning characters STOP re-collecting it per boot (_granted_for was session-only = a per-boot double-grant bug). Receipt tests/test_character_fresh_kit.gd exit 0. (3) IGNORE BOOK: /ignore had zero persistence (list evaporated per reboot), zero UI, and the chat UI's star-match reported "Unknown command" for every service command. ChatService gains ignore_player/unignore_player/get_ignored_players/is_ignored_sender (named causes; id-or-name display matching), _ready calls the previously-dead _load_chat_state (KV revive), /ignore//unignore//muted ride the API, ChatUI's default branch passes through the service's command router DIRECTLY (send_message returns true for unknowns -- direct call keeps the feedback line), add_message drops blocked senders on BOTH chat surfaces (MenuManager feeds the same panel; optional viewer_id for script receipts); IgnoreBookUI (UIPanel shell, idempotent build) on MenuManager's "ignore" row; chat header [Ignore] button. channel_settings_changed STAYS contract surface (per-channel semantics = a channel-mute feature we do not fake). Receipt tests/test_ignore_book_loop.gd exit 0. (4) DRIVING FIX: waypoint/trade/admin called EntityService.get_entity_by_id which does NOT exist (real: get_entity) -- every waypoint activation crashed the proximity tick; all four call sites replaced. Gates: pipeline exit 0 zero script errors, lint 36/0, naming 25/0, all new receipts + login exit 0.
> **Last updated 2026-10-30 (consumer-side round):** THE NO-VOID LAW'S OTHER HALF shipped -- consumers first, then emits earn their keep. DAILIES ROLL AT MIDNIGHT EASTERN now (SignService.current_human_day_index; America/New_York, DST honored via the compiled US rule, the 2-hour sky day and the UTC day both UNTOUCHED on purpose -- Concord calendar/world seeds/ambience stay on current_day_index); test_daily_quest pins both midnight boundaries + spring-forward/fall-back one-second edges. THE SLOT SERVICE WAS NEVER PRINTABLE: slot_service.gd was flat-zero-indent FOR LIFE (4 commits, all flat, never parseable, never referenced -- every gate stayed green over an unloadable file); reindented to tabs + verified via load probe, and ContainerConfigData's static load() SHADOWED the builtin (recursive call, schema never compiled) -> renamed load_config(). THE CONTAINER LOOP IS LIVE: SlotService.open_container/close_container emit container_opened/closed (endpoint did not exist), ContainerUI is the MenuManager 'container' panel (idempotent synchronous content build; UIPanel standard shell), hud_integrator routes through MenuManager.open_menu with an is_showing-guarded close, receipt tests/test_slot_container_open.gd exit 0. CooldownService._process emits cooldown_tick per active cooldown and CooldownIndicator (built for it, tired to reverse-engineering RATE_LIMITED toasts) binds started/tick/ended with instant cancel-retire. InputManager finally hooks Input.joy_connection_changed (controller_disconnected had zero emitters since birth); both pair signals toast CONNECTION_QUALITY. ModeratorProgression's four badge tiers now announce through governance_ref -> _on_badges_gained -> badge_earned -> ACHIEVEMENT_UNLOCKED toasts (inner-class law: owner is passed in, not bare). PartyService.share_xp emits xp_shared (PartyUI refresh rides it); _apply_hit's whiff leg emits skill_missed and hud feeds CombatLog.log_miss (the miss row had zero callers). NOT FAKED (still contract surface): channel_settings_changed (ignore book has no listening UI), npc_spawned (minimap already covers NPC spawns via entity_spawned impressions), zone instance trio, attack_hit (redundant with skill_hit/skill_resolved), observation_ready, instance_contract_changed, notification_queued, character_confirmed, waypoint_clicked. Event-catalog forensics: the deleted 4 files were born 73f6da0 as parallel domain buses whose own commit migrated everything to EventHub instead -- no doc ever promised a later role; EventHub + per-service signals carry every live name. Gates: pipeline 27/0 zero script errors, lint 36/0, naming 25/0, daily/DST + container-loop + quest/login all exit 0.
> **Last updated 2026-10-30 (signal-backlog round):** REAL CENSUS (regex-blindspot-corrected twice): 680 signals = 259 OK / 335 VOID / 78 DEAD / 8 NEWIRE -- NOT 188; grep cannot see string-built emissions (_hub_emit) or name-keyed UI connect maps, so some rows are false. SHIPPED: the dead event-catalog layer (core/events/{combat,entity,inventory,system}_events.gd, ~66 signals, zero refs) DELETED -- EventHub is the one live hub; all true NEWIRE loops closed (target_updated fires on the ring's re-seat frame + target_type_changed on the type flip; blacksmith repair_failed/item_too_broken on every honest leg incl. the can_repair-unreachable bulk path; quest_failed when an IN_PROGRESS daily expires at the sky dawn + abandon refreshes the tracker; respawn_canceled when a revive wins the pending-timer race; InventoryUI item_selected on slot select); the trade anti-scam countdown went LIVE from dormant (both-confirmed used to complete instantly; now a re-fetch-every-beat 3s window ticks through trade_ui's listener); the guild invite loop was finished, not just wired (accept/decline/expire endpoints existed NOWHERE and guild_ui called get_pending_invites() which did not exist; _persist_invite indexed a dict keyed by invite_id with a player_id -- dead writes; new RECRUIT-tier accept path + 30s dual-family sweep emitting the *_expired signals); party_member_updated emits at join/leave/kick; server_manager kick now rides the real NetworkManager.kick_player_by_character_id chain; VantConnector._on_poll GETs /api/action with a busy guard (was a pass-stub). NO-VOID LAW: zero-listener signals are NOT emitted (that would just turn DEAD into VOID wallpaper) -- channel_settings_changed, cooldown_tick, container_opened (no open-endpoint exists), npc_spawned, zone instance trio, skill_missed, attack_hit, threat_overflow, item_bound, bag_locked, badge_earned, state_exited, controller pair, observation_ready, instance_contract_changed, xp_shared, character_confirmed, waypoint_clicked are logged contracts. Gates: pipeline 27/0 zero script errors, lint 36/0, naming 25/0, login/quest/loot all exit 0.
> **Last updated 2026-10-30 (unwired-loops crawl):** THE GUEST-CLICK NOISE WAS A LOG SEMANTICS BUG: login.gd logged press+dispatch as FAIL+OK per click; one honest log now ([OK] on dispatch, [FAIL] only on a real dead end). UNWIRED LOOPS CLOSED in playable: player-menu "report" now reaches PlayerReporter.submit_report (alerts + webhooks); trade add-item is a real ItemList picker (stack + rarity rows, callback-driven so cancel can not strand an await); VaultService GUILD/ACCOUNT resolution wired to GuildService/AccountService and close_vault's false vault_opened emit removed; QuestService min_level gate enforced (_get_player_level existed) and per-player load/save rides the boot loader's DictStore KV path (db stubs deleted). BACKLOG: 188 service signals never fire and/or have zero listeners (telemetry wallpaper, multi-round); vant GET + NetworkManager.disconnect are server-infra TODOs. Pipeline 27/0 exit 0 zero script errors, lint 36/0, naming 25/0, quest gates exit 0.
> **Last updated 2026-10-30 (targeting crawl + ring tracker):** TARGETING IS FULLY HOOKED (crawl): SpawnService registers/unregisters every spawn, Tab/F2/click/interact-press all route through the one `TargetingManager.set_target` chain, HUD TargetFrame/boss bar bind `target_acquired/cleared/updated`, tooltips + party click-targets + a11y ride the same chain, and `use_skill` casts at `get_current_target().node`. THE RING: the pulsing emissive circle mesh under the current target now TRACKS MOVING TARGETS (`TargetingManager._process` re-seats it from the live node; nothing else ever updated it -- zero callers on `update_targetable_position`/`update_highlight`). PIPELINE IS FULLY GREEN HEADLESS: 27/0 exit 0 -- the "pre-existing" 2 failures were schedule drift (the async world boot registers the player ~2 s late), now `_await_player`-gated with a live-NPC re-resolve, plus 3 ring checks (visible, seated under the NPC, hidden on clear).
> **Last updated 2026-10-30 (target-action loop):** THE TARGET-ACTION LOOP SHIPPED: E / touch ACT button / left-click converge on `PlayerController._on_player_input("interact")` -> `_try_interact`, which now opens the ACTION MENU for the nearest NPC/gate in 6 m (`_try_target_context_interact` + `TargetingManager.get_nearest_targetable_by_types`): walk up -> press -> menu -> interact, with an in-range live Tab target outranking the nearest scan and the menu centered (no cursor). Ground loot stays first; placed stations/ankhs after. Receipt: `tests/test_interaction_pipeline.gd` async runner (waits for the async player registration) proves NPC menu (offering-filtered items), dungeon-gate Enter, and 40 m silence; the 2 pre-existing headless guest-click failures are unchanged (test's documented runner is xvfb-run).
> **Last updated 2026-10-27 (audit):** FUNCTIONAL AUDIT SHIPPED (`dev_temp/probes/render_audit.gd`, AUDIT-OK 42): the main world + the underworld booted through the real seams, every recent build walked and asserted on live nodes (beacon/guide halos + night law, Pans deck pieces, cistern, wilds, lake, trail, vents/thrower, mist, live swim credit + a real body's burn). AUDIT-CAUGHT FIX: the lava lake's first geometry sat BELOW the walk shell -- rebuilt to the cistern's walk-line dialect (basin slab collidered at 2000.0, melt surface 2001.2, curb 0.55 over; commons seats re-based, 18/18). Known script-mode noise: headless boots emit pre-existing derive-chain stderr (streamer tints/river specs -- identical in prior probe boots); the audit gates on node/material truth, pixels stay on-device.
> **Last updated 2026-10-27 (commons):** S15.7 THE UNDERWORLD'S WORLD-COMMONS SHIPPED -- lava is WATER-FRAME data (OceanVolume Liquid.WATER/LAVA + burn_dps; data/oceans/lava_underglow_lake.tres: LOCAL pool with a 0.35 m/s east-drift current and 8 dps; _build_lava_lake curb ring + molten disc, tide-pulsed; the visitor tick pays burns in whole digits through _burn_pool -- the debt books EVERY frame, the one-frame reset bug the probe caught) + FORMAL BIOME-BAND DATA (core/schemas/biome_band.gd + data/biomes/biome_underworld_*.tres x5; the wilds builders read count/radii/palette/clearances from the declarations, literals only when a declaration is missing; WILDS-OK byte-identical on the data path) + THE COMMONS: _build_trail (32 plates, camp->cistern->lake overlook), ThermalUpdraft gains world_id (data/thermals underworld_vent_east/vent_flow always-on + thermal_ascent_thrower RITUAL LAUNCHER feeding the East Stack -- the Ascent-door artifact beat, awakened via the ONE ThermalService ritual path), the underworld _process carries visitors through ThermalService.sample (lift + glide-tick + anticheat tickets), and weather_mist(phase) is the strata-mist fog law (0.055 -> 0.02 with the tide, fed per frame). COMMONS-OK (18 checks). Gates: underworld 44 / ocean 44 / CISTERN-OK / WILDS-OK / swim bridge 10/0 / naming lint 25/0 / lint 36/0 / packs 8 green.
> **Last updated 2026-10-27 (warden):** S15.6 THE WARDEN OWES THE CISTERN SHIPPED -- the swim BEAT + the dusk-read + the first wilds. Swim credit is a REAL bridge: OceanService emits `water_entered(body_id, volume_id)` once per dry->wet entry (`_wet_by` book; over-tick-proof), QuestService bridges it deferred into the new QuestData.ObjectiveType.SWIM, and quest_cross_the_cistern.tres targets `ocean_deep_root_pool` verbatim (previous_quest_id chain off quest_listen_to_the_deep; the Warden's greeting carries the cistern branch). The underworld is the LIVE delivery: _visitors hold body nodes and _process ticks every visitor through OceanService (world_root-local), probe_underworld G2 proves one frame in the dish closes the objective (44 checks now). Dusk-read PASS: cistern stone = one shared vein-lit wall mat whose energy rides the tide, darker slab, the bench as the brightest stone (static warm ember -- the exit reads); harbor lights pop at LAMP_ENERGY_LIT 1.8 + a warm halo OmniLight toggled by the same set_lit flip. DEEP WILDS: `_build_wilds` scatters FIVE bands (_wilds_drift golden-spindle, byte-identical on re-conjure): 12 crags / 7 dead trunks / 9 mycelium clumps / 14 stalagmites / 36 grass tufts; stones collidered, paint walks over; aprons keep gates + dish clear (`dev_temp/probes/wilds_probe.gd` WILDS-OK). Gates: underworld 44 / ocean 44 / swim bridge 10/0 / CISTERN-OK / LIGHT-OK / naming lint 25/0 / lint 36/0 / packs 8 green.
> **Last updated 2026-10-26 (cistern):** S15.5 THE GLOW CISTERN SHIPPED -- the Deep Root's catch-dish at the camp shelf: `data/oceans/ocean_deep_root_pool.tres` (LOCAL pool, floor on the walk line 2000.0, surface 2002.4, gentle) + `globe_underworld._build_cistern` (basin slab + 7 tall rim arcs 3.2 m + ONE sheave bench topping 0.3 m over the water = the one honest exit) + the cistern glow law riding the SAME Concord tide (`static cistern_glow(phase)` 0.45-1.0 cos band, high at the surface dawn). Receipt: `dev_temp/probes/cistern_probe.gd` CISTERN-OK; underworld 42 / ocean 44 / naming lint / lint 36/0 / packstruct --deep all green. Script-mode law: no parse-time preloads of game scripts (autoload names register after parse); the lint suite needs `GODOT=$(command -v godot)` after a workspace restore eats the /tmp binary.
> **Last updated 2026-10-26:** HARBOR LIGHTS + FLEET PACKS SHIPPED — S14.8's two-end light law (`entities/harbor_lights.gd`: PierBeacon caged lamp + MoorGuide ember panel, one flank step off the vessel law's dirs, `place_night` reads the Concord epoch the ferry tick already holds — lit dusk→dawn [18.0→6.0 sky hours], sea clamp `max(walk, sea)`; probe `dev_temp/probes/harbor_lights_probe.gd` LIGHT-OK with the berth held at 0.0000 rad). FLEET PACKS: `packs/public/` manifests are GENERATED from the runner's own DEFAULT_SET (`scripts/gen_fleet_packs.mjs`; 8 family packs = 101 tests, zero unfiled; `npx packstruct lint packs/ --deep` exit 0 — the missing-entry drift class the deck round hit dies at generation). The wake chain is complete: deck ride → wake credit → dock warp (warp landings pier-head/moor-bank; `FerryService.warp_wake` validate-only, world owns placement).
> **Last updated 2026-10-26 (deck):** S14.6 DECK RIDE SHIPPED — the Pans Runner's deck is now STANDABLE (piece-collider law in `ferry_vessel.build`: walkable DeckPanel + solid Hull/Hold + thin MastBlock; the old one-belt attach boxed the mast ~7 m up and left the deck unreachable) and `ferry_vessel.place()` carries who stands on her (rigid old→new carry; `deck_rides` anchor meta stamped/cleared by the ride roster; globe_player suppresses the terrain snap under the anchor — the deck panel is the ground, not the seabed law). Receipts: `dev_temp/probes/deck_ride_probe.gd` RIDE-OK (rigid carry 0.0005 m deck-local drift over a 1309 m park step; anchor clears on step-off) + the pans trio re-held + lint 36/0 + the ferry schedule contract. Next: wake-ledger credit for deck rides (the session dock still teleports at the ports, v0 contract). Earlier — **2026-10-19:** WEB/SITE SPLIT SHIPPED — `src/` is now a real site (lander `/`, `/play`, `/privacy`, `/terms`, gated `/admin`) on Vite + React 19 + react-router-dom 6 + Tailwind v4; prerendered by prestruct (`ssr.config.js` route list + `scripts/prerender.js` via `src/AppLayout.tsx` under StaticRouter; build = `npm run build`). Serving law: the raw engine client (`web/`) is served at **`/game/`** on the single domain (dev+preview middleware + `dist/game/` build copy + `public/_headers` for COOP/COEP + pack cache law); legacy `/web/` URL resolves as an alias only, never link it. Gates: `/play` and `/admin` share `src/lib/gate.ts` + `src/components/GateScreen.tsx` (sha256-of-password vs `VITE_GAME_PASSWORD_SHA` / `VITE_ADMIN_PASSWORD_SHA` build-time env, sessionStorage remember, 5s-doubling exponential attempt cooldown); real wall is the Cloudflare WAF rate rule documented in DEPLOY_WEB.md §5 — the gate is friction, not a boundary (static host law). The React 2D companion client, its modals, soundEngine, gameWebSocket mirror, and GodotClientView were REMOVED as tech debt (bridge service stays for admin). CI: `web-ci.yml` bakes `application/config/build_hash` into the pck (in-game truth line proves pack freshness) and uploads artifacts PR/dispatch-only with 3-day retention (push-era artifacts breached the 500 MB quota; `artifact-cleanup.yml` is the one-shot janitor); runner pinned `ubuntu-24.04`. Docs: `DEPLOY_WEB.md` (new web/site guide) + DEPLOY.md (now server-scope only). Guides live in these files; do not re-derive the split.
> **Last updated 2026-10-06:** S13 ROYALE storm shipped (`Contract.STORM_PHASES` + arena_instance `_storm_tick`; storm signals for the fog UI; glider drops; anticheat launch tickets + glide farm clamp). TRAVERSAL ARC: S14 ocean layer SHIPPED through S14.6 (water-as-data + OceanService, swim class + breath clock + pressure, aquatic anticheat + dive tickets + current drift, breather gear, ferries as closed-form schedule, water mounts as rated bodies; probes probe_ocean/probe_swim/probe_ferry/probe_water_mounts + co-located frame tests in the runner default set); S14.7 (the Sundered Sea content pass) remains. S15 underworld + S16 multiworld DESIGNED: `labs/prd-underworld.md` (planet-in-planet; dev/test env relocates there; OFFLINE to players), `labs/prd-multiworld.md` (WorldData registry, closed-form orbits, Moon Gate, world_moon). DEV-TARGET DECISION: the MOON hosts S16.6 dev/probes (the Builder's Pool is its test water); underworld stays the offline mystery layer. Agent memory: vant (axolotl) at workspace `/home/daytona/vant`, brain `cairn` (the agent is "Buffy, callsign Cairn" -- callsign `cairn` is used for ALL registry/brain/horcrux names because the vant engineer side already has a Buffy on the same master entity), org rig Synmergia > Frame Engineering > World Frame > world-frame-architect; disaster-recovery horcrux lives in `horcrux/` on main (password-in-filename convention, see `horcrux/README.md`). Earlier: 3D pipeline proven end-to-end (`scripts/gen_blacksmith_model.py` -> `game/models/npcs/`; exporter gotchas in `labs/prd-3d-pipeline.md` sec 6). Movement Design System: `data/movement_profiles/` + `MovementProfile` schema drive all speeds/gravity/capability gates. Hitbox Profile System: `data/hitbox_profiles/` + `HitboxProfile` schema drive all collision shapes; playable species share ONE player hitbox (species/sex never scale it). Skyward Concord: `labs/prd-psy.md` is worldview DESIGN LAW (no religion in Synmergia); SignService + `data/signs/` run the communal sky clock; AncientDoor re-seals at dawn and door_opened drives ActsService -- the Concord Chronicle (`data/acts/`, act_ prefix) records one chapter per solved day; SkyAlmanacUI (V key) has the Watch-the-sky far-gaze button; the Daily Class Blessing (sky wheel -> +20%/+5 levels for the named class, earn-gated on the code) is the retention beat; quest_watch_the_sky (RECORD_INSIGHT objective, resets at the sky dawn) is the daily beat; the blessed class wears the sky-cyan mote ring + "(*)" sigil (entities/blessed_mark.gd -- NO class_name, preload it; statics late-resolve autoloads) in titles/chat, never GM gold; ChronicleUI (J key) is the lore shelf; chapter-gated mysteries (`data/mysteries/`, `mystery_` prefix, answers DERIVED never stored) solve for titles + XP through ActsService; AudioService (`game/audio/`, WAVs generated by `scripts/gen_door_open_audio.py`) is the repo's only sound path, and a door open erupts the amber PayoffPillar + shard-wide chime. Regression set: `sh ./scripts/godot_test_runner.sh`.
> Accessibility + Agent-Action layer (labs/prd-accessibility.md, SHIPPED rounds 1-5): UIStyles.apply_accessibility writes the real AccessKit properties, A11yService (autoload) runs the [A11Y] stream (menus + world/entity:<id> entries) and focus_next/prev, engine AT support is Auto in project.godot, palette contrast is enforced by tests/test_a11y_contrast.gd (runner default set), and the web probes live in scripts/web_probe/ (window.__synA11yDump() is the agent dump hook; never a human hotkey).
> The hard gate (2026-10-06): `WardGateService` + `data/gates/` (`gate_`
> prefix, filename == id) hold the admin keys (reserved role 0 + the
> Skywarden token, fail-closed on every leg) and the breach embargo
> (embargoed drops die at creation AND pickup; `labs/prd-ward-gate.md`);
> `probe_ward_gate` in the runner default set.

## READ FIRST

Three things that have caused repeated agent damage in this
repo. If you only read one section of this file, read these:

1. **[Autoloads and class_name](#autoloads-and-class_name)** —
   the autoload identifier and `class_name` register different
   things. Putting them on the same script with the same name
   silently breaks code. Read this BEFORE adding any new
   autoload or class.
2. **[Tabs, not spaces](#indentation)** — once a `.gd` file uses
   tabs, every subsequent line must use tabs. Mixed indentation
   is a parse error in 4.7.2.
3. **[No UTF-8 in source](#code-standards)** — emoji, smart
   quotes, and non-ASCII characters cause Godot import failures.
   The existing codebase has 142 lines with emoji (mostly in
   `discord_webhook.gd` and `waypoint_service.gd`); don't
   add more.

---

## Project Overview

Synmergia is a Godot 4.7.2 based MMORPG with an authoritative
server architecture. The architecture has four layers:
**Godot client → Multi-iso orchestrator → State tree
(content-hash) → Postgres + cache**. The orchestrator and
state tree are the **frame**; they live in `/game/core/frame/` and can
extract to their own project.

- **Language:** GDScript
- **Engine:** Godot 4.7.2
- **Architecture:** Client + Authoritative Server + Multi-iso orchestrator + State tree
- **Game root:** `game/` (open this in the Godot editor)
- **Frame root:** `/game/core/frame/` (in Godot project)
- **Persistence layer:** `game/adapters/` (Postgres, Redis, memory)
  — defined in `labs/prd-db.md`. Adapter layer is the official
  interface for all service-level storage.

---

## Code Style Conventions

### Indentation
- **GDScript files (.gd)**: Use **tabs** (not spaces)
- Tab width: 4 characters visually
- `.editorconfig` is configured for automatic enforcement

### Naming Conventions
- Files: `snake_case.gd`
- Classes: `PascalCase`
- Signals: `entity_spawned`, `player_joined`, `target_acquired`
- Enums: `PascalCase.VALUE` (e.g., `Entity.EntityType.PLAYER`)
- Constants: `SCREAMING_SNAKE_CASE`

### Code Patterns
- **Inner classes** for related utilities:
  - `SpawnMetadata`
  - `NotificationService.AlertScope`
  - `NotifKind`
  - `CommunityGovernance.Vote`
  - `CommunityGovernance.ModeratorProgression`
- **Signal naming:** verb past tense (`entity_spawned`, `player_left`)
- **Factory methods** for complex object creation
- **Service singletons** via autoload
- **Frame primitives** in `/game/core/frame/`: NO autoload, NO `class_name`, NO GameManager dependency

### Working with Code

**File Editing:**
- Shell commands and heredocs can be problematic to edit programmatically — prefer direct file edits when possible
- Pay close attention to indentation (GDScript uses tabs, not spaces)
- Always check for unclosed braces, parentheses, and quotes

**Code Standards:**
- Use **tabs** for indentation in GDScript files — `.editorconfig` enforces this
- **No UTF-8 special characters** in the codebase — they cause Godot import issues
- Use `TODO` comments for incomplete work or stubs
- Avoid legacy code, wrappers, and aliases — use current methods when available

**Implementation:**
- Wire and integrate features as you go — look for other code that could benefit from the same wiring
- **Work to completion** — avoid leaving code in a half-baked or non-functional state
- Use existing architecture, methodology, and systems — don't reinvent patterns or go rogue
- The system should function as a **cohesive unit**, not a scattered collection of unrelated pieces

---

---

## Autoloads and class_name

Autoloads are singleton services available globally. `class_name` registers a
script's type as a global identifier. **They look identical when you write
code but behave very differently.** Misuse causes silent runtime errors
(null instance, wrong method dispatch) that cascade through `_ready` and
look like parse errors elsewhere.

**The two rules:**

1. **Autoload name and `class_name` MUST NOT be the same string.** The
   autoload identifier shadows the class_name; you lose the ability to
   call `X.new()` or `extends X` reliably. One of them wins, the parser
   does not warn, and the loser silently does the wrong thing.

2. **Autoloads cannot be instantiated.** `X.new()` on an autoload
   identifier fails at runtime (autoloads are Nodes, not Scripts).
   To make a fresh instance, `load("res://path.gd").new()`.

### Naming

| Aspect | Rule | Example |
|--------|------|---------|
| Filename | `snake_case.gd` | `notification_service.gd` |
| Autoload name | `PascalCase` | `NotificationService` |
| `class_name` | Pick one of: omit it OR rename it differently from the autoload | `class_name NotifDispatcher` is OK; `class_name NotificationService` is NOT if `NotificationService` is also an autoload |

### When to add `class_name`

Add `class_name` when you need to:

- **Instantiate**: `var x := MyClass.new()` (the class is not an autoload)
- **Type-annotate a parameter or variable**: `func process(e: MyClass)`
- **Type-check at runtime**: `if node is MyClass`

Do **not** add `class_name` when the script is an autoload, unless you have
a concrete reason (see below). Autoloads are already globally accessible by
their autoload name; adding `class_name X` where X is also the autoload name
creates a shadow.

### The one case where `class_name` on an autoload is legitimate

If a file is an autoload AND is also extended by other classes (e.g.
`extends Entity` where `Entity` is an autoload), then `class_name Entity`
on the base script is needed so the parser can resolve the parent type
in the `extends` statement. But this is a **smell**: the script is doing
two things (base class + autoload singleton). If you find yourself here,
consider:

- **Option A**: Split. Make the base class its own file (no autoload),
  have the autoload be a small wrapper that `extends BaseClass` and adds
  the singleton state. Other code does `extends BaseClass` and
  `BaseClass.new()`. No shadow.
- **Option B**: Keep `class_name`, but use the autoload ONLY for the
  singleton globals (logger, registry, dispatcher) and never call
  `Entity.new()`. To spawn new entities, use a dedicated subclass
  (`class_name EnemyEntity extends Entity` in a separate file) or
  `load("res://core/entities/entity.gd").new()`.

The current code uses **Option A** for `Entity`: the base class
`res://core/entities/entity.gd` is **not** an autoload. The autoload
was removed from `project.godot` and the script now exposes only
`class_name Entity`. Spawning is done via `Entity.new()` (or
`load("res://core/entities/entity.gd").new()` from contexts that
should not depend on the global class registry). Subclasses
(`extends Entity`) live in `entities/enemy.gd`,
`core/entities/npc_entity.gd`, and `core/entities/skill_academy_npc.gd`.

The old `const Entity = preload("res://core/entities/entity.gd")`
workarounds in 27 callers were removed: they are no longer needed
since `class_name Entity` resolves cleanly without an autoload shadow.
The regression test `tests/test_entity_autoload.gd` covers the fix.

**Allowlist of intentional `class_name` + autoload collisions.** A
small number of autoloads keep both, and they are tracked in
`tests/test_autoload_audit.gd`:

- `QoSService` -- the script exposes static shim methods (e.g.
  `QoSService.rate_limit(...)`) that internally resolve the autoload
  at runtime. The static methods are convenience wrappers; the
  actual state lives in the autoload. The class_name also lets
  callers type-annotate `func (svc: QoSService)`. Do not add more
  entries to this allowlist without updating the audit test and
  this section.

### Accessing autoloads

```gdscript
# Correct: use the autoload name directly (it's already an instance)
NotificationService.notify(...)
QoSService.rate_limit(player_id, "combat")

# Correct: type-check via the autoload name (no class_name needed)
if node.get_parent() == GameManager:
    pass

# Correct: type-annotate a parameter using the autoload name
func process(svc: NotificationService) -> void:
    pass

# Wrong: trying to create a new instance of an autoload
var ns := NotificationService.new()  # FAILS at runtime

# Correct: instantiate a non-autoload class
var math := CombatMath.new()         # class_name CombatMath, no autoload
```

### Extending an autoload's script

```gdscript
# If the autoload file has class_name, this works:
extends Entity  # requires class_name Entity in entity.gd
class_name EnemyEntity

# If the autoload file does NOT have class_name, you must preload:
const EntityScript = preload("res://core/entities/entity.gd")
extends EntityScript
class_name EnemyEntity
```

Preload is more verbose but removes the shadowing risk. Prefer it when
the base script is an autoload.

### Autoload order

The autoload list in `project.godot` is the load and `_ready` order. Top
to bottom. If autoload A's `_ready` calls a method on autoload B, then
A must be listed **after** B. Get this wrong and you get:

```
Attempt to call function 'X' on a null instance
```

This error is misleading. It points to the *caller* (A) but the *cause*
is the *callee* (B) not being ready. Walking the call stack backward
often reveals the real problem.

To check autoload order:

```bash
awk '/^\[autoload\]/{flag=1; next} /^\[/{flag=0} flag' game/project.godot \
  | grep -oP '^\w+(?==)'
```

To detect forward references (autoload using another that comes later
in the list), scan each autoload's source for bare references to other
autoload names. A reference like `GameManager.foo` in `QoSService.gd`
is a forward reference if `GameManager` is listed after `QoSService`
in the autoload list.

### Cycles

Three flavors of cycle, all silent:

1. **`_ready` cycle**: A._ready() calls B.method(), B._ready() calls
   A.method(). Both fail with null instance. No "circular dependency"
   diagnostic. Fix: defer the cross-service calls with
   `call_deferred()` or `await get_tree().process_frame`.

2. **Preload cycle**: A preloads B, B preloads A. Parse error in both
   files. The error message names both, but the root cause is the
   cycle, not the parse error. Fix: extract a third file C that both A
   and B depend on, or use `load()` (runtime) instead of `preload()`
   (parse-time) for one of the references.

3. **Autoload name cycle**: A's autoload entry references B (via direct
   call in `_ready`), B's references A. Same null instance error as
   case 1. Fix: same as case 1.

### When you cannot `extends` an autoload

You cannot use an autoload as the parent class in `extends`. The autoload
is a singleton instance, not a script type. If you need to extend the
script that backs an autoload, you must give that script a `class_name`
(no name collision with the autoload) or preload it.

### Self-recovery playbook (when in a loop)

If the project won't load and you're seeing a cascade of errors:

1. **Stop and identify the FIRST parse error.** Godot reports many
   files failed; usually one is the root cause and the rest are
   downstream. Read the error list top to bottom.

2. **For each candidate root file, check**:
   - Does the file have `class_name X` where X is also an autoload?
     Remove the `class_name` or rename the autoload.
   - Is the file trying `X.new()` where X is an autoload? Use
     `load("res://path.gd").new()` or refactor to a subclass.
   - Does the file extend an autoload's script? Add `class_name` to
     the parent (no collision) or use `preload(...).new()`.
   - Does the file reference an autoload that comes LATER in
     `project.godot`? Move the reference to `call_deferred` or move
     the autoload up in the list.
   - Is the file using a reserved keyword as a variable name
     (`class_name`, `signal`, `func`)? Rename it.
   - Mixed indentation (tabs vs spaces)? Run `cat -A file.gd` to see
     the actual whitespace; pick one and stick to it.
   - `Resource.get("key", default)` parse error? In 4.7.2, default
     args to `Resource.get` were removed. Use `if resource.has(key)`
     guard or `resource.get(key, null)`.
   - Type inference on ternary (`var x := a if cond else b`)? Add
     explicit type: `var x: T = a if cond else b`.

3. **If the file itself is unrecoverable**, do NOT delete the
   business logic as a first resort. Instead:
   - `git stash` to save the working file
   - Reduce the file to: `## Header\nextends Node\nconst Deps = preload(...)`
   - Verify the rest of the project loads
   - Restore the file piece by piece (or use `git checkout HEAD~1 -- file`)
     to find which lines reintroduce the error

4. **Last resort: gut the file.** Only acceptable if (a) the file is
   not on the critical path for the boot sequence, (b) you've checked
   that no other file preloads it, and (c) you record the deletion
   in the commit message with `BREAKING:` so a future agent can
   restore it from history. The pattern:
   ```
   ## OldName - what it did
   ## One-line summary of what was lost
   extends Node
   const Dep = preload("res://path.gd")
   ```
   This is a 3-line stub that does not cascade.

5. **If a stub was created, file a follow-up** to restore the
   implementation. The git history (`git log --all -- path/to/file.gd`)
   has every prior version.

### Diagnostic commands

```bash
# List autoloads in order
awk '/^\[autoload\]/{flag=1; next} /^\[/{flag=0} flag' game/project.godot \
  | grep -oP '^\w+(?==)'

# Find class_name collisions with autoloads
awk '/^\[autoload\]/{flag=1; next} /^\[/{flag=0} flag' game/project.godot \
  | grep -oP '^\w+(?==)' | sort -u \
  | while read a; do
      grep -lP "^\s*class_name\s+${a}\s*$" game/ -r --include="*.gd"
    done

# Find .new() calls on autoload names
# (autoloads are PascalCase; bare class_names are also PascalCase; this
#  returns all .new() calls; manually filter for autoloads)
grep -rEn "\b[A-Z]\w+\.new\(\)" game/ --include="*.gd"

# Find tabs vs spaces in a file
cat -A game/path/to/file.gd | head -5  # ^I = tab, $ = end of line
```

## Architecture

### Core Services (Autoloaded)

A curated subset. For the full autoload list (50+ entries), see
`game/project.godot` `[autoload]` section. This table groups by
purpose; if a service is missing here, it doesn't mean it doesn't
exist.

| Service | Purpose |
|---------|---------|
| **Core base class** | |
| `Entity` | Base class for all entities (`class_name Entity`, NOT an autoload). Use `extends Entity` and `Entity.new()`. |
| **World building & frame** | |
| `FrameService` | Frame execution isolation, seed authority, and T3 state tree management (D030). |
| `ShardParameters` | Dynamic world/shard parameters with immediate or 5-min coalesced persistence (D033). |
| `OpenSeedRegistry` | Reconnect window TTL tracking (5-min default) and instance state finalization (D032). |
| **Storage / persistence** | |
| `AdapterRegistry` | Pluggable storage adapter registry. See `labs/prd-db.md` for the spec. |
| `BackendFactory` | Builds persistence + cache adapters from config. Used during boot. |
| **Event & notification** | |
| `EventHub` | Central event hub with unified entity signals (was named `EventBus` historically). |
| `NotificationService` | Player notifications and alerts. Use `notify()` not `send_to_player()`. |
| **Game state** | |
| `GameManager` | Overall game state, player management |
| `GameLog` | Centralized logger. Use `GameLog.info()` / `GameLog.warn()` / `GameLog.error()`. |
| `GameConfig` | Game-wide configuration access |
| `PlayerConfig` | Per-player config (loaded from disk) |
| **Entities & spawning** | |
| `EntityService` | Track all entities (players, enemies, NPCs) |
| `SpawnService` | Enemy/NPC spawning with metadata |
| `ZoneManager` | Zone transitions and state |
| **Networking** | |
| `NetworkManager` | Authoritative server transport, peer management |
| `PlayerManager` | Connected player state, peer ↔ player_id mapping |
| `InputManager` | Client-side input handling |
| `InteractionLayer` | Range-based interaction resolver |
| **Combat & targeting** | |
| `TargetingManager` | Unified targeting system |
| `CombatSystem` | Combat loop, ability resolution |
| `CombatMath` | Damage/effect calculations (NOT an autoload; a static utility class) |
| `AuraComponent` | (component) Buffs/debuffs |
| `AggroComponent` | (component) Threat/aggro management |
| **Player systems** | |
| `InventoryService` | Player inventory management |
| `TradeService` | Item trading |
| `PartyService` | Party/raid management |
| `GuildService` | Guild management |
| `LootService` | Loot distribution |
| `RespawnService` | Player respawn logic |
| `DeathFeatures` | Death screen, corpse, recovery options |
| `FactionManager` | Faction relationships and PvP modes |
| **Account & login** | |
| `AccountService` | Account creation, password reset |
| `LoginService` | Login + character selection |
| `FriendsService` | Friends list, requests, block/ignore |
| `SameAccountTransferService` | Cross-character transfer within one account |
| **World content** | |
| `DataService` | Static data loader (`.tres` files) |
| `WorldService` | World state, instances, save/load |
| `ShardManager` | Multi-shard routing |
| `ServerManager` | Per-server lifecycle |
| `DialogService` | NPC dialog trees |
| `QuestService` | Quest state and progress |
| `ActsService` | Concord Chronicle (acts/chapters on door_opened) + mystery ledger |
| `AudioService` | Round-robin WAV playback (play/play_world/play_ui); generated assets in `game/audio/` |
| `AchievementService` | Achievement tracking and unlocks |
| `TitleService` | Player titles, prefix/suffix display |
| `WaypointService` | Waypoint discovery, fast travel |
| `FollowService` | Player /party follow mode |
| `BlacksmithService` | Item crafting/upgrading |
| `SkillAcademyService` | Skill learning, training |
| `StarterKitService` | New character starting equipment |
| `VaultService` | Account-wide shared storage |
| `RespawnUIManager` | UI for respawn flow |
| **Moderation & safety** | |
| `AutoResponseService` | Admin alerts and moderation |
| `SecurityService` | Anti-cheat and rate limiting |
| `AppFirewall` | Tool-call firewall, depth limits, recursion guards |
| `SecurityMonitor` | Security event aggregation |
| `CommunityGovernance` | Voting, moderator progression |
| `PermissionManager` | RBAC for admin commands |
| `PlayerReporter` | Player report handling |
| `AdminCommands` | Admin command dispatcher |
| **Infrastructure** | |
| `QoSService` | Latency and rate limiting (also has `class_name`; no `.new()`) |
| `IDRegistry` | Stable ID generation for content |
| `PlayerLockService` | Per-player mutex to prevent race conditions |
| `CooldownService` | Cooldown tracking |
| `SlotService` | Data-driven item slots, no legacy fallbacks |
| **System** | |
| `RegisterTypes` | Type registry initialization (autoload before all services) |
| `DebugOverlay` | Debug HUD (autoload; F-key toggled) |
| `ScreenshotService` | Screenshot capture and storage |
| `WebhookManager` | Outbound webhook dispatch |
| `AntiCheatService` | Server-side anti-cheat detection |

> **Naming caveat:** `EventBus` may appear in comments or older
> code, but the autoload is `EventHub`. If you see `EventBus.X`,
> check whether it's a pre-rename reference (replace with
> `EventHub.X`) or the `class_name SpawnMetadata` (which is a
> bare global defined in `game/core/events/spawn_metadata.gd`).

### Components (Attached to Entities)

| Component | Purpose |
|-----------|---------|
| `HealthComponent` | Health, death, respawn |
| `CombatComponent` | Combat state, skills, damage |
| `AuraComponent` | Buffs/debuffs |
| `AggroComponent` | Threat/aggro management |
| `InventoryComponent` | Item storage and equipment |

### UI Components

| Component | Purpose |
|-----------|---------|
| `UIStyles` | Common styling, colors, fonts |
| `UIPanel` | Base panel class with overlay |
| `ActionMenu` | Context menus (mouse/touch) |
| `TooltipManager` | Unified tooltip system |
| `MenuManager` | HUD management |
| `InventoryUI` | Player inventory grid |
| `BuffBar` | Buff/debuff display |
| `GuildUI` | Guild management |
| `PartyUI` | Party management |
| `TradeUI` | Item trading interface |

---

## Event Patterns

**Unified entity events carry `SpawnMetadata`:**
```gdscript
# Signal signature:
entity_spawned.emit(entity: Entity, metadata: SpawnMetadata)

# Handler must match:
func _on_entity_spawned(entity: Entity, metadata: SpawnMetadata) -> void:
    pass
```

> **WARNING:** Mismatched signal handlers cause runtime errors. Always verify signatures.

---

## Common Operations

### Creating Spawn Metadata
```gdscript
var metadata := SpawnMetadata.world_boss("Dragon", "zone_1", position, 50)
```

### Accessing Enums
```gdscript
# SpawnMetadata types
var type := SpawnMetadata.SpawnType.BOSS
var priority := SpawnMetadata.NotificationPriority.CRITICAL

# Entity types
if target.entity_type == Entity.EntityType.PLAYER:
    pass

# Notification types
NotifKind.WARNING
NotifKind.ALERT
```

### Sending Notifications

Use the **typed-Kind pipeline** (`NotificationService.notify()`) for
all service-level toasts. The frame handles dedupe, type-mapping, and
priority automatically based on the kind.

```gdscript
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

# To a specific player
NotificationService.notify(
    NotifKind.ITEM_ADDED,
    "Picked up Sword of Truth",
    "InventoryService",                       # source_service label
    "inv_add:%s:%s" % [player_id, item_id], # dedupe key (5s window)
    {"item_id": item_id, "rarity": "epic"},
    player_id                                 # recipient
)

# Server-wide / admin scope (recipient = "")
NotificationService.notify(
    NotifKind.ADMIN_ALERT,
    "RecursionGuard exceeded depth 16",
    "AppFirewall",
    "fw:%s" % message.hash(),
    {"context": "agent_tool_call", "depth": 16}
)
```

> **Don't** call `NotificationService.send_to_player()` directly for
> new code — that's the legacy path. Use `notify()` instead.

### Notification → Toast Pipeline
Every service-level event ends up in a toast panel in `HudLayer`:

```
Service → NotificationService.notify() → NotificationDispatcher → TooltipManager.show_toast()
```

When adding a new service:
- For **in-game state changes** (death, level-up, item equipped): emit a typed signal
- For **infrastructure events** (throttled, restricted, banned): call `notify()` so the player sees a toast

```gdscript
# GOOD (infrastructure): player must see the toast
NotificationService.notify(NotifKind.RATE_LIMITED, "You're casting too fast", "QoSService", ...)

# GOOD (in-game state): emit a signal
signal item_equipped(player_id: String, item_id: String)
item_equipped.emit(player_id, item_id)
```

### Range-Based Entity Queries
```gdscript
var nearby := EntityService.get_entities_in_radius(
    player.global_position,
    20.0,  # range
    Entity.EntityType.PLAYER
)
```

---

## File Organization

```
.
├── game/                          # the Godot 4.7.2 project
│   ├── adapters/                  # Storage adapter layer (Postgres, Redis, memory)
│   │   ├── persistence/           # PersistenceStore interface + impls
│   │   ├── cache/                 # CacheStore interface + impls
│   │   ├── memory_layer/          # In-memory state store
│   │   ├── registry.gd            # AdapterRegistry autoload
│   │   ├── backend_factory.gd     # BackendFactory autoload
│   │   └── README.md              # Adapter layer spec summary
│   ├── core/
│   │   ├── admin/                 # Admin shell, permission, reports
│   │   ├── ai/                    # NPC AI (decision trees, behaviors)
│   │   ├── autoload/              # Global singletons (~20)
│   │   ├── combat/                # Combat system, ability resolution
│   │   ├── community/             # Voting, moderator progression
│   │   ├── components/            # Entity components (health, combat, etc.)
│   │   ├── entities/              # Base entity classes (Entity, NPCEntity, ...)
│   │   ├── events/                # Event hubs + metadata types
│   │   ├── frame/                 # Frame primitives (moved from labs/)
│   │   │   ├── math/              # NSC-9, icosahedral
│   │   │   ├── kv/                # LRU, state_tree, T3
│   │   │   ├── srv/               # RulesEngine, ScopeEngine, Markov, LOD, Axis
│   │   │   └── db/                # snapshot_store
│   │   ├── input/                 # Interaction layer, input maps
│   │   ├── notifications/         # NotificationService + NotifKind enum
│   │   ├── schemas/               # Data schemas (Resource subclasses)
│   │   ├── services/              # Game services (30+)
│   │   ├── targeting/             # Targeting system
│   │   ├── ui/                    # Core UI base classes
│   │   └── utils/                 # Generic utilities (id_registry, app_firewall, ...)
│   ├── entities/                  # Concrete entity types (enemy, character, ...)
│   ├── scenes/                    # .tscn scenes (world, NPCs)
│   ├── connectors/                # AI agent connectors (discord, webhook, ...)
│   ├── data/                      # .tres resources (static data)
│   ├── ui/                        # User interface (panels, dialogs, HUD)
│   └── tests/
│       ├── adapters/              # Adapter layer tests (unit + integration)
│       └── *.gd                   # Smoke tests (one per major system)
│
├── labs/                          # Frame + design docs
│   ├── prd.md                     # Product requirements
│   ├── prd-db.md                  # Storage adapter spec (authoritative)
│   ├── TASKS.md                   # Session log + open tasks
│   ├── world-building*.md         # World/architecture docs
│
├── srv/                           # Deployment configs (docker, certs)
├── AGENTS.md                      # This file
└── README.md                      # Project overview
```

The Godot project root is `game/`. The `labs/` directory is outside
the project so it doesn't taint the stable build with experimental work.

`game/adapters/` is the **only** directory that services should use
for persistence. See `labs/prd-db.md` for the full spec.

---

## Scene & World Naming Conventions (spatial layer)

Decided 2026-09-30 after the globe rename. The DATA layer names by
category prefix (`world_`, `zone_`); the SCENE layer names by
containment relation so orbit/nesting is readable from the filename.

| Thing | Pattern | Example |
|-------|---------|---------|
| Generic globe scene (radius from `synmergia/world/planet_radius` -- boots AS Synmergia at 20 km, the prototype at 100 m) | `globe_world.gd/.tscn` | the S3 spherical scene root |
| A world's moon globe | `globe_<world>.gd/.tscn` | `globe_moon.gd` (the pale stone, dev target) |
| Future orbiting/nested bodies | `globe_<world>` | `globe_underworld` when S15 gets its own scene (today it reuses the generic globe via `world_underworld.tres` radius) |
| Runtime node names | `Globe<Scope>`, PascalCase | `GlobeWorld`, `GlobeMoon` (globe_driver waits on these names) |
| Player controller on any globe | `globe_player.gd` (`class_name GlobeWorldPlayer`) | scope-generic on purpose; one controller, every globe |
| World declarations (data) | `world_<id>.tres` | `world_main.tres` (Synmergia), `world_moon.tres` (the pale stone), `world_underworld.tres` (The Deep Root) |

Rules:
- Scene filenames never contain category words in REVERSE order
  (`moon_globe` was the inconsistency; fixed to `globe_moon`).
- The generic globe scene is NOT named after any one world -- it is
  the shape, and `world_<id>.tres` declarations give it identity
  (radius, gravity, orbit, lore). One scene, every planet.
- Canon display names live ONLY in the .tres (`display_name`,
  `lore`); code comments may use them, code identifiers may not.
  Canon today: planet = Synmergia, moon = the pale stone,
  underworld = The Deep Root.
- When renaming a scene, grep `globe_driver.gd` node-name waits and
  the `game/tests/probe_*` paths BEFORE committing; the runtime node
  name changes with the file (`.tscn` root `name=`).

## ID Naming Conventions (data ids)

Decided 2026-09-25 after the data/npc + data/npcs consolidation.
One id per entity, filename equals the id for prefixed categories,
and NO dual-format compatibility shims in code (no trim_prefix
fallbacks, no display-name OR id candidate loops). Quest bridges and
consumers read exactly one form.

| Category | Id style | Example | File |
|----------|----------|---------|------|
| NPCs | `npc_` prefix | `npc_village_elder` | `npc_village_elder.tres` |
| Quests | `quest_` prefix | `quest_wolves_hunt` | `quest_wolves_hunt.tres` |
| Zones | `zone_` prefix | `zone_starter_plains` | `zone_starter_plains.tres` |
| Factions | `faction_` prefix | `faction_human` | `faction_human.tres` |
| Items | kind prefix | `wep_iron_sword`, `potion_soul_gem`, `res_iron_ore` | filename == id |
| Misc items (data/items) | `item_` prefix | `item_ancient_coin` | filename == id |
| Quest items | `item_quest_` prefix | `item_quest_sealed_writ` | filename == id, `is_quest_item = true` |
| Status effects | `buff_` prefix | `buff_barrier_field` | filename == id |
| Loot tables | `loot_` prefix | `loot_wolf` | filename == id |
| Hitbox profiles | `hitbox_` prefix | `hitbox_beast_medium` | filename == id |
| Sky Signs | `sign_` prefix | `sign_the_awakening` | filename == id |
| Chronicle Acts | `act_` prefix | `act_1_the_first_vault` | filename == id; chapters are plain dicts (the QuestData pattern); no faith language in copy (prd-psy sec 4) |
| Mysteries | `mystery_` prefix | `mystery_the_first_vault` | filename == id; answers are DERIVED (never stored) -- SKY_CODE re-derives SignService.get_ancient_code(answer_day), OBSERVATION_TALLY from the live sign catalog; reward titles must exist in data/titles |
| Daily sky quest | `quest_watch_the_sky` | `quest_watch_the_sky.tres` | RECORD_INSIGHT objective targets the literal `sky_insight`; reset keys off SignService.current_day_index() |
| Ancient doors | bare id on the node | `AncientDoor` (entities/ancient_door.gd) | no .tres (door state is SignService unlock history) |
| Dwellings | `dwel_` prefix | `dwel_fireplace_stone` | filename == id |
| Currencies | `currency_` prefix | `currency_gold` | filename == id |
| Mounts | `mount_` prefix | `mount_plains_runner` | filename == id |
| Vehicles | `veh_` prefix | `veh_haven_ferry` | filename == id |
| Accessories (items) | `acc_` prefix | `acc_ring_first_light` | filename == id |
| Enemies | bare id | `wolf` | `enemy_wolf.tres` (file keeps prefix) |
| Dialogues | bare id | `village_elder_greeting` | filename == id |
| Offerings | bare filename key | `village_quests` | `village_quests.tres` |
| Species / titles / achievements / world bosses / targets | bare id | `human`, `slayer`, `first_blood` | filename == id or schema prefix |

Quest data contracts (single-form, no fallbacks):
- TALK objectives target the NPCData id verbatim (`npc_village_elder`).
- EXPLORE objectives target the ZoneData id verbatim (`zone_starter_plains`).
- KILL objectives target the enemy display_name ("Wolf") -- combat
  bridge credits display_name.
- COLLECT objectives target the item display_name ("Moonpetal Flower").
- Quest items (Item.is_quest_item) carry a resolvable `quest_id` and
  never vendor; the lint enforces the ref.

`game/tests/test_data_naming_lint.gd` enforces the prefixed styles,
filename==id, and cross-file references (zone_id, quest chains,
giver/turn_in, offering quest_ids, dialogue npc_id, zone rosters).
Run it after adding or renaming any data ids.

## Data Schemas

### TargetSchema (`data/targets/`)
- `target_player.tres`, `target_enemy.tres`, `target_npc.tres`
- `target_loot.tres`, `target_dwelling.tres`, `target_gateway.tres`

### EnemyData
- `enemy_type`: NORMAL, ELITE, BOSS, WORLD_BOSS
- `level`, `health`, `attack_power`, `defense`

### Item
- `soulbound`, `bind_on_pickup`, `bind_on_equip`
- `unique`, `stack_size`, `rarity`

### GM Classes
Three admin-only classes hidden from normal character selection:
- `gm_akkan`, `gm_human`, `gm_synthetic`
- All have `role = 0` (Role.GM)

GM visibility: `[GM]` prefix in chat, gold name color, "GAME MASTER" badge in tooltip (no emoji; see the no-UTF-8 rule).

---

## Labs Conventions

The `/labs/` directory is for experimental primitives that could
extract to the multi-iso frame. Different rules apply:

| Rule | Game (`game/`) | Frame (`labs/`) |
|------|-----------------|-----------------|
| Autoload | Yes (mind the rules) | No |
| `class_name` | Only when needed (see below) | No |
| GameManager dep | Allowed (singleton access) | No |
| Adapter layer | Yes (Postgres, Redis, memory) | No (pure functions) |
| Tests | Co-located in `game/tests/adapters/`, smoke tests in `game/tests/` | Co-located (`foo.gd` + `test_foo.gd`) |

> **`class_name` in `game/`:** add it ONLY when you need
> `X.new()`, type-annotation, or `is X` checks. Do not add it
> to autoloads (the autoload name is already a global
> identifier). Do not add it to scripts that are only ever
> used by `preload`. See [Autoloads and class_name](#autoloads-and-class_name)
> for the full rules.

### Frame Primitive Rules
1. Each primitive is its own `.gd` file
2. Tests are co-located: `nsc9.gd` + `test_nsc9.gd`
3. No autoload, no `class_name`, no GameManager dependency
4. New code goes here first. The game consumes from here.

### Frame Contents
| Subdirectory | Contains | Examples |
|--------------|----------|----------|
| `game/core/frame/math/` | Pure functions. No state. | NSC-9 encoding, icosahedral projection |
| `game/core/frame/geometry/` | Pure functions for spatial addressing | NSC-9 encoding, spatial fragmenter, bridge |
| `game/core/frame/kv/` | In-memory data structures | LRU cache, content-hash, state tree |
| `game/core/frame/srv/` | Service logic | RulesEngine, ScopeEngine, Markov, LOD, Axis |
| `game/core/frame/db/` | Database integration | snapshot_store, migrations |

See [`labs/README.md`](./labs/README.md) for the full conventions.

---

## Security: BBCode XSS

All `RichTextLabel` nodes have `bbcode_enabled = true`. User-supplied
strings embedded in BBCode format strings are a potential injection vector.

**Pattern to avoid:**
```gdscript
"[color=%s]%s[/color]" % [color, user_string]   # DANGEROUS
```

**The fix:** Replace `[` and `]` with full-width equivalents:
```gdscript
static func _esc(text: String) -> String:
    return text.replace("[", "［").replace("]", "］")
```

**Files with this pattern:**
- `core/services/chat_service.gd`
- `ui/components/combat_log.gd`
- `ui/components/chat_ui.gd`
- `ui/components/dialog_ui.gd`
- `ui/admin/admin_dashboard.gd`
- `core/admin/player_shell.gd`
- `core/autoload/logger.gd`
- `core/services/qos_service.gd`
- `core/services/security_service.gd`

When adding new `RichTextLabel` BBCode with user input, always pass it through `_esc()` first.

---

## Important Patterns

### Null Checks for Services
Always check if a service exists before using:
```gdscript
if NotificationService:
    NotificationService.send_to_player(player_id, message)
```

### Instance Validation
Always validate entities before use:
```gdscript
if is_instance_valid(entity) and entity.entity_id != sender_id:
    # safe to use
```

### Defensive Helper Pattern
When a helper bridges two services, prefer try-known-methods fallback:
```gdscript
func _get_peer_for_player(player_id: String) -> int:
    if PlayerManager == null:
        return -1
    for method_name in ["get_player_info", "get_player", "find_player"]:
        if PlayerManager.has_method(method_name):
            var result = PlayerManager.call(method_name, player_id)
            if result is Dictionary:
                var info: Dictionary = result
                var peer_id = info.get("peer_id", -1)
                if peer_id is int and peer_id > 0:
                    return peer_id
    return -1
```

### Godot GDScript Rules
- **`extends` must precede `class_name`** when both are present
- **Mixed indentation is fatal:** Once a file uses tabs, every subsequent line must use tabs
- **Inner class methods cannot call outer class methods** without qualification
- **`extends Control` for scene-instantiated UIs:** Use `extends Control` + manual stubs for UIPanel methods

### NPC Scene Pattern
NPC entities use `scene_path` in NPCData to specify their `.tscn`:
```gdscript
# NPCData schema
@export var scene_path: String = ""  # Path to NPC .tscn scene

# SpawnService loads the scene and configures it:
if npc_data.scene_path:
    var packed := load(npc_data.scene_path) as PackedScene
    var entity := packed.instantiate() as NPCEntity
```

### Player Spawn Signal
Use `GameManager.player_entered_world` to trigger services when a player enters:
```gdscript
# Connect in your service:
GameManager.player_entered_world.connect(_on_player_entered)

func _on_player_entered(player_id: String, character_data) -> void:
    # Give starter items, initialize player state, etc.
```

---

## Testing

Smoke tests live in `game/tests/`. Run with Godot headless:

```bash
cd game
godot --headless --path . --script res://tests/test_notification_toast.gd
godot --headless --path . --script res://tests/test_hud_integration.gd
godot --headless --path . --script res://tests/test_login_flow.gd
godot --headless --path . --script res://tests/test_auto_response_signals.gd
```

Or run the committed regression set (default: data-naming lint,
movement profiles, anticheat limits, blacksmith + wolf 3D probes;
`--all` = every `test_*.gd`):

```bash
sh ./scripts/godot_test_runner.sh
```

Or run all tests via Docker (see [DEPLOY.md](./DEPLOY.md)):

```bash
docker run --rm -e START_MODE=test synmergia
```

| Test | Coverage |
|------|----------|
| `test_notification_frame.gd` | NotificationService frame (context, kind, dedupe) |
| `test_notification_toast.gd` | NotificationService → TooltipManager.show_toast() end-to-end |
| `test_hud_integration.gd` | HudIntegrator handlers, NotificationService → CombatLog |
| `test_login_flow.gd` | Account + login + character flow |
| `test_auto_response_signals.gd` | AutoResponseService signals and ActionType enum |
| `test_islands.gd` | Core island logic (island_poc.gd) |
| `test_e2e_flow.gd` | End-to-end account flow |
| `test_notif_migration_*.gd` | Notification migration tests |
| `test_acts_service.gd` | ActsService: door_opened consumer, gate/fill/fence logic, voice-law check, almanac watch button, Chronicle panel, DictStore round-trip (int keys normalized on load -- JSON stringifies them) |
| `test_mysteries.gd` | Chapter-gated mysteries: data shape, gate-before-answer ordering, derived sky-code + tally answers, per-player solved ledger + reboot round-trip, TitleService reward |
| `test_audio_service.gd` | AudioService: WAVs load, pool built, unknown names rejected, round-robin advances (structural only -- headless has no audio device) |
| `test_daily_quest.gd` | quest_watch_the_sky: RECORD_INSIGHT credit per player, turn-in, REWARDED-daily reset at the sky day boundary, full re-earn loop |
| `test_blessed_mark.gd` | Blessed-class motif: sigil truth (earn-gated), GM-gold distinctness, mote-ring visuals, transition toast, title composition order |

> **Note:** `--script` mode does not pre-load autoloads. Resolve them via
> `root.get_node_or_null("NotificationService")` rather than the bare identifier.

### Test structure

Tests live in two places:

- **`game/tests/`** — smoke tests for one system each
  (login flow, notification dispatch, etc.). These run the full
  game boot and exercise real autoloads.
- **`game/tests/adapters/`** — unit and integration tests for
  the storage adapter layer. Do not require the full game boot;
  instantiate `AdapterRegistry` and backends directly.

A typical test file uses the `SceneTree` pattern:

```gdscript
extends SceneTree

func _init() -> void:
    var ok := true
    if not _test_basic_crud():
        push_error("FAIL: basic_crud")
        ok = false
    quit(0 if ok else 1)

func _test_basic_crud() -> bool:
    var store := MemoryPersistenceStore.new()
    # ... actual test ...
    return true
```

Run with `godot --headless --path . --script res://tests/test_foo.gd`.
Exit code 0 = pass, 1 = fail.

For adapter tests, use the same pattern but reference backends
through the registry:

```gdscript
extends SceneTree

func _init() -> void:
    AdapterRegistry.register("default", MemoryPersistenceStore.new())
    var store: PersistenceStore = AdapterRegistry.get("default")
    # ... exercise store ...
    quit(0)
```

When adding a new adapter backend (e.g., a new database), add a
test in `game/tests/adapters/` that:
1. Constructs the backend
2. Runs CRUD against `MemoryPersistenceStore` (the reference)
3. Verifies the new backend returns the same results

Do not test against the live database in unit tests; spin up a
test container or use the memory backend as the oracle.

### Adapter layer overview

Services should NEVER touch Postgres, Redis, or any storage
backend directly. They go through `AdapterRegistry`:

```gdscript
# In a service:
var store: PersistenceStore = AdapterRegistry.get("accounts")
await store.put(player_id, account_data)
var data = await store.get(player_id)
```

The registry returns a `PersistenceStore` (memory, Postgres, or
any other impl) based on boot configuration. See
`labs/prd-db.md` §3-5 for the full spec.

---

## Key Godot Rules

1. **Entity autoload is REQUIRED:** `Entity` must be in the
   `[autoload]` section BEFORE `RegisterTypes`. The parser needs
   `Entity` to be a known type when RegisterTypes walks the type
   tree. (Same logic for `AdapterRegistry` and `BackendFactory`:
   they must come before any service that uses them in `_ready`.)

2. **`load()` vs `preload()` vs `class_name.new()`:** pick by use
   case, not by habit.

   ```gdscript
   # Use class_name + .new() when the class is registered globally
   # (preferred for non-autoload, frequently-instantiated types):
   class_name SkillBook          # in res://core/schemas/skill_book.gd
   var book := SkillBook.new()   # works at parse time

   # Use load() + .new() when you do NOT want class_name globally
   # registered (e.g., to avoid an autoload/class_name collision,
   # or to load lazily at runtime):
   var script := load("res://core/schemas/skill_book.gd")
   var book = script.new()

   # Use preload() + .new() only when the file is constant
   # (resource path hard-coded) AND has class_name. Otherwise
   # use load(). Mixing these causes "Identifier X not declared"
   # parse errors.
   ```

3. **`extends` must precede `class_name`** in any file that has
   both. The parser reads them in order; if `class_name` comes
   first, the parse fails.

4. **Tabs only, in GDScript files.** Once a line uses a tab, every
   line in that scope must use a tab. `.editorconfig` is supposed
   to enforce this, but copy-paste from the web and shell heredocs
   frequently introduce spaces. When in doubt, run
   `cat -A file.gd | head -20` — tabs render as `^I`, spaces as ` `.

---

## GDScript 4 Gotchas

Common mistakes agents make with GDScript 4.7.2:

```gdscript
# Scene instantiation — use instantiate(), NOT .instance()
var instance := preload("res://scene.tscn").instantiate()  # Godot 4
var instance := preload("res://scene.tscn").instance()     # Godot 3, breaks in 4

# Script instantiation — load() vs preload() vs class_name
# See "Key Godot Rules" #2 above for the full decision tree.
var book := SkillBook.new()                              # class_name registered
var book := load("res://schemas/SkillBook.gd").new()     # runtime, no class_name

# Node removal — use queue_free(), NOT free()
instance.queue_free()  # safe, deferred
instance.free()        # can break children cleanup

# Null checks — always validate with is_instance_valid()
if node != null and is_instance_valid(node):  # safe
if node != null:                              # can hold stale references

# String formatting — both work in 4.7.2; pick one and be consistent
var msg := f"Hello {name}"   # f-string (Godot 4+, recommended for new code)
var msg := "Hello %s" % name # old style, still works
var msg := "Hello {0}".format([name])  # also works, rarely used

# Reserved keywords — `class_name`, `signal`, `func`, etc. cannot
# be variable names. Use `char_class_name`, `signal_name`, etc.
var class_name := "warrior"   # PARSE ERROR
var char_class_name := "warrior"  # OK
```

### New 4.7.2 strictness (the things that broke during the parse-error cascade)

- `Resource.get(key, default)` default arg was removed. Use
  `if resource.has(key): resource.get(key)` or
  `resource.get(key, null)` then null-check.
- Type inference on ternary requires explicit type. Use
  `var x: T = a if cond else b` not `var x := a if cond else b`.
- `class_name`, `signal`, `func`, `var`, `const` are reserved
  variable names. Rename to `char_class_name` etc.
- `assert(cond, "msg")` in release builds compiles to no-op; use
  for invariants only. For runtime checks that must run in
  release, use explicit `if not cond: return` or push to a logger.
- `await get_tree().process_frame` in `_ready()` is a valid
  way to defer past the autoload order; cheaper than
  `call_deferred` for one-shot deferred work.
- **Don't grep the horcrux.** `horcrux/*.svg` stones are one ~800 KB
  line of base64 ciphertext; a ripgrep-style match echoes the whole
  wall and starves the search result budget. They are listed in the
  repo-root `.ignore` (which search tools honor and git does not --
  the stone stays tracked and committed). If you must inspect the
  stone, use `vant horcrux inspect horcrux/<file>.svg` or read the
  README, never text search.

## Session hygiene (the 2026-10-13 disk-full incident — read this)

### Push to GitHub early and often

One working-tree-only incident cost a full day of terrain law work:
the file existed ONLY in the sandbox when the disk filled, and
`git checkout HEAD` restored a much older era. The law now:
- If it has been **a couple of hours** since the last push, push.
- After any sizeable law/battery step goes green, **commit and push
  immediately** — don't batch three turns' work into one uncommitted
  wedge. Freebuff's GitHub App mints the credential; nothing manual
  is needed and running `git push` normally is the whole job.

### Bound the logs

Probe/test stdout goes to /tmp and is regenerable — but it must
never be allowed to pile up:
- The test runner caps any single log file at 256 MB (`ulimit -f`):
  a runaway logger dies with SIGXFSZ (the test fails visibly, the
  disk survives) instead of eating the workspace.
- The runner sweeps `syn_*` logs older than a day at startup.
- Probes log per-CHECK, never per-tick/per-frame. A frame-loop
  print inside a headless probe is a disk bomb.
- Before any multi-hundred-KB file REPLACEMENT, check `df -h`. A
  failed str_replace mid-write once truncated the source file the
  check-out later had to restore.

