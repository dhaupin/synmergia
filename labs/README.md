# `labs/`

Design, spec and research documents. Shipped code lives in `game/`, the web
client in `src/` + `web/`, services in `srv/`.

**This directory is not code truth.** Where a doc and the code disagree, the
code and its receipt win. `AGENTS.md` is the agent-facing reference and names
the receipts; this directory is where design intent, decisions and open
questions live.

> **Rule when touching a doc:** if a sentence names a system that no longer
> exists, fix the sentence in the same edit. Current offenders: the retired
> terrain renderer (`globe_terrain_streamer`), the planar world
> (`world_playable`, `player_controller`), `LODManager`, `backend_penrose`,
> and `SkillTier` (renamed `GameTier`). `legacy-inventory.md` tracks the
> migration status of each.

> **Checkpoint 2026-11-14 (labs drift pass).** 133 docs / 3.67 MB audited:
> every non-archive doc is indexed below (sub-READMEs included), every
> relative link resolves, `TASKS.md` is condensed, the lore series carries
> verified STATUS blocks, and the AGENTS round logs live in `AGENTS_LOG.md`.
> Superseded docs sit in `archive/` with a banner naming what replaced them.

## Where to start

| Question | Read |
| --- | --- |
| What is this game? | [`prd.md`](./prd.md) |
| How is the frame architected? | [`world-building-arch.md`](./world-building-arch.md) |
| How does terrain render and stream? | [`prd-clipmap.md`](./prd-clipmap.md), [`prd-terrain.md`](./prd-terrain.md) |
| How is data and persistence typed? | [`prd-db.md`](./prd-db.md) |
| What is dead, dormant or migrating? | [`legacy-inventory.md`](./legacy-inventory.md) |
| What is in flight right now? | [`TASKS.md`](./TASKS.md), [`subagent-tasks.md`](./subagent-tasks.md) |

## Status legend

- **ACTIVE** — living spec; edit it when the law changes.
- **TRACKER** — running list of work or migration; update in place.
- **REFERENCE** — decision record or point-in-time snapshot. Do not "refresh"
  casually; superseding it is a deliberate act.
- **LORE** — authored world content, canon rather than engineering.
- **ARCHIVED** — lives in [`archive/`](./archive/README.md); history only.

## Product and systems

| Doc | Status | Settles |
| --- | --- | --- |
| [`prd.md`](./prd.md) | ACTIVE | Product spec, progression, game-wide laws |
| [`prd-world.md`](./prd-world.md) | ACTIVE | World topology and player experience |
| [`territory-system.md`](./territory-system.md) | ACTIVE | Territory ownership: schema, service, guild/war wiring, limits |
| [`prd-web.md`](./prd-web.md) | ACTIVE | Web client, portal, admin |
| [`prd-quests.md`](./prd-quests.md) | ACTIVE | Quests and achievements |
| [`prd-social-instances.md`](./prd-social-instances.md) | ACTIVE | Social layer around instanced rooms |
| [`prd-ocean-depths.md`](./prd-ocean-depths.md) | ACTIVE | Swimming, water volumes, vessels |
| [`prd-ancient-movers.md`](./prd-ancient-movers.md) | ACTIVE | Dormancy, the mystery gate, movers |
| [`prd-monetization.md`](./prd-monetization.md) | ACTIVE | Priced seats, the Concord's table |
| [`prd-economy.md`](./prd-economy.md) | ACTIVE | The living economy: mint, move, melt |
| [`prd-vant-engines.md`](./prd-vant-engines.md) | ACTIVE | The engine block port and its drivers |
| [`prd-shard-mesh.md`](./prd-shard-mesh.md) | ACTIVE | Multi-container deployment |
| [`prd-agent-play.md`](./prd-agent-play.md) | ACTIVE | Agent control layer |
| [`prd-agent-law.md`](./prd-agent-law.md) | ACTIVE | Behavioral integrity for all accounts |
| [`prd-accessibility.md`](./prd-accessibility.md) | ACTIVE | Accessibility and agent-action layer |
| [`prd-perf-bridges.md`](./prd-perf-bridges.md) | ACTIVE | Julia / Redis bridge facets and their ledgers |
| [`prd-3d-pipeline.md`](./prd-3d-pipeline.md) | ACTIVE | Blender to Godot asset pipeline |
| [`prd-art-pipeline.md`](./prd-art-pipeline.md) | ACTIVE | Art lane: models, textures, generation |
| [`art-direction.md`](./art-direction.md) | ACTIVE | Style bible |
| [`data-authoring-baseline.md`](./data-authoring-baseline.md) | ACTIVE | How `.tres` content is authored and gated |
| [`prd-openhands-canvas.md`](./prd-openhands-canvas.md) | ACTIVE | Parallel agent lanes and their conventions |
| [`OSS-AUDIT.md`](./OSS-AUDIT.md) | REFERENCE | Open-source launch audit + post-public hardening |
| [`AGENTS_LOG.md`](./AGENTS_LOG.md) | REFERENCE | Archived AGENTS.md round logs (91 entries, 2026-10-28 .. 2026-11-16); history, not current law |
| [`jolt-playground/`](./jolt-playground/README.md) | REFERENCE | Jolt Physics evaluation plan; point-in-time |
| [`polyglot-ffi/`](./polyglot-ffi/README.md) | REFERENCE | Polyglot FFI port plan (cherry-picked from vant) |
| [`polyglot-ffi/julia-runtime/`](./polyglot-ffi/julia-runtime/README.md) | REFERENCE | Julia sidecar design for hot math paths |
| [`h2-perf-ledger.md`](./h2-perf-ledger.md) | REFERENCE | Lane H2 terrain performance ledger |

