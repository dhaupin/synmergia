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
