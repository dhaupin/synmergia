# 3D & Modeling Pipeline (Blender -> Godot)

> **Status:** PROVEN 2026-09-25 -- blacksmith NPC generated, exported,
> imported, animated, and probed end-to-end in this repo. Screenshot:
> `art/screenshots/npc_blacksmith_village.png`. Install blender once
> with `sudo apt-get update && sudo apt-get install -y blender`, then
> verify: `sh ./scripts/blender_smoke_test.sh`.

## 1. Toolchain

| Stage | Tool | Notes |
|---|---|---|
| Modeling / UV / rig | **Blender** (headless-capable) | The single DCC. Scripts drive it CI-style. |
| Interchange | **glTF 2.0 (.glb)** | Godot 4.7's first-class import format; PBR defaults line up. |
| Engine import | Godot 4.7 `.glb` -> scene | Imports as instanced scenes; materials -> StandardMaterial3D. |
| Procgen assembly | Godot tool scripts | Block vocabulary + anchors per prd-world.md sec 3. |

## 2. Asset flow rules

1. **Source `.blend` files live outside `game/`** (e.g. `art/src/`),
   versioned with the repo. Only exported `.glb` enters `game/models/`.
2. **Naming mirrors the data id conventions**: `mount_plains_runner.glb`,
   `npc_village_elder.glb`, `dwel_fireplace_stone.glb`. A model file
   name resolves to its data id with zero mapping code.
3. **The .glb filename IS the model registry** -- there is no separate
   model-descriptor schema. `model_path`/`scene_path` fields on data
   resources stay EMPTY until the real file exists in `game/models/`;
   the naming lint fails any data file pointing at a phantom path
   (this killed 14 historical phantom refs in one sweep).
3. **Pivot + scale law:** all props exported with origin at the base,
   +Y up, 1 unit = 1 meter. Mounts/vehicles pivot at saddle/driver
   seat. Breaking this law breaks housing grid placement.
4. **Textures:** packed into the .glb for props (2k max), external for
   hero assets. No .blend-embedded images.
5. **Rigs:** skeleton per creature family (biped, quadruped, bird,
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
(`game/models/blocks/`) with placement rules and drops authored
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
# 1. generate the model (writes straight into game/models/npcs/)
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

- `EnemyData.model_path` is LIVE: `enemy.gd._mount_model()` instances
  the .glb under a `ModelRoot` child, hides any author placeholder
  box mesh, and swaps walk/idle clips with AI movement
  (`_update_model_anim`). The phantom-path lint keeps model_path
  empty until the file exists -- populate the .tres only after the
  .glb lands.
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

- `PlayerController._apply_movement_profile()` stamps the profile
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