## Terrain

| Doc | Status | Settles |
| --- | --- | --- |
| [`prd-clipmap.md`](./prd-clipmap.md) | ACTIVE | The sole terrain renderer: rings, water sheet, road deck, prop layer |
| [`prd-terrain.md`](./prd-terrain.md) | ACTIVE | Biomes, surface look, hydrology, progression |
| [`clipmap-fold-survey.md`](./clipmap-fold-survey.md) | TRACKER | What else folds into the provider path; A3/A4 still open |
| [`prd-ground-sample.md`](./prd-ground-sample.md) | REFERENCE | Completed ground-law fusion refactor |
| [`legacy-inventory.md`](./legacy-inventory.md) | TRACKER | Migrate / port / remove census; also the KEEP verdict on isoc addressing |

## Frame substrate (design PRDs, Sept–Oct)

Decision records for systems that largely shipped. **REFERENCE**: verify a
claim against the code before citing it as current.

[`prd-frame-authority`](./prd-frame-authority.md) · [`prd-open-seed-ttl`](./prd-open-seed-ttl.md) ·
[`prd-critical-params`](./prd-critical-params.md) · [`prd-seed-schema`](./prd-seed-schema.md) ·
[`prd-login-seed-chain`](./prd-login-seed-chain.md) · [`prd-manifest-backup`](./prd-manifest-backup.md) ·
[`prd-state-schema`](./prd-state-schema.md) · [`prd-t3-substrate`](./prd-t3-substrate.md) ·
[`prd-scope-engine`](./prd-scope-engine.md) · [`prd-geometry`](./prd-geometry.md) ·
[`prd-world-layers`](./prd-world-layers.md) ·
[`prd-multiworld`](./prd-multiworld.md) · [`prd-spherical-mvp`](./prd-spherical-mvp.md) ·
[`prd-underworld`](./prd-underworld.md) · [`prd-ward-gate`](./prd-ward-gate.md) ·
[`prd-mounts`](./prd-mounts.md) · [`prd-crafting`](./prd-crafting.md) ·
[`prd-gathering`](./prd-gathering.md) · [`prd-blacksmith`](./prd-blacksmith.md) ·
[`prd-bout-host`](./prd-bout-host.md) · [`prd-industry-labs`](./prd-industry-labs.md) ·
[`prd-psy`](./prd-psy.md)

## World-building series

| Doc | Status | Settles |
| --- | --- | --- |
| [`world-building-arch.md`](./world-building-arch.md) | ACTIVE | Systems architecture; cited by code as the frame reference |
| [`world-building-tick.md`](./world-building-tick.md) | ACTIVE | The tick end to end; cited by `tick_service.gd` |
| [`world-building.md`](./world-building.md) | REFERENCE | The original world/netcode/persistence plan; cited by code for section numbers |
| [`world-building-risks.md`](./world-building-risks.md) | REFERENCE | Risk register, decisions, numbers, glossary |
| [`world-building-research.md`](./world-building-research.md) | REFERENCE | Research notes and discarded angles |
| [`world-building-spherical.md`](./world-building-spherical.md) | REFERENCE | Spherical planet and navigation specifics |

This series is the largest single body of prose in the repo (~11.4k lines) and
the most likely home of superseded design. It has not yet had a consolidation
pass; treat older sections as history, and prefer `prd-clipmap.md` for anything
terrain-shaped.

## Lore and voice

