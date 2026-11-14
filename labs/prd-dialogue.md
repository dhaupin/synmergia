# Synmergia — Dialogue System (Design Bible + Engineering Map)

> **STATUS 2026-11-14 (labs fiction pass).** PARTLY IMPLEMENTED:
> `game/core/services/dialog_service.gd` exists and 20 dialogue resources
> ship. Sections describing UI, branching modes or multi-speaker scenes beyond
> that are design, not shipped behaviour.

> **Status:** CANON for dialogue design and the law for how dialogue chains.
> Companion to `labs/prd-story.md` (world bible — read that first),
> `labs/prd-quests.md` (quest engine map; TALK bridge lives there),
> `labs/story-voice-concord.md` + `labs/story-dialogue-creative-voice.md`
> (voice registers, labs-only). When dialogue copy contradicts prd-story.md,
> prd-story.md wins.
>
> 2026-10-14. Written from the staging-branch audit: what actually landed
> (quest_intro_core_npcs.tres + blacksmith_village_intro.tres +
> npc_blacksmith_village.tres includes) and the gaps found by reading the
> engine end-to-end (action execution never wired; dialogue UI never calls
> it; chaining is half-planned). This document reconstructs the chat plan
> into a system the engine can support.

---

## 1. Philosophy: dialogue is the world's second verb

Quests are the world's largest verb (**wake things**). Dialogue is the
daily-size verb: **every NPC is a door the player can open**. A dialogue
tree that ends in "..." with no state change is a tax on attention. Every
meaningful conversation must answer one of:

- **What did the world just do?** (shared state talking: weather, act
  progression, the woken-state scoreboard)
- **What has this player done / not done?** (player-progress talking:
  first meeting, repeat visits, in-flight quests)
- **What can this player do next?** (chaining: a choice, quest offer,
  service hand-off, or route to another NPC)

If a node answers none of the three, cut it or merge it upward. Nodes
cost maker attention and player attention both.

### The honesty law (restated for dialogue)

The world keeps score of what is real. Dialogue must not promise a
mechanic. Every branch key the tree *can* read must be a real state the
engine *does* read (sec. 4); every branch key the tree *cannot* read yet
must not be implied in copy. `labs/story-dialogue-creative-voice.md`
"Honest flags" is the creative-side restatement of this.

---

## 2. What actually exists (engine ground truth, 2026-10-14)

Wired and real:

- `DialogueData` schema (`game/core/schemas/dialogue_data.gd`): nodes +
  choices as Dictionary arrays (.tres-safe), `DialogActionType` enum
  (18 actions), `get_node_action` / `get_choice_action` helpers.
- `DialogService` (autoload): scans `res://data/dialogues/*.tres`,
  `start_dialogue/advance/select_choice`, BBCode X-SS escaping,
  `execute_action(action_type, action_data, player_id)` — a real
  dispatcher over the service door (quests, shop, vault, waypoint,
  inventory, currency, titles, skills).
- `DialogUI` (UiPanel subclass): portrait row, speaker, RichTextLabel,
  choice buttons, continue button, distance auto-close (5m default),
  repair-a11y naming ("Say: <reply>").
- TALK quest bridge: `QuestService` subscribes to
  `DialogService.dialogue_ended` and credits in-progress TALK
  objectives by npc_ id verbatim (single form, per prd-quests.md sec. 5).
- NPCEntity `_dispatch_inline_offering` already starts dialogue from
  `includes` — both inline `{type:"dialogue", dialogue_id}` and
  offering-resource `{type:"dialogue"}` shapes.
- Multi-dialogue-vocabulary exists in the data: `npc_data.gd
  get_dialogue_id()` returns the FIRST dialogue include; 9 NPC .tres
  under data/npc; starter-village quality bar set by
  npc_blacksmith_village.tres on staging.

Real but **wired ON MAIN as of the 2026-10-14 pass** (probe-verified):

- Action execution: `select_choice` fires the choice's action BEFORE
  navigation; `advance` fires node actions on climb-out of auto-advance
  nodes. Both route through the existing `execute_action` with GameLog
  info/warn lines. Per-player seen-memory (`_dialogue_seen`, max node
  index, transcript-free) added with `get_seen_node` /
  `has_seen_dialogue`.
