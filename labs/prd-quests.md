# Synmergia — Quests & Achievements (Design Bible)

> **Status:** CANON for quest/achievement design. Companion to
> `labs/prd-story.md` (the world's story -- read that first). This
> document is the law for what a Synmergia quest IS, and the
> engineering map of the quest engine.
>
> 2026-09-25. Written alongside the quest-engine repair: TALK and
> COLLECT bridges + NPC id normalization (see TASKS.md).

---

## 1. Philosophy: every quest is the world's verb

The tired formula -- "kill 5 wolves" -- fails because the objective
is the POINT. In Synmergia the objective is never the point; it is
the smallest unit of the world waking up. Every quest must answer:
**what piece of the dormant world comes back online because I did
this?** If the answer is "nothing, you just get gold," the quest is
not done -- it is a chore, and chores are why players say quests suck.

The three laws:

1. **Diegetic objectives only.** Objectives are things people in the
   world would actually do: WAKE, LISTEN, RECOVER, RETURN, REPAIR,
   GROW, TRADE, GUARD. "Kill 10 wolves" is only legal when the wolf
   problem is a story problem (the pack is Bloom-stirred, not
   hungry).
2. **The world remembers.** A completed quest changes something
   visible: a waypoint stays lit, an NPC's dialogue advances, a room
   opens. (The woken-state scoreboard from prd-story.md sec. 7 --
   multiplayer IS lore.)
3. **No fetch-task language.** Copy voice follows prd-story.md
   sec. 8: "The Elder asks you to wake the old road," never "Quest:
   activate 3 waypoints." The tracker shows what you ARE doing; the
   journal tells you what it MEANS.

## 2. The objective palette (mapped to the engine)

`QuestData.ObjectiveType` already ships 10 types. Their Synmergia
meanings and canon examples:

| Type | In-world meaning | Canon example |
|------|------------------|---------------|
| KILL | Cull a Bloom-stirred or dangerous threat | Wolf Hunt (wolves stirred by something under Gloomwood) |
| COLLECT | Recover what the world scattered | Herb Gathering; "Recover Lost Schematics" (HUD canon) |
| ESCORT | Walk someone home through the quiet | A seed-carrier to Haven |
| DEFEND | Hold a woken thing while it stabilizes | Defend a just-woken waypoint until its mandala holds gold |
| EXPLORE | Wake / survey a place | "The Old Roads" (main_teachings) -- wake 3 waypoints |
| TALK | Listen; the world's memory is in people | The Awakening |
| DELIVER | Reconnect two places | Carry the alchemist's order to the storekeeper |
| USE_ITEM | Use the tablet the way it wants | Use a schema fragment at a ruin |
| CRAFT | Practice a relearned craft | Forge the first repair-ingot |
| REACH_LEVEL / ACHIEVE_STEP | Milestones, used sparingly | Academy attunement |

**Design rule:** a quest mixing 2 objective types beats 3 of one
type. "Wake the waypoint (EXPLORE), then listen to what it says
(TALK)" is a moment; "kill 6, collect 6, kill 6" is a spreadsheet.

## 3. Quest shapes (anti-grind architecture)

- **Threads, not chains.** The main story is a SPINE
  (main_* .tres, chained via next_quest_id). Around it hang THREADS
  that can be done in any order and still make sense. No thread may
  gate the spine; the spine may gate threads.
- **The wake-chain pattern** (signature structure): every Act gets
  one multi-stage quest where each completed stage visibly wakes
  something -- a stone, a door, a hall. The Forest Depths elevator
  (Act 2 close) and the Nexus Core (Act 3) are the endpoints.
- **Dailies are economies, not errands.** The daily tier
  (Siphon Aether, herb runs, patrol reports) funds the Waking:
  their rewards feed repair materials, faction standing, and
  schematics. A daily should take 5 minutes and teach one system.
- **No quest exists with a single beat** unless it is a tutorial.
  Two beats minimum: do the thing, then see the world answer
  (TALK the result, watch a light change, get a letter).

## 4. Reward law

Gold and XP close loops; they never carry meaning. The memorable
rewards are: **titles** (TitleService -- "Waymaker" for the first
woken road), **schema fragments** (lore + USE_ITEM hooks),
**faction standing** (the Alliance/Horde/Collective each value
different quest types), **cosmetics** (banner dyes from faction
quests), and **world-state** (the woken thing itself). A quest that
only pays gold should not exist.

Achievement law: achievements celebrate the world's verbs, not
grind counters. Canon set already skews right (first_boss,
horde_mvp, explorer) -- extend with wake-counts (Waymaker tiers),
Bloom-containment deeds, and companion/mount bonds, never with
"collect 10,000 herbs."

## 5. Engineering map (what exists, what is wired)

- **Engine:** QuestService (autoload) -- accept/abandon/complete,
  per-player persistence via DictStore KV
  (`_player_quests`, `_persist_player_quests`), signals
  quest_accepted/quest_updated/quest_completed (typed NotifKind
  toasts, deduped).
- **Objective bridges (2026-09-25 repair):**
  - KILL <- EventHub.kill_rewarded (pre-existing; killer credit +
    party-share credit).
  - TALK <- DialogService.dialogue_ended (NEW). Credits every
    in-progress player whose TALK objective matches the npc
    display name OR raw npc_id.
  - COLLECT <- EventHub.item_picked_up (NEW). Keys off
    item display_name/item_name; player via player_id/entity_id.
  - EXPLORE <- ZoneManager.player_entered_zone (NEW, 2026-09-25).
    Credits the trimmed zone convention AND the raw ZoneData id
    (dual-candidate law). "The Old Roads" (main_teachings) is the
    first consumer and is playable end-to-end; when a true world-
    waypoint wake mechanic lands, its events tick the same contract
    and stack additively.
  - The remaining 7 types have NO bridge yet -- they are
    await-callers (update_quest_progress) for the systems that own
    them (InventoryService craft paths for CRAFT, etc.). Wire on
    first use, test like the others.
- **Data:** `game/data/quests/*.tres` (QuestData schema: objectives
  array of {id, type, target, count}, rewards array, chain fields
  next_quest_id/previous_quest_id, required_quests, repeatable +
  cooldown, auto_complete). NPCs load from `game/data/npc/` -- the
  ONLY npc data dir (the old `game/data/npcs/` duplicates were
  migrated + deleted; ids are now npc_-prefixed, matching every
  consumer).
- **Tests:** `game/tests/test_quest_lore_bridges.gd` (TALK + COLLECT
  end-to-end, 8 asserts), `test_quest_explore_bridge.gd` (EXPLORE
  end-to-end, 6 asserts), `test_notif_migration_quest.gd` (10),
  `test_achievement_flow.gd`, `test_achievements.gd`.
- **Known drift:** village elder dialogue fixed to Gloomwood
  (prd-story.md sec. 10). Quest icon paths reference
  `res://icons/quests/` which is mostly empty -- icons are
  art-pipeline work (gemini_interiors_ui.md icon family).

## 6. Content queue (story-first build order)

1. **Act 1 spine (playable now):** Awakening -> The Old Roads ->
   2-3 more main_* beats ending at the Gloomwood gate. Every beat
   uses TALK/EXPLORE/COLLECT only (all three wired and tested).
2. **Dialogue depth:** village_elder_greeting is the only real tree;
   author per-institution greetings (smith, alchemist, storekeeper)
   with quest hooks, using the tone rules.
3. **Thread seeds:** one per faction method toward the Bloom
   (Alliance cuts, Horde wards, Collective listens) -- same Act 2
   area, three philosophies, shared world-state outcomes.
4. **Achievement listeners audit:** achievement_listeners.gd covers
   combat/horde/social; add wake-listeners when EXPLORE bridges land.
