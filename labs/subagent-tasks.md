# Subagent Task Board

Work items that can be handed to a subagent (OpenHands child conversation) or
worked inline. See `labs/prd-openhands-canvas.md` for how subagent lanes run.

**Rewritten 2026-11-28.** The previous board (five docs-only research tasks:
NPC voice profiles, quest briefs, chronicle entries, weather lore, landmark
names) is superseded -- those were written when the repo held 5 dialogues and
9 quests. It now holds 9 dialogues and 27 quests, and a content audit on
2026-11-28 found the gaps below. The old tasks are folded into Tasks 5-9 here.

## How to use this board

- **Ground rule:** every task names its output file under `labs/` or the exact
  `game/data/` / `game/core/` file it changes. Content tasks produce data;
  bug tasks produce code + a gate.
- **Grounding:** read the referenced files before writing. The world has laws
  (see `labs/prd-story.md`, `labs/data-authoring-baseline.md`,
  `labs/story-dialogue-creative-voice.md`) -- extend them, never contradict.
- **Status column:** update only your task's state line (`todo`, `draft`,
  `review`, `landed`, `wontfix`).
- **Order matters:** the parity bugs (Tasks 1-3) land first and green, because
  they are small and every content task downstream depends on the wiring being
  real. The creative tasks (4-9) follow.

## Reusable existing drafts (checked 2026-11-28)

The old board produced three `labs/` drafts that survive. They are **stale on
counts** (written against 5 dialogues / 9 NPCs / 4 weather events; the repo now
has 9 / 20 / 5) but their **voice work and lore framing are still good raw
material**. Reuse them, do not re-write from scratch:

| draft | state | reuse for |
|---|---|---|
| `labs/story-dialogue-npcs.md` (268 lines) | voice profiles for the 9 then-authored NPCs, with lines tagged to real node ids and trigger conditions | **Task 5** -- done (2026-11-28e): the 8 mute NPCs now speak; the profiles for the already-voiced NPCs are done |
| `labs/story-voice-concord.md` (218 lines) | the Concord-as-reading-culture voice bible; the Bloom as maintenance failure | **Tasks 5, 6, 7** -- the tone authority alongside `story-dialogue-creative-voice.md` |
| `labs/story-weather-events.md` (184 lines) | weather law + lore for the 4 then-authored events | **Task 7** -- add `weather_bloom_stir` (the 5th event) and refresh the count |

The other three old outputs (`story-quest-briefs.md`, `story-chronicle.md`,
`story-landmark-names.md`) were never written; Tasks 3, 6, 8 cover them.

---

# PART A -- PARITY BUGS (land first, small + surgical)

These are confirmed by code reading on 2026-11-28. Each is a data-vs-build or
code-vs-schema gap, not a design question. All three want their own commit on
one branch (`fix/npc-parity`) with a gate added.

## Task 1 -- The blacksmith's dead quest hook (NPC include parity) -- status: done (2026-11-28d)

**The bug:** `game/data/npc/npc_blacksmith_village.tres` carries its quest as

```
{"type": "quest", "ref_id": "quest_intro_core_npcs"}
```

Every sibling NPC that offers quests uses the inline shape
`{"type": "quest", "quest_ids": [...]}` (see `npc_village_elder`,
`npc_deep_warden`, `npc_tidewright_fenwick`, `npc_jeweler_haven`,
`npc_herbalist_village`, `npc_elder_capital`). Worse, `quest_intro_core_npcs`
is **not** an offering file under `game/data/npc_offerings/`, so the `ref_id`
dangles: the smith's quest hook is dead data that resolves to nothing.

**Fix:** change the include to the inline shape
`{"type": "quest", "quest_ids": ["quest_intro_core_npcs"]}`.

**Also check:** whether the `includes` docstring in `npc_data.gd` (the block
at `@export var includes`) should be tightened so `ref_id` on a `quest` entry
is documented as invalid -- the schema comment currently only shows `quest_ids`
for the quest shape, so the smith entry contradicts the documented contract.

**Gate:** extend `game/tests/test_data_naming_lint.gd`. It validates offering
`quest_ids` but never the **inline NPC quest includes**. Add a pass that walks
every `game/data/npc/*.tres`, finds `"type": "quest"` entries, and asserts each
names `quest_ids` (not `ref_id`) with every id resolving to a real
`data/quests/*.tres`. Verify the gate FAILS on the current smith file before
fixing it (the same fails-first discipline the skill lint used).

## Task 2 -- The sideways / backwards NPCs (missing radial align) -- status: done (2026-11-28d)

**The bug (two halves, one cause):**

1. `NPCData.spawn_rotation` (`game/core/schemas/npc_data.gd:64`) is declared
   but **read nowhere in the entire codebase** (`grep -rn spawn_rotation
   game/` returns only the declaration). No NPC sets it either.
