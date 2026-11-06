# Subagent Task Board

Docs-only research tasks that can be handed to a subagent (OpenHands child
conversation) or worked inline. See `labs/prd-openhands-canvas.md` for how
subagent lanes run.

## How to use this board

- **Ground rule: everything you produce goes in `labs/` (markdown only).**
  Treat `game/` as **read-only context** for research — never edit GDScript,
  `.tscn`, `.tres`, or anything under `core/`, `scenes/`, `entities/`, `ui/`,
  `adapters/`. Never run terminal commands and never commit — produce docs;
  the maintainer (the dev lane) lands the good parts in data files and code.
- **Grounding:** read the files referenced in each task before writing, and
  keep every name, place, and fact you invent consistent with what they say.
  The world already has laws — extend them, don't contradict them.
- **House style for lore:** the world answers to a sky that everyone shares
  (one sun, one moon, real NOAA solar-wind weather), roads are walked by law,
  and authored things are honest about being built. Favor grounded, workday
  fantasy over drama: weather is a fact of life, not a plot device.
- **Status column:** update the state line of your task only (`draft`,
  `review`, `landed`, `wontfix`). Anything in `review` will be read by the
  maintainer before landing.

---

## Task 1 — NPC voice profiles + extended dialogue drafts — status: draft

**Read first:** `game/core/schemas/npc_data.gd`, `game/core/schemas/dialogue_data.gd`
(and search `game/` for the NPC ids you find there to see how dialogue nodes
are wired today — there are 5 dialogues loaded at boot).

**Produce:** `labs/story-dialogue-npcs.md` containing:
- One voice profile per NPC (the file says 9 NPCs are loaded): age, home,
  motivations, what they want from a stranger, five signature phrases.
- 3–6 new exchange lines each, tagged with the dialogue node id they'd slot
  into, plus the trigger condition (first meeting, after a fight nearby,
  during rain, during aurora — the weather service exposes band names).
- Flag anything that would need a schema field that doesn't exist yet
  instead of inventing it.

## Task 2 — Quest briefs for the loaded quests — status: draft

**Read first:** `game/core/schemas/quest_data.gd` schema (if present) and
search for the 9 quests loaded by DataService ("Loaded 9 quests" at boot —
find them under `game/data/`).

**Produce:** `labs/story-quest-briefs.md` — for each quest: narrative hook,
objective copy (what the quest tracker says), completion flavor text, reward
rationalization, and how it touches the world's facts (the capitol road, the
village harbor, the Sundered Sea). Do not change quest data fields; briefs
only.

## Task 3 — Acts/Almanac chronicle entries — status: draft

**Read first:** `game/core/services/sign_service.gd` (3 signs, 3 acts,
Concord clock), `game/core/services/acts_service.gd`, and this week's canon:
`labs/TASKS.md` turns 22–26 (shore foam, waterfall seams, tree density, the
capitol monolith, the bird chorus, the globe's weather events).

**Produce:** `labs/story-chronicle.md` — almanac-style entries: the three
signs' inscriptions, chronicle paragraphs for each act, the capitol
monolith's wrong-written history (who raised it, why the road ends there),
and the village's origin short. Names must match the canon bearings — the
capitol is the far-coast bearing at the harbor's own range.

## Task 4 — Weather & event lore — status: draft

**Read first:** `game/data/weather_events/*.tres`,
`game/core/schemas/weather_event_data.gd`, `game/core/frame/srv/weather.gd`
(two-provider law: cosmic primary, trad fallback), and the horde configs
under `game/data/` (5 loaded).

**Produce:** `labs/story-weather-events.md` — for the aurora window, storm
pack, and each horde config: what the sky/myth thinks is happening, what the
truth (the frame law) actually does, and one in-world rumination keepers could recite. Separate "what players are told" from "what happens"
— that separation is the world's own honesty law.

## Task 5 — Landmark naming pass — status: draft

**Read first:** `labs/TASKS.md` terrain turns (the globe, bands, ranges,
strait chart, underworld conjures: (`globe_world.gd`, `globe_underworld.gd`, `globe_moon.gd`,
`game/core/services/strait_chart.gd`), plus the biome list in the terrain
probes (climate probes enumerate the band census).

**Produce:** `labs/story-landmark-names.md` — a markdown table of proposed
names keyed to coordinates-bearing facts already in code: the great range
(the alpine crest law), the far coast (capitol), the ford and the harbor,
the underworld strata, the moon's meridian. For each: the name, a one-line
etymology, and the field in code it would attach to. NO code edits — name
choices only.

---

## Maintenance notes for the maintainer

- Landing a task = moving its content into `game/data/` or schema-bearing
  files yourself, then marking `landed` on the board.
- Keep the board small; add tasks one at a time. The board is a queue, not
  a catalog.