- Two engine bugs found and fixed by the load probe
  (`game/tests/probe_dialog_actions.gd` — the standing regression gate):
  (1) `.tres` strips `#`-comment lines inside the `[resource]` block,
  silently truncating every property that follows — design commentary
  belongs in staging notes, never inside .tres property lists; (2)
  nested arrays parsed from .tres come back as untyped Array, so
  `get_choices()` failed its `Array[Dictionary]` return and silently
  yielded `[]` for EVERY dialogue file — fixed in `dialogue_data.gd` by
  rebuilding a typed copy.

Still open after the 2026-10-14 pass (each maps to a later build step):

- `DialogUI` does not yet surface quest-offer `action_data` (title +
  pitch line) above the buttons — the service fires the action either
  way, the offer-node presentation is the remaining UI work.
- No dialogue status layer yet: no "available / in_progress / done"
  state per NPC per player (sec. 3 is the spec for it).
- No chaining conditions in `DialogueData` yet: one text per node; no
  `condition` on choices; no ROUTE_NPC action type (sec. 4 is the
  grammar, sec. 13 the extensibility contract).

---

## 3. Conversation states — the status layer

One reused quad-state per (player, npc), same source of truth for marker
UI and dialogue entry. Read from existing state, not a new store
(persistence law, staging notes sec. 4):

| State | Meaning | Where it comes from (existing systems) |
|-------|---------|----------------------------------------|
| `hidden` | Nothing to say beyond greeting | — |
| `available` | First meaningful dialogue or quest offer exists | NPCData.includes has dialogue/quest + not seen yet |
| `in_progress` | A quest step or conversation beat is live here | QuestService has in-progress TALK objective targeting this NPC |
| `exhausted` | Caught up; greeting/farewell only | Dialogue seen AND no live quest target |

- Marker UI (`available` vs `in_progress` symbols, distinct palettes,
  same placement) consumes this same state — staging notes sec. 2 made
  this the plan; this section is where it lands in data terms.
- Range-cancel: proximity prompt clears on leaving radius; state does
  NOT change from proximity alone (state changes only on dialogue
  start/end + quest events).
- Persistence: per-player `dialogue_seen` map (dialogue_id → node index
  reached) rides the existing player state schema. Keep it small:
  id + max node reached, NOT full transcripts. See sec. 12
  (memory-vs-attention).

---

## 4. Conditions (the branching grammar)

Nodes and choices get an optional `condition` dict. One grammar, no
scripting language — data-only, engine-evaluated. Format:

```
"condition": {"kind": "...", "id": "...", "min"/"eq"/"not": ...}
```

Condition kinds, mapped to REAL state the engine already holds:

| kind | reads | example |
|------|-------|---------|
| `quest_state` | QuestService quest state per player | `{"kind":"quest_state","id":"intro_core_npcs","eq":"in_progress"}` |
| `quest_step` | objective progress | `{"kind":"quest_step","quest":"intro_core_npcs","objective":"meet_bank","min":1}` |
| `dialogue_seen` | per-player conversation memory (sec. 3) | `{"kind":"dialogue_seen","id":"blacksmith_village_intro","min":1}` |
| `world_event` | shared weather/cosmic band (WeatherEventService) | `{"kind":"world_event","id":"weather_storm_pack"}` |
| `sky_band` | cosmic/weather band, no per-NPC oracle pretense | `{"kind":"sky_band","min":2}` |
| `act_state` | ActsService current act | `{"kind":"act_state","min":2}` |
| `level` / `faction_rank` | player stats | `{"kind":"level","min":5}` |

Rules:

- A choice with an unmet condition is **hidden** (not shown greyed).
  Greyed disabled choices train players to click through — hide
  instead, per the A.D.D. consideration in sec. 12.
- A node with an unmet `condition` is skipped by auto-advance.
- Conditions compose with AND via a list; OR via priority ordering (first
  truthy branch wins). Keep one level; nest with dedicated branch nodes.
- **Shared vs individual, sharp split (staging notes sec. 5):**
  `world_event`/`sky_band`/`act_state` are SHARED — they decide why the
  conversation matters right now. `quest_state`/`quest_step`/
  `dialogue_seen`/`level` are INDIVIDUAL — they gate wording and
  progression. A node MAY mix both, but the two layers stay in separate
  condition entries so review can audit them independently.

---

## 5. Action execution — closing the wiring gap

The fix that makes all of this a game instead of a visual novel:

