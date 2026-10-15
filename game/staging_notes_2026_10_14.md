# Staging cut decision notes — 2026-10-14

## 0) Current workspace files on this cut

- `game/data/dialogues/blacksmith_village_intro.tres`
- `game/data/quests/quest_intro_core_npcs.tres`
- `game/data/npc/npc_blacksmith_village.tres`

---

## 1) Interact seam: action-menu path vs dedicated proximity button

Two viable seams, and both can keep the same range-cancel behavior:

- **Existing action-menu path** — `ActionMenu` already knows how to open a context menu for an NPC and filter the `talk` item by the NPC's dialogue offering. This is the smallest seam: it reuses the current right-click / long-press affordance and the existing `action_selected("talk", target_id)` flow.
- **Dedicated proximity / interact button on the NPC** — a separate affordance that appears when the player is in range of an interactable NPC. This is better when you want an explicit "press interact near this thing" read, especially for first-time players who may not yet know where to point and click.

Recommended first cut: **keep the action menu as the command path, but drive it from a proximity state**. That gives you an explicit "something is here" read without inventing a second interaction channel. The range-cancel behavior is the same either way: the moment the player leaves the interaction radius, the prompt and any auto-open behavior go away.

So the seam is not "menu vs button" so much as "menu as the action, proximity as the invitation."

## 2) Marker / prompt interface

You want one marker interface that can express at least:

- **available** — something can start here: first dialogue, first quest, first teaching, first meaningful NPC introduction.
- **in_progress** — the same place still matters, but now it is "continue / next step" rather than "first time."

A single reused marker is the right call. The marker should be data-driven from the same source of truth that decides whether the NPC/site is interesting to this player, so the symbol is just a presentation of that state. Different symbol / palette per state, same placement and same update logic.

For the staging cut, the important part is that the marker is not a separate ad hoc UI layer with its own rules. It should read from the same NPC interest / quest-tenant state that gates the dialogue seam, and it should clear when the player leaves range for the same reason the prompt clears.

## 3) Chaining: blacksmith onboarding vs a longer quest/achievement-gated flow

You already want chaining built around a quest rather than a one-off blacksmith intro. The better first case is the larger "meet the core NPCs and get a handle on what they do" shape, with the blacksmith as one essential node inside it rather than the whole thing.

That means:

- The blacksmith dialogue is a **server-critical, player-individual** step inside a broader quest-shaped walkthrough.
- The quest/achievement framing is what makes it chainable: introductions, first-use guidance, and recap/nudge moments can all attach to progress without turning every NPC into its own one-off tutorial.

So: yes, start with the blacksmith as the first real Concord dialogue, but do it inside a quest-shaped onboarding spine, not as a standalone tutorial bubble.

## 4) Persistence: existing systems, extensions, and migrations

Use only the existing persistence/state systems. Do not introduce a new side store or a new persistence concept for this staging cut.

Acceptable:

- Extending the existing frame/state schema where needed.
- Adding a migrations file if new fields are required.
- Keeping the new "what player state is relevant here" logic inside the existing persistence/state path.

Not acceptable for this cut:

- A separate bespoke persistence or "dialogue state" store.
- Inventing a new system just to remember that a player met an NPC or started a Concord conversation.

The current guidance is "everything you need is in the game already." So the move is to model staging-relevant player state as an extension of existing state, and to let the marker/dialogue seam read from that.

## 5) Weather-aware blacksmith dialogue: shared triggers + separated player progress

The right first shape is the blended one, but with a sharp separation inside it:

- **World/shared triggers** can affect any player — for example, a weather- or cosmic-driven condition that makes the blacksmith conversation particularly relevant.
- **Player-progress path** is individual and persists per player — onboarding stage, what they have already been told, what they have already done.

Concord conversations should read both. The shared side decides "why this matters right now in the world." The player-progress side decides "what to actually say to this player given where they are."

Even though the blacksmith is critical to the server, the dialogue experience is still individual to the player. That is the third option you flagged, and it is the correct one: one Concord conversation that can branch on player state while still being aware of shared world state.

---

## Acceptance criteria for the first staging cut

