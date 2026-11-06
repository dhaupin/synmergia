# PRD -- Planar Retirement (the two-worlds debt)

> **Status:** SCOPED 2026-11-06. Owner confirmed retirement is wanted.
> This PRD exists because the naive read -- "delete world_playable" --
> is WRONG and would delete live gameplay. Read sec 2 before touching
> anything.

## 1. The finding (why this is bigger than a deletion)

`project.godot` sets `world/shape="spherical"`, so the live game boots
`globe_world.tscn`. The planar `world_playable.tscn` + `player_controller.gd`
are dead *code paths* -- but they are NOT dead *content*. The planar
scene is the only place that wires up a whole tier of gameplay, and the
globe never picked it up. Diffing the two scenes' feature sets:

| System | `world_playable` | `globe_world` | Live on the planet? |
|---|---|---|---|
| Sky signs (`_setup_sky_signs`) | yes | **no** | **NO** |
| Ancient door (`_setup_ancient_door`) | yes | **no** | **NO** |
| Moon gate (`_setup_moon_gate`) | yes | **no** | **NO** |
| Ascent gate (`_setup_ascent_gate`) | yes | **no** | **NO** |
| Concord stone (`_setup_concord_stone`) | yes | **no** | **NO** |
| Blessed marks (`_setup_blessed_marks`) | yes | **no** | **NO** |
| Housing (`_setup_housing`) | yes | **no** | **NO** |
| Portal (`_setup_portal`) | yes | **no** | **NO** |
| Guards (`_setup_guards`) | yes | **no** | **NO** |
| Scene enemies + respawn (`_setup_enemies`) | yes | **no** | **NO** |
| Ground loot handlers | yes | **no** | **NO** |
| Kill-reward handler | yes | **no** | **NO** |
| Damage numbers | yes | **no** | **NO** |
| Starter quest auto-accept | yes | **no** | **NO** |
| Sun / sky sun (`_setup_sky_sun`) | yes | yes | yes |
| Ambience / weather | yes | yes | yes |
| Touch HUD | yes | yes | yes |
| HUD bridge | yes | yes (`_install_hud`) | yes |

**The flagship one:** `ActsService` (the Concord Chronicle) resolves
`get_nodes_in_group("ancient_doors")` and connects `door_opened`. Only
`world_playable._setup_ancient_door()` ever creates an `AncientDoor`.
So on the planet the door never exists, the chronicle never records a
chapter, and the whole "watch the sky -> solve the day -> the door
opens at dawn" loop is **dead gameplay**. Same class of gap for the
moon gate (S16 transit), housing, guards, and the kill/loot feedback.

This is very likely the "agents are confused" root cause the owner
named: half the systems live in a scene nobody boots, and the other
half live in the scene everybody boots, with no map saying which is
which.

## 2. What "planar" actually means (two different things)

Do NOT conflate these:

1. **The planar WORLD path** -- `world_playable.{gd,tscn}` +
   `entities/player/player_controller.gd` + the `WorldShape.PLANAR`
   branch in `GameManager`. This is the retirement target.
2. **The PLANAR INSTANCE contract** -- `core/schemas/instance_contract.gd`
   locks arena/duel/dungeon to planar AABB with vanilla -Y gravity
   (`gravity_contract()` returns `shape: "planar"`), consumed by
   `scenes/instances/arena_instance.gd` + `arena_fighter.gd`. This is
   **correct and stays** (locked decision 3, `labs/prd-spherical-mvp.md`
   sec 2). Instances are the ONE legitimate planar surface.

The `WorldShape` knob itself can stay (the parameter contract is real),
but once (1) is retired its `PLANAR` arm means "instance" only.

## 3. The plan (port first, delete last)

Each phase is independently receipt-gated. Nothing is deleted until the
feature it carries is proven present on the globe.

### Phase 0 -- Inventory + law (this PRD)
- Done: the table above, from the scene diff. Extend it as each phase
  is scoped (per-system receipt names).

### Phase 1 -- Port the missing systems to the globe
For each row marked "NO", port `_setup_X` from `world_playable` into
`globe_world` (or, better, into a shared world-content builder both
scenes call, so the two can never drift again). Order by gameplay
value:
1. **Skyward Concord**: sky signs + ancient door + concord stone +
   blessed marks. Receipt: a globe boot where the door exists, is in
   `ancient_doors`, and `ActsService` sees it; a `door_opened` records
   a chapter on the globe.
2. **Enemies + respawn + kill/loot/quest/damage feedback** on the
   planet. Receipt: a globe boot that spawns a scene enemy, kills it,
   and shows the reward/loot rows.