1. In `DialogService.select_choice`/`advance`, when a choice or node
   resolves, call `get_choice_action(...)`/`get_node_action(...)` and
   route a non-NONE action through the existing `execute_action`.
   Order: choice action first, then node action (a closing node can
   consolidate a reward).
2. Add `ROUTE_NPC` + `START_CHAIN` to `DialogActionType`:
   - `ROUTE_NPC`: hand-off — close this dialogue, then
     `start_dialogue(next_npc_id, next_dialogue_id)`. Used via a
     map-pin node (sec. 8) without opening the target NPC's full menu.
   - `START_CHAIN`: open the quest offer ("accept?" node) — distinct
     from auto-GIVE_QUEST because the accept is player-consented.
3. In `DialogUI`, propagate action_data with choices so the accept
   button can fire `GIVE_QUEST` with the quest id; show the quest-offer
   node's `action_data` (title + one-line pitch) above the buttons.
4. `execute_action` gains ROUTE_NPC/START_CHAIN arms and a GameLog
   info line per executed action (already has warn for unknown).

Acceptance: `blacksmith_village_intro.tres` node 3 choice "Point me at
the people who matter." with `action_data {"quest_id":
"intro_core_npcs"}` + action GIVE_QUEST actually accepts the quest in
staging build, and the TALK bridge credits `meet_blacksmith` on
dialogue_ended. That is the demo loop for the whole system.

---

## 6. Chaining — the chain law (the spec/law you asked for)

**Dialogue↔quest↔dialogue chains are the spine of onboarding; the rest
is optional texture.** The pattern that landed on staging is the
canonical shape:

```
NPC A dialogue ──(choice: GIVE_QUEST intro_core_npcs)──▶ quest accepted
quest in-progress ──(TALK bridge)──▶ meet_* objectives credit on
dialogue_ended at NPC B/C/D
□ last TALK completes ──▶ quest_state COMPLETE ──▶ turn-in node back
at A (COMPLETE_QUEST) ──▶ next_quest_id opens the next thread
```

Chain law (numbered, so tests can assert them):

1. **A chain endpoint is always a quest or a state change.** A dialogue
   that changes nothing may not be at the end of a chain.
2. **One quest = one conversation anchor per TALK objective.** The
   objective target is the NPCData id, verbatim (existing bridge
   contract). Never author a target the NPC file doesn't have.
3. **Quest-offer dialogs always consent.** GIVE_QUEST fires only from a
   choice the player clicked, never auto on node entry. (START_CHAIN is
   the offer wrapper; see sec. 5.)
4. **Chains may not require walking out of range of the quest UI.** The
   turn-in node lives at the same NPC either inline (return dialogue)
   or via action. If the chain needs a walk, the walk IS an EXPLORE
   objective type (already bridged); never introduce an invisible
   walk-back.
5. **No chain gates the Act spine.** Threads (prd-quests.md sec. 3)
   chain freely; the spine's main_* chain uses next_quest_id only.
6. **Every chain has a recap node.** A player returning mid-in-flight
   must be able to get "where was I" from the anchor NPC without
   re-hearing the intro — see sec. 12 (A.D.D.).
7. **Shared-world flavor never gates chain progress.** Weather can
   flavor the smith's line; it may NOT be the only path to
   `meet_blacksmith` credit (honesty law: shared side explains why
   now, individual side decides the words; only individual state
   changes quest data).

Data shape for the `intro_core_npcs` chain (FIXED 2026-10-14: valid
QuestData — `display_name`/`giver_npc_id` schema fields, `quest_type = 1`
SIDE, TALK objectives type 5, targets all resolve to real NPC files; the
load probe asserts all of this):
- quest: `intro_core_npcs` — objectives: meet_blacksmith (required),
  meet_academy/meet_bank/meet_store (optional), all TALK.
- next_quest_id empty for now; Act-1 thread chains attach here.

---

## 7. Branching grammar in use — creator's loop

For a given outcome (say, meet_academy), a maker writes:

1. The dialogue at the TARGET NPC with a condition on the in-progress
   quest (`quest_step` sees the objective live).
2. Optional shared-world nodes (`world_event`/`sky_band`) positioned
   before the progress node.
3. A `dialogue_seen` recap node for players who already did this beat.
4. A closing node with COMPLETE_QUEST or the next choice.

Branch cost check before committing a tree: fewer than 3 branch keys in
a whole tree should be flagged for review (it's probably a greeting, not
a conversation). More than 12 keys in one tree needs a schema-level
feature (e.g. per-NPC memory) or it sprawls.

---

## 8. Choose-your-own-adventure pathing

CYOA is a first-class mode, not freeform: it is a DialogueData tree where
most choices carry actions and the graph has dedicated hinge nodes:

- **Hinge nodes** (choices only, no text-only auto-advance) use
  `gate` fields: state check + fallback_node index. Fallback rule:
  a CYOA tree with an unreachable node fails lint, not silently.
- **Map-pin nodes**: ROUTE_NPC choices render with a compass icon.
  Rules: max 1 pin per node; pins never chain more than 1 hop
  (no pin-to-pin); the target NPC always has a real tree (a pin into
  an empty NPC is a broken promise — lint against it).
- **Lore-node containers**: nodes flagged `lore:true` are re-readable
  via a "Tell me again" choice condition-gated on `dialogue_seen`.
  Recap rule: any canon-lore node with only one entrance gets a
  second entrance (a recap choice) or it will be missed.

---

## 9. AI-keeper pathing ("AI david-ish" guided paths)

The artisan convoy concept (world-building conversations) becomes a
pathing mode: the NPC walks the player through a real place on a real
route while talking. Data shape (future, staging-agnostic):

- `AIPathData` (or NPCData extension): `stops: [{position_ref,
  dialogue_id, condition}]`, `on_complete: action`.
- Engine contract: FollowService-style movement (START_FOLLOW already
  exists in DialogActionType and bridges FollowService) — the keeper
  walks, the player follows, stops trigger dialogue. This is dialogue
  driving movement, NOT movement driving dialogue.
- Constraint (honesty law): an AI path stop must correspond to
  something real in the world (a waypoint, a station, a native).
  Flashback-ghost tours through non-woken terrain are NOT allowed
  unless the terrain supports them (`zone_id` must resolve).
- Skill-academy is the first keeper-candidate entity: it already has
  service UI + teaching actions; the pathing node type piggybacks the
  academy tree.

---

## 10. Voicing & tone (compact register — full register lives in labs)

Per-NPC voice contracts live in `labs/story-dialogue-creative-voice.md`.
The canon rules for committed dialogue lines:

- One channel per NPC's relationship: the elder speaks for memory, the
  merchant for cost, the smith for the forge, the Warden for listening.
- No mystery gets resolved in dialogue (mystery-first law).
- Weather is a condition, never a mood.
- The player is a witness on shift, not a chosen one.
- First-time line is a duty beat; recap lines are shorter than the first
  telling; nudge/reminder lines are ≤ 12 words. Three lengths max:
  FIRST (≤ 45 words), RECAP (≤ 25), NUDGE (≤ 12). Keep the honest
  refuse-to-perform beats.

---

## 11. Voice-over (TTS) & flyout avatar systems

These are presentation layers on the same DialogueData data. They must
be optional and degrade gracefully.

### 11.1 Voice-over / TTS

- `DialogueData` gains optional per-node `voice_clip: String` (res://
  path). Null clip → fall back to TTS engine → fall back to text-only.
- TTS order of preference: pre-recorded clip > platform TTS (web
  Speech Synthesis in the wasm client, server TTS for keeper paths
  where a live actor is reading) > text-only.
- Voice lines obey the same length law as text (sec. 10). A line that
  reads wrong aloud at ≤ 45 words should be split into two nodes, not
  recorded long.
- Interrupt: skipping a node stops its audio (no barge-up; one voice at
  a time). Choice narration reads as "Say: <text>" — matches the
  repair-a11y naming already used in DialogUI.
- Mixing state: voice ducking under the ambient/weather mix already
  driven by AudioService; dialogue voice always ducks sfx, never the
  opposite.

### 11.2 Flyout avatars (bubble heads)

- One raster avatar key per talking entity: NPC, enemy, keeper, even
  the sign-voices (sign profile blessing the Concord system directly
  reuse it).
- Format: `res://assets/avatars/<entity_key>.png` (entity_key matches
  the entity id: `npc_blacksmith_village`, `enemy_troll_elite`,
  `sign_the_awakening`). House size: 128×128 (2× for retina = 256),
  single raster PNG per key, background-agnostic.