| Doc | Status | Settles |
| --- | --- | --- |
| [`prd-story.md`](./prd-story.md) | LORE | Story and world lore |
| [`prd-dialogue.md`](./prd-dialogue.md) | LORE | Dialogue system and design bible |
| [`story-chronicle.md`](./story-chronicle.md) | LORE | Concord Chronicle almanac entries |
| [`story-dialogue-npcs.md`](./story-dialogue-npcs.md) | LORE | NPC voice profiles and drafts |
| [`story-dialogue-creative-voice.md`](./story-dialogue-creative-voice.md) | LORE | Dialogue creativity mode |
| [`story-landmark-names.md`](./story-landmark-names.md) | LORE | Landmark names keyed to world coordinates |
| [`story-voice-concord.md`](./story-voice-concord.md) | LORE | The Concord as a reading culture |
| [`story-weather-events.md`](./story-weather-events.md) | LORE | Weather and event lore |

Every doc in this table now carries a verified **STATUS** block from the
2026-11-14 fiction pass, naming what is backed by `game/data` and what exists
only as prose. The checks were concrete: acts (3 files, 9 gated chapters),
weather events (all 5 named events ship), Chronicle puzzles (5 ship; three
authored 2026-11-14 from the five open questions), dialogues (20 resources), and
landmark strings (all 7 named anchors now ship as `data/landmarks/*.tres`
via the atlas; map adoption lands with the map overhaul).

## Trackers and session state

| Doc | Status | Settles |
| --- | --- | --- |
| [`TASKS.md`](./TASKS.md) | TRACKER | Session state; condensed 2026-11-14 (digest + recent sessions, full log in `TASKS_ARCHIVE.md`) |
| [`TASKS_ARCHIVE.md`](./TASKS_ARCHIVE.md) | REFERENCE | Verbatim log of sessions before 2026-09-23 |
| [`subagent-tasks.md`](./subagent-tasks.md) | TRACKER | Task board for parallel lanes |
| [`lanes/`](./lanes/) | REFERENCE | Per-lane briefs and resumes (A–M) |
| [`lane-smoke/`](./lane-smoke/) | REFERENCE | Lane smoke-test reports and maps |
| [`prompts/`](./prompts/) | REFERENCE | Prompt packets for content generation |

## Consolidation backlog

Proposed passes, cheapest first. Nothing here is started unless noted.

1. **DONE 2026-11-14 — `TASKS.md` condensation.** 10,337 -> 1,015 lines:
   digest + 68 recent sessions, 163 older sections verbatim in
   `TASKS_ARCHIVE.md`. Next condensation when the file passes ~2.5k lines.
2. **DONE 2026-11-14 — `prd-geometry` + `prd-spatial-geometry`.** The
   spatial doc was a subset of the canonical one (both fragmenters, bit
   layout, service wiring); it is archived at
   `archive/prd/prd-spatial-geometry.md` and `prd-geometry.md` is the single
   source of truth. 375 + 199 -> 376 lines.
3. **`prd-art-pipeline` + `prd-3d-pipeline`** — overlapping asset-pipeline
   docs, 88 + 198 lines. One lane document with two sections. Not yet done.
4. **`prd-dialogue` + `story-dialogue-creative-voice`** — 633 + 219 lines; the
   second is a working note inside the first's subject. Not yet done.
5. **`world-building` series** — 11.4k lines total. VERDICT 2026-11-14:
   `-research` (1,737 lines) CANNOT be archived as-is -- it is cited by
   `prd.md`, `world-building.md`, `-tick`, `-risks` and by
   `game/core/frame/math/penrose.gd` sec 1. Keeping `-arch` + `-tick` ACTIVE
   is confirmed; any future fold must repoint those citations first.
6. **Agent-law trio** (`prd-agent-play` 517, `prd-agent-law` 89,
   `prd-accessibility` 187) — check for duplicated law before merging; these
   may be three genuinely different concerns. Not yet done.

## Drift audit (2026-11-14)

Method: every `.md` under `labs/` was scanned for (a) relative links that do
not resolve, (b) files absent from this index, (c) the retired-system terms
named in the rule at the top, and (d) `game/...` paths that no longer exist.

Result: **133 docs / 3.67 MB. 0 broken links, 0 unindexed non-archive docs**
(`labs/README.md` is the index itself). Retired-system terms survive only in
history: `TASKS_ARCHIVE`, `AGENTS_LOG`, `archive/`, lane briefs, and the
trackers that deliberately record them (`clipmap-fold-survey`,
`legacy-inventory`). 67 dead `game/` paths remain in exactly those historical
docs; the two live REFERENCE PRDs that cited moved schemas
(`prd-seed-schema`, `prd-state-schema`) were repointed to
`game/core/frame/schemas/`.

Re-run the audit before claiming the labs are clean again. It is a scan, not a
proof of prose truth: claims still have to be checked against code, which is
what the STATUS blocks and `legacy-inventory.md` are for.

## Archive

[`archive/`](./archive/README.md) holds superseded docs: old architecture
notes, session logs, gap analyses, and completed PRDs. Do not trust it without
checking the code.
