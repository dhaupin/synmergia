# Next Agent Pickup Guide

**Last session:** 2026-08-29 / 2026-08-30 (OpenHands, west coast throttling)
**Sessions 2026-08-30:** Morning (7 commits, fun-side) + Afternoon (5 commits, species/classes/char select) + Evening (class/skill fixes + scene wiring + loot + NPC verification)
**Last push:** `a39cdc0` on `main`, `origin/main`
**Current HEAD:** `f148862` — 15 commits ahead of `origin/main`, NOT pushed yet
**Status:** Islands POC shipped (19/19 tests). Project still has 22
class_name cascade errors (deferred). Most architecture decisions made.
**Latest design decision:** content-hash is a Redis-like *layer* in front
  of Postgres, not a replacement. State tree is the new big thing.

## What Was Done This Session (2026-08-30 morning)

7 commits, 979 lines, 24 files changed (all ahead of `origin/main`):

| Category | Files |
|----------|-------|
| Skills (12 total) | basic_attack, shield_bash, charge, battle_shout, shield_wall, whirlwind (warrior); magic_missile, arcane_shield, fireball, frost_nova, arcane_barrage, chain_lightning (mage) |
| Enemies | enemy_wolf.tres (lvl 3 social aggro), enemy_bandit.tres (lvl 5 humanoid) |
| Zones | zone_forest_meadow, zone_dungeon_forest_depths, zone_village_center (wires up existing gateways) |
| Species | (removed elf/orc — too cliche; human/akkan/synthetic already existed) |
| Classes | class_mage.tres (glass cannon, mana, cloth only) |
| Scenes | entities/enemy.gd (Enemy class), scenes/world_playable.tscn (player + 2 slimes), wired into GameManager |
| Misc | main_menu.gd Play button → PLAYING; zone data wires all existing gateways |

## What Was Done This Session (2026-08-30 afternoon)

5 commits — 3 species, 2 new warrior classes, character select, full flow:

### Species (3 — human/akkan/synthetic all pre-existed, very distinct)
All 3 species were already in data/species/ with detailed stat modifiers, factions, visual options.

### Classes per Species
- **Human warrior** — +shield_toss (lvl 25 signature: ranged stun, 20dmg)
- **Akkan attacker** — 6 skills: stomp+rend @ lvl 1; battle_cry @ 5; **ground_bash** @ 10 (SIGNATURE: ground-targeted AoE, 35 dmg + slow); blood_fury @ 15; seismic_slam @ 20
- **Synthetic warrior** — 6 skills: energy_strike+**overclock** @ lvl 1 (SIGNATURE: 8s speed buff); hack_pulse @ 5; plasma_cutter @ 10; nanite_swarm @ 15 (heal+dmg); system_crash @ 20
- **Mage** kept as human-only (glass cannon, mana)

### Character Select Screen
- **species_card.tscn/.gd** — card with name, faction, description, stat modifiers
- **class_card.tscn/.gd** — card with name, role, resource type, armor types, skill count
- **character_select.tscn/.gd** — grid of species cards → class cards on selection → Enter World
- **character_data.gd** — CharacterData schema with get_all_species(), load_class(), get_available_classes_for_species()
- **world_playable.gd** — scene root reads GameManager.selected_character_data
- **game_manager.gd** — selected_character_data field; PLAYING uses change_scene_to_file (clean replacement)
- **main_menu.gd** — restored CHARACTER_SELECT path

**Play path:** Main menu → Character Select (species → class → Enter World) → World (green floor, player + 2 slimes + wolf + bandit with loot)

## What Was Done This Session (2026-08-30 evening)

15 commits total ahead of `origin/main`:

### Data fixes
- Human warrior: removed whirlwind (7 → 6), added war_cry @ lvl 30 (SIGNATURE: party dmg buff, self-buff doubled if solo)
- Akkan attacker: unchanged, ground_bash is signature (ground-targeted AoE)
- Synthetic Exploiter: renamed from warrior, all 6 skill files renamed with _exploiter suffix, IDs updated, overclock now says "skill cooldowns regenerate faster" + "doubled self-buff if no party"
- Whirlwind removed (was leftover from 7-skill warrior plan)