- `DialogueData.voice_clip` + `avatar_key` ride the same node dict.
  `npc_data.icon_path` already exists — the avatar key falls back to
  it when no avatar is built, so no tree blocks on art.
- Flyout UI lives in DialogUI portrait row first (portrait swap on node
  change). Then HUD-adjacent flyout for out-of-dialogue "someone is
  speaking" moments (keeper paths, sky sign openings): a small
  avatar + speaker + one-line fade in/out, range-cancelled same as
  proximity prompts. **Enemy taunts** use the same flyout with the
  enemy's key; they never open the dialog panel (enemies taunt, they
  don't converse).
- **Reuse law (the bonus):** the same raster avatars key quest UI
  (quest-giver chip on the tracker), achievements (achiever-key chip),
  and the party frames. ONE avatar per entity, multiple consumers.
  The raster family is part of the icon tier in the 3d workflow: a
  model brief for any entity must include its raster key; atlas-swap
  not required, individual files are preferred (lazy-load and cache
  friendly).
- Art direction: single-subject bust, 45° three-quarter view, neutral
  backdrop, hard rim light matching the entity's palette key (teal for
  woken things, magenta only for Bloom-touched, gold for active
  services). Hostiles get one knocked-eyebrow expression max — they
  gate on silhouette not grimace.

