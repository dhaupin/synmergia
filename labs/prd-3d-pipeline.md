# 3D & Modeling Pipeline (Blender -> Godot)

> **See also:** [`prd-art-pipeline.md`](./prd-art-pipeline.md) - Lane D, the
> asset-generation lane that consumes this pipeline law;
> [`prd-models.md`](./prd-models.md) - the `ModelData` record and registry.
> This doc owns the toolchain/import law; Lane D owns the per-suite generation
> adapters.

> **Status:** PROVEN 2026-09-25; model registry live 2026-11-15. The blacksmith
> NPC was generated, exported, imported, animated, and probed end-to-end in
> this repo. Screenshot: `game/data/art/screenshots/npc_blacksmith_village.png`.
> Install blender once with
> `sudo apt-get update && sudo apt-get install -y blender`, then verify:
> `sh ./scripts/blender_smoke_test.sh`.
>
> **Current milestone:** the seven GLBs have `ModelData` records and resolve
> through `DataService`; actor data uses `model_id` and carries no GLB path.

## 1. Toolchain

| Stage | Tool | Notes |
|---|---|---|
| Modeling / UV / rig | **Blender** (headless-capable) | The single DCC. Scripts drive it CI-style. |
| Interchange | **glTF 2.0 (.glb)** | Godot 4.7's first-class import format; PBR defaults line up. |
| Engine import | Godot 4.7 `.glb` -> scene | Imports as instanced scenes; materials -> StandardMaterial3D. |
| Procgen assembly | Godot tool scripts | Block vocabulary + anchors per prd-world.md sec 3. |
| **Neural generation (optional)** | **GPU surface** | Image-to-3D / text-to-image for concepts + textures. See `DEPLOY-GPU.md` (Colab first; provider-agnostic). CPU-side rig/export/import is unchanged and must work with no GPU. |

## 2. Asset flow rules

1. **Source `.blend` files live under `game/data/art/src/`**, hidden from
   Godot by `game/data/art/.gdignore`, and versioned with the repo. Only
   exported `.glb` enters `game/data/models/<family>/`.
2. **Naming mirrors the data id conventions**: `mount_plains_runner.glb`,
   `npc_village_elder.glb`, `furn_fireplace_stone.glb`. A model file
   name resolves to its data id with zero mapping code.
3. **The .glb filename is the model id; the `ModelData` record is the
   descriptor** (`game/data/models/<family>/<id>.tres`). Actor data uses
   `model_id`; `scene_path` is only for composite NPC scenes. The naming lint
   fails a record that resolves to a phantom asset. See `labs/prd-models.md`.
4. **Pivot + scale law:** all props exported with origin at the base,
   +Y up, 1 unit = 1 meter. Mounts/vehicles pivot at saddle/driver
   seat. Breaking this law breaks housing grid placement.
5. **Textures:** packed into the .glb for props (2k max), external for
   hero assets. No .blend-embedded images.
6. **Rigs:** skeleton per creature family (biped, quadruped, bird,
   fish) shared across members so animations swap by skeleton id.

## 3. Movement-flow (animation) conventions

- Locomotion set per family: idle / walk / run / turn L-R (+ swim /
  fly variants for aquatic/flying mounts).
- Riders: attachment point named `seat_driver`, passengers
  `seat_p1..N` (VehicleData.seat_count binds to these names).
- Humans: hair/appearance variants ride the head attachment bone
  (`head_mount`) so CharacterData.hairstyle is a mesh swap, not a
  re-rig.

## 4. Procgen assembly contract

Procgen never invents meshes; it composes the block vocabulary
(`game/data/models/blocks/`) with placement rules and drops authored
anchors (whole-city .glb) on top. Every assembled result must be
seed-reproducible (prd-world.md sec 3.4). An AI-assisted layout
generator, if adopted, emits the same block vocabulary -- indistinguishable
downstream.

## 5. Smoke test (runnable)

`scripts/blender_smoke_test.sh` proves the chain end-to-end:
headless Blender builds a 1m reference cube -> exports .glb ->
headless Godot loads it as a PackedScene -> exits 0. Keep it in the
CI rotation once Blender lands on the build image.

## 6. Model generation flow (the proven recipe)

The whole flow is committed; any agent can reproduce it:

```bash
# 1. generate the model (writes straight into game/data/models/npcs/)
blender --background --factory-startup --python scripts/gen_blacksmith_model.py
# 2. verify in-engine (3 probes + movement profiles test)
sh ./scripts/godot_test_runner.sh
```

Pipeline facts baked into `scripts/gen_blacksmith_model.py` (all
proven experimentally on Blender 3.0.1 -- re-derive nothing):

1. Key bone rotations in **QUATERNION** space; XYZ-euler FCurves are
   silently dropped by the exporter (zero animations result).
2. The glTF exporter writes ONLY the action on
   `animation_data.action` (NLA strips ignored) -> export once per
   clip with the scene frame range clamped to the action's own range,
   then merge single-anim GLBs with the stdlib merger in the same
   script. `scripts/fix_clip_ranges.py` then rewrites input accessors
   to place clips in their NLA time slots (idle [0,1.6]s,
   walk [1.6,2.67]s) -- shift each UNIQUE input accessor exactly once
   (samplers share accessors) and never trim trailing zero bytes from
   the binary chunk.
3. Never `nla.bake` between clips: baking pollutes the next clip with
   the previous clip's keys on every bone.
4. Explicit vertex groups beat auto-weights on block-bodies (no
   envelope smear between adjacent boxes).
5. Headless screenshots must use **CYCLES + CPU**; EEVEE/Workbench
   need a display and die with "Unable to open a display"
   (`scripts/render_model_screenshot.py`).