### Scene wiring
- StateMachine node has state_machine.gd script attached
- 4 state children wired: Idle (idle.gd), Run (run.gd), Jump (jump.gd), Fall (fall.gd)
- Added wolf at (-5, 0.4, 6) with loot_wolf factory
- Added bandit at (8, 0.9, 3) with loot_bandit factory

### Loot system
- loot_tables/loot_wolf.gd: health potions, soul gems (rare), ancient coins, gold 2-8
- loot_tables/loot_bandit.gd: health potions, ancient coins, iron sword (10%), leather chest (rare), gold 5-20
- enemy.gd: added loot_factory_class export, _roll_and_drop_loot() called on death, logs loot to console
- NPCs confirmed: blacksmith_village_default + merchant_general_default already exist with full data

This document is the survival guide. Read this first, then the linked
docs in order.

---

## TL;DR for the next agent

Synmergia is a Godot 4.7.2 MMORPG engine. The previous session:

1. Fixed 30+ parse errors across services, UI, and `.tres` files
2. Built a working Islands POC (3 files + 19 passing tests)
3. Wrote 5 design docs (`docs/architecture/`)
4. First honest evaluation: "demote the geometry" — **was wrong**
5. Revised honest evaluation: "geometry is right for a Redis-like
   layer, not a replacement" — was on the right track but flat
6. The actual frontier: **multi-iso orchestrator as a frame**, not
   a feature. Spawn 2+ isos, intersect them, reserve NSC-9 ranges
   per axis. See `multi-iso-frame.md`.

The user caught TWO framing errors:
- First: I was treating the geometry as a *replacement* for
  things Synmergia already has. The user meant it as an
  *extension*. → Revised to redis-like layer.
- Second: even as a layer, treating it as flat KV is "overbuilt
  for internal KV." The actual leverage is **multi-dimensional
  intersection**: spawn N isos, intersect them, get
  multi-dimensional queries. → Multi-iso orchestrator pattern.

**Where to pick up:**
- **Track A, Session 3** (state tree) is the practical foundation.
- **Track A, Session 2** (UIPanel → islands) is UI work.
- **Track B, Session B1** (math primitives) is the research
  start for the multi-iso frame. The frame can be extracted
  later to a separate repo alongside vant.
- The shim approach for the 22 cascade is still independent and
  still worth finishing.

**The 22 cascade failures are still there.** They're non-fatal
("Main menu loaded" still prints) but they pollute the log. Fix
them with the shim approach when convenient. They're not blocking.

**Two-track plan.** Track A is the product (Synmergia). Track B
is the frame (multi-iso orchestrator, alongside vant). They share
the state tree but are otherwise independent.

**Future-work candidates (also drafted 2026-08-30):**
- **Jolt Physics** (`labs/jolt-playground/`) — swap-in benchmark.
  Decision deadline is Phase 5 (World Building). Important for
  hash determinism, which the state tree depends on.
- **Polyglot FFI** (`labs/polyglot-ffi/`) — pattern lifted from
  vant `lib/compute.js`. Lets the frame call into Julia, Python,
  Rust from GDScript. The `julia-runtime/` is the first concrete
  implementation. Use case: vector math hot paths (spatial
  queries, intersection materialization, LOD batch ops).
- **Three tiers of computation.** GDScript for game logic,
  Julia for vector math, C++/GDExtension for the absolute hot
  path. The frame's design budget assumes all three exist.
- **The grail path** (`docs/architecture/grail-path.md`) —
  the pre-materialized orchestration contract. The state IS
  the answer; the math is the rebuild step, async, batched,
  off the read path. The multi-iso orchestrator already has
  the components; the grail is the commitment (5 small
  changes: `tick()` method, composite tables as canonical
  read source, re-root on tick not demand, math as pure
  function, pre/mid/post types explicit).

---

## Repo layout

