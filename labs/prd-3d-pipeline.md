# 3D & Modeling Pipeline (Blender -> Godot)

> **Status:** pipeline design 2026-09-25 + runnable smoke test.
> Blender is not installed in the Freebuff sandbox yet (a full
> install does not fit the command timeout); the smoke-test script
> below runs the moment it is. Install it once with:
>
> ```bash
> sudo apt-get update && sudo apt-get install -y blender
> ```
>
> Then verify: `sh ./scripts/blender_smoke_test.sh`

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
