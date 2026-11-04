# Synmergia - Developer Notes for AI Agents

> **Purpose:** This file is a **stable reference** for AI agents
> working on Synmergia. It documents code conventions, architecture,
> and patterns that don't change frequently.
>
> **What this file is NOT:** An operational log, debugging status,
> or session history. (Session notes go in `labs/TASKS.md`.)

> **Last updated 2026-11-04 (PR-45 merge + S14.7.4 deferral round):** THE DEATH BOOKS PAID, THE STRAIT'S PINS GOT THEIR BUOYS, AND THE GARDEN'S PAINT LEARNED PER-PLANT TRUTH. (0) THE MERGE: OpenHands' PR #45 landed as-is (`08b6e46f`, closes #44): death_features.gd's payout legs were guarded by `has_method()` on methods NO class declares (`get_xp`/`get_gold`/`modify_xp`/`modify_gold`/`get_zone_id`), so kill-streak rewards toasted a phantom payout (+N XP, +N gold that never moved) and death penalties no-opped; the legs now pay through the real duck-typed wallet surface (`experience`/`gold` fields + `add_experience`/`add_gold`, clamped spends, `experience_changed` re-announce, a signed delta mirrored into PlayerManager for the local body) and the death-history zone id routes through `ZoneManager.get_entity_zone_id()`. Receipt `test_death_progression_surface` (18 legs) joins the repo on main as landed-not-DEFAULT (verified 18/0 + the death cluster neighbors + lint). (1) THE STRAIT BUOYS (harbor_lights.gd + globe_world): the barque's two pins get their harbor marks -- `build_strait_buoys()` stands a floating drum + ring band + moor shaft + slim mast + amber lamp ON the sea line at ONE BEACON_FLANK_STEP off each berth (so the hull never touches its own marker; a buoy is not a moor bank -- its base IS the sea line, no walk read by design), carrying the SAME `lamp`/`halo` metas the pier beacon does, so `_barque_ferry_tick` flips both with `HARBOR_LIGHTS.place_night` off the epoch it already holds (lit dusk to dawn, dark to the sun). (2) PER-PLANT PAINT (S14.7.4): the whole-cove hide is GONE. The DERIVE now replays the REGISTER call's jitter seed-for-seed (`base_acc + 9091 + bed_idx*101`, the same three randf_range per plant) so the paint learns each registered plant's real dir, tags every kelp strand / vent spire with the nearest plant's `plant_k`, and mints ONE hidden stump per plant (`Stump0..2`, plant's own material, `plant_k` meta). The binder's refresh is per plant now: the cove's furniture (reef boulders, drowned stones) STANDS through every take -- a taken plant shears to its stump until THAT plant's respawn; ids say nothing -> untouched (fail-open on paint, and paint never invents depletion). Swim receipt H legs re-lawed (one-plant shear, bed's other plants keep paint, furniture stands, cove never vanishes, all-taken all-stumps, respawn restores); the two stale material-count legs count by NAME now (stumps share the bed's material by design), and the shelf-face stump leg reads ALL beds on the face (a face can own kelp AND trench beds). (3) THE SEABAR'S OWN _READY: new receipt `test_sea_bar_hud_ready.gd` (runner DEFAULT_SET -- 108) walks the REAL HUD seam: hud_layer.tscn instantiates, `_ready()` installs SeaBar (named SeaBar, hidden dry), the wet legs read the INSTALLED chip (band SURFACE-SWIM rename / SQUEEZE, breath ratio, pressure row, DROWNING flash, dry hide), and the poll law rides the bar's own `_process` against PlayerManager's local slot (bind shows, clear hides; bounded waits so a dead heartbeat cannot hang the receipt). (4) THE DOCK-WARP TIER RIDES THE BARQUE: `_execute_wake_warp` routes the landing by vehicle_id -- the runner's gateways land at the capitol pier / pans moor bank as before, the barque's land at HER OWN pins read from the VESSEL'S OWN lane metas (the hull's lane is the sailor's landing, never a re-derived bearing), and the landing radius carries the vessel law's own `max(walk, sea)` clamp so a warp never spawns a body UNDER the water line (drowning takes the body only by its own swim). FerryService's tier was already generic; the world owned the landing and now has it. Barque receipt grew the tier legs: unearned warp refused by name ('not yours yet'), three deck wakes make the wake known, the earned warp emits vehicle + pin true, and the landing law tested against a real-streamer-shape stub (seabed walk never lands under the sea line; foreign pins have no landing = INF). GATES: swim receipt 60/0 exit 0, barque receipt green (buoys + warp legs, exit 0), SeaBar HUD receipt PASS, lint green (5 files), fleet packs regenerated 9 packs / 7 unfiled + packstruct --deep green; full default pipeline coverage GREEN on the final tree via the resume ledger over the runner's own per-test boots (106 unique names all exit-0-PASS; four cloud restarts killed four uninterrupted tails, the ledger owns the coverage -- the sweep DID catch probe_crafting's die-flake: its synthetic leg ran one un-seeded roll and now drives the same chain itself, roll-agnostic for any die).