3. **Gates**: moon gate + ascent gate (S16 transit reachable from the
   planet). Receipt: the moon gate exists on the globe and completes
   transit.
4. **Guards + housing + portal + starter quest**. Receipts per system.

### Phase 2 -- Flip the default fully spherical
- `world/shape` stays spherical; remove the `world_playable` branch in
  `GameManager._start_game` (or leave it but make the planar arm
  unreachable/instance-only). Receipt: `test_world_shape` updated.

### Phase 3 -- Delete the planar world path
- Delete `scenes/world_playable.{gd,tscn}` and
  `entities/player/player_controller.gd` -- but ONLY after grepping
  every reference (the planar `PlayerController` class is referenced by
  ~20 files; most are type-annotation / duck-typed and must be retargeted
  to the globe body's surface, or the shared base if one is extracted).
- Receipt: full boot probe on the globe + the default runner set green.

### Phase 4 -- Shared world-content builder (the durable fix)
- The reason the two scenes drifted is that each hand-wrote its own
  `_setup_*` list. Extract a `WorldContentBuilder` (or a data-driven
  content manifest) so a world scene declares WHAT it contains and the
  builder places it. Then "the globe is missing X" becomes impossible --
  X is declared once.

## 4. Risks

- **The globe body is not recognized as a player by the shared systems.**
  CONFIRMED structural finding: `player_controller.gd` is
  `class_name PlayerController`; the globe body is `class_name
  GlobeWorldPlayer`. They are SIBLINGS (`extends CharacterBody3D` each) --
  there is NO shared base. ~20 files gate on `is PlayerController`:
  `targeting_manager.gd:571` refuses to resurrect anyone who is not a
  `PlayerController`; `health_component.gd:81` types the killer,
  `:196` emits `player_died`, `:204` emits `player_killed_player` only
  for `PlayerController`. So on the planet, resurrection targeting and
  the player-death/PvP signals do not fire for the real player. The
  codebase already knows this -- `globe_underworld.gd:885` and
  `hud_integrator.gd:408` both note globe bodies "carry no entity_type".
  **This is the actual root cause of the two-worlds confusion**: the
  shared gameplay services were written against the planar controller's
  type, and the globe body silently falls outside them.
- **Type coupling.** `player_controller.gd` is `class_name`-referenced
  by 64 files (most duck-typed, but the `is PlayerController` gates are
  real behavior). Deleting it is not a file rm; it is a retarget of every
  `PlayerController` annotation to the globe body -- which only works
  once there is a SHARED player base both extend. That extraction is the
  keystone of Phase 3/4.
- **The globe body is a partial player.** It lacks `use_skill` (ActionBar
  no-ops), lacks the progression fields (`experience`/`gold`/`level` --
  the autosave guard added 2026-11-06bh), and lacks `entity_type`. Every
  ported system needs the globe body to grow the surface the planar
  controller already has -- or the shared base to own it.
- **Regression surface.** Every ported system needs its own receipt; a
  bulk port with one receipt is exactly how this debt was created.

## 4b. Recommended keystone (do this before Phase 3)

Extract a shared **player base** (`entities/player/player_base.gd`,
`extends CharacterBody3D`) owning the surface the shared systems gate on:
`entity_type`, `use_skill`, the progression fields (`experience`, `gold`,
`level`, the add/get methods), `health_component`, and the player-death
signal emission. Then `PlayerController extends PlayerBase` and
`GlobeWorldPlayer extends PlayerBase`, and the ~20 `is PlayerController`
gates become `is PlayerBase`. That single change:
- makes resurrection/death/PvP signals fire on BOTH worlds,
- gives the globe body a real progression surface (autosave honest),
- lets Phase 3 delete `player_controller.gd` by folding its unique legs
  into the base + globe body.

This is the highest-leverage step and should be its own receipt-gated
arc, not a side-effect of the deletion.

## 5. Lane D (modeling/assets) -- separate, tracked in the Canvas doc

Lane D (Blender + gen pipelines + Google Colab GPU acceleration) is
defined in `labs/prd-openhands-canvas.md` and is independent of this
arc -- different files, different receipts. The Colab integration
(candidate suites: TRELLIS, Hunyuan3D-2, TripoSR, InstantMesh for
image-to-3D; Hunyuan3D-2 / Stable Fast 3D / DreamGaussian for textured
meshes) is scoped there; artifacts flow `art/src/` -> `game/models/`.

---

# APPENDIX A -- the sequenced execution plan (revised 2026-11-06)

Owner clarification: the planar world is removed ENTIRELY (not
preserved as a knob); the only planar surface that remains is the
INSTANCE contract (`instance_contract.gd`, arena/duel/dungeon). The
planar-only SYSTEMS (Concord loop, housing, gates, guards, enemies)
must live on the GLOBE, because the globe is the open world -- instances
cover arena/dungeon/duel, not the open world.

Each step below is independently receipt-gated. Do them in order; do
not skip ahead to the deletion.

## Step 0 -- the shared player base (KEYSTONE, do first)

Why: ~20 files gate on `is PlayerController`; the globe body is a
sibling with no shared base, so it falls outside resurrection, death,
and PvP. Nothing else can be ported cleanly until the two bodies share
a type.

- New `entities/player/player_base.gd`, `extends CharacterBody3D`,
  `class_name PlayerBase`. Owns the surface the shared systems gate on:
  `entity_id`, `entity_type`, `level`, `experience`, `gold`
  (+`experience_to_next_level`), the progression signals
  (`experience_changed`, `gold_changed`, `leveled_up`), and the methods
  `add_experience` / `add_gold` / the getters. Port them VERBATIM from
  `player_controller.gd` (lines ~333-370, 1700-1800) so behavior is
  unchanged.
- `player_controller.gd`: `extends PlayerBase`; delete the now-inherited
  declarations. Keep everything globe-irrelevant (movement states, planar
  interaction).
- `globe_player.gd`: `extends PlayerBase`; delete its duplicate
  `entity_id`; keep its health/mana/swim/mount surface.
- Retarget the `is PlayerController` gates (health_component.gd:81/196/204,
  targeting_manager.gd:571/1010, ...) to `is PlayerBase`.
- Receipt: a new `test_player_base.gd` proving both bodies are
  `is PlayerBase`, that resurrection targeting accepts the globe body,
  and that `player_died`/`player_killed_player` fire for it.
- RISK: `gold` is a property with a setter in `player_controller.gd`
  (line 1710). Move the whole property (getter+setter) intact; a plain
  field would silently drop the change notification.

## Step 1 -- port the Concord loop to the globe (the flagship)

- Sky signs (`sky_sign_renderer`), the Ancient Door, the Concord Stone,
  the blessed marks -- port `world_playable._setup_*` onto the globe,
  placing them with the globe's own law: `village_props._build_batch`
  (tangent frame, `dir * (planet_radius + lift + walk_surface_h(dir))`).
  The globe already has a `concord_shrine` PROP in `village_props`; the
  port adds the INTERACTIVE `ConcordStone` (the `concord_stones` group).
- Give the globe body the interact resolution the planar controller has
  (`ancient_doors` / `concord_stones` / `ankhs` / `sky_signs` groups).
- Receipt: a globe boot where the door exists, is in `ancient_doors`,
  `ActsService` sees it, and a `door_opened` records a chapter; a
  Concord Stone records an insight on E.

## Step 2 -- port enemies + combat/loot/quest/damage feedback to the globe

- Scene enemies + respawn, ground-loot handlers, the kill-reward
  handler, damage numbers, starter-quest auto-accept. With Step 0 done,
  kill rewards resolve the globe body correctly.
- Receipt: a globe boot that spawns an enemy, kills it, and shows the
  reward/loot/damage rows.

## Step 3 -- port gates + guards + housing + portal

- Moon gate, ascent gate, guards, housing (`DwellingService`), portal.
- Receipt: per system, on the globe.

## Step 4 -- extract WorldContentBuilder (the durable fix)

- A world scene DECLARES its content; the builder places it. Then "the
  globe is missing X" is impossible -- X is declared once. This is what
  stops the drift from ever recurring.

## Step 5 -- flip the default + delete the planar world

- Remove the `world_playable` branch in `GameManager._start_game`.
- Delete `scenes/world_playable.{gd,tscn}` and
  `entities/player/player_controller.gd` (its unique movement legs fold
  into the globe body or are dropped; its progression legs now live in
  `PlayerBase`).
- Keep `WorldShape` + `InstanceContract` (instances stay planar).
- Receipt: full globe boot probe + the default runner set green.

# APPENDIX B -- coverage verification (owner: "instances + globe cover what we need")

- **Instances** (`instance_contract.gd` + `arena_instance.gd` /
  `arena_fighter.gd`): arena / duel / dungeon / royale. Planar AABB,
  vanilla -Y gravity. Self-contained. STAYS as-is.
- **Globe** (`globe_world.tscn`): the open world. Must host every
  non-instance system the planar world hosted -- which is exactly
  Steps 1-3 above.
- **Verdict:** the owner's statement holds -- once the globe hosts the
  ported systems, nothing needs the planar world. No system found in
  `world_playable` belongs to instances instead; all of it is open-world
  content that belongs on the globe.