---

## 12. Human attention (A.D.D.-aware conversation UX)

- Skippable always: every node has both Advance (space/click) and
  Escape (end) affordances visible. Auto-open never blocks input
  beyond radius.
- Recap-not-rewind: pausing/resuming mid-tree re-shows the current
  node with a "Recap" chip the player can click to get the 1-sentence
  memory (drafted from a `recap` text field, NOT the full transcript).
- Session resume: `dialogue_seen` persists the max node index; resuming
  starts at the last hinge (choice) node reached, not node 0. If the
  resumed node's conditions changed (quest progressed while away), the
  tree re-evaluates and reports the reconciliation in the recap chip
  ("This beat changed while you were away").
- Interruption law: opening another menu closes dialogue (existing
  UIPanel behavior); re-entering range does not auto-resume text-only
  trees (only keeper AI paths auto-resume, because the walk is the
  state).
- Choice count: ≤ 3 choices per node. 2 is default; 3 is a hinge.
  4+ requires a CYOA mode exception and appears in review.
- Text budget: see sec. 10 length law. No node beyond 45 words first
  time; no node repeats longer than recap length on repeat visits.

---

## 13. Extensibility routes (walled garden)

What the schema can absorb without new code:
- New `DialogActionType` entries (data + execute_action arm + test).
- New condition kinds (same trio).
- Per-NPC multi-dialogueTrees keyed by quest state (already just
  DialogueData + conditions; `get_dialogue_id()` first-match order is
  the fallback shims until conditions land).

What needs a schema revision (deliberate, not silent — update this doc):
- Per-node speakers with multiple voices in one tree (moot until the
  keeper/AI pathing system exists).
- Per-choice audio timing (voice-clip length metadata; currently the
  clip is enough).
- Passing arbitrary posed parameters into start_dialogue (e.g. weather
  read at open time); today conditions at branch time are the
  contract.

What is explicitly OUT of scope (per staging notes + honesty law):
- A separate dialogue-state persistence system (existing state +
  migration only).
- An in-dialogue scripting interpreter; conditions are data.
- NPC-invented weather predictions (no oracle NPCs).

---

## 14. Acceptance criteria (the demo loop, end-to-end)

The first staging cut is DONE when, in a staging build:

1. `blacksmith_village_intro.tres` plays from the action menu talk path
   (DialogService → DialogUI), with the speaker set to "Village Smithy".
2. Choosing "Point me at the people who matter." fires GIVE_QUEST and
   `intro_core_npcs` appears in the quest UI.
3. Walking to the (unplaced-but-auth) second NPC and talking them
   credits its TALK objective via the dialogue_ended bridge — visible
   in the tracker.
4. The quest-offer path reuses the SAME conversation (offer node inside
   intro dialogue) — no separate prompt bubble.
5. When intro_core_npcs completes, `blacksmith_village_dialogue` gains
   a recap node visible only via the `dialogue_seen` condition, per
   sec. 12 recap rule.
6. No new persistence store; `dialogue_seen` lives in existing player
   state via a migration file (staging note law).

7. And the tonal bar: the first-time line reads like a Concord duty
   beat, not a tutorial tooltip; the smith's voice (labs creative doc)
   matching prd-story.md sec. 8 — hopeful, practical, a little
   reverent; no mystery resolved; no weather-mood adjectives.