2. The globe's town-NPC path (`globe_world.gd` `_spawn_town_npc`) sets
   `entity.global_position` and stops. It never calls `_align_radial` (which
   the gate + portal paths DO call) and never sets a `basis`. So on the
   spherical world every village NPC stands with **world-Y up** -- tilted off
   the surface (the "sideways" report) -- and carries an **identity facing**
   (the "backwards" report).

Contrast the enemies, which get both laws: `EnemyAI._entity_up` returns the
planet radial, and `enemy.gd` (~line 199) sets
`global_transform.basis = Basis.looking_at(-fwd, up)`. NPCs get neither.

**Fix:**
- In `_spawn_town_npc`, after positioning, radial-align the body the same way
  `_align_radial` does (local +Y = surface up) and then apply a yaw.
- Make `spawn_rotation` real: treat it as a **facing yaw** (radians) applied
  around the local up axis. Default 0 should face a sensible direction (e.g.
  plaza-inward / toward the spawn center), not identity.
- Decide whether NPCs should face the player on interact (a small
  `_face_player` on interaction) -- probably yes for the institutions, and it
  makes the `spawn_rotation` default less load-bearing. Record the decision.
- Audit whether the same gap exists in `spawn_service.spawn_npc_entity` (the
  planar path) and in `globe_underworld._build_camp_keeper`.

**Gate:** add an orientation assertion to `game/tests/probe_starter_village.gd`
-- for each spawned village NPC, assert the body's local +Y is within a small
epsilon of the radial up at its position, and that a non-default
`spawn_rotation` produces the expected yaw. This is the check that would have
caught the bug.

## Task 3 -- Quest reachability + the 11 orphaned quests -- status: done (2026-11-28d)

**The finding:** after accounting for BOTH inline includes and offering files
(`shoal_freight_quests`, `village_quests`, etc.), **11 of 27 quests are
offered by no NPC at all**:

```
quest_arena_trial      quest_boar_tusks       quest_copper_seam
quest_gloam_harvest    quest_intro_core_npcs  quest_main_awakening
quest_main_teachings   quest_pearl_dive       quest_tideline_kelp
quest_watch_the_sky    quest_wings_over_haven
```

Separately, `QuestData.giver_npc_id` / `turn_in_npc_id` are **read nowhere in
the codebase** (`grep -rn giver_npc_id game/` returns only the declaration).
So the giver is decorative: quests become available by level + prereq + pack
gate in `QuestService._get_available_quest_ids`, NOT by which NPC you talk to.
The NPC `includes` graph is the real offer surface, and 11 quests are missing
from it.

**Note on `quest_main_awakening`:** it has an empty `giver_npc_id` and is the
opening beat (its `turn_in_npc_id` is the elder). Check whether it is meant to
be auto-accepted on first login; `globe_world.gd` (~line 2039) auto-accepts
`quest_wolves_hunt` and `quest_watch_the_sky` but not the awakening. If the
awakening is meant to be the first auto-accept, wire it; if it is meant to be
offered by the elder, add it to the elder's includes. Record the decision.