```
.
├── synmergia/         # the Godot 4.7.2 project
│   ├── core/
│   │   ├── autoload/      # 30+ autoloads (the source of the cascade)
│   │   ├── components/    # HealthComponent, CombatComponent, etc.
│   │   ├── community/     # CommunityGovernance
│   │   ├── entities/      # Entity base class
│   │   ├── events/        # event_hub.gd (EventBus)
│   │   ├── schemas/       # Item, EnemyData, TargetSchema, etc.
│   │   ├── services/      # 30+ services (consume primitives from /labs)
│   │   ├── targeting/     # TargetingManager
│   │   └── ui/            # UIManager
│   ├── data/              # .tres files (factions, species, zones, items, ...)
│   ├── entities/          # Player, Enemy, NPC concrete entities
│   ├── scenes/            # Main scene
│   ├── scripts/           # state.gd, state_machine.gd
│   ├── ui/
│   │   ├── admin/         # admin_dashboard, admin_toolbar
│   │   ├── community/     # voting_ui
│   │   ├── components/    # cooldown_bar, action_menu, tooltip
│   │   ├── islands/       # THE POC — placeholder, registry, manager
│   │   ├── menus/         # main_menu
│   │   ├── player/        # report_dialog, player_target_tooltip
│   │   ├── respawn/       # respawn_ui
│   │   ├── social/        # guild/party/trade UIs
│   │   └── targeting/     # target_frame
│   ├── tests/             # test_islands.gd (19 tests, cross-cutting)
│   ├── docs/architecture/ # 7 design docs
│   ├── project.godot      # autoload list lives here
│   └── AUDIT.md.session-log           # session log (legacy)
├── labs/                # ROOT-LEVEL: experimental work, aside from game
│   ├── README.md          # the convention
│   └── multi-iso/         # PLANNED: the multi-iso frame work
│       ├── math/          # NSC-9, icosahedral, quasicrystal (B-1)
│       ├── kv/            # LRU, content_hash, state_tree (A-3, B-6)
│       ├── srv/           # markov, predictor, composite_table, LOD, axes (B-6/7/8)
│       ├── db/            # snapshot_store, migrations (A-3)
│       └── tests/
├── docs/                # ROOT-LEVEL: top-level docs (this file lives here)
├── .gitignore           # .godot/, *.uid, tools/ all ignored
└── tools/
    └── godot            # Godot 4.7.2 binary (gitignored, ~150MB)
```

**Why `/labs` at the root?** The user wanted it aside from the
Godot project so experimental code doesn't taint the stable game.
The Godot folder stays clean. Labs work happens in `/labs`.
Graduated work moves into the game.

---

## Key files (read these first)

| File | Why it matters |
|------|----------------|
| `AUDIT.md` | The running log of what's been done, deferred, broken (legacy, now at `labs/AUDIT.md.legacy`) |
| `AGENTS.md` (repo root) | Project-wide conventions, naming, services list |
| `docs/architecture/NEXT-AGENT-PICKUP.md` | This file |
| `docs/architecture/islands-builds-godot.md` | The Islands design |
| `docs/architecture/unified-nsc9-islands-builds.md` | The unified design (mark as exploration) |
| `docs/architecture/nsc9-honest-evaluation.md` | Why we demoted most of the unified design (revised 2026-08-30) |
| `docs/architecture/multi-iso-frame.md` | The multi-iso orchestrator (Part 1: the basic pattern) |
| `docs/architecture/multi-iso-lod-prediction.md` | Part 2: LOD + materialized + prediction (the golden state) |
| `docs/architecture/grail-path.md` | **NEW** The pre-materialized orchestration contract (the read = lookup commitment) |
| `docs/architecture/vant-lift.md` | **NEW** Lift manifest: 9 vant libs → multi-iso frame primitives, with priority order |
| `docs/architecture/security.md` | **NEW** Security analysis: 7 defense layers, recursion guard as foundation, agent framework threat model |
| `docs/architecture/ui-framework.md` | **NEW** UI reactive bridge: the AxisQuery + UIAction model, the schema-driven framework that humans and agents can both render |
| `docs/architecture/scale-200km2.md` | **NEW** 8 innovations for the 200km² world: LOD pyramid, predictive prefetch, multi-axis intersection, state diff sync, hierarchical sync, content-hash addressing, RAM+Postgres split, procedural assimilation |
| `docs/architecture/labs-organization.md` | Independent primitives in `labs/multi-iso/` (the frame staging area) |
| `docs/architecture/autoload-race-solutions.md` | The 4 candidate fixes for the cascade |
| `labs/README.md` | In-tree convention for labs (root-level) |
| `labs/prd.md` | The Synmergia PRD (modernized 2026-08-30, includes the frame appendix) |
| `labs/jolt-playground/README.md` | The Jolt Physics decision (Phase 5 deadline) |
| `labs/polyglot-ffi/README.md` | The Polyglot FFI (lifted from vant) |
| `labs/polyglot-ffi/julia-runtime/README.md` | The Julia server-side math runtime |
| `synmergia/ui/islands/island_placeholder.gd` | POC entry point |
| `synmergia/ui/islands/island_registry.gd` | Static island → PackedScene map |
| `synmergia/ui/islands/island_manager.gd` | Mount orchestrator |
| `synmergia/tests/test_islands.gd` | 19 passing smoke tests |
| `synmergia/core/autoload/type_registry.gd` | Preload table (modified but uncommitted if any) |