---

## 15. Build order — what to build next, in sequence

The demo loop (sec. 14) and the two unbuilt systems (sec. 16/17) fold
into one priority ladder. Each rung is independently testable and
every rung reuses the rung below it:

1. **Offer-presentation in DialogUI** — surface the quest-offer
   `action_data` (title + one-line pitch) on the accept node. Smallest
   remaining piece of the sec. 14 loop; finishable in one sitting.
2. **Status layer** (sec. 3) — quad-state per (player, npc) reading
   existing QuestService/NPCData state; persists by migration, not a
   new store. Unblocks both the markers and the runner.
3. **NPC/goal indicators, first consumer** (sec. 17.3 step 1) —
   `intro_core_npcs` TALK objectives drive world glyphs. This is the
   first thing players SEE; the demo loop becomes visible.
4. **Conditions grammar** (sec. 4) — `dialogue_seen` + `quest_step`
   first (the two keys the demo loop needs), shared-world kinds after.
5. **Guide-runner in tutorial skin** (sec. 16) — dresses the same loop
   completed by rungs 1–4; the quest is already the spine.
6. **CYOA + ROUTE_NPC + keeper pathing** (sec. 8/9) — the expansive
   layer, only after the spine demo loop is shown end-to-end in-world.

Sequencing law: no rung above 3 may start before the in-world touch
(rung 3) proves the TALK bridge + indicator contract on real servers.
Doctor's rule: if rung 4 conditions grow beyond the seven kinds in
sec. 4, stop and split a schema revision, don't grow the grammar.

---

## 16. The guide-runner mode: dialogue as a tutorial that slyly uses the a11y targeting system

The insight from the Solar discussions: a tutorial is just a dialogue
runner with goals. The game already ships a screen-reader/intervention
targeting layer (`A11yService` + `ui_styles.apply_accessibility(...)`) that
exposes every actionable control as named actions with a snapshot +
activate() interface. The tutorial engine is the SAME walk: name the
next thing, wait for its activation, react. So one engine, two skins.

### 16.1 What a tutorial run is, in data

A `TutorialRun` is a linear list of steps; each step is one of the
existing dialogue verbs plus a target spec:

	step := {
		"say": "dialogue_id" OR "text",       # the runner voices guidance
		"target": {"kind": "action_name", "value": "..."},   # what to wait for
		"hint_at": "entity_or_panel_key",      # optional highlight/arrow
		"on_done_goto": next_step_index,       # default: linear
		"skip_if": condition (sec. 4 grammar)   # veterans skip whole steps
	}

Target kinds are REAL engine concepts the a11y layer already exposes:

| kind | matches | example |
|------|---------|---------|
| `a11y_action` | an A11yService snapshot action label | "Talk", "Cast Fireball" |
| `npc_interact` | proximity + action_menu on an NPC id | `npc_blacksmith_village` |
| `panel_open` | MenuManager.open_menu key | "quests", "bank" |
| `zone_cross` | ZoneManager.player_entered_zone | `zone_forest_meadow` |
| `dialogue_choice` | a choice by its text prefix in the active dialogue | "Point me at" |
| `quest_state` | QuestService event (accepted/completed) | `intro_core_npcs` accepted |

The runner advances ONLY on real engine events — it never polls
positions with timers (honesty law: no fake progress). Each step is
metered the same way dialog nodes are; step text obeys the sec. 10
length law (teaching lines are FIRST-length or shorter).

### 16.2 The slyly part: reuse, do not duplicate

- The runner's "where can the player act?" read is `A11yService.snapshot()`
  filtered to the step's target. The same snapshot the screen-reader
  pilot and the repair-a11y probes use. No second action registry.
- `hint_at` highlights via the existing tooltip/highlight visuals, not a
  new arrow system (one highlight vocabulary).
- Completion detection subscribes to the SAME signals the quests do:
  `dialogue_ended`, `quest_accepted`, `player_entered_zone`, choice
  navigation in DialogService. Zero new event sources.