**Fix:** wire each orphaned quest to a sensible giver through the `includes`
graph (or an offering file). Keep the offer graph honest with the story: the
`quest_main_*` spine hangs off the Village Elder; the arena/boar beats are
Haven-side; the pearl/tideline beats are the Jeweler's; etc. Cross-check
`labs/prd-quests.md` section 3 ("threads, not chains -- no thread may gate the
spine").

**Gate:** extend `test_data_naming_lint.gd` (or `test_content_ref_integrity`)
with a **quest reachability** pass: every quest with `quest_type` SIDE or MAIN
must appear in some NPC's include graph or offering `quest_ids`, unless it is
on an explicit allow-list of auto-accepted / event-only quests. This is the
check that keeps the 11 from re-orphaning.

---

# PART B -- CLASS KITS (wire the authored skills)

## Task 4 -- Wire the six empty class skill trees -- status: done (2026-11-28d)

**The finding:** 169 skills are authored under `game/data/skills/<role>/`.
Only 74 are referenced by a class. **95 are orphaned**, and six playable
classes have **completely empty** `starting_skills` / `skill_tree_unlocks`:

```
akkan_attacker    akkan_stalker     human_marksman
human_sorcerer    synthetic_psion   synthetic_tracker
```

plus `human_warrior` (2 starting skills, empty tree). `TASKS.md` line 231
flagged this as "needs a design call" -- but the skills are already authored
AND already carry `required_class` + `required_level`, so each tree is
**derivable, not inventive**. The tagged level spans are:

| class | tagged skills | levels present |
|---|---|---|
| `akkan_attacker` | 4 | 5, 10 |
| `akkan_stalker` | 9 | 1, 5, 10, 15, 20 |
| `human_marksman` | 9 | 1, 5, 10, 15, 20 |
| `human_sorcerer` | 9 | 5, 10, 15 |
| `synthetic_psion` | 9 | 5, 10, 15 |
| `synthetic_tracker` | 9 | 1, 5, 10, 15, 20 |
| `human_warrior` | 10 | 1, 5, 10, 15 |

**Fix (LANDED):** each class kit was derived from its own skills' tags --
ADD-only, so authored levels were preserved. Every class-owned skill that no
kit referenced (38 of them, mostly the `*_sig` signature line) was added at
its tagged level; the six empty classes got their tagged kit. Each class owns
its own line plus one signature per faction (3 `*_sig` each, at L10), matching
the 3-signatures-per-class design the user confirmed. `akkan_attacker` had no
L1 skill, so its void opener was promoted to L1 (the L1 gap is recorded here).
`human_warrior` keeps `human_shield_bash` (it IS tagged `human_warrior`, so it
belongs to the kit) and gains the rest of its tagged line.

**CORRECTION to the original finding:** the `*_sig` cluster was NOT the
pattern to study -- it was the bulk of the ORPHANS. Every one of the 43
signature skills was authored, tagged, and referenced by NO class. They are
now wired (that is the design: 3 signatures per class).

**Watch for:**
- `akkan_attacker` has no L1 skill (its void line starts at L5). Either
  promote `akkan_void_slash` to L1 or author a new L1 opener. Record the call.
- `human_warrior` currently starts with `human_shield_bash`, which is a
  GUARDIAN-flavoured skill -- check it belongs to the warrior kit.
- One skill (`human_time_warp`, in `bender/`) is missing both `required_class`
  and `required_level`. Tag it (likely `human_temporalist`).

**Gate:** `test_data_naming_lint.gd` already has a Skills section asserting
every class ref resolves to a skill OWNED by that class. Extend it to assert
no playable class has an empty tree, and add an **orphan budget**: report (or
fail on growth of) the count of authored skills referenced by no class.

---

# PART C -- CREATIVE CONTENT (the fun stuff)

## Task 5 -- Institution dialogue: give the 8 mute NPCs a voice -- status: done (2026-11-28e)

**Fix (LANDED):** eight new trees authored, one per institution, and the
`{"type": "dialogue", "dialogue_id": ...}` include wired into each NPC file.
Every one of the world's 20 NPCs now speaks (was 12). The trees:

| dialogue_id | npc | hook |
|---|---|---|
| `armory_capital_intro` | `npc_armory_capital` | OPEN_SHOP `armory` |
| `banker_capital_intro` | `npc_banker_capital` | OPEN_VAULT |
| `banker_village_intro` | `npc_banker_village` | OPEN_VAULT |
| `black_market_fixer_intro` | `npc_black_market_fixer` | OPEN_SHOP `black_market_ledger` |
| `herbalist_capital_intro` | `npc_herbalist_capital` | OPEN_SHOP `potions` |
| `herbalist_village_intro` | `npc_herbalist_village` | GIVE_QUEST `quest_gloam_harvest` + OPEN_SHOP `potions` |
| `skill_academy_capital_intro` | `npc_skill_academy_capital` | (voice only; academy opens from the menu) |
| `skill_academy_village_intro` | `npc_skill_academy_village` | (voice only; academy opens from the menu) |

Each tree is 3-4 nodes with a farewell branch, in the Concord register
(attentive before theatrical, honest before helpful; the Bloom is tragic,
never evil). `npc_herbalist_village` -- the worst case, two Bloom quests and
no voice -- now introduces `quest_gloam_harvest` by name and sends the player
to the treeline.

**Deviation from the brief, recorded:** the brief asked for "at least one real
quest hook (GIVE_QUEST)" per tree. Only `npc_herbalist_village` has a quest to
give -- Task 3 already closed the orphan-quest gap, so no other institution
owns a quest. Those trees hook their own institution action instead
(OPEN_SHOP / OPEN_VAULT). Inventing quests to satisfy the letter of the brief
would have re-opened the reachability problem Task 3 closed.

**The finding (as written):** 8 NPCs had no dialogue include at all, so they
were silent statues with a menu:

```
npc_armory_capital        npc_banker_capital      npc_banker_village
npc_black_market_fixer    npc_herbalist_capital   npc_herbalist_village
npc_skill_academy_capital npc_skill_academy_village
```

`npc_herbalist_village` is the worst case: she **gives two Bloom quests**
(`quest_study_the_bloom`, `quest_the_runoff_line`) with no dialogue to
introduce them. `labs/prd-quests.md` section 6 explicitly queues "author
per-institution greetings (smith, alchemist, storekeeper) with quest hooks".

**Voice law:** `labs/story-dialogue-creative-voice.md` -- the Concord register:
attentive before theatrical, honest before helpful, dutiful before convinced.
Weather is a condition to cross, not mood. The world is unpowered: everything
is woken, mended, grown, salvaged. Never "tech", never "magic", never gods.
The Bloom is tragic, never evil.

**Produce:** new `game/data/dialogues/<npc>_intro.tres` trees, one per mute
NPC (or per institution, shared where the two instances are the same person
type -- e.g. one academy greeting for capital + village, with a variant line).
Each tree: 3-6 nodes, at least one real quest hook (GIVE_QUEST action), and a
farewell branch. Match the structural shape of the existing trees
(`village_elder_greeting` is the simplest at 3 nodes; `deep_warden_greeting`
the richest at 7). Then add the `{"type": "dialogue", "dialogue_id": ...}`
include to each NPC file.

**Read first:** the 9 existing trees, `game/core/schemas/dialogue_data.gd`
(the `DialogActionType` enum -- GIVE_QUEST, OPEN_VAULT, OPEN_SHOP,
TEACH_SKILL), and `labs/story-dialogue-npcs.md` if it exists (the old Task 1
output -- reuse any usable voice profiles).

**Gate (LANDED):** `test_data_naming_lint.gd` gained four assertions, so a
silent statue can never come back:
- every offering NPC carries a dialogue include (the mute-statue gate);
- dialogue node links resolve within their tree;
- every tree has a farewell (-1) branch;
- GIVE_QUEST / OPEN_SHOP / TEACH_SKILL action hooks name a real
  quest / offering / skill (the dead-hook class).

Both negative controls were run by hand: deleting an NPC's dialogue include
fails the mute gate by name, and a phantom `quest_id` fails the hook gate by
name.

## Task 6 -- Lore-bearing props: signs, the monolith, the chronicle -- status: todo

**The finding:** only 3 signs exist; the world is full of unlabelled places.
`labs/prd-story.md` section 9 keeps five mysteries deliberately open -- do not
canonize answers.

**Produce:**
- `labs/story-chronicle.md` (the old Task 3): almanac-style entries for the 3
  acts (`game/data/acts/*.tres` chapters), the capitol monolith's
  wrong-written history, and the village origin short.
- New `game/data/signs/*.tres` (schema `sign_profile.gd`, prefix `sign_`): one
  per institution and one per road-marker, each a short inscription in the
  Concord voice. Signs are the cheapest lore surface in the game.

**Read first:** `game/core/services/sign_service.gd`, `acts_service.gd`, the
three existing signs, and `labs/prd-story.md` sections 4-5 (institutions, the
Bloom).

## Task 7 -- Weather + event lore -- status: todo

**The finding:** 5 weather events, 7 hordes, 2 content packs exist; the lore
for them is thin.

**Produce:** `labs/story-weather-events.md` (the old Task 4) -- for the aurora
window, the Bloom Stirs event (`weather_bloom_stir`), and each horde config:
what the sky/myth thinks is happening, what the frame law actually does, and
one keeper's rumination. Keep "what players are told" separate from "what
happens" -- that separation is the world's honesty law.

**Read first:** `game/data/weather_events/*.tres`,
`weather_event_data.gd`, `game/core/frame/srv/weather.gd`.

## Task 8 -- Landmark naming pass -- status: todo

**Produce:** `labs/story-landmark-names.md` (the old Task 5) -- a table of
names keyed to coordinates-bearing facts already in code: the great range, the
far coast (capitol), the ford, the harbor, the underworld strata, the moon's
meridian, the Gloomwood gate. For each: the name, a one-line etymology, and
the field in code it would attach to. Name choices only -- no code edits.

**Read first:** `globe_world.gd`, `globe_underworld.gd`, `globe_moon.gd`,
`strait_chart.gd`, and the biome list in the terrain probes.

## Task 9 -- Achievement listeners for the waking verbs -- status: todo

**The finding:** `labs/prd-quests.md` section 4 says achievements should
celebrate the world's verbs, not grind counters. `achievement_listeners.gd`
covers combat/horde/social; the waking verbs (EXPLORE/waypoint wakes, Bloom
containment, companion/mount bonds) have thin coverage. 32 achievements exist.

**Produce:** an audit of `game/data/achievements/*.tres` against
`achievement_listeners.gd` -- which verbs are celebrated, which are missing --
then author 4-8 new achievements for the wake-counts ("Waymaker" tiers), the
Bloom-containment deeds, and the bond lines. Schema: `achievement_data.gd`.

---

## Maintenance notes for the maintainer

- Landing a task = doing the work yourself (or taking a subagent's draft),
  then marking `landed` on the board.
- The parity tasks (1-3) are the priority: they are small, they are verified
  bugs, and Tasks 4-9 all assume the wiring is real.
- Keep the board honest: when a task's premise turns out wrong, correct the
  board in the same turn (the `labs/TASKS.md` honesty law applies here too).