---

## How to run the tests

```bash
cd /workspace/project/synmergia
chmod +x tools/godot
tools/godot --headless --path synmergia --script res://tests/test_islands.gd
```

Expected output: `=== Results: 19 passed, 0 failed ===` at the end.

The 22 "Could not find type" cascade errors are still in the log
but they don't fail the test. They're noise from a separate problem
(see autoload-race-solutions.md).

---

## What is the Islands POC?

Three files in `synmergia/ui/islands/`:

1. **`island_placeholder.gd`** (`class_name IslandPlaceholder`)
   - Drop into any scene
   - Set `island_name` (e.g. "inventory") and `load_strategy` (eager/visible/idle)
   - Set `island_scene` (optional override)
   - On `_init`, adds itself to group `"island_placeholders"`

2. **`island_registry.gd`** (`class_name IslandRegistry`)
   - Static const map: `ISLANDS = { "name": PackedScene, ... }`
   - 8 existing scenes wired in, 12 future ones pre-commented
   - Static helpers: `resolve(name)`, `has(name)`, `all_names()`,
     `islands_triggered_by(text)` (for chat hydration)

3. **`island_manager.gd`** (`class_name IslandManager`)
   - `mount_placeholders(root: Node) -> int`
   - Scans root for placeholders, replaces each with the registered scene
   - Strategies: eager (immediate), visible (when in viewport), idle (3 frames later)
   - Emits `island_mounted` / `island_skipped` signals
   - Idempotent (mounted placeholders skipped on second pass)

Plus the test file (`synmergia/tests/test_islands.gd`) — 19 tests
covering registry, placeholder lifecycle, manager mount/skip paths.

---

## What's NOT done (pending)

From `labs/AUDIT.md.legacy` and session notes:

**Architectural decision (recorded 2026-08-30):** Schemas
(`synmergia/core/schemas/`) and `/data/*` extensions are
**stable** and not to be refactored without explicit user
direction. All other parts of the codebase are fair game
for refactor. The schemas and data are the contract;
everything else serves them.

### Still Pending

1. **`guild_service.gd`, `party_service.gd`, `chat_service.gd`** still
   have `:=` inference warnings (treated as errors by parser). 8
   warnings × multiple lines. Need explicit type annotations.

2. **Autoload class_name shim layer.** The pending item is
   `core/type_shims.gd` — `const Entity = preload(...)` etc. for
   ~22 cascade-affected types. This closes the parse-time race
   without restructuring the autoload list.

3. **`inventory_component.gd` unindent** — pre-existing issue, deferred.

4. **`GameConfig.*` → `_get_config_*` helpers** — large migration,
   pre-existing pending item. Not blocking.

5. **UIPanel → Island migration.** Currently 8-12 panels still extend
   UIPanel. Convert each to a PackedScene with IslandPlaceholder as
   root. Add to registry. See cookbook above.

6. **Content-hash for templates.**
   `core/geometry/content_hash.gd` — SHA-256 helper. Apply to item
   templates, loot rolls, save verification.

7. **Build pipeline.**
   `tools/build.sh` — `godot --headless --export-pack data data.pck`.
   CI on changes to `synmergia/data/`.