- Persist per-player via the existing state path + migration (step index
  only, like sec. 3's max-node memory; never transcripts).

### 16.3 First run: the meet-the-NPCs onboarding (the flow example)

The `intro_core_npcs` quest IS the first tutorial run — the quest is the
spine and the runner dresses it:

1. say-step `blacksmith_village_intro` opens (auto via spawn proximity,
   skippable) — teach: "the smith is a door; doors matter."
2. `a11y_action: Talk` — invoke the action menu on the smith.
3. `dialogue_choice: "Point me at"` — the quest-accept beat fires
   GIVE_QUEST (now actually wired, sec. 5).
4. `panel_open: quests` — open the tracker once; teach what it is, close it.
5. `npc_interact` on each optional meet_* target — the runner announces
   via the NPC/goal indicator (sec. 17), NOT a text wall.
6. `quest_state: completed` — closing node back at the smith; title chip
   (sec. 11.2 avatar reuse).

Failure shape: steps never block. If a target is unreachable for
60s of real play, the runner offers "skip this step?" — a soft
opt-out, consistent with sec. 12's skippable-always law. A run is
restartable from any completed checkpoint; nothing is one-shot.

---

## 17. NPC/goal indicators (the system that hasn't been built yet)

Two indicator families that share one data contract, because a goal
location and a talkative NPC are the same navigational problem:

### 17.1 The data contract

`IndicatorSource` — anything that can declare "this world-position
currently has a call on the player's attention":

- NPC with available/in_progress state (sec. 3 quad-state drives it).
- Quest objective (TALK npc target, EXPLORE zone, DELIVER npc target).
- Waypoint/gateway data (already placed in data/gateways).
- Tutorial runner step with `hint_at` (sec. 16).

Each source emits: `{entity_or_objective_id, world_pos_getter,
state: available|in_progress|complete, priority: int}`. The indicator
manager subscribes to sources; nothing else knows about rendering.

### 17.2 Rendering rules (one marker interface, staging notes sec. 2)

- **World-space**: floating glyph above the entity — "!"/"?" available/
  in_progress per classic-mmo convention, palette from the entity's key
  (sec. 11.2 rim-light law: teal available, gold active, magenta for
  Bloom-touched targets only). Range-gated: glyphs fade in at
  interaction radius + margin, same cancel law as prompts.
- **Screen-space**: on-screen arrow/edge chevron ONLY for the
  highest-priority active objective; never more than one at a time
  (attention is a budget; the A.D.D. law applies double here).
- **Minimap/settlement map**: dot for every source in current zone,
  shape by quest_type, palette by state. Clickable → routes pin.
- Distance-based priority: the HIGHEST priority wins ties by proximity
  in the zone; cross-zone goals route via the map instead of an arrow
  (no far-arrow pointing through terrain on a spherical world).

### 17.3 First consumers (build order)

1. `intro_core_npcs` TALK objectives → village NPCs get the quad-state
   glyphs. This is the demo loop for the whole indicator contract.
2. Quest giver chip ("!"→"?" while in-progress) — same glyph state,
   sourced from QuestService state intersection with NPCData.includes.
3. EXPLORE objectives → screen chevron to zone edge + map dot.
4. Deliberately NOT first-batch: enemy aggro pings, other players'
   party positions (party_frames already own that).

### 17.4 Laws

- **One source of truth**: state comes from the IndicatorSource contract,
  never hand-placed "!"s in scenes. A glyph without a source is a bug.
- **No attention spam**: max 1 screen chevron + 1 world glyph per entity;
  max map-dot count per zone = number of live objectives, no decoration.
- **A11y binding is mandatory**: every indicator must ALSO exist in the
  a11y snapshot ("Available: Village Smithy, the forge") so pilot-mode
  players navigate by name — this is the sec. 16 tie-back.
- **No fake markers**: if the target world pos is unresolvable (unplaced
  NPC), the indicator DISABLES itself rather than pointing at origin.

---

## 18. Where canon lives (pointer table)

| Topic | Source |
|-------|--------|
| Indicator system law (wins over ad-hoc markers) | this doc sec. 17 |
| Tutorial runner law | this doc sec. 16 |
| Dialogue tone (full register) | `labs/story-dialogue-creative-voice.md` |
| Concord voice bible (world layer) | `labs/story-voice-concord.md` |
| Quest engine/TALK bridge | `labs/prd-quests.md` sec. 5 |
| World law (wins over this doc) | `labs/prd-story.md` |
| Signing/dialogue-on-signs | `labs/sign_profile` + sign .tres |
| Schema law (what is real) | `game/core/schemas/dialogue_data.gd`,
  `game/core/schemas/quest_data.gd`, `game/core/schemas/npc_data.gd` |