6. The exporter SAMPLES THE SCENE frame range -- leftover wide
   scene_end balloons clips (walk 32f exported as 88f once).

In-engine verification lives in `game/tests/`:
`probe_blacksmith_model.gd` (mesh+skeleton+clips load),
`probe_anim_play.gd` (walk visibly drives thigh_l > 0.1 rad inside
its NLA slot), `probe_blacksmith_scene.gd` (npc scene embeds the glb;
NPCEntity's idle path finds the AnimationPlayer and the clip drives
arm_r over 0.5s). Script-mode tests must resolve autoloads in
`_initialize()` -- `_init()` runs before autoloads attach.

## 7. Shared export library

`scripts/model_export_lib.py` carries the whole pipeline
(export-once-per-clip + stdlib merge + fix_clip_ranges NLA slots +
`key_quat`/`make_action` helpers). Generators build their body/rig/
actions, then call `model_export_lib.export_model(rig, out_path,
[clips], {clip: start_s})`. The blacksmith and wolf both run on it;
new models must too. `scripts/render_model_screenshot.py -- wolf`
renders any generator's model via its own build code (Cycles CPU
only, headless).

## 8. Enemy + mount model mounting

- `EnemyData.model_id` resolves a `ModelData` record; `enemy.gd._mount_model()`
  instances `asset_path` under a `ModelRoot` child, hides any author
  placeholder box mesh, and swaps walk/idle clips from `animation_clips`
  with AI movement (`_update_model_anim`). A missing id keeps the
  placeholder body; a phantom asset fails the data lint.
- Mounts/vehicles resolve their MovementProfile through the single
  path `DataService.get_mount_movement_profile(mount)`:
  MountData.movement_profile_id (or VehicleData's) wins, else kind
  derives it (GROUND->quadruped, FLYING->aerial, AQUATIC->aquatic),
  vehicles fall back to movement_mechanical. No per-consumer
  fallback code.

## 9. Movement Design System

Movement feel is DATA, not code: `MovementProfile`
(`core/schemas/movement_profile.gd`) + `.tres` files in
`data/movement_profiles/` (standard, quadruped, aerial, aquatic,
mechanical, npc_ambient). One profile per archetype so walk/run/
sprint/jump/gravity/friction are consistent for every player, enemy,
NPC, and mount; retuning is a .tres edit, never a code edit.

- The player body's spawn stamp (GlobeWorldPlayer; the planar
  `PlayerController` before Step 5) applies the profile
  over export fallbacks in `_ready()`; capability gates
  (`allow_sprint` / `allow_jump_input` / `allow_crouch`) are consulted
  by the movement states (idle/run).
- `EnemyData.movement_profile_id` overrides per mob (empty =
  movement_standard); `enemy.gd` scales its per-mob move_speed onto
  the profile's run band.
- Layering (later wins): profile .tres base -> species speed_modifier
  -> mount/vehicle multiplier -> buff/debuff modifiers.
- Test: `test_movement_profiles.gd` (standard preserves historical
  tuning 5.0/10.0/10.0; quadruped faster; ambient NPCs cannot
  sprint/jump; machines cannot jump).

## 10. Hitbox Profile System

Hitbox SIZE is DATA, not scene furniture: `HitboxProfile`
(`core/schemas/hitbox_profile.gd`) + `.tres` files in
`data/hitbox_profiles/` (player, humanoid, beast_medium, blob, dummy,
npc). One profile per body plan; capsule for bipeds, box for beasts,
sphere for blobs. `build_shape()` emits a fresh Godot `Shape3D`;
`get_dims(scale, stance)` returns pre-multiplied dims + center offset.

- `DataService.get_creature_hitbox_profile(data)` is the single
  resolution path for creatures: explicit `hitbox_profile_id` wins,
  else `animation_set` derives the body plan (wolf -> beast_medium,
  slime -> blob, else humanoid). NPCs resolve
  `NPCData.hitbox_profile_id` (default hitbox_npc); NPCEntity applies
  it to the scene-authored `CollisionShape3D`.
- Enemies: `_apply_hitbox_profile()` targets the scene's
  `StaticBody3D/Hitbox` node first (the live globe renames its inline
  shapes to `Hitbox`), then `Hitbox`, then a bare
  `CollisionShape3D`; only when none exist does it build the
  StaticBody3D/Hitbox pair itself. `EnemyData.scale` multiplies the
  hitbox AND the mounted `ModelRoot` (same clamp band, so visual and
  collider always agree; wolf 1.2 does both).
- FAIRNESS RULE (species PvP): every playable species resolves to ONE
  shared profile via `DataService.resolve_player_hitbox_profile()`;
  a deviating species override is logged as an error and forced back.
  `hitbox_player.tres` is `pvp_fair = true` with scale clamped hard
  to 1.0 -- species, sex, and body_type never resize the player
  hitbox (bigger hitbox = eats more hits = worse PvP).
- Players: `PlayerBase._apply_hitbox_profile()` in _ready (globe body
  calls it deferred); the planar `PlayerController` before Step 5
  (deferred, after species data resolves) + `set_hitbox_stance()`;
  Crouch/Slide states swap to the crouch variant (0.9 capsule at half
  offset), invalid stances ignored.
- Lint: `test_data_naming_lint.gd` enforces `hitbox_` prefix +
  filename==id, resolvable refs from enemies/npc/species, and the
  species fairness rule (all species share one profile).
- Test: `test_hitbox_profiles.gd` (profile load, dims/stances, scale
  clamp, species fairness, creature resolution, enemy + player wiring
  through the live world scene).
- SpawnService.spawn_npc_entity now defers the add_child when called
  during scene setup (`globe_world._ready` NPC spawns were being rejected
  mid-setup and landed half-configured).