- There is a proximity-based "something here" read near the blacksmith NPC, with the same range-cancel behavior as the rest of the interaction model.
- One marker/prompt interface is reused for both "available" and "in progress" states, with visually distinct symbols.
- The blacksmith gets a first Concord dialogue built inside a quest-shaped onboarding flow, not as an isolated tutorial.
- Weather/shared triggers can make the conversation more relevant, but the dialogue is still personalized by player progress.
- No new persistence system is introduced; new needs are handled through existing state plus a migration file if needed.

## 6) Files on this pass

- `game/data/dialogues/blacksmith_village_intro.tres` — created Concord dialogue resource with staging-authored node/choice/branch content.
- `game/data/quests/quest_intro_core_npcs.tres` — created valid `QuestData` quest introducing the core NPC onboarding spine (blacksmith is one node).
- `game/data/npc/npc_blacksmith_village.tres` — edited NPC includes the quest and dialogue seam.
- `game/staging_notes_2026_10_14.md` — updated with staging cut notes.

Files kept in place / not authored this pass:

- `game/core/services/dialog_service.gd`
- `game/core/services/weather_event_service.gd`
- `game/core/schemas/npc_offering.gd`
- `game/core/schemas/sign_profile.gd`
- `game/ui/components/action_menu.gd`
- `game/ui/components/dialog_ui.gd`

Next build steps (not part of this cut):

- Proximity/marker seam + range-cancel behavior through existing game patterns.
- Persistence/migration files for any new player state needed by staging.
- Wider core NPC dialogue + quest wiring (skill academy, bank, general store, etc.).

## 8) Turn 15: the starting-vista pass (world geography + town function)

The owner's vista law: "the starting village should be on a grassy hillside overlooking the Capitol city and coastline (like a km away); turn around and a mountain range stands kms off. Village has all NPCs + ankh + moon gate + duel/elim/tdm/royale gate; the capitol has the tall monolith, the ferry system, and the same prop family; a road connects them."

What was authored this pass:

- **THE BOOT COVE** (`terrain_gen.gd`): an authored sea notch + shelf-city strand cut into the homeland plain on the 90 deg (east) off-boot bearing. The city bench floors at sea+22 over a 0.043..0.055 rad ring (~0.86..1.1 km from the boot), the ramp widens into the bay outside the ring, and the shore apron law stands down inside the cove window so the bay stays water. Boot-eye horizon math: on the flats the eye clears ~654 m, so the Monolith skyline is visible from the spawn plaza across the water.
- **THE VILLAGE HILLSIDE** (`SPAWN_HEIGHT` retune): the boot plaza benches to 28 m so the starter village sits above the capitol strand and the cove water -- the "grassy hillside overlooking" read. The hillside lift is one constant (`VILLAGE_HILLSIDE_LIFT`); all boot laws ride it.
- **The road still walks** harbor -> capitol; the road law re-derives to the new cove strand (probe w=1.00 at the plaza).
- **THE TOWN PROPS** (`entities/village_props.gd`, new): the ankh shrine (Ankh schema node, shared type), the moon gate (MoonGate entity, sealed-by-entry-law), and the bout queue stones (three ArenaGateway arch stones: coliseum = duel/elimination, sandpit = team deathmatch, royale valley = the 30-fighter royale) -- village AND capitol both carry the family. The bout stones ride `queue_mode` (the S11 law: stones are the lobby's doors).
- **THE CAPITOL QUARTERS + PIER** (`capitol_monolith.gd`): four placeholder buildings around the monolith plaza plus a 6-plank timber pier seaward (the ferry's city end; moored landing pad with posts). The harbor bay state stays with the ferry frame's city pin.
- **THE TOWN ROSTERS** (`globe_world.gd`): the village four (elder, smithy, merchant, herbalist) spawn around the spawn plaza frame; the capitol two (armory, skill academy) spawn in the strand frame. Following the underworld's own-frame law: the owning globe spawns its NPCs, spawns are reparented under the town root, and zone bookkeeping rides NPCData's own zone_id (quest TALK credit stays lawful). The planar `spawn_all_offering_npcs` path never boots on the globe, so this is the same seam the underworld already legitimized.
- **Probes updated**: probe_starter_village (8 authored node pins + roster presence), probe_world_shape_ground (the boot-cove window exemption inside the W2 plateau cap, mirroring the law's constants).

Measured on the live seed: capitol strand at bearing 90 deg / 0.98 km, bench sea+22, cove water from 1.1 to ~14 km of the strand read, ring range peaks 247--560 m at 3--14 km on all bearings, village plaza 28 m. probe_starter_village ALL PASS; probe_world_shape_ground 0 failures; terrain climate probe ALL PASS; lint suite 36/36.

Known pre-existing (repro on a clean tree, NOT from this pass): 2 planet-probe lod streaming failures and 4 lattice window/epoch failures in `--headless` script mode.

Next build steps (not part of this cut): the capitol ferry needs the route's second gateway pinned to the cove strand for the harbor-bay state (veh_haven_ferry still routes village dock <-> waypoint_nexus_central); the monolith's future function; the ankh bind charm + moon gate mystery states ride their entity laws untouched.

Persistence, staging-disjoint, tamper-evidence, flow-equivalence, and backpressure notes are still in scope for later passes, but they are not part of the file set for the current cut.

---

## Acceptance criteria for the notes-for-later-passes

- The staging notes record remaining requirements without inventing new files now.
- The later passes are not started until the current file set is verified.

---

## 9) Turn 16: the town function pass (rosters completed + lobby Royale + probe repairs)

The owner's asks: the skill academy + bank NPCs in BOTH towns, the matchmaking/LFP panel status, and the limitation cleanup.

- **NPC plumbing already existed** (action-menu filter by `includes[]`, `bank_vault` + `skill_academy` NPCOfferings, the bank menu opening through `MenuManager.open_menu("bank")`); the TOWN DATA was the gap.
- **Banker NPCs** created: `npc_banker_village.tres` (Village Banker, zone_village_center) and `npc_banker_capital.tres` (Concord Banker, zone_nexus_central) -- both reference the existing `bank_vault` offering.
- **Skill academy in the village** created: `npc_skill_academy_village.tres` (Warden Trainer, zone_village_center, the `skill_academy` service offering; the capital's Master Trainer already stood in the strand batch). Both town batches in globe_world now carry the full rosters: village = elder, smithy, merchant, herbalist, banker, trainer; capitol = armory, skill academy, banker.
- **THE MATCHMAKING PANEL EXISTS**: `ui/components/lobby_ui.gd` is the one-panel/four-tab law (Bouts = queue zone + fill-to-parity + live feed; Duels = the 60 s challenge handshake + rivals list; LFG = open-world crew posts; People = friends presence + consent actions). The gap was the ZONE LIST: `BOUT_ZONES` lacked the Royale entry. Added `zone_royale_valley` ("The Sundered Valley (Royale)") -- queueing, duels, and assembly read the same list, so adding the constant wired all three tabs.
- **PROBE REPAIRS (the pre-existing failures)**:
  - `probe_world_lattice.gd` (was 7 fails -> PASSED, 109 checks): the probe predated the 2-hours-sky-day compression law -- overrides were multiplied by 86400 (real seconds) while `sky_epoch_days()` divides by `SKY_DAY_SECONDS` (7200), so every window check time-traveled to the WRONG sky. The probe now pins the actual unit law (`svc.SKY_DAY_SECONDS`) in both the clock and window sections, and the "one clock" checks assert both answers decode to the SAME override unix (the two clocks disagree only in unit scale, by design).
  - `probe_terrain_planet.gd` (was 2 fails -> PASSED, 39 checks): the skirt + hot-swap pins demanded exactly 2 mesh surfaces, but the v3 hydrology water sheet adds surface 2 on wet patches (louder now that the boot cove sits inside a streamed face). The pins read >= 2 -- terrain + skirt are the always-surface pair, water is the optional third.
- **Verification** (exit-captured): probe_starter_village ALL PASS (exit 0), probe_world_lattice PASSED (109, exit 0), probe_terrain_planet PASSED (39, exit 0), probe_world_shape_ground 0 failures (exit 0), probe_terrain_climate ALL PASS, probe_ferry PASSED (34 checks), lint suite 36/36 (exit 0).

Remaining known limitation: the ferry route's second gateway still points at the old nexus pin (see sec. 8).