> **Last updated 2026-11-04 (PR-43 merge + S14.7.3 barque/binder/damage round):** THE STRAIT'S SCHEDULED RIDE BECAME REAL PAINT, THE GARDEN'S PAINT FOLLOWED ITS TRUTH, AND THE SEA BEGAN TO DROWN THE CARELESS. (0) THE MERGE: PR #43 landed as-is (OpenHands' UIManager fix, `24e1631b`): `has_method()` on SIGNAL names is always false, so UIManager's three GameManager connects were silently dead all project life -- `_initialize_ui()` never ran, TargetTooltip never spawned. Guarded with `has_signal()` + connected de-dupe, autoloads resolved at runtime (script-mode-safe), `TargetingManager.get_local_player_id()` added (the phantom call next door), and a static lint guard now flags `has_method("signal_name")` repo-wide (lint is 37 checks now). Receipt `test_ui_manager_tooltip_wiring` 11/0 joins DEFAULT_SET -- 107 tests. (1) THE BARQUE (globe_world, ferry_vessel): the data route `veh_sundered_barque` (6 casts/day, first 5.5 h, 0.6 h crossing) stood without a hull all this time; `ferry_vessel.gd` gained `build_vessel()` (one generic builder -- the same piece-collider hull, the same `place()` law, guarded by lane metas) and `build_barque()` (the two pins' own dirs from DATA: `DataService.get_gateway("waypoint_strait_moor"/"waypoint_strait_seaward").source_position`, always the gateway's own truth, never an in-file bearing); the Pans runner's build() delegates to build_vessel. `_build_sundered_barque()` boots her with the runner's tick law (FerrySchedule + place() + deck carry) and her own roof of DECK WAKE bookkeepers (the runner's original weak wake glue is kept untouched on purpose). The lane arcs across the strait to the two gateway pins, hull floats ON the world sea line mid-crossing, berthed lifts at both ends. (2) THE WAKE TICK SHAPE: the barque's berthing glue plans `at_sea` BEFORE it clears the seen-roster — a body marked on a sea tick is credited at the very next berth, the runner-law shape just without the runner's old edge. (3) THE BINDING (deep_garden_binder.gd new law + streamer metas): the garden grove grove's no longer just paint -- the register call now stamps `deep_garden` groups and `harvest_ids` metas on each (face, bed) grove, and the world-side binder joins HarvestService's depletion book to the paint: while ALL three of a bed's plants are depleted the cove hides its kelp/pearls until a respawn reveals it; leaf-empty beds (never registered, e.g. a bare host) keep paint without pretending anything was taken. Binding is idempotent (dock-meta guard across re-inits and re-derives). (4) THE SEA OWNS THE BODY IN FULL: globe_player's swim step now reads breath/pressure/burn/drowning from `tick_swimmer`, books them (`_sea_breath_s/_max`, `_sea_pressure`, `_sea_drowning_s`, `_sea_burn_dps`), and pays: drowning (10 dps past an empty breath), the pressure pool (pool = rate, drained at mult 1), and any non-water burn each march a damage debt that drops through `take_damage` in whole points; surfacing wipes the debt (health never heals from a surface, the pool eased by the service's law). The MOUNT HANDOFF also got its feed (RideService.water_stamp_for): before the tick, the sea step asks the ride service for the mount's stamp -- a swimmer mount's grace/crush-bonus/current-immunity enter the SAME tick call (a mounted body and a naked body obey one ocean law), a land mount past the waterline is dismissed by the service itself, no ride service means the naked path unchanged. (5) THE HUD: SeaBar (ui/components/sea_bar.gd, the StormBar dialect) under HudLayer next to StormBar, polls the local body's swim book at 0.15 s, hidden while dry: band row (SURFACE SWIM / SUBMERGED / SQUEEZE / CRUSH), BREATH bar (fraction of breather capacity), DROWNING flash at zero, the pressure pool row. The same posture the horde bar keeps: the damage is the body's law, the bar only tells the truth about it. (6) THE FORD PROBE'S DRY LEG LANDED: probe_terrain_planet measured "dry" walk at a spring's antipode -- under the S14.7 radial sea that antipode can be open ocean on the Sundered backend, so the S14.7.2 sea step then took a "dry" body standing on the seabed (CRUSH band) and the dry speed leg collapsed (ratio 133.33; the last full pipeline had been waived two rounds straight so nothing caught it). The dry site is the hydro law's OWN guaranteed-dry ground now (the spawn apron, flat 28 m): PASS by law, not by accident of geography. RECEIPTS: swim 52/0 (added legs: mount grace re-bands the body, the ride law is asked, a dismissed land mount still obeys the sea, breath/pressure books drain through health, surfacing wipes the debt without a heal, SeaBar band/breath/pressure/drowning rows plus dry-hidden, grove identity metas + full-take hides + respawn reveals); barque 16/0 (route status honest, both pins' gateway dirs, one piece-collider hull, lane metas, floats on the sea line mid-lane, berths at the pins). GATES: receipts 52/0 + 16/0 + 11/0, lint 37/0 (the new guard green, 5 files), full pipeline rerun recorded in the TASKS log below, packs 9/6 unfiled + packstruct --deep green. Deferred: the dock hemp-off ferry moor buoys for the two strait pins, a SeaBar integration test through hud_layer's own _ready, ride entities for the garden's props (kelp stumps when partially taken -- paint-per-plant rather than paint-per-bed), and the wake_known dock-warp tier riding the barque.
> **Last updated 2026-11-04 (S14.7.2 Sundered Sea deep garden + sea body):** THE DEEP SHELF GOT A WORLD AND THE BODY LEARNED TO SWIM IT. Data alone cannot be a sea: S14.7.1 authored the bands and the current, this round puts them in the world. (1) THE DEEP GARDEN (globe_terrain_streamer): SIX AUTHORED BEDS on the strait chart (`DEEP_BEDS`: kelp shelf at x 0.40/0.45/0.50 with y -0.07/0/0.07, trench pearls at 0.58/0.64/0.70 with y -0.04/0/0.04) resolve through `StraitChart.dir_from_chart` onto the real sphere, and the bed direction's OWN FACE (the `IcosahedralFaces` lookup) owns it -- `_deep_beds_for_face(face)` is the ONE placement law read by BOTH the harvest registration and the prop build, so a bed you can see is a bed you can take. A face may own more than one bed (a 21 km patch is large next to the chart), and each bed keeps its own identity (`deep_kelp_<face>_<bed>_<k>`, `DeepGarden<face>_<bed>`) -- the first draft assumed one bed per face and was falsified by the receipt. Registration rides `_kick_prop_derivation` BESIDE the strait freight (main thread, service side effect, never worker work): three live HarvestService nodes per bed on the res_ ids the S14.7.1 economy reads, ids seed-stable per (face, bed), depth jitter clamped INSIDE the authored band (kelp 30-45, pearls 50-58), positions on the RADIAL SEA LINE (`OceanService.sea_surface_radius()` -- one sea truth, resolved by the service; the shell is the fallback when no service exists). Respawn is authored past the tide: kelp 420 s, pearls 900 s. (2) THE DRAW (same face, same beds): kelp beds paint FOURTEEN strands (7-14 m tapered cylinders, radial basis off the bed direction, the shared prop mesh registry + ONE cached kelp material) and four reef boulders; trench beds paint six pale vent spires and two drowned stones; children sit in the patch's local frame through `_tangent_patch_local` exactly like trees and rocks, so a streamed-out face takes its garden with it and a revisit re-derives the same grove. (3) THE SEA STEP (globe_player): the world body finally answers the water. `_sea_swim_step(delta, up, wish)` calls `OceanService.tick_swimmer` ONCE with the breather's grace + `current_immune`, and obeys the returned band -- DRY/WADING return false (the river ford law keeps its bands, untouched), SUBMERGED/SQUEEZE/CRUSH take the body: swim pace = walk x 0.62 steered at 4/s, the volume's CURRENT added on top at its own declared flow (the FERRY LANE: 0.5 m/s along the Sundered RUN tangent; a current-immune breather reads ZERO from the service, the one seam), buoyancy springs onto a 0.6 m float depth unless crouch dives or jump climbs, and CRUSH ignores the wish and pushes up (the ocean says no). `_sea_carry` is the applied horizontal book (HUD/anticheat next). Leaving the water forgets the swimmer book. RECEIPT `tests/test_sundered_sea_swim.gd` (runner DEFAULT_SET -- 105 now; fleet packs regenerated 9 packs / 4 unfiled sets, packstruct --deep green) 32 checks / 0 fails: six beds each owned exactly once, real owning faces, a non-bed face owning nothing, per-kind draw counts (14 kelp + boulders / 6 spires + stones, and a mixed face draws only its own shelf kelp), no draw on a non-bed face, three harvest nodes per bed with the right res_ id + band + sea-line depth, id-stable re-registration, and the body legs (dry keeps the walk, 38 m down is taken, band >= SUBMERGED, depth read, the declared current > 0.4 m/s along RUN, `_sea_carry` == the volume flow, idle float upward, immunity zeroing the flow, leaving clears the book). GATES: receipt 32/0 exit 0, lint 36/0, packstruct --deep green, continent-shard boot probe on the changed streamer (result in labs/TASKS.md). Deferred: node-in-world PROP-ENTITY binding (the harvest nodes are service truth; the garden mesh is the paint), breath/pressure DAMAGE conversion + HUD meters, the ferry as a scheduled ride (FerryService already owns the schedule; the drift is the lane today), and water mounts riding the sea bands.
> **Last updated 2026-11-04 (roster + client-dispatch round):** TWO PHANTOM-CALL SEAMS DIED (issues #34/#35). (1) THE ROSTER API: admin/targeting surfaces asked `PlayerManager` for `get_player_info` / `get_all_players` / `get_online_player_ids` / `is_player_online` -- none of which existed, so every admin command path, the permission session check and `requires_target_online` targeting raised "Nonexistent function ... in base 'Node (player_manager.gd)'". `PlayerManager` now owns the thin delegating helpers, backed by `EntityService`'s live registration (the ONE roster): rows are `{entity_id, name, level, online, permission_level}` built by duck-typing the live player node, "online" means a live player node is registered (`get_entity(id) != null`), never an invented character id, and permission comes from `PermissionManager.get_player_level` with PLAYER (0) as the floor. All reads node-resolve (`get_node_or_null`) instead of touching autoload identifiers, so bare hosts stay quiet. CONSUMER FIX: `admin_commands._find_entity_by_id`'s roster fallback did `p as Node3D` on what is now a dictionary row -- it resolves the row's `entity_id` back through `EntityService.get_entity` and returns the LIVE node (or null). (2) THE CLIENT DISPATCH: `NetworkManager._receive_client_message` called `InputManager.handle_client_input` / `InteractionLayer.handle_client_action` / `ChatService.handle_client_chat` -- three methods that never existed anywhere in the tree (latent: no in-repo producer sends those types yet, so it would have been an instant runtime throw on the first real client message). The dispatch is now honest: chat routes through the REAL `ChatService.send_message`, with the sender identity DERIVED from the peer's associated character (`get_character_for_peer`, the login mapping) -- the payload's own `sender_id` is ignored, so a client cannot speak as someone else; an unmapped peer is dropped by name; a channel resolves through `ChatService.channel_by_name` and falls back to SAY rather than inventing one. Input/action keep their wiring behind `has_method` guards (they call the handler if a manager ever grows one) and otherwise warn ONCE per type per process (`_unrouted_warned`), and unknown message types warn the same way instead of being silently swallowed. RECEIPT `tests/test_roster_and_dispatch.gd` (runner DEFAULT_SET, fleet packs regenerated -- 9 packs / 3 unfiled sets, packstruct --deep green) 37 checks / 0 fails: the four roster methods + `_handle_client_chat`/`_warn_unrouted` exist, `ChatService` has no phantom `handle_client_chat`, empty/unknown ids are honest (false/empty), a REAL registered player body yields the row (entity_id/display_name/level/online/permission_level) and lands in `get_online_player_ids` + `get_all_players`, the admin row-to-node lookup resolves the live body (and null for a stranger), a whisper from an unmapped peer is dropped while a mapped peer delivers exactly one row whose sender is the DERIVED character (the payload's forged sender never appears), unregistration clears online/rows/ids, and the unrouted book stays one line per type. Receipt lore: GDScript lambdas connected to typed signals should stay UNTYPED in the callback signature -- a typed lambda silently failed to receive `message_received` here; SAY also requires a living audience (`_get_channel_targets` empty = honest refusal), so the route leg uses WHISPER's explicit target. GATES: receipt 37/0 exit 0, lint 36/0, quest glide receipt 10/0, data-naming lint 26/0, packstruct --deep green; full pipeline deferred this round by owner instruction (the runner DEFAULT_SET is now 104). Also merged this turn: OpenHands' PR #41 (GLIDE objective + bridge, closes #40) as `94ecc77e`, draft PR #24 closed as already-satisfied (main's web-ci.yml already carries `mkdir -p builds/web-shell`).
> **Last updated 2026-11-04 (glide objective integrity round):** THE UNCOMPLETABLE GLIDE QUEST DIED. `quest_wings_over_haven` authored its only objective as a KILL (type 0) with the descriptive target `'glide 300 meters'` -- the KILL bridge credits enemy display_names (and BoutHostService's fabricated `TRIAL_DUMMY_NAME`), so NO credit path could ever produce that literal and the quest could never leave IN_PROGRESS. THE FIX IS A REAL OBJECTIVE TYPE: `QuestData.ObjectiveType.GLIDE` (13) with the one-id contract `target == "glide_distance"` (the SWIM precedent). ThermalService already accrued per-body glide distance (`record_glide_tick`, fed by the glider tick in globe_player + the underworld visitor tick) but spoke it ONLY to the gliding achievements; it now emits `glide_distance_reached(player_id, meters)` once per `GLIDE_QUEST_STEP` (300 m) boundary crossed, and `QuestService._connect_glide_bridge` (deferred connect, has_signal-guarded, the insight/swim pattern) routes it into GLIDE objectives. `globe_player.gd` flushes the glide session on the falling edge -- the wing AUTO-DEPLOYS near the ground, so a completed glide spans many frames and the old single-tick flush never landed; `_flush_glide_session` (Engine.get_main_loop() guarded) pushes distance/altitude/time once when GLIDING ends. THE STATIC GUARD (test_data_naming_lint): every authored objective target must resolve against the SAME catalog its credit bridge reads -- KILL->enemy display_name, COLLECT->item, EXPLORE->zone id, TALK->npc id, SWIM->ocean id, GLIDE->glide_distance, RECORD_INSIGHT->sky_insight; it scans inline AND multi-line `objectives = [...]` blocks (the multi-line form hid quest_intro_core_npcs from a first draft) and allows only `marshal's dummies` (entity-free trial dummies). It caught the real defect and the Awakening's stale TALK display-name target (the round-1 PR #39 fix, re-landed here). Receipt `tests/test_quest_glide_bridge.gd` exit 0 ten legs (deferred bridge connect, .tres shape, 299 m no-milestone / 300th fires once, real accept + 1/1 credit + COMPLETE, no over-tick, glide text row). Gates: pipeline exit 0 zero script errors, lint 36/0, data-naming 26/0.
> **Last updated 2026-11-04 (S14.7.1 Sundered Sea deep-shelf data pass):** THE WORLD SEA LEARNED ITS OWN WATERLINE. The Sundered Sea round's first increment ships as DATA + SERVICES (no fake visuals): (1) OceanVolume gained the RADIAL WATERLINE model (`waterline_is_radial`) -- the plane waterline is only honest where a scene is small; the 20 km world sea's waterline is a SPHERE. The pairing law binds it to radial rock, the receipt pins both. (2) OceanService resolves the sea's truth ONCE (`sea_surface_radius()` = DEFAULT_FLOOR_RADIUS 20000 + TerrainGen.sea_level(world_seed), runtime-cached; data volumes stay pure and can never disagree with the terrain that paints the water): radial volumes claim [floor_radius, sea_r + 2 m wading reach] in `volume_at`, and `sample_depth` reads the radial column (negative above the line, -1 inside the rock) -- the plane branch is untouched, so probe_ocean/probe_swim's Haven Shelf + Builder's Pool laws did not move a meter. (3) THE CURRENT LAW'S SEA EDITION: Item gained the `current_immune` accessory field (to_dict/from_dict legs ride too); `breather_for` speaks it; `tick_swimmer(..., current_immune)` stamps ZERO (the sea cannot carry the pearl-diver -- the same seam the water mounts ride). (4) HarvestService grew the DEPTH-BAND nodes (`register_node(..., min_depth_m, max_depth_m)`; 0 = ungated): `harvest` samples the ACTOR's body depth (PlayerManager local-body duck truth -> OceanService.sample_depth) and refuses BY NAME -- `not_in_water` (no body / dry / rock), `too_shallow`, `too_deep`, all BEFORE the depleted/rate gates -- fail closed: the deep garden cannot be taken blind from the shore. (5) THE DATA: `data/oceans/ocean_sundered_sea.tres` -- the world's first radial-waterline volume (floor_is_radial, center ZERO, floor_radius 19400, max_depth 60, pressure 0.1; current = backend_sundered's RUN tangent at 0.5 m/s, the ferry lane prd sec 8 promises); `res_kelp_fiber` + `res_abyss_pearl` reagents; `acc_breather_abyss_pearl` (x8 air, +20 m grace, current-immune necklace, level 8); `recipe_abyssal_breather` (1 pearl + 8 kelp, hand station); banding: reef kelp nodes 30-45 m, trench pearls 50-58 m (the squeeze line is 50; the pearl lives past it, the breather buys it back). RECEIPT: `tests/test_sundered_deep_economy.gd` (runner DEFAULT_SET -- fleet packs regenerated, 9 packs / 2 unfiled family sets, packstruct --deep green) 36 checks / 0 fails: the seed sea truth (waterline radius == shell + Gen.sea_level exactly), claim windows (+2 wading, inside-rock -1), RUN-lane current == BS.RUN_DIR.normalized()*0.5 with the immune tick reading ZERO, bands at 20/49/55/61 m, both node bands refusing by name and paying through the honest purse (3 kelp / 2 pearls after the grants), a no-body fail-closed leg, the craft gate (8 kelp alone nothing; 1+8 crafts), the breather equip + default-law reset + un-equip reset. GATES: receipt exit 0 36/0, lint 36/0, full pipeline exit=0 / **103 passed / 0 failed / 0 SCRIPT ERROR** (runner DEFAULT_SET now 103; the four long continent shards included), packstruct lint --deep exit 0. NEXT DUE (S14.7.2+): node-in-world registration in the streamer (the `_register_harvest_node` pattern, seed-stable ids), reef/kelp/trench visual props, globe_player swim integration with OceanService's radial waterline, and the current loop as a ferry ride lane.
> **Last updated 2026-11-04 (driver hookups + dialogue/quest round):** THE PLAY DRIVER'S SOCIAL/NAV HOOKUPS + TWO DIALOGUE/QUEST DEFECTS. THE DRIVER grew three stages in `playthrough_driver_runner.gd` (already in DEFAULT_SET -- extended in place, no fleet-pack regen): 15 WAYPOINT->COMPASS (`create_waypoint_here` + `activate_waypoint` opens the HUD Compass for the local player, out-of-bounds `create_waypoint` refuses, deactivate closes it -- the compass consumer had zero driver coverage), 16 FRIENDS (request -> accept -> block, asserting the observable loop state), 17 CHAT (a real party makes PARTY chat resolve a live audience, System lines always land, the ignore book hides a peer at ChatUI while System stays visible). THREE FIXES THE STAGES SURFACED: (a) `FriendsService.accept_friend_request` emitted BOTH `friend_request_accepted` AND `friend_request_declined` (copy-paste from decline) -- the false decline is gone (issue #38). (b) `quest_main_awakening.tres` (The Awakening, the game's FIRST quest) authored its TALK objective target as the display name `"Village Elder"`, but the TALK bridge credits by the NPCData id verbatim (`dialogue_ended` carries `npc_village_elder`; no display-name fallback), so the first quest was UNCOMPLETABLE and gated the chain behind it (`quest_main_teachings` requires it) -- fixed the data to the npc_ id (issue #37). (c) `test_data_naming_lint.gd` now asserts every TALK (type 5) objective names a real `npc_` id (RegEx over the objectives array) -- verified it flags the original data; the lint had checked giver/turn_in refs but never objective targets. This round also carries the `IcosahedralFaces` mutex-guarded `_ensure_built` (issue #36, the concurrent-build half of the #19 race; the entry below documents the fix itself). GATES: playthrough_driver 113 passed / 0 failed (was 78), full pipeline 102 passed / 0 failed / 0 SCRIPT ERROR / 0 aborts, lint syntax 7/0 + indentation 5/0 + general 12/0 + charset 3/0 + autoload 9/0, data-naming lint 26/0, quest/dialogue/social tests all exit 0.
> **Last updated 2026-11-04 (icosahedral lazy-init race round):** ISSUE #19 IS NOT COSMETIC -- IT IS A DATA RACE WITH A HARD CRASH. `IcosahedralFaces._ensure_built()` (core/frame/math/icosahedral_faces.gd) used a non-atomic lazy init (`if _built: return` ... build ... `_built = true`) over SHARED `static var` books. The terrain streamer derives faces on worker threads (globe_terrain_streamer._mesh_derive_job / _prop_derive_job), and several can reach `face_center()` before the first build finishes; two threads then BOTH ran the build and appended to the shared `_face_centers`, growing it past 20 (`Out of bounds get index '46'`) and tearing the heap (`malloc(): unaligned tcache chunk detected`, abort 134). On this repo's contended 2-core sandbox the crash reproduced on demand (16 threads calling terrain statics cold); on a normal host the derives finish fast enough that the race usually loses, which is why it read as boot "noise". FIX: a `static var _build_lock := Mutex.new()` guarding a double-checked build -- `_ensure_built()` locks, re-checks `_built`, runs `_build_locked()` (the old body, minus its trailing `_built = true`), then sets `_built` and unlocks. VERIFY: the 16-thread cold repro is 0 errors / exit 0 (was abort 134); probe_terrain_backend 11/0 and probe_stream_continent_a all-PASS, still exit 0. This is COMPLEMENTARY to the terrain-fence round's `async_shutdown()` (commit 1e00d88): the fence joins/drops workers at world death (the teardown-lifetime half), while this lock stops the two-lane build itself from tearing the heap mid-run. The fence's instrumentation falsified the race hypothesis because the window is timing-dependent -- the 16-thread cold repro (16 threads calling terrain statics before any build) still aborts 134 on the fenced HEAD, and passes under this lock. RESIDUAL (separate, still open on #19): the teardown-lifetime errors (`get_ticks_msec on a null value`, empty-name calls, "Thread object destroyed without its completion realized") are the probe/world quitting while a derive lane is mid-flight; a blocking `_exit_tree` drain DEADLOCKS on the slow sandbox (derives take 25-30 s there) so it was NOT shipped -- the remaining fix is a non-blocking drain (await frames until `pending_derive()==0`), left for a dedicated round. GATES: repro exit 0 / 0 errors, terrain probes exit 0, lint syntax 7/0 + indentation 5/0 + general 12/0 + charset 3/0 + autoload 9/0, test_terrain_determinism exit 0.
> **Last updated 2026-11-03 (PR-22 merge round):** OPENHANDS' QUEST/DIALOG/MONEY-LOOP SUPER-MERGE LANDED (branch merge commit `bf70f22`, PR #22 recorded merged): the playthrough driver walks 14 verified stages now and the branch also auto-closes #23/#25/#26/#27/#28/#29/#30/#31/#33 -- the big beds: QuestService rewards PAY (both authoring forms; faction/reputation routes through FactionManager.modify_reputation; quest chains enforce prerequisites via a shared `_first_unmet_prereq()`; optional objectives stop gating completion; `auto_complete` turns the onboarding quest in on the spot), DialogService's actions route the REAL seams (`STOP_FOLLOW`/`UNLOCK_TITLE`/`TEACH_SKILL`/`GIVE_ITEM`/`GIVE_CURRENCY`/`SET_WAYPOINT` etc. -- the dialog lane finally executes, set_waypoint reaches the real ZoneManager API), InventoryService grew the signed-delta `modify_gold` (vault + death gold-penalty stop no-oping), VendorService buyback is typed + persisted, TradeService's unique-item guard actually runs, corpse bag drop + the target ring mesh fix, QuestUI renders readable objectives (the `_esc()` BBCode double-escape bug), the journal's Complete tab keeps REWARDED quests, and the runtime nonexistent-method callers (CoordinatorService `GameLog.warning`, AutoResponseService kick/ban legs, HudIntegrator friend names) were routed to the real ones thru. THREE NEW default-lane receipts (not in the runner DEFAULT_SET, driven by web-ci + their own legs): test_dialogue_quest_reward 22/0, test_quest_availability 12/0, test_dialogue_ui_flow 7/0, plus test_trade_unique_guard 4/0 -- the driver is 77/0 and CI green at every commit. MERGE-INTEGRITY GATES ON MERGED MAIN IN THIS WORKTREE: lint `bash tests/lint/run_all.sh` 36/0 (the fence + character-panel gates unchanged), full pipeline `sh ./scripts/godot_test_runner.sh` exit 0 / **102 passed / 0 failed / 0 SCRIPT ERROR** with `playthrough_driver` + `test_quest_availability` + `probe_character_panel` + the four continent shards + `probe_planet_rebase_20km` + `probe_terrain_backend` all passing under the #19 fence (the pipeline ran TWICE to completion: pre-merge at 1e00d88 and post-merge at bf70f22 -- both 102/0/zero script errors; one aborted at 49 passes and one at 51 by the cloud runner restart, never by code). OPEN: #34 (PlayerManager roster API), #35 (NetworkManager client-message dispatch), issue #28/30/31/33 auto-closed by the merge. Next due: the S14.7 Sundered Sea content pass (the long lane), OpenHands now on 23/24-adjacent lanes.
> **Last updated 2026-11-03 (terrain-fence round):** ISSUE #19 CLOSED AS OWNER -- the teardown stderr spam ("Nonexistent function '_tint_for_pure' in base 'RefCounted (globe_terrain_streamer.gd)'" / "Nonexistent function '' in base 'Vector3'" / "Cannot call 'get_ticks_msec' on a null value" + Godot's "A Thread object is being destroyed without its completion having been realized") was TRACED, not believed: HEAD control runs (fix stashed) reproduce the exact 6 SCRIPT ERROR + 3 thread-warning spam on probe_stream_continent_a's natural exit, and the spam lands AFTER "TickService: Stopped" -- THE DERIVE WORKERS ARE STILL RUNNING when the engine starts finalizing (the empty '' names are calls resuming into script state the finalizer frees around them; the get_ticks_msec-on-null is the Time singleton dying mid-call). THE ISSUE'S OWN HYPOTHESIS (a) WAS FALSIFIED BY INSTRUMENTATION: the statics are politely resolved (23 mesh jobs / 11 prop jobs entered and completed inside the workers in one instrumented boot) -- the killers are the UNJOINED THREADS at world death, the exact mechanism probe_meshcache_ram already works around with its clean-exit drain. DEBUG-INSTRUMENTED proof chain: fence entered at world death with N live workers; normal jobs join instantly; a straggler class of RE-DERIVE jobs (face re-kicks from the final frames) parks mid-compute in an engine-internal futex (all worker threads observed parked at futex_wait with ~0% CPU while main lived) and NEVER resumes except under the finalizer -- unbounded wait_to_finish() on it hangs the exit FOREVER (three 900 s timeouts), so THE BOUNDED LAW is the fence's spine: `globe_terrain_streamer.async_shutdown()` (MAIN THREAD ONLY: kickers + appliers are main-thread) marks the streamer closed, then joins every worker that finishes inside a 30 s window -- `wait_to_finish()` only on threads whose job RETURNED (a fast reap), a still-alive park past the window is DROPPED (its Thread dies unjoined, the one honest residue the finalizer would hold anyway) instead of wedging the boot -- then the mesh+prop books clear under their own mutexes. `_kick_mesh_derivation`/`_kick_prop_derivation` refuse work after the fence (`_shutdown` guard -- a dying world never feeds new doomed jobs). `globe_world.gd` grew `_exit_tree()` -> the fence (guarded `has_method`, mock/fence-less streamers stay silent); every world death -- scene swap, probe exit, teardown -- walks the fence BEFORE the node releases the workers' script state. MEASURED vs HEAD control (7 boots / 4 boots): drained boots (probe_planet_rebase_20km, probe_terrain_backend light-load, meshcache) 0 SCRIPT ERROR / 0 thread warnings both sides-per-fence; straggler boots (continent_a, terrain_backend under heavy host contention): 6+3 at HEAD -> 0-3 + 0-3 fenced, and the exit is GUARANTEED natural (HEAD had no exit risk; the fence never adds one -- the bounded drop). RECIDIVISM NOTE IN EAR: the straggler park is ENGINE-LEVEL (issue's own suggestion (b)) -- a 4.7.2 parked-mid-derive worker only resumes inside the finalizer; this round does NOT fake that away, it bounds the cost so logs in the normal and drained cases are silent and no boot can hang. Lint 36/0; full pipeline gate in this round's entry below.

> **Last updated 2026-11-03 (character-panel live stats round):** ISSUE #21 CLOSED -- the character panel reads the character AS THEY ARE, not as they were born: `character_panel.gd`'s `_refresh_stats_display` now renders LIVE truth -- the header and every stat total ride the LIVE level (`_get_local_player()`'s `level` when the body carries one, else the book's), totals come from the new `CharacterData.get_stat_total(stat_name, level_override=-1)` (the +5 sky-blessing law stays INSIDE get_stat_total -- no forked math), the gear delta is read straight off the live bag `_resolve_inventory().get_equipment_stats()` (the SAME book `_apply_equipment_stats` pushes onto the player, single source of truth, parallel write forbidden), and the derived rows route the SAME merged book through the new `CharacterData.get_derived_stats(stats_override={})` (empty = old behavior; the override carries ALL SIX keys because get_derived_stats pads missing keys at 10 -- dropping an untouched stat would silently rewrite it to the floor). Card display law: allocated + gear both -> "%d (+%d pts, +%d gear)", gear only -> "%d (+%d gear)", allocated only -> "%d (+%d)", else plain total. Refresh hooks: `_show_tab` re-renders stats/skills on the STATS/SKILLS shows, and `_equip_item_from_picker` + `_unequip_item` call refresh_stats() after the equipment grid re-render. THREE DEAD-AT-BIRTH LEGS the receipt surfaced and killed: (1) the equip picker + its apply handler iterated `inv._items` -- NEVER a member; the store is the index-addressed `_inventory` -- so every slot picker said "No equippable items" forever and the apply leg always fell to "Could not find item in inventory"; both now walk `_inventory`'s indices. (2) The stat value lookup `VBox/Value` named a node that was a GRANDCHILD (card > HBox > VBox > Value, the HBox auto-named) -- the lookup missed on every resolve, so the six stat value labels froze at their birth text for the panel's whole life; HBox is now named and the lookup is `HBox/VBox/Value`. (3) The tab never re-rendered on show or on equip/unequip -- the hooks above. RECEIPT: `tests/probe_character_panel.gd` EXTENDED in place (runner DEFAULT_SET -- modified, not added, no fleet-pack regen) with the LIVE-TRUTH leg group E beside its original A-D: the level law (book totals at LIVE 7 outrun the stale creation-time cd.level=1), real gear through a REAL bag (wep_iron_sword +5 strength, acc_ring_first_light +2 vitality, equipped from their ACTUAL bag slots -- `add_item` stores a DUPLICATE, so the receipt matches by item id, never resource identity), the header's "Level 7" printed over a cd.level that still says 1, the strength card exactly `"%d (+5 gear)"` from the level-aware total + bag delta, and derived max_health equal to `get_derived_stats(merged_expect)` -- expected value computed by the same method, formula shorts never forked. Exit 0, 24 checks / 0 misses, 0 SCRIPT ERROR. Receipt-lore: the probe's `_check` grew an optional fail-detail third arg (same shape the world probes use); InventoryService-keyed bags resolve through the documented register/pull pattern. GATES: probe exit 0 24/0, lint 36/0, full pipeline exit 0 / 102 passed / 0 failed / 0 SCRIPT ERROR. Next due: OpenHands' dialogue/quest lane stays clear; issue #19 remains open/cosmetic.
> **Last updated 2026-11-03 (money-hub world-building round):** THE SIGIL SINKS GOT A PHYSICAL HOME -- the Concord pillar shrine boots in Nexus Central's capitol plaza at bearing -95: village_props.gd gained the `concord_shrine` kind on CAPITOL_BATCH (dais + 5 m pillar + sky-cyan emissive TorusMesh sigil band, emission 1.2 + bronze capstone + OmniLight halo, deferred in-tree PropCollider.attach via lambda) and a CAPITOL_NPC_BATCH row (-95/+0.006) + zone_nexus_central roster entry spawn the CONCORD HERALD (data/npc/npc_concord_herald.tres NPCData, merchant_general.tscn scene, `npc_type` omitted -- not declared in npc_data.gd, orphaned dead data in old .tres files) whose offering ref data/npc_offerings/concord_pillar_vault.tres (NPCOffering -> PremiumShopService, panel premium, mirroring black_market_premium.tres) rides the EXISTING offering plumbing -- the "Sigil Vault" action menu + "[E] Open Sigil Vault" prompt mint themselves with zero service changes (verified action_menu.gd/npc_entity.gd seams). RECEIPT dev_temp/probes/concord_shrine_probe.gd (dev_temp only, NOT in runner DEFAULT_SET -- world-building precedent, no fleet-pack regen) exit 0 SHRINE-OK 14 passes / 0 misses: data doors (herald loads, offering ref, premium route, roster+batch rows), a REAL globe boot placement leg (ConcordSinkShrine node + herald entity carrying npc_data.id), and the factory body/glow laws (PropBody BoxShape pillar tall > 4.5, the band's emissive TorusMesh + the halo OmniLight found). NOISE VERDICT SETTLED by HEAD control stash cycles with the fixed probe: the intermittent boot SCRIPT ERRORs (sector_cache set_value/get_value, get_ticks_msec on null, "Nonexistent function '' in base 'Vector3'") appear IDENTICALLY at HEAD (same classes, 4 lines) -- pre-existing globe boot randomness, NOT this round; the probe gates on its own verdict only. probe_starter_village stale eliminations refreshed: the capitol prop family is 4 (ConcordSinkShrine joins ankh/moon gate/bout stones) and the capitol roster counts >= 8 incl. the herald. GATES: probe exit 0, lint 36/0, full pipeline exit 0 / 102 passed / 0 failed / 0 SCRIPT ERROR. Next due: issue #21 (stale character-panel stats), then OpenHands' dialogue/quest lane stays clear.
> **Last updated 2026-11-02 (sigil-sink round):** THE CONCORD SINK CATALOG SHIPPED -- the vault panel's far half: BEFORE this round a Concord Sigil could enter a wallet (SKUs through the webhook armor at `a571019`, the gamble's refund-fail books) but could not LEAVE for anything but a black market roll -- no honest OUT door existed, so the SKUs sold an open loop. core/services/sigil_sink_service.gd (the PremiumShopService dialect; static singleton(), NO autoload wiring) declares SEVEN real sinks priced against the processor ladder (sigil_100 = $4.99): FIVE steed deeds riding RideService's real persisted ownership book (data/mounts truth, VENDOR source only, Meadow Pacer 150 / Plains Runner 250 / Reef Glider 400 / Trench Wyrm 650 / Storm Lancer 900; the GM Skywarden's wyrd * is refused ONE GATE BEFORE the service's own fail-closed so the buyer never gets within a debit) + TWO new premium title editions in data/titles/ (title_pillarsworn.tres + title_deepseabaron.tres, UnlockMethod.PURCHASE -- the schema value existed at birth and now earns its grant leg; they equip through TitleService's real register/equip surface) at 200/500. THE BOOK LAW = the audit talks hold: GATE BEFORE BOOKS (unknown ids refuse BY NAME; already-owned reads the REAL books; exact-need affordability; QoS rate gate) then debit-once, grant-once, and a REFUSED GRANT LEG REFUNDS EVERY SIGIL (a refund that cannot land is a hard GL.error -- books never keep a sigil without the prize). GL.info audit line per sale; one sink_purchased signal with the panel as its consumer (no-void law honored). RECEIPT tests/test_sigil_sink_catalog.gd exit 0 six legs: catalog truth (no phantom ids, no GM price), unknown/wallet-less/broke refusals by name, exactly-150 Pacer into RideService.owns_mount + dupe refused without a second debit, exactly-200 Pillarsworn + REAL equip surface, the refund law on both legs via injected refusing doors on a FRESH instance (the transport-receipt seam: injectable resolvers, never product fakes), and the voice + panel render. PremiumShopUI grew the "Where sigils go" section (owned state rendered from the real books, disabled owned rows, hashed dedupe toasts). SCRIPT-MODE LAW EXTENDED IN EAR: TitleService has NO class_name -- bare static calls (TitleService.unlock(...)) do not compile in --script/--check-only context at ALL; route through the autoload NODE calling the instance impls the static facade wraps. Open lanes: OpenHands' play drivers (landed PR #20 as 315d607; dialogue/quest systems next), issue #21 (stale character-panel stats) folds into a pricing round. Next due: Concord money-hub world-building (the physical home of the sinks).
> **Last updated 2026-11-02 (PR-20 merge round):** OPENHANDS' PLAYTHROUGH DRIVER LANDED (repo PR #20, merge commit 315d607): a headless+rendered driver (tests/playthrough_driver.gd + node runner, node-runner law) that walks the REAL input pipeline on world_playable -- spawn -> F2 target a live wolf -> attack to death -> interact-collect the corpse -> equip wep_iron_sword -> blacksmith repair -> NPC menu -- asserting on LIVE nodes, plus the six bugs it surfaced: (1/2) equipment stats never applied to the player (parent read as typed Entity aborted the apply; bonus re-add had no inverse so re-equip stacked) -- duck-typed stat surface + idempotent deltas + Entity-parity get/set/add_stat on PlayerController; (3) currency-only loot rolls were dropped by the item-only gate; (4) the INFINITE-GOLD PICKUP EXPLOIT (a currency-only ground drop was never consumed on pay) -- consumed-on-pay + test_ground_loot regression; (5) the TargetFrame resolved its id as entity_id and HID ITSELF for the whole game -- id normalization + render-on-acquisition; (6) respawn crashed near NPCs without health_component and the dungeon portal registered a phantom "teleport" schema. Runner DEFAULT_SET is now 102 tests. GATES: pipeline exit 0 (102 passed / 0 failed / zero script errors), lint 36/0. PR #18 closed landed-not-merged (e1f49bc); OPEN: issue #19 (terrain worker-lane stderr resolution race, cosmetic) and issue #21 (character panel reads stale creation-time CharacterData instead of the live gear-adjusted player stats -- fold into the sigil-sink/pricing round). Next due: sigil-sink catalog.
> **Last updated 2026-11-02 (webhook transport round):** THE PAYMENT WEBHOOK TRANSPORT SHIPPED -- the processor's HTTP entry finally has an engine on the other side of the door (before this: `handle_webhook` consumed ZERO deliveries through any real burden -- the armor answered to silence, no GL audit line ever described a payload, and the SKUs sat behind a wall between customer and wallet). THE BRIDGE half (srv/webhook-bridge/, mirrors srv/redis-bridge/ exactly: main.py entry + server.py routes + backends.py inmemory/redis + its own stdlib test suite, port 8083): nginx routes PUBLIC /hooks/<channel> in BOTH http+https server blocks to 127.0.0.1:8083 (own hooks zone 5r/s burst 20, 64k body cap); the sidecar accepts the processor's POST (202 accept-first, 413 over cap rejected BEFORE storing, 503 queue saturated), stores the delivery VERBATIM (raw body bytes base64 -- never re-serialized; headers lowercased + hop-by-hop stripped + dupes ","-joined; the SIGNATURE HEADER TRAVELS untouched), and hands each delivery to the engine poller: GET /deliveries/next claims the oldest claimable (secret-free claim token, per-claim TTL default 120 s -- a dead poller's claim lapses and the delivery reopens, at-least-once transport law), POST /deliveries/<id>/ack records the engine's VERDICT (processed|refused|expired|error, detail <=256 ch; stale/mismatched claim -> 409, delivered-since -> 200 idempotent "already", unknown id -> 404), delivered records STAY as operator audit; GET /deliveries/<id> + /stats are the operator readout; GET /health. THE SECRET LAW: the bridge holds NO HMAC secret and verifies NOTHING -- transport, not armor; PAYMENT_WEBHOOK_SECRET stays in the ENGINE process env and the provider revalidates everything. THE ENGINE POLLER (game/core/economy/webhook_transport.gd, no class_name; booted by NetworkManager._boot_webhook_transport in the prod/server start path ONLY when WEBHOOK_BRIDGE_URL is in the env -- OFF is an honest boot state, clients and dev bots never poll): HTTPRequest legs poll /deliveries/next on a Timer (default 5 s, configure() seam, one request in flight via _busy), feeds the provider board's handle_webhook(RAW bytes, headers) -- the provider resolved through PremiumShopService's registry resolver (injectable resolver for script-mode receipts, runtime load() only, no parse-time preloads) -- and acks the verdict. THE ONCE LAW lives in the engine: a per-process ledger (_handled: delivery_id -> verdict) refuses to re-run the door for a resolved id; a redelivery re-acks the FIRST verdict; NOT call counting on the provider -- the book of record. EVERY deliver_once exit settles BEFORE it answers (ledger writes, then verdict travels: no re-entrant beat can double-run the door). REFUSALS ARE ANSWERS: a refused delivery still acks (a refusal that never acked would replay-wrap forever); verdicts: door complete->processed (order poll leg pays), refused->refused (the armor's own reason rides the record), cancelled->expired, wrong channel->refused unrouted (PAYMENT_WEBHOOK_PROVIDER env is the channel map), provider missing->refused no-provider; transport legs (poll/ack network) retry on the next tick fail-soft. The bridge Python suite (14 tests: FIFO + claim exclusivity, TTL lap-over, ack contract incl. already/unknown, id uniqueness, verbatim bytes round-trip; HTTP: health, the accept->next->ack happy path with signature-header-survives, 413, verdict allowlist, claim-mismatch 409, null views) AND the engine receipt tests/test_webhook_transport.gd (boot law OFF/ON, 5 s default + configure seam, signed-truth delivery routes the door EXACTLY once through the RAW-byte path and pays 100 through the poll leg into a mounted wallet, redelivery re-answers from the ledger, unsigned dies AND settles so a replay cannot wedge, wrong-channel/no-provider refuse by name and settle, a mixed-case signature header survives the normalization and still honors the armor) both exit 0. entrypoint.sh starts the bridge in TEST mode (with its unit suite added to the CI bridge gauntlet) and PROD mode (127.0.0.1:8083, first free port after noaa 8082). DEPLOY.md services table + health list updated. Next due: sigil-sink catalog + OpenHands' staging PRs (gameplay driver A, crafting leg B, perf honesty C).
> **Last updated 2026-11-02 (PR-18 verified round):** OPENHANDS' ANALYSIS ROUND (PR #18, branch fix/terrain-stream-probe-surface) was VERIFIED IN THIS WORKTREE AND LANDED ON MAIN: three REAL product bugs + five stale test assertions -- (1) `cosmic_rng.stir_from_cosmic` read `total_chaos` as a property but it is an ACCESSOR METHOD (CosmicEntropy.total_chaos()), so every stir threw "Nonexistent 'int' constructor" and silently DROPPED the chaos entropy word -- two skies with equal kp but different accumulated chaos produced IDENTICAL streams; now calls the accessor guarded by has_method, and the co-located test_cosmic_rng.gd mirror call is fixed too (the audit's seam: a wrong read that QUITS quietly had made an entropy input decorative).

> The rest of the round: (2) inventory_service.get_inventory returned FREED InventoryComponent entries as a typed value -- "previously freed instance" at every consumer; now is_instance_valid=false drops the stale row and returns null (absent keys erase harmlessly). (3) hud_integrator._bind_player_wallet_feedback read player.gold_changed unconditionally -- the globe body (GlobeWorldPlayer) declares no gold/gold_changed (its purse is the mounted component), so every globe boot logged "Invalid access to property or key 'gold_changed'" and the node-wallet leg never bound; has_signal guards on BOTH legs. (4) the runner's DEFAULT_SET/LONG_TESTS were word-split unquoted with comment lines -- comment words became phantom test names and one empty token made grep -qx match EVERY line (long timeout for all); the lists are stripped of comments/blanks before iterating. (5-8) STALE ASSERTIONS against the shipped world: the four probe_stream_continent shards pinned get_surface_count() == 2 but the streamer legitimately emits 3 (ground+skirt+hydrology water; the >=2 form probe_terrain_planet already uses); probe_thermals pinned 7 updrafts while data/thermals grew to 10 (8 thermal + 2 launcher); probe_planet_rebase_20km read streaming face counts before the async derives drained (now drains pending_derive first, the continent-shard law); globe_driver_runner pinned a fixed ride-height from the 100 m prototype era, misreading a correctly seated 20 km world body (28 m spawn plateau, off_shell_29.52) -- now asks the body is_glued(2.0) like probe_planet_walk_20km. VERIFICATION GATES in this sandbox on the applied branch: full pipeline `sh ./scripts/godot_test_runner.sh` exit 0, 101 passed / 0 failed / 0 phantom / 0 SCRIPT ERROR (the previous restore's continent/crafting/thermal probe fails are GONE -- they were the code bugs above, not import-cache drift as once suspected); lint 36/0; naming exit 0; receipts cosmic 8 PASS legs, thermals 10-PASS form, gamble 9 legs, premium 6 legs all exit 0; parse checks on every touched file exit 0 (inventory/hud files check-ONLY "Identifier not found" is the documented script-mode autoload artifact, identical pre/post-patch). NOTE: the earlier 'partial .godot import cache' hypothesis for these probe failures is RETIRED -- PR #18's code fixes account for every failure. Next due: old transport (webhook HTTP entry) + sigil-sink catalog.
> **Last updated 2026-11-02 (economy audit round):** THE AUDIT SWEEP ACROSS THE FRESH ECONOMY SURFACES (black market gamble + webhook armor + premium seam + Sigil Vault panel) FIXED FOUR BOOK-SAFETY BUGS AND TIGHTENED THE ARMOR. (1) THE QUANTITY TRUTH: the gamble drew its QUANTITY REPORT after the GRANT -- a min1/max3 band could land x1 in the bag and say x3 in the toast; the band is now rolled ONCE inside the draw (`_draw_shape`) and grant/report/audit/toast all read that single number, with corrupt band data (min > max) clamp-refused instead of taken through randi_range (a bad range aborts a function -- past the debit that would strand sigils without the refund leg). (2) NEVER BURY A PAID ORDER: the service poll CLOSED the order BEFORE the grant -- a failed grant (wallet unmounted at the moment of truth) erased a genuinely-paid checkout with zero recourse; now grant-before-close: a failed grant leaves the order OPEN and the next poll re-attempts (providers keep reporting complete for a paid order); the residual crash window between grant and close errs CREDIT-side. (3) CANCEL NEVER BURIES MONEY: provider.cancel flipped a COMPLETED (paid) order to cancelled -- webhook AND manual both; a buyer could cancel a paid checkout out from under itself; both providers now REFUSE cancelling a completed order and the service honors the refusal (returns it, keeps the order open) so the poll leg pays instead. (4) PROVIDER HALF OF THE REBOOT LAW: the webhook provider's own pending-vs-paid book lived in RAM, so a rebooted process refused a genuinely-paid webhook; order records now ride the DictStore KV door (`premium:webhookorder:` prefix -- hydrate in _init, written at birth and on every state move; completed/cancelled records STAY so duplicate deliveries stay honestly refused after a reboot) and begin ids loop-until-unique (a collision could silently overwrite a standing order). TIGHTENED: the HMAC chain no longer SKIPS on an empty derived signature (refuses, fail closed); sigils are priced INTO the open order at begin time (a later catalog edit can never change what a paid order grants); panel toast dedupe keys carry the message hash (the fixed key let the 5s window swallow the next honest answer) and a dead `ok` var left the vault. Receipt legs added: cancel-refused paid order pays through poll (exactly 100), grant failure keeps the order open and the retry pays exactly 100, a fresh provider refuses duplicate delivery after reboot. Parse-law note AGAIN: `max()` is a Variant builtin -- `var lo := max(...)` is a PARSE ERROR under warnings-as-errors (`var lo: int = max(...)`). Pipeline note: the full runner in this restored sandbox exits 1 on PRE-EXISTING probe failures (stream continents a-d crash cascade, crafting, thermals prefix taxonomy -- world/streamer derive chain, probes age Oct 18, reproduced at the pushed HEAD with this round stashed; suspected partial `.godot` import cache after the restore) -- the touched surfaces' receipts (gamble 9 legs ALL-OK, premium 6 legs ALL-OK, economy) ran INSIDE that pipeline green. Gates: gamble receipt exit 9 legs, premium receipt exit 0, lint 36/0, naming exit 0.
> **Last updated 2026-11-01 (black market gamble round):** THE FIXER IS A GAMBLER NOW. THE DEEP ROLLS: BlackMarketService (the PremiumShopService singleton dialect) is the gamble engine -- roll_deep(player under their purse, roll_id) debits HONEST sigils from the ONE purse and lands ONE weighted draw out of a REAL LootTable; the pools are data/loot_tables/loot_black_market_tide.tres (3 sigils, the shallow wash) + loot_black_market_depths.tres (12 sigils, the pressure where the rare gear dreams) -- the same LootTable schema the wolves use, so as higher-tier weapons/armors arrive the pools grow by APPENDING ENTRIES (documented shape, no code change; the receipt refuses phantom SKUs). Two tiers with rarity_boost (the depths pays UP); draw math is pure server truth -- the panel/client sends only a roll_id, never weights, item ids or amounts; the prize grant rides inv.add_item via DataService truth and a FAILED grant REFUNDS the sigils (refund-fail is a hard GL.error -- the books never keep a sigil without paying the prize); every completed roll emits roll_granted + GL.info audit line. GATES BEFORE BOOKS: no wallet / broke (names the exact need) / unknown tier / QoS rate_limit("black_market_roll") BEFORE any debit leg moves. THE WEBHOOK ARMOR (defense in depth, core/economy/webhook_payment_provider.gd): the hosted-checkout adapter every real processor slot inherits -- (1) secret zero-knowledge: HMAC secret read from env PAYMENT_WEBHOOK_SECRET on every verification, never in the repo, and an EMPTY secret refuses everything (fail closed); (2) HMAC-SHA256 over the RAW payload bytes, signature envelope in the x-synmergia-signature header ("t=<ts>,v1=<hex>"); (3) freshness -- 5-minute signed-timestamp window kills transcript replay; (4) order binding -- the payload's purchase_id must name a PENDING order the provider itself opened for that buyer; the caller never supplies player identity or amounts; (5) server-side accounting -- sigils come from the provider's own catalog, never the payload; (6) idempotence -- an order completes ONCE, duplicates report already-processed honestly. The transport must call handle_webhook(RAW bytes, headers) once per delivery; the SERVICE grant then re-validates kind/sigils itself, so even a compromised processor truth cannot inflate the purse. THREE HOSTED SKUs ride the provider (100/280/650 sigil packs). REBOOT LAW: PremiumShopService open orders now ride the DictStore KV door ("premium:order:" prefix, chat-book pattern) -- hydrate in _init, persist on open, erase on close, so a checkout mid-flight survives a process restart and can still be fulfilled honestly after; adapters are re-registered at boot (plugins live at boot, not in the KV). THE PANEL: PremiumShopUI grew the Deep Rolls section under the SKU rows (roll rows with cost + pool description tooltips, one Roll button per tier, roll results toast through the NotificationService CUSTOM lane, refresh rides the service's own roll_granted). Receipt tests/test_black_market_gamble.gd exit 0 six legs (pools real/no phantom SKUs, gate refusals by name, 100 sigils in through the honest seam then the golden pull pays one real item and debits exactly 3, rate gate leg, webhook armor chain unsigned/tampered/stale/foreign die + signed-truth grants 280 exactly once + dupes refused + closed polls none, reboot hydrate/erase round-trip). Receipt-lore: a fresh service instance builds its own provider board and must RE-register adapters (the receipt does this before its checkout -- which is also what a rebooted process does). parse-law notes: extends by RES path for the provider chain; var limit: int = max(...) because max() is a untyped builtin (inference from Variant is a parse ERROR under warnings-as-errors); DictStore all_keys/get_value/erase is the KV door. Gates: pipeline exit 0 zero script errors, lint 36/0, naming 25/0, all receipts exit 0.
> **Last updated 2026-11-01 (true-void survivors round):** THE TRUE-VOID LIST CLOSED. THE THREAT SENSE shipped as the enemy/threat-telemetry consumer: hud_integrator._bind_enemy_threat_sense (deferred in _connect_all, once-guarded) joins SpawnService.enemy_spawned and, per spawned enemy, binds its AggroComponent legs -- target_changed rows 'The Wolf turns its attention on you.' on a flip ONTO the local player and 'You slip out of the Wolf's attention.' off, threat_overflow (its FIRST HONEST EMIT, at AggroComponent.add_threat's clamp leg, exactly once when a source's threat first crosses max_threat_per_target) rows 'Your threat on the X maxes out.' (only when the source IS the local player), out_of_combat rows 'The X forgets the fight and breaks off.' through a small _enemy_focused_local book; stranger flips stay silent. threat_changed was REMOVED (decl+3 emits: every leg it covered is a target flip or an overflow; the per-hit number spoke to zero listeners for life). THE ZONE TRIO got its consumer: InstanceService._ready subscribes ZoneManager.instance_created/instance_destroyed -> _rebuild_arena_registry -- the instanced-zone registry was rebuilt ONCE at boot while ZoneManager emitted into silence, so live creates left is_instanced_zone stale until the next boot; the subscription fixes the staleness bug and consumes both emits; instance_contract_changed was REMOVED (a zone contract is boot-static -- gravity/capacity/deadline read ZoneData with NO mutate path; re-declare WITH emit+consumer if hot mutation lands). REMOVED WITH CAUSES: SpawnService.npc_spawned (entity_spawned is the one spawn voice; minimap impressions ride it), NotificationService.notification_queued (queue legs already speak via notification_sent + history; the silent pop-oldest OVERFLOW now GameLog.warns), AgentConnector.observation_ready (the POST leg already lives in send_observation; no consumer ever existed). DRIVE-BY: the connector-native shadow law -- AgentConnector.connect/disconnect/is_connected, VantConnector + McpConnector connect/disconnect, and AgentAction.to_string() all overrode NATIVE Object methods (warnings treated as errors only surfaced when a receipt compiled the chain); renamed to connect_agent/disconnect_agent/is_agent_connected (+ 4 internal call legs, ConnectorService's two callers) and the un-called to_string debug-helper deleted. Receipt tests/test_true_void_survivors.gd exit 0 five legs (sense rows + stranger silence, overflow exactly-once at first cap crossing, removals hold incl. has_signal probes on four autoload scripts, fight-broken book leg, live zone registry rebuild; zero SCRIPT ERROR -- the chain compiles clean now). Receipt-lore: probe enemies need the tiny dynamic-script shape (a bare Node gains NO 'aggro_component' from set()). Gates: pipeline exit 0 zero script errors, lint 36/0, naming 25/0, all receipts exit 0.
> **Last updated 2026-11-01 (premium wallet round):** THE SPLIT-WALLET DEBT DIED AND THE REAL MONEY SEAM WAS BORN. THE ONE PURSE: InventoryComponent is THE authoritative per-player wallet -- its get_currency_amount/add_currency/remove_currency now understand the DEFAULT wallet ("" and "currency_gold" both route through the honest gold legs, others ride the _currencies ledger with the catalog gate + caps -- the split is storage, never semantics); PlayerController.gold became a SYNCED MIRROR (a property setter converts EVERY direct write -- progress restores, horde shares, dwelling field-math -- into REAL deltas through the purse, so nothing pays silently; add_gold delegates to the mounted component and the node stays silent; standalone bodies keep their own voice; the _ready adoption step resyncs the mirror from a boot-restored bag and connects the purse's gold_changed to the mirror). The hud binder keeps the node-seed leg for manual node emits (dwelling) and the component delta leg; the NEW leg binds comp.currency_changed into +N/-N <Currency display_name> rows (no seeding needed: restores never emit, every emit is a real movement; gold and zero-deltas stay quiet). PREMIUM CURRENCY: CurrencyKind.PREMIUM (kind 5) + data/currencies/currency_concord_sigil.tres (Concord Sigil, gold_per_unit 5000, soulbound, NEVER convertible -- it only enters a wallet through the payment seam). THE PAYMENT PLUGIN SEAM (core/economy/): PaymentProvider (RefCounted base; get_catalog/begin_purchase/poll_purchase/cancel; statuses pending/complete/cancelled/refused), ManualPaymentProvider (REAL checkout from the buyer side; money never moves automatically -- fulfill_purchase() is the operator seam a Stripe/Steam adapter replaces; statuses are read, never invented), PaymentProviderRegistry (board by id; re-registering an id REPLACES it = THE swap law; _init seeds the manual default), all owned by PremiumShopService.registry() so no static-call/global-cache parse quirks ever bite. PremiumShopService (singleton dialect like VendorService): renders the board catalog, opens/cancels orders, and grants sigils ONLY on a provider-reported complete through inv.add_currency(currency_concord_sigil, N) -- the ONE grant leg, validated against DataService's kind, closed once, poll after close honestly 'none'. THE UNDERDECK FIXER: npc_black_market_fixer.tres lives in Nexus Central's strand frame (globe_world CAPITOL_NPC_BATCH + zone roster), sells the ledger goods (acc_ring_first_light + acc_cloak_wanderer priced in SIGILS, item_ancient_coin/strait_charm/skiff_ticket in JUNKER SCRIPT) -- VendorService learned per-entry currency: catalog rows carry "currency" (_entry_currency scans the catalog_items entry), buy_item checks/affords/pays through the unified ledger with honest per-currency refuse messages; ShopUI quotes them ("40 Junker Scrip each (you have N, total M)"). THE PREMIUM VAULT PANEL: PremiumShopUI (UIPanel law, MenuManager "premium" row, service gate on PremiumShopService + walk-away close), opened from the fixer's action menu "Sigil Vault" or interact prompt [E] Open Sigil Vault; shows the live sigil balance off the ONE purse, the processor name, SKU rows, pending order state + cancel. THE BAG LEDGER STRIP: every held non-gold currency renders live in the bag header (comp.get_currency_ids through DataService display names) and the blacksmith/gold labels stay on the purse. Receipt tests/test_premium_shop_loop.gd exit 0 six legs (currency voice rows incl. the double-speak guard, ONE purse read/route/refuse, seam pending/refuse/operator-truth, one-time grant + closed order, sigil grant row, panel real-open lifecycle). Receipt-lore: receipt preloads compile BEFORE autoloads register -- runtime load() in the body (the combat-sense law). Gates: pipeline exit 0 zero script errors, lint 36/0, naming 25/0, premium + all prior receipts exit 0.
> **Last updated 2026-11-01 (economy round):** THE ECONOMY TRUE-VOID CLUSTER WAS A CENSUS ARTIFACT -- the real money machinery was never void, it was TWIN-VOICED AND INVISIBLE: two honest wallets move the local player's gold (the NODE wallet, PlayerController.gold, paid by kill rewards/ground loot/horde/dwellings; the COMPONENT wallet, the mounted InventoryComponent._gold, spent by vendors/blacksmith/vault/ferry/transfers) and each emitted gold_changed to essentially one consumer (blacksmith_ui). PlayerManager.gold stays the silent persistence mirror (documented; unchanged). SHIPPED THE WALLET LOOP: hud_integrator._bind_player_wallet_feedback (deferred, local-player seam, per-leg guards) binds BOTH wallets into CombatLog rows -- node wallet speaks in paid deltas with seen-total seeding (hydration re-emits stay quiet), component wallet rides its signed deltas (+N loot rows / -N system rows); the NEW item_equipped signal (item, slot_name: String, equipped: bool) earns its emit on the REAL endpoints (equip_item/unequip_item; clear_equipment_slot = full-loot strips are unequips the player sees), landing "You equip Iron Sword (off_hand)." rows; slot names derive from Item.EquipSlot.keys() (wep_iron_sword.tres really declares equip_slot = 8 = off_hand -- flagged, not changed). The open bag went money-live: InventoryUI's Gold label was stale through every spend; DRIVE-BY CAUGHT: inventory_ui._setup_header was BORN ORPHANED with zero callers -- the bag shipped with no title, NO close X, and the gold total never rendered; the call now sits at the end of _setup_panel. Receipt tests/test_economy_wallet_rows.gd exit 0 six legs (binder no-crash, dual-wallet seed through the local-player seam, hydration-quiet + +45 delta rows, vendor +50/-25 rows, equip/unequip/strip rows via wep_iron_sword through the REAL bag, open-bag label follows the wallet). Split-wallet debt persists by design (node gold and component gold are separate sums until a unification decision; rows are per-wallet honest, no fake unified display). The capture-layer names gold_gained/gold_spent/xp_gained/item_equipped remain DEAD in core/events/{entity,inventory}_events (hub-referenced diagnostics only). Script-mode lore: a bare Node gains NO properties from set() -- probe wallets declare them in a tiny dynamic script (signal + gold + inventory_component). Gates: pipeline exit 0 zero script errors, lint 36/0, naming 25/0, economy + combat-sense + login + map-ping + fresh-kit + ignore-book + channel-mute receipts all exit 0.
> **Last updated 2026-11-01 (combat-sense round):** A FRESH CENSUS (598 declared / 234 OK / 282 regex-VOID / 82 DEAD) PLUS A TRUE-VOID SCAN (265 names mention NOTHING beyond decl(+emit)) -- the connect regex is blind to name-keyed UI connect maps (leader_changed: party + guild UIs already consume it via map keys) so census VOID overcounts; the true-void survivors are the real wallpaper. SHIPPED THE CAST-SENSE LOOP: the local player's CombatComponent lifecycle (cast_started/cast_finished/channel_ended/combat_entered/combat_exited) emitted zero-listener since birth; hud_integrator._bind_player_combat_feedback (deferred, local_player seam, no-crash when absent) binds the five signals into CombatLog System-family rows ("You begin casting X" / "You finish casting X" / "You stop channeling X (interrupted)" / "You have entered/left combat"); player-local on purpose (enemies already surface via skill_hit/skill_resolved). TWO WALLS DEMOLISHED by the duplicate-voice law (a second announce lane with zero consumers only repeats the working one): chapter_recorded removed from ActsService (_announce_chapter already notifies; the Chronicle re-reads on open) and boss_spawned removed from SpawnService (the world-boss arrival already rides NotificationService's bridge over EventHub.entity_spawned -- metadata notification_enabled + scopes, empty scope defaults SERVER-WIDE on the spawn path). DRIVE-BY FIX: PlayerManager.set_local_player(null) crashed on the display-name duck-read -- clearing the slot is a legal state, guarded. Receipt tests/test_combat_sense_loop.gd exit 0 (binder no-op honest, lifecycle-row truth through the entries, the entity_spawned announce bridge proven connected). Remaining true-void clusters: economy gold/xp catalog ghosts, enemy/threat combat telemetry, zone instance trio, npc_spawned (entity_spawned covers it), observation_ready, instance_contract_changed, notification_queued. Gates: pipeline exit 0 zero script errors, lint 36/0, naming 25/0, combat-sense + login + map-ping + fresh-kit + ignore-book + channel-mute + daily + acts receipts all exit 0.
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