8. **Loot tables** — ✅ `loot_tables/loot_wolf.gd` and `loot_bandit.gd` done. Wired into enemy.gd via `loot_factory_class` export.

9. **NPCs** — ✅ `blacksmith_village_default` and `merchant_general_default` already existed in data/npcs/. Confirmed complete.

10. **Ranger class** — hunter archetype, pet mechanics, ranged skills (aimed_shot, multi_shot, traps).

11. **StateMachine scene wiring** — ✅ Done. StateMachine node has script, all 4 states wired.

12. **Add wolf and bandit to world scene** — ✅ Done. Added to world_playable.tscn with loot.

---

## What's been DEMOTED (do not implement)

The following are in `unified-nsc9-islands-builds.md` but should NOT
be implemented (see `nsc9-honest-evaluation.md` for why):

- `core/geometry/nsc9.gd` — 12-digit barcode ID format
- `core/geometry/icosahedral.gd` — icosahedral projection for shards
- `core/geometry/quasicrystal.gd` — file-paths-from-content scheme
- The "fragment across 5 backends" / "Penrose tiling" / "shard by
  icosahedral vertex" patterns

If the user asks to implement these, point them to the honest
evaluation first. We agreed not to.

---

## How to add a new Island (cookbook)

User: "I want a settings panel to mount when the player opens settings."

1. Create the panel scene at `res://ui/panels/settings_panel.tscn`
   with a script that extends Control (NOT UIPanel — see Session 2
   migration).

2. In `synmergia/ui/islands/island_registry.gd`, add:
   ```gdscript
   const SETTINGS := preload("res://ui/panels/settings_panel.tscn")
   ```
   And in the `ISLANDS` dict:
   ```gdscript
   "settings": SETTINGS,
   ```
   (Add to TRIGGERS too if you want chat-command hydration.)

3. In the scene where you want it, add an IslandPlaceholder:
   ```gdscript
   [node name="SettingsPlaceholder" type="Node" parent="UI"]
   script = ExtResource("island_placeholder.gd")
   island_name = "settings"
   load_strategy = "idle"
   ```

4. Call `IslandManager.mount_placeholders(scene_root)` after scene
   load (typically in `GameManager._ready()` or
   `ZoneManager._on_zone_loaded()`).

5. To pre-load on chat input:
   ```gdscript
   IslandManager.hydrate_for_input("/settings")
   ```

6. Run the tests: `tools/godot --headless --path synmergia --script res://tests/test_islands.gd`.
   All 19 should still pass.

---

## What the user wants (personality notes)

- **Frequent small pushes.** Push after every meaningful change, not
  in big batches. Rate limits are real; small commits are easy to
  rebase / recover.
- **Go slow during west coast prime time** (~6-10pm Pacific).
  OpenRouter throttling has caused real issues this session.
- **Honest about uncertainty.** "I don't wanna pressure if it's not
  an efficient angle for real world use" — when the user pushes back
  on a design, take it seriously. Don't defend an idea past its
  useful life. The honest evaluation doc came directly from this.
- **Cross-pollinates from other projects.** User maintains
  `prestruct` (React SEO prerender) and `vant` (Node AI memory
  system). Pattern reuse is encouraged. Cross-project ideas are
  welcome but should be evaluated honestly before adoption.
- **Uses "raw dog" to mean "unframeworked / build-it-yourself."**
  Anti-framework, pro-direct-code. When in doubt, fewer abstractions
  win.

---

## If you crash, the user has said:

> "Please ensure this is all documented in case we crash, so next
> agent picks up."

So this doc exists. If you (the next agent) are reading this
because the previous session crashed, the most important things
are:

1. **Last push is at `3e942bb`.** That's the working state.
2. **Tests pass at that commit.** Run them to confirm.
3. **22 cascade failures are noise, not blockers.** Don't chase
   them before shipping features.
4. **The honest evaluation is binding.** Don't re-implement the
   icosahedral/NSC-9 stuff without the user explicitly asking
   for it after reading the evaluation.

If anything is unclear, read `labs/AUDIT.md.legacy` (the old
session log) and `docs/architecture/` (the design space). The
git history has the actual diffs.
